# scenarios/check-plan.ps1 — check-plan 시나리오 (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case)와 공유 변수($pluginRoot·$work)를 그대로 쓴다.
# 무엇을 재는가: plan.md 결정적 검사(skills/plan/scripts/check-plan.ps1)의 판정 갈래마다 한 케이스 —
#   정상 1 · A1~A6 · B1~B4 위반 · 하위 항목 상태 · 화면 줄 세 요소 · 펜스 무시 · 입력 오류 · PS 5.1 · 출력 ASCII · git 밖 건너뜀 ·
#   증거 대조(-Base) — 커밋 없음·본문 증거 없음·T10≠T1·BASE 이전 제외·통과·HUMAN-VERIFY·불요/열린 task 제외·BASE 오류·git 밖·PS 5.1.
#   코드와 뜻의 정본은 스크립트 머리 주석이다.
# 정상 plan 하나를 두고 케이스가 한 군데씩 망가뜨린다 — 정상 형상이 여러 벌이면 한쪽만 고친 채 갈린다.
# 대상은 hook 이 아니라 스킬 로컬 헬퍼라 `Invoke-Hook` 을 쓰지 않고 인자를 넘기는 자식 셸을 직접 띄운다.
if (Test-HookSelected @('check-plan')) {

$cpPath = Join-Path $pluginRoot 'skills/plan/scripts/check-plan.ps1'
$cpRoot = Join-Path $work 'check-plan'
New-Item -ItemType Directory -Path $cpRoot -Force | Out-Null
$cpSeq = 0

$cpBase = @'
# plan — demo

> 요구: 데모 기능을 추가해줘

## Goal

> BASE: <sha>
> 승인: <date>
> 시작: 2026-01-01 00:00
> 완료: <done>

목표 문단.

| # | 기준 | 측정 방법 |
|---|---|---|
| G1 | 참 | `run` |

## Out of Scope

- 없음

## Investigation Log

| 주장 | 실행한 명령 | 출력 요지 |
|---|---|---|
| 위키 참조 — conventions | `grep x conventions.md` | 0 |
| 크기 | `wc -c a.ps1` | 10 |

## 작업 단계

### T1. 하나

- [ ] **T1-1** 한다
- **Files**: `a.ps1` · 케이스 `t.ps1` (RED)
- **Acceptance**: `grep -c x a.ps1` ≥1 (착수 0)
- **검증**: `run` → OK

## 검증 방법

| task | 명령 | 판정 |
|---|---|---|
| T1 | `run` | 통과 |

## Deferred / Follow-up

없음
'@
# 이 파일은 CRLF 로 저장돼 here-string 도 CRLF 다 — 케이스의 `n 치환이 맞도록 LF 로 맞춘다.
$cpBase = $cpBase -replace "`r`n", "`n"

# 정상 본문에서 한 군데를 바꾼 plan 을 새 폴더에 쓰고 검사한다. $Exe 는 pwsh(7) 또는 powershell(5.1).
function Invoke-CheckPlan([string]$Text, [string]$Dir = '', [string]$Exe = 'pwsh') {
    Assert-EvalParentAlive
    if (-not $Dir) {
        $script:cpSeq++
        $Dir = Join-Path $cpRoot ('p' + $script:cpSeq)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    $file = Join-Path $Dir 'plan.md'
    [System.IO.File]::WriteAllText($file, $Text, (New-Object System.Text.UTF8Encoding($false)))
    $out = & $Exe -NoProfile -ExecutionPolicy Bypass -File $cpPath $file 2>&1
    return @{ code = $LASTEXITCODE; out = (($out | Out-String)).Trim() }
}

# ---- 정상 ----
$r = Invoke-CheckPlan $cpBase
Assert-Case -Name "check-plan: 정상 plan 은 위반 0 으로 통과한다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'

# ---- A1 명령 칸 ----
$r = Invoke-CheckPlan ($cpBase.Replace('| 크기 | `wc -c a.ps1` | 10 |', '| 크기 |  | 10 |'))
Assert-Case -Name "check-plan: A1 명령 칸이 빈 Log 행을 잡는다" -R $r -ExpectExit 1 -ExpectContains 'empty-command'
$r = Invoke-CheckPlan ($cpBase.Replace('| 크기 | `wc -c a.ps1` | 10 |', ('| 크기 | ' + [char]0x2014 + ' | 10 |')))
Assert-Case -Name "check-plan: A1 명령 칸이 줄표뿐인 행도 빈 칸으로 본다" -R $r -ExpectExit 1 -ExpectContains 'empty-command'
$r = Invoke-CheckPlan ($cpBase.Replace('| 크기 | `wc -c a.ps1` | 10 |', '| a \| b |  | 10 |'))
Assert-Case -Name "check-plan: A1 주장 칸의 이스케이프 파이프에 칸이 밀리지 않는다" -R $r -ExpectExit 1 -ExpectContains 'empty-command'

# ---- A2 위키 참조 행 ----
$r = Invoke-CheckPlan ($cpBase.Replace('| 위키 참조 — conventions |', '| 규약 조회 |'))
Assert-Case -Name "check-plan: A2 위키 참조 행이 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'no-wiki-row'
$r = Invoke-CheckPlan ($cpBase.Replace('| 위키 참조 — conventions | `grep x conventions.md` | 0 |', '| 규약 조회 | `grep x conventions.md` | 위키 conventions 0 |'))
Assert-Case -Name "check-plan: A2 위키가 출력 칸에만 있으면 위키 참조 행으로 치지 않는다" -R $r -ExpectExit 1 -ExpectContains 'no-wiki-row'

# ---- A3 종결 대장 조회 흔적 (git 임시 레포) ----
$cpGit = Join-Path $cpRoot 'git-repo'
New-Item -ItemType Directory -Path (Join-Path $cpGit 'docs/plans') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $cpGit 'docs/plans/deferred-closed.md'), "# closed`n", (New-Object System.Text.UTF8Encoding($false)))
& git -C $cpGit init -q 2>$null
& git -C $cpGit add -A 2>$null
$r = Invoke-CheckPlan $cpBase $cpGit
Assert-Case -Name "check-plan: A3 종결 대장이 추적되는데 Log 에 조회 흔적이 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'no-closed-trace'
$r = Invoke-CheckPlan ($cpBase.Replace('| 크기 | `wc -c a.ps1` | 10 |', ("| 크기 | ``wc -c a.ps1`` | 10 |`n| 종결분 | ``grep x docs/plans/deferred-closed.md`` | 0 |"))) $cpGit
Assert-Case -Name "check-plan: A3 Log 에 deferred-closed 조회가 있으면 통과한다" -R $r -ExpectExit 0 -ExpectNotContains 'no-closed-trace'
$r = Invoke-CheckPlan $cpBase
Assert-Case -Name "check-plan: git 밖이면 A3 를 건너뛰고 알린다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: skip closed-ledger'

