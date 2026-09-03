# guard-commit-secrets.ps1 — git commit 직전 스테이징 변경의 시크릿 검사 (dot-source 전용, hook 아님) — 근거는 `rules/commit-secrets-rationale.md`의 「§1 guard-commit-secrets.ps1 — git commit 직전 스테이징 변경의 시크릿 검사 (dot-source 전용, hook 아님)」

# warn-commit-secrets: git commit 직전 스테이징될 변경에서 시크릿 패턴 경고(비차단) — 근거는 `rules/commit-secrets-rationale.md`의 「§2 warn-commit-secrets: git commit 직전 스테이징될 변경에서 시크릿 패턴 경고(비차단)」
function New-HookResult {
    param([bool]$Block = $false, [string[]]$Stderr = @(), [string]$Context = $null)
    return @{ Block = $Block; Stderr = $Stderr; Context = $Context }
}

function Get-DiffHeadAdded {
    param([string[]]$PathArgs = @())
    $out = if ($PathArgs.Count) { @(& git diff HEAD --unified=0 -- $PathArgs 2>$null) }
           else { @(& git diff HEAD --unified=0 2>$null) }
    if ($LASTEXITCODE -ne 0) {
        $scope = if ($PathArgs.Count) { ($PathArgs -join ' ') } else { '전체' }
        # ⚠ `Write-Warning`을 쓰지 않는다 — 근거는 `rules/commit-secrets-rationale.md`의 「§3 ⚠ `Write-Warning`을 쓰지 않는다」
        if (-not $script:diffHeadFailNotified) {
            [Console]::Error.WriteLine("[warn-commit-secrets] git diff HEAD 실패(exit $LASTEXITCODE) — 보완 스캔 미수행: $scope. " +
                                       'HEAD 없는 초기 저장소면 정상이며 --cached 경로가 그대로 검사한다.')
            $script:diffHeadFailNotified = $true
        }
        return @()
    }
    return @($out | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })
}

