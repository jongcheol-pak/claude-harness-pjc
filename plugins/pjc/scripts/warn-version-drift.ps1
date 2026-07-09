# warn-version-drift.ps1 — SessionStart: 설치본 ↔ 하네스 레포 버전 드리프트 경고 (비차단)
#
# 왜: 하네스 레포에서 plugin.json 버전을 올려도 재설치 전까지 설치 캐시는 구버전으로 동작한다.
#   이 드리프트를 사람이 notes.md로 수동 추적하던 것을(v1.101.0~1.104.0 반복 pain point),
#   세션 시작 시점에 기계가 1줄 경고로 알린다 — "레포에는 고쳤는데 세션은 구 동작" 혼동 제거.
# 어떻게: stdin(SessionStart JSON)의 cwd가 하네스 레포일 때만(마커 2종 동시 실재로 판정 —
#   임의 레포 오탐 방지), 레포 plugin.json 버전과 자기 설치본 버전($env:CLAUDE_PLUGIN_ROOT의
#   plugin.json — 다중 버전 캐시·레거시 레이아웃과 무관하게 자기 자신이 곧 활성 설치본)을 비교한다.
# 안전: 경고 hook이므로 모든 실패 경로는 조용히 exit 0 (fail-open — 세션 시작을 절대 막지 않는다).
#   stdout은 SessionStart 규약상 세션 컨텍스트로 주입된다(exit 0).

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

try {
    # ---- 입력 파싱 (cwd) ----
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $inp = $null
    try { $inp = $raw | ConvertFrom-Json } catch { exit 0 }
    $cwd = [string]$inp.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { exit 0 }

    # ---- 하네스 레포 판정 (마커 2종 동시 실재 — 둘 중 하나라도 없으면 즉시 종료, 비레포 비용 최소화) ----
    $repoPluginJson = Join-Path $cwd 'plugins/pjc/.claude-plugin/plugin.json'
    $repoMarketJson = Join-Path $cwd '.claude-plugin/marketplace.json'
    if (-not (Test-Path -LiteralPath $repoPluginJson)) { exit 0 }
    if (-not (Test-Path -LiteralPath $repoMarketJson)) { exit 0 }

    # ---- 자기(설치본) 버전 ----
    $root = $env:CLAUDE_PLUGIN_ROOT
    if ([string]::IsNullOrWhiteSpace($root)) { exit 0 }
    $selfPluginJson = Join-Path $root '.claude-plugin/plugin.json'
    if (-not (Test-Path -LiteralPath $selfPluginJson)) { exit 0 }

    $repoVer = $null; $selfVer = $null
    try { $repoVer = (Get-Content -LiteralPath $repoPluginJson -Raw | ConvertFrom-Json).version } catch { exit 0 }
    try { $selfVer = (Get-Content -LiteralPath $selfPluginJson -Raw | ConvertFrom-Json).version } catch { exit 0 }
    if ([string]::IsNullOrWhiteSpace($repoVer) -or [string]::IsNullOrWhiteSpace($selfVer)) { exit 0 }

    if ($repoVer -ne $selfVer) {
        # stdout → 세션 컨텍스트 주입 (SessionStart exit 0 규약)
        Write-Output "[pjc 버전 드리프트] 설치본 v$selfVer ≠ 레포 v$repoVer — 재설치 전까지 이 세션의 hook·스킬은 설치본(v$selfVer) 기준으로 동작합니다. 레포 변경분을 세션에 반영하려면 재설치가 필요합니다 (install.ps1 — 사용자 실행)."
    }
    exit 0
} catch {
    exit 0
}
