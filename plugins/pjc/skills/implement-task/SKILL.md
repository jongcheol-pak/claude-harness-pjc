---
name: implement-task
description: This skill should be used when executing tasks from an approved plan.md. Triggers on phrases like "구현", "implement", "T<N> 진행", "이대로 진행", "go", "진행해". Runs FULLY AUTONOMOUS loop — processes ALL tasks (T1...Tn) without asking the user between tasks. Resuming mid-plan ("T6부터 계속") means T6 through the LAST task plus Phase F/G — not just T6. Only stops when all tasks complete or a Halt Condition fires. Never asks "Should I proceed to the next task?" between tasks. For trivial single-line edits without a plan, do NOT use this skill — Claude applies the change directly and lets hooks validate.
argument-hint: "<시작 task ID (거기부터 끝까지 자율 진행) | 생략 시 첫 미완료부터>"
---

# Implement Task

승인된 plan.md의 작업을 PIV 루프(Plan-Implement-Validate)로 자율 실행한다.
각 task는 Type에 따라 적절한 단계 통과 후에만 완료된다.

## 자율성 모드: FULLY AUTONOMOUS

> **이 skill 안에서는 사용자에게 묻지 않는다.**
> plan-feature에서 모든 결정이 사전 해결되었음을 전제로 진행.
>
> 멈춤은 **Halt Condition**에서만 발생. 사소한 결정은 plan.md follow-up으로 기록 후 계속.

```
plan-feature                    | implement-task (이 skill)
USER-INTERACTIVE                | FULLY AUTONOMOUS
                                |
질문 OK (Open Questions에 모음) | 질문 금지 (Halt만 가능)
사용자 승인 1회 (게이트)         | plan = 전체 위임장
                                |
                  ↑ 모든 질문 해결 후 ─── 이 시점부터 자율 ───
```

## 절대 규칙 (Hard Rules)

### 완료 정의
1. **Done = Proof.** 빌드 통과, 테스트 통과, 또는 재현 가능한 출력 없이는 완료 선언 금지.

2. **검증된 코드만 사용 (환각·예측 금지).**
   - 모르는 API/라이브러리/시그니처는 Read 또는 문서 확인 후 사용.
   - 정의를 못 찾으면 호출 코드 작성 금지.
   - "이 함수가 있을 것", "이 인자를 받을 것" 같은 추정은 환각 → 리뷰에서 BLOCKER.

3. **연관 파일 함께 수정 (Cross-File Consistency).**
   - 시그니처/타입/계약을 바꾸면 **모든 호출자/구현체/직렬화/테스트를 같은 task에서 함께 수정**.
   - a만 고치고 b·c를 두면 빌드 실패 또는 런타임 오류 → 완료 선언 금지.
   - Phase P-3에서 사전 식별, Phase V-5/V-7과 impact-warn hook에서 사후 검증.

### 변경 범위
4. **요청한 것만, 확인된 범위 안에서, 최소한으로 수정.**
   - 무관한 리팩토링·서식 변경·import 정리 금지.
   - 작업 중 발견한 다른 문제는 plan.md follow-up에 추가만.
   - 한 번에 한 task만 수행.

### 아키텍처·코드 규율
5. **DDD 준수 + YAGNI.**
   - 비즈니스 로직은 Domain 레이어 (AGENTS.md가 다른 아키텍처를 명시하면 우선 적용).
   - 사용처 1곳인 헬퍼는 인라인. 3회 반복 확인된 코드만 공통화.

6. **위생.** 불필요한 주석·죽은 코드·미사용 import·placeholder 문서 금지.

7. **주석은 한글.** "무엇"이 아닌 "왜". 코드로 의도가 드러나면 생략.

8. **파일·인코딩.** 1500라인 내외, UTF-8 (BOM 없음). 초과 시 기능 단위 분리 작업 plan에 등록.

9. **언어 스타일.** 최신 LTS 권장 + 공식 문서 기준. AGENTS.md가 다른 버전 고정이면 우선.

