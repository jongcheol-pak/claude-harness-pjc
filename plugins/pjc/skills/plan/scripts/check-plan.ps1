# check-plan.ps1 — plan.md 의 기계로 갈리는 서식을 검사한다 (pjc:plan Step 6 이 리뷰어보다 먼저 부르는 헬퍼 — hook 아님)
#
# 사용: check-plan.ps1 <plan.md 경로>
# 출력은 ASCII 만이고 줄 종류는 넷이다:
#   check-plan <줄>: <코드> <세부>        위반 하나
#   check-plan: skip <검사> <사유>        건너뛴 검사 하나(위반 아님)
#   check-plan: <N> problems              마지막 줄 — 위반 수
#   check-plan: ERROR <사유>              입력 오류(exit 2)
# 종료 코드: 0 위반 없음 · 1 위반 있음 · 2 입력 오류(경로 없음·파일 없음·읽기 실패).
#
# 코드와 뜻 — 이 표가 정본이다(plan/SKILL.md Step 6 은 여기를 가리킨다):
#   empty-command                Investigation Log 표의 명령 칸이 비었거나 줄표(-·—·–)뿐인 행
#   no-wiki-row                  Investigation Log 표의 주장 칸에 「위키 참조」 가 있는 행이 없음
#   no-closed-trace              레포가 deferred-closed.md 를 추적하는데 Log 에 「deferred-closed」 가 없음
#   open-question                Open Questions 절에 「- [ ]」 가 남음
#   acceptance-baseline T<N>     Acceptance 줄에 백틱(판정 명령·리터럴)이 있는데 「착수」 가 없음
#   case-mark T<N>               Files 줄에 (RED)·(GREEN·[면제 가 하나도 없음
#   missing-section <절>         필수 절 없음 — goal·out-of-scope·investigation-log·tasks·verification·deferred
#   goal-head <줄>               request(첫 절 앞 「> 요구:」 원문 인용)·base·approval·start·done(Goal 절의 「> BASE:」 등) 없음
#   task-item T<N>               하위 항목이 「- [ ]·[x]·[X]·[/]」 뒤 (불요 …) 를 지나 **T<N>-<M>** 가 아니거나 번호가 제목과 다름
#   task-line T<N> <줄>          task 에 files·acceptance·verify 줄 없음
#
# 왜 결정적 스크립트인가: 문자열로 갈리는 판정을 리뷰어(LLM)가 매 라운드 읽어 가르면 놓칠 수 있고 라운드를 쓴다.
#   항목 단위 판정(케이스 경로마다의 표시·명령마다의 착수값·면제 사유의 옳음)은 리뷰어에 남는다.
# 왜 출력에 한글이 없는가: Git Bash 를 거친 PowerShell 출력에서 한글이 깨진다(work-clock 과 같은 이유).
# 왜 펜스 안을 건너뛰는가: 템플릿·예시 펜스 안의 「## 」·「- [ ]」·표 행이 위반으로 잡힌다.
# 왜 「\|」 를 칸 경계로 보지 않는가: 표 칸 안의 정규식은 「\|」 로 적히고, 그것으로 가르면 명령 칸 자리가 밀린다.
# Deferred 마커 서식은 재지 않는다 — session-context hook 의 계수와 하니스 정합 검사가 이미 각자 구현한다.
# stdin 은 읽지 않는다. PS 5.1·7 양쪽에서 돈다 — Windows 에는 5.1 만 있을 수 있다.
param([string]$PlanPath = '')

$problems = New-Object System.Collections.Generic.List[string]
function Add-Problem([int]$Line, [string]$Text) { $problems.Add(('check-plan {0}: {1}' -f $Line, $Text)) }

if (-not $PlanPath) { Write-Output 'check-plan: ERROR no-path'; exit 2 }
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { Write-Output 'check-plan: ERROR not-found'; exit 2 }
try {
    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PlanPath).Path, [System.Text.Encoding]::UTF8)
} catch {
    Write-Output 'check-plan: ERROR unreadable'; exit 2
}

# ---- 줄 목록 — 펜스 안 줄은 code 로 표시해 판정에서 뺀다 ----
$lines = @()
$fenceChar = $null
$n = 0
foreach ($text in ($raw -split "`r?`n")) {
    $n++
    $isCode = $false
    $m = [regex]::Match($text, '^ {0,3}(`{3,}|~{3,})')
    if ($fenceChar) {
        $isCode = $true
        if ($m.Success -and $m.Groups[1].Value[0] -eq $fenceChar) { $fenceChar = $null }
    } elseif ($m.Success) {
        $isCode = $true
        $fenceChar = $m.Groups[1].Value[0]
    }
    $lines += [pscustomobject]@{ N = $n; Text = $text; Code = $isCode }
}

