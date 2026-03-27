# Telegram + Gemini 스케줄 서버 개발 계획

## 1) 프로젝트 개요
지정된 시간에 정해진 작업을 자동 실행하고, 결과물을 텔레그램으로 전송하는 서버를 구축한다.
핵심은 **신뢰성 있는 스케줄 실행**, **Gemini API를 통한 결과 생성/가공**, **텔레그램 알림 전달**이다.

## 2) 목표
- [ ] 관리자가 작업(Job)을 등록/수정/비활성화할 수 있다.
- [ ] 서버가 지정된 스케줄(예: 매일 09:00, 평일 18:30)에 작업을 자동 실행한다.
- [ ] 작업 실행 시 Gemini API로 콘텐츠를 생성/요약/분석할 수 있다.
- [ ] 실행 결과(성공/실패/요약)를 텔레그램으로 전송한다.
- [ ] 실패 시 재시도 및 오류 알림이 동작한다.
- [ ] 최소 운영 지표(성공률, 실패 로그, 마지막 실행 시각)를 확인할 수 있다.

## 3) 범위 정의
### In Scope
- 스케줄 기반 Job 실행 엔진
- Gemini API 연동(프롬프트 템플릿 + 응답 파싱)
- Telegram Bot API 연동(메시지 전송)
- Job 실행 이력 저장(DB)
- 기본 운영 기능(로그, 에러 알림, 헬스체크)

### Out of Scope (초기 버전)
- 복잡한 웹 대시보드
- 멀티테넌트/권한 체계
- 대규모 분산 큐 인프라

## 4) 사용자 시나리오
1. 관리자가 `매일 오전 9시 요약 리포트` Job을 등록한다.
2. 스케줄러가 09:00에 Job을 트리거한다.
3. 서버가 사전 정의된 프롬프트로 Gemini API를 호출한다.
4. 결과 텍스트를 포맷팅해 텔레그램 채팅방으로 보낸다.
5. 실행 결과를 DB에 저장하고, 실패 시 재시도 후 실패 알림을 보낸다.

## 5) 기술 스택(제안)
- Runtime: Node.js 20+
- Framework: Fastify 또는 Express
- Scheduler: `node-cron` (초기), 필요 시 `BullMQ` + Redis로 확장
- DB: PostgreSQL (Job/실행 이력 관리)
- ORM: Prisma
- External APIs:
  - Gemini API
  - Telegram Bot API
- Observability:
  - 구조화 로그(`pino`)
  - 선택: Sentry (오류 수집)

## 6) 시스템 아키텍처
- API Server
  - Job CRUD 엔드포인트
  - 헬스체크 엔드포인트
- Scheduler Module
  - 활성 Job 로딩
  - Cron 트리거 및 실행 큐잉
- Worker Module
  - Gemini 호출
  - 결과 후처리 및 Telegram 전송
  - 실행 결과 저장
- Database
  - jobs, job_runs 테이블

## 7) 데이터 모델 초안
### jobs
- id (PK)
- name
- prompt_template
- schedule_cron
- telegram_chat_id
- timezone (예: Asia/Seoul)
- is_active
- retry_policy_json
- created_at, updated_at

### job_runs
- id (PK)
- job_id (FK)
- scheduled_at
- started_at
- finished_at
- status (`success` | `failed`)
- gemini_response_text
- telegram_message_id
- error_message

## 8) API 설계 초안
- `POST /jobs` : Job 생성
- `GET /jobs` : Job 목록 조회
- `PATCH /jobs/:id` : Job 수정/비활성화
- `POST /jobs/:id/run` : 수동 실행
- `GET /jobs/:id/runs` : 실행 이력 조회
- `GET /health` : 서버 상태 확인

## 9) 실행 플로우
1. 스케줄 시간 도달
2. 실행 잠금/중복 방지 체크
3. Job 실행 레코드 생성(`job_runs`)
4. Gemini API 요청
5. 응답 검증/포맷팅
6. Telegram 전송
7. 실행 결과 저장
8. 실패 시 재시도(예: 3회, 지수 백오프)
9. 최종 실패 시 에러 알림 전송

## 10) 환경 변수
- `PORT`
- `DATABASE_URL`
- `GEMINI_API_KEY`
- `TELEGRAM_BOT_TOKEN`
- `DEFAULT_TELEGRAM_CHAT_ID`
- `LOG_LEVEL`
- `TZ`

## 11) 보안 및 운영 체크포인트
- [ ] API 키는 `.env` 및 시크릿 매니저로 관리
- [ ] 요청/응답 로그에서 민감정보 마스킹
- [ ] 관리자 API에 인증(토큰 또는 IP 제한) 적용
- [ ] 장애 시 알림 채널(텔레그램 운영방) 구성
- [ ] 배포 전 rate limit/timeout 설정

## 12) 개발 단계(마일스톤)
### M1. 기반 구성 (1~2일)
- [ ] 서버 초기화(Fastify/Express + TypeScript)
- [ ] Prisma + PostgreSQL 연결
- [ ] 환경 변수/설정 로더 구축

### M2. Job 관리 API (1~2일)
- [ ] Job CRUD 구현
- [ ] 입력 검증(Zod 등)
- [ ] 기본 테스트 작성

### M3. 스케줄/실행 엔진 (2~3일)
- [ ] Cron 스케줄러 구현
- [ ] 중복 실행 방지 로직
- [ ] 재시도/오류 처리 구현

### M4. 외부 API 연동 (2일)
- [ ] Gemini 연동 및 프롬프트 템플릿 적용
- [ ] Telegram 전송 모듈 구현
- [ ] 실패 케이스 핸들링

### M5. 운영 안정화 (1~2일)
- [ ] 구조화 로그/헬스체크
- [ ] 실행 이력 조회 API
- [ ] 간단 대시보드(옵션) 또는 관리자 스크립트

## 13) 테스트 전략
- 단위 테스트: 스케줄 계산, 재시도 로직, 포맷터
- 통합 테스트: Gemini/Telegram 모듈 Mock 기반 시나리오
- E2E 테스트: 테스트 Job 등록 -> 실행 -> 이력 검증
- 장애 테스트: API 실패, 타임아웃, Telegram 전송 실패

## 14) 리스크 및 대응
- Gemini 응답 지연/실패
  - 대응: 타임아웃, 재시도, fallback 메시지
- 텔레그램 rate limit
  - 대응: 전송 큐, 백오프
- 스케줄 중복 실행
  - 대응: DB 락/분산 락
- 운영 시 디버깅 어려움
  - 대응: run_id 기준 로그 추적

## 15) 완료 기준 (Definition of Done)
- [ ] 등록된 Job이 실제 스케줄 시간에 자동 실행된다.
- [ ] Gemini 결과가 텔레그램으로 정상 전달된다.
- [ ] 실패 시 재시도 및 에러 알림이 동작한다.
- [ ] 실행 이력 조회로 성공/실패를 확인할 수 있다.
- [ ] README에 실행 방법과 환경 변수 설명이 정리되어 있다.