### 안전
10. **파괴적 작업 · 새 의존성 → 자동 실행 금지, Halt.**
    - force push, history rewrite, rm -rf, DB drop, 권한·보안 변경
    - **DB 데이터 삭제·변조**: DROP/TRUNCATE, WHERE 없는(또는 전체 대상) DELETE·UPDATE, 스키마 삭제, migration reset/down, ORM 대량 삭제(RemoveRange·deleteMany({})·delete_all 등). 코드로 작성하든 명령으로 실행하든, 데이터 손실·전체 변조 가능 작업은 **사용자 승인 전 금지** (DB 데이터는 git으로 복구 불가). 단 `DELETE/UPDATE ... WHERE <특정 조건>` 같은 일상적·국소적 작업은 plan에 명시돼 있으면 진행 가능.
    - 새 라이브러리·외부 서비스 도입

> **상세 안티패턴 표는 `references/antipatterns.md` 참조.**

## 자율 루프 (Autonomous Loop)

### 🚨 자율 루프의 절대 규칙

**모든 task가 완료되거나 Halt Condition이 발동할 때까지 멈추지 않는다.**

- ❌ **task 사이에 사용자에게 묻지 않는다.**
- ❌ "다음 task로 진행할까요?", "T2를 시작할까요?" 같은 확인 요청 금지.
- ❌ MINOR follow-up이나 사소한 결정에 사용자 의견 묻지 않는다 (plan.md에 기록 후 계속 진행).
- ✅ **사용자 개입은 다음 두 경우에만**:
  1. Halt Condition 발동
  2. 모든 task 완료 (Phase F 통과 후 최종 보고)

**사용자 승인은 plan-feature 단계에서 plan.md에 대해 단 1회만 받았다.** plan.md = 전체 작업의 위임장.

### 🧠 컨텍스트 관리 (장시간 작업 대비)

자율 루프가 길어지면 컨텍스트가 누적되어 후반 task의 품질이 저하될 수 있다. 다음을 지킨다:

1. **각 task는 독립적으로 처리.**
   - 이전 task에서 읽은 파일 내용·빌드 로그에 의존하지 않는다.
   - 필요한 정보는 **plan.md와 git에서 다시 확인** (둘 다 영구 저장됨).
   - 이전 task 상세를 기억하려 애쓰지 말 것 — 이미 commit과 plan.md에 있음.
   - **plan이 작업을 "Phase 1~N", "단계 1~N", "Step 1~N" 등으로 나눴더라도(T<N>이 아닌 명칭) 동일하게 자율 처리한다.** 그 묶음 사이에서 멈춰 "Phase 2 진행할까요?"라고 묻지 않는다. plan의 "Phase N"은 pjc 내부의 Phase(P/I/V/D·F·G)와 무관한, 사용자 작업 묶음일 뿐이다. 모든 작업 단위를 마지막까지 자율로 진행한다.

2. **빌드/테스트 로그는 핵심만 유지.**
   - 전체 로그 원문을 컨텍스트에 길게 남기지 않는다.
   - "Build OK / Tests 12/12 passed" 같은 결과 + 실패 시 핵심 에러만.

3. **2개 task마다 Progress Log 갱신.**
   - plan.md의 `## Progress Log`에 완료 task 요약 1-2줄 기록.
   - 이후 task는 전체 대화 history 대신 이 요약 + git log 참조.

4. **컨텍스트 한계 근접 시 멈추지 않는다 — 압축을 통과해 계속 진행한다.**
   - 컨텍스트가 과밀해지면 **현재 task를 Phase V/D까지 완료**하고 (task 중간에 끊지 않음 — 절반 수정 상태는 압축 후 복구가 불완전하다), plan.md에 상태를 완전 기록한다: Progress Log + Next Steps + 다음 task의 정확한 시작점.
   - 그 후 **사용자 보고 없이 계속 진행** — Claude Code의 auto-compact가 자동 압축하며, PreCompact hook(backup-on-compact)이 plan.md 스냅샷을 백업한다.
   - **압축 감지 시 (대화에 압축 요약이 보이면) 첫 행동은 plan.md + AGENTS.md 재읽기.** 압축 요약은 세부를 잃으므로, plan.md(진실의 원천)와 AGENTS.md(컨벤션)를 다시 읽어 컨텍스트를 복구한 뒤 다음 task를 재개한다. 요약의 기억만으로 작업을 이어가지 않는다.
   - 사용자 호출(Halt)은 다른 Halt 조건(파괴적 작업, 동일 실패 반복 등)에 해당할 때만. 컨텍스트 한계 자체는 Halt 사유가 아니다.

### 진행 흐름

