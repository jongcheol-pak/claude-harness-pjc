# Intent: 문서 예산 처방 규약화·분할 · 완료 보고의 등재분 한정
Author: 사용자. Status: approved.

## Problem

원문 요청: *"스킬 문서에 내용이 추가되면 예산을 넘었다고 분할을 할지 아니면 내용을 뺄지 정해야 하는데 github에서 하니스 스킬이나 다른 스킬들은 어떻게 하고 있는지 검토해줘"* → 검토 결과를 받고 *"진행하고, 추가로 작업 완료시 남은 이슈에 보면 작업 중 발생한 문제를 수정해서 대장에 추가하지 않았다고 미등재 항목을 표시하는데 이런건 사용자는 관심 없음, 실제 등제한 항목만 표시하고 미등재한 항목은 표시하지 않도록 함."*

후속 지적: *"지금 상한을 하면 추후에는 또 상한을 하나? 아니면 분할 할 건가?"*

【1】 초과 처방이 두 문서로 갈려 있다 — `DESIGN.md` 4절은 *"문장을 줄이지 말고 항목을 뺀다"*(빼기)이고 `AUTHORING.md:49`는 *"초과하면 저빈도 상세를 `references/`로 분리"*(분할)다. `AUTHORING.md:8`이 `DESIGN.md` 우선을 선언하므로 실효 규칙은 「빼기」이고, 업계 공통(Anthropic best-practices · skill-creator · mgechev/skills-best-practices)의 「분할 먼저, 삭제는 마지막」과 반대다. 더 큰 결함은 **상한 상향에 정지 규칙이 없다**는 것이다 — 이 레포는 가이드 문서는 감축으로, hook 스크립트는 상향(15,000→25,000)으로 대응한 이력이 둘 다 있고 어느 쪽을 쓸지 정한 규약이 없다. 대장 `:107`이 같은 결함을 이미 등재해 두었다(*"상한 열이 「현행 +10%」면 파일이 커지면 상한이 따라 오른다"*).

【2】 최종 보고의 「남은 이슈」가 `[미등재:이번 회차가 처리]`처럼 **대장에 올리지 않기로 판정한 항목까지** 화면에 낸다. 사용자가 읽는 자리에는 실제로 등재된 것과 다음 회차가 이어받을 것만 있으면 된다.

**지금 하는 이유**: `DESIGN.md`가 12,974 / 13,000 B(여유 26 B)로 다음 개정 자체가 막혀 있어, 규약을 고치려면 그 문서의 크기 문제를 먼저 풀어야 한다.

## Proposed outcome

문서 예산의 정본이 `plugins/pjc/skills/BUDGET.md` 하나가 되고, 그 문서가 초과 시 처방을 3단 순서(① 모델이 이미 아는 설명·중복 삭제 → ② `references/` 이관 → ③ 항목 제거)로 규정하며 **상한 상향을 처방에서 명시적으로 제외**한다. `DESIGN.md`는 그 규약의 첫 적용 대상으로 4절을 넘겨주고 포인터만 남긴다. 최종 보고의 「남은 이슈」에는 `[등재]`와 `[다음 회차]`만 실린다.

## Affected users and systems

이 하니스로 작업하는 본인. 걸리는 자산: `skills/DESIGN.md` · 신설 `skills/BUDGET.md` · `skills/AUTHORING.md` · `skills/implement/references/report-format.md` · `skills/plan/references/plan-template.md` · `evals/check-harness-consistency.py` · `evals/fixtures/minimal-repo/**` · `scripts/rules/plan-exempt-rationale.md` · `docs/harness-conventions.md` · `AGENTS.md`.

## Constraints

단위는 **바이트 유지** — 검사기가 바이트로 돌고 한글은 줄 길이 편차가 커서 줄 수가 부정확하다. `references/*.md` 게이트는 **15,000 B 유지**(초과 실해가 관측된 적이 없고, 같은 회차에 「상향은 처방이 아니다」를 쓰면서 값을 올리면 신호가 엇갈린다). `plan.md`의 마커 체계 4종과 `session-context` hook의 미판정 계수는 **불변** — 바꾸는 것은 화면 보고뿐이다. hook 신설 없음.

## Open questions

없음.
