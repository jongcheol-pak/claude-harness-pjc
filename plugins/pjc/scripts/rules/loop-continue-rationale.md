# `loop-continue` 판정 근거

> `loop-continue.ps1`의 주석이 가리키는 판정 근거다. 스크립트에는 각 자리에 이 문서의 절을 가리키는 1줄만 남겼다.

## §1 담당 조항과 설계

`plugins/pjc/skills/DESIGN.md` §5 의 **E12(자율 루프를 중간에 멈추지 않는다)** 를 담당한다. 형태 판정의 정본은 여전히 `implement/references/loop-stop-patterns.md` 이고, 이 hook 은 **그 문면이 놓친 정지 가운데 plan 에 미완 task 가 남은 것**에만 계속을 주입하는 2차 방어선이다.

- **transcript 를 읽지 않고 문면도 판정하지 않는다** — v1.225.0 에 제거된 `require-evidence` 가 두 가지를 다 했다. transcript 는 비동기로 쓰여 Stop 시점에 마지막 응답이 빠질 수 있고(공식 hooks 문서 `transcript_path` 항), 파싱 상한·tail 줄 수를 조정할 때마다 fail-open 결함이 새로 났다(대장 종결분 6건). 한국어 정지 문면은 어미 조합이 무한해 정규식이 수렴하지 않는다. 그래서 이 hook 은 **발동 마커 · plan.md 체크박스 · Stop 페이로드의 필드**만 입력으로 쓴다.
- **`decision:"block"` 이 아니라 `additionalContext` 로 계속시킨다** — 공식 문서가 「설계대로 동작하는 안내」에 권하는 형태이고, 같은 루프 보호(`stop_hook_active`·연속 8회 상한)를 받는다. 트랜스크립트에 hook 오류가 아니라 피드백으로 표시된다. 이 형태는 `exit 0` 이므로 `AGENTS.md` 「hook 출력 규약」의 「차단은 `exit 2` 하나, 그것을 내는 hook 은 넷」을 바꾸지 않는다.
- **출처**: Opus 5.5 프롬프팅 가이드 「무인 에이전트 실행」 — 텍스트로 끝난 턴을 완료의 증거가 아니라 보고로 보고, 체크리스트에 항목이 남아 있으면 그 항목을 적은 짧은 메시지로 계속시키며, 같은 작업에 대한 자동 계속은 두세 번에서 멈춘다.

## §2 주입 조건과 상한

주입은 다섯 조건이 **모두** 참일 때만 한다.

1. 이 세션에 발동 마커가 있다(§6)
2. `stop_hook_active` 가 거짓이다 — 이미 이 hook 때문에 계속된 turn 이면 다시 밀지 않는다. 그래서 규약이 지목한 정당한 정지(승인 대기 등)는 **1회 재촉**으로 끝난다: 모델이 막힌 이유를 말하고 멈추면 그 turn 은 `stop_hook_active` 가 참이다
3. `background_tasks` 가 비어 있다 — 모델이 시작한 백그라운드 명령·서브에이전트가 돌고 있으면 turn 종료는 대기이지 정지가 아니다(가이드: 그 작업이 끝나기를 기다린다)
4. `plan.md` 에 미완 task 가 1개 이상이다(§4)
5. **같은 미완 집합**에 대한 이 세션의 주입 횟수가 `$MaxPerSet`(2) 미만이다 — 집합은 미완 ID 목록의 해시로 가른다. 한 task 를 끝내면 집합이 바뀌어 다시 주입할 수 있고, 진전 없이 같은 자리에서 멈추면 두 번 뒤에는 침묵한다. 가이드의 「두세 번 후 중단」이고, 실제로 막힌 실행을 사람이 보게 하는 장치다

## §3 fail-open 은 침묵이다

stdin 파싱 실패 · `session_id` 부재 · `cwd` 부재 · plan.md 읽기 실패 · 상태 파일 쓰기 실패는 전부 **아무것도 출력하지 않고 `exit 0`** 이다. 이 hook 이 틀려서 치르는 비용은 비대칭이다 — 잘못 주입하면 사용자가 멈춘 작업을 밀어붙이고, 잘못 침묵하면 문면만 있던 종전 상태로 돌아갈 뿐이다. 카운터를 쓰지 못하면 주입도 하지 않는 것도 같은 이유다 — 상한을 셀 수 없는 주입은 상한이 없는 주입이다.

## §4 미완 판정식의 짝

`session-context.ps1` 의 `$open` 계수식 `(?m)^- \[[ /]\] \**T\d+` 에 ID 캡처(`T\d+(?:-\d+)?`)만 더한 식이다. 템플릿 정본(`plan/references/plan-template.md` 「작업 단계」)의 `- [ ] **T1-1**` 과 구형 `- [ ] T1:` 을 함께 받고, `[/]`(진행 중)도 미완으로 센다. **사용처가 둘뿐이라 공통 헬퍼로 빼지 않고 두 자리에 서로를 가리키는 주석을 둔다** — 한쪽만 고치면 세션 시작 안내와 계속 주입이 서로 다른 미완 수를 보게 된다.

## §5 상태 파일과 정리

`~/.claude/.state/loop-continue/` 아래 세션별 마커 `<session_id>.active` 와 집합별 카운터 `<session_id>.<집합 해시 12자>.count` 를 둔다. 세션이 끝나도 지우지 않는다 — 다른 세션의 `session_id` 와는 겹치지 않아 해가 없고, `session-end-cleanup.ps1` 은 「다른 책임을 얹지 않는다」고 스스로 범위를 닫았다. 대신 마커를 쓸 때 **30일 지난 파일을 걷는다**(`suggest-agents-record.ps1` 의 같은 하우스키핑).

## §6 발동 마커의 두 경로

마커는 **`pjc:implement` 가 이 세션에서 발동했다**는 사실만 기록한다.

- **`PreToolUse` · `tool_name` = `Skill`** — 모델이 Skill 도구로 스킬을 부를 때다. `tool_input.skill` 이 `implement` 또는 `pjc:implement` 이면 마커를 세운다
- **`UserPromptExpansion`** — 사용자가 `/pjc:implement` 를 직접 쳐서 Skill 도구를 거치지 않는 경로다(공식 문서: 「typing `/skillname` directly bypasses `PreToolUse`」). `command_name` 에 플러그인 접두가 붙는지는 문서에 없어 두 형태를 다 받는다. **hooks.json matcher 도 `^(pjc:)?(implement|plan)$` 정규식으로 둔다** — 글자·`|` 만으로 쓰면 「정확 일치 목록」으로 판정돼(hooks 문서 「Matcher patterns」) 접두 형태가 스크립트에 닿기 전에 떨어진다(완료 리뷰 BLOCKER)
- **`pjc:plan` 이 발동하면 마커를 지운다** — 같은 세션에서 새 계획을 쓰기 시작하면 plan.md 의 미완 task 는 **승인 전 계획**의 것이다. 마커가 남아 있으면 승인 대기 turn 에 「이어서 진행하라」를 주입해 승인 없는 실행을 부추긴다. 승인 뒤 `pjc:implement` 가 다시 발동하면 마커가 다시 선다