```
loop over plan.md tasks (시작 task부터 Tn까지 — 첫 실행은 T1, 재개면 지정/첫 미완료 task):
  Phase P → 변경 전략 확정, caller 사전 추적
  Phase I → 최소 변경으로 구현
  Phase V → Type별 fast-path (V-1~V-8)
  Phase D → checkpoint commit → (2 task마다 Progress Log) → 즉시 다음 task로

# 모든 task 완료 후
Phase F → 전체 plan 통합 검증 (조건부 진입)
Phase G → PRD 요구 재검증 (docs/prd.md 있을 때만 — 갭 발견 시 task 추가 후 자율 재진입, 최대 2회)
→ 최종 보고 (첫 사용자 개입 지점)
```

## Phase P — Plan (작업 단위)

각 task에 대해 Phase I 진입 전 다음 확인.

### 재개 진입 (중간 체크포인트에서 이어하기)

"T<N>부터 계속" 같은 요청으로 시작하는 경우:
1. plan.md의 `## Progress Log`를 읽어 완료 task 파악
2. `git log`로 마지막 commit 상태 확인
3. plan.md의 task 체크박스로 미완료 task 식별
4. 지정된 task(또는 첫 미완료 task)부터 Phase P 시작
5. 이전 task 상세는 Progress Log + git으로만 참조 (전체 history 불필요)

**재개도 완전 자율 루프다.** "T6부터 계속"은 "T6 하나만"이 아니라 **"T6부터 마지막 task까지 + Phase F/G까지"를 의미한다.** 첫 세션의 T1 시작과 재개 세션의 T6 시작은 시작점만 다를 뿐 동일한 루프이며, 금지 표현 규칙("T7 진행할까요?" 금지)도 동일하게 적용된다. task 사이에 멈춰 사용자에게 묻는 것은 재개 세션에서도 위반이다. 단일 task만 실행하는 경우는 사용자가 "T6만" 처럼 명시적으로 한정했을 때뿐이다.

### P-1. plan.md 해당 task 정독
- task의 Acceptance, Files, Edge Cases, Halt Forecast, Type 모두 확인.

### P-2. Files 목록 직접 Read
- task의 Files에 있는 모든 파일을 Read 도구로 직접 열어 현재 상태 확인.
- 가정 금지. 파일 내용은 항상 직접 읽어 검증.

### P-3. 심볼 사용처 전수 추적
- 변경 대상 심볼에 대해 `grep -rn "\b<symbol>\b"` 실행.
- 결과를 모두 Read로 확인.
- task의 Files 목록과 대조 → 누락된 caller 발견 시 **자율 처리가 기본**: plan.md의 해당 task Files에 누락 caller를 추가하고 함께 수정한다 (멈추지 않음). caller 갱신은 절대 규칙 3(Cross-File Consistency)의 정상 작업이다.
  - **예외 (Halt)**: 누락 caller가 plan 범위를 크게 벗어나거나(예: 수십 개 파일 연쇄), 파괴적 변경·새 의존성을 유발하는 경우에만 Halt. 단순 caller 추가는 Halt 사유가 아니다.

### P-4. 외부 식별자 확인 (환각 방지)
- 호출할 외부 API/메서드/타입의 정의 위치를 직접 확인.
- 못 찾으면 호출 코드 작성 금지. plan에 "확인 필요" 등록.

### P-5. 변경 전략 명시
- 어떤 순서로 변경할지 한 줄로 작성 (자기 점검용).

## Phase I — Implement

- 시작 시 **checkpoint** 생성:
  ```bash
  git status                            # clean 확인
  git checkout -b task/<id>-<slug>      # 작업 브랜치 (이미 있으면 스킵)
  git commit --allow-empty -m "checkpoint: T<N> start"
  ```
- 기존 코딩 컨벤션 따름 (AGENTS.md > 주변 코드 모방)
- 최소 변경 원칙
- 변경 후 즉시 빌드. 오류는 다음 변경 전에 해결.

### Sub-skill 호출 (해당 시)

| Task 산출물 | 호출 sub-skill | 조건 |
|---|---|---|
| WinUI 3/WPF/MAUI ViewModel + View | `pjc:add-viewmodel` | AGENTS.md에 WinUI/CommunityToolkit.Mvvm 명시 시 |
| Domain Service / Application Service | `pjc:add-domain-service` | AGENTS.md에 DDD/Clean 아키텍처 명시 시 |
| 그 외 | (sub-skill 없음, 직접 구현) | |

