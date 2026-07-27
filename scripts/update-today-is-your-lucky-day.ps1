# Import / refresh Today Is Your Lucky Day demo.mp3, loop.zip ($9 loop WAV), and pack.zip ($12 full pack).
#
# Multi-file zip convention:
#   Source zip contains multiple WAV variants. ONE loop file is designated for:
#     - demo.mp3 (128 kbps MP3 from the loop WAV)
#     - loop.zip ($9 tier — single loop WAV only)
#   Chosen loop: "Today Is Your Lucky Day Long Loop.wav" (case-insensitive match).
#   ALL files from the source zip go into:
#     - pack.zip ($12 tier — full pack)
#   Remove loopOnly from catalog; set packPrice=12 and packZip. Run refresh-pack-manifests.ps1
#   to populate packContents with ffprobe durations.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$trackDir = Join-Path $ProjectRoot 'tracks\today-is-your-lucky-day'
$staging = Join-Path $PSScriptRoot '.import-staging\today-is-your-lucky-day'
$coverFinal = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress\Music Loops IMG\Final\Today Is Your Lucky Day.jpg'
$sourceZipUrl = 'https://www.dropbox.com/scl/fi/lrv41zy50ptijegx94kg6/Today-Is-Your-Lucky-Day.zip?rlkey=f51s9dqhi0asp458in7o8pyki&dl=1'
$loopWavName = 'Today Is Your Lucky Day Long Loop.wav'
$loopWavPattern = '(?i)today is your lucky day.*long loop'
$title = 'Today Is Your Lucky Day'
$slug = 'today-is-your-lucky-day'
$trackId = 35
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
  $exact = Get-ChildItem $ExtractRoot -Recurse -Filter '*.wav' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq $loopWavName } |
    Select-Object -First 1
  if ($exact) { return $exact.FullName }
  $found = Get-ChildItem $ExtractRoot -Recurse -Filter '*.wav' -ErrorAction SilentlyContinue |
    Where-Object { $_.BaseName -match $loopWavPattern } |
    Select-Object -First 1
  if (-not $found) { throw "Missing $loopWavName in extracted zip" }
  return $found.FullName
}

function Get-PackWavCount([string]$ExtractRoot) {
  @(Get-ChildItem $ExtractRoot -Recurse -Filter '*.wav' -ErrorAction SilentlyContinue).Count
}

function Resolve-Cover([string]$OutPath) {
  if (Test-Path -LiteralPath $coverFinal) {
    Copy-Item -LiteralPath $coverFinal -Destination $OutPath -Force
    return "Dropbox Final\$(Split-Path $coverFinal -Leaf)"
  }
  $wc = Invoke-RestMethod "https://gamemusicandsoundeffects.com/wp-json/wc/store/products?search=Today+Is+Your+Lucky+Day&per_page=10" -TimeoutSec 60
  $match = @($wc | Where-Object { $_.name -match '(?i)today is your lucky day' } | Select-Object -First 1)
  if ($match.Count -eq 0) { throw 'Cover not found locally or on website.' }
  $coverUrl = $match[0].images[0].src -replace '\?.*$', ''
  Invoke-WebRequest -Uri $coverUrl -OutFile $OutPath -TimeoutSec 120
  return $coverUrl
}

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $trackDir | Out-Null

$packStagingZip = Join-Path $staging 'pack-source.zip'
Write-Host 'Downloading source zip from Dropbox...'
& curl.exe -L --fail -o $packStagingZip $sourceZipUrl
if (-not (Test-Path $packStagingZip)) { throw 'Could not obtain source zip.' }

$extractRoot = Join-Path $staging 'pack'
Expand-Archive -LiteralPath $packStagingZip -DestinationPath $extractRoot -Force
$loopWav = Resolve-LoopWav $extractRoot
$wavCount = Get-PackWavCount $extractRoot
$hasFullPack = $wavCount -gt 1

Write-Host "Extracted $wavCount WAV file(s) from source zip."
Get-ChildItem $extractRoot -Recurse -Filter '*.wav' | Sort-Object Name | ForEach-Object { Write-Host "  - $($_.Name)" }
Write-Host "Using loop WAV for demo + loop.zip: $(Split-Path $loopWav -Leaf)"

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

# Metadata from tracks/track-meta.json (Tracks-Upload-Status-2013.xlsx export)
$description = 'This is a video game music loop. A very happy and positive track. Uplifting and cheerful. Full of good spirit and optimism. Featuring electric piano, xylophone, guitar, celeste, and 808 drums. Music has a lot of space, and settles well in the background. The tune is similar to games like: animal crossing, stardew valley, magicians quest, fantasy life, wandering willows, rune factory, shepherds crossing, castaway paradise, harvest moon, viva pinata, happy street and more of that genre. Suitable for games, animations, and children related productions.'
$metaTags = @(
  'achievement', 'atmospheric', 'beautiful', 'bright', 'calm', 'carefree', 'cheerful', 'childish',
  'cute', 'delicate', 'dreamy', 'energetic', 'excited', 'fresh', 'friendly', 'game', 'humorous',
  'inspirational', 'interesting', 'jolly', 'joyful', 'jumpy', 'light', 'lively', 'optimistic',
  'outgoing', 'playful', 'quirky', 'rhythmic', 'soft', 'spacious', 'summery', 'uplifting', 'witty', 'warm'
)
$tags = @($metaTags | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_.ToLowerInvariant()) })
$genre = 'Children'
$bpm = 100
$instruments = '808 drums, synth, xylophone, celeste, guitar'
$category2 = 'games'

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$existing = @($catalog.tracks | Where-Object { $_.title -eq $title -or [int]$_.id -eq $trackId } | Select-Object -First 1)
if ($existing.Count -gt 0) {
  $catalog.tracks = @($catalog.tracks | ForEach-Object {
    if ($_.title -eq $title -or [int]$_.id -eq $trackId) {
      $updated = [ordered]@{}
      $_.PSObject.Properties | ForEach-Object {
        if ($_.Name -notin @('loopOnly', 'packPrice', 'packZip', 'packContents')) { $updated[$_.Name] = $_.Value }
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
    genre = $genre
    bpm = $bpm
    duration = $duration
    instruments = $instruments
    category2 = $category2
    motionElements = 'v'
  }
}
$meta._updated = (Get-Date -Format 'yyyy-MM-dd')
($meta | ConvertTo-Json -Depth 8) -replace '\r?\n', "`n" | Set-Content $metaPath -Encoding UTF8 -NoNewline
Add-Content $metaPath "`n" -Encoding UTF8

Write-Host "Imported/updated track #$trackId '$title' -> tracks/$slug ($(if ($hasFullPack) { 'loop + pack' } else { 'loop only' }))"
Write-Host "  cover.jpg  from $coverSource"
Write-Host "  demo.mp3   128 kbps, $duration, $([math]::Round((Get-Item $demoOut).Length/1MB,2)) MB"
Write-Host "  loop.zip   contains $(Split-Path $loopWav -Leaf), $([math]::Round((Get-Item $loopZip).Length/1MB,2)) MB"
if ($hasFullPack) {
  Write-Host "  pack.zip   $([math]::Round((Get-Item $packOut).Length/1MB,2)) MB (all files from source zip)"
  Write-Host "  Run refresh-pack-manifests.ps1 to populate packContents."
} else {
  Write-Host "  pack.zip   (not included - loop-only track)"
}
