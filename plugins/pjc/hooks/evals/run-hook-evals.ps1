# run-hook-evals.ps1 — pjc hook 골든 회귀 러너 (lint evals의 hook 판)
#
# 사용법: pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
#
# 무엇을: scripts/*.ps1 hook을 격리 USERPROFILE·중립 cwd에서 stdin JSON으로 실행해
#   exit code·출력 키워드를 대조한다. 케이스 정본은 두 곳 —
#   ① hook-cases.json: 무상태(command 기반) 케이스 (block-destructive·warn-external-ops)
#   ② 이 파일의 시나리오 섹션: 상태 필요(plan 폴더·git repo·AGENTS.md 마커·post-write 파일·토글)
#
# pending_fix 규약(red-green): pending_fix=true 케이스는 '수정 전 red(기대 미충족)'가 정상이다 —
#   red면 "PENDING(red 기대대로)"로 exit 0에 포함하고, green이면 stale 마킹이므로 FAIL(마킹 제거 강제).
#   마킹이 없는 케이스가 red면 FAIL(회귀). 해당 수정 task 완료 시 마킹을 제거한다.
#
# 격리: 실제 사용자 ~/.claude/.disabled(토글 상태)를 오염시키지 않도록 USERPROFILE을 임시 폴더로
#   바꿔 자식 hook 프로세스에 상속시키고, 실행 전후 실제 .disabled 목록 무변화를 검증한다.
#
# 전제: pwsh 7 (개발 레포 전용 러너 — hook 자체의 5.1 폴백과 무관). git 부재 시 evidence 시나리오는 skip.

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$evalsDir   = $PSScriptRoot
$pluginRoot = Split-Path (Split-Path $evalsDir -Parent) -Parent   # plugins/pjc
$scriptsDir = Join-Path $pluginRoot 'scripts'
$casesPath  = Join-Path $evalsDir 'hook-cases.json'

# ---- 실제 토글 상태 스냅샷 (격리 검증용 — 러너가 사용자 상태를 오염시키지 않아야 함) ----
$realHome = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$realDisabledDir = Join-Path $realHome '.claude/.disabled'
$snapshotBefore = @()
if (Test-Path -LiteralPath $realDisabledDir) {
    $snapshotBefore = @(Get-ChildItem -LiteralPath $realDisabledDir -Name | Sort-Object)
}

# ---- 격리 환경 구성 ----
# 홈 격리($iso)는 임시 폴더에 둬도 되지만, 시나리오 프로젝트($work)는 반드시 임시 폴더 '밖'이어야
# 한다 — require-plan-for-write가 시스템 임시 폴더 하위를 무조건 통과시키므로(H3 의도된 완화),
# 픽스처가 temp 안에 있으면 차단 시나리오 전체가 우회로 무력화된다.
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$iso = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-" + $suffix)
$workBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $realHome }   # 비Windows 폴백
$work = Join-Path $workBase ("pjc-hook-evals-" + $suffix)
New-Item -ItemType Directory -Path $iso -Force | Out-Null
New-Item -ItemType Directory -Path $work -Force | Out-Null
$env:USERPROFILE = $iso            # 자식 hook 프로세스가 이 홈의 .claude/.disabled를 보게 함
$env:CLAUDE_PROJECT_DIR = $null
Set-Location $work                 # 중립 cwd — hook의 (Get-Location) 폴백이 레포 plan.md를 줍지 않게

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Hook {
    param([string]$ScriptName, [string]$InputJson)
    $path = Join-Path $scriptsDir $ScriptName
    $out = $InputJson | pwsh -NoProfile -ExecutionPolicy Bypass -File $path 2>&1
    return @{ code = $LASTEXITCODE; out = (($out | Out-String)).Trim() }
}

function Assert-Case {
    param(
        [string]$Name, [hashtable]$R,
        [int]$ExpectExit = 0, [string]$ExpectContains = '', [bool]$ExpectSilent = $false,
        [bool]$PendingFix = $false
    )
    $green = ($R.code -eq $ExpectExit)
    if ($green -and $ExpectContains) { $green = ($R.out -match [regex]::Escape($ExpectContains)) }
    if ($green -and $ExpectSilent)   { $green = [string]::IsNullOrWhiteSpace($R.out) }

    if ($PendingFix) {
        if ($green) {
            $script:results.Add(@{ ok = $false; line = "[FAIL] $Name — pending_fix인데 이미 green(마킹 제거 필요: stale)" })
        } else {
            $script:results.Add(@{ ok = $true; line = "[PENDING] $Name — red 기대대로 (수정 task 완료 시 마킹 제거)" })
        }
        return
    }
    if ($green) {
        $script:results.Add(@{ ok = $true; line = "[PASS] $Name" })
    } else {
        $detail = "exit $($R.code) (기대 $ExpectExit)"
        if ($ExpectContains) { $detail += ", 기대 키워드 '$ExpectContains'" }
        if ($ExpectSilent)   { $detail += ", 무출력 기대" }
        $head = ($R.out -split "`r?`n" | Select-Object -First 2) -join ' / '
        $script:results.Add(@{ ok = $false; line = "[FAIL] $Name — $detail | 출력: $head" })
    }
}

