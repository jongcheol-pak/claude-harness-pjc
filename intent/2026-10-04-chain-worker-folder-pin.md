# Intent: 계획 체인 워커를 대상 레포 폴더에 고정하고 자리 충돌은 기다려 진행한다
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문 요청: 「위 작업 중에 plan 2 작업을 시작 할건지 멈줬었는데 이부분은 확인해서 멈추지 않고 진행 하도록 개선」 · 「진짜 충돌과 이번 사례의 차이, 같은 폴더에서 작업하는 세션은 없었고 다른 폴더에서 작업 중이 였음. 혹시 chain-plan에서 작업시 분할 탭으로 에이전트를 실행해서 작업 하는데 이때 문제가 되는지도 확인」. 2026-10-04 체인이 plan 2 `worker-start --worktree current` 에서 `duplicate_worker` 로 멈췄다 — `current` 가 코디네이터 탭이 아니라 Karina 화면의 활성 워크트리 그룹(그때 `Windows/Karina`)으로 해석돼 그 폴더의 다른 Run 워커와 겹쳤다. 그 폴더에 워커가 없었다면 하니스 계획이 다른 레포에서 실행될 상황이었다.

## Proposed outcome
계획 체인은 Karina 에서 어느 워크트리 그룹을 보고 있든 워커를 항상 대상 레포 폴더에 띄운다. 그 폴더를 다른 세션의 워커가 실제로 쥐고 있으면 체인을 멈추지 않고 그 워커가 자리를 놓을 때까지 기다렸다가 띄운다. 분할 탭은 폴더 해석에 영향이 없음을 확인했다.

## Affected users and systems
`pjc:chain-plan` 코디네이터 세션과 그것을 돌리는 사용자. 걸리는 시스템은 `plugins/pjc/skills/chain-plan/SKILL.md`(워커 루프)·`references/cli-errors.md`(`duplicate_worker` 처방)와 Karina `worker-start` 의 `--worktree` 해석·자리 판정(읽기만).

## Constraints
다른 세션의 워커는 stop·abandon 하지 않는다(2026-10-03 결정) · `chain-plan/SKILL.md` 12,000자 게이트(착수 11,991자) · Karina 코드는 고치지 않는다.

## Open questions
없음
