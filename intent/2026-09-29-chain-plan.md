# Intent: chain-plan — 여러 계획을 계획마다 새 세션에서 순서대로 끝내는 코디네이터 스킬
Author: 사용자. Status: approved.

## Problem
원문: *"plan 1/2/3 계획이 이렇게 있으면 현재는 plan 1 작업 후 사용자가 직접 /clear 또는 새 세션에서 plan 2 진행 하라고 직접 입력하고 있는데, 이걸 자동으로 하고 싶은데"* · *"압축한 뒤 이어서 진행하면 작업 성능이 너무 떨어지고 불필요한 컨텍스트 때문에 토큰도 낭비가 되어서"* · *"실제 작업을 진행하기 전에 사용자가 요청하면 미리 계획에 필요한 인터뷰를 사용자에게 해서 답변을 받는건 어떤가?"*
계획이 여럿일 때 `/clear`·새 세션 전환을 사람이 매번 하고 있고, 전환하지 않고 압축으로 이어 가면 뒤 계획의 품질이 떨어진다. `/clear` 는 모델이 대신 입력할 수 없어 「새 세션을 자동으로 여는」 수단이 필요하다.

## Proposed outcome
`pjc:chain-plan` 이 있다. 사용자가 나눠 준 계획 목록을 받아 계획마다 사용자와 요구 인터뷰를 먼저 끝내고, Karina 오케스트레이션 워커 탭(새 세션)을 계획마다 띄워 `pjc:plan`(중계 모드 — 인터뷰 생략) → `pjc:implement` 를 끝까지 돌린다. 워커의 갈림길 질문과 승인 요약은 `ask` 로 코디네이터에 오고, 근거가 재진술에 있으면 코디네이터가 답하고 없으면 사용자에게 넘긴다. 승인은 항상 사용자가 한다. 워커가 멈추면 체인을 멈추고 보고한다. 끝났을 때 사용자의 개입은 「인터뷰 응답 + 계획당 승인 1회 + 재진술로 답할 수 없는 질문」뿐이다.

## Affected users and systems
사용자(pjc 레포에서 계획 여러 개를 순서대로 돌리는 본인). 하니스 레포 — `plugins/pjc/skills/chain-plan/`(신설) · `plugins/pjc/skills/plan/`(중계 모드 예외) · 트리거 eval 케이스 · `validate.ps1` · README · 매니페스트 description. Karina 앱·CLI 코드는 건드리지 않는다(기존 `orchestration` 명령을 그대로 쓴다).

## Constraints
Karina 앱이 켜져 있고 코디네이터 세션이 Karina 탭이어야 한다(`karina-cli` 는 앱에 RPC 한다). 계획은 순서 실행이고 같은 폴더(`--worktree current`)다. 승인·글로벌 지침의 별도 승인 항목은 그대로 사용자 몫이다. 코디네이터는 재진술에 없는 답을 지어내지 않는다. `pjc:implement` 는 고치지 않는다.

## Open questions
없음
