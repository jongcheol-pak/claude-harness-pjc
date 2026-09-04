---
name: add-domain-service
description: This skill should be used when the user requests adding business logic, a domain service, an application service, or any logic that should live in the Domain or Application layer of a DDD project. Triggers on phrases like "서비스 추가", "도메인 로직", "비즈니스 로직", "use case 추가", "add service", "add use case". Generates Domain interface + implementation + DI registration + unit test scaffold. Do NOT trigger for logic that belongs inside a single Aggregate (add a method to the Aggregate instead), for pure UI/ViewModel work (use add-viewmodel), for infrastructure/config-only changes, or for projects without a Domain/Application layer split (single-project apps, scripts, or utilities with no DDD layering — forcing a nonexistent layer is wrong; implement directly per the project's structure).
argument-hint: "<서비스 이름 또는 목적>"
---

# Add Domain Service

DDD 프로젝트에 비즈니스 로직 서비스(Domain Service 또는 Application Service)를 추가한다.
**비즈니스 로직은 Domain 레이어에, 오케스트레이션은 Application 레이어에** 둔다는 원칙을 강제한다.

## 호출 흐름

이 skill은 **`pjc:implement`의 task 실행 중 호출**되거나, 사용자가 직접 `/pjc:add-domain-service`로 호출할 수 있다.

| 호출 방식 | 흐름 |
|---|---|
| `pjc:implement` 구현 단계 안 | plan.md task가 "Domain Service 추가" 또는 "UseCase 추가" 패턴이면 자동 호출. 이 skill이 boilerplate 생성 후 `pjc:implement`의 검증이 검증을 이어받음. |
| 사용자 직접 호출 | plan.md 없이 단독 사용 시 `$env:CLAUDE_HARNESS_QUICK = '1'` 필요 — `guard-write` 의 plan 게이트가 plan 없는 쓰기를 막기 때문이다. **우회 변수는 둘이며 서로 대체되지 않는다** — 커밋 시크릿 차단은 `CLAUDE_HARNESS_ALLOW_SECRET` 전용이고, 이 변수로는 뚫리지 않는다. |

이 skill의 **책임 범위**: 인터페이스 정의, 구현 skeleton, DI 등록, 단위 테스트 스캐폴드 + csproj 의존 방향 검증.
**책임 범위 밖**: 구체 비즈니스 규칙 작성 — `pjc:implement`가 담당.

이 skill은 **.NET 프로젝트를 기준**으로 한다. 다른 스택(Kotlin/Android 등)은 AGENTS.md 컨벤션을 우선하고, 아래 단계·검증은 .NET 기준의 개념적 참고로만 사용한다.

## 사전 조건

`pjc:plan`에서 다음이 결정되어 있어야 한다:

- 서비스 이름과 책임 (한 문장)
- 레이어 (Domain Service vs Application Service)
- 인터페이스명·구현명·네임스페이스
- 의존하는 다른 서비스/리포지토리
- 트랜잭션 경계 (있다면)
- 도메인 이벤트 발행 여부

미정 항목이 있으면 `pjc:plan`로 복귀.

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

1. **AGENTS.md > 이 skill.** 다른 아키텍처를 명시했으면 그쪽을 따른다 — 배치 규칙이 둘이면 충돌한다. **단 이름만 있고 배치 규칙이 없으면 이 skill 의 절차는 그대로 쓴다.**
2. **Domain 레이어는 인프라 의존 0.** EF Core·HttpClient·파일 IO·ILogger 직접 사용 금지 — 인프라에 묶인 Domain 은 그 인프라를 세워야 테스트된다. 인터페이스만 Domain 에 두고 구현은 Infrastructure 에 둔다(목록·판정 축·Halt 정본은 아래 **"Domain 의존 방향 검증"**).
3. **불변성 우선.** `record`·`readonly`·불변 컬렉션 — 공유 가변 상태의 결함은 재현되지 않는 형태로 나타난다.
4. **Aggregate 경계 존중.** 한 트랜잭션에 한 Aggregate — 둘을 걸치면 어느 불변식이 깨졌는지 사후에 못 가린다. **레이어를 옮겨도 한 트랜잭션이면 위반은 남으며**, 둘을 함께 바꿔야 하는 요구는 설계 결정이라 `pjc:plan` 으로 돌린다.
5. **한글 주석**(XML doc 포함) — 언어가 섞이면 grep 대상이 갈린다.
6. **파일 단일 책임** — 두 책임이 한 파일이면 하나만 고칠 때도 전체를 읽어야 한다.
7. **직접 검증한 코드만 사용** — 기억으로 쓴 API 는 컴파일 시점에야 어긋남이 드러난다.
8. **인코딩은 대상 프로젝트 관례를 따른다** — `.cs` 는 Visual Studio 기본이 BOM 포함이라 이 하니스의 `.md` 관례를 적용하면 기존 파일과 갈린다.

## 실행 단계

> **코드 형태는 Step 1에서 읽은 기존 서비스를 따른다** — 그 코드가 정본이다.

### Step 1. 컨텍스트 파악

- AGENTS.md에서 레이어 구조 확인 — **Domain/Application 레이어 분리가 없으면(비-DDD: 단일 프로젝트·Core/Infra만 등) 아래 Halt 조건으로 중지**(존재하지 않는 레이어를 강요하지 않는다).
- 기존 Domain Service / Application Service 한 개씩 읽어 컨벤션 파악:
  - 네이밍 (`I<Name>Service`, `<Name>Handler`, `<Name>UseCase` 등)
  - 메서드 시그니처 패턴 (Result 타입 vs 예외, async vs 동기)
  - 에러 처리 (커스텀 예외, Result<T>, OneOf 등)
  - 리포지토리 인터페이스 위치

### Step 2. Domain Service 추가 (해당 시)

인터페이스 `src/<Project>.Domain/Services/I<Name>Service.cs` 와 구현 `src/<Project>.Domain/Services/<Name>Service.cs` 를 만든다.

### Step 3. Application Service 추가 (해당 시)

`src/<Project>.Application/UseCases/<Name>/<Name>Handler.cs` 에 만든다(또는 프로젝트 컨벤션에 맞는 위치).

영속화가 필요하면 **그 프로젝트의 기존 영속화 컨벤션을 그대로 쓴다** — `IUnitOfWork` 가 없는 프로젝트(리포지토리가 직접 `SaveChanges`·`DbContext` 주입 등)에 그것을 새로 도입하지 않는다. 도입은 구조 결정이라 `pjc:plan` 으로 돌린다.

### Step 4. DI 등록

`src/<Project>.Domain/DependencyInjection.cs`(또는 동등 위치)와 `src/<Project>.Application/DependencyInjection.cs` 에 등록하고, **진입점(Program.cs · App.xaml.cs)에서 그 등록 메서드가 실제로 호출되는지** 확인한다.

> **수명**: 보통 `Scoped`. 상태 없는 순수 함수형이면 `Transient` 가능. `Singleton`은 동시성 위험.

### Step 5. 단위 테스트 (Domain 우선)

`tests/<Project>.Domain.Tests/Services/<Name>ServiceTests.cs` 에 만든다.

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

**판정 축 — 목록에 없는 패키지는 둘로 가른다**: 런타임 인프라를 끌고 오면(DB·HTTP·파일·직렬화 구현) 금지, 타입·계약만 주면 허용. `Dapper`·`MediatR`·`System.Text.Json` 은 전자다. **이름의 `Abstractions` 로 판정하지 않는다** — 관례일 뿐 보증이 아니다.

**위반이 발견되면 즉시 Halt** — 의존 방향은 이 산출물의 전제라 깨진 채로 얹으면 잘못된 구조가 커진다. **단 기존 위반이면 보고하고 이번 변경이 그것을 늘리지 않는지만 확인한 뒤 진행한다.**

## 안티패턴 (금지)

| 안티패턴 | 올바른 행동 | 왜 |
|---|---|---|
| Domain에서 `DbContext` 직접 사용 | `IRepository` 인터페이스로 추상화 | 저장 방식이 바뀌면 도메인 규칙까지 함께 고쳐야 한다 |
| Domain에서 `HttpClient` 사용 | Application 레이어로 이동 | 외부 응답에 따라 도메인 판정이 달라져 테스트가 네트워크에 묶인다 |
| Domain에서 `DateTime.Now` 직접 호출 | `IClock` / `TimeProvider` 추상화 | 시간을 고정할 수 없어 경계값(만료·마감) 테스트가 불가능하다. **`UtcNow` 도 같다** |
| 정적 상태 (`static` 필드로 캐시) | DI Singleton 또는 외부 캐시 | 수명을 컨테이너가 모르므로 테스트 간 상태가 새고 동시성 가정이 깨진다 |
| Anemic Domain (서비스가 모든 로직, Entity는 데이터만) | Aggregate에 메서드 추가 | 불변식이 Entity 밖에 흩어져 어느 경로가 그것을 지키는지 추적할 수 없다 |
| Repository를 ViewModel에서 직접 호출 | Application Service 경유 | UI 가 영속화 계약에 묶여 화면 하나를 바꿀 때 저장 코드를 함께 본다 |
| Service명에 `Manager`, `Helper`, `Util` | 책임 기반 명사 (Calculator, Validator, Policy 등) | 이름이 책임을 좁히지 못하면 무엇이든 그 안에 들어와 파일 단일 책임이 무너진다 |
| Result type과 예외를 혼용 | 프로젝트 컨벤션 하나로 통일 | 호출부가 두 경로를 모두 처리해야 하고, 한쪽을 빠뜨려도 컴파일은 통과한다 |

## Halt 조건

- Domain 레이어 csproj에 인프라 의존성 발견 (→ "Domain 의존 방향 검증" 섹션대로 즉시 Halt — 그 섹션이 금지/허용·Halt 정본)
- 기존 서비스들이 일관된 패턴을 따르지 않음 — 어느 쪽을 따라도 절반과 어긋나므로 다수결로 정할 문제가 아니다. **Step 1 이 각 1개씩만 읽으므로 이 불일치는 우연히 관측된다** — 보이면 보고하고, 안 보인다고 없는 것으로 단정하지 않는다
- Aggregate 경계가 불명확 — 경계를 모르면 절대 규칙 4를 지켰는지 자체를 판정할 수 없다
- **영속화를 수반하는 Application Service인데 트랜잭션 경계가 plan.md에 명시되지 않음** (순수 도메인 계산·조회 등 영속화가 없는 서비스는 이 Halt 대상이 아니다 — 트랜잭션이 필요 없으므로)
- 동일 이름의 서비스가 **같은 네임스페이스에** 이미 존재 — 다른 바운디드 컨텍스트의 같은 이름은 충돌이 아니다(모듈형 모놀리스에서 정상이다). 판정은 네임스페이스까지 포함한 완전 이름이다
- **프로젝트에 Domain/Application 레이어가 없음(비-DDD)** — 존재하지 않는 `src/<Project>.Domain/`·`.Application/` 구조를 새로 강요하지 말고, 어디에 둘지(또는 단순 서비스 클래스로 둘지)를 사용자에게 확인
