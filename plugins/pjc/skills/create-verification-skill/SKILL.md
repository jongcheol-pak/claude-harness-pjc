---
name: create-verification-skill
description: 대상 레포를 조사해 앱을 사용자처럼 조작해 기능을 증명하는 프로젝트 검증 스킬(.claude/skills/verify-앱이름/ · 기능 지도)을 만들고 한 번 실제로 돌려 넘긴다. 사용자 호출 전용.
disable-model-invocation: true
---

# Create a verification skill

> 출처는 Cursor pstack 의 create-verification-skill 이다 — 고정 위치 `https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/skills/create-verification-skill/SKILL.md`. Copyright (c) 2026 Lauren Tan · MIT(`https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/LICENSE`). 한글로 옮기며 생성 위치를 Claude Code 프로젝트 스킬로 바꾸고, Windows 네이티브 조작·「변경 검증」 절·pjc 등록 절차를 더했다.

실제 앱을 띄우고, 사용자가 쓰는 방식으로 기능을 조작하고, 증거를 남기는 절차를 대상 레포 전용 스킬 `.claude/skills/verify-<app>/` 로 만든다. **생성물의 독자는 사람이 아니라 다음 에이전트다** — 앱을 한 번도 본 적 없는 에이전트가 작업 도중에 처음 읽고 그대로 따라 한다. 그 에이전트는 `pjc:implement` 의 화면 확인 전 조작과 `pr-verifier` 의 merge 전 검증이다(`AGENTS.md` 의 `Verify (앱 조작)` 줄로 찾는다).

## 1. 사용자가 아니라 레포를 조사한다

아래를 코드베이스에서 답하고, 볼 수 없는 것만 사용자에게 묻는다.

- **Surface** — 사용자가 실제로 만지는 것: 웹 UI · CLI/TUI · Windows 데스크톱 앱(WinUI·WPF·WinForms) · API · 모바일 앱 · 라이브러리. 여럿이면 주된 하나를 고르고 나머지는 적어 둔다.
- **Run** — 로컬에서 어떻게 뜨는가. 레포가 문서로 정한 개발 명령(package scripts·Makefile·`dotnet run`·README 빠른 시작)을 먼저 쓴다. 포트·환경변수(이름만 — 값은 적지 않는다)·시드 데이터·인증을 적는다.
- **Drive** — 에이전트가 프로그램으로 조작할 수단. 레포에 이미 있는 하네스(Playwright·Cypress 스펙, FlaUI·WinAppDriver·Appium 테스트, expect 스크립트, curl 로 부를 엔드포인트, 디버그 포트)가 먼저다. 없을 때만 `references/drive-recipes.md` 의 일반 방식을 고른다.
- **Observe** — 남길 수 있는 증거: 스크린샷·접근성 트리·터미널 기록·응답 본문·로그·종료 코드·DB 상태.
- **Isolate** — 두 인스턴스를 나란히 띄울 수 있는가(포트·데이터 폴더·프로필). 안 되면 생성물에 그렇게 적는다 — 남이 쓰는 인스턴스를 같이 조작하는 것보다 거부하는 편이 사용자 세션을 망치지 않는다.

**체크아웃이 그대로 빌드·실행되지 않으면 무엇이 왜 안 되는지 정확히 보고하고 멈춘다** — 깨진 기반 위에 쓴 스킬은 틀린 단계를 가르치고, 제품 코드를 고치는 것은 이 스킬의 일이 아니라 `pjc:plan` 이다(하니스의 `guard-write` 도 plan 없는 제품 코드 쓰기를 막는다). 실행과 무관한 자산 하나가 없어 시작이 막히는 경우(서비스가 쓰지 않는 정적 폴더·샘플 설정)만, 그 자산을 `.claude/skills/verify-<app>/` 안에 검증용 발판으로 만들고 Cleanup 이 지우게 한다.

## 2. 스킬을 만든다

`.claude/skills/verify-<app>/SKILL.md` 를 쓴다. YAML frontmatter(`name: verify-<app>` · 앱·표면·언제 쓰는지를 담은 `description`)가 없으면 스킬로 등록되지 않는다. 아래 절은 모두 1단계에서 실제로 찾은 것으로 채운다 — **자리표시를 남기지 않는다.**

