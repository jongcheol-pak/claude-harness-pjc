# Intent: 체인 마찰 수집·앞선 답 잇기의 리뷰 지적 수정
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: `/code-review` 지적 10건에 「지적 검증 후 일괄 계획 (권장)」 → 「권장 진행」. v1.348.0 이 더한 환경 마찰 수집은 워커 보고 서식(실패 경로 누락·횟수 없음·반복분만)과 체인 보고의 계수 규칙(체인 전체 2회 이상·CLI 오류 미분류)이 맞지 않아 후보가 빠지거나 추측으로 채워지고, 앞선 답 규칙은 같은 계획의 이어받기 워커를 덮지 않으며 사용자에게 보이는 참고 문구가 그 답의 출처를 가리지 않는다.

## Proposed outcome
실패로 멈춘 워커도 환경 마찰을 보고하고, 워커는 원인별 실패를 1회부터 횟수와 함께 적어 코디네이터가 체인 전체로 임계를 잰다. 워커가 마찰을 모으는 자리(Progress Log)는 「다음 task 에 필요한 것만」 규칙의 예외로 밝히고, `plan.md` 를 쓰기 전에 겪은 마찰도 그 자리로 옮긴다. 같은 CLI 오류 코드는 2회 이상일 때 후보가 된다(사용자 답 「같은 코드 2회 이상」). 이어받기 마찰은 압축 뒤에도 task 목록으로 센다. 앞선 답 규칙은 같은 계획의 앞 워커에게 준 답까지 덮고, 사용자에게 넘기는 참고 문구는 앞 답이 사용자 답인지 코디네이터 판정인지와 이번에 다르게 볼 이유를 보인다.

## Affected users and systems
Karina 탭에서 `pjc:chain-plan` 을 돌리는 사용자와 코디네이터·워커 세션. `chain-plan/SKILL.md`·`references/{report,compaction,prior-answers,user-relay}.md`·`plan/references/relay-mode.md`.

## Constraints
`chain-plan/SKILL.md` 는 12,000자 게이트 아래 · 같은 질문 판정 기준(결정 대상 + 갈림길 축, 애매하면 다름)은 바꾸지 않는다 · 코디네이터는 파일을 고치지 않는다 · 워커 답 서식 셋은 늘리지 않는다.

## Open questions
없음
