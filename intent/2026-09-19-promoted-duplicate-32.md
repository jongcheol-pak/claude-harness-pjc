# Intent: 승격 중복 조사 — 스크립트·구조·릴리즈 32항목
Author: 사용자. Status: approved.

## Problem

Deferred 대장의 [2026-09-17] 「승격 중복 조사 나머지 95항목」이 대기 중이다. 위키 `conventions-*.md` 의 규칙 문장 중 일부가 레포 스킬 문면으로 이미 승격돼 있어, 계획 세션이 같은 규칙을 위키에서 다시 읽는다 — 순수 비용이고 읽은 절 수(N)만 늘려 `wiki-usage.md` 의 M/N 판정을 흐린다. 원문 요청은 *"승격 중복 95항목 계획 세워줘"* 이고, 인터뷰에서 범위를 **스크립트·구조·릴리즈 32항목**으로 한정했다(검증 자산 71항목은 조건부 로드라 상시 비용이 없어 대장에 남긴다).

## Proposed outcome

`conventions-2.md`(13) · `conventions-3.md`(11) · `conventions-release.md`(8) 전 32항목이 레포 문면과 대조돼 중복/부분중복/고유로 판정되고, 중복·부분중복분은 회차 79 의 D6 형식(레포 경로를 정본으로 지목 + 실해만 남김)으로 축약된다. 항목은 지워지지 않는다.

## Affected users and systems

위키 vault 의 `20_projects/personal/claude-harness-pjc/conventions-{2,3,release}.md` 3파일과, 레포 `docs/plans/deferred.md` 의 해당 대장 항목 1건. 읽는 쪽은 절차 K 2 로 이 파일들을 여는 모든 코드 세션이다.

## Constraints

축약이지 삭제가 아니다 — 실해를 남긴다(그 규칙을 완화하자는 제안이 왔을 때의 반박 근거). 대조 대상은 레포 문면이고 위키끼리의 중복은 이번 축이 아니다. vault 는 병행 세션이 `pending.md` 를 고치고 있어 커밋은 경로 한정으로 한다.

## Open questions

없음.
