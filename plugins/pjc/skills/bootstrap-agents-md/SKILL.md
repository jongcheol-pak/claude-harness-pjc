---
name: bootstrap-agents-md
description: This skill should be used when starting work on a project that has no AGENTS.md file, to generate one. Triggered automatically by plan-feature when AGENTS.md is missing, manually with "/pjc:bootstrap-agents-md", or when the user asks to create a project agent guide - e.g. "AGENTS.md 만들어줘", "프로젝트 가이드 문서 자동으로 만들어줘", "Claude가 이 프로젝트 컨벤션을 알게 해줘". Detects project stack from marker files (.csproj, package.json, pyproject.toml, go.mod, Cargo.toml, etc.) and generates a minimal AGENTS.md from one of 9 stack templates (plus generic/multi-stack). If stack is unknown, asks the user. Do NOT trigger when an AGENTS.md or CLAUDE.md already exists, when only editing/adding a line to an existing AGENTS.md, or for writing a README.
argument-hint: "(자동)"
---

# Bootstrap AGENTS.md

프로젝트 루트에 `AGENTS.md`가 없을 때, 표식 파일을 감지하여 적절한 template으로
초기 `AGENTS.md`를 생성한다.

## 호출 흐름

| 시점 | 호출 방식 |
|---|---|
| `plan-feature` Step 1에서 AGENTS.md 부재 감지 | 자동 호출 |
| 사용자 직접 호출 | `/pjc:bootstrap-agents-md` |

생성 후 plan-feature가 그 `AGENTS.md`를 읽고 정상 진행.

## 절대 규칙

1. **사용자 확인 없이 저장 금지.** 생성한 내용을 보여주고 명시적 승인 받음.
2. **기존 AGENTS.md 덮어쓰기 금지.** 있으면 즉시 종료.
3. **빈 칸은 빈 칸으로 유지.** 모르는 정보를 추측해 채우지 않음.
4. **다중 stack 발견 시 사용자에게 선택 요청.**
5. **AGENTS.md 신규 생성은 이 스킬 절차로만.** 스킬을 발동하지 않은 직접 Write는 `require-plan-for-write` hook의 bootstrap 게이트가 차단한다 — 차단되면 정상 경로는 이 스킬을 Skill 도구로 호출하는 것이며, 게이트를 우회할 다른 쓰기 경로를 찾지 않는다.

## 실행 단계

### Step 1. 기존 AGENTS.md 확인

```powershell
(Test-Path AGENTS.md) -or (Test-Path CLAUDE.md)
```
결과가 True면(둘 중 하나라도 있으면) → 즉시 종료, plan-feature로 복귀.

### Step 2. 표식 파일 감지

다음 표 순서대로 검사 (위에서부터):

| 표식 파일 (glob) | Stack | Template 파일 |
|---|---|---|
| `*.csproj`에 `<UseWinUI>true</UseWinUI>` 포함 | WinUI 3 | `winui3.md` |
| `*.csproj`에 `<UseWPF>true</UseWPF>` 포함 (WinUI 아님) | WPF | `wpf.md` |
| `*.csproj`에 `<UseMaui>true</UseMaui>` 포함 (WinUI/WPF 아님) | MAUI | `maui.md` |
| `*.csproj`, `*.sln`, `*.slnx`, `*.fsproj` (WinUI/WPF/MAUI 아님) | .NET | `dotnet.md` |
| `AndroidManifest.xml` **또는** `build.gradle*`에 `com.android.application/library` 플러그인 | Android | `android.md` |
| `build.gradle*`/`settings.gradle*`만 (위 Android 표식 없음 — Spring Boot·JVM 라이브러리 등) | JVM (Gradle) | Case B → `generic.md` |
| `package.json` + `tsconfig.json` 또는 `*.ts` 파일 | Node/TypeScript | `node-typescript.md` |
| `package.json` (TS 없음) | Node/JavaScript | `node-typescript.md` (라벨만 변경) |
| `pyproject.toml`, `setup.py`, `requirements*.txt` | Python | `python.md` |
| `go.mod` | Go | `go.md` |
| `Cargo.toml` | Rust | `rust.md` |
| `pubspec.yaml` / `Package.swift` / `Gemfile` / `mix.exs` / `build.zig` / `pom.xml` | Flutter / Swift / Ruby / Elixir / Zig / Java(Maven) | Case B → `generic.md` |

> Gradle 파일만으로는 Android로 판정하지 않는다 — `AndroidManifest.xml`이나 `com.android.*` 플러그인이 없는 순수 JVM Gradle 프로젝트(Spring Boot 등)를 `android.md`로 오탐하는 것을 막기 위함. Case B 표식(마지막 두 행)도 Step 2에서 함께 탐색해야 Case B 분기가 실제로 작동한다.

