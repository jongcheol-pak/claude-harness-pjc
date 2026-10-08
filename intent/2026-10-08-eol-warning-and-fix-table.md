# Intent: EOL 경고는 레포가 실제로 CRLF 일 때만, --fix 는 크기 임계 표도 고친다
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「1·3번 묶음 계획 세워줘」 — Deferred 대장 2건. ① `post-write-checks.ps1` EOL 경고가 eol 속성 없는 파일에서 기계 설정 `core.autocrlf=true`(Git 설치본 시스템 gitconfig)를 레포 규약으로 읽어 LF·혼합 레포(Karina — 대상 확장자 추적 파일 CRLF 98 / LF 186)에 오경보를 냈고 문구가 하네스 레포 `AGENTS.md` 를 가리켰다(2026-10-08 오경보 11회). ② `check-harness-consistency.py --fix` 가 「조건부 참조 문서 크기 임계」 표의 기록값 불일치(exit 1)를 고치지 않으면서 「고칠 것 없음」을 낸다(2026-09-21 왕복 1회 · 2026-10-08 두 회차가 손으로 맞춤).

## Proposed outcome
eol 속성이 없는 파일은 검사 대상 확장자의 추적 파일 중 90% 이상이 워킹트리 CRLF 이고 표본이 충분할 때만 EOL 경고를 내고, `core.autocrlf` 는 보지 않으며, 문구에 하네스 레포 참조가 없다 — Karina 같은 혼합 레포는 무경고, 하네스 레포는 지금처럼 경고, 속성이 있으면 속성이 이긴다. `--fix` 는 크기 임계 표의 기록값을 실측 문자 수로 고치고(자기 행은 안정될 때까지), `--dry-run` 은 쓰지 않고 보이기만 한다. 각 동작을 골든 케이스가 잰다.

## Affected users and systems
플러그인이 붙은 모든 레포의 세션(EOL 경고)과 이 하니스 레포 회차(`--fix`). `post-write-checks.ps1`·근거 §15·hook 골든 · `check-harness-consistency.py`·근거 문서·evals 골든 · `docs/harness-conventions.md`·`docs/golden-runner.md`.

## Constraints
EOL 경고는 비차단(exit 0) 유지. `--fix --dry-run` 은 한 바이트도 쓰지 않는다. 표의 상한 초과는 고치지 않는다. hook 실행 비용은 git 호출 1회 이내. 차단 hook 은 고치지 않는다.

Q: eol 속성이 없는 파일은 무엇으로 「이 레포는 CRLF」를 판정할까요? 선택지: 추적 파일 압도적 다수 (권장) / 단순 다수결 / 같은 폴더 다수. A: 추적 파일 압도적 다수 (권장)
Q: --fix 는 크기 임계 표의 기록값을 직접 고치게 할까요, 「이 축은 수동」이라고 알리게만 할까요? 선택지: --fix 가 고친다 (권장) / 수동이라고 알린다. A: --fix 가 고친다 (권장)
후보 라운드: 후보 없음.

## Open questions
없음