# ---- A4 Open Questions ----
$r = Invoke-CheckPlan ($cpBase.Replace('## Investigation Log', "## Open Questions`n`n- [ ] 미정인 질문`n`n## Investigation Log"))
Assert-Case -Name "check-plan: A4 Open Questions 에 남은 [ ] 를 잡는다" -R $r -ExpectExit 1 -ExpectContains 'open-question'

# ---- A5 · A6 ----
$r = Invoke-CheckPlan ($cpBase.Replace('`grep -c x a.ps1` ≥1 (착수 0)', '`grep -c x a.ps1` ≥1'))
Assert-Case -Name "check-plan: A5 명령이 있는 Acceptance 에 착수값이 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'acceptance-baseline T1'
$r = Invoke-CheckPlan ($cpBase.Replace('`a.ps1` · 케이스 `t.ps1` (RED)', '`a.ps1`'))
Assert-Case -Name "check-plan: A6 Files 에 케이스 표시도 면제도 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'case-mark T1'

# ---- B1 · B2 ----
$r = Invoke-CheckPlan ($cpBase.Replace("## 검증 방법`n", "`n"))
Assert-Case -Name "check-plan: B1 필수 절이 빠지면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'missing-section verification'
$r = Invoke-CheckPlan ($cpBase.Replace("> 승인: <date>`n", ''))
Assert-Case -Name "check-plan: B2 Goal 머리 줄이 빠지면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'goal-head approval'
$r = Invoke-CheckPlan ($cpBase.Replace("> 요구: 데모 기능을 추가해줘`n", ''))
Assert-Case -Name "check-plan: B2 첫 절 앞의 요구 줄이 빠지면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'goal-head request'

