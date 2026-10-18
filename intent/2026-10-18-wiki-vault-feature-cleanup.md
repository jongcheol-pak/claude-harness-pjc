# Intent: 기존 vault feature 정리 — 폐지 절·조각 일괄 제거
Author: 사용자 (코디네이터 인터뷰 경유 — chain-plan run_5be6991686a994abff53a3a9ff083d1d plan 2/3). Status: approved.

## Problem
spec 「원문:」 블록 그대로:

plan 2: 기존 vault 정리 — 정리 스크립트로 feature 376개에서 구현 방법·동작(사용법)·UI·UX 절과 그 절이 가리키는 분할 조각 제거, 남는 조각 병합, 인덱스·허브 링크 갱신 (vault 레포 D:/Personal Project/Obsidian Vault/LLM WIKI)
사용자 처음 지시: 「위키작업이 비용도 많이 들고 시간도 오래 걸리는데 불필요한 정보까지 너무 많이 추가 하는거 갔은데 검토해줘」 → 「모두 개선하는데 위키는 실제 llm이 작업하면서 필요한 정보만 있으면 되기 때문에 잘 확인해줘」
Q: 이미 있는 feature 페이지 376개는 어떻게 정리할까 / 선택지: 스크립트로 일괄 정리 (권장) · 모델이 페이지마다 검토 · 정리하지 않음 / A: 권장
Q: 재진술(위키·기록 경량화 전체) 동의 / 선택지: 없음 / A: 승인

지금 하는 이유: 규칙만 바꾸면 기존 feature 의 조회되지 않는 서술(폐지 세 절의 비-포인터 본문 약 174만 자 — feature 전체 384만 자 중)이 vault 에 남는다.

## Proposed outcome
vault feature 페이지가 새 3절 형태(개요·관련 파일·관련 지식·레시피)가 된다 — 폐지된 세 절과 그 절에서만 가리키던 분할 조각이 사라지고, 관련 지식·관련 파일 쪽 조각은 부모로 합쳐지며(합친 결과가 예산 임박·초과가 되는 조각은 남긴다), 지우는 조각 안의 실제 관련 지식·관련 파일 본문은 보존되고, 인덱스·허브·크로스링크가 깨지지 않는다. vault 전체 feature 에 폐지된 세 절 0, lint 오류 0·깨진 wikilink 0, 새로 생긴 경고 0.

## Affected users and systems
위키를 조회하는 LLM 세션. vault 레포(`20_projects/**/feat-*.md`·프로젝트 허브·`index*.md`·크로스링크를 가진 페이지·`log.md`)와 판정에 쓰는 하니스 `llm-wiki/scripts/lint.py`(plan 1 반영본).

## Constraints
모델이 페이지마다 읽지 않고 스크립트로 처리(비용) · 구현 방법에 섞인 채택 이유가 함께 지워지는 것은 감수(사용자가 승인한 재진술의 제약) · 폐지 절 안의 함정·이유도 옮기지 않고 지운다(코디네이터 판정 — 판정 원칙 「비용 우선 — 스크립트 일괄」) · vault 커밋·push 는 llm-wiki 규약대로 · 다른 세션의 vault 변경을 삼키지 않음 · vault `*.md eol=lf` 원래 줄바꿈 유지 · DB 변경 금지.

## Open questions
없음
