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
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로가 깨져 cwd 기준 plugin.json 탐색이 어긋난다. 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

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

    # ---- 릴리즈 누락 감지 (v1.158.0) ----
    # 왜: 이 레포의 작업 규약은 "버전 업 커밋을 push한 뒤 곧바로 GitHub 릴리즈 발행"인데, 그것을 강제하는
    #   신호가 없어 v1.156.0·v1.157.0이 연속으로 발행되지 않은 채 넘어갈 뻔했다(사용자가 물어서 발견).
    #   push·병합에는 warn-external-ops 경고가 있지만 "버전을 올렸는데 태그가 없다"를 보는 것은 없었다.
    # 판정 기준은 **워킹트리 버전이 아니라 push된 버전**이다 — 개발 중(버전만 올리고 작업 중)에는 태그가
    #   없는 것이 정상이라, 워킹트리로 판정하면 매 세션 오탐이 된다. origin/main에 올라간 plugin.json의
    #   버전에 해당하는 태그가 없을 때만 알린다(그 시점이 규약상 릴리즈 의무가 발생한 시점이다).
    # 안전: git이 없거나 origin/main이 없거나(미push 레포) 어느 단계든 실패하면 조용히 통과(fail-open).
    # ⚠ 출력 문구의 변수는 `${pushedVer}`처럼 **중괄호 필수** — 한글 조사가 붙으면(`v$pushedVer가`)
    #   PowerShell이 `$pushedVer가`를 변수명으로 해석해 빈 값이 된다(이 검사 구현 중 실제로 밟았다).
    # 배치: **설치본 버전 판정보다 앞**이다 — 두 검사는 독립인데 뒤에 두면 `CLAUDE_PLUGIN_ROOT` 부재
    #   (설치본 없이 레포만 연 세션 등)에서 조기 exit에 막혀 도달하지 못한다(구현 중 실측).
    try {
        Push-Location -LiteralPath $cwd
        try {
            # `-join` 필수: git show는 **줄 배열**을 반환하는데, 배열을 그대로 ConvertFrom-Json에
            #   파이프하면 PowerShell 5.1(AGENTS.md가 명시한 폴백 런타임)에서 줄마다 개별 JSON으로
            #   파싱을 시도해 실패한다(7은 누적 처리라 통과 — 런타임에 따라 결과가 갈리는 형태다).
            $pushedJson = (& git show origin/main:plugins/pjc/.claude-plugin/plugin.json 2>$null) -join "`n"
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($pushedJson)) {
                $pushedVer = $null
                try { $pushedVer = ($pushedJson | ConvertFrom-Json).version } catch { $pushedVer = $null }
                if (-not [string]::IsNullOrWhiteSpace($pushedVer)) {
                    $tag = & git tag -l "v$pushedVer" 2>$null
                    if ($LASTEXITCODE -eq 0 -and [string]::IsNullOrWhiteSpace(($tag -join ''))) {
                        Write-Output "[pjc 릴리즈 누락] origin/main에 v${pushedVer}가 올라가 있는데 태그 v${pushedVer}가 없습니다 — 이 레포 규약은 '버전 업 커밋 push 뒤 곧바로 릴리즈 발행'입니다. 발행: gh release create v$pushedVer --target <full-sha> (short sha는 거부됩니다)."
                    }
                }
            }
        } finally { Pop-Location }
    } catch {}

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
