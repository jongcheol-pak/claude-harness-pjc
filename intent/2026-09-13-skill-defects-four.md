# Intent: 검사기가 재지 않는 자리의 결함 넷을 막는다

Author: 사용자. Status: approved.

## Problem

*"위키, 하니스 스킬에서 결함·구멍 검토"* → 넷을 찾았고 **H2 세션과 교차 검토해 넷 다 「고친다」로 합의**했다. 기존 검사기 3종(`check-harness-consistency` 18축 · `check-stale-refs` · `check_wiki_circuit` 7단계)은 전부 green 이라, 넷은 그 축들이 재지 않는 자리에 있다.

- **① `[SKILL-IMPROVE]` 큐의 소비 진입점이 실제로 없다** — 네 곳이 *"하네스 레포 세션의 `pjc:plan` Step 1이 `skill-feedback.md`를 할 일 후보로 조회한다"* 를 정본처럼 단언한다(`queue-rules.md:16` · `lookup-rules.md:42` · `session-wiki-signals.ps1:119` 의 사용자 노출 문구 · `session-context-rationale-wiki.md:39`). 그런데 `plan/SKILL.md` Step 1 의 항목은 **5개**이고 그 조회가 없다(`plugins/pjc/skills/plan/` 전역 `skill-feedback`·`SKILL-IMPROVE` **0건**). **실해는 이미 기록돼 있다** — `session-context-rationale-wiki.md:39` 가 hook 을 만든 근거로 *"[SKILL-IMPROVE] 큐는 유입만 자동이고 착수 지점이 없어 12건이 최장 22일 방치됐다"* 를 적고, 그 hook 을 **보완재**로 규정한다(*"계획을 열지 않는 세션에서는 잔량이 보이지 않는다 — 이 1줄이 그 사각을 메운다"*). 보완재만 있고 본 경로가 없다.
- **② `implement` 의 정지 자리 목록이 자기모순** — `implement/SKILL.md:41` 이 *"넷을 정지 조건의 전부로 읽지 않는다 — 목록 밖에서 멈추는 자리가 **셋** 더 있다"* 로 목록을 닫는데, 같은 문서 `:56` 에 *"`AGENTS.md`에 없으면 **사용자에게 묻는다**"* 가 있고 넷에도 셋에도 없다. 넷째다. 그리고 `loop-stop-patterns.md` 의 판정문(*"도구 호출 없이 텍스트만 내고 turn을 끝냈는가"*)은 **「멈추는 넷」의 정당한 정지에도 똑같이 참**인데 그 예외 전제가 문서 어디에도 없다 — 자율 루프가 규약대로 멈춰도 그것이 위반인지 아닌지 갈리지 않는다.
- **③ `lint.py` 의 `section()` 이 코드펜스를 인식하지 못한다** — `lint.py:362` 가 `strip_code` 를 거치지 않고 원문에 직접 정규식을 건다. 같은 파일 `:2201` 주석이 위험을 이미 적었으나(*"코드펜스 안의 `## `를 헤딩으로 오인"*) 고친 것은 `relocate_sections` 한 곳이고, 실호출 25곳 중 `strip_code` 선통과는 **2곳**(`:2550`·`:3117`)뿐이다. **읽기**(`:3418`·`:3450`·`:3453`·`:3500` — 하위 문서 목록 검사)와 **쓰기**(`_replace_section` 경유 `:1657`·`:1680`·`:1868`) 양쪽이 걸리고, 같은 함수의 탐욕 매치 사고가 **회차 45 완료 리뷰 2R** 에 이미 한 번 났다. 현재 vault 502페이지 × 질의 헤딩 11종 전수 비교로 **불일치 0건**(미발현)이지만, 발현 조건 ⓑ(질의되는 진짜 절 안에 `## `를 품은 펜스)는 이 vault 의 `conventions.md` 가 문서 규약을 펜스 예시로 적는 문서라 시간문제다.
- **④ 「절 단위 읽기」 수단이 같은 펜스 구멍을 갖는다** — `WIKI.md:17~18` 의 `grep -n '^## '` → `awk -v n=<순번> '/^## /{c++} c==n'` 이 펜스를 세지 않는다. **③과 달리 이미 재현된다**: vault 의 `40_guides/ui-ux/help-doc-template.md` 에서 절 목록이 **11개**로 나오고(진짜 1개 · 유령 10개) `n=1` 추출이 **321B** 에서 잘린다(진짜 4,090B — **92% 유실**). 모델은 잘린 줄 모른 채 *"그 내용이 없다"* 고 판정한다. 같은 수단의 사본이 `session-context.ps1:237` 의 주입 문구에도 있다.

지금 하는 이유: ①은 실해가 이미 났고 방치 기간이 늘고 있으며, ④는 재현 가능한 손상이 vault 에 존재하고, ②③은 처방이 이미 정해져 있어 등재보다 고치는 것이 싸다.

## Proposed outcome

① `pjc:plan` Step 1 에 큐 조회 항목이 생겨 네 곳의 단언이 실재하는 자리를 가리킨다 ② `implement` 의 정지 자리 목록이 실제 수와 맞고, `loop-stop` 판정문이 정당한 정지를 제외해 두 문서가 갈리지 않는다 ③ `section()`·`without_section()` 이 `_md_sections` 와 같은 경계를 쓴다 ④ 「절 단위 읽기」 수단이 펜스를 세지 않아 잘린 절을 「내용 없음」으로 읽지 않는다.

## Affected users and systems

코드 작업 세션(계획·구현)과 위키 세션을 여는 사용자. `plugins/pjc/skills/plan/SKILL.md` · `plugins/pjc/skills/implement/SKILL.md` · `plugins/pjc/skills/implement/references/loop-stop-patterns.md` · `plugins/pjc/skills/llm-wiki/scripts/lint.py` · `plugins/pjc/skills/llm-wiki/evals/{lint-cases.json,fixtures/}` · `plugins/pjc/skills/WIKI.md` · `plugins/pjc/scripts/session-context.ps1` · `plugins/pjc/hooks/evals/scenarios/session-context.ps1`.

## Constraints

**vault 데이터는 고치지 않는다** — `help-doc-template.md` 의 펜스 형상은 정상 문서이고 고칠 대상이 아니다. 대상은 repo 의 규약·스크립트뿐이다. **②-b 는 규약 개정이라 사용자가 방식을 확정했다** — 「현행 규약 안의 안」(implement 쪽에 한 줄)이 아니라 **「규약을 함께 고치는 안」**(판정문 자체에 단서)을 채택했다. 정본이 둘로 갈리지 않는 쪽이다. **③과 ④를 한 회차에 묶는다** — ③만 고치면 중간 상태에서 `section()`(펜스 셈) 과 `_md_sections`(안 셈) 의 관계가 뒤집혀 스크립트와 수동 규약이 오히려 갈린다. **`section()` 을 호출부별로 고치지 않는다** — 지금 상태가 그 방식의 결과물이다(위험을 주석으로 적은 곳 1 · 실제 통과시킨 곳 25 중 2). **넷 다 대장에 등재하지 않는다** — `deferred-rules.md` 의 「지금 고칠 것인가」 3조건(처방 확정 · 범위 안 · 비용 < 등재+재조사)을 넷 다 만족하고, 등재 하한선 ①(실해)은 미룰 것을 올릴 때만 걸린다.

## Open questions

없음.
