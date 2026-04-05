# 구현 가이드: Telegram + Gemini 할 일 자동화 서버

## 기술 스택 결정

| 영역 | 선택 | 이유 |
|------|------|------|
| 런타임 | Node.js (v20+) | 스케줄러, I/O 비동기 처리에 최적 |
| 웹 프레임워크 | Express 4 | 단순 구조에 과도한 추상 불필요 |
| DB | sql.js | 인메모리 SQLite DB를 파일 백업으로 사용 |
| 스케줄러 | node-cron | cron 표현식 기반 1분 폴링 |
| 템플릿 | EJS | 서버사이드 렌더링, 빌드 불필요 |
| Gemini | @google/genai | 최신 Google GenAI SDK |
| Telegram | node-telegram-bot-api | Bot API 래퍼 |
| 환경변수 | dotenv | .env 로드 |
| 인증 | express-session | 웹 페이지 보호를 위한 세션 |
| 로깅 | 직접 구현 (console + DB) | 외부 의존 최소화 |

---

## 프로젝트 폴더 구조

```
helper/
├── src/
│   ├── index.js              # 서버 진입점 (Express 앱 + 스케줄러 시작)
│   ├── db.js                 # DB 연결 및 마이그레이션 실행
│   ├── scheduler.js          # node-cron 기반 1분 폴링 로직
│   ├── gemini.js             # Gemini API 호출 모듈
│   ├── telegram.js           # Telegram Bot API 전송 모듈
│   ├── recurrence.js         # 반복 규칙 → 다음 실행시간 계산
│   ├── routes/
│   │   ├── auth.js           # 로그인/로그아웃 라우터
│   │   ├── tasks.js          # /tasks 라우터
│   │   └── health.js         # /health 라우터
│   └── views/
│       ├── index.ejs         # 메인 화면 (등록 폼 + 활성 목록 + 지난 할 일)
│       ├── login.ejs         # 로그인 화면
│       └── partials/
│           ├── task-row.ejs  # 활성 할 일 행
│           └── archive-row.ejs # 지난 할 일 행
├── migrations/
│   └── 001_init.sql          # tasks, task_runs 테이블 DDL
├── scripts/
│   └── setup.js              # npm run setup 진입점
├── data/                     # .gitignore 대상 (SQLite 파일 생성 위치)
│   └── .gitkeep
├── .env.example
├── .gitignore
├── package.json
└── README.md
```

---

## 의존성 (`package.json`)

```json
{
  "name": "helper",
  "version": "1.0.0",
  "engines": { "node": ">=20" },
  "scripts": {
    "setup": "node scripts/setup.js",
    "start": "node src/index.js",
    "dev": "node --watch src/index.js"
  },
  "dependencies": {
    "@google/genai": "^1.48.0",
    "cron-parser": "^4.9.0",
    "dotenv": "^16.4.5",
    "ejs": "^3.1.10",
    "express": "^4.19.2",
    "express-session": "^1.19.0",
    "node-cron": "^3.0.3",
    "node-telegram-bot-api": "^0.66.0",
    "pm2": "^6.0.14",
    "sql.js": "^1.12.0"
  }
}
```

---

## 환경변수 (`.env.example`)

```dotenv
# Gemini
GEMINI_API_KEY=

# Telegram
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# 서버
PORT=6240
TZ=Asia/Seoul
SESSION_SECRET=
APP_PASSWORD=
```

`SESSION_SECRET`, `APP_PASSWORD`를 비워두면 서버 기본값(`helper-secret-key`, `13579`)이 사용됩니다.

`.gitignore` 필수 항목:
```
.env
.env.*
data/*.db
data/*.sqlite
```

---

## DB 스키마 (`migrations/001_init.sql`)

