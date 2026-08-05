# run-hook-evals.ps1 — pjc hook 골든 회귀 러너 (lint evals의 hook 판)
#
# 사용법: pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1
#   부분 실행(개발 반복 전용): ... run-hook-evals.ps1 -Filter block-destructive,require-plan-for-write
#   순차 실행(등가 대조·폴백):  ... run-hook-evals.ps1 -Sequential
#   중단 후 이어하기:           ... run-hook-evals.ps1 -Resume
#
# 무엇을: scripts/*.ps1 hook을 격리 USERPROFILE·중립 cwd에서 stdin JSON으로 실행해
#   exit code·출력 키워드를 대조한다. 케이스 정본은 두 곳 —
#   ① hook-cases.json: 무상태(command 기반) 케이스 (block-destructive·warn-external-ops)
#   ② scenarios/*.ps1 13개: 상태 필요(plan 폴더·git repo·AGENTS.md 마커·post-write 파일)
#   공용 헬퍼·격리 구성은 eval-common.ps1이며, 이 파일과 run-scenario.ps1이 함께 dot-source한다.
#
# 실행 구조(v1.159.0): 기본은 **시나리오 그룹 단위 병렬**이다 — 그룹마다 자식 pwsh를 띄워
#   각자의 격리 홈에서 돌리고 판정 JSON을 취합한다. 케이스마다 자식 pwsh를 새로 띄우는 구조상
#   비용의 절반 이상이 프로세스 기동이라(빈 pwsh 콜드스타트 약 1.0초 / hook 1회 약 1.8초),
#   시나리오를 동시에 돌리면 wall-clock이 최대 그룹 하나의 시간으로 수렴한다.
#   케이스 단위로 쪼개지 않는 이유는 시나리오 내부의 픽스처 생성 순서가 깨지기 때문이다.
#
# -Sequential 계약: 병렬 디스패치를 끄고 **한 프로세스에서 13 시나리오를 종전대로 dot-source**한다.
#   ① 병렬 결과와의 등가 대조 기준(같은 세션에서 두 모드를 연속 측정해야 한다 — 같은 스위트가
#      19분 6초 ↔ 27분 14초로 실측된 만큼 wall-clock 편차가 커서 교차 세션 비교는 근거가 못 된다)
#   ② 병렬 경로에 문제가 생겼을 때의 폴백. 판정 정본으로서의 자격은 두 모드가 동일하다.
#
# -Filter 계약(v1.107.0): hook 기본명(.ps1 유무·대소문자 무관, 쉼표 복수)으로 실행 범위를 좁힌다.
#   구현 중 반복 확인 전용이며 task 검증(V-2 검증 매핑)·Phase F-2 판정에는 사용 금지 — 부분 실행은
#   커버리지가 좁아(섹션 태그는 케이스 단위가 아니라 섹션 단위 — 소량 초과 실행은 허용, 누락은 불허)
#   무인자 전체 실행만 판정 정본이다. 필터 모드는 경고 헤더를 강제 출력하고, 실행 케이스 0이면
#   exit 1로 실패한다(필터 이름 오타가 "전부 통과"로 보이는 거짓 안심 방지).
#
# -Resume 계약: 이전 실행이 남긴 그룹별 판정 파일에 완료 마커(done)가 있으면 그 그룹을 건너뛴다.
#   30분대 실행이 kill되면 재실행이 곧 전량 재소요였기 때문이다(백그라운드 kill로 프로세스가
#   동반 사망한 것이 2회 관측됐다). 완료 마커가 없는 그룹은 판정 파일을 버리고 다시 돌린다 —
#   중간까지의 판정을 재사용하면 그 그룹의 커버리지가 조용히 좁아진다.
#
# pending_fix 규약(red-green): pending_fix=true 케이스는 '수정 전 red(기대 미충족)'가 정상이다 —
#   red면 "PENDING(red 기대대로)"로 exit 0에 포함하고, green이면 stale 마킹이므로 FAIL(마킹 제거 강제).
#   마킹이 없는 케이스가 red면 FAIL(회귀). 해당 수정 task 완료 시 마킹을 제거한다.
#
# 전제: pwsh 7 (개발 레포 전용 러너 — hook 자체의 5.1 폴백과 무관). git 부재 시 evidence 시나리오는 skip.

