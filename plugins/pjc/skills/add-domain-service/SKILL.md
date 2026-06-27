---
name: add-domain-service
description: This skill should be used when the user requests adding business logic, a domain service, an application service, or any logic that should live in the Domain or Application layer of a DDD project. Triggers on phrases like "서비스 추가", "도메인 로직", "비즈니스 로직", "use case 추가", "add service", "add use case". Generates Domain interface + implementation + DI registration + unit test scaffold. Do NOT trigger for logic that belongs inside a single Aggregate (add a method to the Aggregate instead), for pure UI/ViewModel work (use add-viewmodel), or for infrastructure/config-only changes.
argument-hint: "<서비스 이름 또는 목적>"
---

# Add Domain Service

DDD 프로젝트에 비즈니스 로직 서비스(Domain Service 또는 Application Service)를 추가한다.
**비즈니스 로직은 Domain 레이어에, 오케스트레이션은 Application 레이어에** 둔다는 원칙을 강제한다.

## 호출 흐름

이 skill은 **`pjc:implement-task`의 Phase I 안에서 호출**되거나, 사용자가 직접 `/pjc:add-domain-service`로 호출할 수 있다.

| 호출 방식 | 흐름 |
|---|---|
| implement-task Phase I 안 | plan.md task가 "Domain Service 추가" 또는 "UseCase 추가" 패턴이면 자동 호출. 이 skill이 boilerplate 생성 후 implement-task의 Phase V가 검증을 이어받음. |
| 사용자 직접 호출 | plan.md 없이 단독 사용 시 `$env:CLAUDE_HARNESS_QUICK = '1'` 필요. |

이 skill의 **책임 범위**: 인터페이스 정의, 구현 skeleton, DI 등록, 단위 테스트 스캐폴드 + csproj 의존 방향 검증.
**책임 범위 밖**: 구체 비즈니스 규칙 작성 — implement-task가 담당.

이 skill은 **.NET 프로젝트를 기준**으로 한다. 다른 스택(Kotlin/Android 등)은 AGENTS.md 컨벤션을 우선하고, 아래 템플릿·검증은 .NET 기준의 개념적 참고로만 사용한다.

## 사전 조건

`plan-feature`에서 다음이 결정되어 있어야 한다:

- 서비스 이름과 책임 (한 문장)
- 레이어 (Domain Service vs Application Service)
- 인터페이스명·구현명·네임스페이스
- 의존하는 다른 서비스/리포지토리
- 트랜잭션 경계 (있다면)
- 도메인 이벤트 발행 여부

미정 항목이 있으면 `plan-feature`로 복귀.

## Domain vs Application — 어디에 둘 것인가

| 케이스 | 위치 |
|---|---|
| 순수 비즈니스 규칙 (예: 가격 계산, 정책 판정) | **Domain Service** |
| 여러 Aggregate에 걸친 규칙 (Aggregate 안에 못 넣음) | **Domain Service** |
| 외부 시스템 호출, DB 트랜잭션, 메시징 오케스트레이션 | **Application Service** |
| 단순 CRUD + UI 호출 | **Application Service** |
| 단일 Aggregate 내부 로직 | Aggregate에 메서드로 추가 (서비스 X) |

판단 기준이 모호하면 사용자에게 한 번 질문.

## 절대 규칙

1. **AGENTS.md > 이 skill.** 프로젝트가 다른 아키텍처(Clean, Hexagonal, Vertical Slice 등)를 명시했다면 그쪽 컨벤션을 따른다.
2. **Domain 레이어는 인프라 의존 0.** EF Core, HttpClient, 파일 IO, ILogger 직접 사용 금지. 필요하면 Domain에서 인터페이스만 정의하고 구현은 Infrastructure에 둔다.
3. **불변성 우선.** 가능하면 `record`, `readonly`, `immutable collection` 사용.
4. **Aggregate 경계 존중.** 한 트랜잭션에서 여러 Aggregate를 수정하지 않는다.
5. **한글 주석 / UTF-8 / 1500라인 / 직접 검증한 코드만 사용.**

## 실행 단계

### Step 1. 컨텍스트 파악

- AGENTS.md에서 레이어 구조 확인 — **Domain/Application 레이어 분리가 없으면(비-DDD: 단일 프로젝트·Core/Infra만 등) 아래 Halt 조건으로 중지**(존재하지 않는 레이어를 강요하지 않는다).
- 기존 Domain Service / Application Service 한 개씩 읽어 컨벤션 파악:
  - 네이밍 (`I<Name>Service`, `<Name>Handler`, `<Name>UseCase` 등)
  - 메서드 시그니처 패턴 (Result 타입 vs 예외, async vs 동기)
  - 에러 처리 (커스텀 예외, Result<T>, OneOf 등)
  - 리포지토리 인터페이스 위치

