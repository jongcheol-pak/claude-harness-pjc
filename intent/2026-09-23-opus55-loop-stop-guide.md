# Intent: Opus 5.5 가이드 대조 — 자율 루프 조기 정지 문면과 설계 원칙 세대 갱신
Author: 사용자. Status: approved.

## Problem
원문 요청: *"1·3항이랑 중간 업데이트 문구까지 계획 세워줘"* — 앞선 검토(`prompting-claude-opus-5-5` 가이드 대조)의 1항(정지 형태 누락)·3항(DESIGN.md 세대 표기)과 「중간 업데이트」 문구 조정이다. Opus 5.5 가이드가 조기 정지를 네 형태로 들었는데 정지 형태 정본(`loop-stop-patterns.md`)에는 나머지를 막지 않는 결정 목록으로 멈추는 형태가 없고, `implement` 의 「중간 업데이트를 내지 않는다」는 5.5 의 기본 동작·Claude Code 의 「몇 마디로 말하고 계속하라」 리마인더와 문면상 부딪친다. 실사용 모델이 5.5 로 바뀐 지금 맞춰 둔다.

## Proposed outcome
정지 형태 목록에 ⑤가 있고, `implement/SKILL.md` 가 가이드 영문 단락을 원문으로 싣되 규약이 지목한 정지와 충돌하지 않으며, 한 줄 상태 메모는 도구 호출과 같은 메시지 안이면 허용된다. `plan` 밖 변경 정지 전에 의존하지 않는 task 를 먼저 끝낸다. `DESIGN.md` 가 5.5 가이드를 출처로 갖는다.

## Affected users and systems
`pjc:implement` 자율 루프를 돌리는 사용자. `implement/SKILL.md` · `implement/references/loop-stop-patterns.md` · `skills/DESIGN.md`.

## Constraints
가이드 문구는 원문 그대로 인용한다. hook·검사기 코드는 고치지 않는다. `DESIGN.md` §3 절 제목은 위키 각주가 참조하므로 유지한다. CRLF·예산 상한을 지킨다.

## Open questions
없음 — 인터뷰에서 영문 단락의 위치(`implement/SKILL.md`)를 확정했다.
