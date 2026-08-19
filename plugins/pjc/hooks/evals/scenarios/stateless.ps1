# scenarios/stateless.ps1 — 무상태 케이스 (hook-cases.json 구동 + 디스패처 전수 동등성) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
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
            -ExpectNotContains ([string]($c.expect_not_contains ?? '')) `
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
    #   `expect_not_contains`도 개별 전용이다 — 디스패처는 3 hook 합산이라 같은 문자열이
    #   다른 hook의 출력에서 정당하게 나올 수 있어, 상위집합에 「없어야 한다」를 걸면 오판한다.
    if ($runDispatchEcho) {
        $rd = Invoke-Hook 'pre-bash-dispatch.ps1' $json
        Assert-Case -Name "dispatch=$($c.hook): $($c.name)" -R $rd `
            -ExpectExit ([int]($c.expect_exit ?? 0)) `
            -ExpectContains ([string]($c.expect_contains ?? ''))
    }
}

