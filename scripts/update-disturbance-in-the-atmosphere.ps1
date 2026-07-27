# Import / refresh Disturbance in the Atmosphere demo.mp3 and loop.zip ($9 loop WAV only — no full pack).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\disturbance-in-the-atmosphere'
$staging = Join-Path $PSScriptRoot '.import-staging\disturbance-in-the-atmosphere'
$coverFinal = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops IMG\Final\Disturbance in the Atmosphere.jpg'
$coverFinalAlt = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops IMG\Final\Disturbance In The Atmosphere.jpg'
$loopZipUrl = 'https://www.dropbox.com/scl/fi/kvpmpxedfqpifmfhf8m6w/Disturbance-in-the-Atmosphere.zip?rlkey=d3z5wz0gb3oy4c0kx8pkoj5r4&dl=1'
$loopZipUrlAlt = 'https://www.dropbox.com/scl/fi/kvpmpxedfqpqpifmfhf8m6w/Disturbance-in-the-Atmosphere.zip?rlkey=d3z5wz0gb3oy4c0kx8pkoj5r4&dl=1'
$loopWavName = 'Disturbance in the Atmosphere loop.wav'
$title = 'Disturbance in the Atmosphere'
$slug = 'disturbance-in-the-atmosphere'
$trackId = 27
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
      ($_.BaseName -match '(?i)disturbance in the atmosphere' -and $_.BaseName -match '(?i)\bloop\b' -and $_.BaseName -notmatch 'short')
    } |
    Select-Object -First 1
  if (-not $found) {
    $only = @(Get-ChildItem $ExtractRoot -Recurse -Filter '*.wav' -ErrorAction SilentlyContinue)
    if ($only.Count -eq 1) { return $only[0].FullName }
    throw "Missing loop WAV in extracted zip"
  }
  return $found.FullName
}

function Resolve-Cover([string]$OutPath) {
  foreach ($candidate in @($coverFinal, $coverFinalAlt)) {
    if (Test-Path -LiteralPath $candidate) {
      Copy-Item -LiteralPath $candidate -Destination $OutPath -Force
      return "Dropbox Final\$(Split-Path $candidate -Leaf)"
    }
  }
  $wc = Invoke-RestMethod "https://gamemusicandsoundeffects.com/wp-json/wc/store/products?slug=disturbance-in-the-atmosphere&per_page=1" -TimeoutSec 60
  if (-not $wc -or $wc.Count -eq 0) { throw 'Cover not found locally or on website.' }
  $coverUrl = $wc[0].images[0].src -replace '\?.*$', ''
  Invoke-WebRequest -Uri $coverUrl -OutFile $OutPath -TimeoutSec 120
  return $coverUrl
}

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

$loopStagingZip = Join-Path $staging 'loop-source.zip'
Write-Host 'Downloading loop zip from Dropbox...'
foreach ($url in @($loopZipUrl, $loopZipUrlAlt)) {
  & curl.exe -L --fail -o $loopStagingZip $url
  if ((Test-Path $loopStagingZip) -and (Get-Item $loopStagingZip).Length -gt 1MB) { break }
}
if (-not (Test-Path $loopStagingZip) -or (Get-Item $loopStagingZip).Length -lt 1MB) {
  throw 'Could not obtain loop zip.'
}

$extractRoot = Join-Path $staging 'extract'
Expand-Archive -LiteralPath $loopStagingZip -DestinationPath $extractRoot -Force
$loopWav = Resolve-LoopWav $extractRoot
Write-Host "Using loop WAV: $(Split-Path $loopWav -Leaf)"

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

if (Test-Path (Join-Path $trackDir 'pack.zip')) {
  Remove-Item (Join-Path $trackDir 'pack.zip') -Force
}

$coverOut = Join-Path $trackDir 'cover.jpg'
$coverSource = Resolve-Cover $coverOut
$duration = Get-AudioDuration $demoOut
$publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$description = 'A futuristic tune with a cyberpunk vibe. Upbeat, dark, and ominous.'
$tags = @(
  'Action', 'Menu', 'Level', 'Gameplay', 'Cyberpunk', 'Badass', 'Dark', 'Ominous', 'Dangerous',
  'Mystery', 'Bad', 'Scary', 'Horror', 'Futuristic', 'Scifi', 'Science', 'Apocalyptic', 'Beat',
  'Serious', 'Underscore', 'Future', 'Retro', 'Electronic', 'Techno', 'Melancholic', 'Cinematic'
)
$metaTags = @(
  'action', 'menu', 'level', 'gameplay', 'cyberpunk', 'badass', 'dark', 'ominous', 'dangerous',
  'mystery', 'bad', 'scary', 'horror', 'futuristic', 'scifi', 'science', 'apocalyptic', 'beat',
  'serious', 'underscore', 'future', 'retro', 'electronic', 'techno', 'melancholic', 'cinematic'
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
        if ($_.Name -notin @('packPrice', 'packZip', 'packContents')) { $updated[$_.Name] = $_.Value }
      }
      $updated.duration = $duration
      $updated.price = 9
      $updated.loopPrice = 9
      $updated.loopOnly = $true
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
    loopOnly = $true
  }
  $catalog.tracks += [pscustomobject]$newEntry
}
($catalog | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $catalogPath -Encoding UTF8 -NoNewline
Add-Content $catalogPath "`n" -Encoding UTF8

$meta = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$metaExisting = @($meta.tracks | Where-Object { $_.slug -eq $slug -or $_.title -eq $title } | Select-Object -First 1)
if ($metaExisting.Count -gt 0) {
  $meta.tracks = @($meta.tracks | ForEach-Object {
    if ($_.slug -eq $slug -or $_.title -eq $title) {
      $updated = [ordered]@{}
      $_.PSObject.Properties | ForEach-Object { $updated[$_.Name] = $_.Value }
      $updated.duration = $duration
      return [pscustomobject]$updated
    }
    $_
  })
} else {
  $meta.tracks += [pscustomobject][ordered]@{
    title = $title
    slug = $slug
    description = $description
    tags = @($metaTags)
    genre = 'video games'
    bpm = $bpm
    duration = $duration
    instruments = 'synths, drums'
    category2 = 'film'
    motionElements = 'v'
  }
}
$meta._updated = (Get-Date -Format 'yyyy-MM-dd')
($meta | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $metaPath -Encoding UTF8 -NoNewline
Add-Content $metaPath "`n" -Encoding UTF8

Write-Host "Imported/updated track #$trackId '$title' -> tracks/$slug (loop only)"
Write-Host "  cover.jpg  from $coverSource"
Write-Host "  demo.mp3   128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB"
Write-Host "  loop.zip   contains $(Split-Path $loopWav -Leaf), $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB"
Write-Host "  pack.zip   (not included - loop-only track)"