# ---- B3 · B4 ----
$r = Invoke-CheckPlan ($cpBase.Replace('- [ ] **T1-1** 한다', '- [ ] T1-1 한다'))
Assert-Case -Name "check-plan: B3 볼드 없는 하위 항목을 잡는다" -R $r -ExpectExit 1 -ExpectContains 'task-item T1'
$r = Invoke-CheckPlan ($cpBase.Replace('**T1-1**', '**T2-1**'))
Assert-Case -Name "check-plan: B3 제목과 번호가 다른 하위 항목을 잡는다" -R $r -ExpectExit 1 -ExpectContains 'task-item T1'
$r = Invoke-CheckPlan ($cpBase.Replace("- **검증**: ``run`` → OK`n", ''))
Assert-Case -Name "check-plan: B4 task 에 검증 줄이 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'task-line T1 verify'
$r = Invoke-CheckPlan ($cpBase.Replace('- [ ] **T1-1** 한다', "- [x] **T1-1** 한다`n- [X] **T1-2** 한다`n- [/] **T1-3** 하는 중`n- [x] **T1-4** (불요 — 근거)`n- [x] (불요 — 근거) **T1-5** 끝"))
Assert-Case -Name "check-plan: 하위 항목 상태 x·X·/·불요 표기를 받아들인다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'

# ---- 화면 줄 — 줄이 있으면 시나리오·스크린샷·통과 조건 셋을 다 가져야 한다 ----
$cpScreen = '- **화면**: 시나리오 메뉴에서 데모 열기 · 스크린샷 demo.png · 통과 조건 데모 창이 보인다'
function New-ScreenPlan([string]$Line) { return $cpBase.Replace('- **Acceptance**:', ($Line + "`n- **Acceptance**:")) }
$r = Invoke-CheckPlan (New-ScreenPlan ($cpScreen + ' · (BASE 대조)'))
Assert-Case -Name "check-plan: 화면 줄 세 요소와 (BASE 대조) 표지를 받아들인다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
$r = Invoke-CheckPlan (New-ScreenPlan $cpScreen.Replace(' · 통과 조건 데모 창이 보인다', ''))
Assert-Case -Name "check-plan: 화면 줄에 통과 조건이 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'screen-line T1 predicate'
$r = Invoke-CheckPlan (New-ScreenPlan $cpScreen.Replace(' · 스크린샷 demo.png', ''))
Assert-Case -Name "check-plan: 화면 줄에 스크린샷이 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'screen-line T1 screenshot'
$r = Invoke-CheckPlan (New-ScreenPlan $cpScreen.Replace('시나리오 메뉴에서 데모 열기 · ', ''))
Assert-Case -Name "check-plan: 화면 줄에 시나리오가 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'screen-line T1 scenario'
$r = Invoke-CheckPlan (New-ScreenPlan $cpScreen.Replace('통과 조건 데모 창이 보인다', '통과 조건 '))
Assert-Case -Name "check-plan: 화면 줄의 라벨만 있고 값이 빈 요소를 잡는다" -R $r -ExpectExit 1 -ExpectContains 'screen-line T1 predicate'
$r = Invoke-CheckPlan (New-ScreenPlan "``````text`n- **화면**: 시나리오만 있다`n``````")
Assert-Case -Name "check-plan: 펜스 안의 화면 줄은 판정하지 않는다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'

# ---- 펜스 · 입력 오류 ----
$r = Invoke-CheckPlan ($cpBase.Replace('| 크기 | `wc -c a.ps1` | 10 |', ("| 크기 | ``wc -c a.ps1`` | 10 |`n`n``````text`n| 가짜 |  | 빈 |`n## 가짜 절`n- [ ] T9-9 가짜`n```````n")))
Assert-Case -Name "check-plan: 펜스 안의 표 행·절·체크박스는 판정하지 않는다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
Assert-EvalParentAlive
$cpMissing = pwsh -NoProfile -ExecutionPolicy Bypass -File $cpPath (Join-Path $cpRoot 'no-such-plan.md') 2>&1
$r = @{ code = $LASTEXITCODE; out = (($cpMissing | Out-String)).Trim() }
Assert-Case -Name "check-plan: 파일이 없으면 ERROR 와 exit 2" -R $r -ExpectExit 2 -ExpectContains 'check-plan: ERROR'

