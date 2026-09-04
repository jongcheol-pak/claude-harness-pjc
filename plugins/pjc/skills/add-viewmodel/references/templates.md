# `add-viewmodel` 코드 템플릿

> `SKILL.md`의 「실행 단계」가 가리키는 코드 골격이다. **규칙은 그쪽에 있고 여기는 형태만 담는다** — 두 곳에 같은 규칙을 적으면 한쪽만 고쳐져 갈린다(`skills/DESIGN.md` 2절).

## Step 2

**기본 템플릿**

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

## Step 3

**코드비하인드 (`<Name>Page.xaml.cs`)**

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

## Step 4

**`App.xaml.cs` (또는 `Program.cs`) 의 `ConfigureServices`에 추가**

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

## Step 6

**`tests/<Project>.Tests/ViewModels/<Name>ViewModelTests.cs`**

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

## XAML 골격

XAML(`<Name>Page.xaml`) — `<Page x:Class="<ProjectNamespace>.Views.<Name>Page">` 에 표준 namespace 4개(`xmlns`·`xmlns:x`·`xmlns:d`·`xmlns:mc` + `mc:Ignorable="d"`)를 선언하고 그 안에 `<Grid Padding="16" RowDefinitions="Auto,*">`를 두고, 헤더는 `TextBlock` + `Text="{x:Bind ViewModel.Title, Mode=OneWay}"` + `Style="{StaticResource TitleTextBlockStyle}"`, 본문은 `ProgressRing IsActive="{x:Bind ViewModel.IsBusy, Mode=OneWay}"`로 시작한다.

> **WPF 차이**: WPF에는 `x:Bind`·`ProgressRing`·`TitleTextBlockStyle`이 없다. WPF View는 `{Binding Title}`(DataContext에 VM 주입), `ProgressRing` 대신 `ProgressBar IsIndeterminate="True"`, namespace는 `System.Windows.Controls.Page`, Style은 프로젝트/WPF-UI 리소스를 사용한다. 또한 WPF는 **`Grid`의 `RowDefinitions="Auto,*"` 축약 문법과 `Grid Padding`을 지원하지 않는다** — `<Grid.RowDefinitions>`를 전개해 `<RowDefinition Height="Auto"/><RowDefinition Height="*"/>`로 쓰고, `Padding` 대신 자식 요소에 `Margin`을 준다(또는 Grid를 `Border Padding`으로 감싼다).

> **MAUI 차이**: MAUI는 `Page` 대신 `ContentPage`(`Microsoft.Maui.Controls`). `x:Bind`가 없어 `{Binding Title}`(BindingContext에 VM 주입, `x:DataType`으로 컴파일 바인딩 권장), `ProgressRing` 대신 `ActivityIndicator`, 코드비하인드 namespace는 `Microsoft.Maui.Controls`, DI는 `MauiProgram`의 `builder.Services`(`App.GetService` 대신 생성자 주입). ViewModel(Step 2)은 CommunityToolkit.Mvvm 그대로 사용한다.

코드비하인드 (`<Name>Page.xaml.cs`):

> **주의**: `App.GetService<T>()`는 `App.xaml.cs`에 정의된 정적 헬퍼라고 가정. 프로젝트가 다른 방식(생성자 주입, IPageFactory 등)을 쓰면 그쪽을 따른다.
