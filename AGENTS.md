# AGENTS.md — Agent Guide

> pjc 하니스 플러그인 repo. 컴파일 언어가 없는 **PowerShell hooks + Markdown skills/agents** 구성이라 표준 build/test가 없다. 아래 **워킹트리 정적 검증** 명령으로 `implement-task`의 V-1/V-2를 결정적으로 수행한다.

## Stack
- **언어/플랫폼**: Claude Code 플러그인 (pjc harness). PowerShell 7(pwsh) 우선 · Windows PowerShell 5.1 폴백. 컴파일 언어 없음.
- **Claude Code 버전**: 최소 v2.0, **권장 v2.1.219+**. plan 리뷰어 2종(`plan-reviewer`·`plan-completion-reviewer`)만 `model: opus`이며, 그 별칭이 **Claude Opus 5로 해소되는 것이 v2.1.219+**다 — 미만에서는 그 둘이 이전 세대 Opus로 실행돼 판정 품질이 달라질 수 있다(`spec-compliance`·`code-quality`는 sonnet, `explorer`·`spec-prefilter`는 haiku 지정이라 무관).
- **버전**: pwsh 7+ (hook 실행). 플러그인 버전은 `plugins/pjc/.claude-plugin/plugin.json`.
- **주요 프레임워크**: 없음 (hooks.json 배선 + PowerShell 스크립트 + Markdown SKILL/agent).
- **테스트 도구**: 없음 (단위 테스트 프레임워크 없음 — 아래 구문·JSON 검증으로 대체).

## Build & Test
컴파일이 없으므로 "빌드/테스트" = **워킹트리 정적 검증**이다. **repo 루트에서** 실행한다(상대경로 기준).

- **Build (전 ps1 구문 검사)**:
  ```
  pwsh -NoProfile -Command "$f=0; Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { $e=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e); if($e.Count){$f++; Write-Host ('PARSE FAIL ' + $_.Name + ': ' + $e.Count)} }; if($f){exit 1}; 'parse OK'"
  ```
- **Test (JSON 매니페스트 유효성)**:
  ```
  pwsh -NoProfile -Command "@('plugins/pjc/.claude-plugin/plugin.json','plugins/pjc/hooks/hooks.json','.claude-plugin/marketplace.json') | ForEach-Object { $c = Get-Content -LiteralPath $_ -Raw -ErrorAction Stop; $null = $c | ConvertFrom-Json; Write-Host ($_ + ' OK') }"
  ```
