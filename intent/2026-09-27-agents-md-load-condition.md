# Intent: session-context 가 AGENTS.md 자동 로드 조건을 판정한다
Author: 사용자. Status: approved.

## Problem
사용자 요청 *"공식 홈페이지에서 claude code 최신 업데이트 내용과 opus 5.5 기능을 확인해서 개선할 부분이 있는지 검토"* 의 검토 결과 1번. Claude Code v2.1.277 은 **cwd·상위에 `CLAUDE.md`·`.claude/CLAUDE.md`·`CLAUDE.local.md` 가 없을 때만** AGENTS.md 를 읽는데(`code.claude.com/docs/en/memory` 「When Claude Code reads AGENTS.md」), v1.310.0(`b83c32b4`)의 `session-context` 는 조건 없이 「자체 로드하므로 다시 싣지 않습니다」라고 주입한다 — 두 파일을 함께 둔 레포에서는 AGENTS.md 가 세션 컨텍스트에서 빠진 채 로드됐다고 안내된다. 이미 배포된 판이라 지금 고친다.

## Proposed outcome
AGENTS.md 가 로드되지 않는 조건(위 세 파일 중 하나가 cwd·상위에 있고, 그것이 AGENTS.md 를 import 하지 않음 · `~/.claude/CLAUDE.md` 는 세지 않음)이면 `session-context` 가 AGENTS.md 전문을 주입하고(16KB 초과면 목차 + Read 지시), 로드되는 조건이면 현행 목차 주입을 유지한다. 관련 서술이 이 조건부 동작과 맞는다.

## Affected users and systems
`CLAUDE.md`·`AGENTS.md` 를 함께 둔 레포에서 pjc 를 쓰는 사용자. `plugins/pjc/scripts/session-context.ps1` 과 그 골든·근거 문서, 「자체 로드」를 서술한 README·스킬·규약 문서.

## Constraints
차단 hook 4종은 건드리지 않는다. 상한 변수 이름(`$agentsMaxBytes` 등)은 `relocate-agents.py` 가 읽으므로 보존한다. 이 레포(CLAUDE.md 없음)의 SessionStart 출력은 현행 목차 주입 그대로다.

## Open questions
없음