function Invoke-WarnCommitSecrets {
    param($data)
    # 실패 경고 1회 억제 플래그를 **호출마다 리셋**한다 — 근거는 `rules/commit-secrets-rationale.md`의 「§4 실패 경고 1회 억제 플래그를 **호출마다 리셋**한다」
    $script:diffHeadFailNotified = $false
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

        # -a/-am/--all이면 추적 파일 자동 스테이징분 — 근거는 `rules/commit-secrets-rationale.md`의 「§5 -a/-am/--all이면 추적 파일 자동 스테이징분」
        $cmdFlags = $cmd -replace '(?i)(^|\s)(-[a-zA-Z]*m|--message)(=|\s+)("[^"]*"|''[^'']*''|\S+)', '$1$2'
        # 셸 줄 연속 — 근거는 `rules/commit-secrets-rationale.md`의 「§6 셸 줄 연속」
        $commitSeg = @(($cmdFlags -replace '\\\r?\n\s*', ' ') -split '(\|\||&&|[;|]|\r?\n)' |
            Where-Object { $_ -match 'git\s+((-c|-C)\s+\S+\s+)*commit\b' })
        # 분리 결과가 비면 전체 명령으로 되돌아간다 — 정규화가 못 잡은 표기에서 판정 대상을
        #   잃느니 종전처럼 넓게 보는 편이 안전하다(스캔이 한 번 더 도는 대가로 미탐을 막는다).
        if (-not $commitSeg.Count) { $commitSeg = @($cmdFlags) }
        $commitFlags = $commitSeg -join ' '
        $autoStage = ($commitFlags -match '(^|\s)-[a-zA-Z]*a[a-zA-Z]*(\s|$)') -or ($commitFlags -match '(^|\s)--all(\s|$)')
        if ($autoStage) {
            $addedLines += Get-DiffHeadAdded
        }

        # 선행 스테이징 인지 — 근거는 `rules/commit-secrets-rationale.md`의 「§7 선행 스테이징 인지」
        $capHit = $false
        $addMatch = [regex]::Match($cmd, '(?i)git\s+((-c|-C)\s+\S+\s+)*add\s+([^&;|\r\n]*)')
        if ($addMatch.Success) {
            $addArgs = $addMatch.Groups[3].Value.Trim()
            $addTargets = @()
            # 스캔 캡은 **추적 파일 분기와 공유한다** — 근거는 `rules/commit-secrets-rationale.md`의 「§8 스캔 캡은 **추적 파일 분기와 공유한다**」
            $scanned = 0
            $capNotified = $false
            if ($addArgs -match '(^|\s)(-A|--all|-u|--update|\.)(\s|$)') {
                # 전체 스테이징: untracked + 추적 파일 수정분
                $addTargets = @(& git ls-files --others --exclude-standard 2>$null)
                $addedLines += Get-DiffHeadAdded
            } else {
                # 경로 나열: 플래그를 뺀 인자만 대상으로 본다. — 근거는 `rules/commit-secrets-rationale.md`의 「§9 경로 나열: 플래그를 뺀 인자만 대상으로 본다.」
                $rawTargets = @($addArgs -split '\s+' | Where-Object { $_ -and -not $_.StartsWith('-') } |
                    ForEach-Object { $_.Trim('"', "'") })
                foreach ($rt in $rawTargets) {
                    if ($scanned -ge 50) {
                        $capHit = $true
                        if (-not $capNotified) {
                            [Console]::Error.WriteLine('[warn-commit-secrets] 스캔 대상 50개 상한 도달 (경로 나열) — 초과분을 검사하지 못해 커밋을 차단합니다.')
                            $capNotified = $true
                        }
                        break
                    }
                    if (Test-Path -LiteralPath $rt -PathType Leaf) {
                        # 추적 파일은 diff HEAD 추가 라인만 스캔 — 이력에 이미 있는 내용 — 근거는 `rules/commit-secrets-rationale.md`의 「§10 추적 파일은 diff HEAD 추가 라인만 스캔 — 이력에 이미 있는 내용」
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

            # 파일 수·크기 상한 — hook은 매 커밋마다 도는 경로라 무제한 정독은 지연을 만든다. — 근거는 `rules/commit-secrets-rationale.md`의 「§11 파일 수·크기 상한 — hook은 매 커밋마다 도는 경로라 무제한 정독은 지연을 만든다.」
            foreach ($t in $addTargets) {
                if ($scanned -ge 50) {
                    $capHit = $true
                    if (-not $capNotified) {
                        [Console]::Error.WriteLine('[warn-commit-secrets] 스캔 대상 50개 상한 도달 (신규 파일 정독) — 초과분을 검사하지 못해 커밋을 차단합니다.')
                        $capNotified = $true
                    }
                    break
                }
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

        # `-and -not $capHit` — 캡에 걸렸으면 **검출 0건이어도 여기서 빠져나가면 안 된다** — 근거는 `rules/commit-secrets-rationale.md`의 「§12 `-and -not $capHit` — 캡에 걸렸으면 **검출 0건이어도 여기서 빠져나가면 안 된다**」
        if ($hits.Count -eq 0 -and $envFiles.Count -eq 0 -and -not $capHit) { return New-HookResult }

        # 고신뢰 라벨 — 근거는 `rules/commit-secrets-rationale.md`의 「§13 고신뢰 라벨」
        $gradeUnknown = -not (Get-Command Get-HighConfidenceSecretLabels -ErrorAction SilentlyContinue)
        if ($gradeUnknown) {
            $highConf = @($hits | Select-Object -Unique)
        } else {
            $hcLabels = @(Get-HighConfidenceSecretLabels)
            $highConf = @($hits | Where-Object { $hcLabels -contains $_ } | Select-Object -Unique)
        }

        # 우회는 전용 변수로만 — CLAUDE_HARNESS_QUICK을 쓰지 않는다. — 근거는 `rules/commit-secrets-rationale.md`의 「§14 우회는 전용 변수로만 — CLAUDE_HARNESS_QUICK을 쓰지 않는다.」
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
            # 캡에도 걸렸으면 그 사실을 부기한다 — 검출된 것 말고도 **못 본 파일이 있다**는 정보가
            #   사용자 판단에 필요하다(검출분만 지우면 통과할 것으로 오인하지 않게).
            if ($capHit) {
                $lines.Add("")
                $lines.Add("  ! 스캔 대상 50개 상한에도 걸려 일부 파일은 아예 검사하지 못했습니다 — 위 목록이 전부가 아닐 수 있습니다.")
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

        # 캡 차단 — 근거는 `rules/commit-secrets-rationale.md`의 「§15 캡 차단」
        if ($capHit -and -not $allowSecret) {
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add("[HARNESS] BLOCKED: 커밋될 파일이 많아 시크릿 검사를 끝까지 하지 못했습니다.")
            $lines.Add("")
            $lines.Add("  - 스캔 대상 50개 상한에 도달해 초과분은 검사하지 않았습니다.")
            # 저신뢰 검출분·.env 스테이징은 원래 경고 경로로 나가던 정보다 — 근거는 `rules/commit-secrets-rationale.md`의 「§16 저신뢰 검출분·.env 스테이징은 원래 경고 경로로 나가던 정보다」
            if ($hits.Count -eq 0) {
                $lines.Add("  - 검사한 범위에서 검출된 시크릿은 없습니다.")
            } else {
                $lines.Add("  - 검사한 범위에서 아래가 감지됐습니다(차단 등급은 아니지만 확인 필요):")
                foreach ($h in ($hits | Select-Object -Unique)) { $lines.Add("      - $h") }
            }
            foreach ($e in $envFiles) { $lines.Add("  - .env 파일 스테이징: $e (시크릿 파일이 커밋에 포함되려 합니다)") }
            $lines.Add("")
            $lines.Add("검사하지 못한 파일에 자격증명이 있어도 통과하므로 차단합니다 — 커밋되면 이력에서 회수할 수 없습니다.")
            $lines.Add("")
            $lines.Add("해결 방법:")
            $lines.Add("  1) 커밋을 나눠 한 번에 50개 이하로 스테이징한 뒤 다시 commit")
            $lines.Add("  2) 나눌 수 없으면 — 사용자에게 보고하고 멈춥니다. 우회는 사용자만 설정합니다")
            $lines.Add("     (Claude Code 시작 전 터미널에서): `$env:CLAUDE_HARNESS_ALLOW_SECRET = '1'")
            $lines.Add("     Claude가 Bash 도구로 설정해도 hook 프로세스에 전파되지 않아 무효입니다.")
            return New-HookResult -Block $true -Stderr $lines
        }

        # 캡에 걸렸는데 우회가 켜져 있으면 **캡 사유로** 알린다 — 아래 시크릿 경고 문면을 쓰면
        #   검출 0건일 때 항목 없는 "민감 정보 감지" 경고가 나가 사유를 잘못 가리킨다.
        if ($capHit -and $hits.Count -eq 0) {
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add("[COMMIT SECRET WARNING] 커밋될 파일이 많아 시크릿 검사를 끝까지 하지 못했습니다(50개 상한).")
            foreach ($e in $envFiles) { $lines.Add("  - .env 파일 스테이징: $e (시크릿 파일이 커밋에 포함되려 합니다)") }
            $lines.Add("  * CLAUDE_HARNESS_ALLOW_SECRET=1 — 차단이 우회된 상태입니다.")
            $msg = ($lines -join "`n")
            return New-HookResult -Block $false -Stderr @($msg) -Context $msg
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("[COMMIT SECRET WARNING] 커밋될 스테이징된 변경에서 민감 정보로 보이는 내용이 감지되었습니다:")
        foreach ($h in ($hits | Select-Object -Unique)) { $lines.Add("  - $h") }
        foreach ($e in $envFiles) { $lines.Add("  - .env 파일 스테이징: $e (시크릿 파일이 커밋에 포함되려 합니다)") }
        if ($allowSecret -and $highConf.Count -gt 0) {
            $lines.Add("  * CLAUDE_HARNESS_ALLOW_SECRET=1 — 자격증명 차단이 우회된 상태입니다.")
        }
        # 캡 부기는 **이 경로에도** 필요하다 — 근거는 `rules/commit-secrets-rationale.md`의 「§17 캡 부기는 **이 경로에도** 필요하다」
        if ($capHit) {
            $lines.Add("  ! 스캔 대상 50개 상한에도 걸려 일부 파일은 아예 검사하지 못했습니다 — 위 목록이 전부가 아닐 수 있습니다.")
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
