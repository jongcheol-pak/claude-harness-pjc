# AGENTS.md — Agent Guide (WinUI 3 / Windows App SDK)

> WinUI 3 (Windows App SDK) Desktop 프로젝트용 가이드. Claude Code의 모든 작업은 이 문서를 우선 따른다.
> 상세 원문이 있으면 `docs/WINUI3-PROJECT-GUIDE.md`, `docs/WINUI3-DESIGN-GUIDE.md`를 함께 참조한다.

## Stack
- **언어**: C# / .NET <version, 예: net8.0-windows10.0.19041.0>
- **UI**: WinUI 3 (Windows App SDK 2.x), MVVM = `CommunityToolkit.Mvvm`
- **주요 패키지**: `Microsoft.WindowsAppSDK`, `CommunityToolkit.WinUI.Controls.SettingsControls`, `CommunityToolkit.WinUI.Extensions`, `WinUIEx` <실제 사용하는 것만>
- **테스트**: <xUnit | NUnit | MSTest>

## Build & Test
- **Build**: `dotnet build <Project>.csproj -c Debug -p:Platform=x64`  ← **반드시 `-p:Platform` 명시**
- **Test**: `dotnet test tests/`
- **Lint/Format**: `dotnet format`
- **실행**: 패키지형은 VS F5(Package 프로필) 권장. 비패키지형은 `dotnet run --project <Project>.csproj -p:Platform=x64`

## 프로젝트 생성/실행 필수 규칙 (위반 시 "실행할 수 없습니다"/배포 실패)

이 4가지가 어긋나면 빌드는 되어도 실행/배포가 막힌다. 새 프로젝트 생성·구조 수정 시 반드시 확인:

1. **`.slnx`에 솔루션 플랫폼 매핑 필수.** WinUI 3는 `Any CPU` 미지원. 매핑 없으면 VS가 Any CPU로 열려 실행 불가.
   - `<Configurations>`에 ARM64/x64/x86 정의 + 각 `<Project>`에 `<Platform Solution="*|x64" Project="x64"/>` + `<Deploy/>`
2. **패키지/비패키지 설정과 시작 프로필 일치.**
   - 패키지형(MSIX, 권장): `.csproj`에 `WindowsPackageType` **미지정** + `launchSettings.json`의 `MsixPackage` 프로필.
   - 비패키지형: `.csproj`에 `<WindowsPackageType>None</WindowsPackageType>` + 시작 프로필 `Unpackaged`(commandName: Project).
   - 비패키지인데 Package 프로필로 실행하면 배포 산출물 없어 실패.
3. **진입점은 `MainWindow`(Window).** `App.OnLaunched`에서 `_window = new MainWindow(); _window.Activate();`
   - ❌ `Window.Current`는 UWP API. WinUI 3 Desktop에서 항상 null → 사용 금지.
4. **플랫폼 명시 빌드.** `-p:Platform=x64` 없이 빌드하면 플랫폼 불일치 가능.

> ❌ **`dotnet new winui` (CLI) 사용 금지.** 서드파티 템플릿이 점유 — VS 기본 구조와 다름(MainPage+Frame, `WindowsPackageType=None`, slnx 매핑 누락). VS2026 "Blank App, Packaged (WinUI 3 in Desktop)" 템플릿 사용.

## 디자인 규칙 (WinUI Gallery 스타일)

1. **자체 디자인 만들지 않는다.** Gallery에 같은 UX 있으면 그 표준 컨트롤·구조 사용.
2. **하드코딩 금지.** 색·간격·라운드는 `Resources/`의 토큰(ResourceDictionary)으로 분리, 화면은 토큰 키만 참조.
3. **테마는 시스템에 맡긴다.** Light/Dark/HighContrast = `ThemeResource` + `ThemeDictionaries` 자동 처리. 전환은 루트 `RequestedTheme` 한 곳만 변경.
4. **폰트 미지정.** `FontFamily` 박지 말 것 (다국어 글꼴 깨짐). 표준 텍스트 램프 스타일(`TitleTextBlockStyle`, `BodyTextBlockStyle` 등)만 적용, 크기·굵기만 조정.
5. **시스템 키 우선.** 커스텀 Brush 만들기 전에 Gallery 표준 ThemeResource 키로 표현 가능한지 먼저 확인.
6. 페이지 골격: `ScrollViewer(페이지 패딩 36,24,40,24) → StackPanel(MaxWidth 1024, Spacing 24) → 헤더 + 카드`. Primary 버튼(`AccentButtonStyle`)은 화면당 1개.
7. 설정 페이지는 `SettingsCard`/`SettingsExpander` 사용.

## XAML 작성 규칙 (레이아웃 실수 방지 — 시각 확인 없이)

빌드는 통과해도 화면이 깨지는 흔한 실수를 사전 차단한다.

