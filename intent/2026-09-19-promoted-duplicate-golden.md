# Intent: 승격 중복 조사 — 골든 러너·hook 검사 31항목
Author: 사용자. Status: approved.

## Problem

Deferred 대장의 [2026-09-17] 항목이 검증 자산 71항목으로 남아 있다. 원문 요청은 *"검증 자산 71항목도 계획 세워줘"* 이고, 인터뷰에서 **주제 단위 2회차**로 끊기로 해 이번은 「골든 러너 운용·픽스처」 24 + 「hook 검사·차단」 7 = **31항목**이다(직전 회차 32와 같은 규모라 오판률을 재현할 수 있다). 조사 중 `docs/golden-runner.md` 가 「현행 **925**케이스」를 기준선으로 담는 것을 확인했는데 위키에는 **923·643 두 옛 값**이 남아 있다 — 중복이면서 동시에 낡았다.

## Proposed outcome

31항목이 레포 문면과 대조돼 중복/부분중복/고유로 판정되고, 중복·부분중복은 D6 형식으로 축약된다. **낡은 값을 담은 항목은 레포 지목으로 대체해 값 자체를 위키에서 들어낸다** — `conventions` 는 항목 불변이 아니므로(schema §2.9) 이것이 정상 경로다.

## Affected users and systems

위키 `conventions-verification-3.md`(21) · `conventions-verification-2.md` 의 「골든을 돌리거나 픽스처를 고칠 때」(3) · `conventions-verification.md` 의 「hook 검사·차단」(7). 레포는 `docs/plans/deferred.md` 항목 요지와 `docs/plans/wiki-usage.md` 1줄.

## Constraints

**레포 실해를 복사해 오지 않는다** — 직전 회차가 그렇게 해서 중복이 순증했다. **검색어는 어간으로 쓴다**(조사를 붙여 정본을 놓친 오판이 직전 회차에 있었다). 커밋 메시지에 백틱·semver 를 넣지 않는다.

## Open questions

없음.
