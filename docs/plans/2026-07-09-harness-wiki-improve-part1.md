# Plan: 하네스 개선 — 버전 드리프트 감지·hook 이벤트 로깅·핸드오프·검증 매핑·LSP (part1)

**다음 plan**: docs/plans/2026-07-09-harness-wiki-improve-part2.md

## 요구 이해
- **원문 요청**: "위키, 하니스 모두 수정해줘" — 직전 대화에서 Claude가 제안한 개선 항목(하네스 5건 + 위키 4건)을 반영. 질문 라운드에서 사용자 확정: 전 항목 진행, plan 2분할(part1 하네스 / part2 위키), 로깅은 차단+경고 모두·명령 200자 마스킹 포함·block-destructive 포함(Q3 A/A/A), 드리프트 감지는 SessionStart hook 신설(Q4 A).
- **이해한 요구**: pjc 하네스에 ① 설치 캐시 버전 ↔ 하네스 레포 plugin.json 버전 불일치를 세션 시작 시 자동 경고하는 SessionStart hook, ② hook 차단/경고 이벤트를 발생 시점에 로컬 로그(jsonl)로 적재해 오탐 리뷰의 실측 데이터를 만드는 공용 로깅, ③ 분할 plan part1 완료 시 part2 세션용 핸드오프 노트(함정·기각 접근·검증 지름길)를 part2 plan 파일에 남기는 규약, ④ 이 레포 AGENTS.md에 변경 파일 → 검증 명령 매핑 표 명문화 + implement-task V-2의 표 인식, ⑤ reviewer/explorer subagent에 LSP 도구 추가와 "활성이면 우선" 가이드를 반영한다.
- **포함하지 않는 것으로 이해**: ④는 새 검증 선택 메커니즘 신설이 아니다 — V-2 조건부 축소·F-2 전체 보장이 이미 있어(v1.100.0) 매핑 표 명문화만 한다. suggest(제안) 이벤트 로깅은 이번 범위 아님(차단+경고만 — 사용자 확정).

## Goal
하네스가 버전 드리프트를 스스로 알리고, hook 오탐이 발생 시점에 데이터로 남고, 분할 plan 재개 세션이 이전 part의 암묵지를 물려받으며, task 검증 선택이 결정론적이 되고, reviewer의 심볼 추적 정확도가 LSP로 보강된다.

**전체 목표**: 직전 대화에서 제안·확정된 하네스 5건 + 위키 4건 개선 전체 반영 (part1 = 이 plan, part2 = 위키).

## Out of Scope
- **suggest-agents-record의 제안 이벤트 로깅**: 차단/경고가 아닌 제안 — 사용자 확정 범위(차단+경고) 밖. 필요성 확인되면 후속.
- **로그 자동 요약·리뷰 명령**: 이번은 적재만 — 리뷰는 사용자가 "오탐 검토" 세션에서 로그를 읽는 방식(README 안내). 자동 요약 스크립트는 데이터가 쌓인 뒤 재검토.
- **block-destructive·protect-harness의 차단 로직 변경**: 로깅 추가는 차단 판정에 어떤 영향도 주지 않는다(AGENTS.md DO NOT 준수 — try/catch 격리 + 골든 무회귀로 실증).

## Deferred / Follow-up
- **다음 분할 plan**: docs/plans/2026-07-09-harness-wiki-improve-part2.md — T1~T5 (전체의 위키 몫, 미실행)
- suggest 이벤트 로깅 확장 (Out of Scope의 재검토 조건과 함께)
- 로그 기반 오탐 자동 요약 스크립트 — 로그 3개월 축적 후
- (이월) suggest-agents-record grep 패턴 오탐 — T2 로깅 데이터 축적 후 근거 기반 수정
- (이월) plan-feature description 1,024자 한도 근접
- (T6 발견, 기존 상태) llm-wiki fixture `archive-exempt/.../oldproj.md`에 UTF-8 BOM 존재(v1.94.0부터, 이번 plan 미접촉·lint는 utf-8-sig로 허용이라 무해) — 다음 fixture 정비 때 무BOM으로 정리

