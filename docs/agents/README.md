# Agent Documents

Claude Code CLI에서 여러 역할의 에이전트가 같은 프로젝트를 다룰 때 사용하는 문서 모음입니다.

## 파일 구조

```text
docs/agents/
├── README.md
├── guides/
│   ├── pl-guide.md
│   ├── pm-guide.md
│   ├── developer-guide.md
│   └── quality-guide.md
└── prompts/
    ├── pl-prompt.md
    ├── pm-prompt.md
    ├── developer-prompt.md
    └── quality-prompt.md
```

## 사용 방법

1. 새 Claude Code CLI 세션을 열 때 담당 역할을 하나 정한다.
2. 루트의 `CLAUDE.md`를 먼저 읽는다.
3. `docs/agents/guides/{role}-guide.md`를 읽는다.
4. `docs/agents/prompts/{role}-prompt.md`의 프롬프트를 해당 세션에 입력한다.
5. 작업 종료 시 `CLAUDE.md`의 공통 보고 형식으로 결과를 남긴다.

## 역할별 목적

- PL: 프로젝트 진행 상태와 의사결정의 단일 정리자
- PM: 사용자 가치, 시장성, 차별화 포인트의 책임자
- 개발자: 코드 구현, 테스트 작성, 기술적 안정성의 책임자
- 품질: 테스트 설계, 검증, 결함 재현과 재검증의 책임자
