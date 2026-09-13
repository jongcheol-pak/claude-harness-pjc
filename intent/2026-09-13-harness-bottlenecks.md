# Intent: 하니스의 병목·중복 읽기 4건을 해소한다

Author: 사용자. Status: approved.

## Problem

*"병목, 여러번 읽는 문제, 중복, 불필요한 작업이 있는지 검토"* — 실측으로 넷이 나왔다. ① `plugins/pjc/evals/run-evals.py` 가 94케이스를 **직렬**로 돌아 **25.4초**다(케이스마다 `subprocess` 로 검사기를 새로 띄우고 임시 트리를 만든다 — `run_case()` 는 서로 독립인데 병렬 축이 없다). 같은 문제를 hook 골든은 v1.159.0 에서 시나리오 단위 병렬로 이미 해소했다(`deferred-closed.md:173` — 27분 25초 → 14분 58초). ② `plugins/pjc/scripts/post-write-checks.ps1` 이 **같은 파일에 `git diff HEAD` 를 두 번** 호출한다(`:153` 시크릿 스캔용 `--unified=0` · `:203` 심볼 추출용 전체). 심볼 추출은 `+` 라인만 보므로 `--unified=0` 결과로 충분해, 코드 확장자 파일을 편집할 때마다 git 호출 1회가 순수 낭비다. ③ `docs/harness-conventions.md` 는 **82,359B** 인데 세션이 필요로 하는 것은 보통 **1개 절**(18절 · 절 평균 2,416자)이다. `session-context.ps1` 이 절 제목 목차를 주입하면서 *"해당 절이 필요하면 그 파일을 Read"* 라고만 해 전문 Read 가 전제된다. ④ `implement/SKILL.md:50` 이 *"압축이 일어나면 첫 행동은 … `AGENTS.md` 를 다시 읽는 것"* 이라고 지시하는데, `session-context.ps1` 은 `compact` 매처에도 걸려 **AGENTS.md 전문(10,441B)을 다시 주입하고** 그 줄에 *"재Read 불필요"* 라고 적는다 — 두 문면이 정면으로 갈린다.

지금 하는 이유는 ①②④ 가 회차마다 고정 비용으로 반복되고, ③ 은 그 파일이 이 repo 에서 가장 활발히 편집되는 문서라 비용이 단조 증가하기 때문이다.

## Proposed outcome

① `run-evals.py` 가 케이스를 병렬로 돌되 출력 순서는 결정적으로 유지하고 순차 폴백을 남긴다. ② `post-write-checks.ps1` 이 정상 경로에서 `git diff` 를 1회만 호출하고, 섹션 1·2 의 격리는 유지한다. ③ `session-context.ps1` 의 이관처 주입이 절 **순번**과 추출 명령을 함께 내 세션이 필요한 절만 뽑아 읽는다. ④ `implement/SKILL.md` 의 압축 후 재Read 지시에서 `AGENTS.md` 를 뺀다.

## Affected users and systems

이 레포에서 코드 작업을 하는 모든 세션. `plugins/pjc/evals/run-evals.py` · `plugins/pjc/scripts/post-write-checks.ps1` · `plugins/pjc/scripts/session-context.ps1`(+ `rules/session-context-rationale-wiki.md`) · `plugins/pjc/skills/implement/SKILL.md` · `plugins/pjc/hooks/evals/scenarios/session-context.ps1`(골든).

## Constraints

**`exit 2` 를 내는 넷의 차단 동작은 건드리지 않는다** — 이번 대상 중 hook 은 `post-write-checks`(PostToolUse 경고)와 `session-context`(SessionStart)뿐이라 그 넷에 들지 않는다. **hook 골든은 부분 실행으로 갈음하고 마지막 task 에서 무인자 전체를 1회 돈다**(`docs/harness-conventions.md` 「골든 부분 실행의 판정 자격」 ⓐ — 이 문장이 그 사전 기재다). **`post-write-checks.ps1` 의 섹션 1/섹션 2 격리를 깨지 않는다** — 한쪽 실패가 다른 쪽을 막지 않는 것이 그 파일의 설계다. **`git` 호출은 `$data.cwd` 기준을 유지한다**(위키 conventions-verification 「hook 검사·차단」 2026-09-10 실해 — 프로세스 cwd 로 돌리면 엉뚱한 레포를 읽는다). **절 단위 읽기 수단의 문면을 두 곳에 두지 않는다** — 주입 줄 하나에만 둔다(회차 68 이 같은 이유로 `WIKI.md` 단일 정본을 택했다). **hook 골든 케이스 수를 바꾸면 `docs/golden-runner.md` 의 기준선 줄을 함께 갱신한다.**

## Open questions

없음.