## Investigation Log
- **hooks.json 현행 배선** (explorer + 직접 grep): PreToolUse(block-destructive 독립·pre-bash-dispatch·require-plan-for-write·protect-harness), PostToolUse(suggest-agents-record·post-write-checks), Stop(require-evidence). **SessionStart 배선 없음**. 모든 command가 `${CLAUDE_PLUGIN_ROOT}/scripts/*.ps1` + pwsh/powershell 폴백 패턴(:11~:80).
- **SessionStart 공식 지원 확인** (claude-code-guide, plugins-reference.md·hooks-guide.md·hooks.md 근거): 플러그인 hooks.json에 SessionStart 배선 가능. matcher = startup/resume/clear/compact(생략 시 동작은 문서 미명시 → 명시적 matcher 사용). stdin JSON에 `cwd`·`source`·`session_id`. stdout(또는 JSON `additionalContext`)이 세션 컨텍스트에 주입, exit 0 = 정상 진행.
- **설치 캐시 구조** (explorer): 캐시 루트 `~/.claude/plugins/cache/pjc-harness`, 신규 레이아웃 `pjc/<버전>/`(validate.ps1:30~41 — `[version]` 정렬로 최신 선택). hook 자신의 설치 경로는 `$env:CLAUDE_PLUGIN_ROOT`로 주어지므로 자기 버전은 `$env:CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json`에서 읽을 수 있다.
- **상태 마커 전례** (explorer): `~/.claude/.state/<용도>/` 패턴 — suggest-agents-record(:80~102, 30일 자동 정리 포함)·post-write-checks(:36~48). 이벤트 로그 위치·정리 규약의 재사용 근거.
- **보호 이름 집합 규약** (v1.97.2 전례 + 2026-07-09 grep 실측): hook 신설 시 protect-harness.ps1 `$harnessHookName`(:70)·post-write-checks.ps1(:56) 두 곳 + validate.ps1 `$hooks`/`$knownHelpers` 목록에 함께 추가. 누락 시 골든 시나리오가 FAIL로 잡는 구조(run-hook-evals 2b). AGENTS.md에도 산문 열거 2곳 실재(:26 골든 러너 "hook 9종(...)" 목록·:41 Repository Structure의 hook·헬퍼 열거) — 자동 검사가 없어 신설 시 함께 갱신해야 드리프트를 막는다(plan-reviewer m2 반영).
- **디스패처 구조** (v1.99.0, notes.md + AGENTS.md :41): pre-bash-dispatch가 bash-hook-lib 함수 3종(warn-external·require-task-checkbox·warn-commit-secrets)을 in-process 실행, 결과 객체 `@{Block;Stderr;Context}`로 수신 — **로깅을 디스패처 수준에서 결과 객체로 수행 가능**(lib 함수·얇은 래퍼 무수정). 로드 가드 전례: pre-bash-dispatch 헤더(Get-Command 부재 시 stderr 1줄 + exit 0 비차단, v1.101.0 T4).
- **시크릿 마스킹 재료**: secret-patterns.ps1(dot-source 헬퍼 — post-write·warn-commit-secrets가 사용)의 패턴 정규식을 마스킹에 재사용 가능. 로그에 시크릿 평문 금지(글로벌 보안 규칙 — 로그도 "로그 출력" 범주).
- **골든 러너**: run-hook-evals.ps1이 격리 USERPROFILE에서 실행(:AGENTS.md :26) — 이벤트 로그가 격리 프로필 `.state`에 쓰여 실 환경 오염 없음. 신규 케이스 추가 위치: hook-cases.json + 러너 내장 시나리오(2b 전례).
- **V-2 조건부 축소 현행** (implement-task SKILL.md:275 직접 Read): "AGENTS.md에 영향 범위 필터 명령이 있거나 스위트가 크면 변경 모듈만, 전체는 F-2 보장, 커밋 Tests: 줄에 범위 명시" — ④는 이 규정이 읽을 **매핑 표를 AGENTS.md에 명문화**하는 것 + V-2에 표 인식 1문장.
- **AGENTS.md 검증 명령 현행** (직접 Read :11~32): Build(전 ps1 parse)·Test(JSON 3종)·hook 골든("hook 스크립트 수정 시 필수")·check_consistency("llm-wiki 상수·배치 정합 … 수정 시 필수")·validate(재설치 후) — 조건이 산문으로 존재, 표로 재구성 가능(내용 신설 아님).
- **분할 plan 규약 현행** (직접 Read): implement-task SKILL.md:183(part 호출 규약 — part2는 경로 명시 호출·독립 T1), final-report-template.md:38~42(v1.104.0 복붙 안내), plan-template.md:41~46·:62~64·:80~81·:208(분할 포인터 3곳 동기 규칙). 재개 진입 :165~181(Progress Log·git·체크박스, 경량 K 참조 :172).
- **LSP 도구 공식 확인** (claude-code-guide, tools-reference.md 근거): LSP는 Claude Code 내장 도구 — subagent frontmatter `tools:`에 나열 가능. 코드 인텔리전스 플러그인 + 언어 서버 바이너리 설치 전까지 비활성(불활성 시 자연 부재 — fail-safe). 존재하지 않는 도구명 지정 시 동작은 문서 미명시 → LSP는 실존 도구명이라 해당 없음.
- **agent 정의 현행** (직접 Read frontmatter 6종): plan-reviewer(tools: Read, Grep, Glob — Bash 없음), spec-compliance·code-quality·plan-completion(Read, Grep, Glob, Bash), explorer(Read, Grep, Glob, Bash, haiku), spec-prefilter(haiku·8턴 — 경량 유지 대상).
- **SKILL 행수 실측** (wc -l): implement-task 492/500 — part1 T3(:183 부근)·T4(V-2) + part2 T4(:172) 합산 추가 ≤6줄 설계 필요. plan-feature 434/500 여유.
- **기존 plan.md 완료 확인**: v1.102.0 plan — 전 task [x]·PRD 없음·병합(0e42e2f)·push·릴리즈 완료(notes.md 2026-07-09 기록). Deferred 4건은 notes.md에 보존 + 관련분 이 plan Deferred로 이관. 교체 안전(분할 plan은 docs/plans/ 누적이라 루트 plan.md는 이번에 미사용 — implement-task가 경로 명시 호출).
- **AGENTS.md 신선도**: 이번 계획이 참조하는 검증 명령(parse·JSON·hook 골든·check_consistency·run_lint_evals) 전부 실재 — 어긋남 0.

