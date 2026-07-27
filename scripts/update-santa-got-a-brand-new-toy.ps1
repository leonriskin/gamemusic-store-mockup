# Refresh Santa Got A Brand New Toy demo.mp3 from Dropbox zip (128 kbps). loop.zip left unchanged when it already matches source.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\santa-got-a-brand-new-toy'
$staging = Join-Path $PSScriptRoot '.import-staging\santa-got-a-brand-new-toy'
$packUrl = 'https://www.dropbox.com/scl/fi/ejfvd0ik8v3em15rcj46n/Santa-Got-A-Brand-New-Toy.zip?rlkey=bs6gfs2bjsnor2gswjzi126bl&dl=1'
$localZip = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV\Santa Got A Brand New Toy.zip'
$demoWavName = 'Santa Got A Brand New Toy.wav'
$title = 'Santa Got A Brand New Toy'
$slug = 'santa-got-a-brand-new-toy'
$trackId = 3
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

function Resolve-DemoWav([string]$ExtractRoot) {
  $exact = Join-Path $ExtractRoot $demoWavName
  if (Test-Path -LiteralPath $exact) { return (Resolve-Path -LiteralPath $exact).Path }

  $wavs = @(Get-ChildItem $ExtractRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '(?i)\.(wav|aiff?|flac)$' })
  if ($wavs.Count -eq 1) { return $wavs[0].FullName }

  $preferred = $wavs |
    Where-Object {
      $_.BaseName -match '(?i)santa got a brand new toy' -and
      $_.BaseName -match '(?i)(loop|full)' -and
      $_.BaseName -notmatch '(?i)short|no drums|no sfx'
    } |
    Sort-Object {
      if ($_.BaseName -match '(?i)\bfull\b') { 0 }
      elseif ($_.BaseName -match '(?i)\blong loop\b') { 1 }
      elseif ($_.BaseName -match '(?i)\bloop\b') { 2 }
      else { 3 }
    } |
    Select-Object -First 1
  if ($preferred) { return $preferred.FullName }

  throw "Missing demo WAV in Dropbox pack (expected $demoWavName or a loop/full variant)"
}

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

$packStagingZip = Join-Path $staging 'pack-source.zip'
Write-Host 'Downloading pack from Dropbox...'
& curl.exe -L --fail -o $packStagingZip $packUrl
if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $localZip)) {
  Write-Warning 'Dropbox download failed; using local Dropbox zip.'
  Copy-Item -LiteralPath $localZip -Destination $packStagingZip -Force
}
if (-not (Test-Path $packStagingZip)) { throw 'Could not obtain pack zip.' }

$extractRoot = Join-Path $staging 'extract'
Expand-Archive -LiteralPath $packStagingZip -DestinationPath $extractRoot -Force
$demoWav = Resolve-DemoWav $extractRoot
Write-Host "Using demo WAV: $demoWav"

$loopZip = Join-Path $trackDir 'loop.zip'
$needsLoopUpdate = $true
if (Test-Path $loopZip) {
  $srcHash = (Get-FileHash -LiteralPath $packStagingZip -Algorithm MD5).Hash
  $curHash = (Get-FileHash -LiteralPath $loopZip -Algorithm MD5).Hash
  $needsLoopUpdate = ($srcHash -ne $curHash)
}
if ($needsLoopUpdate) {
  Copy-Item -LiteralPath $packStagingZip -Destination $loopZip -Force
  Write-Host "Updated tracks/$slug/loop.zip from Dropbox zip"
} else {
  Write-Host "tracks/$slug/loop.zip already matches Dropbox source - left unchanged"
}

$demoOut = Join-Path $trackDir 'demo.mp3'
& $ffmpeg.FullName @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $demoWav,
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
