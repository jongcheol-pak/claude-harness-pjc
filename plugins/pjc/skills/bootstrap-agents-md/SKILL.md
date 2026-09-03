---
name: bootstrap-agents-md
description: This skill should be used when starting work on a project that has no AGENTS.md file, to generate one. Triggered automatically by pjc:plan when AGENTS.md is missing, manually with "/pjc:bootstrap-agents-md", or when the user asks to create a project agent guide - e.g. "AGENTS.md 만들어줘", "프로젝트 가이드 문서 자동으로 만들어줘", "Claude가 이 프로젝트 컨벤션을 알게 해줘". 파일 이름을 대지 않고 목적만 말하는 요청도 이 스킬이다 — 빌드·실행·테스트 방법이나 프로젝트 규약을 정리한 문서를 새로 만들어 달라는 요청이 여기 해당한다. 그 경우에도 산출물은 AGENTS.md이며 README·ONBOARDING 등 다른 이름의 문서를 새로 만들지 않는다. Detects project stack from marker files (.csproj, package.json, pyproject.toml, go.mod, Cargo.toml, etc.) and generates a minimal AGENTS.md from the canonical section list in AGENTS-BOUNDARY.md. If stack is unknown, asks the user. Do NOT trigger when an AGENTS.md already exists, when only editing/adding a line to an existing AGENTS.md, or for writing a README. An existing CLAUDE.md does NOT block it — that file is Claude-only and usually gitignored, while AGENTS.md is committed and read by other agents.
argument-hint: "(자동)"
---

# Bootstrap AGENTS.md

`AGENTS.md`가 없는 프로젝트에서 표식 파일로 스택을 감지해 초기 `AGENTS.md`를 만든다. `pjc:plan` Step 1이 부재를 감지하면 자동 호출되고, 생성 후 그 스킬이 결과를 읽고 계속한다.

## 절대 규칙

1. **사용자 확인 없이 저장하지 않는다** — 생성한 내용을 보여주고 명시적 승인을 받는다.
2. **기존 `AGENTS.md`를 덮어쓰지 않는다** — 있으면 즉시 종료한다. **판정 대상은 `AGENTS.md`뿐이다**(`CLAUDE.md`가 있어도 진행한다 — 근거는 `references/bootstrap-rationale.md`).
3. **모르는 값은 빈 칸으로 둔다** — 추측해 채우지 않는다.
4. **다중 stack이면 사용자에게 고르게 한다.**
5. **`AGENTS.md` 신규 생성은 이 스킬 절차로만 한다** — 스킬을 발동하지 않은 직접 Write는 `guard-harness` hook의 AGENTS.md bootstrap 게이트가 차단한다. 차단되면 정상 경로는 이 스킬을 Skill 도구로 호출하는 것이며, 게이트를 우회할 다른 쓰기 경로를 찾지 않는다.
6. **절 구성의 정본은 `../AGENTS-BOUNDARY.md`다** — 무엇을 담고 무엇을 담지 않는지를 그 문서가 정한다. 이 스킬은 그 표를 재서술하지 않고, 아래 「생성물 골격」은 그 표에서 파생한 뼈대다.
7. **생성물에 설명을 길게 쓰지 않는다** — 서술 밀도 기준도 규칙 6이 가리키는 같은 문서의 「서술 밀도 규칙」을 따른다.

## 실행 단계

### Step 1. 기존 `AGENTS.md` 확인

`AGENTS.md`가 있으면 즉시 종료하고 `pjc:plan`으로 복귀한다(절대 규칙 2).

**`CLAUDE.md` 존재는 종료 조건이 아니다.** 다만 있으면 **먼저 읽고 중복 서술을 피한다** — 같은 사실을 두 파일에 적으면 한쪽만 갱신될 때 갈린다. 겹치는 항목은 `AGENTS.md`에 두고 `CLAUDE.md`에는 포인터만 남기도록 제안한다.

### Step 2. 표식 파일 감지

**표 순서대로** 검사한다(위에서부터).

