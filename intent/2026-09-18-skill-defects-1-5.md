# Intent: 하니스 스킬 결함 1~5 수정
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
2026-09-18 스킬 전수 검토(6개 읽기 전용 에이전트 + 기계 검사기 4종 통과)가 의미 결함 18건을 냈고, 그중 1~5는 산출물이 실제로 틀리게 나오는 것이다 — `relocate-agents.py`가 파일 부재를 rc 1(원복)로 내고, `KEEP_SECTIONS`에 `## OS/플랫폼`이 없어 승인 없는 Step 5가 잔류 절을 옮길 수 있고, plan 템플릿에 `> BASE:` 줄이 없어 완료 리뷰가 diff 범위를 잃고, `WIKI.md`의 `[PROJECT-FACT]` 형식에 `({근거})` 꼬리가 없어 소비 후 lint §7-34 미보유로 영구 집계되고, `[DECISION]` 배치 큐잉의 호출 지점이 plan·implement 어디에도 없어 pending.md의 `[DECISION]`이 0건이다. 원문 요청: *"결함 1~5부터 고치는 plan 세워줘"*. 지금 하는 이유: 검토 직후라 근거 실측이 손에 있고, 5건 모두 정본이 이미 있어 처방이 정해져 있다.

## Proposed outcome
다섯 자리가 각자의 정본(docstring · AGENTS-BOUNDARY · intent-rules · queue-rules K 5-3 · K 5-2 트리거 선언)과 같은 값을 내고, 그 각각을 재는 골든·grep이 있어 재발이 기계로 잡힌다.

## Affected users and systems
하니스 레포 세션(pjc:plan · pjc:implement · pjc:record-project-fact Step 5) · 코드 세션이 읽는 `skills/WIKI.md` · `relocate-agents.py`와 그 골든 러너 · `docs/harness-conventions.md` 「검증 명령 상세」 기준선.

## Constraints
hook 스크립트·골든 시나리오는 손대지 않는다(결함 5는 사용자 선택 「호출 지점 추가」) · DESIGN §1 형식(규칙 1줄 + 근거 1문장)과 §2 「한 사실은 한 곳」 · 워킹트리 CRLF · 케이스 수를 바꾸면 같은 task에서 「검증 명령 상세」 기준선을 갱신한다.

## Open questions
없음.
