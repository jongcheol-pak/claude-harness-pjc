---
name: add-viewmodel
description: This skill should be used when the user requests adding a new screen, dialog, page, window, or any UI component that needs a ViewModel in a WinUI 3 / WPF / MAUI project using CommunityToolkit.Mvvm. Triggers on phrases like "ViewModel 추가", "새 화면", "다이얼로그 추가", "페이지 만들기", "add screen/page/dialog/window". 화면이 앱 전역 상태(테마·언어·환경설정)를 다루더라도 요청 단위가 화면 하나면 이 스킬이며, 그 이유로 `pjc:plan`에 넘기지 않는다 — 전역 기능이 들어간다는 것은 화면의 내용이지 요청 규모가 아니다. Generates ViewModel + View skeleton with proper MVVM bindings and DI registration. Do NOT trigger for non-XAML stacks (React/web, ASP.NET WebAPI controllers), simple UI text/label/style tweaks on an existing view, or debugging an existing ViewModel (use pjc-systematic-debugging). Android Jetpack ViewModel is out of scope.
argument-hint: "<화면 이름 또는 목적>"
---

# Add ViewModel

WinUI 3 / WPF / MAUI 프로젝트에 MVVM 패턴(`CommunityToolkit.Mvvm`)으로
View + ViewModel 스켈레톤을 추가한다.

## 호출 흐름

`pjc:implement`가 plan의 task에서 자동 호출하거나 사용자가 `/pjc:add-viewmodel`로 직접 호출한다. 직접 호출은 `guard-write` hook의 plan 게이트에 걸릴 수 있어 `$env:CLAUDE_HARNESS_QUICK = '1'`이 필요하다(커밋 시크릿 차단은 이 변수로 뚫리지 않는다 — `CLAUDE_HARNESS_ALLOW_SECRET`이 전용이다).

**책임 범위**는 ViewModel/View boilerplate · DI 등록 · 기본 테스트 스켈레톤까지다. 비즈니스 로직·바인딩 상세·통합 검증은 `pjc:implement`가 담당한다. **Android의 Jetpack ViewModel은 비대상**이다.

## 사전 조건

이 skill을 호출하기 전에 `pjc:plan`로 다음이 결정되어 있어야 한다:

- 화면 이름 (예: `Settings`, `UserDetail`)
- 화면 종류 (Page / Window / UserControl / ContentDialog)
- 위치 (어느 모듈/프로젝트)
- 상위 네비게이션과의 연결 방식
- 필요한 의존성 서비스 (있다면)

위 정보가 없으면 사용자에게 묻거나 `pjc:plan`로 복귀.

## 절대 규칙

1. **AGENTS.md 우선.** 다른 패턴(ReactiveUI, MVVM Light 등)을 **명시**했다면 이 skill 을 쓰지 않는다 — 이 skill 의 단계가 `CommunityToolkit.Mvvm` 생성기를 전제해 다른 베이스에서는 컴파일되지 않는다. **`pjc:implement` 안에서는 멈추지 말고 그 프로젝트 패턴으로 직접 작성한다**(루프가 정지한다).
2. **DDD 준수.** ViewModel 은 UI 레이어이고 비즈니스 로직은 Domain 서비스를 호출하기만 한다 — **판정 축은 「화면이 없어도 성립하는가」** — 입력 형식은 화면 것, 금액 한도는 도메인 것이며, 규칙이 VM 에 있으면 화면을 더 만들 때 복제된다.
3. **DI 등록 누락 금지.** ViewModel 은 반드시 컨테이너에 등록 — 빌드는 통과하고 **화면을 여는 순간 해석 실패로 죽는다** — 판정은 **진입점에서 실제로 호출되는가**다(이름은 프로젝트마다 다르다).
4. **한글 주석**(XML doc 포함) — 이 하니스의 산출물을 읽는 것은 한국어 세션이고, 언어가 섞이면 grep 대상이 갈린다.
5. **인코딩은 대상 프로젝트 관례를 따른다** — `.cs` 는 Visual Studio 기본이 **BOM 포함**이라 이 하니스의 `.md` 관례를 적용하면 기존 파일과 갈린다(판정은 같은 폴더의 기존 파일).
6. **WinUI 3 프로젝트면 그 프로젝트의 디자인·다국어 규칙을 따른다.** 정본은 위키 `conventions.md`(스택 고유 규약의 자리)이고, 레포에 `docs/WINUI3-DESIGN-GUIDE.md` 같은 상세 문서가 있으면 함께 본다 — **어디에도 없으면 규약이 없는 것으로 보고 넘어간다**(다국어를 쓰지 않는 앱에 리소스 분리를 강요하면 과잉이다).

