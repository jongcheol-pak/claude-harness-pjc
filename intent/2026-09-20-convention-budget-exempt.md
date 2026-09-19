# Intent: convention 을 분할 처방에서 빼고 순번 접미 재분할을 막는다
Author: 사용자. Status: approved.

## Problem

위키 비용 최적화 2회차다. 사용자 요청 원문: *"convention 타입을 예산 대상에서 제외한다 — `lint.py:563` 의 `stage=2 if typ == "convention" else 1` 특례 제거. 사라지는 것: ⓑ 갈래(convention 전용 80% WARN) · ⓔ 구역화(세션 손작업 전부) · stage=2 특례 · convention 의 auto-split 경로"*, *"순번 접미 재분할 금지 — `conventions-verification-2-2.md` 같은 3단 분할을 구조적으로 막는다"*. 지금인 이유는 실측이다 — convention 52페이지 중 8개가 이미 예산 80% 를 넘어 `--auto-split` 대기 중이고, 그중 `conventions-verification-2.md`(96%)는 다음 실행에서 **`conventions-verification-2-3.md` 라는 3단 분할**을 만든다. vault 전체 산문 분리 47건 중 24건(51%)이 convention 이라, 파편과 세션 손작업의 절반이 이 한 타입에서 나온다.

## Proposed outcome

`--auto-split` 이 convention 에 대해 0건을 내고, 「구역화 필요」 WARN 과 세션 구역화 처방이 규약·코드에서 사라진다. 12,000자 초과 WARN 1줄은 남아 크기 신호가 끊기지 않는다. 이미 `-N` 접미를 가진 페이지가 다시 분할되면 `-N-M` 이 아니라 루트 family 의 평면 형제 순번(`-K`)이 붙는다.

## Affected users and systems

위키 세션(`pjc:llm-wiki` 의 lint·`--auto-split` 수행자)과 절차 K 로 `conventions.md` 를 읽는 모든 코드 세션. 걸리는 코드는 `llm-wiki/scripts/lint.py`·`evals/check_consistency.py`·`evals/lint-cases.json` + `fixtures/`, 규약은 `references/wiki-ops-rules.md`·`wiki-schema.md`·`templates.md`·`lint-rationale.md`·`procedures-ops.md`, 기준선은 `docs/harness-conventions.md` 다.

## Constraints

롤오버 3종(`rollover_log`·`rollover_decisions`·`rollover_hub_changes`)은 그대로 둔다 — `log.md` 는 append-only 라 실제로 무한 증가하고 아카이브 포인터로 조회 경로가 실재한다. vault 의 분할 산물 56개를 되돌리지 않는다(96파일 편집이고 깨져 있지 않은 불변식을 손으로 다시 맞추는 순 리스크다) — 따라서 `## 하위 문서` 도달 경로 검사(§7-30 ⓑ)는 유지한다. 2026-08-13 「타입별 예산 값 상향」 기각과는 다른 결정이므로(값을 올리는 것이 아니라 처방을 뺀다) 결정 기록을 새 항목으로 남긴다.

## Open questions

없음.
