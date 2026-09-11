# guard-stale-docs.ps1 — PreToolUse/Bash: 커밋 직전 참고 문서 낡음 고지 (비차단) — 근거는 `rules/stale-docs-rationale.md`
#
# `guard-bash.ps1` 이 dot-source 한다. 별도 파일인 이유는 그 파일의 예산 여유가 264 B 뿐이고,
#   분리해 두어야 골든이 이 파일만 단독 프로브할 수 있기 때문이다(`guard-commit-secrets.ps1` 선례).
# 결과 객체 생성기 `New-HookResult` 는 `guard-commit-secrets.ps1` 에 있다 — 디스패처가 그쪽을
#   먼저 dot-source 하므로 여기서 다시 정의하지 않는다(정의가 둘이면 어느 쪽이 이겼는지 갈린다).

# 층 3: 스테이징 경로 → 기계가 못 재는 축. **내용 판정은 못 해도 해당 여부는 경로로 기계 판정된다** —
#   그래서 사람이 답할 질문을 기계가 내미는 형태로 둔다.
# ⚠ 이 표 자체가 「낡을 목록」이다(`check-stale-refs.py` 의 DEAD·`CRITICAL_POINTERS` 와 같은 계열).
#   그래서 아래 BASELINE 으로 총량을 묶어 증감이 diff 에 드러나게 한다 — 안 묶으면 이 회차가
#   그 결함을 고치면서 같은 결함을 하나 더 만든다.
$script:StaleAxisMap = @(
    @{ Pattern = '^docs/harness-conventions\.md$'
       Axis    = '산문 서술 — 이 문서가 코드 동작을 서술하는 자리는 어느 검사기도 재지 않는다' }
    @{ Pattern = '^AGENTS\.md$'
       Axis    = '외부 사실(권장 Claude Code 버전 등) — 레포 안에 대조 상대가 없다' }
    @{ Pattern = '^plugins/pjc/skills/llm-wiki/'
       Axis    = '위키 feature 서술 ↔ 코드 — 경로·심볼 실존은 lint 가 재지만 서술 내용은 표본 판정뿐이다' }
    @{ Pattern = '^docs/golden-runner\.md$'
       Axis    = '소요 시간 실측값 — 실행마다 편차가 커 자동 갱신 대상이 아니다' }
)
$script:StaleAxisBaseline = 4

function Get-StagedPaths {
    param([string]$RepoRoot)
    $out = @(& git -C $RepoRoot diff --cached --name-only 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }   # 판정 불가와 「0건」을 가른다
    # ⚠ `,` 를 빼면 **빈 배열이 `$null` 로 무너져** 「스테이징 0건」이 「판정 불가」로 뒤집힌다 —
    #   PowerShell 이 반환값의 빈 컬렉션을 풀어 버리기 때문이고, 위 `$null` 판정과 충돌한다.
    #   델타 음성 케이스(낡음 없음 무출력)가 이것을 잡았다.
    return ,@($out | Where-Object { $_ })
}

function Get-CountMismatchLines {
    <#
      층 1 잔여 — 축 ⑰ 불일치가 남은 채로 커밋되는 경로를 잡는다(`--fix` 를 안 돌린 경우).
      ⚠ **스테이징 경로와 무관하게 매니페스트 전수로 돈다** — 검증 매핑이 `lint-cases.json`·
        `relocation-cases.json`·`trigger-cases.json` 편집에는 축 ⑰을 부르지 않으므로, 이 자리가
        파일 패턴에 묶이면 그 3종의 드리프트가 커밋까지 통과한다.
    #>
    param([string]$RepoRoot)
    $checker = Join-Path $RepoRoot 'plugins/pjc/evals/check-harness-consistency.py'
    if (-not (Test-Path -LiteralPath $checker)) { return @() }
    $out = @(& python $checker --fix --dry-run 2>$null)
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($out | Where-Object { $_ -match '^\[WOULD-FIX\]' })
}

function Get-WikiLag {
    <#
      층 2 — 위키가 레포에 얼마나 뒤처졌는가. 허브 frontmatter 의 `synced_commit` 과 HEAD 사이
      커밋 수를 센다. **알아야 할 시점이 위키 세션 시작이 아니라 코드 세션의 커밋 직전이다** —
      시작 알림은 「이번 세션이 또 벌린 격차」를 원리상 못 알린다(그때는 아직 안 벌어졌다).
      lint §7-26 의 등급은 건드리지 않는다 — 그쪽은 WARN 으로 올려도 exit 0 이라 실효가 없다.
    #>
    param([string]$RepoRoot, [string]$HubPath)
    if ([string]::IsNullOrWhiteSpace($HubPath) -or -not (Test-Path -LiteralPath $HubPath)) { return $null }
    $head = (Get-Content -LiteralPath $HubPath -TotalCount 40 -ErrorAction SilentlyContinue) -join "`n"
    if ($head -notmatch '(?m)^synced_commit:\s*["'']?([0-9a-f]{7,40})') { return $null }
    $sha = $Matches[1]
    $n = & git -C $RepoRoot rev-list --count "$sha..HEAD" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }   # 그 sha 가 이 레포에 없으면 판정 불가
    return [int]$n
}

