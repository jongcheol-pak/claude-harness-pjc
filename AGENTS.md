# AGENTS.md — Agent Guide

> pjc 하니스 플러그인 repo. 컴파일 언어가 없는 **PowerShell hooks + Markdown skills/agents** 구성이라 표준 build/test가 없다. 아래 **워킹트리 정적 검증** 명령으로 `implement-task`의 V-1/V-2를 결정적으로 수행한다.

## Stack
- **언어/플랫폼**: Claude Code 플러그인 (pjc harness). PowerShell 7(pwsh) 우선 · Windows PowerShell 5.1 폴백. 컴파일 언어 없음.
- **Claude Code 버전**: 최소 v2.0, **권장 v2.1.219+**. plan 리뷰어 2종(`plan-reviewer`·`plan-completion-reviewer`)만 `model: opus`인데 그 별칭이 **Claude Opus 5로 해소되는 것이 v2.1.219+**다 — 미만에서는 이전 세대 Opus로 실행돼 판정 품질이 달라질 수 있다(sonnet·haiku 지정 리뷰어는 무관).
- **버전**: pwsh 7+ (hook 실행). 플러그인 버전은 `plugins/pjc/.claude-plugin/plugin.json`.
- **주요 프레임워크**: 없음 (hooks.json 배선 + PowerShell 스크립트 + Markdown SKILL/agent).
- **테스트 도구**: 없음 (단위 테스트 프레임워크 없음 — 아래 구문·JSON 검증으로 대체).

## Build & Test
모든 명령은 **repo 루트에서** 실행한다(상대경로 기준).

- **Build (전 ps1 구문 검사)**:
  ```
  pwsh -NoProfile -Command "$f=0; Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { $e=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e); if($e.Count){$f++; Write-Host ('PARSE FAIL ' + $_.Name + ': ' + $e.Count)} }; if($f){exit 1}; 'parse OK'"
  ```
- **Test (JSON 매니페스트 유효성)**:
  ```
  pwsh -NoProfile -Command "@('plugins/pjc/.claude-plugin/plugin.json','plugins/pjc/hooks/hooks.json','.claude-plugin/marketplace.json') | ForEach-Object { $c = Get-Content -LiteralPath $_ -Raw -ErrorAction Stop; $null = $c | ConvertFrom-Json; Write-Host ($_ + ' OK') }"
  ```
- **Hook 골든 회귀 (hook 스크립트·골든 케이스 수정 시 필수)**:
  ```
  pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
  ```
  **⚠ 이대로 실행하면 완주하지 않는다** — 스위트가 **도구 시간 캡(10분)을 넘는다**(643케이스 — 2026-08-21 실측. 소요 편차가 커 시간으로 완료를 판정하지 않는다)인데 Bash 도구의 시간 캡은 **전경·`run_in_background` 모두 10분**이라 어느 쪽으로 띄워도 killed되고, `Start-Process`의 리다이렉트 파라미터는 0바이트 파일을 남긴다. **분리 프로세스 + 래퍼 스크립트 + `Monitor` 폴링**이 정본 절차이며 **실행·대기·판정·모드(`-Sequential`·`-Resume`·`-Filter`) 상세는 `docs/harness-conventions.md` 「골든 러너 운용 (실행·대기·판정)」이 정본**이다. 그 절을 읽지 않고 돌리면 과거처럼 "환경상 실행 불가"로 F-2를 갈음하게 된다.

  격리 USERPROFILE에서 hook 12종(block-destructive·protect-harness·warn-external-ops·require-plan-for-write·require-task-checkbox·suggest-agents-record·post-write-checks·require-evidence·warn-commit-secrets·warn-version-drift·session-context·session-end-cleanup)을 stdin JSON 케이스로 실행해 exit code·출력을 대조한다(케이스 정본: `plugins/pjc/hooks/evals/hook-cases.json` + 러너 내장 시나리오). 전부 OK면 exit 0.
  부분 실행 `-Filter <hook명>`(쉼표 복수, `.ps1` 생략 가능)은 **구현 중 반복 확인 전용**이고, task 검증과 Phase F-2는 무인자 **전체 실행**이 정본이다 — **부분 실행 결과로 검증 판정 금지**(골든 케이스가 hook 간 얽혀 있어 커버리지가 좁다).
  **케이스를 추가할 때는 `docs/harness-conventions.md` 「검증 케이스의 축 분리」를 먼저 본다** — 한 케이스가 여러 축을 담으면 나중에 한 축을 제외할 때 나머지가 조용히 무력화된다.
