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

# Use local pm2
$pm2 = Join-Path $appDir "node_modules\pm2\bin\pm2"

# Step 1: Stop server before updating files
Write-Host "[deploy] Stopping server..."
$ErrorActionPreference = "SilentlyContinue"
node $pm2 stop helper 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
Write-Host "[deploy] Server stopped (or was not running)"

# Step 2: Sync source files
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

# Step 3: Install dependencies if package.json changed
$pkgJson    = Join-Path $appDir "package.json"
$hashFile   = Join-Path $appDir ".pkg-hash"
$currentHash = (Get-FileHash $pkgJson -Algorithm MD5).Hash

$needsInstall = $true
if (Test-Path $hashFile) {
  $savedHash = Get-Content $hashFile -Raw
  if ($savedHash.Trim() -eq $currentHash) {
    $needsInstall = $false
  }
}

if ($needsInstall) {
  Write-Host "[deploy] package.json changed - running npm install..."
  Invoke-Native { npm install --prefer-offline }
  $currentHash | Out-File $hashFile -NoNewline
  Write-Host "[deploy] npm install complete"
} else {
  Write-Host "[deploy] package.json unchanged - skipping npm install"
}

# Step 4: Init DB (idempotent)
Invoke-Native { npm run setup }
Write-Host "[deploy] DB init complete"

# Step 5: Start server
$entryPoint = Join-Path $appDir "src\index.js"

$ErrorActionPreference = "SilentlyContinue"
node $pm2 delete helper 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

node $pm2 start $entryPoint --name helper --cwd $appDir
if ($LASTEXITCODE -ne 0) { throw "pm2 start failed" }
Write-Host "[deploy] Server started"

Invoke-Native { node $pm2 save }
Write-Host "[deploy] Deploy complete"
