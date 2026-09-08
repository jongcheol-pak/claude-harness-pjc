# Intent: 위키·하니스 스킬 결함 검토 결과를 대장 등재 없이 전부 수정한다
Author: 사용자. Status: approved.

## Problem
원문 요청: *"위키,하니스 스킬에 결함이 있는지 검토"* → *"대장 등재보다 모두 수정하면 안되나?"*. 2026-09-08 검토(subagent 5 + 직접 재현)가 검사기 11종이 전부 green 인 채로 살아 있는 미등재 결함 약 40건을 냈다 — hook 골든 2건 FAIL(낡은 앵커), 자기보호 집합에 `write-gate-exempt` 누락, force push 후치 `-f`·MSYS 루트·PowerShell 따옴표 미탐, E7 완료 커밋 게이트 사문화, lint.py 롤오버의 아카이브 쓰기 실패 무시(항목 유실), `--fix --dry-run` 실쓰기, llm-wiki 절차 6곳의 폐기 F-6.5 전제, 계획 단계 위키 조회 정본 이중화 등. **지금 하는 이유**: 대장은 이미 대기 106건이라 등재는 사실상 방치이고, 그중 데이터 유실·차단 미탐은 관측 경로가 없어 기다려도 신고되지 않는다.

## Proposed outcome
검토가 낸 미등재 결함 전건이 수정돼, ① 재현 입력이 기대 exit 를 내고 ② hook 골든·lint 골든·이관 골든·정합 검사기가 전부 exit 0 이며 ③ 폐기 식별자·죽은 § 라벨의 잔존 grep 이 0건이고 ④ description 을 고친 두 스킬의 트리거 eval 이 기준선 이상이다. 회차 3개로 나눈다 — ① hook 안전·게이트 → ② lint.py·relocate-agents.py 데이터 유실 → ③ 스킬 문면·description·골든 정합.

## Affected users and systems
이 하니스로 작업하는 모든 pjc 세션(코드 프로젝트 포함). 걸리는 시스템: `plugins/pjc/scripts/*.ps1`·`rules/*` 와 hook 골든, `llm-wiki/scripts/lint.py`·`record-project-fact/scripts/relocate-agents.py` 와 각 골든, `skills/{plan,implement,llm-wiki,pjc-systematic-debugging}/**`·`WIKI.md`·`AGENTS-BOUNDARY.md`·`agents/*.md`, `docs/harness-conventions.md`·`docs/golden-runner.md`, `validate.ps1`.

## Constraints
안전 임계 hook 변경은 「오탐 수정·미탐 보완」 두 종류만이며 델타 음성 케이스 실증이 필수다. 게이트 등급 문서 예산(SKILL 12,000 B 등)을 넘지 않는다. 워킹트리 CRLF 를 유지한다. description 수정은 회차 ③에 몰아 트리거 eval 을 스킬당 1회만 돌린다. 인터뷰 확정: 완료 커밋 제목은 `{유형}: T<N> — …` 로 통일 · F-6.5 자동 소비는 복원하지 않고 잔존 참조를 삭제 · 디버깅 스킬은 원인 규명까지 맡고 비trivial 수정은 `pjc:plan`→`pjc:implement` 로 넘김 · 계획 단계 위키 조회 정본은 `WIKI.md` 하나이고 절차 K 는 디버깅 세션 전용으로 좁힘.

## Open questions
없음.
