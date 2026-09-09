# `guard-bash` 판정 근거

> `guard-bash.ps1`의 주석에서 옮긴 판정 근거다. 스크립트에는 각 자리에 이 문서의 절을 가리키는 1줄만 남겼다.
> **문면을 요약하지 않고 이동만 했다** — 이관은 이동이지 요약이 아니다.

## §1 guard-bash.ps1 — PreToolUse hook: Bash/PowerShell 도구 호출 시 6종 검사를 한 프로세스에서 수행

```
# guard-bash.ps1 — PreToolUse hook: Bash/PowerShell 도구 호출 시 6종 검사를 한 프로세스에서 수행
#
# 담당 조항(정본: `plugins/pjc/skills/DESIGN.md`의 hook 담당 조항 표):
#   E2 외부·비가역 작업 승인 · E3 커밋 시크릿 · E7 task 체크박스 갱신.
#   부수 경고 둘(전역 탐색·위험값 대입)은 대응하는 독립 hook이 없고 이 파일이 유일한 실행 경로다.
#
# block-destructive는 여기 합치지 않는다 — 끌 수 없는 마지막 방어선이라 이 파일의 로드 실패가
#   그쪽에 영향을 주면 안 된다(hooks.json 독립 엔트리 유지).
#
# 출력 계약:
#   - 차단(task 체크박스·시크릿) 발생 → 그 사유만 stderr + exit 2. warn 경고는 출력하지 않는다
#     (차단된 커밋이라 안전 회귀가 아니며, 차단 해소 후 재시도에서 노출된다).
#   - 차단 없음 → warn 경고를 stderr로, additionalContext는 단일 JSON으로 병합해 stdout + exit 0.
#
# 트레이드오프(수용): 차단 게이트가 이 파일의 로드에 결합돼 있어 로드 실패 시 5검사가 모두
#   미수행된다(fail-open). 아래 로드 가드가 그 상태를 stderr로 가시화한다.
```

## §2 검사 6종을 한 프로세스에 담는 구조

v1.225.0이 Bash 계열 hook 을 `guard-bash.ps1` 하나로 통폐합하며 공유 모듈 `bash-hook-lib.ps1` 을 삭제했다.
종전에는 검사 로직을 그 모듈에 두고 ① 검사마다 standalone 래퍼 ② 단일 디스패처
두 경로가 그것을 dot-source 했는데, **지금은 실행 경로가 하나뿐이라 그 이중화가 필요 없다.**
dot-source 자체는 하나 남아 있다 — `guard-commit-secrets.ps1`(아래).

현행 구조:

- **검사 6종 중 5종이 `guard-bash.ps1` 안의 함수다** — `Invoke-WarnExternalOps` ·
  `Invoke-RequireTaskCheckbox` · `Invoke-BlockPlanWrite` · `Invoke-WarnGlobalFind` · `Invoke-WarnDangerousAssignment`.
  **`Invoke-WarnCommitSecrets` 하나만 `guard-commit-secrets.ps1` 에 있고 dot-source 한다** —
  그 파일이 커밋 시점 검사 전체(스캔 캡·우회 변수·시크릿 패턴 연동)를 담아 크기가 따로 놀고,
  분리해 두어야 골든이 그 파일만 단독 프로브할 수 있다. 로드 실패는 침묵하지 않는다 —
  `guard-bash.ps1` 이 `Get-Command` 로 확인해 stderr 로 알린다(비차단 fail-open).
  파일 끝의 `$checks` 배열이 함수명 ↔ **rule 이름**을 짝지어 순서대로 부른다.
- **rule 이름은 옛 hook 이름을 그대로 쓴다** — `warn-external-ops` 등 다섯은 hook 으로는
  사라졌지만 이벤트 로그·골든 필터가 그 이름으로 돌아 식별자로 살아 있다. **삭제 자산으로
  오인하지 말 것**(`plugins/pjc/evals/check-stale-refs.py` 의 DEAD 목록이 이 다섯을 뺀 이유).
- **함수 계약**: 파싱된 `$data`(hook stdin JSON) → 결과 객체
  `@{ Block = [bool]; Stderr = [string[]]; Context = [string] }`.
  **`Block = $true`(exit 2)를 내는 경로는 셋이다** — `require-task-checkbox` 1곳
  (`guard-bash.ps1`) + `warn-commit-secrets` 2곳(`guard-commit-secrets.ps1` 의 시크릿 검출·
  스캔 캡 초과). `check-block-coverage.py` 가 세는 「guard-bash 경로 1 · guard-commit-secrets
  경로 2」가 그 셋이다. 나머지 3종은 경고 전용이라 `Block` 을 세우지 않는다.
  출력·exit 번역은 파일 하단의 단일 caller 가 하고, 각 함수는 「판정 → 결과」만 낸다.
