# Import 18 tracks from Dropbox (or website demo/cover when Dropbox zip is missing)
$ErrorActionPreference = 'Stop'
$base = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress'
$preview = Join-Path $base 'Music Loops PREVIEW'
$wav = Join-Path $base 'Music Loops WAV'
$imgFinal = Join-Path $base 'Music Loops IMG\Final'
$scriptDir = $PSScriptRoot
$staging = Join-Path (Join-Path $scriptDir '..') 'scripts\.import-staging'
New-Item -ItemType Directory -Force -Path $staging | Out-Null
$staging = (Resolve-Path $staging).Path

function Get-WcProduct([string]$Slug) {
  $items = Invoke-RestMethod "https://gamemusicandsoundeffects.com/wp-json/wc/store/products?slug=$Slug&per_page=1" -TimeoutSec 60
  if (-not $items -or $items.Count -eq 0) { return $null }
  return $items[0]
}

function Get-WcProductBySearch([string]$Query) {
  $items = Invoke-RestMethod "https://gamemusicandsoundeffects.com/wp-json/wc/store/products?search=$([uri]::EscapeDataString($Query))&per_page=5" -TimeoutSec 60
  if (-not $items -or $items.Count -eq 0) { return $null }
  return $items[0]
}

function Parse-WcFields($product) {
  $html = [string]$product.name
  $plainName = ($html -split '<')[0].Trim() -replace '\s*-\s*CC\s*$', '' -replace '&#8211;', '-'
  $duration = if ($html -match 'data-duration="([^"]+)"') { $Matches[1] } else { '2:00' }
  $demoUrl = if ($html -match 'src="([^"]+\.mp3)"') { $Matches[1] } else { $null }
  $desc = [System.Net.WebUtility]::HtmlDecode(($product.short_description -replace '<[^>]+>', ' ' -replace 'Download Demo', '' -replace '\s+', ' ').Trim())
  $tags = @($product.tags | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.name) } | Where-Object { $_ })
  $genre = 'Electronic'
  $cats = @($product.categories | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.name) })
  foreach ($c in @('Chiptune', '8bit', 'Ambient', 'Orchestral', 'Cinematic', 'Rock', 'Jazz', 'Holidays', 'Acoustic')) {
    if ($cats -match $c -or ($tags -join ' ') -match $c) { $genre = $c; break }
  }
  if ($tags -contains '8bit' -or ($tags -join ' ') -match '8bit|retro') { $genre = 'Chiptune' }
  elseif ($cats -match 'Fun') { $genre = 'Electronic' }
  elseif ($cats -match 'chill') { $genre = 'Ambient' }
  $coverUrl = $product.images[0].src -replace '\?.*$', ''
  return @{
    Title = $plainName
    Duration = $duration
    DemoUrl = $demoUrl
    Description = $desc
    Tags = $tags
    Genre = $genre
    CoverUrl = $coverUrl
  }
}

