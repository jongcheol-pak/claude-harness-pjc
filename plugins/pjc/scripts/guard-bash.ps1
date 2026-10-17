# guard-bash.ps1 — PreToolUse hook: Bash/PowerShell 도구 호출 시 7종 검사를 한 프로세스에서 수행 — 근거는 `rules/bash-guard-rationale.md` §1

# 아래 검사 함수 7종의 판정 근거는 `rules/bash-guard-rationale.md` 가 정본이다(v1.225.0에 삭제된 `bash-hook-lib.ps1` 의 주석을 옮긴 것).

# 공용 헬퍼 New-HookResult·Remove-HeredocBodyForJudge 는 여기 둔다 — 커밋 판정 라이브러리 둘은 커밋 명령에서만
#   dot-source 되므로(아래 로드 루프) 거기 두면 나머지 검사가 돌 수 없다.
function New-HookResult {
    param([bool]$Block = $false, [string[]]$Stderr = @(), [string]$Context = $null)
    return @{ Block = $Block; Stderr = $Stderr; Context = $Context }
}

# heredoc 블록 정규식 — 아래 함수들과 커밋 판정 라이브러리의 스트립이 공유한다(dot-source 라 같은 스코프).
$script:HeredocBlockRx = '(?m)^(?<line>[^\r\n]*<<-?\s*(?<q>["'']?)(?<tag>\w+)\k<q>[^\r\n]*)\r?\n(?<body>[\s\S]*?)\r?\n[ \t]*\k<tag>[ \t]*(?=\r?\n|$)'
# heredoc 본문 전량 스트립 (커밋 판정 전용) — 근거는 `rules/commit-secrets-rationale.md` §3a
#   쓰는 쪽은 `guard-commit-secrets.ps1`·`guard-stale-docs.ps1` 둘이다. 여기 두면 한쪽 파일이 없어도 다른 쪽의 스트립이 유지된다.
function Remove-HeredocBodyForJudge([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $s }
    if (-not $script:HeredocBlockRx) { return $s }   # 단독 dot-source 시 fail-open(보수측: 스트립 없이 판정)
    return [regex]::Replace($s, $script:HeredocBlockRx, { param($m) $m.Groups['line'].Value })
}
# heredoc 데이터-싱크 본문 스트립 — 근거는 `rules/bash-guard-rationale.md` §16
function Remove-HeredocDataSink([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $s }
    return [regex]::Replace($s, $script:HeredocBlockRx, {
        param($m)
        $line = $m.Groups['line'].Value
        # 싱크 판정은 heredoc 을 받는 세그먼트(소비자)로 하고, 스크립트(.sh·.py 등)로 쓰는 본문은 걷지 않는다 — 근거는 `rules/bash-guard-rationale.md` §16
        $target = Get-HeredocSinkTarget $line $script:IsPsTool
        $isDataSink = ($null -ne $target) -and -not (Test-ScriptSinkTarget $target $line)
        if ($isDataSink) { $line } else { $m.Value }
    })
}
function Get-HeredocSinkTarget([string]$line, [bool]$PsQuoting) {
    $cons = $null
    foreach ($sg in @(Split-TopLevel $line $PsQuoting)) { if ($sg -match '<<') { $cons = $sg; break } }
    if ($null -eq $cons) { return $null }
    $rest = $line.Substring($line.IndexOf($cons) + $cons.Length)
    $t = $null
    if ($cons -match '(?i)^\s*cat\b[^>]*>\s*(\S+)') { $t = $Matches[1] }
    elseif ($cons -match '(?i)^\s*tee\b(?:\s+-\S+)*\s+(\S+)') { $t = $Matches[1] }
    elseif ($cons -match '(?i)^\s*cat\b' -and $rest -match '(?i)^\s*\|\s*tee\b(?:\s+-\S+)*\s+(\S+)\s*$') { return $Matches[1] }
    # 출력이 다시 파이프로 나가거나 대상이 표준출력이면 본문이 다음 명령(셸)으로 흘러간다 — 싱크가 아니다
    if ($null -eq $t -or $rest -match '^\s*\|(?!\|)' -or $t.Trim('"', "'") -match '^/(dev|proc/self)/(stdout|fd/)') { return $null }
    return $t
}
function Test-ScriptSinkTarget([string]$target, [string]$line) {
    $t = $target.Trim('"', "'")
    if ($t -match '^\$\{?(\w+)\}?$') {
        if ($line -match ('(?:^|[\s;&|])' + $Matches[1] + '=("[^"]*"|''[^'']*''|[^\s;&|]+)')) { $t = $Matches[1].Trim('"', "'") } else { return $false }
    }
    return ($t -match '(?i)\.(sh|bash|py|ps1|psm1|js|rb|pl|cmd|bat)$')
}
# 데이터 명령 세그먼트의 따옴표 문자열 스트립 — 근거는 `rules/bash-guard-rationale.md` §17
function Remove-DataQuotes([string[]]$segs, [string]$src, $ops) {
    $qRx = '"(?:[^"\\]|\\.)*"|''[^'']*'''
    $pos = @(); $p = 0
    foreach ($s in $segs) { $a = $src.IndexOf($s, $p); if ($a -lt 0) { $a = $p }; $pos += $a; $p = $a + $s.Length }
    for ($i = 0; $i -lt $segs.Count; $i++) {
        if (-not $ops.dataCommandRx -or $segs[$i] -notmatch $ops.dataCommandRx) { continue }
        $bare = $segs[$i] -replace $qRx, ''
        if ($bare -match '(?<![0-9&])>|\b1>' -and $bare -notmatch '>\s*(/dev/null|\$null|NUL)\s*$') { continue }
        if ($src.Substring($pos[$i] + $segs[$i].Length) -match '^\s*&>') { continue }
        $ok = $true; $j = $i
        while ($ok -and $j + 1 -lt $segs.Count -and $src.Substring($pos[$j] + $segs[$j].Length) -match '^\s*\|(?!\|)') {
            $j++; $ok = $segs[$j] -match $ops.dataReceiverRx
        }
        if ($ok) { $segs[$i] = [regex]::Replace($segs[$i], $qRx, { param($m) if ($m.Value -match '\$\(|`') { $m.Value } else { '""' } }) }
    }
    return $segs
}
# 최상위 구분자 분리(따옴표 인식) — 근거는 `rules/bash-guard-rationale.md` §11
function Split-TopLevel([string]$s, [bool]$PsQuoting = $false) {
    $parts = New-Object System.Collections.Generic.List[string]
    $cur = ''
    $q = $null
    $chars = $s.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]
        if ($q -eq "'") {
            $cur += $ch
            if ($ch -eq "'") { $q = $null }
        } elseif ($q -eq '"') {
            $esc = if ($PsQuoting) { '`' } else { '\' }
            if ($ch -eq $esc -and $i + 1 -lt $chars.Length) {
                $cur += $ch; $cur += $chars[$i + 1]; $i++
            } else {
                $cur += $ch
                if ($ch -eq '"') { $q = $null }
            }
        } else {
            if ((-not $PsQuoting) -and $ch -eq '\' -and $i + 1 -lt $chars.Length) {
                $cur += $ch; $cur += $chars[$i + 1]; $i++
            } elseif ($ch -eq '"' -or $ch -eq "'") {
                $q = $ch; $cur += $ch
            } elseif ($ch -eq ';' -or $ch -eq '|' -or $ch -eq '&' -or $ch -eq "`n" -or $ch -eq "`r") {
                $parts.Add($cur); $cur = ''
            } else {
                $cur += $ch
            }
        }
    }
    $parts.Add($cur)
    return $parts
}

