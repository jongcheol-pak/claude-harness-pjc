# claude-harness-pjc

> Windows + PowerShell 환경에서 Claude Code의 작업 흐름을 강제·검증하는 plugin

Claude Code가 "계획 없이 추측하고 a 파일 수정하면서 b·c 파일을 빠뜨리고 검증 없이 완료 선언"하는 것을 막기 위한 도구입니다. 모든 코드 변경은 **계획 → 구현 → 다층 검증 → 완료**의 자율 루프를 거칩니다.

## 무엇을 해결하나요

| 문제 | 해결 |
|---|---|
| 추측 코드, 환각 메서드 호출 | plan-feature가 코드 변경 전 영향 범위 전수 조사 + plan-reviewer 적대적 검증 |
| a 파일 수정하고 b·c 파일 빠뜨림 | impact-warn hook이 모든 Write 후 caller 자동 검출 + V-7 grep 재검증 |
| "잘 동작할 것 같음"으로 완료 선언 | 빌드/테스트 + 2단계 subagent 리뷰 + 자기정직성 검사 후에만 완료 |
| 검토 결과를 자체 판단으로 묵살 | spec-compliance/code-quality subagent의 BLOCKER가 0이 될 때까지 반복 |
| task 사이 "다음 진행할까요?" | 자율 루프 — plan 승인 1회 후 모든 task 끝까지 자동 진행 |
| 짧은 수정에도 plan + 검증 강제 | Trivial Bypass — UI 문구·아이콘·오타 수정은 plan 없이 직접 처리 |
| 매번 빌드/테스트 명령 모름 | bootstrap-agents-md skill이 stack 자동 감지 + AGENTS.md 생성 |

## 빠른 시작

### 1. 사전 요구사항

- Windows 10/11 + PowerShell 5.1 이상
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) v2.0 이상 (`claude --version`으로 확인)
- Git (실제 코드 작업 시)

### 2. 설치

**방법 A — GitHub (권장)**: Claude Code가 repo를 clone해 캐시하므로 로컬 폴더가 불필요합니다.

```powershell
# 저장소를 GitHub에 올린 뒤 (private 가능):
claude plugin marketplace add <user>/claude-harness-pjc
claude plugin install pjc@pjc-harness
claude plugin enable pjc@pjc-harness

# Claude Code 시작
claude
```

**방법 B — 로컬 (개발/수정용)**: 압축 해제 폴더가 plugin 본체로 참조됩니다.
⚠️ 설치 후 폴더를 삭제·이동·이름변경하면 plugin이 깨집니다 — 고정 경로에 두세요.

```powershell
Expand-Archive claude-harness-pjc.zip -DestinationPath C:\Tools\
C:\Tools\claude-harness-pjc\install.ps1
claude
```

설치 확인:
```
/plugin list   # pjc 표시되어야 함
```

정밀 검증 (선택):
```powershell
C:\Tools\claude-harness-pjc\validate.ps1
```

### 3. AGENTS.md 준비

처음 사용하는 프로젝트에서 plugin이 자동으로 묻습니다. 또는 수동:

```powershell
# 프로젝트 루트로 이동 후
claude
> /pjc:bootstrap-agents-md
```

자동으로 stack (`.NET`, `Android`, `Node/TS`, `Python`, `Go`, `Rust` 등) 감지 → `AGENTS.md` 생성.

알려지지 않은 stack은 사용자에게 4가지 질문 (언어, build, test, 아키텍처).

### 4. (선택) 권한 설정으로 승인 줄이기

매번 빌드/테스트/git 명령에 승인을 묻는 게 번거롭다면, `~/.claude/settings.json`(전역) 또는 프로젝트의 `.claude/settings.json`에 권한 규칙을 추가하세요. (plugin 자체는 권한을 설정하지 않습니다 — Claude Code가 plugin의 settings는 `agent` 키만 인식하기 때문입니다.)

stack에 맞는 예시를 복사:

