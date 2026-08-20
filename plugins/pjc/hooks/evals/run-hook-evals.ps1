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
#   ② scenarios/*.ps1 14개: 상태 필요(plan 폴더·git repo·AGENTS.md 마커·post-write 파일)
#   공용 헬퍼·격리 구성은 eval-common.ps1이며, 이 파일과 run-scenario.ps1이 함께 dot-source한다.
#
# 실행 구조(v1.159.0): 기본은 **시나리오 그룹 단위 병렬**이다 — 그룹마다 자식 pwsh를 띄워
#   각자의 격리 홈에서 돌리고 판정 JSON을 취합한다. 케이스마다 자식 pwsh를 새로 띄우는 구조상
#   비용의 절반 이상이 프로세스 기동이라(빈 pwsh 콜드스타트 약 1.0초 / hook 1회 약 1.8초),
#   시나리오를 동시에 돌리면 wall-clock이 최대 그룹 하나의 시간으로 수렴한다.
#   케이스 단위로 쪼개지 않는 이유는 시나리오 내부의 픽스처 생성 순서가 깨지기 때문이다.
#
# -Sequential 계약: 병렬 디스패치를 끄고 **한 프로세스에서 14 시나리오를 종전대로 dot-source**한다.
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
    # 동시에 띄울 자식 프로세스 상한. 기본 6 — 13 그룹을 한꺼번에 띄우면 CPU·디스크 경합으로
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
    @('orphan-process-cleanup'),
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

# ---- 필터 정규화 + 이름 검증 (코디네이터에서 선행) ----
# 정규화는 eval-common과 같은 규칙이다(단일 문자열 'a,b'도 나눈다). **코디네이터가 먼저 하는 이유는 둘**:
#   ① -Resume 스코프 각인(아래)에 정규화된 집합이 필요하다.
#   ② 병렬 경로는 자식을 숨김 창으로 띄우고 출력을 캡처하지 않으므로(0바이트 리다이렉트 실측 때문),
#      eval-common이 내는 "[WARN] 알 수 없는 필터 이름" 안내가 사용자에게 도달하지 못한다 — 오타를
#      냈을 때 "매칭 0건 → FAIL" 가드가 실패로 잡아주긴 하지만 **어느 이름이 왜 안 맞는지 알 수 없다.**
#      그 진단을 여기서 되살린다(병렬화로 없앤 기존 출력의 복구).
# 이름 목록·정규화 규칙은 `filter-spec.ps1`이 단일 정본이다 — 여기와 eval-common이 각자 복제하면
# 정규화가 갈릴 때 서로 다른 실제 필터가 같은 `-Resume` 스코프로 매핑돼 그 가드가 무력화된다.
. (Join-Path $evalsDirTop 'filter-spec.ps1')

$script:NormalizedFilter = Get-NormalizedFilter -Filter $Filter
if ($script:NormalizedFilter) {
    Write-UnknownFilterWarning -NormalizedFilter $script:NormalizedFilter
    Write-Host "⚠ 부분 실행 모드 (-Filter: $($script:NormalizedFilter -join ', ')) — 개발 반복 전용, task 검증(V-2)·F-2 판정에 사용 금지"
}

# =====================================================================
# 순차 경로 — 종전 구조 그대로 (한 프로세스에서 14 시나리오 dot-source)
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

