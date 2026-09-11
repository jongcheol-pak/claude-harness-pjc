# pjc 스킬 작성 스타일 가이드

> **이 파일은 스킬이 아니라 작성 가이드 문서다.** (skill frontmatter `name:`/`description:` 없음 → 플러그인 로더가 스킬로 등록하지 않는다. 스킬은 `<name>/SKILL.md`만 대상.)

pjc 플러그인에 **새 스킬을 추가하거나 기존 스킬을 개정**할 때 참고하는 스타일 가이드다.
기존 스킬을 이 골격으로 **소급 재작성하지 않는다**(최소 수정 원칙) — 향후 작업의 참고용이다.

상충 시 우선순위: **글로벌/프로젝트 `CLAUDE.md` 절대·보안 규칙 > `DESIGN.md`·`BUDGET.md` > 기존 스킬의 고유 규칙 > 이 가이드.** 이 가이드는 그것들을 대체하지 않고 보완한다. **`DESIGN.md` 를 위에 두는 것은 그 문서가 이미 선언한 관계다** — 한쪽만 적으면 이 파일을 먼저 연 세션이 그 선언을 모른다.

## 권장 섹션 골격

스킬 본문은 다음 순서를 기본으로 한다(해당 없는 항목은 생략 가능):

**Quick start → Why → Workflow → Anti-patterns → Checklist → See also → Troubleshooting.**

이 순서에서 이 하니스가 따로 정한 것만 적는다 — 나머지는 일반적인 문서 구성이다.

- **Anti-patterns 는 아래 원칙 ①의 WRONG/RIGHT 형식**을 쓴다.
- **Checklist 는 기계로 판정 가능한 기준**만 담는다("잘 동작한다" 금지).
- **Troubleshooting 의 공용 내용은 별도 파일로 분리해 포인터**를 둔다(`BUDGET.md` 처방 ②).

## 작성 원칙

① **추상 규칙보다 WRONG/RIGHT 구체 예시.** "올바르게 매칭하라" 같은 추상 지시는 약하다. 실제 함정을 코드/예시로 대비시킨다:
   ```
   WRONG: cwd.startsWith(projectPath)  → "/repo-a"일 때 "/repo-a-staging"을 오매칭
   RIGHT: cwd === projectPath || cwd.startsWith(projectPath + sep)  → 디렉터리 경계 검사
   ```

② **"왜"를 설명한다** — 대문자 MUST·NEVER를 늘어놓기보다 이유를 적는다. 단 진짜 절대 규칙(보안·파괴적 작업)은 단호하게. **무엇을 규칙으로 만들고 무엇을 만들지 않는가는 `DESIGN.md`「1. 규약 문면 형식」이 정본이다.**

③ **이 가이드는 상위 규약을 대체하지 않는다** — 글로벌 `~/.claude/CLAUDE.md`(한글·UTF-8·승인 워크플로우·정직한 보고)와 `DESIGN.md`·`BUDGET.md`가 내용의 정본이고, 이 문서는 **형식**만 권장한다. **그 규칙들을 여기 복창하지 않는다**(`BUDGET.md` 처방 ①).

④ **평가를 문서보다 먼저 만든다.** 공식 권장이고(*"Create evaluations BEFORE writing extensive documentation. This ensures your Skill solves real problems rather than documenting imagined ones."*) 순서는 **결함 식별 → 평가 작성 → 기준선 측정 → 최소 문면 → 반복**이다. 스킬을 **안 붙인 상태로** 대표 작업을 돌려 무엇이 실제로 실패하는지 먼저 적고, 그 실패를 재는 케이스를 만든 뒤, 그것을 통과시킬 만큼만 쓴다. **우리 자리는 둘이다** — 발동 경계는 `skills/evals/trigger_eval.py`(실제 모델 호출), 검사기 판정은 `evals/cases.json`(모델 호출 없음). **없는 요구를 미리 문서로 막는 문면이 이 순서를 건너뛴 자리에서 나온다.**

## description 작성 (트리거 메타데이터)

