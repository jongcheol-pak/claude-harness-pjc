# AGENTS.md - Agent Guide

> **이 파일은 글로벌 harness가 사용하는 프로젝트별 설정입니다.**
> 각 프로젝트의 루트에 배치하세요 (`<repo>/AGENTS.md`).
> 300줄 이내로 유지하고, 세부는 글로벌 skills와 hooks가 처리합니다.
>
> **사용법**: 아래는 두 가지 스택(A = WinUI 3 / .NET, B = Android / Kotlin)의 예시입니다.
> 본인 프로젝트에 맞는 쪽만 남기고 다른 쪽은 삭제하세요.
> 다른 스택(TypeScript, Python, Flutter 등)도 같은 형식을 따라 채우면 됩니다.

---

# A. WinUI 3 / .NET 예시

## Stack
- 언어/런타임: C# 12, .NET 8
- 주요 프레임워크: WinUI 3, Windows App SDK
- 아키텍처: MVVM + DDD
- 핵심 라이브러리: CommunityToolkit.Mvvm, Microsoft.Extensions.DependencyInjection, Serilog

## Build & Test
- **Build**: `dotnet build src/MyApp.sln -c Debug`
- **Test**: `dotnet test tests/`
- **Lint/Format**: `dotnet format`
- **Run (local)**: `dotnet run --project src/MyApp.UI`

## Repository Structure

```
<repo>/
├── src/
│   ├── MyApp.Domain         ← 도메인 (UI/Infra 의존 금지)
│   ├── MyApp.Application    ← UseCase, 오케스트레이션
│   ├── MyApp.Infrastructure ← EF Core, HttpClient, 외부 어댑터
│   └── MyApp.UI             ← Views, ViewModels (WinUI 3)
├── tests/
│   ├── MyApp.Domain.Tests
│   └── MyApp.Integration.Tests
└── docs/
    └── adr/                 ← 아키텍처 결정 기록
```

## Conventions
- 비즈니스 로직은 **Domain 레이어** (DDD).
- ViewModel은 `ObservableObject` 상속, `[ObservableProperty]` / `[RelayCommand]` 우선.
- 새 의존성은 `App.xaml.cs`의 `ConfigureServices`에 등록.
- 로깅은 Serilog. 콘솔 직접 출력 금지.
- 비동기 메서드는 `Async` 접미사. `Wait()`, `.Result` 금지.
- 파일 1500라인 내외 유지.
- 주석은 한글. "왜"를 설명.
- 파일 UTF-8 (BOM 없음), `.ps1`만 BOM.

## DO NOT
- `src/*/Generated/*` 수정 금지 (코드 생성기 산출물).
- `App.manifest` 임의 변경 금지.
- 환경 변수 파일(`.env*`, `appsettings.Production.json`) 커밋 금지.
- 비밀 정보 하드코딩 금지.
- Domain 레이어에 EF Core / HttpClient / AspNetCore 의존 추가 금지.

---

# B. Android / Kotlin 예시

## Stack
- 언어/런타임: Kotlin 2.x, JDK 17, Android Gradle Plugin 8.x
- minSdk / targetSdk: 24 / 34 (또는 프로젝트 값)
- 주요 프레임워크: Jetpack Compose, AndroidX
- 아키텍처: Clean Architecture (data/domain/presentation) + MVVM
- 핵심 라이브러리: Hilt(DI), Coroutines + Flow, Retrofit + OkHttp, Room, Coil, Timber

## Build & Test
- **Build**: `./gradlew assembleDebug`
- **Test (unit)**: `./gradlew test`
- **Test (instrumented)**: `./gradlew connectedAndroidTest` (에뮬레이터/디바이스 필요)
- **Lint**: `./gradlew lint detekt ktlintCheck`
- **Run (debug)**: `./gradlew installDebug` 후 디바이스에서 실행

## Repository Structure

```
<repo>/
├── app/                          ← Application 모듈 (DI 진입, Activity)
│   └── src/main/java/.../
├── core/
│   ├── common/                   ← 유틸, 공통 모델
│   ├── ui/                       ← 공통 Compose 컴포넌트, 테마
│   ├── data/                     ← 데이터 소스, Repository 구현
│   ├── network/                  ← Retrofit API
│   └── database/                 ← Room
├── domain/                       ← 순수 Kotlin 모듈 (Android 의존 금지)
│   ├── model/
│   ├── repository/               ← 인터페이스만
│   └── usecase/
├── feature/
│   ├── home/
│   ├── settings/
│   └── login/
└── docs/
    └── adr/                      ← 아키텍처 결정 기록
```

