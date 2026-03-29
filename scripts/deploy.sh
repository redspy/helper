#!/bin/bash
set -e

# GITHUB_WORKSPACE = {runner_root}/_work/{repo}/{repo}
# .env는 runner_root (run.cmd 와 같은 위치) 에 있음
RUNNER_ROOT="$(cd "$GITHUB_WORKSPACE/../../.." && pwd)"
ENV_SOURCE="$RUNNER_ROOT/.env"

echo "[deploy] Runner root: $RUNNER_ROOT"

# run.cmd 존재 여부로 경로 검증
if [ ! -f "$RUNNER_ROOT/run.cmd" ]; then
  echo "[deploy] ERROR: run.cmd를 찾을 수 없습니다 — 경로 확인 필요: $RUNNER_ROOT"
  exit 1
fi

# .env 복사
if [ ! -f "$ENV_SOURCE" ]; then
  echo "[deploy] ERROR: .env 파일을 찾을 수 없습니다: $ENV_SOURCE"
  exit 1
fi
cp "$ENV_SOURCE" "$GITHUB_WORKSPACE/.env"
echo "[deploy] .env 복사 완료"

cd "$GITHUB_WORKSPACE"

# 의존성 설치
npm ci
echo "[deploy] 의존성 설치 완료"

# DB 초기화 (멱등 — 이미 존재하면 스킵)
npm run setup
echo "[deploy] DB 초기화 완료"

# PM2로 서버 재시작 (없으면 신규 시작)
if pm2 describe helper > /dev/null 2>&1; then
  pm2 restart helper --update-env
  echo "[deploy] 서버 재시작 완료"
else
  pm2 start src/index.js --name helper
  echo "[deploy] 서버 시작 완료"
fi

pm2 save
echo "[deploy] 배포 완료"