## 실행 단계

> **코드 형태는 Step 1에서 읽은 기존 ViewModel 을 따른다** — 그 코드가 정본이다.

### Step 1. 컨텍스트 파악

다음을 확인:
- 기존 ViewModel 위치 (예: `src/*/ViewModels/`)
- 기존 View 위치 (예: `src/*/Views/`)
- DI 등록 진입점 (보통 `App.xaml.cs` 또는 `Program.cs`의 `ConfigureServices`)
- 네비게이션 서비스 패턴 (`INavigationService` 등 존재 여부)
- 기존 ViewModel·View 각 한 개를 읽어 컨벤션 파악 (네이밍, 베이스 클래스, 주석 스타일, 바인딩 문법)
- **`CommunityToolkit.Mvvm` PackageReference 존재 확인**(csproj grep) — 없으면 **Halt**(아래 Halt 조건이 정본: 의존성 추가는 승인 필요이므로 임의 추가·컴파일 불가 코드 생성 금지).

### Step 2. ViewModel 생성

`src/<Project>/ViewModels/<Name>ViewModel.cs` 에 만든다.

### Step 3. View 생성

**View 베이스 타입은 사전 조건의 화면 종류를 따른다** — `src/<Project>/Views/<Name><종류>.xaml` 과 코드비하인드를 만들고(`<Name>Page.xaml` · `<Name>ContentDialog.xaml` — 그 프로젝트에 축약 관례가 있으면 따른다), **WinUI 3·WPF·MAUI 는 바인딩 문법이 달라 기존 View 를 따른다**.

> **`Page` 가 아니면 Step 4·5 가 갈린다** — `ContentDialog`·`Window` 는 프레임이 꽂아 줄 자리가 없어 **View 자체를 컨테이너에 등록**하고 Step 5 대신 호출부에서 직접 띄운다. `UserControl` 은 **부모 View 가 `DataContext` 로 주입**하므로 **View 등록도 직접 띄우기도 하지 않는다**(ViewModel 등록은 절대 규칙 3 대로 그대로 한다).

### Step 4. DI 등록

`App.xaml.cs`(또는 `Program.cs`)의 `ConfigureServices` 에 ViewModel 을 등록한다 — **View 는 View DI 를 쓰는 프로젝트에서만** 함께 등록한다 — 종류별 판정은 Step 3 의 단서가 정본이다(`ContentDialog`·`Window` 는 등록 대상 · `UserControl` 은 제외).

> **수명**: 일반적으로 ViewModel은 `Transient`. 앱 전체에서 상태를 유지해야 하면 `Singleton` 검토.

### Step 5. 네비게이션 연결 (`Page` 인 경우)

기존 네비게이션 패턴에 따라:
- `Frame.Navigate(typeof(<Name>Page))`
- `INavigationService.NavigateTo("<Name>")`
- 메뉴/사이드바에 항목 추가

이 단계는 **plan.md에 명시된 진입점**에 따라 진행. 추측 금지.

### Step 6. 테스트 스캐폴드

`tests/<Project>.Tests/ViewModels/<Name>ViewModelTests.cs` 에 만든다.

### Step 7. 검증

다음을 모두 통과해야 완료:
- [ ] 빌드 성공
- [ ] 단위 테스트 통과 (최소 초기 로딩 커맨드 1건 — 이름은 기존 ViewModel 컨벤션을 따른다)
- [ ] DI 등록 누락 없음 — 그 프로젝트의 해석 경로로 확인한다(`App.GetService<T>()` · 생성자 주입 · `IPageFactory` 등)
- [ ] 네비게이션 진입 시 정상 표시 (가능하면 수동 확인)

