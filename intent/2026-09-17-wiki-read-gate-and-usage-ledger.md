# Intent: 위키 읽기 게이트와 회차별 사용 기록
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문 요청: *"하니스에서 위키를 제대로 사용하고 있나? 불필요하게 추가로 읽고만 있는지 실제로 도움이 되는지 확인해줘"* → 감사 결과의 선택지 1번(*"읽기 게이트를 검사 가능하게 만들고 재측정"*)을 사용자가 골랐다. 감사 실측: 현 회차 `plan.md` 의 Investigation Log 에 `위키 참조` 행이 0건인 채 계획 리뷰·승인·구현이 통과했고(`WIKI.md` §1 「기록 의무」 위반), `plan-reviewer` 는 「Log 에 위키 함정이 있는데 배분이 없으면」만 지적해 읽기를 통째로 건너뛰면 통과한다. `intent/` 36건·`notes-archive/` 3건 어디에도 위키 참조 기록이 없어 **효용을 잴 데이터 자체가 없다**. `plan.md` 는 gitignore 라 회차가 끝나면 그 기록도 사라진다.

## Proposed outcome
① `plan-reviewer` 가 Investigation Log 에 `위키 참조` 행이 없는 계획을 지적한다(읽었든 건너뛰었든 행은 남는다). ② 계획 단계의 위키 참조 기록이 **절 단위로 「어느 task 함정에 배분됐는가 / 해당 없음」**을 담는다. ③ `pjc:implement` 완료 시점에 커밋되는 `docs/plans/wiki-usage.md` 에 회차당 1줄(읽은 절 수·배분 건수·실행 중 실제 걸린 건수·전문 폴백 절 수)이 쌓여, 3~5회차 뒤 「읽고만 있는가 / 도움이 되는가」를 그 파일만 보고 판정할 수 있다.

## Affected users and systems
이 하니스로 계획·구현하는 모든 코드 레포 세션(계획 리뷰가 한 항목 늘고, 완료 시 1줄 append 가 는다). 걸리는 자산: `plugins/pjc/agents/plan-reviewer.md` · `plugins/pjc/skills/WIKI.md` · `plugins/pjc/skills/implement/SKILL.md` · 신설 `docs/plans/wiki-usage.md` · `README.md` · `plugins/pjc/scripts/guard-write.ps1`(진단 문구 1줄 — `docs/plans/` 를 「Deferred 대장 전용」으로 서술하는 자리).

## Constraints
- 기록 위치는 사용자 결정(2026-09-17): `docs/plans/wiki-usage.md` 에 완료 시점 1줄 append. 커밋 본문 방식은 쓰지 않는다.
- `guard-write.ps1` 의 차단 동작은 건드리지 않는다 — 문구 1줄만 고치고 hook 골든·차단 커버리지로 실증한다.
- 위키 회로 12단계(`check_wiki_circuit.py`)의 앵커 문면을 유지한다.
- 이 회차는 측정 장치만 세운다 — 위키 읽기 대상(conventions.md 등)을 줄이거나 뒤처짐 임계를 바꾸지 않는다(감사 선택지 2·3은 측정 뒤 판정).

## Open questions
없음.
