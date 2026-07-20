# Parses tracks/Tracks-Upload-Status-2013.xlsx (sheet "Tracks Status ") into tracks/track-meta.json
param(
  [string]$XlsxPath = (Join-Path $PSScriptRoot '..\tracks\Tracks-Upload-Status-2013.xlsx'),
  [string]$OutPath = (Join-Path $PSScriptRoot '..\tracks\track-meta.json')
)

$ErrorActionPreference = 'Stop'
$XlsxPath = (Resolve-Path $XlsxPath).Path
$OutPath = [IO.Path]::GetFullPath($OutPath)

function Get-ColumnLetters([int]$index) {
  $n = $index + 1
  $s = ''
  while ($n -gt 0) {
    $rem = ($n - 1) % 26
    $s = [char](65 + $rem) + $s
    $n = [int](($n - 1) / 26)
  }
  return $s
}

function Parse-CellRef([string]$ref) {
  if ($ref -match '^([A-Z]+)(\d+)$') {
    $letters = $Matches[1]
    $row = [int]$Matches[2]
    $col = 0
    foreach ($ch in $letters.ToCharArray()) {
      $col = $col * 26 + ([int][char]$ch - 64)
    }
    return @{ Row = $row; Col = $col - 1 }
  }
  return $null
}

$tempZip = Join-Path $env:TEMP ("track-meta-" + [guid]::NewGuid().ToString() + '.zip')
$extractDir = Join-Path $env:TEMP ("track-meta-" + [guid]::NewGuid().ToString())
Copy-Item $XlsxPath $tempZip
Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force

$ns = @{ m = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main' }
$sharedXml = [xml](Get-Content (Join-Path $extractDir 'xl\sharedStrings.xml') -Raw -Encoding UTF8)
$strings = @()
foreach ($si in $sharedXml.sst.si) {
  if ($si.t.'#text') { $strings += $si.t.'#text' }
  elseif ($si.t) { $strings += [string]$si.t }
  else {
    $parts = @()
    foreach ($node in $si.r) {
      if ($node.t.'#text') { $parts += $node.t.'#text' }
      elseif ($node.t) { $parts += [string]$node.t }
    }
    $strings += ($parts -join '')
  }
}

$sheetPath = Join-Path $extractDir 'xl\worksheets\sheet1.xml'
$sheetXml = [xml](Get-Content $sheetPath -Raw -Encoding UTF8)
$rows = @{}
foreach ($row in $sheetXml.worksheet.sheetData.row) {
  $rowNum = [int]$row.r
  $cells = @{}
  foreach ($cell in $row.c) {
    $pos = Parse-CellRef $cell.r
    if (-not $pos) { continue }
    $value = $null
    if ($cell.t -eq 's') { $value = $strings[[int]$cell.v] }
    elseif ($cell.v) { $value = [string]$cell.v }
    $cells[$pos.Col] = $value
  }
  $rows[$rowNum] = $cells
}

if ($rows.Count -lt 2) { throw 'No data rows found in Tracks Status sheet.' }

$headerRow = $rows[1]
$headers = @{}
foreach ($kv in $headerRow.GetEnumerator()) {
  $name = ($kv.Value -replace '\s+', ' ').Trim()
  if ($name) { $headers[$name.ToLowerInvariant()] = [int]$kv.Key }
}

function Get-Cell($rowCells, [string[]]$names) {
  foreach ($name in $names) {
    $key = $name.ToLowerInvariant()
    if ($headers.ContainsKey($key) -and $rowCells.ContainsKey($headers[$key])) {
      $val = $rowCells[$headers[$key]]
      if ($val -and $val.Trim()) { return $val.Trim() }
    }
  }
  return $null
}

function Split-Tags([string]$raw) {
  if (-not $raw) { return @() }
  return ($raw -split '[;,/|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Slugify([string]$text) {
  $s = ($text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
  return $s
}

function Parse-Bpm([string]$raw) {
  if (-not $raw) { return $null }
  if ($raw -match '(\d{2,3})') { return [int]$Matches[1] }
  return $null
}

function Parse-Duration([string]$raw) {
  if (-not $raw) { return $null }
  $raw = $raw.Trim()
  if ($raw -match '^(\d+):(\d{1,2})$') {
    return ('{0}:{1}' -f [int]$Matches[1], $Matches[2].PadLeft(2, '0'))
  }
  if ($raw -match '^(\d+)m\s*(\d+)s$') {
    return ('{0}:{1}' -f [int]$Matches[1], $Matches[2].PadLeft(2, '0'))
  }
  return $raw
}

$tracks = @()
for ($r = 2; $r -le ($rows.Keys | Measure-Object -Maximum).Maximum; $r++) {
  if (-not $rows.ContainsKey($r)) { continue }
  $cells = $rows[$r]
  $title = Get-Cell $cells @('Track Title', 'Title')
  if (-not $title) { continue }

  $tags = Split-Tags (Get-Cell $cells @('Tags'))
  $genre = Get-Cell $cells @('Category 1', 'Genre', 'Category')
  if (-not $genre) { $genre = Get-Cell $cells @('Category 2') }

  $track = [ordered]@{
    title = $title
    slug = Slugify $title
    description = Get-Cell $cells @('Description')
    tags = $tags
    genre = $genre
    bpm = Parse-Bpm (Get-Cell $cells @('BPM', 'Tempo, Key, Time Signature'))
    duration = Parse-Duration (Get-Cell $cells @('Duration'))
    key = Get-Cell $cells @('Key')
    timeSignature = Get-Cell $cells @('Time Sig.', 'Time Signature')
    instruments = Get-Cell $cells @('Instruments')
    category2 = Get-Cell $cells @('Category 2')
    loop = Get-Cell $cells @('Loop')
    motionElements = Get-Cell $cells @('Motion Elements')
  }

  $hasMeta = [bool]($track.description -or $track.tags.Count -gt 0 -or $track.genre -or $track.bpm -or $track.duration)
  if (-not $hasMeta) { continue }

  $clean = [ordered]@{}
  foreach ($prop in $track.Keys) {
    $val = $track[$prop]
    if ($null -eq $val) { continue }
    if ($val -is [array] -and $val.Count -eq 0) { continue }
    if ($val -is [string] -and -not $val.Trim()) { continue }
    $clean[$prop] = $val
  }
  $tracks += $clean
}

$output = [ordered]@{
  _sourceUrl = 'https://www.dropbox.com/scl/fi/my8k721elifs4zl71dosm/Tracks-Upload-Status-2013.xlsx?rlkey=3ome8ym5wcg0sbg4q3u4ddcv0&dl=0'
  _source = 'Tracks-Upload-Status-2013.xlsx'
  _sheet = 'Tracks Status '
  _updated = (Get-Date).ToString('yyyy-MM-dd')
  _instructions = 'Update the spreadsheet, copy it to tracks/Tracks-Upload-Status-2013.xlsx, then run scripts/import-track-meta.ps1'
  tracks = $tracks
}

$json = $output | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($OutPath, $json, [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $($tracks.Count) tracks to $OutPath"

Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