| 표식 | Stack |
|---|---|
| `*.csproj`에 `<UseWinUI>true</UseWinUI>` | WinUI 3 |
| `*.csproj`에 `<UseWPF>true</UseWPF>` (WinUI 아님) | WPF |
| `*.csproj`에 `<UseMaui>true</UseMaui>` (WinUI/WPF 아님) | MAUI |
| `*.csproj`·`*.sln`·`*.slnx`·`*.fsproj` (위 셋 아님) | .NET |
| `AndroidManifest.xml` **또는** `build.gradle*`에 `com.android.application/library` | Android |
| `build.gradle*`·`settings.gradle*`만 (위 Android 표식 없음) | JVM (Gradle) → Case B |
| `package.json` + `tsconfig.json`/`*.ts` | Node/TypeScript |
| `package.json` (TS 없음) | Node/JavaScript |
| `pyproject.toml`·`setup.py`·`requirements*.txt` | Python |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pubspec.yaml`·`Package.swift`·`Gemfile`·`mix.exs`·`build.zig`·`pom.xml` | Flutter/Swift/Ruby/Elixir/Zig/Java(Maven) → Case B |

**감지 방법** — 표식을 **깊이 3까지** 탐색하고 `node_modules`·`bin`·`obj`·`.git`·`target`·`build`·`dist`·`out`·`.venv`·`__pycache__`·`Pods`·`vendor`를 제외한다. **Case B 행의 표식도 이 단계에서 함께 찾는다** — 안 찾으면 그 분기가 도달 불가가 된다. 위 표의 순서·조건이 곧 판정이며 그 근거는 `references/bootstrap-rationale.md` §4에 있다.

### Step 3. 결과 분기

| Case | 조건 | 처리 |
|---|---|---|
| **A** | 단일 stack 매칭 | 「생성물 골격」으로 생성 + 자동 추론값 채움 |
| **B** | 표식은 알지만 전용 추론이 없음 | 같은 골격 + 아래 추측치 매핑(「(추측)」 표시) |
| **C** | 표식조차 없음 | 같은 골격을 빈 칸으로 두고 사용자에게 4가지 질문 |
| **D** | 다중 stack (모노레포) | 사용자에게 주 stack을 묻고, 「모두」면 stack별 `## Build & Test`·`## Conventions`·`## DO NOT`를 반복 배치 |

**Case A 자동 추론값** — `*.sln` 파일명으로 솔루션 경로 · `app/build.gradle`의 namespace/minSdk/targetSdk · `package.json`의 `scripts`(build·test·dev·lint) · `pyproject.toml`의 `project.name`·pytest 설정 · `go.mod`의 module 경로 · `Cargo.toml`의 `package.name`·edition.

**Case B 추측치 매핑** (전부 「(추측)」 표시):

```
pubspec.yaml → Flutter | flutter build / flutter test
Package.swift → Swift | swift build / swift test
Gemfile      → Ruby | bundle install / bundle exec rspec
mix.exs      → Elixir | mix compile / mix test
build.zig    → Zig | zig build / zig build test
pom.xml      → Java (Maven) | mvn compile / mvn test
build.gradle* (Android 아님) → JVM (Gradle) | gradlew build / gradlew test
```

**Case C 질문 4개** — ① 언어/플랫폼 ② Build 명령 ③ Test 명령 ④ 아키텍처·디렉터리 구조.

> 감지된 stack 라벨을 **`AGENTS.md`에 절로 적지 않는다**(절대 규칙 6) — 위키 허브의 `tech_stack`이 정본이다. 라벨은 어느 추론·추측치를 쓸지 고르는 데만 쓴다.

#### Step 3-1. 아키텍처 확인 (저장 전)

**추측해서 채우지 않는다.** Step 4의 `[Y/E/N]` 미리보기에 이 질문을 함께 실어 확인한다(질문 라운드를 새로 늘리지 않는다).

1. **구조로 근거를 만든다** — 레이어 폴더(`Domain/`·`domain/`·`internal/domain/` 등)가 실재하는지 Glob으로 확인한다. 코드가 이미 있으면 그 구조가 답이다.
2. **후보를 제시하고 고르게 한다**:
   ```
   아키텍처를 확인해 주세요 (AGENTS.md의 "어디에 코드를 둘지"를 결정합니다):
   A) DDD/Clean — 도메인 규칙(검증·상태 전이·계산)이 두터움. 엔티티에 행위를 두고 애그리게이트 경계를 잡음
   B) 계층형(트랜잭션 스크립트) — 규칙이 얇은 CRUD·조회 위주. 서비스가 절차를 순서대로 실행
   C) 기타 (직접 명시)

   <감지된 구조가 있으면: "src/에 Domain/·Application/ 폴더가 보입니다 → A로 추정">
   ```
3. **답을 못 얻으면 빈 칸으로 저장한다.**

> **왜 묻는가**는 `references/bootstrap-rationale.md`에 있다.

#### Step 3-2. 위키 포인터 절 처리 (전 Case 공통, 저장 전)

이 스킬은 **위키에 등록하지 않는다** — 등록은 `pjc:plan` Step 1 소관이고, 여기서 하면 두 스킬 사이에 순서 의존이 생긴다.

