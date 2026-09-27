# Intent: 위키 ingest 가 찾은 레포 문서 드리프트 5건 수정
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
위키 ingest(2026-09-27)가 코드와 어긋난 레포 문면 5곳을 찾았다. 원문 요청: *"레포 문서 드리프트 5건 수정"*. 골든 러너 그룹 수, `session-context` 주석의 위키 신호 수, `deferred-rules` 의 하니스 검사기 전제와 긴 일화, 디버깅 스킬 description 의 「spec-compliance review」, 두 리뷰어의 헤딩 체계가 현재 코드·본문과 맞지 않는다.

## Proposed outcome
다섯 자리가 현재 코드·본문과 일치한다. 디버깅 description 변경은 트리거 eval(dbg)로 발동 경계가 유지됨을 확인한다. 레포 검사기는 착수 시점과 같은 green 이다.

## Affected users and systems
본인과 마켓플레이스 배포 사용자. `docs/golden-runner.md`, `plugins/pjc/scripts/session-context.ps1`·`session-wiki-signals.ps1`(주석)·`scripts/rules/wiki-signals-rationale.md`, `plugins/pjc/skills/plan/references/deferred-rules.md`, `plugins/pjc/skills/pjc-systematic-debugging/SKILL.md`(description), `plugins/pjc/agents/plan-reviewer.md`.

## Constraints
문면만 고친다(동작 변경 없음) · 판정 근거인 날짜 꼬리는 남긴다 · `.ps1` 은 UTF-8 BOM, 워킹트리 CRLF · description 은 트리거 eval 로 검증한다 · push·릴리즈는 별도 승인.

## Open questions
없음.
