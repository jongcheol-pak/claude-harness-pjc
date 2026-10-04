# Intent: 스킬 발동 경계 description·트리거 eval
Author: 코디네이터 인터뷰 경유 (pjc:chain-plan run_522092b84250d355c17aadad5c9644be, plan 2/2). Status: approved.

## Problem
원문: 「plan 2: 스킬 발동 경계 — A2 chain-plan 재개 발화 description · A4 plan description 서술형·「만들어줘」 트리거와 AGENTS.md 정리·생성 담당 · A5 트리거 eval 러너 오라우팅 판정 + 경계 케이스 추가 + 트리거 eval 실행·기준선 갱신」. 2026-10-04 skill-creator 전체 검토가 발동 경계의 빈틈·겹침과, 다른 스킬이 먼저 떠도 PASS 로 세는 eval 판정 사각을 확인해 지금 한다.

## Proposed outcome
계획 체인 재개·AGENTS.md 정리/생성·승인 전 plan 의 「계속」 같은 경계 요청이 description 만으로 올바른 스킬에 가고, 트리거 eval 이 다른 스킬이 먼저 뜨는 오라우팅을 FAIL 로 잡는다. 경계 사례가 trigger/no-trigger 케이스로 있고 새 판정으로 전량 run 이 돌아 `evals/README.md` 기준선이 그 run 으로 바뀌며, 각 description ≤1,024자·chain-plan SKILL.md ≤12,000자다.

## Affected users and systems
pjc 플러그인 사용자와 스킬 목록만 보고 스킬을 고르는 모델. 걸리는 시스템은 `plugins/pjc/skills/evals/`(trigger_eval.py·test_exit_code.py·trigger-cases.json·README.md)와 chain-plan·implement·plan·record-project-fact 의 SKILL.md, `docs/harness-conventions.md`·`plugins/pjc/skills/AUTHORING.md` 의 수 인용.

## Constraints
트리거 eval 실행 중 플러그인 디렉터리 편집 금지 · 케이스 파일이 바뀌면 옛 run 은 기준선 자격을 잃는다 · 고빈도 단어 단독 트리거 금지 · 질의가 description 을 복창하지 않는다 · 판정 = trigger 는 첫 발동 스킬이 목표, no-trigger 는 `route_to` 가 있으면 그 스킬이 첫 발동(없으면 현행) · 모든 케이스 첫 Skill 호출에서 종료 · 「AGENTS.md 새로 만들어줘」 담당은 record-project-fact · plan description 서술형 트리거 유지 + AGENTS.md 예외 · eval 은 description 수정 전 필터 4종, 수정 후 전량 1회 · DB 변경 금지 · push·릴리즈는 하지 않는다.

## Open questions
없음
