# check-plan.ps1 — plan.md 의 기계로 갈리는 서식과, 회차 끝에 [x] task 의 실행 증거를 검사한다
#   (pjc:plan Step 6 과 pjc:implement 최종 리뷰가 리뷰어보다 먼저 부르는 헬퍼 — hook 아님)
#
# 사용: check-plan.ps1 <plan.md 경로>                 서식 검사(계획 시점)
#       check-plan.ps1 <plan.md 경로> -Base <sha>     증거 대조만(회차 끝) — 서식 검사는 돌리지 않는다
# 출력은 ASCII 만이고 줄 종류는 넷이다:
#   check-plan <줄>: <코드> <세부>        위반 하나
#   check-plan: skip <검사> <사유>        건너뛴 검사 하나(위반 아님)
#   check-plan: <N> problems              마지막 줄 — 위반 수
#   check-plan: ERROR <사유>              입력 오류(exit 2)
# 종료 코드: 0 위반 없음 · 1 위반 있음 · 2 입력 오류(경로 없음·파일 없음·읽기 실패 · -Base 모드의 git 밖·없는 BASE).
#
# 코드와 뜻 — 이 표가 정본이다(plan/SKILL.md Step 6 은 여기를 가리킨다):
#   empty-command                Investigation Log 표의 명령 칸이 비었거나 줄표(-·—·–)뿐인 행
#   no-wiki-row                  Investigation Log 표의 주장 칸에 「위키 참조」 가 있는 행이 없음
#   no-closed-trace              레포가 deferred-closed.md 를 추적하는데 Log 에 「deferred-closed」 가 없음
#   open-question                Open Questions 절에 「- [ ]」 가 남음
#   acceptance-baseline T<N>     Acceptance 줄에 백틱(판정 명령·리터럴)이 있는데 「착수」 가 없음
#   case-mark T<N>               Files 줄에 (RED)·(GREEN·[면제 가 하나도 없음
#   missing-section <절>         필수 절 없음 — goal·out-of-scope·investigation-log·tasks·verification·deferred
#                                (Goal 절에 「> 경량:」 줄이 있는 경량 plan 은 out-of-scope·verification 을 재지 않는다)
#   light-files <N>              경량 plan 의 task Files 줄 백틱 경로(줄의 첫 「[면제」 앞까지) 합집합이 2 를 넘음
#   light-structure T<N>         경량 plan 의 task 에 「- **구조**:」 줄이 있음(새 파일·공개 표면·경계를 넘는 재구성)
#   light-approval               경량 plan 에 「승인 필요 항목」 절이 있음
#   light-relay                  경량 plan 의 「> 요구:」 가 「코디네이터 인터뷰 경유」(중계 모드는 경량 불허)
#   goal-head <줄>               request(첫 절 앞 「> 요구:」 원문 인용)·base·approval·start·done(Goal 절의 「> BASE:」 등) 없음
#   task-item T<N>               하위 항목이 「- [ ]·[x]·[X]·[/]」 뒤 (불요 …) 를 지나 **T<N>-<M>** 가 아니거나 번호가 제목과 다름
#   task-line T<N> <줄>          task 에 files·acceptance·verify 줄 없음
#   screen-line T<N> <요소>      「- **화면**:」 줄에 scenario(시나리오)·screenshot(스크린샷)·predicate(통과 조건) 조각이 없거나 값이 빔
#                                (화면 줄이 없는 task 는 재지 않는다 — 있어야 할 task 인지는 plan-reviewer 가 본다)
# -Base 모드의 코드 — 대상은 하위 항목이 전부 [x]·[X] 인 task 이고, 전부 「(불요」 인 task 는 뺀다:
#   no-task-commit T<N>          BASE..HEAD 에 제목이 「{유형}: T<N> —」(또는 「T<N>:」)인 커밋이 없음
#   no-commit-evidence T<N>      그 커밋은 있으나 어느 본문에도 「검증 결과」·「검증:」·HUMAN-VERIFY 가 없음
#   ERROR no-git · ERROR bad-base  plan 이 git 밖 · BASE 가 커밋이 아님(exit 2)
# 제목 형식의 정본은 guard-bash 의 완료 커밋 판정이다(scripts/rules/bash-guard-rationale.md §14) — 같은 정규식을 쓴다.
#
# 왜 결정적 스크립트인가: 문자열로 갈리는 판정을 리뷰어(LLM)가 매 라운드 읽어 가르면 놓칠 수 있고 라운드를 쓴다.
#   항목 단위 판정(케이스 경로마다의 표시·명령마다의 착수값·면제 사유의 옳음)은 리뷰어에 남는다.
# 왜 출력에 한글이 없는가: Git Bash 를 거친 PowerShell 출력에서 한글이 깨진다(work-clock 과 같은 이유).
# 왜 펜스 안을 건너뛰는가: 템플릿·예시 펜스 안의 「## 」·「- [ ]」·표 행이 위반으로 잡힌다.
# 왜 「\|」 를 칸 경계로 보지 않는가: 표 칸 안의 정규식은 「\|」 로 적히고, 그것으로 가르면 명령 칸 자리가 밀린다.
# Deferred 마커 서식은 재지 않는다 — session-context hook 의 계수와 하니스 정합 검사가 이미 각자 구현한다.
# stdin 은 읽지 않는다. PS 5.1·7 양쪽에서 돈다 — Windows 에는 5.1 만 있을 수 있다.
param([string]$PlanPath = '', [string]$Base = '')

