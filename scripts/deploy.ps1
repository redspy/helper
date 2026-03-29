$ErrorActionPreference = "Stop"

# GITHUB_WORKSPACE = {runner_root}\_work\{repo}\{repo}
# .env 는 runner_root (run.cmd 와 같은 위치) 에 있음
$runnerRoot = (Resolve-Path "$env:GITHUB_WORKSPACE\..\..\..\").Path
$envSource  = Join-Path $runnerRoot ".env"

Write-Host "[deploy] Runner root: $runnerRoot"

# run.cmd 존재 여부로 경로 검증
if (-not (Test-Path (Join-Path $runnerRoot "run.cmd"))) {
  Write-Error "[deploy] ERROR: run.cmd 를 찾을 수 없습니다 — 경로 확인 필요: $runnerRoot"
  exit 1
}

# .env 복사
if (-not (Test-Path $envSource)) {
  Write-Error "[deploy] ERROR: .env 파일을 찾을 수 없습니다: $envSource"
  exit 1
}
Copy-Item $envSource (Join-Path $env:GITHUB_WORKSPACE ".env") -Force
Write-Host "[deploy] .env 복사 완료"

Set-Location $env:GITHUB_WORKSPACE

# 의존성 설치
npm ci
Write-Host "[deploy] 의존성 설치 완료"

# DB 초기화 (멱등)
npm run setup
Write-Host "[deploy] DB 초기화 완료"

# PM2 로 서버 재시작 (없으면 신규 시작)
$pm2List = pm2 describe helper 2>&1
if ($LASTEXITCODE -eq 0) {
  pm2 restart helper --update-env
  Write-Host "[deploy] 서버 재시작 완료"
} else {
  pm2 start src/index.js --name helper
  Write-Host "[deploy] 서버 시작 완료"
}

pm2 save
Write-Host "[deploy] 배포 완료"
