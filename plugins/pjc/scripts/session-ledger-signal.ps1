# session-ledger-signal.ps1 — 세션 시작 주입의 Deferred 대장 최고령 신호 (dot-source 전용, hook 아님) — 근거는 `rules/ledger-signal-rationale.md`의 「§1 session-ledger-signal.ps1 — 세션 시작 주입의 Deferred 대장 최고령 신호 (dot-source 전용, hook 아님)」

function Get-LedgerSignal {
    param([string]$cwd)
    $ledgerLine = $null
            # ---- Deferred 대장 최고령 「마지막 판정일」 — 근거는 `rules/session-context-rationale.md`의 「§12 # ---- Deferred 대장 최고령 「마지막 판정일」」
            try {
                $ledgerPluginJson = Join-Path $cwd 'plugins/pjc/.claude-plugin/plugin.json'
                $ledgerPath = Join-Path $cwd 'docs/plans/deferred.md'
                if ((Test-Path -LiteralPath $ledgerPluginJson -PathType Leaf) -and (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
                    $ledgerText = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8
                    # 종료 앵커 `^## `는 현재 대장에 `## 대기` 하나뿐이라 실질적으로 `\z`로 끝난다. — 근거는 `rules/session-context-rationale.md`의 「§13 # 종료 앵커 `^## `는 현재 대장에 `## 대기` 하나뿐이라 실질적으로 `\z`로 끝난다.」
                    $ledgerWait = [regex]::Match($ledgerText, '(?ms)^## 대기\s*?$(.*?)(?=^## |\z)')
                    if ($ledgerWait.Success) {
                        $ledgerItemRx = [regex]'^- \[\d{4}-\d{2}-\d{2}'
                        $ledgerDateRx = [regex]'[\[(](\d{4}-\d{2}-\d{2})'
                        # vN 부기는 형식이 둘이다 — ⓐ 날짜 접두 — 근거는 `rules/session-context-rationale.md`의 「§14 # vN 부기는 형식이 둘이다 — ⓐ 날짜 접두」
                        $ledgerVnPrefixRx = [regex]'^- \[\d{4}-\d{2}-\d{2}, '
                        $ledgerVnTailRx = [regex]'\(v\d+\.\d+\.\d+[^)]*해소\)'
                        # 항목이 아닌 구조 줄 — 앵커 — 근거는 `rules/session-context-rationale.md`의 「§15 # 항목이 아닌 구조 줄 — 앵커」
                        $ledgerStructRx = [regex]'^\s*(?:>|\*\*▶)'
                        $ledgerToday = (Get-Date).Date

                        $ledgerItems = New-Object System.Collections.Generic.List[string]
                        $ledgerCur = $null
                        foreach ($ledgerLine in ($ledgerWait.Groups[1].Value -split "`r?`n")) {
                            if ($ledgerItemRx.IsMatch($ledgerLine)) {
                                if ($null -ne $ledgerCur) { $ledgerItems.Add($ledgerCur) }
                                $ledgerCur = $ledgerLine
                            } elseif ($null -ne $ledgerCur -and -not $ledgerStructRx.IsMatch($ledgerLine)) {
                                $ledgerCur = $ledgerCur + "`n" + $ledgerLine
                            }
                        }
                        if ($null -ne $ledgerCur) { $ledgerItems.Add($ledgerCur) }

                        $ledgerJudged = @()
                        $ledgerVnCount = 0
                        foreach ($ledgerItem in $ledgerItems) {
                            $ledgerBest = $null
                            foreach ($ledgerHit in $ledgerDateRx.Matches($ledgerItem)) {
                                $ledgerDate = $null
                                # 형식은 맞지만 의미가 무효인 문자열(2026-13-45 등)은 그 날짜만 건너뛴다 —
                                #   항목 자체를 버리면 그 항목이 최고령 후보에서 통째로 빠진다.
                                try { $ledgerDate = [datetime]::ParseExact($ledgerHit.Groups[1].Value, 'yyyy-MM-dd', $null) } catch { continue }
                                if ($ledgerDate -gt $ledgerToday) { continue }
                                if ($null -eq $ledgerBest -or $ledgerDate -gt $ledgerBest) { $ledgerBest = $ledgerDate }
                            }
                            if ($null -ne $ledgerBest) { $ledgerJudged += $ledgerBest }
                            $ledgerHead = ($ledgerItem -split "`n")[0]
                            if ($ledgerVnPrefixRx.IsMatch($ledgerHead) -or $ledgerVnTailRx.IsMatch($ledgerHead)) { $ledgerVnCount++ }
                        }

                        if ($ledgerItems.Count -gt 0 -and $ledgerJudged.Count -gt 0) {
                            # @() 로 감싸는 것이 요점이다 — 항목이 **1건이면** 파이프 결과가 배열이 아니라
                            #   스칼라라 [0] 이 엉뚱한 값을 준다(아래 스킬 개선 큐 라인이 같은 사고를 겪었다).
                            $ledgerOldest = @($ledgerJudged | Sort-Object)[0]
                            $ledgerAge = [int][math]::Floor(($ledgerToday - $ledgerOldest).TotalDays)
                            $ledgerVnNote = if ($ledgerVnCount -gt 0) { " (단 vN 부기 ${ledgerVnCount}건은 릴리즈 날짜를 반영하지 않았습니다 — 손계산 확인 필요.)" } else { "" }
                            $ledgerLine = ("[pjc 세션 컨텍스트] Deferred 대장: 대기 $($ledgerItems.Count)건 / 최고령 ${ledgerAge}일($($ledgerOldest.ToString('yyyy-MM-dd'))) — 축 ② 임계 30일.${ledgerVnNote}")
                            # 이 라인은 **vault 게이팅 신호가 아니다** — 근거는 `rules/session-context-rationale.md`의 「§16 이 라인은 **vault 게이팅 신호가 아니다**」
                            }
                    }
                }
            } catch {}
    return $ledgerLine
}
