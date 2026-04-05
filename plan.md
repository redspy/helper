# Telegram + Gemini + SQLite 할 일 자동화 기획서

## 1. 목적
웹페이지에서 시간과 할 일을 등록/관리하고,
지정된 시간이 되면 Gemini로 내용을 정리한 뒤 텔레그램으로 결과를 자동 전송하는 서버를 설계한다.

## 2. 핵심 요구사항 (필수)
- [ ] 웹페이지에서 할 일 제목/내용/실행 시간을 등록할 수 있어야 한다.
- [ ] 등록된 할 일 목록을 웹페이지에서 조회/수정/삭제할 수 있어야 한다.
- [ ] 모든 할 일 데이터는 SQLite로 저장/관리되어야 한다.
- [ ] 진행 중 로그인 인증 기능(세션)을 도입하여 허가된 사용자만 접근할 수 있어야 한다.
- [ ] 실행 시간이 되면 서버가 해당 할 일을 자동 처리해야 한다.
- [ ] 자동 처리 시 Gemini API(@google/genai)를 사용해 할 일을 요약/분석해야 한다.
- [ ] 추가적으로 Google Search 도구를 사용하여 최신 정보에 접근할 수 있게 한다.
- [ ] 정리 결과를 텔레그램으로 전송해야 한다.
- [ ] 각 할 일은 반복 주기(예: 1회, 매일, 매주, 매월, 커스텀)를 설정할 수 있어야 한다.
- [ ] 1회성 할 일이 완료/만료되면 메인 목록 하단의 `지난 할 일` 영역으로 분리되어야 한다.
- [ ] `지난 할 일`은 기본 접힘 상태이며 펼치면 과거 이력을 확인할 수 있어야 한다.
- [ ] 지난 1회성 할 일은 UI에서 시간 재설정 후 다시 활성 할 일로 복구할 수 있어야 한다.
- [ ] Gemini/Telegram API 키 및 민감정보는 Git에 올라가지 않도록 gitignore 대상 파일로 관리해야 한다.
- [ ] 다른 서버에서도 패키지 매니저 명령으로 의존성 설치와 서버 초기 구성이 즉시 완료되어야 한다.
- [ ] 서버 초기 구성 시 `.env` 파일이 자동 생성되어야 하며, 기본값은 비어있는 상태로 제공되어야 한다.
- [ ] 구현 완료 후 `README.md`에 Gemini/Telegram 키 발급 절차와 `.env` 저장 방법을 초보자도 따라할 수 있게 상세 문서화해야 한다.

## 3. 사용자 시나리오
1. 사용자가 웹페이지에서 `내일 09:00`, `할 일: 주간 우선순위 정리`를 등록한다.
2. 데이터가 SQLite DB에 저장된다.
3. 서버 스케줄러가 주기적으로 실행 대상을 확인한다.
4. 시간이 되면 Gemini에 프롬프트를 보내 할 일을 구조화된 결과로 정리한다.
5. 정리 결과를 텔레그램 채팅방으로 전송한다.
6. 성공/실패 이력을 DB에 기록하고 웹에서 확인 가능하게 한다.

## 4. 기능 요구사항 상세
### 4.1 웹 기능
- 할 일 등록 폼
  - 필수 입력: 제목, 원문 내용, 실행 시간
  - 반복 주기 선택: `1회`, `매일`, `매주`, `매월`, `커스텀`
- 할 일 목록 화면
  - 상태 표시: `pending`, `sent`, `failed`, `archived`
  - 최근 실행 결과/오류 확인
- 수정/삭제 기능
- 수동 실행 버튼(옵션, 운영 편의)
- 메인 화면 하단에 `지난 할 일` 섹션 제공
  - 기본은 접힘(Collapsed) 상태
  - 펼치면 완료/만료된 1회성 할 일 목록 표시
  - 각 항목에 `다시 수행`(재설정) 버튼 제공

