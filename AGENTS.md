# AGENTS.md — Agent Guide

> pjc 하니스 플러그인 repo. 컴파일 언어가 없어 표준 build/test가 없다 — 아래 **워킹트리 정적 검증**으로 `pjc:implement`의 빌드·테스트 단계를 수행한다.
> **이 파일의 내용 경계**(무엇을 담고 무엇을 담지 않는가)는 `plugins/pjc/skills/AGENTS-BOUNDARY.md`의 「AGENTS.md 내용 경계」가 정본이다.

## 위키

- **프로젝트 페이지**: `20_projects/personal/claude-harness-pjc.md` (LLM WIKI vault)
- 프로젝트 성격·기술 스택·디렉터리 구조·**아키텍처 상세**·기능 목록은 **위키가 정본**이다. 이 파일에 중복 기재하지 않는다 (단 `## Conventions`의 **아키텍처 선언 1줄**은 여기 남는다).
- 작업 규약·함정: 같은 폴더의 `conventions.md`(+ `conventions-*.md` 하위)

## Build & Test

모든 명령은 **repo 루트에서** 실행한다. **각 명령이 무엇을 대조하는지·함정은 `docs/harness-conventions.md`의 「검증 명령 상세 (무엇을 대조하는가 · 함정)」이 정본이다.**

- **Build (전 ps1 구문 검사)**:
  ```
  pwsh -NoProfile -Command "$f=0; Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { $e=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e); if($e.Count){$f++; Write-Host ('PARSE FAIL ' + $_.Name + ': ' + $e.Count)} }; if($f){exit 1}; 'parse OK'"
  ```
- **Test (JSON 매니페스트 유효성)**:
  ```
  pwsh -NoProfile -Command "@('plugins/pjc/.claude-plugin/plugin.json','plugins/pjc/hooks/hooks.json','.claude-plugin/marketplace.json') | ForEach-Object { $c = Get-Content -LiteralPath $_ -Raw -ErrorAction Stop; $null = $c | ConvertFrom-Json; Write-Host ($_ + ' OK') }"
  ```
- **Hook 골든 회귀** (hook 스크립트·골든 케이스 수정 시 필수):
  ```
  pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
  ```
  전경에서 그대로 돌아간다(v1.225.0 실측 192~429초 · 767케이스 — 무상태 그룹 샤딩으로 분리 실행 절차가 사라졌다). **완료는 시간이 아니라 `결과: N/N OK` 라인과 exit 0으로 판정한다.** 실행 전 `CLAUDE_HARNESS_QUICK`을 지울 것 — 남아 있으면 41건이 FAIL한다(`docs/golden-runner.md` 「⚠ 우회 변수 오염 — 실행 전에 `CLAUDE_HARNESS_QUICK`을 지울 것」).
- **차단 경로 커버리지** (차단 hook·골든 케이스 수정 시 필수 — 차단 사유 문구가 골든에 없으면 그 경로는 코드를 지워도 green 이다):
  ```
  python plugins/pjc/hooks/evals/check-block-coverage.py
  ```
- **llm-wiki 상수·배치 정합 셀프체크** (SKILL.md 예산표·라우팅 표·`references/procedures-*.md`·`wiki-schema` §2/§3/§4/§7/§8/§11/§12·목차·`templates.md`·`lint.py` 상수 수정 시 필수):
  ```
  python plugins/pjc/skills/llm-wiki/evals/check_consistency.py
  ```
- **llm-wiki lint 골든 회귀** (`lint.py`·골든 케이스·픽스처 수정 시 필수 — 102케이스, 약 45초. `--auto-split` 26케이스가 같은 실행에 포함):
  ```
  python plugins/pjc/skills/llm-wiki/evals/run_lint_evals.py
  ```
- **AGENTS.md 이관 골든** (`relocate-agents.py` 수정 시 필수 — 14케이스):
  ```
  python plugins/pjc/skills/record-project-fact/evals/run_relocation_evals.py
  ```
- **하니스 정합 셀프체크** (`plugins/pjc/evals/**`·**대장 3파일**(`deferred.md`·`deferred-closed.md`·`deferred-history.md`)·`session-context.ps1`의 절 추출 앵커·**`skills/**`·`agents/*.md`·`scripts/*.ps1`의 크기** 수정 시 필수 — 일곱 축, **exit 2는 앵커 파싱 실패이지 통과가 아니다**):
  ```
  python plugins/pjc/evals/check-harness-consistency.py
  ```

