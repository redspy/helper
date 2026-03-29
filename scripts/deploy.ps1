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

# Sync source files only (preserve node_modules to avoid OOM reinstall)
Write-Host "[deploy] Syncing source files..."
robocopy $env:GITHUB_WORKSPACE $appDir /E /XD node_modules .git data /XF "*.db" "*.db-shm" "*.db-wal" /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) {
  throw "[deploy] robocopy failed (exit code $LASTEXITCODE)"
}
Write-Host "[deploy] Source sync complete"

# Copy .env
Copy-Item $envSource (Join-Path $appDir ".env") -Force
Write-Host "[deploy] .env copied"

Set-Location $appDir

# Install dependencies only if node_modules is missing
# Run manually on first deploy: cd $appDir && npm install
$nodeModules = Join-Path $appDir "node_modules"
if (-not (Test-Path $nodeModules)) {
  Write-Host "[deploy] ERROR: node_modules not found."
  Write-Host "[deploy] Run this once on the server to install dependencies:"
  Write-Host ""
  Write-Host "    cd `"$appDir`""
  Write-Host "    npm install"
  Write-Host ""
  exit 1
}
Write-Host "[deploy] node_modules found - skipping install"

# Init DB (idempotent)
Invoke-Native { npm run setup }
Write-Host "[deploy] DB init complete"

# Restart server with PM2 (start if not running)
pm2 describe helper 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  Invoke-Native { pm2 restart helper --update-env }
  Write-Host "[deploy] Server restarted"
} else {
  Invoke-Native { pm2 start src/index.js --name helper }
  Write-Host "[deploy] Server started"
}

Invoke-Native { pm2 save }
Write-Host "[deploy] Deploy complete"