- **llm-wiki 상수·배치 정합 셀프체크 (SKILL.md 예산표·「예산 단계 신호」 표·라우팅 표·references/procedures-*.md·wiki-schema §2/§3/§4/§7/§8/§11/§12·목차·templates.md·lint.py 상수 수정 시 필수)**:
  ```
  python plugins/pjc/skills/llm-wiki/evals/check_consistency.py
  ```
  다음을 기계 대조한다 — 네 곳의 공유 상수(파일 예산·통제 어휘) / 절차 배치(본체 `## 절차 목차` 라우팅 표 **전 행** ↔ `references/procedures-content.md`·`procedures-ops.md`의 절차 헤딩 실존·1곳·위치 일치. 절차 문자는 표에서 동적 캡처라 신규 절차도 자동 검사되고, 비문자 행·중복 행·스트레이 헤딩도 잡는다) / wiki-schema 목차 § ↔ `## N.` 헤딩 / procedures-ops F-1 실행 순서 ↔ wiki-schema §7 검사 번호 1:1 / 산문 크로스파일 포인터(절차 라벨 ↔ 실제 `### X.` 헤딩 파일) / templates.md 타입 ↔ schema §2 타입 집합 / **예산 단계 임계·판정 어휘**(SKILL 「예산 단계 신호」 표 ↔ lint 상수 4값+어휘 — 임계는 이 축 말고는 어디서도 대조되지 않는다) / **타입 열거 정합 11자리·12항목**(새 타입이 산문 열거에서 조용히 빠지는 사각 — ⓐ `lint.py` 타입 집합 상수 ↔ 문서 산문 8항목(§3 origin·confidence·§7-3·§7-9·§7-28·§7-29·§8 아카이브 예외·§11) ⓑ §2 타입 전 커버 4항목(목차 §2 행·계층 태그·templates 목차·§12 권장/비대상 분할 커버)) / **트리거 유일성**(예산 처방의 발동·종료·재발동·승급 조건이 wiki-schema §7-2와 SKILL 「예산 단계 신호」 표 밖에 서술되지 않는가 — 면제는 열거로만 두고 앵커별 매치 수를 함께 검증한다. 상세 리포트는 `--trigger-report`). 일치 exit 0, 불일치 1, 파싱 앵커 실패 2.
  **lint 검사에 제외(exemption)를 넣을 때는 `docs/harness-conventions.md` 「검증 케이스의 축 분리」를 먼저 본다** — 제외 기준에 걸리는 기존 골든 케이스가 다른 축을 함께 싣고 있으면 그 축이 통째로 가려진다(§7-29 타입 제외에서 실측).
- **하니스 정합 셀프체크 (`plugins/pjc/evals/**`·예산 표·리뷰어 각주·`deferred.md` 수정 시 필수)**:
  ```
  python plugins/pjc/evals/check-harness-consistency.py
  ```
  아홉 축(문서 로드 예산 · 리뷰어 각주 앵커 · **실행 예산 수치** · 포인터 도달성 · 마커 동기 · **개념 정본** · Deferred 잔량 · **볼드 마커 짝** · **한 줄 문장 중복**)을 대조한다. **exit 0 일치 / 1 불일치 / 2 앵커 파싱 실패**(2는 통과가 아니다). 축별 기준표는 `docs/harness-conventions.md`.
- **⚠ 검증 배치에 `Remove-Item`을 인라인으로 넣지 말 것**: Claude Code **PowerShell 도구의 내장 경로 보호**가 삭제 대상을 추출할 때 실제 대상이 아니라 **같은 명령 문자열 안 다른 위치의 따옴표 경로**를 집어 오차단한다(`Remove-Item on system path ''D:\Personal' is blocked.`). **하니스 hook과 무관하다** — `block-destructive`에 변형 11종을 stdin 주입한 결과 **11/11 exit 0**(차단 0건)이다. `Remove-Item` 토큰과 공백 포함 경로가 **한 명령 문자열에 함께 있을 때만** 발화하는 조합 의존이라 "가끔 막힌다"로 보인다. **회피**: 검증 배치를 **스크립트 파일로 분리**(가장 확실) · **Bash 도구** 사용 · 환경변수 제거는 `$env:NAME = ''` 대입.
- **통합 검증 (재설치 후)**: `pwsh ./validate.ps1` — ⚠️ **설치 캐시**(`~/.claude/plugins/cache/...`)를 검사하므로 **워킹트리 변경은 재설치 후에만 반영**된다(`install.ps1 -Uninstall` 후 `install.ps1`). 개발 중 워킹트리 검증은 위 Build/Test로 한다.

### 검증 매핑 (task 검증 선택)
**표 정본은 `docs/harness-conventions.md`의 「검증 매핑 (task 검증 선택)」이다** — 변경 파일 패턴 → 필수 검증. task 단위 검증은 그 표에서 변경 파일에 맞는 행만 실행하고(여러 패턴이면 합집합), 전체 검증은 Phase F-2가 1회 보장한다. 표를 여기 두지 않는 이유는 이 파일의 16KB 주입 상한이다.
같은 문서의 **「골든 부분 실행의 판정 자격」**(부분 실행으로 갈음할 수 있는 조건 — plan에 미리 명시 + 커밋 `Tests:` 범위 기재)과 **「문서 로드 예산 기준선」**(스킬·리뷰어 파일 바이트 기계 대조)도 함께 읽는다.

