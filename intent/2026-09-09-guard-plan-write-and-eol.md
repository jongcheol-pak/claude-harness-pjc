# Intent: plan.md 쓰기 차단 · 저장 직후 줄바꿈 경고
Author: 사용자. Status: approved.

## Problem

회차 50 이 대장에 올린 2건 모두 **규약은 이미 있는데 기계가 지키게 하지 않는 형태**다. ① `plan/SKILL.md` 「Step 5」가 *"`plan.md` 는 `Write` 1회로 쓰고 `sed`·`cp`·python 으로 후편집하지 않는다"* 를 적어 두었으나, 회차 50 이 그것을 어겨 `plan.md` 를 29줄만 남기고 잘랐고 — `plan.md` 는 gitignore 라 `git show` 로 복구할 수 없다 — 그사이 두 커밋이 잘린 plan 위를 지나갔다(검사기·커밋 차단 hook 전부 green, 완료 리뷰만이 잡았다). ② `AGENTS.md` 「줄바꿈」이 *"`Edit` 도구가 파일 전체를 LF 로 바꿔 놓는다 — 편집 후 `git ls-files --eol` 로 확인"* 을 적어 두었으나, 같은 회차가 `intent/` 파일을 쓰고 확인하지 않아 「줄바꿈 정합」 축이 red 를 냈다. 지금 하는 이유는 둘 다 사람의 주의력에 기대는 상태이고, ①은 복구 불가능한 유실을 낳기 때문이다.

## Proposed outcome

`plan.md` 를 대상으로 하는 **쓰기 명령**이 `guard-bash` 에서 `exit 2` 로 막히고(읽기는 통과한다), git 추적 파일을 `Write`·`Edit` 로 쓴 직후 워킹트리가 LF 면 `post-write-checks` 가 경고한다. 둘 다 골든 케이스가 오차단·오탐 0 을 함께 실증한다.

## Affected users and systems

이 레포에서 작업하는 모든 세션. 걸리는 것은 `plugins/pjc/scripts/guard-bash.ps1` 과 그 근거 `rules/bash-guard-rationale.md` · `plugins/pjc/scripts/post-write-checks.ps1` 과 `rules/post-write-rationale.md` · 두 hook 의 골든 시나리오 · 차단 경로 커버리지 검사기 · Deferred 대장이다.

## Constraints

차단은 `guard-bash`(`Bash|PowerShell` 매처)에 둔다 — `guard-write` 는 `Write|Edit|MultiEdit` 매처라 스크립트 경로를 보지 못한다(대장의 처방 후보가 hook 을 잘못 지목했다). **읽기 명령은 통과해야 한다** — `grep`·`cat`·`sed -n`·`awk`, 그리고 `plan.md` 를 읽어 **다른 파일로** 내보내는 형태까지. LF 경고는 `llm-wiki/evals/fixtures/` 를 제외한다(그 18건은 테스트 입력이라 LF 가 의도된 것이다).

## Open questions

없음.
