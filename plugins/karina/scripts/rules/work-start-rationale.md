# record-work-start 근거

> `plugins/karina/scripts/record-work-start.ps1` 의 주석이 가리키는 근거다. 시작 시각을 소비하는 규칙의 정본은 `plugins/karina/skills/plan/SKILL.md` Step 1 · `plugins/karina/skills/implement/references/report-format.md` 「소요 기록」 · `plugins/karina/skills/chain-plan/references/report.md` 「체인 시작 시각」 이고, 이 파일은 hook 쪽의 「왜」만 담는다.

## §1 왜 hook 이 시작 시각을 남기는가

완료 보고의 소요는 계획을 세우기 시작한 시각부터 잰다. 모델은 현재 시각을 모르고, 종전에는 plan Step 1 의 셸 호출에 `date` 를 얹어 그 값을 Step 5 까지 기억했다. 그 사이에 압축되거나 회차 경계로 `karina:chain-plan` 에 넘기면 값이 사라졌고, 빠뜨려도 잡는 장치가 없었다(v1.375.0 완료 리뷰 5·7번). 발동 시각은 스킬이 불리는 순간 기계적으로 정해지므로 hook 이 그 자리에서 남긴다.

- **루프 계속 주입(`loop-continue.ps1`)에 얹지 않는다** — 같은 이벤트를 받지만 변경 이유가 다르다. 같은 이벤트의 hook 은 병렬로 돌아 파일을 나눠도 대기 시간이 늘지 않는다(공식 hooks 문서 「runs all matching hooks in parallel」).

## §2 대상 스킬과 두 이벤트

`karina:plan`(계획 시작)과 `karina:chain-plan`(체인 시작) 둘이다. `karina:implement` 는 대상이 아니다 — 소요의 시작은 계획 시작이고, 새 세션 구현은 `plan.md` 의 `> 시작:` 이 시각을 넘긴다.

- **`PreToolUse` · `tool_name` = `Skill`** — 모델이 Skill 도구로 부를 때다. 이름은 `tool_input.skill` 이다.
- **`UserPromptExpansion`** — 사용자가 `/karina:plan` 을 직접 쳐서 Skill 도구를 거치지 않는 경로다. 이름은 `command_name` 이고 플러그인 접두가 붙는지 문서에 없어 두 형태를 다 받는다. **hooks.json matcher 도 같은 정규식 `^(karina:)?(plan|chain-plan)$` 이다** — 글자·`|` 만으로 쓰면 「정확 일치 목록」으로 판정돼 `karina:plan` 을 놓친다.

## §3 판정 불가는 침묵

stdin 이 JSON 이 아니거나 `session_id` 가 없거나 대상 스킬이 아니면 아무것도 쓰지 않고 exit 0 이다. 이 hook 은 보고 편의를 위한 기록이라, 실패가 스킬 호출을 막거나 경고로 컨텍스트를 채우면 얻는 것보다 잃는 것이 크다. 시각이 없으면 문서 쪽이 `work-clock.ps1` 으로 폴백한다.

## §4 상태 파일 — 세션 단위 · 발동마다 덮어쓰기

`~/.claude/.state/work-start/<sid>.json` 에 `{ "plan": "<YYYY-MM-DD HH:mm>", "chain-plan": "…" }` 를 둔다.

- **sid 는 `[^A-Za-z0-9._-]` 를 `_` 로 바꿔 파일명으로 쓴다** — `loop-continue.ps1` 과 같은 식이고, compact 재주입(`session-context.ps1`)도 같은 식으로 이 파일을 찾는다. 두 식이 갈리면 재주입이 출력 없이 빠져 아무도 모른다.
- **발동마다 그 키를 덮어쓴다** — 같은 세션에서 계획을 새로 세우면 새 시작이다. 옛 초안을 이어 쓸 때 옛 시각을 보존할지는 `plan.md` 의 `> 시작:` 규칙(`plugins/karina/skills/plan/references/plan-template.md` 「Goal」)이 가르고, 이 파일은 늘 마지막 발동 값이다.
- **30일 지난 파일은 `session-context.ps1` 이 세션 시작에 걷는다** — 다른 상태 디렉터리와 같은 정리 목록이다.

## §5 주입 줄

`[karina 작업 시작] karina:plan <시각>` 한 줄을 `hookSpecificOutput.additionalContext` 로 낸다. `hookEventName` 은 받은 이벤트 이름이다. **`karina:chain-plan` 발동이면 이 세션의 `plan` 기록을 ` · karina:plan <시각>` 으로 덧붙인다** — `karina:plan` 이 회차를 나눠 같은 세션에서 `karina:chain-plan` 을 부르면(`회차 경계:` 넘김) 체인 시작은 계획 시작이어야 하는데, 넘김 args 는 그 시각을 담지 않는다.
