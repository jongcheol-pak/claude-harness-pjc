# Intent: 계획 체인 대기 스크립트 — 코드 리뷰 지적 수정
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
v1.342.0(chain-plan 진행 한 줄) 범위 `49fd5248^..HEAD` 의 `/code-review` 가 `wait-worker.py`·대기 골든에 지적 10건을 냈다. 사용자가 「지적을 검증해 확인된 것만 task 로 묶어 plan 을 세운다」를 골랐다.

## Proposed outcome
코드와 대조해 확인된 지적이 고쳐진다 — 잠금을 잃은 대기는 진행 감지 중이었어도 배치를 싣지 않고, 상태 파일 쓰기 실패가 대기를 RESULT 줄 없이 죽이지 않으며, 상태 파일은 쓰는 도중의 내용이 읽히지 않고, 시작 HEAD 를 못 잡은 대기는 다음 주기에 다시 잡고, 분모를 넘는 번호는 분모 없이 표시하며, 골든 러너 docstring 과 출력이 실제와 맞는다. 기각한 지적은 근거와 함께 plan 의 Out of Scope 에 남는다.

## Affected users and systems
pjc:chain-plan 사용자. `chain-plan/scripts/wait-worker.py`·`chain-plan/evals/run_wait_evals.py`, `docs/harness-conventions.md` 의 대기 골든 항목.

## Constraints
기존 갈래(message·stall·error·renew·superseded·progress)와 첫 줄 지시 문면 유지 · `--repo` 없는 호출은 종전 인자·순서 유지 · 앞 회차 결정(D1 차감식 대기 · D3 커밋 형식 · 병행 세션 T 커밋 비필터)은 다시 열지 않는다 · CRLF.

## Open questions
없음
