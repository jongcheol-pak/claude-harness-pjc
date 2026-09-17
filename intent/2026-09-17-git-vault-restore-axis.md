# Intent: git vault 경로의 원복 축을 골든에 세운다
Author: 사용자. Status: approved.

## Problem
사용자 원문: *"`--auto-split` 골든 38케이스 중 git vault 경로가 2건뿐이다. 나머지가 git vault에서 다르게 도는지 미측정 — 어느 처방이 그 경로에서만 갈리는지 재고, 필요한 케이스를 정해 계획 세워줘."* 실측으로 갈림의 정체가 좁혀졌다 — **처방 4종의 로직은 갈리지 않고, 갈리는 것은 `SplitSession`의 원복 수단**(사본 복원 ↔ `git checkout --`)이다. 그런데 **원복을 태우는 `auto_split` 케이스 4건이 전부 비 git vault**라, git 경로의 원복은 코드를 지워도 골든이 green이다. 지금 하는 이유는 회차 73이 git vault 경로를 연 직후라 그 경로의 사각이 아직 하나도 소비되지 않았다는 것이다.

## Proposed outcome
git vault에서 처방이 실패했을 때의 원복(기존 파일 복원 · 신설물 제거 · 원본 불변)을 재는 골든 케이스가 실재하고, 그 경로가 줄바꿈을 훼손하지 않는다. 케이스를 지우거나 원복 분기를 지우면 골든이 red가 된다.

## Affected users and systems
위키 vault를 git으로 관리하는 사용자(현행 LLM WIKI vault가 그렇다)와 `pjc:llm-wiki` 절차 F·A·B가 부르는 `--auto-split`. 걸리는 코드는 `lint.py`의 `SplitSession.backup`·`restore`, 골든 러너 `run_lint_evals.py`, 케이스 대장 `lint-cases.json`, 기준선 기록 `docs/harness-conventions.md`.

## Constraints
픽스처 워킹트리는 CRLF 규약을 유지한다 — LF 조건은 러너가 사본에 심는다(`bad_encoding_paths`와 같은 방식). 케이스 수를 바꾸므로 `check-harness-consistency.py`가 필수이고 기준선 기록을 함께 갱신한다. 안전 임계 hook은 건드리지 않는다.

## Open questions
없음.
