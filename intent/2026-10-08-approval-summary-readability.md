# Intent: 승인 요약을 사람이 판단할 수 있게 보강
Author: 사용자. Status: approved.

## Problem
원문: *"plan.md파일 작성은 사용자가 읽기 좋게 만들고 있나? 아니면 llm이 작업을 이해하기 쉽게 작성하고 있나?"* → *"승인 요약 보강안으로 계획 세워줘"*. `plan.md` 는 실행자·리뷰어·검사기용 명세라 사람이 읽고 판단하는 자리는 화면의 승인 요약 하나인데, 그 서식이 task 한 줄 목록·승인 필요 항목·남은 리뷰 지적뿐이라 무엇을 왜 하는지와 무엇을 안 하는지는 `plan.md` 를 열어야 알 수 있고, 문장도 기준 번호·검사 축 번호 같은 내부 식별자로 쓰인다.

## Proposed outcome
`interview.md` 「승인 제시」 서식에 `목표:`·`범위 밖:`·`결정:` 줄이 있고, 결정 줄은 인터뷰에서 사용자가 답한 것과 근거로 정한 것을 모두 싣되 어느 쪽인지 표시한다. 요약의 모든 줄을 내부 식별자 없이 무엇이 바뀌는지로 쓰라는 규칙이 있다.

## Affected users and systems
`pjc:plan` 의 승인 요약을 읽고 Y/E/N 을 고르는 사용자, 그리고 체인 중계 모드에서 같은 본문을 받는 `pjc:chain-plan` 코디네이터. `plugins/pjc/skills/plan/references/interview.md` 「승인 제시」.

## Constraints
`plan.md` 템플릿은 바꾸지 않는다. 기존 줄(task 줄·`승인 필요 항목`·`남은 리뷰 지적`)과 체인 봉투 대조가 쓰는 줄 이름을 유지한다.

## Open questions
없음
