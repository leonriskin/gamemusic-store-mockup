# Refresh Blindfold Speed Racing loop.zip from Dropbox and 128 kbps demo MP3 from loop WAV.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$base = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV'
$srcZip = Join-Path $base 'Blindfold Speed Racing.zip'
$trackDir = Join-Path $ProjectRoot 'tracks\blindfold-speed-racing'
$staging = Join-Path $PSScriptRoot '.import-staging\blindfold-speed-racing'
$ffmpeg = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not (Test-Path -LiteralPath $srcZip)) { throw "Missing source zip: $srcZip" }
if (-not $ffmpeg) { throw 'ffmpeg not found in scripts/.tools — run update-2am-snowflakes.ps1 once to fetch it.' }

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
Expand-Archive -LiteralPath $srcZip -DestinationPath $staging -Force
$wav = Get-ChildItem $staging -Filter '*.wav' | Select-Object -First 1
if (-not $wav) { throw 'WAV not found in source zip' }

New-Item -ItemType Directory -Force -Path $trackDir | Out-Null
Copy-Item -LiteralPath $srcZip -Destination (Join-Path $trackDir 'loop.zip') -Force

$demoOut = Join-Path $trackDir 'demo.mp3'
& $ffmpeg.FullName @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $wav.FullName,
  '-codec:a', 'libmp3lame', '-b:a', '128k', '-ar', '44100',
  $demoOut
)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $demoOut)) { throw 'ffmpeg failed to create demo.mp3' }

Write-Host "Updated tracks/blindfold-speed-racing/loop.zip from Dropbox zip"
Write-Host "Updated tracks/blindfold-speed-racing/demo.mp3 (128 kbps, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB)"