# ---- 절 — `## ` 로 가르고 이름은 대괄호 표기 앞까지 ----
$sections = @()
$head = New-Object System.Collections.Generic.List[object]
foreach ($l in $lines) {
    if (-not $l.Code -and $l.Text -match '^## (.+?)\s*(\[.*)?$') {
        $sections += [pscustomobject]@{ Title = $Matches[1].Trim(); N = $l.N; Body = (New-Object System.Collections.Generic.List[object]) }
    } elseif ($sections.Count) {
        $sections[-1].Body.Add($l)
    } else {
        $head.Add($l)
    }
}
# 접두 비교는 서수로 한다 — 문화권 비교는 .NET Framework(PS 5.1)와 .NET(7)에서 한글 결과가 갈릴 수 있다.
function Test-Prefix([string]$Text, [string]$Prefix) { return $Text.StartsWith($Prefix, [System.StringComparison]::Ordinal) }
function Find-Section([string]$Title) { foreach ($s in $sections) { if ($s.Title -eq $Title) { return $s } }; return $null }
function Get-ProseLines($Section) { if ($Section) { return @($Section.Body | Where-Object { -not $_.Code }) }; return @() }

# 표 행을 칸으로 가른다 — 「\|」 는 칸 경계가 아니다.
function Split-Row([string]$Row) {
    $cells = [regex]::Split($Row.Trim(), '(?<!\\)\|')
    if ($cells.Count -ge 3) { return $cells[1..($cells.Count - 2)] | ForEach-Object { $_.Trim() } }
    return @()
}

# ---- B1 필수 절 ----
$required = [ordered]@{
    'goal' = 'Goal'; 'out-of-scope' = 'Out of Scope'; 'investigation-log' = 'Investigation Log'
    'tasks' = ([string][char]0xC791 + [char]0xC5C5 + ' ' + [char]0xB2E8 + [char]0xACC4)    # 작업 단계
    'verification' = ([string][char]0xAC80 + [char]0xC99D + ' ' + [char]0xBC29 + [char]0xBC95)    # 검증 방법
    'deferred' = 'Deferred / Follow-up'
}
foreach ($key in $required.Keys) {
    if (-not (Find-Section $required[$key])) { Add-Problem 1 ('missing-section ' + $key) }
}

# ---- B2 머리 줄 — 요구 줄은 첫 절 앞, 나머지 넷은 Goal 절 ----
$requestLabel = '> ' + [char]0xC694 + [char]0xAD6C + ':'    # > 요구:
if (-not ($head | Where-Object { -not $_.Code -and (Test-Prefix $_.Text $requestLabel) })) { Add-Problem 1 'goal-head request' }
$goal = Find-Section 'Goal'
if ($goal) {
    $goalHeads = [ordered]@{
        'base' = '> BASE:'
        'approval' = '> ' + [char]0xC2B9 + [char]0xC778 + ':'    # > 승인:
        'start' = '> ' + [char]0xC2DC + [char]0xC791 + ':'       # > 시작:
        'done' = '> ' + [char]0xC644 + [char]0xB8CC + ':'        # > 완료:
    }
    $goalProse = Get-ProseLines $goal
    foreach ($key in $goalHeads.Keys) {
        if (-not ($goalProse | Where-Object { Test-Prefix $_.Text $goalHeads[$key] })) { Add-Problem $goal.N ('goal-head ' + $key) }
    }
}

