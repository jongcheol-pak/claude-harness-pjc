# Intent: ingest 가 대상 외 큐 항목을 묻지 않는다
Author: jongcheol-pak. Status: approved.

## Problem
원문: *"위키 업데이트 완료 후 다른 프로젝트도 해야 된다고 나오는 경우가 있는데 현재 프로젝트만 확인하면 되는데 왜 다른 프로젝트까지 확인하지? 이런 부분들이 모두 불필요한 작업 아닌가?"* → *"1번으로 계획 세워줘"*. ingest(B-1 0)가 공용 `pending.md` 의 타 프로젝트 항목을 보고하고 소비 동의를 물어, 이번 작업과 무관한 일이 할 일처럼 읽힌다. 미등록 프로젝트 등록 여부·스택 공통 항목 목적지 질문도 같은 자리에서 나온다.

## Proposed outcome
ingest 는 대상 프로젝트 항목만 처리하고, 그 밖의 항목(타 프로젝트·미등록·스택 공통)은 묻지 않고 완료 보고에 건수 1줄만 남긴다. 그 항목들의 소비·질문은 사용자가 요청한 lint(F-2)·큐 정리(M)에서만 일어난다.

## Affected users and systems
`pjc:llm-wiki` 로 위키 갱신을 돌리는 사용자. `llm-wiki/references/queue-consume-rules.md`(소비 규칙 정본)와 파생 서술(`SKILL.md`·`schema-types.md`·`queue-rules.md` 소비 측 두 문장·`scripts/lint.py` 잔량 라벨·`README.md`).

## Constraints
대상 외 항목을 큐에서 지우거나 표식을 붙이지 않는다(유실 방지). lint·큐 정리의 동의 게이트는 유지한다. 정합 검사·lint 골든·위키 회로가 통과한다. 버전 커밋까지 하고 push·릴리즈는 별도 승인이다.

## Open questions
없음
