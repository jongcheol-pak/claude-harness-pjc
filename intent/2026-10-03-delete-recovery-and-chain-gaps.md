# Intent: 삭제 정지를 복구 경로로 가르고, 계획→구현·체인의 task 누락과 불필요한 정지를 막는다
Author: 사용자(이 세션 1문1답 3회 + 재진술 동의 + plan 승인). Status: approved.

## Problem
원문: *"chain-plan,plan 스킬 개선 - 파일 삭제시 무족건 멈추고 사용자에게 승인 요청을 받는데 이전 내용이 커밋한 상태여서 복구가 가능한 경우는 그냥 진행하고, 계획 단계에서 제대로 확인해서 필요한 경우 미리 사용자 승인을 받음. - 계획후 진행시 task가 빠지는 부분이 있는지 확인 - 작업중 멈출 수 있는 부분이 있는지 확인"*
문서 대조로 확인한 빈틈(실행 재현 없음): 삭제 정지가 건수(5파일·100줄)로만 갈려 git 이력으로 되살릴 수 있는 삭제에서도 루프가 선다 · 글로벌 `CLAUDE.md` 가 「재귀/대량 삭제」를 plan 에 적혀 있어도 항상 실행 시점 승인으로 둔다 · 코디네이터의 워커 plan 승인 대조가 넘침만 보고 누락을 안 본다 · `worker_done` 의 `남은 일` 을 보지 않고 다음 계획을 띄운다 · 중계 워커가 회차를 나누면 남은 회차가 아무도 안 보는 화면에만 남는다 · plan→implement 이행이 Skill 도구 호출로 명시되지 않아 `loop-continue` 마커가 안 설 수 있다 · 검증 명령 출처를 리뷰가 안 봐 implement 가 실행 중 묻는다 · 중계 워커는 실행 시점 승인 항목에서 묻지 않고 `failed` 로 체인을 멈춘다(chain-plan 은 「그때 사용자에게 간다」고 적어 모순).
이 세션 사용자 답: Q「글로벌 지침도 함께 고치나」 → *"글로벌도 함께 수정 (권장)"* · Q「누락 보완 범위」 → *"승인 대조에 누락 추가 · worker_done 남은 일 판정 · 중계 워커 [다음 회차] 행방"* · Q「정지 보완 범위」 → *"implement 이행 Skill 호출 명시 · 검증 명령 출처 리뷰 · 중계 워커 실행 승인 ask 경로"* · 재진술 → *"동의"*.

## Proposed outcome
파일 삭제는 복구 경로로 가른다 — 대상이 git 에 커밋돼 있으면(미커밋 변경·untracked·ignored 없음 — 진행 중 task 가 새로 만든 경로와 `plan.md`·`notes.md` 는 판정 밖, 고친 경로는 그 task 착수 때 깨끗했을 때만 무시) plan 승인으로 덮고 실행 중 멈추지 않으며, 복구 경로가 없는 삭제는 plan Step 3 에서 실측해 `## 승인 필요 항목` 으로 plan 승인 때 받는다. 이동·이름 변경은 내용이 남아 정지 대상이 아니고, 덮어쓰기는 종전대로 글로벌 「승인 또는 사전 백업」에 맡긴다. 글로벌 지침도 같은 기준으로 개정한다. 체인에서는 체인 승인에 없던 복구 불가 삭제를 코디네이터가 대신 승인하지 않는다. 체인은 워커 plan 의 누락을 대조하고 `남은 일` 을 판정하며, 중계 워커는 회차를 나눈 나머지를 `남은 일` 로 올리고 실행 시점 승인을 `ask` 로 받는다. plan 은 implement 를 Skill 도구로 부르고, plan-reviewer 는 검증 명령 출처를 본다.

## Affected users and systems
pjc 하니스로 계획→자율 구현과 계획 체인을 돌리는 사용자. 하니스 레포 — `plan/SKILL.md` · `plan/references/plan-template.md` · `plan/references/interview.md` · `implement/SKILL.md` · `chain-plan/SKILL.md` · 신설 `chain-plan/references/report.md` · `agents/plan-reviewer.md` · `README.md` · 버전. 레포 밖 — 글로벌 `~/.claude/CLAUDE.md`.

## Constraints
push·병합·태그·릴리즈·PR·force push·DB DROP 등 외부·비가역 작업의 실행 시점 승인은 그대로 둔다. 차단 hook 동작은 바꾸지 않는다. plan 에 없던 복구 불가 삭제는 여전히 실행 시점 승인이다. 두 스킬 `description` 은 바꾸지 않는다. `SKILL.md` 12,000자 · `references/*.md` 15,000자 · `agents/*.md` 6,000자 예산. 글로벌 위키 vault 예외 조항은 보존한다.

## Open questions
없음
