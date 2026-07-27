# Refresh Our Dream House In The Sky demo.mp3, loop.zip ($9 loop WAV), and pack.zip ($12 full pack).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\our-dream-house-in-the-sky'
$staging = Join-Path $PSScriptRoot '.import-staging\our-dream-house-in-the-sky'
$localFullZip = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV\Our Dream House In The Sky.zip'
$packUrl = 'https://www.dropbox.com/scl/fi/k8168drxggwyeyxwlljo4/Our-Dream-House-In-The-Sky.zip?rlkey=aueynwcj90kj3kk4o79x66lwh&dl=1'
$loopWavName = 'Our Dream House In The Sky - loop.wav'
$title = 'Our Dream House In The Sky'
$slug = 'our-dream-house-in-the-sky'
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

function Resolve-LoopWav([string]$ExtractRoot) {
  $exact = Join-Path $ExtractRoot $loopWavName
  if (Test-Path -LiteralPath $exact) { return (Resolve-Path -LiteralPath $exact).Path }
  $found = Get-ChildItem $ExtractRoot -Recurse -Filter '*.wav' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq $loopWavName -or $_.BaseName -match '(?i)our dream house in the sky.*\bloop\b' -and $_.BaseName -notmatch 'short|loop 2' } |
    Select-Object -First 1
  if (-not $found) { throw "Missing $loopWavName in extracted pack" }
  return $found.FullName
}

function Get-PackWavCount([string]$ExtractRoot) {
  @(Get-ChildItem $ExtractRoot -Recurse -Filter '*.wav' -ErrorAction SilentlyContinue).Count
}

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

$packStagingZip = Join-Path $staging 'pack-source.zip'
Write-Host 'Downloading full pack from Dropbox...'
& curl.exe -L --fail -o $packStagingZip $packUrl
if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $localFullZip)) {
  Write-Warning 'Dropbox download failed; using local Dropbox zip.'
  Copy-Item -LiteralPath $localFullZip -Destination $packStagingZip -Force
}
if (-not (Test-Path $packStagingZip)) { throw 'Could not obtain full pack zip.' }

$extractRoot = Join-Path $staging 'pack'
Expand-Archive -LiteralPath $packStagingZip -DestinationPath $extractRoot -Force
$loopWav = Resolve-LoopWav $extractRoot
$wavCount = Get-PackWavCount $extractRoot
$hasFullPack = $wavCount -gt 1

Write-Host "Extracted $wavCount WAV file(s) from full pack."

$loopZip = Join-Path $trackDir 'loop.zip'
if (Test-Path $loopZip) { Remove-Item $loopZip -Force }
Compress-Archive -LiteralPath $loopWav -DestinationPath $loopZip -Force

$demoOut = Join-Path $trackDir 'demo.mp3'
& $ffmpeg.FullName @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $loopWav,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $demoOut)) { throw 'ffmpeg failed to create demo.mp3' }

$packOut = Join-Path $trackDir 'pack.zip'
if ($hasFullPack) {
  Copy-Item -LiteralPath $packStagingZip -Destination $packOut -Force
} elseif (Test-Path $packOut) {
  Remove-Item $packOut -Force
}

$duration = Get-AudioDuration $demoOut

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog.tracks = @($catalog.tracks | ForEach-Object {
  if ($_.title -eq $title -or $_.id -eq 18) {
    $updated = [ordered]@{}
    $_.PSObject.Properties | ForEach-Object {
      if ($_.Name -notin @('loopOnly', 'packPrice', 'packZip')) { $updated[$_.Name] = $_.Value }
    }
    $updated.duration = $duration
    $updated.price = 9
    $updated.loopPrice = 9
    if ($hasFullPack) {
      $updated.packPrice = 12
      $updated.packZip = "tracks/$slug/pack.zip"
    } else {
      $updated.loopOnly = $true
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

Write-Host "Updated tracks/$slug/loop.zip (contains $loopWavName, $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB)"
Write-Host "Updated tracks/$slug/demo.mp3 (128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
if ($hasFullPack) {
  Write-Host "Updated tracks/$slug/pack.zip ($([math]::Round((Get-Item $packOut).Length/1MB,2)) MB, all files from Dropbox full pack)"
  Write-Host "Updated catalog duration=$duration, packPrice=12, packZip=tracks/$slug/pack.zip (removed loopOnly)"
} else {
  Write-Host "Updated catalog duration=$duration, loopOnly=true, loopPrice=9, price=9 (no full pack)"
}