# 셸 접두어를 벗긴 토큰 배열 — 근거는 `rules/bash-guard-rationale.md` §12
function Get-EffectiveTokens([string]$seg) {
    $tk = @(($seg -split '\s+') | Where-Object { $_ })
    $i = 0
    while ($i -lt $tk.Count -and ($tk[$i] -match '^(?i)(sudo|time|nohup|env)$' -or $tk[$i] -match '^[A-Za-z_]\w*=')) { $i++ }
    if ($i -ge $tk.Count) { return @() }
    return @($tk[$i..($tk.Count - 1)])
}

# warn-global-find: 루트 전역 탐색 경고 — 근거는 `rules/bash-guard-rationale.md` §3
function Invoke-WarnGlobalFind {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($seg in Split-TopLevel (Remove-HeredocDataSink $cmd) $script:IsPsTool) {
        $tokens = Get-EffectiveTokens $seg
        if ($tokens.Count -eq 0) { continue }

        if ($tokens[0] -notmatch '(?i)^(.*[\/])?find(\.exe)?$') { continue }

        $start = $null
        for ($j = 1; $j -lt $tokens.Count; $j++) {
            if ($tokens[$j].StartsWith('-')) { continue }
            $start = $tokens[$j].Trim('"', "'")
            break
        }
        if ([string]::IsNullOrWhiteSpace($start)) { continue }

        # 루트·홈 최상위·드라이브 루트만 대상. `/usr`·`./src`·`~/.cargo/registry`는 범위가 한정돼 통과한다. — 근거는 `rules/bash-guard-rationale.md` §4
        if ($start -match '^(/|~/?|\$HOME/?|/[a-zA-Z]/?|[a-zA-Z]:[\/]?)$') { $hits.Add($start) }
    }

    if ($hits.Count -eq 0) { return New-HookResult }
    $where = (($hits | Select-Object -Unique) -join ', ')
    $msg = "[GLOBAL FIND WARNING] 루트 전역 탐색 감지 (시작점: $where) — Bash 도구는 10분 캡이 있어 이 명령은 끝나지 않고, 캡에 걸리면 셸만 죽고 find가 고아로 남아 CPU를 계속 먹습니다(회수해도 커널에 갇히면 재부팅 전까지 안 죽습니다)."
    $ctx = "루트 전역 탐색($where)은 Bash 10분 캡 안에 끝나지 않아 회수 불가능한 고아 프로세스를 남깁니다. 탐색 시작점을 좁히거나(예: ~/.cargo/registry), 프로젝트 안을 찾는 것이라면 Glob 도구를 쓰세요."
    return New-HookResult -Stderr @($msg) -Context $ctx
}