# ---- 출력 ASCII · PS 5.1 ----
$cpMulti = $cpBase.Replace('| 크기 | `wc -c a.ps1` | 10 |', '| 크기 |  | 10 |').Replace('- [ ] **T1-1** 한다', '- [ ] T1-1 한다').Replace('`grep -c x a.ps1` ≥1 (착수 0)', '`grep -c x a.ps1` ≥1')
$r = Invoke-CheckPlan $cpMulti
$cpAscii = if ($r.out -match '[^\x00-\x7F]') { 'NON-ASCII' } else { 'ASCII-ONLY' }
Assert-Case -Name "check-plan: 위반이 여럿이어도 출력은 ASCII 뿐이다" -R @{ code = $r.code; out = $cpAscii } -ExpectExit 1 -ExpectContains 'ASCII-ONLY'
$cpWinPs = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($cpWinPs) {
    $r = Invoke-CheckPlan ($cpBase.Replace('| 크기 | `wc -c a.ps1` | 10 |', '| 크기 |  | 10 |')) '' $cpWinPs.Source
    Assert-Case -Name "check-plan: PS 5.1 에서도 위반을 잡는다" -R $r -ExpectExit 1 -ExpectContains 'empty-command'
    $r = Invoke-CheckPlan $cpBase '' $cpWinPs.Source
    Assert-Case -Name "check-plan: PS 5.1 에서 정상 plan 은 통과한다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
    $r = Invoke-CheckPlan (New-ScreenPlan $cpScreen.Replace(' · 통과 조건 데모 창이 보인다', '')) '' $cpWinPs.Source
    Assert-Case -Name "check-plan: PS 5.1 에서도 화면 줄 요소 누락을 잡는다" -R $r -ExpectExit 1 -ExpectContains 'screen-line T1 predicate'
} else {
    # 이 레포는 Windows 검증이라 5.1 이 없으면 건너뛰지 않고 실패로 낸다 — 건너뛰면 5.1 결함을 볼 자리가 사라진다.
    Assert-Case -Name "check-plan: PS 5.1 에서도 위반을 잡는다" -R @{ code = 99; out = 'powershell.exe not found' } -ExpectExit 1 -ExpectContains 'empty-command'
    Assert-Case -Name "check-plan: PS 5.1 에서 정상 plan 은 통과한다" -R @{ code = 99; out = 'powershell.exe not found' } -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
    Assert-Case -Name "check-plan: PS 5.1 에서도 화면 줄 요소 누락을 잡는다" -R @{ code = 99; out = 'powershell.exe not found' } -ExpectExit 1 -ExpectContains 'screen-line T1 predicate'
}

# ---- 증거 대조 (-Base) — 임시 git 레포에 BASE 커밋을 두고 그 앞뒤로 task 커밋을 쌓는다 ----
# 커밋 메시지는 파일(-F)로 넘긴다 — 한글 메시지가 인자 인코딩을 거치지 않게 한다.
$cpEvSeq = 0
function New-EvidenceRepo([string[]]$After = @(), [string[]]$Before = @()) {
    $script:cpEvSeq++
    $dir = Join-Path $cpRoot ('ev' + $script:cpEvSeq)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & git -C $dir init -q 2>$null
    $msgFile = Join-Path $cpRoot ('ev' + $script:cpEvSeq + '.msg')
    $commit = {
        param([string]$Msg)
        [System.IO.File]::WriteAllText($msgFile, $Msg, (New-Object System.Text.UTF8Encoding($false)))
        & git -C $dir -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q --allow-empty -F $msgFile 2>$null
    }
    foreach ($m in $Before) { & $commit $m }
    & $commit 'base'
    $base = ((& git -C $dir rev-parse HEAD 2>$null) | Out-String).Trim()
    foreach ($m in $After) { & $commit $m }
    return @{ dir = $dir; base = $base }
}
function Invoke-CheckEvidence([string]$Text, [string]$Dir, [string]$Base, [string]$Exe = 'pwsh') {
    Assert-EvalParentAlive
    $file = Join-Path $Dir 'plan.md'
    [System.IO.File]::WriteAllText($file, $Text, (New-Object System.Text.UTF8Encoding($false)))
    $out = & $Exe -NoProfile -ExecutionPolicy Bypass -File $cpPath $file -Base $Base 2>&1
    return @{ code = $LASTEXITCODE; out = (($out | Out-String)).Trim() }
}

