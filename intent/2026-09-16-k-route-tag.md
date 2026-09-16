# Intent: `[K-ROUTE]` 태그 신설과 lint 집계
Author: 사용자. Status: approved.

## Problem

원문 요청: *"[K-ROUTE] 태그 신설 · lint 집계를 진행해줘."*

「절 단위 읽기」가 전문 Read 로 폴백한 사실 — 곧 **절 제목이 라우터 역할을 못 했다는 신호** — 는 지금 `plan.md` 의 Investigation Log 에만 남는데 그 파일은 `.gitignore` 라 **회차가 끝나면 사라진다**(`plugins/pjc/skills/WIKI.md` 「절 단위 읽기」 마지막 불릿). 회차 71 이 이 태그를 만들려다 3라운드 연속 BLOCKER 를 냈고, 회차 72 가 그 원인(태그 열거 전수를 재는 기계 검사 부재)을 축 ㉑ 으로 닫았다. **지금 하는 이유는 그 착수 조건이 충족됐기 때문이다** — 축 ㉑ 이 열거 자리 18 과 수 표현 자리 11 을 전수로 낸다.

## Proposed outcome

`pending.md` 가 여섯 태그를 담고, 폴백이 일어나면 `- [날짜] [K-ROUTE] {프로젝트}: {경로}#{절 제목} — {사유}` 1줄이 큐에 쌓인다. 위키 세션이 vault 경로 항목을 소비해 그 절 제목을 고치고, repo 경로 항목은 하네스 세션이 받는다. `lint.py` 가 그 잔량을 태그별로 세고 형식 위반을 잡는다.

## Affected users and systems

pjc 하니스를 쓰는 모든 세션(폴백은 계획·디버깅 세션에서 일어난다)과 LLM WIKI vault. 걸리는 자산은 `skills/llm-wiki/references/**`·`llm-wiki/scripts/lint.py`·`skills/WIKI.md`·`skills/plan/SKILL.md`·`evals/check-harness-consistency.py`·`skills/evals/check_wiki_circuit.py`·`README.md`·`docs/harness-conventions.md` 와 두 골든 자산(`evals/fixtures/tagenum-*`·`llm-wiki/evals/lint-cases.json`).

## Constraints

축 ㉑ 은 **자기 소스와 자기 근거 문서도 세므로 acceptance 를 절대 수로 잡지 않고 「MISMATCH 0」으로 잡는다**. 정본 집합이 셋이라(pending 5 · skill-feedback 1 · 전체 6) 태그를 pending 에 넣으면 **세 상수가 함께 움직인다**. 골든 케이스 수는 늘리지 않는다 — 늘리면 `harness-conventions.md` 의 기준선 기재까지 함께 움직인다.

## Open questions

없음.
