# install.ps1
# pjc Claude Code Harness Plugin - 자동 설치 스크립트
#
# 사용법:
#   .\install.ps1                                    # 로컬 모드 (이 폴더를 marketplace로 등록 - 개발용)
#   .\install.ps1 -GitHub jongcheol-pak/claude-harness-pjc   # GitHub 모드 (권장 - 원본 폴더 불필요)
#   .\install.ps1 -Scope project                     # 프로젝트별 설치 (.claude/settings.json)
#   .\install.ps1 -Uninstall                         # 제거만
#   .\install.ps1 -KeepExisting                      # 이미 설치되어 있으면 그대로 둠
#
# 모드 차이:
#   로컬 모드  - 이 폴더가 plugin 본체로 참조됨. 폴더를 삭제/이동하면 plugin이 깨짐.
#   GitHub 모드 - Claude Code가 repo를 clone해 캐시. 로컬 폴더 불필요, push로 배포.
#
# Claude Code REPL이 실행 중이면 종료 후 다시 시작해야 변경이 반영됩니다.

param(
    [ValidateSet('user', 'project')]
    [string]$Scope = 'user',

    [string]$GitHub = '',

    [switch]$Uninstall,

    [switch]$SkipVerification,

    [switch]$KeepExisting
)

$ErrorActionPreference = 'Stop'

# 홈 경로: Claude Code 홈과 정합 — Windows는 USERPROFILE(없으면 $HOME 폴백), 비Windows는 $HOME
$homeBase = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }

# 색상 헬퍼
function Write-Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)      { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t)    { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Write-Err($t)     { Write-Host "  [X]  $t" -ForegroundColor Red }
function Write-Info($t)    { Write-Host "  $t" -ForegroundColor Gray }

Write-Host ""
Write-Host "pjc Claude Code Harness - Plugin Installer" -ForegroundColor Cyan
Write-Host ""

# ---- 0. 런타임 확인 (안전 hook은 pwsh 7 우선 — 실행 셸은 Claude Code가 결정) ----
# v1.108.0부터 hook은 Claude Code가 띄운 PowerShell에서 직접 실행된다(자체 재기동 없음).
# 실행 셸 선택은 Claude Code의 powershell 해석을 따르며(실측: pwsh 있으면 pwsh 우선·NoProfile),
# 스크립트는 5.1 호환(BOM)이라 pwsh 미설치 Windows에서도 동작한다(추가 설치 불요, pwsh 설치 시 그쪽 우선).
# 비-Windows(macOS/Linux)는 5.1이 없어 pwsh가 반드시 필요하다(미검증·실험적).
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
$isWin = ($IsWindows -or -not (Test-Path variable:IsWindows))
if (-not $pwshCmd) {
    if ($isWin) {
        Write-Info "pwsh(PowerShell 7+) 미설치 — 안전 hook은 Claude Code가 띄우는 내장 PowerShell(5.1)에서 동작합니다(추가 설치 불요, 스크립트 5.1 호환)."
        Write-Info "pwsh 7을 설치하면 그쪽을 우선 사용합니다(실측 기준, 선택): winget install Microsoft.PowerShell"
    } else {
        Write-Warn "안전 hook 실행에 pwsh(PowerShell 7+)가 필요한데 찾을 수 없습니다 (비-Windows는 5.1 폴백 불가)."
        Write-Warn "macOS: 'brew install powershell' / Linux: 배포판 패키지로 pwsh 설치 후 재시작 (비-Windows hook은 미검증·실험적)."
        Write-Warn "pwsh 없이 진행하면 skill은 동작하나 hook 안전망(위험 명령 차단·plan 강제 등)은 작동하지 않습니다. (계속 진행 — 중단하려면 Ctrl+C)"
    }
    Write-Host ""
}

# ---- 1. claude CLI 확인 ----
Write-Section "Prerequisite Check"

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Err "claude CLI를 찾을 수 없습니다."
    Write-Info "Claude Code 설치 후 다시 실행하세요:"
    Write-Info "  npm install -g @anthropic-ai/claude-code"
    exit 1
}
Write-Ok "claude CLI 발견: $($claudeCmd.Source)"

