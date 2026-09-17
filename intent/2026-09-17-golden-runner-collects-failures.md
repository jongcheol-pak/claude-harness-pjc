# Intent: 골든 러너가 앞 축에서 끊지 않고 실패를 모아 보고한다
Author: 사용자. Status: approved.

## Problem

원문 요청: *"대장에 등재된 파일 축 검증 다음 회차로 계획 세워줘"* — 직전 회차가 `[다음 회차]` 로 남긴 항목이다. 그 회차는 `auto-split-dirty-reject`·`fix-dirty-reject` 두 케이스의 rationale 에 *"`expect_unchanged`·`expect_absent_files` 가 두 번째 축이다"* 를 적었으나, **변이 실증이 실제로 red 로 만든 것은 rc 축뿐이었다** — 러너가 rc 불일치에서 즉시 `return` 해 파일 축에 도달하지 못한다. 즉 그 축이 실제로 무는지는 아무도 확인하지 않았다. **지금 하는 이유는 이 사각이 그 두 케이스만의 문제가 아니기 때문이다** — `auto_split`·`fix_mode` 두 핸들러 전체에서 앞 축의 실패가 뒤 축을 가리고, 어떤 변이를 걸어도 앞 축이 먼저 걸리면 뒤 축은 영원히 검증되지 않는다.

## Proposed outcome

한 케이스가 여러 축을 어겼을 때 러너가 **그 전부를 모아 보고**한다. 그래서 변이 하나로 rc 축과 파일 축이 함께 발화하고, 「앞 축이 뒤 축을 가린다」는 사각이 두 핸들러에서 사라진다.

## Affected users and systems

이 레포에서 골든을 돌리는 회차 전부. 걸리는 것은 `plugins/pjc/skills/llm-wiki/evals/run_lint_evals.py` 의 `auto_split`·`fix_mode` 핸들러와, 그 판정 서술을 담은 `lint-cases.json` 의 rationale이다.

## Constraints

- **케이스 수와 PASS/FAIL 판정은 바뀌지 않는다** — 바꾸는 것은 실패 *사유의 수집 방식*이지 통과 기준이 아니다.
- 정리(`undo_split_failures`·`rmtree`)와 SKIP(git 미설치)은 조기 종료를 유지한다 — 전자는 자원 회수라 누락되면 임시 폴더가 남고, 후자는 그 뒤 판정이 성립하지 않는다.
- `dry-run` 무변경 계약 위반도 조기 종료를 유지한다 — 그 시점에 파일이 이미 오염돼 이후 판정이 무의미하다.
- 새 관용구를 만들지 않는다 — 같은 파일의 `chunk_split` 핸들러가 이미 `problems` 수집 형태를 쓴다.

## Open questions

없음