# warn-dangerous-assignment: 위험 경로를 담은 변수를 삭제 명령에 쓰는 형태 경고 — 근거는 `rules/bash-guard-rationale.md` §5
function Invoke-WarnDangerousAssignment {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    # 위험값: 루트·홈 최상위·드라이브 루트. — 근거는 `rules/bash-guard-rationale.md` §6
    $dangerRx = '^(/|~/?|\$HOME/?|/[a-zA-Z]/?|[a-zA-Z]:[\\/]?)$'
    $deleteRx = '(?i)^(.*[\\/])?(rm|rmdir|unlink|shred|del|erase|rd|remove-item|ri)(\.exe)?$'

    $assigned = @{}
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($seg in Split-TopLevel (Remove-HeredocDataSink $cmd) $script:IsPsTool) {
        $t = $seg.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }

        $decl = $t -replace '^(?i)(export|declare|local|typeset)\s+', ''
        $asg = [regex]::Match($decl, '^\$?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\S*)$')
        if ($asg.Success) {
            $assigned[$asg.Groups[1].Value] = $asg.Groups[2].Value.Trim('"', "'")
            continue
        }

        $tokens = Get-EffectiveTokens $t
        if ($tokens.Count -eq 0 -or $tokens[0] -notmatch $deleteRx) { continue }

        for ($j = 1; $j -lt $tokens.Count; $j++) {
            foreach ($m in [regex]::Matches($tokens[$j], '\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?')) {
                $name = $m.Groups[1].Value
                if (-not $assigned.ContainsKey($name)) { continue }
                if ($assigned[$name] -match $dangerRx) {
                    $pair = '$' + $name + ' = ' + $assigned[$name]
                    if (-not $hits.Contains($pair)) { $hits.Add($pair) }
                }
            }
        }
    }

    if ($hits.Count -eq 0) { return New-HookResult }
    $where = ($hits -join ', ')
    $msg = "[DANGEROUS ASSIGNMENT WARNING] 삭제 명령의 대상이 같은 줄에서 루트·홈 경로로 대입된 변수입니다 ($where) — 변수를 한 번 거치면 block-destructive의 정규식 차단을 통과하므로(의도된 미탐) 이 명령은 차단되지 않습니다."
    $ctx = "삭제 대상 변수($where)가 루트·홈·드라이브 루트를 가리킵니다. 실행하면 그 아래 전체가 지워질 수 있고 차단 hook은 이 형태를 잡지 못합니다 — 대입값이 의도한 것인지 확인하고, 아니면 대상 경로를 좁히세요."
    return New-HookResult -Stderr @($msg) -Context $ctx
}

