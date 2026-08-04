# One-click: authenticate (if needed) and start R2 upload
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')

Write-Host "Riskin Tracks -> Cloudflare R2 upload" -ForegroundColor Cyan
Write-Host "Bucket: riskin-tracks"
Write-Host ""

if (-not (Test-Path (Join-Path $Root 'node_modules\wrangler'))) {
  Write-Host "Installing wrangler..."
  npm install wrangler --save-dev
}

$wrangler = Join-Path $Root 'node_modules\.bin\wrangler.cmd'
$whoami = & $wrangler whoami 2>&1 | Out-String
if ($whoami -match 'not authenticated' -and -not (Test-Path (Join-Path $Root '.env'))) {
  Write-Host "Opening Cloudflare login in your browser..." -ForegroundColor Yellow
  Write-Host "Complete login, then this script will continue."
  & $wrangler login
}

# Prefer incremental upload unless -DryRun.
$uploadArgs = @()
if ($DryRun) { $uploadArgs += '-DryRun' } else { $uploadArgs += '-SkipExisting' }
& (Join-Path $PSScriptRoot 'upload-tracks-to-r2.ps1') @uploadArgs