# 버전 확인 (v2.0 이상 필요)
try {
    $versionOutput = & claude --version 2>&1 | Out-String
    Write-Info "Version: $($versionOutput.Trim())"
} catch {
    Write-Warn "버전 확인 실패. v2.0 이상이 필요합니다."
}

# ---- 2. marketplace 경로 확인 (로컬 모드만) ----
$marketplacePath = $PSScriptRoot
$marketplaceManifest = Join-Path $marketplacePath ".claude-plugin/marketplace.json"

if (-not $GitHub) {
    if (-not (Test-Path -LiteralPath $marketplaceManifest)) {
        Write-Err "marketplace.json을 찾을 수 없습니다: $marketplaceManifest"
        Write-Info "이 스크립트는 압축 해제된 패키지 root에서 실행되어야 합니다."
        Write-Info "또는 GitHub 모드 사용: .\install.ps1 -GitHub jongcheol-pak/claude-harness-pjc"
        exit 1
    }
    Write-Ok "Marketplace 경로: $marketplacePath"
} else {
    Write-Ok "GitHub marketplace: $GitHub"
}

# ---- 3. 제거 모드 ----
if ($Uninstall) {
    Write-Section "Uninstalling pjc Plugin"

    try {
        & claude plugin uninstall pjc 2>&1 | ForEach-Object { Write-Info $_ }
        Write-Ok "Plugin uninstalled"
    } catch {
        Write-Warn "Plugin 제거 실패 (이미 제거됨일 수 있음)"
    }

    try {
        & claude plugin marketplace remove pjc-harness 2>&1 | ForEach-Object { Write-Info $_ }
        Write-Ok "Marketplace removed"
    } catch {
        Write-Warn "Marketplace 제거 실패 (이미 제거됨일 수 있음)"
    }

    Write-Host ""
    Write-Host "Uninstall complete." -ForegroundColor Green
    Write-Host ""
    return
}

# ---- 4. Claude Code 실행 중인지 확인 (참고용) ----
$claudeProc = Get-Process -Name claude -ErrorAction SilentlyContinue
if ($claudeProc) {
    Write-Section "Notice"
    Write-Warn "Claude Code REPL이 현재 실행 중입니다."
    Write-Info "설치 후 변경 사항을 반영하려면 종료 후 다시 시작하세요."
}

# ---- 5. 기존 설치 자동 감지 + 재설치 (기본 동작) ----
$cacheDir = Join-Path $homeBase ".claude/plugins/cache/pjc-harness"
$marketplaceCacheDir = Join-Path $homeBase ".claude/plugins/marketplaces/pjc-harness"

$existingInstall = (Test-Path -LiteralPath $cacheDir) -or (Test-Path -LiteralPath $marketplaceCacheDir)

if ($existingInstall) {
    if ($KeepExisting) {
        Write-Section "Existing Installation Detected (Keeping)"
        Write-Info "기존 설치를 유지합니다 (-KeepExisting 옵션)."
        Write-Info "변경 사항이 반영되지 않을 수 있습니다."
    } else {
        Write-Section "Existing Installation Detected — Auto Reinstall"
        Write-Info "기존 설치를 발견했습니다. 자동으로 재설치를 진행합니다."

        # 5-1. plugin uninstall
        try {
            & claude plugin uninstall pjc 2>&1 | ForEach-Object { Write-Info "  $_" }
            Write-Ok "Plugin uninstalled"
        } catch {
            Write-Warn "Plugin 제거 실패 (이미 제거됨일 수 있음)"
        }

        # 5-2. marketplace remove
        try {
            & claude plugin marketplace remove pjc-harness 2>&1 | ForEach-Object { Write-Info "  $_" }
            Write-Ok "Marketplace removed"
        } catch {
            Write-Warn "Marketplace 제거 실패 (이미 제거됨일 수 있음)"
        }

        # 5-3. 캐시 디렉터리 강제 정리 (stale cache 버그 회피)
        if (Test-Path -LiteralPath $cacheDir) {
            try {
                Remove-Item -Recurse -Force -LiteralPath $cacheDir -ErrorAction Stop
                Write-Ok "Cache 정리: $cacheDir"
            } catch {
                Write-Warn "Cache 디렉터리 삭제 실패: $($_.Exception.Message)"
            }
        }
        if (Test-Path -LiteralPath $marketplaceCacheDir) {
            try {
                Remove-Item -Recurse -Force -LiteralPath $marketplaceCacheDir -ErrorAction Stop
                Write-Ok "Marketplace cache 정리: $marketplaceCacheDir"
            } catch {
                Write-Warn "Marketplace cache 삭제 실패: $($_.Exception.Message)"
            }
        }

        Write-Ok "기존 설치 정리 완료. 새 설치 진행."
    }
} else {
    Write-Section "Fresh Install"
    Write-Info "기존 설치 없음. 새로 설치합니다."
}

