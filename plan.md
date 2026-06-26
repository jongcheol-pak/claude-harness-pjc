# plan.md — skill-creator 가이드 감사 수정안 적용 (pjc 8개 스킬)

## 목표
skill-creator 가이드 감사에서 도출된 MINOR 다듬기 수정안을 pjc 플러그인 8개 스킬에 적용한다.
모두 스킬 문서(SKILL.md frontmatter description + 본문 + references .md) 편집이며 코드 로직 변경은 없다.

## 결정 (사용자 승인 완료)
- **B6 (implement-task desc)**: 경량 정리 — 자율루프 동작 시그널 유지, 중복·장황만 다듬음.
- **C3 (llm-wiki 중복)**: 경량 포인터화 — 가장 명백히 중복된 워크플로 블록만 schema에서 포인터로 축약, 규칙 정의는 schema 유지.
- **C1/C4 구조 강도**: 보수적 — C1은 halt 포인터 + 컨텍스트한계 중복만 정리(549줄이 약간 초과로 남아도 허용, 가이드상 줄수는 근사치). **C4는 생략**(plan-feature는 425줄로 이미 적합).
- **A2 (harness-toggle Bypass)**: 삭제하지 않고 **유지 + "왜 필요한지" 한 줄 주석** 추가(로컬 미서명 스크립트를 실행정책 제한 환경에서도 실행하기 위함, AV 위험 조합 아님).
- **버전/릴리즈**: plugin.json 1.62.0 → **1.63.0**(minor — description=트리거는 사실상 공개 동작 변경). README/notes 갱신. 승인된 push 후 GitHub 릴리즈 발행(release-on-version-bump).

## 배경
- 직전 plan.md(한/영 양방향 검색)는 T1~T4 전부 완료·커밋(2b25da1) 반영, git 클린 → 새 계획으로 교체.
- AGENTS.md 없음. 프로젝트/글로벌 CLAUDE.md가 컨벤션 원천이라 bootstrap 강제 안 함(문서 편집 작업).

