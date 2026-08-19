# bash-hook-lib.ps1 — Bash 계열 PreToolUse hook 3종의 검사 로직 공유 모듈 (dot-source 전용, hook 아님)
#
# warn-external-ops·require-task-checkbox·warn-commit-secrets의 검사 로직을 함수로 담아,
#   ① 각 standalone 래퍼 스크립트(동일 파일명 유지 — 골든·격리 테스트용)
#   ② 단일 pre-bash-dispatch.ps1 디스패처(도구 호출당 pwsh 콜드스타트 4→2)
# 두 경로가 같은 함수를 호출하게 한다(동작 단일 출처 — 래퍼·디스패처가 갈라지지 않음).
#
# block-destructive.ps1은 이 모듈에 포함하지 않는다 — "끌 수 없는 마지막 방어선"이라 공유 모듈
#   로드 실패에 결합시키지 않고 hooks.json 독립 엔트리로 직접 실행 유지(결정 B).
#
# 함수 계약: 파싱된 $data(hook stdin JSON) → 결과 객체
#   @{ Block = [bool];        # true면 도구 차단(exit 2). require-task-checkbox만 true 가능.
#      Stderr = [string[]];   # 사용자 가시성 경고/차단 사유 줄들(없으면 빈 배열).
#      Context = [string] }   # 모델 전달용 additionalContext(없으면 $null).
#   출력·exit는 각 caller(래퍼/디스패처)가 결과를 번역해 수행한다(이 함수는 "판정→결과"만).
#
# 이 파일은 stdin을 읽지 않고 함수 정의만 한다(실행 부작용 없음) — validate.ps1 $knownHelpers에 등록.

function New-HookResult {
    param([bool]$Block = $false, [string[]]$Stderr = @(), [string]$Context = $null)
    return @{ Block = $Block; Stderr = $Stderr; Context = $Context }
}

# ---- warn-external-ops: 외부·비가역 작업(push·merge·tag·gh release/pr·배포)·로컬 비가역(reset --hard 등) 경고 ----
function Invoke-WarnExternalOps {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    # 메시지성 값 스트립 — 그 값 속 push/merge/tag 텍스트가 실제 경고를 삼키지 않게(값만 제거, 플래그 토큰 보존).
    #   `gh`도 대상인 이유: 릴리즈 노트에 회차 서사를 적으면 `--notes "…git merge…"`가 통째로
    #   경고를 유발한다(v1.113.1 릴리즈 발행 때 실관찰). `-m`은 종전대로 `git`에만 건다 —
    #   `gh`의 짧은 플래그는 의미가 명령마다 달라 일괄 스트립하면 판정 대상까지 지운다.
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
        @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*checkout\s+\.(\s|$)';          label = 'git checkout . (워킹트리 전체 변경 폐기)' }
    )

    # 셸 구분자(&&·;·|·개행)로 세그먼트를 나눠 세그먼트별로 판정(다른 세그먼트의 --dry-run 텍스트가 앞 경고를 삼키지 않게).
    $segments = $scanCmd -split '(\|\||&&|[;|]|\r?\n)'
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