$problems = New-Object System.Collections.Generic.List[string]
function Add-Problem([int]$Line, [string]$Text) { $problems.Add(('check-plan {0}: {1}' -f $Line, $Text)) }
function Complete-Check {
    foreach ($p in $problems) { Write-Output $p }
    Write-Output ('check-plan: {0} problems' -f $problems.Count)
    if ($problems.Count) { exit 1 }
    exit 0
}
function Get-Text([int[]]$Codes) { return -join ($Codes | ForEach-Object { [char]$_ }) }

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

# task 블록 — `### T<N>.` 줄부터 다음 그 줄 앞까지.
$tasksTitle = Get-Text @(0xC791, 0xC5C5, 0x20, 0xB2E8, 0xACC4)    # 작업 단계
function Get-TaskBlocks {
    $blocks = @()
    foreach ($l in (Get-ProseLines (Find-Section $tasksTitle))) {
        if ($l.Text -match '^### T(\d+)\.') {
            $blocks += [pscustomobject]@{ Id = [int]$Matches[1]; N = $l.N; Lines = (New-Object System.Collections.Generic.List[object]) }
        } elseif ($blocks.Count) {
            $blocks[-1].Lines.Add($l)
        }
    }
    return $blocks
}

# ---- 증거 대조 (-Base) — [x] 로 닫힌 task 마다 BASE..HEAD 의 T<N> 커밋 본문에 검증 기록이 있는가 ----
if ($Base) {
    # PS 5.1 은 네이티브 출력을 콘솔 코드페이지로 디코딩해 커밋의 한글을 깨뜨린다. 콘솔 없는 호스트에서는 setter 가 던진다.
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    $planDir = Split-Path -Parent (Resolve-Path -LiteralPath $PlanPath).Path
    $top = $null
    try { $top = (& git -C $planDir rev-parse --show-toplevel 2>$null) } catch { $top = $null }
    if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output 'check-plan: ERROR no-git'; exit 2 }
    $null = & git -C $top rev-parse --verify -q ($Base + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Output 'check-plan: ERROR bad-base'; exit 2 }

    # 커밋 경계는 NUL — 본문의 줄바꿈과 섞이지 않는다.
    $logText = (& git -C $top log --format='%B%x00' ($Base + '..HEAD') 2>$null) -join "`n"
    $types = (@(@(0xAE30, 0xB2A5), @(0xC218, 0xC815), @(0xB9AC, 0xD329, 0xD1A0, 0xB9C1), @(0xBB38, 0xC11C), @(0xC124, 0xC815)) | ForEach-Object { Get-Text $_ }) -join '|'    # 기능|수정|리팩토링|문서|설정
    $titleRx = '^\s*(?:(?:' + $types + ')\s*:\s*)?T(\d+)\s*(?::|' + [char]0x2014 + '|-)'
    $verify = Get-Text @(0xAC80, 0xC99D)    # 검증
    $evidenceRx = $verify + '\s*(?:' + (Get-Text @(0xACB0, 0xACFC)) + '|:)|HUMAN-VERIFY'    # 검증 결과 · 검증: · HUMAN-VERIFY
    $commits = @()
    foreach ($msg in ($logText -split "`0")) {
        $msg = $msg.Trim()
        if (-not $msg) { continue }
        $parts = $msg -split "`n", 2
        $m = [regex]::Match($parts[0], $titleRx)
        if (-not $m.Success) { continue }
        $body = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $commits += [pscustomobject]@{ Id = [int]$m.Groups[1].Value; Evidence = [regex]::IsMatch($body, $evidenceRx) }
    }

    $unneeded = '(' + (Get-Text @(0xBD88, 0xC694))    # (불요
    foreach ($b in @(Get-TaskBlocks)) {
        $items = @($b.Lines | Where-Object { $_.Text -match '^- \[[ xX/]\]' })
        if (-not $items.Count) { continue }
        if (@($items | Where-Object { $_.Text -notmatch '^- \[[xX]\]' }).Count) { continue }
        if (-not @($items | Where-Object { -not $_.Text.Contains($unneeded) }).Count) { continue }
        $mine = @($commits | Where-Object { $_.Id -eq $b.Id })
        if (-not $mine.Count) { Add-Problem $b.N ('no-task-commit T' + $b.Id) }
        elseif (-not @($mine | Where-Object { $_.Evidence }).Count) { Add-Problem $b.N ('no-commit-evidence T' + $b.Id) }
    }
    Complete-Check
}

