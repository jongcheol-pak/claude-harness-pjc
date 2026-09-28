# Intent: llm-wiki 스킬 검토 결과 개선 — 동작 결함·문서 충돌·고아·중복
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
llm-wiki 스킬 전수 검토(2026-09-28, 세 축 병렬)에서 다음이 나왔다. 원문 요청: *"위키 스킬 고아 항목, 중복 등 개선할 부분 검토"* → *"권장 순서대로 계획 세워줘"*.
- 동작 결함 2건: `SKILL.md` 의 쓰기 규칙 라우팅 grep 이 0줄을 내고, `lint.py` `--fix` 쓰기 경로의 섹션 경계가 읽기 경로와 갈렸다.
- 한쪽만 고쳐져 어긋난 문서 사본 다수: §7-36 누락, 개수 서술, 허브 분할 주체, 백업 조건, §7-30 범위, 정본 순환, 절차 H 문구, 끊긴 번호 참조, 안전장치 서술(git 체크포인트 누락), lint 폴백 적용 목록, 낡은 크기 서술, rationale 포인터 누락 절, 규칙 번들 `version` 미갱신.
- 고아: 러너 없는 `evals/evals.json`, 죽은 케이스 옵션·변수, 골든 공백 §7-11·§7-17.
- 가드 없는 중복 사본.

골든(135/135 · 257항목)은 이것을 재지 못한 채 green 이다.

## Proposed outcome
- 결함 2건이 고쳐지고 각각을 재는 케이스(또는 실행 확인)가 있다.
- 충돌 사본이 정본과 일치한다.
- `check_consistency.py` 가 「lint.py 의 §7-N ⊆ schema §7」을 대조해 같은 누락이 재발하면 red 를 낸다.
- `evals.json` 의 미커버 케이스가 `trigger-cases.json` 으로 옮겨져 실제로 돌고, 원본은 삭제된다.
- `migrate-index-labels.py` 는 레거시 vault 전용으로 표기돼 남는다.
- 가드 없는 중복 사본은 정본 포인터로 바뀐다.
- 기존 검증이 전부 green 이다.

## Affected users and systems
본인과 마켓플레이스 배포 사용자(위키 세션 에이전트). `plugins/pjc/skills/llm-wiki/`(SKILL·references·scripts/lint.py·evals), `plugins/pjc/skills/WIKI.md`, `plugins/pjc/skills/evals/trigger-cases.json`, `docs/harness-conventions.md`(기준선·임계표·검사기 설명), `plugins/pjc/skills/AUTHORING.md`(케이스 수).

## Constraints
- 워킹트리 CRLF · `.ps1` BOM 규약을 지킨다.
- `lookup-rules.md` 를 고치면 임계표를 같은 task 에서 갱신한다.
- 파일 삭제(`evals.json`)는 승인 항목이다.
- push·릴리즈는 별도 승인이다.
- 트리거 eval 은 wiki 필터로만 1회 돈다(모델 호출 비용). 실패한 케이스는 그 케이스만 1회 더 돌려 재현을 확인한다.

범위 밖:
- `wiki-schema.md` 3분할(다음 회차)
- `rollover_*` 2회 중복 공통화(기준 3회 미달)
- `lint.py` `main()` 구조 개편

## Open questions
없음.