```sql
CREATE TABLE IF NOT EXISTS tasks (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  title           TEXT    NOT NULL,
  content         TEXT    NOT NULL,
  scheduled_at    TEXT    NOT NULL,          -- ISO8601, Asia/Seoul 기준
  recurrence_type TEXT    NOT NULL DEFAULT 'once',  -- once|daily|weekly|monthly|custom
  recurrence_rule TEXT,                      -- custom일 때 cron 표현식 저장
  status          TEXT    NOT NULL DEFAULT 'pending', -- pending|running|sent|failed|archived
  retry_count     INTEGER NOT NULL DEFAULT 0,
  last_run_at     TEXT,
  archived_at     TEXT,
  created_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
  updated_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS task_runs (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id             INTEGER NOT NULL REFERENCES tasks(id),
  trace_id            TEXT    NOT NULL,       -- UUID, 로그 추적용
  started_at          TEXT    NOT NULL,
  finished_at         TEXT,
  status              TEXT    NOT NULL,       -- running|success|failed
  gemini_result       TEXT,
  telegram_message_id TEXT,
  error_message       TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_status_scheduled
  ON tasks(status, scheduled_at);

CREATE TABLE IF NOT EXISTS schema_migrations (
  name TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);
```

---

## 모듈별 구현 명세

### `src/db.js`

```
- sql.js를 사용하여 in-memory 데이터베이스 초기화 및 data/helper.db 파일로 동기화(백업)
- 앱 시작 시 migrations/*.sql 자동 실행
- schema_migrations 테이블로 적용 이력 관리 (이미 적용된 파일은 스킵)
- legacy DB에서 중복 컬럼 오류가 발생하면 해당 마이그레이션은 적용 완료로 간주하고 이력 기록
- db 인스턴스를 싱글턴으로 export, saveToFile()을 통해 파일 기록 유지
- Proxy 객체로 better-sqlite3와 유사한 API (run, prepare 등) 래핑 제공
- PRAGMA foreign_keys=ON; 적용
```

### `src/gemini.js`

```
export async function summarize(title, content): Promise<string>

- @google/genai 초기화 (GEMINI_API_KEY)
- 모델: gemini-2.5-flash
- tools 옵션으로 googleSearch 포함 (최신 정보 검색 기능 활성화)
- 프롬프트 템플릿:
    당신은 유능한 AI 어시스턴트입니다. 아래 할 일 또는 주제에 대해 분석하고, 필요하다면 Google 검색을 통해 최신 정보를 찾아서 도움이 되는 내용을 자유롭게 응답해 주세요.
    응답 시 마크다운 문법을 사용하지 말고, 일반 텍스트로만 작성해 주세요.

    [제목]
    {title}

    [내용]
    {content}

- 응답이 비어있거나 에러면 throw Error
- 타임아웃: 60초 제한 (Promise.race)
- 최대 3회 재시도 (실패 시 1초 간격)
```

### `src/telegram.js`

```
export async function sendMessage(title, scheduledAt, geminiResult, processedAt): Promise<string>  // message_id 반환

- TelegramBot 초기화 (TELEGRAM_BOT_TOKEN, {polling: false})
- TELEGRAM_CHAT_ID로 sendMessage
- 실패 시 최대 3회 재시도 (1초 간격)
- 3회 모두 실패 시 throw Error
- 메시지 포맷:
    📋 {title}
    🕐 예정: {scheduled_at}

    {gemini_result}

    ✅ 처리 시각: {processed_at}
- parse_mode: 'HTML' (Gemini 응답 특수문자 이스케이프 후 전송)
```

### `src/recurrence.js`

```
export function nextScheduledAt(task): string | null

- recurrence_type별 계산:
  - 'once'    → null (아카이브 처리)
  - 'daily'   → scheduled_at + 1일
  - 'weekly'  → scheduled_at + 7일
  - 'monthly' → scheduled_at + 1개월 (date-fns 없이 Date 직접 연산)
  - 'custom'  → recurrence_rule(cron 표현식)에서 다음 실행시간 계산
                 node-cron의 schedule 없이 직접 파싱하기 복잡하므로
                 'custom'은 cron-parser 패키지 추가 (^4.9.0)
- 반환값: ISO8601 문자열 (Asia/Seoul 기준)
```

> **의존성 추가**: `"cron-parser": "^4.9.0"` (custom 반복에만 사용)

### `src/scheduler.js`