# ---- B1 필수 절 — 경량 plan 은 Out of Scope·검증 방법을 뺀다(task 의 검증 줄이 대신한다) ----
$goal = Find-Section 'Goal'
$lightLabel = '> ' + (Get-Text @(0xACBD, 0xB7C9)) + ':'    # > 경량:
$isLight = [bool]@(Get-ProseLines $goal | Where-Object { Test-Prefix $_.Text $lightLabel }).Count
$required = [ordered]@{
    'goal' = 'Goal'; 'out-of-scope' = 'Out of Scope'; 'investigation-log' = 'Investigation Log'
    'tasks' = $tasksTitle
    'verification' = ([string][char]0xAC80 + [char]0xC99D + ' ' + [char]0xBC29 + [char]0xBC95)    # 검증 방법
    'deferred' = 'Deferred / Follow-up'
}
foreach ($key in $required.Keys) {
    if ($isLight -and @('out-of-scope', 'verification') -contains $key) { continue }
    if (-not (Find-Section $required[$key])) { Add-Problem 1 ('missing-section ' + $key) }
}

# ---- B2 머리 줄 — 요구 줄은 첫 절 앞, 나머지 넷은 Goal 절 ----
$requestLabel = '> ' + [char]0xC694 + [char]0xAD6C + ':'    # > 요구:
$requestLines = @($head | Where-Object { -not $_.Code -and (Test-Prefix $_.Text $requestLabel) })
if (-not $requestLines.Count) { Add-Problem 1 'goal-head request' }
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

# ---- B5 경량 조건 — 사용자 승인 말고도 기계로 갈리는 조건은 여기서 잰다(모델 판정만으로 경량을 열지 않는다) ----
if ($isLight) {
    $exemptMark = '[' + (Get-Text @(0xBA74, 0xC81C))                                  # [면제
    $structLabel = '- **' + (Get-Text @(0xAD6C, 0xC870)) + '**:'                       # - **구조**:
    $paths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($b in @(Get-TaskBlocks)) {
        foreach ($l in $b.Lines) {
            if (Test-Prefix $l.Text $structLabel) { Add-Problem $l.N ('light-structure T' + $b.Id) }
            if (-not (Test-Prefix $l.Text '- **Files**:')) { continue }
            $t = $l.Text
            $cut = $t.IndexOf($exemptMark, [System.StringComparison]::Ordinal)
            if ($cut -ge 0) { $t = $t.Substring(0, $cut) }
            foreach ($m in [regex]::Matches($t, '`([^`]+)`')) { $null = $paths.Add($m.Groups[1].Value.Trim()) }
        }
    }
    if ($paths.Count -gt 2) { Add-Problem $goal.N ('light-files ' + $paths.Count) }
    $approval = Find-Section (Get-Text @(0xC2B9, 0xC778, 0x20, 0xD544, 0xC694, 0x20, 0xD56D, 0xBAA9))    # 승인 필요 항목
    if ($approval) { Add-Problem $approval.N 'light-approval' }
    $relayMark = Get-Text @(0xCF54, 0xB514, 0xB124, 0xC774, 0xD130, 0x20, 0xC778, 0xD130, 0xBDF0, 0x20, 0xACBD, 0xC720)    # 코디네이터 인터뷰 경유
    if (@($requestLines | Where-Object { $_.Text.Contains($relayMark) }).Count) { Add-Problem $requestLines[0].N 'light-relay' }
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
if (Find-Section $tasksTitle) {
    $blocks = @(Get-TaskBlocks)
    $verifyLabel = '- **' + [char]0xAC80 + [char]0xC99D + '**:'    # - **검증**:
    $baseline = [string][char]0xCC29 + [char]0xC218                # 착수
    $exempt = '[' + [char]0xBA74 + [char]0xC81C                     # [면제
    $screenLabel = '- **' + (Get-Text @(0xD654, 0xBA74)) + '**:'    # - **화면**:
    $screenParts = [ordered]@{
        'scenario' = Get-Text @(0xC2DC, 0xB098, 0xB9AC, 0xC624)            # 시나리오
        'screenshot' = Get-Text @(0xC2A4, 0xD06C, 0xB9B0, 0xC0F7)          # 스크린샷
        'predicate' = Get-Text @(0xD1B5, 0xACFC, 0x20, 0xC870, 0xAC74)     # 통과 조건
    }
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
        foreach ($s in @($b.Lines | Where-Object { Test-Prefix $_.Text $screenLabel })) {
            $pieces = @($s.Text.Substring($screenLabel.Length).Split([char]0xB7) | ForEach-Object { $_.Trim() })
            foreach ($key in $screenParts.Keys) {
                $head = $screenParts[$key] + ' '
                if (-not @($pieces | Where-Object { (Test-Prefix $_ $head) -and $_.Substring($head.Length).Trim() }).Count) {
                    Add-Problem $s.N ('screen-line ' + $tag + ' ' + $key)
                }
            }
        }
    }
}

Complete-Check