function Invoke-WarnStaleDocs {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    # 커밋 판정은 `guard-commit-secrets.ps1` 과 **같은 형태를 쓴다** — 두 검사가 같은 자리에서
    #   발화하므로 판정이 갈리면 한쪽만 도는 조합이 생긴다. **heredoc 스트립도 그 형태에
    #   포함된다** — 2026-09-11 한쪽만 고쳐 그 조합이 실제로 생겼다(완료 리뷰 MAJOR).
    $cmdForJudge = if (Get-Command Remove-HeredocBodyForJudge -ErrorAction SilentlyContinue) { Remove-HeredocBodyForJudge $cmd } else { $cmd }
    if ($cmdForJudge -notmatch 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { return New-HookResult }
    if ($cmdForJudge -match '--dry-run' -or $cmdForJudge -match '--help' -or $cmdForJudge -match '(^|\s)-h(\s|$)') { return New-HookResult }

    # **레포는 `$data.cwd` 기준으로 찾는다** — 프로세스 cwd 를 쓰면 안 된다. .NET 의
    #   `Environment.CurrentDirectory` 는 PowerShell 의 `Set-Location`·`Push-Location` 을
    #   따라가지 않아, 자식 프로세스가 엉뚱한 레포에서 `git` 을 돌린다(골든이 이것을 잡았다 —
    #   다른 레포의 스테이징을 이 커밋의 것으로 읽는 오판정이 실제로 났다).
    $cwd = [string]$data.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $cwd)) { return New-HookResult }
    $root = (& git -C $cwd rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) { return New-HookResult }
    # 하니스 레포에서만 돈다 — 마커 2종 동시 실재로 가른다(`warn-version-drift.ps1` 과 같은 판정).
    if (-not (Test-Path -LiteralPath (Join-Path $root 'plugins/pjc/.claude-plugin/plugin.json'))) { return New-HookResult }
    if (-not (Test-Path -LiteralPath (Join-Path $root '.claude-plugin/marketplace.json'))) { return New-HookResult }

    $lines = New-Object System.Collections.Generic.List[string]

    # --- 층 1: 남은 계수·버전 불일치 ---
    foreach ($m in (Get-CountMismatchLines -RepoRoot $root)) {
        $lines.Add('[낡음] ' + ($m -replace '^\[WOULD-FIX\]\s*', '') + ' — `check-harness-consistency.py --fix` 로 갱신하세요')
    }

    # --- 층 2: 러너 총계 기준선 ---
    # 러너 자신도 실행 끝에 이것을 대조하지만(T4), **러너를 돌리지 않은 회차**에는 그 경고가
    #   뜨지 않는다. 커밋 직전은 그 자리다 — 문서와 러너 상수가 갈린 채 커밋되는 것을 잡는다.
    $runner = Join-Path $root 'plugins/pjc/hooks/evals/run-hook-evals.ps1'
    $conv = Join-Path $root 'docs/harness-conventions.md'
    if ((Test-Path -LiteralPath $runner) -and (Test-Path -LiteralPath $conv)) {
        $rs = Select-String -LiteralPath $runner -Pattern '\$GoldenTotalBaseline\s*=\s*(\d+)' | Select-Object -First 1
        $cs = Select-String -LiteralPath $conv -Pattern '\*\*기준선 (\d+)케이스\*\*' | Select-Object -First 1
        if ($rs -and $cs -and $rs.Matches[0].Groups[1].Value -ne $cs.Matches[0].Groups[1].Value) {
            $lines.Add("[낡음] hook 골든 총계가 갈립니다 — 러너 상수 $($rs.Matches[0].Groups[1].Value) ↔ 문서 $($cs.Matches[0].Groups[1].Value). 이 수는 기계로 세어지지 않아 둘을 손으로 맞춰야 합니다")
        }
    }

    # --- 층 2: 위키 격차 ---
    $vault = $env:CLAUDE_WIKI_VAULT
    if ($vault) {
        $lag = Get-WikiLag -RepoRoot $root -HubPath (Join-Path $vault '20_projects/personal/claude-harness-pjc.md')
        if ($null -ne $lag -and $lag -gt 0) {
            $lines.Add("[뒤처짐] 위키가 레포보다 $lag 커밋 뒤에 있습니다 — 이번 커밋이 격차를 더 벌립니다. `pending.md` 소비는 위키 세션에서 하세요")
        }
    }

    # --- 층 3: 기계가 못 재는 축 ---
    if ($script:StaleAxisMap.Count -ne $script:StaleAxisBaseline) {
        $lines.Add("[내부] 경로→축 매핑이 $($script:StaleAxisMap.Count)건인데 기준선은 $($script:StaleAxisBaseline)건입니다 — 정당한 증감이면 StaleAxisBaseline 을 함께 갱신하세요(그 diff 가 목록 변화의 기록입니다)")
    }
    $staged = Get-StagedPaths -RepoRoot $root
    if ($null -eq $staged) {
        $lines.Add('[판정불가] 스테이징 목록을 읽지 못해 기계 미커버 축을 대조하지 못했습니다')
    } elseif ($staged.Count -gt 0) {
        foreach ($entry in $script:StaleAxisMap) {
            $hit = @($staged | Where-Object { $_ -match $entry.Pattern })
            if ($hit.Count -gt 0) {
                $lines.Add("[고지] $($entry.Axis) — 이번 커밋의 $($hit.Count)개 파일이 여기 걸립니다: $(($hit | Select-Object -First 3) -join ', ')")
            }
        }
    }

    if ($lines.Count -eq 0) { return New-HookResult }
    $lines.Insert(0, '[guard-bash] 커밋 직전 참고 문서 점검 — 차단이 아닙니다.')
    return New-HookResult -Stderr $lines.ToArray() -Context ($lines -join "`n")
}
