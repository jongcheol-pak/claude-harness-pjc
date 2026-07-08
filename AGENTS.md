# AGENTS.md — Agent Guide

> pjc 하니스 플러그인 repo. 컴파일 언어가 없는 **PowerShell hooks + Markdown skills/agents** 구성이라 표준 build/test가 없다. 아래 **워킹트리 정적 검증** 명령으로 `implement-task`의 V-1/V-2를 결정적으로 수행한다.

## Stack
- **언어/플랫폼**: Claude Code 플러그인 (pjc harness). PowerShell 7(pwsh) 우선 · Windows PowerShell 5.1 폴백. 컴파일 언어 없음.
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
  pwsh -NoProfile -Command "@('plugins/pjc/.claude-plugin/plugin.json','plugins/pjc/hooks/hooks.json','.claude-plugin/marketplace.json') | ForEach-Object { Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json | Out-Null; Write-Host ($_ + ' OK') }"
  ```
- **Hook 골든 회귀 (hook 스크립트 수정 시 필수)**:
  ```
  pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
  ```
  격리 USERPROFILE에서 hook 9종(block-destructive·protect-harness·warn-external-ops·require-plan-for-write·require-task-checkbox·suggest-agents-record·post-write-checks·require-evidence·warn-commit-secrets)을 stdin JSON 케이스로 실행해 exit code·출력을 대조한다(케이스 정본: `plugins/pjc/hooks/evals/hook-cases.json` + 러너 내장 시나리오). 전부 OK면 exit 0.
- **llm-wiki 상수·배치 정합 셀프체크 (SKILL.md 예산표·라우팅 표·references/procedures-*.md·wiki-schema §2/§3/§4·목차·lint.py 상수 수정 시 필수)**:
  ```
  python plugins/pjc/skills/llm-wiki/evals/check_consistency.py
  ```
  네 곳의 공유 상수(파일 예산·통제 어휘)와 절차 배치(본체 `## 절차 목차` 라우팅 표 **전 행** ↔ `references/procedures-content.md`·`procedures-ops.md`의 절차 헤딩 실존·1곳·위치 일치 — 절차 문자는 표에서 동적 캡처(신규 절차도 자동 검사), 체크리스트 등 비문자 행·중복 행·표에 없는 스트레이 헤딩 포함), wiki-schema 목차(부분 Read 인덱스) § ↔ `## N.` 헤딩 정합, procedures-ops F-1 실행 순서 인덱스 ↔ wiki-schema §7 검사 항목 번호 1:1 정합, 산문 크로스파일 포인터(파일-귀속 절차 라벨 ↔ 실제 `### X.` 헤딩 파일), templates.md 타입 ↔ schema §2 타입 집합을 기계 대조한다 — 전부 일치 exit 0, 불일치 exit 1, 파싱 앵커 실패 exit 2.
- **통합 검증 (재설치 후)**: `pwsh ./validate.ps1` — ⚠️ **설치 캐시**(`~/.claude/plugins/cache/...`)를 검사하므로 **워킹트리 변경은 재설치 후에만 반영**된다(`install.ps1 -Uninstall` 후 `install.ps1`). 개발 중 워킹트리 검증은 위 Build/Test로 한다.

## Repository Structure
```
<repo>/
├── .claude-plugin/marketplace.json
├── plugins/pjc/
│   ├── .claude-plugin/plugin.json   # 플러그인 버전·메타
│   ├── hooks/hooks.json             # PreToolUse/PostToolUse/Stop hook 배선
│   ├── scripts/*.ps1                # hook 구현(block-destructive·protect-harness·require-plan-for-write·require-task-checkbox·post-write-checks·require-evidence·warn-external-ops·suggest-agents-record·warn-commit-secrets) + secret-patterns.ps1(공유 dot-source 헬퍼, hook 아님)
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
- **hook 출력 규약**: 경고는 `exit 0` 비차단 + stderr + additionalContext. 차단(`exit 2`)은 `block-destructive`·`protect-harness`·`require-plan-for-write`·`require-task-checkbox`만.
- **SKILL 문서 작성**: `plugins/pjc/skills/AUTHORING.md` 참조("왜"를 설명, 절대 규칙만 단호하게).

## DO NOT
- 실제 비밀번호·API 키·토큰·시크릿·DB 연결문자열·내부 IP/호스트를 코드·문서·notes·plan에 기록(환경변수 이름만 적고 값은 `.env`로).
- **`block-destructive.ps1`·`protect-harness.ps1`의 차단 동작 변경** — 안전 임계 hook(끌 수 없음, 마지막 방어선). protect-harness는 설치본 hook 스크립트·hooks.json을 Write/Edit로 개조해 안전장치를 무력화하는 시도를 차단한다. 헤더 경고 참조. **단 "정상 작업 오차단만 없애고 위험 차단은 유지"하는 오탐 수정은 골든 회귀(신규 통과 케이스 + 수정 전 차단 음성 대조)로 실증하는 조건에서 허용된다(2026-07-08 하니스 품질 검토 승인 — v1.98.0 $env: cap·chmod 조건화·heredoc 스트립 등).**
- 자동 생성·캐시 디렉터리(`__pycache__/`, lock 파일 등) 커밋.
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass`(백신이 공격 도구로 오인해 격리할 수 있음).

## Plan Location
- 단일 plan: `plan.md`(덮어쓰기 방식).
- **`plan.md`·`notes.md`·`notes-archive/`는 `.gitignore`(로컬 전용)** — git에 안 올라간다. 커밋되는 건 코드·문서(README 등)뿐이며, 작업의 영구 기록은 로컬 `notes.md`에 둔다.
- PRD: 현재 없음.

## OS/플랫폼
- Windows 검증 · macOS/Linux 실험적(hooks는 pwsh 7 cross-platform 의도). 검증/배포는 Windows 기준.
