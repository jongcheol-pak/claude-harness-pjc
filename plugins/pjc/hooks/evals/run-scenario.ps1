# run-scenario.ps1 — 골든 시나리오 그룹 1개를 자기 격리 환경에서 실행하는 자식 러너
#
# 사용법 (코디네이터가 호출한다 — 직접 실행도 가능):
#   pwsh -NoProfile -ExecutionPolicy Bypass -File run-scenario.ps1 -Names stateless -OutJson <경로>
#   pwsh ... -Names protect-harness-installed,hook-event-log -OutJson <경로>   # 같은 그룹 = 한 프로세스
#
# 무엇을: `-Names`로 받은 시나리오 파일을 **자기 격리 홈·작업 폴더**에서 순차 dot-source한다.
#   케이스 판정은 호출될 때마다 -OutJson에 JSON 라인으로 append되므로(증분 기록), 이 프로세스가
#   중간에 죽어도 그때까지의 판정이 파일에 남는다.
#
# 왜 시나리오 단위인가: 케이스 단위로 쪼개면 같은 시나리오 안의 픽스처 생성 순서가 깨진다
#   (예: post-write-checks는 $pw에 파일을 쓰고 이어서 그 파일을 검사한다). 시나리오 내부는
#   종전대로 순차이고, 병렬은 시나리오 사이에서만 일어난다.
#
# 왜 그룹인가: 대부분의 시나리오는 $work 아래 자기 하위 디렉터리만 쓰므로 완전히 독립이지만,
#   `protect-harness-installed`와 `hook-event-log`는 **$vdCache를 공유**하고 후자는 격리 홈의
#   `.state/hook-events/*.jsonl` 적재를 관찰한다 — 두 시나리오를 같은 프로세스(=같은 홈)에 묶어
#   분리 전과 동일한 관찰 조건을 유지한다.

param(
    # 실행할 시나리오 파일 기본명(`.ps1` 없이). 여러 개면 이 순서대로 순차 실행한다.
    [Parameter(Mandatory = $true)][string[]]$Names,
    # 판정을 JSON 라인으로 append할 경로. 코디네이터가 그룹별로 다른 경로를 준다.
    [Parameter(Mandatory = $true)][string]$OutJson,
    # 부분 실행 필터 — 코디네이터가 그대로 전달한다.
    [string[]]$Filter
)

# -Names 정규화 — `pwsh -File`로 넘어온 `a,b`는 **단일 문자열**이다(PowerShell CLI가 콤마를
# 나누지 않는다). 나누지 않으면 'a,b'라는 이름의 시나리오를 찾다가 "파일 없음"으로 실패한다 —
# `-Filter "a,b"`가 매칭 0건으로 조용히 실패했던 것과 같은 형태이므로 같은 방식으로 푼다.
. (Join-Path $PSScriptRoot 'filter-spec.ps1')
$Names = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# eval-common.ps1이 읽는 입력 변수 (dot-source 전에 설정해야 한다)
$EvalFilter = $Filter
$EvalOutJson = $OutJson
# 격리 이름 접미: 그룹 이름 + 짧은 GUID. 그룹 이름을 넣는 이유는 중단 후 남은 폴더를 보고
# 어느 그룹이 죽었는지 알 수 있게 하기 위함이다. **그 진단 창은 3일이다** — 코디네이터 기동 시
# sweep이 그보다 오래된 잔여를 걷는다(`eval-paths.ps1`). 더 오래 보려면 그 전에 복사해 둘 것.
$EvalHomeSuffix = (($Names -join '+') -replace '[^\w+-]', '') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)

. (Join-Path $PSScriptRoot 'eval-common.ps1')

$exitCode = 0
try {
    foreach ($n in $Names) {
        $sh = Resolve-ScenarioShard $n
        $script:ShardIndex = $sh.Index; $script:ShardCount = $sh.Count
        $path = Join-Path $evalsDir ('scenarios/' + $sh.File + '.ps1')
        if (-not (Test-Path -LiteralPath $path)) {
            # 존재하지 않는 시나리오를 조용히 건너뛰면 "케이스 0건인데 통과"가 되므로 실패로 만든다.
            Add-EvalResult $false "[FAIL] run-scenario: 시나리오 파일 없음 — $n" "run-scenario:$n"
            $exitCode = 1
            continue
        }
        # 현재 시나리오 이름을 JSON 라인에 싣기 위해 script 스코프에 둔다(Add-EvalResult가 읽는다).
        $script:EvalCurrentScenario = $n
        . $path
    }
} catch {
    # 예외를 **판정 파일에 남긴다** — 코디네이터는 자식의 stdout을 신뢰하지 않으므로(리다이렉트가
    # 0바이트로 남는 실측이 있다) 여기서 기록하지 않으면 "완주하지 못했다"만 보이고 원인이 사라진다.
    Add-EvalResult $false "[FAIL] run-scenario($($Names -join '+')) 예외 — $($_.Exception.Message)" "run-scenario:exception"
    $exitCode = 1
} finally {
    # 격리 원복 + 자기 폴더만 정리 — 다른 그룹의 폴더는 건드리지 않는다(병렬 안전).
    $env:USERPROFILE = $realHome
    Set-Location $env:TEMP
    Remove-Item -Recurse -Force $EvalIso -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $EvalWork -ErrorAction SilentlyContinue
}

# ---- 완주 시 판정 전량 덤프 (증분 라인보다 우선하는 정본) ----
# **왜 전량을 다시 쓰는가**: 증분 기록은 `Assert-Case` 경유분만 잡는데, 일부 시나리오는 그 헬퍼를
#   쓰지 않고 `$results.Add(...)`를 **직접** 호출한다(`guard-bash.ps1`의 secret-patterns
#   24건·dispatch 2건 · `session-context.ps1` SC22 · `hook-event-log.ps1`).
#   Assert-Case만 후킹했을 때 그 **29건이 취합에서 조용히 빠져** 병렬 결과가 502/502 OK로 보였다
#   (순차는 531/531 — 개수만 대조하면 통과로 읽히는 형태였고, 순차 대비 집합 등가 검사가 잡았다).
#   여기서 $results 전량을 덤프하면 **어떤 경로로 누적된 판정이든 빠지지 않는다** — 앞으로 누가
#   Assert-Case를 우회해도 자동으로 포함되므로, 시나리오 15개를 고치는 것보다 견고하다.
# 증분 라인은 그대로 남겨 둔다: 자식이 중간에 죽어 이 덤프에 도달하지 못한 경우의 부분 보존용이다.
$failCount = @($results | Where-Object { -not $_.ok }).Count
$total = $results.Count
Add-Content -LiteralPath $OutJson -Value (
    ([ordered]@{
        final = $true; done = $true; group = ($Names -join '+'); total = $total; fail = $failCount
        results = @($results | ForEach-Object { [ordered]@{ ok = [bool]$_.ok; line = [string]$_.line } })
    } | ConvertTo-Json -Compress -Depth 5)
) -Encoding utf8NoBOM
Write-Host ("GROUP={0} {1}/{2} OK (FAIL {3})" -f ($Names -join '+'), ($total - $failCount), $total, $failCount)
exit $(if ($failCount -or $exitCode) { 1 } else { 0 })