- **한 검사의 예외는 나머지를 막지 않는다** — `foreach` 안에서 `try/catch` 로 격리하고
  안전측으로 통과시킨다. 다섯 중 하나가 깨져 전체가 침묵하는 것을 막는다.
- **`New-HookResult` 생성기도 `guard-commit-secrets.ps1` 에 있다** — 그쪽이 이 생성기를
  쓰므로 정의를 거기 두어야 그 파일 단독 dot-source(골든 프로브)가 성립한다.
- **`block-destructive.ps1` 은 여기 합치지 않는다** — 「끌 수 없는 마지막 방어선」이라
  공유 로드 실패에 결합시키지 않고 `hooks.json` 독립 엔트리로 직접 실행한다(결정 B).

## §3 warn-global-find: 루트 전역 탐색 경고

```
# ---- warn-global-find: 루트 전역 탐색 경고 (회수 불가능한 고아를 애초에 막는다) ----
# 왜 차단이 아니라 경고인가: 루트부터 훑어야 하는 정당한 경우를 배제할 수 없다. 다만 그 명령은
#   Bash 도구의 10분 캡 안에 끝나지 않아 **셸만 죽고 자식 find가 고아로 남는다** — 2026-08-20에
#   `find / …` 12건이 15~20시간을 돌며 코어 3개를 먹고 있었고, 그중 다수는 커널에 갇혀
#   `Stop-Process`·`taskkill`이 모두 무효였다(회수로 닫히지 않는다). 그래서 예방이 본류다.
# 범위: `find`의 시작점만 본다 — "느린 명령 일반"을 다루는 틀을 만들지 않는다(무엇이 느린지는
#   인자·대상에 달려 있어 일반화하면 오탐이 폭증한다. 실측된 고아는 전부 find였다).
# 판정: 세그먼트별 첫 실효 토큰이 find일 때만, 그 뒤 첫 비플래그 인자를 탐색 시작점으로 본다.
#   `xargs find /`는 첫 토큰이 xargs라 대상이 아니다(의도된 미탐 — 인자 조합이 무한해 안전하게
#   판정할 수 없고, 실측 12건이 전부 직접 호출이었다). 인용부호 안의 find도 첫 토큰이 아니라 제외된다.
```

## §4 루트·홈 최상위·드라이브 루트만 대상. `/usr`·`./src`·`~/.cargo/registry`는 범위가 한정돼 통과한다.

```
        # 루트·홈 최상위·드라이브 루트만 대상. `/usr`·`./src`·`~/.cargo/registry`는 범위가 한정돼 통과한다.
        # 트레일링 슬래시를 허용한다 — git-bash에서 `~/`·`/c/`가 일상 표기이고, 슬래시 하나 차이로
        #   경고가 통째로 빠지면 이 검사의 존재 이유가 무너진다(실측: 종전 패턴이 `~/`·`/c/`를 놓쳤다).
```

## §5 warn-dangerous-assignment: 위험 경로를 담은 변수를 삭제 명령에 쓰는 형태 경고

```
# ---- warn-dangerous-assignment: 위험 경로를 담은 변수를 삭제 명령에 쓰는 형태 경고 ----
# 왜 차단이 아니라 경고인가: block-destructive는 정규식이라 `X=/; rm -rf $X`처럼 값이 변수를
#   한 번 거치면 미탐한다(그 파일 헤더가 "의도된 트레이드오프"로 선언한 사각). 그 hook은
#   "끌 수 없는 마지막 방어선"이라 차단 범위를 넓히면 오차단의 대가가 크고 되돌리기도 어렵다.
#   그래서 차단 동작은 그대로 두고, 같은 명령줄에 드러난 형태만 실행 전에 알린다.
# 범위(비추상화 선언): 데이터플로 분석을 하지 않는다. **같은 명령줄 안의 대입만** 본다 —
#   앞선 도구 호출에서 만든 변수·파일에서 읽은 값·명령치환(`X=$(echo /)`)은 대상 밖이다.
#   범위를 넓히면 오탐이 늘고, 경고 피로가 생기면 경고 자체가 없는 것과 같아진다.
# 판정: 세그먼트를 앞에서부터 훑으며 대입을 기록하고, 세그먼트의 첫 실효 토큰이 삭제 계열일 때
#   그 인자의 변수 참조를 본다. 값은 **그 사용 지점까지의 마지막 대입**이다 — 같은 줄에서
#   변수가 재대입되면 뒤 대입이 앞 대입을 덮는다(`X=/tmp/a; X=/; rm -rf $X`는 `/`로 본다).
```

