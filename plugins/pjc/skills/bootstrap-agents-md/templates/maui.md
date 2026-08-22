# AGENTS.md — Agent Guide (.NET MAUI)

> .NET MAUI(멀티플랫폼) 프로젝트용 가이드. 단일 코드베이스로 Android·iOS·macOS(Mac Catalyst)·Windows를 빌드한다. Claude Code의 모든 작업은 이 문서를 우선 따른다.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·타깃 플랫폼·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.

## 위키

- **프로젝트 페이지**: `20_projects/<personal|work>/<프로젝트명>.md` (LLM WIKI vault)
- 프로젝트 성격·기술 스택·디렉터리 구조·**아키텍처 상세**·기능 목록은 **위키가 정본**이다. 이 파일에 중복 기재하지 않는다 (단 `## Conventions`의 **아키텍처 선언 1줄**은 여기 남는다 — "어디에 코드를 둘지"는 매 변경마다 필요하고 `pjc:add-domain-service`가 그것을 레이어 판정 근거로 쓴다).
- 위키에 등록되면 이 경로가 채워진다(등록은 `pjc:plan-feature` Step 1 소관).

## Build & Test
- **타깃 프레임워크(TFM)**: `<TODO: net8.0-android;net8.0-ios;net8.0-maccatalyst;net8.0-windows10.0.19041.0 중 사용하는 것>`
- **Build (단일 TFM 권장)**: `dotnet build -f <TFM>` (예: `dotnet build -f net8.0-windows10.0.19041.0`)
- **Build (전체)**: `dotnet build` (csproj의 모든 TargetFrameworks)
- **실행**: `dotnet build -t:Run -f <TFM>` 또는 VS에서 디버그 타깃 선택
- **Test**: `dotnet test <솔루션 파일>` 또는 테스트 프로젝트 단일 지정 (단위 테스트는 별도 `net8.0` 프로젝트로 분리 권장 — UI 비의존 로직만. `tests/` 디렉터리 지정은 테스트 프로젝트가 2개 이상이면 MSB1011로 실패)
- **Lint/Format**: `dotnet format`

> ⚠️ MAUI 빌드는 워크로드 설치(`dotnet workload install maui`)와 플랫폼 SDK가 필요하다. 빌드 명령·TFM은 프로젝트 csproj의 `<TargetFrameworks>`를 확인해 채운다 (위 값은 추측 — 실제 값으로 교체).

## UI/UX — 시안 우선, 미제공 시 .NET MAUI 표준

**사용자가 UI/UX 시안(디자인 HTML·이미지·Figma 등)을 제공하면 시안이 기준이다.** 아래 표준 컨트롤·스타일 규칙은 시안이 정하지 않은 부분(테마·공유 스타일·접근성 등)에만 적용한다. **MAUI에 비슷한 표준 컨트롤이 있다는 이유로 시안의 레이아웃·구성 요소를 대체하지 않는다.**

시안을 제공하지 않거나 별도 디자인 요청이 없으면 **.NET MAUI 공식 컨트롤·스타일대로** 진행한다 (자체 디자인 임의 창작 금지).

### 1. 페이지는 ContentPage
```xml
<ContentPage
    xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
    xmlns:x="http://schemas.microsoft.com/winfx/2009/xaml"
    xmlns:vm="clr-namespace:<ProjectNamespace>.ViewModels"
    x:Class="<ProjectNamespace>.Views.<Name>Page"
    x:DataType="vm:<Name>ViewModel">
    <VerticalStackLayout Padding="16" Spacing="12">
        <Label Text="{Binding Title}" Style="{StaticResource Headline}" />
        <ActivityIndicator IsRunning="{Binding IsBusy}" IsVisible="{Binding IsBusy}" />
    </VerticalStackLayout>
</ContentPage>
```

### 2. 바인딩 규칙 (WinUI와 다름)
- MAUI에는 `x:Bind`가 **없다.** `{Binding}`을 쓰되 **`x:DataType`을 페이지/뷰에 지정**해 컴파일 바인딩(성능·오타 검출)을 활성화한다.
- 로딩 표시는 `ActivityIndicator` (WinUI `ProgressRing` 아님).
- 레이아웃은 `VerticalStackLayout`/`Grid`/`FlexLayout`. 코드비하인드 namespace·컨트롤은 `Microsoft.Maui.Controls`.

### 3. DI 등록 (MauiProgram)
```csharp
public static MauiApp CreateMauiApp()
{
    var builder = MauiApp.CreateBuilder();
    builder.UseMauiApp<App>();
    // .UseMauiCommunityToolkit();   // CommunityToolkit.Maui 사용 시

    // ViewModels / Pages
    builder.Services.AddTransient<<Name>ViewModel>();
    builder.Services.AddTransient<<Name>Page>();

    return builder.Build();
}
```
- ViewModel은 보통 `Transient`. 앱 전역 상태는 `Singleton` 검토.
- Page는 생성자 주입으로 ViewModel을 받는다 (`App.GetService` 같은 서비스 로케이터 지양).

### 4. 디자인 규칙
- **자체 디자인 만들지 않는다.** (시안 미제공 시) MAUI 표준 컨트롤·`Resources/Styles/`의 공유 스타일을 우선 사용.
- **하드코딩 금지.** 색·치수·문구는 `Resources/Styles/`의 `ResourceDictionary`·`StaticResource`로 분리. 다국어는 `.resx` + `IStringLocalizer` 또는 프로젝트 패턴.
- **테마(Light/Dark)는 `AppThemeBinding`으로.** 색을 직접 박지 말고 `{AppThemeBinding Light=..., Dark=...}`.
- 플랫폼별 차이는 `OnPlatform`/`OnIdiom` 또는 `Platforms/` 폴더의 핸들러로.

