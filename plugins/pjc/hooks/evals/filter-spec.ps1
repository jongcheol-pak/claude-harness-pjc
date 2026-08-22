# filter-spec.ps1 — `-Filter` 유효 이름 목록 + 정규화 규칙 (dot-source 전용, 부작용 없음)
#
# 왜 별 파일인가: 이 둘을 **코디네이터(`run-hook-evals.ps1`)와 `eval-common.ps1` 양쪽이 필요로 한다.**
#   - 코디네이터: 자식을 숨김 창으로 띄우고 출력을 캡처하지 않으므로(0바이트 리다이렉트 실측) **필터
#     이름 경고를 부모가 직접 내야** 하고, `-Resume` 스코프 키에도 정규화된 집합이 필요하다.
#   - `eval-common.ps1`: 실제 섹션 게이트(`Test-HookSelected`)가 그 집합을 쓴다.
#   두 곳에 복제하면 정규화가 갈릴 때 **서로 다른 실제 필터가 같은 스코프로 매핑돼** `-Resume`이 다른
#   조건의 판정을 재사용할 수 있다(v1.159.0에서 그 실패형을 스코프 격리로 닫았는데, 복제가 그 가드의
#   정확성 경로에 놓이는 셈이다). 이름 목록 드리프트는 진단 오도에 그치지만 정규화 드리프트는 판정을 바꾼다.
#
# 이 파일은 **함수와 상수만 정의한다** — 격리 환경을 만들거나 cwd를 바꾸지 않으므로 코디네이터가
# eval-common을 dot-source하지 않는 병렬 경로에서도 안전하게 읽을 수 있다.

# 유효한 -Filter 이름(hook 기본명). 신규 hook을 골든에 추가하면 여기만 고친다.
$script:GoldenFilterNames = @(
    'block-destructive', 'protect-harness', 'require-plan-for-write', 'require-task-checkbox',
    'post-write-checks', 'require-evidence', 'warn-external-ops', 'suggest-agents-record',
    'warn-commit-secrets', 'pre-bash-dispatch', 'warn-version-drift', 'session-context', 'hook-event-log',
    'orphan-process-cleanup', 'session-end-cleanup', 'guard-agents-content'
)

function Get-NormalizedFilter {
    <#
      -Filter 입력을 정규화한다. `pwsh -File`로 넘어온 'a,b'는 **단일 문자열**이므로(CLI가 콤마를
      나누지 않는다) 여기서 쪼갠다 — 나누지 않으면 'a,b'가 통째로 한 이름이 되어 어느 필터에도
      걸리지 않고 "매칭 0건" 실패로만 드러났다(2026-07-10 등재, v1.159.0에서 해소).
    #>
    param([string[]]$Filter)
    if (-not $Filter -or -not @($Filter).Count) { return $null }
    return @(
        $Filter |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { ($_ -replace '\.ps1$', '').Trim().ToLowerInvariant() } |
            Where-Object { $_ }
    )
}

function Write-UnknownFilterWarning {
    # 알 수 없는 이름을 각각 경고한다. 정확성은 "매칭 0건 → FAIL" 가드가 지키지만, 이 안내가 없으면
    # 어느 이름이 왜 안 맞는지 알 수 없다.
    param([string[]]$NormalizedFilter)
    foreach ($f in @($NormalizedFilter)) {
        if ($script:GoldenFilterNames -notcontains $f) {
            Write-Host "[WARN] 알 수 없는 필터 이름: '$f' (유효: $($script:GoldenFilterNames -join ', '))"
        }
    }
}
