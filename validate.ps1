# validate.ps1 — pjc plugin 설치 후 정상 동작 검증
#
# 사용법:
#   .\validate.ps1
#
# 검증 항목:
#   1. plugin 디렉터리 존재
#   2. plugin.json + marketplace.json 유효
#   3. skill 8개 모두 등록
#   4. agent 6개 모두 등록
#   5. hook 5개 모두 등록 + BOM 확인
#   6. 모든 ps1 파일에 UTF-8 BOM
#   7. JSON 파일 파싱 가능
#   8. 토글 디렉터리 접근 가능

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$pluginRoot = Join-Path $env:USERPROFILE ".claude\plugins\cache\pjc-harness\plugins\pjc"
$marketplaceRoot = Join-Path $env:USERPROFILE ".claude\plugins\marketplaces\pjc-harness"

$pass = 0
$fail = 0
$warnings = @()

function Test-Item-Exists {
    param([string]$Path, [string]$Description)
    if (Test-Path -LiteralPath $Path) {
        Write-Host "  [OK]   $Description" -ForegroundColor Green
        $script:pass++
        return $true
    } else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        Write-Host "         경로: $Path" -ForegroundColor DarkGray
        $script:fail++
        return $false
    }
}

function Test-Json-Valid {
    param([string]$Path, [string]$Description)
    try {
        $null = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        Write-Host "  [OK]   $Description" -ForegroundColor Green
        $script:pass++
        return $true
    } catch {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        Write-Host "         오류: $_" -ForegroundColor DarkGray
        $script:fail++
        return $false
    }
}

function Test-Ps1-Bom {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return $true
    }
    return $false
}

Write-Host "=== pjc plugin 검증 시작 ===" -ForegroundColor Cyan
Write-Host ""

# 1. Plugin 디렉터리 구조
Write-Host "1. Plugin 디렉터리 구조" -ForegroundColor Yellow
Test-Item-Exists $pluginRoot "plugin 루트 디렉터리" | Out-Null
Test-Item-Exists (Join-Path $pluginRoot ".claude-plugin\plugin.json") "plugin.json" | Out-Null
Test-Item-Exists $marketplaceRoot "marketplace 루트 디렉터리" | Out-Null
Write-Host ""

# 2. JSON 파일 유효성
Write-Host "2. JSON 파일 유효성" -ForegroundColor Yellow
Test-Json-Valid (Join-Path $pluginRoot ".claude-plugin\plugin.json") "plugin.json 파싱" | Out-Null
Test-Json-Valid (Join-Path $pluginRoot "hooks\hooks.json") "hooks.json 파싱" | Out-Null
Write-Host ""

# 3. Skills (expected 목록 존재 + 미등록 탐지 — 카운트는 목록에서 산출)
$skills = @('plan-feature', 'implement-task', 'pjc-systematic-debugging', 'add-viewmodel', 'add-domain-service', 'harness-toggle', 'bootstrap-agents-md', 'llm-wiki')
Write-Host "3. Skills $($skills.Count)개" -ForegroundColor Yellow
foreach ($s in $skills) {
    $skillPath = Join-Path $pluginRoot "skills\$s\SKILL.md"
    Test-Item-Exists $skillPath "skill: $s" | Out-Null
}
# 실제 skills/ 에 SKILL.md가 있는데 expected 목록에 없으면 경고 (skill 추가 후 validate 갱신 누락 포착)
$actualSkills = Get-ChildItem -Path (Join-Path $pluginRoot 'skills') -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    Select-Object -ExpandProperty Name
foreach ($a in $actualSkills) {
    if ($skills -notcontains $a) {
        Write-Host "         [WARN] validate 미등록 skill: $a (이 목록에 추가 필요)" -ForegroundColor DarkYellow
        $script:warnings += "validate 미등록 skill: $a"
    }
}
Write-Host ""