## Risks & Unknowns
| 위험 | 영향 | 완화책 |
|---|---|---|
| block-destructive(마지막 방어선) 수정 | 로깅 결함이 차단을 깨면 안전 상실 | 로깅 호출 전체 try/catch(로깅 실패 = 무시), 로드 가드(함수 부재 시 조용히 skip), 차단 판정 코드 무변경, 골든 전 케이스 무회귀 + "로그 디렉터리 쓰기 불가여도 차단 정상" 케이스 신설 |
| SessionStart hook이 모든 세션 시작에 pwsh 콜드스타트 추가 | 세션 시작 지연 | 스크립트 첫 단계에서 cwd 마커 2종(plugins/pjc/.claude-plugin/plugin.json + .claude-plugin/marketplace.json) 부재 시 즉시 exit 0 — 비레포 세션 비용은 파일 존재 확인 2회 |
| matcher 생략 동작 미문서화 | 의도치 않은 발동 | 명시적 matcher `startup|resume|clear` 사용(compact 제외 — 압축 후 재주입 노이즈 방지) |
| 로그에 시크릿 유입 | 보안 규칙 위반 | secret-patterns 정규식으로 매치 값 `***` 치환 후 200자 절단 — 마스킹 실패 시 명령 텍스트 필드 자체를 생략(fail-closed) |
| implement-task SKILL.md 500줄 근접 | 공식 권장 위반 | part1+part2 합산 추가 ≤6줄, 초과 시 references 이관(v1.101.0 T6 전례) |
| LSP 미설치 환경에서 가이드가 공회전 | reviewer 혼란 | 가이드 문구를 "LSP 도구가 사용 가능하면"으로 조건화 — 불활성이면 기존 grep 절차가 그대로 정본 |

## Impact Analysis
### 4-A. 심볼/타입 추적 결과
| 심볼/앵커 | 영향 받는 파일 | 영향 종류 |
|---|---|---|
| hooks.json 이벤트 배선 | plugins/pjc/hooks/hooks.json | SessionStart 엔트리 신설 |
| `$harnessHookName` 이름 집합 | protect-harness.ps1(:70), post-write-checks.ps1(:56) | 신규 2파일(warn-version-drift·hook-event-log) 합류 |
| AGENTS.md 산문 열거 | AGENTS.md(:26 골든 hook 목록, :41 Repository Structure hook·헬퍼 열거) | T1(hook 합류)·T2(헬퍼 합류) 갱신 |
| validate.ps1 `$hooks`/`$knownHelpers` | validate.ps1 | 목록 2건 추가 |
| 차단/경고 방출 지점 | block-destructive.ps1, pre-bash-dispatch.ps1, require-plan-for-write.ps1, protect-harness.ps1, post-write-checks.ps1, require-evidence.ps1 | Write-HookEvent 호출 추가(판정 로직 무변경) |
| bash-hook-lib.ps1·얇은 래퍼 3종 | (무수정) | 로깅은 디스패처 수준 — 래퍼 골든 격리 유지 |
| V-2 조건부 축소(:275) | implement-task/SKILL.md | 매핑 표 인식 1문장 |
| 분할 plan 규약 | implement-task/SKILL.md(:183), final-report-template.md(:38~42), plan-template.md(:41~46 등 3곳 동기) | 핸드오프 생성·읽기 규정 |
| reviewer tools frontmatter | plan-reviewer.md, spec-compliance-reviewer.md, code-quality-reviewer.md, plan-completion-reviewer.md, explorer.md | LSP 추가 + 가이드 1~2줄 (spec-prefilter 제외) |