### 4.2 스케줄 실행 기능
- 스케줄러는 최소 1분 단위로 실행 대상을 확인한다.
- `pending` 상태이며 실행 시간이 현재 시각 이하인 항목을 처리한다.
- 중복 실행 방지 장치(실행 잠금 또는 상태 전환)를 둔다.
- 반복 할 일은 실행 후 반복 규칙에 따라 다음 실행 시간을 자동 갱신한다.
- 1회성 할 일은 실행 완료 후 `archived`로 이동한다.

### 4.3 Gemini 처리 기능
- Google 검색이 적용된 모델(`gemini-2.5-flash`)을 사용하여 할 일 원문에 대해 분석, 최신 정보 검색 수행
- 마크다운 문법 없이 텍스트로 자유롭게 도움이 되는 내용 응답
- 응답 텍스트 유효성 검사 (빈 응답/타임아웃 시 재시도)

### 4.4 로그인 및 인증
- 웹페이지 접근 시 세션 기반 (`express-session`) 로그인 검증
- 환경 변수 `APP_PASSWORD` 로 단일 비밀번호 인증 수행

### 4.4 Telegram 전송 기능
- Bot API를 통해 지정 채팅방으로 메시지 전송
- 메시지 기본 포맷:
  - 할 일 제목
  - 예정 시간
  - Gemini 정리 결과
  - 처리 시각
- 전송 모듈 재시도: 최대 3회
- 작업 단위 재시도: 1분 간격 최대 5회 후 `failed` 확정

## 5. 데이터 저장 설계 (SQLite)
### 5.1 tasks 테이블
- id (INTEGER PK)
- title (TEXT, NOT NULL)
- content (TEXT, NOT NULL)
- scheduled_at (TEXT/ISO8601, NOT NULL)
- recurrence_type (TEXT, NOT NULL: `once` | `daily` | `weekly` | `monthly` | `custom`)
- recurrence_rule (TEXT, NULL: 커스텀 반복 규칙 저장)
- status (TEXT, NOT NULL, default: `pending`)
- last_run_at (TEXT, NULL)
- archived_at (TEXT, NULL)
- created_at (TEXT, NOT NULL)
- updated_at (TEXT, NOT NULL)

### 5.2 task_runs 테이블
- id (INTEGER PK)
- task_id (INTEGER, FK)
- started_at (TEXT)
- finished_at (TEXT)
- status (TEXT: `success` | `failed`)
- gemini_result (TEXT)
- telegram_message_id (TEXT)
- error_message (TEXT)

## 6. API/서버 엔드포인트 초안
- `GET /login`, `POST /login` : 로그인
- `POST /logout` : 로그아웃
- `GET /` : 웹페이지(등록 + 목록)
- `POST /tasks` : 할 일 등록
- `POST /tasks/:id/update` : 할 일 수정
- `POST /tasks/:id/delete` : 할 일 삭제
- `POST /tasks/:id/run` : 수동 실행(옵션)
- `POST /tasks/:id/reschedule` : 지난 1회성 할 일 재설정 후 활성화
- `GET /tasks?view=archived` : 지난 할 일 목록 조회(펼침 UI 연동)
- `GET /health` : 헬스체크

## 7. 민감정보 관리 정책 (중요)
### 7.1 관리 파일
- `.env` 파일에 아래 정보 저장
  - `GEMINI_API_KEY`
  - `TELEGRAM_BOT_TOKEN`
  - `TELEGRAM_CHAT_ID`
  - `APP_PASSWORD` (웹 로그인 암호)
  - `SESSION_SECRET` (세션 암호화 키)
  - 기타 서버 설정값

### 7.2 Git 정책
- `.gitignore`에 반드시 포함:
  - `.env`
  - `.env.*`
  - `*.db`
  - `*.sqlite`
- 저장소에는 `.env.example`만 커밋하여 키 이름만 공유

### 7.3 초기 환경 자동 구성
- `package manager` 스크립트(`npm run setup` 등) 1회 실행으로 아래를 자동 처리
  - SQLite 파일/폴더 초기화
  - `.env` 파일 자동 생성(없을 때만, 키는 존재하되 값은 빈 상태)
- 신규 서버에서는 `git clone -> npm install -> setup 스크립트 실행 -> 환경값 입력 -> 서버 시작` 순서로 동작해야 한다.

