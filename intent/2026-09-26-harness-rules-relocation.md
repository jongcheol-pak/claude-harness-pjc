# Intent: 배포 스킬에 섞인 하니스 레포 전용 규칙을 레포 쪽으로 옮긴다
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
마켓플레이스로 배포되는 `pjc:plan`·`pjc:implement` 문면이 하니스 레포에만 있는 파일(`docs/harness-conventions.md`·`check-harness-consistency.py`·`docs/plans/deferred.md`)과 경로(`agents/*.md`·`skills/`)를 전제한다 — 다른 레포에서는 가리키는 대상이 없는 규칙이다. 직전 회차(v1.310.0)가 `[다음 회차]`로 미룬 항목이다. 원문: *"배포 스킬에 섞인 '하니스 레포 전용 규칙'(plan-template:113-115·149, implement:115, plan:26 의 docs/harness-conventions·check-harness-consistency·deferred.md 전제)을 옮긴다"*.

## Proposed outcome
배포 스킬에는 어느 레포에서나 성립하는 일반 문면만 남고, 하니스 전용 구체(3축 이름·검사기 축·⑤ 대상 경로·대장 경로)는 이 레포의 `AGENTS.md`·`docs/harness-conventions.md` 가 정본으로 갖는다. 하니스 레포에서의 판정(검사기 축 ⑲·리뷰어의 ⑤ 검사)은 그대로 돈다.

## Affected users and systems
본인과 마켓플레이스 배포 사용자. `plan-template.md`·`plan/SKILL.md`·`implement/SKILL.md`·`deferred-rules.md`, 레포 `AGENTS.md`·`docs/harness-conventions.md`, 검사기 축 ⑲의 주석·근거 문서.

## Constraints
3축은 일반형 1불릿으로 치환(사용자 선택) · ⑤는 범주를 일반어로, 경로는 레포로(사용자 선택) · ⑤ 번호와 근거 요구(놓친 인스턴스·구조 동형·삭제형)는 리뷰어 2종이 검사하므로 유지 · 검사기 판정 로직은 바꾸지 않는다 · 워킹트리 CRLF.

## Open questions
없음.
