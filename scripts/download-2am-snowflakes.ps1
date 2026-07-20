$dest = 'C:\Users\ionic\gamemusic-store-mockup\tracks\2am-snowflakes'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$downloads = @(
  @{
    Out = 'loop.zip'
    Url = 'https://www.dropbox.com/scl/fo/sjq6oti9wvkqc4k0wkvrr/ADO857mTRn34Ax0O6LgC4Qg/2AM%20Snowflakes%20-%20long%20loop.zip?rlkey=1dhn5zqej013wjlis8t3ws920&dl=1'
  },
  @{
    Out = 'pack.zip'
    Url = 'https://www.dropbox.com/scl/fo/sjq6oti9wvkqc4k0wkvrr/AFfAQE0Z9e3gSj9b6-jonpY/2AM%20Snowflakes.zip?rlkey=1dhn5zqej013wjlis8t3ws920&dl=1'
  }
)

foreach ($item in $downloads) {
  $outPath = Join-Path $dest $item.Out
  Write-Host "Downloading $($item.Out) ..."
  & curl.exe -L --fail -o $outPath $item.Url
  if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED: $($item.Out) (exit $LASTEXITCODE)"
    exit 1
  }
  $info = Get-Item $outPath
  Write-Host "Saved $($info.Name) ($([math]::Round($info.Length/1MB,2)) MB)"
}

Write-Host 'Done.'
