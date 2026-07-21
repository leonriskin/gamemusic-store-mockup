# Serves the mockup at http://localhost:8765
# Required for reliable audio storage/playback in some browsers.
Set-Location $PSScriptRoot
$port = 8765
$url = "http://localhost:$port/"

Write-Host "Open $url in your browser"
Write-Host "Press Ctrl+C to stop"

function Send-StaticFile($ctx, $file) {
  $bytes = [IO.File]::ReadAllBytes($file)
  $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
  $response = $ctx.Response
  $response.ContentType = switch ($ext) {
    '.html' { 'text/html; charset=utf-8' }
    '.js' { 'application/javascript; charset=utf-8' }
    '.css' { 'text/css; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.mp3' { 'audio/mpeg' }
    '.wav' { 'audio/wav' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.png' { 'image/png' }
    '.svg' { 'image/svg+xml' }
    '.zip' { 'application/zip' }
    default { 'application/octet-stream' }
  }
  $response.Headers['Accept-Ranges'] = 'bytes'

  $rangeHeader = $ctx.Request.Headers.Get('Range')
  if ($rangeHeader -is [array]) { $rangeHeader = $rangeHeader[0] }

  if ($rangeHeader -and ($rangeHeader -match 'bytes=(\d+)-(\d*)')) {
    $start = [int64]$Matches[1]
    $end = if ($Matches[2]) { [int64]$Matches[2] } else { $bytes.Length - 1 }
    if ($start -ge $bytes.Length -or $end -lt $start) {
      $response.StatusCode = 416
      $response.Headers['Content-Range'] = "bytes */$($bytes.Length)"
      $response.ContentLength64 = 0
      return
    }
    if ($end -ge $bytes.Length) { $end = $bytes.Length - 1 }
    $length = $end - $start + 1
    $response.StatusCode = 206
    $response.Headers['Content-Range'] = "bytes $start-$end/$($bytes.Length)"
    $response.ContentLength64 = $length
    $response.OutputStream.Write($bytes, [int]$start, [int]$length)
    return
  }

  $response.StatusCode = 200
  $response.ContentLength64 = $bytes.Length
  $response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Start-PowerShellServer {
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add($url)
  $listener.Prefixes.Add("http://127.0.0.1:$port/")
  try {
    $listener.Start()
  } catch {
    Write-Host ""
    Write-Host "Could not start server on $url"
    Write-Host "Another server is already using this port. Stop it first (Ctrl+C in its terminal), then run this script again."
    Write-Host ""
    exit 1
  }

  Write-Host "Serving files from $PSScriptRoot"
  try {
    while ($listener.IsListening) {
      $ctx = $null
      try {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.LocalPath
        if ($ctx.Request.HttpMethod -eq 'POST' -and $path -eq '/__dev/save-track-file') {
          $rel = $ctx.Request.QueryString['rel']
          if (-not $rel -or $rel -notmatch '^tracks/[a-z0-9-]+/[a-z0-9._-]+$') {
            $ctx.Response.StatusCode = 400
            continue
          }
          $target = Join-Path $PSScriptRoot ($rel.Replace('/', [IO.Path]::DirectorySeparatorChar))
          $dir = Split-Path $target -Parent
          if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
          $ms = New-Object IO.MemoryStream
          $ctx.Request.InputStream.CopyTo($ms)
          [IO.File]::WriteAllBytes($target, $ms.ToArray())
          $ctx.Response.StatusCode = 200
          $ctx.Response.ContentType = 'text/plain; charset=utf-8'
          $bytes = [Text.Encoding]::UTF8.GetBytes('OK')
          $ctx.Response.ContentLength64 = $bytes.Length
          $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
          continue
        }
        if ($ctx.Request.HttpMethod -eq 'POST' -and $path -eq '/__dev/update-catalog-track') {
          $reader = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
          $json = $reader.ReadToEnd()
          if (-not $json) {
            $ctx.Response.StatusCode = 400
            continue
          }
          try {
            $payload = $json | ConvertFrom-Json
          } catch {
            $ctx.Response.StatusCode = 400
            continue
          }
          if (-not $payload.id -or -not $payload.slug) {
            $ctx.Response.StatusCode = 400
            continue
          }
          $catalogPath = Join-Path $PSScriptRoot 'tracks\catalog.json'
          $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
          $entry = $catalog.tracks | Where-Object { [int]$_.id -eq [int]$payload.id } | Select-Object -First 1
          if (-not $entry) {
            $entry = [ordered]@{ id = [int]$payload.id }
            $catalog.tracks += $entry
          }
          $base = "tracks/$($payload.slug)"
          $entry | Add-Member -NotePropertyName demo -NotePropertyValue "$base/demo.mp3" -Force
          $entry | Add-Member -NotePropertyName loopZip -NotePropertyValue "$base/loop.zip" -Force
          $hasPack = $false
          if ($payload.PSObject.Properties.Name -contains 'hasPackZip') {
            $hasPack = [bool]$payload.hasPackZip
          } elseif ($payload.PSObject.Properties.Name -contains 'loopOnly') {
            $hasPack = -not [bool]$payload.loopOnly
          }
          if ($hasPack) {
            $entry | Add-Member -NotePropertyName packZip -NotePropertyValue "$base/pack.zip" -Force
            if ($entry.PSObject.Properties.Name -contains 'loopOnly') { $entry.PSObject.Properties.Remove('loopOnly') }
          } else {
            if ($entry.PSObject.Properties.Name -contains 'packZip') { $entry.PSObject.Properties.Remove('packZip') }
            if ($entry.PSObject.Properties.Name -contains 'packPrice') { $entry.PSObject.Properties.Remove('packPrice') }
            $entry | Add-Member -NotePropertyName loopOnly -NotePropertyValue $true -Force
          }
          if ($payload.title) { $entry | Add-Member -NotePropertyName title -NotePropertyValue $payload.title -Force }
          if ($payload.genre) { $entry | Add-Member -NotePropertyName genre -NotePropertyValue $payload.genre -Force }
          if ($payload.bpm) { $entry | Add-Member -NotePropertyName bpm -NotePropertyValue $payload.bpm -Force }
          if ($payload.duration) { $entry | Add-Member -NotePropertyName duration -NotePropertyValue $payload.duration -Force }
          if ($payload.desc) { $entry | Add-Member -NotePropertyName desc -NotePropertyValue $payload.desc -Force }
          if ($payload.loopPrice) { $entry | Add-Member -NotePropertyName loopPrice -NotePropertyValue $payload.loopPrice -Force }
          if ($payload.packPrice) { $entry | Add-Member -NotePropertyName packPrice -NotePropertyValue $payload.packPrice -Force }
          if ($payload.price) { $entry | Add-Member -NotePropertyName price -NotePropertyValue $payload.price -Force }
          if ($payload.tags) { $entry | Add-Member -NotePropertyName tags -NotePropertyValue $payload.tags -Force }
          $entry.PSObject.Properties.Remove('zip')
          ($catalog | ConvertTo-Json -Depth 8) | Set-Content $catalogPath -Encoding UTF8
          $ctx.Response.StatusCode = 200
          $ctx.Response.ContentType = 'text/plain; charset=utf-8'
          $ok = [Text.Encoding]::UTF8.GetBytes('OK')
          $ctx.Response.ContentLength64 = $ok.Length
          $ctx.Response.OutputStream.Write($ok, 0, $ok.Length)
          continue
        }
        if ($path -eq '/') { $path = '/index.html' }
        $file = Join-Path $PSScriptRoot ($path.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (Test-Path $file -PathType Leaf) {
          Send-StaticFile $ctx $file
        } else {
          $ctx.Response.StatusCode = 404
        }
      } catch {
        Write-Host "Request error: $_"
        if ($ctx -and $ctx.Response) {
          try { $ctx.Response.StatusCode = 500 } catch {}
        }
      } finally {
        if ($ctx -and $ctx.Response) {
          try { $ctx.Response.Close() } catch {}
        }
      }
    }
  } finally {
    if ($listener.IsListening) { $listener.Stop() }
  }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($env:GMS_USE_PYTHON_SERVER -eq '1' -and $python) {
  Write-Host "GMS_USE_PYTHON_SERVER=1 — admin save-to-disk endpoints are unavailable."
  & $python.Source -m http.server $port
  if ($LASTEXITCODE -eq 0) { return }
}

$py = Get-Command py -ErrorAction SilentlyContinue
if ($env:GMS_USE_PYTHON_SERVER -eq '1' -and $py) {
  Write-Host "GMS_USE_PYTHON_SERVER=1 — admin save-to-disk endpoints are unavailable."
  & $py.Source -m http.server $port
  if ($LASTEXITCODE -eq 0) { return }
}

Write-Host "Using built-in PowerShell server (admin saves update tracks/catalog.json)."
Start-PowerShellServer