- **Hook 골든 회귀 (hook 스크립트 수정 시 필수)**:
  ```
  pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
  ```
  **⚠ 실행 방법 (이대로 하지 않으면 완주하지 않는다 — 2026-07-30 실측)**: 무인자 전체는 **출력을 파일로 리다이렉트(`*> <파일>`)해 백그라운드로** 실행한다. 원인은 둘이며 둘 다 피해야 한다 — ① `| Select-Object -Last N` 같은 **파이프라인이 출력을 끝까지 버퍼링**해 중단·미종료를 유발한다 ② 스위트 자체가 **10분을 넘으므로 전경(foreground) 실행은 시간 캡에 걸린다**(리다이렉트만 해도 전경이면 실패). 파일 출력은 즉시 기록되어 진행 상황(`[PASS]` 누적)도 실시간으로 볼 수 있다. 이 방법으로 **447/447 OK(FAIL 0)** 완주를 확인했다(v1.148.0 기준 스위트 크기 — 케이스를 추가하면 이 숫자도 함께 갱신할 것. 회귀 기준선으로 쓰인다) — 과거 "환경상 실행 불가"로 F-2를 갈음한 사례들은 이 방법을 쓰지 않은 것이다.

  **⚠ 도구 timeout까지 감안할 것 (v1.148.0 실측)**: 위 "백그라운드"만으로는 부족하다 — 에이전트의 Bash 도구는 **timeout 상한이 10분**이라 `run_in_background`로 띄워도 그 시점에 killed된다(실제로 이 방식이 한 번 죽었다). **스위트는 30분 이상 걸린다**(447케이스, 케이스마다 pwsh 콜드스타트 — 2026-07-30 실측 약 32분). 확실한 방법은 **세션에서 분리된 프로세스로 띄우고 완료를 폴링**하는 것이다:
  ```
  Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','plugins/pjc/hooks/evals/run-hook-evals.ps1' -RedirectStandardOutput <out> -RedirectStandardError <err> -NoNewWindow
  ```
  그 뒤 `until grep -q "결과:" <out>; do sleep 15; done` 형태로 대기한다. **러너는 결과를 끝에 일괄 출력**하므로(케이스마다 append가 아니다) 실행 중 출력 파일은 헤더뿐이며, **"파일이 안 자란다 = 멈췄다"가 아니다** — 진행 확인은 `Get-Process pwsh`로 한다.

  격리 USERPROFILE에서 hook 11종(block-destructive·protect-harness·warn-external-ops·require-plan-for-write·require-task-checkbox·suggest-agents-record·post-write-checks·require-evidence·warn-commit-secrets·warn-version-drift·session-context)을 stdin JSON 케이스로 실행해 exit code·출력을 대조한다(케이스 정본: `plugins/pjc/hooks/evals/hook-cases.json` + 러너 내장 시나리오). 전부 OK면 exit 0.
  부분 실행 `-Filter <hook명>`(쉼표 복수, `.ps1` 생략 가능)은 **구현 중 반복 확인 전용** — task 검증(아래 검증 매핑 표의 "Hook 골든 회귀")과 Phase F-2는 무인자 **전체 실행**이 정본이다(부분 실행 결과로 검증 판정 금지 — 골든 케이스가 hook 간 얽혀 있어 부분 실행은 커버리지가 좁다).
- **llm-wiki 상수·배치 정합 셀프체크 (SKILL.md 예산표·라우팅 표·references/procedures-*.md·wiki-schema §2/§3/§4·목차·lint.py 상수 수정 시 필수)**:
  ```
  python plugins/pjc/skills/llm-wiki/evals/check_consistency.py
  ```
  네 곳의 공유 상수(파일 예산·통제 어휘)와 절차 배치(본체 `## 절차 목차` 라우팅 표 **전 행** ↔ `references/procedures-content.md`·`procedures-ops.md`의 절차 헤딩 실존·1곳·위치 일치 — 절차 문자는 표에서 동적 캡처(신규 절차도 자동 검사), 체크리스트 등 비문자 행·중복 행·표에 없는 스트레이 헤딩 포함), wiki-schema 목차(부분 Read 인덱스) § ↔ `## N.` 헤딩 정합, procedures-ops F-1 실행 순서 인덱스 ↔ wiki-schema §7 검사 항목 번호 1:1 정합, 산문 크로스파일 포인터(파일-귀속 절차 라벨 ↔ 실제 `### X.` 헤딩 파일), templates.md 타입 ↔ schema §2 타입 집합을 기계 대조한다 — 전부 일치 exit 0, 불일치 exit 1, 파싱 앵커 실패 exit 2.
- **통합 검증 (재설치 후)**: `pwsh ./validate.ps1` — ⚠️ **설치 캐시**(`~/.claude/plugins/cache/...`)를 검사하므로 **워킹트리 변경은 재설치 후에만 반영**된다(`install.ps1 -Uninstall` 후 `install.ps1`). 개발 중 워킹트리 검증은 위 Build/Test로 한다.

### 검증 매핑 (task 검증 선택)
task 단위 검증은 변경 파일 패턴에 맞는 행만 실행한다(여러 패턴에 걸치면 해당 행 전부 — 합집합). 전체 검증은 Phase F-2가 1회 보장하므로 매 task 전량 실행은 중복이다(implement-task V-2 조건부 축소의 결정론화 — 위 산문 조건과 동일 내용의 표 형식).