### 4-B. 계약·직렬화 변경
- hook 출력 규약(AGENTS.md Conventions) 불변 — 신규 SessionStart hook은 경고형(exit 0 + stdout 컨텍스트), 차단(exit 2) 목록 불변.
- 이벤트 로그 형식(신규 계약): `~/.claude/.state/hook-events/{YYYY-MM}.jsonl`, 1행 = `{ts, hook, decision(block|warn), rule, cmd?}` — 소비자는 사람/후속 세션(기계 파서 없음), 3개월 초과 파일 자동 정리.
- hooks.json 스키마: 기존 이벤트 엔트리 무변경, SessionStart 추가만.

### 4-C. 테스트 파일
- `plugins/pjc/hooks/evals/hook-cases.json` + `run-hook-evals.ps1` 내장 시나리오 — T1 3건·T2 3건 신설 + 기존 288 무회귀

### 4-D. 재사용 확인
| 신규 심볼 | 유사 기존 구현 검색 결과 | 재사용/신규 사유 |
|---|---|---|
| warn-version-drift.ps1 | 유사 기능 없음(validate.ps1은 수동·설치본 검사) | 신규 — 명명은 기존 warn-* 관례, stdin 파싱·pwsh 폴백은 기존 hook 패턴 복제 |
| hook-event-log.ps1 (Write-HookEvent) | secret-patterns.ps1·bash-hook-lib.ps1 (dot-source 헬퍼 전례) | 신규 헬퍼 — 마스킹은 secret-patterns 정규식 재사용, 저장·정리는 .state 마커 패턴(suggest-agents-record :84~88) 재사용 |
| AGENTS.md `## 검증 매핑` 표 | Build & Test 절의 산문 조건 | 기존 내용의 표 재구성(신설 아님) + 파일 패턴 열 추가 |
| 핸드오프 섹션(`## 이전 part 핸드오프`) | Progress Log·Next Steps | 목적 상이(재개 안내 ≠ 함정·기각 접근 전수) — 신규 섹션, 5줄 상한으로 비대 방지 |

### Verified by
- grep `CLAUDE_PLUGIN_ROOT|SessionStart` hooks.json → SessionStart 0건(신설 확인), 전 command 패턴 확인
- grep `K-DRIFT|...` (part2 몫 — part2 plan에 기재)
- agent frontmatter 6종 직접 Read — tools 현행 전수 확인

## Decisions
### D1. 드리프트 감지 방식 (사용자 확정 Q4-A)
- **Chosen**: SessionStart hook 신설(`warn-version-drift.ps1`), matcher `startup|resume|clear`
- **Rationale**: 이미 벌어진 드리프트를 세션 시작에 잡는 것이 목적 — Write 편승(B안)은 반쪽. compact는 재주입 노이즈라 제외. 비레포 세션은 마커 파일 확인 2회로 즉시 종료.
- **Source**: 사용자 답변 Q4=A, plugins-reference.md(SessionStart 지원), hooks.md(stdin cwd·source)

### D2. 하네스 레포 판정·버전 비교
- **Chosen**: stdin `cwd`에서 `plugins/pjc/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` 둘 다 실재할 때만 레포로 판정. 레포 버전(plugin.json) ≠ 자기 버전(`$env:CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json`)이면 stdout 경고 1줄("설치본 vX ≠ 레포 vY — 재설치 전까지 설치본은 구 동작(install.ps1)"). `CLAUDE_PLUGIN_ROOT` 부재·파싱 실패 등 모든 예외는 조용히 exit 0(경고 hook은 fail-open).
- **Rationale**: 마커 2중으로 임의 레포 오탐 방지. 자기 버전을 캐시 폴더 스캔이 아니라 자기 plugin.json에서 읽으면 다중 버전 캐시·레거시 레이아웃과 무관.
- **Source**: validate.ps1:28~41(캐시 레이아웃), hooks.json `${CLAUDE_PLUGIN_ROOT}` 사용 실재