## 안티패턴 (금지)

| 안티패턴 | 올바른 행동 | 왜 |
|---|---|---|
| `INotifyPropertyChanged` 수동 구현 | `[ObservableProperty]` 사용 | 알림 누락이 컴파일에 안 걸려 화면이 조용히 갱신되지 않는다(**기존 코드가 수동 구현으로 통일돼 있으면 절대 규칙 1이 우선**) |
| `ICommand`를 수동 구현 | `[RelayCommand]` 사용 | 위와 같은 축 — `CanExecute` 변경 통지를 손으로 관리하게 된다 |
| ViewModel에서 `MessageBox` 직접 호출 | `IDialogService` 등으로 추상화 | UI 스레드와 창 핸들에 묶여 **VM 단위 테스트가 창을 띄운다** |
| ViewModel에서 `HttpClient` 직접 사용 | Domain/Application 서비스 경유 | **VM 단위 테스트가 네트워크에 묶인다** — 규칙 2는 「비즈니스 로직」의 귀속을 정하지만 표시용 데이터를 직접 가져오는 것은 그 축에 안 걸린다 |
| 코드비하인드에 비즈니스 로직 작성 | ViewModel로 이동 | 코드비하인드는 View 수명에 묶여 테스트에서 인스턴스화할 수 없다 |
| 동기 `Wait()`, `.Result` 호출 | `async/await` | **UI 스레드에서 즉시 데드락** — 생성자라 `await` 을 못 쓰는 경우도 예외가 아니고 아래 `Loaded`·커맨드로 옮긴다 |
| `LoadAsync`를 생성자에서 직접 호출 | `Loaded` 이벤트 또는 명시적 커맨드 | 생성자는 예외를 돌려줄 자리가 없어 실패가 DI 해석 실패로 나타난다 |

> 여기서 뺀 행: `new ViewModel()` 금지·영문 XML doc 금지는 절대 규칙 3·4가 정본이다. **`HttpClient` 행은 뺐다가 되살렸다** — 규칙 2의 축(비즈니스 로직 귀속)과 달라 중복이 아니었다(회차 6 완료 리뷰).

## Halt 조건

다음 발견 시 사용자에게 보고하고 중지:

- 기존 ViewModel 이 다른 베이스 클래스(`BindableBase`·`ReactiveObject` 등)를 쓰고 있음 — **절대 규칙 1과 발화 조건이 다르다** — 그쪽은 AGENTS.md 가 **명시**했을 때, 이쪽은 **코드에서 관측**됐을 때이며 어느 쪽을 따라도 절반과 어긋나므로 사용자가 정한다
- DI 컨테이너가 없거나 **관례 없는 전역 Service Locator를 남용**하고 있음(제3자 로케이터 라이브러리·전역 정적 컨테이너를 여기저기서 직접 뒤지는 형태). **`App.GetService<T>()` 같은 프로젝트 관례의 정적 헬퍼는 남용이 아니다** — 절대 규칙 3의 「진입점에서 등록이 호출되는가」를 확인할 자리가 없으면 누락을 판정할 수 없다
- 네비게이션 패턴이 plan.md 에 없고 코드베이스에도 단일 패턴이 없음 — 추측해 붙이면 **화면이 어디서도 도달되지 않는 채 완료 보고된다** — 단일 패턴이 코드에 있으면 그것을 따르고 멈추지 않는다
- View 가 코드 생성기로 만들어지는 경우(`*.Generated.*`) — 손으로 고쳐도 다음 생성에서 덮인다 — 고칠 자리는 생성기 입력이다
- **`CommunityToolkit.Mvvm` 패키지가 프로젝트에 없음** — `[ObservableProperty]`·`[RelayCommand]`·`ObservableObject`가 컴파일되지 않는다. 의존성 추가는 승인 필요이므로 임의로 추가하지 말고 사용자에게 확인(또는 plan에 패키지 추가를 명시)
