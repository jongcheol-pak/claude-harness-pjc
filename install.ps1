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

# 색상 헬퍼
function Write-Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)      { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t)    { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Write-Err($t)     { Write-Host "  [X]  $t" -ForegroundColor Red }
function Write-Info($t)    { Write-Host "  $t" -ForegroundColor Gray }

Write-Host ""
Write-Host "pjc Claude Code Harness - Plugin Installer" -ForegroundColor Cyan
Write-Host ""

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
$marketplaceManifest = Join-Path $marketplacePath ".claude-plugin\marketplace.json"

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
    Write-Info "토글 상태 파일은 남아있습니다. 완전 제거하려면:"
    Write-Info "  Remove-Item -Recurse `"`$env:USERPROFILE\.claude\.disabled`""
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

# ---- 5. 기존 설치 자동 감지 + 재설치 (1.11.1+ 기본 동작) ----
$cacheDir = Join-Path $env:USERPROFILE ".claude\plugins\cache\pjc-harness"
$marketplaceCacheDir = Join-Path $env:USERPROFILE ".claude\plugins\marketplaces\pjc-harness"

$existingInstall = (Test-Path -LiteralPath $cacheDir) -or (Test-Path -LiteralPath $marketplaceCacheDir)

if ($existingInstall) {
    if ($KeepExisting) {
        Write-Section "Existing Installation Detected (Keeping)"
        Write-Info "기존 설치를 유지합니다 (-KeepExisting 옵션)."
        Write-Info "변경 사항이 반영되지 않을 수 있습니다."
    } else {
        Write-Section "Existing Installation Detected — Auto Reinstall"
        Write-Info "기존 설치를 발견했습니다. 자동으로 재설치를 진행합니다."
        Write-Info "(토글 상태(.disabled)는 보존됩니다.)"

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

$templatesDir = Join-Path $marketplacePath "plugins\pjc\skills\bootstrap-agents-md\templates"
if (Test-Path $templatesDir) {
    Write-Host "  각 프로젝트의 루트에 AGENTS.md를 배치하세요." -ForegroundColor White
    Write-Host "  자동 생성 (권장):" -ForegroundColor White
    Write-Host ""
    Write-Host "    cd C:\Repos\<your-project>" -ForegroundColor Yellow
    Write-Host "    claude" -ForegroundColor Yellow
    Write-Host "    > /pjc:bootstrap-agents-md   # stack 자동 감지 + AGENTS.md 생성" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  또는 수동 (template에서 복사):" -ForegroundColor White
    Write-Host ""
    Write-Host "    # 사용 가능 templates:" -ForegroundColor DarkGray
    Get-ChildItem -Path $templatesDir -Filter "*.md" | ForEach-Object {
        Write-Host "    #   $($_.Name)" -ForegroundColor DarkGray
    }
    Write-Host "    Copy-Item `"$templatesDir\<stack>.md`" .\AGENTS.md" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Claude Code 사용:" -ForegroundColor White
Write-Host ""
Write-Host "    claude                          # 시작" -ForegroundColor Yellow
Write-Host "    /plugin list                    # pjc 확인" -ForegroundColor Yellow
Write-Host "    /                               # /pjc: 시작 명령들 자동완성" -ForegroundColor Yellow
Write-Host ""
Write-Host "  주요 명령:" -ForegroundColor White
Write-Host "    /pjc:plan-feature <설명>" -ForegroundColor Yellow
Write-Host "    /pjc:implement-task <T번호>" -ForegroundColor Yellow
Write-Host "    /pjc:pjc-systematic-debugging <증상>" -ForegroundColor Yellow
Write-Host "    /pjc:harness-toggle <hook> <on|off|toggle|status>" -ForegroundColor Yellow
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
