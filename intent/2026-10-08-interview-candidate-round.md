# Intent: 계획 인터뷰에서 함께 고칠 곳·추가 기능을 먼저 제안
Author: 사용자. Status: approved.

## Problem
원문: *"인터뷰 시 사용자가 요청한 기능에 대해서만 인터뷰를 하고 있는데 같이 수정해야 할 부분과 추가해야 할 기능을 좀 더 생각해서 인터뷰때 같이 알려주도록 해줘, 지금은 작업이 완료되고 나면 그때 추가로 수정할 부분을 알려주고 있는데 미리 같이 계획을 세워서 작업 할 수 있도록"*. `pjc:plan` 인터뷰(Step 2)는 영향 범위 실측(Step 3)보다 먼저 끝나서, 실측에서 드러난 연관 수정을 물을 자리가 없다. 옛 `plan-feature` 4-E 「동반 변경 판정」이 스킬 재작성 때 빠졌는데도 README 는 아직 그 기능을 설명한다.

## Proposed outcome
실측이 끝나면 plan 을 쓰기 전에 「후보 라운드」를 연다. 함께 고칠 곳(전부)·Deferred 대장 겹침(전부)·근거 있는 추가 기능(최대 3개)을 권장 답과 함께 한 화면 목록으로 보이고, `포함 / 제외 / 보류`(대장 겹침은 `포함 / 대장 유지`)를 일괄로 받는다. 후보가 없으면 확인 범위와 함께 「후보 없음」 한 줄을 낸다. `pjc:chain-plan` 코디네이터도 계획마다 같은 절을 따르고, `plan-reviewer` 는 실측에 드러났는데 task·범위 밖·보류 어디에도 없는 연관 수정을 지적한다. 승인 요약에는 포함한 요청 밖 항목이 보인다.

## Affected users and systems
`pjc:plan`·`pjc:chain-plan` 으로 계획을 세우는 사용자. `plugins/pjc/skills/plan/`(SKILL.md·interview.md·round-split.md), `plugins/pjc/skills/chain-plan/`(SKILL.md·handoff.md·measure.md), `plugins/pjc/agents/plan-reviewer.md`, `README.md`.

## Constraints
규칙 정본은 `interview.md` 한 곳에 두고 다른 파일은 그 절을 가리킨다. 중계 모드 워커는 후보 라운드를 열지 않는다(지금처럼 `[요청 밖]` 질문). 근거 없는 추가 기능과 이미 기각·보류된 방안은 후보로 내지 않는다. 문서 크기 상한을 지킨다.

## Open questions
없음
