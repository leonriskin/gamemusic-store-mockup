param([string]$Pattern = 'Santa')
$xlsx = Join-Path $PSScriptRoot '..\tracks\Tracks-Upload-Status-2013.xlsx'
$tempZip = Join-Path $env:TEMP ("xlsx-$([guid]::NewGuid()).zip")
$extractDir = Join-Path $env:TEMP ("xlsx-$([guid]::NewGuid())")
Copy-Item $xlsx $tempZip
Expand-Archive $tempZip $extractDir -Force
$shared = [xml](Get-Content (Join-Path $extractDir 'xl\sharedStrings.xml') -Raw -Encoding UTF8)
$strings = @()
foreach ($si in $shared.sst.si) {
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
$sheet = [xml](Get-Content (Join-Path $extractDir 'xl\worksheets\sheet1.xml') -Raw -Encoding UTF8)
foreach ($row in $sheet.worksheet.sheetData.row) {
  $vals = @()
  foreach ($cell in $row.c) {
    $v = if ($cell.t -eq 's') { $strings[[int]$cell.v] } elseif ($cell.v) { [string]$cell.v } else { $null }
    if ($v) { $vals += $v }
  }
  $line = ($vals -join ' | ')
  if ($line -match $Pattern) { Write-Output $line }
}
