# Refresh The Perfect Escape Plan demo.mp3 from Loop clean.wav (128 kbps). loop.zip left unchanged when it already matches Dropbox source.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$localBase = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV'
$srcZip = Join-Path $localBase 'The Perfect Escape Plan.zip'
$loopWavName = 'The Perfect Escape Plan - Loop clean.wav'
$title = 'The Perfect Escape Plan'
$slug = 'the-perfect-escape-plan'
$trackId = 15
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

function Resolve-LoopWav([string]$ExtractRoot) {
  $exact = Join-Path $ExtractRoot $loopWavName
  if (Test-Path -LiteralPath $exact) { return (Resolve-Path -LiteralPath $exact).Path }

  $found = Get-ChildItem $ExtractRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Extension -match '(?i)\.(wav|aiff?|flac)$' -and
      $_.BaseName -ieq 'The Perfect Escape Plan - Loop clean'
    } |
    Select-Object -First 1
  if ($found) { return $found.FullName }

  throw "Missing $loopWavName in Dropbox pack"
}

if (-not (Test-Path -LiteralPath $srcZip)) { throw "Missing source zip: $srcZip" }

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

Expand-Archive -LiteralPath $srcZip -DestinationPath $staging -Force
$loopWav = Resolve-LoopWav $staging
Write-Host "Using loop WAV: $loopWav"

$loopZip = Join-Path $trackDir 'loop.zip'
$needsLoopUpdate = $true
if (Test-Path $loopZip) {
  $srcHash = (Get-FileHash -LiteralPath $srcZip -Algorithm MD5).Hash
  $curHash = (Get-FileHash -LiteralPath $loopZip -Algorithm MD5).Hash
  $needsLoopUpdate = ($srcHash -ne $curHash)
}
if ($needsLoopUpdate) {
  Copy-Item -LiteralPath $srcZip -Destination $loopZip -Force
  Write-Host "Updated tracks/$slug/loop.zip from Dropbox zip"
} else {
  Write-Host "tracks/$slug/loop.zip already matches Dropbox source - left unchanged"
}

$demoOut = Join-Path $trackDir 'demo.mp3'
& $ffmpeg.FullName @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $loopWav,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $demoOut)) { throw 'ffmpeg failed to create demo.mp3' }

$duration = Get-AudioDuration $demoOut
$hasPack = Test-Path (Join-Path $trackDir 'pack.zip')

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog.tracks = @($catalog.tracks | ForEach-Object {
  if ($_.title -eq $title -or [int]$_.id -eq $trackId) {
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

Write-Host "Updated tracks/$slug/demo.mp3 (128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
if ($hasPack) {
  Write-Host "Left tracks/$slug/pack.zip unchanged"
} else {
  Write-Host "Updated catalog duration=$duration, loopOnly=true, loopPrice=9 (no full pack)"
}
