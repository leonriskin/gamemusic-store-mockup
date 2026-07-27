# Refresh All Is Quiet Under The Sea loop.zip (full.wav only) and 128 kbps demo MP3 from Dropbox pack.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$localBase = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV'
$srcZip = Join-Path $localBase 'All Is Quiet Under The Sea.zip'
$fullWavName = 'All Is Quiet Under The Sea - full.wav'
$title = 'All Is Quiet Under The Sea'
$slug = 'all-is-quiet-under-the-sea'
$trackDir = Join-Path $ProjectRoot "tracks\$slug"
$staging = Join-Path $PSScriptRoot ".import-staging\$slug"
$catalogPath = Join-Path $ProjectRoot 'tracks\catalog.json'
$metaPath = Join-Path $ProjectRoot 'tracks\track-meta.json'

$ffmpeg = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$ffprobe = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ffmpeg) { throw 'ffmpeg not found in scripts/.tools — run update-2am-snowflakes.ps1 once to fetch it.' }
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

function Resolve-FullWav([string]$ExtractRoot) {
  $exact = Join-Path $ExtractRoot $fullWavName
  if (Test-Path -LiteralPath $exact) { return (Resolve-Path -LiteralPath $exact).Path }

  $found = Get-ChildItem $ExtractRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Extension -match '(?i)\.(wav|aiff?|flac)$' -and
      $_.BaseName -ieq 'All Is Quiet Under The Sea - full'
    } |
    Select-Object -First 1
  if ($found) { return $found.FullName }

  throw "Missing $fullWavName in Dropbox pack"
}

if (-not (Test-Path -LiteralPath $srcZip)) { throw "Missing source zip: $srcZip" }

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

Expand-Archive -LiteralPath $srcZip -DestinationPath $staging -Force
$fullWav = Resolve-FullWav $staging
Write-Host "Using full WAV: $fullWav"

$loopZip = Join-Path $trackDir 'loop.zip'
if (Test-Path $loopZip) { Remove-Item $loopZip -Force }
Compress-Archive -LiteralPath $fullWav -DestinationPath $loopZip -Force

$demoOut = Join-Path $trackDir 'demo.mp3'
& $ffmpeg.FullName @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $fullWav,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $demoOut)) { throw 'ffmpeg failed to create demo.mp3' }

$duration = Get-AudioDuration $demoOut
$hasPack = Test-Path (Join-Path $trackDir 'pack.zip')

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog.tracks = @($catalog.tracks | ForEach-Object {
  if ($_.title -eq $title -or $_.id -eq 12) {
    $updated = [ordered]@{}
    $_.PSObject.Properties | ForEach-Object { $updated[$_.Name] = $_.Value }
    $updated.duration = $duration
    $updated.price = 9
    $updated.loopPrice = 9
    if (-not $hasPack) {
      $updated.loopOnly = $true
      if ($updated.Contains('packPrice')) { $updated.Remove('packPrice') }
      if ($updated.Contains('packZip')) { $updated.Remove('packZip') }
    }
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

Write-Host "Updated tracks/$slug/loop.zip (contains $fullWavName, $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB)"
Write-Host "Updated tracks/$slug/demo.mp3 (128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
if ($hasPack) {
  Write-Host "Left tracks/$slug/pack.zip unchanged"
} else {
  Write-Host "Updated catalog duration=$duration, loopOnly=true, loopPrice=9 (no full pack)"
}
