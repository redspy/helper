# Telegram + Gemini + SQLite 할 일 자동화 서버 계획서

## 1. 목적
웹페이지에서 시간과 할 일을 등록/관리하고,
지정된 시간이 되면 Gemini로 내용을 정리한 뒤 텔레그램으로 결과를 자동 전송하는 서버를 설계한다.

## 2. 핵심 요구사항 (필수)
- [ ] 웹페이지에서 할 일 제목/내용/실행 시간을 등록할 수 있어야 한다.
- [ ] 등록된 할 일 목록을 웹페이지에서 조회/수정/삭제할 수 있어야 한다.
- [ ] 모든 할 일 데이터는 SQLite로 저장/관리되어야 한다.
- [ ] 실행 시간이 되면 서버가 해당 할 일을 자동 처리해야 한다.
- [ ] 자동 처리 시 Gemini API를 사용해 할 일을 정리(요약/실행안 제시)해야 한다.
- [ ] 정리 결과를 텔레그램으로 전송해야 한다.
- [ ] Gemini/Telegram API 키 및 민감정보는 Git에 올라가지 않도록 gitignore 대상 파일로 관리해야 한다.

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
- 할 일 목록 화면
  - 상태 표시: `pending`, `sent`, `failed`
  - 최근 실행 결과/오류 확인
- 수정/삭제 기능
- 수동 실행 버튼(옵션, 운영 편의)

### 4.2 스케줄 실행 기능
- 스케줄러는 최소 1분 단위로 실행 대상을 확인한다.
- `pending` 상태이며 실행 시간이 현재 시각 이하인 항목을 처리한다.
- 중복 실행 방지 장치(실행 잠금 또는 상태 전환)를 둔다.

### 4.3 Gemini 처리 기능
- 할 일 원문을 바탕으로 다음 형식으로 정리 요청:
  - 핵심 요약
  - 우선순위
  - 지금 바로 할 첫 행동 1~3개
- 응답 텍스트 유효성 검사(빈 응답/에러 처리)

### 4.4 Telegram 전송 기능
- Bot API를 통해 지정 채팅방으로 메시지 전송
- 메시지 기본 포맷:
  - 할 일 제목
  - 예정 시간
  - Gemini 정리 결과
  - 처리 시각
- 전송 실패 시 재시도 정책(예: 3회)

## 5. 데이터 저장 설계 (SQLite)
### 5.1 tasks 테이블
- id (INTEGER PK)
- title (TEXT, NOT NULL)
- content (TEXT, NOT NULL)
- scheduled_at (TEXT/ISO8601, NOT NULL)
- status (TEXT, NOT NULL, default: `pending`)
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
- `GET /` : 웹페이지(등록 + 목록)
- `POST /tasks` : 할 일 등록
- `POST /tasks/:id/update` : 할 일 수정
- `POST /tasks/:id/delete` : 할 일 삭제
- `POST /tasks/:id/run` : 수동 실행(옵션)
- `GET /health` : 헬스체크

## 7. 민감정보 관리 정책 (중요)
### 7.1 관리 파일
- `.env` 파일에 아래 정보 저장
  - `GEMINI_API_KEY`
  - `TELEGRAM_BOT_TOKEN`
  - `TELEGRAM_CHAT_ID`
  - 기타 서버 설정값

### 7.2 Git 정책
- `.gitignore`에 반드시 포함:
  - `.env`
  - `.env.*`
  - `*.db`
  - `*.sqlite`
- 저장소에는 `.env.example`만 커밋하여 키 이름만 공유

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

### Phase 2. 기본 서버 + 웹 UI
- [ ] 서버 부트스트랩
- [ ] 할 일 등록/조회/수정/삭제 구현

### Phase 3. 스케줄러 + 자동 실행
- [ ] 시간 도달 감지
- [ ] 중복 실행 방지

### Phase 4. Gemini + Telegram 연동
- [ ] Gemini 정리 결과 생성
- [ ] 텔레그램 전송 및 실패 처리

### Phase 5. 운영 안정화
- [ ] 실행 이력/로그 개선
- [ ] 재시도 정책/알림 튜닝

## 11. 완료 기준 (Definition of Done)
- [ ] 웹페이지에서 시간/할 일을 등록하고 DB에 저장된다.
- [ ] SQLite 기준으로 실행 대상이 정확히 선택된다.
- [ ] 실행 시간이 되면 Gemini 정리 결과가 생성된다.
- [ ] 결과가 텔레그램으로 자동 전송된다.
- [ ] API 키 파일(.env)은 Git에 포함되지 않는다.