# block-plan-write: plan.md 를 대상으로 하는 쓰기 명령 차단 — 근거는 `rules/bash-guard-rationale.md` §10
function Invoke-BlockPlanWrite {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    $assigned = @{}
    foreach ($m in [regex]::Matches($cmd, '(?:^|[\s;&|("''])\s*\$?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[''"]([^''"]*)[''"]')) {
        $assigned[$m.Groups[1].Value] = $m.Groups[2].Value
    }
    function Test-PlanTarget([string]$arg) {
        if ([string]::IsNullOrWhiteSpace($arg)) { return $false }
        $a = $arg.Trim().Trim('"', "'", '(', ')', ',')
        if ($a -match '^\$?\{?([A-Za-z_][A-Za-z0-9_]*)\}?$' -and $assigned.ContainsKey($Matches[1])) {
            $a = $assigned[$Matches[1]]
        }
        return ($a -match '^(\./)?plan\.md$')
    }

    $hits = New-Object System.Collections.Generic.List[string]

    foreach ($m in [regex]::Matches($cmd, '(?i)\bopen\s*\(\s*([^,()]+?)\s*,\s*[''"]([rwaxb+]+)[''"]')) {
        if ($m.Groups[2].Value -match '[wa]' -and (Test-PlanTarget $m.Groups[1].Value)) { $hits.Add('open(w)') }
    }
    $stripped = Remove-HeredocDataSink $cmd
    foreach ($m in [regex]::Matches($stripped, '>>?\s*(\S+)')) {
        if (Test-PlanTarget $m.Groups[1].Value) { $hits.Add('>') }
    }
    foreach ($m in [regex]::Matches($cmd, '(?i)\[System\.IO\.File\]::(WriteAll\w+|AppendAllText)\s*\(\s*([^,()]+)')) {
        if (Test-PlanTarget $m.Groups[2].Value) { $hits.Add('[System.IO.File]') }
    }
    foreach ($seg in Split-TopLevel $stripped $script:IsPsTool) {
        $tk = Get-EffectiveTokens $seg
        if ($tk.Count -eq 0) { continue }
        $verb = ($tk[0] -replace '^.*[\\/]', '') -replace '(?i)\.exe$', ''
        $rest = if ($tk.Count -gt 1) { @($tk[1..($tk.Count - 1)] | Where-Object { $_ -notmatch '^\d*[<>]' }) } else { @() }
        if ($verb -match '^(?i)(cp|mv|copy-item|move-item|rename-item)$') {
            if (Test-PlanTarget (@($rest) | Select-Object -Last 1)) { $hits.Add('cp/mv') }
        } elseif ($verb -match '^(?i)sed$') {
            if (($seg -match '(?i)(\s-[a-z]*i\b|--in-place)') -and (Test-PlanTarget (@($rest) | Select-Object -Last 1))) { $hits.Add('sed -i') }
        } elseif ($verb -match '^(?i)(set-content|add-content|out-file|tee)$') {
            $t = $null
            for ($j = 0; $j -lt $rest.Count - 1; $j++) {
                if ($rest[$j] -match '^(?i)-(Path|LiteralPath|FilePath|Destination)$') { $t = $rest[$j + 1]; break }
            }
            if (-not $t) { $t = @($rest | Where-Object { $_ -notmatch '^-' }) | Select-Object -First 1 }
            if (Test-PlanTarget $t) { $hits.Add($verb) }
        }
    }

    if ($hits.Count -eq 0) { return New-HookResult }
    $where = (($hits | Select-Object -Unique) -join ', ')
    return New-HookResult -Block $true -Stderr @(
        "[HARNESS] BLOCKED: plan.md 를 스크립트로 쓰려 합니다.",
        "감지된 쓰기 구문: $where.",
        "gitignore 라 잘못 쓰면 복구할 수 없습니다 — 전체 교체는 Write, 부분 수정은 Edit 도구로 하세요(`plan/SKILL.md` 「Step 5」). 읽기는 막지 않습니다."
    ) -Context "plan.md 쓰기가 차단됐습니다($where). Write·Edit 도구를 쓰세요 — 그 둘은 파일 상태를 추적해 잘림을 막습니다."
}

