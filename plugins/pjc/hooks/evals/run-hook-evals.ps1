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
        'warn-commit-secrets', 'pre-bash-dispatch', 'warn-version-drift', 'hook-event-log'
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

function New-WriteJson([string]$cwd, [string]$file, [string]$tool = 'Write', [hashtable]$extra = @{}) {
    # §2 require-plan·§2b protect-harness·§6 post-write 등 다수 섹션 공용
    $ti = @{ file_path = $file; content = 'class A {}' } + $extra
    return (@{ tool_name = $tool; cwd = $cwd; tool_input = $ti } | ConvertTo-Json -Compress)
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
}   # ---- §2 게이트 끝 (require-plan-for-write) ----

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
