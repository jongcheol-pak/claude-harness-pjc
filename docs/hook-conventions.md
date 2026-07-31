# hook 출력 규약 — 상세

> `AGENTS.md`의 `## Conventions` → **hook 출력 규약** 항목의 상세본이다. AGENTS.md는 세션 시작 시 전문이 자동 주입되므로 **16KB 상한**(`session-context.ps1`의 `$agentsMaxBytes`)을 지켜야 하고, 그 예산에 담기지 않는 조건부 차단의 세부 조건·스캔 범위·라벨 매치 형태를 여기로 옮겼다.
>
> **AGENTS.md에는 요약(차단 형태 2종 · 각 형태의 hook 이름 · 우회 변수 2종)이 남아 있다.** 이 파일은 그 요약을 펼친 것이며, hook을 수정하거나 차단 범위를 문서에 적을 때 읽는다.

## 출력 형태

- **경고**: `exit 0` 비차단 + stderr + additionalContext.
- **차단**은 두 형태다.
  - ① **`exit 2`** — `block-destructive` · `protect-harness` · `require-plan-for-write` · `require-task-checkbox`, 그리고 **`warn-commit-secrets`(조건부)**.
  - ② **`stdout JSON`(`{"decision":"block","reason":…}`) + `exit 0`** — **`require-evidence`(조건부)**.

②는 Stop hook 전용 형태로, 종료를 막고 `reason`을 모델에 전달해 루프를 잇는다. PreToolUse의 `exit 2`와 목적이 다르다 — 도구 호출을 막는 게 아니라 *종료를 되돌린다*.

## `require-evidence`의 조건부란

검사 1~3(checkpoint · 증거 없음 · 미커밋)은 **비차단 경고**이고, **검사 4(자율 루프 미완료 정지)만** 차단한다. 차단은 **6조건 AND**를 모두 만족할 때만이다:

1. 미완료 task 존재
2. `implement-task` 발동 흔적
3. 예고 문구 positive 매치
4. 정당 정지 신호 없음
5. **사용자가 중단·한정을 지시하지 않음**
6. 차단 3회 미만

**판정 불가는 전부 fail-open**이다. 우회는 `CLAUDE_HARNESS_QUICK=1`.

## `warn-commit-secrets`의 조건부란

고신뢰 라벨만 차단하고 저신뢰 라벨은 경고다.

- **고신뢰(차단)** — `secret-patterns.ps1`의 `Get-HighConfidenceSecretLabels`: 개인키 · DB 연결 문자열 · DB/서비스 URI 인증정보 · 자격증명 쌍.
- **저신뢰(경고)** — password 값 · API key · Bearer · IP · 비인용 자격증명 쌍, 그리고 `.env` 스테이징.

### 스캔 대상

스테이징 diff + 명령에 `git add`가 있으면 그 대상의 신규 유입분이다 — **추적 파일은 `git diff HEAD` 추가 라인만, untracked는 워킹트리 전체 내용**이다. PreToolUse는 실행 전에 돌기 때문에 `git add -A && git commit` 한 호출 시 인덱스가 비어 있고, untracked는 `diff HEAD`에도 없다.

**편집 시점 검사(`post-write-checks`)도 같은 논리다** — 추적 파일은 `git diff HEAD --unified=0` 추가 라인만 보고, untracked · gitignore · 비 git · `git diff` 실패(초기 커밋 전 exit 128 등)는 **전재 폴백**이다. 탐지 패턴은 무수정이라 미탐 위험 없이 "어디를 보는가"만 좁힌 것이다.

> **`git diff` 실패를 반드시 exit code로 검사할 것.** 검사하지 않으면 "추가 라인 0줄"과 구분되지 않아 스캔이 스킵되고 시크릿이 통째로 미탐된다.

**단 이 규칙은 편집 경로에만 적용됐다** — 커밋 경로(`bash-hook-lib.ps1`의 `diff HEAD` 보완 스캔)는 미적용이며 `docs/plans/deferred.md`에 등재돼 있다(기본 경로인 `--cached`는 HEAD 없이도 동작하므로 기본 스캔은 성립한다).

### 각 라벨이 실제로 매치하는 형태는 좁다

- `자격증명 쌍` — 인용부호로 감싼 두 토큰이 슬래시로 이어질 때만.
- `DB 연결 문자열` — `Server=` 직후에 자격증명 키가 올 때만(중간 키가 낀 흔한 형태는 저신뢰 경고).

그래서 문서에 차단 범위를 **실제보다 넓게 쓰지 말 것** — "차단한다고 썼는데 안 잡는" 상태가 가장 위험하다.

### 우회

**전용 변수 `CLAUDE_HARNESS_ALLOW_SECRET=1`**(사용자만, Claude Code 시작 전 터미널)이다. `CLAUDE_HARNESS_QUICK`으로는 꺼지지 않는다 — QUICK은 일상 변수라 재사용하면 자격증명 차단이 함께 꺼진다.
