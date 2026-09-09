# guard-bash.ps1 — PreToolUse hook: Bash/PowerShell 도구 호출 시 6종 검사를 한 프로세스에서 수행 — 근거는 `rules/bash-guard-rationale.md`의 「§1 guard-bash.ps1 — PreToolUse hook: Bash/PowerShell 도구 호출 시 6종 검사를 한 프로세스에서 수행」

# 아래 검사 함수 6종의 판정 근거는 `rules/bash-guard-rationale.md` 가 정본이다(v1.225.0에 삭제된 `bash-hook-lib.ps1` 의 주석을 옮긴 것).

# 결과 객체 생성기 New-HookResult 는 아래 dot-source 대상(guard-commit-secrets.ps1)에 있다 —
#   그쪽이 이 함수를 쓰므로 정의를 그 파일에 두어야 단독 dot-source(골든 프로브)가 성립한다.

# 최상위 구분자 분리(따옴표 인식) — 근거는 `rules/bash-guard-rationale.md`의 「§11 최상위 구분자 분리(따옴표 인식)」
# 이 함수는 block-destructive.ps1 과 의도적 복제다 — 드리프트는 check-harness-consistency.py 의 「분할 헬퍼 동기」 축이 잡는다.
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

# warn-global-find: 루트 전역 탐색 경고 — 근거는 `rules/bash-guard-rationale.md`의 「§3 warn-global-find: 루트 전역 탐색 경고」
function Invoke-WarnGlobalFind {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    $hits = New-Object System.Collections.Generic.List[string]
    # 연결·파이프로 나눈다 — `cd /tmp && find / …`처럼 뒤 세그먼트에 있는 것도 잡아야 한다.
    foreach ($seg in Split-TopLevel $cmd $script:IsPsTool) {
        $t = $seg.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $tokens = @(($t -split '\s+') | Where-Object { $_ })
        if ($tokens.Count -eq 0) { continue }

        # 접두어를 벗긴다(sudo·time·nohup·env·VAR=값) — 그 뒤가 진짜 명령이다.
        $i = 0
        while ($i -lt $tokens.Count -and
               ($tokens[$i] -match '^(?i)(sudo|time|nohup|env)$' -or $tokens[$i] -match '^[A-Za-z_][A-Za-z0-9_]*=')) { $i++ }
        if ($i -ge $tokens.Count) { continue }

        # 첫 실효 토큰이 find여야 한다(경로 붙은 형태와 .exe도 인정).
        if ($tokens[$i] -notmatch '(?i)^(.*[\/])?find(\.exe)?$') { continue }

        # 그 뒤 첫 비플래그 인자가 탐색 시작점이다(`find -L / -name x`처럼 플래그가 앞설 수 있다).
        $start = $null
        for ($j = $i + 1; $j -lt $tokens.Count; $j++) {
            if ($tokens[$j].StartsWith('-')) { continue }
            $start = $tokens[$j].Trim('"', "'")
            break
        }
        if ([string]::IsNullOrWhiteSpace($start)) { continue }

        # 루트·홈 최상위·드라이브 루트만 대상. `/usr`·`./src`·`~/.cargo/registry`는 범위가 한정돼 통과한다. — 근거는 `rules/bash-guard-rationale.md`의 「§4 루트·홈 최상위·드라이브 루트만 대상. `/usr`·`./src`·`~/.cargo/registry`는 범위가 한정돼 통과한다.」
        if ($start -match '^(/|~/?|\$HOME/?|/[a-zA-Z]/?|[a-zA-Z]:[\/]?)$') { $hits.Add($start) }
    }

    if ($hits.Count -eq 0) { return New-HookResult }
    $where = (($hits | Select-Object -Unique) -join ', ')
    $msg = "[GLOBAL FIND WARNING] 루트 전역 탐색 감지 (시작점: $where) — Bash 도구는 10분 캡이 있어 이 명령은 끝나지 않고, 캡에 걸리면 셸만 죽고 find가 고아로 남아 CPU를 계속 먹습니다(회수해도 커널에 갇히면 재부팅 전까지 안 죽습니다)."
    $ctx = "루트 전역 탐색($where)은 Bash 10분 캡 안에 끝나지 않아 회수 불가능한 고아 프로세스를 남깁니다. 탐색 시작점을 좁히거나(예: ~/.cargo/registry), 프로젝트 안을 찾는 것이라면 Glob 도구를 쓰세요."
    return New-HookResult -Stderr @($msg) -Context $ctx
}