- **Launch** — 검증용으로 앱을 띄우는 정확한 명령과 준비 판정(로그 한 줄·프롬프트·기대 창의 출현). 빈 데이터 폴더에서 마이그레이션·시드까지 거쳐 **쓸 수 있는 상태**에 닿아야 한다. 프로세스가 응답하는 것은 준비가 아니다 — DB 헬스 체크는 초기화 스크립트가 도는 중에도 통과한다. 종료 방법을 함께 적는다. 수명이 짧은 CLI·TUI 는 붙잡아 둘 서버가 없다 — Launch 는 바이너리를 한 번 빌드(또는 의존성 설치)하는 것이고, 조작마다 격리된 세션에서 새로 띄운다. **레포 루트를 인자로 받아 다른 worktree 에서도 돌게 쓴다** — `pjc:implement` 가 `(BASE 대조)` 시나리오를 BASE worktree 에서 같은 Launch 로 돌린다.
- **Doctor** — 「이 인스턴스를 조작해도 되는가」에 답하는 읽기 전용 점검 하나: 프로세스가 떠 있는가 · 기대한 버전·빌드인가 · 포트를 우리가 쥐고 있는가 · 인증이 유효한가. 무언가 이상해 보이면 에이전트가 가장 먼저 돌린다.
- **Drive** — 이 레포의 실제 셀렉터·명령으로 쓴 조작법. 예시가 아니다. 좌표·탭 순서보다 안정된 손잡이(ARIA 이름·data 속성·AutomationId·프롬프트 문자열·라우트 경로)를 쓴다.
- **Evidence** — 증명에 무엇을 남기고 어디에 두는가. 증거는 **레포 밖**(시스템 임시 폴더 아래, 예: `%TEMP%/verify-<app>/<실행 id>/`)에 둔다 — `pr-verifier` 는 파일을 고치지 않는 에이전트라 레포 안에 쓰면 그 규칙을 어긴다. 증거 기준을 적는다:
  - 실제 사용자 경로로 조작한다 — 내부 setter·테스트 전용 엔드포인트는 쓰지 않는다
  - 조작과 그 결과 상태를 함께 남긴다 — 마지막 화면만으로는 증명이 아니다
  - 보이는 것과 함께 부수 효과(쓴 파일·추가된 행·보낸 메시지)를 확인한다
  - mock 은 운영 경계가 이미 외부 시스템을 떼어 놓은 자리에서만 쓴다
  - dry-run·테스트 모드가 안전한 경로면, 이름을 믿지 말고 실제로 무엇을 건너뛰는지(파일·네트워크·git ref) 관측한다 — 네트워크를 건드리거나 브라우저를 여는 dry-run 도 있다
- **Cleanup** — 이번 실행이 만든 인스턴스를 내리는 법. 프로세스 이름으로 죽이지 않고 **시작한 것만**(PID) 내린다. Cleanup 은 인스턴스와 임시 상태를 지우되 **증거는 지우지 않는다** — 증거는 Evidence 가 이름 댄 위치에 남는다.
- **Helpers** — 스킬이 함께 두는 스크립트는 실행 가능해야 하고 호출 방법이 본문에 있어야 한다. 읽는 쪽이 거꾸로 분석해야 하는 헬퍼는 헬퍼가 아니다. **헬퍼는 `helpers/` 아래에 둔다 — `.claude/` 아래 `scripts/*.ps1` 은 pjc 하니스의 `guard-harness` hook 이 hook 스크립트 개조로 보고 막는다.** PowerShell 헬퍼는 UTF-8 BOM 으로 저장한다(Windows PowerShell 5.1 한글).
- **변경 검증** — 코드 변경 하나를 증명할 때의 절차: 계획 `**화면**` 줄이나 PR 본문 `화면 시나리오:` 줄이 입력으로 오면 그 시나리오를 그대로 조작해 스크린샷을 Evidence 위치에 그 이름으로 남기고 통과 조건으로 판정한다(BASE 에서도 돌리라는 입력이면 그 worktree 경로로 Launch 한다). 입력이 없으면 바뀐 파일이 닿는 기능을 `features/README.md` 색인에서 고르고, 고른 기능 파일의 **모든 진입 경로**를 조작한다. 편한 진입 경로 하나만 조작한 증명은 지도가 다른 경로를 적었으면 불완전하다. 어느 기능에도 닿지 않으면 그 사실과 근거를 적는다. `pjc:implement` 와 `pr-verifier` 는 이 절을 따른다.

조작 방식별 Launch·Drive·Evidence·Cleanup 의 일반 방식과 함정은 `references/drive-recipes.md` 다.

## 3. 기능 지도를 시드한다

`.claude/skills/verify-<app>/features/README.md` 와, 찾을 수 있는 사용자 기능마다 파일 하나를 만든다(라우트·명령·메뉴·문서에서 주요 기능 3~5개로 시작한다). 형태는 `references/feature-map-example/` 를 따른다 — README 색인 하나와 기능마다 파일 하나다.

- **기능 파일은 사용자 관점에서 넷에 답한다** — 그 기능이 무엇인가 · 어떻게 닿는가 · 하네스로 어떻게 조작하는가 · 무엇이 보이면 동작한다는 증명인가. H2 넷은 이 이름 그대로 쓴다: `Sub-features` · `How to get to it (user POV)` · `Driving it with <harness>` · `Gotchas`. 유지 스킬(`/pjc:maintain-verification-skill`)이 이 이름으로 절을 찾는다.
- **시드 데이터에 경로가 요구하는 전제가 없으면 그 경로는 실패로 보고하고 이유를 그 기능의 `Gotchas` 에 적는다** — 통과시키려고 경로를 약하게 바꾸지 않는다.
- **지도는 그 레포가 유지하는 검증의 정본이다** — 지도가 진입 경로를 여럿 적었는데 편한 하나만 조작한 증명은 불완전하다.

## 4. 넘기기 전에 생성한 스킬을 증명한다