**.NET UI 프레임워크 우선 판정**: `.csproj`가 있으면 그 안의 UI 플래그를 먼저 확인한다. `<UseWinUI>true</UseWinUI>`면 `winui3.md`, `<UseWPF>true</UseWPF>`(WinUI 아님)면 `wpf.md`, `<UseMaui>true</UseMaui>`(WinUI/WPF 아님)면 `maui.md`, 셋 다 없으면 `dotnet.md`. WinUI 3가 WPF보다 우선(WinUI 프로젝트도 드물게 UseWPF가 보일 수 있음).

검색 명령 (PowerShell):
```powershell
# 의존성·산출물 디렉터리 제외 — 하위 node_modules의 package.json 등이 stack으로 오탐되는 것 방지
$excludeDirs = '\\(node_modules|bin|obj|\.git|target|build|dist|out|\.venv|__pycache__|Pods|vendor)\\'
# -Recurse -Depth 3: 표식이 루트가 아닌 하위(src/, 모듈 폴더 등)에 있어도 감지 (깊이 3 상한)
function Find-Marker([string[]]$patterns) {
    foreach ($p in $patterns) {
        $hit = Get-ChildItem -Filter $p -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch $excludeDirs } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

# [ordered]: 표 순서 보장 (@{}는 키 순서 비보장 — "표 순서대로 검사"가 실제로 지켜지게)
$markers = [ordered]@{
    'dotnet'          = @('*.csproj', '*.sln', '*.slnx', '*.fsproj')
    'android'         = @('AndroidManifest.xml')   # Gradle 파일만으로는 Android 판정 금지 (아래 gradle-jvm 정제 참조)
    'gradle-jvm'      = @('build.gradle', 'build.gradle.kts', 'settings.gradle', 'settings.gradle.kts')
    'node-typescript' = @('package.json', 'tsconfig.json')
    'python'          = @('pyproject.toml', 'setup.py', 'requirements*.txt')
    'go'              = @('go.mod')
    'rust'            = @('Cargo.toml')
    # ↓ template 없는 기지 표식 — 발견 시 Case B로 라우팅
    'flutter'         = @('pubspec.yaml')
    'swift'           = @('Package.swift')
    'ruby'            = @('Gemfile')
    'elixir'          = @('mix.exs')
    'zig'             = @('build.zig')
    'java-maven'      = @('pom.xml')
}
$detected = @()
foreach ($stack in $markers.Keys) {
    if (Find-Marker $markers[$stack]) { $detected += $stack }
}

# gradle-jvm 정제: build.gradle에 com.android 플러그인이 있으면 android로 승격,
# 없으면 순수 JVM(Gradle) 프로젝트 → Case B (Spring Boot 등을 android.md로 오탐하지 않음)
if ($detected -contains 'gradle-jvm' -and $detected -notcontains 'android') {
    $gradleContent = Get-ChildItem -Include 'build.gradle','build.gradle.kts' -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -notmatch $excludeDirs } |
                     Get-Content -Raw -ErrorAction SilentlyContinue
    if ($gradleContent | Select-String -Pattern 'com\.android\.(application|library)' -Quiet) {
        $detected += 'android'
    }
}
if ($detected -contains 'android') {
    $detected = @($detected | Where-Object { $_ -ne 'gradle-jvm' })
}

# WinUI 3 / WPF / MAUI 우선 판정: csproj의 UI 플래그로 dotnet → winui3/wpf/maui 승격
if ($detected -contains 'dotnet') {
    $csprojContent = Get-ChildItem -Filter '*.csproj' -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -notmatch $excludeDirs } |
                     Get-Content -Raw -ErrorAction SilentlyContinue
    $isWinUI = $csprojContent | Select-String -Pattern '<UseWinUI>\s*true\s*</UseWinUI>' -Quiet
    $isWPF   = $csprojContent | Select-String -Pattern '<UseWPF>\s*true\s*</UseWPF>' -Quiet
    $isMaui  = $csprojContent | Select-String -Pattern '<UseMaui>\s*true\s*</UseMaui>' -Quiet
    if ($isWinUI) {
        $detected = @($detected | Where-Object { $_ -ne 'dotnet' }) + 'winui3'
    } elseif ($isWPF) {
        $detected = @($detected | Where-Object { $_ -ne 'dotnet' }) + 'wpf'
    } elseif ($isMaui) {
        $detected = @($detected | Where-Object { $_ -ne 'dotnet' }) + 'maui'
    }
}
# flutter/swift/ruby/elixir/zig/java-maven/gradle-jvm 이 $detected에 있으면 → Case B로 진행
```

### Step 3. 결과 분기

#### Case A — 단일 stack 매칭됨

해당 `templates/<stack>.md` 복사 + 자동 추론 가능한 값 채움.

자동 채울 수 있는 값:
- **dotnet**: `*.sln` 파일명으로 솔루션 경로 추정
- **android**: `app/build.gradle`에서 namespace/minSdk/targetSdk 추출
- **node-typescript**: `package.json`의 `scripts` 분석 (build, test, dev, lint)
- **python**: `pyproject.toml`의 project.name, tool.pytest 설정
- **go**: `go.mod`의 module 경로
- **rust**: `Cargo.toml`의 package.name, edition