# warn-dangerous-assignment: 위험 경로를 담은 변수를 삭제 명령에 쓰는 형태 경고 — 근거는 `rules/bash-guard-rationale.md`의 「§5 warn-dangerous-assignment: 위험 경로를 담은 변수를 삭제 명령에 쓰는 형태 경고」
function Invoke-WarnDangerousAssignment {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    # 위험값: 루트·홈 최상위·드라이브 루트. — 근거는 `rules/bash-guard-rationale.md`의 「§6 위험값: 루트·홈 최상위·드라이브 루트.」
    $dangerRx = '^(/|~/?|\$HOME/?|/[a-zA-Z]/?|[a-zA-Z]:[\\/]?)$'
    # 삭제 계열만 본다 — chmod·chown 같은 권한 변경까지 넓히면 정상 스크립트에서 자주 발화한다.
    $deleteRx = '(?i)^(.*[\\/])?(rm|rmdir|unlink|shred|del|erase|rd|remove-item|ri)(\.exe)?$'

    $assigned = @{}
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($seg in Split-TopLevel $cmd $script:IsPsTool) {
        $t = $seg.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }

        # ① 대입 기록 — bash `NAME=값` / PowerShell `$NAME = 값`. 선언 접두어는 벗긴다.
        $decl = $t -replace '^(?i)(export|declare|local|typeset)\s+', ''
        $asg = [regex]::Match($decl, '^\$?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\S*)$')
        if ($asg.Success) {
            $assigned[$asg.Groups[1].Value] = $asg.Groups[2].Value.Trim('"', "'")
            continue
        }

        # ② 사용 판정 — 접두어(sudo·time·nohup·env·VAR=값)를 벗긴 첫 토큰이 삭제 계열일 때만.
        $tokens = @(($t -split '\s+') | Where-Object { $_ })
        $i = 0
        while ($i -lt $tokens.Count -and
               ($tokens[$i] -match '^(?i)(sudo|time|nohup|env)$' -or $tokens[$i] -match '^[A-Za-z_][A-Za-z0-9_]*=')) { $i++ }
        if ($i -ge $tokens.Count) { continue }
        if ($tokens[$i] -notmatch $deleteRx) { continue }

        for ($j = $i + 1; $j -lt $tokens.Count; $j++) {
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

# block-plan-write: plan.md 를 대상으로 하는 쓰기 명령 차단 — 근거는 `rules/bash-guard-rationale.md`의 「§10 block-plan-write: plan.md 를 대상으로 하는 쓰기 명령 차단」
function Invoke-BlockPlanWrite {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    # 변수 대입 기록 — 이름을 거쳐 지시하는 형태를 역참조한다(§10).
    $assigned = @{}
    foreach ($m in [regex]::Matches($cmd, '(?:^|[\s;&|("''])\s*\$?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[''"]([^''"]*)[''"]')) {
        $assigned[$m.Groups[1].Value] = $m.Groups[2].Value
    }
    # 인자가 plan.md 를 가리키는가 — 리터럴이거나 값이 plan.md 인 변수 이름이거나(§10).
    function Test-PlanTarget([string]$arg) {
        if ([string]::IsNullOrWhiteSpace($arg)) { return $false }
        $a = $arg.Trim().Trim('"', "'", '(', ')', ',')
        if ($a -match '^\$?\{?([A-Za-z_][A-Za-z0-9_]*)\}?$' -and $assigned.ContainsKey($Matches[1])) {
            $a = $assigned[$Matches[1]]
        }
        return ($a -match '^(\./)?plan\.md$')
    }

    $hits = New-Object System.Collections.Generic.List[string]

    # ⓐ open(…,'w') 의 첫 인자 · ⓑ 리다이렉션 대상.
    foreach ($m in [regex]::Matches($cmd, '(?i)\bopen\s*\(\s*([^,()]+?)\s*,\s*[''"]([rwaxb+]+)[''"]')) {
        if ($m.Groups[2].Value -match '[wa]' -and (Test-PlanTarget $m.Groups[1].Value)) { $hits.Add('open(w)') }
    }
    foreach ($m in [regex]::Matches($cmd, '>>?\s*(\S+)')) {
        if (Test-PlanTarget $m.Groups[1].Value) { $hits.Add('>') }
    }
    foreach ($m in [regex]::Matches($cmd, '(?i)\[System\.IO\.File\]::(WriteAll\w+|AppendAllText)\s*\(\s*([^,()]+)')) {
        if (Test-PlanTarget $m.Groups[2].Value) { $hits.Add('[System.IO.File]') }
    }
    # ⓒⓓⓔⓕ 쓰기 동사는 **세그먼트의 첫 실효 토큰일 때만** 본다 — 어디에 있든 찾으면
    #   `grep -n 'Copy-Item' plan.md` 같은 조회가 막힌다(완료 리뷰 BLOCKER).
    foreach ($seg in Split-TopLevel $cmd $script:IsPsTool) {
        $tk = @(($seg -split '\s+') | Where-Object { $_ })
        $i = 0
        while ($i -lt $tk.Count -and ($tk[$i] -match '^(?i)(sudo|time|nohup|env)$' -or $tk[$i] -match '^[A-Za-z_]\w*=')) { $i++ }
        if ($i -ge $tk.Count) { continue }
        $verb = ($tk[$i] -replace '^.*[\\/]', '') -replace '(?i)\.exe$', ''
        $rest = if ($i + 1 -lt $tk.Count) { @($tk[($i + 1)..($tk.Count - 1)]) } else { @() }
        if ($verb -match '^(?i)(cp|mv|copy-item|move-item|rename-item)$') {
            if (Test-PlanTarget (@($rest) | Select-Object -Last 1)) { $hits.Add('cp/mv') }
        } elseif ($verb -match '^(?i)sed$') {
            if (($seg -match '(?i)(\s-[a-z]*i\b|--in-place)') -and (Test-PlanTarget (@($rest) | Select-Object -Last 1))) { $hits.Add('sed -i') }
        } elseif ($verb -match '^(?i)(set-content|add-content|out-file|tee)$') {
            # PowerShell 은 named parameter 가 표준이라 -Path 계열 값을 먼저 읽는다.
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

# ---- warn-external-ops: 외부·비가역 작업(push·merge·tag·gh release/pr·배포)·로컬 비가역(reset --hard 등) 경고 ----
function Invoke-WarnExternalOps {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    # 메시지성 값 스트립 — 그 값 속 push/merge/tag 텍스트가 실제 경고를 삼키지 않게(값만 제거, 플래그 토큰 보존). — 근거는 `rules/bash-guard-rationale.md`의 「§7 메시지성 값 스트립 — 그 값 속 push/merge/tag 텍스트가 실제 경고를 삼키지 않게(값만 제거, 플래그 토큰 보존).」
    $scanCmd = $cmd
    if ($scanCmd -match '(?i)(^|\s)git(\s|$)') {
        $scanCmd = $scanCmd -replace '(?i)(^|\s)(-[a-z]*m|--message)(=|\s+)("[^"]*"|''[^'']*''|\S+)', ' '
    }
    if ($scanCmd -match '(?i)(^|\s)gh(\s|$)') {
        $scanCmd = $scanCmd -replace '(?i)(^|\s)(--notes|--body)(=|\s+)("[^"]*"|''[^'']*''|\S+)', ' '
    }

    $externalOps = @(
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*push\b';   label = 'git push (원격 반영)' },
        # merge: --abort/--continue/--quit는 복구·진행이라 병합 실행이 아님 — 제외(lookahead는 셸 구분자를 넘지 않음).
        #   merge(?![-\w])는 하이픈 결합 plumbing(merge-base·merge-tree·merge-file·merge-index 등 — 읽기 전용 조회로 병합 아님)을 오탐하지 않게 한다(\b는 하이픈 앞도 경계로 인정해 오탐).
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*merge(?![-\w])(?![^&;|\r\n]*\s--(abort|continue|quit)\b)';  label = 'git merge (브랜치 병합)' },
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*tag\s+(--delete\b|-[asfmd]|[^\s-])';  label = 'git tag (태그 생성/삭제)' },
        @{ rx = 'gh\s+release\s+create';          label = 'gh release create (릴리즈 발행)' },
        @{ rx = 'gh\s+release\s+delete';          label = 'gh release delete (릴리즈 삭제 — 비가역)' },
        @{ rx = 'gh\s+pr\s+create';               label = 'gh pr create (PR 생성)' },
        @{ rx = 'gh\s+pr\s+merge';                label = 'gh pr merge (PR 병합)' },
        @{ rx = '\b(npm|pnpm|yarn)\s+publish\b';  label = '패키지 배포 (npm/pnpm/yarn publish)' },
        @{ rx = '\bdotnet\s+nuget\s+push\b';      label = 'NuGet 배포 (dotnet nuget push)' },
        @{ rx = '(^|\s)nuget\s+push\b';           label = 'NuGet 배포 (nuget push)' },
        @{ rx = '\bcargo\s+publish\b';            label = 'crates.io 배포 (cargo publish)' },
        @{ rx = '\btwine\s+upload\b';             label = 'PyPI 배포 (twine upload)' },
        @{ rx = '\bdocker\s+push\b';              label = '이미지 배포 (docker push)' }
    )
    $localOps = @(
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*reset\s+[^&;|\r\n]*--hard\b';   label = 'git reset --hard (워킹트리·인덱스 되돌리기)' },
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*stash\s+clear\b';              label = 'git stash clear (스태시 전체 삭제)' },
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*checkout\s+--\s';              label = 'git checkout -- <path> (워킹트리 변경 폐기)' },
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*checkout\s+\S+\s+--\s';        label = 'git checkout <ref> -- <path> (워킹트리 변경 폐기)' },
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*checkout\s+\.(\s|$)';          label = 'git checkout . (워킹트리 전체 변경 폐기)' },
        # git restore 는 checkout -- <path> 와 등가의 워킹트리 폐기다 — `--staged` 단독(인덱스만 되돌림)은 제외하고 `--staged --worktree`/`-W` 는 포함(회차 44).
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*restore\s+(?![^&;|\r\n]*--staged\b(?![^&;|\r\n]*(--worktree\b|\s-W\b)))\S'; label = 'git restore <path> / . (워킹트리 변경 폐기)' }
    )

    # 셸 구분자(&&·;·|·개행)로 세그먼트를 나눠 세그먼트별로 판정(다른 세그먼트의 --dry-run 텍스트가 앞 경고를 삼키지 않게).
    #   넘기는 것은 `$cmd` 가 아니라 위에서 메시지값을 스트립한 `$scanCmd` 다 — 분리기가 따옴표를 인식하므로
    #   `$cmd` 를 넘기면 `git commit -m "…git push…"` 가 한 세그먼트로 보존돼 그 안의 push 에 오경고가 난다.
    $segments = Split-TopLevel $scanCmd $script:IsPsTool
    $hits = New-Object System.Collections.Generic.List[string]
    $hitsLocal = New-Object System.Collections.Generic.List[string]
    foreach ($seg in $segments) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        $segHasDryRun = $seg -match '--dry-run'
        foreach ($op in $externalOps) {
            if ($seg -match $op.rx) {
                if ($segHasDryRun) { continue }   # 조회성(실제 반영 아님) — 같은 세그먼트 dry-run만 인정
                if (-not $hits.Contains($op.label)) { $hits.Add($op.label) }
            }
        }
        foreach ($op in $localOps) {
            if ($seg -match $op.rx -and -not $hitsLocal.Contains($op.label)) { $hitsLocal.Add($op.label) }
        }
    }

    if ($hits.Count -eq 0 -and $hitsLocal.Count -eq 0) { return New-HookResult }

    $lines = @()
    if ($hits.Count -gt 0) {
        $lines += "[EXTERNAL OP WARNING] 외부·비가역 작업이 감지되었습니다:"
        foreach ($h in $hits) { $lines += "  - $h" }
    }
    if ($hitsLocal.Count -gt 0) {
        $lines += "[LOCAL OP WARNING] 로컬 비가역 작업이 감지되었습니다:"
        foreach ($h in $hitsLocal) { $lines += "  - $h" }
    }
    $lines += ""
    if ($hits.Count -gt 0) {
        $lines += "이 작업들은 자율 루프 권한 밖입니다 (규칙 12 — push·병합·태그·릴리즈·PR)."
        $lines += "사용자에게 '그 행위를 이름으로 적어' 별도 승인받았는지 확인하세요. 승인 없이 실행하지 마세요."
    }
    if ($hitsLocal.Count -gt 0) {
        $lines += "로컬 비가역: 미커밋 변경이 영구 소실될 수 있습니다 — reflog로는 커밋된 것만 일부 복구됩니다. 진행 전 의도된 되돌리기인지 확인하세요."
    }
    $lines += "이 경고는 차단이 아닙니다."
    $msg = ($lines -join "`n")
    return New-HookResult -Block $false -Stderr @($msg) -Context $msg
}

# ---- require-task-checkbox: 'T<N>' 완료 커밋(제목 `{유형}: T<N> — …` 또는 구형 `T<N>: …`)인데 plan의 해당 체크박스가 미완료면 차단(exit 2) ----
function Invoke-RequireTaskCheckbox {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    if ($cmd -notmatch 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { return New-HookResult }

    # 완료 커밋 판정: 커밋 메시지 '제목(첫 줄)'이 `{유형}: T<N> — …`(글로벌 「Git」 다섯 유형 · 회차 44 정본) 또는 구형 `T<N>: …` 일 때만
    #   (본문·괄호 언급 오탐 방지). 종전 정규식은 구형만 받아 최근 40커밋(전부 신형)에서 한 번도 발화하지 않았다 — 게이트가 사문화돼 있었다.
    $msgMatch = [regex]::Match($cmd, '(?i)(?:^|\s)(?:-[a-z]*m|--message)(?:=|\s+)(?:"([^"]*)"|''([^'']*)''|(\S+))')
    if (-not $msgMatch.Success) { return New-HookResult }
    $msgVal = if ($msgMatch.Groups[1].Success) { $msgMatch.Groups[1].Value }
              elseif ($msgMatch.Groups[2].Success) { $msgMatch.Groups[2].Value }
              else { $msgMatch.Groups[3].Value }
    $msgLines = @($msgVal -split '\r?\n')
    $msgTitle = $msgLines[0]
    # `-m "$(cat <<'EOF' … EOF)"` 형태는 첫 줄이 heredoc 여는 줄이라 제목이 아니다 — 그 다음 줄이 제목이다(회차 44 실측 미탐).
    if ($msgTitle -match '^\s*\$\(\s*cat\s+<<-?\s*["'']?\w+["'']?\s*$' -and $msgLines.Count -gt 1) { $msgTitle = $msgLines[1] }
    $m = [regex]::Match($msgTitle, '^\s*(?:(?:기능|수정|리팩토링|문서|설정)\s*:\s*)?T(\d+)\s*(?::|—|-)')
    if (-not $m.Success) { return New-HookResult }
    $taskNum = $m.Groups[1].Value

    if ($env:CLAUDE_HARNESS_QUICK -eq '1') {
        return New-HookResult -Block $false -Stderr @("[HARNESS] QUICK 모드: T$taskNum 체크박스 검사 우회")
    }

    # 단일 plan 파일 상향 탐색 — plan 위치는 루트 plan.md 하나다.
    $startDir = $null
    if ($data.cwd) { $startDir = $data.cwd }
    elseif ($env:CLAUDE_PROJECT_DIR) { $startDir = $env:CLAUDE_PROJECT_DIR }
    else { $startDir = (Get-Location).Path }

    $planFile = Find-SinglePlanUpwards -StartDir $startDir
    if (-not $planFile) { return New-HookResult }

    try {
        $planText = Get-Content -LiteralPath $planFile -Raw -Encoding UTF8
    } catch {
        return New-HookResult
    }
    if ([string]::IsNullOrWhiteSpace($planText)) { return New-HookResult }

    # 미완료 마커 [ ]/[/] + 해당 task 번호. 불릿은 '-'·'*' 둘 다. 템플릿 정본의 하위 항목 `- [ ] **T<N>-<M>**`(볼드)도 받는다 —
    #   T<N> 완료 커밋의 대상은 T<N>-1…T<N>-k 전부라 하나라도 미완료면 차단한다(회차 44 D2). 'T$taskNum(-\d+)?\b'라 T1이 T10 오매치 안 함.
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

# require-task-checkbox의 단일 plan 파일 상향 탐색 헬퍼(래퍼·디스패처 공유).
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
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로·명령이 깨진다(디스패처가 lib 함수로 넘기는 명령 원문까지 손상). 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
} catch {
    exit 0   # 파싱 실패 시 통과 (검사 실패가 차단보다 안전)
}

# PowerShell 도구는 따옴표 규칙이 bash 와 다르다(이스케이프는 백틱, `\` 는 리터럴) — 분리기에 넘긴다(회차 44).
$script:IsPsTool = ([string]$data.tool_name -eq 'PowerShell')

. (Join-Path $PSScriptRoot 'guard-commit-secrets.ps1')

# 로드 가드: lib 로드 실패(파일 누락·손상) 시 5검사가 침묵 fail-open되는 것을 가시화한다 —
#   차단 게이트(require-task-checkbox)까지 실리는 지점이라 경고 없이 통과시키지 않는다(비차단 유지).
if (-not (Get-Command Invoke-WarnCommitSecrets -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('[guard-bash] guard-commit-secrets.ps1 로드 실패 — 커밋 시크릿 검사 미수행(fail-open) — 나머지 4검사는 이 파일 안에 있어 계속 동작합니다. 플러그인 재설치를 권장합니다.')
    exit 0
}

# [이벤트 로깅] 차단/경고 이벤트를 오탐 리뷰 데이터로 적재 — lib 함수·얇은 래퍼는 무수정(골든 격리 유지),
#   로깅은 디스패처 수준에서 결과 객체로 수행한다. 실패는 전면 격리(검사 판정 무영향).
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}
$cmdText = [string]$data.tool_input.command
function Write-DispatchEvent {
    param([string]$HookName, [string]$Decision, [object]$Result)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            $rule = if ($Result.Stderr -and @($Result.Stderr).Count -gt 0) { [string](@($Result.Stderr)[0]) } else { '' }
            Write-HookEvent $HookName $Decision $rule $script:cmdText
        }
    } catch {}
}

# 검사 6종을 한 프로세스에 담는 구조 — 근거는 `rules/bash-guard-rationale.md`의 「§2 검사 6종을 한 프로세스에 담는 구조」
# 순서: 원 hooks.json 순서에서 block-destructive — 근거는 `rules/bash-guard-rationale.md`의 「§8 순서: 원 hooks.json 순서에서 block-destructive」
$checks = @(
    @{ fn = 'Invoke-WarnExternalOps';     name = 'warn-external-ops' },
    @{ fn = 'Invoke-RequireTaskCheckbox'; name = 'require-task-checkbox' },
    @{ fn = 'Invoke-BlockPlanWrite';      name = 'block-plan-write' },
    @{ fn = 'Invoke-WarnCommitSecrets';   name = 'warn-commit-secrets' },
    @{ fn = 'Invoke-WarnGlobalFind';      name = 'warn-global-find' },
    @{ fn = 'Invoke-WarnDangerousAssignment'; name = 'warn-dangerous-assignment' }
)
$results = New-Object System.Collections.Generic.List[object]
foreach ($c in $checks) {
    try {
        $r = & $c.fn $data
        if ($r) { $r['Name'] = $c.name; $results.Add($r) }
    } catch {
        # 한 검사의 예외는 나머지를 막지 않는다(런타임 격리 — 안전측 통과).
    }
}

$blocked = @($results | Where-Object { $_.Block })
if ($blocked.Count -gt 0) {
    # 차단: 차단 사유만 출력(warn 경고는 버림 — D4 트레이드오프), exit 2로 도구 차단.
    foreach ($b in $blocked) {
        foreach ($l in $b.Stderr) { [Console]::Error.WriteLine($l) }
        Write-DispatchEvent $b['Name'] 'block' $b
    }
    exit 2
}

# 비차단: warn 경고 stderr 전부 + additionalContext 병합(Claude Code는 hook당 1 JSON 파싱).
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
