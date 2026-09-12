# Intent: 산문 백틱 심볼의 실존과 영향 검토 3축을 기계가 잰다
Author: 사용자 (회차 65 가 남긴 `[다음 회차]` 중 착수 조건이 충족된 둘). Status: approved.

## Problem

**축 ①** — 회차 65 가 산문 백틱 **경로**의 실존만 재고 심볼을 다음 회차로 미뤘다. 미룬
근거는 *"심볼은 실측 오탐 4/85 가 전부 이력 인용이라 면제 규칙 자체가 또 하나의 「낡을
목록」이 된다"* 였다. 착수 조건이던 *"경로 축이 실제로 무언가를 잡은 관측 1건"* 은 회차 65 가
충족시켰다 — `docs/harness-conventions.md` 가 gitignore 대상인 `docs/.agents-presplit/` 를
가리키던 자리를 그 축이 양성으로 잡았고 서술을 고쳐 닫았다(커밋 `0bf422bd`).

**축 ②** — 「개정·개선 전 영향 검토 (3축)」은 규약이 있고 `plan-template.md:104` 가 기재를
요구하는데 **재는 기계가 없다**. 착수 조건이던 *"T1 이 지켜지는지 1회차 관측"* 을 회차 65 가
수행했다(그 회차 `plan.md` 의 Investigation Log 에 3축 행을 실었다).

## Proposed outcome

- `check-stale-refs.py` 가 `docs/harness-conventions.md` 의 백틱 **심볼**(구분자 없는 토큰)
  실존을 대조하고, 없으면 exit 1 이다. 그 결과로 `guard-stale-docs` 층 3 축 1 의 고지가
  한 번 더 좁아진다 — 사람에게 남는 것은 「동작이 이렇게 돈다」는 문장의 진위와
  **`.`·`-`·`_` 도 없는 순수 식별자**뿐이다.
- `check-harness-consistency.py` 가 `plan.md` 의 Investigation Log 에 3축 행이 실렸는지를
  잰다. 대상 판정은 그 계획의 `- **Files**:` 줄이 hook·스킬·에이전트·검사기·규약 문서를
  담는가이고, 부분 기재(한 축만 싣고 나머지를 빠뜨림)도 red 다.

## Affected users and systems

이 레포의 모든 코드 세션. 걸리는 자산은 `plugins/pjc/evals/check-stale-refs.py` ·
`plugins/pjc/evals/check-harness-consistency.py` · `plugins/pjc/evals/cases.json`
(+ `fixtures/refs-repo` · `fixtures/minimal-repo`) · `plugins/pjc/scripts/guard-stale-docs.ps1` ·
`docs/harness-conventions.md` · `plugins/pjc/skills/plan/references/plan-template.md` 다.
CI(`.github/workflows/checks.yml`)가 두 검사기와 골든 러너를 모두 돌린다.

## Constraints

- **축 ①의 필터는 「필터 D」다**(인터뷰 Q1 — 사용자 선택): hex SHA 제외 · `--` 접두 제외 ·
  구분자(`.`·`-`·`_`) 1개 이상 요구. **셋 다 구조 규칙이라 유지 목록이 생기지 않는다** — 이것이
  회차 65 가 경고한 「낡을 목록」의 대가를 치르지 않는 경로다. 실측 후보 77 · 오탐 1건이고
  그 1건은 문서 서술을 고쳐 닫는다(회차 65 가 경로 축에서 쓴 것과 같은 처방).
- **회차 65 가 처방 후보로 적은 셋 중 채택은 ⓐ 하나다.** ⓑ(확장자만 있고 구분자 없는 토큰을
  경로 축으로 이관)는 오탐을 다른 축으로 옮길 뿐 닫지 못하고, ⓒ(`HISTORY_VERB_RX` 에
  「바뀌었다」 추가)는 그 정규식이 **다른 축(삭제 자산 참조)의 소유**라 산문 축에는 닿지 않는다.
- **축 ②의 게이트는 「경로 게이트 + 부분 기재 금지」다**(인터뷰 Q2 — 사용자 선택).
- **심볼 축의 corpus 는 `git ls-files` 로 짓는다 — 파일시스템 순회가 아니다.** 순회하면
  `plan.md`·`notes.md` 같은 gitignore 대상이 실존 근거가 되어 같은 커밋이 로컬 exit 0 ·
  프레시 체크아웃 exit 1 로 갈린다(회차 65 완료 리뷰 BLOCKER 의 재발 경로다).
- **hook 에는 넣지 않는다** — 검증 매핑이 `docs/**`·`plugins/pjc/evals/**` 수정에 두 검사기를
  이미 붙이므로 커밋 비용을 0 으로 둔다.

## Open questions

없음.
