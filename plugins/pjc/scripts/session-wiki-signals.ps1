# session-wiki-signals.ps1 — 세션 시작 주입의 위키 신호 3종 — 근거는 `rules/wiki-signals-rationale.md`의 「§1 session-wiki-signals.ps1 — 세션 시작 주입의 위키 신호 3종」

function Get-WikiSignals {
    param([string]$cwd)
    $vaultLine = $null; $staleLine = $null; $feedbackLine = $null
            # ---- 위키 vault 설정 상태 판정 — 근거는 `rules/session-context-rationale.md`의 「§23 ---- 위키 vault 설정 상태 판정」
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
                            $vaultLine = "[pjc 세션 컨텍스트] 위키 vault: 설정됨 ($vaultPath) — 프로젝트 맥락이 필요하면 AGENTS.md의 '## 위키'가 지목한 허브를 먼저 Read하세요(판정 단서는 글로벌 지침 「프로젝트 맥락은 위키를 먼저 본다」). 절차 K 참조 가능. `"미설정`"으로 단정하지 마세요."

                            # ---- 스킬 개선 큐 잔량 — 근거는 `rules/session-context-rationale.md`의 「§24 ---- 스킬 개선 큐 잔량」
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
                                            # @ — 근거는 `rules/session-context-rationale.md`의 「§25 @」
                                            $fbOldest = @($fbDates | Sort-Object)[0]
                                            $fbAge = [int]([math]::Floor(((Get-Date).Date - [datetime]::ParseExact($fbOldest, 'yyyy-MM-dd', $null)).TotalDays))
                                            $feedbackLine = "[pjc 세션 컨텍스트] 스킬 개선 큐(skill-feedback.md): 대기 $($fbDates.Count)건 / 최고령 ${fbAge}일 — pjc:plan Step 1이 할 일 후보로 조회합니다."
                                        }
                                    }
                                }
                            } catch {}

                            # ---- 위키 뒤처짐 알림 — 근거는 `rules/session-context-rationale.md`의 「§26 ---- 위키 뒤처짐 알림」
                            try {
                                $hubDir = Join-Path $vaultPath '20_projects'
                                if (Test-Path -LiteralPath $hubDir -PathType Container) {
                                    $cwdNorm = ($cwd -replace '\\', '/').TrimEnd('/')
                                    # cwd 의 origin URL 은 **루프 밖에서 1회만** 읽는다 — 근거는 `rules/session-context-rationale.md`의 「§27 cwd 의 origin URL 은 **루프 밖에서 1회만** 읽는다」
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

                                        # 축 ① URL — cwd 쪽 URL 을 읽은 경우에만 판정한다. — 근거는 `rules/session-context-rationale.md`의 「§28 축 ① URL — cwd 쪽 URL 을 읽은 경우에만 판정한다.」
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
                                            # $LASTEXITCODE 를 게이트로 쓰지 않는다 — 이 hook은 앞서 다른 외부 — 근거는 `rules/session-context-rationale.md`의 「§29 $LASTEXITCODE 를 게이트로 쓰지 않는다 — 이 hook은 앞서 다른 외부」
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

                                        # 계산된 축만 문구에 싣는다. 미계산 sentinel — 근거는 `rules/session-context-rationale.md`의 「§30 계산된 축만 문구에 싣는다. 미계산 sentinel」
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
                                            $staleLine = "[pjc 세션 컨텍스트] 위키 뒤처짐: ${head}${driftPart} — 기능 목록·아키텍처 서술은 지도로만 쓰고 코드를 1차 출처로 하세요. 반영하려면 `"위키 업데이트`"라고 하세요."
                                        }
                                        break   # 허브 하나면 족하다 — 같은 경로를 가리키는 둘째가 있어도 라인을 두 번 내지 않는다
                                    }
                                }
                            } catch {}
                        } else {
                            # 파일을 가리키는 경우도 여기로 온다(-PathType Container 실패) — vault로 쓸 수 없으므로 부재와 동일 취급
                            $vaultLine = "[pjc 세션 컨텍스트] 위키 vault: 설정 경로 부재 ($vaultPath) — 절차 K는 조용히 통과하되 건너뛴 사실을 K 1 형식으로 1줄 기록하세요. 위키 작업 요청 시 경로 재확인이 필요합니다."
                        }
                    }
                }
            }
    return @{ VaultLine = $vaultLine; StaleLine = $staleLine; FeedbackLine = $feedbackLine }
}