```jsonc
{
  "permissions": {
    "allow": [
      "Read", "Glob", "Grep",
      "Bash(git status)", "Bash(git diff:*)", "Bash(git log:*)",
      "Bash(git add:*)", "Bash(git commit:*)", "Bash(git checkout:*)",
      "Bash(git branch:*)", "Bash(git stash:*)", "Bash(git rev-parse:*)",

      // .NET
      "Bash(dotnet build:*)", "Bash(dotnet test:*)", "Bash(dotnet format:*)",
      // Android
      "Bash(./gradlew assembleDebug)", "Bash(./gradlew test)", "Bash(./gradlew lint)",
      // Node/TS
      "Bash(npm run build)", "Bash(npm test)", "Bash(npm run lint)",
      // Python
      "Bash(pytest:*)", "Bash(ruff:*)",
      // Go
      "Bash(go build:*)", "Bash(go test:*)", "Bash(go vet:*)",
      // Rust
      "Bash(cargo build:*)", "Bash(cargo test:*)", "Bash(cargo clippy:*)"
    ],
    "ask": [
      "Bash(git push:*)", "Bash(git merge:*)",
      "Write", "Edit"
    ],
    "deny": [
      "Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)",
      "Read(./**/*.pem)", "Read(./**/*.key)",
      "Bash(git push --force:*)", "Bash(git push -f:*)",
      "Bash(git filter-branch:*)"
    ]
  }
}
```

> 안전성은 권한 설정과 별개로 `block-destructive` hook이 항상 보장합니다 (force push, `rm -rf /` 등 차단). 위 설정은 **편의를 위한 것**이며 필수는 아닙니다.

본인이 쓰는 stack 줄만 남기고 나머지는 지워도 됩니다.

### 5. 첫 사용

```
claude
> 사용자 설정 화면을 추가하고 싶어
```

흐름:
1. `plan-feature` 자동 트리거 → 계획 작성 + plan-reviewer 검증 → 사용자 승인
2. `implement-task` 자동 진행 → task별 P/I/V/D 루프 → 모든 task 자동 완료
3. Phase F 통합 검증 → 최종 보고

## 주요 기능

### 6개 Skills

| Skill | 트리거 | 역할 |
|---|---|---|
| `pjc:plan-feature` | "기능 추가", "리팩토링", "구현" 등 | 코드 변경 전 계획 수립 + 적대적 검증 |
| `pjc:implement-task` | plan 승인 후 자동 | 자율 루프 — 모든 task를 사용자 개입 없이 완료 |
| `pjc:systematic-debugging` | "디버깅", "버그", "에러" 등 | 4-phase 근본 원인 분석 |
| `pjc:add-viewmodel` | "ViewModel 추가" (WinUI/WPF/MAUI만) | MVVM boilerplate 생성 |
| `pjc:add-domain-service` | "도메인 서비스", "use case" | DDD 서비스 추가 |
| `pjc:harness-toggle` | "hook 꺼", "harness 상태" | hook 런타임 on/off |
| `pjc:bootstrap-agents-md` | AGENTS.md 부재 시 자동 | stack 자동 감지 → AGENTS.md 생성 |

### 6개 Subagents (적대적 검증)

| Subagent | 모델 | 시점 | 역할 |
|---|---|---|---|
| `plan-reviewer` | Opus | plan 작성 후 | 11개 항목으로 plan 적대적 검토 (BLOCKER 0까지) |
| `spec-prefilter` | Haiku | Type B task의 V-5 | 빠른 1차 필터 (Sonnet 호출 회피) |
| `spec-compliance-reviewer` | Sonnet | 각 task V-5 | acceptance, 범위, cross-file 영향 검증 |
| `code-quality-reviewer` | Sonnet | 각 task V-6 | DDD, 환각, 위생, 보안, 동시성 |
| `plan-completion-reviewer` | Opus | Phase F-7 | plan 전체 적대적 통합 검증 |
| `explorer` | Haiku | plan-feature 컨텍스트 수집 | 메인 컨텍스트 보호용 빠른 탐색 |

### 6개 Hooks (자동 안전망)

| Hook | 이벤트 | 동작 |
|---|---|---|
| `block-destructive` | PreToolUse Bash | `rm -rf /`, `git push --force` 등 차단 (토글 불가) |
| `require-plan-for-write` | PreToolUse Write/Edit | plan.md 없이 코드 파일 작성 차단 (문서·이미지·리소스 예외) |
| `check-utf8-and-lines` | PostToolUse | UTF-8 BOM, 1500라인, 한글 주석 검사 |
| `impact-warn` | PostToolUse | public 심볼 변경 시 caller 자동 grep → 경고 |
| `require-evidence` | Stop | 증거 없는 완료 선언 경고 |
| `backup-on-compact` | PreCompact | 컨텍스트 압축 직전 plan.md 스냅샷 백업 |

## 동작 방식

### 자율 루프 구조