### 5. XAML 작성 규칙 (레이아웃 실수 방지 — 시각 확인 없이)
1. **레이아웃 컨테이너를 명시한다.** `Grid`는 `RowDefinitions`/`ColumnDefinitions` 필수. 스택은 `VerticalStackLayout`/`HorizontalStackLayout`.
2. **고정 픽셀 대신 `*`/`Auto`·`Fill`.** 다양한 화면 크기·DPI에서 깨짐 방지.
3. **`x:DataType` 지정.** 바인딩 오타·타입 불일치를 빌드에서 잡는다.
4. **리소스 키는 정의 확인 후 사용.** `{StaticResource X}`의 키 X 존재를 grep 확인 (누락 시 런타임 예외).
5. **WinUI 문법 혼입 금지.** `x:Bind`·`ProgressRing`·`Microsoft.UI.Xaml`은 MAUI에 없다.
6. **빌드로 1차 검증.** `dotnet build -f <TFM>`로 XAML 오류를 잡고 통과시킨 뒤 다음 task로. 단 레이아웃 적정성(보기 좋은가)은 빌드로 못 잡으므로 ⏳ HUMAN-VERIFY로 남기고 사용자 확인 목록에 적는다.

## Conventions
- **아키텍처**: MVVM(UI 패턴, 고정) + `<Clean/DDD | 계층형(트랜잭션 스크립트) | 기타 — 하나만 남기세요>`
  - **Clean/DDD** — UI(View/ViewModel) → Application → Domain ← Infrastructure. 도메인 규칙이 두터울 때.
  - **계층형(트랜잭션 스크립트)** — 규칙이 얇은 CRUD·조회 위주 앱에 **정당한 선택**이다. 로직이 없는데 레이어만 나누면 과한 추상화다.
  - ⚠️ **실제 구조와 다르게 적지 마세요.** 선언만 DDD면 리뷰어도 사람도 "지켜지고 있다"고 착각합니다.
- **ViewModel**: `[ObservableProperty]` / `[RelayCommand]` (CommunityToolkit.Mvvm), DI 등록 필수
- **에러 처리**: `Result<T>` 패턴 권장
- **비동기**: `async`/`await` 일관. `.Result`/`.Wait()` 금지, `async void`는 이벤트 핸들러만
- **테마/색**: `AppThemeBinding` (Light/Dark 대응). 색 하드코딩 금지
- **파일**: 단일 책임 유지(분할은 줄 수가 아니라 책임·읽기 부담으로 판정), UTF-8 (BOM 없음, `.ps1`만 BOM — Windows PowerShell 5.1 호환), 주석은 한글 ("왜"만 설명)
- **접근성**: `SemanticProperties.Description`, `SemanticProperties.HeadingLevel`

## 산출물·파일 관리
- **빌드 산출물**: `bin/` · `obj/` (플랫폼별 APK/AAB·MSIX 출력 포함, gitignore)
- **런타임 생성물**: <로그·로컬 데이터 경로 — 예: `FileSystem.AppDataDirectory`>

## 데이터 접근
- **DB/스토어**: <예: SQLite(sqlite-net / EF Core) / Preferences / 없음>
- **접속**: <연결 정보는 환경변수·secrets로 — 실제 값 금지, 환경변수 이름만>

## DO NOT
- `x:Bind`·`ProgressRing`·`Microsoft.UI.Xaml`(WinUI 전용) 사용 — MAUI는 `{Binding}`·`ActivityIndicator`·`Microsoft.Maui.Controls`
- 색·치수·문구 하드코딩 (테마 전환·다국어 깨짐 → `AppThemeBinding`·`StaticResource`·리소스)
- 서비스 로케이터(`App.GetService` 남용) — 생성자 주입 우선
- 메인 스레드 블로킹 (동기 I/O, `.Result`/`.Wait()`) — UI 멈춤
- 플랫폼 코드를 공용 코드에 직접 작성 — `Platforms/` 또는 `OnPlatform` 사용
- `bin/`, `obj/` 커밋
- 코드·문서·notes·plan 등 어떤 파일에도 실제 IP·계정·비밀번호·토큰·DB 연결문자열 기록 (환경변수 이름만 적고 값은 .env로)
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass` (백신이 공격 도구로 오인해 격리할 수 있음)

## Plan Location

```
Plan Location: <plan.md | docs/plans/>   ← 하나만 남기세요
PRD Location:  docs/prd.md (대규모 작업 시. 누적은 docs/prds/<YYYY-MM-DD>-<slug>.md)
```

- `plan.md` = 단일 파일 덮어쓰기(작은 프로젝트) / `docs/plans/` = `<YYYY-MM-DD>-<slug>.md` 날짜별 누적(히스토리 보존)
- 미설정 시 기본: `docs/plans/`가 이미 있으면 그것, 없으면 `plan.md`

## 추가 정보
- 타깃 플랫폼: <Android | iOS | macOS | Windows 중 사용하는 것>
- CommunityToolkit.Maui 버전: 새 프로젝트 생성 시점의 최신 안정 버전 고정 (와일드카드 지양)
- 배포: <APK/AAB | App Store | MSIX 등>
- 상세 가이드: https://learn.microsoft.com/dotnet/maui/get-started/first-app

> ⚠️ `pjc:add-viewmodel` skill은 WinUI 3 / WPF / MAUI 대상입니다(CommunityToolkit.Mvvm 기반 — MAUI도 ViewModel 생성에 사용 가능). 단 View 측은 WinUI와 달라 `ContentPage`·`{Binding}`(`x:Bind` 없음)·`ActivityIndicator`를 쓰므로, SKILL의 "MAUI 차이" 주석과 이 문서의 규칙을 따르세요.