param(
    # 부분 실행 필터 — hook 기본명 목록 (예: 'block-destructive', 'post-write-checks.ps1'도 허용)
    [string[]]$Filter,
    # 병렬 디스패치를 끄고 한 프로세스에서 순차 실행 (등가 대조 기준 · 폴백)
    [switch]$Sequential,
    # 이전 실행의 완료된 그룹을 건너뛰고 남은 그룹만 실행
    [switch]$Resume,
    # 동시에 띄울 자식 프로세스 상한. 기본 6 — 12 그룹을 한꺼번에 띄우면 CPU·디스크 경합으로
    # 케이스당 시간이 늘어 총 시간이 오히려 나빠질 수 있어 상한을 둔다.
    [int]$MaxParallel = 6,
    # 그룹별 판정 JSON을 둘 디렉터리. 기본은 임시 폴더 하위(실행 간 재사용 = -Resume의 입력).
    [string]$StateDir
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$evalsDirTop = $PSScriptRoot

# ---- 시나리오 그룹 정의 ----
# 이 목록의 순서가 곧 출력 순서다(분리 전 dot-source 순서를 그대로 보존한다 — 케이스 라인이
# 종전과 같은 순서로 나와야 순차·병렬 등가 대조가 형식까지 일치한다).
# 그룹이 둘 이상인 항목은 **같은 격리 홈을 공유해야 하는** 시나리오들이다:
#   protect-harness-installed + hook-event-log — $vdCache 공유 + 후자가 홈의 이벤트 로그 적재를 관찰
$scenarioGroups = @(
    @('stateless'),
    @('require-plan-for-write'),
    @('protect-harness'),
    @('pre-bash-dispatch'),
    @('require-evidence'),
    @('suggest-agents-record'),
    @('post-write-checks'),
    @('require-task-checkbox'),
    @('warn-commit-secrets'),
    @('warn-version-drift'),
    @('protect-harness-installed', 'hook-event-log'),
    @('session-context')
)

Write-Host "== pjc hook 골든 회귀 =="
if ($Filter -and @($Filter).Count) {
    # 단일 문자열 'a,b'도 나눠 표시한다(eval-common의 정규화와 같은 규칙)
    $shown = @($Filter | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Write-Host "⚠ 부분 실행 모드 (-Filter: $($shown -join ', ')) — 개발 반복 전용, task 검증(V-2)·F-2 판정에 사용 금지"
}

# =====================================================================
# 순차 경로 — 종전 구조 그대로 (한 프로세스에서 13 시나리오 dot-source)
# =====================================================================
if ($Sequential) {
    $EvalFilter = $Filter
    . (Join-Path $evalsDirTop 'eval-common.ps1')
    try {
        foreach ($g in $scenarioGroups) {
            foreach ($n in $g) {
                $script:EvalCurrentScenario = $n
                . (Join-Path $evalsDirTop ('scenarios/' + $n + '.ps1'))
            }
        }
    } finally {
        $env:USERPROFILE = $realHome
        Set-Location $env:TEMP
        Remove-Item -Recurse -Force $EvalIso -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $EvalWork -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force (Join-Path ([System.IO.Path]::GetTempPath()) 'pjc-hook-eval-scratch') -ErrorAction SilentlyContinue
    }
    $failCount = 0
    foreach ($res in $results) {
        Write-Host $res.line
        if (-not $res.ok) { $failCount++ }
    }
    $total = $results.Count
    Write-Host ""
    if ($Filter -and $total -eq 0) {
        Write-Host "[FAIL] -Filter 매칭 실행 케이스 0건 — 필터 이름(오타) 또는 환경(git 부재 skip)을 확인하세요."
        exit 1
    }
    if ($Filter) {
        Write-Host "⚠ 부분 실행 결과 (-Filter) — 개발 반복 전용, task 검증(V-2)·F-2 판정에 사용 금지"
    }
    Write-Host "[MODE] 순차 실행 (-Sequential)"
    Write-Host ("결과: {0}/{1} OK (FAIL {2})" -f ($total - $failCount), $total, $failCount)
    exit $(if ($failCount) { 1 } else { 0 })
}

# =====================================================================
# 병렬 경로 — 그룹마다 자식 pwsh, 판정 JSON 취합
# =====================================================================
if (-not $StateDir) {
    $StateDir = Join-Path ([System.IO.Path]::GetTempPath()) 'pjc-hook-evals-state'
}
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

function Get-GroupFile([string[]]$Group) {
    # 그룹 이름을 파일명으로 — 그룹 구성이 바뀌면 파일명도 바뀌므로 낡은 -Resume 상태를 자동으로 무시한다.
    return (Join-Path $StateDir ((($Group -join '+') -replace '[^\w+-]', '') + '.jsonl'))
}

function Test-GroupDone([string]$Path) {
    # 완료 마커(done)가 있는지. 없으면 그 그룹은 미완료이므로 처음부터 다시 돌린다.
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    foreach ($l in (Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($l -match '"done"\s*:\s*true') { return $true }
    }
    return $false
}

$jobs = @()
$skipped = @()
foreach ($g in $scenarioGroups) {
    $gf = Get-GroupFile $g
    if ($Resume -and (Test-GroupDone $gf)) {
        $skipped += ($g -join '+')
        continue
    }
    Remove-Item -LiteralPath $gf -ErrorAction SilentlyContinue   # 미완료 잔여분은 버린다(부분 재사용 금지)
    # **경로 인자는 반드시 큰따옴표로 감싼다** — Start-Process는 -ArgumentList 배열을 공백으로 이어
    # 붙이기만 하고 자동 인용을 하지 않아, 레포 경로에 공백이 있으면(이 repo가 그렇다:
    # "…\Personal Project\…") `-File D:\Personal` 로 잘려 자식이 시작조차 못 한다. 이 증상은
    # "판정 파일이 없다"로만 드러나 원인이 보이지 않으므로 여기 근거를 남긴다.
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + (Join-Path $evalsDirTop 'run-scenario.ps1') + '"'),
        '-Names', ($g -join ','),
        '-OutJson', ('"' + $gf + '"'))
    if ($Filter -and @($Filter).Count) { $argList += @('-Filter', ($Filter -join ',')) }

    # 동시 실행 상한 — 슬롯이 빌 때까지 기다린다.
    while (@($jobs | Where-Object { -not $_.Proc.HasExited }).Count -ge $MaxParallel) {
        Start-Sleep -Milliseconds 400
    }
    # 출력 리다이렉트는 쓰지 않는다 — `-RedirectStandardOutput` + `-NoNewWindow` 조합이 정상 종료에도
    # 0바이트 파일을 남기는 것이 이 환경에서 실측됐다(AGENTS.md 골든 운용 항목). 진단이 필요한 정보는
    # 자식이 판정 파일에 직접 쓰므로(예외도 FAIL 레코드로 기록) stdout을 신뢰하지 않는다.
    $proc = Start-Process pwsh -ArgumentList $argList -PassThru -WindowStyle Hidden
    $jobs += [pscustomobject]@{ Group = ($g -join '+'); File = $gf; Proc = $proc }
}

if ($skipped.Count) {
    Write-Host ("[RESUME] 완료된 그룹 {0}개 건너뜀: {1}" -f $skipped.Count, ($skipped -join ', '))
}

foreach ($j in $jobs) { $j.Proc.WaitForExit() }

# ---- 판정 취합 (그룹 정의 순서 = 종전 dot-source 순서) ----
$allResults = New-Object System.Collections.Generic.List[object]
$deadGroups = @()
foreach ($g in $scenarioGroups) {
    $gf = Get-GroupFile $g
    $name = ($g -join '+')
    if (-not (Test-Path -LiteralPath $gf)) {
        $deadGroups += $name
        $allResults.Add(@{ ok = $false; line = "[FAIL] 그룹 $name — 판정 파일이 없다(자식이 시작조차 못 했다)" })
        continue
    }
    # 취합 우선순위: **완주 덤프(final) > 증분 라인.** 증분은 Assert-Case 경유분만 담으므로
    # (일부 시나리오가 $results.Add를 직접 호출한다 — run-scenario.ps1의 덤프 주석 참조)
    # 완주한 그룹은 반드시 final 레코드를 써야 하고, 그것이 그 그룹 판정의 정본이다.
    $done = $false
    $lines = @(Get-Content -LiteralPath $gf -Encoding UTF8)
    $final = $null
    foreach ($l in $lines) {
        if (-not $l.Trim()) { continue }
        try { $rec = $l | ConvertFrom-Json } catch { continue }
        if ($rec.PSObject.Properties.Name -contains 'final') { $final = $rec; $done = $true }
        elseif ($rec.PSObject.Properties.Name -contains 'done') { $done = $true }
    }
    if ($final) {
        foreach ($r in @($final.results)) {
            $allResults.Add(@{ ok = [bool]$r.ok; line = [string]$r.line })
        }
    } else {
        # 미완주 — 증분 라인으로 그때까지의 판정을 살린다(부분 보존).
        foreach ($l in $lines) {
            if (-not $l.Trim()) { continue }
            try { $rec = $l | ConvertFrom-Json } catch { continue }
            if ($rec.PSObject.Properties.Name -contains 'done') { continue }
            $allResults.Add(@{ ok = [bool]$rec.ok; line = [string]$rec.line })
        }
    }
    if (-not $done) {
        # 자식이 죽어 완료 마커가 없으면 **그 그룹을 FAIL로 보고하고 나머지는 완주**한다 —
        # 부분 결과를 조용히 통과시키면 커버리지가 줄어든 것이 초록으로 보인다.
        $deadGroups += $name
        $allResults.Add(@{ ok = $false; line = "[FAIL] 그룹 $name — 완주하지 못했다(완료 마커 없음, 판정 $($allResults.Count)건까지 기록됨)" })
    }
}

$failCount = 0
foreach ($res in $allResults) {
    Write-Host $res.line
    if (-not $res.ok) { $failCount++ }
}
$total = $allResults.Count
Write-Host ""

# 필터 모드 가드: 매칭 실행 0건이면 "전부 통과"로 오인되지 않게 실패 처리(오타·환경 문제 가시화).
if ($Filter -and $total -eq 0) {
    Write-Host "[FAIL] -Filter 매칭 실행 케이스 0건 — 필터 이름(오타) 또는 환경(git 부재 skip)을 확인하세요."
    exit 1
}
if ($Filter) {
    Write-Host "⚠ 부분 실행 결과 (-Filter) — 개발 반복 전용, task 검증(V-2)·F-2 판정에 사용 금지"
}
if ($deadGroups.Count) {
    Write-Host ("[WARN] 완주하지 못한 그룹 {0}개: {1} — -Resume 으로 이어서 돌릴 수 있습니다." -f $deadGroups.Count, ($deadGroups -join ', '))
}
Write-Host ("[MODE] 병렬 실행 (그룹 {0}개, 동시 상한 {1}) · 상태 {2}" -f $scenarioGroups.Count, $MaxParallel, $StateDir)
Write-Host ("결과: {0}/{1} OK (FAIL {2})" -f ($total - $failCount), $total, $failCount)
exit $(if ($failCount) { 1 } else { 0 })
