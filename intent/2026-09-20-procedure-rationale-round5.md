# Intent: 위키 절차 근거 분리 5회차 — A·I·B-1·B-1a
Author: 사용자. Status: approved.

## Problem

`procedures-content.md`(28,048자)는 절차 수행 세션이 `offset`+`limit` 으로 부분 Read 하는 문서인데, 각 절차 안에 *무엇을 언제 어떻게 하는가*와 *왜 그렇게 정했는가*가 섞여 있어 수행에 필요 없는 근거까지 매번 읽힌다. 4회차가 B-2 하나에서 1,476자를 걷어 수단을 실증했고(7,659 → 6,183), 사용자의 요청은 *"① `procedures-content.md` 나머지 절차의 근거 분리 ② B-1a·B-1 축소"* 다. 지금 하는 이유는 수령처 `procedures-rationale.md` 가 4회차에 이미 생겨 절만 얹으면 되기 때문이다.

## Proposed outcome

A·I·B-1·B-1a 의 근거 문면이 `procedures-rationale.md` 로 옮겨지고, 각 절 머리의 포인터 1줄이 그리로 가는 경로가 된다. 절차 수행 세션이 읽는 양이 약 2,500자 줄고, 옮긴 문면은 한 자도 사라지지 않는다.

## Affected users and systems

`pjc:llm-wiki` 의 절차 수행 세션(A 등록 · B ingest · I 가이드 작성)이 사용자다. 걸리는 것은 `references/procedures-content.md` · `references/procedures-rationale.md` 둘이고, 정합 검사기 `check_consistency.py`(산문 포인터 축)와 `check-harness-consistency.py`(포인터 도달성 축)가 그 결과를 잰다.

## Constraints

문면 압축·삭제는 하지 않는다(이관만 — `E-2` 가 *"덜어내고 링크로 대체하는 방식은 쓰지 않는다"* 로 금지한다). C·D·E 는 수확이 포인터 비용 이하라 제외한다. 수령처 증가 상한은 4회차 실측 계수로 「걷은 양 × 2.4」다.

## Open questions

없음