# 4. Agents (expected 목록 존재 + 미등록 탐지)
$agents = @('plan-reviewer', 'spec-compliance-reviewer', 'code-quality-reviewer', 'explorer', 'plan-completion-reviewer', 'spec-prefilter')
Write-Host "4. Agents $($agents.Count)개" -ForegroundColor Yellow
foreach ($a in $agents) {
    $agentPath = Join-Path $pluginRoot "agents\$a.md"
    Test-Item-Exists $agentPath "agent: $a" | Out-Null
}
$actualAgents = Get-ChildItem -Path (Join-Path $pluginRoot 'agents') -Filter '*.md' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty BaseName
foreach ($a in $actualAgents) {
    if ($agents -notcontains $a) {
        Write-Host "         [WARN] validate 미등록 agent: $a (이 목록에 추가 필요)" -ForegroundColor DarkYellow
        $script:warnings += "validate 미등록 agent: $a"
    }
}
Write-Host ""

# 5. Hooks (expected 목록 존재 + BOM + 미등록 탐지)
$hooks = @('block-destructive.ps1', 'require-plan-for-write.ps1', 'check-utf8-and-lines.ps1', 'require-evidence.ps1', 'impact-warn.ps1')
$knownHelpers = @('harness-toggle.ps1')   # hook이 아닌 scripts/ 내 헬퍼 (미등록 탐지에서 제외)
Write-Host "5. Hooks $($hooks.Count)개" -ForegroundColor Yellow
foreach ($h in $hooks) {
    $hookPath = Join-Path $pluginRoot "scripts\$h"
    if (Test-Item-Exists $hookPath "hook: $h") {
        if (-not (Test-Ps1-Bom $hookPath)) {
            Write-Host "         [WARN] BOM 없음 — 한글 인코딩 문제 가능" -ForegroundColor DarkYellow
            $script:warnings += "Hook $h 에 UTF-8 BOM 없음"
        }
    }
}
# scripts/ 에 hook도 known helper도 아닌 .ps1이 있으면 경고 (hook 추가 후 validate/hooks.json 갱신 누락 포착)
$actualScripts = Get-ChildItem -Path (Join-Path $pluginRoot 'scripts') -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Name
foreach ($s in $actualScripts) {
    if (($hooks -notcontains $s) -and ($knownHelpers -notcontains $s)) {
        Write-Host "         [WARN] validate 미등록 스크립트: $s (hook이면 목록·hooks.json에 추가 필요)" -ForegroundColor DarkYellow
        $script:warnings += "validate 미등록 스크립트: $s"
    }
}
Write-Host ""

# 6. Harness toggle 헬퍼
Write-Host "6. Harness toggle 헬퍼" -ForegroundColor Yellow
$togglePath = Join-Path $pluginRoot "scripts\harness-toggle.ps1"
if (Test-Item-Exists $togglePath "harness-toggle.ps1") {
    if (-not (Test-Ps1-Bom $togglePath)) {
        Write-Host "         [WARN] BOM 없음" -ForegroundColor DarkYellow
        $script:warnings += "harness-toggle.ps1 에 UTF-8 BOM 없음"
    }
}
Write-Host ""