## Repository Structure
```
<repo>/
├── .claude-plugin/marketplace.json
├── plugins/pjc/
│   ├── .claude-plugin/plugin.json   # 플러그인 버전·메타
│   ├── hooks/hooks.json             # PreToolUse/PostToolUse/Stop/SessionStart/SessionEnd 배선
│   ├── skills/llm-wiki/scripts/lint.py  # 검사 + `--fix`(안전 3종) + `--build-index`(index.md 생성 구역 파생 · sub-index 생성) / migrate-index-labels.py  # index 라벨 역이관(1회성, 기본 dry-run)
│   ├── scripts/*.ps1                # hook 구현(block-destructive·protect-harness·require-plan-for-write·require-task-checkbox·post-write-checks·require-evidence·warn-external-ops·suggest-agents-record·warn-commit-secrets·pre-bash-dispatch·warn-version-drift(버전 드리프트 경고)·session-end-cleanup(SessionEnd — 고아 콘솔 프로세스 회수)·session-context(SessionStart **startup|resume|clear|compact|fork** — fork 세션도 주입 대상이다, plan 상태 + **위키 vault 설정 상태**(설정+실재 / 경로 부재만 1줄 주입, 미설정은 무출력 — 절차 K의 "미설정" 오판정 차단. 게이팅은 cwd 수집 라인 기준이고 compact 리마인더는 신호가 아니다) + AGENTS.md 전문 주입(**16KB 초과 시 목차 폴백**) — compact 포함)) + 공유 dot-source 헬퍼(secret-patterns·bash-hook-lib·hook-event-log·orphan-process-cleanup(고아 more.com·find.exe 회수 — Stop·SessionStart·SessionEnd가 호출) — 차단/경고 이벤트를 `~/.claude/.state/hook-events/`에 jsonl 적재, hook 아님) + 수동 도구 report-hook-events(이벤트 집계 리포트, 읽기 전용, hook 아님). Bash PreToolUse는 block-destructive(독립) + pre-bash-dispatch(warn-external-ops·require-task-checkbox·warn-commit-secrets·warn-global-find를 bash-hook-lib 함수로 in-process 실행 — pwsh 콜드스타트 4→2). 3 스크립트는 얇은 래퍼로 존치(골든·격리용). hooks.json command는 스크립트를 hook 셸에서 직접 실행한다(엔트리당 outer+inner 2프로세스 → outer 1프로세스. 실행 셸은 Claude Code가 powershell로 해석하며 실측상 pwsh 우선 — 크로스플랫폼 hook 디버깅 시 이 해석 규칙을 먼저 본다).
│   ├── agents/*.md                  # reviewer subagent 정의
│   └── skills/*/SKILL.md            # plan-feature·implement-task 등 (+ references/·templates/)
├── docs/
│   ├── harness-conventions.md       # 하니스 전역 규약 상세 (hook 차단·검증 매핑·문서 예산·리뷰어 각주의 정본)
│   ├── prd.md
│   └── plans/deferred.md            # 미처리 Deferred 단일 대장
├── validate.ps1                     # 설치본 검증
├── install.ps1
└── README.md                        # (notes.md·plan.md·notes-archive/ 는 .gitignore — 로컬 전용)
```

