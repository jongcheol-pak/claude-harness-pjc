# Intent: llm-wiki schema §7 ↔ F-1 통합 (§7 을 schema-lint.md 로)
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원 요청 *"위키 스킬 고아 항목, 중복 등 개선할 부분 검토"* → *"권장 순서대로 계획 세워줘"* 의 마지막 `[다음 회차]` 항목이다. 코어 `wiki-schema.md`(77,287 B)의 §7(약 23.6KB)은 lint 세션만 쓰는데 코어에 남아 있고, `procedures-ops.md` F-1 이 같은 36번호를 따로 들고 있어 `check_consistency` ⑦ 이 두 목록의 번호 1:1 을 손 대조 대신 지켜 왔다. 직전 회차(`intent/2026-09-28-llm-wiki-schema-split.md`)에서 「코어에 둔다」로 제외했으나 이번 회차에 진행하기로 사용자가 정했다.

## Proposed outcome
§7 전체가 신규 `references/schema-lint.md`(`## 7. Lint 워크플로우`)에 있고, 각 검사 항목이 수행 주체 태그(`[기계]`/`[에이전트]`)를 직접 달아 F-1 은 그 파일을 가리키는 포인터만 남는다 — 검사 목록은 하나다. 코어 목차의 「파일」 열이 §7 을 새 파일로 라우팅하고, `wiki-schema §7` 파일명 인용은 0건이며, ⑦ 은 번호 1:1 대신 「각 항목의 주체 태그와 머리 집계 문장이 맞는가」를 잰다. 기존 검증은 전부 green 이다.

## Affected users and systems
lint 세션(절차 F)을 도는 에이전트, 그리고 `check_consistency.py`·`lint.py`·`check-harness-consistency.py` 를 고치는 하니스 세션. 걸리는 시스템은 llm-wiki schema 번들 · `procedures-ops.md` · `check_consistency.py` 의 ⑥⑦⑧⑩⑪⑭⑮ 축 · 번들 구성을 서술한 사본들이다.

## Constraints
§ 번호·`§7-N` 이름·`lint-rationale.md` 「§7-N」 헤딩은 바꾸지 않는다. F-1 에만 있던 사실은 잃지 않는다. vault 페이지는 고치지 않는다.

## Open questions
없음
