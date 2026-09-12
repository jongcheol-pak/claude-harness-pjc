# session-wiki-signals.ps1 — 세션 시작 주입의 위키 신호 3종 — 근거는 `rules/wiki-signals-rationale.md`의 「§1 session-wiki-signals.ps1 — 세션 시작 주입의 위키 신호 3종」

# Get-StaleFeatures — 허브가 가리키는 프로젝트의 feature 중 `updated` 이후 소스가 바뀐 것을 고른다.
#   현행 뒤처짐 신호는 프로젝트 단위 수치(N커밋 미반영)까지만 말해 **어느 페이지를 볼지가 통째로
#   사람 몫**이었다. 실측(회차 64): 이 프로젝트 feature 12건 중 8건이 updated 이후 소스 변경.
# ⚠ **이 파서는 `lint.py` 의 `## 관련 파일` 수집 규칙과 수동 동기화 대상이다** — 코드를 공유하지
#   않기로 했으므로(같은 판정을 두 벌 두지 않는다), 그쪽 형식이 바뀌면 여기도 확인해야 한다.
# ⚠ **상한과 타임아웃을 둔다** — vault 실측 최대가 31 feature 라 40 이면 현 vault 전체가 들어오고
#   이상 증식만 걸린다. 상한을 넘으면 **거기서 멈추되 「이하 미검사」를 남긴다**(조용히 자르면
#   0건과 구분되지 않는다). 10초는 `lint.py` 가 같은 목적으로 쓰는 값이라 새 상수를 만들지 않는다.
# ⚠ `Start-Job` 을 쓰지 않는다 — feature 마다 runspace 가 생겨 세션 시작이 수 초 늘어난다.
#   외부 프로세스를 직접 띄우고 `WaitForExit(ms)` 로 잰다.
function Get-StaleFeatures {
    param([string]$FeatureDir, [string]$RepoRoot)
    $scanCap = 40
    $result = @{ Names = @(); Truncated = $false }
    if (-not (Test-Path -LiteralPath $FeatureDir -PathType Container)) { return $result }
    if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { return $result }
    $files = @(Get-ChildItem -LiteralPath $FeatureDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $names = New-Object System.Collections.Generic.List[string]
    $seen = 0
    foreach ($f in $files) {
        if ($seen -ge $scanCap) { $result.Truncated = $true; break }
        $body = $null
        try { $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 } catch { continue }
        if (-not $body) { continue }
        if ($body -notmatch '(?m)^type:\s*feature\s*$') { continue }
        $seen++
        $um = [regex]::Match($body, '(?m)^updated:\s*(\d{4}-\d{2}-\d{2})')
        if (-not $um.Success) { continue }
        $upd = $um.Groups[1].Value
        # `## 관련 파일` 섹션의 백틱 토큰 중 **구분자를 포함한 것만** 경로로 본다
        #   (무구분자 토큰은 클래스·멤버명이라 오탐이 된다 — lint 쪽과 같은 필터).
        $sec = [regex]::Match($body, '(?ms)^##\s*관련 파일\b(.*?)(?=^##\s|\z)')
        if (-not $sec.Success) { continue }
        $paths = New-Object System.Collections.Generic.List[string]
        foreach ($pm in [regex]::Matches($sec.Groups[1].Value, '`([^`\r\n]+)`')) {
            $tok = $pm.Groups[1].Value
            if ($tok -notmatch '[/\\]') { continue }
            if (Test-Path -LiteralPath (Join-Path $RepoRoot $tok)) { $paths.Add($tok) }
        }
        if ($paths.Count -eq 0) { continue }
        # 경로 전체를 **한 번의 git log** 로 잰다 — 하나씩 재면 호출이 N배가 된다.
        $lastDate = $null
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'git'
            foreach ($arg in @('-C', $RepoRoot, 'log', '-1', '--format=%cI', '--')) { $null = $psi.ArgumentList.Add($arg) }
            foreach ($tok in $paths) { $null = $psi.ArgumentList.Add($tok) }
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $out = $proc.StandardOutput.ReadToEnd()
            if (-not $proc.WaitForExit(10000)) { try { $proc.Kill() } catch {}; continue }
            if ($proc.ExitCode -ne 0) { continue }
            $lastDate = ("$out").Trim()
        } catch { continue }
        if (-not $lastDate -or $lastDate.Length -lt 10) { continue }
        if ($lastDate.Substring(0, 10) -gt $upd) { $names.Add($f.Name) }
    }
    $result.Names = $names.ToArray()
    return $result
}

