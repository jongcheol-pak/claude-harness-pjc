# Intent: 하니스 스킬의 삭제 후보 34곳 제거와 1곳 통합
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
2026-09-18 스킬 전수 검토가 결함 18건과 함께 삭제 후보 36곳을 냈고, 결함은 v1.296.0·v1.297.0 이 닫았으나 삭제분은 그대로 남았다. 셋으로 갈린다 — **발동 불가**(리뷰어에게 없는 도구를 쓰지 말라 하거나, 존재하지 않는 호출 지점에 규약을 붙이거나, 넣으면 반드시 기각되는 큐잉을 지시하는 규칙 6건), **정본 복제**(정본을 포인터로 가리켜 놓고 그 내용을 그대로 옮겨 적어, 한쪽만 고쳐지면 갈리는 자리 11곳), **이력 서술**(분리 경위·폐기된 기제·회차 식별자만 남아 현재 동작을 규정하지 않는 문장 18곳). 원문 요청: *"삭제 후보도 이어서 고치는 plan 세워줘 새 세션에서 진행 할 수 있게"*. 지금 하는 이유: 두 회차가 결함을 닫으며 같은 파일들을 열었고 그 실측이 아직 유효하다.

## Proposed outcome
지운 규칙 하나하나가 상위 규약이나 다른 정본에 실재함을 `grep` 으로 보인 상태로 34곳이 사라지고, 살아남는 자리를 못 댄 1곳은 삭제 대신 제자리를 찾는다. 검사기 전수가 green 을 유지한다.

## Affected users and systems
`pjc:plan`·`pjc:implement`·`pjc:llm-wiki`·`pjc:pjc-systematic-debugging`·`pjc:record-project-fact` 의 문면과 그 references · `plan-reviewer` 정의 · 공통 규약 문서(`DESIGN.md`·`AUTHORING.md`·`BUDGET.md`·`AGENTS-BOUNDARY.md`·`WIKI.md`).

## Constraints
지운 규칙마다 **살아남는 자리를 `grep` 출력으로 보인다** — 못 대면 중복 삭제가 아니라 규칙 폐기이고 별도 승인이다 · `implement/SKILL.md` 의 「멈추는 넷」은 DESIGN 이 의도적 이중화로 이미 지목해 유지한다 · 회귀 감시 축 신설은 다음 회차다 · 안전 임계 hook 넷의 차단 동작은 건드리지 않는다 · 워킹트리 CRLF · `llm-wiki/references/*.md` 를 고치면 조건부 참조 표 기록값을 같은 task 에서 갱신한다.

## Open questions
없음.
