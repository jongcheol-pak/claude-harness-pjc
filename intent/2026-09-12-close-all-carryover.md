# Intent: 회차 65 가 남긴 넷을 전부 닫아 「다음 회차」를 없앤다
Author: 사용자. Status: approved.

## Problem

회차 65 가 `[다음 회차]` 6건을 남겼고 회차 66 이 그중 **착수 조건이 충족된 2건만** 닫았다.
남은 4건은 「착수 조건 미충족」으로 다시 이월됐는데, **사용자의 원 지시는 「다음 회차로
더이상 절대 남기지 않도록」이었다.** 회차 66 이 그 지시를 「조건이 충족된 것만」으로 좁혀
읽은 것이 결함이다.

**그리고 그 「미충족」 판정 자체가 틀렸다** — 넷 다 **재면 갈리는 조건**이었지 기다릴 조건이
아니었다. 회차 65 도 회차 66 도 그 조건을 재는 명령을 돌리지 않았다. 이번에 실측한 결과:

| 항목 | 등재된 착수 조건 | 실측 판정 |
|---|---|---|
| ① 외부 사실 `verified` TTL | 새 규약 문면의 실해 관측 1건 | **충족** — `AGENTS.md:113` 이 「권장 v2.1.219+」인데 실제 설치본은 **v2.1.269** 다(50 패치). 근거로 적힌 *"`completion-reviewer` 의 `opus` 별칭 해소"* 도 이미 지난 이슈다 |
| ② 「영향 검토」↔「규약 개정 요청」 경계 | 규약 개정 회차 1건 | **충족** — 회차 66 의 T7·`6b36df10` 이 두 규약 문면을 실제로 고쳤다 |
| ③ `Get-StaleFeatures` ↔ `lint.py` 파서 드리프트 | 한쪽만 바뀐 사례 1건 | **충족 — 이미 갈려 있다.** 드리프트 2건을 실측했다 |
| ④ 산문 백틱 축 대상 문서 확대 | 확대 대상 1건의 오탐 실측 10% 미만 | **충족** — 후보 8문서 **전부** 10% 미만(0.0%~9.5%) |

## Proposed outcome

넷을 이번 회차에 전부 닫는다. **이 회차는 `[다음 회차]` 를 남기지 않는다.**

- ① `AGENTS.md` 의 외부 사실 줄에 `verified` 표기를 두고, `guard-stale-docs` 층 3 축 2 가
  그 날짜를 읽어 **90일이 지났을 때만** 고지한다. 표기가 없으면 종전대로 항상 고지한다(fail-closed).
- ② 영향 검토 3축의 ① 충돌 축이 **「이 변경이 규약 문서를 고치게 되는가」**를 판정하면
  「규약 개정 요청의 취급」의 ⓐⓑⓒ 를 요구하도록 두 절을 잇는다.
- ③ `Get-StaleFeatures` 를 `lint.py` §7-21 쪽으로 맞추고(정본은 `wiki-schema:176` 의
  `- ` 목록 형식), **두 파서가 다시 갈리는 것을 재는 기계 축**을 신설한다.
- ④ 산문 두 축의 대상을 **9문서**로 넓힌다. 구조 규칙 둘(분수·비율 · URL)을 더하고,
  잔여 오탐 11건은 **백틱을 벗겨** 닫는다.

## Affected users and systems

이 레포의 모든 코드 세션. 걸리는 자산은 `plugins/pjc/evals/check-stale-refs.py` ·
`plugins/pjc/evals/check-harness-consistency.py` · `plugins/pjc/evals/cases.json`(+ 픽스처) ·
`plugins/pjc/scripts/guard-stale-docs.ps1` · `plugins/pjc/scripts/session-wiki-signals.ps1` ·
`plugins/pjc/hooks/evals/scenarios/guard-stale-docs.ps1` · `docs/harness-conventions.md` ·
`AGENTS.md` · `README.md` · `docs/golden-runner.md` · `plugins/pjc/skills/{DESIGN,AUTHORING,BUDGET}.md` ·
`plugins/pjc/evals/harness-consistency-rationale.md`.
CI(`.github/workflows/checks.yml`)가 두 검사기와 골든 러너를 전부 돌린다.

## Constraints

- **④ 의 잔여 오탐 11건은 「낡을 목록」을 만들지 않고 닫는다** — 11건 전부 **실재를 주장하지
  않는 인용**이다(레포 밖 vault 경로 · gitignore 대상을 「커밋 금지」로 서술 · 가상 예시 ·
  외부 도구 이름 · frontmatter 필드명). 회차 66 이 세운 *「백틱은 실재 주장이다」* 규약을
  그 범주까지 넓혀 적용하는 것이지 면제 목록을 만드는 것이 아니다.
- **① 은 규약 개정이다**(인터뷰 Q1 — 사용자가 「`verified` TTL 도입」을 선택). 대안이었던
  「값만 갱신」은 같은 낡음이 다시 쌓이는 경로라 기각, 「축 2 를 없앤다」는 재는 자리가
  통째로 사라져 기각.
- **`StaleAxisBaseline` 은 3 그대로다** — ① 은 축 2 의 **발화 조건**을 바꿀 뿐 축을 늘리거나
  줄이지 않는다.
- **③ 은 `lint.py` 를 고치지 않는다** — 정본 형식에 맞는 쪽이 `lint.py` 이므로 움직이는 것은
  `Get-StaleFeatures` 다. 안전 임계 hook 이 아니라 경고·신호 경로다.
- **hook 변경은 설치 캐시에 반영돼야 실제로 돈다** — 워킹트리 검증은 골든이 대신하고,
  실사용 확인은 재설치 뒤다(HUMAN-VERIFY).

## Open questions

없음.