```
export function startScheduler(db)

- node-cron.schedule('* * * * *', callback, {timezone: 'Asia/Seoul'})
- callback 내부:
  1. SELECT tasks WHERE status='pending' AND scheduled_at <= now()
  2. 각 task를 순차 처리 (Promise.allSettled 병렬 가능하나 DB 잠금 고려)
  3. 처리 시작 전 status='running'으로 UPDATE (중복 실행 방지)
  4. trace_id(UUID) 생성 후 task_runs INSERT
  5. gemini.summarize() 호출
  6. telegram.sendMessage() 호출
  7. 성공: task_runs UPDATE(status=success)
     - 1회성 task: tasks UPDATE(status=archived, archived_at=now(), retry_count=0)
     - 반복 task: nextScheduledAt() 계산 후 tasks UPDATE(status=pending, scheduled_at=next, retry_count=0)
  8. 실패: task_runs UPDATE(status=failed, error_message), tasks retry_count 증가
  9. retry_count < 5 이면 1분 뒤 재시도(pending + scheduled_at 갱신)
  10. retry_count >= 5 이면 tasks status='failed' 확정 후 retry_count 초기화

- crypto.randomUUID() 사용 (Node.js 내장, 추가 패키지 불필요)
```

### `src/routes/tasks.js`

```
GET  /                      → index.ejs 렌더링
                              - query: 활성 tasks (status IN ('pending','running','sent','failed'))
                              - archived: tasks WHERE status='archived' (접힘 섹션용)
                              (세션 미들웨어로 인증 필요)

POST /tasks                 → 할 일 등록
                              body: { title, content, scheduled_at, recurrence_type, recurrence_rule? }
                              유효성: 필수 필드 존재 여부만 확인
                              성공 후 redirect('/')

POST /tasks/:id/update      → 수정 (제목/내용/예정시간/반복주기)
                              body: 위와 동일
                              status가 'archived'면 수정 불가 (reschedule 사용)
                              성공 후 redirect('/')

POST /tasks/:id/delete      → 삭제 (task_runs 포함 CASCADE)
                              성공 후 redirect('/')

POST /tasks/:id/run         → 수동 실행
                              스케줄러의 단일 task 처리 로직 재사용
                              성공 후 redirect('/')

POST /tasks/:id/reschedule  → 지난 1회성 할 일 재활성화
                              body: { scheduled_at }  ← 새 예정시간
                              tasks UPDATE: status='pending', scheduled_at=new, archived_at=NULL
                              성공 후 redirect('/')

GET  /health                → { status: 'ok', time: now }

GET  /login                 → 로그인 화면 렌더링 (session.authenticated 인 경우 / 로 리다이렉트)
POST /login                 → APP_PASSWORD 확인 후 session에 인증 정보 부여
POST /logout                → 세션 소멸 및 로그인 화면 렌더링
```

---

## 웹 UI 구조 (`src/views/index.ejs`)

### 레이아웃
```
[헤더] 할 일 자동화

[등록 폼]
  - 제목 (text, required)
  - 내용 (textarea, required)
  - 예정 시간 (datetime-local, required)
  - 반복 주기 (select: 1회/매일/매주/매월/커스텀)
  - 커스텀 규칙 입력 (text, 커스텀 선택 시에만 표시)
  - [등록] 버튼

[활성 할 일 목록]
  각 행: 제목 | 예정시간 | 반복 | 상태 | 마지막 실행 | [수정][삭제][실행]

[지난 할 일] ← <details> 태그로 기본 접힘
  각 행: 제목 | 완료시간 | [다시 수행] → 모달(새 예정시간 입력) or 인라인 폼
```

### 상태별 색상
- `pending` → 회색
- `running` → 파란색
- `sent` → 초록색
- `failed` → 빨간색
- `archived` → 흐리게

### JS (인라인, 최소화)
```javascript
// 커스텀 반복 입력 표시/숨김
document.querySelector('[name=recurrence_type]')
  .addEventListener('change', e => {
    document.getElementById('custom-rule').hidden = e.target.value !== 'custom'
  })

// 다시 수행 버튼 → scheduled_at 입력 폼 인라인 토글
```

---

## Setup 스크립트 (`scripts/setup.js`)

```javascript
// 실행 순서:
// 1. data/ 디렉토리 생성 (없으면)
// 2. .env 파일 생성 (.env.example 복사, 이미 있으면 유지)
// 3. sql.js DB 초기화 및 migrations/*.sql 적용
// 4. 완료 메시지 출력 (.env 편집 안내 포함)

const fs = require('fs')
const path = require('path')

const envPath = path.join(__dirname, '..', '.env')
const examplePath = path.join(__dirname, '..', '.env.example')
const dataDir = path.join(__dirname, '..', 'data')

if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true })
if (!fs.existsSync(envPath)) fs.copyFileSync(examplePath, envPath)

// DB 초기화는 db.js import로 자동 처리
require('../src/db.js')

console.log('[setup] 완료. .env 파일에 API 키를 입력하세요.')
```