| 변경 파일 패턴 | 필수 검증 |
|---|---|
| `plugins/pjc/scripts/*.ps1` · `plugins/pjc/hooks/**` | Build(전 ps1 parse) + Hook 골든 회귀 |
| `plugins/pjc/skills/llm-wiki/**` (SKILL·references·lint.py·evals) | check_consistency + (lint.py·evals 수정 시) run_lint_evals |
| JSON 매니페스트 3종 (`plugin.json`·`hooks.json`·`marketplace.json`) | Test(JSON 유효성) — hooks.json은 Hook 골든도 |
| `validate.ps1`·`install.ps1` | Build(전 ps1 parse) |
| 그 외 (`*.md` 문서·`agents/*.md`·기타 skills) | Build(전 ps1 parse) + Test(JSON 3종) — 기본값 |
| `plugins/pjc/skills/evals/**` (스킬 트리거·루브릭 eval) | 러너 자체 실행(`--filter`로 스모크) + Build + Test(JSON 3종). **eval 전량 실행은 명시 호출 전용 — 기본 검증 경로·Phase F-2에 포함하지 않는다**(실제 모델을 호출해 분·비용 단위 비용이 든다) |

## Repository Structure
```
<repo>/
├── .claude-plugin/marketplace.json
├── plugins/pjc/
│   ├── .claude-plugin/plugin.json   # 플러그인 버전·메타
│   ├── hooks/hooks.json             # PreToolUse/PostToolUse/Stop hook 배선
│   ├── scripts/*.ps1                # hook 구현(block-destructive·protect-harness·require-plan-for-write·require-task-checkbox·post-write-checks·require-evidence·warn-external-ops·suggest-agents-record·warn-commit-secrets·pre-bash-dispatch·warn-version-drift(SessionStart 버전 드리프트 경고)·session-context(SessionStart plan/notes 상태 + **위키 vault 설정 상태**(설정+실재 / 경로 부재만 1줄 주입, 미설정은 무출력 — 절차 K의 "미설정" 오판정 차단. 게이팅은 cwd 수집 라인(plan·notes·AGENTS) 기준이고 compact 리마인더는 신호가 아니다) + AGENTS.md 전문 주입(16KB 초과 시 목차 폴백) — compact 포함)) + 공유 dot-source 헬퍼(secret-patterns·bash-hook-lib·hook-event-log(차단/경고 이벤트 jsonl 적재 — `~/.claude/.state/hook-events/`), hook 아님) + 수동 실행 도구 report-hook-events(이벤트 로그 집계 리포트 — hook별·판정별·규칙별, 읽기 전용, hook 아님). Bash PreToolUse는 block-destructive(독립) + pre-bash-dispatch(warn-external-ops·require-task-checkbox·warn-commit-secrets를 bash-hook-lib 함수로 in-process 실행 — pwsh 콜드스타트 4→2). 3 스크립트는 얇은 래퍼로 존치(골든·격리용). hooks.json command는 스크립트를 hook 셸에서 직접 실행(v1.108.0 — 엔트리당 outer+inner 2프로세스 → outer 1프로세스, 실행 셸은 Claude Code powershell 해석·실측 pwsh 우선).
│   ├── agents/*.md                  # reviewer subagent 정의
│   └── skills/*/SKILL.md            # plan-feature·implement-task 등 (+ references/·templates/)
├── validate.ps1                     # 설치본 검증
├── install.ps1
└── README.md                        # (notes.md·plan.md·notes-archive/ 는 .gitignore — 로컬 전용)
```