# ---- 6. Marketplace 추가 ----
Write-Section "Adding Marketplace"

# GitHub 모드면 repo를, 아니면 이 폴더(로컬)를 marketplace 소스로 사용
if ($GitHub) {
    $marketplaceSource = $GitHub
    Write-Info "GitHub 모드: $GitHub (clone 캐시 방식 - 로컬 폴더 불필요)"
} else {
    $marketplaceSource = $marketplacePath
    Write-Info "로컬 모드: $marketplacePath"
    Write-Warn "이 폴더가 plugin 본체로 참조됩니다. 삭제/이동하면 plugin이 깨집니다."
    Write-Info "원본 의존을 없애려면: .\install.ps1 -GitHub jongcheol-pak/claude-harness-pjc"
}

try {
    $addOutput = & claude plugin marketplace add $marketplaceSource 2>&1 | Out-String
    Write-Info $addOutput.Trim()
    # 네이티브 exe의 비0 종료는 throw되지 않으므로 $LASTEXITCODE로 직접 감지 (거짓 성공 방지)
    if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }
    Write-Ok "Marketplace 'pjc-harness' added"
} catch {
    # 이미 추가된 경우일 수 있음 (출력/메시지에 already 포함 시 비치명적)
    if ("$addOutput $($_.Exception.Message)" -match "already") {
        Write-Warn "Marketplace 이미 추가되어 있음 (계속 진행)"
    } else {
        Write-Err "Marketplace 추가 실패: $($_.Exception.Message)"
        exit 1
    }
}

# ---- 7. Plugin 설치 ----
Write-Section "Installing Plugin"

try {
    $installOutput = & claude plugin install pjc@pjc-harness --scope $Scope 2>&1 | Out-String
    Write-Info $installOutput.Trim()
    # 네이티브 exe의 비0 종료는 throw되지 않으므로 $LASTEXITCODE로 직접 감지 (거짓 성공 방지)
    if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }
    Write-Ok "Plugin 'pjc' installed (scope: $Scope)"
} catch {
    if ("$installOutput $($_.Exception.Message)" -match "already") {
        Write-Warn "Plugin 이미 설치되어 있음. 업데이트를 원하면:"
        Write-Info "  claude plugin update pjc"
    } else {
        Write-Err "Plugin 설치 실패: $($_.Exception.Message)"
        exit 1
    }
}

# ---- 7-1. Plugin 활성화 (방어적 명시 호출) ----
# install이 기본 자동 enable이지만, 사용자 settings.json의 enabledPlugins에
# 명시적으로 false로 남아 있는 경우 무시되지 않으므로 명시 호출.
try {
    $enableOutput = & claude plugin enable pjc@pjc-harness 2>&1 | Out-String
    if ($enableOutput.Trim()) { Write-Info $enableOutput.Trim() }
    if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }
    Write-Ok "Plugin 'pjc' enabled"
} catch {
    Write-Warn "Plugin enable 실패 (이미 enabled일 수 있음): $($_.Exception.Message)"
    Write-Info "수동 확인: claude 시작 후 /plugin list"
}

