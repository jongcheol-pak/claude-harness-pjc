# Intent: 멈춘 체인의 워커를 사용자가 직접 이어 가면 코디네이터가 합류하고, 추적 레포의 plan.md 를 커밋한다
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「2·3·4 chain-plan 묶음부터 계획 세워줘」 — Deferred 대장 2026-10-08 등재 3건(Karina 체인 run_4b6b42f1). ① stall 로 체인이 멈춘 뒤 사용자가 워커를 직접 재개하자 워커의 승인 `ask` 를 받을 대기가 없어 540초×3 만료로 failed 가 됐다. ② 그 뒤 워커가 끝까지 갔지만 `worker_done` 이 `inactive_dispatch` 로 거절돼 사후 완료를 알릴 경로가 없었다. ③ 중계 워커가 `plan.md` 를 추적하는 Karina 레포에서 「gitignore」로 오판해 `plan.md` 를 커밋하지 않았다.

## Proposed outcome
stall·failed 로 멈춘 체인에서 사용자가 워커를 탭에서 직접 이어 가게 했으면, 코디네이터 탭에 알리는 것만으로 체인이 잇는다 — stall 이면 같은 워커의 대기를 다시 띄우고, failed 뒤 사후 완료면 워커가 정한 서식의 `status` 로 완료를 보내고 코디네이터가 그것을 완료로 반영해 다음 계획으로 간다. 멈춤 보고에 그 알림 방법이 실린다. `plan.md` 를 추적하는 레포에서는 `pjc:implement` 가 마무리에 `plan.md` 를 한 번 커밋하고, 플러그인 지침이 「`plan.md` 는 gitignore」를 모든 레포의 사실로 단정하지 않는다.

## Affected users and systems
Karina 에서 `pjc:chain-plan` 을 돌리는 사용자와 중계 워커. `pjc:chain-plan`(SKILL·보고·대기 스크립트)·`pjc:plan` 중계 모드·`pjc:implement` 커밋 절차·`plan-template`·`intent-rules`·`completion-reviewer`·README.

## Constraints
「멈춘 워커의 자동 재개 금지」를 유지한다 — 합류는 사용자 알림으로만 시작한다(Q/A). `plan.md` 커밋은 마무리에 한 번이다(Q/A). Karina 앱 코드·차단 hook 은 고치지 않는다. `plan.md` 가 gitignore 인 레포(이 하니스 레포 포함)의 동작은 바뀌지 않는다.

Q: 멈춘 체인에서 사용자가 워커를 직접 이어 가게 했을 때 코디네이터는 어떻게 하나요? 선택지: 알리면 잇는다 (권장) / 보고만 고친다 / 질문만 받는 대기. A: 알리면 잇는다 (권장)
Q: plan.md 를 추적하는 레포에서 pjc:implement 는 plan.md 를 언제 커밋하나요? 선택지: 마무리에 한 번 (권장) / task 커밋마다. A: 마무리에 한 번 (권장)
후보 라운드: 「plan.md 는 gitignore」 단정 문면 수정 — 포함(권장) · hook 근거 문서 post-write-rationale.md:197 — 제외(권장). A: 권장대로

## Open questions
없음
