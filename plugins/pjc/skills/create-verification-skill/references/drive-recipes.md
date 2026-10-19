# 조작 방식 (생성할 검증 스킬의 Launch·Drive·Evidence·Cleanup)

> `../SKILL.md` 1·2단계가 레포에 쓸 하네스가 없을 때 읽는다. **레포에 이미 있는 하네스가 언제나 먼저다** — 여기는 그것이 없을 때의 일반 방식이다. 출처는 pstack create-verification-skill 의 Drive 항목(브라우저/CDP · tmux/PTY · HTTP)이고, Windows 데스크톱은 pjc 가 더했다.

## 목차

- 웹 · Electron
- CLI · TUI
- 서비스 (HTTP)
- Windows 데스크톱 (WinUI · WPF · WinForms · gpui 등)

## 웹 · Electron

- **하네스** — 레포의 Playwright·Cypress 설정과 스펙이 있으면 그 러너와 셀렉터를 쓴다. 없으면 브라우저 자동화(Playwright CLI·CDP 디버그 포트)를 쓴다. Electron 은 `--remote-debugging-port=<포트>` 로 띄워 같은 방식으로 붙는다.
- **Launch** — 개발 서버 명령과 포트를 고정한다. 준비 판정은 HTTP 응답이 아니라 **첫 화면의 기대 요소가 보이는가**다.
- **Drive** — ARIA 역할·접근 가능한 이름 → `data-testid` 류 속성 → CSS 순으로 고른다. DOM 위치·좌표는 쓰지 않는다.
- **Evidence** — 조작 전후의 접근성 스냅샷 + 앱 이름이 보이는 스크린샷 + 콘솔 오류 + 저장된 값을 다른 화면에서 다시 읽은 결과.
- **Cleanup** — 띄운 개발 서버·브라우저 프로세스(PID)와 임시 프로필 폴더.
- **함정** — 개발 서버의 HMR 이 조작 도중 화면을 갈아 끼운다. 사용자가 쓰는 브라우저 프로필로 붙지 않는다(남의 세션을 조작한다).

## CLI · TUI

- **하네스** — 레포의 expect·PTY 테스트 도우미가 있으면 그것.
- **비대화형 명령** — 프로세스를 직접 띄워 표준 입력을 주고 표준 출력·표준 오류·종료 코드를 남긴다. 조작마다 새 프로세스이고 격리된 작업 폴더를 준다.
- **대화형 TUI** — 레포 하네스를 먼저 찾는다. 없으면 tmux 세션(`tmux new -d -s <id>` → `send-keys` → `capture-pane -p`)을 쓴다. **Windows 의 Git Bash 에는 tmux 가 없다** — 그 환경이면 비대화 모드·파이프 입력 옵션이 있는지 레포에서 찾고, 없으면 그 경로를 지도에 `verified-unreachable` 로 적는다.
- **Evidence** — 명령 · 표준 출력 · 표준 오류 · 종료 코드 · TUI 면 조작 전후 화면 캡처 텍스트.
- **Cleanup** — 만든 세션·임시 폴더. 증거 파일은 남긴다.
- **함정** — 색상 코드가 출력 비교를 깬다(`NO_COLOR=1` 등 레포가 지원하는 끄기 수단). 터미널 폭이 출력 줄바꿈을 바꾼다 — 세션 크기를 고정한다.

## 서비스 (HTTP)

- **하네스** — 레포의 API 테스트·`.http` 파일·Postman 컬렉션이 있으면 그 요청을 쓴다.
- **Drive** — `curl`(Git Bash) 또는 `Invoke-WebRequest`(PowerShell). 요청마다 메서드·경로·본문·헤더(인증 값은 환경변수 이름으로만)를 적는다.
- **Evidence** — 요청 · 상태 코드 · 응답 본문 · 바뀐 저장 상태를 읽기 전용 요청이나 DB 조회로 다시 읽은 결과.
- **Cleanup** — 띄운 서버 PID · 테스트 데이터베이스·컨테이너.
- **함정** — 헬스 체크 통과가 준비를 뜻하지 않는다(마이그레이션·시드가 도는 중일 수 있다). 운영 엔드포인트에 쓰는 요청을 보내지 않는다 — 대상이 로컬 인스턴스인지 Doctor 가 먼저 확인한다.

## Windows 데스크톱 (WinUI · WPF · WinForms · gpui 등)

- **하네스** — 레포에 FlaUI·WinAppDriver·Appium(Windows) UI 테스트가 있으면 그 러너와 셀렉터를 쓴다.
- **없으면 karina-computer-use 가 있는지 먼저 본다** — Karina CLI 를 `KARINA_CLI_COMMAND` 환경변수 → PATH 의 `karina-cli`·`karina-dev-cli` → 설치본 전체경로(`$LOCALAPPDATA/Programs/Karina/karina-cli.exe`) 순으로 고르고, 그 CLI 의 `skills get karina-computer-use` 가 exit 0 이면 그 CLI 의 `computer` 명령으로 조작한다. 이 순서의 정본은 그 출력의 「Preconditions」 절이다. 명령·옵션·창 선택·좌표 환산도 그 출력을 따르고 여기에 옮겨 적지 않는다 — Karina 판이 바뀌면 사본이 낡는다. `computer` 는 Karina 앱 없이 CLI 프로세스 안에서 돈다.
  - 접근성 트리가 있는 앱은 요소를 이름·역할로 찾는다. 요소 번호는 실행마다 바뀌므로 지도·헬퍼에 적지 않고, 조작할 때마다 직전 트리에서 다시 얻는다.
  - 접근성 트리가 없는 창(gpui·게임 엔진·canvas 렌더 — 트리에 OS 창 틀만 잡힌다)은 직전 스크린샷에서 자리를 읽어 좌표로 조작한다. 지도에는 좌표값 대신 자리를 찾는 기준(창의 어느 영역에 있는 어떤 라벨·아이콘)을 적는다.
