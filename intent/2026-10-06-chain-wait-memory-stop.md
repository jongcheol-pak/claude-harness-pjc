# Intent: 체인 대기의 메모리 부족 종료 처리
Author: 사용자. Status: approved.

## Problem
원문 요청: 「환경 변수 등록과 하니스 수정해줘」 — 앞선 대화에서 Karina 체인 코디네이터가 plan 1·2·3 마다 「메모리가 부족해 Claude Code가 plan N 워커를 기다리던 대기 스크립트를 중단시켰습니다. 메모리가 아직 부족할 수 있어 제가 다시 띄우지 않았습니다」로 섰다. `chain-plan/SKILL.md` 는 RESULT 없는 종료를 한 번 다시 띄우라고 하고 Claude Code 알림은 요청받을 때만 다시 띄우라고 해 둘이 부딪히며, 알림 쪽이 이겨 체인이 규칙 밖에서 멈춘다.

## Proposed outcome
메모리 부족 종료는 다시 띄우지 않고 멈춘 계획·끄는 법을 알린 뒤 「계속」을 기다리는 것이 스킬 규칙이 되고, 체인 승인 화면이 그 종료를 끄는 환경변수가 켜졌는지 보인다.

## Affected users and systems
`pjc:chain-plan` 을 Karina 탭에서 돌리는 사용자 · `chain-plan/SKILL.md`「워커 루프」·「체인 승인」과 `references/cli-errors.md` 의 자리 대기 규칙 · README 「계획 체인」 행.

## Constraints
사용자 답 「보고+시작 전 점검 (권장)」 — 변수가 꺼져 있어도 체인을 멈추지 않고 알리기만 한다. `chain-plan/SKILL.md` 는 12,000자 게이트 아래에 둔다.

## Open questions
없음
