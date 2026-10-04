# Intent: debugging·record 결함과 교차 결함 — 실행 규칙 도달·조사 로그 위치·이관 사본·description 합계·절 추출 정본화
Author: 사용자(코디네이터 인터뷰 경유 — 계획 체인 run_df97d5067a35f3985c2fb07d3e031680 plan 3/4). Status: approved.

## Problem
원문(spec 「원문:」): "plan 3: debugging·record·교차 결함 — D1~D6 · R2~R4 · R6 · X1 description 합계 축 · X3 절 추출·PROJECT-FACT 조회 복제를 정본 포인터로(스크립트화 없음)" · "[공통] 나머지 검토 결함도 계획 세워줘" · "[plan 3] 요청 밖 후보 — debugging/SKILL.md:95·149 의 짝 문구 — 포함 — plan 3 에 (권장)" · "[plan 3] D2 — 기존 plan.md 절 · 없으면 대화만 (권장)" · "[plan 3] R3 — 사후 보고로 안내 (권장) — 스크립트가 .gitignore 등록 여부를 보고 없으면 보고에 한 줄" · "[plan 3] R6 — 정의 + 넘길 때 절대경로 (권장)" · "[plan 3] X1 — 통지 · 상한 6,000자 (권장)" · "[plan 3] harness-consistency-rationale.md 감량 — 보류 — X1 근거는 축 주석에 (권장)". 2026-10-04 skill-creator 전체 검토에서 남은 debugging·record·교차 결함이다.

## Proposed outcome
pjc-systematic-debugging 이 실행에 필요한 규칙을 실행 중에 읽는 자리에서 얻고, 승인된 plan.md 를 덮지 않으며, 진단 계측을 남기지 않고, 루프 안에서의 처방이 implement 정지 규칙과 같게 읽힌다. record-project-fact 의 경계·사본·경로 서술이 실제 동작과 맞고, 스킬 description 합계가 기계로 재지며, 절 추출 규칙은 정본 한 곳을 가리킨다. 검증 매핑 필수 검증(relocation 골든·evals 골든 포함)이 통과하고 바뀐 파일은 CRLF 다.

## Affected users and systems
pjc-systematic-debugging·record-project-fact 를 쓰는 세션과 하니스 정합 검사기. 걸리는 것은 두 스킬 문서와 참조 문서, relocate-agents.py 와 그 골든, check-harness-consistency.py 와 evals 골든, plan·implement SKILL.md 의 절 추출 사본, AUTHORING.md·harness-conventions.md 의 기준선, README·plugin.json 이다.

## Constraints
스크립트화 없음(X3 는 포인터 통합만) · guard-write 무변경 · 스킬 description 무수정 · plan 2 가 고친 plan/implement SKILL.md 위에서 X3 · Step 5 의 무승인 쓰기 범위(AGENTS.md·이관처) 유지 · llm-wiki 파일 무수정 · DB 변경 금지 · 로컬 커밋까지(push·릴리즈는 보고).

## Open questions
없음
