# PreToolUse hook (디스패처) - PowerShell 버전
# Bash/PowerShell 도구 호출 시 warn-external-ops·require-task-checkbox·warn-commit-secrets
#   3종의 검사를 한 프로세스에서 순차 수행한다(도구 호출당 pwsh 콜드스타트 4→2 — 개별 4엔트리를
#   block-destructive 독립 + 이 디스패처 2엔트리로 줄인 것).
#
# block-destructive는 이 디스패처에 포함하지 않는다 — "끌 수 없는 마지막 방어선"이라 hooks.json
#   독립 엔트리로 직접 실행 유지(결정 B). 이 디스패처의 로드 실패가 block-destructive에 영향 없음.
#
# 각 검사는 bash-hook-lib.ps1 함수를 호출하며(래퍼 스크립트와 동일 함수 — 동작 단일 출처),
#   호출을 try/catch로 격리해 한 검사의 예외가 나머지를 막지 않는다.
#
# 출력 계약:
#   - Block(require-task-checkbox 차단) 발생 → 그 차단 사유만 stderr + exit 2(도구 차단).
#     이때 warn 경고는 출력하지 않는다(차단된 커밋이라 안전 회귀 아님 — 차단 해소 후 재시도 시 노출).
#   - Block 없음 → warn 경고들을 stderr로, additionalContext는 단일 JSON으로 병합해 stdout + exit 0.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
} catch {
    exit 0   # 파싱 실패 시 통과 (검사 실패가 차단보다 안전)
}

. (Join-Path $PSScriptRoot 'bash-hook-lib.ps1')

# 순서: 원 hooks.json 순서에서 block-destructive(독립)만 앞으로 뺀 나머지 3종.
$checks = @('Invoke-WarnExternalOps', 'Invoke-RequireTaskCheckbox', 'Invoke-WarnCommitSecrets')
$results = New-Object System.Collections.Generic.List[object]
foreach ($fn in $checks) {
    try {
        $r = & $fn $data
        if ($r) { $results.Add($r) }
    } catch {
        # 한 검사의 예외는 나머지를 막지 않는다(런타임 격리 — 안전측 통과).
    }
}

$blocked = @($results | Where-Object { $_.Block })
if ($blocked.Count -gt 0) {
    # 차단: 차단 사유만 출력(warn 경고는 버림 — D4 트레이드오프), exit 2로 도구 차단.
    foreach ($b in $blocked) {
        foreach ($l in $b.Stderr) { [Console]::Error.WriteLine($l) }
    }
    exit 2
}

# 비차단: warn 경고 stderr 전부 + additionalContext 병합(Claude Code는 hook당 1 JSON 파싱).
$contexts = New-Object System.Collections.Generic.List[string]
foreach ($r in $results) {
    foreach ($l in $r.Stderr) { [Console]::Error.WriteLine($l) }
    if ($r.Context) { $contexts.Add($r.Context) }
}
if ($contexts.Count -gt 0) {
    $merged = ($contexts -join "`n`n")
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $merged } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}
exit 0
