# run-hook-evals.ps1 — pjc hook 골든 회귀 러너 (lint evals의 hook 판)
#
# 사용법: pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
#   부분 실행(개발 반복 전용): ... run-hook-evals.ps1 -Filter block-destructive,require-plan-for-write
#
# 무엇을: scripts/*.ps1 hook을 격리 USERPROFILE·중립 cwd에서 stdin JSON으로 실행해
#   exit code·출력 키워드를 대조한다. 케이스 정본은 두 곳 —
#   ① hook-cases.json: 무상태(command 기반) 케이스 (block-destructive·warn-external-ops)
#   ② 이 파일의 시나리오 섹션: 상태 필요(plan 폴더·git repo·AGENTS.md 마커·post-write 파일)
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

# =====================================================================
# 1) 무상태 케이스 (hook-cases.json)
# =====================================================================
Write-Host "== pjc hook 골든 회귀 =="
if ($script:FilterSet) {
    Write-Host "⚠ 부분 실행 모드 (-Filter: $($script:FilterSet -join ', ')) — 개발 반복 전용, task 검증(V-2)·F-2 판정에 사용 금지"
}
$cases = (Get-Content -LiteralPath $casesPath -Raw -Encoding UTF8 | ConvertFrom-Json).cases
foreach ($c in $cases) {
    # 무상태 케이스는 케이스 단위 필터: 개별 hook 선택 시 그 케이스, dispatch 에코는
    # "그 hook 선택 또는 pre-bash-dispatch 선택" 시 실행(D10 — 에코만 따로 돌릴 수 있게).
    $hookBase = ($c.hook -replace '\.ps1$', '').ToLowerInvariant()
    $isDispatchEchoTarget = (-not [bool]($c.pending_fix ?? $false)) -and
        ($c.hook -in @('warn-external-ops.ps1', 'require-task-checkbox.ps1', 'warn-commit-secrets.ps1'))
    $runIndividual = Test-HookSelected @($hookBase)
    $runDispatchEcho = $isDispatchEchoTarget -and (Test-HookSelected @($hookBase, 'pre-bash-dispatch'))
    if (-not ($runIndividual -or $runDispatchEcho)) { continue }

    $json = @{ tool_name = 'Bash'; tool_input = @{ command = $c.command } } | ConvertTo-Json -Compress
    if ($runIndividual) {
        $r = Invoke-Hook $c.hook $json
        Assert-Case -Name "$($c.hook): $($c.name)" -R $r `
            -ExpectExit ([int]($c.expect_exit ?? 0)) `
            -ExpectContains ([string]($c.expect_contains ?? '')) `
            -ExpectSilent ([bool]($c.expect_silent ?? $false)) `
            -PendingFix ([bool]($c.pending_fix ?? $false))
    }

    # [v1.99.0 T6] 디스패처 전수 동등성 — 3 hook의 stateless 케이스를 pre-bash-dispatch.ps1에도
    #   같은 stdin으로 재공급해 개별 hook 경유와 일치하는지 실증(프로덕션 배선이 디스패처이므로
    #   대표 선별이 아닌 전수). block-destructive는 디스패처 무포함이라 제외.
    #   디스패처는 3 hook을 합산하므로 출력은 개별 hook의 상위집합이다 — 동등성 판정은
    #   ① exit code 일치(차단은 rtc만 유발, warn 2종은 항상 0이라 개별 exit와 동일) +
    #   ② 개별이 keyword를 요구하면 디스패처도 그 keyword 포함(상위집합). 개별 '무출력' 케이스는
    #   같은 명령이 다른 hook(예: 'git merge'가 warn-external)을 건드리면 디스패처 출력이 생기므로
    #   silent를 강제하지 않고 exit 0만 확인한다(그게 올바른 합산 동등성).
    #   pending_fix 케이스는 개별 hook 쪽에서만 판정(수정 전 red 실증용 — 디스패처 중복 불필요).
    if ($runDispatchEcho) {
        $rd = Invoke-Hook 'pre-bash-dispatch.ps1' $json
        Assert-Case -Name "dispatch=$($c.hook): $($c.name)" -R $rd `
            -ExpectExit ([int]($c.expect_exit ?? 0)) `
            -ExpectContains ([string]($c.expect_contains ?? ''))
    }
}

# =====================================================================
# 2) require-plan-for-write 시나리오 (plan 유무·trivial·temp·NotebookEdit)
# =====================================================================
# 섹션 게이트: 본문 재들여쓰기 없이 if 블록으로만 감싼다(디프 최소화 — 게이트 추가가 케이스
# 내용 변경으로 보이지 않게). 이하 모든 섹션 게이트 동일.
if (Test-HookSelected @('require-plan-for-write')) {
$noplan = Join-Path $work 'proj-noplan';  New-Item -ItemType Directory $noplan -Force | Out-Null
$withplan = Join-Path $work 'proj-plan';  New-Item -ItemType Directory $withplan -Force | Out-Null
"# plan`n- [ ] T1: work" | Set-Content (Join-Path $withplan 'plan.md')
$doneplan = Join-Path $work 'proj-done';  New-Item -ItemType Directory $doneplan -Force | Out-Null
"# plan`n- [x] T1: done" | Set-Content (Join-Path $doneplan 'plan.md')
$emptyplan = Join-Path $work 'proj-empty';  New-Item -ItemType Directory $emptyplan -Force | Out-Null
"# plan`n요약만 있고 task 체크박스가 하나도 없음" | Set-Content (Join-Path $emptyplan 'plan.md')
# 별표('*') 불릿으로 완료된 plan — G4/H3 카운팅이 '-'만 보던 버그 회귀 가드:
#   '*' 불릿을 못 세면 done=0으로 오판해 H3 '빈 plan'을 오탐한다. 통일 후엔 G4 '완료 plan'이어야 한다.
$starplan = Join-Path $work 'proj-star';  New-Item -ItemType Directory $starplan -Force | Out-Null
"# plan`n* [x] T1: done" | Set-Content (Join-Path $starplan 'plan.md')

$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'A.cs'))
Assert-Case -Name "require-plan: plan 없이 .cs Write 차단" -R $r -ExpectExit 2
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'x.md'))
Assert-Case -Name "require-plan: plan 없이 .md 통과" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $withplan (Join-Path $withplan 'A.cs'))
Assert-Case -Name "require-plan: plan 있으면 .cs 통과" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $doneplan (Join-Path $doneplan 'A.cs'))
Assert-Case -Name "require-plan: 완료 plan 경고+비차단 (in-scope 후속 안내 포함)" -R $r -ExpectExit 0 -ExpectContains '범위 내 후속'
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $emptyplan (Join-Path $emptyplan 'A.cs'))
Assert-Case -Name "require-plan: 빈 plan(체크박스 0) 경고+비차단 (H3)" -R $r -ExpectExit 0 -ExpectContains '빈/플레이스홀더'
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $starplan (Join-Path $starplan 'A.cs'))
Assert-Case -Name "require-plan: 별표('*') 완료 plan은 G4(완료)로 판정, H3(빈) 오탐 아님" -R $r -ExpectExit 0 -ExpectContains '완료된 것으로'
$trivial = @{ tool_name = 'Edit'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'A.cs'); old_string = 'int x = 1;'; new_string = 'int x = 2;' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $trivial
Assert-Case -Name "require-plan: trivial Edit 통과" -R $r -ExpectExit 0 -ExpectContains 'Trivial'
$newsym = @{ tool_name = 'Edit'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'A.cs'); old_string = '// x'; new_string = 'public class Foo { }' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $newsym
Assert-Case -Name "require-plan: 새 클래스 정의 Edit 차단" -R $r -ExpectExit 2

# [H3] 시스템 임시 폴더의 검증 스크립트 — plan 없이도 통과가 기대(회귀 가드)
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) 'pjc-hook-eval-scratch/check.py'
New-Item -ItemType Directory (Split-Path $tempFile) -Force | Out-Null
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson (Split-Path $tempFile) $tempFile)
Assert-Case -Name "require-plan: 시스템 임시폴더 .py 통과 (H3)" -R $r -ExpectExit 0

# [H5] NotebookEdit — notebook_path 인식 후 plan 게이트 적용이 기대(회귀 가드)
$nb = @{ tool_name = 'NotebookEdit'; cwd = $noplan; tool_input = @{ notebook_path = (Join-Path $noplan 'n.ipynb'); new_source = 'x=1' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $nb
Assert-Case -Name "require-plan: NotebookEdit plan 없음 차단 (H5)" -R $r -ExpectExit 2

# [T2] 실행 자산(.github/workflows/*.yml·package.json)은 plan 게이트 적용, 일반 .json/.yml은 계속 통과
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan '.github/workflows/ci.yml'))
Assert-Case -Name "require-plan: .github/workflows/*.yml plan 없이 차단 (T2)" -R $r -ExpectExit 2
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'package.json'))
Assert-Case -Name "require-plan: package.json plan 없이 차단 (T2)" -R $r -ExpectExit 2
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'tsconfig.json'))
Assert-Case -Name "require-plan: tsconfig.json 통과 (T2 회귀 가드)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'docker-compose.yml'))
Assert-Case -Name "require-plan: docker-compose.yml 통과 (T2 회귀 가드)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'package-lock.json'))
Assert-Case -Name "require-plan: package-lock.json 통과 (T2 basename 불일치)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'dist/package.json'))
Assert-Case -Name "require-plan: dist/package.json plan 없이 차단 (T2 산출물디렉터리 우회 전파)" -R $r -ExpectExit 2
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'packages/plans/package.json'))
Assert-Case -Name "require-plan: packages/plans/package.json plan 없이 차단 (T2)" -R $r -ExpectExit 2
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'dist/config.json'))
Assert-Case -Name "require-plan: dist/config.json 통과 (T2 비실행자산은 산출물 우회 유지)" -R $r -ExpectExit 0
# 선행 구분자 없는 순수 상대경로 — 정규식 (^|[\\/])의 ^ 분기 직접 검증 (cwd=noplan, file_path만 상대)
$relYml = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = '.github/workflows/rel.yml'; content = 'on: push' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $relYml
Assert-Case -Name "require-plan: 상대경로 .github/workflows/rel.yml plan 없이 차단 (T2 ^ 분기)" -R $r -ExpectExit 2

# ---- [P1T3] 신규 파일 Trivial (테스트·재현 스크립트 조건부 허용, v1.98.0) ----
$c20 = (1..20 | ForEach-Object { "line$_ = $_" }) -join "`n"
$c31 = (1..31 | ForEach-Object { "line$_ = $_" }) -join "`n"
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'tests/repro_bug.py'); content = $c20 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $wj
Assert-Case -Name "require-plan: tests/ 신규 20줄 Write 통과 (P1T3)" -R $r -ExpectExit 0 -ExpectContains 'Trivial write'
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'src/service.py'); content = $c20 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $wj
Assert-Case -Name "require-plan: 일반 소스 신규 20줄 Write 차단 유지 (P1T3)" -R $r -ExpectExit 2
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'tests/big_test.py'); content = $c31 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $wj
Assert-Case -Name "require-plan: tests/ 신규 31줄 Write 차단 (P1T3 상한)" -R $r -ExpectExit 2
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'repro-crash.sh'); content = $c20 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'require-plan-for-write.ps1' $wj
Assert-Case -Name "require-plan: repro* 네이밍 신규 Write 통과 (P1T3)" -R $r -ExpectExit 0 -ExpectContains 'Trivial write'

# ---- [P1T3] 마크업·스타일 확장자 허용 (.xml/.html/.css) ----
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'config/app.xml'))
Assert-Case -Name "require-plan: .xml plan 없이 통과 (P1T3)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'site/page.html'))
Assert-Case -Name "require-plan: .html plan 없이 통과 (P1T3)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'site/style.css'))
Assert-Case -Name "require-plan: .css plan 없이 통과 (P1T3)" -R $r -ExpectExit 0

# ---- [P1T3] G4/H3 경고 세션당 1회 디듑 (.state 마커) ----
# 위에서 doneplan·emptyplan에 각각 1회 경고했으므로, 같은 격리 홈(세션)에서 두 번째 호출은 무출력이어야 한다.
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $doneplan (Join-Path $doneplan 'B.cs'))
Assert-Case -Name "require-plan: G4 완료 plan 경고 2회차 무출력 (P1T3 디듑)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $emptyplan (Join-Path $emptyplan 'B.cs'))
Assert-Case -Name "require-plan: H3 빈 plan 경고 2회차 무출력 (P1T3 디듑)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [v1.111.0] AGENTS.md bootstrap 게이트 (신규 생성 + 스킬 미발동 차단, fail-open) ----
$agentsProj = Join-Path $work 'proj-agents';  New-Item -ItemType Directory $agentsProj -Force | Out-Null
# fixture transcript 3종 — 흔적 없음(산문 언급만: 언급만으로 통과되지 않음을 동시 실증) / Skill input 흔적 / tool result 흔적
$trNo  = Join-Path $work 'tr-no-launch.jsonl'
'{"type":"assistant","text":"bootstrap-agents-md 스킬 이야기만 하는 산문 언급"}' | Set-Content $trNo
$trIn  = Join-Path $work 'tr-launch-input.jsonl'
'{"type":"assistant","tool_use":{"name":"Skill","input":{"skill":"pjc:bootstrap-agents-md"}}}' | Set-Content $trIn
$trRes = Join-Path $work 'tr-launch-result.jsonl'
'{"type":"tool_result","content":"Launching skill: pjc:bootstrap-agents-md"}' | Set-Content $trRes

$agentsNew = Join-Path $agentsProj 'AGENTS.md'
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $agentsProj $agentsNew -top @{ transcript_path = $trNo })
Assert-Case -Name "require-plan: AGENTS.md 신규 + 발동 흔적 없음 차단 (AG1)" -R $r -ExpectExit 2 -ExpectContains 'bootstrap-agents-md'
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $agentsProj $agentsNew -top @{ transcript_path = $trIn })
Assert-Case -Name "require-plan: AGENTS.md 신규 + Skill input 흔적 통과 (AG2)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $agentsProj $agentsNew -top @{ transcript_path = $trRes })
Assert-Case -Name "require-plan: AGENTS.md 신규 + Launching result 흔적 통과 (AG3)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $agentsProj $agentsNew)
Assert-Case -Name "require-plan: AGENTS.md 신규 + transcript 미제공 fail-open 통과 (AG4)" -R $r -ExpectExit 0
$agentsExistDir = Join-Path $agentsProj 'existing';  New-Item -ItemType Directory $agentsExistDir -Force | Out-Null
'# AGENTS.md' | Set-Content (Join-Path $agentsExistDir 'AGENTS.md')
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $agentsProj (Join-Path $agentsExistDir 'AGENTS.md') -top @{ transcript_path = $trNo })
Assert-Case -Name "require-plan: 기존 AGENTS.md Write 통과 — 신규만 게이트 (AG5)" -R $r -ExpectExit 0
$agentsSubDir = Join-Path $agentsProj 'sub';  New-Item -ItemType Directory $agentsSubDir -Force | Out-Null
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $agentsProj (Join-Path $agentsSubDir 'AGENTS.md') -top @{ transcript_path = $trNo })
Assert-Case -Name "require-plan: 하위 폴더 AGENTS.md 신규도 차단 — 경로 무관 게이트 (AG6)" -R $r -ExpectExit 2 -ExpectContains 'bootstrap-agents-md'
}   # ---- §2 게이트 끝 (require-plan-for-write) ----