function Get-WikiSignals {
    param([string]$cwd)
    $vaultLine = $null; $staleLine = $null; $feedbackLine = $null
            # ---- 위키 vault 설정 상태 판정 — 근거는 `rules/session-context-rationale-wiki.md`의 「§23 ---- 위키 vault 설정 상태 판정」
            $vaultLine = $null
            $feedbackLine = $null              # 스킬 개선 큐 잔량 (하네스 레포 세션에서만 — 아래)
            $staleLine = $null                 # 위키 뒤처짐 (프로젝트를 가리지 않는다 — 아래)
            $userHome = [string]$env:USERPROFILE
            if (-not [string]::IsNullOrWhiteSpace($userHome)) {
                $vaultCfg = Join-Path $userHome '.claude/llm-wiki-config.json'
                if (Test-Path -LiteralPath $vaultCfg -PathType Leaf) {
                    $vaultPath = $null
                    # 손상 JSON·BOM·권한 오류는 조용히 통과(fail-open) — 세션 시작을 막지 않는다
                    try { $vaultPath = [string]((Get-Content -LiteralPath $vaultCfg -Raw -Encoding UTF8 | ConvertFrom-Json).vault_path) } catch {}
                    if (-not [string]::IsNullOrWhiteSpace($vaultPath)) {
                        if (Test-Path -LiteralPath $vaultPath -PathType Container) {
                            $vaultLine = "[pjc 세션 컨텍스트] 위키 vault: 설정됨 ($vaultPath) — 프로젝트 맥락이 필요하면 AGENTS.md의 '## 위키'가 지목한 허브를 먼저 Read하세요(판정 단서는 글로벌 지침 「프로젝트 맥락은 위키를 먼저 본다」). 읽고 쓰는 시점은 skills/WIKI.md 가 정본입니다. `"미설정`"으로 단정하지 마세요."

                            # ---- 스킬 개선 큐 잔량 — 근거는 `rules/session-context-rationale-wiki.md`의 「§24 ---- 스킬 개선 큐 잔량」
                            try {
                                $pluginJson = Join-Path $cwd 'plugins/pjc/.claude-plugin/plugin.json'
                                if (Test-Path -LiteralPath $pluginJson -PathType Leaf) {
                                    $fbPath = Join-Path $vaultPath 'skill-feedback.md'
                                    if (Test-Path -LiteralPath $fbPath -PathType Leaf) {
                                        $fbDates = @()
                                        foreach ($fbLine in (Get-Content -LiteralPath $fbPath -Encoding UTF8)) {
                                            $fbMatch = [regex]::Match($fbLine, '^\s*-\s*\[(\d{4}-\d{2}-\d{2})\]\s*\[SKILL-IMPROVE\]')
                                            if ($fbMatch.Success) { $fbDates += $fbMatch.Groups[1].Value }
                                        }
                                        if ($fbDates.Count -gt 0) {
                                            # @ — 근거는 `rules/session-context-rationale-wiki.md`의 「§25 @」
                                            $fbOldest = @($fbDates | Sort-Object)[0]
                                            $fbAge = [int]([math]::Floor(((Get-Date).Date - [datetime]::ParseExact($fbOldest, 'yyyy-MM-dd', $null)).TotalDays))
                                            $feedbackLine = "[pjc 세션 컨텍스트] 스킬 개선 큐(skill-feedback.md): 대기 $($fbDates.Count)건 / 최고령 ${fbAge}일 — pjc:plan Step 1이 할 일 후보로 조회합니다."
                                        }
                                    }
                                }
                            } catch {}

                            # ---- 위키 뒤처짐 알림 — 근거는 `rules/session-context-rationale-wiki.md`의 「§26 ---- 위키 뒤처짐 알림」
                            try {
                                $hubDir = Join-Path $vaultPath '20_projects'
                                if (Test-Path -LiteralPath $hubDir -PathType Container) {
                                    $cwdNorm = ($cwd -replace '\\', '/').TrimEnd('/')
                                    # cwd 의 origin URL 은 **루프 밖에서 1회만** 읽는다 — 근거는 `rules/session-context-rationale-wiki.md`의 「§27 cwd 의 origin URL 은 **루프 밖에서 1회만** 읽는다」
                                    $cwdUrl = ''
                                    try {
                                        $urlRaw = (& git -C $cwd remote get-url origin 2>$null | Select-Object -First 1)
                                        if ("$urlRaw" -match '^\S+://\S+$') {
                                            $cwdUrl = ("$urlRaw".Trim().ToLowerInvariant() -replace '\.git$', '').TrimEnd('/')
                                        }
                                    } catch {}
                                    # Depth 1 = `20_projects/<카테고리>/<프로젝트>.md` 까지. 그 아래 feature 파일
                                    #   (`.../<프로젝트>/feat-*.md`)은 허브가 아니라 대상에서 자연히 빠진다.
                                    foreach ($hubFile in (Get-ChildItem -LiteralPath $hubDir -Filter '*.md' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue)) {
                                        $hubText = $null
                                        try { $hubText = Get-Content -LiteralPath $hubFile.FullName -Raw -Encoding UTF8 } catch { continue }
                                        if (-not $hubText) { continue }

                                        # 축 ① URL — cwd 쪽 URL 을 읽은 경우에만 판정한다. — 근거는 `rules/session-context-rationale-wiki.md`의 「§28 축 ① URL — cwd 쪽 URL 을 읽은 경우에만 판정한다.」
                                        $hubUrl = ''
                                        if ($cwdUrl) {
                                            $urlMatch = [regex]::Match($hubText, '(?m)^repo_url:\s*"?([^"\r\n]+?)"?\s*$')
                                            if ($urlMatch.Success) {
                                                $hubUrl = ($urlMatch.Groups[1].Value.Trim().ToLowerInvariant() -replace '\.git$', '').TrimEnd('/')
                                            }
                                        }
                                        if ($hubUrl) {
                                            if ($hubUrl -ne $cwdUrl) { continue }
                                        } else {
                                            # 축 ② 경로 — URL 축이 꺼졌거나 허브에 `repo_url` 이 없을 때.
                                            $pathMatch = [regex]::Match($hubText, '(?m)^- \*\*경로\*\*:\s*`([^`]+)`')
                                            if (-not $pathMatch.Success) { continue }
                                            if ((($pathMatch.Groups[1].Value -replace '\\', '/').TrimEnd('/')) -ine $cwdNorm) { continue }
                                        }

                                        # ---- 이 허브가 현재 레포다 ----
                                        $projName = ''
                                        $projMatch = [regex]::Match($hubText, '(?m)^project:\s*"?([^"\r\n]+?)"?\s*$')
                                        if ($projMatch.Success) { $projName = $projMatch.Groups[1].Value }

                                        # 축 1 — synced_commit 이후 커밋 수(read-only 조회).
                                        $behind = -1
                                        $syncedSha = ''
                                        $shaMatch = [regex]::Match($hubText, '(?m)^synced_commit:\s*(\S+)')
                                        if ($shaMatch.Success) {
                                            $syncedSha = $shaMatch.Groups[1].Value
                                            # $LASTEXITCODE 를 게이트로 쓰지 않는다 — 이 hook은 앞서 다른 외부 — 근거는 `rules/session-context-rationale-wiki.md`의 「§29 $LASTEXITCODE 를 게이트로 쓰지 않는다 — 이 hook은 앞서 다른 외부」
                                            try {
                                                $countRaw = (& git -C $cwd rev-list --count "$syncedSha..HEAD" 2>$null | Select-Object -First 1)
                                                if ("$countRaw" -match '^\d+$') { $behind = [int]$countRaw }
                                            } catch {}
                                        }

                                        # 축 2 — 허브 updated 로부터의 경과일.
                                        $staleDays = -1
                                        $updMatch = [regex]::Match($hubText, '(?m)^updated:\s*(\d{4}-\d{2}-\d{2})')
                                        if ($updMatch.Success) {
                                            try {
                                                $updDate = [datetime]::ParseExact($updMatch.Groups[1].Value, 'yyyy-MM-dd', $null)
                                                $staleDays = [int]([math]::Floor(((Get-Date).Date - $updDate).TotalDays))
                                            } catch {}
                                        }

                                        # 축 3 — 이 프로젝트의 [K-DRIFT] 잔량. **대소문자를 무시**한다
                                        #   (큐 라벨이 허브 project 값과 대소문자만 다를 수 있다).
                                        $driftCount = 0
                                        if ($projName) {
                                            $pendPath = Join-Path $vaultPath 'pending.md'
                                            if (Test-Path -LiteralPath $pendPath -PathType Leaf) {
                                                $driftRx = '^\s*-\s*\[\d{4}-\d{2}-\d{2}\]\s*\[K-DRIFT\]\s*' + [regex]::Escape($projName) + '\s*:'
                                                foreach ($pendLine in (Get-Content -LiteralPath $pendPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
                                                    if ($pendLine -imatch $driftRx) { $driftCount++ }
                                                }
                                            }
                                        }

                                        # 계산된 축만 문구에 싣는다. 미계산 sentinel — 근거는 `rules/session-context-rationale-wiki.md`의 「§30 계산된 축만 문구에 싣는다. 미계산 sentinel」
                                        $behindKnown = ($behind -ge 0)
                                        $daysKnown = ($staleDays -ge 0)
                                        $behindHit = ($behindKnown -and ($behind -ge 30)) -or ($daysKnown -and ($staleDays -ge 14))
                                        if ($behindHit -or ($driftCount -ge 1)) {
                                            $label = if ($projName) { $projName } else { $hubFile.BaseName }
                                            # 뒤처짐 축이 둘 다 미달이면 수치를 싣지 않는다 — 잔량만이 신호다.
                                            $head = if ($behindHit) {
                                                if ($behindKnown -and $daysKnown) { "$label 위키가 ${behind}커밋 미반영 (synced: $syncedSha, ${staleDays}일 경과)" }
                                                elseif ($behindKnown) { "$label 위키가 ${behind}커밋 미반영 (synced: $syncedSha)" }
                                                else { "$label 위키가 ${staleDays}일째 미반영" }
                                            } else { "$label 위키 반영이 밀려 있습니다" }
                                            $driftPart = if ($driftCount -ge 1) { " · 미반영 발견 ${driftCount}건([K-DRIFT])" } else { '' }
                                            # 표적은 **발화가 확정된 뒤에만** 계산한다 — 축이 전부
                                            #   미달이면 표적을 낼 대상도 없고, 평소 세션 시작 비용이 0 으로 유지된다.
                                            $featPart = ''
                                            try {
                                                $sf = Get-StaleFeatures -FeatureDir (Join-Path $hubFile.DirectoryName $hubFile.BaseName) -RepoRoot $cwd
                                                if ($sf.Names.Count -gt 0) {
                                                    $top = (@($sf.Names | Select-Object -First 3) -join ', ')
                                                    $more = if ($sf.Names.Count -gt 3) { ' …' } else { '' }
                                                    $cap = if ($sf.Truncated) { ' · 40건까지만 검사' } else { '' }
                                                    $featPart = " · 뒤처진 feature $($sf.Names.Count)건: ${top}${more}${cap}"
                                                }
                                            } catch { }
                                            $staleLine = "[pjc 세션 컨텍스트] 위키 뒤처짐: ${head}${driftPart}${featPart} — 기능 목록·아키텍처 서술은 지도로만 쓰고 코드를 1차 출처로 하세요. 반영하려면 `"위키 업데이트`"라고 하세요."
                                        }
                                        break   # 허브 하나면 족하다 — 같은 경로를 가리키는 둘째가 있어도 라인을 두 번 내지 않는다
                                    }
                                }
                            } catch {}
                        } else {
                            # 파일을 가리키는 경우도 여기로 온다(-PathType Container 실패) — vault로 쓸 수 없으므로 부재와 동일 취급
                            $vaultLine = "[pjc 세션 컨텍스트] 위키 vault: 설정 경로 부재 ($vaultPath) — 조용히 통과하되 확인한 사실을 1줄 기록하세요(형식은 skills/WIKI.md 의 기록 의무). 위키 작업 요청 시 경로 재확인이 필요합니다."
                        }
                    }
                }
            }
    return @{ VaultLine = $vaultLine; StaleLine = $staleLine; FeedbackLine = $feedbackLine }
}