function Resolve-Cover([string]$Title, [string]$CoverUrl) {
  $exact = Join-Path $imgFinal ($Title + '.jpg')
  if (Test-Path $exact) { return (Resolve-Path $exact).Path }
  $found = Get-ChildItem $imgFinal -File -ErrorAction SilentlyContinue | Where-Object {
    $_.BaseName -ieq $Title
  } | Select-Object -First 1
  if ($found) { return $found.FullName }
  if (-not $CoverUrl) { throw "No cover for $Title" }
  $safe = ($Title -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
  $out = Join-Path $staging "$safe-cover.jpg"
  Invoke-WebRequest -Uri $CoverUrl -OutFile $out -TimeoutSec 120
  return (Resolve-Path $out).Path
}

function Ensure-Demo([string]$Path, [string]$DemoUrl, [string]$FallbackName) {
  if ($Path -and (Test-Path -LiteralPath $Path)) { return (Resolve-Path -LiteralPath $Path).Path }
  if (-not $DemoUrl) { throw "Missing demo source for $FallbackName (path=$Path)" }
  $safe = ($FallbackName -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
  $out = Join-Path $staging "$safe-demo.mp3"
  Invoke-WebRequest -Uri $DemoUrl -OutFile $out -TimeoutSec 120
  return (Resolve-Path $out).Path
}

function Ensure-LoopZip([string]$Path, [string]$DemoPath, [string]$FallbackName, [switch]$WebFallback) {
  if ($Path -and (Test-Path -LiteralPath $Path)) { return (Resolve-Path -LiteralPath $Path).Path }
  if (-not $WebFallback) { throw "Missing loop zip for $FallbackName at $Path" }
  $safe = ($FallbackName -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
  $zipPath = Join-Path $staging "$safe-loop-fallback.zip"
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -LiteralPath $DemoPath -DestinationPath $zipPath -Force
  Write-Warning "Using demo MP3 as loop.zip fallback for $FallbackName (Dropbox loop zip not found)"
  return (Resolve-Path $zipPath).Path
}

$tracks = @(
  @{ Title = 'Best Time Of The Day'; Slug = 'best-time-of-the-day'; Preview = 'Best Time Of The Day - PREVIEW.mp3'; Loop = 'Best Time Of The Day.zip'; Cover = 'Best Time Of The Day.jpg' }
  @{ Title = 'Blindfold Speed Racing'; Slug = 'blindfold-speed-racing-cc'; Preview = 'Blindfold Speed Racing.mp3'; Loop = 'Blindfold Speed Racing.zip'; Cover = 'Blindfold speed racing.jpg' }
  @{ Title = 'Palm Tree Getaway Island'; Slug = 'palm-tree-getaway-island'; Preview = $null; Loop = $null; Cover = $null; WebOnly = $true }
  @{ Title = 'Against All Odds'; Slug = 'aginst-all-odds'; Preview = $null; Loop = $null; Cover = $null; WebOnly = $true }
  @{ Title = 'Tiny World'; Slug = 'tiny-world'; Preview = $null; Loop = $null; Cover = $null; WebOnly = $true }
  @{ Title = 'The Wrong Party'; Slug = 'the-wrong-party'; Preview = $null; Loop = $null; Cover = $null; WebOnly = $true }
  @{ Title = 'Building Cities'; Slug = '3423'; Preview = 'Building Cities.mp3'; Loop = 'Building Cities.zip'; Cover = $null }
  @{ Title = 'All Is Quiet Under The Sea'; Slug = 'all-is-quiet-under-the-sea'; Preview = 'All Is Quiet Under The Sea - PREVIEW.mp3'; Loop = 'All Is Quiet Under The Sea.zip'; Cover = $null }
  @{ Title = 'Welcome To The Black Market'; Slug = 'welcome-to-the-black-market'; Preview = 'Welcome To The Black Market - PREVIEW.mp3'; Loop = 'Welcome To The Black Market.zip'; Cover = $null }
  @{ Title = 'Wonders Of The Lost World'; Slug = 'wonders-of-the-lost-world'; Preview = 'Wonders Of The Lost World - PREVIEW.mp3'; Loop = 'Wonders Of The Lost World.zip'; Cover = $null }
  @{ Title = 'The Perfect Escape Plan'; Slug = 'the-perfect-escape-plan'; Preview = 'The Perfect Escape Plan - PREVIEW.mp3'; Loop = 'The Perfect Escape Plan.zip'; Cover = $null }
  @{ Title = "That Wasn't A Chicken"; Slug = 'that-wasnt-a-chicken'; Preview = 'That Wasnt A Chicken - loop PREVIEW.mp3'; Loop = 'That Wasnt A Chicken.zip'; Cover = $null }
  @{ Title = 'Deep Space Surrealism'; Slug = 'deep-space-surrealizm'; Preview = 'Deep Space Surrealizm PREVIEW.mp3'; Loop = 'Deep Space Surrealizm.zip'; Cover = $null }
  @{ Title = 'Our Dream House In The Sky'; Slug = 'our-dream-house-in-the-sky'; Preview = $null; Loop = $null; Cover = $null; WebOnly = $true }
  @{ Title = 'Burning Tracks'; Slug = 'burning-tracks'; Preview = 'Burning Tracks - full PREVIEW.mp3'; Loop = 'Burning Tracks.zip'; Cover = $null }
  @{ Title = 'A Song For Naomi'; Slug = 'a-song-for-naomi'; Preview = 'A Song For Naomi - PREVIEW.mp3'; Loop = 'A Song For Naomi.zip'; Cover = $null }
  @{ Title = 'Suspicious Mushrooms'; Slug = 'suspicious-mushrooms'; Preview = 'Suspicious Mushrooms - DEMO.mp3'; Loop = 'Suspicious Mushrooms.zip'; Cover = 'Suspicious Mushrooms.jpg' }
  @{ Title = 'Midnight Strawberries'; Slug = 'midnight-strawberries'; Preview = 'Midnight Strawberries - DEMO.mp3'; Loop = 'Midnight Strawberries - full loop.zip'; Cover = 'Midnight Strawberries.jpg' }
)

$startId = 5
$i = 0
$imported = @()
$failed = @()

foreach ($t in $tracks) {
  $i++
  $id = $startId + $i - 1
  try {
    Write-Host "`n========== [$id] $($t.Title) ==========" -ForegroundColor Cyan
    $wc = Get-WcProduct $t.Slug
    if (-not $wc) { $wc = Get-WcProductBySearch $t.Title }
    if (-not $wc) { throw "No WooCommerce product found" }
    $meta = Parse-WcFields $wc

    $previewPath = if ($t.Preview) { Join-Path $preview $t.Preview } else { $null }
    $loopPath = if ($t.Loop) { Join-Path $wav $t.Loop } else { $null }
    $coverPath = if ($t.Cover) { Join-Path $imgFinal $t.Cover } else { $null }

    $demo = Ensure-Demo $previewPath $meta.DemoUrl $t.Title
    $cover = Resolve-Cover $t.Title $meta.CoverUrl
    $loop = Ensure-LoopZip $loopPath $demo $t.Title -WebFallback:([bool]$t.WebOnly)

    $tagPick = @($meta.Tags | Select-Object -First 25)
    if ($tagPick.Count -lt 3) { $tagPick = @('Game', 'Menu', 'Gameplay') + $tagPick }

    $importParams = @{
      Title = $t.Title
      Id = $id
      PreviewMp3 = $demo
      LoopZip = $loop
      CoverImage = $cover
      Description = $meta.Description
      Tags = $tagPick
      Genre = $meta.Genre
      Bpm = 120
      Duration = $meta.Duration
      Instruments = 'synth, electronic'
      Category2 = $meta.Genre
    }
    & (Join-Path $scriptDir 'import-track.ps1') @importParams
    $imported += $t.Title
  } catch {
    Write-Host "FAILED: $($t.Title) -> $_" -ForegroundColor Red
    $failed += "$($t.Title): $_"
  }
}

Write-Host "`n========== SUMMARY =========="
Write-Host "Imported: $($imported.Count)"
$imported | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
if ($failed.Count) {
  Write-Host "Failed: $($failed.Count)" -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Red }
}
