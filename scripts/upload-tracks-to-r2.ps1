# Upload tracks/* media to Cloudflare R2 bucket riskin-tracks
# Requires: Node.js, npm install (wrangler), and either wrangler login OR .env with R2 keys
param(
  [string]$ProjectRoot = (Join-Path $PSScriptRoot '..'),
  [string]$Bucket = 'riskin-tracks',
  [switch]$DryRun,
  [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$TracksRoot = Join-Path $ProjectRoot 'tracks'
$EnvFile = Join-Path $ProjectRoot '.env'
$LogFile = Join-Path $ProjectRoot 'scripts\r2-upload.log'
$StateFile = Join-Path $ProjectRoot 'scripts\.r2-upload-state.json'
$PublicBase = 'https://pub-45a1df6488174a1a84baf1ed003ac6dd.r2.dev'

function Write-Log([string]$Message) {
  $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
  Add-Content -Path $LogFile -Value $line
  Write-Host $line
}

function Load-DotEnv([string]$Path) {
  if (-not (Test-Path $Path)) { return @{} }
  $map = @{}
  Get-Content $Path | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $parts = $_ -split '=', 2
    if ($parts.Count -eq 2) { $map[$parts[0].Trim()] = $parts[1].Trim() }
  }
  return $map
}

function Get-WranglerExe([string]$Root) {
  $local = Join-Path $Root 'node_modules\.bin\wrangler.cmd'
  if (Test-Path $local) { return $local }
  return 'wrangler'
}

function Load-UploadState([string]$Path) {
  if (-not (Test-Path $Path)) { return @{} }
  try {
    $raw = Get-Content $Path -Raw | ConvertFrom-Json
    $map = @{}
    $raw.PSObject.Properties | ForEach-Object { $map[$_.Name] = [string]$_.Value }
    return $map
  } catch {
    return @{}
  }
}

function Save-UploadState([string]$Path, [hashtable]$State) {
  ($State.GetEnumerator() | Sort-Object Name | ForEach-Object {
    [ordered]@{ $_.Key = $_.Value }
  }) | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8
}

function Get-FileFingerprint([IO.FileInfo]$File) {
  return "{0}-{1}" -f $File.Length, $File.LastWriteTimeUtc.Ticks
}

if (-not (Test-Path $TracksRoot)) { throw "Missing tracks folder: $TracksRoot" }

$envMap = Load-DotEnv $EnvFile
if ($envMap['R2_ACCOUNT_ID']) { $env:CLOUDFLARE_ACCOUNT_ID = $envMap['R2_ACCOUNT_ID'] }
if ($envMap['CLOUDFLARE_ACCOUNT_ID']) { $env:CLOUDFLARE_ACCOUNT_ID = $envMap['CLOUDFLARE_ACCOUNT_ID'] }
if ($envMap['CLOUDFLARE_API_TOKEN']) { $env:CLOUDFLARE_API_TOKEN = $envMap['CLOUDFLARE_API_TOKEN'] }
if ($envMap['R2_ACCESS_KEY_ID']) { $env:R2_ACCESS_KEY_ID = $envMap['R2_ACCESS_KEY_ID'] }
if ($envMap['R2_SECRET_ACCESS_KEY']) { $env:R2_SECRET_ACCESS_KEY = $envMap['R2_SECRET_ACCESS_KEY'] }
if (-not $env:CLOUDFLARE_ACCOUNT_ID) { $env:CLOUDFLARE_ACCOUNT_ID = '90f505deba234410dfcef0f5a4b880f8' }

$wrangler = Get-WranglerExe $ProjectRoot
Push-Location $ProjectRoot
try {
  Write-Log "Checking wrangler auth..."
  $whoami = & $wrangler whoami 2>&1 | Out-String
  $wranglerAuthed = $whoami -notmatch 'not authenticated'
  if (-not $wranglerAuthed) {
    if ($env:CLOUDFLARE_API_TOKEN) {
      Write-Log "Using CLOUDFLARE_API_TOKEN from .env"
    } elseif ($env:R2_ACCESS_KEY_ID -and $env:R2_SECRET_ACCESS_KEY) {
      Write-Log "Wrangler not logged in; will use S3-compatible upload with R2 keys from .env"
    } else {
      throw @"
Not authenticated. Run ONE of:
  1) npx wrangler login
  2) Add CLOUDFLARE_API_TOKEN to .env
  3) Add R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY to .env (from Cloudflare R2 API Tokens)
"@
    }
  } else {
    Write-Log $whoami.Trim()
  }

  $files = Get-ChildItem -Path $TracksRoot -Recurse -File |
    Where-Object {
      $_.Name -notlike '.~lock*' -and
      $_.Extension -in @('.mp3', '.zip', '.jpg', '.jpeg', '.png', '.json')
    } |
    Sort-Object FullName

  Write-Log "Found $($files.Count) files to upload (~$([math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 0)) MB)"

  if ($DryRun) {
    Write-Log "Dry run only — no uploads performed."
    return
  }

  if ($env:R2_ACCESS_KEY_ID -and $env:R2_SECRET_ACCESS_KEY) {
    Write-Log "Using S3-compatible upload (node upload-r2.mjs, skip-existing=$($SkipExisting.IsPresent))"
    $nodeArgs = @((Join-Path $PSScriptRoot 'upload-r2.mjs'))
    if (-not $SkipExisting) { $nodeArgs += '--force' }
    & node @nodeArgs
    if ($LASTEXITCODE -ne 0) { throw "upload-r2.mjs failed with exit code $LASTEXITCODE" }
    Write-Log "Upload complete. Public base: $PublicBase"
    return
  }

  $state = Load-UploadState $StateFile
  $i = 0
  foreach ($file in $files) {
    $i++
    $rel = $file.FullName.Substring($ProjectRoot.Length + 1).Replace('\', '/')
    $objectKey = $rel
    $fingerprint = Get-FileFingerprint $file
    $pct = [math]::Round(100 * $i / $files.Count, 1)

    if ($SkipExisting -and $state[$objectKey] -eq $fingerprint) {
      Write-Log "[$i/$($files.Count) $pct%] skip (unchanged) $objectKey"
      continue
    }

    Write-Log "[$i/$($files.Count) $pct%] upload $objectKey ($([math]::Round($file.Length / 1MB, 2)) MB)"
    & $wrangler r2 object put "$Bucket/$objectKey" --file="$($file.FullName)" --remote 2>&1 | Out-String | ForEach-Object { if ($_.Trim()) { Write-Log $_.Trim() } }
    if ($LASTEXITCODE -ne 0) { throw "wrangler upload failed for $objectKey (exit $LASTEXITCODE)" }
    $state[$objectKey] = $fingerprint
  }

  Save-UploadState $StateFile $state
  Write-Log "Upload complete. Public base: $PublicBase"
  Write-Log "Example: $PublicBase/tracks/2am-snowflakes/demo.mp3"
}
finally {
  Pop-Location
}