```
사용자 요청
    ↓
[plan-feature] USER-INTERACTIVE
  - 컨텍스트 수집 (AGENTS.md 없으면 bootstrap 자동)
  - 영향 범위 grep 전수 조사
  - Task 분해 + Type 분류 (A/B/C/D)
  - plan-reviewer 적대적 검증
  - 사용자 승인 1회 ✋
    ↓
[implement-task] FULLY AUTONOMOUS — 끝까지 사용자 개입 없음
  반복 (T1, T2, ..., Tn):
    Phase P: caller 사전 추적
    Phase I: 최소 변경 구현
    Phase V: Type별 fast-path 검증 (V-1 ~ V-8)
    Phase D: commit + 즉시 다음 task
    ↓
[Phase F] plan 전체 통합 검증 (조건부)
  - 전체 빌드 + 전체 테스트
  - plan-completion-reviewer 적대적 검토
    ↓
최종 보고 ✋
```

### Task Type 4단계 (검증 fast-path)

| Type | 정의 | 검증 단계 |
|---|---|---|
| **A** Doc/Config | `.md`, `.json` 등 코드 외 | V-1(필요 시) + V-8 |
| **B** Trivial Code | 단일 파일·단일 메서드·caller 없음 | V-1, V-2, V-5(Haiku prefilter), V-7, V-8 |
| **C** Normal Code | 2-3 파일, caller 갱신 있음 | V-1~V-3, V-5(Sonnet), V-7, V-8 |
| **D** Complex/Cross-cutting | 다중 파일, 시그니처 변경 | V-1 ~ V-8 전체 |

작은 변경은 빠르게, 큰 변경은 철저하게.

### Trivial Bypass (1분 작업 가속)

다음 케이스는 plan-feature를 호출하지 않고 직접 처리:

- UI 문구·라벨 변경 ("확인 버튼을 'OK'로")
- 아이콘·이미지 파일 교체
- 색상·치수 토큰 1-2개 변경
- README/문서 오타 수정
- 주석 추가
- 단일 라인 설정 변경 (`.editorconfig`, `.gitignore`)
- 단일 라인 리소스 변경 (`strings.xml`, `Resources.resx`)
- **작은 코드 수정** — 값·조건·문자열 변경 등 3줄 이내 (새 함수/클래스/시그니처 추가 아님)

판정 기준: 3줄 이내, 새 정의/시그니처 변경 없음, 의도 명확. 코드 파일(`.cs`, `.xaml`, `.ts` 등)이라도 이 기준을 만족하면 직접 수정합니다. `require-plan-for-write` hook이 작은 변경을 자동 통과시키고, cross-file 영향은 `impact-warn` hook이 사후 검출합니다.

## 사용 예시

### 예시 1 — 새 기능 추가

```
> 다크 모드 토글을 설정 화면에 추가해줘

[plan-feature 자동 트리거]
컨텍스트 수집 → 영향 범위 분석 → plan-reviewer 검증 → 사용자 승인

[plan.md 생성됨]
Tasks:
  T1 (Type C): SettingsViewModel에 IsDarkMode 속성 추가
  T2 (Type C): SettingsPage XAML에 ToggleSwitch 바인딩
  T3 (Type D): ThemeService 추가 (Light/Dark 전환)
  T4 (Type C): App.xaml에서 ThemeService 적용
  T5 (Type B): 단위 테스트 추가

> [승인]

[implement-task 자율 루프]
✅ T1 완료 (1/5) → T2 시작
   Type: C | Tests: 12/12 | Phase V: V-1,V-2,V-3,V-5,V-7,V-8
   Elapsed: 3m 20s | Turn ~28

✅ T2 완료 (2/5) → T3 시작
...
✅ T5 완료 (5/5)

[Phase F]
- 전체 빌드: OK
- 전체 테스트: 87/87 passed
- plan-completion-reviewer: OK

🎉 모든 task 완료
```

### 예시 2 — Trivial 작업 (plan 없이 빠르게)

```
> README 첫 문장 오타 수정해줘

[plan-feature 우회 — trivial 판정]
직접 Edit 실행 → impact-warn hook 자동 검증 → 완료

Elapsed: 8s
```

### 예시 2.5 — 대규모 작업 (PRD + 요구 재검증 루프)

```
> 메모장 앱 만들어줘

[plan-feature — 대규모 판정 → PRD 단계]
요구사항 질문 (카테고리 묶음 + 추천 ★) → docs/prd.md 작성
  FR-1 (Must): 메모 생성/편집/삭제
  FR-2 (Must): 자동 저장
  FR-3 (Should): 검색
  NFR-1 (Must): 한/영 다국어
→ PRD 사용자 승인 (이후 고정)

[plan.md 작성 — 각 task가 PRD ID 역참조]
  T1 (FR-1): 메모 도메인 모델 + Repository
  T2 (FR-1): 목록/편집 화면 ...

> [승인]

[implement-task 자율 루프] T1 → ... → Tn

[Phase F] plan.md 대비 검증 — 통과

[Phase G] PRD 대비 재검증 (PRD 있을 때만)
  FR-1 ✅  FR-2 ✅  FR-3 ❌ (plan에서 누락!)  NFR-1 ✅
  → Must/Should 갭 발견 → T(n+1) 자동 추가 → 자율 재진입
  → 재대조 → 전체 충족 → 완료
  (재루프 최대 2회 — 이후 잔여 갭은 사용자 보고)

🎉 PRD Must 100% 충족 + 충족표 보고
```

