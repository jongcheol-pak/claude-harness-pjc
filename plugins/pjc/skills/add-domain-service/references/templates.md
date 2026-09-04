# `add-domain-service` 코드 템플릿

> `SKILL.md`의 「실행 단계」가 가리키는 코드 골격이다. **규칙은 그쪽에 있고 여기는 형태만 담는다** — 두 곳에 같은 규칙을 적으면 한쪽만 고쳐져 갈린다(`skills/DESIGN.md` 2절).

## Step 2

**`src/<Project>.Domain/Services/I<Name>Service.cs`**

```csharp
namespace <Project>.Domain.Services;

/// <summary>
/// <서비스 책임 한 줄>
/// </summary>
public interface I<Name>Service
{
    /// <summary>
    /// <연산 설명>
    /// </summary>
    /// <param name="<param>">...</param>
    /// <returns>...</returns>
    <ReturnType> <MethodName>(<Params>);
}
```

**`src/<Project>.Domain/Services/<Name>Service.cs`**

```csharp
namespace <Project>.Domain.Services;

/// <summary>
/// <서비스 책임 + 핵심 알고리즘 요약>
/// </summary>
public sealed class <Name>Service : I<Name>Service
{
    // Domain 레이어에서는 다른 Domain 인터페이스/리포지토리만 의존
    private readonly I<Repository> _repo;

    public <Name>Service(I<Repository> repo)
    {
        _repo = repo;
    }

    public <ReturnType> <MethodName>(<Params>)
    {
        // 비즈니스 규칙 검증
        // ...

        // 결과 반환 또는 도메인 이벤트 발행
        // ...
    }
}
```

## Step 3

**(또는 프로젝트 컨벤션에 맞게)**

```csharp
using <Project>.Domain.Services;
// 필요한 다른 Domain 타입

namespace <Project>.Application.UseCases.<Name>;

public sealed record <Name>Request(/* params */);
public sealed record <Name>Response(/* fields */);

/// <summary>
/// <UseCase 책임>
/// </summary>
public sealed class <Name>Handler
{
    // 아래 스캐폴드는 프로젝트에 UnitOfWork 패턴이 이미 있음을 전제로 한다.
    // 없으면(리포지토리가 직접 SaveChanges, DbContext 주입 등) IUnitOfWork 관련 줄(_uow 필드·생성자 인자·_uow.SaveChangesAsync 호출)을
    // 그 프로젝트의 기존 영속화 컨벤션으로 대체한다 — IUnitOfWork를 새로 도입하지 말 것.
    private readonly I<Name>Service _domainService;
    private readonly IUnitOfWork _uow;
    private readonly ILogger<<Name>Handler> _logger;

    public <Name>Handler(
        I<Name>Service domainService,
        IUnitOfWork uow,
        ILogger<<Name>Handler> logger)
    {
        _domainService = domainService;
        _uow = uow;
        _logger = logger;
    }

    public async Task<<Name>Response> HandleAsync(
        <Name>Request request,
        CancellationToken ct = default)
    {
        // 1. 유효성/권한 (필요 시)
        // 2. Aggregate 로딩
        // 3. Domain Service 호출
        // 4. 영속화
        await _uow.SaveChangesAsync(ct);

        return new <Name>Response(/* ... */);
    }
}
```

## Step 4

**`src/<Project>.Domain/DependencyInjection.cs` 또는 동등 위치**

```csharp
public static IServiceCollection AddDomainServices(this IServiceCollection services)
{
    services.AddScoped<I<Name>Service, <Name>Service>();
    return services;
}
```

**`src/<Project>.Application/DependencyInjection.cs`**

```csharp
public static IServiceCollection AddApplicationServices(this IServiceCollection services)
{
    services.AddScoped<<Name>Handler>();
    return services;
}
```

**진입점 (Program.cs / App.xaml.cs)**

```csharp
services.AddDomainServices();
services.AddApplicationServices();
```

## Step 5

**`tests/<Project>.Domain.Tests/Services/<Name>ServiceTests.cs`**

```csharp
using NSubstitute;  // 또는 Moq
using Xunit;

namespace <Project>.Domain.Tests.Services;

public class <Name>ServiceTests
{
    private readonly I<Repository> _repo = Substitute.For<I<Repository>>();
    private <Name>Service CreateSut() => new(_repo);

    [Fact]
    public void <MethodName>_정상입력_기대결과를반환한다()
    {
        // Arrange
        var sut = CreateSut();
        // _repo.<Method>().Returns(<test data>);

        // Act
        var result = sut.<MethodName>(/* params */);

        // Assert
        Assert.<Expected>(result);
    }

    [Fact]
    public void <MethodName>_규칙위반입력_예외를던진다()
    {
        // Arrange
        var sut = CreateSut();

        // Act & Assert
        Assert.Throws<<DomainException>>(() =>
            sut.<MethodName>(/* invalid params */));
    }
}
```
