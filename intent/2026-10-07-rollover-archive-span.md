# Intent: 롤오버가 아카이브 포인터·인덱스의 범위와 건수를 「이번 이동분」으로 덮어쓰는 결함
Author: 사용자. Status: approved.

## Problem
원문 요청: 「lint.py 포인터 결함도 고쳐줘」 — Karina 위키 큐 정리 세션에서 드러났다. `--auto-split` 롤오버가 decision-log·허브 `## 아카이브` 포인터의 날짜 범위를 아카이브 파일 전체가 아니라 그 실행에 옮긴 항목만으로 다시 쓰고, `log.md` `## 아카이브 인덱스` 월 줄은 기존 월 파일이 있어도 건수·기간을 이번 이동분으로 덮는다. 실 vault 에서 Karina 결정 포인터 「2026-10-06~2026-10-06, 누적 405건」(실제 07-22~10-06), log 인덱스 「2026-09.md: 21건」(실제 311건)처럼 조회 진입점이 거짓을 말한다.

## Proposed outcome
롤오버 뒤 포인터의 범위는 아카이브 파일의 가장 오래된 항목~가장 최신 항목, log 인덱스 월 줄의 건수·기간은 그 월 파일 전체를 센 값이다. 기존 골든 중 결함 값을 기대값으로 고정한 것은 바른 값으로 바뀌고, 기존 월 파일에 append 하는 log 롤오버를 재는 골든이 생긴다. 실 vault 의 어긋난 log 인덱스 줄은 실측값으로 고쳐진다.

## Affected users and systems
pjc 하네스로 LLM WIKI 를 운영하는 세션(절차 F-2·A-4·B-3·I-4 의 `--auto-split`, 조회 K·G 가 포인터로 아카이브를 찾는 경로). `plugins/pjc/skills/llm-wiki/scripts/lint.py` · `llm-wiki/evals/` · `docs/harness-conventions.md` 기준선 · 실 vault `log.md`.

## Constraints
포인터·인덱스의 기존 형식(실 vault 의 wikilink 형식 포함)을 바꾸지 않는다. 아카이브 본문은 손대지 않는다(항목 불변). 스키마 문면(§2.8·§2.2·§8)과 같은 뜻으로 맞춘다 — 문면은 이미 「가장 오래된~가장 최신」이다.

## Open questions
없음