### 7.4 운영 문서(README) 요구사항
- `README.md`에는 아래 내용을 순서대로 포함
  - 프로젝트 설치/실행 방법(신규 서버 기준)
  - Gemini API 키 발급 절차(어디서 생성하고 어떤 키를 복사하는지)
  - Telegram Bot 생성 및 Bot Token/Chat ID 확보 절차
  - `.env` 파일 생성 위치(프로젝트 루트)와 변수별 입력 예시
  - `.env` / `.env.example`의 역할 차이와 보안 주의사항
- 문서는 실제 화면 흐름 기준으로 작성하고, 복붙 가능한 명령 예시를 포함한다.

## 8. 실패/예외 처리 요구사항
- Gemini API 실패
  - 타임아웃, 재시도, 실패 로그 저장
- Telegram 전송 실패
  - 재시도 후 최종 실패 처리
- DB 오류
  - 에러 로그 + 상태 유지
- 서버 재시작 시
  - 미처리 `pending` 작업 재확인

## 9. 비기능 요구사항
- 시간대 명시(`Asia/Seoul`)로 오동작 방지
- 로깅: 실행 단위별 추적 ID로 디버깅 가능
- 유지보수성: Gemini/Telegram 모듈 분리
- 확장성: 추후 PostgreSQL/큐 시스템으로 이관 가능한 구조

## 10. 단계별 구현 계획
### Phase 1. 설계 확정
- [ ] 요구사항/화면/DB 스키마 확정
- [ ] 메시지 포맷 확정
- [ ] 서버 초기 구축 플로우(패키지 매니저 + `.env` 자동 생성) 확정

### Phase 2. 기본 서버 + 웹 UI
- [ ] 서버 부트스트랩 및 인증(`express-session`) 구성
- [ ] 로그인 화면 및 미들웨어 구현
- [ ] 할 일 등록/조회/수정/삭제 구현
- [ ] 반복 주기 입력 UI 및 지난 할 일 접힘/펼침 UI 구현
- [ ] 지난 할 일 `다시 수행` 재설정 UX 구현
- [ ] `setup` 스크립트 구현(`.env` 자동 생성 포함)

### Phase 3. 스케줄러 + 자동 실행
- [ ] 시간 도달 감지
- [ ] 중복 실행 방지
- [ ] 반복 규칙별 다음 실행시간 계산
- [ ] 1회성 실행 완료 항목 아카이브 처리

### Phase 4. Gemini + Telegram 연동
- [ ] Gemini 정리 결과 생성
- [ ] 텔레그램 전송 및 실패 처리

### Phase 5. 운영 안정화
- [ ] 실행 이력/로그 개선
- [ ] 재시도 정책/알림 튜닝

### Phase 6. 문서화(README)
- [ ] `README.md` 작성: 설치/실행/트러블슈팅
- [ ] Gemini API 키 발급 및 저장 방법 상세 작성
- [ ] Telegram Bot Token + Chat ID 발급 및 저장 방법 상세 작성
- [ ] `.env` 작성 예시 및 보안 주의사항 작성

## 11. 완료 기준 (Definition of Done)
- [ ] 웹페이지에서 시간/할 일을 등록하고 DB에 저장된다.
- [ ] 웹페이지에서 각 할 일의 반복 주기를 설정할 수 있다.
- [ ] SQLite 기준으로 실행 대상이 정확히 선택된다.
- [ ] 실행 시간이 되면 Gemini 정리 결과가 생성된다.
- [ ] 결과가 텔레그램으로 자동 전송된다.
- [ ] 1회성 지난 할 일은 목록 하단 접힘 섹션에서 조회 가능하다.
- [ ] 지난 할 일을 재설정하여 다시 실행 대기 상태로 되돌릴 수 있다.
- [ ] API 키 파일(.env)은 Git에 포함되지 않는다.
- [ ] 신규 서버에서 패키지 매니저 기반 초기 구축이 즉시 가능하고, `.env`가 자동 생성된다.
- [ ] `README.md`만 보고도 Gemini/Telegram 키 발급부터 `.env` 저장까지 완료할 수 있다.
