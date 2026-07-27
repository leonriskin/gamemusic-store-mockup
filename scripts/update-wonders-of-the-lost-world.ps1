# Refresh Wonders Of The Lost World: loop.zip ($9, 2 WAVs only), demo.mp3, packContents.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$localBase = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV'
$srcZip = Join-Path $localBase 'Wonders Of The Lost World.zip'
$loopWavName = 'Wonders Of The Lost World - loop no sfx.wav'
$fullWavName = 'Wonders Of The Lost World - full no sfx.wav'
$productWavNames = @($fullWavName, $loopWavName)
$title = 'Wonders Of The Lost World'
$slug = 'wonders-of-the-lost-world'
$trackId = 14
$trackDir = Join-Path $ProjectRoot "tracks\$slug"
$staging = Join-Path $PSScriptRoot ".import-staging\$slug"
$catalogPath = Join-Path $ProjectRoot 'tracks\catalog.json'
$metaPath = Join-Path $ProjectRoot 'tracks\track-meta.json'

$ffmpeg = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$ffprobe = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ffmpeg) { throw 'ffmpeg not found in scripts/.tools - run update-2am-snowflakes.ps1 once to fetch it.' }
if (-not $ffprobe) { throw 'ffprobe not found in scripts/.tools.' }

function Get-AudioDuration([string]$Path) {
  $raw = & $ffprobe.FullName @(
    '-v', 'error', '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1:nokey=1', $Path
  )
  if ($LASTEXITCODE -ne 0) { throw "ffprobe failed for $Path" }
  $seconds = [int][math]::Round([double]$raw.Trim())
  $mins = [math]::Floor($seconds / 60)
  $secs = $seconds % 60
  return ('{0}:{1:D2}' -f [int]$mins, [int]$secs)
}

function Resolve-ProductWav([string]$ExtractRoot, [string]$ExpectedName) {
  $exact = Join-Path $ExtractRoot $ExpectedName
  if (Test-Path -LiteralPath $exact) { return (Resolve-Path -LiteralPath $exact).Path }

  $found = Get-ChildItem $ExtractRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Extension -match '(?i)\.(wav|aiff?|flac)$' -and
      $_.Name -ieq $ExpectedName
    } |
    Select-Object -First 1
  if ($found) { return $found.FullName }

  throw "Missing $ExpectedName in Dropbox pack"
}

if (-not (Test-Path -LiteralPath $srcZip)) { throw "Missing source zip: $srcZip" }

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

Expand-Archive -LiteralPath $srcZip -DestinationPath $staging -Force
$loopWav = Resolve-ProductWav $staging $loopWavName
$fullWav = Resolve-ProductWav $staging $fullWavName
Write-Host "Using loop WAV: $loopWav"
Write-Host "Using full WAV: $fullWav"

$zipStaging = Join-Path $staging 'product'
New-Item -ItemType Directory -Force -Path $zipStaging | Out-Null
foreach ($name in $productWavNames) {
  $src = Resolve-ProductWav $staging $name
  Copy-Item -LiteralPath $src -Destination (Join-Path $zipStaging $name) -Force
}

$loopZip = Join-Path $trackDir 'loop.zip'
if (Test-Path $loopZip) { Remove-Item $loopZip -Force }
Compress-Archive -Path (Join-Path $zipStaging '*') -DestinationPath $loopZip -Force

$packOut = Join-Path $trackDir 'pack.zip'
if (Test-Path $packOut) { Remove-Item $packOut -Force }

$demoOut = Join-Path $trackDir 'demo.mp3'
& $ffmpeg.FullName @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $loopWav,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $demoOut)) { throw 'ffmpeg failed to create demo.mp3' }

$duration = Get-AudioDuration $demoOut
$packContents = @($productWavNames | ForEach-Object {
  $path = Join-Path $zipStaging $_
  [ordered]@{
    name     = $_
    duration = (Get-AudioDuration $path)
  }
})

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog.tracks = @($catalog.tracks | ForEach-Object {
  if ($_.title -eq $title -or [int]$_.id -eq $trackId) {
    $updated = [ordered]@{}
    $_.PSObject.Properties | ForEach-Object {
      if ($_.Name -notin @('packPrice', 'packZip', 'packContents')) { $updated[$_.Name] = $_.Value }
    }
    $updated.duration = $duration
    $updated.price = 9
    $updated.loopPrice = 9
    $updated.loopOnly = $true
    $updated.desc = 'A haunting and enchanting theme. Inspiring yet mysterious. Imagine alien worlds, distant enchanted forests and fields of glowing flowers, surrounded by dark trees. Package contents: - Full version - no SFX - Loop version - no sfx'
    $updated.packContents = $packContents
    return [pscustomobject]$updated
  }
  $_
})
($catalog | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $catalogPath -Encoding UTF8 -NoNewline
Add-Content $catalogPath "`n" -Encoding UTF8

$meta = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$meta.tracks = @($meta.tracks | ForEach-Object {
  if ($_.slug -eq $slug -or $_.title -eq $title) {
    $updated = [ordered]@{}
    $_.PSObject.Properties | ForEach-Object { $updated[$_.Name] = $_.Value }
    $updated.duration = $duration
    return [pscustomobject]$updated
  }
  $_
})
$meta._updated = (Get-Date -Format 'yyyy-MM-dd')
($meta | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $metaPath -Encoding UTF8 -NoNewline
Add-Content $metaPath "`n" -Encoding UTF8

Write-Host "Updated tracks/$slug/loop.zip (2 files, $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB)"
$packContents | ForEach-Object { Write-Host "  $($_.name) - $($_.duration)" }
Write-Host "Updated tracks/$slug/demo.mp3 (128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
Write-Host "Updated catalog: loopOnly=true, loopPrice=9, packContents=$($packContents.Count) files"
