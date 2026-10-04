# Intent: 계획 체인의 중복 실측과 이중 동의를 걷어 체인 소요 시간을 줄인다
Author: 사용자(이 세션 검토 요청 → 1문1답 3회 + 재진술 동의). Status: approved.

## Problem
원문: *"chain-plan 스킬을 사용하면 기존 plan 보다 2배이상 작업 속도가 더 걸리는거 같은데 중복으로 작업을 하고 있는지 또는 불필요한 작업을 하는지 검토해줘"* → 검토 결과의 개선 후보 중 *"개선 후보 1~3번으로 계획 세워줘"*.
검토(문서 대조): ① 실측이 원 세션(또는 코디네이터 Explore)과 워커 Step 3 에서 두 번 돈다 — 워커는 「실측 요지는 출발점이다 — 다시 잰다」(`chain-plan/SKILL.md` spec 진행 1 · `plan/references/interview.md` 중계 모드)라 앞 계획이 코드를 바꾸지 않은 plan 1 도 다시 잰다. ② 코디네이터가 계획마다 2-6 명시적 동의를 받은 뒤 체인 승인에서 같은 성공의 모습·범위 밖을 다시 승인받는다(`handoff.md`「확인 인터뷰」·`SKILL.md`「인터뷰」).
이 세션 사용자 답: Q「겹치지 않을 때 워커 Step 3 에서 무엇을 건너뛰나」 → *"A로 진행해"*(재측정만 생략 — Explore 가 보장하지 않는 호출자·테스트 Files 보강·삭제 복구 경로·acceptance 착수값은 잰다) · Q「체인 승인에 없는 재진술 항목 처리」 → *"A로 진행해"*(체인 승인에 `제약조건:` 줄을 더하고 계획별 동의 삭제) · Q「3번(후처리를 체인 끝으로) 범위」 → *"A로 진행해"*(3번 제외 — 실측상 절감이 작고 Deferred 유실 위험) · 재진술 → *"응 진행해"*.

## Proposed outcome
체인 워커는 실측 요지의 바뀌는 파일이 실측 기준 커밋 이후 바뀐 파일과 겹치지 않고 앞 계획 의존이 없으면 실측 요지 항목을 다시 재지 않는다 — 근거를 Investigation Log 로 옮기고 호출자·테스트 Files 보강·삭제 복구 경로·acceptance 착수값만 잰다. 기준 커밋이 없거나 겹치거나 의존이 있거나 이어받기 워커면 지금처럼 다시 잰다. 실측 기준(그 시점 `HEAD`)은 회차 실측·코디네이터 실측·spec 에 실려 워커까지 간다. 코디네이터 인터뷰는 계획마다 2-6 명시적 동의를 받지 않고 체인 승인이 재진술 확인을 겸한다 — 체인 승인 화면에 계획마다 `제약조건:` 줄을 더하고 `E` 가 재진술 수정 통로다.

## Affected users and systems
계획 체인을 돌리는 사용자와 그 코디네이터·워커 세션. 하니스 레포 — `plugins/pjc/skills/chain-plan/SKILL.md` · `chain-plan/references/handoff.md` · `chain-plan/references/measure.md` · `plugins/pjc/skills/plan/references/interview.md` · `plugins/pjc/skills/plan/SKILL.md` · `README.md` · 버전(`plugin.json`·README).

## Constraints
「명령 열이 빈 행은 주장 불가」 실측 규칙과 다른 회차 task 흡수 금지는 그대로다. 체인 승인 화면의 성공의 모습·범위 밖은 유지한다(2026-10-03 결정). `interview.md` 2-6 자체는 고치지 않는다(2026-10-02 결정 — 넘김 경로를 2-6 에 적지 않는다). 두 스킬 `description` 은 바꾸지 않는다. `SKILL.md` 12,000자 · `references/*.md` 15,000자 예산. push·릴리즈는 별도 승인이다.

## Open questions
없음