# =====================================================================
# 1) 무상태 케이스 (hook-cases.json)
# =====================================================================
Write-Host "== pjc hook 골든 회귀 =="
$cases = (Get-Content -LiteralPath $casesPath -Raw -Encoding UTF8 | ConvertFrom-Json).cases
foreach ($c in $cases) {
    $json = @{ tool_name = 'Bash'; tool_input = @{ command = $c.command } } | ConvertTo-Json -Compress
    $r = Invoke-Hook $c.hook $json
    Assert-Case -Name "$($c.hook): $($c.name)" -R $r `
        -ExpectExit ([int]($c.expect_exit ?? 0)) `
        -ExpectContains ([string]($c.expect_contains ?? '')) `
        -ExpectSilent ([bool]($c.expect_silent ?? $false)) `
        -PendingFix ([bool]($c.pending_fix ?? $false))
}

# =====================================================================
# 2) require-plan-for-write 시나리오 (plan 유무·trivial·temp·NotebookEdit)
# =====================================================================
$noplan = Join-Path $work 'proj-noplan';  New-Item -ItemType Directory $noplan -Force | Out-Null
$withplan = Join-Path $work 'proj-plan';  New-Item -ItemType Directory $withplan -Force | Out-Null
"# plan`n- [ ] T1: work" | Set-Content (Join-Path $withplan 'plan.md')
$doneplan = Join-Path $work 'proj-done';  New-Item -ItemType Directory $doneplan -Force | Out-Null
"# plan`n- [x] T1: done" | Set-Content (Join-Path $doneplan 'plan.md')

function New-WriteJson([string]$cwd, [string]$file, [string]$tool = 'Write', [hashtable]$extra = @{}) {
    $ti = @{ file_path = $file; content = 'class A {}' } + $extra
    return (@{ tool_name = $tool; cwd = $cwd; tool_input = $ti } | ConvertTo-Json -Compress)
}

$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'A.cs'))
Assert-Case -Name "require-plan: plan 없이 .cs Write 차단" -R $r -ExpectExit 2
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'x.md'))
Assert-Case -Name "require-plan: plan 없이 .md 통과" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $withplan (Join-Path $withplan 'A.cs'))
Assert-Case -Name "require-plan: plan 있으면 .cs 통과" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $doneplan (Join-Path $doneplan 'A.cs'))
Assert-Case -Name "require-plan: 완료 plan 경고+비차단" -R $r -ExpectExit 0 -ExpectContains '완료된 것으로'
$trivial = @{ tool_name = 'Edit'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'A.cs'); old_string = 'int x = 1;'; new_string = 'int x = 2;' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $trivial
Assert-Case -Name "require-plan: trivial Edit 통과" -R $r -ExpectExit 0 -ExpectContains 'Trivial'
$newsym = @{ tool_name = 'Edit'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'A.cs'); old_string = '// x'; new_string = 'public class Foo { }' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $newsym
Assert-Case -Name "require-plan: 새 클래스 정의 Edit 차단" -R $r -ExpectExit 2

# [H3] 시스템 임시 폴더의 검증 스크립트 — 수정 후 통과가 기대 (pending_fix, T2)
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) 'pjc-hook-eval-scratch/check.py'
New-Item -ItemType Directory (Split-Path $tempFile) -Force | Out-Null
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson (Split-Path $tempFile) $tempFile)
Assert-Case -Name "require-plan: 시스템 임시폴더 .py 통과 (H3)" -R $r -ExpectExit 0

# [H5] NotebookEdit — notebook_path 인식 후 plan 게이트 적용이 기대 (pending_fix, T2)
$nb = @{ tool_name = 'NotebookEdit'; cwd = $noplan; tool_input = @{ notebook_path = (Join-Path $noplan 'n.ipynb'); new_source = 'x=1' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $nb
Assert-Case -Name "require-plan: NotebookEdit plan 없음 차단 (H5)" -R $r -ExpectExit 2

# =====================================================================
# 3) 토글 메커니즘 (격리 홈 — 실제 상태 무영향)
# =====================================================================
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'harness-toggle.ps1') 'require-plan-for-write' 'off' | Out-Null
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'B.cs'))
Assert-Case -Name "toggle: off 후 plan 없이 .cs 통과" -R $r -ExpectExit 0
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'harness-toggle.ps1') 'require-plan-for-write' 'on' | Out-Null
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'B.cs'))
Assert-Case -Name "toggle: on 후 다시 차단" -R $r -ExpectExit 2
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'harness-toggle.ps1') 'block-destructive' 'off' *> $null
Assert-Case -Name "toggle: block-destructive off 거부" -R @{ code = $LASTEXITCODE; out = '' } -ExpectExit 1