### D3. 로깅 수위·대상 (사용자 확정 Q3 A/A/A)
- **Chosen**: 차단(exit 2) + 경고 이벤트 모두. 1행 = ts·hook명·판정·발동 규칙 키워드·마스킹된 명령 앞 200자. block-destructive 포함.
- **Rationale**: 오탐 판정에 명령 문맥 필수. 마스킹은 secret-patterns 정규식 재사용, 마스킹 단계 실패 시 cmd 필드 생략(fail-closed). block-destructive가 오탐 데이터의 최대 가치원.
- **Source**: 사용자 답변 Q3, v1.98.0 오탐 수정 이력(notes.md)

### D4. 로깅 아키텍처
- **Chosen**: 신규 dot-source 헬퍼 `hook-event-log.ps1`(함수 `Write-HookEvent`). 적용 지점 6곳 — block-destructive·require-plan-for-write·protect-harness(각 자기 판정 시점), pre-bash-dispatch(lib 3검사 결과 객체로 일괄 — **lib 함수·얇은 래퍼 무수정**), post-write-checks·require-evidence(경고 방출 시점). 전 지점 try/catch + 로드 가드(함수 부재 시 skip). 로그: `~/.claude/.state/hook-events/{YYYY-MM}.jsonl`, 90일 초과 파일 정리(suggest-agents-record 30일 정리 패턴 재사용).
- **Rationale**: 디스패처 수준 로깅으로 골든 격리 구조(래퍼 존치) 유지. 헬퍼 분리로 6곳 중복 없이 1곳 수정. 월별 jsonl은 log 롤오버 전례와 일관.
- **Source**: AGENTS.md :41(디스패처 구조), pre-bash-dispatch 로드 가드 전례(v1.101.0 T4)

### D5. 핸드오프 생성·소비 지점
- **Chosen**: 생성 — part1 최종 보고 직전(final-report-template 분할 안내 절), part2 plan 파일 상단(분할 포인터 아래)에 `## 이전 part 핸드오프` 섹션 append: 함정·기각된 접근·검증 지름길 각 1줄, 총 5줄 상한(없으면 "특이사항 없음" 1줄). 소비 — implement-task :183 분할 호출 규약에 "part 시작 시 이 섹션을 먼저 읽는다" 명시 + plan-template 분할 주석에 섹션 규약 동기.
- **Rationale**: part2 파일에 두면 재개 세션이 plan만 읽어도 핸드오프가 보인다(별도 파일은 유실 위험). 5줄 상한으로 Progress Log 중복·비대 방지. plan 파일 기록은 implement-task의 기존 쓰기 범위(plan 갱신) 내.
- **Source**: final-report-template.md:38~42(v1.104.0 안내 강화 — 같은 자리 확장), SKILL.md:183

### D6. 검증 매핑 표 형식
- **Chosen**: AGENTS.md Build & Test 절에 `### 검증 매핑 (task 검증 선택)` 표 — `| 변경 파일 패턴 | 필수 검증 |` (예: `plugins/pjc/hooks/**·scripts/*.ps1` → parse+hook 골든 / `skills/llm-wiki/**` → check_consistency+run_lint_evals / `*.json 매니페스트` → JSON 3종 / 그 외 .md → parse만). implement-task V-2(:275)에 "AGENTS.md에 검증 매핑 표가 있으면 task 검증은 변경 파일 패턴에 맞는 행만 실행(전체는 F-2 보장)" 1문장.
- **Rationale**: 기존 산문 조건("수정 시 필수")의 표 재구성 — 신규 정책이 아니라 결정론화. F-2 전체 보장 불변이라 회귀 안전망 유지.
- **Source**: AGENTS.md :11~32(산문 조건 실재), implement-task SKILL.md:275(조건부 축소 정본)

### D7. LSP 적용 대상·문구
- **Chosen**: reviewer 4종(plan·spec-compliance·code-quality·plan-completion) + explorer의 tools에 `LSP` 추가 + 본문에 "LSP 도구가 사용 가능하면 호출자/구현체/참조 추적에 grep보다 우선 사용(불활성 환경이면 기존 grep 절차 그대로)" 1~2줄. spec-prefilter 제외(경량 8턴 유지).
- **Rationale**: LSP는 내장 도구로 tools 나열 가능(공식 문서 확인), 미설치 환경 자연 비활성 — 가이드 조건화로 공회전 방지. 호출자 2곳 이상 판정 등 참조 추적이 reviewer 핵심 입력.
- **Source**: tools-reference.md(내장 도구 확인 — claude-code-guide), agent frontmatter 직접 Read

