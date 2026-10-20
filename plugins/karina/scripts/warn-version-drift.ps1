# warn-version-drift.ps1 — SessionStart: 설치본 ↔ 하네스 레포 버전 드리프트 경고 (비차단) — 근거는 `rules/version-drift-rationale.md` §1

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
    $repoPluginJson = Join-Path $cwd 'plugins/karina/.claude-plugin/plugin.json'
    $repoMarketJson = Join-Path $cwd '.claude-plugin/marketplace.json'
    if (-not (Test-Path -LiteralPath $repoPluginJson)) { exit 0 }
    if (-not (Test-Path -LiteralPath $repoMarketJson)) { exit 0 }

    # ---- 릴리즈 누락 감지 — 근거는 `rules/version-drift-rationale.md` §2
    try {
        Push-Location -LiteralPath $cwd
        try {
            # `-join` 필수 — git show는 **줄 배열**을 반환한다 — 근거는 `rules/version-drift-rationale.md` §3
            $pushedJson = (& git show origin/main:plugins/karina/.claude-plugin/plugin.json 2>$null) -join "`n"
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($pushedJson)) {
                $pushedVer = $null
                try { $pushedVer = ($pushedJson | ConvertFrom-Json).version } catch { $pushedVer = $null }
                if (-not [string]::IsNullOrWhiteSpace($pushedVer)) {
                    # 원격에서 이미 찾은 태그는 기억해 두고 다시 묻지 않는다 — 「없음」은 기억하지 않는다. 파일 내용은 태그 커밋 sha(빈 파일은 종전 형식).
                    $vdHome = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
                    $releasedDir = Join-Path $vdHome '.claude/.state/version-drift'
                    $releasedMark = Join-Path $releasedDir ('released-v' + $pushedVer)
                    $hasMark = Test-Path -LiteralPath $releasedMark
                    # 미배포 판정의 기준점(태그 커밋) — 로컬 태그 → 캐시 → 원격 순 — 근거는 `rules/version-drift-rationale.md` §5
                    $tagSha = ((& git rev-parse -q --verify "refs/tags/v$pushedVer^{commit}" 2>$null) -join '').Trim()
                    if (-not $tagSha -and $hasMark) {
                        $markText = ((Get-Content -LiteralPath $releasedMark -Raw -ErrorAction SilentlyContinue) -join '').Trim()
                        if ($markText -match '^[0-9a-f]{40}$') { $tagSha = $markText }
                    }
                    if (-not $tagSha) {
                        # 로컬에 없다 → 원격 확인. — 근거는 `rules/version-drift-rationale.md` §4
                        $env:GIT_TERMINAL_PROMPT = '0'
                        $remoteTag = @(& git ls-remote --tags origin "v$pushedVer" "v$pushedVer^{}" 2>$null)
                        $remoteExit = $LASTEXITCODE   # 즉시 캡처 — 아래 문자열 연산이 값을 덮어쓰기 전에
                        if ($remoteExit -eq 0) {
                            $peel = $remoteTag | Where-Object { $_ -match "\srefs/tags/v$([regex]::Escape($pushedVer))\^\{\}$" } | Select-Object -First 1
                            $plain = $remoteTag | Where-Object { $_ -match "\srefs/tags/v$([regex]::Escape($pushedVer))$" } | Select-Object -First 1
                            $line = if ($peel) { $peel } else { $plain }
                            if (-not $line) {
                                if (-not $hasMark) {
                                    Write-Output "[karina 릴리즈 누락] origin/main에 v${pushedVer}가 올라가 있는데 태그 v${pushedVer}를 로컬·원격 어디에서도 찾지 못했습니다 — 이 레포 규약은 '버전 전용 PR merge(또는 버전 커밋 push) 뒤 곧바로 릴리즈 발행'입니다. 발행: gh release create v$pushedVer --target <main 에 올라간 버전 커밋 — 버전 전용 PR 이면 그 merge 커밋 — 의 full-sha> (short sha는 거부됩니다)."
                                }
                            } else {
                                $tagSha = ($line -split '\s+')[0]
                                # 원격에 있다 — 다른 버전의 기록을 지우고 이 버전의 태그 커밋 sha 만 남긴다(캐시 실패는 삼킨다, 비차단).
                                try {
                                    New-Item -ItemType Directory -Path $releasedDir -Force -ErrorAction Stop | Out-Null
                                    Get-ChildItem -LiteralPath $releasedDir -Filter 'released-v*' -File -ErrorAction Stop | Remove-Item -Force -ErrorAction SilentlyContinue
                                    Set-Content -LiteralPath $releasedMark -Value $tagSha -NoNewline -ErrorAction Stop
                                } catch {}
                            }
                        }
                    }
                    # 미배포 — 태그 커밋 뒤 origin/main 의 plugins/ 커밋. sha 를 못 얻거나 그 커밋이 로컬에 없으면 건너뛴다(폴백 없음).
                    if ($tagSha) {
                        & git cat-file -e "$tagSha^{commit}" 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            $undeployed = @(& git log --format=%h "$tagSha..origin/main" -- plugins/ 2>$null | Where-Object { $_ })
                            if ($LASTEXITCODE -eq 0 -and $undeployed.Count -gt 0) {
                                Write-Output "[karina 미배포] 마지막 릴리즈 v${pushedVer}(태그 커밋 $($tagSha.Substring(0,8))) 뒤 origin/main 에 plugins/ 커밋 $($undeployed.Count)건이 버전·릴리즈 없이 올라가 있습니다 — 설치본 사용자에게 가지 않은 변경입니다. 버전 전용 PR 로 버전을 올린 뒤 릴리즈를 발행하세요(docs/harness-conventions.md 「판정 시점」)."
                            }
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
        Write-Output "[karina 버전 드리프트] 설치본 v$selfVer ≠ 레포 v$repoVer — 재설치 전까지 이 세션의 hook·스킬은 설치본(v$selfVer) 기준으로 동작합니다. 레포 변경분을 세션에 반영하려면 재설치가 필요합니다 (커밋·push 뒤 /plugin update — 사용자 실행)."
    }

    exit 0
} catch {
    exit 0
}
