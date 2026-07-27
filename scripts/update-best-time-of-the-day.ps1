# Refresh Best Time Of The Day loop.zip (Loop.wav only) and 128 kbps demo MP3 from Dropbox pack.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$srcZip = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV\Best Time Of The Day.zip'
$loopWavName = 'Best Time Of The Day - Loop.wav'
$trackDir = Join-Path $ProjectRoot 'tracks\best-time-of-the-day'
$staging = Join-Path $PSScriptRoot '.import-staging\best-time-of-the-day'
$ffmpeg = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not (Test-Path -LiteralPath $srcZip)) { throw "Missing source zip: $srcZip" }
if (-not $ffmpeg) { throw 'ffmpeg not found in scripts/.tools — run update-2am-snowflakes.ps1 once to fetch it.' }

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
Expand-Archive -LiteralPath $srcZip -DestinationPath $staging -Force
$wav = Join-Path $staging $loopWavName
if (-not (Test-Path -LiteralPath $wav)) { throw "Missing $loopWavName in Dropbox pack" }

New-Item -ItemType Directory -Force -Path $trackDir | Out-Null
$loopZip = Join-Path $trackDir 'loop.zip'
if (Test-Path $loopZip) { Remove-Item $loopZip -Force }
Compress-Archive -LiteralPath $wav -DestinationPath $loopZip -Force

$demoOut = Join-Path $trackDir 'demo.mp3'
$proc = Start-Process -FilePath $ffmpeg.FullName -ArgumentList @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $wav,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
) -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0 -or -not (Test-Path $demoOut)) { throw 'ffmpeg failed to create demo.mp3' }

Write-Host "Updated tracks/best-time-of-the-day/loop.zip (contains $loopWavName)"
Write-Host "Updated tracks/best-time-of-the-day/demo.mp3 (128 kbps, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
