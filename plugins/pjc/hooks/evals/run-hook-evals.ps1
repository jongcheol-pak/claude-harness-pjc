# run-hook-evals.ps1 — pjc hook 골든 회귀 러너 (lint evals의 hook 판)
#
# 사용법: pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
#   부분 실행(개발 반복 전용): ... run-hook-evals.ps1 -Filter block-destructive,require-plan-for-write
#
# 무엇을: scripts/*.ps1 hook을 격리 USERPROFILE·중립 cwd에서 stdin JSON으로 실행해
#   exit code·출력 키워드를 대조한다. 케이스 정본은 두 곳 —
#   ① hook-cases.json: 무상태(command 기반) 케이스 (block-destructive·warn-external-ops)
#   ② 이 파일의 시나리오 섹션: 상태 필요(plan 폴더·git repo·AGENTS.md 마커·post-write 파일)
#   ※ ②의 본문은 v1.152.0부터 scenarios/*.ps1 13개에 있다(순수 이동 — 본체엔 dot-source 목록만).
#     즉 케이스 정본은 hook-cases.json · scenarios/*.ps1 · 본체 헤더의 공용 픽스처 세 곳이다.
#
# -Filter 계약(v1.107.0): hook 기본명(.ps1 유무·대소문자 무관, 쉼표 복수)으로 실행 범위를 좁힌다.
#   구현 중 반복 확인 전용이며 task 검증(V-2 검증 매핑)·Phase F-2 판정에는 사용 금지 — 부분 실행은
#   커버리지가 좁아(섹션 태그는 케이스 단위가 아니라 섹션 단위 — 소량 초과 실행은 허용, 누락은 불허)
#   무인자 전체 실행만 판정 정본이다. 필터 모드는 경고 헤더를 강제 출력하고, 실행 케이스 0이면
#   exit 1로 실패한다(필터 이름 오타가 "전부 통과"로 보이는 거짓 안심 방지).
#
# pending_fix 규약(red-green): pending_fix=true 케이스는 '수정 전 red(기대 미충족)'가 정상이다 —
#   red면 "PENDING(red 기대대로)"로 exit 0에 포함하고, green이면 stale 마킹이므로 FAIL(마킹 제거 강제).
#   마킹이 없는 케이스가 red면 FAIL(회귀). 해당 수정 task 완료 시 마킹을 제거한다.
#
# 격리: 실제 사용자 홈(~/.claude)을 오염시키지 않도록 USERPROFILE을 임시 폴더로 바꿔 자식 hook
#   프로세스에 상속시킨다(suggest-agents-record의 .state 마커 등이 격리 홈에만 쓰이게). 종료 시 원복한다.
#
# 전제: pwsh 7 (개발 레포 전용 러너 — hook 자체의 5.1 폴백과 무관). git 부재 시 evidence 시나리오는 skip.

param(
    # 부분 실행 필터 — hook 기본명 목록 (예: 'block-destructive', 'post-write-checks.ps1'도 허용)
    [string[]]$Filter
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$evalsDir   = $PSScriptRoot
$pluginRoot = Split-Path (Split-Path $evalsDir -Parent) -Parent   # plugins/pjc
$scriptsDir = Join-Path $pluginRoot 'scripts'
$casesPath  = Join-Path $evalsDir 'hook-cases.json'

# ---- 실제 홈 보관 (테스트는 USERPROFILE을 격리 홈으로 바꾸므로 종료 시 원복용) ----
$realHome = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }

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
$env:USERPROFILE = $iso            # 자식 hook 프로세스가 이 격리 홈의 .claude를 보게 함(.state 마커 등)
$env:CLAUDE_PROJECT_DIR = $null
Set-Location $work                 # 중립 cwd — hook의 (Get-Location) 폴백이 레포 plan.md를 줍지 않게

$results = New-Object System.Collections.Generic.List[object]

# ---- -Filter 정규화 + 섹션 선택 헬퍼 ----
# 섹션 태그 원칙: 각 시나리오 섹션은 자기가 실행하는 hook 전부를 태그로 갖고, 필터에 하나라도
# 걸리면 섹션 전체를 실행한다(소량 초과 실행 허용 — 케이스 단위 정밀 필터보다 구조 단순 우선).
$script:FilterSet = $null
if ($Filter -and @($Filter).Count) {
    $script:FilterSet = @($Filter | ForEach-Object { ($_ -replace '\.ps1$', '').Trim().ToLowerInvariant() } | Where-Object { $_ })
    $knownFilterNames = @(
        'block-destructive', 'protect-harness', 'require-plan-for-write', 'require-task-checkbox',
        'post-write-checks', 'require-evidence', 'warn-external-ops', 'suggest-agents-record',
        'warn-commit-secrets', 'pre-bash-dispatch', 'warn-version-drift', 'session-context', 'hook-event-log'
    )
    foreach ($f in $script:FilterSet) {
        if ($knownFilterNames -notcontains $f) {
            Write-Host "[WARN] 알 수 없는 필터 이름: '$f' (유효: $($knownFilterNames -join ', '))"
        }
    }
}

function Test-HookSelected {
    # $Hooks: 이 케이스/섹션이 실행하는 hook 기본명 목록. 필터 미지정이면 항상 실행.
    param([string[]]$Hooks)
    if (-not $script:FilterSet) { return $true }
    foreach ($h in $Hooks) {
        if ($script:FilterSet -contains $h.ToLowerInvariant()) { return $true }
    }
    return $false
}

