# `guard-harness` 판정 근거

> `guard-harness.ps1`의 주석에서 옮긴 판정 근거다. 스크립트에는 각 자리에 이 문서의 절을 가리키는 1줄만 남겼다.
> **문면을 요약하지 않고 이동만 했다** — 이관은 이동이지 요약이 아니다.

## §1 guard-harness.ps1 — PreToolUse hook: Write/Edit 대상이 하니스 자신·AGENTS.md 경계를 침범하는지 검사

```
# guard-harness.ps1 — PreToolUse hook: Write/Edit 대상이 하니스 자신·AGENTS.md 경계를 침범하는지 검사
#
# 담당 조항(정본: `plugins/pjc/skills/DESIGN.md`의 hook 담당 조항 표):
#   E4 하니스 자기 게이트 무력화 차단 · E6 AGENTS.md 내용 경계.
#   둘을 한 파일에 둔 이유는 판정 입력이 같기 때문이다 — 둘 다 대상 경로 하나로 갈린다.
#
# 게이트 ①(설치본 hook 개조)은 끌 수 없다 — 안전 임계다.
# 게이트 ②(AGENTS.md 경계)는 `CLAUDE_HARNESS_QUICK=1`로 우회된다.
```

## §2 하니스 hook·공유 헬퍼 이름 집합 — post-write-checks.ps1 H2 의 $harnessHookName 과 동일 유지(탐지↔차단 대칭).

```
# 하니스 hook·공유 헬퍼 이름 집합 — post-write-checks.ps1 H2 의 $harnessHookName 과 동일 유지(탐지↔차단 대칭).
# hook 신설 시 여기에 함께 추가할 것(v1.96.0 warn-commit-secrets 누락이 v1.97.2에서 뒤늦게 합류한 전례).
# secret-patterns는 hook이 아닌 dot-source 헬퍼지만, 설치본 개조 시 시크릿 경고 계층(post-write·
# warn-commit-secrets)이 동일하게 무력화되는 등가 우회라 보호 대상에 포함한다.
# session-end-cleanup-lib도 같은 이유로 헬퍼이면서 보호 대상이다 — 회수 함수 모듈 하나를 개조하면
# 그것을 dot-source하는 두 hook(session-context·session-end-cleanup)의 고아 프로세스
# 회수가 한꺼번에 무력화된다(secret-patterns와 동형의 등가 우회).
# 자기보호 대상 이름 집합은 `rules/harness-hooks.json`이 단일 정본이다 —
#   탐지(post-write-checks)와 차단(이 파일)이 같은 값을 써야 대칭이 성립하는데,
#   두 파일에 복제하면 hook을 신설할 때 한쪽만 갱신돼 그 이름이 조용히 무방비가 된다.
```

## §3 규칙

```
# (2) 8.3 단축명 마스킹 우회(H3) — .claude를 CLAUDE~1로 숨겨 위 리터럴 매칭을 우회하는 설치본 hook 경로를
#   잡는다. "실제 마스킹 형태(CLAUDE~N) + hook명 + 설치 캐시(/plugins/cache/)"로 판정한다.
#   일반 8.3 세그먼트(PROGRA~1·RUNNER~1)는 $has83 미매치라 무영향.
```

## §4 규칙

