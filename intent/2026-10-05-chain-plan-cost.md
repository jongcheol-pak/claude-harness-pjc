# Intent: 계획 체인의 코디네이터 비용과 계획당 고정비 줄이기
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
「chain-plan 이 plan 단독보다 너무 느리고 토큰을 너무 많이 쓴다」(사용자). 실측상 코디네이터가 27만~61만 토큰 컨텍스트에서 체인을 시작해, 워커를 기다리는 9분 폴링마다 그 컨텍스트를 다시 읽어 체인 1회 폴링에만 21~32M 토큰을 쓴다. 의존이 있는 계획은 워커가 넘겨받은 실측 전체를 다시 재고, 작은 계획도 계획마다 리뷰·인계 고정비를 진다.

## Proposed outcome
워커가 일하는 동안 코디네이터는 메시지 도착·멈춤 판정 때만 깨어난다. 무관한 작업을 한 세션에서 체인을 시작하려 하면 새 세션을 권고받는다(`pjc:plan` 이 회차를 넘긴 경우는 인터뷰 맥락을 쓰므로 제외). 워커는 앞 계획이 바꾼 자리와 겹치는 실측 항목만 다시 잰다. 나란한 작은 두 계획(task 초안 합 6 이하)은 묶을지 질문받는다.

## Affected users and systems
pjc:chain-plan 으로 여러 계획을 돌리는 사용자. `chain-plan/SKILL.md`·references, 새 대기 스크립트, 워커 쪽 `plan/references/relay-mode.md` 재측정 조건.

## Constraints
10-04 결정(재측정 생략 조건·체인 승인 겸 동의) 유지 · 안전 임계 hook 불변 · BUDGET 상한 · CRLF/.ps1 BOM · 계획 경계는 사용자가 정한다(자동 묶기 금지).

## Open questions
없음