# ---- 8. 검증 ----
if (-not $SkipVerification) {
    Write-Section "Verification"

    try {
        $listOutput = & claude plugin list 2>&1 | Out-String
        if ($listOutput -match "pjc") {
            Write-Ok "pjc plugin 등록 확인"
        } else {
            Write-Warn "Plugin list에서 pjc를 찾지 못했습니다."
            Write-Info "수동 확인: claude plugin list"
        }
    } catch {
        Write-Warn "검증 실패 (수동 확인 권장): claude plugin list"
    }
}

# ---- 9. 실행 정책 안내 ----
Write-Section "PowerShell Execution Policy"

$policy = Get-ExecutionPolicy -Scope CurrentUser
Write-Info "Current user policy: $policy"

if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Warn "Hook 스크립트가 차단될 수 있습니다."
    Write-Info "권장: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned"
    Write-Info "(hooks.json은 이미 -ExecutionPolicy Bypass를 포함하므로 그대로 두어도 동작)"
} else {
    Write-Ok "Execution policy 호환: $policy"
}

# ---- 10. AGENTS.md 안내 ----
Write-Section "Next Steps"

Write-Host "  각 프로젝트의 루트에 AGENTS.md가 필요합니다 — 빌드·테스트 명령이 거기서 옵니다." -ForegroundColor White
Write-Host "  직접 만들 필요는 없습니다:" -ForegroundColor White
Write-Host ""
Write-Host "    cd C:\Repos\<your-project>" -ForegroundColor Yellow
Write-Host "    claude" -ForegroundColor Yellow
Write-Host "    > 무엇이든 계획을 요청하세요            # pjc:plan Step 1이 AGENTS.md 부재를" -ForegroundColor Yellow
Write-Host "                                            #   감지하면 최소 골격으로 만듭니다" -ForegroundColor Yellow
Write-Host ""
Write-Host "  빈 절은 작업하며 채워집니다 — 빌드·테스트 명령을 실제로 돌리면" -ForegroundColor DarkGray
Write-Host "  hook이 기록을 제안하고 /pjc:record-project-fact가 받습니다." -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Claude Code 사용:" -ForegroundColor White
Write-Host ""
Write-Host "    claude                          # 시작" -ForegroundColor Yellow
Write-Host "    /plugin list                    # pjc 확인" -ForegroundColor Yellow
Write-Host "    /                               # /pjc: 시작 명령들 자동완성" -ForegroundColor Yellow
Write-Host ""
Write-Host "  주요 명령:" -ForegroundColor White
Write-Host "    /pjc:plan <설명>" -ForegroundColor Yellow
Write-Host "    /pjc:implement <T번호>" -ForegroundColor Yellow
Write-Host "    /pjc:pjc-systematic-debugging <증상>" -ForegroundColor Yellow
Write-Host ""

Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""

Write-Host "다음 단계 (Claude Code 시작 후):" -ForegroundColor Cyan
Write-Host "  /plugin list                  # pjc Harness가 Enabled인지 확인" -ForegroundColor White
Write-Host "  /reload-plugins               # 필요 시 새 변경 반영" -ForegroundColor White
Write-Host ""
Write-Host "skill이 자동 실행 안 되는 경우:" -ForegroundColor Cyan
Write-Host "  /plugin list 에서 Disabled로 보이면 - /plugin enable pjc@pjc-harness" -ForegroundColor White
Write-Host "  REPL 재시작 - claude 종료 후 다시 실행" -ForegroundColor White
Write-Host "  마지막 수단 - notepad `$env:USERPROFILE\.claude\settings.json" -ForegroundColor White
Write-Host "                enabledPlugins 의 pjc 항목을 true로 또는 제거" -ForegroundColor White
Write-Host ""

if ($claudeProc) {
    Write-Warn "실행 중이던 Claude Code를 재시작하세요."
    Write-Host ""
}
