# Intent: 산문 백틱 경로의 실존을 기계가 잰다
Author: 사용자 (회차 64 가 남긴 `[다음 회차]` 축 1). Status: approved.

## Problem

`guard-stale-docs.ps1` 층 3 의 첫 축이 *"산문 서술 — 이 문서가 코드 동작을 서술하는 자리는
어느 검사기도 재지 않는다"* 라, `docs/harness-conventions.md`(71 KB)가 스테이징되기만 하면
무조건 발화해 **"어딘가 낡았을 수 있다"** 만 말한다. 원문 요청: *"`docs/harness-conventions.md`
산문이 백틱으로 인용한 **경로·심볼의 실존**을 `check-stale-refs.py`가 재게 한다. … 백틱 토큰의
실존을 기계가 재면 **서술이 가리키는 대상이 사라진 자리**는 걸리고, 사람에게 남는 것은 "동작이
이렇게 돈다"는 문장의 진위뿐이라 그 고지가 좁아진다."* **지금 하는 이유**는 착수 조건인
*"StaleAxisBaseline 3 이 안정된 것을 1회차 이상 관측"* 을 회차 64 가 4→3 으로 내리고 골든
906/906 으로 검증해 충족시켰기 때문이다.

## Proposed outcome

`check-stale-refs.py` 가 그 문서의 백틱 **경로** 토큰을 뽑아 실존을 대조하고, 없으면 exit 1 이다.
그 결과로 층 3 축 1 의 고지가 「경로 실존은 기계가 재고 남는 것은 서술의 진위와 무구분자
심볼뿐」으로 좁아진다.

## Affected users and systems

이 레포에서 커밋 직전 고지를 받는 모든 코드 세션. 걸리는 자산은 `plugins/pjc/evals/check-stale-refs.py` ·
`plugins/pjc/evals/cases.json`(+ `fixtures/refs-repo`) · `plugins/pjc/scripts/guard-stale-docs.ps1` ·
`docs/harness-conventions.md` 다.

## Constraints

**사정거리는 경로만이다**(인터뷰 Q1 — 사용자 선택). 심볼은 실측 오탐 4/85 가 전부 이력
인용이라 면제 규칙 자체가 또 하나의 「낡을 목록」이 되므로 다음 회차로 미룬다. 대상 문서도
하나뿐이다 — 전체 `*.md` 로 넓히면 후보 706 · 미실존 191 이라 성립하지 않는다. **hook 에는
넣지 않는다** — 검증 매핑이 `docs/**` 수정에 이미 이 검사기를 붙이므로 커밋 비용을 0 으로 둔다.

## Open questions

없음.
