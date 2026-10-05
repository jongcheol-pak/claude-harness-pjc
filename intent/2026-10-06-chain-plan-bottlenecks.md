# Intent: 계획 체인 코디네이터의 불필요한 깨어남과 쓰이지 않는 규칙 걷기
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「chain-plan 스킬에서 병목이 발생할 수 있는 부분이나 사용하지 않는 규칙이 있거나 불필요한 규칙이 있는지 확인」 → 점검 결과에서 「B3까지 포함해서 작업 계획」. 체인 비용은 코디네이터가 깨어나는 횟수 × 컨텍스트 크기인데, 다른 세션이 같은 폴더를 쥔 경우의 상한 없는 전경 기다림(B1)·같은 화면 4장을 요구하는 멈춤 판정(B2)·정보 없이 깨우는 renew(B3)가 남아 있고, 도달 불가 처방(`source_changed`)과 두 곳에 갈린 중복 규칙이 있다. 사용자 질문 「멈추지 않고 계속 진행했으면 하는데」 — 자리를 쥔 경우에도 체인이 서지 않기를 원한다.

## Proposed outcome
다른 세션이 자리를 쥔 동안 코디네이터는 깨어나지 않고, 자리가 비면 체인이 스스로 이어진다. 대기 스크립트는 메시지·멈춤·오류·진행·자리 비움(·물러남) 때만 끝나고, 멈춤은 같은 화면 3장에서 판정된다. 45분 백그라운드 실측이 통과하면 renew 가 없어진다. 도달 불가 처방과 중복 규칙은 한 곳에만 남는다.

## Affected users and systems
Karina 탭에서 `pjc:chain-plan` 을 돌리는 사용자. `chain-plan/scripts/wait-worker.py`·`chain-plan/evals/run_wait_evals.py`·`chain-plan/SKILL.md`·`references/cli-errors.md`·`references/user-relay.md`·`docs/harness-conventions.md` 의 대기 골든 항목.

## Constraints
Karina 는 고치지 않는다 · 안전 임계 hook 은 건드리지 않는다 · 다른 세션의 dispatch 를 stop·abandon 하지 않는다 · `.py` 는 BOM 없음·CRLF 유지 · `SKILL.md` 는 12,000자 게이트 아래.

## Open questions
없음
