# Intent: llm-wiki 결함 W2~W8·W10 + description R7·W9 + 트리거 eval 전량 재측정
Author: 사용자(코디네이터 인터뷰 경유 — 계획 체인 run_df97d5067a35f3985c2fb07d3e031680 plan 4/4). Status: approved.

## Problem
원문(spec 「원문:」): "plan 4: llm-wiki 결함 W2~W8·W10 + description R7(rec 「기억해둬」)·W9(llm-wiki 영어·고빈도) + 트리거 eval 전량 재측정·기준선 갱신" · "[공통] 나머지 검토 결함도 계획 세워줘" · "[공통] 스크립트화 제외 · description 은 마지막 회차 (권장)" · "[plan 4] W2 — 규칙 삭제 (권장) — 손으로 지킬 수 없는 규칙을 걷고 rationale·커밋 [PID] 의미(세션 식별 고정값)를 맞춘다" · "[plan 4] W5 — 위키 소비 측 단일 (권장) — F-2·M 이 사용자 판단을 받아 붙인다" · "[plan 4] W6 — 폐지 — --auto-split 위임 (권장) — I-4 를 --auto-split 호출로 바꾸고 I-2b 는 포인터로" · "[plan 4] R7 — rec(AGENTS.md) + K 5-3 좁힘 (권장)" · "[plan 4] 요청 밖 후보 — schema-types.md 의 레포 루트 기준 경로 3곳도 W7 과 함께 — 포함 (권장)". 2026-10-04 skill-creator 전체 검토에서 남은 llm-wiki 결함과 description 경계 결함이다.

## Proposed outcome
llm-wiki 문서가 구현(`lint.py`)·다른 규약과 어긋나지 않고 중복 없이 정본 한 곳을 가리킨다 — 끊긴 참조가 없고, 구현 없는 lock 규칙이 걷히며, 가이드 분할이 `--auto-split` 로 일원화되고, 경위 서술은 근거 문서로 내려간다. record-project-fact 와 llm-wiki 의 description 이 「기억해둬(명령)」·영어·고빈도 단독어 경계를 올바르게 가르고, 빌드·테스트 명령 기억 요청이 rec 로만 가도록 queue-rules K 5-3 이 작업 규약·함정만으로 좁혀진다. 그 경계가 트리거 eval 케이스로 재지고 새 전량 run 이 기준선이 된다. 검증 매핑 필수 검증이 통과하고 바뀐 파일은 CRLF 다.

## Affected users and systems
pjc:llm-wiki·pjc:record-project-fact 를 쓰는 세션, 스킬 목록만 보고 고르는 모델, 하니스 유지보수자. 걸리는 것은 llm-wiki SKILL.md·references 문서(새 schema-rationale.md 포함)·lint.py 주석·check_consistency.py 앵커, record-project-fact description, 트리거 eval 케이스·README, docs/harness-conventions.md 기준선, README·plugin.json 버전이다.

## Constraints
스크립트화 없음 · eval 실행 중 레포 편집 금지 · 질의는 description 복창 금지 · 새 FAIL 은 원인 분류만 · llm-wiki 쓰기 범위를 vault 밖으로 넓히지 않는다(글로벌 결합) · plan 1~3 의 스킬 본문은 범위 밖 · DB 변경 금지 · 로컬 커밋까지(push·릴리즈는 보고).

## Open questions
없음
