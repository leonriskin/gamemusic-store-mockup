# Refresh Tiny World demo.mp3, loop.zip ($9 loop WAV), and pack.zip ($12 full pack).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\tiny-world'
$staging = Join-Path $PSScriptRoot '.import-staging\tiny-world'
$localBase = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV'
$localFullZip = Join-Path $localBase 'Tiny World.zip'
$packUrl = 'https://www.dropbox.com/scl/fi/lu0n0m0iklr7n9afhyi54/Tiny-World.zip?rlkey=eubzv0bvxj3zjjzu45pdgamgv&dl=1'
$loopWavName = 'tiny world - loop.wav'
$title = 'Tiny World'
$slug = 'tiny-world'
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

  $found = Get-ChildItem $ExtractRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Extension -match '(?i)\.(wav|aiff?|flac)$' -and
      ($_.BaseName -ieq 'tiny world - loop' -or $_.BaseName -match '(?i)^tiny world\s*-\s*loop$')
    } |
    Select-Object -First 1
  if ($found) { return $found.FullName }

  if (Test-Path -LiteralPath $localBase) {
    $local = Get-ChildItem $localBase -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Extension -match '(?i)\.(wav|aiff?|flac)$' -and
        ($_.BaseName -ieq 'tiny world - loop' -or $_.BaseName -match '(?i)^tiny world\s*-\s*loop$')
      } |
      Select-Object -First 1
    if ($local) { return $local.FullName }
  }

  throw "Missing loop WAV matching 'tiny world - loop' in extracted pack or local Dropbox"
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
Write-Host "Using loop WAV: $loopWav"

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

Copy-Item -LiteralPath $packStagingZip -Destination (Join-Path $trackDir 'pack.zip') -Force
$duration = Get-AudioDuration $demoOut

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog.tracks = @($catalog.tracks | ForEach-Object {
  if ($_.title -eq $title -or $_.id -eq 9) {
    $updated = [ordered]@{}
    $_.PSObject.Properties | ForEach-Object {
      if ($_.Name -ne 'loopOnly') { $updated[$_.Name] = $_.Value }
    }
    $updated.duration = $duration
    $updated.price = 9
    $updated.loopPrice = 9
    $updated.packPrice = 12
    $updated.packZip = "tracks/$slug/pack.zip"
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

Write-Host "Updated tracks/$slug/loop.zip (contains $(Split-Path $loopWav -Leaf), $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB)"
Write-Host "Updated tracks/$slug/demo.mp3 (128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
Write-Host "Updated tracks/$slug/pack.zip ($([math]::Round((Get-Item (Join-Path $trackDir 'pack.zip')).Length/1MB,2)) MB, all files from Dropbox full pack)"
Write-Host "Updated catalog duration=$duration, packPrice=12, packZip=tracks/$slug/pack.zip (removed loopOnly)"