### D8. 버전
- **Chosen**: part1 완료 시 1.105.0 (minor).
- **Source**: 버전 규약 전례(notes.md)

## Tasks

- [x] T1. SessionStart 버전 드리프트 경고 hook (warn-version-drift.ps1)
  - **Type**: D
  - **Acceptance**: Given 하네스 레포 cwd + 설치본 버전 ≠ 레포 plugin.json 버전, When SessionStart(startup|resume|clear), Then stdout으로 "설치본 vX ≠ 레포 vY …" 경고 1줄 + exit 0. Given 버전 일치 또는 비레포 cwd 또는 CLAUDE_PLUGIN_ROOT 부재, Then 무출력 exit 0. And protect-harness·post-write 이름 집합, validate `$hooks`에 합류(설치본 개조 차단). And 골든 3건(불일치 경고/일치 침묵/비레포 침묵) PASS + 기존 288 무회귀.
  - **Files**:
    - 주: `plugins/pjc/scripts/warn-version-drift.ps1` (신규), `plugins/pjc/hooks/hooks.json` (SessionStart 엔트리)
    - 동반: `plugins/pjc/scripts/protect-harness.ps1` (:70 집합), `plugins/pjc/scripts/post-write-checks.ps1` (:56 집합), `validate.ps1` ($hooks 목록), `AGENTS.md` (:26 골든 hook 목록 + :41 Repository Structure hook 열거)
    - 테스트: `plugins/pjc/hooks/evals/hook-cases.json` 또는 러너 내장 시나리오 (+ `run-hook-evals.ps1`)
  - **Edge Cases**:
    - stdin JSON 파싱 실패·cwd 필드 없음 → 조용히 exit 0
    - 레포 plugin.json이 손상 JSON → 조용히 exit 0 (경고 hook fail-open)
    - 레거시 캐시 레이아웃(자기 plugin.json 경로 상이) → `$env:CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json` 부재 시 조용히 exit 0
    - Windows PowerShell 5.1 폴백 경로에서도 동작(기존 hook과 동일 pwsh 폴백 패턴)
  - **Halt Forecast**:
    - (ii-a) hooks.json 구조 변경(이벤트 신설) → `## 사전 승인 항목`에 등록
  - **Depends on**: -

- [x] T2. hook 이벤트 로깅 (hook-event-log.ps1 헬퍼 + 6개 지점 적용)
  - **Type**: D
  - **Acceptance**: Given 차단·경고가 실제 방출되는 hook 이벤트, Then `~/.claude/.state/hook-events/{YYYY-MM}.jsonl`에 `{ts, hook, decision, rule, cmd(≤200자·시크릿 마스킹)}` 1행 append — 차단/경고 판정 자체는 수정 전과 완전 동일(골든 288 무회귀로 실증). Given 로그 디렉터리 쓰기 불가·헬퍼 로드 실패, Then hook 본연 동작(차단/경고) 정상 + 로깅만 조용히 생략(신규 골든 케이스로 실증). Given 시크릿 포함 명령, Then 로그의 cmd 필드에 시크릿 평문 부재(마스킹 실패 시 cmd 필드 생략). And 90일 초과 로그 파일 자동 정리.
  - **Files**:
    - 주: `plugins/pjc/scripts/hook-event-log.ps1` (신규 헬퍼 — Write-HookEvent)
    - 동반: `plugins/pjc/scripts/block-destructive.ps1`, `plugins/pjc/scripts/pre-bash-dispatch.ps1`, `plugins/pjc/scripts/require-plan-for-write.ps1`, `plugins/pjc/scripts/protect-harness.ps1`, `plugins/pjc/scripts/post-write-checks.ps1`, `plugins/pjc/scripts/require-evidence.ps1`, `plugins/pjc/scripts/protect-harness.ps1`(:70)·`post-write-checks.ps1`(:56) 이름 집합, `validate.ps1` ($knownHelpers), `AGENTS.md` (:41 헬퍼 열거에 hook-event-log 합류), `README.md` (오탐 리뷰 안내 1블록)
    - 테스트: `plugins/pjc/hooks/evals/hook-cases.json`·`run-hook-evals.ps1` (로그 생성 실증 1건 + 쓰기 불가 격리 1건 + 마스킹 1건, 기존 288 무회귀)
  - **Edge Cases**:
    - bash-hook-lib 함수·얇은 래퍼 3종 무수정 유지(래퍼 단독 실행 골든은 로그 없이도 PASS — 로깅은 디스패처 몫)
    - 동시 세션 두 개가 같은 월 파일에 append → append 모드 사용, 실패 시 무시(로그는 best-effort)
    - block-destructive: 로깅 코드가 차단 경로보다 먼저 실패해도 차단 도달 보장(try/catch 위치를 판정 후·exit 직전으로)
  - **Halt Forecast**:
    - (ii-a) block-destructive·protect-harness 파일 수정(차단 로직 무변경, 로깅 추가만 — AGENTS.md DO NOT 대상 파일) → `## 사전 승인 항목`에 등록 (사용자 Q3 답변으로 방향 기승인, plan 승인으로 확정)
  - **Depends on**: T1 (protect-harness·validate 이름 집합을 두 task가 연속 수정 — 충돌 방지 순차)