**공식 한도 (Agent Skills 표준 — agentskills.io/specification + code.claude.com/docs/en/plugins.md, 2026-07-08 확인 · 작성 권장은 platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, 2026-09-11 확인)**:
- `name`: 1-64자, 소문자·숫자·하이픈만, **스킬 디렉터리명과 일치**. **XML 태그 금지 · 예약어 `anthropic`·`claude` 금지**(둘 다 하드 제약 — 넘으면 그 스킬이 로드되지 않는다).
- `description`: **두 사양이 함께 걸린다 — 낮은 쪽이 실효 한도다.**
  - **Agent Skills 표준: 1-1,024자** (하드 제약). 표준을 따르는 다른 도구에서도 쓰려면 이 값을 지켜야 한다.
  - **Claude Code: `description` + `when_to_use` 합산이 스킬 목록에서 1,536자로 절단**된다(목록 예산은 컨텍스트의 1% — `skillListingBudgetFraction`, 항목당 캡은 `skillListingMaxDescChars`. 출처: code.claude.com/docs/en/skills, 2026-07-29 확인). 즉 Claude Code만 놓고 보면 여유가 더 있으나, **`when_to_use`를 쓰면 그 몫만큼 `description` 가용분이 줄어든다.**
  - **pjc의 운용 기준은 1,024자**다 — 두 사양 중 낮은 쪽이고, 표준 호환을 잃지 않는다. 초과분은 잘리거나 무효가 될 수 있으므로 트리거 어휘·near-miss 경계는 유지한 채 산문 연결부를 압축해 맞춘다(v1.100.0에서 1,230자로 초과된 전례 — 개정 때마다 자수 재측정).
- SKILL.md 본문: **500줄 미만 권장**(Agent Skills 표준). **근거가 두 문장을 넘으면 `references/`로 내린다**(`DESIGN.md`「1. 규약 문면 형식」). **초과했을 때 무엇을 하는가는 `BUDGET.md`「초과했을 때」가 정본이고 이 줄은 그것을 되풀이하지 않는다** — 5,000토큰 권장도 그 파일의 예산 표가 대체한다(SKILL.md 12,000자).
- **`description` 도 XML 태그 금지**(하드 제약).
- 측정: **사람이 재지 않는다** — `check-harness-consistency.py` 「계수·버전 정합」 축이 길이 2종·예약어·XML 태그를 대조한다(`SKILL_FM_MAX`). ⚠ **그 축의 대상은 `plugins/pjc/skills/*/SKILL.md` 뿐이고 `plugins/pjc/agents/*.md` 는 밖이다** — 에이전트 정의는 Agent Skills 가 아니라 설계상 제외이며, 그쪽 값은 재어지지 않으므로 고칠 때 직접 센다. **단위는 바이트가 아니라 문자다**(한글에서 3배로 어긋난다).

### 공식 권장 중 달리 정한 것

**출처**: platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices (2026-09-11 확인). **우리 값이 있는데 근거가 없으면 다음 회차가 「공식을 안 봤나」를 다시 묻는다** — 그래서 갈린 자리마다 이유를 적는다.

| 공식 | 우리 | 왜 갈렸는가 |
|---|---|---|
| reference 파일이 **100줄**을 넘으면 목차 | `BUDGET.md`「나눈 뒤에 지킬 것」의 **10,000자** | 줄 길이가 파일마다 33~82자로 갈려 줄 수는 분량을 재지 못한다. **예산 축이 재는 단위에 맞춘다** — v1.273.0 에 그 축이 바이트에서 **문자 수**로 옮겨 갔고, 이 임계도 같은 단위로 재산정됐다(숫자 유지 · 상한 15,000자의 2/3 지점이라 비율이 보존된다). 종전 근거였던 *"한글이라 줄 수와 바이트가 3배로 갈린다"* 는 단위 전환으로 무효가 됐다 |
| **Haiku·Sonnet·Opus 전부**로 시험 | 기준선은 **Opus 하나** | 트리거 eval 이 실제 모델 호출이라 비용이 크다. **비채택이 아니라 미수행**이고 `[다음 회차]` 의 **별도 승인 대상**이다 |
| 스킬마다 **평가 3개 이상** | 트리거 eval 43케이스(전체) | 총량은 이미 넘지만 **스킬당 분포를 재는 축이 없다** — 한 스킬에 몰려 있어도 지금은 green 이다 |

