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
# orphan-process-cleanup도 같은 이유로 헬퍼이면서 보호 대상이다 — 회수 함수 모듈 하나를 개조하면
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