# ---- warn-external-ops ----
function Invoke-WarnExternalOps {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    # 메시지성 값 스트립 — 그 값 속 push/merge/tag 텍스트가 실제 경고를 삼키지 않게(값만 제거, 플래그 토큰 보존). — 근거는 `rules/bash-guard-rationale.md` §7
    $scanCmd = $cmd
    if ($scanCmd -match '(?i)(^|\s)git(\s|$)') {
        $scanCmd = $scanCmd -replace '(?i)(^|\s)(-[a-z]*m|--message)(=|\s+)("[^"]*"|''[^'']*''|\S+)', ' '
    }
    if ($scanCmd -match '(?i)(^|\s)gh(\s|$)') {
        $scanCmd = $scanCmd -replace '(?i)(^|\s)(--notes|--body)(=|\s+)("[^"]*"|''[^'']*''|\S+)', ' '
    }

    # 판정 데이터·문면 외부화와 로드 실패 격리 — 근거는 `rules/bash-guard-rationale.md` §13
    try {
        $ops = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rules/external-ops.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    } catch {
        [Console]::Error.WriteLine('[guard-bash] rules/external-ops.json 로드 실패 — 외부·비가역 작업 경고 미수행(fail-open). 나머지 검사는 계속 동작합니다.')
        return New-HookResult
    }

    #   넘기는 것은 `$cmd` 가 아니라 `$scanCmd` 다(근거는 위 §7 인용의 문단 끝).
    $src = Remove-HeredocDataSink $scanCmd
    $segments = Remove-DataQuotes @(Split-TopLevel $src $script:IsPsTool) $src $ops
    $hits = New-Object System.Collections.Generic.List[string]
    $hitsLocal = New-Object System.Collections.Generic.List[string]
    $hitContext = $false; $hitAlways = $false
    foreach ($seg in $segments) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        $segIsQuery = $seg -match '--dry-run|(^|\s)--help(\s|$)'
        foreach ($op in $ops.externalOps) {
            if ($seg -match $op.rx) {
                if ($segIsQuery) { continue }   # 조회성(실제 반영 아님) — 같은 세그먼트의 dry-run·help만 인정
                if (-not $hits.Contains($op.label)) { $hits.Add($op.label) }
                if ($op.approval -eq 'context') { $hitContext = $true } else { $hitAlways = $true }
            }
        }
        foreach ($op in $ops.localOps) {
            if ($seg -match $op.rx -and -not $hitsLocal.Contains($op.label)) { $hitsLocal.Add($op.label) }
        }
    }

    if ($hits.Count -eq 0 -and $hitsLocal.Count -eq 0) { return New-HookResult }

    $lines = @()
    $t = $ops.messages
    if ($hits.Count -gt 0) {
        $lines += $t.externalHead
        foreach ($h in $hits) { $lines += "  - $h" }
    }
    if ($hitsLocal.Count -gt 0) {
        $lines += $t.localHead
        foreach ($h in $hitsLocal) { $lines += "  - $h" }
    }
    $lines += ""
    if ($hitContext) { $lines += $t.contextBody }
    if ($hitAlways) { $lines += $t.alwaysBody }
    if ($hitsLocal.Count -gt 0) { $lines += $t.localBody }
    $lines += $t.footer
    $msg = ($lines -join "`n")
    return New-HookResult -Block $false -Stderr @($msg) -Context $msg
}

