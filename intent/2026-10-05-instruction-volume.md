# Intent: 계획 체인·공용 스킬의 매번 읽히는 지침량 줄이기
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문 요청: *"지침량 줄이는 계획 세워줘"* — 직전 질의(「opus 5.5 모델이 chain-plan 스킬을 사용하면서 계획이나 작업을 잘 할 수 있나?」)의 답에서 남은 위험 1번으로 든 「지침량이 많아 규칙 누락·해석 편차 여지」의 후속이다. 실측상 코디네이터가 매번 읽는 문서는 16,719자(규칙 69개)이고 `chain-plan/SKILL.md` 는 게이트 12,000자 중 11,988자다. 워커는 44,655자(규칙 165개)를 매번 읽고 그중 `relay-mode.md` 9,893자는 절 하나에 아키텍처 선언 부재·ask 만료처럼 드문 조건에만 쓰는 규칙이 섞여 있다.

## Proposed outcome
체인 워커와 비체인 `pjc:plan`·`pjc:implement` 가 매번 읽는 글자 수가 줄어든다(코디네이터 쪽은 옮길 수 있는 후보가 적어 소폭이다). 규칙은 하나도 사라지지 않는다 — 옮긴 규칙은 판정 가능한 로드 트리거로 닿고, 지운 복창은 정본에 살아 있다. 매번 읽힘 글자 수·규칙 수는 착수·완료 때 재서 보고한다(목표치 없음).

## Affected users and systems
`pjc:chain-plan` 사용자와 비체인 계획·구현 사용자. `chain-plan/SKILL.md`·references, `plan/SKILL.md`·`plan/references/relay-mode.md`·`plan-template.md`, `implement/SKILL.md` 와 그것을 가리키는 문서·에이전트 정의.

## Constraints
BUDGET 처방 ②(조건부 이동)와 ①(중복 삭제)만 쓴다 — 압축·통합·폐기 금지(사용자 답 「이동+중복 삭제」) · 대상은 체인 전용과 공용 문서 전부(사용자 답 「체인+공용 전부」) · 수치 목표 없이 전후 실측만 보고(사용자 답 「전후 실측만」) · 스킬 `description` 불변 · 안전 임계 hook 불변 · CRLF·BUDGET 상한.

## Open questions
없음
