# AGENTS.md — Agent Guide

> 골든 픽스처. 실 레포의 최소 형상만 담는다.

## Build & Test

- 검증: `python plugins/pjc/evals/check-harness-consistency.py`
- 상세는 `docs/harness-conventions.md`의 「검증 매핑 (task 검증 선택)」이 정본이다.
- 모드별 차이는 아래 「실행 모드」 표가 정본이다.

| 모드 | 명령 |
|---|---|
| 기본 | `check-harness-consistency.py` |
| 수정 | `--fix` |

## 실행 모드

- 위험한 명령 차단 (끌 수 없음)
- 기본 모드는 판정만 한다.

> 차단 목록은 위 「위험한 명령 차단」이 정본이다.

## §3 ---- 접두 달린 절

기계가 붙인 `§N ---- ` 접두를 참조 쪽은 적지 않는다 — 아래 「접두 달린 절」로 가리킨다.

## Conventions

- **인코딩**: `.md`는 BOM 없음. **줄바꿈**: CRLF.
- 표 열 이름으로도 가리킨다 — 위 「명령」 열을 볼 것.
