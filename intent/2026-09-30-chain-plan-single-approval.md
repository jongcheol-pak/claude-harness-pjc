# Intent: chain-plan — 체인 승인 한 번으로 완료까지 자동 진행
Author: 사용자(karina-44 세션이 정리한 요구를 이 세션 인터뷰로 확정). Status: approved.

## Problem
원문(karina-44 경유 요지): *"작업을 요청하면 인터뷰하며 계획을 쓰고, 사용자 승인을 받아 완료까지 가야 한다. 지금은 plan 1/2 마다 승인을 따로 받는다. chain-plan 을 쓰는 이유가 자동 진행인데 그게 안 된다"* · *"작업 중 DB 수정·삭제는 절대 금지. 필요하면 계획을 쓸 때 사용자 승인을 미리 받는다"* · *"plan 1 의 결과를 plan 2·3 이 참고해야 하면 파일로 남겨"* · *"심각한 문제이거나 계획대로 진행할 수 없는 경우가 아니면 자동으로 진행한다. 작업 중 생긴 문제는 임시로 때우지 말고 근본 원인을 고친다"* · *"끝나면 한 일을 사용자가 이해하기 쉽게 요약해 알린다"*. 이 세션 사용자 발화: *"pjc:plan에서 작업 내용이 많은 경우 분할을 할 지 사용자에게 물어 보는데 chain-plan에서만 분할을 한다는 건가?"*
E2E(2계획)에서 계획마다 승인을 따로 받아 자동 진행이 되지 않았고, 워커는 WHERE 있는 UPDATE/DELETE·INSERT·스키마 변경을 막는 장치가 없으며, 앞 계획의 결과가 뒤 계획으로 가는 경로가 git 이력과 `--body` 한 줄뿐이다.

## Proposed outcome
체인 시작 때 사용자가 체인 승인을 한 번 하면, 워커의 plan 승인 요청은 코디네이터가 봉투(재진술 범위·승인 필요 항목·DB 목록)를 대조해 자동으로 답하고 어긋날 때만 사용자에게 간다. DB 변경은 인터뷰에서 받은 승인 목록 안에서만 일어난다. 앞 계획의 결과는 인계 파일로 다음 워커에 간다. `pjc:plan` 이 회차를 나눌 때 Karina 탭이면 회차 전부를 체인으로 돌릴지 물어 `chain-plan` 에 넘긴다. 완료 보고는 사용자 관점으로 요약된다. 2계획 E2E 에서 사용자 승인이 체인 승인 1회로 끝나고 plan 2 워커가 인계 파일을 읽는다.

## Affected users and systems
Karina 탭에서 계획 여러 개를 돌리는 사용자. 하니스 레포 — `plugins/pjc/skills/chain-plan/SKILL.md` · `plugins/pjc/skills/plan/references/interview.md` 「중계 모드」 · `plugins/pjc/skills/plan/SKILL.md` Step 5 · `README.md`.

## Constraints
push·병합·태그·릴리즈·PR·파괴적 작업·신규 인증 서비스는 위임하지 않고 실행 시점에 사용자 승인을 받는다. 코디네이터는 파일을 고치지 않는다. `pjc:implement` 는 고치지 않는다. 두 스킬의 description 은 바꾸지 않는다.

## Open questions
없음