#### Case B — 표식 알지만 template 없음

예: `pubspec.yaml` (Flutter), `Package.swift` (Swift), `Gemfile` (Ruby), `mix.exs` (Elixir), `pom.xml` (Java/Maven), Android 표식 없는 `build.gradle*` (JVM/Gradle)

→ `templates/generic.md`로 복사 + 다음 정보로 채움:
- Stack: <감지된 라벨>
- Build/Test: 알려진 추측치 (있으면, 주석으로 "추측"임 표시)

추측치 매핑 (확신 없음 표시):
```
pubspec.yaml → "Flutter | flutter build / flutter test (추측)"
Package.swift → "Swift | swift build / swift test (추측)"
Gemfile      → "Ruby | bundle install / bundle exec rspec (추측)"
mix.exs      → "Elixir | mix compile / mix test (추측)"
build.zig    → "Zig | zig build / zig build test (추측)"
pom.xml      → "Java (Maven) | mvn compile / mvn test (추측)"
build.gradle* (Android 아님) → "JVM Java/Kotlin (Gradle) | gradlew build / gradlew test (추측)"
```

#### Case C — 표식조차 없음

`generic.md` 복사. 모든 값 빈 칸. 사용자에게 4가지 질문:

```
프로젝트의 stack을 자동 감지하지 못했습니다.

발견된 주요 파일:
- <Get-ChildItem 결과 상위 10개>

다음 4가지만 알려주세요:
1. 언어/플랫폼은? (예: Flutter, Swift, Ruby, Elixir, Zig, ...)
2. Build 명령은? (예: zig build)
3. Test 명령은? (예: zig build test)
4. 아키텍처/디렉터리 구조 간단히
```

답변을 받아 `generic.md`에 채움.

#### Case D — 다중 stack 발견 (모노레포)

```
이 프로젝트에서 여러 stack을 발견했습니다:
- .NET (src/Backend/Backend.csproj)
- Node.js (frontend/package.json)
- Python (scripts/pyproject.toml)

어떤 작업을 주로 하실 건가요?
A) .NET 위주 → dotnet 명령 기본
B) Node.js 위주 → npm 명령 기본
C) Python 위주 → pytest 등 기본
D) 모두 → AGENTS.md에 3개 섹션 (큰 파일)
```

D 선택 시 `multi-stack-example.md`를 참고하여 3개 섹션 모두 작성.

### Step 4. 생성된 AGENTS.md 사용자에게 보여주기

```markdown
다음 AGENTS.md를 생성했습니다. 검토하세요:

---
<생성된 내용 전체>
---

이대로 저장할까요?
[Y] 그대로 저장
[E] 편집 후 저장 (어디를 수정할지 알려주세요)
[N] 취소
```

### Step 5. 저장 + plan-feature로 복귀

`Y` → `./AGENTS.md`에 저장 → "AGENTS.md 생성 완료" 보고 → plan-feature 계속.
`E` → 사용자 수정 사항 반영 → 다시 보여주기.
`N` → 종료. plan-feature는 추측 모드로 진행 (또는 사용자가 plan-feature 재호출).

## 출력 형식

```markdown
## 🔧 bootstrap-agents-md

**감지 결과**: <stack>
**Template 사용**: <template 파일명>
**자동 채움**:
- Build 명령: <값>
- Test 명령: <값>
- 아키텍처: <값>
**비워둔 항목** (사용자 입력 필요):
- <항목 1>
- <항목 2>

<생성된 AGENTS.md 전체 미리보기>

저장하시겠습니까? [Y/E/N]
```

## 행동 원칙

- **추측은 명시.** 확신 없는 값은 "(추측)" 또는 "<TODO>" 표시.
- **사용자 시간 절약.** 자동으로 채울 수 있는 건 모두 채움.
- **빈 칸 유지가 추측 채움보다 안전.** 사용자가 채우게 함.
- **간결.** 사용자에게 보여주는 메시지는 핵심만.

## Template 위치

이 스킬 번들의 `templates/` 디렉터리 (`${CLAUDE_PLUGIN_ROOT}/skills/bootstrap-agents-md/templates/`):
- `winui3.md` — WinUI 3 (Windows App SDK). 프로젝트 생성/실행 실패 방지 규칙 + Gallery 디자인 + 다국어 규칙 포함
- `wpf.md` — WPF + WPF-UI(Fluent). 패키지 설치·App.xaml 병합·FluentWindow·테마 규칙 포함
- `maui.md` — .NET MAUI (멀티플랫폼). ContentPage·Shell·CommunityToolkit.Mvvm/Maui·MauiProgram DI 규칙 포함
- `dotnet.md` — 일반 .NET (WinUI/WPF/MAUI 아님)
- `android.md`
- `node-typescript.md`
- `python.md`
- `go.md`
- `rust.md`
- `generic.md` — 매칭 실패 또는 알려지지 않은 stack용
- `multi-stack-example.md` — 모노레포 참고용
