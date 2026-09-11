# AGENTS.md — Agent Guide

> pjc 하니스 플러그인 repo. 표준 build/test 가 없어 아래 **워킹트리 정적 검증**이 `pjc:implement` 의 빌드·테스트 단계다.
> **이 파일의 내용 경계**(무엇을 담고 무엇을 담지 않는가)는 `plugins/pjc/skills/AGENTS-BOUNDARY.md`의 「AGENTS.md 내용 경계」가 정본이다.

## 위키

- **프로젝트 페이지**: `20_projects/personal/claude-harness-pjc.md` (LLM WIKI vault)
- 프로젝트 성격·기술 스택·구조·**아키텍처 상세**·기능 목록은 **위키가 정본**이다(단 `## Conventions` 의 아키텍처 선언 1줄은 남는다).
- 작업 규약·함정: 같은 폴더의 `conventions.md`(+ `conventions-*.md` 하위)

## Build & Test

모든 명령은 **repo 루트에서** 실행한다. **각 명령이 무엇을 대조하는지·함정·소요 시간·케이스 수 기준선은 `docs/harness-conventions.md`의 「검증 명령 상세」가 정본**이다 — 여기에는 명령과 트리거만 둔다.

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
- **차단 경로 커버리지** (차단 hook·골든 케이스 수정 시 필수): `python plugins/pjc/hooks/evals/check-block-coverage.py`
- **llm-wiki 상수·배치 정합** (`skills/llm-wiki/**` 수정 시 필수): `python plugins/pjc/skills/llm-wiki/evals/check_consistency.py`
- **llm-wiki lint 골든 회귀** (`lint.py`·골든 케이스·픽스처 수정 시 필수):
  ```
  python plugins/pjc/skills/llm-wiki/evals/run_lint_evals.py
  ```
- **AGENTS.md 이관 골든** (`relocate-agents.py` 수정 시 필수): `python plugins/pjc/skills/record-project-fact/evals/run_relocation_evals.py`
- **하니스 정합 셀프체크** (`plugins/pjc/evals/**`·**대장 3파일**·`agents/*.md`·`*.md` 수정 시 필수 · **골든 케이스 수를 바꿨으면 매니페스트 무관하게 필수** — **exit 2는 앵커 파싱 실패이지 통과가 아니다**):
  ```
  python plugins/pjc/evals/check-harness-consistency.py
  python plugins/pjc/evals/check-harness-consistency.py --fix [--dry-run]
  ```
  `--fix` 는 **판단이 0인 자리만** 고치고 `--dry-run` 은 한 바이트도 쓰지 않는다(대상·제외는 정본).
- **evals 골든 회귀** (`plugins/pjc/evals/**` 수정 시 필수 — **exit 2는 `cases.json` 서식 위반 또는 미추적 픽스처**이지 통과가 아니다):
  ```
  python plugins/pjc/evals/run-evals.py
  ```
- **잘린 주석 검사** (`scripts/*.ps1`·`scripts/rules/*-rationale.md` 수정 시 필수):
  ```
  python plugins/pjc/evals/check-comment-truncation.py
  ```
- **삭제 자산 참조 검사** (`plugins/**`·`docs/**`·**루트 `*.ps1`·`*.md`** 수정 시 필수):
  ```
  python plugins/pjc/evals/check-stale-refs.py
  ```
- **트리거 러너 종료 코드** (`skills/evals/trigger_eval.py` 수정 시 필수 · 모델 호출 없음): `python plugins/pjc/skills/evals/test_exit_code.py`
- **스킬 트리거 eval** (`skills/*/SKILL.md` frontmatter `description` 수정 시 필수 — **실제 모델 호출이라 비용이 크다**):
  ```
  python plugins/pjc/skills/evals/trigger_eval.py --filter <plan|impl|rec|wiki|dbg>
  ```
- **위키 회로 검사** (`implement/SKILL.md`·`WIKI.md`·`plan/SKILL.md`·`skills/llm-wiki/**` 수정 시 필수):
  ```
  python plugins/pjc/skills/evals/check_wiki_circuit.py
  ```
- **통합 검증**: `pwsh ./validate.ps1` — ⚠ **설치 캐시**를 보므로 재설치 후에만 반영된다.
- **Release**: 버전 정본은 `plugin.json` + `README.md` 상단 `**버전**:` 줄. **버전만 올리는 별도 커밋** → push → **곧바로 릴리즈 발행**. ⚠ 태그가 원격에만 생겨 확인은 `gh release list` 다. 절차 정본은 `docs/harness-conventions.md` 「Release (배포·릴리즈 발행)」이고 **push·릴리즈는 별도 승인**이다.
- **⚠ 검증 배치에 `Remove-Item` 인라인 금지** — 도구 경로 보호가 오차단한다(회피법은 정본).

### 검증 매핑 (task 검증 선택)

**표 정본은 `docs/harness-conventions.md`의 「검증 매핑 (task 검증 선택)」이다** — 변경 파일 패턴 → 필수 검증(합집합). **「줄바꿈 정합」 축만은 모든 task가 대상**이다. 같은 문서의 **「골든 부분 실행의 판정 자격」**·**「조건부 참조 문서 크기 임계」**도 함께 읽는다.

## Conventions