# ---- -Resume 상태의 유효 범위 각인 (거짓 green 차단) ----
# **왜 필요한가**: 상태를 그룹명만으로 식별하면 `-Resume`이 **다른 조건에서 만든 판정을 재사용**한다.
#   실측 사고: `-Filter "stateless,pre-bash-dispatch"` 로 2그룹만 돌린 뒤 **무필터 `-Resume`** 을 실행하자
#   12그룹을 전부 "완료"로 건너뛰고 `112/112 OK (FAIL 0)` exit 0을 냈다 — **419케이스가 조용히 빠졌는데
#   부분 실행 경고조차 없어** 문서화된 판정 절차(EXIT 마커 + 결과 줄)로는 구분이 불가능했다.
#   커밋이 달라진 경우도 같다: 커밋 A에서 완주 → 커밋 B에서 중단 → `-Resume`이면 A의 판정을 섞는다.
# **해법은 상태를 스코프별로 격리하는 것**이다 — 필터 집합과 HEAD를 디렉터리 이름에 각인하면 조건이
#   다른 상태는 **애초에 보이지 않아** 스킵 판정 자체가 성립하지 않는다(`Get-GroupFile`이 그룹 구성을
#   파일명에 담아 낡은 상태를 무효화하는 것과 같은 방식 — 검사를 추가하는 것보다 구조가 단순하다).
$scopeFilter = if ($script:NormalizedFilter) { ($script:NormalizedFilter | Sort-Object) -join ',' } else { 'all' }
$scopeHead = 'nogit'
try {
    $sha = & git -C $evalsDirTop rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $sha) { $scopeHead = ([string]$sha).Trim().Substring(0, 12) }
} catch { }
# **검증 자산의 내용 해시도 각인한다.** HEAD만으로는 *"전체 실행 → kill → 코드 수정 → `-Resume`"* 을
# 구분하지 못한다 — 커밋이 그대로이므로 낡은 코드로 낸 판정이 재사용되고 스코프 줄은 유효한 것처럼
# 보인다(개발 중 흔한 시퀀스라 실해가 크다). 대상은 판정을 바꿀 수 있는 것 전부: 러너 3종 · 시나리오 ·
# 케이스 JSON · hook 스크립트. 파일 수십 개의 MD5라 비용은 실행당 수십 ms다.
$assetHash = 'none'
try {
    $assetFiles = @(
        Get-ChildItem -LiteralPath $evalsDirTop -Filter *.ps1 -File
        Get-ChildItem -LiteralPath (Join-Path $evalsDirTop 'scenarios') -Filter *.ps1 -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $evalsDirTop -Filter *.json -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path (Split-Path (Split-Path $evalsDirTop -Parent) -Parent) 'scripts') -Filter *.ps1 -File -ErrorAction SilentlyContinue
    ) | Sort-Object FullName
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $acc = New-Object System.Text.StringBuilder
    foreach ($f in $assetFiles) {
        [void]$acc.Append($f.Name).Append(':').Append(
            [System.BitConverter]::ToString($md5.ComputeHash([System.IO.File]::ReadAllBytes($f.FullName))).Replace('-', '')
        ).Append(';')
    }
    $assetHash = [System.BitConverter]::ToString(
        $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($acc.ToString()))
    ).Replace('-', '').Substring(0, 10).ToLowerInvariant()
} catch { }
$scopeKey = "filter=$scopeFilter|head=$scopeHead|assets=$assetHash"
# 디렉터리 이름은 짧게 유지하되 사람이 스코프를 확인할 수 있어야 하므로 해시 + scope.txt를 함께 둔다.
$scopeHash = [System.BitConverter]::ToString(
    [System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($scopeKey))
).Replace('-', '').Substring(0, 10).ToLowerInvariant()
$StateDir = Join-Path $StateDir $scopeHash
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $StateDir 'scope.txt') -Value $scopeKey -Encoding utf8NoBOM