- **karina-computer-use 가 없으면 .NET UI Automation 을 PowerShell 에서 쓴다** — `Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes` 는 Windows PowerShell 5.1 과 pwsh 7 양쪽에서 로드된다(2026-10-18 pwsh 7.6.7 실측). 헬퍼는 `helpers/uia.ps1` 처럼 **`helpers/` 에 둔다** — `.claude/` 아래 `scripts/*.ps1` 은 pjc 하니스 hook 이 막는다. 파일은 UTF-8 BOM 으로 저장한다. **접근성 트리가 없는 창은 이 경로로 조작할 수 없다** — 그 기능의 경로를 지도에 `verified-unreachable` 로 적고 생성 보고에 사유(karina-computer-use 없음)를 싣는다.
  ```powershell
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
  $A = [System.Windows.Automation.AutomationElement]
  $C = [System.Windows.Automation.PropertyCondition]
  $win = $A::RootElement.FindFirst('Children', $C::new($A::AutomationIdProperty, 'MainWindow'))
  $btn = $win.FindFirst('Descendants', $C::new($A::AutomationIdProperty, 'SaveButton'))
  $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  ```
- **Launch** — 빌드 산출물의 exe 를 `Start-Process -PassThru` 로 띄워 PID 를 남긴다. 준비 판정은 짧은 간격으로 잰다 — Karina CLI 경로면 **그 CLI 의 창 목록에 대상 창이 나타나는가**, UI Automation 경로면 **기대 AutomationId 를 가진 최상위 창이 나타나고 사용 가능(`IsEnabled`)한가**다. MSIX 로 패키징된 앱(WinUI 기본)은 `Start-Process "shell:AppsFolder\<AUMID>"` 로 띄우므로 `Start-Process` 의 PID 가 앱이 아니다 — 최상위 창의 UIA `ProcessId` 속성으로 PID 를 얻어 Cleanup 이 쓰게 한다. 접근성 트리가 없는 창도 최상위 창 요소는 있어 이 속성을 읽을 수 있다.
- **Doctor** — Karina CLI 경로를 고른 스킬은 실행마다 그 CLI 의 `skills get karina-computer-use` 가 exit 0 인지 다시 본다. 스킬을 만든 PC·시점과 돌리는 PC·시점이 다를 수 있다. 실패하면 조작하지 않고 그 사실을 보고한다.
- **Drive** — 접근성 트리가 있는 앱은 `AutomationId` → `Name` + `ControlType` 순으로 찾는다. UI Automation 경로는 패턴을 쓴다: 버튼 `InvokePattern` · 입력 `ValuePattern.SetValue` · 목록 항목 `SelectionItemPattern.Select` · 체크박스 `TogglePattern` · 펼침 `ExpandCollapsePattern`. 트리가 있는 앱에서 좌표 클릭·`SendKeys` 는 마지막 수단이고, AutomationId 가 없는 컨트롤이 많으면 그것이 지도 `Gotchas` 와 제품 쪽 보고 대상이다(XAML 의 `AutomationProperties.AutomationId`). 접근성 트리가 없는 창은 좌표가 유일한 수단이라 결함 보고 대상이 아니다.
- **Evidence** — 대상 창의 스크린샷(Karina CLI 경로면 그 CLI 의 스크린샷, UI Automation 경로면 `System.Drawing` 으로 창 `BoundingRectangle` 을 캡처 — 앱 제목이 보이게) + 트리가 있으면 조작 전후의 트리 덤프(이름·AutomationId·ControlType·값) + 부수 효과(쓴 파일·레지스트리·DB)를 앱 밖에서 다시 읽은 결과. 접근성 트리가 없는 창은 조작 전후 스크린샷과 부수 효과가 증거다.
- **Cleanup** — Launch 가 남긴 PID 만 `Stop-Process -Id` 로 내린다. 같은 이름의 다른 인스턴스(사용자가 연 앱)는 건드리지 않는다.
- **함정**
  - UI Automation 은 **같은 사용자 세션의 보이는 데스크톱**에서만 돈다 — 잠긴 화면·서비스 세션·원격 데스크톱 최소화에서는 요소를 못 찾는다. Doctor 가 데스크톱이 잠기지 않았는지 본다.
  - 앱이 관리자 권한으로 돌면 일반 권한 스크립트가 그 창을 조작하지 못한다(UIPI).
  - WinUI 3 의 일부 컨트롤은 트리가 늦게 채워진다 — 찾기 전에 기대 요소의 출현을 기다린다.
  - DPI 배율이 스크린샷 좌표를 바꾼다 — 좌표를 하드코딩하지 않고 조작할 때마다 직전 스크린샷에서 읽는다. 스크린샷 픽셀과 클릭 좌표의 환산은 Karina CLI 경로면 karina-computer-use 출력을 따르고, UI Automation 경로면 캡처를 `BoundingRectangle` 기준으로 한다.
