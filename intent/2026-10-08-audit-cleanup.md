# Intent: 감사 결과 정리 — 충돌·낡은 규칙·고아·예산·병목
Author: 사용자. Status: approved.

## Problem
원문: *"불필요한 규칙/병목/사용하지 않는 규칙/고아/ 검토"* → *"전부 계획 세워줘"*. 읽기 전용 감사(4영역)가 서로 충돌하는 규약 3건, 이미 없는 동작을 설명하는 서술, 실행되지 않는 분기, 등록 누락·1회성 잔존 파일, 상한 직전의 문서 2개, 검증 14분 중 83%를 차지하는 hook 골든과 매 Write·세션 시작의 반복 비용을 찾았다. 충돌은 세션의 판정을 갈라 놓고, chain-plan SKILL 은 여유 3자라 다음 편집이 막힌다.

## Proposed outcome
4회차로 나눠 끝낸다 — ① 문서 정합(충돌·낡은 서술·실행되지 않는 분기·등록 누락·삭제 3건) ② 크기 예산 ③ 병목 ④ 중복 통일. 각 회차 끝에 모든 검증이 통과하고, 회차 1 끝에 충돌·낡은 서술이 남지 않으며, 회차 3 끝에 hook 골든 소요가 착수 기준선(694초)보다 줄어든다.

## Affected users and systems
이 하니스를 쓰는 세션과 유지보수하는 사용자. `plugins/pjc/scripts/**`·`hooks/evals/**`·`evals/**`·`skills/{llm-wiki,record-project-fact,chain-plan,implement,plan}/**`·`docs/**`·`AGENTS.md`·`validate.ps1`, 레포 밖 `~/.claude/.state/require-evidence-warn/`.

## Constraints
차단 hook 4종(`block-destructive`·`guard-bash`·`guard-write`·`guard-harness`)은 동작을 보존하는 정리만 하고 골든 전량 통과로 무변경을 보인다 — 판정 통일은 비차단 hook 쪽을 맞춘다. AGENTS.md 의 글로벌 지침 중복 문장은 유지한다. 레포 밖 잔존 마커 삭제는 백업 뒤 승인 항목으로 한다. 코드 레포 push·릴리즈는 하지 않는다.

## Open questions
없음
