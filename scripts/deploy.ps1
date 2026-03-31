$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$ErrorActionPreference = "Stop"

function Invoke-Native {
  param([scriptblock]$Command)
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed (exit code $LASTEXITCODE): $Command"
  }
}

# GITHUB_WORKSPACE = {runner_root}\_work\{repo}\{repo}
$runnerRoot = (Resolve-Path "$env:GITHUB_WORKSPACE\..\..\..\").Path
$appDir     = Join-Path $runnerRoot "app"
$envSource  = Join-Path $runnerRoot ".env"

Write-Host "[deploy] Runner root : $runnerRoot"
Write-Host "[deploy] App dir     : $appDir"

if (-not (Test-Path (Join-Path $runnerRoot "run.cmd"))) {
  throw "[deploy] ERROR: run.cmd not found - check runner root path: $runnerRoot"
}

if (-not (Test-Path $envSource)) {
  throw "[deploy] ERROR: .env not found at: $envSource"
}

# Create app directory on first run
if (-not (Test-Path $appDir)) {
  New-Item -ItemType Directory -Path $appDir | Out-Null
  Write-Host "[deploy] Created app directory"
}

# Sync source files
Write-Host "[deploy] Syncing source files..."
robocopy $env:GITHUB_WORKSPACE $appDir /E /XD .git data /XF "*.db" "*.db-shm" "*.db-wal" /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) {
  throw "[deploy] robocopy failed (exit code $LASTEXITCODE)"
}
Write-Host "[deploy] Source sync complete"

# Always overwrite .env immediately after sync
Copy-Item $envSource (Join-Path $appDir ".env") -Force
Write-Host "[deploy] .env copied"

Set-Location $appDir

# Init DB (idempotent)
Invoke-Native { npm run setup }
Write-Host "[deploy] DB init complete"

# Use local pm2
$pm2 = Join-Path $appDir "node_modules\pm2\bin\pm2"

# Try restart first; if process doesn't exist yet, start it
# SilentlyContinue is required in PS 5.1 to suppress NativeCommandError from pm2 stderr
$ErrorActionPreference = "SilentlyContinue"
node $pm2 restart helper --update-env 2>&1 | Out-Null
$restartOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"

if ($restartOk) {
  Write-Host "[deploy] Server restarted"
} else {
  Invoke-Native { node $pm2 start src/index.js --name helper }
  Write-Host "[deploy] Server started"
}

Invoke-Native { node $pm2 save }
Write-Host "[deploy] Deploy complete"