### 예시 3 — Hook 일시 끄기

```
> 일단 plan 강제 검사 꺼

[harness-toggle 트리거]
require-plan-for-write 비활성화됨.
~/.claude/.disabled/require-plan-for-write 생성됨.

> 다시 켜
require-plan-for-write 활성화됨.
```

## 주요 명령

```
# Claude Code 안에서
/plugin list                                  # pjc 활성 확인
/pjc:plan-feature <설명>                      # 명시적 plan 호출
/pjc:implement-task <T번호>                   # 특정 task 실행 (또는 'all')
/pjc:systematic-debugging <증상>              # 디버깅 모드
/pjc:bootstrap-agents-md                      # AGENTS.md 생성
/pjc:harness-toggle <hook> <on|off|status>    # hook 토글
/pjc:harness-toggle status                    # 모든 hook 상태
```

자연어로도 호출 가능: "기능 추가해줘", "버그 분석해줘", "hook 상태 보여줘" 등.

## 설치 관리

### GitHub 모드 (권장)

```powershell
# 최초 설치
claude plugin marketplace add <user>/claude-harness-pjc
claude plugin install pjc@pjc-harness
claude plugin enable pjc@pjc-harness

# 업데이트 (개발 PC에서 git push 후, 사용 PC에서)
claude plugin marketplace update pjc-harness
claude plugin update pjc@pjc-harness

# 제거
claude plugin uninstall pjc
claude plugin marketplace remove pjc-harness
```

GitHub 모드에서 install.ps1을 쓰고 싶으면 (재설치 정리 + enable + 검증 안내 일괄):
```powershell
.\install.ps1 -GitHub <user>/claude-harness-pjc
```

### 로컬 모드 (개발용)

```powershell
# 자동 재설치 (기본 동작)
C:\Tools\claude-harness-pjc\install.ps1

# 제거 / 프로젝트별 설치 / 검증
C:\Tools\claude-harness-pjc\install.ps1 -Uninstall
C:\Tools\claude-harness-pjc\install.ps1 -Scope project
C:\Tools\claude-harness-pjc\validate.ps1
```

로컬 업데이트 — **반드시 같은 경로에 내용만 교체** (경로가 바뀌면 참조가 깨짐):
```powershell
Remove-Item C:\Tools\claude-harness-pjc -Recurse -Force
Expand-Archive claude-harness-pjc.zip -DestinationPath C:\Tools\
C:\Tools\claude-harness-pjc\install.ps1
```

### 배포 워크플로 (GitHub 모드)

```powershell
# 개발 폴더에서 수정 후
git add -A
git commit -m "1.x.y: <변경 요약>"
git push
# 사용 측: claude plugin marketplace update pjc-harness && claude plugin update pjc@pjc-harness
```

## AGENTS.md 작성

`plan-feature`가 가장 먼저 읽는 프로젝트 가이드 파일입니다. 8개 template이 `AGENTS.md.templates/`에 제공됩니다:

```
AGENTS.md.templates/
├── winui3.md             (WinUI 3 / Windows App SDK — 생성·실행 실패 방지 + 디자인 + 다국어)
├── dotnet.md             (일반 .NET / C# / F#)
├── android.md            (Android / Kotlin / Java)
├── node-typescript.md    (Node.js / TypeScript / JavaScript)
├── python.md             (Python)
├── go.md                 (Go)
├── rust.md               (Rust)
├── generic.md            (그 외 모든 stack)
└── multi-stack-example.md (모노레포 참고용)
```

WinUI 3 프로젝트는 `bootstrap-agents-md`가 `<UseWinUI>true</UseWinUI>`를 감지해 `dotnet.md` 대신 `winui3.md`를 사용합니다 — `.slnx` 플랫폼 매핑, 패키지/비패키지 설정, `MainWindow` 진입점 등 "실행할 수 없습니다" 오류를 예방하는 규칙이 포함됩니다.

대부분의 경우 `bootstrap-agents-md` skill이 자동 처리합니다. 수동 작성 시 다음 4개는 필수:

