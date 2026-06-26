# AGENTS.md — Agent Guide (WPF + WPF-UI)

> WPF (.NET) 프로젝트용 가이드. UI는 WPF-UI(Fluent) 라이브러리를 사용한다. Claude Code의 모든 작업은 이 문서를 우선 따른다.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.


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

### 5. XAML 작성 규칙 (레이아웃 실수 방지 — 시각 확인 없이)

빌드는 통과해도 화면이 깨지는 흔한 실수를 사전 차단한다.

1. **레이아웃을 손으로 짜지 말고 WPF-UI 완성 컨트롤을 조합한다.** Grid 직접 조립 전에 `ui:NavigationView`·`ui:Card`·`ui:InfoBar` 등으로 표현 가능한지 먼저 확인.
2. **Grid 사용 시 `RowDefinitions`/`ColumnDefinitions` 필수 명시.** 정의 없이 `Grid.Row` 지정하면 모두 0행에 겹친다.
3. **고정 픽셀 대신 `*`/`Auto`.** 고정 `Width`/`Height`는 DPI·창 크기에서 깨짐. 콘텐츠는 `Auto`, 채움은 `*`.
4. **요소 겹침 방지**: `Canvas`·음수 Margin 금지. 겹침은 `Grid` 같은 칸 + `Panel.ZIndex`.
5. **바인딩 모드 명시.** 입력 컨트롤 양방향은 `Mode=TwoWay`, `UpdateSourceTrigger=PropertyChanged` 명시. WPF 기본 바인딩은 INotifyPropertyChanged 구현 필요 (CommunityToolkit.Mvvm `[ObservableProperty]`가 자동 처리).
6. **리소스 키는 정의 확인 후 사용.** `{DynamicResource X}`/`{StaticResource X}`의 키 X 존재를 grep 확인. WPF는 `StaticResource` 키 누락 시 **빌드는 통과하고 런타임 크래시**.
7. **네임스페이스 혼동 금지.** WPF는 `System.Windows.Controls`(표준) + `Wpf.Ui.Controls`(WPF-UI, `ui:` 접두사). WinUI(`Microsoft.UI.Xaml`) 컨트롤·문법을 섞지 말 것 (`x:Bind`는 WinUI 전용 — WPF는 `Binding` 사용).
8. **참조 구현 우선.** 새 화면은 Wpf.Ui.Gallery의 동일 패턴 구조를 복제.
9. **빌드로 1차 검증.** `dotnet build`로 XAML 오류를 잡고 반드시 통과시킨 뒤 다음 task로. 단 레이아웃 적정성(보기 좋은가)은 빌드로 못 잡으므로 ⏳ HUMAN-VERIFY로 남기고 사용자 확인 목록에 적는다.

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
- 코드·문서·notes·plan 등 어떤 파일에도 실제 IP·계정·비밀번호·토큰·DB 연결문자열 기록 (환경변수 이름만 적고 값은 .env로)
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass` (백신이 공격 도구로 오인해 격리할 수 있음)

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- 타깃: <net8.0-windows 등>
- WPF-UI 버전: 새 프로젝트 생성 시점의 최신 안정 버전 고정 (와일드카드 지양)
- 배포: <MSIX | ClickOnce | 자체 installer>
- 상세 가이드: https://wpfui.lepo.co/documentation/getting-started.html

> ⚠️ `pjc:add-viewmodel` skill은 WinUI 3 / WPF / MAUI 대상입니다(CommunityToolkit.Mvvm 기반 — WPF도 ViewModel 생성에 사용 가능). 단 View 측은 WinUI와 달라 WPF-UI 컨트롤을 쓰므로, SKILL의 "WPF 차이" 주석(`x:Bind`→`{Binding}`, `ProgressRing`→`ProgressBar` 등)과 이 문서의 규칙을 따르세요.
