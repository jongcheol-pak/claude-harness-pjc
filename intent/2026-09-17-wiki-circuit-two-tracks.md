# Intent: 위키 참조 회로를 계획/구현 두 트랙으로 가른다
Author: 사용자. Status: approved.

## Problem

사용자 요청은 *"위키 활용도가 어떤가?"* → *"수정할 부분이 있는지 실제 작업에 도움이 되는지 확인"* → *"A로 진행해줘"*(4건 전부 계획) 였다. 확인 결과 위키 자료의 질은 높은데 **전달 경로가 어긋나 있다** — 계획 단계에서 소비되는 지식(acceptance 설계·측정 명령 함정)을 구현 시점 자리(task `**함정**` 줄)로 배분하게 돼 있어, 실행에서 「해당 없음」이 되고 K=0 으로 집계된다. 지금 하는 이유는 **Deferred 대장의 「5회차 누적 뒤 효용 판정」이 이 지표를 입력으로 쓰기 때문**이다 — 정의를 고치지 않으면 4회차를 더 모아도 K=0 이 반복되고, 그 0 이 「위키 무용」이라는 틀린 결론의 근거가 된다.

## Proposed outcome

위키에서 읽은 지식이 쓰이는 시점에 맞는 자리로 가고, 계획 트랙과 구현 트랙의 기여가 `wiki-usage.md` 에서 따로 측정된다. `WIKI.md` 의 낡은 실측값 3곳이 현재와 일치하고, 계획 경로 34항목의 승격 중복이 정리된다.

## Affected users and systems

이 레포에서 `pjc:plan`·`pjc:implement` 를 돌리는 세션과, 그 회로의 효용을 판정할 사용자. 걸리는 자산은 `skills/WIKI.md` · `plan/SKILL.md` · `plan/references/plan-template.md` · `implement/SKILL.md` · `agents/plan-reviewer.md` · `docs/plans/wiki-usage.md` · 위키 vault 2파일이다.

## Constraints

`decisions.md` 5번(의도적 이중화 예외)은 스킬↔글로벌 축이라 위키↔스킬 중복에 적용되지 않는다. `BUDGET.md` 「예산 표」의 *"근거 열의 B 표기는 과거 실측이라 그대로 둔다"* 와 충돌하지 않도록, 날짜가 박힌 사건 기록은 유지하고 현재 상태 주장만 갱신한다. 위키 vault 편집은 이 세션이 `pjc:llm-wiki` 가 아니므로 별도 승인 대상이다.

## Open questions

없음.
