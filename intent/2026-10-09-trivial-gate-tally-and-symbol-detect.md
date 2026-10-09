# Intent: trivial 게이트의 편집 분할 구멍과 새 정의 미탐 보완
Author: 사용자. Status: approved.

## Problem
원문 요청: 「1번이랑 3번 보완하는 계획 세워줘」 — 앞 대화에서 지적한 두 결함이다. ① `guard-write` 의 3줄 trivial 판정이 `Edit` 호출 1회 단위라, 큰 변경을 3줄씩 나눠 고치면 매번 plan 없이 통과한다(「변경이 하나일 때만 계획 없이 편집」이라는 `pjc:plan` 규칙을 hook 이 강제하지 못한다). ③ 새 정의 감지 정규식이 Rust `fn`·JS/TS 화살표 함수·접근 제한자 없는 메서드를 놓쳐 그런 3줄 편집이 「새 정의 없음」으로 통과한다.

## Proposed outcome
한 사용자 요청 안에서 trivial 통과가 서로 다른 파일 3개째 또는 4회째에 이르면 그 편집은 trivial 로 통과하지 않고 plan 존재·PLAN-EXEMPT 검사로 넘어가, plan 이 없으면 A/B 질문 경로로 안내된다. 새 요청이 오면 누적이 다시 0 에서 시작한다. Rust `fn`·Go 리시버 메서드·JS/TS 화살표 함수 대입·접근 제한자 없는 메서드(이름만 · 반환형만)를 정의하는 편집은 3줄 이하여도 trivial 로 통과하지 않고, 제어문·호출문 편집은 종전대로 통과한다. `pjc:plan` 본문과 README 가 누적 판정을 서술한다.

## Affected users and systems
pjc 하니스를 쓰는 모든 코드 세션 — `plugins/pjc/scripts/write-gate-trivial.ps1`·`guard-write.ps1`(안전 임계 차단 hook)·`session-context.ps1`(마커 정리)과 그 근거 문서·골든, `pjc:plan` SKILL 본문, README.

## Constraints
- 안전 임계 hook 이라 미탐 보완만 허용되고, 새 경계가 실제로 발화하는 델타 음성 골든으로 오차단 0 을 실증한다.
- 누적 판정은 판정 근거를 못 얻으면(transcript 부재·식별자 없음) 오늘의 동작(그대로 trivial 통과)으로 돌아간다.
- `pjc:plan` description 은 고치지 않는다(사용자 답 「본문만 보강」).
- 누적 임계는 `pjc:plan` description 의 「바꾸는 값의 종류가 하나뿐인 단순 치환은 몇 곳이든 직접 편집」에도 걸린다 — 셋째 파일에서 막히고 A/B 절차로 표식을 받는다(사용자 답: 그 결과를 제시한 질문에 「본문만 보강」).

## Open questions
없음