# =====================================================================
# 2c) [v1.118.0] plan 작성 게이트 + plan 존재 판정 강화
#   PG = plan 작성 게이트(Write 축) / PE = 체크박스 도입 Edit 축 / PD = plan 존재 판정(docs/plans)
#   TE = temp 예외 분기(plan·AGENTS 두 게이트 — 종전 스위트 사각, 2026-07-10 deferred 종결)
#   §2 픽스처에 의존하지 않고 자기 픽스처를 자기 안에서 만든다(-Filter 부분 실행에서 깨지지 않게).
# =====================================================================
if (Test-HookSelected @('require-plan-for-write')) {
# transcript 스텁 — §2의 3종은 bootstrap-agents-md 문자열이라 재사용 불가(스킬명이 다르면 매치 안 됨)
$trPlanNo = Join-Path $work 'tr-plan-none.jsonl'
'{"type":"assistant","text":"plan-feature 스킬 이야기만 하는 산문 언급"}' | Set-Content $trPlanNo
$trPlanIn = Join-Path $work 'tr-plan-input.jsonl'
'{"type":"assistant","tool_use":{"name":"Skill","input":{"skill":"pjc:plan-feature"}}}' | Set-Content $trPlanIn
$trImplRes = Join-Path $work 'tr-impl-result.jsonl'
'{"type":"tool_result","content":"Launching skill: pjc:implement-task"}' | Set-Content $trImplRes

$pg = Join-Path $work 'proj-plangate'; New-Item -ItemType Directory $pg -Force | Out-Null
$pgPlan = Join-Path $pg 'plan.md'
$pgPlansDir = Join-Path $pg 'docs/plans'; New-Item -ItemType Directory $pgPlansDir -Force | Out-Null

function New-PlanWriteJson([string]$cwd, [string]$file, [string]$content, [string]$tr) {
    $top = @{}
    if ($tr) { $top = @{ transcript_path = $tr } }
    return ((@{ tool_name = 'Write'; cwd = $cwd; tool_input = @{ file_path = $file; content = $content } } + $top) | ConvertTo-Json -Compress)
}
function New-PlanEditJson([string]$cwd, [string]$file, [string]$old, [string]$new, [string]$tr) {
    $top = @{}
    if ($tr) { $top = @{ transcript_path = $tr } }
    return ((@{ tool_name = 'Edit'; cwd = $cwd; tool_input = @{ file_path = $file; old_string = $old; new_string = $new } } + $top) | ConvertTo-Json -Compress)
}

# --- PG: Write 축 ---
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: plan.md 신규 Write + 흔적 없음 차단 (PG1)" -R $r -ExpectExit 2 -ExpectContains 'plan-feature'
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $trPlanIn)
Assert-Case -Name "plan게이트: plan.md Write + plan-feature 흔적 통과 (PG2)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $trImplRes)
Assert-Case -Name "plan게이트: plan.md Write + implement-task 흔적 통과 (PG3)" -R $r -ExpectExit 0
# PG4: 기존 plan.md도 Write면 차단 (신규/기존 무관 — 통째 재작성이므로)
"# 기존 plan`n- [x] T1: done" | Set-Content $pgPlan
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg $pgPlan "# 재작성`n- [ ] T1: y" $trPlanNo)
Assert-Case -Name "plan게이트: 기존 plan.md Write도 차단 — 재작성 게이트 (PG4)" -R $r -ExpectExit 2
# PG5: 체크박스 '상태 변경' Edit은 통과 (old에도 체크박스 있음 — 정당 갱신 경로의 핵심 회귀 가드)
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanEditJson $pg $pgPlan '- [ ] T1: x' '- [x] T1: x' $trPlanNo)
Assert-Case -Name "plan게이트: plan.md 체크박스 [ ]->[x] Edit 통과 (PG5)" -R $r -ExpectExit 0
# PG6: docs/plans/deferred.md(체크박스 0) Write 통과 — 대장 오차단 방지
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg (Join-Path $pgPlansDir 'deferred.md') "# Deferred 대장`n- [2026-07-10] 항목 하나" $trPlanNo)
Assert-Case -Name "plan게이트: docs/plans/deferred.md(체크박스 0) Write 통과 (PG6)" -R $r -ExpectExit 0
# PG7/PG8: docs/plans/*.md에 체크박스 있으면 차단 (별표 불릿 표기 변형 포함)
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg (Join-Path $pgPlansDir '2026-07-13-x.md') "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: docs/plans/ 체크박스 plan Write 차단 (PG7)" -R $r -ExpectExit 2
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg (Join-Path $pgPlansDir 'y.md') "# plan`n* [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: docs/plans/ 별표('*') 불릿 plan도 차단 (PG8)" -R $r -ExpectExit 2
# PG9: transcript 미제공 → fail-open
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $null)
Assert-Case -Name "plan게이트: transcript 미제공 fail-open 통과 (PG9)" -R $r -ExpectExit 0

# --- PE: 체크박스 '도입' Edit 축 (2단계 우회 차단) ---
$peFile = Join-Path $pgPlansDir 'sneak.md'
"# 그냥 메모" | Set-Content $peFile
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanEditJson $pg $peFile '# 그냥 메모' "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: 체크박스 도입 Edit 차단 — 2단계 우회 (PE1)" -R $r -ExpectExit 2 -ExpectContains 'plan-feature'
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanEditJson $pg $peFile '# 그냥 메모' "# plan`n- [ ] T1: x" $trImplRes)
Assert-Case -Name "plan게이트: 체크박스 도입 Edit + implement-task 흔적 통과 (PE2)" -R $r -ExpectExit 0
# PE3: MultiEdit 순차 적용 우회 — edit#1이 도입, edit#2가 그 체크박스를 old로 참조.
#   합산 판정이면 old에 체크박스가 섞여 통과했을 것(false-negative). edit 단위 판정이라 차단된다.
$peMulti = @{ tool_name = 'MultiEdit'; cwd = $pg; transcript_path = $trPlanNo; tool_input = @{
    file_path = $pgPlan
    edits = @(
        @{ old_string = 'PLACEHOLDER'; new_string = '- [ ] T1: x' },
        @{ old_string = '- [ ] T1: x'; new_string = "- [ ] T1: x`n- [ ] T2: y" }
    )
} } | ConvertTo-Json -Compress -Depth 5
$r = Invoke-Hook 'require-plan-for-write.ps1' $peMulti
Assert-Case -Name "plan게이트: MultiEdit 순차 적용 우회 차단 — edit 단위 판정 (PE3)" -R $r -ExpectExit 2

# --- PD: plan 존재 판정 (docs/plans 디렉터리) ---
# PD1: 체크박스 없는 .md만 있는 docs/plans → plan 판정 OFF → 코드 Write 차단 + 진단 문구
$pd1 = Join-Path $work 'proj-pd1'; New-Item -ItemType Directory (Join-Path $pd1 'docs/plans') -Force | Out-Null
"# 메모`n- [2026-07-10] 체크박스 아님" | Set-Content (Join-Path $pd1 'docs/plans/notes.md')
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $pd1 (Join-Path $pd1 'A.cs'))
Assert-Case -Name "plan판정: docs/plans에 체크박스 plan 없으면 코드 Write 차단 (PD1)" -R $r -ExpectExit 2 -ExpectContains 'task 체크박스'
# PD2: 체크박스 plan이 있으면 통과 (기존 동작 보존 — 강화가 정상 plan을 죽이지 않음)
$pd2 = Join-Path $work 'proj-pd2'; New-Item -ItemType Directory (Join-Path $pd2 'docs/plans') -Force | Out-Null
"# plan`n- [ ] T1: work" | Set-Content (Join-Path $pd2 'docs/plans/2026-07-13-a.md')
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $pd2 (Join-Path $pd2 'A.cs'))
Assert-Case -Name "plan판정: docs/plans에 체크박스 plan 있으면 통과 (PD2)" -R $r -ExpectExit 0
# PD3: '+' 불릿·ordered list 표기 plan도 인정 (표기 커버리지 부족으로 인한 오차단 방지)
$pd3 = Join-Path $work 'proj-pd3'; New-Item -ItemType Directory (Join-Path $pd3 'docs/plans') -Force | Out-Null
"# plan`n1. [ ] 첫 작업`n+ [ ] 둘째 작업" | Set-Content (Join-Path $pd3 'docs/plans/p.md')
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $pd3 (Join-Path $pd3 'A.cs'))
Assert-Case -Name "plan판정: '+'/ordered 체크박스 표기 plan도 인정 — 오차단 없음 (PD3)" -R $r -ExpectExit 0

# --- TE: 시스템 임시 폴더 예외 분기 (두 게이트 공통 — 종전 스위트 사각) ---
# 반드시 '흔적 없는' transcript를 주입한다 — 미주입이면 fail-open으로 exit 0이 되어
#   temp 예외를 검증하지 않고도 green이 된다(거짓 green).
$teDir = Join-Path $iso 'te-scratch'; New-Item -ItemType Directory $teDir -Force | Out-Null
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-PlanWriteJson $teDir (Join-Path $teDir 'plan.md') "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: 시스템 임시폴더 plan.md Write 통과 — temp 예외 (TE1)" -R $r -ExpectExit 0
$r = Invoke-Hook 'require-plan-for-write.ps1' (New-WriteJson $teDir (Join-Path $teDir 'AGENTS.md') 'Write' @{} @{ transcript_path = $trPlanNo })
Assert-Case -Name "AGENTS게이트: 시스템 임시폴더 AGENTS.md 신규 Write 통과 — temp 예외 (TE2)" -R $r -ExpectExit 0
}   # ---- §2c 게이트 끝 ----

# =====================================================================
# 2b) protect-harness 시나리오 (Write/Edit로 하니스 게이트 무력화 차단 — 경로 문자열만 검사, 무상태)
#   .claude 하위 설치본 hook 스크립트·hooks.json 개조만 차단.
#   .claude 없는 개발 repo 소스·일반 .claude 설정은 통과(하니스 자기 개발은 plan 게이트로 관리).
# =====================================================================
if (Test-HookSelected @('protect-harness')) {
$ph = Join-Path $work 'ph'; New-Item -ItemType Directory $ph -Force | Out-Null
$fakeInstall = Join-Path $ph '.claude/plugins/cache/pjc-harness/pjc/1.89.0'
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/block-destructive.ps1'))
Assert-Case -Name "protect-harness: 설치본 hook 스크립트 Write 차단" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'hooks/hooks.json'))
Assert-Case -Name "protect-harness: 설치본 hooks.json Write 차단" -R $r -ExpectExit 2
$phEdit = @{ tool_name = 'Edit'; cwd = $ph; tool_input = @{ file_path = (Join-Path $fakeInstall 'scripts/protect-harness.ps1'); old_string = 'exit 0'; new_string = 'exit 0 # x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'protect-harness.ps1' $phEdit
Assert-Case -Name "protect-harness: 자기 자신 Edit 차단 (self-protect)" -R $r -ExpectExit 2
# 경로 표기 변형 우회 차단 (세그먼트 정규화 — B1): ./ · 이중슬래시 · ../ 삽입해도 설치본 hook 경로를 차단
$phFwd = $ph -replace '\\', '/'
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/.claude/./plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: hook 경로 우회(./) 차단 (B1)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/.claude//plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: hook 경로 우회(이중슬래시) 차단 (B1)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/.claude/foo/../plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: hook 경로 우회(../) 차단 (B1)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $ph '.claude/settings.json'))
Assert-Case -Name "protect-harness: .claude/settings.json 통과(무경고)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'plugins/pjc/scripts/block-destructive.ps1'))
Assert-Case -Name "protect-harness: 개발 repo hook 스크립트(.claude 없음) 통과" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'src/app.ts'))
Assert-Case -Name "protect-harness: 일반 소스 통과" -R $r -ExpectExit 0 -ExpectSilent $true
# NotebookEdit — notebook_path 폴백으로 설치본 hook 경로 차단 (폴백 분기 검증)
$phNb = @{ tool_name = 'NotebookEdit'; cwd = $ph; tool_input = @{ notebook_path = "$phFwd/.claude/plugins/cache/pjc-harness/pjc/1.89.0/scripts/require-plan-for-write.ps1"; new_source = 'x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'protect-harness.ps1' $phNb
Assert-Case -Name "protect-harness: NotebookEdit notebook_path 폴백 차단" -R $r -ExpectExit 2
# [v1.90.2 H3] 8.3 단축명 마스킹 — 무관 8.3 세그먼트(RUNNER~1 등)는 hook명이 있어도 통과(개발 repo 무영향 보장).
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph 'C:/Users/RUNNER~1/myrepo/scripts/block-destructive.ps1')
Assert-Case -Name "protect-harness: 무관 8.3(RUNNER~1)+hook명 통과 (v1.90.2 H3 오탐 방지)" -R $r -ExpectExit 0 -ExpectSilent $true
# [v1.90.3 F2] CLAUDE~1 충돌 오탐 수정 — 'Claude…' 폴더의 8.3명 CLAUDE~1(이 repo 자신 포함) 아래 개발 소스
#   편집은 통과해야 한다(캐시 밖). 실제 마스킹된 설치본 hook 경로는 /plugins/cache/를 포함하므로 그때만 차단.
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/pjc/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: 8.3 CLAUDE~1 개발 repo 소스(캐시 밖) 통과 (v1.90.3 F2 오탐 수정)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/cache/pjc-harness/pjc/1.90.2/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: 8.3 마스킹 설치본(캐시 컨텍스트) 차단 (v1.90.3 F2)" -R $r -ExpectExit 2 -ExpectContains '8.3'
# [v1.97.2] v1.96.0 신설분의 이름 집합 합류 — warn-commit-secrets(hook)·secret-patterns(공유 헬퍼, 개조 시
#   시크릿 경고 계층 등가 무력화) 설치본 개조 차단. 집합 누락이 재발하면 이 두 케이스가 잡는다.
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/warn-commit-secrets.ps1'))
Assert-Case -Name "protect-harness: 설치본 warn-commit-secrets Write 차단 (v1.97.2 집합 합류)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/secret-patterns.ps1'))
Assert-Case -Name "protect-harness: 설치본 secret-patterns 헬퍼 Write 차단 (v1.97.2 등가 우회 봉쇄)" -R $r -ExpectExit 2
# [v1.99.0 T6] 디스패처·공유 lib 이름 집합 합류 — pre-bash-dispatch(hook)·bash-hook-lib(3 hook 검사 로직
#   헬퍼, 개조 시 3 게이트 등가 무력화) 설치본 개조 차단. 집합 누락 재발 시 이 두 케이스가 잡는다.
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/pre-bash-dispatch.ps1'))
Assert-Case -Name "protect-harness: 설치본 pre-bash-dispatch Write 차단 (v1.99.0 T6 집합 합류)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/bash-hook-lib.ps1'))
Assert-Case -Name "protect-harness: 설치본 bash-hook-lib 헬퍼 Write 차단 (v1.99.0 T6 등가 우회 봉쇄)" -R $r -ExpectExit 2
}   # ---- §2b 게이트 끝 (protect-harness) ----

if (Test-HookSelected @('pre-bash-dispatch')) {
# [v1.101.0 T4] 디스패처 로드 가드 — bash-hook-lib.ps1 부재(로드 실패) 시 침묵 fail-open 대신
#   stderr 경고 1줄 + exit 0(비차단)을 실증한다. lib 없는 임시 사본에서 디스패처를 단독 실행
#   (Invoke-Hook은 $scriptsDir 고정이라 lib가 항상 옆에 있음 — 부재 상황은 사본으로만 재현 가능).
$noLib = Join-Path $work 'dispatch-nolib'; New-Item -ItemType Directory $noLib -Force | Out-Null
Copy-Item (Join-Path $scriptsDir 'pre-bash-dispatch.ps1') $noLib -Force
$noLibJson = @{ tool_name = 'Bash'; tool_input = @{ command = 'git commit -m "T1: x"' } } | ConvertTo-Json -Compress
$outNoLib = $noLibJson | pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $noLib 'pre-bash-dispatch.ps1') 2>&1
$rNoLib = @{ code = $LASTEXITCODE; out = (($outNoLib | Out-String)).Trim() }
Assert-Case -Name "pre-bash-dispatch: lib 부재 시 로드 가드 경고 + exit 0 (v1.101.0 T4 fail-open 가시화)" -R $rNoLib -ExpectExit 0 -ExpectContains '로드 실패'
}   # ---- 로드 가드 게이트 끝 (pre-bash-dispatch) ----