## Conventions
- **인코딩**: `.ps1`은 **UTF-8 BOM 필수**(Windows PowerShell 5.1 한글 호환). 그 외(.md/.json)는 **BOM 없음**.
- **주석**: 한글, "왜"를 설명("무엇"은 코드로).
- **파일 크기**: 1500라인은 분리 "검토" 신호(강제 분리선 아님).
- **hook 출력 규약**: 경고는 `exit 0` 비차단 + stderr + additionalContext. 차단 형태는 **둘**이다 — ① **`exit 2`**: `block-destructive`·`protect-harness`·`require-plan-for-write`·`require-task-checkbox`, 그리고 **`warn-commit-secrets`(조건부 — v1.119.0)** ② **`stdout JSON`(`{"decision":"block","reason":…}`) + `exit 0`**: **`require-evidence`(조건부 — v1.148.0)**. ②는 Stop hook 전용 형태로, 종료를 막고 `reason`을 모델에 전달해 루프를 이어가게 한다(PreToolUse의 `exit 2`와 목적이 다르다 — 도구 호출을 막는 게 아니라 *종료를 되돌린다*). **`require-evidence`의 조건부란**: 검사 1~3(checkpoint·증거 없음·미커밋)은 **비차단 경고 그대로**이고, **검사 4(자율 루프 미완료 정지)만** 차단한다 — 6조건 AND(미완료 task + implement-task 발동 흔적 + 예고 문구 positive 매치 + 정당 정지 신호 없음 + **사용자가 중단·한정을 지시하지 않음** + 차단 3회 미만)를 모두 만족할 때만이며, 판정 불가는 전부 fail-open이다. 우회는 `CLAUDE_HARNESS_QUICK=1`. **`warn-commit-secrets`의 조건부란**: 고신뢰 시크릿 라벨(`secret-patterns.ps1`의 `Get-HighConfidenceSecretLabels` — 개인키·DB 연결 문자열·DB/서비스 URI 인증정보·자격증명 쌍)이 있을 때만 차단하고, 저신뢰 라벨(password 값·API key·Bearer·IP·비인용 자격증명 쌍)과 `.env` 스테이징은 종전대로 경고다. **스캔 대상은 스테이징 diff + 명령에 `git add`가 있으면 그 대상의 신규 유입분 — 추적 파일은 `git diff HEAD` 추가 라인만, untracked 파일은 워킹트리 전체 내용**(v1.119.0 — PreToolUse는 실행 전에 돌아 `git add -A && git commit` 한 호출 시 인덱스가 비어 있고 untracked는 `diff HEAD`에도 없다. 사고의 실제 경로이자 자율 루프의 표준 커밋 형태 / v1.136.0 — 추적 파일은 추가 라인만으로 정밀화: 이력에 이미 있는 내용의 재신고는 보호 효과 0에 차단 비용만 낳는다). **편집 시점 검사(`post-write-checks`)도 v1.147.0부터 같은 논리다** — 추적 파일은 `git diff HEAD --unified=0`의 추가 라인만 스캔하고, untracked·gitignore·비 git·`git diff` 실패(초기 커밋 전 저장소의 exit 128 등)는 **전재 폴백**이다. 탐지 패턴(`secret-patterns.ps1`)은 무수정이라 미탐 위험 없이 "어디를 보는가"만 좁혔다. **`git diff` 실패를 반드시 exit code로 검사할 것** — 검사하지 않으면 "추가 라인 0줄"과 구분되지 않아 스캔이 스킵되고 시크릿이 통째로 미탐된다(v1.147.0 리뷰가 실제로 잡은 결함). **단 이 규칙은 아직 편집 경로에만 적용됐다** — 커밋 경로(`bash-hook-lib.ps1`의 `diff HEAD` 보완 스캔)는 미적용이며 `docs/plans/deferred.md`에 등재돼 있다(기본 경로인 `--cached`는 HEAD 없이도 동작하므로 기본 스캔은 성립한다). **각 라벨이 실제로 매치하는 형태는 좁다** — `자격증명 쌍`은 인용부호로 감싼 두 토큰이 슬래시로 이어질 때만, `DB 연결 문자열`은 `Server=` 직후에 자격증명 키가 올 때만이다(중간 키가 낀 흔한 형태는 저신뢰 경고). 문서에 차단 범위를 적을 때 **실제보다 넓게 쓰지 말 것** — "차단한다고 썼는데 안 잡는" 상태가 가장 위험하다. **우회는 전용 변수 `CLAUDE_HARNESS_ALLOW_SECRET=1`(사용자만, Claude Code 시작 전 터미널)** — `CLAUDE_HARNESS_QUICK`으로는 꺼지지 않는다(QUICK은 스킬 단독 사용 시 켜라고 안내하는 일상 변수라, 재사용하면 자격증명 차단이 함께 꺼진다).
- **`require-plan-for-write`는 게이트 3종을 담는다**(v1.118.0): ① plan 존재 게이트(코드 Write 시 plan 필요 — `docs/plans/`는 **체크박스 plan 실재**로 판정, 디렉터리 존재만으로는 안 켜짐) ② **plan 작성 게이트**(plan 파일 Write·체크박스 도입 Edit은 `pjc:plan-feature`/`implement-task` 발동 흔적 필요) ③ AGENTS.md bootstrap 게이트. ①과 ②는 같은 정규식(`$planTaskRx`)을 공유한다 — **기준이 갈리면 그 차이가 곧 우회 경로**이므로 한쪽만 고치지 말 것.
- **SKILL 문서 작성**: `plugins/pjc/skills/AUTHORING.md` 참조("왜"를 설명, 절대 규칙만 단호하게).
- **README.md 갱신 규약**: 버전별 수정 내역(`> v1.x.y: …` changelog 블록) 기재 **금지** — 현재 기능 설명만 유지한다(변경 반영은 이력 서술 append가 아니라 기존 문장을 현재 동작에 맞게 수정, 제거된 기능 설명은 삭제). 버전 표기는 상단 `**버전**:` 1곳만 두고 릴리즈 시 `plugin.json` version과 **함께** 갱신한다(2026-07-15 동기화 누락·changelog 재유입 지적으로 확정 — 이력은 git 커밋이 정본).