1. **레이아웃을 손으로 짜지 말고 완성 컨트롤을 조합한다.** Grid를 직접 행·열로 쪼개기 전에, `NavigationView`·`SettingsCard`·`InfoBar`·`Expander` 등 레이아웃이 내장된 컨트롤로 표현 가능한지 먼저 확인. 자체 Grid 조립은 정렬·간격 실수의 주원인.
2. **Grid 사용 시 `RowDefinitions`/`ColumnDefinitions` 필수 명시.** 정의 없이 `Grid.Row` 지정하면 모두 0행에 겹친다.
3. **고정 픽셀 대신 `*`/`Auto`/`GridLength`.** `Width="320"` 같은 고정값은 다양한 창 크기·DPI에서 깨짐. 콘텐츠 크기는 `Auto`, 채움은 `*`.
4. **요소 겹침 방지**: 절대 위치(`Canvas`, 음수 Margin) 사용 금지. 겹침이 필요하면 `Grid` 같은 칸 + `ZIndex`.
5. **바인딩 모드 명시.** 입력 컨트롤 양방향은 `Mode=TwoWay` 명시 (기본값이 OneWay인 속성 많음). `x:Bind`는 기본 OneTime이라 갱신되려면 `Mode=OneWay` 필요.
6. **리소스 키는 정의 확인 후 사용.** `{ThemeResource X}`/`{StaticResource X}`의 키 X가 실제 정의돼 있는지 grep으로 확인. 오타 키는 런타임 크래시(빌드는 통과).
7. **참조 구현 우선.** 새 화면은 WinUI Gallery의 동일 패턴 XAML 구조를 따른다 (창작보다 검증된 구조 복제가 안정적).
8. **빌드로 1차 검증.** `dotnet build`는 XAML 컴파일 오류·`x:Bind` 경로 오류·일부 리소스 키 오류를 잡는다. 빌드는 반드시 통과시킨 뒤 다음 task로. 단, 빌드 통과가 "레이아웃이 보기 좋다"를 보장하지는 않으므로, 레이아웃 적정성은 ⏳ HUMAN-VERIFY로 남기고 사용자 확인 목록에 적는다 (시각 결함은 빌드로 못 잡음).

## 다국어(문구) 규칙

1. **문구 하드코딩 금지.** 모든 화면 문구는 `.resw` + `x:Uid`로 분리. XAML/코드에 직접 쓴 문자열은 번역 누락 원인.
   - 폴더: `Strings/en-US/Resources.resw`(중립 폴백), `Strings/ko-KR/Resources.resw`
   - `.csproj`에 `<DefaultLanguage>en-US</DefaultLanguage>`
   - 키 = `{x:Uid값}.{속성}` (예: `AutoStartCard.Header`)
2. **코드비하인드 문구**는 헬퍼로 조회 (`Loc.Get("키")`), 내부적으로 `ResourceLoader.GetString`, 없으면 키 자체 반환(누락 가시화).
3. **런타임 언어 전환** 순서: ① 설정 저장 → ② `ApplicationLanguages.PrimaryLanguageOverride` 설정 → ③ ResourceContext Language qualifier 갱신 + ResourceLoader 재생성 → ④ 셸을 새 `Frame`으로 재로드 → ⑤ **새 Frame이라 `RequestedTheme` 초기화됨 → 테마 재적용 필수**.
4. **StartupTask 표시명**은 `ms-resource:///Resources/<키>` 형식. 전체 URI(`ms-resource://앱이름/...`)는 resolve 실패.

## Conventions
- **아키텍처**: DDD + Clean. 의존 방향: UI → Application → Domain ← Infrastructure
- **MVVM**: ViewModel은 `[ObservableProperty]` / `[RelayCommand]` (CommunityToolkit.Mvvm)
- **DI**: `Microsoft.Extensions.DependencyInjection`, 인터페이스 통한 등록
- **에러 처리**: `Result<T>` 패턴 권장
- **비동기**: `async`/`await` 일관. `.Result`/`.Wait()` 금지, `async void`는 이벤트 핸들러만
- **파일**: 1500라인 내외, UTF-8 (BOM 없음), 주석은 한글 ("왜"만 설명)
- **접근성**: 포커스 비주얼 + `AutomationProperties.Name` 설정

## Repository Structure

```
<repo>/
├── <Project>.slnx              # 플랫폼 매핑 포함
├── <Project>/
│   ├── <Project>.csproj        # UseWinUI=true, WindowsAppSDK
│   ├── App.xaml(.cs)           # OnLaunched → new MainWindow()
│   ├── MainWindow.xaml(.cs)    # 진입점 Window
│   ├── Package.appxmanifest
│   ├── Resources/              # 디자인 토큰 5개 사전 (Colors/Brushes/Typography/Spacing/ControlStyles)
│   ├── Strings/                # en-US, ko-KR .resw
│   ├── Views/ + ViewModels/
│   └── Properties/launchSettings.json
├── tests/
└── docs/                       # WINUI3-PROJECT-GUIDE.md, WINUI3-DESIGN-GUIDE.md (있으면)
```

## DO NOT
- `dotnet new winui` (CLI) 사용
- `Window.Current` 사용 (UWP 잔재)
- `FontFamily` 하드코딩, 문구 하드코딩
- 언어 전환 후 테마 재적용 누락
- `WindowsPackageType` 설정과 시작 프로필 불일치
- `secrets.json`/`appsettings.Development.json` 실제 credential 커밋
- `bin/`, `obj/` 커밋

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- 타깃 OS: Windows 11 21H2+ (`net10.0-windows10.0.22000.0`) 또는 프로젝트 지정값
- 배포: MSIX (패키지형 권장)
- 상세 가이드: `docs/WINUI3-PROJECT-GUIDE.md` (생성/실행), `docs/WINUI3-DESIGN-GUIDE.md` (UI)