**SKILL.md 500줄과 참조 깊이 1단계는 갈리지 않았다** — 전자는 위 「description 작성」이, 후자는 `BUDGET.md` 가 같은 값으로 담는다.

### frontmatter 필드 (pjc가 쓸 수 있는 것)

**출처**: code.claude.com/docs/en/skills (2026-07-29 확인) — 아래 필드 목록·치환 변수·`disallowed-tools` 해제 규칙·`background`의 도구 축소는 모두 이 문서 기준이다.

공식 지원 필드는 17종이며, 그중 이 하니스에서 실제로 쓸 만한 것만 추린다. **표준(agentskills.io) 밖의 Claude Code 확장 필드는 다른 도구에서 무시되므로, 그 필드에 의존하는 동작은 문서 규칙으로도 한 겹 받쳐 둔다**(예: `disallowed-tools`에 기댄 자율 루프의 질문 금지).

| 필드 | 용도 |
|---|---|
| `name` | 스킬 이름 — 디렉터리명과 일치해야 한다 |
| `description` | 트리거 메타데이터 (위 한도 참조) |
| `when_to_use` | 트리거 조건을 `description`에서 분리 — 목록 예산은 둘의 **합산**으로 잡힌다 |
| `argument-hint` | `/skill` 입력 시 보이는 인자 힌트 |
| `arguments` | 이름 있는 위치 인자 선언 — 본문에서 `$name`으로 치환 |
| `allowed-tools` | 이 스킬이 쓸 도구를 화이트리스트로 한정 |
| `disallowed-tools` | 이 스킬 활성 중 제거할 도구. **사용자의 다음 메시지에서 해제**되므로 영구 차단이 아니다 |
| `model` | 이 스킬이 쓸 모델 고정 |
| `effort` | 이 스킬 활성 중 effort 오버라이드 — `low`·`medium`·`high`·`xhigh`·`max` (모델에 따라 가용 등급이 다르다) |
| `context` | 스킬에 주입할 추가 컨텍스트 |
| `agent` | 이 스킬을 특정 subagent로 실행 |
| `background` | 백그라운드 실행. **내장 도구가 축소되고 `LSP`가 빠지므로** 검증 성격의 스킬에는 쓰지 않는다 |
| `paths` | 특정 경로에서만 활성화 |
| `shell` | 본문의 `` !`cmd` `` 전처리에 쓸 셸 지정 |

**본문 치환 변수**: `$ARGUMENTS`·`$ARGUMENTS[N]`·`$N`·`$name`·`${CLAUDE_SESSION_ID}`·`${CLAUDE_EFFORT}`·`${CLAUDE_SKILL_DIR}`·`${CLAUDE_PROJECT_DIR}`. **치환은 원본 파일 전체에 1회 적용되며 코드펜스 안이라고 예외가 아니다** — 변수명을 설명문에 그대로 적으면 그것까지 치환되므로, 설명할 때는 이름을 쪼개 쓴다.

스킬 트리거의 1차 메커니즘이다(skill-creator 가이드 정합):
- **무엇을 하는가 + 언제 트리거되는가**를 모두 담는다.
- 구체적 트리거 표현(한/영)을 나열해 undertriggering을 막는다(약간 pushy하게).
  - **pushy는 저빈도·전문 어휘에 한정한다.** "디버깅", "ViewModel", "도메인 서비스"처럼 그 스킬 맥락에서만 쓰이는 전문어는 단독 트리거로 나열해도 안전하다. 그러나 **일상 고빈도 단어**("fix", "에러", "추가", "변경")는 무관한 대화에서도 흔해 **단독 트리거로 넣지 않는다** — 반드시 맥락 조건과 결합한다(예: "fix" 단독이 아니라 "test failure·build error를 fix"처럼). 고빈도 단어를 단독 트리거로 두면 과트리거로 엉뚱한 스킬이 발동한다.
- **near-miss(트리거 금지) 경계**를 명시한다 — 과트리거를 줄이고 형제 스킬과의 경계를 분명히 한다.