- [x] T3. 분할 plan 핸드오프 브리핑
  - **Type**: C
  - **Acceptance**: Given 분할 plan part1의 Phase F 통과 후 최종 보고 생성, Then part2 plan 파일 상단(분할 포인터 아래)에 `## 이전 part 핸드오프`(함정·기각된 접근·검증 지름길 — 총 5줄 상한, 없으면 "특이사항 없음" 1줄)를 append하는 규정이 final-report-template 분할 안내 절에 존재. And implement-task :183 분할 호출 규약에 "part 시작 시 이 섹션 우선 읽기" 명시(SKILL.md ≤500줄 유지). And plan-template 분할 주석에 섹션 규약 동기(3곳 동기 목록 갱신 불필요 — 경로 아님).
  - **Files**:
    - 주: `plugins/pjc/skills/implement-task/references/final-report-template.md` (분할 안내 절 확장)
    - 동반: `plugins/pjc/skills/implement-task/SKILL.md` (:183 1~2줄), `plugins/pjc/skills/plan-feature/references/plan-template.md` (분할 주석 1~2줄)
  - **Edge Cases**:
    - part2 파일이 없거나 접근 불가 → 핸드오프 생략하고 최종 보고에 그 사실 1줄(보고는 계속)
    - 핸드오프에 시크릿·민감 정보 금지(plan.md 민감 정보 규칙 그대로 적용)
    - 3-part 이상 분할(드묾) → "다음 part 파일"에 동일 적용(part2→part3도 같은 규약)
  - **Halt Forecast**: (해당 없음 — 순수 스킬 문서 편집, 파괴적·외부·의존성 요소 없음)
  - **Depends on**: -

- [x] T4. 검증 매핑 표 (AGENTS.md + V-2 인식)
  - **Type**: C
  - **Acceptance**: AGENTS.md Build & Test에 `### 검증 매핑` 표(변경 파일 패턴 → 필수 검증 — 기존 산문 조건과 모순 0, hook 골든·check_consistency·run_lint_evals·JSON·parse 전 명령 포함). implement-task V-2(:275)에 매핑 표 인식 1문장(전체는 F-2 보장 문구 유지, SKILL.md ≤500줄).
  - **Files**:
    - 주: `AGENTS.md`
    - 동반: `plugins/pjc/skills/implement-task/SKILL.md` (:275 1문장)
  - **Edge Cases**:
    - 매핑에 없는 파일 패턴 변경 → 표에 "그 외" 행으로 기본값(parse+JSON) 명시 — 미매핑 공백 방지
    - 한 task가 여러 패턴에 걸침 → 해당 행 전부 실행(합집합) 명시
  - **Halt Forecast**:
    - (ii-a) AGENTS.md 수정(기존 산문 조건의 표 재구성) → `## 사전 승인 항목`에 등록
  - **Depends on**: T1 (AGENTS.md를 T1도 수정 — 순차)

