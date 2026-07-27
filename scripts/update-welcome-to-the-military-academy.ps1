# Import / refresh Welcome to the Military Academy demo.mp3 and loop.zip ($9 loop WAV only — no full pack).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\welcome-to-the-military-academy'
$staging = Join-Path $PSScriptRoot '.import-staging\welcome-to-the-military-academy'
$localWav = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops WAV\Welcome to the Military Academy.wav'
$coverFinal = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops IMG\Final\Welcome to the Military Academy.jpg'
$loopWavName = 'Welcome to the Military Academy.wav'
$title = 'Welcome to the Military Academy'
$slug = 'welcome-to-the-military-academy'
$trackId = 28
$catalogPath = Join-Path $ProjectRoot 'tracks\catalog.json'
$metaPath = Join-Path $ProjectRoot 'tracks\track-meta.json'

$ffmpeg = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$ffprobe = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ffmpeg) { throw 'ffmpeg not found in scripts/.tools — run update-2am-snowflakes.ps1 once to fetch it.' }
if (-not $ffprobe) { throw 'ffprobe not found in scripts/.tools.' }
if (-not (Test-Path -LiteralPath $localWav)) { throw "Missing source WAV: $localWav" }

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

function Resolve-Cover([string]$OutPath) {
  if (Test-Path -LiteralPath $coverFinal) {
    Copy-Item -LiteralPath $coverFinal -Destination $OutPath -Force
    return "Dropbox Final\$(Split-Path $coverFinal -Leaf)"
  }
  $wc = Invoke-RestMethod "https://gamemusicandsoundeffects.com/wp-json/wc/store/products?slug=welcome-to-the-military-academy&per_page=1" -TimeoutSec 60
  if (-not $wc -or $wc.Count -eq 0) { throw 'Cover not found locally or on website.' }
  $coverUrl = $wc[0].images[0].src -replace '\?.*$', ''
  Invoke-WebRequest -Uri $coverUrl -OutFile $OutPath -TimeoutSec 120
  return $coverUrl
}

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

$wavStaging = Join-Path $staging $loopWavName
Copy-Item -LiteralPath $localWav -Destination $wavStaging -Force
Write-Host "Using loop WAV: $localWav"

$loopZip = Join-Path $trackDir 'loop.zip'
if (Test-Path $loopZip) { Remove-Item $loopZip -Force }
Compress-Archive -LiteralPath $wavStaging -DestinationPath $loopZip -Force

$demoOut = Join-Path $trackDir 'demo.mp3'
& $ffmpeg.FullName @(
  '-y', '-hide_banner', '-loglevel', 'error',
  '-i', $wavStaging,
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

# Metadata from Tracks-Upload-Status-2013.xlsx via track-meta.json
$description = 'A fun marching theme to match audiovisual projects related to police, army, training, and military schools. Militant and somewhat comic. Featuring whistles, marching band percussion and a tuba. Suitable for games, commercials, and film'
$metaTags = @(
  'army', 'marching', 'band', 'military', 'comedy', 'funny', 'uplifting', 'drums', 'tuba', 'whistle',
  'soldier', 'training', 'academy', 'school', 'left', 'right', 'parade', 'marine', 'usa', 'war',
  'snare', 'proud', 'athletic'
)
$tags = @($metaTags | ForEach-Object {
  if ($_ -match '^usa$') { 'USA' }
  else { (Get-Culture).TextInfo.ToTitleCase($_.ToLowerInvariant()) }
})
$genre = 'Games'
$bpm = 120
$instruments = 'whistles, snare, drums, tuba'
$category2 = 'commercials'

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
$metaMatch = @(
  'welcome-to-the-military-academy',
  'welcome-to-the-military-academy-loop',
  $title,
  'Welcome to the Military Academy (loop)'
)
$meta.tracks = @($meta.tracks | Where-Object {
  $_.slug -notin $metaMatch -and $_.title -notin $metaMatch
})
$meta.tracks += [pscustomobject][ordered]@{
  title = $title
  slug = $slug
  description = $description
  tags = @($metaTags)
  genre = $genre
  bpm = $bpm
  duration = $duration
  key = 'C'
  timeSignature = '4,4'
  instruments = $instruments
  category2 = $category2
  motionElements = 'v'
}
$meta._updated = (Get-Date -Format 'yyyy-MM-dd')
($meta | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $metaPath -Encoding UTF8 -NoNewline
Add-Content $metaPath "`n" -Encoding UTF8

Write-Host "Imported/updated track #$trackId '$title' -> tracks/$slug (loop only)"
Write-Host "  cover.jpg  from $coverSource"
Write-Host "  demo.mp3   128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB"
Write-Host "  loop.zip   contains $(Split-Path $wavStaging -Leaf), $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB"
Write-Host "  pack.zip   (not included - loop-only track)"