- **잘린 주석 검사** (`scripts/*.ps1`·`scripts/rules/*-rationale.md` 수정 시 필수 — 근거 인용 주석의 절단과 rationale 헤딩 짝 2축):
  ```
  python plugins/pjc/evals/check-comment-truncation.py
  ```

- **삭제 자산 참조 검사** (`plugins/**`·`docs/*.md` 수정 시 필수 — 회차 1·2가 없앤 21개 이름이 살아 있는 자산에 남았는가. `--ledger` 는 대장 `## 대기` 를 본다):
  ```
  python plugins/pjc/evals/check-stale-refs.py
  ```
- **통합 검증**: `pwsh ./validate.ps1` — ⚠ **설치 캐시**를 검사하므로 워킹트리 변경은 재설치 후에만 반영된다.
- **⚠ 검증 배치에 `Remove-Item`을 인라인으로 넣지 말 것** — PowerShell 도구의 경로 보호가 오차단한다.

### 검증 매핑 (task 검증 선택)

**표 정본은 `docs/harness-conventions.md`의 「검증 매핑 (task 검증 선택)」이다** — 변경 파일 패턴 → 필수 검증. task 단위 검증은 변경 파일에 맞는 행만 실행하고(여러 패턴이면 합집합), 전체 검증은 Phase F-2가 1회 보장한다. 같은 문서의 **「골든 부분 실행의 판정 자격」**·**「조건부 참조 문서 크기 임계」**도 함께 읽는다.

## Conventions

- **인코딩**: `.ps1`은 **UTF-8 BOM 필수**(Windows PowerShell 5.1 한글 호환). 그 외(.md/.json)는 **BOM 없음**.
- **줄바꿈**: 워킹트리 **CRLF**·`core.autocrlf=true`. ⚠ **`sed -i`도 `Edit` 도구도 파일 전체를 LF로 바꿀 수 있다** — blob이 정규화돼 **`git diff`에 안 나타나므로** 조용히 누적된다(v1.214.0 실측: `Edit`으로 1줄만 고친 `README.md`·`plugin.json`이 `w/lf`가 됐다). **판정은 `git ls-files --eol <파일>`**(미수정 파일과 대조 — 정상은 `w/crlf`), **복원은 python `newline=""`로 읽어 `\r\n`으로 다시 쓴다**.
- **주석**: 한글, "왜"를 설명("무엇"은 코드로).
- **명령 출력 예산**: 판정용 명령은 판정에 필요한 최소 형식으로 — `git status --porcelain`(clean이면 0B) · `git diff --stat` 선행 · `git blame -L` 범위 지정 · `gh`는 `--json <필드> --jq <표현식>`로 필드 지정. **단 `git log`는 `--oneline`으로 줄이지 않는다** — 커밋 본문에 회차 서사와 검증 결과가 담긴다. 실측 표·미채택 근거는 `docs/harness-conventions.md` 「명령 출력 예산」이 정본.
- **파일 크기**: 문서 예산과 분할 판정은 `plugins/pjc/skills/DESIGN.md` 4절이 정본.
- **hook 출력 규약**: 경고는 `exit 0` 비차단 + stderr + additionalContext. 차단은 **`exit 2`** 하나이고 그것을 내는 hook은 넷이다 — `block-destructive`(파괴적 명령) · `guard-bash`(task 체크박스 게이트 + 커밋 시크릿(조건부)) · `guard-write`(plan 게이트) · `guard-harness`(자기보호 + AGENTS.md 내용 경계). **커밋 시크릿의 조건부 세부·스캔 범위는 `docs/harness-conventions.md`가 정본** — hook 수정 전 반드시 읽을 것. **우회 변수는 둘이며 서로 대체되지 않는다**: `CLAUDE_HARNESS_QUICK`(`guard-write`·`guard-harness`의 AGENTS.md 내용 경계·`guard-bash`의 체크박스 게이트) / `CLAUDE_HARNESS_ALLOW_SECRET`(커밋 시크릿 차단 전용). **`guard-write`의 plan 존재 게이트에는 우회 변수와 별개로 파일 단위 면제 경로가 있다** — `pjc:plan`이 사용자 승인을 받아 남긴 `[PLAN-EXEMPT]` 표식에 적힌 파일만 통과한다(판정 상세는 `docs/harness-conventions.md`의 「`guard-write`의 PLAN-EXEMPT 면제 경로」).
- **`guard-write`는 게이트 2종**: ① plan 존재 ② plan 작성. 둘은 같은 정규식(`$planTaskRx`)을 공유하므로 **한쪽만 고치지 말 것**(차이가 곧 우회 경로). **`guard-harness`는 자기보호와 AGENTS.md 내용 경계 2종이다** — AGENTS.md **신규 생성** 게이트는 v1.227.0에 없앴다(생성이 `pjc:plan` Step 1의 최소 골격으로 바뀌어 차단 대상이 소멸했다).
- **⚠ `llm-wiki`의 절차 이름·번호·쓰기 범위를 바꾸면 글로벌 `~/.claude/CLAUDE.md`의 vault 예외를 함께 확인**한다 — 검사기가 잡지 못한다(repo 밖). 필수 결합 2건·판정 기준은 `docs/harness-conventions.md`의 「llm-wiki ↔ 글로벌 지침 결합 (동반 수정 판정)」이 정본.
- **SKILL 문서 작성**: 형식은 `plugins/pjc/skills/AUTHORING.md`, **설계 원칙(규약 문면 형식·자기참조 금지·문서 예산)은 `plugins/pjc/skills/DESIGN.md`가 정본**이다.
- **위키 연동**: 계획·구현이 위키를 언제 읽고 언제 쓰는지는 `plugins/pjc/skills/WIKI.md`가 정본.
- **README.md 갱신 규약**: 버전별 changelog 블록 기재 **금지** — 현재 기능 설명만 유지한다(제거된 기능 설명은 삭제). 버전 표기는 상단 1곳만 두고 릴리즈 시 `plugin.json`과 **함께** 갱신한다. 이력은 git 커밋이 정본이다.
- **규약 개정 요청**: 요청이 이 레포 규약에 걸려도 「규약이 금지한다」로 작업을 제외·전환하지 않는다 — **현행 규약 안의 안**과 **규약을 함께 고치는 안**을 둘 다 제시한다. 정본은 `docs/harness-conventions.md`의 「규약 개정 요청의 취급」.