# =====================================================================
# 4) require-evidence 시나리오 (git 필요 — 부재 시 skip. $gitOk는 top-level 공유 정의)
# =====================================================================
if (Test-HookSelected @('require-evidence')) {
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

    # ---- [P1T5] require-evidence 신규 동작 골든 (traceRx 스크립트 빌드 · 세션 Write/Edit 게이트) ----
    # 깨끗한 트리 + 증거 있는 T커밋으로 재설정(미커밋·checkpoint 경고 배제하고 traceRx만 검증).
    $ev2 = Join-Path $work 'evrepo2'; New-Item -ItemType Directory $ev2 -Force | Out-Null
    Push-Location $ev2
    git init -q; git config user.email t@t; git config user.name t
    'x' | Set-Content a.txt; git add .; git commit -qm "T1: done`n`nBuild OK, Tests 2/2 passed"
    Pop-Location
    # (A1) transcript에 표준·스크립트 빌드 흔적 없음 → '실행 흔적 못 찾음' 경고 발생
    $trA1 = Join-Path $work 'tr-a1.jsonl'
    '{"type":"tool_use","name":"Bash","input":{"command":"git status"}}' | Set-Content -Encoding UTF8 $trA1
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trA1 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: transcript에 빌드 흔적 없음 → 실행흔적 경고 (P1T5 대조군)" -R $r -ExpectExit 0 -ExpectContains '실행 흔적'
    # (A2) transcript에 스크립트 빌드(build.ps1) 흔적 → 실행흔적 경고 억제(traceRx 확장 검증). 깨끗한 트리라 전체 무출력.
    $trA2 = Join-Path $work 'tr-a2.jsonl'
    '{"type":"tool_use","name":"Bash","input":{"command":"pwsh -NoProfile -File ./build.ps1"}}' | Set-Content -Encoding UTF8 $trA2
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trA2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: transcript에 build.ps1 흔적 → 실행흔적 경고 억제 (P1T5 traceRx)" -R $r -ExpectExit 0 -ExpectSilent $true
    # (B) 미커밋 .cs + transcript에 Write/Edit 없음 → 미커밋 경고 억제(세션 게이트). build.ps1 흔적으로 실행흔적 경고도 배제.
    Push-Location $ev2; 'w' | Set-Content orphan.cs; Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trA2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 미커밋 .cs + Write/Edit 없는 세션 → 미커밋 경고 억제 (P1T5 세션 게이트)" -R $r -ExpectExit 0 -ExpectSilent $true
    # (B 대조군) 같은 미커밋 상태 + transcript에 Write 흔적 → 미커밋 경고 발생(억제가 무차별 아님)
    $trB2 = Join-Path $work 'tr-b2.jsonl'
    @('{"type":"tool_use","name":"Bash","input":{"command":"pwsh -File ./build.ps1"}}', '{"type":"tool_use","name":"Write","input":{"file_path":"orphan.cs"}}') | Set-Content -Encoding UTF8 $trB2
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trB2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 미커밋 .cs + Write 흔적 세션 → 미커밋 경고 유지 (P1T5 게이트 무차별 아님)" -R $r -ExpectExit 0 -ExpectContains '커밋되지 않은 코드'

    # ---- [v1.138.0 T5] 세션 디듑 골든 (같은 세션·같은 프로젝트의 동일 종류 경고는 1회) ----
    # 별도 repo(evrepo3)로 격리한다 — 마커 키가 cwd를 포함하므로 위 케이스들(evrepo·evrepo2)과 겹치지 않는다.
    #   (이 키 설계가 기존 골든 무회귀의 조건이다: 507의 evrepo 미커밋 경고와 534의 evrepo2 미커밋 경고가 둘 다 살아야 한다.)
    $ev3 = Join-Path $work 'evrepo3'; New-Item -ItemType Directory $ev3 -Force | Out-Null
    Push-Location $ev3
    git init -q; git config user.email t@t; git config user.name t
    'x' | Set-Content a.txt; git add .; git commit -qm 'checkpoint: T1 start'
    Pop-Location
    $jd1 = @{ cwd = $ev3; session_id = 'sd1' } | ConvertTo-Json -Compress
    # (D1) 같은 세션 1회차 → 경고 발생
    $r = Invoke-Hook 'require-evidence.ps1' $jd1
    Assert-Case -Name "evidence: 세션 디듑 1회차 → 경고 발생 (T5 red)" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    # (D2) 같은 세션 2회차 → 억제(무출력). T5의 핵심 동작.
    $r = Invoke-Hook 'require-evidence.ps1' $jd1
    Assert-Case -Name "evidence: 세션 디듑 2회차 → 억제 (T5 green)" -R $r -ExpectExit 0 -ExpectSilent $true
    # (D3) 다른 세션 → 다시 발생(디듑 단위가 세션임을 실증 — 영구 억제가 아니다)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev3; session_id = 'sd2' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 다른 세션 → 경고 재발생 (T5 세션 단위)" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    # (D4) 같은 세션·다른 종류 → 독립 발생(checkpoint는 억제된 상태에서 미커밋 경고는 살아 있어야 한다)
    Push-Location $ev3; 'w' | Set-Content orphan.cs; Pop-Location
    $trD = Join-Path $work 'tr-d.jsonl'
    '{"type":"tool_use","name":"Write","input":{"file_path":"orphan.cs"}}' | Set-Content -Encoding UTF8 $trD
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev3; session_id = 'sd1'; transcript_path = $trD } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 같은 세션 다른 종류 → 독립 발생 (T5 종류별 키)" -R $r -ExpectExit 0 -ExpectContains '커밋되지 않은 코드'
    # (D5) 마커 디렉터리 생성 불가 → fail-open(경고 유지). 상태 경로에 동명 '파일'을 두어 디렉터리 생성을 막는다.
    $reMarkerDir = Join-Path $iso '.claude/.state/require-evidence-warn'
    if (Test-Path -LiteralPath $reMarkerDir) { Remove-Item -Recurse -Force $reMarkerDir }
    New-Item -ItemType File -Path $reMarkerDir -Force | Out-Null
    $r = Invoke-Hook 'require-evidence.ps1' $jd1
    Assert-Case -Name "evidence: 마커 생성 불가 → fail-open 경고 유지 (T5)" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    Remove-Item -Force -LiteralPath $reMarkerDir

    # ---- [v1.148.0 T3 / v1.149.0 T3] 자율 루프 미완료 정지 차단 골든 (검사 4 — 유일한 차단 경로) ----
    # 검사 1~3은 비차단 경고라 stderr만 보지만, 검사 4는 stdout에 {"decision":"block"}을 낸다.
    #   Invoke-Hook이 2>&1로 합치므로 ExpectContains로 그 리터럴을 직접 고정한다.
    # 잡는 정지는 3유형 — ② 진행 예고 / ③ 세션 전환 제안 / ④ 중간 수동 실행 요청.
    # 음성을 두텁게(9건) 까는 이유: 오차단이 이 검사의 최악 실패다(사용자가 세션을 못 끝낸다).
    #   음성은 ExpectSilent가 아니라 ExpectNotContains를 쓴다 — 검사 1~3의 stderr 경고가 함께
    #   나올 수 있어 무출력이 아니며, 여기서 확인할 것은 "차단되지 않았다"뿐이다.
    # ③④는 Weak 신호(물음표·"확인 요청")를 통과 근거로 인정하지 않으므로 오차단 표면이 ②보다
    #   넓다. 그래서 **정당 개입 지점은 Strong 마커(⛔🎉⏸️)로 구분**하는데, 그 경계가 실제로
    #   작동하는지는 **마커 유무만 다른 델타 짝**(L20~L22)으로만 실증된다 — 애초에 정규식에
    #   닿지 않는 문면을 음성으로 깔면 그건 무회귀 케이스일 뿐 경계의 근거가 되지 못한다
    #   (AGENTS.md `## DO NOT`의 미탐 보완 조항이 요구하는 실증 형식).
    $loopMsg = '여기까지 진행 상황을 정리 합니다. 계속 T5부터 이어서 진행하겠습니다.'
    $loopBlock = '"decision":"block"'
    # 정상 transcript: implement-task 발동 흔적 + 평범한 사용자 발화
    $loopTr = Join-Path $work 'tr-loop.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"진행"}}'
    ) | Set-Content -Encoding UTF8 $loopTr

    # 미완료 task가 있는 저장소 2종 — task 형식 ⓑ(heading)와 ⓐ(템플릿).
    #   한 형식만 픽스처로 두면 다른 형식에서의 무발화가 검출되지 않는다(plan 2회차 BLOCKER).
    #   커밋 메시지에 'Build: OK'를 넣어 검사 2(증거 없음)가 함께 발동하지 않게 한다.
    $ev4 = Join-Path $work 'evrepo4'; New-Item -ItemType Directory $ev4 -Force | Out-Null
    Push-Location $ev4
    git init -q; git config user.email t@t; git config user.name t
    "# plan`n`n### T1 - first`n- [x] **Type**: C`n`n### T2 - second`n- [ ] **Type**: C`n" | Set-Content -Encoding UTF8 plan.md
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: first (Build: OK)'
    Pop-Location

    $ev5 = Join-Path $work 'evrepo5'; New-Item -ItemType Directory $ev5 -Force | Out-Null
    Push-Location $ev5
    git init -q; git config user.email t@t; git config user.name t
    "# plan`n`n- [x] T1. first`n- [ ] T2. second`n" | Set-Content -Encoding UTF8 plan.md
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: first (Build: OK)'
    Pop-Location

    # (L1) 양성 ⓑ — heading 형식 + **실제 사고 문장 원문**.
    #   리터럴 4문구가 아니라 어간 매칭이어야 걸린다(원문은 "여기까지 진행 상황을 정리 합니다"처럼
    #   어절이 삽입돼 있어, 리터럴 "여기까지 정리합니다"로는 매치되지 않는다).
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp1'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 미완료 + 예고 문구(heading 형식·실제 사고 원문) → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L2) 양성 ⓐ — 템플릿 형식(`- [ ] T2. second`)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev5; session_id = 'lp2'; transcript_path = $loopTr; last_assistant_message = '이어서 진행하겠습니다' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 미완료 + 예고 문구(템플릿 형식) → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L3) 음성 — stop_hook_active=true (재귀 차단 방지: 이 hook이 건 block으로 Stop이 다시 돌 때)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp3'; transcript_path = $loopTr; last_assistant_message = $loopMsg; stop_hook_active = $true } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: stop_hook_active=true → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L4) 음성 — 미완료 task 0 (전부 [x])
    $ev6 = Join-Path $work 'evrepo6'; New-Item -ItemType Directory $ev6 -Force | Out-Null
    Push-Location $ev6
    git init -q; git config user.email t@t; git config user.name t
    "# plan`n`n### T1 - only`n- [x] **Type**: C`n" | Set-Content -Encoding UTF8 plan.md
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: only (Build: OK)'
    Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev6; session_id = 'lp4'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 미완료 task 0 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L5) 음성 — 정당한 정지 신호(Halt 보고 마커)가 함께 있음
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp5'; transcript_path = $loopTr; last_assistant_message = "## ⛔ 작업 중단: T2`n이어서 진행하겠습니다만 중단합니다" } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: Halt 보고 마커 동반 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L6) 음성 — **사용자가 중단을 지시**했다. 이 검사에서 가장 중요한 안전 조건:
    #   어시스턴트 발화만 보면 사용자가 멈추라고 한 세션에 루프 재개를 강요하게 된다.
    $loopTrStop = Join-Path $work 'tr-loop-stop.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"오늘은 그만 하자"}}'
    ) | Set-Content -Encoding UTF8 $loopTrStop
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp6'; transcript_path = $loopTrStop; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 사용자가 중단 지시 → 미차단 (T3 음성·최우선 안전 조건)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L7) 음성 — `docs/plans/deferred.md`만 있는 저장소는 plan으로 인정하지 않는다.
    #   대장에는 task 패턴(ⓐ·ⓑ)이 없으므로 파일 수준 게이트에서 탈락해야 한다.
    $ev7 = Join-Path $work 'evrepo7'; New-Item -ItemType Directory $ev7 -Force | Out-Null
    Push-Location $ev7
    git init -q; git config user.email t@t; git config user.name t
    New-Item -ItemType Directory (Join-Path $ev7 'docs/plans') -Force | Out-Null
    "# Deferred 대장`n`n## 대기`n`n- [2026-07-30] 미처리 항목`n" | Set-Content -Encoding UTF8 (Join-Path $ev7 'docs/plans/deferred.md')
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: first (Build: OK)'
    Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev7; session_id = 'lp7'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: deferred.md만 있는 repo → plan 미인정, 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L8) 음성 — 직전 user 엔트리가 tool_result뿐이면 사용자 발화 추출 0건 → fail-open.
    #   tool_result를 사용자 발화로 오인하면 이 조건이 항상 참이 되어 (L6)의 방어가 무너진다.
    $loopTrTool = Join-Path $work 'tr-loop-tool.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x1","content":"ok"}]}}'
    ) | Set-Content -Encoding UTF8 $loopTrTool
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp8'; transcript_path = $loopTrTool; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: user 엔트리가 tool_result뿐 → fail-open 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L9) 음성 — 예고 문구가 없는 평범한 종료(positive 매치가 실제 게이트로 작동하는지)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp9'; transcript_path = $loopTr; last_assistant_message = '요청하신 조사를 마쳤습니다.' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 예고 문구 없는 종료 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L10) 음성 — stdin 필드가 없어도 transcript 폴백으로 판정한다(양성) / 그 폴백에서도 사용자
    #   중단 지시는 억제된다. 필드 미제공 환경에서 검사가 죽은 코드가 되지 않음을 고정한다.
    $loopTrFb = Join-Path $work 'tr-loop-fb.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"진행"}}',
        ('{"type":"assistant","message":{"content":[{"type":"text","text":"' + $loopMsg + '"}]}}')
    ) | Set-Content -Encoding UTF8 $loopTrFb
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lpA'; transcript_path = $loopTrFb } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: stdin 필드 부재 + transcript 폴백 → 차단 (T3 양성·폴백)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L11) 상한 — 같은 세션·같은 plan에서 4회째는 차단하지 않는다(판정이 어긋나도 세션을 끝낼 수 있게).
    $capJson = @{ cwd = $ev5; session_id = 'lpCap'; transcript_path = $loopTr; last_assistant_message = '계속 진행합니다' } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 1회차 → 차단 (T3)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 2회차 → 차단 (T3)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 3회차 → 차단 (T3)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 4회차 → 미차단 (T3 상한 실증)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L12) 문서↔코드 동일성 대조 — SKILL.md 금지 표현 ②③④ **세 절**의 문구 목록을 파일에서
    #   읽어 각 문구가 실제로 차단을 유발하는지 확인한다.
    #   여기서 문구를 하드코딩하면 안 된다: SKILL.md가 정본이므로 그쪽이 바뀌었는데 hook의
    #   정규식($rxAdvance·$rxHandoff·$rxManualAsk)이 안 따라가면 "규칙에 있는데 안 잡히는"
    #   상태가 되는데, 하드코딩 사본은 그 드리프트를 영원히 못 본다(사본이 낡은 채로 계속 green).
    #   어느 절이든 추출이 0건이면 그 자체가 FAIL이라 SKILL.md 구조 변경도 신호로 잡힌다.
    $skillMdPath = Join-Path $pluginRoot 'skills/implement-task/SKILL.md'
    $skillTxt = ''
    try { $skillTxt = Get-Content -LiteralPath $skillMdPath -Raw -Encoding UTF8 } catch {}
    # 절 헤더 리터럴은 SKILL.md가 정본이며 여기가 추종한다(T1이 고정한 문자열).
    foreach ($sec in @(
            @{ label = '② 평서형 예고'; head = '② 평서형 예고' },
            @{ label = '③ 세션 전환 제안'; head = '③ 세션 전환' },
            @{ label = '④ 수동 실행 요청'; head = '④ 중간 수동' })) {
        $phraseList = @()
        try {
            # 개행 클래스는 [\r\n]로 쓴다 — SKILL.md가 CRLF라 `\n+`는 `\r\n\r\n` 사이의 `\r`에 막힌다.
            $secM = [regex]::Match($skillTxt, ('(?ms)\*\*' + [regex]::Escape($sec.head) + '[^\r\n]*[\r\n]+((?:- "[^"]+"[\r\n]+)+)'))
            if ($secM.Success) {
                $phraseList = @([regex]::Matches($secM.Groups[1].Value, '- "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
            }
        } catch {}
        if ($phraseList.Count -eq 0) {
            $script:results.Add(@{ ok = $false; line = "[FAIL] evidence: SKILL.md 금지 표현 $($sec.label) 문구 추출 실패 (T3 문서<->코드 대조 - 목록 구조가 바뀌었는지 확인)" })
            continue
        }
        $phIdx = 0
        foreach ($ph in $phraseList) {
            $phIdx++
            # 문서의 자리표시자(T\<N\>)를 실제 번호로 바꿔 프로브 문장을 만든다.
            $probe = ($ph -replace '\\<N\\>', '5') -replace '<N>', '5'
            # 세션 id는 절·문구마다 고유해야 한다 — 차단 3회 상한 카운터가 세션·cwd 해시 단위라
            #   재사용하면 4번째 케이스부터 상한에 걸려 거짓 FAIL이 난다.
            $sid = 'lpP' + ($sec.head.Substring(0, 1)) + $phIdx
            $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = $sid; transcript_path = $loopTr; last_assistant_message = $probe } | ConvertTo-Json -Compress)
            Assert-Case -Name "evidence: SKILL.md $($sec.label) 문구 $phIdx/$($phraseList.Count) '$probe' → 차단 (T3 문서<->코드 동일성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
        }
    }

    # (L13) [v1.148.0 T8 / F-7 M2] transcript가 tail 상한(3000줄)을 넘어도 발동 흔적을 찾는가.
    #   흔적을 **맨 앞**에 두고 뒤를 3000줄 이상으로 채운다 — 조건 ③이 tail만 보면 흔적이 밖으로
    #   밀려 거짓이 되는데, **하필 그 긴 루프가 이 검사가 필요한 바로 그 상황**이다
    #   (실측: 이 repo transcript 최대 2817줄 = 상한의 94%).
    $loopTrBig = Join-Path $work 'tr-loop-big.jsonl'
    $bigLines = New-Object System.Collections.Generic.List[string]
    [void]$bigLines.Add('{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}')
    for ($bi = 0; $bi -lt 3200; $bi++) { [void]$bigLines.Add('{"type":"assistant","message":{"content":[{"type":"text","text":"filler"}]}}') }
    [void]$bigLines.Add('{"type":"user","message":{"content":"진행"}}')
    $bigLines | Set-Content -Encoding UTF8 $loopTrBig
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lpBig'; transcript_path = $loopTrBig; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: transcript 3000줄 초과 + 발동 흔적이 앞부분 → 차단 (T8 M2 회귀)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L14) [v1.148.0 T8 / F-7 m1] 차단 시 이벤트 로그에 block으로 적재되는가.
    #   오차단이 최악인 검사라 **사후 검토 수단**이 살아 있어야 한다(protect-harness와 같은 관례).
    #   stdout만 단언하면 적재 누락이 조용히 통과한다.
    $evLogFile = Join-Path $iso ('.claude/.state/hook-events/' + (Get-Date).ToString('yyyy-MM') + '.jsonl')
    $blkBefore = 0
    if (Test-Path -LiteralPath $evLogFile) { $blkBefore = @(Select-String -LiteralPath $evLogFile -Pattern '"decision":"block"' -SimpleMatch).Count }
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lpEv'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    $blkAfter = 0
    if (Test-Path -LiteralPath $evLogFile) { $blkAfter = @(Select-String -LiteralPath $evLogFile -Pattern '"decision":"block"' -SimpleMatch).Count }
    if ($blkAfter -gt $blkBefore) {
        $script:results.Add(@{ ok = $true; line = "[PASS] evidence: 차단 시 이벤트 로그에 block 적재 (T8 m1)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] evidence: 차단 시 이벤트 로그에 block 적재 안 됨 (T8 m1) — before=$blkBefore after=$blkAfter, 로그=$evLogFile" })
    }

    # ---- [v1.149.0 T3] ③④ 확대 골든 (L15~L22) ----
    # 실제 사고 원문과 그 형제 유형을 고정하고, 오차단 표면을 음성으로 두텁게 덮는다.
    $script:sess = 0
    function New-LoopCase {
        # 케이스마다 고유 세션 id를 발급한다(차단 3회 상한 카운터가 세션·cwd 해시 단위).
        param([string]$Msg, [string]$Cwd = $ev4, [string]$Tr = $loopTr)
        $script:sess++
        return (@{ cwd = $Cwd; session_id = ('lp149_' + $script:sess); transcript_path = $Tr; last_assistant_message = $Msg } | ConvertTo-Json -Compress)
    }

    # (L15) 양성 ③ — **실제 관측된 사고 문장**. 이 확대의 존재 이유이므로 원문 그대로 고정한다.
    $realIncident = '한 가지 알려드릴 것: 이 세션이 상당히 길어져 남은 8개 task를 이 컨텍스트에서 끝까지 끌고 가면 후반 품질이 떨어질 수 있습니다. 이대로 계속할지, 새 세션으로 옮길지 알려주세요.'
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase $realIncident)
    Assert-Case -Name "evidence: ③ 관측 사고 원문(세션 전환 제안) → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L16) 양성 ③ 폴백 — 같은 문장을 stdin 필드 없이 transcript 마지막 assistant 텍스트로만 준다.
    #   last_assistant_message의 실환경 제공 여부가 미실증이라 **폴백이 프로덕션 주 경로일 수 있다** —
    #   stdin 경로만 검증하면 ③④가 실환경에서 영구 무발화한 채 골든만 green이 된다(L10과 같은 취지).
    $loopTrHandoff = Join-Path $work 'tr-loop-handoff.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"진행"}}',
        ('{"type":"assistant","message":{"content":[{"type":"text","text":"' + $realIncident + '"}]}}')
    ) | Set-Content -Encoding UTF8 $loopTrHandoff
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp149fb'; transcript_path = $loopTrHandoff } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: ③ stdin 필드 부재 + transcript 폴백 → 차단 (T3 양성·폴백)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L17) 양성 ③ — /clear 제안.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '/clear 후 새로 시작하시면 같은 지점에서 이어집니다.')
    Assert-Case -Name "evidence: ③ /clear 제안 → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L18) 양성 ④ — 중간 수동 실행 요청(3요소 결합).
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '여기서 한번 직접 실행해 보시겠어요?')
    Assert-Case -Name "evidence: ④ 중간 수동 실행 요청 → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L19) 양성 혼합 — ②어휘 + ③어휘 + 물음표. **조기 반환 금지의 회귀 고정**:
    #   ②가 Weak(물음표)로 통과 판정된 뒤 ③ 검사에 닿지 못하면 이 문장이 그대로 새어 나간다.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '컨텍스트가 찼습니다. 새 세션으로 옮길까요? 이어서 진행하겠습니다.')
    Assert-Case -Name "evidence: ②어휘+③어휘+물음표 혼합 → 차단 (T3 양성·조기반환 금지)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L20~L22) **델타 짝** — 마커 유무만 다른 두 문면이 미차단/차단으로 갈리는지 확인한다.
    #   이것이 성립해야 "D7 Strong 마커가 정당 개입 지점의 경계를 만든다"가 실증된다.
    #   짝의 본문은 반드시 ③ 또는 ④ positive에 매치되는 것이어야 한다 — 애초에 안 걸리는 문면을
    #   음성으로 두면 마커와 무관하게 통과하므로 아무것도 증명하지 못한다.
    foreach ($pair in @(
            @{ name = 'Phase 0 사전 승인 확인'; marker = '## ⏸️ 사전 승인 확인'; body = '사전 승인 항목을 한번 직접 확인해 주시겠어요?' },
            @{ name = '규칙 12 외부 작업 승인'; marker = '## ⏸️ 외부 작업 승인 요청'; body = '새 세션에서 릴리즈를 진행할지 알려주세요.' },
            @{ name = 'plan-feature 세션 확인'; marker = '## ⏸️ 세션 확인'; body = '컨텍스트가 많이 찼습니다. 새 세션으로 옮길까요, 이대로 계속할지 알려주세요.' })) {
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase ($pair.marker + "`n" + $pair.body))
        Assert-Case -Name "evidence: $($pair.name) — Strong 마커 있음 → 미차단 (T3 음성·델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase $pair.body)
        Assert-Case -Name "evidence: $($pair.name) — 마커 제거 시 → 차단 (T3 양성·델타 짝)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    }

    # (L23) 음성 — ③ 문구에 Halt 마커(⛔)가 동반되면 통과(Strong 존중).
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase "## ⛔ 작업 중단: T2`n새 세션으로 옮길지 알려주세요")
    Assert-Case -Name "evidence: ③ + Halt 마커 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L24) 음성 — 미완료 task 0이면 ③ 문구여도 통과(조건 ① 불성립).
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '새 세션으로 옮길지 알려주세요' $ev6)
    Assert-Case -Name "evidence: ③ + 미완료 task 0 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L25) 음성 — **사용자가 먼저** 세션 전환을 꺼낸 대화에서는 억제한다(D3-ⓑ).
    #   이 검사에서 가장 위험한 오작동인 "사용자 의사 무시"를 ③에서도 막는 조건이다.
    $loopTrUserSess = Join-Path $work 'tr-loop-usersess.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"새 세션으로 옮기자"}}'
    ) | Set-Content -Encoding UTF8 $loopTrUserSess
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '알겠습니다. 새 세션에서 이어가시면 같은 지점에서 재개됩니다.' $ev4 $loopTrUserSess)
    Assert-Case -Name "evidence: 사용자가 먼저 세션 전환 제안 → 미차단 (T3 음성·D3-ⓑ)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L26) 음성 — ④ 어휘가 있으나 3요소 미충족(위임 부사 없음)인 정상 안내. 오차단 반례 회귀 고정.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '설치 후 동작을 확인해 주세요.')
    Assert-Case -Name "evidence: ④ 3요소 미충족 정상 보고 → 미차단 (T3 음성·오차단 반례)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L27) 음성 — 규칙 4를 수행하는 정상 보고. ③ ⓐ에서 상태 서술 명사를 뺀 이유의 회귀 고정.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '컨텍스트 관리 규칙에 따라 plan.md를 갱신했습니다. 이제 다음 작업자가 이어가시면 됩니다.')
    Assert-Case -Name "evidence: 규칙 4 수행 보고 → 미차단 (T3 음성·오차단 반례)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
} else {
    Write-Host "[SKIP] require-evidence 시나리오 (git 없음)"
}
}   # ---- §4 게이트 끝 (require-evidence) ----

