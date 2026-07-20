$names = @('demo.mp3', '2AM Snowflakes - long loop.zip', '2AM Snowflakes.zip')
$roots = @(
  "$env:USERPROFILE\Downloads",
  "$env:USERPROFILE\Desktop",
  "$env:USERPROFILE\Documents",
  "$env:USERPROFILE\Music",
  "$env:USERPROFILE\OneDrive",
  'C:\Users\ionic\gamemusic-store-mockup'
)
foreach ($root in $roots) {
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $names -contains $_.Name } |
    Select-Object FullName, Length, LastWriteTime
}
