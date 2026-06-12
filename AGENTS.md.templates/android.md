# AGENTS.md — Agent Guide

> Android (Kotlin/Jetpack Compose 또는 Java) 프로젝트용 가이드.

## Stack
- **언어**: Kotlin <version> (또는 Java)
- **UI**: Jetpack Compose / View XML
- **최소 SDK / 타겟 SDK**: <minSdk> / <targetSdk>
- **주요 라이브러리**: Hilt, Room, Retrofit, Coroutines/Flow 등 (실제 사용 명시)

## Build & Test
- **Build (debug)**: `./gradlew assembleDebug` (Windows: `.\gradlew.bat assembleDebug`)
- **Build (release)**: `./gradlew assembleRelease`
- **Test (unit)**: `./gradlew test`
- **Test (instrumented)**: `./gradlew connectedAndroidTest`
- **Lint**: `./gradlew lint`
- **Clean**: `./gradlew clean`

## Repository Structure

```
<repo>/
├── app/
│   ├── src/main/
│   │   ├── java/<package>/
│   │   │   ├── domain/        # 비즈니스 로직
│   │   │   ├── data/          # Repository, DTO, API
│   │   │   ├── ui/            # Composable, ViewModel
│   │   │   └── di/            # Hilt 모듈
│   │   ├── res/               # strings, drawables, layouts
│   │   └── AndroidManifest.xml
│   ├── src/test/              # JVM 단위 테스트
│   └── src/androidTest/       # Instrumented 테스트
├── build.gradle.kts (또는 build.gradle)
└── settings.gradle.kts
```

## Conventions
- **아키텍처**: MVVM + Clean Architecture. UI → Domain ← Data.
- **DI**: Hilt (`@HiltAndroidApp`, `@HiltViewModel`, `@Module`)
- **상태 관리**: `StateFlow` 또는 `LiveData` (Compose는 `StateFlow` 권장)
- **비동기**: Coroutines + Flow. `runBlocking` 금지 (테스트 제외)
- **테스트**: Domain·Data는 JVM 단위, UI는 Compose Test 또는 Espresso
- **리소스**: 문자열은 `strings.xml`, 색상은 `colors.xml` (하드코딩 금지)
- **파일**: 1500라인 내외, UTF-8, 주석은 한글

## DO NOT
- `gradle.properties`, `keystore`, `google-services.json` 커밋
- `.idea/`, `build/`, `*.iml` 커밋 (gitignore에 포함)
- 메인 스레드에서 I/O (네트워크/DB)
- `GlobalScope` 사용 (테스트 격리·생명주기 관리 곤란)
- View binding 없이 `findViewById` 직접 호출 (legacy 코드 제외)

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- JDK: <17 등>
- Android Studio 버전: <Iguana, Koala 등 — 권장 명시>
- CI/CD: <GitHub Actions, Bitrise 등>
- 배포: <Play Console, Internal Distribution 등>

> ⚠️ `pjc:add-viewmodel` skill은 WinUI 3 전용입니다. Android Jetpack ViewModel은 비대상이므로 직접 작성하거나 별도 skill을 사용하세요.
