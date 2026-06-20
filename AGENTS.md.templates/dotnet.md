# AGENTS.md — Agent Guide

> .NET (C#, F#, VB) 프로젝트용 가이드. Claude Code의 모든 작업은 이 문서를 우선 따른다.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.


## Stack
- **언어**: C# / .NET <version>
- **주요 패키지**: <CommunityToolkit.Mvvm, MediatR, EF Core 등 — 실제로 사용하는 것 명시>
- **테스트**: <xUnit | NUnit | MSTest>

## Build & Test
- **Build**: `dotnet build src/<Sln 또는 Project>.sln`
- **Test**: `dotnet test tests/`
- **Lint/Format**: `dotnet format`
- **Watch (개발)**: `dotnet watch run --project src/<Main>`

## Repository Structure

```
<repo>/
├── src/
│   ├── <Domain>/          # 비즈니스 로직 (POCO, no infra deps)
│   ├── <Application>/     # UseCases, Services
│   ├── <Infrastructure>/  # DB, External API
│   └── <UI/Host>/         # WinUI 3, WPF, ASP.NET 등
├── tests/
│   ├── <Domain>.Tests/
│   ├── <Application>.Tests/
│   └── <Integration>.Tests/
└── docs/
```

## Conventions
- **아키텍처**: DDD + Clean. 의존 방향: UI → Application → Domain ← Infrastructure
- **MVVM (WinUI 3/WPF/MAUI)**: ViewModel은 `CommunityToolkit.Mvvm`의 `[ObservableProperty]` / `[RelayCommand]` 사용
- **DI**: `Microsoft.Extensions.DependencyInjection`. 모든 서비스는 인터페이스 통한 등록.
- **에러 처리**: `Result<T>` 패턴 권장 (또는 명시된 예외 정책)
- **비동기**: `async`/`await` 일관성. `.Result`, `.Wait()` 금지.
- **테스트**: 단위 테스트는 Domain/Application, 통합은 Infrastructure 별도
- **파일**: 1500라인 내외, UTF-8 (BOM 없음), 주석은 한글 ("왜"만 설명)

## DO NOT
- `secrets.json`, `appsettings.Development.json`의 실제 credential 커밋
- `bin/`, `obj/` 커밋 (gitignore에 포함)
- 전역 정적 상태 사용 (테스트 격리 곤란)
- `async void` (이벤트 핸들러 제외)

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- 빌드 환경: <Windows / Linux / macOS>
- CI/CD: <GitHub Actions / Azure DevOps 등 — 있으면 명시>
- 배포: <NuGet / Docker / MSIX 등 — 해당 시>
