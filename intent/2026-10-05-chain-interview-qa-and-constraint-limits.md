# Intent: 계획 체인 인터뷰 문답 보존·제약 수치 판정 금지·인계 커밋 범위 갱신
Author: 사용자(2026-10-05 체인 감사 후속 요청). Status: approved.

## Problem
원문: 「1, 2, 3 전부 계획 세워줘」 — 감사 보고가 낸 셋: ① Q/A 원문 보존 — 중계 intent Problem 에 spec 「원문:」 블록 전체(질문·선택지·답)를 싣게 하고 plan-reviewer 가 Q/A 와 Constraints 를 대조 ② 제약 수치 판정 금지 — 비용·횟수·계획 경계처럼 제약에 수치나 경계가 적힌 항목을 넘는 일은 코디네이터 판정이 아니라 사용자 몫 ③ 인계 커밋 범위 갱신 — 완료 리뷰 수정 커밋이 인계 절 뒤에 생기면 범위를 다시 적는다. 인터뷰 문답: Q 「Q/A 원문을 어디에 남길까」 / 선택지: intent Problem 예외 (권장) · 인계 파일에 기록 · intent 별도 첨부 / A: intent Problem 예외 (권장) — Q 「Q/A 한 건에 무엇을 남길까」 / 선택지: 질문+선택지 이름+답 (권장) · 설명까지 전부 · 질문+답만 / A: 질문+선택지 이름+답 (권장) — Q 「[요청 밖] 2번을 워커 쪽에도 적용할까」 / 선택지: 포함 (권장) · 제외 · 보류 / A: 포함 (권장). 지금 하는 이유: 2026-10-05 감사에서 Run 2개(계획 6개)의 왜곡은 0건이었으나 Q/A 원문이 intent 에 남지 않아 사용자가 정한 것과 코디네이터가 정한 것이 갈리지 않았고, 코디네이터가 eval 재측정(제약 「전량 1회」 초과)과 X3 계획 재배정을 혼자 판정했으며, 인계 파일 커밋 범위에서 리뷰 수정 커밋 5개가 빠졌다.

## Proposed outcome
계획 체인에서 인터뷰 문답(질문·선택지 이름·사용자 답)이 중계 intent Problem 에 줄지 않고 남고 plan-reviewer 가 그 답을 Constraints·task·Decisions 와 대조한다. 제약에 적힌 대상·수치·계획 경계를 넘거나 좁히는 결정은 코디네이터 판정·워커 Decisions 로 닫히지 않고 사용자에게 간다. 인계 절 커밋 뒤에 워커가 커밋을 더 만들면 인계 파일 커밋 범위가 그 커밋까지 고쳐진다.

## Affected users and systems
pjc:chain-plan 을 돌리는 사용자·코디네이터 세션·중계 워커·plan-reviewer. 걸리는 시스템은 `plugins/pjc/skills/chain-plan/SKILL.md`·`references/handoff.md`, `plugins/pjc/skills/plan/references/relay-mode.md`·`intent-rules.md`, `plugins/pjc/agents/plan-reviewer.md`, `README.md`·`plugin.json`.

## Constraints
중계 intent 의 Problem 만 「각 절 1~3문장」 예외이고 일반 intent 형식은 그대로 · 선택지 설명은 싣지 않는다 · 리뷰어 수(2종)를 늘리지 않는다 · hook 무변경 · chain-plan SKILL.md ≤12,000자 · plan-reviewer.md ≤6,000자 · DB 변경 없음 · push·릴리즈는 하지 않는다.

## Open questions
없음
