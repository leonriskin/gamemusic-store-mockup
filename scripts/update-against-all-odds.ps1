# Refresh Against All Odds loop.zip (single loop WAV) and 128 kbps demo MP3 from Dropbox.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\against-all-odds'
$staging = Join-Path $PSScriptRoot '.import-staging\against-all-odds'
$wavUrl = 'https://www.dropbox.com/scl/fi/o3fndbh7797jautp7f5sx/Aginst-All-Odds.wav?rlkey=2aakup3gvcrvdz48g2rycmgof&dl=1'
$localWav = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV\Aginst-All-Odds.wav'
$loopWavName = 'Aginst-All-Odds.wav'
$title = 'Against All Odds'
$slug = 'against-all-odds'
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
  $seconds = [math]::Round([double]$raw.Trim())
  $mins = [math]::Floor($seconds / 60)
  $secs = [int]($seconds % 60)
  return ('{0}:{1}' -f $mins, $secs.ToString('00'))
}

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

$wavStaging = Join-Path $staging $loopWavName
Write-Host 'Downloading loop WAV from Dropbox...'
& curl.exe -L --fail -o $wavStaging $wavUrl
if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $localWav)) {
  Write-Warning 'Dropbox download failed; using local Dropbox WAV.'
  Copy-Item -LiteralPath $localWav -Destination $wavStaging -Force
}
if (-not (Test-Path $wavStaging)) { throw 'Could not obtain loop WAV.' }

$loopZip = Join-Path $trackDir 'loop.zip'
if (Test-Path $loopZip) { Remove-Item $loopZip -Force }
Compress-Archive -LiteralPath $wavStaging -DestinationPath $loopZip -Force

$demoOut = Join-Path $trackDir 'demo.mp3'
$proc = Start-Process -FilePath $ffmpeg.FullName -ArgumentList @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $wavStaging,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
) -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0 -or -not (Test-Path $demoOut)) { throw 'ffmpeg failed to create demo.mp3' }

if (Test-Path (Join-Path $trackDir 'pack.zip')) {
  Remove-Item (Join-Path $trackDir 'pack.zip') -Force
}

$duration = Get-AudioDuration $demoOut

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog.tracks = @($catalog.tracks | ForEach-Object {
  if ($_.title -eq $title -or $_.id -eq 8) {
    $updated = [ordered]@{}
    $_.PSObject.Properties | ForEach-Object {
      if ($_.Name -notin @('packPrice', 'packZip')) { $updated[$_.Name] = $_.Value }
    }
    $updated.duration = $duration
    $updated.price = 9
    $updated.loopPrice = 9
    $updated.loopOnly = $true
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
Write-Host "Updated catalog duration=$duration, loopOnly=true, loopPrice=9, price=9 (no full pack)"