## 데이터 접근

- 없음 (DB·외부 스토어를 쓰지 않는다).

## 산출물·파일 관리

- 캐시: `__pycache__/`·`.state` (커밋 금지)
- 설치본: `~/.claude/plugins/cache/pjc-harness/` (워킹트리와 별개 — `validate.ps1`이 검사하는 대상)

## DO NOT

- 실제 비밀번호·API 키·토큰·시크릿·DB 연결문자열·내부 IP/호스트를 코드·문서·notes·plan에 기록(환경변수 이름만, 값은 `.env`로).
- **`block-destructive.ps1`·`guard-harness.ps1`의 차단 동작 변경** — 안전 임계 hook(끌 수 없음, 마지막 방어선). **각 hook이 무엇을 차단하는지는 `plugins/pjc/scripts/rules/`의 판정 데이터와 근거 문서가 정본이다.** **단 두 종류는 사용자 승인 선례로 허용된다**: ① **오탐 수정** — 골든 회귀(신규 통과 케이스 + 수정 전 차단 음성 대조)로 실증하는 조건 ② **미탐 보완**(차단 범위 확대) — 같은 조건 + **새 경계가 실제로 발화하는 「델타 음성」 케이스로 오차단 0을 반드시 실증**할 것(통과만 확인하는 무회귀 케이스는 근거가 못 된다).
- 자동 생성·캐시 디렉터리(`__pycache__/`, lock 파일 등) 커밋.
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass`(백신이 격리할 수 있음).

## Plan Location

- **plan은 루트 `plan.md` 하나**다(덮어쓰기). 위치 선택지가 없으므로 `Plan Location:` 선언을 두지 않는다.

- **`plan.md`·`notes.md`·`notes-archive/`는 `.gitignore`(로컬 전용)** — **작업의 영구 기록은 git 커밋**이고, 미처리 Deferred는 커밋되는 `docs/plans/deferred.md`가 담는다(v1.198.0부터 **대장은 셋** — 대기는 `deferred.md`, 기각 종결은 `deferred-closed.md`, 소진 batch 회고는 `deferred-history.md`. **계획 때 여는 것은 `deferred.md` 하나**이고 나머지 둘은 batch·차수 대조 때만 연다).
- **PRD는 쓰지 않는다** — 요구는 `plan.md`의 `## 요구 이해`, 결정 이력은 위키 `decisions.md`, 미착수 항목은 `docs/plans/deferred.md`가 담는다.

## OS/플랫폼

- Windows 검증 · macOS/Linux 실험적(hooks는 pwsh 7 cross-platform 의도). 검증·배포는 Windows 기준.
- **Claude Code**: 최소 v2.0 · **권장 v2.1.219+**(`completion-reviewer`의 `opus` 별칭 해소 기준).