**Android의 Jetpack ViewModel은 `add-viewmodel` 비대상** — 직접 구현 또는 별도 skill 필요.

## Phase V — Validate

순서대로 실행. 실패 시 Phase I로 1회 복귀 후 재시도.

### 🚀 Fast-Path — Task Type에 따른 단계 선택

| Type | 실행 단계 | 생략 단계 |
|---|---|---|
| **A** (Doc/Config) | V-8만 (코드 빌드에 영향 주는 설정이면 V-1 추가) | V-1(대개)~V-7 |
| **B** (Trivial Code) | V-1 + V-2 + V-5(**prefilter Haiku**) + V-8 (prefilter PASS 시 V-7은 grep 1회로 축소) | V-3, V-6, (V-7 축소) |
| **C** (Normal Code) | V-1 + V-2 + V-3 + V-5(compliance Sonnet) + V-7 + V-8 | V-6 (선택) |
| **D** (Complex/Cross-cutting) | V-1 ~ V-8 **전체** (V-5는 compliance Sonnet) | 생략 없음 |

**Task Type 미명시** → D로 간주 (안전 우선).
**V-4(PostToolUse hook)는 자동 실행** — 모든 Type에서 작동 (UTF-8 + impact-warn).

#### Type A 빌드 판단
- 순수 문서·주석·README·`.gitignore` 등 **빌드에 영향 없는 파일** → V-1도 skip, V-8만.
- `.csproj`/`build.gradle`/`package.json` 등 **빌드 구성에 영향 주는 설정** → V-1 빌드 실행.

#### Type B prefilter PASS 시 V-7 축소
- spec-prefilter(Haiku)가 PASS → 변경 심볼이 trivial이므로 V-7 caller 재검증을 **변경 심볼 grep 1회**로 축소 (전체 재추적 불필요).
- prefilter가 ESCALATE → 정상 V-5(Sonnet) + V-7 전체 수행.

### V-1. 빌드
- AGENTS.md의 build 명령 실행. exit 0 확인. 오류 시 Phase I로 1회 복귀 후 재시도.
- **AGENTS.md 없거나 build 명령 미정의** → 표식 파일로 자동 추론:
  - `*.csproj`/`*.sln` → `dotnet build`
  - `build.gradle*` → `./gradlew assembleDebug`
  - `package.json` → `npm run build` (script 있을 때) 또는 skip
  - `pyproject.toml` → `python -m build`
  - `go.mod` → `go build ./...`
  - `Cargo.toml` → `cargo build`
  - 위 어느 것도 아님 → AGENTS.md에 build 명령이 있으면 그것 사용. 없으면 Halt → 사용자에게 build 명령 요청 (또는 `pjc:bootstrap-agents-md`로 AGENTS.md 생성 제안)

### V-2. 테스트
- AGENTS.md의 test 명령 실행. 통과 케이스 수 기록.
- **AGENTS.md 없거나 test 명령 미정의** → 표식 파일 fallback:
  - `*.csproj` → `dotnet test`
  - `build.gradle*` → `./gradlew test`
  - `package.json` (test script 있음) → `npm test`
  - `pyproject.toml` → `pytest`
  - `go.mod` → `go test ./...`
  - `Cargo.toml` → `cargo test`
  - 위 어느 것도 아님 → Halt

### V-3. 린트/정적 분석
- 프로젝트 표준 도구 실행. 신규 경고 0 확인.

### V-4. 자동 검증 hook
- PostToolUse hook 자동 실행 (`check-utf8-and-lines`, `impact-warn`).
- impact-warn 경고 발생 시: caller 파일을 Read로 즉시 열어 영향 검증.
  - 영향 받으면 같은 task에서 함께 수정.
  - 영향 없으면 commit 메시지에 "영향 없음 확인" 명시.

### V-5. Spec Compliance Review (subagent 필수)

Task Type에 따라 다른 흐름:

**Type B**: `spec-prefilter` (Haiku) 먼저 호출.
- PASS → V-5 완료, V-6 진행 (Sonnet 호출 안 함).
- ESCALATE → 아래 Type C/D 흐름.

**Type C/D 또는 B에서 ESCALATE**: `spec-compliance-reviewer` (Sonnet) 호출.
- 전달: task ID, plan.md 해당 섹션, BASE_SHA, HEAD_SHA.
- BLOCKER/MAJOR → Phase I로 복귀, 수정 후 재호출.
- MINOR → follow-up 등록 후 다음 단계.
- OK → V-6 진행.

