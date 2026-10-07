# Intent: llm-wiki 병렬 분업 발동 기준
Author: 사용자. Status: approved.

## Problem
원문: *"병렬 분업은 언제 쓰는 게 기준이야?"* → *"그럼 high 유지하고 병렬 분업 기준만 추가해줘"*. wiki-schema §9 는 병렬 분업의 「방법」(소유권·공유 파일·위임 프롬프트)만 정하고 「언제 쓰는가」가 없어, 분업 여부가 호스트 재량이다 — 대량 작성을 Opus 본체가 직접 하거나 소량 작성에 위임 비용을 들이는 것이 판정 없이 갈린다.

## Proposed outcome
§9 에 발동 기준이 한 곳에 있다: 이번 세션이 내용을 작성할 페이지(새로 쓰기·전면 재작성·델타 갱신을 가리지 않음, 공유 파일 제외)가 3개 이상이고 담당을 겹치지 않게 나눌 수 있으면 `pjc:wiki-page-writer` 로 반드시 분업하고, 미달이면 호스트가 직접 쓴다. 쓰기 절차가 실제로 읽는 요약(`wiki-ops-rules.md`)과 README 에이전트 표가 같은 기준을 말한다.

## Affected users and systems
위키 쓰기 세션의 호스트(메인 세션). `plugins/pjc/skills/llm-wiki/references/wiki-schema.md` §9 · `wiki-ops-rules.md` · `schema-rationale.md` · `README.md`.

## Constraints
`wiki-page-writer` 의 `model: sonnet` · `effort: high` 를 유지한다. 기준의 정본은 §9 하나다. 새 문면은 `check_consistency.py` 축 ⑪ 조건어(「초과」·「넘」 등)를 쓰지 않는다.

## Open questions
없음