# 커밋 제목 읽기 — 근거는 `rules/bash-guard-rationale.md` §14
function Get-CommitTitle([string]$cmd, [string]$baseDir) {
    $judge = [regex]::Replace((Remove-HeredocBodyForJudge $cmd), '(?s)@([''"])[ \t]*\r?\n.*?\r?\n\1@', { param($m) '@' + $m.Groups[1].Value + ' ' + $m.Groups[1].Value + '@' })
    $cm = [regex]::Match($judge, 'git\s+((-c|-C)\s+\S+\s+)*commit\b')
    if (-not $cm.Success) { return $null }
    $seg = @(Split-TopLevel $judge.Substring($cm.Index) $script:IsPsTool)[0]
    $hereDocFirst = $null
    foreach ($hm in [regex]::Matches($cmd, $script:HeredocBlockRx)) {
        if ($hm.Groups['line'].Value -match 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { $hereDocFirst = @($hm.Groups['body'].Value -split '\r?\n')[0]; break }
    }
    $hs = [regex]::Match($cmd, '(?s)@([''"])[ \t]*\r?\n(?<body>.*?)\r?\n\1@')
    $hereStrFirst = if ($hs.Success) { @($hs.Groups['body'].Value -split '\r?\n')[0] } else { $null }

    $mm = [regex]::Match($seg, '(?i)(?:^|\s)(?:-[a-z]*m|--message)(?:=|\s+)(?:"([^"]*)"|''([^'']*)''|(\S+))')
    if ($mm.Success) {
        if ($mm.Groups[2].Success) { return @($mm.Groups[2].Value -split '\r?\n')[0] }   # 작은따옴표 — 치환 없는 리터럴
        $val = if ($mm.Groups[1].Success) { $mm.Groups[1].Value } else { $mm.Groups[3].Value }
        if ($val -match '^\s*\$\(\s*cat\s+<<') { if ($null -ne $hereDocFirst) { return $hereDocFirst } else { return $false } }
        if ($val -match '^@[''"]') { if ($null -ne $hereStrFirst) { return $hereStrFirst } else { return $false } }
        if ($val -match '^\$(\{|[A-Za-z_])') { return $false }   # 변수 — 값을 알 수 없다
        return @($val -split '\r?\n')[0]
    }
    $fm = [regex]::Match($seg, '(?:^|\s)(?:-F|--file)(?:=|\s+)(?:"([^"]*)"|''([^'']*)''|(\S+))')
    if (-not $fm.Success) { return $null }
    $path = @($fm.Groups[1], $fm.Groups[2], $fm.Groups[3] | Where-Object { $_.Success })[0].Value
    if ($path -eq '-') {
        if ($null -ne $hereDocFirst) { return $hereDocFirst }
        if ($null -ne $hereStrFirst) { return $hereStrFirst }
        return $false
    }
    if ($path -match '^/tmp(/.*)?$') { $path = $env:TEMP + ($Matches[1] -replace '/', '\') }
    elseif ($path -match '^/([A-Za-z])/(.*)$') { $path = $Matches[1] + ':\' + ($Matches[2] -replace '/', '\') }
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $gc = [regex]::Match($seg, 'git\s+(?:-c\s+\S+\s+)*-C\s+("[^"]*"|''[^'']*''|\S+)')
        if ($gc.Success) { $baseDir = Join-Path $baseDir $gc.Groups[1].Value.Trim('"', "'") }
        $path = Join-Path $baseDir $path
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    try { return [string](@(Get-Content -LiteralPath $path -TotalCount 1 -Encoding UTF8)[0]) } catch { return $false }
}

# ---- require-task-checkbox: 'T<N>' 완료 커밋(제목 `{유형}: T<N> — …` 또는 구형 `T<N>: …`)인데 plan의 해당 체크박스가 미완료면 차단(exit 2) ----
function Invoke-RequireTaskCheckbox {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    if ($cmd -notmatch 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { return New-HookResult }

    $startDir = $null
    if ($data.cwd) { $startDir = $data.cwd }
    elseif ($env:CLAUDE_PROJECT_DIR) { $startDir = $env:CLAUDE_PROJECT_DIR }
    else { $startDir = (Get-Location).Path }

    # 완료 커밋 제목 판정 — 근거는 `rules/bash-guard-rationale.md` §14
    $msgTitle = Get-CommitTitle $cmd $startDir
    if ($null -eq $msgTitle) { return New-HookResult }
    if ($msgTitle -is [bool]) {
        if ($env:CLAUDE_HARNESS_QUICK -eq '1' -or -not (Find-SinglePlanUpwards -StartDir $startDir)) { return New-HookResult }
        $w = '[HARNESS] 커밋 제목을 읽지 못해 task 체크박스 검사를 건너뜁니다 — heredoc -m 을 쓰세요(변수 -m · 본문 없는 -F - · 없는 -F 파일).'
        return New-HookResult -Stderr @($w) -Context $w
    }
    $m = [regex]::Match($msgTitle, '^\s*(?:(?:기능|수정|리팩토링|문서|설정)\s*:\s*)?T(\d+)\s*(?::|—|-)')
    if (-not $m.Success) { return New-HookResult }
    $taskNum = $m.Groups[1].Value

    if ($env:CLAUDE_HARNESS_QUICK -eq '1') {
        return New-HookResult -Block $false -Stderr @("[HARNESS] QUICK 모드: T$taskNum 체크박스 검사 우회")
    }

    $planFile = Find-SinglePlanUpwards -StartDir $startDir
    if (-not $planFile) { return New-HookResult }

    try {
        $planText = Get-Content -LiteralPath $planFile -Raw -Encoding UTF8
    } catch {
        return New-HookResult
    }
    if ([string]::IsNullOrWhiteSpace($planText)) { return New-HookResult }

    # 미완료 마커 매칭 — 근거는 `rules/bash-guard-rationale.md` §15
    $unchecked = [regex]::Match($planText, "(?m)^\s*[-*]\s*\[[ /]\]\s*\**T$taskNum(-\d+)?\b")
    if (-not $unchecked.Success) { return New-HookResult }

    $foundLine = $unchecked.Value.Trim()
    if ($foundLine.Length -gt 80) { $foundLine = $foundLine.Substring(0, 80) + '...' }
    $lines = @(
        "[HARNESS] BLOCKED: T$taskNum 완료 커밋인데 plan의 T$taskNum 체크박스가 아직 미완료입니다.",
        "",
        "plan 파일 : $planFile",
        "발견한 줄 : $foundLine",
        "",
        "구현 완료 커밋 규약: 완료 커밋 전에 해당 task 체크박스를 [x]로 갱신합니다.",
        "",
        "해결 방법:",
        "  1) plan의 해당 줄을 '- [x] T$taskNum ...'으로 갱신한 뒤 다시 commit",
        "  2) 긴급 우회 (Claude Code 시작 전 PowerShell에서):",
        "     `$env:CLAUDE_HARNESS_QUICK = '1'"
    )
    return New-HookResult -Block $true -Stderr $lines
}

function Find-SinglePlanUpwards {
    param([string]$StartDir, [int]$MaxDepth = 8)
    if ([string]::IsNullOrEmpty($StartDir)) { return $null }
    $dir = $StartDir
    for ($i = 0; $i -lt $MaxDepth; $i++) {
        if (-not $dir) { break }
        foreach ($cand in @('plan.md', 'PLAN.md', 'docs/plan.md')) {
            $pf = Join-Path $dir $cand
            if (Test-Path -LiteralPath $pf -PathType Leaf) { return $pf }
        }
        if ((Test-Path -LiteralPath (Join-Path $dir '.git') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $dir '.claude') -PathType Container)) {
            return $null
        }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
} catch {
    exit 0   # 파싱 실패 시 통과 (검사 실패가 차단보다 안전)
}

$script:IsPsTool = ([string]$data.tool_name -eq 'PowerShell')

$cmdText = [string]$data.tool_input.command

# 커밋 시점 검사 둘은 별도 파일이고 로드 실패를 침묵시키지 않는다 — 근거는 `rules/stale-docs-rationale.md` §2
#   존재는 매 호출 확인하고(부재 경고를 커밋 때만 내면 고장이 오래 숨는다), dot-source 는 명령에 commit 이 있을 때만 한다 —
#   두 검사의 커밋 판정(`git\s+…commit\b`)이 참이면 명령에 commit 이 반드시 있어 이 조건은 그 판정의 상위 집합이다.
$loadCommitLibs = $cmdText -match 'commit'
foreach ($lib in @(@('guard-commit-secrets.ps1', 'Invoke-WarnCommitSecrets'),
                   @('guard-stale-docs.ps1', 'Invoke-WarnStaleDocs'))) {
    $libPath = Join-Path $PSScriptRoot $lib[0]
    if (Test-Path -LiteralPath $libPath) {
        if (-not $loadCommitLibs) { continue }
        . $libPath
        if (Get-Command $lib[1] -ErrorAction SilentlyContinue) { continue }
    }
    [Console]::Error.WriteLine("[guard-bash] $($lib[0]) 로드 실패 — 그 검사 미수행(fail-open). 플러그인 재설치를 권장합니다.")
}

# [이벤트 로깅] 차단/경고 이벤트를 오탐 리뷰 데이터로 적재 — lib 함수·얇은 래퍼는 무수정(골든 격리 유지),
#   로깅은 디스패처 수준에서 결과 객체로 수행한다. 실패는 전면 격리(검사 판정 무영향).
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}
function Write-DispatchEvent {
    param([string]$HookName, [string]$Decision, [object]$Result)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            $rule = if ($Result.Stderr -and @($Result.Stderr).Count -gt 0) { [string](@($Result.Stderr)[0]) } else { '' }
            Write-HookEvent $HookName $Decision $rule $script:cmdText
        }
    } catch {}
}

# 검사 7종을 한 프로세스에 담는 구조 — 근거는 `rules/bash-guard-rationale.md` §2
# 순서: 원 hooks.json 순서에서 block-destructive — 근거는 `rules/bash-guard-rationale.md` §8
$checks = @(
    @{ fn = 'Invoke-WarnExternalOps';     name = 'warn-external-ops' },
    @{ fn = 'Invoke-RequireTaskCheckbox'; name = 'require-task-checkbox' },
    @{ fn = 'Invoke-BlockPlanWrite';      name = 'block-plan-write' },
    @{ fn = 'Invoke-WarnCommitSecrets';   name = 'warn-commit-secrets' },
    @{ fn = 'Invoke-WarnGlobalFind';      name = 'warn-global-find' },
    @{ fn = 'Invoke-WarnDangerousAssignment'; name = 'warn-dangerous-assignment' },
    @{ fn = 'Invoke-WarnStaleDocs';       name = 'warn-stale-docs' }
)
$results = New-Object System.Collections.Generic.List[object]
foreach ($c in $checks) {
    if (-not (Get-Command $c.fn -ErrorAction SilentlyContinue)) { continue }
    try {
        $r = & $c.fn $data
        if ($r) { $r['Name'] = $c.name; $results.Add($r) }
    } catch {
    }
}

$blocked = @($results | Where-Object { $_.Block })
if ($blocked.Count -gt 0) {
    foreach ($b in $blocked) {
        foreach ($l in $b.Stderr) { [Console]::Error.WriteLine($l) }
        Write-DispatchEvent $b['Name'] 'block' $b
    }
    exit 2
}

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