1. **Build 명령** — Phase V-1 검증의 기반
2. **Test 명령** — Phase V-2 검증의 기반
3. **아키텍처** — 코드 위치 결정
4. **파일 위치 컨벤션** — task Files 정확도

## 트러블슈팅

### plugin 명령이 자동완성에 안 보임

먼저 공식 진단 명령:
```
/plugin validate            # plugin.json, frontmatter, hooks.json 검증
claude plugin validate ./claude-harness-pjc --strict   # CI/배포 전 엄격 검증
claude --debug              # plugin 로딩 상세 로그
```

또는 자체 검증:
```powershell
C:\Tools\claude-harness-pjc\validate.ps1
```

`FAIL` 항목이 있으면 재설치:
```powershell
C:\Tools\claude-harness-pjc\install.ps1
```

### 토큰 비용이 궁금할 때

plugin이 세션에 더하는 토큰을 공식 명령으로 확인:
```
claude plugin details pjc
```
always-on (매 세션 고정) + on-invoke (각 컴포넌트 호출 시) 토큰을 보여줍니다.

### Hook이 너무 자주 차단함

```
> require-plan 꺼
```

또는 환경 변수 (한 번만 우회):
```powershell
$env:CLAUDE_HARNESS_QUICK = '1'
```

### 한글 메시지가 깨짐

`validate.ps1` 실행 → `[WARN] UTF-8 BOM 없음` 항목 확인 → 해당 `.ps1` 파일에 BOM 추가.

### Claude Code REPL이 실행 중에 plugin 업데이트

REPL 종료 후 다시 시작해야 변경 반영됨.

## 여러 프로젝트 동시 작업

서로 다른 프로젝트 폴더에서 Claude Code를 동시에 실행하는 것은 안전합니다. plan.md·git·작업 파일이 폴더별로 분리되기 때문입니다.

| 자원 | 동시 실행 |
|---|---|
| plan.md, git, 작업 파일 | ✅ 폴더별 독립 |
| subagent, hook | ✅ 인스턴스별 독립 |
| hook 토글 (`~/.claude/.disabled/`) | ⚠️ 전역 공유 — 한 곳에서 끄면 모두 영향 |

같은 프로젝트를 여러 작업으로 병렬 진행하려면 git worktree 사용을 권장합니다:

```bash
git worktree add ../proj-feature-1 -b feature-1
git worktree add ../proj-feature-2 -b feature-2
# 각 worktree에서 독립된 plan.md, 독립 브랜치로 작업
```

## 공식 Claude Code 기능과의 관계

pjc는 Claude Code의 내장 기능을 대체하지 않고 보완합니다.

| 공식 기능 | pjc와의 관계 |
|---|---|
| `/code-review` (PR correctness 리뷰) | **보완** — pjc는 구현 중 plan 준수를 검증(게이트), 공식은 PR 단계에서 correctness 버그를 조언. 둘 다 쓰면 작성 중 + PR 후 이중 점검 |
| `/security-review` (보안 취약점) | **보완** — pjc는 보안 전용 스캐너가 아니므로, 보안이 중요하면 공식 명령 병행 권장 |
| Code Review GitHub App (PR 자동) | **보완** — pjc로 작성·검증 후 PR을 열면 공식 App이 클라우드 병렬 에이전트로 재점검 |

권장 워크플로:

```
pjc (작성 중)                    공식 (PR 후)
plan-feature → implement-task → [PR 생성] → /code-review 또는 Code Review App
  plan 준수 + 품질 게이트            correctness 버그 + 보안 재점검
```

pjc의 리뷰 subagent는 **plan.md 명세 준수**와 **프로젝트 규칙(DDD·한글주석 등)**에 집중하고, 공식 기능은 **correctness·보안**과 **PR 워크플로 통합**에 강합니다.

## 설계 철학

- **예측 코드 방지 > 토큰 비용 절감**: 다층 검증 비용은 재작업 비용보다 작음
- **자율성과 결정성 동시 추구**: plan 단계는 USER-INTERACTIVE, 구현 단계는 FULLY AUTONOMOUS
- **결정적 안전망**: subagent 검증은 확률적이지만 hook은 결정적
- **Type-aware 검증**: 작은 작업 빠르게, 큰 작업 철저하게

## 호환 환경

| 항목 | 지원 |
|---|---|
| OS | Windows 10/11 (PowerShell native) |
| Shell | PowerShell 5.1 / PowerShell 7+ |
| Git Bash, WSL | 미지원 (PowerShell hook 사용) |
| Claude Code | v2.0 이상 |
| 대상 언어 | .NET, Android, Node/TS, Python, Go, Rust (template 제공) + 그 외 generic |

## 라이선스

MIT