## Conventions
- 비즈니스 로직은 **`:domain` 모듈**에. UI/Android API 의존 금지 (`androidx.*`, `android.*` import 금지).
- UI는 **Jetpack Compose** 우선. XML View는 레거시 화면에만.
- ViewModel은 `androidx.lifecycle.ViewModel` 상속 + `@HiltViewModel`.
- 상태는 `StateFlow` / `MutableStateFlow`. `LiveData`는 신규 코드 사용 지양.
- 비동기는 **Coroutines**. `runBlocking` 프로덕션 코드 금지. `GlobalScope` 금지.
- 의존성 주입은 **Hilt**. `@Inject constructor`로 생성자 주입.
- 네트워크 결과는 `Result<T>` 또는 sealed class (`Loading/Success/Error`)로 표현.
- 로깅은 **Timber**. `Log.d` 직접 호출 금지.
- 문자열 리소스는 `strings.xml`에 정의 (하드코딩 금지). 다국어 키는 snake_case.
- 파일 1500라인 내외 유지. Composable은 한 함수당 100라인 내외 권장.
- 주석은 한글, KDoc(`/** ... */`) 사용. "왜"를 설명.
- 파일 UTF-8 (BOM 없음).

## DO NOT
- `:domain` 모듈에 `androidx.*` / `android.*` import 금지 (순수 Kotlin 유지).
- `build/`, `.gradle/`, `*.iml` 커밋 금지.
- 키스토어 파일(`*.jks`, `*.keystore`) 커밋 금지.
- `local.properties`, `google-services.json`(서명용 secrets 포함 시) 커밋 금지.
- API key, 시크릿 하드코딩 금지 (BuildConfig + gradle.properties + CI 시크릿).
- `runBlocking { }`을 프로덕션 코드에 사용 금지.
- `GlobalScope.launch` 사용 금지 (반드시 lifecycle-aware scope).
- `findViewById`를 신규 Compose 화면에 혼용하지 마세요.

---

# 공통 — 모든 스택

## Plan Location

`pjc:plan-feature`가 생성하는 `plan.md`의 위치 설정:

```
Plan Location: <plan.md | docs/plans/>
PRD Location:  docs/prd.md (대규모 작업 시)
```

| 값 | 동작 |
|---|---|
| `plan.md` | 단일 plan 파일 (덮어쓰기). 작은 프로젝트, 1회성 작업에 권장 |
| `docs/plans/` | 날짜별 누적 (`docs/plans/<YYYY-MM-DD>-<slug>.md`). 큰 프로젝트, 히스토리 보존에 권장 |

미설정 시 기본: `docs/plans/`가 이미 있으면 그것을, 없으면 `plan.md`.

## Skills & Agents (글로벌 plugin에서 자동 제공)

이 프로젝트는 글로벌 harness의 다음 워크플로를 따릅니다:

1. **계획 단계**: `pjc:plan-feature` — `plan.md` 작성
2. **구현 단계**: `pjc:implement-task` — PIV 루프 + 2단계 리뷰
3. **디버깅**: `pjc:pjc-systematic-debugging` — 4-phase 근본 원인 분석
4. **MVVM (WinUI 3 전용)**: `pjc:add-viewmodel` — Android에는 적용되지 않음
5. **DDD/Clean (양쪽 적용 가능)**: `pjc:add-domain-service` — Domain/Application 서비스 추가
6. **Hook 토글**: `pjc:harness-toggle` — 런타임 on/off

> Android의 경우 `pjc:add-viewmodel`은 WinUI 3 코드를 생성하므로 사용하지 마세요.
> Android ViewModel 추가는 `pjc:implement-task`로 직접 작성합니다.

글로벌 위치: `%USERPROFILE%\.claude\plugins\pjc-harness\plugins\pjc\skills\<name>\SKILL.md`

## Pointers (세부 문서)

- 아키텍처 결정: `docs/adr/`
- API 명세: `docs/api/`
- 코드 스타일 (.NET): `.editorconfig`
- 코드 스타일 (Android): `.editorconfig` + `detekt.yml` + `.ktlint`
- CI: `<해당 경로 (예: .github/workflows/ 또는 build.gradle.kts)>`
