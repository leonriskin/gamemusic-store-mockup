# Import / refresh Counting Heartbeats demo.mp3, loop.zip ($9 loop WAV), and pack.zip ($12 full pack).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\counting-heartbeats'
$staging = Join-Path $PSScriptRoot '.import-staging\counting-heartbeats'
$localFullZip = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV\Counting Heartbeats.zip'
$coverFinal = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops IMG\Final\Counting Heartbeats.jpg'
$packUrl = 'https://www.dropbox.com/scl/fi/do62nriyyb6z7i60qzkn7/Counting-Heartbeats.zip?rlkey=d2qbl9pkg8jtuv2qmmmorz8ze&dl=1'
$loopWavName = 'Counting Heartbeats - loop.wav'
$title = 'Counting Heartbeats'
$slug = 'counting-heartbeats'
$trackId = 23
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
    Where-Object {
      $_.Name -ieq $loopWavName -or
      ($_.BaseName -match '(?i)counting heartbeats.*\bloop\b' -and $_.BaseName -notmatch 'short')
    } |
    Select-Object -First 1
  if (-not $found) { throw "Missing $loopWavName in extracted pack" }
  return $found.FullName
}

function Get-PackWavCount([string]$ExtractRoot) {
  @(Get-ChildItem $ExtractRoot -Recurse -Filter '*.wav' -ErrorAction SilentlyContinue).Count
}

function Resolve-Cover([string]$OutPath) {
  if (Test-Path -LiteralPath $coverFinal) {
    Copy-Item -LiteralPath $coverFinal -Destination $OutPath -Force
    return 'Dropbox Final\Counting Heartbeats.jpg'
  }
  $wc = Invoke-RestMethod "https://gamemusicandsoundeffects.com/wp-json/wc/store/products?slug=counting-heartbeats&per_page=1" -TimeoutSec 60
  if (-not $wc -or $wc.Count -eq 0) { throw 'Cover not found locally or on website.' }
  $coverUrl = $wc[0].images[0].src -replace '\?.*$', ''
  Invoke-WebRequest -Uri $coverUrl -OutFile $OutPath -TimeoutSec 120
  return $coverUrl
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
Get-ChildItem $extractRoot -Recurse -Filter '*.wav' | ForEach-Object { Write-Host "  - $($_.Name)" }

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

$coverOut = Join-Path $trackDir 'cover.jpg'
$coverSource = Resolve-Cover $coverOut
$duration = Get-AudioDuration $demoOut
$publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$description = 'An ominous electronic tune with a melancholic vibe, forboding the apocalypse. Features various percussion, synths, and an electric guitar'
$tags = @(
  'Action', 'Menu', 'Level', 'Gameplay', 'Cyberpunk', 'Badass', 'Dark', 'Ominous', 'Dangerous',
  'Mystery', 'Bad', 'Scary', 'Horror', 'Futuristic', 'Scifi', 'Science', 'Apocalyptic', 'Beat',
  'Serious', 'Underscore', 'Future', 'Retro', 'Electronic', 'Techno', 'Melancholic', 'Cinematic'
)
$genre = 'Cinematic'
$bpm = 120

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$existing = @($catalog.tracks | Where-Object { $_.title -eq $title -or [int]$_.id -eq $trackId } | Select-Object -First 1)
if ($existing.Count -gt 0) {
  $catalog.tracks = @($catalog.tracks | ForEach-Object {
    if ($_.title -eq $title -or [int]$_.id -eq $trackId) {
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
      if (-not $updated.Contains('publishedAt') -or -not $updated.publishedAt) {
        $updated.publishedAt = $publishedAt
      }
      if (-not $updated.Contains('status') -or -not $updated.status) {
        $updated.status = 'published'
      }
      return [pscustomobject]$updated
    }
    $_
  })
} else {
  $newEntry = [ordered]@{
    id = $trackId
    title = $title
    genre = $genre
    bpm = $bpm
    duration = $duration
    price = 9
    loopPrice = 9
    tags = @($tags)
    desc = $description
    cover = "tracks/$slug/cover.jpg"
    demo = "tracks/$slug/demo.mp3"
    loopZip = "tracks/$slug/loop.zip"
    status = 'published'
    publishedAt = $publishedAt
  }
  if ($hasFullPack) {
    $newEntry.packPrice = 12
    $newEntry.packZip = "tracks/$slug/pack.zip"
  } else {
    $newEntry.loopOnly = $true
  }
  $catalog.tracks += [pscustomobject]$newEntry
}
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

Write-Host "Imported/updated track #$trackId '$title' -> tracks/$slug ($(if ($hasFullPack) { 'loop + pack' } else { 'loop only' }))"
Write-Host "  cover.jpg  from $coverSource"
Write-Host "  demo.mp3   128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB"
Write-Host "  loop.zip   contains $(Split-Path $loopWav -Leaf), $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB"
if ($hasFullPack) {
  Write-Host "  pack.zip   $([math]::Round((Get-Item $packOut).Length/1MB,2)) MB (all files from Dropbox full pack)"
} else {
  Write-Host "  pack.zip   (not included - loop-only track)"
}
