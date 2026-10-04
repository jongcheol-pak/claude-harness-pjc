# Intent: chain-plan 결함 C1~C6 — 압축 뒤 상태 복원 · 위임 줄 정의 · 멈춤 경로 탭 보고 · 교차 참조 · 배치 규칙 · 워커 프로토콜 정본
Author: 사용자(코디네이터 인터뷰 경유 — 계획 체인 run_df97d5067a35f3985c2fb07d3e031680 plan 1/4). Status: approved.

## Problem
원문(spec 「원문:」): "plan 1: chain-plan 결함 C1~C6 — 압축 뒤 코디네이터 상태 복원 · 「외부 계약 위임」 줄 정의 · 멈춤 경로 워커 처분과 남은 탭 보고 · 원문자 번호 교차 참조 · measure↔handoff 배치 규칙 · 워커 프로토콜 정본 단일화" · "[공통] 나머지 검토 결함도 계획 세워줘" · "[plan 1] C1 — Run·Task 에 실고 CLI 로 재구성 (권장) — 승인 원문은 run objective 끝, 이어받기 횟수는 task 제목에 — 압축 뒤 run-current·task-list·worker-list 로 재구성. 코디네이터 파일 수정 금지와 맞는다". 2026-10-04 skill-creator 전체 검토에서 남은 chain-plan 결함이다.

## Proposed outcome
계획 체인 코디네이터가 컨텍스트 압축 뒤에도 체인을 이어 갈 상태를 되찾고, 체인 승인 화면에서 위임 범위를 보고 고르며, 멈출 때 워커 처분과 남은 탭을 빠짐없이 보고하고, 같은 규칙·번호가 한 정본으로 읽힌다. chain-plan 의 SKILL.md 는 12,000자 이하이고 검증 매핑 필수 검증이 통과하며 바뀐 파일은 CRLF 다.

## Affected users and systems
pjc:chain-plan 코디네이터 세션과 그것을 돌리는 사용자, 중계 모드 워커. 걸리는 것은 chain-plan 스킬 문서와 참조 문서, pjc:plan 중계 모드 문서, README·plugin.json 이다.

## Constraints
스크립트화 없음(사용자 결정) · Karina 코드 무수정 · 다른 세션 워커는 닫지 않는다(2026-10-03 결정) · description 무수정 · AGENTS.md DO NOT · DB 변경 금지 · 로컬 커밋까지(push·릴리즈는 보고).

## Open questions
없음
