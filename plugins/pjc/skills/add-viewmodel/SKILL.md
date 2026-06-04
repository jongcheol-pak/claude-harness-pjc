---
name: add-viewmodel
description: This skill should be used when the user requests adding a new screen, dialog, page, window, or any UI component that needs a ViewModel in a WinUI 3 / WPF / MAUI project using CommunityToolkit.Mvvm. Triggers on phrases like "ViewModel 추가", "새 화면", "다이얼로그 추가", "페이지 만들기", "add screen/page/dialog/window". Generates ViewModel + View skeleton with proper MVVM bindings and DI registration.
argument-hint: "<화면 이름 또는 목적>"
---

# Add ViewModel

WinUI 3 / WPF / MAUI 프로젝트에 MVVM 패턴(`CommunityToolkit.Mvvm`)으로
View + ViewModel 스켈레톤을 추가한다.

## 호출 흐름

이 skill은 **`pjc:implement-task`의 Phase I 안에서 호출**되거나, 사용자가 직접 `/pjc:add-viewmodel`로 호출할 수 있다.

| 호출 방식 | 흐름 |
|---|---|
| implement-task Phase I 안 | plan.md task가 "ViewModel 추가" 패턴이면 자동 호출. 이 skill이 boilerplate 생성 후 implement-task의 Phase V가 검증을 이어받음. |
| 사용자 직접 호출 | plan.md 없이 단독 사용. 단, `require-plan-for-write` hook이 차단할 수 있으므로 `$env:CLAUDE_HARNESS_QUICK = '1'` 필요. |

이 skill의 **책임 범위**: ViewModel/View boilerplate, DI 등록, 기본 테스트 스켈레톤 생성까지.
**책임 범위 밖**: 비즈니스 로직, 데이터 바인딩 상세, 통합 검증 — implement-task가 담당.

**Android의 Jetpack ViewModel은 비대상.** Android의 경우 implement-task가 직접 구현.

## 사전 조건

이 skill을 호출하기 전에 `plan-feature`로 다음이 결정되어 있어야 한다:

- 화면 이름 (예: `Settings`, `UserDetail`)
- 화면 종류 (Page / Window / UserControl / ContentDialog)
- 위치 (어느 모듈/프로젝트)
- 상위 네비게이션과의 연결 방식
- 필요한 의존성 서비스 (있다면)

위 정보가 없으면 사용자에게 묻거나 `plan-feature`로 복귀.

## 절대 규칙

1. **AGENTS.md 우선.** 프로젝트가 다른 패턴(ReactiveUI, MVVM Light 등)을 명시했다면 이 skill을 사용하지 않는다.
2. **DDD 준수.** ViewModel은 UI 레이어. 비즈니스 로직은 Domain 서비스를 호출하기만 한다.
3. **DI 등록 누락 금지.** ViewModel은 반드시 `ConfigureServices`에 등록.
4. **한글 주석.** XML 문서 주석 포함 모두 한글.
5. **UTF-8 (BOM 없음).**
6. **WinUI 3 프로젝트면 디자인·다국어 규칙 준수.** AGENTS.md(winui3 템플릿)의 디자인 규칙(토큰화, 폰트 미지정, 시스템 키 우선)과 다국어 규칙(문구는 `x:Uid`+`.resw`, 하드코딩 금지)을 따른다. 상세는 `docs/WINUI3-DESIGN-GUIDE.md`가 있으면 참조. View의 문구를 코드/XAML에 직접 쓰지 않는다.

## 실행 단계

### Step 1. 컨텍스트 파악

다음을 확인:
- 기존 ViewModel 위치 (예: `src/*/ViewModels/`)
- 기존 View 위치 (예: `src/*/Views/`)
- DI 등록 진입점 (보통 `App.xaml.cs` 또는 `Program.cs`의 `ConfigureServices`)
- 네비게이션 서비스 패턴 (`INavigationService` 등 존재 여부)
- 기존 ViewModel 한 개를 읽어 컨벤션 파악 (네이밍, 베이스 클래스, 주석 스타일)

### Step 2. ViewModel 생성

기본 템플릿:

```csharp
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Extensions.Logging;

namespace <ProjectNamespace>.ViewModels;

/// <summary>
/// <화면 목적 한 줄 설명>
/// </summary>
public sealed partial class <Name>ViewModel : ObservableObject
{
    private readonly ILogger<<Name>ViewModel> _logger;
    // 기타 의존성: private readonly I<Service> _service;

    // 화면 표시용 상태
    [ObservableProperty]
    private string _title = "<기본 제목>";

    [ObservableProperty]
    private bool _isBusy;

    public <Name>ViewModel(
        ILogger<<Name>ViewModel> logger
        /* , I<Service> service */)
    {
        _logger = logger;
        // _service = service;
    }

    /// <summary>
    /// 화면이 표시될 때 호출. 초기 데이터 로딩 등.
    /// </summary>
    [RelayCommand]
    private async Task LoadAsync()
    {
        if (IsBusy) return;

        try
        {
            IsBusy = true;
            // TODO: 초기화 로직 (Domain 서비스 호출)
            _logger.LogInformation("<Name> 화면 로딩 완료");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "<Name> 화면 로딩 실패");
            // 사용자 알림 로직 (Dialog/SnackBar)
        }
        finally
        {
            IsBusy = false;
        }
    }
}
```

### Step 3. View 생성

#### WinUI 3 / WPF Page 또는 Window