# ---- 크로스섹션 공유 정의 (필터 게이트 밖 — 반드시 top-level) ----
# 섹션 게이트가 어떤 조합으로 건너뛰어도 후속 섹션이 깨지지 않도록, 둘 이상의 섹션이 쓰는
# 변수·함수·픽스처는 여기서 무조건 정의한다. 특히 $gitOk는 게이트로 건너뛰면 오류 없이
# falsy가 되어 §7 impact·§9가 침묵 skip되는 사각이므로(plan-reviewer M1) top-level 고정.
$gitOk = $null -ne (Get-Command git -ErrorAction SilentlyContinue)   # §4·§7·§9 게이트
$pw = Join-Path $work 'pwproj'; New-Item -ItemType Directory $pw -Force | Out-Null   # §6·§7 후속·Pre.cs 픽스처
$vdCache = Join-Path $iso '.claude/plugins/cache/pjc-harness/pjc/1.0.0/scripts'      # §10 개조 차단·§11(d) 경로

function New-WriteJson([string]$cwd, [string]$file, [string]$tool = 'Write', [hashtable]$extra = @{}, [hashtable]$top = @{}) {
    # §2 require-plan·§2b protect-harness·§6 post-write 등 다수 섹션 공용
    # $top: tool_input이 아니라 stdin JSON 최상위에 병합할 필드 (예: transcript_path — AGENTS 게이트)
    $ti = @{ file_path = $file; content = 'class A {}' } + $extra
    return ((@{ tool_name = $tool; cwd = $cwd; tool_input = $ti } + $top) | ConvertTo-Json -Compress)
}

function New-CommitJson([string]$cwd, [string]$msg) {
    # §8 rtc·§8b dispatch 동등성 공용
    return (@{ tool_name = 'Bash'; cwd = $cwd; tool_input = @{ command = "git commit -m `"$msg`"" } } | ConvertTo-Json -Compress)
}

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
        [string]$ExpectNotContains = '', [bool]$PendingFix = $false
    )
    $green = ($R.code -eq $ExpectExit)
    if ($green -and $ExpectContains) { $green = ($R.out -match [regex]::Escape($ExpectContains)) }
    # ExpectContains와 대칭 — 지정 시 해당 문자열이 출력에 '없어야' green (기본값 ''이면 미발동, 기존 호출 무영향)
    if ($green -and $ExpectNotContains) { $green = -not ($R.out -match [regex]::Escape($ExpectNotContains)) }
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
        if ($ExpectNotContains) { $detail += ", 미포함 기대 '$ExpectNotContains'" }
        if ($ExpectSilent)   { $detail += ", 무출력 기대" }
        $head = ($R.out -split "`r?`n" | Select-Object -First 2) -join ' / '
        $script:results.Add(@{ ok = $false; line = "[FAIL] $Name — $detail | 출력: $head" })
    }
}

# ---- 시나리오 dot-source (이 목록 순서가 곧 실행 순서 — 분리 전 블록 순서를 그대로 보존한다) ----
# dot-source여야 한다: 함수·모듈로 감싸면 호출자 스코프 공유가 끊겨 $script:results 누적과 공용 헬퍼·변수 참조가 깨진다.
. (Join-Path $evalsDir 'scenarios/stateless.ps1')
. (Join-Path $evalsDir 'scenarios/require-plan-for-write.ps1')
. (Join-Path $evalsDir 'scenarios/protect-harness.ps1')
. (Join-Path $evalsDir 'scenarios/pre-bash-dispatch.ps1')
. (Join-Path $evalsDir 'scenarios/require-evidence.ps1')
. (Join-Path $evalsDir 'scenarios/suggest-agents-record.ps1')
. (Join-Path $evalsDir 'scenarios/post-write-checks.ps1')
. (Join-Path $evalsDir 'scenarios/require-task-checkbox.ps1')
. (Join-Path $evalsDir 'scenarios/warn-commit-secrets.ps1')
. (Join-Path $evalsDir 'scenarios/warn-version-drift.ps1')
. (Join-Path $evalsDir 'scenarios/protect-harness-installed.ps1')
. (Join-Path $evalsDir 'scenarios/hook-event-log.ps1')
. (Join-Path $evalsDir 'scenarios/session-context.ps1')
# =====================================================================
# USERPROFILE 원복 + 결과 보고
# =====================================================================
$env:USERPROFILE = $realHome

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

# 필터 모드 가드: 매칭 실행 0건이면 "전부 통과"로 오인되지 않게 실패 처리(오타·환경 문제 가시화).
if ($script:FilterSet -and $total -eq 0) {
    Write-Host "[FAIL] -Filter 매칭 실행 케이스 0건 — 필터 이름(오타) 또는 환경(git 부재 skip)을 확인하세요."
    exit 1
}
if ($script:FilterSet) {
    Write-Host "⚠ 부분 실행 결과 (-Filter: $($script:FilterSet -join ', ')) — 개발 반복 전용, task 검증(V-2)·F-2 판정에 사용 금지"
}
Write-Host ("결과: {0}/{1} OK (FAIL {2})" -f ($total - $failCount), $total, $failCount)
exit $(if ($failCount) { 1 } else { 0 })
