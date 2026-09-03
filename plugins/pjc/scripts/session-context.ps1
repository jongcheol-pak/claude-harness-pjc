# session-context.ps1 — SessionStart: 로컬 plan 상태 요약 + AGENTS.m — 근거는 `rules/session-context-rationale.md`의 「§1 session-context.ps1 — SessionStart: 로컬 plan 상태 요약 + AGENTS.m」

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로가 깨져 plan 탐색이 어긋난다. 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# [고아 프로세스 회수] 세션 시작 시점에 이전 세션이 남긴 — 근거는 `rules/session-context-rationale.md`의 「§2 [고아 프로세스 회수] 세션 시작 시점에 이전 세션이 남긴」
try { . (Join-Path $PSScriptRoot 'session-end-cleanup-lib.ps1'); $null = Invoke-OrphanProcessCleanup -Hook 'session-context' } catch {}

# [절 추출] 스킬 문서에서 지정 헤딩 사이를 잘라 낸다 — compact 직후 루프 제어 규칙 주입용. — 근거는 `rules/session-context-rationale.md`의 「§3 [절 추출] 스킬 문서에서 지정 헤딩 사이를 잘라 낸다 — compact 직후 루프 제어 규칙 주입용.」
$sectionMaxBytes = 20000   # 추출 결과 상한 — 대상 절이 예상 밖으로 커졌을 때 주입이 세션을 잠식하는 것을 막는다
function Get-SkillSection {
    param([string]$Path, [string]$StartHeading, [string]$StopHeading)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($raw)) { return $null }
        # 헤딩 비교는 TrimEnd() 후 완전 일치 — 부분 일치를 쓰면 `###`가 같은 이름의 `##`를 먼저 문다.
        $lines = $raw -split "`r?`n"
        $startIdx = -1; $stopIdx = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].TrimEnd()
            if ($startIdx -lt 0) { if ($t -eq $StartHeading) { $startIdx = $i } }
            elseif ($t -eq $StopHeading) { $stopIdx = $i; break }
        }
        if ($startIdx -lt 0) { return $null }
        # 종료 앵커가 없으면 파일 끝까지 — 대상 절이 파일 마지막일 수 있다(에러가 아니다).
        $text = ($lines[$startIdx..($stopIdx - 1)] -join "`n").TrimEnd()
        if ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $sectionMaxBytes) { return $null }
        return $text
    } catch { return $null }
}

