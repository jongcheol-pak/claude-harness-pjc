# Intent: 체크포인트 커밋이 절차 본 커밋을 삼키는 것을 막는다
Author: 사용자. Status: approved.

## Problem

원문 요청: *"ⓑ로 계획 세워줘"* — 위키 스킬 개선 큐(`skill-feedback.md`)의 `[SKILL-IMPROVE]` 항목 1건을 처방 후보 ⓑ로 처리하라는 것이다. `lint.py` 의 체크포인트 커밋이 `git add -A` 로 그 시점의 모든 미커밋 변경을 담아, 절차가 편집한 산출물이 `문서: auto-split 직전 체크포인트` 라는 이름의 커밋에 들어가고 절차 본 커밋에는 그 뒤 손댄 것만 남는다. 커밋을 절차 단위로 나눈 목적(「무엇이 무엇을 바꿨는지 이력에서 읽히게」)이 그 자리에서 깨진다. **지금 하는 이유는 2회 재발했기 때문이다** — 2026-09-16 Maid ingest 두 번(6파일 삼킴 · 체크포인트 `8e87b13` 대 본 커밋 `fb85314`), 그리고 그 경로를 재는 골든이 하나도 없다.

## Proposed outcome

절차가 편집한 파일은 그 절차의 이름이 붙은 커밋에 담기고, 체크포인트 커밋에는 처방 자신이 만든 변경만 남는다. 규약을 어겨 미커밋 편집을 남긴 채 처방을 호출하면 스크립트가 수행을 거부하고 그 사실을 알린다.

## Affected users and systems

위키 쓰기 세션(절차 A·B·F)을 쓰는 사용자. 걸리는 것은 `llm-wiki` 스킬의 절차 문서 셋(`procedures-content.md` B-3·A-4 · `procedures-ops.md` F-2), 커밋 규약(`wiki-ops-rules.md` 「git 자동 반영」), `scripts/lint.py` 의 `auto_split`·`apply_fixes` 진입부, 그리고 골든 러너·케이스(`evals/run_lint_evals.py`·`lint-cases.json`)다.

## Constraints

- 처방 후보 ⓐ(체크포인트를 실제 처방이 있을 때만 생성)는 채택하지 않는다 — 2회차 관측이 그것으로 막히지 않음을 실증했다.
- 탈출 플래그(`--allow-dirty` 류)를 두지 않는다 — 두면 그것이 기본 경로가 된다.
- 「pass 당 1회 체크포인트」 격리 규약은 유지한다 — 합치면 재점검 pass의 실패가 본 pass 성공분을 되돌린다.
- 비 git vault·`--dry-run` 경로의 동작은 바꾸지 않는다.

## Open questions

없음
