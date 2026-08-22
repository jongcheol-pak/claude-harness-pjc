# AGENTS.md — Agent Guide (Android)

> Android (Kotlin/Jetpack Compose 또는 Java) 프로젝트용 가이드. Claude Code의 모든 작업은 이 문서를 우선 따른다.
>
> **이 템플릿은 그대로 써도 동작합니다.** 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고 고유 규칙을 추가하면 Claude가 추측을 줄여 더 정확하게 작업합니다. 빌드·테스트 명령만 채워 시작하고 점진적으로 다듬는 것을 권장합니다.

## 위키

- **프로젝트 페이지**: `20_projects/<personal|work>/<프로젝트명>.md` (LLM WIKI vault)
- 프로젝트 성격·기술 스택·디렉터리 구조·아키텍처·기능 목록은 **위키가 정본**이다. 이 파일에 중복 기재하지 않는다.
- 위키에 등록되면 이 경로가 채워진다(등록은 `pjc:plan-feature` Step 1 소관).

## 검증·테스트 — Android CLI 우선

가능하면 **Android CLI(`android` 명령)** 로 빌드·실행·테스트를 검증한다. Gradle 직접 호출은 fallback.
설치 확인: `which android` 또는 `command -v android` (경로 반환 시 설치됨). 없으면 https://developer.android.com/tools/agents 에서 설치.