### V-6. Code Quality Review (subagent, Type C/D)
- `code-quality-reviewer` subagent 호출. 자체 검토 금지.
- 검토 기준: DDD, 환각, 한글 주석, 1500라인, UTF-8, 보안, 동시성.
- 결과 처리: V-5와 동일.

### V-7. Caller Re-verification

변경된 모든 public/internal 심볼에 대해:
- `grep -rn "\b<symbol>\b"` 실행.
- hit 위치가 모두 diff에 포함되어 있거나, 변경 영향 없음이 명백한가.
- 누락 발견 → Phase I 복귀.

빌드가 통과해도 잡는 cross-file 마지막 관문.

**Type B + prefilter PASS 시 축소**: 변경 심볼이 trivial하므로 변경한 심볼에 대한 grep 1회만 수행 (전체 심볼 재추적 생략). impact-warn hook(V-4)이 이미 자동 검출했으므로 중복을 줄인다.

### V-8. Self-Honesty Check

Phase D 진입 직전 자기 정직성 검증. 모두 "예"여야 진행 가능:

- [ ] 빌드 명령을 실제로 실행했고 exit 0을 봤는가?
- [ ] 테스트 명령을 실제로 실행했고 통과 수를 봤는가?
- [ ] acceptance 각 항목에 대해 diff 어디서 충족되는지 지목할 수 있는가?
- [ ] 변경한 심볼의 caller가 모두 함께 갱신되었는가?
- [ ] "동작 확인됨" 주장의 근거가 빌드 통과 외에 있는가?
- [ ] 이 task에서 추측으로 작성한 코드가 하나도 없는가?

하나라도 "아니오" → Phase I 복귀.

**자기기만 패턴**: "아마 동작할 것이다", "테스트는 안 돌렸지만 빌드 통과했으니 OK", "비슷한 코드를 본 적 있어서 맞을 것" → Phase I 즉시 복귀.

### 재시도 한계
- 같은 task에서 동일 BLOCKER 3회 연속 → Halt.
- 상세 복구 절차는 `references/recovery.md` 참조.

## Phase D — Done

```bash
git add -A
git commit -m "T<N>: <한 줄 요약>

<변경 요약>
Type: <A/B/C/D>
Build: <명령> → OK
Tests: <X/Y passed>
Review: spec OK (prefilter: <PASS/ESCALATE→OK>), quality <OK/SKIPPED>
Caller-recheck: <확인한 심볼 수>개 심볼, 누락 0
Self-honesty: PASS
Elapsed: <Hm Ms> | Turn ~<N>
"
```

진행 보고 (각 task 1줄, 사용자 확인 요청 금지):
```
✅ T<N> 완료 (<N>/<TOTAL>)  →  T<N+1> 시작
   Type: <A/B/C/D> | Tests: <X/Y> | Phase V: <적용 단계 요약>
   Elapsed (cumulative): <Hm Ms> | Turn ~<N>
```

이 보고는 **알림**이지 **확인 요청이 아니다**. 사용자 응답을 기다리지 말고 즉시 T<N+1>의 Phase P를 시작한다.

### Progress Log 갱신 (2 task마다 또는 큰 task 후)

장시간 작업의 컨텍스트 누적 대비. plan.md의 `## Progress Log`에 기록:

```markdown
## Progress Log
- T1-T2 완료 (커밋 abc123, def456): SettingsViewModel + Page 바인딩 추가. 빌드/테스트 OK.
- T3-T4 완료 (커밋 ghi789, jkl012): ThemeService 추가 + App.xaml 적용. 회귀 없음.
```

이후 task는 전체 대화 history 대신 이 Progress Log + git log를 참조한다.
이렇게 하면 컨텍스트가 압축(auto-compact)되어도 plan.md에 진행 상황이 남아 복구가 쉽다.

### Next Steps 갱신 (압축 대비 체크포인트 + 최종 보고 시)

컨텍스트 과밀 시 압축 대비 체크포인트(절대 규칙 4), Halt 보고, 그리고 Phase F 통과 최종 보고 시 plan.md의 `## Next Steps`에 다음을 기록:

```markdown
## Next Steps
- 권장 다음 액션: <명확한 한 줄> (예: T7부터 implement-task 재개 / PR 생성 후 /code-review 호출)
- Suggested skills: <쉼표 구분> (예: pjc:implement-task, 공식 /code-review, 공식 /security-review)
- 위키 갱신 (llm-wiki 사용 중이고 이 프로젝트가 등록돼 있을 때만): 이번 작업으로 기능·구현·동작이 바뀌었으면 `pjc:llm-wiki` 절차 B(ingest)로 위키 반영을 제안 (선택). 구현 세션은 위키를 직접 수정하지 않으므로 별도 위키 세션에서 진행.
```

목적: ① 압축 직후의 Claude 자신이 plan.md만 읽고 정확히 재개할 수 있게 함 (압축 생존의 핵심), ② Halt·완료 시 종철님이 plan.md만 보고도 무엇을 호출할지 즉시 알 수 있게 함. handoff 패턴 차용.

### 🚫 금지 표현

- "T2 진행할까요?"
- "다음 작업으로 넘어가도 될까요?"
- "이대로 진행해도 괜찮을까요?"
- "T1 완료. 계속할까요?"
- "확인 부탁드립니다."
- "Phase 2 진행할까요?" / "다음 단계로 넘어갈까요?" / "2단계 시작할까요?" / "Step 2 진행할까요?"

→ 대신 "✅ T1 완료 (1/10) → T2 시작" 후 **즉시** T2 진행.

## Phase F — Finalize (모든 task 완료 후)

전체 plan 통합 검증. **상세 절차는 `references/phase-f-detail.md` 참조.**

### Phase F 조건부 진입

| Plan 구성 | Phase F |
|---|---|
| 1 task + Type A만 | **생략** |
| 1 task + Type B | F-1, F-2, F-6만 |
| 2+ tasks 또는 Type C/D 포함 | **전체 (F-1~F-7)** |

F-7은 `plan-completion-reviewer` subagent (Opus) 호출 — plan 전체 적대적 검토.

## Phase G — 요구 재검증 (PRD 있을 때만)

**진입 조건**: plan.md 상단의 `**PRD**: <경로>` 줄이 있으면 그 경로의 PRD로 진입. 줄이 없어도 `docs/prd.md` 또는 `docs/prds/`에 이 작업의 PRD가 존재하면 진입. 둘 다 없으면 이 Phase는 존재하지 않는다 (Phase F가 최종).

Phase F는 "plan.md에 적힌 것"을 검증한다. Phase G는 한 단계 위 — **"plan.md가 PRD 요구를 빠뜨리지 않았는가"** 를 검증한다.

### G-1. PRD 전수 대조

PRD의 각 FR/NFR에 대해:
1. 해당 요구를 구현한 task와 commit이 존재하는가? (plan.md task의 FR 역참조 + git log)
2. **검증 방법을 기계 검증 가능 여부로 구분하여 처리한다:**
   - **기계 검증 가능** (테스트·CLI 실행·파일 확인·grep): 실제 실행하고 출력을 근거로 기록.
   - **기계 검증 불가** (GUI 조작, 시각 확인, 사용자 체감): **절대 "확인했다"고 적지 않는다.** 대신 ⏳ `HUMAN-VERIFY`로 표기하고, 가능한 간접 근거(관련 단위 테스트 통과, 바인딩 코드 존재 지목)만 기록한다. GUI 동작을 실행해 보지 않고 "표시 확인됨"이라 쓰는 것은 환각이다.
3. 결과를 표로 기록:

```markdown
| PRD ID | 우선순위 | 충족 | 근거 |
|--------|---------|------|------|
| FR-1 | Must | ✅ | T2 (commit abc123), MemoServiceTests 5/5 통과 |
| FR-2 | Must | ⏳ HUMAN-VERIFY | 자동저장 단위테스트 통과, 단 실제 UI 체감은 사용자 확인 필요 |
| FR-3 | Should | ❌ | 매칭 task 없음 — plan에서 누락 |
```

- `HUMAN-VERIFY` 항목은 미충족(❌)이 아니다 — 기계로 가능한 검증은 모두 통과했고 사람 확인만 남은 상태. 최종 보고의 "사용자 확인 필요" 목록으로 모아 제시한다.
- `HUMAN-VERIFY`를 ✅로 둔갑시키는 것은 V-8 자기기만 패턴과 동일한 위반이다.

### G-2. 갭 처리 — 자율 재루프

미충족 항목 발견 시:

| 우선순위 | 처리 |
|---|---|
| **Must 미충족** | plan.md에 새 task 추가 (`T<N+1> (FR-x 충족)`) → **Phase P부터 자율 재진입** (사용자 확인 불필요 — PRD가 이미 승인된 요구이므로) |
| Should 미충족 | 사용자에게 보고: "지금 진행 A / follow-up B" 선택 |
| Could 미충족 | follow-up 등록만, 재루프 없음 |
| **요구 자체가 바뀌어야 함** (FR이 현실과 안 맞거나 변경 필요) | plan/코드를 임의로 바꾸지 않는다. **사용자에게 PRD 변경 제안 → 승인 → PRD 갱신 → plan 조정** 순서. PRD를 두고 구현만 어긋나게 바꾸는 것은 금지 |

새 task도 동일한 P→I→V→D 루프 + 해당 task 완료 후 G-1 재대조.

### G-3. 종료 조건 (무한 루프 방지)

- **Phase G 재루프는 최대 2회.** 2회 후에도 Must 미충족이 남으면 Halt — 아래 형식으로 보고하고 사용자 지시를 기다린다. **그냥 끝내거나 완료 선언하지 않는다.**
- 같은 FR이 2회 연속 미충족이면 즉시 Halt (구현 접근 자체가 잘못됐을 가능성 — 재시도는 헛돎).
- PRD 범위를 벗어나는 새 요구 발견은 추가하지 않는다 (Out of Scope 가드). follow-up으로만 기록.

#### 한도 도달 Halt 보고 형식 (의무)

```markdown
## ⚠️ Phase G 재루프 한도 도달 (2회)

**충족**: <FR-1 ✅, FR-2 ✅, ...>
**미충족 (Must)**: <FR-x — 한 줄 설명>

**시도 이력** (같은 실패 반복 방지용 — plan.md에도 기록)
- 1차: <접근> → <실패 양상>
- 2차: <다른 접근> → <실패 양상>

**원인 분석**: <왜 안 됐는지 — 추정이면 추정이라고 명시>

선택해 주세요:
A) 다른 접근으로 1회 더 시도 (제안: <구체적 새 접근>)
B) <FR-x>를 follow-up으로 미루고 현재 상태로 완료 처리
C) <FR-x> 요구 자체를 조정 (예: <현실적 대안>)
D) 직접 지침 제공
```

- 시도 이력은 plan.md의 Progress Log에도 기록한다 — 새 세션에서 같은 접근을 반복하지 않도록.
- A 선택 시 사용자가 승인한 새 접근으로 1회만 추가 시도. 또 실패하면 재차 이 보고로 복귀 (자동 재시도 없음).

### G-4. 최종 보고에 PRD 충족표 포함

Phase G 통과 시 최종 보고에 G-1 표 전체 + Must 충족률 100% 명시.

### 최종 보고 (Phase F 통과 후 — PRD 있으면 Phase G까지 통과 후)

```markdown
## 🎉 모든 task 완료 + Phase F 통과 (+ Phase G 통과, PRD 있을 때)

**Plan**: <plan.md 경로>
**Tasks**: <N>/<TOTAL> 완료

**Summary of changes**
- T1 (Type <A/B/C/D>): <한 줄>
- ...

**Phase F 결과**
- F-2 전체 빌드: OK
- F-2 전체 테스트: <X/Y passed>
- F-7 plan-completion-reviewer: OK (또는 MINOR n개 follow-up 등록)

**Phase G 결과 (PRD 있을 때만 — G-1 충족표 전체 포함)**
- Must: <n>/<n> 충족 (기계 검증)
- 재루프: <0-2>회
- ⏳ 사용자 확인 필요 (HUMAN-VERIFY): <FR-x UI 체감, ...> ← 기계 검증 불가 항목, 직접 확인 부탁

**Execution stats**
- Elapsed (total): <Hm Ms>
- Turns: ~<N>
- Type 분포: A=<n>, B=<n>, C=<n>, D=<n>
- Prefilter PASS율 (Type B): <n/n>

**Follow-ups** (있으면)
- <항목 1>

다음 단계를 안내해 주세요 (PR 생성, 추가 검증, 머지 등).
```

## 참조 문서

- 중단 조건 + 보고 양식: `references/halt-conditions.md`
- 복구 메커니즘: `references/recovery.md`
- 안티패턴 표: `references/antipatterns.md`
- Phase F 상세: `references/phase-f-detail.md`
