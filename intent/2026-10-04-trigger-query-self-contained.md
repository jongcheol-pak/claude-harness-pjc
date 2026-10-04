# Intent: 트리거 eval 의 질의 원인 FAIL 2건을 자기완결 질의로 고치고 기준선을 다시 잰다
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문 요청: 「wiki-neg-6 대장 항목 처리 계획 세워줘」. 기준선 run `20261004-160310` 의 FAIL 2건이 둘 다 질의 원인이라 description 품질을 재지 못한다 — `wiki-neg-6` 은 질의가 전제한 「위키의 CSV 방식」을 모델이 vault 에서 읽으려다 격리 run 권한 거부로 멈췄고, `wiki-query-1` 은 자리표시 「OO」를 되묻고 멈췄다. 대장(2026-10-04 등재)은 비용 결정을 선행 조건으로 적었고, 사용자가 전량 재측정과 `wiki-query-1` 동반 수정을 골랐다.

## Proposed outcome
`wiki-neg-6` 질의가 위키 내용(CSV 규칙)을 직접 담고 `wiki-query-1` 의 자리표시가 구체 기능명으로 바뀌어, 둘 다 질의만으로 상황이 성립한다. 그 케이스로 돈 전량 run 이 README 의 새 기준선이 된다. 대장 항목은 새 run 에서 고쳐졌으면 종결되고, 같은 원인(vault 읽기)으로 다시 FAIL 하면 실해 기록을 새 run 으로 고쳐 남긴다.

## Affected users and systems
하니스 유지보수자(기준선을 보고 description 을 고치는 사람)와 트리거 eval 러너. 걸리는 것은 `plugins/pjc/skills/evals/trigger-cases.json`·`evals/README.md`·`docs/plans/deferred.md`.

## Constraints
케이스 목적 유지(`wiki-neg-6` = 위키를 언급한 구현 요청은 `pjc:plan` 으로 · `wiki-query-1` = 위키 조회는 `pjc:llm-wiki` 로) · 질의가 description 을 복창하지 않는다 · eval 실행 중 레포 편집 금지 · 새 FAIL 은 원인만 분류하고 재수정·재실행하지 않는다.

## Open questions
없음