```
# ---- (1) plan 진행 상태·세션 인계 서술 ----
# 헤딩(`## …`) 또는 볼드 제목(`**…**`) 또는 목록 제목 형태일 때만 잡는다.
#   본문 산문에 스쳐 지나가는 "다음 작업"까지 막으면 정상 문장이 걸린다.
```

## §5 규칙

```
# ---- (2) 디렉터리 트리 블록 ----
# **박스 드로잉 문자를 포함한 줄이 3줄 이상 연속**일 때만.
#   ⚠ ASCII 파이프(`|`)는 판정에 넣지 않는다 — `ls | grep x` 같은 명령 예시와 마크다운 표가
#     전부 걸린다. 트리를 그리는 실제 문자는 박스 드로잉이고, ASCII 트리(`|-- src/`)를 놓치는
#     대신 오차단 0을 택했다(이 게이트는 미탐보다 오탐이 비싸다).
```


## §6 이름 집합 로드 실패

**`-ErrorAction Stop` 이 없으면 그 `catch` 는 죽은 코드다.** 이 파일은 머리에서 `$ErrorActionPreference = 'SilentlyContinue'` 를 세우는데, 그 상태에서 `Get-Content` 의 파일 부재는 **non-terminating error** 라 `try/catch` 를 그냥 지나간다. 변수는 `$null` 이 되고 뒤 폴백이 조용히 걸려, **검사가 사라진 것을 아무도 모른다**(회차 53 실측 — 규칙 json 을 지우고 돌리면 stderr 한 줄 없이 통과했다). `block-destructive.ps1` 만 파일 전역이 `'Stop'` 이라 같은 파이프라인 형태로도 `catch` 가 걸린다 — 그 파일의 가시화가 실제로 동작하는 이유이고, 나머지 hook 은 **지역 `-ErrorAction Stop`** 으로 같은 상태를 만든다(전역을 바꾸면 이번에 재지 않은 경로가 함께 바뀐다).

**이름 집합이 비어도 `throw` 한다** — `$hookNames` 가 `$null` 이면 `-join '|'` 이 **빈 문자열**을 내고, 그것이 `'/\.claude/.*/(' + $harnessHookName + ')\.ps1$'` 에 들어가면 **빈 대안**이 되어 정규식이 무너진다. 폴백 `'(?!)'`(절대 매치 안 함)로 가는 것이 의도이므로 그 자리에서 예외로 만든다.

## §7 이름과 독립된 경로 축

`$isHookScript` 의 네 번째 축은 `(?i)/\.claude/.*/scripts/[^/]+\.ps1$` 다 — **이름 목록을 전혀 쓰지 않는다.**

**왜 필요한가** — §6 의 폴백 `'(?!)'` 는 이름 축을 **끄는 것**이라, 로드가 실패하면 설치본 hook 스크립트 개조가 그대로 통과한다(회차 53 실측: 규칙 json 을 지우면 `~/.claude/…/scripts/guard-bash.ps1` 쓰기가 `rc=0` 무출력). **이름 목록은 로드 실패로 사라질 수 있고 경로는 사라지지 않는다** — 그래서 마지막 방어선을 경로 위에 세운다.

**소유를 가리지 않는 것은 의도된 선택이다.** 이 축은 pjc 소유 여부를 구분하지 않아 다른 플러그인의 `.claude/**/scripts/*.ps1` 도 막는다. 가르려면 **플러그인 이름 목록**이 필요한데, 그 목록이야말로 로드 실패로 사라지는 바로 그것이라 자기순환이다. `.claude/` 아래 `scripts/` 에 놓인 `.ps1` 은 hook 이든 그 dot-source 대상이든 **개조되면 안전망이 함께 무너지는 자리**이므로, 넓게 잡는 쪽을 택했다.

**비-hook 헬퍼까지 막히는 것도 의도다** — `guard-commit-secrets.ps1`·`secret-patterns.ps1` 같은 dot-source 대상이 개조되면 그것을 부르는 hook 이 함께 무너진다. 이름 목록에 없다고 통과시키면 보호면에 구멍이 남는다.

**경계는 세 조각으로 잰다** — 회차 53 실측: `.claude` 세그먼트만 없는 개발 레포 경로 · `scripts/` 아래인데 확장자가 `.ps1` 이 아닌 것 · `.claude/` 인데 `scripts/` 하위가 아닌 `.ps1`. 셋 다 `exit 0` 이고, 각각 새 경계에서 **한 조각씩만** 어긋난 근접형이라 오차단 0 을 실제로 잰다.

**이 판정은 「개발 레포 경로에 `.claude` 세그먼트가 없다」는 전제 위에 있다**(§5 의 안내문이 이미 그렇게 적는다) — 레포를 `~/.claude/` 아래 클론하면 자기 자신을 막는다.