# ---- A1·A2·A3 Investigation Log ----
$log = Find-Section 'Investigation Log'
if ($log) {
    $logProse = Get-ProseLines $log
    $dashes = @('-', [string][char]0x2014, [string][char]0x2013)
    $wikiLabel = [string][char]0xC704 + [char]0xD0A4 + ' ' + [char]0xCC38 + [char]0xC870    # 위키 참조
    $hasWikiRow = $false
    for ($i = 0; $i -lt $logProse.Count; $i++) {
        $row = $logProse[$i].Text
        if (-not $row.TrimStart().StartsWith('|')) { continue }
        if ($row -match '^\s*\|[\s:|-]+\|\s*$') { continue }    # 구분 행
        $next = if ($i + 1 -lt $logProse.Count) { $logProse[$i + 1].Text } else { '' }
        if ($next -match '^\s*\|[\s:|-]+\|\s*$') { continue }   # 머리 행
        $cells = @(Split-Row $row)
        if ($cells.Count -lt 2) { continue }
        if ($cells[1] -eq '' -or $dashes -contains $cells[1]) { Add-Problem $logProse[$i].N 'empty-command' }
        if ($cells[0].Contains($wikiLabel)) { $hasWikiRow = $true }
    }
    if (-not $hasWikiRow) { Add-Problem $log.N 'no-wiki-row' }

    # A3 — 대장 위치는 레포마다 다르다. git 레포 전체에서 추적 여부만 본다.
    $planDir = Split-Path -Parent (Resolve-Path -LiteralPath $PlanPath).Path
    $top = $null
    try { $top = (& git -C $planDir rev-parse --show-toplevel 2>$null) } catch { $top = $null }
    if ($LASTEXITCODE -ne 0 -or -not $top) {
        Write-Output 'check-plan: skip closed-ledger no-git'
    } else {
        $closed = @(& git -C $top ls-files -- '*deferred-closed.md' 2>$null)
        $logText = ($logProse | ForEach-Object { $_.Text }) -join "`n"
        if ($closed.Count -and -not $logText.Contains('deferred-closed')) { Add-Problem $log.N 'no-closed-trace' }
    }
}

# ---- A4 Open Questions ----
foreach ($l in (Get-ProseLines (Find-Section 'Open Questions'))) {
    if ($l.Text -match '^\s*- \[ \]') { Add-Problem $l.N 'open-question' }
}

# ---- A5·A6·B3·B4 task 마다 ----
$tasks = Find-Section $required['tasks']
if ($tasks) {
    $blocks = @()
    foreach ($l in (Get-ProseLines $tasks)) {
        if ($l.Text -match '^### T(\d+)\.') {
            $blocks += [pscustomobject]@{ Id = [int]$Matches[1]; N = $l.N; Lines = (New-Object System.Collections.Generic.List[object]) }
        } elseif ($blocks.Count) {
            $blocks[-1].Lines.Add($l)
        }
    }
    $verifyLabel = '- **' + [char]0xAC80 + [char]0xC99D + '**:'    # - **검증**:
    $baseline = [string][char]0xCC29 + [char]0xC218                # 착수
    $exempt = '[' + [char]0xBA74 + [char]0xC81C                     # [면제
    foreach ($b in $blocks) {
        $tag = 'T' + $b.Id
        $items = 0
        foreach ($l in $b.Lines) {
            if ($l.Text -match '^- \[[ xX/]\]') {
                $items++
                $m = [regex]::Match($l.Text, '^- \[[ xX/]\] (?:\([^)]*\) )?\*\*T(\d+)-\d+\*\*')
                if (-not $m.Success -or [int]$m.Groups[1].Value -ne $b.Id) { Add-Problem $l.N ('task-item ' + $tag) }
            }
        }
        if (-not $items) { Add-Problem $b.N ('task-item ' + $tag) }

        $files = $b.Lines | Where-Object { Test-Prefix $_.Text '- **Files**:' } | Select-Object -First 1
        $accept = $b.Lines | Where-Object { Test-Prefix $_.Text '- **Acceptance**:' } | Select-Object -First 1
        $verify = $b.Lines | Where-Object { Test-Prefix $_.Text $verifyLabel } | Select-Object -First 1
        if (-not $files) { Add-Problem $b.N ('task-line ' + $tag + ' files') }
        if (-not $accept) { Add-Problem $b.N ('task-line ' + $tag + ' acceptance') }
        if (-not $verify) { Add-Problem $b.N ('task-line ' + $tag + ' verify') }
        if ($files -and -not ($files.Text.Contains('(RED)') -or $files.Text.Contains('(GREEN') -or $files.Text.Contains($exempt))) {
            Add-Problem $files.N ('case-mark ' + $tag)
        }
        if ($accept -and $accept.Text.Contains('`') -and -not $accept.Text.Contains($baseline)) {
            Add-Problem $accept.N ('acceptance-baseline ' + $tag)
        }
    }
}

foreach ($p in $problems) { Write-Output $p }
Write-Output ('check-plan: {0} problems' -f $problems.Count)
if ($problems.Count) { exit 1 }
exit 0
