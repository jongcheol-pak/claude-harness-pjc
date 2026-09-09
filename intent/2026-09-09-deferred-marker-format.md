# Intent: Deferred 마커 서식 고정
Author: 사용자. Status: approved.

## Problem

`plan.md` 의 `## Deferred / Follow-up` 항목이 `- **`[등재]` 제목**` 처럼 **볼드로 시작**하는데, 그것을 읽는 정규식 넷(`session-context.ps1` 의 skip 3 + `check-harness-consistency.py` 의 `LEDGER_MARKER_RX`)은 전부 `- ` 바로 뒤에 마커가 오는 형태만 받는다. 그래서 hook 은 판정을 마친 9건을 **「Deferred 미판정 9건」으로 틀리게 출력**했고, 검사기 축 ⑪ 「등재 마커 실재」는 이번 회차의 등재 4건을 **0항목**으로 세어 통째로 침묵했다. 지금 하는 이유는 둘 다 2026-09-09 에 실제로 관측됐고(대장 `:13`), 침묵하는 축은 다음 회차의 이관 누락을 그대로 통과시키기 때문이다.

## Proposed outcome

`plan.md` 의 Deferred 항목 서식이 `- `[등재]` **제목** — 본문` 으로 규약에 고정되고, 그 서식을 벗어난 줄을 검사기가 **서식 위반으로 잡는다**. 실 레포에서 축 ⑪ 의 항목 수가 0 이 아니게 되고, hook 의 「미판정」 계수가 판정 완료 항목을 세지 않는다.

## Affected users and systems

다음 회차를 여는 세션(hook 계수를 읽는 사람)과 완료 시점의 `pjc:implement`. 걸리는 것은 `plan/references/deferred-rules.md` · `plan/references/plan-template.md` · `plugins/pjc/evals/check-harness-consistency.py` 와 그 골든(`cases.json` · `fixtures/minimal-repo/`) · `hooks/evals/scenarios/session-context.ps1` 이다.

## Constraints

정규식 넷은 고치지 않는다 — 서식 쪽에서 닫는다. 대장의 과거 문면은 손대지 않는다(이력 기록이다). 검사기를 고치므로 **그 검사기를 재는 골든 케이스를 함께 옮긴다**.

## Open questions

없음.
