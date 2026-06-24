# harness-toggle.ps1
# 개별 harness hook을 런타임에 on/off (상태 파일 기반).
# Claude Code 재시작이나 settings.json 수정 없이 즉시 반영.
#
# 사용법:
#   harness-toggle.ps1                                    # 상태 출력 (기본)
#   harness-toggle.ps1 "" status                          # 상태 출력
#   harness-toggle.ps1 require-plan-for-write off         # 비활성화
#   harness-toggle.ps1 require-plan-for-write on          # 활성화
#   harness-toggle.ps1 require-plan-for-write toggle      # 토글

param(
    [Parameter(Position = 0)]
    [string]$Hook = '',

    [Parameter(Position = 1)]
    [ValidateSet('on', 'off', 'toggle', 'status')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Stop'

$disabledDir = Join-Path $env:USERPROFILE '.claude\.disabled'
New-Item -Force -ItemType Directory -Path $disabledDir | Out-Null

# 토글 가능한 hook 화이트리스트
# block-destructive 는 안전상 의도적으로 제외 (파괴적 명령 차단은 항상 동작)
$known = @(
    'require-plan-for-write',
    'require-evidence',
    'check-utf8-and-lines',
    'impact-warn'
)

function Show-Status {
    Write-Host ""
    Write-Host "Harness Hook Status" -ForegroundColor Cyan
    Write-Host "-------------------"
    foreach ($h in $known) {
        $isOff = Test-Path -LiteralPath (Join-Path $disabledDir $h)
        if ($isOff) {
            Write-Host ("  [OFF] " + $h) -ForegroundColor Yellow
        } else {
            Write-Host ("  [ON]  " + $h) -ForegroundColor Green
        }
    }
    Write-Host ""
    Write-Host "  [ON]  block-destructive  (안전상 토글 불가)" -ForegroundColor DarkGray
    Write-Host ""
}

# 인자가 비어있거나 status 액션이면 상태 출력
if ([string]::IsNullOrWhiteSpace($Hook) -or $Action -eq 'status') {
    Show-Status
    return
}

# 알 수 없는 hook
if ($known -notcontains $Hook) {
    Write-Host ""
    Write-Host "[ERROR] Unknown hook: $Hook" -ForegroundColor Red
    Write-Host ""
    Write-Host "토글 가능한 hook:" -ForegroundColor Yellow
    foreach ($h in $known) { Write-Host "  - $h" }
    Write-Host ""
    Write-Host "block-destructive 는 안전상 토글할 수 없습니다." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

$file = Join-Path $disabledDir $Hook

switch ($Action) {
    'off' {
        New-Item -Force -ItemType File -Path $file | Out-Null
        Write-Host "[OFF] $Hook 비활성화됨" -ForegroundColor Yellow
        Write-Host "      파일: $file" -ForegroundColor DarkGray
    }
    'on' {
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force
            Write-Host "[ON]  $Hook 활성화됨" -ForegroundColor Green
        } else {
            Write-Host "[ON]  $Hook 이미 활성 상태" -ForegroundColor DarkGray
        }
    }
    'toggle' {
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force
            Write-Host "[ON]  $Hook 활성화됨" -ForegroundColor Green
        } else {
            New-Item -Force -ItemType File -Path $file | Out-Null
            Write-Host "[OFF] $Hook 비활성화됨" -ForegroundColor Yellow
        }
    }
}