## Conventions
- **인코딩**: `.ps1`은 **UTF-8 BOM 필수**(Windows PowerShell 5.1 한글 호환). 그 외(.md/.json)는 **BOM 없음**.
- **줄바꿈**: 워킹트리는 **CRLF**이고 `core.autocrlf=true`다 — `sed -i`로 md를 고치면 파일 전체가 LF로 바뀌는데 **blob이 LF로 정규화돼 `git diff`에 안 나타난다**(v1.186.0 T1에서 `harness-conventions.md` 360줄이 이 회귀를 겪었다). **md 수정은 Edit 도구를 쓴다.**
- **주석**: 한글, "왜"를 설명("무엇"은 코드로).
- **파일 크기**: 분할은 줄 수가 아니라 책임·읽기 부담으로 판정한다(`implement-task` 규칙 8의 네 질문이 정본).
- **hook 출력 규약**: 경고는 `exit 0` 비차단 + stderr + additionalContext. 차단 형태는 **둘**이다 — ① **`exit 2`**: `block-destructive`·`protect-harness`·`require-plan-for-write`·`require-task-checkbox` + **`warn-commit-secrets`(조건부)** ② **`stdout JSON`(`{"decision":"block","reason":…}`) + `exit 0`**: **`require-evidence`(조건부)**. ②는 Stop hook 전용으로 종료를 막고 `reason`을 모델에 전달해 루프를 잇는다(도구 호출이 아니라 *종료를 되돌린다*). **두 조건부의 세부 조건·스캔 범위·라벨 매치 형태는 `docs/harness-conventions.md`가 정본이다** — hook을 수정하거나 문서에 차단 범위를 적기 전에 반드시 읽을 것(차단 범위를 실제보다 넓게 쓰면 "차단한다고 썼는데 안 잡는" 상태가 된다). **우회 변수는 둘이며 서로 대체되지 않는다** — `require-evidence`는 `CLAUDE_HARNESS_QUICK=1`, `warn-commit-secrets`는 전용 변수 `CLAUDE_HARNESS_ALLOW_SECRET=1`(QUICK으로는 꺼지지 않는다).
- **`require-plan-for-write`는 게이트 3종을 담는다**: ① plan 존재 게이트(코드 Write 시 plan 필요 — `docs/plans/`는 **체크박스 plan 실재**로 판정, 디렉터리 존재만으로는 안 켜짐) ② **plan 작성 게이트**(plan 파일 Write·체크박스 도입 Edit은 `pjc:plan-feature`/`implement-task` 발동 흔적 필요) ③ AGENTS.md bootstrap 게이트. ①과 ②는 같은 정규식(`$planTaskRx`)을 공유한다 — **기준이 갈리면 그 차이가 곧 우회 경로**이므로 한쪽만 고치지 말 것.
- **SKILL 문서 작성**: `plugins/pjc/skills/AUTHORING.md` 참조("왜"를 설명, 절대 규칙만 단호하게).
- **README.md 갱신 규약**: 버전별 수정 내역(`> v1.x.y: …` changelog 블록) 기재 **금지** — 현재 기능 설명만 유지한다(변경 반영은 이력 서술 append가 아니라 기존 문장을 현재 동작에 맞게 수정, 제거된 기능 설명은 삭제). 버전 표기는 상단 `**버전**:` 1곳만 두고 릴리즈 시 `plugin.json` version과 **함께** 갱신한다. **이력은 git 커밋이 정본이다.** (이 규칙은 실제로 버전 동기화가 누락되고 changelog가 재유입된 사고를 겪은 뒤 확정됐다 — 관례가 아니라 재발 방지책이다.)

## DO NOT
- 실제 비밀번호·API 키·토큰·시크릿·DB 연결문자열·내부 IP/호스트를 코드·문서·notes·plan에 기록(환경변수 이름만 적고 값은 `.env`로).
- **`block-destructive.ps1`·`protect-harness.ps1`의 차단 동작 변경** — 안전 임계 hook(끌 수 없음, 마지막 방어선). protect-harness는 설치본 hook 스크립트·hooks.json을 Write/Edit로 개조해 안전장치를 무력화하는 시도를 차단한다. 헤더 경고 참조. **단 두 종류의 수정은 사용자 승인 선례로 허용된다** — ① **오탐 수정**("정상 작업 오차단만 없애고 위험 차단은 유지"): 골든 회귀(신규 통과 케이스 + 수정 전 차단 음성 대조)로 실증하는 조건. ② **미탐 보완**(차단 범위 확대): 같은 실증 조건 + **새 경계가 실제로 발화하는 "델타 음성" 케이스로 오차단 0을 반드시 실증할 것** — 통과만 확인하는 무회귀 케이스는 근거가 되지 못한다(차단이 늘어나므로 오탐 수정보다 요구가 강하다).
- 자동 생성·캐시 디렉터리(`__pycache__/`, lock 파일 등) 커밋.
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass`(백신이 공격 도구로 오인해 격리할 수 있음).

## Plan Location
- 단일 plan: `plan.md`(덮어쓰기 방식).
- **`plan.md`·`notes.md`·`notes-archive/`는 `.gitignore`(로컬 전용)** — git에 안 올라간다. 커밋되는 건 코드·문서(README 등)뿐이며, **작업의 영구 기록은 git 커밋**이다(회차를 관통하는 서사는 F-6.5의 「회차 서사 커밋」이 담고, 미처리 Deferred는 커밋되는 `docs/plans/deferred.md`가 담는다).
- PRD: `docs/prd.md` (Opus 5 세대 대응 작업분 — active FR 14건·NFR 6건). **소규모 후속 작업은 이 PRD에 닿는지 경량 확인만 하고**(plan-feature Step 1), 닿지 않으면 plan에 `**PRD**:` 줄을 두지 않는다 — 무관한 과거 PRD를 끌어와 거짓 미충족을 보고하지 않기 위함이다(Phase G 진입은 그 줄이 단일 신호).

## OS/플랫폼
- Windows 검증 · macOS/Linux 실험적(hooks는 pwsh 7 cross-platform 의도). 검증/배포는 Windows 기준.
