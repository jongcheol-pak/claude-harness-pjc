# Intent: llm-wiki 위키 규칙 경량화 — feature 3절화·예산·ingest 축소
Author: 사용자 (코디네이터 인터뷰 경유 — chain-plan run_5be6991686a994abff53a3a9ff083d1d plan 1/3). Status: approved.

## Problem
spec 「원문:」 블록 그대로:

plan 1: llm-wiki 위키 규칙 경량화 — feature 페이지 3절화(개요·관련 파일·관련 지식·레시피), 예산·압축 규칙 개정, ingest 고정 단계 축소, lint·골든·픽스처 동기, 재성장 방지 lint
사용자 처음 지시: 「위키작업이 비용도 많이 들고 시간도 오래 걸리는데 불필요한 정보까지 너무 많이 추가 하는거 갔은데 검토해줘」 → 「모두 개선하는데 위키는 실제 llm이 작업하면서 필요한 정보만 있으면 되기 때문에 잘 확인해줘」
Q: feature 페이지를 어떤 형태로 바꿀까 / 선택지: 3절만 남김 (권장) · 4절 / A: 권장
Q: 재진술(위키·기록 경량화 전체 — 범위 밖: llm-wiki 스킬 문서 분량 감축·conventions/guide/concept 내용 정리) 동의 / 선택지: 없음 / A: 승인
Q: 대장 겹침 — llm-wiki E-2 경로의 예산 처방 절 라우팅 누락(대장 2026-10-15) / 선택지: 포함 (권장) · 대장 유지 / A: 권장으로 진행
Q: 추가 기능 — feature 관련 파일을 「빠짐없이」에서 「진입 파일·핵심 파일만」으로 / 선택지: 포함 (권장) · 제외 · 보류 / A: 권장으로 진행

지금 하는 이유: ingest 비용·시간이 크고 위키가 원문보다 커졌다(chain-plan 위키 181KB > 스킬 원문 130KB) — vault feature 6.3MB 중 코드 작업 절차가 읽지 않는 세 절이 약 47%다.

## Proposed outcome
feature 페이지 규칙·템플릿·ingest 절차에 폐지된 세 절(구현 방법·동작(사용법)·UI·UX)이 없고, 관련 파일은 진입·핵심 파일만 담으며, lint 가 폐지 절을 가진 feature 를 경고한다. 예산 초과 시 분할보다 레포 사본 서술 삭제가 먼저이고, ingest 한 번의 고정 단계가 줄며, E-2 경로도 예산 처방 절을 읽는다. 기존 lint 골든·정합 검사는 전부 통과한다.

## Affected users and systems
이 하니스로 위키를 ingest·조회하는 LLM 세션. `plugins/pjc/skills/llm-wiki/`(SKILL.md·references·lint.py·evals)와 `plugins/pjc/skills/WIKI.md`.

## Constraints
안전 임계 hook 4종 차단 동작 불변 · llm-wiki 절차 이름·쓰기 범위를 바꾸면 글로벌 `~/.claude/CLAUDE.md` vault 예외 결합 확인 · 압축 허용 시에도 결정·함정의 근거는 보존 · DB 변경 금지.

## Open questions
없음
