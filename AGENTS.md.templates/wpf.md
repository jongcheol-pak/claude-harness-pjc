# AGENTS.md — Agent Guide (WPF + WPF-UI)

> WPF (.NET) 프로젝트용 가이드. UI는 WPF-UI(Fluent) 라이브러리를 사용한다. Claude Code의 모든 작업은 이 문서를 우선 따른다.

## Stack
- **언어**: C# / .NET <version, 예: net8.0-windows>
- **UI 프레임워크**: WPF + **WPF-UI** (NuGet `WPF-UI`, Fluent/Windows 11 스타일)
- **MVVM**: `CommunityToolkit.Mvvm` (`[ObservableProperty]`, `[RelayCommand]`)
- **DI**: `Microsoft.Extensions.DependencyInjection` / `Microsoft.Extensions.Hosting`
- **공식 가이드**: https://wpfui.lepo.co  (소스: https://github.com/lepoco/wpfui)

## Build & Test
- **Build**: `dotnet build <Project>.csproj -c Debug`
- **Test**: `dotnet test tests/`
- **Lint/Format**: `dotnet format`
- **실행**: `dotnet run --project <Project>.csproj` 또는 VS F5

## UI/UX — WPF-UI 사용 (미제공 시 공식 가이드 준수)

사용자가 UI/UX 시안을 제공하지 않거나 별도 디자인 요청이 없으면 **WPF-UI 공식 가이드(wpfui.lepo.co)대로** 진행한다 (자체 디자인 임의 창작 금지).

### 1. 패키지 설치
```powershell
dotnet add package WPF-UI
```

### 2. App.xaml에 리소스 사전 병합 (필수)
```xml
<Application ...
    xmlns:ui="http://schemas.lepo.co/wpfui/2022/xaml">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ui:ThemesDictionary Theme="Dark" />   <!-- Light | Dark -->
                <ui:ControlsDictionary />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Application.Resources>
</Application>
```

### 3. 윈도우는 FluentWindow 사용
```xml
<ui:FluentWindow ...
    xmlns:ui="http://schemas.lepo.co/wpfui/2022/xaml">
    <StackPanel>
        <ui:TitleBar Title="앱 이름"/>
        <!-- 컨트롤은 ui: 접두사 -->
    </StackPanel>
</ui:FluentWindow>
```
- App.xaml이 없는 구조면 윈도우 생성자에서 `ApplicationThemeManager.Apply(this);` 호출.
- WPF-UI 컨트롤(`ui:Button`, `ui:Card`, `ui:NavigationView`, `ui:SymbolIcon` 등)을 표준 WPF 컨트롤보다 우선 사용.
- 아이콘은 `{ui:SymbolIcon Fluent24}` 형식 (Fluent System Icons).

### 4. 디자인 규칙
- **자체 디자인 만들지 않는다.** WPF-UI Gallery에 같은 UX가 있으면 그 컨트롤·구조를 따른다 (Wpf.Ui.Gallery 참고).
- **하드코딩 금지.** 색·브러시는 `DynamicResource`로 참조 (테마 전환이 런타임에 반영되려면 필수). 문구는 리소스로 분리.
- **테마는 시스템에 맡긴다.** Light/Dark/HighContrast = `ApplicationThemeManager`. 전환은 `ApplicationThemeManager.Apply(theme)` 한 곳. `ApplicationThemeManager.Changed` 이벤트로 커스텀 요소 갱신.
- 테마 적용은 생명주기 초기(App.xaml 또는 MainWindow 생성자)에.

## Conventions
- **아키텍처**: MVVM + Clean. UI(View/ViewModel) → Application → Domain ← Infrastructure
- **ViewModel**: `[ObservableProperty]` / `[RelayCommand]` (CommunityToolkit.Mvvm), DI 등록 필수
- **에러 처리**: `Result<T>` 패턴 권장
- **비동기**: `async`/`await` 일관. `.Result`/`.Wait()` 금지, `async void`는 이벤트 핸들러만
- **색/브러시**: `DynamicResource` (테마 대응). `StaticResource`는 테마 무관 항목만
- **파일**: 1500라인 내외, UTF-8 (BOM 없음), 주석은 한글 ("왜"만 설명)
- **접근성**: `AutomationProperties.Name`, 키보드 내비게이션

## Repository Structure
```
<repo>/
├── <Project>.sln
├── <Project>/
│   ├── <Project>.csproj        # UseWPF=true, WPF-UI 패키지
│   ├── App.xaml(.cs)           # ThemesDictionary + ControlsDictionary 병합
│   ├── MainWindow.xaml(.cs)    # ui:FluentWindow
│   ├── Views/ + ViewModels/
│   ├── Services/               # DI 등록 서비스
│   └── Assets/
├── tests/
└── docs/                       # WPF-UI 커스텀 패턴 메모 (있으면)
```

## DO NOT
- WPF-UI 설치 후 표준 `Window`로 새 창 생성 (FluentWindow 사용)
- 색·브러시를 `StaticResource`/하드코딩 (테마 전환 깨짐 → `DynamicResource`)
- 자체 Fluent 스타일 재구현 (WPF-UI 컨트롤 우선)
- `appsettings.Development.json`/`secrets` 실제 credential 커밋
- `bin/`, `obj/` 커밋
- 메인 스레드 블로킹 (`Dispatcher` 남용, 동기 I/O)

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- 타깃: <net8.0-windows 등>
- WPF-UI 버전: 새 프로젝트 생성 시점의 최신 안정 버전 고정 (와일드카드 지양)
- 배포: <MSIX | ClickOnce | 자체 installer>
- 상세 가이드: https://wpfui.lepo.co/documentation/getting-started.html

> ⚠️ `pjc:add-viewmodel` skill은 WinUI 3 전용입니다. WPF ViewModel은 패턴이 유사하나(CommunityToolkit.Mvvm 공통), View 측은 WPF-UI 컨트롤을 사용하므로 이 문서의 규칙을 따르세요.