1. **vault 판정**: `pjc:llm-wiki` 절차 K 1의 판정 게이트를 그대로 쓴다(`~/.claude/llm-wiki-config.json` · SessionStart 주입 라인). **확인 없이 "미설정"으로 단정하지 않는다.**
2. **vault 있음** → 절을 두고 경로는 `<프로젝트명>` placeholder로 남긴다. 이미 등록된 프로젝트면 그 허브 경로를 채운다.
3. **vault 없음** → `## 위키` 절을 **생성물에서 뺀다**(없는 곳을 가리키는 포인터는 다음 세션을 헤매게 한다). 뺀 생성물을 Step 4 미리보기에 그대로 싣고, **저장 후** 1줄 보고한다: *"위키 vault가 없어 `## 위키` 절은 넣지 않았습니다 — 등록되면 이 경로가 채워집니다(등록은 `pjc:plan` Step 1 소관)."*

### Step 4. 미리보기와 승인

```markdown
## 🔧 bootstrap-agents-md

**감지 결과**: <stack>
**자동 채움**: Build `<값>` · Test `<값>`
**확인 필요**: 아키텍처 <A/B/C — 감지된 구조가 있으면 추정 근거 1줄>
**비워둔 항목**: <항목들>

---
<생성된 AGENTS.md 전체>
---

<아키텍처가 미확정이면 여기에 Step 3-1의 A/B/C 질문을 함께 제시>

이대로 저장할까요?
[Y] 그대로 저장   [E] 편집 후 저장 (어디를 고칠지)   [N] 취소
```

`Y` → `./AGENTS.md` 저장 후 `pjc:plan` 계속 · `E` → 수정 반영 후 다시 보여준다 · `N` → 종료(`pjc:plan`은 추측 모드로 진행). **아키텍처에 답하지 않고 `[Y]`면 그 항목은 빈 칸으로 저장한다.**

## 생성물 골격

**절 구성과 각 절이 담는 것의 정본은 `../AGENTS-BOUNDARY.md`의 표다.** 아래는 그 표에서 파생한 뼈대이며, 스택이 달라도 이 구성은 같다.

```markdown
# AGENTS.md — Agent Guide

## 위키
- **프로젝트 페이지**: `20_projects/<personal|work>/<프로젝트명>.md` (LLM WIKI vault)
- 프로젝트 성격·기술 스택·디렉터리 구조·**아키텍처 상세**·기능 목록은 **위키가 정본**이다.
  이 파일에 중복 기재하지 않는다 (단 `## Conventions`의 **아키텍처 선언 1줄**은 여기 남는다).

## Build & Test
- **Build**: `<명령>`   - **Run (개발)**: `<명령>`   - **Test**: `<명령>`
- **Lint/Format**: `<있으면>`   - **Clean**: `<있으면>`
> ⚠️ Build/Test가 비면 `pjc:implement`의 검증이 무의미해진다.

<검증 매핑 표 — 변경 파일 패턴 → 필수 검증. 축이 둘 이상일 때만 만든다>

## 데이터 접근
- **DB/스토어**: <없으면 "없음">
- **접속**: <환경변수 **이름**만 — 실제 값 금지>

## 산출물·파일 관리
- **빌드 산출물** / **런타임 생성물** / **임시·캐시**: <경로만>

## Conventions
- **아키텍처**: <Step 3-1에서 확정한 1줄 — "어디에 코드를 둘지">
- **인코딩** / **줄바꿈** / **주석 언어** / **이름 규칙** / **테스트 위치** / **포맷터**

## DO NOT
- 실제 IP·계정·비밀번호·토큰·DB 연결문자열을 코드·문서·plan에 기록 (환경변수 이름만)
- 환경변수 파일(`.env*`)·secrets·인증서 커밋
- 빌드 산출물 디렉터리 커밋
- 검증 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass`
- <그 밖 stack별 금지사항>

```

- **`## Plan Location`은 그 레포가 PRD를 쓸 때만 만든다**(경로만) — plan은 루트 `plan.md` 고정이라 `Plan Location:` 선언을 두지 않는다.
- **`## Stack`·`## Repository Structure` 같은 프로젝트 정보 절을 만들지 않는다**(절대 규칙 6).
- **스택 고유의 UI·디자인·마크업 규칙을 여기 넣지 않는다** — 그것은 위키 `conventions.md` 소관이다(근거는 `references/bootstrap-rationale.md`).

## See also

- `../AGENTS-BOUNDARY.md` — 절 구성·서술 밀도의 정본
- `references/bootstrap-rationale.md` — 이 절차가 왜 이렇게 생겼는가
- `pjc:record-project-fact` — 이미 있는 `AGENTS.md`에 사실을 더한다
