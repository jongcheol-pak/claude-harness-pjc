# PreToolUse hook (디스패처) - PowerShell 버전
# Bash/PowerShell 도구 호출 시 warn-external-ops·require-task-checkbox·warn-commit-secrets
#   3종의 검사를 한 프로세스에서 순차 수행한다(도구 호출당 pwsh 콜드스타트 4→2 — 개별 4엔트리를
#   block-destructive 독립 + 이 디스패처 2엔트리로 줄인 것).
#
# block-destructive는 이 디스패처에 포함하지 않는다 — "끌 수 없는 마지막 방어선"이라 hooks.json
#   독립 엔트리로 직접 실행 유지(결정 B). 이 디스패처의 로드 실패가 block-destructive에 영향 없음.
#
# 트레이드오프(수용됨 — 결정 B의 이면): require-task-checkbox는 차단(exit 2) 게이트인데 이 디스패처의
#   lib 로드에 결합돼 있어, bash-hook-lib.ps1 로드 실패 시 3검사가 모두 수행되지 않는다(fail-open —
#   독립 실행이 보존된 것은 block-destructive뿐). 아래 로드 가드가 이 상태를 stderr 경고로 가시화한다
#   (비차단 유지 — "검사 실패가 차단보다 안전" 원칙 동일, 골든 케이스가 회귀 방지).
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
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로·명령이 깨진다(디스패처가 lib 함수로 넘기는 명령 원문까지 손상). 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
} catch {
    exit 0   # 파싱 실패 시 통과 (검사 실패가 차단보다 안전)
}

. (Join-Path $PSScriptRoot 'bash-hook-lib.ps1')

# 로드 가드: lib 로드 실패(파일 누락·손상) 시 3검사가 침묵 fail-open되는 것을 가시화한다 —
#   차단 게이트(require-task-checkbox)까지 실리는 지점이라 경고 없이 통과시키지 않는다(비차단 유지).
if (-not (Get-Command Invoke-WarnExternalOps -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('[pre-bash-dispatch] bash-hook-lib.ps1 로드 실패 — 검사 3종(외부작업 경고·task 체크박스 게이트·시크릿 경고) 미수행(fail-open). 플러그인 재설치를 권장합니다.')
    exit 0
}

# [이벤트 로깅] 차단/경고 이벤트를 오탐 리뷰 데이터로 적재 — lib 함수·얇은 래퍼는 무수정(골든 격리 유지),
#   로깅은 디스패처 수준에서 결과 객체로 수행한다. 실패는 전면 격리(검사 판정 무영향).
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}
$cmdText = [string]$data.tool_input.command
function Write-DispatchEvent {
    param([string]$HookName, [string]$Decision, [object]$Result)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            $rule = if ($Result.Stderr -and @($Result.Stderr).Count -gt 0) { [string](@($Result.Stderr)[0]) } else { '' }
            Write-HookEvent $HookName $Decision $rule $script:cmdText
        }
    } catch {}
}

# 순서: 원 hooks.json 순서에서 block-destructive(독립)만 앞으로 뺀 나머지 3종 + warn-global-find(v1.183.0 신설 —
#   대응하는 독립 hook 스크립트가 없고 이 디스패처가 유일한 실행 경로다).
$checks = @(
    @{ fn = 'Invoke-WarnExternalOps';     name = 'warn-external-ops' },
    @{ fn = 'Invoke-RequireTaskCheckbox'; name = 'require-task-checkbox' },
    @{ fn = 'Invoke-WarnCommitSecrets';   name = 'warn-commit-secrets' },
    @{ fn = 'Invoke-WarnGlobalFind';      name = 'warn-global-find' }
)
$results = New-Object System.Collections.Generic.List[object]
foreach ($c in $checks) {
    try {
        $r = & $c.fn $data
        if ($r) { $r['Name'] = $c.name; $results.Add($r) }
    } catch {
        # 한 검사의 예외는 나머지를 막지 않는다(런타임 격리 — 안전측 통과).
    }
}

$blocked = @($results | Where-Object { $_.Block })
if ($blocked.Count -gt 0) {
    # 차단: 차단 사유만 출력(warn 경고는 버림 — D4 트레이드오프), exit 2로 도구 차단.
    foreach ($b in $blocked) {
        foreach ($l in $b.Stderr) { [Console]::Error.WriteLine($l) }
        Write-DispatchEvent $b['Name'] 'block' $b
    }
    exit 2
}

# 비차단: warn 경고 stderr 전부 + additionalContext 병합(Claude Code는 hook당 1 JSON 파싱).
$contexts = New-Object System.Collections.Generic.List[string]
foreach ($r in $results) {
    foreach ($l in $r.Stderr) { [Console]::Error.WriteLine($l) }
    if (($r.Stderr -and @($r.Stderr).Count -gt 0) -or $r.Context) { Write-DispatchEvent $r['Name'] 'warn' $r }
    if ($r.Context) { $contexts.Add($r.Context) }
}
if ($contexts.Count -gt 0) {
    $merged = ($contexts -join "`n`n")
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $merged } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}
exit 0
