# Scan pack.zip files and write packContents [{ name, duration }] into tracks/catalog.json.
# Uses ffprobe from scripts/.tools (same bundle as other import scripts).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Join-Path $PSScriptRoot '..'
$catalogPath = Join-Path $ProjectRoot 'tracks\catalog.json'

$ffprobe = Get-ChildItem (Join-Path $PSScriptRoot '.tools') -Recurse -Filter ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ffprobe) { throw 'ffprobe not found in scripts/.tools - run update-2am-snowflakes.ps1 once to fetch it.' }

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

function Get-PackContents([string]$PackZipPath) {
  $tmp = Join-Path $env:TEMP ("pack-manifest-" + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    Expand-Archive -LiteralPath $PackZipPath -DestinationPath $tmp -Force
    $files = Get-ChildItem $tmp -Recurse -File |
      Where-Object { $_.Extension -match '\.(wav|mp3|flac|aiff?)$' } |
      Sort-Object Name
    $items = @()
    foreach ($f in $files) {
      $items += [ordered]@{
        name     = $f.Name
        duration = (Get-AudioDuration $f.FullName)
      }
    }
    return ,$items
  } finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$updated = 0

$catalog.tracks = @($catalog.tracks | ForEach-Object {
  $track = $_
  $packZipRel = $track.packZip
  if (-not $packZipRel) { return $track }

  $packZipPath = Join-Path $ProjectRoot ($packZipRel -replace '/', '\')
  if (-not (Test-Path -LiteralPath $packZipPath)) {
    Write-Warning "Skip $($track.title): missing $packZipRel"
    return $track
  }

  $contents = Get-PackContents $packZipPath
  Write-Host "$($track.title): $($contents.Count) files"
  $contents | ForEach-Object { Write-Host "  $($_.name) - $($_.duration)" }

  $ordered = [ordered]@{}
  $track.PSObject.Properties | ForEach-Object {
    if ($_.Name -ne 'packContents') { $ordered[$_.Name] = $_.Value }
  }
  $ordered['packContents'] = $contents
  $updated++
  return [pscustomobject]$ordered
})

$catalog | ConvertTo-Json -Depth 10 | Set-Content -Path $catalogPath -Encoding UTF8
Write-Host "Updated $updated track(s) with packContents in tracks/catalog.json"
