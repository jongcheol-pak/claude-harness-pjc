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
