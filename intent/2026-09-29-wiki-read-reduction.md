# Intent: 코드 세션의 위키 조회에서 헛읽기를 걷어 낸다
Author: jongcheol-pak. Status: approved.

## Problem
원문: *"하니스 스킬에서 작업시 위키를 검색 하는데 불필요한 부분이 있는지 검색시 불필요한 내용이 같이 포함 되는지 등 검토해줘"* → 검토 뒤 *"대장 항목으로 일괄 계획 세워줘"*. 검토가 실측으로 드러낸 것: 하니스 레포 계획은 구조적으로 0건인 `pending.md` 조회를 매번 하고(31행 중 13행), 단일 절 하위 문서는 절 단위 읽기가 통째 읽기가 되며, 호출측은 `WIKI.md`·`index.md`를 파일째 읽고, 절차 K의 vault 전체 grep 에 이력(`90_archive/`)·큐가 섞인다. 지금 하는 이유: 대장 「위키 읽기 대상 축소 판정」의 착수 조건이 2026-09-20 에 이미 충족됐다.

## Proposed outcome
하니스 규약이 위키를 필요한 만큼만 읽게 바뀐다 — 하니스 레포 계획의 `[PROJECT-FACT]` 조회 생략, 하위 문서 항목 단위 읽기, 제목만 보고 건너뛴 절과 라우터가 사용 기록 N 에서 빠짐, `WIKI.md` 를 호출자별 필요한 절만 읽음, `index.md` 절 단위 읽기, 전체 grep 의 이력·큐 제외, `lookup-rules.md` 의 낡은 배분 문면 교정. 대장 항목은 판정 결과와 함께 종결된다.

## Affected users and systems
`pjc:plan`·`pjc:implement`·`pjc:pjc-systematic-debugging` 을 돌리는 코드 세션. `plugins/pjc/skills/WIKI.md`·세 SKILL.md·`llm-wiki/references/lookup-rules.md`·`scripts/session-context.ps1`(압축 직후 조회 지시)·`docs/plans/` 의 대장과 사용 기록.

## Constraints
vault 는 읽기만 한다(쓰기는 llm-wiki 세션 몫). 함정 회로(기록 → 소비 → 조회)를 끊지 않는다. 정합 검사·위키 회로·hook 골든이 통과한다. 버전 커밋까지 하고 push·릴리즈는 별도 승인이다.

## Open questions
없음
