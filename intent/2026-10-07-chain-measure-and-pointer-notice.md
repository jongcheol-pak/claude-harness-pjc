# Intent: 계획 체인 위키 조회 재사용·묶기 기준의 효과 측정과 줄이 지워진 절의 포인터 알림
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「chain-plan 개선 후보 2건 계획 세워줘」 — 위키 조회에서 찾은 두 후보다. ① 위키 조회 재사용·계획 묶기 임계 조정은 2026-10-05 고정비 회차에서 「이번 범위 밖 — 효과 미측정」으로 미뤄졌다(인터뷰 답 「측정만 (권장)」 · 「대장 등재 (권장)」). ② 다른 파일이 절 이름으로 가리키는 절에서 규칙 줄을 지워도 절이 남아 포인터 도달성 축이 통과한다 — 2026-10-05 chain-plan 「하지 않는 것」 ↔ merge.md 포인터 사례를 계획 리뷰 2라운드가 잡았다(인터뷰 답 「삭제 절 포인터 알림 (권장)」).

## Proposed outcome
① 계획 체인 워커 기록에서 워커당 위키 조회 비용·재사용 가능성과 계획 크기별 고정비·묶기 기준 발동 수를 재고, 수치와 다음 회차 착수 여부 판정이 Deferred 대장에 남는다(근거는 커밋 본문). ② 정합 검사기가 git 작업 트리 변경에서 줄 수가 순감한 절을 찾아 그 절을 절 이름으로 가리키는 포인터를 통지로 알리고, 줄을 지우지 않은 변경에서는 알리지 않는다.

## Affected users and systems
chain-plan 을 고치는 세션(이 레포의 계획·구현 세션). `plugins/pjc/evals/check-harness-consistency.py`·`run-evals.py`·`cases.json`·`docs/harness-conventions.md` 기준선 · `docs/plans/deferred.md`.

## Constraints
① 은 측정만 — chain-plan 규칙·묶기 기준값은 바꾸지 않고 측정 스크립트는 레포에 넣지 않는다 · ② 의 알림은 실패가 아니다(종료 코드 불변) · 기존 포인터 도달성 판정·안전 임계 hook 4종·스킬 `description` 불변 · CRLF·파일 크기 상한.

## Open questions
없음