- **아키텍처**: 계층 없음 — 실행 단위가 hook 스크립트와 Markdown 지침이라 도메인/UI/인프라로 가를 대상이 없다(글로벌 「단순 스크립트·유틸리티는 대상이 아니다」).
- **인코딩**: `.ps1` 은 **UTF-8 BOM 필수**(PS 5.1 한글 호환), 그 외는 **BOM 없음**.
- **줄바꿈**: 워킹트리 **CRLF**·`core.autocrlf=true`. ⚠ **`sed -i` 도 `Edit` 도구도 python 텍스트 쓰기(`open(p,'w')`)도 파일 전체를 LF 로 바꿔 놓는다** — 편집 후 `git ls-files --eol` 로 확인(정본은 `docs/harness-conventions.md` 의 「편집 스크립트의 줄바꿈 사고」).
- **주석**: 한글, "왜"를 설명한다.
- **명령 출력 예산**: 판정용 명령은 **최소 형식**으로 낸다(정본은 `docs/harness-conventions.md` 「명령 출력 예산」).
- **파일 크기**: 상한 표·초과 처방·참조 깊이·목차 규칙은 `plugins/pjc/skills/BUDGET.md`「예산 표」가 정본. **처방은 묻지 않고 적용하고, 상한을 올리는 것은 처방이 아니다.**
- **병행 세션의 커밋은 `git commit -- <경로…>` 다** — `git add` 경로 한정으로는 상대의 staged 를 삼킨다(회차 54·55 두 번 관측). 커밋 명령에 `2>&1` 을 붙이고 **시크릿 스캔과 커밋을 한 명령에 잇지 않는다**. 근거·부분 스테이징 주의는 `docs/harness-conventions.md` 「병행 세션의 커밋」.
- **hook 출력 규약**: 경고는 `exit 0` 비차단 + stderr + additionalContext, **차단은 `exit 2` 하나**이고 그것을 내는 hook은 넷이다. **우회 변수는 둘이며 서로 대체되지 않는다.** 이름·범위·담당·면제 경로는 `docs/harness-conventions.md` 「`guard-write`의 PLAN-EXEMPT 면제 경로」가 정본 — hook 수정 전 읽을 것.
- **`guard-write` 는 게이트 2종**(plan 존재·plan 작성)이고 **같은 정규식을 공유하므로 한쪽만 고치지 말 것** — 차이가 곧 우회 경로다.
- **⚠ `llm-wiki` 의 절차 이름·번호·쓰기 범위를 바꾸면 글로벌 `~/.claude/CLAUDE.md` 의 vault 예외를 함께 확인**한다 — repo 밖이라 검사기가 못 잡는다(정본은 `docs/harness-conventions.md` 「llm-wiki ↔ 글로벌 지침 결합」).
- **SKILL 문서**: 형식은 `skills/AUTHORING.md`, **설계 원칙은 `skills/DESIGN.md` 가 정본**이다.
- **위키 연동**: `plugins/pjc/skills/WIKI.md` 가 정본.
- **README.md 갱신 규약**: changelog 기재 **금지**(현재 기능 설명만) · 버전 표기는 상단 1곳. 정본은 `docs/harness-conventions.md` 「README.md 갱신 규약」.
- **규약 개정 요청**: 「규약이 금지한다」로 제외·전환하지 않고 **현행 규약 안의 안**과 **규약을 함께 고치는 안**을 둘 다 낸다(정본은 `docs/harness-conventions.md` 의 「규약 개정 요청의 취급」).

## 데이터 접근

- 없음 (DB·외부 스토어를 쓰지 않는다).

## 산출물·파일 관리

- 캐시 `__pycache__/`·`.state` 는 커밋 금지.
- 설치본: `~/.claude/plugins/cache/pjc-harness/` (`validate.ps1` 이 검사하는 대상)

## DO NOT

- **실제 자격증명을 코드·문서·notes·plan 에 기록** — 환경변수 이름만 적고 값은 `.env` 에 둔다. 종류는 `docs/harness-conventions.md` 「자격증명 취급」.
- **`exit 2` 를 내는 넷의 차단 동작 변경** — `block-destructive.ps1`·`guard-harness.ps1`·`guard-bash.ps1`(**dot-source 하는 `guard-commit-secrets`·`guard-stale-docs` 의 커밋 판정 포함**)·`guard-write.ps1`. 안전 임계 hook(끌 수 없는 마지막 방어선)이고 차단 대상은 `plugins/pjc/scripts/rules/` 가 정본이다. **넷 전부에 오탐 수정·미탐 보완만 허용되며 골든 실증이 붙는다**(`docs/harness-conventions.md` 「안전 임계 hook 의 차단 동작 변경」).
- 자동 생성·캐시 디렉터리(`__pycache__/`, lock 파일 등) 커밋.
- **검증·테스트 스크립트에 평문 자격증명·창 숨김·과도한 실행정책 완화**(사유는 같은 절).

## Plan Location

- **plan은 루트 `plan.md` 하나**다(덮어쓰기). 선택지가 없어 `Plan Location:` 선언을 두지 않는다.
- **`plan.md`·`notes.md`·`notes-archive/`는 `.gitignore`(`intent/`는 추적)** — **영구 기록은 git 커밋**이고 미처리 Deferred 는 **대장 3파일**이 담는다(`deferred.md` 대기 · `deferred-closed.md` 종결 · `deferred-history.md` batch 회고 — 연산 규칙은 그 머리말이 정본).
- **PRD는 쓰지 않는다** — 요구는 `intent/`, 결정은 위키 `decisions.md`, 미착수는 대장이 담는다.

## OS/플랫폼

- Windows 검증 · macOS/Linux 실험적(hooks 는 pwsh 7 cross-platform 의도).
- **Claude Code**: 최소 v2.0 · **권장 v2.1.219+**(`completion-reviewer` 의 `opus` 별칭 해소).