function Get-GroupFile([string[]]$Group) {
    # 그룹 이름을 파일명으로 — 그룹 구성이 바뀌면 파일명도 바뀌므로 낡은 -Resume 상태를 자동으로 무시한다.
    # (필터·HEAD 범위는 위 $StateDir 스코프 격리가 담당한다.)
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
    # 폴링 400ms: 그룹 하나가 최소 수십 초라 이 간격이 총 시간에 미치는 영향은 무시할 수 있고,
    # 더 짧게 잡으면 13그룹 대기 동안 폴링 자체가 CPU를 잠식해 자식과 경합한다.
    while (@($jobs | Where-Object { -not $_.Proc.HasExited }).Count -ge $MaxParallel) {
        Start-Sleep -Milliseconds 400
    }
    # 출력 리다이렉트는 쓰지 않는다 — `-RedirectStandardOutput` + `-NoNewWindow` 조합이 정상 종료에도
    # 0바이트 파일을 남기는 것이 이 환경에서 실측됐다(`docs/harness-conventions.md` 「골든 러너 운용」).
    # 진단이 필요한 정보는
    # 자식이 판정 파일에 직접 쓰므로(예외도 FAIL 레코드로 기록) stdout을 신뢰하지 않는다.
    $proc = Start-Process pwsh -ArgumentList $argList -PassThru -WindowStyle Hidden
    $jobs += [pscustomobject]@{ Group = ($g -join '+'); File = $gf; Proc = $proc }
}

if ($skipped.Count) {
    # 스코프를 함께 낸다 — 무엇을 재사용했는지가 보이지 않으면 "몇 그룹 건너뜀"만으로는 그 판정이
    # 이번 조건에서 유효한지 알 수 없다(스코프 격리가 잘못된 재사용을 이미 막지만, 재사용 사실 자체는
    # 판정 근거로 남아야 한다).
    Write-Host ("[RESUME] 완료된 그룹 {0}개 건너뜀 (스코프 {1}): {2}" -f $skipped.Count, $scopeKey, ($skipped -join ', '))
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
        # 이 그룹이 남긴 판정 수만 센다 — 누적 전체($allResults.Count)를 쓰면 앞 그룹들의 케이스가
        # 섞여 그 그룹의 진행이 실제보다 많아 보인다(진단 문구가 오히려 오해를 만든다).
        $partial = @($lines | Where-Object { $_.Trim() -and $_ -notmatch '"(done|final)"\s*:\s*true' }).Count
        $allResults.Add(@{ ok = $false; line = "[FAIL] 그룹 $name — 완주하지 못했다(완료 마커 없음, 이 그룹 판정 $partial건까지 기록됨)" })
    }
}

# ---- 그룹 공유 임시 픽스처 정리 ----
# `scenarios/require-plan-for-write.ps1`이 만드는 `%TEMP%\pjc-hook-eval-scratch`는 **의도적으로
# 시스템 임시 폴더 하위**에 있다(require-plan-for-write가 temp 하위를 무조건 통과시키는 완화 경로를
# 그 위치에서만 재현할 수 있다). 그래서 자식의 $EvalWork 하위로 옮길 수 없고, 자식은 자기 격리
# 폴더만 지우므로 **어느 쪽 책임에도 걸리지 않는다** — 순차 경로에만 정리가 있어 병렬(기본값)에서
# 매 실행마다 남던 회귀를 여기서 닫는다. 자식이 모두 끝난 뒤 코디네이터가 지운다.
Remove-Item -Recurse -Force (Join-Path ([System.IO.Path]::GetTempPath()) 'pjc-hook-eval-scratch') -ErrorAction SilentlyContinue

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
# 미완주가 있으면 **결과 줄 자체**에 분모의 성격을 적는다 — 위 [WARN]은 결과 줄 위에 따로 떠서
# 읽는 사람이 `FAIL 1`을 회귀로 오해한다(v1.173.0 F-7에서 실제로 메인·리뷰어가 둘 다 오독했다).
# 미실행 케이스 수는 세지 않는다 — 그러려면 시나리오 파서가 필요한데, 막으려는 것이 오독이라
# "분모가 전체가 아니다"를 말하는 것으로 충분하다.
$deadSuffix = ''
if ($deadGroups.Count) {
    $deadSuffix = ' — ⚠ 그룹 {0}개 미완주, 분모는 실행분 기준(전체 아님)' -f $deadGroups.Count
}
Write-Host ("결과: {0}/{1} OK (FAIL {2}){3}" -f ($total - $failCount), $total, $failCount, $deadSuffix)
exit $(if ($failCount) { 1 } else { 0 })
