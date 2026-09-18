# Intent: 하니스 스킬 결함 6~17과 정본 갈림 4건 수정
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
2026-09-18 스킬 전수 검토가 낸 결함 18건 중 1~5는 직전 회차(v1.296.0)가 닫았고 나머지가 남았다. 같은 문서가 상반된 지시를 하거나(리뷰어가 성공 기준 명령을 실행하라면서 러너는 돌리지 말라 한다), 없는 대상을 가리키거나(절차 M의 「2-b」·「재구현 원칙」 정본·hook 표의 출처 절 이름), 같은 값이 두 곳에서 갈린다(큐 커밋 메시지의 세션 식별자·백업 보존 기간·백업 폴더 이름). 여기에 정본이 서로를 가리키는 갈림 4건이 겹친다. 원문 요청: *"결함 6~18도 이어서 고치는 plan 세워줘"*. 지금 하는 이유: 직전 회차의 실측이 손에 있고 줄 번호가 아직 밀리지 않았다.

## Proposed outcome
결함 ⑥~⑰과 정본 갈림 4건이 각각 한 값·한 정본으로 수렴하고, 상반 지시와 죽은 포인터가 사라진다. 예산 표가 실행 중 읽히는 파일 전부를 대상으로 잡는다.

## Affected users and systems
`pjc:implement`의 최종 리뷰와 red 확인 · `completion-reviewer` · `pjc:plan`의 Deferred 판정 · `pjc:record-project-fact` Step 5 · `pjc:pjc-systematic-debugging`의 경량 경로와 위키 교차 검색 · `pjc:llm-wiki`의 절차 K·L·M과 백업 규정 · 하니스 정합 검사기의 예산 축.

## Constraints
결함 ⑱(BUDGET의 「처방은 묻지 않고 적용·보고에 싣지 않는다」)은 현행 유지 — 사용자 판정이며 실해가 관측되지 않았다 · 삭제 후보 36곳과 결함 3·4·5 회귀 감시 축은 이번 범위 밖 · 안전 임계 hook 넷의 차단 동작은 건드리지 않는다 · 예산 표 라벨을 바꾸면 검사기 `BUDGET_TARGETS`를 같은 task에서 갱신한다 · 워킹트리 CRLF.

## Open questions
없음.