XAML (`<Name>Page.xaml`):
```xml
<Page
    x:Class="<ProjectNamespace>.Views.<Name>Page"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    mc:Ignorable="d">

    <Grid Padding="16" RowDefinitions="Auto,*">
        <!-- 헤더 -->
        <TextBlock Grid.Row="0"
                   Text="{x:Bind ViewModel.Title, Mode=OneWay}"
                   Style="{StaticResource TitleTextBlockStyle}"/>

        <!-- 본문 -->
        <ProgressRing Grid.Row="1"
                      IsActive="{x:Bind ViewModel.IsBusy, Mode=OneWay}"
                      HorizontalAlignment="Center"/>
    </Grid>
</Page>
```

코드비하인드 (`<Name>Page.xaml.cs`):
```csharp
using Microsoft.UI.Xaml.Controls;

namespace <ProjectNamespace>.Views;

public sealed partial class <Name>Page : Page
{
    public <Name>ViewModel ViewModel { get; }

    public <Name>Page()
    {
        // DI 컨테이너에서 ViewModel 해석
        ViewModel = App.GetService<<Name>ViewModel>();
        InitializeComponent();

        // 페이지가 표시될 때 초기 로딩
        Loaded += async (_, _) => await ViewModel.LoadCommand.ExecuteAsync(null);
    }
}
```

> **주의**: `App.GetService<T>()`는 `App.xaml.cs`에 정의된 정적 헬퍼라고 가정. 프로젝트가 다른 방식(생성자 주입, IPageFactory 등)을 쓰면 그쪽을 따른다.

### Step 4. DI 등록

`App.xaml.cs` (또는 `Program.cs`) 의 `ConfigureServices`에 추가:

```csharp
private static IServiceProvider ConfigureServices()
{
    var services = new ServiceCollection();

    // ... 기존 등록 ...

    // ViewModels
    services.AddTransient<<Name>ViewModel>();   // 화면 진입마다 새 인스턴스

    // Pages (선택 - Page DI를 쓰는 경우만)
    services.AddTransient<<Name>Page>();

    return services.BuildServiceProvider();
}
```

> **수명**: 일반적으로 ViewModel은 `Transient`. 앱 전체에서 상태를 유지해야 하면 `Singleton` 검토.

### Step 5. 네비게이션 연결 (해당하는 경우)

기존 네비게이션 패턴에 따라:
- `Frame.Navigate(typeof(<Name>Page))`
- `INavigationService.NavigateTo("<Name>")`
- 메뉴/사이드바에 항목 추가

이 단계는 **plan.md에 명시된 진입점**에 따라 진행. 추측 금지.

### Step 6. 테스트 스캐폴드

`tests/<Project>.Tests/ViewModels/<Name>ViewModelTests.cs`:

```csharp
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace <ProjectNamespace>.Tests.ViewModels;

public class <Name>ViewModelTests
{
    private static <Name>ViewModel CreateSut()
    {
        return new <Name>ViewModel(
            NullLogger<<Name>ViewModel>.Instance
            /* , Mock 의존성 */);
    }

    [Fact]
    public async Task LoadCommand_초기실행_IsBusy_가_복원된다()
    {
        // Arrange
        var sut = CreateSut();

        // Act
        await sut.LoadCommand.ExecuteAsync(null);

        // Assert
        Assert.False(sut.IsBusy);
    }
}
```

### Step 7. 검증

다음을 모두 통과해야 완료:
- [ ] 빌드 성공
- [ ] 단위 테스트 통과 (최소 LoadCommand 1건)
- [ ] DI 등록 누락 없음 (`App.GetService<<Name>ViewModel>()` 동작 확인)
- [ ] 네비게이션 진입 시 정상 표시 (가능하면 수동 확인)

## 변형 (Variants)

### A. ContentDialog (모달)

`Page` 대신 `ContentDialog` 사용:

```csharp
public sealed partial class <Name>Dialog : ContentDialog
{
    public <Name>ViewModel ViewModel { get; }

    public <Name>Dialog(<Name>ViewModel viewModel)
    {
        ViewModel = viewModel;
        InitializeComponent();
    }
}
```

생성자 주입 가능 (DI에서 직접 해석).

### B. UserControl (재사용 부품)

`ViewModel`을 외부에서 `DataContext`로 주입받는 형태.

```xml
<UserControl ...>
    <Grid DataContext="{x:Bind ViewModel}">
        ...
    </Grid>
</UserControl>
```

### C. Settings / 영속화가 필요한 경우

`Singleton` ViewModel + `ISettingsService` 의존성 주입.

## 안티패턴 (금지)

| 안티패턴 | 올바른 행동 |
|---|---|
| `INotifyPropertyChanged` 수동 구현 | `[ObservableProperty]` 사용 |
| `ICommand`를 수동 구현 | `[RelayCommand]` 사용 |
| ViewModel에서 `MessageBox` 직접 호출 | `IDialogService` 등으로 추상화 |
| ViewModel에서 `HttpClient` 직접 사용 | Domain/Application 서비스 경유 |
| 코드비하인드에 비즈니스 로직 작성 | ViewModel로 이동 |
| DI 등록 없이 `new <Name>ViewModel()` | 항상 컨테이너 경유 |
| 영문 XML doc 주석 | 한글로 작성 |
| 동기 `Wait()`, `.Result` 호출 | `async/await` |
| `LoadAsync`를 생성자에서 직접 호출 | `Loaded` 이벤트 또는 명시적 커맨드 |

## Halt 조건

다음 발견 시 사용자에게 보고하고 중지:

- 기존 ViewModel이 다른 베이스 클래스(`BindableBase`, `ReactiveObject` 등)를 쓰고 있음
- DI 컨테이너가 없거나 ServiceLocator 패턴을 쓰고 있음
- 네비게이션 패턴이 plan.md에 명시되지 않았고 코드베이스에서도 단일 패턴이 보이지 않음
- View가 코드 생성기로 만들어지는 경우 (`*.Generated.*`)