## §6 위험값: 루트·홈 최상위·드라이브 루트.

```
    # 위험값: 루트·홈 최상위·드라이브 루트. warn-global-find의 탐색 시작점 판정과 같은 형태이지만
    #   재는 대상이 다르므로(그쪽은 인자, 이쪽은 대입값) 공통 함수로 묶지 않는다.
    #   `C:\`도 인정한다 — PowerShell 도구 경로에서 드라이브 루트의 일상 표기다.
```

**회차 44 — `git restore` 를 `$localOps` 에 더했다.** `checkout -- <path>`·`checkout .` 과 등가의 워킹트리 폐기인데 목록에 없어 무경고였다(검토 실측). `--staged` 단독은 인덱스만 되돌려 워킹트리 손실이 없으므로 제외하고, `--staged --worktree`·`-W` 동반은 포함한다.

## §7 메시지성 값 스트립 — 그 값 속 push/merge/tag 텍스트가 실제 경고를 삼키지 않게(값만 제거, 플래그 토큰 보존).

```
    # 메시지성 값 스트립 — 그 값 속 push/merge/tag 텍스트가 실제 경고를 삼키지 않게(값만 제거, 플래그 토큰 보존).
    #   `gh`도 대상인 이유: 릴리즈 노트에 회차 서사를 적으면 `--notes "…git merge…"`가 통째로
    #   경고를 유발한다(v1.113.1 릴리즈 발행 때 실관찰). `-m`은 종전대로 `git`에만 건다 —
    #   `gh`의 짧은 플래그는 의미가 명령마다 달라 일괄 스트립하면 판정 대상까지 지운다.
```

## §8 순서: 원 hooks.json 순서에서 block-destructive

```
# 순서: 원 hooks.json 순서에서 block-destructive(독립)만 앞으로 뺀 나머지 3종 + warn-global-find(v1.183.0 신설)
#   + warn-dangerous-assignment(v1.199.0 신설). 뒤 둘은 대응하는 독립 hook 스크립트가 없고 이 디스패처가
#   유일한 실행 경로다. **새 검사는 경고 출력 순서를 지키는 자리에 넣는다** — 경고를 내는 검사 사이에 끼우면 기존 출력 순서가 바뀐다. `block-plan-write` 는 차단 전용(경고를 내지 않는다)이라 `require-task-checkbox` 뒤에 두어도 순서가 움직이지 않는다.
```


## §10 block-plan-write: plan.md 를 대상으로 하는 쓰기 명령 차단

```powershell
# block-plan-write: plan.md 를 대상으로 하는 쓰기 명령 차단
```

**왜 차단인가.** `plan.md` 는 `.gitignore` 대상이라 잘못 쓰면 **`git show` 로 복구할 수 없다.** 2026-09-09 회차 50 이 Deferred 절을 python 으로 교체하다 `s.index("## Deferred / Follow-up")` 가 Goal 문단의 **인용 문자열**을 먼저 잡아, 그 지점부터 Progress Log 직전까지를 통째로 지웠다 — 파일이 29줄만 남았다. 그 상태로 커밋 두 개가 지나갔다: 절이 사라지자 「등재 마커 실재」 축의 서식 게이트가 `DEFERRED_SECTION_RX` 실패로 **아무것도 안 본 채 exit 0** 을 냈고, `require-task-checkbox` 도 체크박스를 못 읽어 통과했다. **경고로는 부족하다** — 자율 루프가 경고를 보고도 진행하면 같은 유실이 반복되고, 그 유실은 되돌릴 수단이 없다.

**`guard-write` 가 아니라 여기인 이유.** `guard-write` 는 `Write|Edit|MultiEdit|NotebookEdit` 매처라 **스크립트 경로를 원리상 보지 못한다.** 사고 명령은 `Bash` 도구의 python 인라인이었다. 대장의 처방 후보가 hook 을 잘못 지목했고 회차 51 계획이 정정했다.

