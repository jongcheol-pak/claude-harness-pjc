# Intent: 하니스 스킬·훅의 중복·결함·모델 인지 문면 정리와 AGENTS.md 목차 주입 전환
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
직접 검토(스킬 미사용) 결과 파일 단위 고아는 0건이나 규칙 단위로 정리할 것이 남았다 — 세션마다 주입되는 줄이 글로벌 지침에 없는 절 「프로젝트 맥락은 위키를 먼저 본다」를 가리키고, Claude Code 2.1.283 이 `AGENTS.md` 를 자체 로드하는데 `session-context` hook 이 같은 전문(약 10.8KB)을 또 주입한다. 스킬 사이 중복·모델이 이미 아는 일반론·긴 실측 일화도 상시 로드 문서에 남아 있다. 원문 요청: *"하네스 스킬/훅에서 중복, 불필요한 규칙, opus 5.5에서 알고 있는 내용, 고아 규칙 등 삭제해도 되는 내용 검토"* → *"이대로 계획 세워줘"*.

## Proposed outcome
결함 2건이 고쳐지고, 세션 시작 주입에 `AGENTS.md` 전문 대신 절 목차가 실리며, 지운 문면마다 살아남는 자리가 있거나 사용자가 승인한 폐기 목록에 있다. 전 검사기가 착수 시점과 같은 green 이다.

## Affected users and systems
본인과 마켓플레이스 배포 사용자. `session-context.ps1`·`session-wiki-signals.ps1`·그 골든·근거 문서, `pjc:plan`·`pjc:implement`·`pjc:pjc-systematic-debugging`·`pjc:record-project-fact` 문면, 리뷰어 2종, `WIKI.md`, README.

## Constraints
글로벌 지침과 겹치는 규칙·「멈추는 넷」·「커밋」·`report-format.md` 보고 항목·5.5 가이드 원문·`code-style.md`·`AUTHORING.md` 는 유지한다 · 차단 hook 4종은 건드리지 않는다 · 이력 서술은 날짜 꼬리를 남겨 판정 근거를 지우지 않는다 · 워킹트리 CRLF.

## Open questions
없음.