# =====================================================================
# 4) require-evidence 시나리오 (git 필요 — 부재 시 skip)
# =====================================================================
$gitOk = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
if ($gitOk) {
    $repo = Join-Path $work 'evrepo'; New-Item -ItemType Directory $repo -Force | Out-Null
    Push-Location $repo
    git init -q; git config user.email t@t; git config user.name t
    'x' | Set-Content a.txt; git add .; git commit -qm 'checkpoint: T1 start'
    Pop-Location
    $json = @{ cwd = $repo } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'require-evidence.ps1' $json
    Assert-Case -Name "evidence: checkpoint 커밋 경고" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    Push-Location $repo; 'y' | Set-Content a.txt; git add .; git commit -qm 'T1: 작업 완료'; Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' $json
    Assert-Case -Name "evidence: T커밋 증거 없음 경고" -R $r -ExpectExit 0 -ExpectContains '증거'
    Push-Location $repo; 'z' | Set-Content a.txt; git add .; git commit -qm "T2: done`n`nBuild OK, Tests 3/3 passed"; 'w' | Set-Content b.cs; Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' $json
    Assert-Case -Name "evidence: 미커밋 코드(.cs) 경고" -R $r -ExpectExit 0 -ExpectContains '커밋되지 않은 코드'
} else {
    Write-Host "[SKIP] require-evidence 시나리오 (git 없음)"
}

# =====================================================================
# 5) suggest-agents-record 시나리오 (제안·억제 2중·마커 정리)
# =====================================================================
$aproj = Join-Path $work 'aproj'; New-Item -ItemType Directory $aproj -Force | Out-Null
"# AGENTS`n## Build & Test`n" | Set-Content (Join-Path $aproj 'AGENTS.md')
$sj = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 's1'; tool_input = @{ command = 'dotnet build MyApp.sln' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj
Assert-Case -Name "suggest: dotnet build 첫 실행 제안" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj
Assert-Case -Name "suggest: 같은 세션 2회째 억제" -R $r -ExpectExit 0 -ExpectSilent $true
"# AGENTS`n## Build & Test`n- dotnet build" | Set-Content (Join-Path $aproj 'AGENTS.md')
$sj2 = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 's2'; tool_input = @{ command = 'dotnet build MyApp.sln' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj2
Assert-Case -Name "suggest: AGENTS.md 기재 시 억제(self-terminating)" -R $r -ExpectExit 0 -ExpectSilent $true

# [H5/T4] 30일 지난 상태 마커 자동 정리 — 수정 후 삭제가 기대
$stateDir = Join-Path $iso '.claude/.state/suggest-agents-record'
New-Item -ItemType Directory $stateDir -Force | Out-Null
$oldMarker = Join-Path $stateDir 'old_session_proj_build'
New-Item -ItemType File $oldMarker -Force | Out-Null
(Get-Item $oldMarker).LastWriteTime = (Get-Date).AddDays(-40)
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj2   # 아무 실행이나 1회 (정리 트리거)
$cleaned = -not (Test-Path -LiteralPath $oldMarker)
Assert-Case -Name "suggest: 30일 경과 마커 자동 정리 (H5)" -R @{ code = ([int](-not $cleaned)); out = '' } -ExpectExit 0

# =====================================================================
# 6) post-write-checks 시나리오 (BOM·영문 주석·시크릿·비차단)
# =====================================================================
$pw = Join-Path $work 'pwproj'; New-Item -ItemType Directory $pw -Force | Out-Null
$csPath = Join-Path $pw 'Big.cs'
$body = (1..6 | ForEach-Object { "// english comment $_" }) + 'var password = "Sup3rSecret99";'
[System.IO.File]::WriteAllText($csPath, ($body -join "`n"), [System.Text.UTF8Encoding]::new($true))  # BOM 포함
$pj = @{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $csPath } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $pj
Assert-Case -Name "post-write: BOM 경고" -R $r -ExpectExit 0 -ExpectContains 'BOM'
Assert-Case -Name "post-write: 영문 주석 경고" -R $r -ExpectExit 0 -ExpectContains '영문'
Assert-Case -Name "post-write: password 값 경고" -R $r -ExpectExit 0 -ExpectContains 'password'
Assert-Case -Name "post-write: 비차단 exit 0" -R $r -ExpectExit 0

# =====================================================================
# 격리 검증 + 결과 보고
# =====================================================================
$env:USERPROFILE = $realHome
$snapshotAfter = @()
if (Test-Path -LiteralPath $realDisabledDir) {
    $snapshotAfter = @(Get-ChildItem -LiteralPath $realDisabledDir -Name | Sort-Object)
}
$isoOk = (($snapshotBefore -join ',') -eq ($snapshotAfter -join ','))
$results.Add(@{ ok = $isoOk; line = $(if ($isoOk) { "[PASS] 격리: 실제 ~/.claude/.disabled 무변화" } else { "[FAIL] 격리 위반: 실제 토글 상태가 변경됨!" }) })

Set-Location $env:TEMP
Remove-Item -Recurse -Force $iso -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path ([System.IO.Path]::GetTempPath()) 'pjc-hook-eval-scratch') -ErrorAction SilentlyContinue

$failCount = 0
foreach ($res in $results) {
    Write-Host $res.line
    if (-not $res.ok) { $failCount++ }
}
$total = $results.Count
Write-Host ""
Write-Host ("결과: {0}/{1} OK (FAIL {2})" -f ($total - $failCount), $total, $failCount)
exit $(if ($failCount) { 1 } else { 0 })