$cpDone = $cpBase.Replace('- [ ] **T1-1** 한다', '- [x] **T1-1** 한다')
$cpOk = "기능: T1 — 한다`n`n검증 결과: run → OK"
$ev = New-EvidenceRepo @()
$r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base
Assert-Case -Name "check-plan 증거: [x] task 에 T<N> 커밋이 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'no-task-commit T1'
$ev = New-EvidenceRepo @("기능: T1 — 한다`n`n무엇을 바꿨는지만 적었다")
$r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base
Assert-Case -Name "check-plan 증거: T<N> 커밋 본문에 검증 결과가 없으면 잡는다" -R $r -ExpectExit 1 -ExpectContains 'no-commit-evidence T1'
$ev = New-EvidenceRepo @("기능: T10 — 다른 task`n`n검증 결과: run → OK")
$r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base
Assert-Case -Name "check-plan 증거: T10 커밋은 T1 의 증거가 아니다" -R $r -ExpectExit 1 -ExpectContains 'no-task-commit T1'
$ev = New-EvidenceRepo @() @($cpOk)
$r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base
Assert-Case -Name "check-plan 증거: BASE 이전 커밋은 세지 않는다" -R $r -ExpectExit 1 -ExpectContains 'no-task-commit T1'
$ev = New-EvidenceRepo @($cpOk)
$r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base
Assert-Case -Name "check-plan 증거: 한글 제목·한글 검증 결과 본문이 있으면 통과한다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
$ev = New-EvidenceRepo @("문서: T1 — 한다`n`nHUMAN-VERIFY: 화면 배치는 사용자 확인")
$r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base
Assert-Case -Name "check-plan 증거: 본문의 HUMAN-VERIFY 를 증거로 받는다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
$cpSkip = $cpBase.Replace('- [ ] **T1-1** 한다', '- [x] **T1-1** (불요 — 근거)').Replace("## 검증 방법`n", "### T2. 둘`n`n- [ ] **T2-1** 아직`n- **Files**: ``b.ps1`` [면제 ①] 문서`n- **Acceptance**: 참`n- **검증**: ``run`` → OK`n`n## 검증 방법`n")
$ev = New-EvidenceRepo @()
$r = Invoke-CheckEvidence $cpSkip $ev.dir $ev.base
Assert-Case -Name "check-plan 증거: 전부 불요인 task 와 열린 task 는 대조하지 않는다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
$r = Invoke-CheckEvidence $cpDone $ev.dir 'deadbeefdeadbeef'
Assert-Case -Name "check-plan 증거: 없는 BASE 는 ERROR 와 exit 2" -R $r -ExpectExit 2 -ExpectContains 'check-plan: ERROR bad-base'
$cpNoGit = Join-Path $cpRoot 'ev-nogit'
New-Item -ItemType Directory -Path $cpNoGit -Force | Out-Null
$r = Invoke-CheckEvidence $cpDone $cpNoGit 'HEAD'
Assert-Case -Name "check-plan 증거: git 밖이면 ERROR no-git 와 exit 2" -R $r -ExpectExit 2 -ExpectContains 'check-plan: ERROR no-git'
if ($cpWinPs) {
    $ev = New-EvidenceRepo @($cpOk)
    $r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base $cpWinPs.Source
    Assert-Case -Name "check-plan 증거: PS 5.1 에서 한글 제목·본문 증거를 읽어 통과한다" -R $r -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
    $ev = New-EvidenceRepo @("기능: T1 — 한다`n`n무엇을 바꿨는지만 적었다")
    $r = Invoke-CheckEvidence $cpDone $ev.dir $ev.base $cpWinPs.Source
    Assert-Case -Name "check-plan 증거: PS 5.1 에서도 본문 증거 없음을 잡는다" -R $r -ExpectExit 1 -ExpectContains 'no-commit-evidence T1'
} else {
    Assert-Case -Name "check-plan 증거: PS 5.1 에서 한글 제목·본문 증거를 읽어 통과한다" -R @{ code = 99; out = 'powershell.exe not found' } -ExpectExit 0 -ExpectContains 'check-plan: 0 problems'
    Assert-Case -Name "check-plan 증거: PS 5.1 에서도 본문 증거 없음을 잡는다" -R @{ code = 99; out = 'powershell.exe not found' } -ExpectExit 1 -ExpectContains 'no-commit-evidence T1'
}

}
