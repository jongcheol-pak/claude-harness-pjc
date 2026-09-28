# Intent: llm-wiki 스킬 개선 2회차 — wiki-schema 3분할·이름 충돌·결정 ID 잔재·description 미커버
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
직전 회차(`intent/2026-09-28-llm-wiki-review-fixes.md`)가 `[다음 회차]` 로 넘긴 4건이다. 원문 요청: *"위키 스킬 고아 항목, 중복 등 개선할 부분 검토"* → *"권장 순서대로 계획 세워줘"* → *"다음 회차를 이어서 계획해줘"*.
- `references/wiki-schema.md` 가 185,063 B 로 단일 Read 에 담기지 않는다(§2 51.7KB · §4 31.7KB · §7 33.6KB · §8 14.8KB). 같은 규칙의 반복 서술(「6번째 항목」 트리거 8곳 · index 3단계 순번 분할 메커니즘 2곳 · 파일 이름 규칙 표 2곳)이 가드 없이 흩어져 있다.
- schema §4 에서 「1단계」가 두 뜻(본체 비분할 섹션 분리 / 소제목 구역화)으로 쓰인다.
- 레포 안에서 정의되지 않는 결정 ID(`D1`·`D2`·`D5`·`D6`·`D8`·`D11`)가 문서·코드·lint 출력·골든에 남아 있다.
- llm-wiki `description` 이 위키 조회(G)·결정 이력 조회(G 2b)·vault 경로 설정(0-1) 질의에 발동하지 않는다(2회 연속 미발동).

## Proposed outcome
- `wiki-schema.md` 가 코어(§1·§3·§5·§6·§7·§9·§11·§12 + 목차) · `schema-types.md`(§2) · `schema-budget.md`(§4 · §7-2 · §8) 셋으로 나뉜다. § 번호는 그대로 유지하고 코어 목차가 세 파일을 라우팅한다.
- 분할 절을 가리키는 파일명 인용(`wiki-schema §4` 등)이 새 파일명으로 바뀌고, `check_consistency.py` 에 「§ 인용 → 그 § 헤딩이 실재하는 파일」 축이 생겨 다음 이동 때 red 를 낸다.
- 반복 서술 3종이 정본 1곳 + 포인터로 줄어든다.
- 「1단계」는 본체 분리 한 뜻만 남는다.
- 정의 없는 결정 ID 가 0건이 된다(lint 출력 문자열·골든 포함).
- 세 질의가 트리거 eval 에서 발동하고 케이스가 `trigger-cases.json` 에 되살아난다.
- 기존 검증이 전부 green 이다.

## Affected users and systems
본인과 마켓플레이스 배포 사용자(위키 세션 에이전트). `plugins/pjc/skills/llm-wiki/`(SKILL·references·scripts/lint.py·evals), `plugins/pjc/skills/evals/trigger-cases.json`·`README.md`, `plugins/pjc/skills/AUTHORING.md`, `plugins/pjc/scripts/rules/session-context-rationale-wiki.md`, `plugins/pjc/skills/pjc-systematic-debugging/references/debugging-rationale.md`, `docs/harness-conventions.md`.

## Constraints
- 워킹트리 CRLF · `.ps1` BOM 규약을 지킨다.
- 절 이동은 원문 그대로 옮기고, 분리 경계를 넘는 상대 참조는 경로를 명시한다.
- §7 나머지는 코어에 둔다(§7-2 자리는 번호를 지키는 포인터).
- description 은 미커버 3질의 보강만 한다 — 의도 범주 압축(위키 decisions 2026-09-27 보류)은 하지 않는다.
- 트리거 eval 은 `--filter wiki` 로만 돈다(모델 호출 비용).
- push·릴리즈는 별도 승인이다.

범위 밖:
- §7 ↔ F-1 통합(lint 파일 이관)
- description 의도 범주 압축
- vault 페이지의 `wiki-schema §N` 인용 갱신(코어 목차 라우팅으로 도달 가능 — 위키 세션 몫)

## Open questions
없음.
