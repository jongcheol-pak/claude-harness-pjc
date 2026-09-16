# Intent: 태그 목록 복제를 재는 축 · red 확인의 되돌리기 수단

Author: 사용자. Status: approved.

## Problem

원문 요청: *"skill-feedback 2건도 하네스 레포에서 처리하자"*. `skill-feedback.md` 에 대기하던 `[SKILL-IMPROVE]` 둘이다.

**① red 확인의 되돌리기 수단이 문면에 없다** — `implement/SKILL.md:70` 이 *"그 변경을 되돌린 상태에서 1회 돌려 red 를 본다"* 라고만 적고 **무엇으로 되돌리면 안 되는지**가 없다. 실해: 2026-09-15 Maid 좌측 목록 정합 ①회차가 `git checkout -- <파일>` 로 되돌렸다가 **같은 파일에 있던 아직 커밋하지 않은 다른 task(T6·T7)의 편집을 통째로 잃었다.** red 확인은 「고쳐 놓고 잠깐 깨뜨린다」라 그 시점의 워킹트리가 유일한 사본이다.

**② 큐 태그 집합의 개별 열거를 재는 축이 없다** — 태그 이름 열거가 여러 파일에 사본으로 살고 그 전수를 재는 기계 검사가 없다. 7번째 태그(`[K-ROUTE]`)를 추가하려던 회차 71 이 `grep` 으로 쫓다 **3라운드 연속 BLOCKER** 를 냈고 매 라운드 새 자리가 나왔다(1R 소비 트리거 · 2R `procedures-ops.md:66` 과 개별 열거 2곳 · 3R 같은 줄 안의 두 번째 열거와 `queue-consume-rules.md:9` 축 오독). 문자열 검색으로 전수가 서지 않는 이유는 **수 표현(「다섯 태그」)과 태그 이름 개별 열거가 서로 다른 문면**이라 한쪽 검색어로 다른 쪽이 안 나오기 때문이다.

## Proposed outcome

① `pjc:implement` 의 red 확인이 **커밋 뒤에** 일어나고, 되돌릴 때 파일 전체가 아니라 **깨뜨린 그 한 줄만** 되돌린다.

② `check-harness-consistency.py` 에 축 ㉑ 「큐 태그 열거 정합」이 생겨, 태그 열거 자리의 전수가 기계로 확정된다. 다음 회차의 `[K-ROUTE]` 신설이 그 축 위에서 진행된다(대장 `[다음 회차]` 항목의 착수 조건).

## Affected users and systems

pjc 하니스를 쓰는 모든 코드 레포 세션. 걸리는 자산은 `implement/SKILL.md`, `plugins/pjc/evals/check-harness-consistency.py`, `harness-consistency-rationale.md`, `plugins/pjc/evals/cases.json`(골든), `docs/harness-conventions.md`.

## Constraints

- **정본 집합은 셋이다** — `pending.md` 가 담는 5개(`[DECISION]`·`[PROJECT-FACT]`·`[K-DRIFT]`·`[K-MISS]`·`[SYMPTOM]`) · `skill-feedback.md` 가 담는 1개(`[SKILL-IMPROVE]`) · 전체 6개. **「6개가 아니면 틀렸다」로 재면 `lint.py:15` 의 정상 5개 열거가 곧바로 오탐이 된다.**
- **acceptance 에 오탐 측정이 들어간다** — `decisions.md` 2026-09-13 §7-37 폐기 사례의 재설계 조건이다. 다만 그 축은 vault 페이지를 재는 `lint.py` 축이었고 **이 축은 레포 문서를 재므로 측정 대상은 실 vault 가 아니라 실 레포 전수**다.
- **`[K-ROUTE]` 태그 신설은 이번 범위 밖이다** — 축이 자기 회차가 만든 변경을 재게 되면 red 실증이 오염된다.
- 축 번호는 **㉑** 이다 — ⑫⑬ 은 결번이고 재사용하면 한 문자열이 두 축을 뜻한다.

## Open questions

없음.
