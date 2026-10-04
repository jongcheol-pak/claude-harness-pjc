# Intent: 계획 체인의 재개 인계·체크포인트 판정·판정 E: 기록·첫 Task 규칙의 빈틈을 메운다
Author: 사용자(chain-plan 동작 순서 질문 → 수정할 부분 검토 → 1문1답 1회 + 재진술 동의). Status: approved.

## Problem
원문: *"수정할 부분은 없나?"* → 검토 결과 4건에 *"4건 모두 수정 계획 세워줘"*. 문서 대조로 확인한 빈틈(실행 재현 없음): ① 「plan N부터」 재개는 새 Run 을 만들어 spec `인계:` 경로(`chain-<Run id>.md`)가 바뀌고, 워커는 파일이 없으면 첫 계획으로 넘어가 앞 계획의 결정·제약을 읽지 못한다 ② 체크포인트 정지 조건이 「busy 가 아닌데」를 쓰는데 같은 문서가 `worker-show` 에 busy 필드가 없다고 적는다 ③ 봉투 밖 승인 요청에 코디네이터가 내는 `E:` 지시에 판정 표식이 없어 체인 보고 `코디네이터 판정:` 줄에서 빠진다 ④ 「plan 1 은 `--deps` 를 뺀다」가 재개 시 첫 Task 를 다루지 않는다.
이 세션 사용자 답: Q「재개 시 인계를 어떻게 넘기나」 → *"a"*(옛 인계 파일을 그대로 이어 쓴다 — 경로는 체인 승인 화면에 보인다) · 재진술 → *"동의"*.

## Proposed outcome
「plan N부터」 재개 시 코디네이터가 앞 계획 절이 있는 기존 인계 파일 중 가장 최근 커밋된 것을 골라 spec `인계:` 에 싣고 체인 승인 화면에 보이며, 후보가 없으면 새 Run 경로와 「앞 인계 없음」을 보인다. 체크포인트 정지는 `worker-read` 화면이 앞 체크포인트와 같은 횟수로 판정한다. 코디네이터의 `E:` 답은 `(코디네이터 판정 — <근거>)` 를 달고 체인 보고에 모인다. `--deps` 생략은 첫 Task 규칙으로 적힌다.

## Affected users and systems
계획 체인을 돌리는 사용자와 그 코디네이터 세션. 하니스 레포 — `plugins/pjc/skills/chain-plan/SKILL.md` · `chain-plan/references/`(신규 `resume.md` · `delegation.md` · `report.md` · `continuation.md`) · `README.md` · 버전(`plugin.json`·README).

## Constraints
워커 쪽 `plan/references/interview.md` 「중계 모드」는 고치지 않는다. `SKILL.md` 12,000자 · `references/*.md` 15,000자 예산. 워킹트리 CRLF. 편집은 필요한 부분만. push·릴리즈는 별도 승인이다.

## Open questions
없음
