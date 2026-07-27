# Refresh 2AM Snowflakes loop.zip (long loop WAV) and 128 kbps demo MP3 from Dropbox source.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$base = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV'
$srcZip = Join-Path $base '2AM Snowflakes - long loop.zip'
$trackDir = Join-Path $ProjectRoot 'tracks\2am-snowflakes'
$staging = Join-Path $PSScriptRoot '.import-staging\2am-snowflakes'
$ffmpeg = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not (Test-Path -LiteralPath $srcZip)) {
  throw "Missing source zip: $srcZip"
}
if (-not $ffmpeg) {
  throw 'ffmpeg not found. Run scripts/setup-ffmpeg.ps1 first or install ffmpeg.'
}

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
Expand-Archive -LiteralPath $srcZip -DestinationPath $staging -Force
$wav = Get-ChildItem $staging -Filter '*.wav' | Select-Object -First 1
if (-not $wav) { throw 'WAV not found in source zip' }

New-Item -ItemType Directory -Force -Path $trackDir | Out-Null
Copy-Item -LiteralPath $srcZip -Destination (Join-Path $trackDir 'loop.zip') -Force

$demoOut = Join-Path $trackDir 'demo.mp3'
$ffmpegExe = $ffmpeg.FullName
$proc = Start-Process -FilePath $ffmpegExe -ArgumentList @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $wav.FullName,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
) -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0 -or -not (Test-Path $demoOut)) {
  throw 'ffmpeg failed to create demo.mp3'
}

Write-Host "Updated tracks/2am-snowflakes/loop.zip from Dropbox long loop zip"
Write-Host "Updated tracks/2am-snowflakes/demo.mp3 (128 kbps, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
