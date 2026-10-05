# Intent: 계획 체인 — task 완료마다 코디네이터에 진행 한 줄
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
백그라운드 대기(v1.341.0)로 바뀐 뒤 코디네이터 메인 탭에 워커 진행이 보이지 않는다. 사용자가 「Plan 2 워커가 T1/T5 을 완료 했습니다」처럼 짧게 표시할 수 있는지 물었고, 「task 완료마다 한 줄」을 골랐다.

## Proposed outcome
워커가 task 를 끝낼 때마다 메인 탭에 「Plan 2: T1/T5 완료 — <무엇을> · T2 시작」 한 줄이 나온다(마지막 task 는 다음 시작 없음). 커밋 뒤 약 1분 안에 나오고, 같은 커밋을 두 번 표시하지 않으며, 주기적 「진행 중」 줄은 없다.

## Affected users and systems
pjc:chain-plan 사용자. `chain-plan/scripts/wait-worker.py`·골든, `chain-plan/SKILL.md` 대기 명령, README·검증 명령 상세.

## Constraints
task 당 코디네이터 깨움 1회 · 멈춤 판정 주기(9분 × 3) 유지 · 기존 갈래(질문·완료·멈춤·오류) 유지 · SKILL.md 12,000자 예산 · CRLF.

## Open questions
없음
