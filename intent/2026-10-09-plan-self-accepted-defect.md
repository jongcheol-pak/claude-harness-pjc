# Intent: 계획이 스스로 고른 설계의 결함을 자체 수용하지 못하게 한다
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「이미지 적용 기능을 요청해서 작업을 완료 했는데 남은 작업으로 이미지가 표시될 때 메모리 증가 문제가 발생 한다고 나왔는데 이런 경우 기능 작업을 진행 하면서 같이 수정을 해야 되는거 아닌가?」 · 「이 세션에서 지금 수정해」. Karina 회차(2026-10-09)의 계획이 「9장 동시 해독 시 순간 메모리 약 94MB — 받아들이고 완료 보고에 남긴다 (근거로 정함)」를 결정 11개 사이에 넣어 승인받았고, 승인된 설계 선택이 되어 구현의 「그 회차가 만든 결함은 그 회차가 닫는다」가 걸리지 않아 사용자가 후속 회차를 따로 돌렸다.

## Proposed outcome
`pjc:plan` 인터뷰 규칙이 계획 자신의 설계가 남기는 결함을 자체 수용하지 못하게 한다 — 결함 없는 설계를 기본으로 고르고, 그 설계가 다른 비용을 새로 만들 때만 사용자에게 묻는다(사용자 답 「A」). 묻는 통로는 이미 열리는 화면(후보 라운드 · 승인 제시)이다. 중계 모드 워커에도 같은 규칙이 닿고, `plan-reviewer` 가 그런 결함을 MAJOR 로 지적하며 「결함 없는 설계로 바꿔라」로 처방한다. README 가 계획 동작과 리뷰어 검사를 적는다(후보 라운드 포함 2건 · 리뷰 뒤 추가 2건 — 중계 모드 규칙과 README 계획 절은 승인 제시에서 확인).

## Affected users and systems
`pjc:plan` 을 쓰는 모든 계획 세션. `plugins/pjc/skills/plan/references/interview.md` · `relay-mode.md` · `plugins/pjc/agents/plan-reviewer.md` · `README.md`.

## Constraints
질문 수를 늘리지 않는다. 문서 예산(`references/*.md` 15,000자 · `agents/*.md` 6,000자) 안에서 고친다.

## Open questions
없음
