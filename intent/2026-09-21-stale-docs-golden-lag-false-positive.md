# Intent: guard-stale-docs 골든 실측 낡음 오탐 수정
Author: 사용자. Status: approved.

## Problem

커밋할 때마다 `[낡음] 골든 실측이 낡았습니다 — 문서 최신 923케이스 ↔ 러너 상수 914케이스` 가 뜨는데, 실제로는 세 자리가 전부 914 로 맞다. 사용자가 *"커밋 훅의 별건 경고는 뭐지?"* 로 물어 조사한 결과 오탐으로 판명됐다. 지금 하는 이유는 이 경고가 매 커밋에 붙어 진짜 낡음 고지를 묻어 버리기 때문이고, Deferred 대장에 2026-09-19 로 이미 등재돼 있다.

## Proposed outcome

현행 레포에서 커밋할 때 그 줄이 뜨지 않는다. 케이스 수가 줄어드는 회차에서도 정확히 갱신하면 침묵하고, 실제로 갱신을 빠뜨리면 종전대로 고지한다.

## Affected users and systems

하니스 레포에서 커밋하는 모든 세션. 걸리는 것은 `plugins/pjc/scripts/guard-stale-docs.ps1` 의 `Get-GoldenTimingLag()` 과 그것을 재는 골든 시나리오, 그리고 케이스 총계 사본 넷이다.

## Constraints

`guard-bash.ps1` 이 dot-source 하는 안전 임계 hook 이라 오탐 수정에도 골든 실증이 붙는다. 기존 골든 3-c2 가 「최댓값을 고르는가」를 축으로 못박고 있어 최댓값 폴백은 남긴다.

## Open questions

없음.