생성한 스킬의 지시를 처음부터 끝까지 한 번 그대로 돈다: Launch → Doctor → 지도의 기능 **하나** 조작(하나면 된다 — 나머지는 이후 실행이 지도로 덮는다) → 증거 남기기 → Cleanup.

- **Cleanup 뒤에 증거가 Evidence 의 위치에 남아 있는지 확인한다** — 증거까지 지우는 Cleanup 은 이 단계의 실패다.
- **실패하면 고치고 다시 돈다 — 실패한 시도마다 생성한 Cleanup 을 돌린다** — 깨진 시도가 프로세스·포트를 남기지 않게 한다.
- **실제로 돌려 보지 않은 생성물은 초안이지 산출물이 아니다** — 증명에 끝내 실패하면 SKILL.md 본문 첫 줄에 `> 초안 — 실행 증명 실패: <어느 단계에서 무엇이>` 를 남기고 5단계의 등록을 하지 않는다.
- **진짜 대상 대신 대역(새 VM 대신 컨테이너, 원격 대신 로컬 스택)에서 증명했으면, 대역이 해 주고 대상은 하지 않을 준비 단계를 모두 적는다** — 그 단계는 진짜 대상에서 돌기 전까지 미검증이다.

## 5. 등록하고 유지 루프를 안내한다

증명에 성공했을 때만 한다. 순서가 정해져 있다.

1. **추적되는 경로인지 본다** — `git check-ignore -q .claude/skills/verify-<app>/SKILL.md` 의 종료 코드가 **1** 이어야 한다(0 이면 무시되는 경로다). 무시되는 경로면 `git check-ignore -v` 출력(어느 ignore 파일의 몇째 줄인지)을 보이고 사용자에게 둘 중 하나를 고르게 한다 — 고르지 않으면 등록하지 않고 보고한다. `pr-verifier` 는 PR head 의 worktree 에서만 돌아 추적되지 않은 스킬을 보지 못한다(전역 `core.excludesfile` 이 `.claude/` 를 무시하는 PC 가 흔하다).
   - **(권장) 레포 `.gitignore` 에 부정 사슬 다섯 줄을 더한다** — `!.claude/` · `.claude/*` · `!.claude/skills/` · `.claude/skills/*` · `!.claude/skills/verify-<app>/`. git 은 제외된 부모 폴더 아래 파일을 되살리지 못해 `!.claude/skills/verify-<app>/` 한 줄로는 풀리지 않는다. 이후 `add` 는 그대로 통하고, 4번 커밋 경로에 `.gitignore` 를 더한다.
   - **`git add -f -- .claude/skills/verify-<app>`** — 폴더 전체를 지정한다. 이 경로를 고르면 4번과 유지 스킬의 `add` 에도 `-f` 가 필요하다 — 없으면 `The following paths are ignored` 로 실패한다.
   - 고른 수단을 적용한 뒤 이 1번을 다시 돌려 종료 코드 1 을 확인한다(2026-10-18 전역 ignore 를 둔 임시 레포 실측: 부정 사슬 rc 0→1·이후 add rc 0 · `add -f` 뒤 일반 add rc 1·`add -f` rc 0).
2. **`AGENTS.md` 에 이번과 무관한 미커밋 변경이 없는지 먼저 본다** — `git status --porcelain -- AGENTS.md` 가 비어 있지 않으면 등록하지 않고 보고한다. 아래 커밋이 그 파일의 다른 변경까지 담기 때문이다.
3. **`pjc:record-project-fact` 로 `AGENTS.md` 의 `Verify (앱 조작)` 줄에 `.claude/skills/verify-<app>/` 를 적는다** — `AGENTS.md` 쓰기의 정본은 그 스킬이고, 그 스킬이 바꿀 내용을 보이고 승인을 받는다.
4. **생성 폴더와 `AGENTS.md` 를 함께 로컬 커밋한다** — `git add -- .claude/skills/verify-<app> AGENTS.md` 뒤 `git commit -m "설정: 검증 스킬 verify-<app> 생성" -- .claude/skills/verify-<app> AGENTS.md`. 새 폴더는 추적 전이라 `add` 없이 경로를 지정하면 `pathspec … did not match` 로 실패한다. 1번에서 부정 사슬을 골랐으면 `.gitignore` 를, `-f` 를 골랐으면 `add` 에 `-f` 를 더한다. 포인터만 커밋되고 대상이 빠지거나 그 반대면 PR head 에서 한쪽이 없다.
5. **앱이 바뀌면 `/pjc:maintain-verification-skill` 로 지도를 다시 맞춘다고 안내한다** — 주기는 사용자가 물을 때만 제안한다.

## 보고

생성 폴더 경로 · 고른 Surface 와 조작 방식 · 지도에 넣은 기능 목록 · 증명한 기능과 증거 위치 · 증명 결과(성공 | 초안 — 실패 단계) · 등록 결과(줄을 쓴 커밋 | 건너뜀 — 사유) · 대역 환경에서 미검증으로 남은 단계. 문장은 `../WRITING.md` 를 따른다.
