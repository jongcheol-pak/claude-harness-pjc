# Intent: 큐 3항목 — 사용 기록 필드 · 분할 조각 허브 오식별 · `[다음 회차]` 근거
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문 요청: *"큐에 등록된 수정항목 검토"* → 검토 결과 권장 순서(A-3 → B → A-1 → A-2)를 사용자가 골랐고, 범위는 앞 셋으로 한정했다. ⓐ **A-3**: `wiki-usage.md` 착수 조건(행 5개)이 이미 8행으로 지나갔는데 아무도 재지 않았고, 행이 `읽음 N절`만 적어 **안 쓰인 절이 무엇인지가 기록에 없어** 감사 선택지 2(읽기 대상 축소)를 판정할 데이터 자체가 없다. ⓑ **B**: `session-wiki-signals.ps1` 의 허브 탐색이 분할 조각(`karina-2.md` 등)을 부모보다 먼저 열거하고 `repo_url` 이 같아 그것을 허브로 확정해, 조각의 낡은 `synced_commit` 으로 오경보를 냈다(실측: 「130커밋 미반영」, 실제 0). ⓒ **A-1**: `[다음 회차]` 마커가 실제 상태와 갈려도 재는 축이 없어, 회차 66 이 이미 완료·릴리즈된 회차를 「미완」으로 읽고 계획을 시작했다.

## Proposed outcome
① `wiki-usage.md` 행이 **미반영 절 이름**을 담아 다음 5회차 뒤 축소 대상을 실제로 고를 수 있다. ② hook 이 분할 조각을 허브 후보에서 빼 **부모 허브의 값**으로 뒤처짐을 재고, `procedures-content.md` B-2 1 이 조각 frontmatter 를 동반 갱신해 애초에 갈리지 않게 한다. ③ `[다음 회차]` 항목에 근거 필드가 필수가 되고 `check-harness-consistency.py` 가 그 부재를 잡는다.

## Affected users and systems
이 하니스로 계획·구현하는 모든 레포 세션(사용 기록 1줄이 길어지고, 뒤처짐 알림이 분할된 프로젝트에서 정확해진다). 걸리는 자산: `plugins/pjc/skills/WIKI.md` · `docs/plans/wiki-usage.md` · `docs/plans/deferred.md` · `plugins/pjc/scripts/session-wiki-signals.ps1` · `plugins/pjc/hooks/evals/scenarios/session-context.ps1` · `plugins/pjc/skills/llm-wiki/references/procedures-content.md` · `plugins/pjc/skills/plan/references/deferred-rules.md` · `plugins/pjc/evals/check-harness-consistency.py` · `plugins/pjc/evals/cases.json` · `docs/harness-conventions.md` · `README.md`.

## Constraints
- 감사 선택지 3(뒤처짐 임계를 회차 수로)은 **기각**이 사용자 결정이다(2026-09-19) — 「회차」의 기계 경계가 하니스 레포 `intent/` 뿐이라 범용 구현이 불가하고, 관측된 오경보의 원인이 임계가 아니라 조각 오식별이었다.
- `lint.py` §7-26 은 고치지 않는다 — `repo_root_for_hub()` 가 본문 `## 레포 정보` 를 요구해 조각을 이미 skip 한다(큐 항목의 ⓑ 진단이 그 자리에서는 틀렸다).
- 안전 임계 hook 넷의 차단 동작을 건드리지 않는다. `session-wiki-signals.ps1` 은 그 넷이 아니다.
- 분할 조각의 판정 신호는 새로 만들지 않고 `wiki-schema.md` §4 의 `> 상위 문서:` 를 쓴다(lint §7-30ⓔ 가 이미 그것을 쓴다).

## Open questions
없음.
