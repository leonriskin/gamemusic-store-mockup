# Runs before git push: sync local tracks/* to Cloudflare R2 (incremental).
# Installed automatically by scripts/install-git-hooks.ps1 (see .githooks/pre-push).
param(
  [string]$ProjectRoot = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$TracksRoot = Join-Path $ProjectRoot 'tracks'

if (-not (Test-Path $TracksRoot)) {
  Write-Host "pre-push: no tracks/ folder — skipping R2 upload."
  exit 0
}

$media = Get-ChildItem -Path $TracksRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object {
    $_.Name -notlike '.~lock*' -and
    $_.Extension -in @('.mp3', '.zip', '.jpg', '.jpeg', '.png', '.json')
  }

if (-not $media -or $media.Count -eq 0) {
  Write-Host "pre-push: no track files to upload — skipping R2 upload."
  exit 0
}

Write-Host ""
Write-Host "pre-push: syncing $($media.Count) track file(s) to Cloudflare R2..." -ForegroundColor Cyan
Write-Host "(incremental — unchanged files are skipped)" -ForegroundColor DarkGray
Write-Host ""

& (Join-Path $PSScriptRoot 'upload-tracks-to-r2.ps1') -ProjectRoot $ProjectRoot -SkipExisting
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "pre-push: R2 upload failed — push blocked." -ForegroundColor Red
  Write-Host "Fix auth (.env R2 keys or wrangler login) and retry git push." -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Host "pre-push: R2 upload complete." -ForegroundColor Green
exit 0
