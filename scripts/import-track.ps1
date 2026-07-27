# Import a published track into tracks/<slug>/ and update catalog.json + track-meta.json
param(
  [Parameter(Mandatory = $true)][string]$Title,
  [int]$Id = 0,
  [string]$PreviewMp3,
  [string]$LoopZip,
  [string]$PackZip,
  [string]$CoverImage,
  [string]$Description,
  [string[]]$Tags = @(),
  [string]$Genre = 'Holidays',
  [int]$Bpm = 120,
  [string]$Duration = '1:29',
  [string]$Instruments = 'piano, bells, strings, celesta',
  [string]$Category2 = 'Christmas',
  [string]$ProjectRoot = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$slug = ($Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
$trackDir = Join-Path $ProjectRoot "tracks\$slug"
$catalogPath = Join-Path $ProjectRoot 'tracks\catalog.json'
$metaPath = Join-Path $ProjectRoot 'tracks\track-meta.json'

function Require-File([string]$Path, [string]$Label) {
  if (-not (Test-Path $Path)) { throw "Missing $Label`: $Path" }
  return (Resolve-Path $Path).Path
}

$PreviewMp3 = Require-File $PreviewMp3 'preview MP3'
$LoopZip = Require-File $LoopZip 'loop ZIP'
$LoopZip = (Resolve-Path $LoopZip).Path
$hasPack = $false
if ($PackZip -and (Test-Path $PackZip)) {
  $PackZip = (Resolve-Path $PackZip).Path
  if ($PackZip -ne $LoopZip) { $hasPack = $true }
}
if (-not $CoverImage) { throw 'CoverImage path is required.' }
$CoverImage = Require-File $CoverImage 'cover image'

New-Item -ItemType Directory -Force -Path $trackDir | Out-Null
Copy-Item $PreviewMp3 (Join-Path $trackDir 'demo.mp3') -Force
Copy-Item $LoopZip (Join-Path $trackDir 'loop.zip') -Force
if ($hasPack) {
  Copy-Item $PackZip (Join-Path $trackDir 'pack.zip') -Force
} elseif (Test-Path (Join-Path $trackDir 'pack.zip')) {
  Remove-Item (Join-Path $trackDir 'pack.zip') -Force
}
Copy-Item $CoverImage (Join-Path $trackDir 'cover.jpg') -Force

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Id -le 0) {
  $maxId = ($catalog.tracks | ForEach-Object { [int]$_.id } | Measure-Object -Maximum).Maximum
  $Id = [int]$maxId + 1
}

$catalog.tracks = @($catalog.tracks | ForEach-Object {
  if ($_.title -eq $Title -or [int]$_.id -eq $Id) {
    $updated = [ordered]@{}
    $_.PSObject.Properties | ForEach-Object { $updated[$_.Name] = $_.Value }
    return [pscustomobject]$updated
  }
  $_
})
$catalog.tracks = @($catalog.tracks | Where-Object { $_.title -ne $Title -and [int]$_.id -ne $Id })

$newEntry = [ordered]@{
  id = $Id
  title = $Title
  genre = $Genre
  bpm = $Bpm
  duration = $Duration
  price = 9
  loopPrice = 9
  tags = @($Tags)
  desc = $Description
  cover = "tracks/$slug/cover.jpg"
  demo = "tracks/$slug/demo.mp3"
  loopZip = "tracks/$slug/loop.zip"
  status = 'published'
}
if ($hasPack) {
  $newEntry.packPrice = 12
  $newEntry.packZip = "tracks/$slug/pack.zip"
} else {
  $newEntry.loopOnly = $true
}
$catalog.tracks += [pscustomobject]$newEntry
($catalog | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $catalogPath -Encoding UTF8 -NoNewline
Add-Content $catalogPath "`n" -Encoding UTF8

$meta = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$meta.tracks = @($meta.tracks | Where-Object { $_.title -ne $Title -and $_.slug -ne $slug })
$metaEntry = [ordered]@{
  title = $Title
  slug = $slug
  description = $Description
  tags = @($Tags)
  genre = $Genre
  bpm = $Bpm
  duration = $Duration
  instruments = $Instruments
  category2 = $Category2
  motionElements = 'v'
}
$meta.tracks += [pscustomobject]$metaEntry
$meta._updated = (Get-Date -Format 'yyyy-MM-dd')
($meta | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $metaPath -Encoding UTF8 -NoNewline
Add-Content $metaPath "`n" -Encoding UTF8

Write-Host "Imported track #$Id '$Title' -> tracks/$slug ($(if ($hasPack) { 'loop + pack' } else { 'loop only' }))"
Write-Host "  demo.mp3  $([math]::Round((Get-Item (Join-Path $trackDir 'demo.mp3')).Length/1MB,2)) MB"
Write-Host "  loop.zip  $([math]::Round((Get-Item (Join-Path $trackDir 'loop.zip')).Length/1MB,2)) MB"
if ($hasPack) {
  Write-Host "  pack.zip  $([math]::Round((Get-Item (Join-Path $trackDir 'pack.zip')).Length/1MB,2)) MB"
} else {
  Write-Host "  pack.zip  (not included - loop-only track)"
}
Write-Host "  cover.jpg  $([math]::Round((Get-Item (Join-Path $trackDir 'cover.jpg')).Length/1KB,0)) KB"
Write-Host "Updated $catalogPath and $metaPath"
