# Helper — 할 일 자동화 서버

웹페이지에서 할 일을 등록하면, 지정한 시간에 Gemini가 내용을 정리하고 텔레그램으로 자동 전송합니다.

---

## 목차

1. [사전 요구사항](#1-사전-요구사항)
2. [설치 및 초기 설정](#2-설치-및-초기-설정)
3. [Gemini API 키 발급](#3-gemini-api-키-발급)
4. [Telegram Bot 생성 및 Chat ID 확보](#4-telegram-bot-생성-및-chat-id-확보)
5. [.env 파일 작성](#5-env-파일-작성)
6. [서버 실행](#6-서버-실행)
7. [사용 방법](#7-사용-방법)
8. [보안 주의사항](#8-보안-주의사항)

---

## 1. 사전 요구사항

- **Node.js 20 이상** 설치 필요
  - 버전 확인: `node -v`
  - 설치: https://nodejs.org 에서 LTS 버전 다운로드

---

## 2. 설치 및 초기 설정

```bash
# 저장소 클론
git clone https://github.com/redspy/helper.git
cd helper

# 의존성 설치
npm install

# DB 초기화 + .env 파일 자동 생성
npm run setup
```

`npm run setup` 한 번으로 아래가 자동 처리됩니다.

- `data/helper.db` SQLite 데이터베이스 생성
- `.env` 파일이 없으면 생성 (키 이름만 있고 값은 비어있는 상태)
- `.env` 파일이 이미 있으면 덮어쓰지 않고 유지

---

## 3. Gemini API 키 발급

### 3-1. Google AI Studio 접속

1. 브라우저에서 **https://aistudio.google.com** 접속
2. Google 계정으로 로그인

### 3-2. API 키 생성

1. 왼쪽 메뉴에서 **"Get API key"** 클릭
2. **"Create API key"** 버튼 클릭
3. 프로젝트 선택 또는 새 프로젝트 생성 → **"Create API key in existing project"** 선택
4. 생성된 키(`AIza...` 로 시작하는 문자열) 복사

### 3-3. 주의사항

- API 키는 한 번만 표시될 수 있으니 복사 후 바로 `.env`에 저장하세요.

---

## 4. Telegram Bot 생성 및 Chat ID 확보

### 4-1. BotFather로 Bot 생성

1. 텔레그램 앱에서 **@BotFather** 검색 후 채팅 시작
2. `/newbot` 명령어 입력
3. Bot 이름 입력 (예: `My Helper Bot`)
4. Bot 사용자명 입력 — 반드시 `bot`으로 끝나야 함 (예: `my_helper_bot`)
5. BotFather가 **Bot Token** 발급 (`123456789:AAF...` 형태) → 복사

### 4-2. Chat ID 확인

Bot이 메시지를 보낼 채팅방의 ID가 필요합니다.

**개인 채팅 Chat ID 확인 방법:**

1. 텔레그램에서 방금 만든 Bot을 검색 후 `/start` 메시지 전송
2. 아래 URL을 브라우저에서 열기 (Bot Token으로 교체):
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
   ```
3. 응답 JSON에서 `"chat":{"id":숫자}` 부분의 숫자가 Chat ID

예시 응답:
```json
{
  "result": [{
    "message": {
      "chat": {
        "id": 123456789,
        "type": "private"
      }
    }
  }]
}
```
→ `123456789`이 Chat ID

**그룹 채팅 Chat ID 확인 방법:**

1. Bot을 그룹에 초대
2. 그룹에서 아무 메시지나 전송
3. 위와 동일하게 `getUpdates` 호출 → `"chat":{"id":-숫자}` (음수)

---

## 5. .env 파일 작성

`npm run setup` 실행 후 프로젝트 루트에 `.env` 파일이 생성됩니다.
텍스트 편집기로 열어서 아래와 같이 값을 입력합니다.

```dotenv
# Gemini
GEMINI_API_KEY=AIzaSy...여기에_발급받은_키_붙여넣기

# Telegram
TELEGRAM_BOT_TOKEN=123456789:AAF...여기에_Bot_Token_붙여넣기
TELEGRAM_CHAT_ID=123456789

# 서버
PORT=6240
TZ=Asia/Seoul
SESSION_SECRET=helper-secret-key-변경요망
APP_PASSWORD=단번에로그인할비밀번호입력
```

### .env vs .env.example 차이

| 파일 | 용도 | Git 포함 여부 |
|------|------|--------------|
| `.env` | 실제 API 키가 들어있는 파일 | ❌ 절대 포함하지 않음 |
| `.env.example` | 키 이름만 있는 템플릿 | ✅ 포함 (값은 비어있음) |

---

## 6. 서버 실행

```bash
# 일반 실행
npm start

# 개발 모드 (파일 변경 시 자동 재시작)
npm run dev
```

서버 시작 후 브라우저에서 http://localhost:6240 접속

---

## 7. 사용 방법

### 할 일 등록

1. 브라우저에서 서버 주소 접속 후 `APP_PASSWORD`에 지정된 비밀번호로 로그인
   - `APP_PASSWORD`를 비워두면 기본값 `13579` 사용
2. 웹페이지 상단 폼에 **제목**, **내용**, **예정 시간**, **반복 주기** 입력
3. **등록** 버튼 클릭

반복 주기 옵션:
- `1회` — 한 번 실행 후 "지난 할 일"로 이동
- `매일` / `매주` / `매월` — 실행 후 다음 주기로 자동 갱신
- `커스텀` — cron 표현식 직접 입력 (예: `0 9 * * 1-5` = 평일 오전 9시)

### 자동 실행 흐름

1. 서버가 1분마다 예정 시간이 된 할 일을 확인
2. Gemini(`gemini-2.5-flash`)가 원문 내용을 분석하고 Google 검색을 통해 최신 정보를 포함하여 자유롭게 정리
3. 텔레그램으로 결과 전송
4. Gemini/Telegram 호출은 각각 최대 3회 재시도
5. 작업 단위 실패는 1분 간격으로 최대 5회까지 자동 재시도 후 `failed` 처리

### 지난 할 일 재수행

1. 화면 하단 **"지난 할 일"** 섹션 펼치기
2. 원하는 항목의 **"다시 수행"** 버튼 클릭
3. 새 예정 시간 입력 → **활성화**

---

## 8. 보안 주의사항

- `.env` 파일은 절대 Git에 커밋하지 마세요. `.gitignore`에 이미 등록되어 있습니다.
- API 키가 노출된 경우 즉시 해당 서비스에서 키를 폐기하고 재발급하세요.
  - Gemini: https://aistudio.google.com → API Keys → 해당 키 삭제
  - Telegram: BotFather → `/revoke` 명령으로 Token 재발급
- 서버를 외부에 노출할 경우 방화벽 또는 인증 미들웨어를 추가하세요.
