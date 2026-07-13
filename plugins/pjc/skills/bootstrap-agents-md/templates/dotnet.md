# AGENTS.md — Agent Guide

> .NET (C#, F#, VB) 프로젝트용 가이드. Claude Code의 모든 작업은 이 문서를 우선 따른다.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.


## Stack
- **언어**: C# / .NET <version>
- **주요 패키지**: <CommunityToolkit.Mvvm, MediatR, EF Core 등 — 실제로 사용하는 것 명시>
- **테스트**: <xUnit | NUnit | MSTest>

## Build & Test
- **Build**: `dotnet build src/<Sln 또는 Project>.sln`
- **Test**: `dotnet test src/<Sln>.sln` 또는 테스트 프로젝트 단일 지정 (`tests/` 디렉터리 지정은 테스트 프로젝트가 2개 이상이면 MSB1011로 실패 — 아래 구조처럼 3개면 반드시 솔루션 단위)
- **Lint/Format**: `dotnet format`
- **Watch (개발)**: `dotnet watch run --project src/<Main>`

## 데이터 접근
- **DB/스토어**: <예: SQL Server / PostgreSQL / SQLite / 없음>
- **ORM/접속**: <EF Core / Dapper 등 — 연결 정보는 환경변수·secrets로, 실제 값 금지 (예: `ConnectionStrings__Default`)>
- **마이그레이션**: <예: `dotnet ef migrations add <Name>` / `dotnet ef database update`>
- **시드/조회**: <개발용 데이터 확인 방법>

> ⚠️ 실제 연결문자열·계정·비밀번호는 적지 않는다(환경변수 이름만). DB가 없으면 "없음".

## Repository Structure

> 아래는 **DDD/Clean을 택했을 때**의 구조다. 계층형을 택했으면 이 트리를 그대로 두지 말고 실제 구조로 바꾼다(예: `src/<App>/` 단일 프로젝트 + `Services/`·`Data/` 폴더). **선택한 아키텍처에 맞게 조정하세요.**

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

## 산출물·파일 관리
- **빌드 산출물**: `bin/` · `obj/` (gitignore)
- **런타임 생성물**: <로그·리포트·게시 출력(`publish/`) 등 경로>
- **임시/캐시**: `obj/` · `TestResults/`

## Conventions
- **아키텍처**: `<DDD + Clean | 계층형(트랜잭션 스크립트) | 기타 — 하나만 남기세요>`
  - **DDD + Clean** — 의존 방향: UI → Application → Domain ← Infrastructure. 도메인 규칙(검증·상태 전이·계산)이 두터울 때. 엔티티에 행위를 두고 애그리게이트 경계를 잡는다.
  - **계층형(트랜잭션 스크립트)** — 서비스가 절차를 순서대로 실행. 규칙이 얇은 CRUD·조회 위주 앱에 **정당한 선택**이다. 로직이 없는데 레이어만 4개로 나누면 그 자체가 과한 추상화다.
  - ⚠️ **실제 구조와 다르게 적지 마세요.** 선언만 DDD면(엔티티는 프로퍼티뿐, 로직은 전부 서비스) 리뷰어도 사람도 "지켜지고 있다"고 착각합니다 — 없느니만 못합니다.
- **MVVM (WinUI 3/WPF/MAUI)**: ViewModel은 `CommunityToolkit.Mvvm`의 `[ObservableProperty]` / `[RelayCommand]` 사용
- **DI**: `Microsoft.Extensions.DependencyInjection`. 모든 서비스는 인터페이스 통한 등록.
- **에러 처리**: `Result<T>` 패턴 권장 (또는 명시된 예외 정책)
- **비동기**: `async`/`await` 일관성. `.Result`, `.Wait()` 금지.
- **테스트**: 단위 테스트는 Domain/Application, 통합은 Infrastructure 별도
- **파일**: 1500라인 내외, UTF-8 (BOM 없음, `.ps1`만 BOM — Windows PowerShell 5.1 호환), 주석은 한글 ("왜"만 설명)

## DO NOT
- `secrets.json`, `appsettings.Development.json`의 실제 credential 커밋
- `bin/`, `obj/` 커밋 (gitignore에 포함)
- 전역 정적 상태 사용 (테스트 격리 곤란)
- `async void` (이벤트 핸들러 제외)
- 코드·문서·notes·plan 등 어떤 파일에도 실제 IP·계정·비밀번호·토큰·DB 연결문자열 기록 (환경변수 이름만 적고 값은 .env로)
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass` (백신이 공격 도구로 오인해 격리할 수 있음)

## Plan Location

```
Plan Location: <plan.md | docs/plans/>   ← 하나만 남기세요
PRD Location:  docs/prd.md (대규모 작업 시. 누적은 docs/prds/<YYYY-MM-DD>-<slug>.md)
```

- `plan.md` = 단일 파일 덮어쓰기(작은 프로젝트) / `docs/plans/` = `<YYYY-MM-DD>-<slug>.md` 날짜별 누적(히스토리 보존)
- 미설정 시 기본: `docs/plans/`가 이미 있으면 그것, 없으면 `plan.md`

## 추가 정보
- 빌드 환경: <Windows / Linux / macOS>
- CI/CD: <GitHub Actions / Azure DevOps 등 — 있으면 명시>
- 배포: <NuGet / Docker / MSIX 등 — 해당 시>
