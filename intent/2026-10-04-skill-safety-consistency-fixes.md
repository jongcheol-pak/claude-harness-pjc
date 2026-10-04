# Intent: 스킬 본문·규약 문면의 안전·정합 결함 7건
Author: 코디네이터 인터뷰 경유 (pjc:chain-plan run_522092b84250d355c17aadad5c9644be, plan 1/2). Status: approved.

## Problem
원문: 「plan 1: 스킬 본문·규약 문면의 안전·정합 결함 7건 — B1 implement 완료 단계 순서(리뷰 등재분 대장 이관) · B2 RED 규칙 범위 · B3 큐 append 후 vault 커밋 규칙 · B4 record-project-fact 절 신설 위치 문면 불일치 · B5 AGENTS-BOUNDARY.md 끊긴 WIKI.md 경로 · A1 plan 승인 표지 + implement 진입 확인 · A3 debugging 단독 수정의 PLAN-EXEMPT 경로 (description·트리거 eval 은 건드리지 않는다)」. 2026-10-04 skill-creator 전체 검토가 찾은 결함 중 사용자가 「발동 경계·안전 결함부터」로 고른 묶음이라 지금 한다.

## Proposed outcome
승인 전 plan 을 implement 가 확인 없이 실행하지 않고, plan 없이 발동한 debugging 의 단일 파일 수정이 guard-write 에 막히지 않으며, 리뷰 등재분 대장 이관·RED 판정 범위·큐 append 커밋·AGENTS.md 절 신설 위치·WIKI.md 포인터가 문서 사이에서 한 가지로 읽힌다. 7건이 각 정본 문면에 반영되고 필수 검증이 전부 통과하며 변경 파일이 워킹트리 CRLF 다.

## Affected users and systems
pjc 플러그인 사용자와 그 스킬을 실행하는 모델(plan·implement·debugging·record-project-fact·llm-wiki 큐를 쓰는 코드 세션). 걸리는 시스템은 `plugins/pjc/skills/` 의 implement·plan·pjc-systematic-debugging·record-project-fact·llm-wiki 문서, `WIKI.md`·`AGENTS-BOUNDARY.md`, `docs/harness-conventions.md`, `plugins/pjc/scripts/rules/plan-exempt-rationale.md`, `README.md`·`plugin.json`.

## Constraints
hook 코드 무변경(A3 는 스킬·규약 문면만 — guard-write 는 안전 임계 hook) · SKILL.md frontmatter description 무수정 · BUDGET.md 상한 준수 · AGENTS.md DO NOT · B4 는 근거 문서 §9 를 SKILL.md(뼈대 순서 정본)에 맞추고 기록 시 기존 절은 옮기지 않는다 · DB 변경 금지 · push·릴리즈는 하지 않는다(로컬 커밋까지).

## Open questions
없음
