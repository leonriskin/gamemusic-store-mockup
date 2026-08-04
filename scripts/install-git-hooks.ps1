# One-time (or npm install) setup: point git at .githooks/ for automatic R2 upload on push.
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if (-not (Test-Path (Join-Path $Root '.git'))) {
  Write-Host 'install-git-hooks: not a git repo - skipping.'
  exit 0
}

Push-Location $Root
try {
  git config core.hooksPath .githooks
  Write-Host 'Git hooks installed: core.hooksPath=.githooks (pre-push syncs track media to R2).' -ForegroundColor Green
}
finally {
  Pop-Location
}
