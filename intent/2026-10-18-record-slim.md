# Intent: 작업 기록 경량화 ([DECISION]·Deferred 종결 대장·intent) — 체인 plan 3/3
Author: 코디네이터 인터뷰 경유 (pjc:chain-plan run_5be6991686a994abff53a3a9ff083d1d). Status: approved.

## Problem
spec 「원문:」 블록 그대로:

plan 3: 작업 기록 경량화 — [DECISION] 큐잉을 기각·보류만으로, Deferred 종결 대장은 기각만 1줄로 남기고 반영·해소·병합 삭제·대장 누계 2종·불변식 제거, intent/ 산출물 폐지(기존 파일 유지)
사용자 처음 지시: 「작업 하면서 개선 사항이나 대장등에 남기는 정보들도 실제 필요한지 검토」 → 「모두 개선하는데 위키는 실제 llm이 작업하면서 필요한 정보만 있으면 되기 때문에 잘 확인해줘」
Q: intent/를 어떻게 할까 / 선택지: 폐지 (권장) · PR 본문으로 흡수 · 유지 / A: 권장
Q: deferred-closed.md를 어떻게 정리할까 / 선택지: 기각만 1줄로 남김 (권장) · 전부 1줄화 / A: 권장
Q: 재진술(위키·기록 경량화 전체) 동의 / 선택지: 없음 / A: 승인
Q: 후보 — 세션 시작 hook 주석의 대장 「3파일 파싱」 서술 정정 / 선택지: 포함 (권장) · 제외 · 보류 / A: 권장으로 진행

지금 하는 이유: 한 달 레포 커밋 925 중 257 이 intent/·docs/plans 만 건드림 · 종결 232 중 기각은 약 100 · intent/ 를 다시 읽는 스킬 없음 · vault 큐 append 커밋 225.

## Proposed outcome
작업 기록이 다시 읽히는 것만 남는다 — [DECISION] 은 보류·기각(과 기록된 보류·기각의 번복)만 pjc:implement 완료 한 시점에 큐에 들어가고, 종결 대장은 기각 1줄 목록(「요지 — 기각: 사유」)이 되며 반영·해소·병합 종결 항목은 지워지고 대장 누계 2종·불변식이 사라진다. pjc:plan 은 intent 파일을 새로 쓰지 않고 요구는 plan.md 의 `> 요구:`·`## Goal` 이 담으며 두 리뷰어의 범위 대조 기준이 그것이 된다. 세션 시작 hook 의 대장 계수 주석이 실제와 맞는다. 정합 검사기·hook 골든·check-plan 골든이 전부 통과한다.

## Affected users and systems
이 하니스로 plan·implement 를 돌리는 LLM 세션과 사용자 · plan·implement·chain-plan 스킬 문서 · llm-wiki queue-rules.md · plan-reviewer·completion-reviewer · check-plan.ps1 · session-context.ps1 주석 · 정합 검사기·stale-refs·evals 골든·픽스처 · docs/plans 대장 2파일 · AGENTS.md·README.md.

## Constraints
기존 intent/ 파일은 지우지 않는다(미커밋 intent/2026-09-29-chain-plan.md·intent/2026-10-04-skill-trigger-boundaries.md 는 손대지도 커밋에 담지도 않는다) · 안전 임계 hook 4종 차단 동작 불변 · 세션 시작 hook 이 잘라 주입하는 큐 규약 절 헤딩은 유지하거나 hook·골든을 함께 고친다 · DB 변경 금지.

## Open questions
없음