| 작업 | Android CLI | Gradle fallback |
|---|---|---|
| 프로젝트 생성 | `android create -o <dir> <template>` (`android create list`로 템플릿 확인) | — |
| 빌드 산출물 경로 파악 | `android describe --project_dir=<dir>` (APK 경로 JSON) | — |
| 앱 배포 | `android run --apks=<apk-path>` | `adb install` |
| UI 테스트 | `android` Journeys (https://developer.android.com/tools/agents/android-cli/journeys) | `connectedAndroidTest` |
| 단위 테스트 | (Gradle) | `.\gradlew.bat test` |
| 의존성 최신 버전 | `android studio version-lookup <artifact...>` | — |
| 문서 검색 | `android docs search '<질문>'` → `android docs fetch kb://...` | — |
| 화면 캡처/검증 | `android screen capture`, `android layout` | — |

**빌드(권장)**: 단위 테스트는 Gradle, 빌드·배포·UI 검증은 Android CLI.
- 단위 테스트: `.\gradlew.bat test`
- 빌드: `.\gradlew.bat assembleDebug` → `android describe`로 APK 경로 확인 → `android run --apks=<경로>`
- Lint: `.\gradlew.bat lint`

> ⚠️ **Windows 제약**: Android CLI의 `android emulator` 서브명령만 Windows에서 비활성. 에뮬레이터 자체는 SDK의 `emulator.exe`로 정상 실행한다. 아래 "Windows 에뮬레이터 워크플로" 참조.

## Windows 에뮬레이터 워크플로 (검증됨)

PowerShell 기준, `android emulator` 대신 SDK의 `emulator.exe` + `adb`를 직접 쓴다.

**0. 환경변수 (세션당 1회)**
```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_SDK_ROOT = "C:\Users\<user>\AppData\Local\Android\Sdk"
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_SDK_ROOT\platform-tools;$env:Path"
$adb = "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"   # adb는 절대경로 호출 권장
```

**1. 에뮬레이터 부팅** (`android emulator`가 아니라 `emulator.exe` 직접)
```powershell
& "$env:ANDROID_SDK_ROOT\emulator\emulator.exe" -list-avds          # AVD 목록
Start-Process -FilePath "$env:ANDROID_SDK_ROOT\emulator\emulator.exe" -ArgumentList '-avd','<AVD명>'
```

**2. 부팅 완료 대기**
```powershell
& $adb wait-for-device
& $adb -s emulator-5554 shell getprop sys.boot_completed   # 1 될 때까지 폴링
& $adb devices                                             # emulator-5554  device 확인
```

**3. 빌드 (Gradle — 빌드만)**
```powershell
.\gradlew.bat assembleDebug
```

**4. 배포·실행** — Android CLI 우선, 세밀 제어는 adb
```powershell
# Android CLI (우선)
android run --apks="app\build\outputs\apk\debug\app-debug.apk" --device=emulator-5554

# 재설치·강제종료·데이터 초기화 등은 adb 직접
& $adb -s emulator-5554 install -r "app\build\outputs\apk\debug\app-debug.apk"
& $adb -s emulator-5554 shell am force-stop <package>
& $adb -s emulator-5554 shell pm clear <package>
& $adb -s emulator-5554 shell am start -n "<package>/.MainActivity"
```

**5. 권한 부여** (런타임 권한 테스트)
```powershell
& $adb -s emulator-5554 shell pm grant <package> android.permission.ACCESS_FINE_LOCATION
# COARSE_LOCATION / ACTIVITY_RECOGNITION / POST_NOTIFICATIONS 등 동일
```

**6. 화면 캡처**
```powershell
android screen capture --output="docs\screenshots\<name>.png"     # Android CLI
# 또는 adb (대용량은 리사이즈 후 확인)
& $adb -s emulator-5554 shell screencap -p /sdcard/s.png
& $adb -s emulator-5554 pull /sdcard/s.png "docs\screenshots\<name>.png"
```

**7. UI 입력 (동선 자동화)**
```powershell
& $adb -s emulator-5554 shell input tap 540 1790                  # 탭
& $adb -s emulator-5554 shell input swipe 540 1800 540 700 400    # 스와이프(스크롤)
```

> 좌표 기반 input은 화면 해상도에 의존적이다. `android screen capture --annotate` + `android screen resolve`로 요소 좌표를 얻으면 더 안정적이다.

## Android Skills — 작업 전 확인·설치

Android 공식 skill(agentskills.io 오픈 표준, repo: github.com/android/skills)을 활용한다.
**작업에 맞는 skill이 있으면 설치 여부를 확인하고, 없거나 오래됐으면 사용자 승인 후 설치·업데이트한다.**

절차:
1. `android skills list --long` 으로 설치된 skill + 버전 확인
2. 작업 관련 skill 검색: `android skills find '<키워드>'` (예: `performance`, `compose`, `navigation`)
3. 필요한 skill이 미설치/구버전이면 → **사용자에게 "skill X 설치/업데이트할까요?" 확인** → 승인 시 `android skills add --skill=<name>` (전체는 `--all`)
4. 커스텀 수정한 skill은 이름을 바꿔 둔다 (`skills add`가 덮어쓰므로)

대표 공식 skill: `migrate-xml-views-to-jetpack-compose`, `agp-9-upgrade`, `navigation-3`, `r8-analyzer`(성능), `play-billing-library-version-upgrade`, `edge-to-edge`.
관련 작업(예: Compose 마이그레이션, AGP 업그레이드, 성능 최적화) 시 해당 skill을 우선 적용한다.

## UI/UX — 시안 우선, 미제공 시 공식 가이드 준수

**사용자가 UI/UX 시안(디자인 HTML·이미지·Figma 등)을 제공하면 시안이 기준이다.** 아래 공식 가이드는 시안이 정하지 않은 부분(접근성·적응형 대응 등)에만 적용한다. **Material에 비슷한 표준 패턴이 있다는 이유로 시안의 레이아웃·구성 요소를 표준 컴포넌트로 대체하지 않는다.**

시안을 제공하지 않거나 별도 디자인 요청이 없으면 **Android 공식 디자인 가이드대로 진행**한다 (자체 디자인 임의 창작 금지):
- Material 3 (Material You) 디자인 시스템
- 공식 UI 가이드: https://developer.android.com/design/ui/mobile
- 접근성: 터치 타깃 48dp+, contentDescription, 동적 글꼴 대응
- `android docs search`로 공식 패턴 확인 후 적용

## Adaptive Apps — 적응형 우선

가능하면 **적응형 앱(adaptive app)** 으로 구축한다 (https://developer.android.com/adaptive-apps):
- 단일 화면 고정 레이아웃이 아니라 폰/태블릿/폴더블/데스크톱/ChromeOS에서 창 크기에 적응
- `WindowSizeClass`(Compact/Medium/Expanded)로 분기, 고정 dp 폭 가정 금지
- 리스트-디테일 등은 `ListDetailPaneScaffold` 등 적응형 레이아웃 사용
- 회전·창 크기 변경·접힘 상태에서 상태 보존
- 단, 사용자가 "폰 전용" 등 명시하면 그 범위를 따른다

## 산출물·파일 관리
- **빌드 산출물**: `build/` · `app/build/` (APK: `app/build/outputs/apk/`, gitignore)
- **임시/캐시**: `.gradle/` · `.idea/` · `local.properties`
- **런타임 생성물**: <로그·스크린샷 경로 — 예: `docs/screenshots/`>

## 데이터 접근
- **DB/스토어**: <예: Room(SQLite) / DataStore / 없음>
- **접속**: <원격 API·DB 연결 정보는 BuildConfig + gradle.properties(비커밋)·환경변수로 — 실제 값 금지>

## Conventions
- **아키텍처**: MVVM(UI 패턴, 고정) + `<Clean Architecture | 계층형(단순 Repository) | 기타 — 하나만 남기세요>`
  - **Clean Architecture** — UI → Domain ← Data. UseCase·도메인 모델을 두고 규칙을 Domain에 모은다. 도메인 규칙이 두터울 때.
  - **계층형(단순 Repository)** — ViewModel → Repository → 데이터소스. 규칙이 얇은 CRUD·조회 앱에 **정당한 선택**이다. UseCase가 Repository를 한 줄 위임만 한다면 그 레이어는 비용만 남는다.
  - ⚠️ **실제 구조와 다르게 적지 마세요.** 선언만 Clean이면 리뷰어도 사람도 "지켜지고 있다"고 착각합니다.
- **DI**: Hilt (`@HiltAndroidApp`, `@HiltViewModel`, `@Module`)
- **상태 관리**: `StateFlow` (Compose 권장) 또는 `LiveData`
- **비동기**: Coroutines + Flow. `runBlocking` 금지 (테스트 제외)
- **테스트**: Domain·Data는 JVM 단위, UI는 Compose Test 또는 Journeys
- **리소스**: 문자열은 `strings.xml`, 색상은 `colors.xml` (하드코딩 금지)
- **적응형**: 고정 폭 가정 금지, `WindowSizeClass` 기준 분기
- **파일**: 단일 책임 유지(분할은 줄 수가 아니라 책임·읽기 부담으로 판정), UTF-8, 주석은 한글

## DO NOT
- `gradle.properties`(민감), `keystore`, `google-services.json` 커밋
- `.idea/`, `build/`, `*.iml` 커밋 (gitignore에 포함)
- 메인 스레드에서 I/O (네트워크/DB)
- `GlobalScope` 사용 (생명주기 관리 곤란)
- 고정 화면 폭 가정 (적응형 위반)
- Windows에서 `android emulator` 서브명령 사용 시도 (비활성 — `emulator.exe` 직접 호출)
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
- JDK: <17 등>
- Android Studio 버전: <Iguana, Koala 등 — 권장 명시>
- CI/CD: <GitHub Actions, Bitrise 등>
- 배포: <Play Console, Internal Distribution 등>

> ⚠️ `pjc:add-viewmodel` skill은 CommunityToolkit.Mvvm 기반의 WinUI 3 / WPF / MAUI 대상입니다. **Android Jetpack ViewModel은 비대상**이므로 직접 작성하거나 Android 공식 skill을 사용하세요.