- [x] T5. reviewer·explorer LSP 보강
  - **Type**: C
  - **Acceptance**: plan-reviewer·spec-compliance-reviewer·code-quality-reviewer·plan-completion-reviewer·explorer 5개 frontmatter `tools:`에 LSP 추가 + 각 본문에 "LSP 사용 가능 시 참조 추적 우선(불활성이면 기존 grep 절차)" 1~2줄. spec-prefilter 무변경. disallowedTools 무변경(Write/Edit 차단 유지).
  - **Files**:
    - 주: `plugins/pjc/agents/plan-reviewer.md`, `plugins/pjc/agents/spec-compliance-reviewer.md`, `plugins/pjc/agents/code-quality-reviewer.md`, `plugins/pjc/agents/plan-completion-reviewer.md`, `plugins/pjc/agents/explorer.md`
  - **Edge Cases**:
    - plan-reviewer는 Bash 미보유 — LSP 추가가 Bash 부여로 오인되지 않게 tools 나열만 정확히
    - LSP 불활성 프로젝트(이 레포 포함 — ps1/md에 언어 서버 없음) → 가이드 조건문이 공회전 없이 grep 경로 유지
  - **Halt Forecast**:
    - (ii-a) agent 정의 5개 frontmatter tools 변경 → `## 사전 승인 항목`에 등록
  - **Depends on**: -

- [x] T6. 버전·README·통합 검증
  - **Type**: A
  - **Acceptance**: plugin.json·README 1.104.0→1.105.0 + README v1.105.0 안내 1블록(드리프트 경고·이벤트 로깅·핸드오프·검증 매핑·LSP). 통합 검증 전부 green: 전 ps1 parse OK, JSON 3종 OK, hook 골든 전 케이스(기존 288 + 신규 ~6) PASS, check_consistency exit 0(이 plan은 llm-wiki 상수 무변경 — 통과 확인만), .md 무BOM·.ps1 BOM 규약.
  - **Files**:
    - 주: `plugins/pjc/.claude-plugin/plugin.json`, `README.md`
  - **Edge Cases**: (없음 — 기계 검증만)
  - **Halt Forecast**: (해당 없음)
  - **Depends on**: T1~T5

## 사전 승인 항목 (일괄 승인 대상)
- T1 — hooks.json에 SessionStart 이벤트 엔트리 신설(구조 변경) + 신규 hook 스크립트 1개 추가
- T2 — `block-destructive.ps1`·`protect-harness.ps1` 파일 수정(차단 판정 로직 무변경, 로깅 호출 추가만 — AGENTS.md DO NOT 대상 파일이라 명시 승인 필요, 골든 무회귀로 실증) + 신규 헬퍼 1개 추가
- T4 — AGENTS.md 수정(검증 매핑 표 — 기존 산문 조건의 표 재구성)
- T5 — agent 정의 5개 frontmatter tools 변경
- T1~T6 — 로컬 작업 브랜치 commit(체크포인트·task 완료 commit, implement-task 규약)

## 불가피한 Halt (위임 불가 — 일괄 사전승인 불가)
- push·main 병합·태그·릴리즈 v1.105.0 발행 — 최종 보고 후 별도 승인
- 재설치(install.ps1) — 사용자 제외 지시 유지 중

## Known Workarounds (있는 경우만)
- (없음)

## Verification Strategy
- 빌드: AGENTS.md Build(전 ps1 PSParser parse) — hook 스크립트 수정 task 전부
- 테스트: `pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1` (T1·T2 필수), JSON 매니페스트 3종, `python plugins/pjc/skills/llm-wiki/evals/check_consistency.py` (T6 통과 확인)
- 수동 검증: SessionStart hook의 실 세션 발동은 재설치 후에만 가능 — "골든 통과 + 재설치 후 실동작은 사용자 확인 필요"로 구분 보고(빌드 통과 ≠ 동작 확인 원칙)

## Phase Ledger

## Retry Ledger

## Progress Log
- T1-T2 완료 (커밋 74f9485, T2는 amend 예정): warn-version-drift(SessionStart, matcher startup|resume|clear, 마커 2종+fail-open) + hook-event-log 헬퍼(6지점, 시크릿은 cmd 필드 생략 fail-closed — Get-SecretMatches가 라벨만 반환해 값 치환 대신 생략 채택). 골든 288→297 전부 green, 리뷰 4건 전부 OK 1심 통과.
- T3-T5 완료 (커밋 ca4b5b5·ec7cbdb·T5 amend): 핸드오프 섹션 규약(final-report-template 생성 + SKILL :183 읽기 + plan-template 주석, 3-part 일반화 MINOR 즉시 반영) / AGENTS 검증 매핑 표 + V-2 표 인식 / agent 5종 LSP(tools+조건화 가이드, prefilter·disallowedTools 무변경). 리뷰 3건 전부 OK.

## Next Steps
- 이 plan(part1) 완료 후: 남은 분할 plan `docs/plans/2026-07-09-harness-wiki-improve-part2.md` — pjc:implement-task로 별도 실행

## Open Questions
- (없음 — Q1~Q4 사용자 확정 반영 완료)