---

## 타임존 처리 주의사항

```
- process.env.TZ = 'Asia/Seoul' 은 index.js 최상단 첫 줄에 설정
  (dotenv.config() 이전에 위치해야 함)
- DB 저장: datetime('now','localtime') 사용 (SQLite)
- 비교: scheduled_at <= datetime('now','localtime')
- Node.js Date 연산 시: new Date().toLocaleString('sv-SE', {timeZone: 'Asia/Seoul'})
  → 'YYYY-MM-DD HH:MM:SS' 형식, ISO8601 변환 용이
```

---

## 구현 순서 (Phase별 작업 목록)

### Phase 1 — 골격 (우선 완료)
1. `package.json` 작성 후 `npm install`
2. `.env.example`, `.gitignore` 작성
3. `migrations/001_init.sql` 작성
4. `scripts/setup.js` 작성 및 `npm run setup` 동작 확인
5. `src/db.js` 작성 (마이그레이션 자동 실행 확인)
6. `src/index.js` 작성 (Express 앱 + 포트 리스닝)

### Phase 2 — 웹 CRUD
7. `src/routes/tasks.js` — GET / (목록 조회)
8. `src/views/index.ejs` — 기본 레이아웃 + 목록 렌더링
9. `src/routes/tasks.js` — POST /tasks (등록)
10. POST /tasks/:id/update, delete 구현
11. `<details>` 기반 지난 할 일 섹션 + reschedule 구현
12. 수동 실행 버튼 (scheduler 로직 추출 후 재사용)

### Phase 3 — 스케줄러
13. `src/recurrence.js` 작성
14. `src/scheduler.js` 작성 (gemini/telegram 없이 로그만 출력하는 stub으로 먼저 테스트)
15. 중복 실행 방지 (running 상태 전환) 검증

### Phase 4 — 외부 API 연동
16. `src/gemini.js` 작성 + GEMINI_API_KEY로 단독 테스트
17. `src/telegram.js` 작성 + TELEGRAM_BOT_TOKEN/CHAT_ID로 단독 테스트
18. scheduler.js에 실제 호출 연결

### Phase 5 — 안정화
19. 서버 재시작 시 `running` 상태 → `pending` 복구 (index.js 시작 시 1회 실행)
20. task_runs 이력을 웹에서 확인 (각 task 행에 마지막 실행 결과 표시)
21. 실패 task 수동 재시도 경로 확인

### Phase 6 — 문서화
22. `README.md` 작성 (plan.md §7.4 요구사항 기준)

---

## 서버 재시작 복구 처리 (`src/index.js`)

```javascript
// 서버 시작 시 running 상태 잔존 항목 복구
db.prepare(`
  UPDATE tasks SET status = 'pending'
  WHERE status = 'running'
`).run()
```

---

## Telegram 메시지 포맷 (실제 예시)

```
📋 *주간 우선순위 정리*
🕐 예정: 2026-03-30 09:00

## 핵심 요약
이번 주 주요 목표와 긴급 항목을 정리하는 작업입니다.

## 우선순위
상 — 월요일 오전에 처리해야 주간 흐름이 확보됩니다.

## 지금 바로 할 첫 행동
1. 지난 주 미완료 항목 목록 열기
2. 이번 주 마감 기준으로 3개 추리기
3. 캘린더에 집중 블록 30분 예약

✅ 처리 시각: 2026-03-30 09:00:12
```

---

## 완료 체크리스트

- [ ] `npm run setup` → data/helper.db 생성 + .env 자동 생성
- [ ] `npm start` → localhost:6240 접속 가능
- [ ] 등록 폼 제출 → DB 저장 + 목록 반영
- [ ] 반복 주기별 다음 실행시간 계산 정확성 확인
- [ ] 스케줄러 1분 폴링 동작 확인 (로그)
- [ ] Gemini 응답 수신 확인
- [ ] Telegram 메시지 수신 확인
- [ ] 1회성 완료 후 지난 할 일 섹션 이동 확인
- [ ] 지난 할 일 reschedule 후 활성 목록 복귀 확인
- [ ] .env가 git status에 나타나지 않음 확인
- [ ] 신규 서버에서 clone → setup → 키 입력 → start 흐름 검증
