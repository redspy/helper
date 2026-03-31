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
robocopy $env:GITHUB_WORKSPACE $appDir /E /XD .git data /XF "*.db" "*.db-shm" "*.db-wal" /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) {
  throw "[deploy] robocopy failed (exit code $LASTEXITCODE)"
}
Write-Host "[deploy] Source sync complete"

Set-Location $appDir

# Init DB (idempotent)
Invoke-Native { npm run setup }
Write-Host "[deploy] DB init complete"

# Always overwrite .env with the one from runner root
Copy-Item $envSource (Join-Path $appDir ".env") -Force
Write-Host "[deploy] .env copied"

# Use local pm2 to avoid broken global installation
$pm2 = Join-Path $appDir "node_modules\pm2\bin\pm2"

# Restart server with PM2 (start if not running)
# Temporarily allow non-zero exit for describe (returns 1 when process doesn't exist)
$ErrorActionPreference = "Continue"
node $pm2 describe helper 2>&1 | Out-Null
$processExists = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"

if ($processExists) {
  node $pm2 restart helper --update-env
  if ($LASTEXITCODE -ne 0) { throw "pm2 restart failed" }
  Write-Host "[deploy] Server restarted"
} else {
  node $pm2 start src/index.js --name helper
  if ($LASTEXITCODE -ne 0) { throw "pm2 start failed" }
  Write-Host "[deploy] Server started"
}

node $pm2 save
if ($LASTEXITCODE -ne 0) { throw "pm2 save failed" }
Write-Host "[deploy] Deploy complete"
