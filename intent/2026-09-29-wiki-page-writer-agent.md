# Intent: llm-wiki 병렬 분업용 전용 에이전트 (sonnet · effort 고정)
Author: 사용자. Status: approved.

## Problem
원문: *"위키/하니스 스킬에서 opus 모델만 사용하고 있는데 서브 에이전트 사용시 sonnet 모델을 사용할 부분이 있는지 검토"* → *"그럼 3번으로 해서 effort를 고정해야 되는거 아닌가?"*. llm-wiki 병렬 분업(wiki-schema §9)의 에이전트는 모델 지정이 없어 호스트(Opus)와 세션 effort 를 그대로 물려받는다 — 명확히 정의된 대량 작업에 Opus 비용이 들고, Agent 호출로 `sonnet` 만 넘기면 effort 는 Opus 에 맞춘 세션 값을 따라가 고정되지 않는다. §9 는 「담당 페이지를 쓴다」와 「파일 생성 금지·텍스트로만 보고」가 서로 부딪힌다.

## Proposed outcome
`plugins/pjc/agents/` 에 `model: sonnet` · `effort: high` 를 고정한 위키 페이지 작성 에이전트가 있고, §9 가 그 에이전트를 호출 대상으로 지목하며, 에이전트가 담당 페이지를 직접 쓰는 쪽으로 §9 의 모순이 풀린다. 에이전트 목록을 담은 문서·검증 스크립트가 새 에이전트를 안다.

## Affected users and systems
위키 세션에서 병렬 분업을 쓰는 호스트(메인 세션). `plugins/pjc/agents/` · `llm-wiki/references/wiki-schema.md` §9 · `wiki-ops-rules.md` · `validate.ps1` · `README.md` · `plugin.json`·`marketplace.json` · `docs/harness-conventions.md` 구조도.

## Constraints
경로 표기·섹션 순서·예산 같은 형식 규칙은 schema 가 정본이고 에이전트 본문에 복제하지 않는다(에이전트 본문은 소유권·공유 파일 금지·소스 실제 Read·반환 형식 같은 불변만). 리뷰어 2종은 Opus 를 유지한다. 에이전트 정의는 6,000자 이내.

## Open questions
없음
