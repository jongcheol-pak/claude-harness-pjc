# warn-version-drift.ps1 — SessionStart: 설치본 ↔ 하네스 레포 버전 드리프트 경고 (비차단) — 근거는 `rules/version-drift-rationale.md`의 「§1 warn-version-drift.ps1 — SessionStart: 설치본 ↔ 하네스 레포 버전 드리프트 경고 (비차단)」

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

    # ---- 릴리즈 누락 감지 — 근거는 `rules/version-drift-rationale.md`의 「§2 # ---- 릴리즈 누락 감지」
    try {
        Push-Location -LiteralPath $cwd
        try {
            # `-join` 필수 — git show는 **줄 배열**을 반환한다 — 근거는 `rules/version-drift-rationale.md`의 「§3 `-join` 필수 — git show는 **줄 배열**을 반환한다」
            $pushedJson = (& git show origin/main:plugins/pjc/.claude-plugin/plugin.json 2>$null) -join "`n"
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($pushedJson)) {
                $pushedVer = $null
                try { $pushedVer = ($pushedJson | ConvertFrom-Json).version } catch { $pushedVer = $null }
                if (-not [string]::IsNullOrWhiteSpace($pushedVer)) {
                    $tag = & git tag -l "v$pushedVer" 2>$null
                    if ($LASTEXITCODE -eq 0 -and [string]::IsNullOrWhiteSpace(($tag -join ''))) {
                        # 로컬에 없다 → 원격 확인. — 근거는 `rules/version-drift-rationale.md`의 「§4 로컬에 없다 → 원격 확인.」
                        $env:GIT_TERMINAL_PROMPT = '0'
                        $remoteTag = & git ls-remote --tags origin "v$pushedVer" 2>$null
                        $remoteExit = $LASTEXITCODE   # 즉시 캡처 — 아래 문자열 연산이 값을 덮어쓰기 전에
                        if ($remoteExit -eq 0 -and [string]::IsNullOrWhiteSpace(($remoteTag -join ''))) {
                            Write-Output "[pjc 릴리즈 누락] origin/main에 v${pushedVer}가 올라가 있는데 태그 v${pushedVer}를 로컬·원격 어디에서도 찾지 못했습니다 — 이 레포 규약은 '버전 업 커밋 push 뒤 곧바로 릴리즈 발행'입니다. 발행: gh release create v$pushedVer --target <full-sha> (short sha는 거부됩니다)."
                        }
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
