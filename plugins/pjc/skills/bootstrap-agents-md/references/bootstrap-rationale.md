# bootstrap-agents-md — 근거

> `SKILL.md`가 「왜」를 묻지 않고 절차만 담도록 여기로 내렸다. 스킬을 고칠 때만 연다.

## §1 `CLAUDE.md`가 있어도 종료하지 않는 이유

두 파일은 역할이 다르다 — `CLAUDE.md`는 Claude 전용이고 `AGENTS.md`는 다른 에이전트(Codex·Gemini 등)도 읽는 공용 가이드다. 환경에 따라 `CLAUDE.md`가 전역 `.gitignore` 대상이라 **커밋조차 안 되는** 경우가 있다(실측 1건).

종전처럼 `CLAUDE.md`가 있다고 종료하면 **그 프로젝트는 `AGENTS.md`를 영영 만들 수 없다** — hook이 직접 Write를 막고 이 스킬이 유일 경로이기 때문이다. 그러면 가이드가 한 PC에만 남는다. 실제로 LLM WIKI vault에서 이 봉쇄가 관측됐다(v1.190.0).

## §2 아키텍처를 감지로 채우지 않고 묻는 이유

종전 템플릿은 stack만 보고 「DDD + Clean」을 값으로 박았다. 그래서 도메인 규칙이 얇은 CRUD 앱도 `AGENTS.md`에는 DDD라고 적혔고, 실제 코드는 트랜잭션 스크립트인데 **선언만 DDD인 상태**가 됐다 — 리뷰어도 사람도 "지켜지고 있다"고 착각한다.

**없는 레이어를 강요하는 것은 그 자체가 과한 추상화다.** 그래서 값을 박지 않고 ① 구조로 근거를 만들고 ② 후보를 제시해 고르게 하고 ③ 답이 없으면 빈 칸으로 둔다.

## §3 스택 고유 규칙을 `AGENTS.md`에 넣지 않는 이유

v1.226.0(회차 3)에서 스택 템플릿 11파일을 폐기하며 함께 판정한 것이다.

폐기 전 템플릿 11종 중 **6종**(`dotnet`·`generic`·`go`·`node-typescript`·`python`·`rust`)은 `AGENTS-BOUNDARY.md` 표와 절 구성이 정확히 같았다. 나머지 **5종에만 고유 절 12개**가 있었다:

| 템플릿 | 고유 절 |
|---|---|
| `winui3` | 프로젝트 생성/실행 필수 규칙 · 디자인 규칙(WinUI Gallery) · XAML 작성 규칙 · 다국어 규칙 |
| `android` | 검증·테스트 Android CLI · Windows 에뮬레이터 워크플로 · Android Skills · UI/UX · Adaptive Apps |
| `wpf` · `maui` | UI/UX (각 1절) |
| `multi-stack-example` | Skills & Agents · Pointers |

**이 12절은 `AGENTS-BOUNDARY.md` 표가 「위키」 행으로 분류한 범주다** — *"아키텍처 상세와 온보딩 · 크로스 세션 작업 규약·함정"*. XAML 작성 규칙이나 에뮬레이터 워크플로는 매 세션 예외 없이 필요한 것이 아니라 **그 작업을 할 때만** 필요하고, 계속 누적되며, 코드를 읽으면 복구된다. 애초에 `AGENTS.md`에 둘 것이 아니었다.

그래서 스택 고유 규칙이 필요하면 **위키 `conventions.md`**에 쓰고 `AGENTS.md`에는 두지 않는다. 이것이 `AGENTS.md` 자동 증가(실측 하루 평균 +170B로 2주에 이관 3회)를 억제하는 축이기도 하다.

## §4 표식 감지 규칙 3개의 근거

- **깊이 3 + 제외 디렉터리** — 표식이 루트가 아니라 `src/`·모듈 폴더에 있는 프로젝트가 흔하다. 그런데 제외 없이 재귀하면 하위 `node_modules`의 `package.json`이 stack으로 잡힌다.
- **Gradle 파일만으로 Android로 판정 금지** — `AndroidManifest.xml`도 `com.android.*` 플러그인도 없는 순수 JVM Gradle 프로젝트(Spring Boot 등)를 Android로 오탐한다.
- **Case B 표식을 Step 2에서 함께 탐색** — 이 단계에서 안 찾으면 Case B 분기가 도달 불가가 된다(분기는 있는데 그리로 가는 입력이 없다).

## §5 위키 등록을 이 스킬이 하지 않는 이유

등록은 `pjc:plan` Step 1 소관이다. 여기서 등록까지 하면 두 스킬 사이에 순서 의존이 생겨, `bootstrap`을 단독 호출했을 때와 `plan` 경유로 호출했을 때 결과가 달라진다.

vault가 없을 때 `## 위키` 절을 통째로 빼는 이유는 **없는 곳을 가리키는 포인터가 다음 세션을 헤매게 하기 때문**이다. 빈 절을 남기는 것보다 없는 편이 낫다.
