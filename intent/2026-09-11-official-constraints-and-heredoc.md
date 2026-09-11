# Intent: 공식 권장을 축과 문서에 반영하고, 부분해로 남은 heredoc 오탐을 닫는다
Author: 사용자. Status: approved.

## Problem
회차 57 이 잘라 남긴 `[다음 회차]` 7건이 처방과 함께 있으나, **그 처방을 그대로 믿을 수 없다는 것이 회차 57 자신의 결론이다** — `skill-feedback` ②의 큐 항목이 제안한 처방(`Remove-HeredocDataSink`)은 착수해 보고서야 **부분해**임이 드러났다. 실제로 이번 재측정에서 처방 하나가 **구조적으로 성립하지 않음**이 확인됐다: 「`description`·`name` 상한을 `BUDGET.md` 예산 표에 행으로」는 그 표가 **파일 글로브 → `os.path.getsize`** 축에 1:1로 묶여 있어(`check-harness-consistency.py:625-650`), frontmatter 필드를 행으로 넣으면 **아무것도 재지 않는 죽은 행**이 된다. 그 상한은 이미 `AUTHORING.md`(문서 정본)와 `SKILL_FM_MAX`(기계 축) 두 곳에 있어 세 번째는 `BUDGET.md` 자신의 처방 ①(상위 규약 복창 금지)에도 걸린다.

남은 실체는 셋이다. ⓐ 공식 문서를 직접 받아 대조하니 **우리가 축도 문서도 갖지 않은 제약이 2건** 더 있다 — `name` 예약어 금지(`"anthropic"`·`"claude"`)와 `name`·`description` XML 태그 금지(현재 위반 0건이나 재는 것이 없다). ⓑ 공식이 *"Create evaluations BEFORE writing extensive documentation"* 을 핵심으로 두는데 우리 `AUTHORING.md` 에 그 구가 없고, 공식과 값이 갈리는 **비채택 3건**(TOC 100줄 · 모델별 테스트 · 최소 평가 3개)에 「왜 갈렸는가」가 적혀 있지 않다. ⓒ `skill-feedback` ②가 부분 해소로 잔류한다 — `python3 - <<PY` 형태의 heredoc 본문에 커밋 문구가 있으면 아직 커밋으로 읽혀 오차단된다(회차 55 실해: 사유가 「커밋 파일이 많다」로 나와 오탐이 안 보였다).

그리고 hook 비용은 회차 57 이 실측했으나 기록되지 않아, 다음 세션이 같은 측정을 되풀이해야 한다.

## Proposed outcome
공식 제약 5종이 **전건 기계로 재어진다**(길이 2 + 예약어 + XML 태그 + 본문 줄수는 현행 예산 축이 대신한다). 공식과 갈린 값마다 **근거와 URL** 이 `AUTHORING.md` 에 있어 다음 회차가 「공식을 안 봤나」를 다시 묻지 않는다. 태그 종류·싱크 여부와 무관하게 heredoc 본문이 커밋 판정에서 빠져, 규약 문구를 heredoc 에 담은 호출이 오차단되지 않는다 — **두 호출부가 같은 판정을 쓴다**(회차 57 완료 리뷰가 한쪽만 고친 것을 MAJOR 로 잡았다). hook 1회 비용이 재측정돼 `(기계 미대조)` 표시와 함께 기록된다.

## Affected users and systems
하니스 레포 — `plugins/pjc/skills/AUTHORING.md` · `plugins/pjc/evals/**`(검사기·골든·픽스처) · `plugins/pjc/scripts/guard-bash.ps1`·`guard-commit-secrets.ps1`·`guard-stale-docs.ps1` 와 그 근거 문서 · `plugins/pjc/hooks/evals/**` · `docs/harness-conventions.md` · `docs/golden-runner.md`. 위키 vault 는 `skill-feedback.md` 항목 종결 1건뿐이다. 읽는 쪽은 이후 모든 pjc 세션이고, 차단 판정 변경은 **모든 Bash 호출**이 지난다.

## Constraints
**차단 판정을 바꾼다** — `guard-commit-secrets`·`guard-stale-docs` 는 `AGENTS.md` 「DO NOT」이 지목한 안전 임계 hook 이 **아니다**(그 조문은 `block-destructive.ps1`·`guard-harness.ps1` 둘만 지목한다). 그래도 `exit 2` 를 내는 판정이라 **같은 수준의 실증(골든 양성 + 델타 음성)** 을 자발적으로 적용한다. `Remove-HeredocDataSink` 는 건드리지 않는다 — 그쪽의 판정 축은 「본문이 파일로 가는가」라 의미가 다르다. **새 케이스는 red 를 먼저 본다** — 회차 57 이 그 자리에서 실제로 걸렸다(픽스처가 판정 경로에 안 닿아 수정을 되돌려도 PASS 했다). 규칙 717개에 근거 달기(318건 미보유)와 `.github/` CI · Haiku·Sonnet 트리거 eval 은 이번 범위 밖이다.

## Open questions
없음 — 회차 범위와 「공식 제약 2건을 축에 붙인다」는 2026-09-11 사용자 결정으로 확정됐다. hook 비용의 저장처는 `docs/harness-conventions.md`(79,287/137,000 B)로 정했고 사용자가 이의를 내지 않았다.