# 7. 토글 메커니즘 (hook 토글)
Write-Host "7. 토글 메커니즘" -ForegroundColor Yellow
$disabledDir = Join-Path $env:USERPROFILE ".claude\.disabled"
if (Test-Path -LiteralPath $disabledDir) {
    $disabled = Get-ChildItem -LiteralPath $disabledDir -ErrorAction SilentlyContinue
    if ($disabled.Count -gt 0) {
        Write-Host "  [INFO] 현재 비활성화된 hook:" -ForegroundColor Cyan
        foreach ($d in $disabled) {
            Write-Host "         - $($d.Name)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [OK]   토글 디렉터리 존재, 모든 hook 활성" -ForegroundColor Green
    }
} else {
    Write-Host "  [OK]   토글 디렉터리 없음 (모든 hook 활성, 정상)" -ForegroundColor Green
}
Write-Host ""

# 7-1. Plugin Enabled 상태 검증 (Claude Code 인식 여부)
Write-Host "7-1. Plugin Enabled 상태" -ForegroundColor Yellow
$userSettings = Join-Path $env:USERPROFILE ".claude\settings.json"
$enableStatus = "unknown"
if (Test-Path -LiteralPath $userSettings) {
    try {
        $settings = Get-Content -LiteralPath $userSettings -Raw | ConvertFrom-Json
        if ($settings.enabledPlugins) {
            $pjcKey = $settings.enabledPlugins.PSObject.Properties | Where-Object { $_.Name -match "^pjc(@|$)" }
            if ($pjcKey) {
                if ($pjcKey.Value -eq $true) {
                    $enableStatus = "enabled"
                    Write-Host "  [OK]   settings.json에 pjc enabled" -ForegroundColor Green
                    $script:pass++
                } elseif ($pjcKey.Value -eq $false) {
                    $enableStatus = "disabled"
                    Write-Host "  [FAIL] settings.json에 pjc가 false로 설정됨" -ForegroundColor Red
                    Write-Host "         해결: claude plugin enable pjc@pjc-harness" -ForegroundColor DarkGray
                    Write-Host "         또는 settings.json에서 해당 항목 제거" -ForegroundColor DarkGray
                    $script:fail++
                }
            }
        }
        if ($enableStatus -eq "unknown") {
            Write-Host "  [OK]   settings.json에 명시 없음 (기본 enabled 동작)" -ForegroundColor Green
            $script:pass++
        }
    } catch {
        Write-Host "  [WARN] settings.json 파싱 실패: $($_.Exception.Message)" -ForegroundColor DarkYellow
        $script:warnings += "settings.json 파싱 실패"
    }
} else {
    Write-Host "  [OK]   settings.json 없음 (기본 enabled 동작)" -ForegroundColor Green
    $script:pass++
}
Write-Host ""

# 8. bootstrap-agents-md templates 디렉터리 (번들 내)
Write-Host "8. bootstrap-agents-md templates 디렉터리" -ForegroundColor Yellow
$templatesDir = Join-Path $pluginRoot "skills\bootstrap-agents-md\templates"
if (Test-Path -LiteralPath $templatesDir) {
    Write-Host "  [OK]   templates 디렉터리" -ForegroundColor Green
    $script:pass++

    $expectedTemplates = @('winui3.md', 'wpf.md', 'maui.md', 'dotnet.md', 'android.md', 'node-typescript.md', 'python.md', 'go.md', 'rust.md', 'generic.md')
    foreach ($t in $expectedTemplates) {
        $tPath = Join-Path $templatesDir $t
        if (Test-Path -LiteralPath $tPath) {
            Write-Host "  [OK]   template: $t" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "  [WARN] template 없음: $t" -ForegroundColor DarkYellow
            $script:warnings += "template $t 누락 — bootstrap 시 해당 stack에 generic 사용"
        }
    }
} else {
    Write-Host "  [WARN] templates 디렉터리 없음" -ForegroundColor DarkYellow
    $script:warnings += "skills\bootstrap-agents-md\templates 디렉터리 없음 — bootstrap-agents-md 동작 불가"
}
Write-Host ""

# 결과 요약
Write-Host "=== 검증 결과 ===" -ForegroundColor Cyan
Write-Host "  PASS: $pass" -ForegroundColor Green
Write-Host "  FAIL: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })
Write-Host "  WARN: $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -gt 0) { 'Yellow' } else { 'Green' })

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "경고 사항:" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  - $w" -ForegroundColor DarkYellow
    }
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "✅ plugin 설치 정상" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ plugin에 문제 있음. 위 FAIL 항목 확인 후 재설치 권장." -ForegroundColor Red
    Write-Host "   재설치: install.ps1 -Uninstall 후 install.ps1" -ForegroundColor DarkGray
    exit 1
}
