# Intent: 세그먼트 분할 공통화 · 판정 데이터 외부화 · 양성 골든 보강
Author: 사용자. Status: approved.

## Problem

회차 51 이 대장에 올린 3건이 남아 있다. ① `guard-bash.ps1` 26,228 B · `post-write-checks.ps1` 25,479 B 가 상한 25,000 B 를 넘었다 — 통지 등급이라 `exit 0` 은 유지되지만 「상한을 올리는 것은 처방이 아니다」이고 **다음 회차가 한 줄만 더해도 초과가 이어진다**. ② `sed -i "s|a|b|" plan.md` 가 차단을 빠져나간다 — 세그먼트 분할이 따옴표 안의 `|` 를 파이프로 보아 마지막 조각의 첫 토큰이 `"` 가 된다. 같은 분할이 `guard-bash.ps1` 안에 **4곳** 있고 정규식이 서로 다르다. ③ `block-plan-write` 의 7신호 중 3종(`cp`/`mv` · `Copy-Item` 계열 · `[System.IO.File]::WriteAll*`)에 양성 골든이 없어 **분기를 지워도 전건 green** 이다. 지금 하는 이유는 ②가 차단을 실제로 우회하는 경로이고, ③이 그런 우회를 앞으로도 못 잡게 하는 공백이기 때문이다.

## Proposed outcome

세그먼트 분할이 **따옴표 구간을 마스킹한 뒤** 나뉘고, 그 로직이 **헬퍼 하나**에 모여 4곳이 같은 것을 쓴다. 외부·비가역 작업 판정 패턴과 **경고 문면**이 `rules/external-ops.json` 으로 내려가 `guard-bash.ps1` 이 상한 아래로 돌아온다(배열만 옮기면 5 B 모자란다 — 실측). 신호 3종에 양성 골든이 붙어 분기를 지우면 red 가 난다.

## Affected users and systems

이 레포에서 작업하는 모든 세션(네 검사가 매 Bash 호출에 돈다). 걸리는 것은 `plugins/pjc/scripts/guard-bash.ps1` 과 그 근거 `rules/bash-guard-rationale.md` · 신설 `rules/external-ops.json` · `plugins/pjc/scripts/post-write-checks.ps1` · 두 hook 골든 시나리오 · 차단 경로 커버리지 검사기 · Deferred 대장이다.

## Constraints

`block-destructive` 가 이미 쓰는 json 로드 패턴을 그대로 따른다(로드 실패는 `exit 0` + stderr 가시화). **분할 동작을 바꾸는 것은 경고 검사 셋에도 영향을 주므로** 전량 골든으로 회귀를 확인한다. `post-write-checks.ps1` 은 `guard-bash` 와 공유하는 판정 데이터가 없어 감량 수단이 다르다 — 그 파일의 초과는 따로 판정한다.

## Open questions

없음.