### Step 2. Domain Service 추가 (해당 시)

#### 인터페이스 (Domain 레이어)

`src/<Project>.Domain/Services/I<Name>Service.cs`:

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

#### 구현 (Domain 레이어)

`src/<Project>.Domain/Services/<Name>Service.cs`:

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

### Step 3. Application Service 추가 (해당 시)

`src/<Project>.Application/UseCases/<Name>/<Name>Handler.cs`
(또는 프로젝트 컨벤션에 맞게):

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

### Step 4. DI 등록

`src/<Project>.Domain/DependencyInjection.cs` 또는 동등 위치:

```csharp
public static IServiceCollection AddDomainServices(this IServiceCollection services)
{
    services.AddScoped<I<Name>Service, <Name>Service>();
    return services;
}
```

`src/<Project>.Application/DependencyInjection.cs`:

```csharp
public static IServiceCollection AddApplicationServices(this IServiceCollection services)
{
    services.AddScoped<<Name>Handler>();
    return services;
}
```

진입점 (Program.cs / App.xaml.cs):

```csharp
services.AddDomainServices();
services.AddApplicationServices();
```

> **수명**: 보통 `Scoped`. 상태 없는 순수 함수형이면 `Transient` 가능. `Singleton`은 동시성 위험.

### Step 5. 단위 테스트 (Domain 우선)

`tests/<Project>.Domain.Tests/Services/<Name>ServiceTests.cs`:

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

### Step 6. 검증

- [ ] 빌드 성공
- [ ] Domain Test 통과 (정상 케이스 + 규칙 위반 케이스 최소 각 1건)
- [ ] DI 등록 누락 없음
- [ ] **Domain 레이어가 Infrastructure를 참조하지 않음** (csproj/import 확인)

## Domain 의존 방향 검증

`src/<Project>.Domain/<Project>.Domain.csproj`에 다음이 없어야 한다:

```xml
<!-- 금지 -->
<PackageReference Include="Microsoft.EntityFrameworkCore..." />
<PackageReference Include="Microsoft.AspNetCore..." />
<PackageReference Include="System.Net.Http..." />
<PackageReference Include="Microsoft.Extensions.Logging" />  <!-- 추상화만 허용 -->
<ProjectReference Include="...Infrastructure..." />
<ProjectReference Include="...Application..." />
<ProjectReference Include="...UI..." />
```

허용:
```xml
<PackageReference Include="Microsoft.Extensions.Logging.Abstractions" />
<!-- 또는 자체 ILogger 추상화 -->
```

위반이 발견되면 **즉시 Halt**하고 사용자에게 보고.

## 안티패턴 (금지)

| 안티패턴 | 올바른 행동 |
|---|---|
| Domain에서 `DbContext` 직접 사용 | `IRepository` 인터페이스로 추상화 |
| Domain에서 `HttpClient` 사용 | Application 레이어로 이동 |
| Domain에서 `DateTime.Now` 직접 호출 | `IClock` / `TimeProvider` 추상화 |
| Domain Service가 여러 Aggregate를 트랜잭션으로 수정 | Application 레이어에서 조정 |
| 정적 상태 (`static` 필드로 캐시) | DI Singleton 또는 외부 캐시 |
| Anemic Domain (서비스가 모든 로직, Entity는 데이터만) | Aggregate에 메서드 추가 |
| Repository를 ViewModel에서 직접 호출 | Application Service 경유 |
| Service명에 `Manager`, `Helper`, `Util` | 책임 기반 명사 (Calculator, Validator, Policy 등) |
| Result type과 예외를 혼용 | 프로젝트 컨벤션 하나로 통일 |
| 영문 XML doc 주석 | 한글 |

## Halt 조건

- Domain 레이어 csproj에 인프라 의존성 발견
- 기존 서비스들이 일관된 패턴을 따르지 않음 (혼란 — 사용자 확인 필요)
- Aggregate 경계가 불명확
- 트랜잭션 경계가 plan.md에 명시되지 않음
- 동일 이름의 서비스가 이미 존재
- **프로젝트에 Domain/Application 레이어가 없음(비-DDD)** — 존재하지 않는 `src/<Project>.Domain/`·`.Application/` 구조를 새로 강요하지 말고, 어디에 둘지(또는 단순 서비스 클래스로 둘지)를 사용자에게 확인
