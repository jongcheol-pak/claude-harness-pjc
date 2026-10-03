# Intent: 체인 워커가 남긴 회차를 멈추지 않고 이어받고, 계획·보고의 사실 주장을 실측으로 말한다
Author: 사용자(이 세션 1문1답 2회 + 재진술 동의). Status: approved.

## Problem
원문: *"chain-plan 스킬 사용시 계획을 분할해서 작업을 진행하는 경우 1회차에서 작업 완료후 2회차로 일부 작업을 넘기는 경우가 있는데 이렇게 다음 회차로 작업을 넘기는 경우 계획에 포함해서 다음 회차 작업을 진행 할 건지 사용자에게 질문하면서 작업이 멈추는데 이런 경우 사용자에게 요청을 하지 말고 포함해서 작업을 멈추지 않고 자동으로 계속 진행하도록 수정."* · *"계획, 작업 완료에서 추측으로 설명하는 경우가 많음. 실측 가능한 부분은 제대로 실측해서 보고 하도록 개선"*.
이 세션 사용자 답: Q1「`[다음 회차]` 를 어떻게 이어 가는가 — GUESS: 코디네이터가 같은 계획의 이어받기 task 를 새 워커로 돌린 뒤 plan N+1 로 간다, 체인 승인으로 위임, 진척 없는 반복만 정지」 → *"이어받기 워커 (권장)"* · Q2「추측 설명을 막는 규칙의 범위 — GUESS: plan 승인 제시·plan.md 설명 / implement 완료 보고 / 체인 보고의 사실 주장은 잴 수 있으면 재고 명령·출력을 붙이고, 못 재는 것만 추정(근거)·모름 표시, 두 리뷰어가 지적」 → *"세 자리 + 리뷰어 (권장)"* · 재진술 → *"동의"*.

## Proposed outcome
체인 워커가 `worker_done`(succeeded)의 `남은 일` 에 `[다음 회차]` 를 실으면, 코디네이터는 체인을 멈추지 않고 같은 계획의 이어받기 task 를 만들어 새 워커 탭으로 돌린 뒤 plan N+1 로 간다. 체인 승인이 그 계획 전체를 이미 위임했으므로 사용자에게 묻지 않는다. 같은 `[다음 회차]` 가 진척 없이 연속으로 오면 그때만 멈춘다. 워커는 이 계획의 남은 회차만 `[다음 회차]` 로 적고 다른 체인 계획을 적지 않는다. `pjc:plan` 의 plan.md 설명·승인 제시, `pjc:implement` 의 완료 보고, `pjc:chain-plan` 의 체인 보고에 담기는 사실 주장(현재 상태·원인·영향·수치)은 읽기 전용 명령으로 잴 수 있으면 보고 전에 재고 그 명령·출력 요지를 붙인다. 잴 수 없는 것만 「추정(근거)」·「모름」으로 표시하고 왜 못 재는지 적는다. `plan-reviewer`·`completion-reviewer` 는 잴 수 있는데 실측·표시 없이 남은 주장을 지적한다.

## Affected users and systems
계획 체인·`pjc:plan`·`pjc:implement` 를 쓰는 사용자와 그 코디네이터·워커 세션. 하니스 레포 — `plugins/pjc/skills/chain-plan/SKILL.md`·`references/continuation.md`(신설)·`references/report.md` · `plan/references/interview.md`·`plan-template.md` · `implement/references/report-format.md` · `agents/plan-reviewer.md`·`completion-reviewer.md` · `README.md` · 버전(`plugin.json`·README).

## Constraints
스킬 `description` 은 바꾸지 않는다. `SKILL.md` 12,000자 · `agents/*.md` 6,000자 · `references/*.md` 15,000자 예산(`chain-plan/SKILL.md` 는 착수 11,618자라 이어받기 절차는 references 로 둔다). 글로벌 「항상 별도 승인」(파괴적·외부 비가역·인증 신규 서비스)은 이어받기 워커에서도 사용자에게 간다. push·릴리즈는 별도 승인이다.

## Open questions
없음
