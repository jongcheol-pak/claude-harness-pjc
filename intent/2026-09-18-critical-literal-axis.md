# Intent: 호출 문면 소실을 검사기 축으로 감시한다
Author: 사용자. Status: approved.

## Problem

직전 삭제 회차(v1.298.0)가 남긴 결함 3·4·5 다 — `plan-template.md` 의 `> BASE:` 슬롯 · `WIKI.md` 의 `({근거})` 꼬리 · 두 SKILL.md 의 `K 5-2` 호출은 **지금 지워도 검사기 8종이 전부 exit 0** 이다(evals 3개 디렉터리 grep 실측: 그 리터럴을 참조하는 검사기 0건). 세 자리 모두 규약 정본은 다른 파일에 있고 이 문면이 그 정본에 닿는 **유일한 호출 지점**이라, 지워지면 규약이 살아 있어도 도달 경로가 끊긴다. 사용자 원문 요청: *"축 ⑩ 「핵심 포인터 실재」를 리터럴 문면까지 검사하도록 확장한다 … 축 번호는 늘리지 않고 ⑩ 안에 둔다."* 지금 하는 이유는 삭제 회차가 막 끝나 남은 문면을 보고 어디에 축을 걸지 정할 수 있는 시점이기 때문이다.

## Proposed outcome

축 ⑩ 이 파일 basename 뿐 아니라 **지정한 리터럴 문면의 실재**도 재고, 네 자리 중 어느 하나라도 사라지면 `check-harness-consistency.py` 가 exit 1 을 낸다. 그 회귀 검출이 골든 케이스로 실증된다.

## Affected users and systems

이 레포에서 문면을 삭제·치환하는 모든 회차. 걸리는 자산은 `plugins/pjc/evals/check-harness-consistency.py`(축 로직) · `cases.json` + `fixtures/minimal-repo`(골든) · `docs/harness-conventions.md` 와 `harness-consistency-rationale.md`(축 서술의 정본·파생).

## Constraints

- 축 번호를 늘리지 않는다 — 축 ⑩ 안에 둔다(축 수 계수 문면 불변, 기존 골든 3건의 `expect_keywords` 인 「핵심 포인터 실재」 라벨 불변).
- 기존 `CRITICAL_POINTERS_BASELINE` 과 같은 손목록 + 기준선 상수 패턴을 쓴다.
- 골든은 대표 1자리(`implement/SKILL.md` 의 `K 5-2`)만 잰다 — 픽스처에 파일을 새로 늘리지 않는다.

## Open questions

없음.
