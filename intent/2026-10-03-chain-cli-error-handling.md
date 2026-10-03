# Intent: 계획 체인 코디네이터의 Karina CLI 오류 응답 처리
Author: 사용자(jongcheol-pak) — `/code-review` 결과에 「수정」. Status: approved.

## Problem
5cf28559 가 `chain-plan` 의 `worker-start` ⓐ 갈래를 「Karina 가이드 Errors 의 코드 전부 → 보고 후 중단」으로 넓혔다. 그런데 Karina 가이드(릴리스판)는 `protocol_error`(같은 `--retry-request` id 로 재전송)·`runtime_access_denied`(권한 상승 재실행)에 복구 동작을 정해 두어, 지금 문면은 복구 가능한 실패에서 체인을 세우고 `protocol_error` 때는 감독 없는 워커를 남길 수 있다. 사용자는 리뷰 요약 뒤 권장안(수정 plan 작성)을 「수정」으로 골랐다.

## Proposed outcome
코디네이터가 `<CLI>` 응답을 `ok: false` 로 판정하고, 가이드가 복구 동작을 정한 코드는 그 동작을 따르며 나머지는 코드·사유·남은 잔여물을 보고하고 멈춘다. 전제조건 확인도 같은 규칙으로 `runtime_access_denied` 를 인터뷰 전에 걸러 낸다.

## Affected users and systems
`pjc:chain-plan` 을 쓰는 사용자 · `plugins/pjc/skills/chain-plan/` (SKILL.md·references).

## Constraints
SKILL.md 12,000자 게이트(착수 11,961자) 안에 있어야 한다. 다른 세션의 워커일 수 있는 dispatch 는 닫지 않는다. 코디네이터는 파일을 고치지 않는다.

## Open questions
없음