## DO NOT
- 실제 비밀번호·API 키·토큰·시크릿·DB 연결문자열·내부 IP/호스트를 코드·문서·notes·plan에 기록(환경변수 이름만 적고 값은 `.env`로).
- **`block-destructive.ps1`·`protect-harness.ps1`의 차단 동작 변경** — 안전 임계 hook(끌 수 없음, 마지막 방어선). protect-harness는 설치본 hook 스크립트·hooks.json을 Write/Edit로 개조해 안전장치를 무력화하는 시도를 차단한다. 헤더 경고 참조. **단 "정상 작업 오차단만 없애고 위험 차단은 유지"하는 오탐 수정은 골든 회귀(신규 통과 케이스 + 수정 전 차단 음성 대조)로 실증하는 조건에서 허용된다(2026-07-08 하니스 품질 검토 승인 — v1.98.0 $env: cap·chmod 조건화·heredoc 스트립 등).** **미탐 보완(차단 범위 확대)도 같은 실증 조건에서 허용된다(2026-07-20 코드 검토 승인 — v1.129.0 `\rm` 앞 경계: 골든 red-green 2건 + **델타 음성 2건(이것이 오차단 0의 근거)** + 무회귀 음성 2건). 오탐 수정과 달리 차단이 늘어나므로, 새 경계가 실제로 발화하는 "델타 음성" 케이스로 오차단 0을 반드시 실증할 것 — 통과만 확인하는 무회귀 케이스는 근거가 되지 못한다.**
- 자동 생성·캐시 디렉터리(`__pycache__/`, lock 파일 등) 커밋.
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass`(백신이 공격 도구로 오인해 격리할 수 있음).

## Plan Location
- 단일 plan: `plan.md`(덮어쓰기 방식).
- **`plan.md`·`notes.md`·`notes-archive/`는 `.gitignore`(로컬 전용)** — git에 안 올라간다. 커밋되는 건 코드·문서(README 등)뿐이며, 작업의 영구 기록은 로컬 `notes.md`에 둔다.
- PRD: `docs/prd.md` (Opus 5 세대 대응 작업분 — active FR 14건·NFR 6건). **소규모 후속 작업은 이 PRD에 닿는지 경량 확인만 하고**(plan-feature Step 1), 닿지 않으면 plan에 `**PRD**:` 줄을 두지 않는다(무관한 과거 PRD를 끌어와 거짓 미충족을 보고하지 않기 위함 — Phase G 진입은 그 줄이 단일 신호).

## OS/플랫폼
- Windows 검증 · macOS/Linux 실험적(hooks는 pwsh 7 cross-platform 의도). 검증/배포는 Windows 기준.
