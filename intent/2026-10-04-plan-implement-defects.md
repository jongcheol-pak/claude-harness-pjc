# Intent: plan·implement 결함 — 정지·승인·리뷰·중계 모드 정합과 커밋 유형 이중화
Author: 사용자(코디네이터 인터뷰 경유 — 계획 체인 run_df97d5067a35f3985c2fb07d3e031680 plan 2/4). Status: approved.

## Problem
원문(spec 「원문:」): "plan 2: plan·implement 결함 — I1 커밋 유형 이중화 · I2 루프 중 debugging 관계 · I3 정지 목록 밖 승인 사항 · I4 BASE 출처 · I5 정지 분류 · P1 중계 모드 분리 · P2 리뷰어 중계 조항 · P3 검증 명령 처방 · P4 버그 항목 순서 · P5 리뷰 루프 정지 · P6 중계 아키텍처 선언 · P8 규칙 복제 · P10 참조 불일치 · X2 Conventions 포인터 · X4 정지 번호 지목" · "[공통] 나머지 검토 결함도 계획 세워줘" · "[plan 2] P1 — 분리함 (권장) — 일반 세션은 7,029자를 안 싣고, 중계 워커는 SKILL.md 앞 트리거로 Step 1 전에 읽는다. chain-plan 포인터 3곳 동반" · "[plan 2] I3 — 기존 칸 확장 (권장) — 「plan에 없던 기능 변경」을 「plan 승인이 덮지 않는 변경(동작·의존성·환경·데이터)」으로 넓힌다. 정지 수 「여덟」은 그대로, hook 무변경" · "[plan 2] I2 — Files 안이면 고침 · 밖이면 정지 (권장) — 원인 규명은 그대로, 수정이 그 task Files 안이면 루프 안에서, 밖이면 pjc:plan 으로 넘기지 않고 「plan 승인이 덮지 않는 변경」 정지(진행 중 plan.md 덮어쓰기 방지)". 2026-10-04 skill-creator 전체 검토에서 남은 plan·implement 결함이다.

## Proposed outcome
pjc:plan·pjc:implement 가 정지·승인·리뷰·중계 모드를 서로 같은 규칙으로 읽고, 글로벌 지침이 없는 배포본 사용자에게도 커밋 유형이 정의되며, 중계 모드 규칙이 그것이 필요한 세션에만 실리고 Step 1 전에 도달한다. 각 SKILL.md 는 12,000자 이하이고 Hook 골든(session-context 발췌 절)을 포함한 검증 매핑 필수 검증이 통과하며 바뀐 파일은 CRLF 다.

## Affected users and systems
pjc:plan·pjc:implement 를 쓰는 세션(일반·중계 워커)과 plan-reviewer. 걸리는 것은 plan·implement 스킬 문서와 참조 문서, plan-reviewer 에이전트 정의, chain-plan 의 포인터 3곳, 트리거 eval 케이스의 설명 1건, README·plugin.json 이다.

## Constraints
스크립트화 없음(사용자 결정) · 스킬 description 무수정(마지막 회차 몫) · 골든 앵커 「task 사이에서 묻지 않는다」·「모든 사실 주장은 명령을 실행해 얻는다」 보존 · check_wiki_circuit 7단계(plan/SKILL.md 에 pending.md·PROJECT-FACT 한 줄 공존) 보존 · 정지 수 「여덟」 유지·hook 무변경 · chain-plan 본문·debugging·record·llm-wiki 본문은 범위 밖(chain-plan 은 포인터만) · DB 변경 금지 · 로컬 커밋까지(push·릴리즈는 보고).

## Open questions
없음
