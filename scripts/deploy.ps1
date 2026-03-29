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

# Install dependencies when package.json changed or node_modules missing
$nodeModules  = Join-Path $appDir "node_modules"
$pkgJson      = Join-Path $appDir "package.json"
$hashFile     = Join-Path $appDir ".pkg-hash"
$currentHash  = (Get-FileHash $pkgJson -Algorithm MD5).Hash
$previousHash = if (Test-Path $hashFile) { Get-Content $hashFile -Raw } else { "" }

if (-not (Test-Path $nodeModules) -or $currentHash.Trim() -ne $previousHash.Trim()) {
  Write-Host "[deploy] Installing dependencies..."
  $env:NODE_OPTIONS = "--max-old-space-size=4096"
  Invoke-Native { npm install --prefer-offline }
  Set-Content $hashFile $currentHash
  Write-Host "[deploy] Dependencies installed"
} else {
  Write-Host "[deploy] node_modules up to date - skipping install"
}

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
