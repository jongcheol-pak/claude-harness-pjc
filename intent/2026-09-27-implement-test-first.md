# Intent: implement 스킬의 테스트를 먼저 작성하게 바꾼다
Author: 사용자. Status: approved.

## Problem
사용자 요청 *"implement 스킬도 테스트 먼저 작성하게 바꿔줘"*. 현행 `pjc:implement` 는 구현 뒤 케이스를 쓰고 변경을 한 줄 되돌려 red 를 사후 확인한다 — 구현을 본 뒤 쓴 케이스는 구현의 가정을 공유할 여지가 남고, 버그 수정 경로(`pjc-systematic-debugging` 4-A)만 테스트 먼저라 두 실행 경로의 순서가 갈려 있다.

## Proposed outcome
`pjc:implement` 의 검증 규칙이 「케이스 작성 → 실행해 RED 확인 → 구현 → GREEN」 순서를 규정한다. 구현 전 컴파일이 안 되면 시그니처만 있는 스텁을 먼저 두고 assertion 실패로 RED 를 본다. 사후 되돌리기 절차(한 줄 되돌리기·기대값 어긋내기)는 사라지고, RED 를 못 봤으면 미검증으로 보고하며, RED 출력은 커밋의 검증 결과에 남는다.

## Affected users and systems
모든 레포에서 `pjc:implement` 를 실행하는 세션. `plugins/pjc/skills/implement/SKILL.md` 「검증」 절.

## Constraints
케이스 면제 5종(`plan-template.md`)은 그대로 둔다. 스킬 본문 예산(`SKILL.md` 12,000자)을 넘지 않는다.

## Open questions
없음