## Impact Analysis (전수 확인 결과)
- **description = 스킬 트리거 메타데이터**. 코드 호출자 없음. 스킬은 Claude Code 스킬 로더가 **플러그인 캐시**에서 읽음 — 레포 소스(`D:\...\plugins\pjc\skills\*`) 편집은 **현재 세션(캐시 `C:\...\plugins\cache\...\1.62.0\`)에 영향 없음**. 변경은 캐시 갱신/재설치 후 적용(플러그인 개발 정상 흐름).
- 시그니처 변경 없음, 직렬화 변경 없음, 코드 caller 없음 → cross-file 코드 영향 0.
- `wiki-schema.md`는 llm-wiki SKILL.md가 참조(문서). lint.py는 **vault**를 검사하지 실제 schema 파일을 읽지 않음 → C3 편집이 lint 동작에 영향 없음. C3로 schema 본문을 고치므로 schema 내부 version 2.13 → 2.14 동반.
- plugin.json version은 마켓플레이스/설치 메타. 1.62.0 → 1.63.0.
- 실행 중인 plan-feature/implement-task는 캐시본을 쓰므로, 레포의 plan-feature·implement-task SKILL.md 편집(T5·T8)이 이 세션 진행을 깨지 않음.

## 작업 단계 (모두 Type A — .md/.json 편집)

### T1 — add-domain-service: A1 + B1  [Type A]
- **A1** 본문 24행: `DDD/Clean Architecture를 따르는 프로젝트라면 .NET/Kotlin(Android) 양쪽 모두 적용 가능.` → `이 skill은 **.NET 프로젝트를 기준**으로 한다. 다른 스택(Kotlin/Android 등)은 AGENTS.md 컨벤션을 우선하고, 아래 템플릿·검증은 .NET 기준의 개념적 참고로만 사용한다.` (템플릿·DI·테스트·검증이 전부 .NET이라 주장-내용 불일치 해소)
- **B1** description 끝에 near-miss 추가: `... unit test scaffold.` 뒤에 `Do NOT trigger for logic that belongs inside a single Aggregate (add a method to the Aggregate instead), for pure UI/ViewModel work (use add-viewmodel), or for infrastructure/config-only changes.`
- Acceptance: frontmatter YAML 파싱 정상; 24행에 Kotlin 적용 주장 잔존 0; description에 near-miss 문장 존재.
- Halt Forecast: 없음(문서).

### T2 — add-viewmodel: B2  [Type A]
- description 끝(`... DI registration.`) 뒤 near-miss 추가: `Do NOT trigger for non-XAML stacks (React/web, ASP.NET WebAPI controllers), simple UI text/label/style tweaks on an existing view, or debugging an existing ViewModel (use pjc-systematic-debugging). Android Jetpack ViewModel is out of scope.`
- Acceptance: YAML 파싱 정상; near-miss 문장 존재.
- Halt Forecast: 없음.

### T3 — bootstrap-agents-md: B3 + D  [Type A]
- **B3** description 보강: 자연어 트리거 예시(`"AGENTS.md 만들어줘", "프로젝트 가이드 문서 자동으로 만들어줘", "Claude가 이 프로젝트 컨벤션을 알게 해줘"`)를 트리거 절에 추가 + 끝에 near-miss `Do NOT trigger when an AGENTS.md or CLAUDE.md already exists, when only editing/adding a line to an existing AGENTS.md, or for writing a README.`
- **D** Step 1(32~34행) bash `test -f AGENTS.md || test -f CLAUDE.md` 블록을 PowerShell로 통일(Step 2가 PowerShell이므로): ` ```powershell\nif ((Test-Path AGENTS.md) -or (Test-Path CLAUDE.md)) { <있음 → 종료, plan-feature로 복귀> }\n``` `
- Acceptance: YAML 파싱 정상; Step 1이 PowerShell; description에 자연어 트리거 + near-miss 존재.
- Halt Forecast: 없음.

### T4 — harness-toggle: A2  [Type A]
- 32행("...다음 PowerShell 명령 중 **하나**를 Bash 도구로 실행하세요.") 바로 뒤에 한 줄 주석 추가: `> 참고: 명령의 \`-ExecutionPolicy Bypass\`는 로컬 미서명 플러그인 스크립트(\`harness-toggle.ps1\`)를 실행정책이 제한된 환경(Restricted/AllSigned)에서도 실행하기 위한 최소 설정이다. 이 스크립트는 자격증명·네트워크·프로세스 종료를 다루지 않아 AV 오인 조합(정책우회+숨김실행+평문자격증명 등)이 아니다.`
- 4개 명령의 `-ExecutionPolicy Bypass`는 **유지**(삭제 시 제한정책 PC에서 토글 깨짐).
- Acceptance: 주석 1줄 존재; 4개 명령 Bypass 유지; 토글 동작 수동 검증(아래 검증 방법 5).
- Halt Forecast: 없음.

### T5 — implement-task: B6 + C1  [Type A]
- **B6** description 경량 정리: 자율루프 시그널(FULLY AUTONOMOUS·processes ALL tasks·without asking between tasks·resuming mid-plan)은 유지하되 중복 문장("Never asks 'Should I proceed to the next task?'")을 제거해 간결화. 트리거·near-miss는 유지.
- **C1(a)** halt-conditions.md 인라인 포인터: 89행(`> **상세 안티패턴 표는 references/antipatterns.md 참조.**`) 뒤에 한 줄 추가 `> **중단 조건 전체 표 + 중단 보고 양식은 \`references/halt-conditions.md\` 참조 — Halt 여부가 애매하면 먼저 확인.**`
- **C1(b)** 컨텍스트 한계 중복 축약: 본문 133~137행(🧠 컨텍스트 관리 항목 4의 세부 4불릿)은 halt-conditions.md 27~36행이 동일 내용을 완전 보유 → 본문은 요지 1~2줄 + 포인터로 축약(`컨텍스트 한계 근접 시: 현재 task를 Phase V/D까지 완료·plan.md에 상태 완전 기록 후 멈추지 말고 압축 통과. 압축 감지 시 첫 행동은 plan.md+AGENTS.md 재읽기. 상세: references/halt-conditions.md.`). **보수적 — 500줄 미만 강제 아님**(약간 초과 잔존 허용).
- Acceptance: YAML 파싱 정상; description에 "Never asks..." 중복 문장 제거되고 자율 시그널 유지; 89행 근처에 halt-conditions 포인터 존재; 133~137 중복 축약·정보 손실 없음(halt-conditions.md가 상세 보유).
- Halt Forecast: 축약 중 정보 누락 우려 → halt-conditions.md에 해당 4불릿 전부 존재함을 대조 확인 후 축약(이미 확인: 27~36행 일치).

### T6 — llm-wiki: B4 + C2 + C3  [Type A]
- **B4** description에서 구현 디테일(`vault 경로의 진실원천은 사용자 설정 파일 ~/.claude/llm-wiki-config.json`) 제거하고, **본문 §0-1에 동일 내용이 있는지 확인**(있으면 그대로, 없으면 §0-1에 1줄 보강) + description 끝에 near-miss `단순 코드 수정·위키와 무관한 일반 지식 질문에는 발동하지 않는다(그건 plan-feature/implement-task 영역).` 추가. (folded scalar `>` 형식 유지)
- **C2** 본문 상단(H1 `# LLM WIKI 운영 스킬` 직후, §0 시작 전)에 절차 목차(TOC) 추가 — 실제 섹션 헤더(0, A~K)를 읽어 정확히 반영. **형식은 wiki-schema.md의 기존 `## 목차` 패턴을 따른다**(일관성).
- **C3** 경량 포인터화: wiki-schema.md에서 **SKILL 절차를 그대로 재서술한 "순수 절차 블록"만** `(절차: SKILL <해당 단계> 참조)` 한 줄로 축약. **실제 대상은 §6 "작업 참조" 블록**(SKILL K의 4단계를 그대로 재서술하던 부분 — SKILL K 포인터로 축약). §5 ingest 절차는 이미 `(절차: 스킬 …)` 인라인 포인터를 보유하고 규칙 근거를 함께 담고 있어 추가 포인터화 시 정의 손실 위험이 있어 **무수정 유지**(보수적). **다음은 포인터화 금지(정의·진실원천)**: 규칙/타입/예산 정의, **그리고 §7의 번호 검사항목(§7-N)** — lint.py가 주석에서 `wiki-schema §7-N`을 진실원천으로 번호 참조하고 lint.py:10이 "SKILL 예산표·wiki-schema·lint.py 3중 동기화" 불변식을 명시하므로, §7을 포인터화하면 lint.py 참조가 댕글링되고 검사 정의가 사라진다(M1). schema 내부 version 2.13 → 2.14.
- Acceptance: YAML 파싱 정상(folded scalar — near-miss 추가 시 2칸 들여쓰기 유지, 더 깊은 들여쓰기/빈 줄 금지); description에 config 경로 디테일 제거 + near-miss 존재; §0-1에 config 진실원천 명시 유지; 본문 상단 TOC 존재; **§7 번호 검사항목 정의가 schema에 그대로 잔존(lint.py의 §7-N 주석 참조 유효)**; 규칙/타입/예산 정의 잔존; §5 순수 절차 재서술만 포인터화; version 2.14.
- Halt Forecast: ① C2 TOC가 실제 섹션과 어긋남 → 편집 전 실제 헤더 grep으로 확정. ② C3에서 정의까지 지워 정보 손실 → "재서술(절차)"만 포인터화하고 "정의(규칙·타입·예산·§7 검사항목)"는 절대 삭제 안 함, 애매하면 유지.

### T7 — pjc-systematic-debugging: B7  [Type A]
- description 말미(`Symptom patches are forbidden.` 뒤, `See SKILL body...` 앞)에 변별 문장 추가: `This is the pjc/DDD-integrated variant (regression-test-first fix, spec-compliance review, cross-project llm-wiki lookup); prefer it over the generic systematic-debugging skill inside pjc-managed projects.`
- Acceptance: YAML 파싱 정상; 변별 문장 존재; 기존 트리거·SKIP 절 유지.
- Halt Forecast: 없음.

### T8 — plan-feature: B5 + B8  [Type A] (C4 생략)
- **B5** description 맨 앞에 "무엇을 하는가" 추가: `This skill plans a code change before any code is written — it decomposes the work into tasks, pre-resolves every decision branch, and defines verifiable acceptance, producing a single plan.md.` + 뒤 트리거 절을 약간 정리(중복 축약, 트리거·near-miss·impact-warn 안내 유지).
- **B8** 같은 description 안에 형제 스킬 경계 한 줄 포함: `A single defect needing root-cause investigation goes to pjc-systematic-debugging first; if the fix grows to span multiple files or change a signature, plan it here.` (B8은 plan-feature 쪽에만 명시 — pjc-systematic-debugging은 T7에서 정체성 강화로 충분, 중복 회피)
- Acceptance: YAML 파싱 정상; description 첫 문장이 "무엇"; 형제 경계 문장 존재; 트리거/near-miss 유지; 줄수 425 부근 유지(C4 미적용).
- Halt Forecast: 없음.
- 비고: **레포 소스 편집이며 현재 세션은 캐시본 사용 → 진행 중 plan-feature 동작에 영향 없음.**

### T9 — 버전 업 + 문서 갱신  [Type A]
- `plugins/pjc/.claude-plugin/plugin.json`: version `1.62.0` → `1.63.0`.
- `README.md`: **L10 `**버전**: 1.62.0` → `1.63.0` 필수 편집**(plan-reviewer 실측 확인). 그 외 스킬 description을 직접 인용·나열하는 부분이 있으면 grep로 찾아 동기화. (`marketplace.json`은 version 필드 없음 → 손대지 않음)
- `notes.md`: `## 최근 변경` 최상단에 1.63.0 항목 추가(이번 8개 스킬 감사 수정 요약 — 무엇/왜/검증).
- Acceptance: plugin.json 1.63.0; README L10 버전 1.63.0; notes에 1.63.0 항목; README 불일치 0.
- Halt Forecast: 없음.

## 검증 방법
1. **YAML frontmatter 파싱**: 변경한 8개 SKILL.md 각각의 `---...---` 블록을 파이썬 `yaml.safe_load`로 파싱 → 에러 0, `name`·`description` 키 존재 확인.
2. **줄 수 확인**: 각 SKILL.md `wc -l`. implement-task는 축약 후 줄 수 보고(500 미만 권장이나 미달성 시 사유 명시 — 보수적 결정).
3. **문구 대조**: 각 description에 near-miss/변별/"무엇" 문장이 실제 포함됐는지 grep.
4. **wiki-schema 정합**: C3 후 schema에서 "정의"가 삭제되지 않았는지(규칙/타입/예산 헤더 존재) + version 2.14 확인. C1 후 halt-conditions.md 내용 손실 0(축약된 본문 정보가 ref에 존재).
5. **harness-toggle 동작 수동 검증**: `harness-toggle.ps1 "" status` 1회 실행해 정상 출력(Bypass 유지 확인). 상태만 조회(토글 변경 없음) — 부수효과 없음.
6. plugin.json JSON 파싱 정상.

## 승인 필요 항목
- 본 plan 전체(8개 스킬 description=트리거 변경 + 구조/설계 변경 + 버전 업) — ExitPlanMode 게이트에서 승인.
- commit/push 및 GitHub 릴리즈 발행 — **별도 승인**(push 후 release-on-version-bump 규칙대로 즉시 릴리즈 제안).

## Out of Scope
- C4(plan-feature 예시 references 분리) — 보수적 결정으로 생략(이미 적합).
- description 트리거 정확도 정량 평가(skill-creator eval 루프) — 이번은 가이드 정합 다듬기까지. **단, 8개 description을 바꾸면 각 `evals/evals.json`과 미세 드리프트가 생기므로(plan-reviewer m4) 후속 eval 패스가 필요함을 인지**(이번 범위 밖).
- AGENTS.md 신규 생성(bootstrap) — 범위 밖.
- 8개 스킬 외 다른 스킬/플러그인 파일.

## Progress Log
- T1 완료 (Type A): add-domain-service — A1 본문 .NET 기준으로 축소 + B1 description near-miss.
- T2 완료 (Type A): add-viewmodel — B2 description near-miss(비-XAML/단순변경/디버깅/Jetpack 제외).
- T3 완료 (Type A): bootstrap-agents-md — B3 자연어 트리거+near-miss, D Step1 bash→PowerShell(Test-Path).
- T4 완료 (Type A): harness-toggle — A2 Bypass 유지 + 사유 주석(제한정책 호환·AV 위험조합 아님). status 실행 정상.
- T5 완료 (Type A): implement-task — B6 desc 중복문장 제거(자율 시그널 유지), C1a halt-conditions 인라인 포인터, C1b 컨텍스트한계 중복 축약. 546줄(보수적: 500 약간 초과 잔존).
- T6 완료 (Type A): llm-wiki — B4 desc config 경로 제거+near-miss(§0-1 보존), C2 절차 TOC, C3 wiki-schema §6 작업참조 포인터화(§7·정의 보존, version 2.14).
- T7 완료 (Type A): pjc-systematic-debugging — B7 pjc/DDD 변형 정체성 보강.
- T8 완료 (Type A): plan-feature — B5 "무엇"(plan.md 산출) 선두 추가, B8 형제 경계. C4 생략(보수적).
- T9 완료 (Type A): plugin.json·README L10 → 1.63.0, notes.md 1.63.0 항목.
- **검증 실증**: pyyaml로 8개 frontmatter 파싱 OK(name/desc 존재), 핵심 문구 20/20 grep(부정검사 포함) OK, wiki-schema §7 정의 보존+2.14, plugin.json JSON OK 1.63.0, harness-toggle status 정상.
- **결정**: B6 경량정리 / C3 경량포인터화 / 구조강도 보수적(C4 생략) / 버전 minor+릴리즈 / A2 Bypass 유지+주석 — 사용자 승인.