try {
    # ---- 입력 파싱 (cwd·source) ----
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $inp = $null
    try { $inp = $raw | ConvertFrom-Json } catch { exit 0 }
    $cwd = [string]$inp.cwd
    $source = [string]$inp.source   # startup|resume|clear|compact|fork (부재 시 빈 문자열 → 비compact 취급. fork는 compact가 아니라 startup과 같은 경로를 탄다)

    $lines = New-Object System.Collections.Generic.List[string]

    # ---- compact 리마인더 (plan 유무 무관) ----
    if ($source -eq 'compact') {
        $lines.Add("[pjc 세션 컨텍스트] 컨텍스트 요약 직후입니다 — 진행 중이던 작업이 있으면 plan.md의 현재 task와 활성 스킬(pjc:implement 등)의 중단 조건·승인 게이트·커밋 프로토콜을 요약 기억에 의존하지 말고 SKILL 문서·plan.md 원문에서 재확인하세요. 그리고 **아직 plan.md에 적지 않은** 발견(이연할 항목·확인된 사실)이 요약 전에 있었다면 지금 plan.md에 적으세요 — 대화에만 있던 것은 요약을 지나면 근거 없이 사라집니다.")
    }

    if (-not [string]::IsNullOrWhiteSpace($cwd) -and (Test-Path -LiteralPath $cwd -PathType Container)) {
        # # cwd 수집으로 라인이 늘었는지 판정하는 기준 개수 — vault 라인 게이팅에 쓴다. — 근거는 `rules/session-context-rationale.md`의 「§4 # cwd 수집으로 라인이 늘었는지 판정하는 기준 개수 — vault 라인 게이팅에 쓴다.」
        $cwdBaseCount = $lines.Count

        # # ---- plan 탐색: 루트 plan.md 하나 — 근거는 `rules/session-context-rationale.md`의 「§5 # ---- plan 탐색: 루트 plan.md 하나」
        $rootPlan = Join-Path $cwd 'plan.md'
        $planPath = $null
        $planLabel = $null
        if (Test-Path -LiteralPath $rootPlan -PathType Leaf) {
            $planPath = $rootPlan
            $planLabel = 'plan.md'
        }

        # # 압축 직후 절 원문 주입이 쓰는 스킬 폴더 — 구현 세션 분기와 계획 세션 분기가 배타적이라 — 근거는 `rules/session-context-rationale.md`의 「§6 # 압축 직후 절 원문 주입이 쓰는 스킬 폴더 — 구현 세션 분기와 계획 세션 분기가 배타적이라」
        $skillsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'

        if ($planPath) {
            $planText = $null
            try { $planText = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 } catch {}
            if ($planText) {
                # task 라인만 카운트 (pjc plan 규약: "- [x] T1: ..." — 통과 체크리스트 등 다른 체크박스 제외)
                $all = [regex]::Matches($planText, '(?m)^- \[[ /x]\] T\d+').Count
                $open = [regex]::Matches($planText, '(?m)^- \[[ /]\] T\d+').Count

                # # ---- Deferred 미판정 계수 — 근거는 `rules/session-context-rationale.md`의 「§7 # ---- Deferred 미판정 계수」
                $defUnjudged = 0
                $defMatch = [regex]::Match($planText, '(?ms)^## Deferred / Follow-up\s*?$(.*?)(?=^## |\z)')
                if ($defMatch.Success) {
                    foreach ($defLine in ($defMatch.Groups[1].Value -split "`r?`n")) {
                        if ($defLine -notmatch '^- ') { continue }
                        # # `- ` 접두와 있으면 마커까지 벗겨 낸 뒤 본문을 본다 — 마커 그룹이 — 근거는 `rules/session-context-rationale.md`의 「§8 # `- ` 접두와 있으면 마커까지 벗겨 낸 뒤 본문을 본다 — 마커 그룹이」
                        if (($defLine -replace '^- (?:\[[^\]]*\]\s*)?', '') -match '^<') { continue }   # 템플릿 placeholder
                        if ($defLine -match '^- \[등재\]') { continue }
                        # # 기호는 닫는 대괄호가 아닌 문자 1자 이상이어야 한다 — 사유 없는 — 근거는 `rules/session-context-rationale.md`의 「§9 # 기호는 닫는 대괄호가 아닌 문자 1자 이상이어야 한다 — 사유 없는」
                        if ($defLine -match '^- \[미등재:[^\]]+\]') { continue }
                        $defUnjudged++
                    }
                }
                # 기존 라인 **뒤에** 붙인다 — 앞에 끼우면 `미완료 2`·`전부 완료`·`존재`를 부분문자열로
                #   재는 기존 골든 7건이 살아남더라도 사람이 읽는 순서가 뒤집힌다.
                $defNote = if ($defUnjudged -gt 0) { " · **Deferred 미판정 ${defUnjudged}건** — 대장(docs/plans/deferred.md) 등재 판정이 남아 있습니다(F-6.5)." } else { "" }
                if ($all -gt 0) {
                    if ($open -gt 0) {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 중 미완료 ${open}개 — 작업 시작 전 plan.md 진행 상태를 확인하세요.${defNote}")
                        # # 압축 직후 + 미완료 task = 자율 루프가 규칙을 잃은 채 재개될 최위험 조합. — 근거는 `rules/session-context-rationale.md`의 「§10 # 압축 직후 + 미완료 task = 자율 루프가 규칙을 잃은 채 재개될 최위험 조합.」
                        if ($source -eq 'compact') {
                            # ⚠ 경로 리터럴을 보존한다 — 골든이 ExpectContains로 재고 있어, 문면을 다듬다
                            #   경로가 빠지면 즉시 FAIL한다. 조정 대상은 경로를 감싸는 서술뿐이다.
                            $lines.Add("[pjc 세션 컨텍스트] 진행 중 plan이 있습니다 — 아래에 자율 루프 규칙 원문을 함께 주입했습니다. 그 밖의 절차가 필요하면 Read로 확인하세요(스킬 재invoke로는 복구되지 않습니다): implement/SKILL.md. 그 파일이 참조하는 WIKI.md도 필요하면 함께 읽으세요.")

                            # # 경로만 지시하면 실제로 읽었는지 검증할 장치가 없다. 루프가 멈추는 것을 막는 — 근거는 `rules/session-context-rationale.md`의 「§11 # 경로만 지시하면 실제로 읽었는지 검증할 장치가 없다. 루프가 멈추는 것을 막는」
                            $secRules = Get-SkillSection -Path (Join-Path $skillsDir 'implement/SKILL.md') -StartHeading '## 자율 루프' -StopHeading '## 검증'
                            if ($secRules) { $lines.Add("[pjc 세션 컨텍스트] 압축 직후 루프 제어 규칙 (원문 발췌 — implement/SKILL.md 「자율 루프」)`n$secRules") }
                        }
                    } else {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 전부 완료 — 새 작업이면 plan 교체 전 Deferred/Follow-up 잔여 항목을 확인하세요.${defNote}")
                    }
                } else {
                    # task 체크박스가 없는 plan.md(비 pjc 형식) — 카운트 오보 대신 존재만 알림
                    $lines.Add("[pjc 세션 컨텍스트] ${planLabel} 존재 — 작업 시작 전 진행 상태를 확인하세요.${defNote}")
                }
            }
        }

        # Deferred 대장 최고령 신호는 `session-ledger-signal.ps1`이 계산한다 —
        #   그 신호만 대장 3파일을 파싱해(항목별 날짜 부기 인식·미래 날짜 배제) 입력이 다르다.
        . (Join-Path $PSScriptRoot 'session-ledger-signal.ps1')
        $ledgerLine = Get-LedgerSignal -cwd $cwd
        if ($ledgerLine) { $lines.Add($ledgerLine); $cwdBaseCount++ }

        # # ---- 계획 세션의 압축 리마인더 — 근거는 `rules/session-context-rationale.md`의 「§17 # ---- 계획 세션의 압축 리마인더」
        if ($source -eq 'compact' -and (-not $planPath -or $all -eq 0 -or $open -eq 0) -and ($planPath -or (Test-Path -LiteralPath (Join-Path $cwd 'AGENTS.md')))) {
            $lines.Add("[pjc 세션 컨텍스트] 계획을 세우던 중이었다면 — plan/SKILL.md를 Read로 재확인하세요(스킬 재invoke로는 복구되지 않습니다). 인터뷰 절차·영향 범위 실측·작업 분해가 요약으로 뭉개집니다.")
            # # 이 줄은 compact 리마인더라 vault 게이팅 신호가 아니다 — 기존 리마인더 — 근거는 `rules/session-context-rationale.md`의 「§18 # 이 줄은 compact 리마인더라 vault 게이팅 신호가 아니다 — 기존 리마인더」
            $cwdBaseCount++

            # # 경로만 지시하면 읽었는지 검증할 수 없다. 계획이 추측으로 흐르는 것을 막는 절 하나만 — 근거는 `rules/session-context-rationale.md`의 「§19 # 경로만 지시하면 읽었는지 검증할 수 없다. 계획이 추측으로 흐르는 것을 막는 절 하나만」
            $secPlanRules = Get-SkillSection -Path (Join-Path $skillsDir 'plan/SKILL.md') -StartHeading '## Step 3. 영향 범위 실측' -StopHeading '## Step 4. 작업 분해'
            if ($secPlanRules) {
                $lines.Add("[pjc 세션 컨텍스트] 압축 직후 계획 규칙 (원문 발췌 — plan/SKILL.md 「영향 범위 실측」)`n$secPlanRules")
                # # 위 리마인더와 같은 이유로 기준선을 함께 올린다 — 이 분기는 「줄 1개 추가 = 기준선 1 증가」가 — 근거는 `rules/session-context-rationale.md`의 「§20 # 위 리마인더와 같은 이유로 기준선을 함께 올린다 — 이 분기는 「줄 1개 추가 = 기준선 1 증가」가」
                $cwdBaseCount++
            }

            # # 같은 분기에서 큐 기록 규약도 넣는다 — 계획 세션의 배치 시점 — 근거는 `rules/session-context-rationale.md`의 「§21 # 같은 분기에서 큐 기록 규약도 넣는다 — 계획 세션의 배치 시점」
            $secQueueRules = Get-SkillSection -Path (Join-Path $skillsDir 'llm-wiki/references/queue-rules.md') -StartHeading '### K 5-2. 결정 큐잉 ([DECISION])' -StopHeading '### K 5-4. 미스 큐잉 ([K-MISS])'
            if ($secQueueRules) {
                $lines.Add("[pjc 세션 컨텍스트] 압축 직후 큐 기록 규약 (원문 발췌 — llm-wiki/references/queue-rules.md 「K 5-2~5-3」)`n$secQueueRules")
                # 위 주입과 같은 짝 — 줄 1개 추가 = 기준선 1 증가(SC41e가 고정한 계약).
                $cwdBaseCount++
            }

            # # 조회 절차는 원문을 싣지 않고 경로만 가리킨다 — 근거는 `rules/session-context-rationale.md`의 「§22 # 조회 절차는 원문을 싣지 않고 경로만 가리킨다」
            $lookupPath = "$skillsDir/llm-wiki/references/lookup-rules.md"
            $lines.Add("[pjc 세션 컨텍스트] 위키 조회 절차: $lookupPath — 위키를 참조하기 전에 이 파일을 Read하세요(절차 K 1~5 전체). vault 판정 게이트가 그 안에 있습니다.")
            # 위 둘과 같은 짝 — 라인이 하나 늘었으므로 기준선도 하나 올린다.
            #   주입과 달리 추출 실패 분기가 없어 무조건 올린다.
            $cwdBaseCount++
        }

        # 위키 신호 3종(vault 상태·뒤처짐·큐 잔량)은 `session-wiki-signals.ps1`이 계산한다 —
        #   그 셋만 vault를 훑어(허브 전수 스캔·git rev-list·pending.md 파싱) 판정 입력이 다르다.
        $vaultInsertAt = $lines.Count      # AGENTS 라인보다 앞 위치를 미리 기록(전문이 길어 뒤에 붙으면 묻힌다)
        . (Join-Path $PSScriptRoot 'session-wiki-signals.ps1')
        $wikiSig = Get-WikiSignals -cwd $cwd
        $vaultLine = $wikiSig.VaultLine
        $staleLine = $wikiSig.StaleLine
        $feedbackLine = $wikiSig.FeedbackLine

        # # ---- AGENTS.md 전문 주입 — 근거는 `rules/session-context-rationale.md`의 「§31 # ---- AGENTS.md 전문 주입」
        $agentsMaxBytes = 16384      # 전문 주입 상한 — 하니스 생성 템플릿·이 repo가 모두 전문 주입 범위에 들어가는 값 (v1.135.0 기준 실측 최대 약 12KB)
        $agentsTocMaxBytes = 1048576 # 목차 폴백 상한(1MB) — 초과 시 읽기·목차 스캔 자체를 생략 (비정상 대형 파일 방어)
        # # 임박 신호 2축 — 근거는 `rules/session-context-rationale.md`의 「§32 # 임박 신호 2축」
        $agentsNearRatio = 0.95
        $agentsNearSlack = 500
        $agentsPath = Join-Path $cwd 'AGENTS.md'
        $agentsInfo = Get-Item -LiteralPath $agentsPath -ErrorAction SilentlyContinue
        # 빈 파일(0B)은 조용히 스킵 (내용 없는 --- 블록 방지)
        if ($agentsInfo -and -not $agentsInfo.PSIsContainer -and $agentsInfo.Length -gt 0) {
            $agentsBytes = [long]$agentsInfo.Length
            if ($agentsBytes -gt $agentsTocMaxBytes) {
                $lines.Add("[pjc 세션 컨텍스트] AGENTS.md (${agentsBytes}B) — 크기 상한(16KB) 초과로 전문 미주입(자동 로드되지 않습니다). 참조 시 전문을 Read하세요 — 앞부분만 읽고 'AGENTS.md에 없다'고 단정하지 마세요.")
            } else {
                $agentsText = $null
                try { $agentsText = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8 } catch {}
                # 공백뿐인 파일·읽기 실패는 조용히 스킵
                if (-not [string]::IsNullOrWhiteSpace($agentsText)) {
                    if ($agentsText.IndexOf([char]0xFFFD) -ge 0) {
                        # U+FFFD 검출 = UTF-8 디코딩 실패(CP949 등 다른 인코딩) — 깨진 전문을 "정본"으로
                        #   주입하면 오히려 원문 Read를 막으므로, 주입 대신 직접 Read를 안내한다
                        $lines.Add("[pjc 세션 컨텍스트] AGENTS.md 존재 — UTF-8 디코딩 실패(다른 인코딩으로 보임)로 전문 미주입. 참조 시 파일을 직접 Read하세요 — 앞부분만 읽고 'AGENTS.md에 없다'고 단정하지 마세요.")
                    } elseif ($agentsBytes -le $agentsMaxBytes) {
                        # 임박이면 전문 주입은 그대로 하고 꼬리에 경고만 덧붙인다 — 아직 상한 안이라
                        #   가이드를 빼앗을 이유가 없고, 알리는 것만이 목적이다.
                        $agentsSlack = $agentsMaxBytes - $agentsBytes
                        $agentsNear = ($agentsBytes -ge ($agentsMaxBytes * $agentsNearRatio)) -or ($agentsSlack -lt $agentsNearSlack)
                        # 스킬 이름을 백틱으로 감싸지 않는다 — 이중 인용 문자열에서 백틱은 이스케이프 문자라
                        #   출력에서 그대로 사라진다(`n·`t 등으로 오해석될 여지도 있다). 작은따옴표로 표기한다.
                        $agentsNearMsg = if ($agentsNear) { " ⚠ 주입 상한 임박(${agentsBytes}/${agentsMaxBytes}B · 여유 ${agentsSlack}B) — 넘으면 이 전문이 목차로 대체됩니다. 'pjc:record-project-fact'의 「주입 상한 점검·이관」으로 큰 절을 별도 문서로 옮기세요." } else { "" }
                        $lines.Add("[pjc 세션 컨텍스트] AGENTS.md (${agentsBytes}B) 전문 — 이 repo 프로젝트 가이드의 정본입니다(재Read 불필요). AGENTS.md에 관한 판단은 아래 전문을 근거로 하세요 — '관련 내용이 없다'고 말하려면 아래 전문 전체를 근거로만 단정하고, 앞부분만 보고 단정하지 마세요.${agentsNearMsg}`n---`n${agentsText}`n---")
                    } else {
                        # # 폴백: 전문 대신 헤딩 목차 — 근거는 `rules/session-context-rationale.md`의 「§33 # 폴백: 전문 대신 헤딩 목차」
                        $tocSource = [regex]::Replace($agentsText, '(?ms)^```[^\r\n]*\r?\n.*?^```[^\r\n]*', '')
                        $agentsHeadings = @([regex]::Matches($tocSource, '(?m)^#{1,3} .+') | ForEach-Object { ($_.Value -replace '^#{1,3}\s*', '').Trim() })
                        $agentsToc = if ($agentsHeadings.Count -gt 0) { "섹션: " + ($agentsHeadings -join ' · ') + " " } else { "" }
                        $lines.Add("[pjc 세션 컨텍스트] AGENTS.md (${agentsBytes}B) — 크기 상한(${agentsMaxBytes}B) 초과로 전문 미주입(자동 로드되지 않습니다). ${agentsToc}참조 시 offset/limit 없이 전문을 Read하세요 — 앞부분만 읽고 'AGENTS.md에 없다'고 단정하지 마세요. 해소하려면 'pjc:record-project-fact'의 「주입 상한 점검·이관」으로 큰 절을 별도 문서로 옮기고 포인터만 남기세요.")
                    }
                }
            }
        }

        # # ---- vault 라인 주입 — 근거는 `rules/session-context-rationale.md`의 「§34 # ---- vault 라인 주입」
        if ($vaultLine -and ($lines.Count -gt $cwdBaseCount)) {
            $lines.Insert([Math]::Min($vaultInsertAt, $lines.Count), $vaultLine)
            # 스킬 개선 큐 라인은 vault 라인 바로 뒤에 둔다 — 같은 게이팅(cwd 수집분 존재)을
            #   공유하며, vault 라인 없이 단독으로 나오지 않는다(큐는 vault 안에 있으므로).
            if ($feedbackLine) {
                $lines.Insert([Math]::Min($vaultInsertAt + 1, $lines.Count), $feedbackLine)
            }
            # # 뒤처짐 라인은 큐 라인 다음이다. 오프셋을 `+2`로 못박지 않는 이유: $feedbackLine — 근거는 `rules/session-context-rationale.md`의 「§35 # 뒤처짐 라인은 큐 라인 다음이다. 오프셋을 `+2`로 못박지 않는 이유: $feedbackLine」
            if ($staleLine) {
                $lines.Insert([Math]::Min($vaultInsertAt + 1 + [int][bool]$feedbackLine, $lines.Count), $staleLine)
            }
        }
    }

    if ($lines.Count -gt 0) {
        # stdout → 세션 컨텍스트 주입 (SessionStart exit 0 규약 — warn-version-drift와 동일)
        Write-Output ($lines -join "`n")
    }
    exit 0
} catch {
    exit 0
}
