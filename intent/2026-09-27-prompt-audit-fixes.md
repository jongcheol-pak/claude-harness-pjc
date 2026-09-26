# Intent: prompt-audit(Opus 5.5 기준) 발견 사항 수정
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
`/claude-api prompt-audit` 가 이 레포와 전역 설정에서 낡은 문면(이력 서술·중복 금지문·모순)과 전역 지침과의 충돌을 찾았다. 원문 요청: *"전체 수정해"*. 감사 직후라 근거가 살아 있는 지금 반영한다.

## Proposed outcome
레포의 `AGENTS.md` 이력 서술이 정본 문서로 옮겨지고, pjc 스킬 5종·`plan-reviewer` 의 지적 문면이 고쳐지며, 전역 `CLAUDE.md` 「종전대로」 4곳과 개인 스킬 9개의 감사 hunk·전역 지침 충돌 5건이 해소된다. 레포 검사기는 착수 시점과 같은 green 이다.

## Affected users and systems
본인과 마켓플레이스 배포 사용자. `AGENTS.md`·`docs/harness-conventions.md`, `pjc:implement`·`pjc:plan`·`pjc:llm-wiki`·`pjc:record-project-fact`·`pjc:pjc-systematic-debugging`·`plan-reviewer`, 레포 밖 `~/.claude/CLAUDE.md`·`~/.claude/skills/` 개인 스킬 9개(모든 프로젝트에 로드).

## Constraints
「멈추는 넷」·「목록 밖의 넷」 이름과 구조, 판정 근거인 날짜 꼬리는 유지한다(2026-09-26 intent) · `implement` 진행 보고 억제 문구는 유지한다 · pjc `description` 은 고치지 않는다 · 레포 밖 파일은 고치기 전에 시스템 임시 폴더로 백업한다 · 추정 사실은 공식 문서 대조 후 고친다 · 워킹트리 CRLF · push·릴리즈는 별도 승인.

## Open questions
없음.