# ---- require-task-checkbox: 'T<N>:' 완료 커밋인데 plan의 해당 체크박스가 미완료면 차단(exit 2) ----
function Invoke-RequireTaskCheckbox {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    if ($cmd -notmatch 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { return New-HookResult }

    # 완료 커밋 판정: 커밋 메시지 '제목(첫 줄)'이 'T<N>:'로 시작할 때만(본문·괄호 언급 오탐 방지).
    $msgMatch = [regex]::Match($cmd, '(?i)(?:^|\s)(?:-[a-z]*m|--message)(?:=|\s+)(?:"([^"]*)"|''([^'']*)''|(\S+))')
    if (-not $msgMatch.Success) { return New-HookResult }
    $msgVal = if ($msgMatch.Groups[1].Success) { $msgMatch.Groups[1].Value }
              elseif ($msgMatch.Groups[2].Success) { $msgMatch.Groups[2].Value }
              else { $msgMatch.Groups[3].Value }
    $msgTitle = ($msgVal -split '\r?\n', 2)[0]
    $m = [regex]::Match($msgTitle, '^\s*T(\d+)\s*:')
    if (-not $m.Success) { return New-HookResult }
    $taskNum = $m.Groups[1].Value

    if ($env:CLAUDE_HARNESS_QUICK -eq '1') {
        return New-HookResult -Block $false -Stderr @("[HARNESS] QUICK 모드: T$taskNum 체크박스 검사 우회")
    }

    # 단일 plan 파일 상향 탐색(docs/plans 복수 plan은 판정 모호 — 제외).
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

    # 미완료 마커 [ ]/[/] + 해당 task 번호. 불릿은 '-'·'*' 둘 다. 'T$taskNum\b'라 T1이 T10 오매치 안 함.
    $unchecked = [regex]::Match($planText, "(?m)^\s*[-*]\s*\[[ /]\]\s*T$taskNum\b")
    if (-not $unchecked.Success) { return New-HookResult }

    $foundLine = $unchecked.Value.Trim()
    if ($foundLine.Length -gt 80) { $foundLine = $foundLine.Substring(0, 80) + '...' }
    $lines = @(
        "[HARNESS] BLOCKED: T$taskNum 완료 커밋인데 plan의 T$taskNum 체크박스가 아직 미완료입니다.",
        "",
        "plan 파일 : $planFile",
        "발견한 줄 : $foundLine",
        "",
        "implement-task Phase D 규약: 완료 커밋 전에 해당 task 체크박스를 [x]로 갱신합니다.",
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

# ---- warn-commit-secrets: git commit 직전 스테이징될 변경에서 시크릿 패턴 경고(비차단) ----
# `git diff HEAD` 보완 스캔 — 실패를 **조용한 빈 배열로 두지 않는다**.
#   HEAD가 없는(초기 커밋 전) 저장소에서는 이 호출이 실패하는데, 종전에는 `2>$null`로
#   삼켜 그 경로의 스캔분이 통째로 사라져도 아무 신호가 없었다. 기본 경로(`--cached`)는
#   빈 트리와 비교해 정상 동작하므로 차단 자체가 사라지는 것은 아니지만, **보완 스캔이
#   빠졌다는 사실은 드러나야 한다**(이 repo가 반복 등재한 "조용한 fail-open" 계열).
function Get-DiffHeadAdded {
    param([string[]]$PathArgs = @())
    $out = if ($PathArgs.Count) { @(& git diff HEAD --unified=0 -- $PathArgs 2>$null) }
           else { @(& git diff HEAD --unified=0 2>$null) }
    if ($LASTEXITCODE -ne 0) {
        $scope = if ($PathArgs.Count) { ($PathArgs -join ' ') } else { '전체' }
        # ⚠ `Write-Warning`을 쓰지 않는다 — pwsh 기본 호스트는 Warning 스트림을 **stdout(fd 1)** 에
        #   쓰므로, hook이 stdout으로 내보내는 JSON(`additionalContext`)에 끼어들어 파싱을 깨뜨린다
        #   (실측 확인). 이 repo의 hook 출력 규약도 경고는 stderr다(AGENTS.md 「hook 출력 규약」).
        [Console]::Error.WriteLine("[warn-commit-secrets] git diff HEAD 실패(exit $LASTEXITCODE) — 보완 스캔 미수행: $scope. " +
                                   'HEAD 없는 초기 저장소면 정상이며 --cached 경로가 그대로 검사한다.')
        return @()
    }
    return @($out | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })
}

function Invoke-WarnCommitSecrets {
    param($data)
    $cmd = $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return New-HookResult }

    if ($cmd -notmatch 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { return New-HookResult }
    if ($cmd -match '--dry-run' -or $cmd -match '--help' -or $cmd -match '(^|\s)-h(\s|$)') { return New-HookResult }

    # cwd로 이동해 git 명령 실행. Set-Location이 caller(디스패처)·다른 검사에 잔존하지 않게 finally로 복원.
    $origLoc = Get-Location
    try {
        if ($data.cwd -and (Test-Path -LiteralPath $data.cwd -PathType Container)) {
            Set-Location -LiteralPath $data.cwd
        } elseif ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR -PathType Container)) {
            Set-Location -LiteralPath $env:CLAUDE_PROJECT_DIR
        }

        $gitDir = & git rev-parse --git-dir 2>$null
        if (-not $gitDir -or $LASTEXITCODE -ne 0) { return New-HookResult }

        $addedLines = @(@(& git diff --cached --unified=0 2>$null) |
            Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })

        # -a/-am/--all이면 추적 파일 자동 스테이징분(git diff HEAD)도 스캔. 먼저 메시지(-m) 값을 제거해
        #   메시지 속 '-a'를 자동 스테이징으로 오인하지 않게 하되, 플래그 토큰(-am의 a)은 보존.
        $cmdFlags = $cmd -replace '(?i)(^|\s)(-[a-zA-Z]*m|--message)(=|\s+)("[^"]*"|''[^'']*''|\S+)', '$1$2'
        $autoStage = ($cmdFlags -match '(^|\s)-[a-zA-Z]*a[a-zA-Z]*(\s|$)') -or ($cmdFlags -match '(^|\s)--all(\s|$)')
        if ($autoStage) {
            $addedLines += Get-DiffHeadAdded
        }

        # 선행 스테이징 인지 (v1.119.0 — F-7 B1): PreToolUse는 명령 '실행 전'에 돈다.
        #   `git add -A && git commit`을 한 호출로 보내면 이 시점 인덱스가 비어 --cached가 0줄이고,
        #   untracked 신규 파일은 git diff HEAD에도 없어 자격증명이 그대로 통과했다.
        #   사고의 실제 경로(신규 프로젝트의 새 README)이자 자율 루프의 표준 커밋 형태다.
        # → 명령에 git add가 있으면 그 대상을 미리 스캔한다 — untracked 파일은 워킹트리 전체 내용,
        #   추적 파일은 diff HEAD 추가 라인만(커밋으로 이력에 새로 들어가는 것은 추가 라인뿐).
        $addMatch = [regex]::Match($cmd, '(?i)git\s+((-c|-C)\s+\S+\s+)*add\s+([^&;|\r\n]*)')
        if ($addMatch.Success) {
            $addArgs = $addMatch.Groups[3].Value.Trim()
            $addTargets = @()
            # 스캔 캡은 **추적 파일 분기와 공유한다** — 종전에는 아래 untracked 정독 루프에만
            #   걸려 있어, 경로를 대량 나열하면 파일당 git 서브프로세스 2회가 무제한으로 돌았다.
            $scanned = 0
            if ($addArgs -match '(^|\s)(-A|--all|-u|--update|\.)(\s|$)') {
                # 전체 스테이징: untracked + 추적 파일 수정분
                $addTargets = @(& git ls-files --others --exclude-standard 2>$null)
                $addedLines += Get-DiffHeadAdded
            } else {
                # 경로 나열: 플래그를 뺀 인자만 대상으로 본다.
                #   인자가 디렉터리(`git add docs/`)거나 글롭(`git add *.md`)이면 파일이 아니라서
                #   그냥 두면 통째로 스킵된다 — 둘 다 일상 형태이므로 git에게 대상 파일을 물어
                #   전개한다(F-7 2회차 M1 — 이걸 빼면 `git add src/` 한 줄로 게이트가 뚫린다).
                $rawTargets = @($addArgs -split '\s+' | Where-Object { $_ -and -not $_.StartsWith('-') } |
                    ForEach-Object { $_.Trim('"', "'") })
                foreach ($rt in $rawTargets) {
                    if ($scanned -ge 50) { break }
                    if (Test-Path -LiteralPath $rt -PathType Leaf) {
                        # 추적 파일은 diff HEAD 추가 라인만 스캔 — 이력에 이미 있는 내용(시크릿 픽스처·
                        #   탐지 규칙 정의)의 재신고는 보호 효과 0에 차단 비용만 낳는다. 전체 스캔 특례는
                        #   untracked(ignored 강제 add 포함) 전용으로 유지 — v1.119.0 신규 파일 사고 경로.
                        if (@(& git ls-files -- $rt 2>$null).Count -gt 0) {
                            $addedLines += Get-DiffHeadAdded -PathArgs @($rt)
                            $scanned++
                        } else {
                            $addTargets += $rt
                        }
                        continue
                    }
                    # 디렉터리·글롭·미존재 경로 → git이 해석하게 맡긴다
                    $addTargets += @(& git ls-files --others --exclude-standard -- $rt 2>$null)
                    $addedLines += Get-DiffHeadAdded -PathArgs @($rt)
                    $scanned++
                }
            }

            # 파일 수·크기 상한 — hook은 매 커밋마다 도는 경로라 무제한 정독은 지연을 만든다.
            #   상한 초과분은 스캔하지 않으므로 미탐이 될 수 있으나, 커밋 직전 신규 파일이 50개를
            #   넘는 경우는 드물고 그때도 --cached/diff HEAD 경로는 그대로 작동한다.
            foreach ($t in $addTargets) {
                if ($scanned -ge 50) { break }
                if ([string]::IsNullOrWhiteSpace($t)) { continue }
                try {
                    $tf = if ([System.IO.Path]::IsPathRooted($t)) { $t } else { Join-Path (Get-Location).Path $t }
                    if (-not (Test-Path -LiteralPath $tf -PathType Leaf)) { continue }
                    if ((Get-Item -LiteralPath $tf).Length -gt 1MB) { continue }   # 대용량·바이너리 회피
                    $txt = Get-Content -LiteralPath $tf -Raw -Encoding UTF8 -ErrorAction Stop
                    if ($txt) { $addedLines += ('+' + ($txt -replace '\r?\n', "`n+")) }
                    $scanned++
                } catch { continue }   # 바이너리·읽기 실패는 조용히 스킵
            }
        }

        $scanText = (@($addedLines | ForEach-Object { $_.Substring(1) }) -join "`n")

        . (Join-Path $PSScriptRoot 'secret-patterns.ps1')
        $hits = @(Get-SecretMatches $scanText)

        $envFiles = New-Object System.Collections.Generic.List[string]
        $staged = & git diff --cached --name-only 2>$null
        if ($staged) {
            foreach ($n in $staged) {
                if ([string]::IsNullOrWhiteSpace($n)) { continue }
                $base = [System.IO.Path]::GetFileName($n)
                if ($base -match '^\.env(\..*)?$') { $envFiles.Add($n) }
            }
        }

        if ($hits.Count -eq 0 -and $envFiles.Count -eq 0) { return New-HookResult }

        # 고신뢰 라벨(개인키·DB 연결 문자열·DB/서비스 URI 인증정보·자격증명 쌍)은 오탐 여지가 거의 없어
        #   커밋을 차단한다(v1.119.0). 나머지 라벨·.env 스테이징은 종전대로 경고만 — 이 둘은
        #   테스트 픽스처·문서 예시에서 흔히 나와, 차단하면 정상 작업이 막힌다.
        # 배경: README에 관리자 계정이 적힌 채 공개 저장소에 push된 사고. 경고는 이미 있었으나
        #   비차단이라 자율 루프가 그대로 커밋했다 — 경고를 하나 더 얹는 것은 같은 실패의 반복이다.
        # 등급 판정 함수가 없으면(모듈 부분 로드·손상) 검출된 시크릿을 전부 고신뢰로 취급해 차단한다.
        #   조용히 경고로 강등하면 "검사가 꺼진 줄 모르고 통과"하는데, 그건 이 게이트가 막으려는
        #   사고(경고는 있었으나 그냥 커밋됨)와 똑같은 실패 모드다 — 판정 불가는 fail-closed로 간다.
        #   (hits가 0이면 이 분기 자체에 오지 않으므로 정상 작업이 막히지 않는다.)
        $gradeUnknown = -not (Get-Command Get-HighConfidenceSecretLabels -ErrorAction SilentlyContinue)
        if ($gradeUnknown) {
            $highConf = @($hits | Select-Object -Unique)
        } else {
            $hcLabels = @(Get-HighConfidenceSecretLabels)
            $highConf = @($hits | Where-Object { $hcLabels -contains $_ } | Select-Object -Unique)
        }

        # 우회는 전용 변수로만 — CLAUDE_HARNESS_QUICK을 쓰지 않는다. QUICK은 add-viewmodel·
        #   add-domain-service가 단독 사용 시 켜라고 안내하는 일상 변수라, 재사용하면 그 세션에서
        #   자격증명 차단까지 함께 꺼진다(block-destructive·protect-harness가 "QUICK도 무시"하는
        #   것과 같은 이유 — 안전 임계 게이트는 QUICK에 종속되지 않는다).
        $allowSecret = ($env:CLAUDE_HARNESS_ALLOW_SECRET -eq '1')

        if ($highConf.Count -gt 0 -and -not $allowSecret) {
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add("[HARNESS] BLOCKED: 커밋될 변경에 자격증명으로 보이는 값이 있습니다.")
            $lines.Add("")
            foreach ($h in $highConf) { $lines.Add("  - $h") }
            if ($gradeUnknown) {
                $lines.Add("")
                $lines.Add("  ! 시크릿 등급 판정 함수를 불러오지 못해 검출분을 전부 차단했습니다(secret-patterns.ps1 확인 필요).")
            }
            $lines.Add("")
            $lines.Add("공개 저장소에 한 번 올라가면 커밋 이력에 남아 회수할 수 없습니다.")
            $lines.Add("")
            $lines.Add("해결 방법:")
            $lines.Add("  1) 실제 값이면 — 파일에서 값을 지우고 환경변수 이름만 남긴 뒤(실제 값은 .env),")
            $lines.Add("     `git restore --staged <파일>` 로 스테이징에서 빼고 다시 commit")
            $lines.Add("  2) 오탐이면 — 사용자에게 보고하고 멈춥니다. 우회는 사용자만 설정합니다")
            $lines.Add("     (Claude Code 시작 전 터미널에서): `$env:CLAUDE_HARNESS_ALLOW_SECRET = '1'")
            $lines.Add("     Claude가 Bash 도구로 설정해도 hook 프로세스에 전파되지 않아 무효입니다.")
            return New-HookResult -Block $true -Stderr $lines
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("[COMMIT SECRET WARNING] 커밋될 스테이징된 변경에서 민감 정보로 보이는 내용이 감지되었습니다:")
        foreach ($h in ($hits | Select-Object -Unique)) { $lines.Add("  - $h") }
        foreach ($e in $envFiles) { $lines.Add("  - .env 파일 스테이징: $e (시크릿 파일이 커밋에 포함되려 합니다)") }
        if ($allowSecret -and $highConf.Count -gt 0) {
            $lines.Add("  * CLAUDE_HARNESS_ALLOW_SECRET=1 — 자격증명 차단이 우회된 상태입니다.")
        }
        $lines.Add("")
        $lines.Add("실제 값을 커밋하지 말고, .env(gitignore)로 분리하거나 스테이징에서 제외(git restore --staged <파일>)하세요.")
        $lines.Add("이 경고는 차단이 아닙니다 — 검토 후 진행하세요.")
        $msg = ($lines -join "`n")
        return New-HookResult -Block $false -Stderr @($msg) -Context $msg
    } finally {
        Set-Location -LiteralPath $origLoc
    }
}
