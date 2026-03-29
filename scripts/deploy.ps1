# UTF-8 출력 설정
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$ErrorActionPreference = "Stop"

# 네이티브 커맨드(npm, pm2 등) 실패 시 즉시 중단
function Invoke-Native {
  param([scriptblock]$Command)
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "명령 실패 (exit code $LASTEXITCODE): $Command"
  }
}

# GITHUB_WORKSPACE = {runner_root}\_work\{repo}\{repo}
$runnerRoot = (Resolve-Path "$env:GITHUB_WORKSPACE\..\..\..\").Path
$appDir     = Join-Path $runnerRoot "app"
$envSource  = Join-Path $runnerRoot ".env"

Write-Host "[deploy] Runner root : $runnerRoot"
Write-Host "[deploy] App dir     : $appDir"

# run.cmd 존재 여부로 경로 검증
if (-not (Test-Path (Join-Path $runnerRoot "run.cmd"))) {
  throw "[deploy] ERROR: run.cmd 를 찾을 수 없습니다 — 경로 확인 필요: $runnerRoot"
}

# .env 존재 확인
if (-not (Test-Path $envSource)) {
  throw "[deploy] ERROR: .env 파일을 찾을 수 없습니다: $envSource"
}

# app 디렉토리 생성 (최초 1회)
if (-not (Test-Path $appDir)) {
  New-Item -ItemType Directory -Path $appDir | Out-Null
  Write-Host "[deploy] app 디렉토리 생성"
}

# 소스 파일만 동기화 (node_modules, .git, data 제외 — 재컴파일 방지)
Write-Host "[deploy] 소스 동기화 중..."
robocopy $env:GITHUB_WORKSPACE $appDir /E /XD node_modules .git data /XF "*.db" "*.db-shm" "*.db-wal" /NFL /NDL /NJH /NJS | Out-Null
# robocopy는 성공 시 0~7 사이 코드 반환 (8 이상이 실제 오류)
if ($LASTEXITCODE -ge 8) {
  throw "[deploy] robocopy 실패 (exit code $LASTEXITCODE)"
}
Write-Host "[deploy] 소스 동기화 완료"

# .env 복사
Copy-Item $envSource (Join-Path $appDir ".env") -Force
Write-Host "[deploy] .env 복사 완료"

Set-Location $appDir

# 의존성 설치 (node_modules 유지 — OOM 방지)
$env:NODE_OPTIONS = "--max-old-space-size=4096"
Write-Host "[deploy] 의존성 설치 중..."
Invoke-Native { npm install --prefer-offline }
Write-Host "[deploy] 의존성 설치 완료"

# DB 초기화 (멱등)
Invoke-Native { npm run setup }
Write-Host "[deploy] DB 초기화 완료"

# PM2 로 서버 재시작 (없으면 신규 시작)
pm2 describe helper 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  Invoke-Native { pm2 restart helper --update-env }
  Write-Host "[deploy] 서버 재시작 완료"
} else {
  Invoke-Native { pm2 start src/index.js --name helper }
  Write-Host "[deploy] 서버 시작 완료"
}

Invoke-Native { pm2 save }
Write-Host "[deploy] 배포 완료"
