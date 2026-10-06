# Intent: 계획 체인 보고의 환경 개선 후보와 체인 안 앞선 답 잇기
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「https://github.com/mattpocock/skills 에서 'chief-of-staff` 스킬이 있는데 참고해서 chain-plan 스킬에 개선할 부분이 있는지 검토」 → 검토 결과 두 후보에 「1,2 같이 수정」. 체인 중 마찰(같은 질문의 반복 이관·hook 차단·`AGENTS.md` 에 없는 명령)을 모으는 자리가 없어 사고를 사람이 나중에 찾았고, 앞 계획에서 답한 질문과 같은 질문이 뒤 계획에서 다시 오면 그 답이 이어지지 않는다.

## Proposed outcome
체인 보고가 「환경 개선 후보」를 행선지와 함께 제안한다(워커 보고에 `환경 마찰` 필드 · 코디네이터가 본 마찰 — 같은 질문의 이관·같은 hook 차단·같은 원인 실패는 2회 이상일 때, `AGENTS.md` 에 없는 명령과 이어받기·stall 은 1회도). 코디네이터 판정은 같은 질문(결정 대상·갈림길 축이 같음)에 준 앞 판정·앞 사용자 답과 어긋나지 않고, 사용자 몫 질문은 그대로 넘기되 앞 답을 덧붙인다.

## Affected users and systems
Karina 탭에서 `pjc:chain-plan` 을 돌리는 사용자와 코디네이터·워커 세션. `chain-plan/SKILL.md`·`references/report.md`·`references/user-relay.md`·`references/compaction.md`·새 참조 파일·`README.md`.

## Constraints
코디네이터는 파일을 고치지 않는다(제안만) · 사용자 몫 넷과 위임되지 않는 항목은 그대로 · 워커 답 서식 셋(옮긴 답·위임·판정)에 새 서식을 더하지 않는다 · `SKILL.md` 는 12,000자 게이트 아래.

## Open questions
없음