**판정은 「쓰기 구문의 대상 인자가 `plan.md` 인가」 하나다.** 초안은 *"명령에 `plan.md` 언급 ∧ 쓰기 신호 존재"* 의 논리곱이었는데, 그러면 `sed -i '/plan.md …/d' docs/plans/deferred.md` 가 걸린다 — 쓰기 대상은 `deferred.md` 인데 패턴 문자열에 `plan.md` 가 있다. **대장에 리터럴 `plan.md` 가 20회 있고**, 그 줄을 지우는 것이 정상 작업이다(계획 리뷰 BLOCKER).

**변수 역참조가 필요하다.** 사고 명령의 형태가 `p='plan.md'` → `open(p,'w')` 라 `open()` 의 첫 인자는 식별자였다. 리터럴만 매치하면 **재현 케이스가 그대로 샌다.** `Invoke-WarnDangerousAssignment` 가 쓰는 `$assigned` 해시 방식을 그대로 쓴다.

**대상 특정 7종** — ⓐ `open(…, 'w'|'a')` 의 첫 인자 ⓑ `>`·`>>` 의 대상 ⓒ `sed -i` 의 **마지막 위치 인자**(패턴 안은 대상이 아니다) ⓓ `Set-Content`·`Out-File`·`Add-Content`·`tee` 의 대상 ⓔ `cp`·`mv` 의 마지막 인자 ⓕ `Copy-Item`·`Move-Item`·`Rename-Item`(ⓔ는 별칭 텍스트만 매치한다) ⓖ `[System.IO.File]::WriteAll*`·`AppendAllText` 의 첫 인자.

**단어 경계를 두는 이유** — `plan-template.md`·`docs/plans/deferred.md` 가 부분문자열로 걸리면 정당한 작업이 막힌다. 회차 51 자신이 두 파일을 다 다뤘다.

**읽기는 막지 않는다** — `grep`·`cat`·`sed -n`·`awk`, 그리고 **`plan.md` 를 읽어 다른 파일로 내보내는 형태**(`head -12 plan.md > other.txt`)까지 통과한다. 오차단이 나면 실측·조사 자체가 막힌다.

## §11 최상위 구분자 분리(따옴표 인식)

단순 `-split` 는 **따옴표 안의 구분자에서 쪼개** 인용이 깨진다. `sed -i "s|a|b|" plan.md` 를 `|` 로 나누면 마지막 조각의 첫 토큰이 `"` 가 되어, 쓰기 동사를 첫 실효 토큰으로 판정하는 `block-plan-write` 가 이 형태를 놓쳤다(회차 51 실측 — 쓰기 32형태 중 유일한 MISS). 그래서 정규식이 아니라 **문자 단위 상태 스캔**으로 인용 구간을 지나며 나눈다. 개행도 최상위 구분자다 — 아니면 둘째 줄의 명령이 `^` 앵커 패턴을 벗어난다.

**`$PsQuoting`** — PowerShell 도구 입력이면 `\` 를 이스케이프로 보지 않는다. bash 규칙으로 읽으면 드라이브 루트를 큰따옴표로 감싼 인자(`"C:\"`) 뒤에 `;` 로 이어 붙인 파괴 명령에서 `\"` 가 인용을 열어 둔 채로 남아 `;` 분리가 안 되고, echo 스트립이 뒤 명령까지 지워 `exit 0` 이었다(회차 44 실측 — PowerShell 에서 `"C:\"` 는 닫힌 문자열이다). PowerShell 의 큰따옴표 안 이스케이프는 백틱이므로 그쪽을 대신 소비한다.

**분기별 근거** — 작은따옴표 안은 bash 에서 이스케이프가 없어 다음 `'` 까지 전부 리터럴이다. 인용 **밖**의 백슬래시도 다음 문자를 이스케이프한다 — `\"` 가 인용을 열어 구분자 분리를 깨뜨리던 미탐을 그 분기가 막는다.

**의도적 복제** — 이 함수는 `block-destructive.ps1` 과 `guard-bash.ps1` 두 곳에 같은 본문으로 있다. `block-destructive` 는 `AGENTS.md` 「DO NOT」의 마지막 방어선이라 **외부 파일 의존을 만들지 않는다** — 공유 모듈로 빼면 dot-source 실패 시 차단이 통째로 사라지고 그 경로를 재는 것이 없다. 복제의 드리프트는 `check-harness-consistency.py` 의 「분할 헬퍼 동기」 축이 잡는다.
