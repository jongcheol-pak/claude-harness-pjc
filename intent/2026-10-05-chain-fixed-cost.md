# Intent: 계획 체인 워커의 계획당 고정비 줄이기 — 리뷰 재호출과 마무리 커밋
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문 요청: *"계획당 고정비 줄이는 계획 세워줘"* — 직전 답의 「남은 병목 1(계획당 고정비)」 후속이다. 워커 기록 31건 실측에서 실전 계획(task 6~12, 21건)의 고정비 중앙값은 계획당 약 43분·40M 토큰(활동 시간 46%)이고, 그중 계획 리뷰 루프가 18분(plan-reviewer 2~3라운드가 21건 중 9건), 마무리 구간이 12분(턴마다 약 520K 컨텍스트 재독)이다.

## Proposed outcome
체인 워커(중계 모드)는 계획 리뷰·완료 리뷰를 BLOCKER 가 있었을 때만 고친 뒤 다시 부르고, MAJOR 는 고친 뒤(MINOR 는 기존 규칙대로 고치거나 버린 뒤) 처리 내역을 남긴다(계획 리뷰는 승인 ask 의 `리뷰 지적 처리:` 줄). Deferred 대장 이관과 위키 사용 기록은 리뷰 전 한 커밋으로 묶인다. 인계 절은 plan 의 task 가 아니라 마무리의 마지막 커밋으로 쓰여, 인계 뒤 커밋 범위를 고치는 별도 커밋이 없어진다. 이 규칙은 압축 뒤에도 `plan.md` Next Steps 블록으로 남는다.

## Affected users and systems
`pjc:chain-plan` 사용자. `plan/references/relay-mode.md`·`plan/SKILL.md` Step 6·`implement/references/final-review.md` 의 중계 예외 포인터·`chain-plan/references/continuation.md` 이어받기 봉투·`README.md` 계획 체인 행.

## Constraints
대상 구간은 계획 리뷰 루프와 마무리 둘(사용자 답 「계획 리뷰 루프」·「마무리 구간」) · 재호출은 중계 모드에서 BLOCKER 만(사용자 답 「중계: BLOCKER만 재호출」) · 마무리는 재호출 축소와 쓰기 묶기(사용자 답 「재호출 축소+쓰기 묶기」) · 비체인 경로·스킬 `description` 불변 · 체인 끝 1회 후처리(2026-10-04 기각)·자동 묶기 금지 · 레포 고유 문서 갱신은 건드리지 않는다 · BUDGET 상한·CRLF.

## Open questions
없음