# =====================================================================
# 5) suggest-agents-record 시나리오 (제안·억제 2중·마커 정리)
# =====================================================================
if (Test-HookSelected @('suggest-agents-record')) {
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
}   # ---- §5 게이트 끝 (suggest-agents-record) ----

# =====================================================================
# 6) post-write-checks 시나리오 (BOM·영문 주석·시크릿 7종·NotebookEdit·비차단)
#    ($pw 픽스처는 top-level 공유 정의 — §7 후속 Pre.cs 블록도 사용)
# =====================================================================
if (Test-HookSelected @('post-write-checks')) {
$csPath = Join-Path $pw 'Big.cs'
$body = (1..6 | ForEach-Object { "// english comment $_" }) + 'var password = "Sup3rSecret99";'
[System.IO.File]::WriteAllText($csPath, ($body -join "`n"), [System.Text.UTF8Encoding]::new($true))  # BOM 포함
$pj = @{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $csPath } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $pj
Assert-Case -Name "post-write: BOM 경고" -R $r -ExpectExit 0 -ExpectContains 'BOM'
Assert-Case -Name "post-write: 영문 주석 경고" -R $r -ExpectExit 0 -ExpectContains '영문'
Assert-Case -Name "post-write: password 값 경고" -R $r -ExpectExit 0 -ExpectContains 'password'
Assert-Case -Name "post-write: 비차단 exit 0" -R $r -ExpectExit 0

# ---- 시크릿 잔여 유형 (API key·DB 연결문자열·URI 자격증명·개인키·Bearer·IP) ----
# 전부 명백한 가짜 값. 개인키 마커·Bearer는 문자열 연결로 분리 기재 — 이 러너 파일 자체가
# 시크릿 스캐너·자사 post-write hook에 오탐되지 않게 한다.
$secPath = Join-Path $pw 'notes-secrets.md'
$fakeKeyMarker = '-----BEGIN RSA ' + 'PRIVATE KEY-----'
$fakeBearer = 'Bear' + 'er FAKETOKEN1234567890abc'
$secBody = @(
    'api_key = "FAKEKEY1234567890"',
    'conn: Server=dbhost;User=app;Password=fakepw123;',
    'uri: postgres://appuser:fakepass123@dbhost/appdb',
    $fakeKeyMarker,
    ('Authorization: ' + $fakeBearer),
    '운영 장비: 10.20.30.40'
) -join "`n"
[System.IO.File]::WriteAllText($secPath, $secBody, [System.Text.UTF8Encoding]::new($false))
$sjp = @{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $secPath } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $sjp
Assert-Case -Name "post-write: API key/token 값 경고" -R $r -ExpectExit 0 -ExpectContains 'API key/token 값'
Assert-Case -Name "post-write: DB 연결 문자열 경고" -R $r -ExpectExit 0 -ExpectContains 'DB 연결 문자열'
Assert-Case -Name "post-write: URI 자격증명 경고" -R $r -ExpectExit 0 -ExpectContains 'DB/서비스 URI 인증정보'
Assert-Case -Name "post-write: 개인키 경고" -R $r -ExpectExit 0 -ExpectContains '개인키'
Assert-Case -Name "post-write: Bearer 토큰 경고" -R $r -ExpectExit 0 -ExpectContains 'Bearer 토큰'
Assert-Case -Name "post-write: IP 주소 경고" -R $r -ExpectExit 0 -ExpectContains 'IP 주소'

# ---- IP 음성 2건 (예약 IP·버전 문자열 제외 로직 회귀 가드 — 다른 트리거 없는 파일이라 완전 무출력 기대) ----
$ipnegPath = Join-Path $pw 'ip-neg.md'
[System.IO.File]::WriteAllText($ipnegPath, '로컬 검증은 127.0.0.1 에서 수행.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $ipnegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 예약 IP(127.0.0.1) 무경고(음성)" -R $r -ExpectExit 0 -ExpectSilent $true
$vernegPath = Join-Path $pw 'ver-neg.md'
[System.IO.File]::WriteAllText($vernegPath, 'Version="1.2.3.4" 로 배포.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $vernegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 버전 문자열 IP 무경고(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- notes.md 아카이브 시점 경고 (v1.112.0 — 초과 경고·디듑·경계 음성) ----
# 픽스처는 순수 한글 1줄(시크릿·IP·영문 주석·1500라인 트리거 없음) — 아카이브 경고만 단독 검증.
$naDir = Join-Path $pw 'notes-arch'; New-Item -ItemType Directory $naDir -Force | Out-Null
$naPath = Join-Path $naDir 'notes.md'
[System.IO.File]::WriteAllText($naPath, [string]::new([char]'가', 30001), [System.Text.UTF8Encoding]::new($false))
$naj = @{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $naPath } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $naj
Assert-Case -Name "post-write: notes.md 30,000자 초과 아카이브 경고 (NA1)" -R $r -ExpectExit 0 -ExpectContains '아카이브'
$r = Invoke-Hook 'post-write-checks.ps1' $naj
Assert-Case -Name "post-write: notes.md 아카이브 경고 2회차 무출력 (NA2 디듑)" -R $r -ExpectExit 0 -ExpectSilent $true
# 경계: 정확히 30,000자는 "초과" 아님 → 무경고 (디듑 키가 경로 기반이라 별도 폴더로 분리)
$naDir2 = Join-Path $pw 'notes-arch-neg'; New-Item -ItemType Directory $naDir2 -Force | Out-Null
$naPath2 = Join-Path $naDir2 'notes.md'
[System.IO.File]::WriteAllText($naPath2, [string]::new([char]'가', 30000), [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $naPath2 } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: notes.md 정확히 30,000자 무경고 (NA3 경계)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [L5] 옥텟 초과(999.x)는 IP 아님 — 무경고 (옥텟 0-255 제한 회귀 가드) ----
$octnegPath = Join-Path $pw 'oct-neg.md'
[System.IO.File]::WriteAllText($octnegPath, '식별자 999.999.999.999 는 IP 아님.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $octnegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 옥텟 초과 999.x IP 무경고 (L5)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [P1T2] password 값 제외 조건 (타입 선언·env 조회·키워드 — 오탐 방지, v1.98.0) ----
# hook이 권장하는 패턴(환경변수 조회)까지 'password 값'으로 경고하던 늑대소년화 수정의 회귀 가드.
$pwnegPath = Join-Path $pw 'pw-neg.md'
$pwnegBody = @(
    'interface Login { password: string }',
    'pwd = os.getcwd()',
    "db_password = os.getenv('DB_PASSWORD')",
    'password = None'
) -join "`n"
[System.IO.File]::WriteAllText($pwnegPath, $pwnegBody, [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $pwnegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: password 타입선언·env조회·키워드 무경고 (P1T2 음성)" -R $r -ExpectExit 0 -ExpectSilent $true
# 평문 값은 경고 유지 (제외 조건이 실 시크릿을 놓치지 않는지 — 양성 유지 가드)
$pwposPath = Join-Path $pw 'pw-pos.md'
[System.IO.File]::WriteAllText($pwposPath, 'password = "hunter2fake"', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $pwposPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: password 평문 값 경고 유지 (P1T2 양성)" -R $r -ExpectExit 0 -ExpectContains 'password'

# ---- [P1T2] IP 전체 매치 순회 (first-match-only 양방향 결함 수정, v1.98.0) ----
# 첫 매치가 예약 IP(127.0.0.1)여도 뒤따르는 공인 IP를 검출한다(종전엔 검사가 통째로 끝나던 미탐).
$ipmixPath = Join-Path $pw 'ip-mix.md'
[System.IO.File]::WriteAllText($ipmixPath, '로컬 127.0.0.1 검증 후 8.8.4.4 로 전환.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $ipmixPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 예약 IP 뒤 공인 IP 검출 (P1T2 미탐 수정)" -R $r -ExpectExit 0 -ExpectContains 'IP 주소'
# 사설 대역은 별도 라벨(톤 완화)
$ipprivPath = Join-Path $pw 'ip-priv.md'
[System.IO.File]::WriteAllText($ipprivPath, '게이트웨이 192.168.0.10 설정.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $ipprivPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 사설 IP 별도 라벨 (P1T2)" -R $r -ExpectExit 0 -ExpectContains 'IP 주소(사설)'

# ---- [H2] 하니스 hook 스크립트 변경 감지 (비차단 경고) ----
$hookPath = Join-Path $pw 'plugins/pjc/scripts/block-destructive.ps1'
New-Item -ItemType Directory (Split-Path $hookPath) -Force | Out-Null
[System.IO.File]::WriteAllText($hookPath, '# test', [System.Text.UTF8Encoding]::new($true))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $hookPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 하니스 hook 스크립트 변경 감지 (H2)" -R $r -ExpectExit 0 -ExpectContains 'hook 스크립트 변경'

# ---- [v1.90.2 M2] .claude/settings.json 변경 감지 (enabledPlugins 하니스 전체 무력화면 — 비차단 경고) ----
$setPath = Join-Path $pw '.claude/settings.json'
New-Item -ItemType Directory (Split-Path $setPath) -Force | Out-Null
[System.IO.File]::WriteAllText($setPath, '{}', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $setPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: .claude/settings.json 변경 경고 (v1.90.2 M2)" -R $r -ExpectExit 0 -ExpectContains 'enabledPlugins'

# ---- NotebookEdit — notebook_path 인식 후 검사 적용 (T1 매처·폴백 회귀 가드) ----
$nbPath = Join-Path $pw 'analysis.ipynb'
[System.IO.File]::WriteAllText($nbPath, '{"cells":[{"cell_type":"code","source":["password = ''Fake12345''"]}]}', [System.Text.UTF8Encoding]::new($false))
$nbj = @{ tool_name = 'NotebookEdit'; cwd = $pw; tool_input = @{ notebook_path = $nbPath; new_source = 'x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $nbj
Assert-Case -Name "post-write: NotebookEdit notebook_path 인식 — password 경고" -R $r -ExpectExit 0 -ExpectContains 'password'

# ---- 시크릿 스캔 범위: 추적 파일은 추가 라인만 (v1.147.0) — 델타 2건 ----
# 위 시크릿 7종은 비 git 픽스처($pw)라 전재 폴백 경로로 통과한다(무회귀) — 그래서 새 동작을
#   고정하지 못한다. 아래 2건이 "추적 파일에서 실제로 좁혀졌음"을 실증하는 델타 케이스다:
#   ① HEAD에 이미 있는 시크릿을 재저장 → 무경고(종전에는 매 저장마다 경고)
#   ② 같은 파일에 새 시크릿 라인 추가 → 경고(탐지 능력 유지 — 미탐이 아님)
# git 임시 repo 구성은 §9 warn-commit-secrets 케이스(L910 근방)와 동일 패턴.
if ($gitOk) {
    $pwRepo = Join-Path $work 'pwrepo'; New-Item -ItemType Directory $pwRepo -Force | Out-Null
    $pwDoc = Join-Path $pwRepo 'doc.md'
    # 가짜 값은 문자열 연결로 분리 기재 — 러너 파일 자체가 자사 시크릿 스캐너에 오탐되지 않게(L854 관례)
    $fakeUri = 'postgres://' + 'u1' + ':' + 'p123456' + '@h/db'
    Push-Location $pwRepo
    git init -q; git config user.email t@t; git config user.name t
    ('예시: DATABASE_URL=' + $fakeUri) | Set-Content doc.md -Encoding UTF8
    git add doc.md; git commit -qm init
    Pop-Location
    $pwRepoJson = @{ tool_name = 'Write'; cwd = $pwRepo; tool_input = @{ file_path = $pwDoc } } | ConvertTo-Json -Compress

    # ① 델타: HEAD에 이미 있는 시크릿 → 추가 라인 0줄이라 무경고
    $r = Invoke-Hook 'post-write-checks.ps1' $pwRepoJson
    Assert-Case -Name "post-write: 추적 파일의 기존 시크릿 재신고 안 함 (범위 축소 델타)" -R $r -ExpectExit 0 -ExpectNotContains '민감 정보'

    # ② 델타: 새 시크릿 라인 추가 → 경고 (탐지 능력 유지 실증)
    Add-Content -LiteralPath $pwDoc -Value ('신규: DB_URL=' + $fakeUri) -Encoding UTF8
    $r = Invoke-Hook 'post-write-checks.ps1' $pwRepoJson
    Assert-Case -Name "post-write: 추적 파일의 신규 시크릿 라인은 경고 (미탐 아님)" -R $r -ExpectExit 0 -ExpectContains '민감 정보'

    Remove-Item -Recurse -Force $pwRepo -ErrorAction SilentlyContinue

    # ③ HEAD 없는 저장소(초기 커밋 전 staged) → 전재 폴백으로 경고 유지 (V-5 B1 회귀 가드)
    #   ls-files는 staged 파일이면 HEAD 없이도 성공하지만 `diff HEAD`는 exit 128로 실패한다 —
    #   그 실패를 무시하면 "추가 라인 0줄"과 구분되지 않아 스캔이 스킵되고 시크릿이 통째로 미탐된다.
    #   위 ①②는 항상 커밋된 저장소만 쓰므로 이 공백을 잡지 못한다(그래서 별도 케이스).
    $pwFresh = Join-Path $work 'pwfresh'; New-Item -ItemType Directory $pwFresh -Force | Out-Null
    $pwFreshDoc = Join-Path $pwFresh 'sec.md'
    Push-Location $pwFresh
    git init -q; git config user.email t@t; git config user.name t
    ('DATABASE_URL=' + $fakeUri) | Set-Content sec.md -Encoding UTF8
    git add sec.md                      # 커밋하지 않는다 — HEAD 부재 상태를 만든다
    Pop-Location
    $r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pwFresh; tool_input = @{ file_path = $pwFreshDoc } } | ConvertTo-Json -Compress)
    Assert-Case -Name "post-write: HEAD 없는 저장소는 전재 폴백 — 시크릿 경고 유지" -R $r -ExpectExit 0 -ExpectContains '민감 정보'
    Remove-Item -Recurse -Force $pwFresh -ErrorAction SilentlyContinue
}

# =====================================================================
# 7) impact-warn 시나리오 (git 필요 — caller 경고 양성·음성. §6과 같은 post-write-checks
#    게이트 안 — $gitOk는 top-level 정의라 필터 조합과 무관하게 항상 판정됨)
# =====================================================================
if ($gitOk) {
    $imp = Join-Path $work 'imprepo'; New-Item -ItemType Directory $imp -Force | Out-Null
    Push-Location $imp
    git init -q; git config user.email t@t; git config user.name t
    'namespace Demo { }' | Set-Content Widget.cs
    'var s = WidgetService.RefreshCache();' | Set-Content CallerFile.cs
    'namespace Demo2 { }' | Set-Content Lonely.cs
    git add .; git commit -qm 'base'
    # public 클래스·메서드 심볼 추가 수정 — caller(CallerFile.cs)가 있는 양성 케이스
    "public class WidgetService {`n    public static void RefreshCache() { }`n}" | Set-Content Widget.cs
    Pop-Location
    $ij = @{ tool_name = 'Write'; cwd = $imp; tool_input = @{ file_path = (Join-Path $imp 'Widget.cs') } } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'post-write-checks.ps1' $ij
    Assert-Case -Name "impact: public 심볼 변경 caller 경고" -R $r -ExpectExit 0 -ExpectContains 'IMPACT WARNING'
    Assert-Case -Name "impact: caller 파일 경로 제시" -R $r -ExpectExit 0 -ExpectContains 'CallerFile.cs'
    # caller 없는 심볼 — 완전 무출력(음성. BOM·주석·시크릿도 없는 파일이라 IMPACT 미출력이면 전체 무출력)
    Push-Location $imp
    "public class LonelyThing {`n}" | Set-Content Lonely.cs
    Pop-Location
    $ij2 = @{ tool_name = 'Write'; cwd = $imp; tool_input = @{ file_path = (Join-Path $imp 'Lonely.cs') } } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'post-write-checks.ps1' $ij2
    Assert-Case -Name "impact: caller 없는 심볼 무경고(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [P1T4] stop-list 흔한 식별자 제외 (Name/Type 등 — 무관 파일 다독 유도 방지) ----
    $imp2 = Join-Path $work 'imprepo-stop'; New-Item -ItemType Directory $imp2 -Force | Out-Null
    Push-Location $imp2
    git init -q; git config user.email t@t; git config user.name t
    'namespace D { class X { } }' | Set-Content Model.cs
    "// Name 은 여기저기 쓰인다`nvar a = ""Name"";`nvar b = Name;" | Set-Content Uses.cs
    git add .; git commit -qm base
    "public class Model {`n    public string Name { get; set; }`n}" | Set-Content Model.cs
    Pop-Location
    $r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $imp2; tool_input = @{ file_path = (Join-Path $imp2 'Model.cs') } } | ConvertTo-Json -Compress)
    Assert-Case -Name "impact: stop-list 심볼(Name) 무경고 (P1T4)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [P1T4] 세션·심볼당 1회 디듑 (같은 파일 2회 편집 시 2회차 impact 무경고) ----
    $imp3 = Join-Path $work 'imprepo-dedup'; New-Item -ItemType Directory $imp3 -Force | Out-Null
    Push-Location $imp3
    git init -q; git config user.email t@t; git config user.name t
    'namespace D { }' | Set-Content Widget.cs
    'var s = RefreshCache();' | Set-Content Caller.cs
    git add .; git commit -qm base
    "public class Svc {`n    public static void RefreshCache() { }`n}" | Set-Content Widget.cs
    Pop-Location
    $ijd = @{ tool_name = 'Write'; cwd = $imp3; session_id = 'dedup-sess'; tool_input = @{ file_path = (Join-Path $imp3 'Widget.cs') } } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'post-write-checks.ps1' $ijd
    Assert-Case -Name "impact: RefreshCache 1회차 경고 (P1T4 디듑 전제)" -R $r -ExpectExit 0 -ExpectContains 'RefreshCache'
    $r = Invoke-Hook 'post-write-checks.ps1' $ijd
    Assert-Case -Name "impact: RefreshCache 2회차 무경고 (P1T4 세션 디듑)" -R $r -ExpectExit 0 -ExpectSilent $true
} else {
    Write-Host "[SKIP] impact-warn 시나리오 (git 없음)"
}

# ---- [P1T4] C# 전처리 지시문(#region/#if)은 영문 주석 오집계 제외 ----
$prePath = Join-Path $pw 'Pre.cs'
# 영문 // 주석 3줄(≤5) + 전처리 지시문 6개 — 종전 '//|#' 판정이면 지시문까지 세어 9줄(>5)로
# 영문주석 경고를 오탐했을 것. 새 판정(.cs는 //만)이면 3줄뿐이라 >5 미달로 무경고여야 한다.
# .cs이지만 BOM 없이 저장(BOM 경고와 분리해 영문주석 판정만 검증).
$preBody = @('#region Helpers', '#if DEBUG', '#pragma warning disable', '// one', '// two', '// three', '#else', '#endif', '#endregion') -join "`n"
[System.IO.File]::WriteAllText($prePath, $preBody, [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; session_id = 'pre-sess'; tool_input = @{ file_path = $prePath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: C# 전처리 지시문 영문주석 오집계 제외 (P1T4 — //3줄뿐이라 >5 미달로 무경고)" -R $r -ExpectExit 0 -ExpectSilent $true
}   # ---- §6·§7·Pre.cs 게이트 끝 (post-write-checks) ----

# =====================================================================
# 8) require-task-checkbox 시나리오 (plan 체크박스 게이트 — git 불요, plan 파일만)
# =====================================================================
# hook은 command 문자열 파싱 + plan 파일 Read만 하므로 git repo가 필요 없다.
# 무상태 음성(비커밋·checkpoint·merge 등)은 hook-cases.json, 여기는 plan 상태 필요분.
# 게이트 태그 2개: dispatch 동등성 블록이 이 섹션의 plan 픽스처($rtcUn·$rtcOk)를 재사용하므로
# pre-bash-dispatch 필터에서도 섹션 전체를 실행한다(초과 실행 허용 원칙).
if (Test-HookSelected @('require-task-checkbox', 'pre-bash-dispatch')) {
$rtcUn = Join-Path $work 'rtc-unchecked'; New-Item -ItemType Directory $rtcUn -Force | Out-Null
"# plan`n- [ ] T3. 검색 기능`n- [x] T1. 완료분" | Set-Content (Join-Path $rtcUn 'plan.md')
$rtcIn = Join-Path $work 'rtc-inprog'; New-Item -ItemType Directory $rtcIn -Force | Out-Null
"# plan`n- [/] T3. 진행 중" | Set-Content (Join-Path $rtcIn 'plan.md')
$rtcOk = Join-Path $work 'rtc-checked'; New-Item -ItemType Directory $rtcOk -Force | Out-Null
"# plan`n- [x] T3. 검색 기능" | Set-Content (Join-Path $rtcOk 'plan.md')
$rtcMulti = Join-Path $work 'rtc-multi/docs/plans'; New-Item -ItemType Directory $rtcMulti -Force | Out-Null
"# part1`n- [ ] T3. x" | Set-Content (Join-Path $rtcMulti 'a-part1.md')

$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcUn 'T3: 검색 요약')
Assert-Case -Name "rtc: 미완료 [ ] T3 커밋 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcIn 'T3: 검색 요약')
Assert-Case -Name "rtc: 진행중 [/] T3 커밋 차단" -R $r -ExpectExit 2 -ExpectContains 'T3'
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcOk 'T3: 검색 요약')
Assert-Case -Name "rtc: 완료 [x] T3 커밋 통과(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcUn 'T99: 없는 task')
Assert-Case -Name "rtc: plan에 없는 T번호 통과(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson (Join-Path $work 'rtc-multi') 'T3: x')
Assert-Case -Name "rtc: docs/plans 복수만 존재 통과(판정 모호)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcUn 'T1: 이미 완료된 task')
Assert-Case -Name "rtc: [x] T1은 통과·[ ] T3 무관(첫 매치만 판정)" -R $r -ExpectExit 0 -ExpectSilent $true
$rtcStar = Join-Path $work 'rtc-star'; New-Item -ItemType Directory $rtcStar -Force | Out-Null
"# plan`n* [ ] T3. 별표 불릿" | Set-Content (Join-Path $rtcStar 'plan.md')
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcStar 'T3: 요약')
Assert-Case -Name "rtc: 별표 불릿 * [ ] T3 커밋 차단 (M6)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

# plan 파일이 아예 없는 프로젝트 → 통과 (fail-open. 상위 탐색은 .git/.claude 경계에서 멈춤)
$rtcNo = Join-Path $work 'rtc-noplan'; New-Item -ItemType Directory $rtcNo -Force | Out-Null
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcNo 'T3: 검색 요약')
Assert-Case -Name "rtc: plan 파일 없음 통과(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [P1T5] 제목이 아닌 본문·괄호의 T<N>: 언급은 판정 제외 (제목 첫 줄만) ----
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcUn '문서: 릴리즈 노트 (T3: 스키마 변경 반영)')
Assert-Case -Name "rtc: 제목이 '문서:'이고 괄호에 T3 언급 → 통과 (P1T5 제목 한정)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcUn 'T3: 실제 완료 커밋')
Assert-Case -Name "rtc: 제목이 T3:로 시작 → 미완료 차단 유지 (P1T5)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

# QUICK 우회 — 별도 stderr 안내 출력이 있는 독립 분기 (silent 아님, exit 0)
$env:CLAUDE_HARNESS_QUICK = '1'
$r = Invoke-Hook 'require-task-checkbox.ps1' (New-CommitJson $rtcUn 'T3: 검색 요약')
Assert-Case -Name "rtc: QUICK=1 우회 (비차단 + 안내)" -R $r -ExpectExit 0 -ExpectContains 'QUICK'
$env:CLAUDE_HARNESS_QUICK = $null

# ---- [v1.99.0 T6] rtc 스테이트풀 케이스 디스패처 동등성 (plan cwd 필요분) ----
$r = Invoke-Hook 'pre-bash-dispatch.ps1' (New-CommitJson $rtcUn 'T3: 검색 요약')
Assert-Case -Name "dispatch=rtc: 미완료 [ ] T3 커밋 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$r = Invoke-Hook 'pre-bash-dispatch.ps1' (New-CommitJson $rtcOk 'T3: 검색 요약')
Assert-Case -Name "dispatch=rtc: 완료 [x] T3 커밋 통과(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'pre-bash-dispatch.ps1' (New-CommitJson $rtcUn '문서: 릴리즈 노트 (T3: 반영)')
Assert-Case -Name "dispatch=rtc: 제목 아닌 T3 언급 통과 (제목 한정)" -R $r -ExpectExit 0 -ExpectSilent $true
}   # ---- §8 게이트 끝 (require-task-checkbox·pre-bash-dispatch) ----

# =====================================================================
# 9) warn-commit-secrets 시나리오 (git 필요 — 커밋 시점 스테이징 스캔)
# =====================================================================
# 무상태 음성(비커밋·--dry-run)은 스테이징 상태가 필요 없지만, 양성(스테이징 시크릿·-am)은 git 상태 필요.
# 러너 파일 자체가 자사 시크릿 스캐너·post-write hook에 오탐되지 않게 가짜 값은 문자열 연결로 분리 기재.
# 게이트 태그 2개: 내부 dispatch 동등성·고유 분기가 이 섹션의 $wcs git 상태를 공유(초과 실행 허용).
if (Test-HookSelected @('warn-commit-secrets', 'pre-bash-dispatch')) {

# ---- [v1.119.0] secret-patterns 라벨 판정 (함수 단위 — hook 실행 전 단계) ----
# 실사고: README의 "관리자 계정: `<id>` / `<pw>`"가 종전 7패턴 어디에도 안 걸려 공개 커밋됐다.
# 자격증명 쌍은 오탐이 곧 커밋 차단(자율 루프 정지)이라, 양성만큼 음성(정상 문서)이 중요하다 —
#   경로·라우트·파일명·버전·역할 열거는 반드시 통과해야 한다.
. (Join-Path $scriptsDir 'secret-patterns.ps1')
$spId = 'ad' + 'min'
$spPw = 'Zq7' + '#mK21'
$spBt = [char]96
$spCases = @(
    @{ n = '인용 쌍 → 자격증명 쌍(고신뢰)';   t = "관리자 계정: $spBt$spId$spBt / $spBt$spPw$spBt";                  e = '자격증명 쌍' }
    @{ n = '비인용 쌍 → 경고 라벨';           t = "계정: $spId / $spPw";                                             e = '자격증명 쌍(비인용)' }
    @{ n = '한글 비밀번호 값';                t = '비밀번호: ' + 'Zq7' + '#mK21';                                    e = 'password 값' }
    @{ n = '음성: 한글 대비 문구';            t = '계정 종류: 관리자 / 일반 사용자';                                 e = '' }
    @{ n = '음성: 코드 심볼';                 t = 'AdminService / UserService_v2';                                    e = '' }
    @{ n = '음성: 표·경로';                   t = '| admin | /api/v1/users |';                                        e = '' }
    @{ n = '음성: 환경변수 안내';             t = '비밀번호: 환경변수 PD_ADMIN_PASSWORD로 지정';                     e = '' }
    @{ n = '음성: API 라우트';                t = '계정 생성 API: POST /api/v1/accounts';                             e = '' }
    @{ n = '음성: 파일 경로 쌍';              t = '관리자 계정 설정: appsettings.json / appsettings.Production.json'; e = '' }
    @{ n = '음성: 버전 쌍';                   t = '계정 서비스 v1.2 / v1.3';                                          e = '' }
    @{ n = '음성: 미열거 확장자';             t = '계정 설정 파일: config.yml / config.production.yml';               e = '' }
    @{ n = '음성: 역할 열거형';               t = '계정 유형: admin / super_admin';                                   e = '' }
    # T1 리뷰 지적분 — 골든에 없어 통과했던 구멍 3종
    @{ n = 'ID/PW 키워드 쌍';                 t = "ID/PW: $spBt$spId$spBt / $spBt$spPw$spBt";                        e = '자격증명 쌍' }
    @{ n = '음성: 각괄호 플레이스홀더';       t = "관리자 계정: $spBt$spId$spBt / $spBt<PASSWORD123>$spBt";          e = '' }
    @{ n = '음성: 인용부호 짝 불일치';        t = "관리자 계정: $($spBt)$spId`" / `"$spPw$spBt";                     e = '' }
    # F-7 지적분 — 공개 GitHub의 다수가 영문 README다. 한글 \b는 어절 경계와 어긋나 무공백을 놓쳤다.
    @{ n = '영문 account 쌍';                 t = "Default account: $spBt$spId$spBt / $spBt$spPw$spBt";               e = '자격증명 쌍' }
    @{ n = '영문 credentials 쌍';             t = "Credentials: $spBt$spId$spBt / $spBt$spPw$spBt";                   e = '자격증명 쌍' }
    @{ n = '무공백 관리자계정';               t = "관리자계정: $spBt$spId$spBt / $spBt$spPw$spBt";                    e = '자격증명 쌍' }
    @{ n = 'test 접두 실계정(testadmin)';     t = "계정: ${spBt}testadmin$spBt / $spBt$spPw$spBt";                    e = '자격증명 쌍' }
    @{ n = '음성: 영문 설정값(login: true)';  t = 'login: true / false';                                              e = '' }
    @{ n = '음성: 영문 라우트(account API)';  t = 'account API: GET /api/v1/accounts';                                e = '' }
    @{ n = '음성: 영문 예시 플레이스홀더';    t = "Login: ${spBt}example$spBt / ${spBt}your-password$spBt";           e = '' }
)
foreach ($sc in $spCases) {
    $got = (@(Get-SecretMatches $sc.t) -join ',')
    $ok = if ($sc.e -eq '') { $got -eq '' } else { $got -eq $sc.e }
    if ($ok) {
        $script:results.Add(@{ ok = $true; line = "[PASS] secret-patterns: $($sc.n)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] secret-patterns: $($sc.n) — 기대 '$($sc.e)', 실제 '$got'" })
    }
}
# 고신뢰 라벨 집합 — warn-commit-secrets 차단 기준(T2). 집합이 조용히 바뀌면 차단 범위가 바뀐다.
$hcExpect = @('개인키', 'DB 연결 문자열', 'DB/서비스 URI 인증정보', '자격증명 쌍')
$hcGot = @(Get-HighConfidenceSecretLabels)
if (-not (Compare-Object $hcExpect $hcGot)) {
    $script:results.Add(@{ ok = $true; line = '[PASS] secret-patterns: 고신뢰 라벨 집합 4종' })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] secret-patterns: 고신뢰 라벨 집합 불일치 — 실제 '$($hcGot -join ',')'" })
}

if ($gitOk) {
    $wcs = Join-Path $work 'wcsrepo'; New-Item -ItemType Directory $wcs -Force | Out-Null
    Push-Location $wcs
    git init -q; git config user.email t@t; git config user.name t
    'v=1' | Set-Content app.js; git add .; git commit -qm init
    Pop-Location
    $fakeApi = 'api_key = "' + 'ABCDEF1234567890' + '"'
    $wcsJson = @{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m test' } } | ConvertTo-Json -Compress

    # 1) staged 시크릿 → 경고
    Push-Location $wcs; Set-Content secret.js $fakeApi; git add secret.js; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsJson
    Assert-Case -Name "commit-secrets: staged 시크릿 경고" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # 2) --dry-run → 스킵(무출력)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit --dry-run' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: --dry-run 스킵(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true

    # 3) .env 스테이징 → 파일명 경고
    Push-Location $wcs; Set-Content .env 'v=1'; git add -f .env; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsJson
    Assert-Case -Name "commit-secrets: .env 스테이징 경고" -R $r -ExpectExit 0 -ExpectContains '.env'

    # 4) 클린 스테이징(시크릿·.env 제거) → 무출력(음성)
    Push-Location $wcs
    git rm -q --cached secret.js .env; Remove-Item secret.js, .env -Force
    'clean=1' | Set-Content ok.txt; git add ok.txt; git commit -qm clean
    Pop-Location
    Push-Location $wcs; 'more=1' | Set-Content ok.txt; git add ok.txt; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsJson
    Assert-Case -Name "commit-secrets: 클린 스테이징 무출력(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

    # 5) -am 자동 스테이징분(추적 파일 시크릿) → 경고
    Push-Location $wcs; git commit -qm ok2; Add-Content app.js $fakeApi; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -am update' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: -am 자동스테이징 시크릿 경고" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # 6) 같은 미스테이징 변경 + -m(자동스테이징 아님) → 무출력(음성 — 메시지 속 -a 오탐 없음 포함)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m update' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: -m 미스테이징 미탐(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

    # 7) git commit 아님 → 통과(무출력, fast path)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git status' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: git commit 아님 통과(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [v1.119.0] 고신뢰 라벨 커밋 차단 (exit 2) ----
    # 상태 오염을 피하려고 별도 repo를 쓴다(위 $wcs는 케이스 1~7이 순서 의존으로 공유).
    # 픽스처는 러너 자신이 자사 스캐너·post-write hook에 걸리지 않게 문자열 연결로 분리 기재한다.
    $wcsB = Join-Path $work 'wcsblock'; New-Item -ItemType Directory $wcsB -Force | Out-Null
    Push-Location $wcsB
    git init -q; git config user.email t@t; git config user.name t
    'v=1' | Set-Content app.js; git add .; git commit -qm init
    Pop-Location
    $wcsBJson = @{ tool_name = 'Bash'; cwd = $wcsB; tool_input = @{ command = 'git commit -m test' } } | ConvertTo-Json -Compress
    $btB = [char]96
    $credLine = '기본 관리자 계정: ' + $btB + 'ad' + 'min' + $btB + ' / ' + $btB + 'Zq7' + '#mK21' + $btB

    # (a) 자격증명 쌍(고신뢰) 스테이징 → 차단 + 회복 경로 2종 안내
    Push-Location $wcsB; Set-Content README.md $credLine; git add README.md; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 자격증명 쌍 커밋 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    Assert-Case -Name "commit-secrets: 차단 메시지에 우회 변수 안내" -R $r -ExpectExit 2 -ExpectContains 'CLAUDE_HARNESS_ALLOW_SECRET'
    # 우회 변수는 세션 시작 전에만 설정 가능하다 — Bash 도구로 설정해도 hook에 전파되지 않는다(M8).
    Assert-Case -Name "commit-secrets: 차단 메시지에 세션 시작 전 설정 안내" -R $r -ExpectExit 2 -ExpectContains '시작 전 터미널'

    # (b) QUICK=1이어도 차단 유지 — 안전 임계 게이트는 QUICK에 종속되지 않는다(M6).
    $env:CLAUDE_HARNESS_QUICK = '1'
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: QUICK=1이어도 자격증명 차단 유지" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    $env:CLAUDE_HARNESS_QUICK = $null

    # (c) 전용 escape hatch → 통과(경고). 오탐 시 사용자가 빠져나갈 문이 있어야 한다.
    $env:CLAUDE_HARNESS_ALLOW_SECRET = '1'
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: ALLOW_SECRET=1 우회(경고, exit 0)" -R $r -ExpectExit 0 -ExpectContains 'ALLOW_SECRET'
    $env:CLAUDE_HARNESS_ALLOW_SECRET = $null

    # (d) 개인키(고신뢰) → 차단
    Push-Location $wcsB
    git rm -q --cached README.md; Remove-Item README.md -Force
    Set-Content key.pem ('-----BEGIN RSA ' + 'PRIVATE KEY-----'); git add key.pem
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 개인키 커밋 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (d2) DB 연결 문자열(고신뢰) → 차단. 고신뢰 4종 중 hook 레벨 실증이 빠지면 $highConf 필터
    #      버그를 함수 단위 테스트로는 못 잡는다.
    Push-Location $wcsB
    git rm -q --cached key.pem; Remove-Item key.pem -Force
    # 기존 DB 패턴은 'Server=<v>;' 바로 뒤 User/Pwd/Password 키를 요구한다(secret-patterns.ps1:29).
    #   'User Id='(공백)·중간 키(Database=…)가 끼면 미탐 — 기존 결함이라 plan Deferred에 등록했고,
    #   여기서는 패턴이 실제로 잡는 유효 형태로 차단 경로를 실증한다.
    # 키 이름과 '='를 반드시 분리해 조립한다 — 한 리터럴에 붙여 두면 이 러너 파일(과 그 주석!)
    #   자체가 자사 커밋 게이트에 차단된다(실측으로 두 번 걸렸다).
    $dbConn = 'Server' + '=' + 'prod-sql' + ';' + 'Pwd' + '=' + 'Zq7#mK21' + ';'
    Set-Content db.config $dbConn; git add db.config
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: DB 연결 문자열 커밋 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (e) 저신뢰(비인용 자격증명 쌍) → 경고만. 차단 범위가 넓어지면 여기서 잡힌다.
    Push-Location $wcsB
    git rm -q --cached db.config; Remove-Item db.config -Force
    Set-Content notes.md ('계정: ' + 'ad' + 'min' + ' / ' + 'Zq7' + '#mK21'); git add notes.md
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 비인용 쌍은 경고만(exit 0)" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # (e2) IP 주소만(저신뢰) → 경고만. 오차단 0의 핵심 회귀 감시 — 차단 범위가 IP까지 넓어지면
    #      문서·설정에 IP를 적는 모든 정상 커밋이 막힌다.
    Push-Location $wcsB
    git rm -q --cached notes.md; Remove-Item notes.md -Force
    Set-Content hosts.md ('배포 서버 ' + '203.0' + '.113.5' + ' 접속'); git add hosts.md
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: IP 주소만은 경고만(exit 0, 오차단 0)" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # (f) 시크릿 제거 후 재커밋 → 통과. 차단이 막다른 골목이 아님을 실증한다.
    Push-Location $wcsB
    git rm -q --cached hosts.md; Remove-Item hosts.md -Force
    'clean=1' | Set-Content ok.txt; git add ok.txt
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 시크릿 제거 후 재커밋 통과(회복 가능)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [v1.119.0 F-7 B1] 선행 스테이징 경로 (untracked + 'git add' 한 호출) ----
    # PreToolUse는 명령 실행 '전'에 돈다 — add가 아직 안 돌았으므로 인덱스는 비어 있고 untracked는
    #   git diff HEAD에도 없다. 사고의 실제 경로(신규 프로젝트의 새 README)이자 자율 루프의 표준
    #   커밋 형태(`git add -A && git commit`)라, 여기서 안 잡히면 게이트 전체가 무의미하다.
    $wcsC = Join-Path $work 'wcsuntracked'; New-Item -ItemType Directory $wcsC -Force | Out-Null
    Push-Location $wcsC
    git init -q; git config user.email t@t; git config user.name t
    'v=1' | Set-Content seed.txt; git add .; git commit -qm init
    Set-Content README.md $credLine    # untracked 신규 파일 (스테이징 안 함)
    Pop-Location

    # (h) untracked + 'git add -A && git commit' 한 호출 → 차단
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add -A && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: untracked + 'add -A && commit' 차단(exit 2, F-7 B1)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (i) untracked + 'git add <파일> && git commit' → 차단 (경로 나열 형태)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add README.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: untracked + 'add <파일> && commit' 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (j) 'git add'만 있고 commit 없음 → 무검사 통과 (기존 fast-path 유지)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add -A' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 'git add'만(commit 없음) 무검사 통과" -R $r -ExpectExit 0 -ExpectSilent $true

    # (j2) 'git add <디렉터리>' — 적대적 우회가 아니라 일상 형태다(`git add src/`). 파일이 아니라서
    #      스킵되면 디렉터리 한 단어로 게이트가 뚫린다(F-7 2회차 M1).
    Push-Location $wcsC; New-Item -ItemType Directory -Path 'docs' -Force | Out-Null; Set-Content 'docs/guide.md' $credLine; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add docs/ && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 'add <디렉터리>/ && commit' 차단(exit 2, F-7 M1)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (j3) 'git add <글롭>' — 파일로 존재하지 않는 인자라 git에게 전개를 맡겨야 한다
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add docs/*.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 'add <글롭> && commit' 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    Push-Location $wcsC; Remove-Item 'docs' -Recurse -Force; Pop-Location

    # (k) 시크릿 없는 신규 파일 + 'add -A && commit' → 통과 (오차단 0 — 정상 신규 커밋을 막지 않는다)
    Push-Location $wcsC; Remove-Item README.md -Force; 'hello world' | Set-Content notes.md; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add -A && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 시크릿 없는 신규 파일 'add -A && commit' 통과(오차단 0)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [v1.136.0] 경로 나열 Leaf 분기의 추적 인지 (T1 그물) ----
    # HEAD에 고신뢰 픽스처가 '이미' 커밋된 상태가 전제라 기존 repo($wcs·$wcsB·$wcsC — 케이스 순서
    #   의존 공유)와 얽히지 않게 전용 repo를 쓴다(§13 SC 픽스처 분리와 동일 원칙).
    $wcsD = Join-Path $work 'wcstracked'; New-Item -ItemType Directory $wcsD -Force | Out-Null
    Push-Location $wcsD
    git init -q; git config user.email t@t; git config user.name t
    Set-Content fixtures.md $credLine          # 이력 기존 내용 — 재신고 오탐의 원천이던 형태
    'ignored.txt' | Set-Content .gitignore
    git add .; git commit -qm init
    Pop-Location

    # (n1) 추적 파일 + HEAD 픽스처 + 무해 추가 라인 → 무차단 (핵심 델타 — 이력 기존 내용 재신고 제거)
    Push-Location $wcsD; git checkout -q -- .; Add-Content fixtures.md '무해한 안내 라인 추가'; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsD; tool_input = @{ command = 'git add fixtures.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 추적 파일 HEAD 픽스처 + 무해 추가 라인 무차단(n1, v1.136.0)" -R $r -ExpectExit 0 -ExpectSilent $true

    # (n2) 추적 파일 + 추가 라인에 자격증명 쌍 → 차단 유지 (신규 유입 보호 그물)
    Push-Location $wcsD; git checkout -q -- .; Add-Content fixtures.md ('신규 유입: ' + $credLine); Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsD; tool_input = @{ command = 'git add fixtures.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 추적 파일 추가 라인 자격증명 차단(n2, exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (n3) ignored 파일 강제 add + 자격증명 → 차단 유지 (D1 (a) 근거 — untracked 전체 스캔 보존)
    Push-Location $wcsD; git checkout -q -- .; Set-Content ignored.txt $credLine; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsD; tool_input = @{ command = 'git add -f ignored.txt && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: ignored 강제 add 자격증명 차단(n3, exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (g) 디스패처 경유도 동일 차단 — lib 함수 공유라 두 경로가 갈리면 안 된다(D3).
    Push-Location $wcsB; Set-Content README.md $credLine; git add README.md; Pop-Location
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 디스패처 경유 자격증명 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    Push-Location $wcsB; git rm -q --cached README.md; Remove-Item README.md -Force; Pop-Location

    # ---- [v1.99.0 T6] 디스패처 동등성 + 디스패처 고유 분기 (git repo 필요) ----
    # 현재 $wcs 상태: app.js에 시크릿(-am 자동스테이징 대상), ok.txt 미스테이징. 명시 스테이징 시크릿을 다시 심는다.
    Push-Location $wcs; Set-Content secret2.js $fakeApi; git add secret2.js; Pop-Location
    # (a) commit-secrets 양성 → 디스패처 경유도 경고 유지
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' $wcsJson
    Assert-Case -Name "dispatch=commit-secrets: staged 시크릿 경고" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'
    # (b) 디스패처 고유: block(rtc 미완료) + warn(commit-secrets) 동시 → block 우선 exit 2, warn 경고는 버림(D4)
    "# plan`n- [ ] T7. 미완료" | Set-Content (Join-Path $wcs 'plan.md')
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m "T7: 완료"' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "dispatch: block(rtc)+warn(secret) 동시 → exit 2 차단 우선" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    if (($r.out -match 'COMMIT SECRET')) { $script:results.Add(@{ ok = $false; line = "[FAIL] dispatch: block 시 warn 경고 버림(D4) — COMMIT SECRET가 출력됨" }) }
    else { $script:results.Add(@{ ok = $true; line = "[PASS] dispatch: block 시 warn 경고 버림(D4 트레이드오프)" }) }
    Remove-Item (Join-Path $wcs 'plan.md') -Force -ErrorAction SilentlyContinue
    # (c) 디스패처 고유: warn 2개(external push + commit secret) 병합 → exit 0 + 두 keyword 모두
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m x && git push origin main' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "dispatch: warn 2개 병합 (external) — exit 0" -R $r -ExpectExit 0 -ExpectContains 'EXTERNAL OP'
    if (($r.out -match 'COMMIT SECRET') -and ($r.out -match 'EXTERNAL OP')) { $script:results.Add(@{ ok = $true; line = "[PASS] dispatch: warn 2개(secret+external) additionalContext 병합" }) }
    else { $script:results.Add(@{ ok = $false; line = "[FAIL] dispatch: warn 병합 누락 | 출력: $(($r.out -split "`r?`n" | Select-Object -First 2) -join ' / ')" }) }
} else {
    Write-Host "[SKIP] warn-commit-secrets 시나리오 (git 없음)"
}
}   # ---- §9 게이트 끝 (warn-commit-secrets·pre-bash-dispatch) ----

# =====================================================================
# 10) warn-version-drift 시나리오 (SessionStart — 설치본↔레포 버전 비교)
# =====================================================================
# 설치본은 $env:CLAUDE_PLUGIN_ROOT 픽스처로, 레포는 마커 2종(plugins/pjc/.claude-plugin/plugin.json +
# .claude-plugin/marketplace.json) 픽스처로 위장한다. 실행 후 CLAUDE_PLUGIN_ROOT는 원복(다른 시나리오 오염 방지).
if (Test-HookSelected @('warn-version-drift')) {
$vdRealRoot = $env:CLAUDE_PLUGIN_ROOT
try {
    # 가짜 설치본 (v1.0.0)
    $vdInst = Join-Path $work 'vd-installed'
    New-Item -ItemType Directory (Join-Path $vdInst '.claude-plugin') -Force | Out-Null
    '{ "name": "pjc", "version": "1.0.0" }' | Set-Content (Join-Path $vdInst '.claude-plugin/plugin.json')
    $env:CLAUDE_PLUGIN_ROOT = $vdInst

    # 가짜 하네스 레포 (v9.9.9 — 불일치)
    $vdRepo = Join-Path $work 'vd-repo'
    New-Item -ItemType Directory (Join-Path $vdRepo 'plugins/pjc/.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $vdRepo '.claude-plugin') -Force | Out-Null
    '{ "name": "pjc", "version": "9.9.9" }' | Set-Content (Join-Path $vdRepo 'plugins/pjc/.claude-plugin/plugin.json')
    '{ "name": "pjc-harness" }' | Set-Content (Join-Path $vdRepo '.claude-plugin/marketplace.json')

    $vdJson = @{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $vdRepo } | ConvertTo-Json -Compress
    # 1) 불일치 → 드리프트 경고 (exit 0 — 비차단)
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: 설치본≠레포 경고" -R $r -ExpectExit 0 -ExpectContains '버전 드리프트'

    # 2) 일치 → 무출력
    '{ "name": "pjc", "version": "1.0.0" }' | Set-Content (Join-Path $vdRepo 'plugins/pjc/.claude-plugin/plugin.json')
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: 버전 일치 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

    # 3) 비레포 cwd(마커 없음) → 무출력
    $r = Invoke-Hook 'warn-version-drift.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $work } | ConvertTo-Json -Compress)
    Assert-Case -Name "version-drift: 비레포 cwd 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

    # 4) CLAUDE_PLUGIN_ROOT 부재 → 무출력 (fail-open)
    $env:CLAUDE_PLUGIN_ROOT = $null
    '{ "name": "pjc", "version": "9.9.9" }' | Set-Content (Join-Path $vdRepo 'plugins/pjc/.claude-plugin/plugin.json')
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: CLAUDE_PLUGIN_ROOT 부재 무출력(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true
} finally {
    $env:CLAUDE_PLUGIN_ROOT = $vdRealRoot
}
}   # ---- §10 게이트 끝 (warn-version-drift) ----

# ---- [T1] protect-harness: 신규 hook(warn-version-drift) 설치본 개조 차단 (이름 집합 합류 실증) ----
# ($vdCache는 top-level 공유 정의 — §11(d)도 사용)
if (Test-HookSelected @('protect-harness')) {
$vdTarget = (Join-Path $vdCache 'warn-version-drift.ps1') -replace '\\', '/'
$r = Invoke-Hook 'protect-harness.ps1' (@{ tool_name = 'Write'; tool_input = @{ file_path = $vdTarget; content = 'x' } } | ConvertTo-Json -Compress)
Assert-Case -Name "protect-harness: 설치본 warn-version-drift 개조 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
# session-context(v1.112.0 신설)도 동일 실증 — 이름 집합 합류 확인
$scTarget = (Join-Path $vdCache 'session-context.ps1') -replace '\\', '/'
$r = Invoke-Hook 'protect-harness.ps1' (@{ tool_name = 'Write'; tool_input = @{ file_path = $scTarget; content = 'x' } } | ConvertTo-Json -Compress)
Assert-Case -Name "protect-harness: 설치본 session-context 개조 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
}   # ---- 게이트 끝 (protect-harness) ----

# =====================================================================
# 11) hook 이벤트 로깅 (hook-event-log.ps1 — 적재·격리·시크릿 fail-closed)
# =====================================================================
# 로그는 격리 홈($iso)의 .claude/.state/hook-events/{YYYY-MM}.jsonl에 쓰인다.
# 게이트 태그 4개: 이벤트 로깅 검증이 block-destructive(차단 적재)·pre-bash-dispatch(warn 적재)·
# protect-harness(헬퍼 개조 차단)를 실행 수단으로 쓴다 — 그 hook들의 필터에서도 커버 유지.
if (Test-HookSelected @('hook-event-log', 'block-destructive', 'pre-bash-dispatch', 'protect-harness')) {

# (a) 쓰기 불가 격리 — 로그 경로가 막혀도 차단 동작은 정상 (별도 격리 홈에서 hook-events 자리를 파일로 선점).
#     ※ (b)보다 먼저: $iso에는 앞 섹션들의 경고 로깅으로 이미 디렉터리가 생겨 있을 수 있어 새 홈을 쓴다.
$iso2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-lockedlog-" + $suffix)
New-Item -ItemType Directory -Path (Join-Path $iso2 '.claude/.state') -Force | Out-Null
'lock' | Set-Content (Join-Path $iso2 '.claude/.state/hook-events')   # 디렉터리 자리에 파일 — 로깅만 실패 유도
$env:USERPROFILE = $iso2
$r = Invoke-Hook 'block-destructive.ps1' (@{ tool_name = 'Bash'; tool_input = @{ command = 'rm -rf /' } } | ConvertTo-Json -Compress)
Assert-Case -Name "event-log: 로그 경로 쓰기 불가여도 차단 정상(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$env:USERPROFILE = $iso
Remove-Item -Recurse -Force $iso2 -ErrorAction SilentlyContinue

# (b) 차단 이벤트 적재 실증 — block-destructive 차단 1건 후 로그 라인 존재.
$r = Invoke-Hook 'block-destructive.ps1' (@{ tool_name = 'Bash'; tool_input = @{ command = 'rm -rf /' } } | ConvertTo-Json -Compress)
$evDir = Join-Path $iso '.claude/.state/hook-events'
$evText = ''
try { $evText = (Get-ChildItem -LiteralPath $evDir -Filter '*.jsonl' -ErrorAction Stop | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" } catch {}
if (($r.code -eq 2) -and ($evText -match '"hook":"block-destructive"') -and ($evText -match '"decision":"block"')) {
    $script:results.Add(@{ ok = $true; line = "[PASS] event-log: 차단 이벤트 jsonl 적재" })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] event-log: 차단 이벤트 적재 누락 (exit=$($r.code), 로그검색 실패)" })
}

# (c) 시크릿 fail-closed — warn 명령에 시크릿 값 포함 시 로그에 평문 부재 (cmd 필드 생략).
$fakeKey = 'ZXCV9876QWER5432'   # 가짜 값 (러너 자체 오탐 방지용 분리 기재 불필요 — 패턴 좌변 없음)
$secCmd = 'git push origin main && export api_key="' + $fakeKey + '"'
$r = Invoke-Hook 'pre-bash-dispatch.ps1' (@{ tool_name = 'Bash'; tool_input = @{ command = $secCmd } } | ConvertTo-Json -Compress)
$evText2 = ''
try { $evText2 = (Get-ChildItem -LiteralPath $evDir -Filter '*.jsonl' -ErrorAction Stop | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" } catch {}
if (($r.code -eq 0) -and ($evText2 -match '"hook":"warn-external-ops"') -and ($evText2 -notmatch [regex]::Escape($fakeKey))) {
    $script:results.Add(@{ ok = $true; line = "[PASS] event-log: 시크릿 포함 명령 fail-closed (평문 미기록)" })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] event-log: 시크릿 fail-closed 위반 또는 warn 미적재 (exit=$($r.code))" })
}

# (d) protect-harness: 설치본 hook-event-log(헬퍼) 개조 차단 (이름 집합 합류 실증)
$elTarget = (Join-Path $vdCache 'hook-event-log.ps1') -replace '\\', '/'
$r = Invoke-Hook 'protect-harness.ps1' (@{ tool_name = 'Write'; tool_input = @{ file_path = $elTarget; content = 'x' } } | ConvertTo-Json -Compress)
Assert-Case -Name "protect-harness: 설치본 hook-event-log 개조 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
}   # ---- §11 게이트 끝 (hook-event-log 외) ----

# =====================================================================
# 12) report-hook-events.ps1 스모크 (이벤트 로그 집계 리포트 — hook 아님, 직접 실행)
# =====================================================================
# 리포트는 stdin이 아니라 USERPROFILE 기반 로그 디렉터리를 읽으므로 Invoke-Hook을 쓰지 않고
# 전용 격리 홈에 통제된 fixture jsonl을 심어 결정적으로 검증한다($iso는 앞 섹션들의 실제
# 이벤트로 오염돼 건수 단정 불가).
if (Test-HookSelected @('hook-event-log')) {
    $repScript = Join-Path $scriptsDir 'report-hook-events.ps1'

    # (a) fixture 3건(block 1 + warn 2) → 집계 키워드·건수 확인
    $isoR = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-report-" + $suffix)
    $repDir = Join-Path $isoR '.claude/.state/hook-events'
    New-Item -ItemType Directory -Path $repDir -Force | Out-Null
    @(
        '{"ts":"2026-07-01T10:00:00+09:00","hook":"block-destructive","decision":"block","rule":"rm -rf 루트","cmd":"rm -rf /"}',
        '{"ts":"2026-07-02T11:00:00+09:00","hook":"warn-external-ops","decision":"warn","rule":"git push"}',
        '{"ts":"2026-07-03T12:00:00+09:00","hook":"warn-external-ops","decision":"warn","rule":"git push"}'
    ) | Set-Content -Encoding UTF8 (Join-Path $repDir '2026-07.jsonl')
    $env:USERPROFILE = $isoR
    $outRep = & pwsh -NoProfile -ExecutionPolicy Bypass -File $repScript 2>&1
    $rRep = @{ code = $LASTEXITCODE; out = (($outRep | Out-String)).Trim() }
    $env:USERPROFILE = $iso
    Assert-Case -Name "report-hook-events: fixture 3건 총계 집계" -R $rRep -ExpectExit 0 -ExpectContains '총 이벤트: 3건 (차단 1 · 경고 2)'
    Assert-Case -Name "report-hook-events: hook×판정·규칙 집계 표기" -R $rRep -ExpectExit 0 -ExpectContains 'warn-external-ops'
    Remove-Item -Recurse -Force $isoR -ErrorAction SilentlyContinue

    # (b) 로그 없는 빈 홈 → 안내 + exit 0 (오류로 죽지 않음)
    $isoR2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-report-empty-" + $suffix)
    New-Item -ItemType Directory -Path $isoR2 -Force | Out-Null
    $env:USERPROFILE = $isoR2
    $outRep2 = & pwsh -NoProfile -ExecutionPolicy Bypass -File $repScript 2>&1
    $rRep2 = @{ code = $LASTEXITCODE; out = (($outRep2 | Out-String)).Trim() }
    $env:USERPROFILE = $iso
    Assert-Case -Name "report-hook-events: 로그 없음 안내 + exit 0" -R $rRep2 -ExpectExit 0 -ExpectContains '적재된 이벤트 없음'
    Remove-Item -Recurse -Force $isoR2 -ErrorAction SilentlyContinue
}   # ---- §12 게이트 끝 (hook-event-log) ----

# =====================================================================
# 13) session-context 시나리오 (SessionStart — plan/notes 상태 요약 주입, v1.112.0)
# =====================================================================
if (Test-HookSelected @('session-context')) {
    # 픽스처: plan.md(T 3개 중 미완료 2 — [x]/[/]/[ ] 혼합) + notes.md(최근 항목 날짜)
    $scProj = Join-Path $work 'sc-proj'
    New-Item -ItemType Directory $scProj -Force | Out-Null
    @(
        '# Plan: test',
        '## Tasks',
        '- [x] T1: done (Type A)',
        '- [/] T2: in progress (Type B)',
        '- [ ] T3: todo (Type C)'
    ) | Set-Content -Encoding UTF8 (Join-Path $scProj 'plan.md')
    @('## 최근 변경', '- 2026-07-01: 테스트 항목') | Set-Content -Encoding UTF8 (Join-Path $scProj 'notes.md')

    # SC1: startup → plan 미완료 카운트 + notes 날짜 주입 (같은 실행 결과로 2개 확인)
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: plan 미완료 카운트 주입 (SC1)" -R $r -ExpectExit 0 -ExpectContains '미완료 2'
    Assert-Case -Name "session-context: notes 최근 항목 날짜 주입 (SC1b)" -R $r -ExpectExit 0 -ExpectContains '2026-07-01'

    # SC2: compact → 재확인 리마인더 추가 주입
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 재확인 리마인더 (SC2)" -R $r -ExpectExit 0 -ExpectContains '요약 직후'

    # SC3: plan/notes 없는 빈 폴더 → 무출력 (비 pjc 프로젝트 노이즈 방지)
    $scEmpty = Join-Path $work 'sc-empty'; New-Item -ItemType Directory $scEmpty -Force | Out-Null
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: plan/notes 없음 무출력 (SC3)" -R $r -ExpectExit 0 -ExpectSilent $true

    # SC4: 루트 plan 없음 → docs/plans/ 폴백 (체크박스 없는 deferred.md는 건너뜀 실증 — 더 최신이어도 비인식)
    $scDocs = Join-Path $work 'sc-docs'
    New-Item -ItemType Directory (Join-Path $scDocs 'docs/plans') -Force | Out-Null
    @('- [x] T1: a', '- [ ] T2: b') | Set-Content -Encoding UTF8 (Join-Path $scDocs 'docs/plans/2026-07-01-feature.md')
    '- [2026-07-10] deferred 항목 (T 체크박스 아님)' | Set-Content -Encoding UTF8 (Join-Path $scDocs 'docs/plans/deferred.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDocs } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: docs/plans 폴백 인식 (SC4)" -R $r -ExpectExit 0 -ExpectContains '2026-07-01-feature.md'

    # SC5: task 체크박스 없는 plan.md(비 pjc 형식) → 카운트 오보 대신 존재 강등 문구
    $scNoT = Join-Path $work 'sc-not'; New-Item -ItemType Directory $scNoT -Force | Out-Null
    '# 자유 형식 계획 문서' | Set-Content -Encoding UTF8 (Join-Path $scNoT 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scNoT } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비 pjc plan 존재 강등 문구 (SC5)" -R $r -ExpectExit 0 -ExpectContains '존재'

    # SC6: 빈 stdin → 무출력 exit 0 (fail-open)
    $r = Invoke-Hook 'session-context.ps1' ''
    Assert-Case -Name "session-context: 빈 stdin 무출력 fail-open (SC6)" -R $r -ExpectExit 0 -ExpectSilent $true

    # SC7~SC9: AGENTS.md 전문 주입 (v1.135.0) — 전용 픽스처(기존 $scProj 오염 방지, 4-C)
    $scAgents = Join-Path $work 'sc-agents'; New-Item -ItemType Directory $scAgents -Force | Out-Null
    @(
        '---', 'type: x', '---',
        '# Agent Guide',
        'SC_AGENTS_UNIQUE_MARKER 이 문자열은 AGENTS.md 전문에만 있다',
        '## DO NOT', '금지 항목'
    ) | Set-Content -Encoding UTF8 (Join-Path $scAgents 'AGENTS.md')
    @('# Plan', '- [ ] T1: todo') | Set-Content -Encoding UTF8 (Join-Path $scAgents 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scAgents } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: AGENTS.md 전문 주입 (SC7)" -R $r -ExpectExit 0 -ExpectContains 'SC_AGENTS_UNIQUE_MARKER'
    Assert-Case -Name "session-context: AGENTS.md 근거 요구 문구 (SC8)" -R $r -ExpectExit 0 -ExpectContains '단정'

    # SC9: 16KB 초과 AGENTS.md → 전문 대신 섹션 목차 폴백 (헤딩 포함, 바이트로 상한 초과)
    $scBig = Join-Path $work 'sc-agents-big'; New-Item -ItemType Directory $scBig -Force | Out-Null
    (@('---', 'type: x', '---', '# Big Guide', '## Section One') + (1..2500 | ForEach-Object { '가나다라마 반복 채우기 줄' }) + @('### Sub Section', '끝')) | Set-Content -Encoding UTF8 (Join-Path $scBig 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scBig } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 16KB 초과 AGENTS.md 목차 폴백 (SC9)" -R $r -ExpectExit 0 -ExpectContains '섹션:'

    # SC10: AGENTS.md 없는 기존 픽스처($scProj: plan+notes만)는 AGENTS 문자열 무오염 — T1 acceptance ⓑ의 영구 그물.
    #   SC3(완전 빈 폴더)은 plan/notes는 있고 AGENTS만 없는 이 경로를 고정 못 하므로 별도 케이스로 둔다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: AGENTS.md 없는 픽스처 무오염 (SC10)" -R $r -ExpectExit 0 -ExpectContains '미완료 2' -ExpectNotContains 'AGENTS'

    # SC11~SC13: AGENTS.md 주입 견고성 가드 (v1.135.0 리뷰 후속 — 비정상 입력에서 깨진/오도 컨텍스트 주입 방지)
    # SC11: UTF-8이 아닌 인코딩(CP949 등) → 깨진 전문 대신 디코딩 실패 안내 1줄 (U+FFFD 검출 가드)
    $scMoji = Join-Path $work 'sc-agents-moji'; New-Item -ItemType Directory $scMoji -Force | Out-Null
    # 0xB0A1 = CP949 '가' — UTF-8로 디코딩하면 U+FFFD가 된다 (CodePagesEncodingProvider 없이 재현 가능한 원시 바이트)
    [System.IO.File]::WriteAllBytes((Join-Path $scMoji 'AGENTS.md'), [byte[]](0x23, 0x20, 0xB0, 0xA1, 0xB0, 0xA1, 0x0A))
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scMoji } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비UTF-8 AGENTS.md 디코딩 실패 안내 (SC11)" -R $r -ExpectExit 0 -ExpectContains '디코딩 실패'

    # SC12: 목차 폴백 상한(1MB) 초과 → 읽기·목차 스캔 생략, Read 지시만 (타임아웃·메모리 방어)
    $scHuge = Join-Path $work 'sc-agents-huge'; New-Item -ItemType Directory $scHuge -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $scHuge 'AGENTS.md'), "# Huge Guide`n" + ('a' * 1100000))
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scHuge } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 1MB 초과 AGENTS.md 목차 생략 Read 지시 (SC12)" -R $r -ExpectExit 0 -ExpectContains '전문 미주입' -ExpectNotContains '섹션:'

    # SC13: 목차 폴백이 0열 코드 펜스 안의 '# 주석'을 섹션으로 오인하지 않음 (펜스 제거 후 헤딩 추출)
    $scFence = Join-Path $work 'sc-agents-fence'; New-Item -ItemType Directory $scFence -Force | Out-Null
    (@('# Real Guide', '## Real Section', '```sh', '# FENCE_MARKER not a heading', 'echo hi', '```') + (1..2500 | ForEach-Object { '가나다라마 반복 채우기 줄' })) | Set-Content -Encoding UTF8 (Join-Path $scFence 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scFence } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 목차 폴백 코드 펜스 내 # 비오인 (SC13)" -R $r -ExpectExit 0 -ExpectContains '섹션:' -ExpectNotContains 'FENCE_MARKER'

    # SC14~SC17: compact 재읽기 경로 지정 — 압축 후 스킬 뒷부분(Phase 절차·Halt 조건)이 유실되고
    #   재invoke로는 복구되지 않으므로, 미완료 task가 있을 때만 Read 대상 3종을 못박는다.
    #   3경로 리터럴을 골든이 고정한다 — 문구가 흔들려도 "무엇을 읽어야 하는지"는 남아야 한다.
    # SC14: compact + 미완료 task 있는 plan → 고정 3경로 전부 주입
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 재읽기 경로 SKILL.md (SC14)" -R $r -ExpectExit 0 -ExpectContains 'implement-task/SKILL.md'
    Assert-Case -Name "session-context: compact 재읽기 경로 halt-conditions (SC14b)" -R $r -ExpectExit 0 -ExpectContains 'references/halt-conditions.md'
    Assert-Case -Name "session-context: compact 재읽기 경로 recovery (SC14c)" -R $r -ExpectExit 0 -ExpectContains 'references/recovery.md'

    # SC15: compact + plan 없음 → 기존 일반 리마인더만, 경로 지정 없음 (무회귀)
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact plan 없음 경로 미지정 (SC15)" -R $r -ExpectExit 0 -ExpectContains '요약 직후' -ExpectNotContains 'halt-conditions'

    # SC16: compact + 전 task 완료 → 경로 지정 없음. 재개할 루프가 없으면 재읽기를 유도하지 않는다.
    $scDone = Join-Path $work 'sc-done'; New-Item -ItemType Directory $scDone -Force | Out-Null
    @('# Plan', '- [x] T1: done', '- [x] T2: done') | Set-Content -Encoding UTF8 (Join-Path $scDone 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scDone } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 전 task 완료 경로 미지정 (SC16)" -R $r -ExpectExit 0 -ExpectContains '전부 완료' -ExpectNotContains 'halt-conditions'

    # SC17: compact + 존재하지 않는 cwd → 기존 compact 문구는 그대로 나온다.
    #   이 라인이 cwd 검사 블록 밖에 있어야 성립하므로, 블록 안으로 옮기는 회귀를 골든이 막는다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = (Join-Path $work 'sc-nonexistent') } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 무효 cwd 기본 문구 유지 (SC17)" -R $r -ExpectExit 0 -ExpectContains '요약 직후'

    # SC18~SC23: 위키 vault 설정 상태 주입 (v1.146.0) — 절차 K의 "미설정" 오판정을 기계로 차단.
    #   전용 격리 홈에 llm-wiki-config.json을 심는다($iso에는 config가 없어 미설정 상태이며 SC20이 그것을 쓴다).
    #   무회귀 1건(SC20) + 델타 3건(SC21 과다 주입·SC22 과억제·SC23 리마인더 오신호) 구성 —
    #   통과만 확인하는 케이스는 게이팅을 고정하지 못한다.
    $isoV = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-vault-" + $suffix)
    $isoVault = Join-Path $isoV 'my-wiki'
    New-Item -ItemType Directory -Path (Join-Path $isoV '.claude') -Force | Out-Null
    New-Item -ItemType Directory -Path $isoVault -Force | Out-Null
    (@{ vault_path = ($isoVault -replace '\\', '/') } | ConvertTo-Json) | Set-Content -Encoding UTF8 (Join-Path $isoV '.claude/llm-wiki-config.json')

    # SC18: 설정+실재 → 경로와 "단정 금지" 문구가 함께 주입된다 (문구 리터럴 고정)
    $env:USERPROFILE = $isoV
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: vault 설정됨 상태 주입 (SC18)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨'
    Assert-Case -Name "session-context: vault 단정 금지 문구 (SC18b)" -R $r -ExpectExit 0 -ExpectContains '단정하지 마세요'

    # SC21 (델타): 설정+실재인데 비 pjc cwd(plan/notes/AGENTS 전무) → 게이팅으로 미주입.
    #   vault는 cwd와 무관한 사용자 홈 자원이라, 게이팅이 없으면 위키를 쓰는 사용자의 모든 세션에 라인이 붙는다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비 pjc cwd는 vault 라인 미주입 (SC21)" -R $r -ExpectExit 0 -ExpectSilent $true

    # SC23 (델타): compact + 빈 cwd → 리마인더는 나오되 vault 라인은 미주입.
    #   리마인더는 cwd 블록 밖에서 append되므로 게이팅 신호가 아니다 — $lines.Count -gt 0 판정을 이 케이스가 검출한다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 리마인더는 vault 게이팅 신호 아님 (SC23)" -R $r -ExpectExit 0 -ExpectContains '요약 직후' -ExpectNotContains '위키 vault'

    # SC22 (델타): AGENTS.md만 있고 plan/notes 없는 cwd → vault 라인이 주입되고 AGENTS 라인보다 **앞**에 온다.
    #   ① 게이팅을 AGENTS 진입 전 시점에 판정하면 이 케이스가 억제된다(과억제 검출).
    #   ② 순서 단정은 Assert-Case로 불가하다 — ExpectContains가 [regex]::Escape를 거쳐 전후 관계를 비교할 수단이 없으므로
    #      IndexOf 비교 후 결과를 직접 push한다(§11 (b) 패턴과 동일).
    #   기존 AGENTS 단독 픽스처($scBig 등)는 16KB 초과·비UTF-8이라 전문이 아니라 폴백을 출력하므로 소형 픽스처를 따로 둔다.
    $scVOnly = Join-Path $work 'sc-agents-only'; New-Item -ItemType Directory $scVOnly -Force | Out-Null
    @('# Guide', 'SC_VAULT_ORDER_MARKER 전문 주입 대상') | Set-Content -Encoding UTF8 (Join-Path $scVOnly 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scVOnly } | ConvertTo-Json -Compress)
    $iVault  = $r.out.IndexOf('위키 vault: 설정됨')
    $iAgents = $r.out.IndexOf('SC_VAULT_ORDER_MARKER')
    if (($r.code -eq 0) -and ($iVault -ge 0) -and ($iAgents -gt $iVault)) {
        $script:results.Add(@{ ok = $true; line = "[PASS] session-context: AGENTS 단독 cwd vault 주입 + AGENTS보다 앞 (SC22)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] session-context: SC22 주입·순서 위반 (exit=$($r.code), vault=$iVault, agents=$iAgents)" })
    }

    # SC19: 설정됐으나 폴더 부재(이동·삭제) → 부재 문구 주입 (경로 재확인 신호)
    $isoV2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-vault-gone-" + $suffix)
    New-Item -ItemType Directory -Path (Join-Path $isoV2 '.claude') -Force | Out-Null
    (@{ vault_path = ((Join-Path $isoV2 'moved-away') -replace '\\', '/') } | ConvertTo-Json) | Set-Content -Encoding UTF8 (Join-Path $isoV2 '.claude/llm-wiki-config.json')
    $env:USERPROFILE = $isoV2
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: vault 설정 경로 부재 주입 (SC19)" -R $r -ExpectExit 0 -ExpectContains '설정 경로 부재'

    # SC20 (무회귀): config 없는 홈 → vault 라인 미주입. 미설정은 무출력이 설계다(노이즈 방지).
    $env:USERPROFILE = $iso
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 미설정 홈은 vault 라인 미주입 (SC20)" -R $r -ExpectExit 0 -ExpectContains '미완료 2' -ExpectNotContains '위키 vault'
    Remove-Item -Recurse -Force $isoV, $isoV2 -ErrorAction SilentlyContinue
}   # ---- §13 게이트 끝 (session-context) ----

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
