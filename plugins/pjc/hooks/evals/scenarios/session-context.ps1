# scenarios/session-context.ps1 — session-context 시나리오 (§13 — plan 요약·AGENTS 주입·vault 라인) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 13) session-context 시나리오 (SessionStart — plan 상태 요약 주입, v1.112.0)
# =====================================================================
if (Test-HookSelected @('session-context')) {
    # 픽스처: plan.md(T 3개 중 미완료 2 — [x]/[/]/[ ] 혼합)
    $scProj = Join-Path $work 'sc-proj'
    New-Item -ItemType Directory $scProj -Force | Out-Null
    @(
        '# Plan: test',
        '## Tasks',
        '- [x] T1: done (Type A)',
        '- [/] T2: in progress (Type B)',
        '- [ ] T3: todo (Type C)'
    ) | Set-Content -Encoding UTF8 (Join-Path $scProj 'plan.md')

    # SC1: startup → plan 미완료 카운트 주입
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: plan 미완료 카운트 주입 (SC1)" -R $r -ExpectExit 0 -ExpectContains '미완료 2'

    # SC2: compact → 재확인 리마인더 추가 주입
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 재확인 리마인더 (SC2)" -R $r -ExpectExit 0 -ExpectContains '요약 직후'

    # SC2b: fork → startup과 같은 경로를 탄다(plan 카운트 주입), compact 전용 리마인더는 나오지 않는다.
    #   공식 SessionStart matcher 값은 startup|resume|clear|compact|fork인데 fork만 배선에서 빠져 있어
    #   fork 세션에는 plan 상태·vault·AGENTS.md가 통째로 주입되지 않았다. hooks.json에 fork를 넣은 뒤
    #   이 두 케이스가 그 경로를 고정한다 — 스크립트는 무수정이다($source가 'compact'가 아니면 동일 경로).
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'fork'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: fork도 plan 카운트 주입 (SC2b)" -R $r -ExpectExit 0 -ExpectContains '미완료 2'
    Assert-Case -Name "session-context: fork에는 compact 리마인더 없음 (SC2c)" -R $r -ExpectExit 0 -ExpectNotContains '요약 직후'

    # SC3: plan/notes 없는 빈 폴더 → 무출력 (비 pjc 프로젝트 노이즈 방지)
    $scEmpty = Join-Path $work 'sc-empty'; New-Item -ItemType Directory $scEmpty -Force | Out-Null
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: plan/notes 없음 무출력 (SC3)" -R $r -ExpectExit 0 -ExpectSilent $true

    # SC4: 루트 plan 없음 → docs/plans/ 폴백 (체크박스 없는 deferred.md는 건너뜀 실증 — 더 최신이어도 비인식)
    $scDocs = Join-Path $work 'sc-docs'
    New-Item -ItemType Directory (Join-Path $scDocs 'docs/plans') -Force | Out-Null
    @('- [x] T1: a', '- [ ] T2: b') | Set-Content -Encoding UTF8 (Join-Path $scDocs 'docs/plans/2026-07-01-feature.md')
    '- [2026-07-10] deferred 항목 (T 체크박스 아님)' | Set-Content -Encoding UTF8 (Join-Path $scDocs 'docs/plans/deferred.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDocs } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: docs/plans 폴백 인식 (SC4)" -R $r -ExpectExit 0 -ExpectContains '2026-07-01-feature.md'

    # SC5: task 체크박스 없는 plan.md(비 pjc 형식) → 카운트 오보 대신 존재 강등 문구
    $scNoT = Join-Path $work 'sc-not'; New-Item -ItemType Directory $scNoT -Force | Out-Null
    '# 자유 형식 계획 문서' | Set-Content -Encoding UTF8 (Join-Path $scNoT 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scNoT } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비 pjc plan 존재 강등 문구 (SC5)" -R $r -ExpectExit 0 -ExpectContains '존재'

    # SC6: 빈 stdin → 무출력 exit 0 (fail-open)
    $r = Invoke-Hook 'session-context.ps1' ''
    Assert-Case -Name "session-context: 빈 stdin 무출력 fail-open (SC6)" -R $r -ExpectExit 0 -ExpectSilent $true

    # SC7~SC9: AGENTS.md 전문 주입 (v1.135.0) — 전용 픽스처(기존 $scProj 오염 방지, 4-C)
    $scAgents = Join-Path $work 'sc-agents'; New-Item -ItemType Directory $scAgents -Force | Out-Null
    @(
        '---', 'type: x', '---',
        '# Agent Guide',
        'SC_AGENTS_UNIQUE_MARKER 이 문자열은 AGENTS.md 전문에만 있다',
        '## DO NOT', '금지 항목'
    ) | Set-Content -Encoding UTF8 (Join-Path $scAgents 'AGENTS.md')
    @('# Plan', '- [ ] T1: todo') | Set-Content -Encoding UTF8 (Join-Path $scAgents 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scAgents } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: AGENTS.md 전문 주입 (SC7)" -R $r -ExpectExit 0 -ExpectContains 'SC_AGENTS_UNIQUE_MARKER'
    Assert-Case -Name "session-context: AGENTS.md 근거 요구 문구 (SC8)" -R $r -ExpectExit 0 -ExpectContains '단정'

    # SC9: 16KB 초과 AGENTS.md → 전문 대신 섹션 목차 폴백 (헤딩 포함, 바이트로 상한 초과)
    $scBig = Join-Path $work 'sc-agents-big'; New-Item -ItemType Directory $scBig -Force | Out-Null
    (@('---', 'type: x', '---', '# Big Guide', '## Section One') + (1..2500 | ForEach-Object { '가나다라마 반복 채우기 줄' }) + @('### Sub Section', '끝')) | Set-Content -Encoding UTF8 (Join-Path $scBig 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scBig } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 16KB 초과 AGENTS.md 목차 폴백 (SC9)" -R $r -ExpectExit 0 -ExpectContains '섹션:'

    # SC10: AGENTS.md 없는 기존 픽스처($scProj: plan만)는 AGENTS 문자열 무오염 — T1 acceptance ⓑ의 영구 그물.
    #   SC3(완전 빈 폴더)은 plan은 있고 AGENTS만 없는 이 경로를 고정 못 하므로 별도 케이스로 둔다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: AGENTS.md 없는 픽스처 무오염 (SC10)" -R $r -ExpectExit 0 -ExpectContains '미완료 2' -ExpectNotContains 'AGENTS'

    # SC11~SC13: AGENTS.md 주입 견고성 가드 (v1.135.0 리뷰 후속 — 비정상 입력에서 깨진/오도 컨텍스트 주입 방지)
    # SC11: UTF-8이 아닌 인코딩(CP949 등) → 깨진 전문 대신 디코딩 실패 안내 1줄 (U+FFFD 검출 가드)
    $scMoji = Join-Path $work 'sc-agents-moji'; New-Item -ItemType Directory $scMoji -Force | Out-Null
    # 0xB0A1 = CP949 '가' — UTF-8로 디코딩하면 U+FFFD가 된다 (CodePagesEncodingProvider 없이 재현 가능한 원시 바이트)
    [System.IO.File]::WriteAllBytes((Join-Path $scMoji 'AGENTS.md'), [byte[]](0x23, 0x20, 0xB0, 0xA1, 0xB0, 0xA1, 0x0A))
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scMoji } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비UTF-8 AGENTS.md 디코딩 실패 안내 (SC11)" -R $r -ExpectExit 0 -ExpectContains '디코딩 실패'

    # SC12: 목차 폴백 상한(1MB) 초과 → 읽기·목차 스캔 생략, Read 지시만 (타임아웃·메모리 방어)
    $scHuge = Join-Path $work 'sc-agents-huge'; New-Item -ItemType Directory $scHuge -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $scHuge 'AGENTS.md'), "# Huge Guide`n" + ('a' * 1100000))
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scHuge } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 1MB 초과 AGENTS.md 목차 생략 Read 지시 (SC12)" -R $r -ExpectExit 0 -ExpectContains '전문 미주입' -ExpectNotContains '섹션:'

    # SC13: 목차 폴백이 0열 코드 펜스 안의 '# 주석'을 섹션으로 오인하지 않음 (펜스 제거 후 헤딩 추출)
    $scFence = Join-Path $work 'sc-agents-fence'; New-Item -ItemType Directory $scFence -Force | Out-Null
    (@('# Real Guide', '## Real Section', '```sh', '# FENCE_MARKER not a heading', 'echo hi', '```') + (1..2500 | ForEach-Object { '가나다라마 반복 채우기 줄' })) | Set-Content -Encoding UTF8 (Join-Path $scFence 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scFence } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 목차 폴백 코드 펜스 내 # 비오인 (SC13)" -R $r -ExpectExit 0 -ExpectContains '섹션:' -ExpectNotContains 'FENCE_MARKER'

    # SC14~SC17: compact 재읽기 경로 지정 — 압축 후 스킬 뒷부분(Phase 절차·Halt 조건)이 유실되고
    #   재invoke로는 복구되지 않으므로, 미완료 task가 있을 때만 Read 대상 3종을 못박는다.
    #   3경로 리터럴을 골든이 고정한다 — 문구가 흔들려도 "무엇을 읽어야 하는지"는 남아야 한다.
    # SC14: compact + 미완료 task 있는 plan → 고정 3경로 전부 주입
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 재읽기 경로 SKILL.md (SC14)" -R $r -ExpectExit 0 -ExpectContains 'implement-task/SKILL.md'
    Assert-Case -Name "session-context: compact 재읽기 경로 halt-conditions (SC14b)" -R $r -ExpectExit 0 -ExpectContains 'references/halt-conditions.md'
    Assert-Case -Name "session-context: compact 재읽기 경로 recovery (SC14c)" -R $r -ExpectExit 0 -ExpectContains 'references/recovery.md'

    # SC15: compact + plan 없음 → 기존 일반 리마인더만, 경로 지정 없음 (무회귀)
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact plan 없음 경로 미지정 (SC15)" -R $r -ExpectExit 0 -ExpectContains '요약 직후' -ExpectNotContains 'halt-conditions'

    # SC16: compact + 전 task 완료 → 경로 지정 없음. 재개할 루프가 없으면 재읽기를 유도하지 않는다.
    $scDone = Join-Path $work 'sc-done'; New-Item -ItemType Directory $scDone -Force | Out-Null
    @('# Plan', '- [x] T1: done', '- [x] T2: done') | Set-Content -Encoding UTF8 (Join-Path $scDone 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scDone } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 전 task 완료 경로 미지정 (SC16)" -R $r -ExpectExit 0 -ExpectContains '전부 완료' -ExpectNotContains 'halt-conditions'

    # SC17: compact + 존재하지 않는 cwd → 기존 compact 문구는 그대로 나온다.
    #   이 라인이 cwd 검사 블록 밖에 있어야 성립하므로, 블록 안으로 옮기는 회귀를 골든이 막는다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = (Join-Path $work 'sc-nonexistent') } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 무효 cwd 기본 문구 유지 (SC17)" -R $r -ExpectExit 0 -ExpectContains '요약 직후'

    # SC18~SC23: 위키 vault 설정 상태 주입 (v1.146.0) — 절차 K의 "미설정" 오판정을 기계로 차단.
    #   전용 격리 홈에 llm-wiki-config.json을 심는다($iso에는 config가 없어 미설정 상태이며 SC20이 그것을 쓴다).
    #   무회귀 1건(SC20) + 델타 3건(SC21 과다 주입·SC22 과억제·SC23 리마인더 오신호) 구성 —
    #   통과만 확인하는 케이스는 게이팅을 고정하지 못한다.
    $isoV = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-vault-" + $suffix)
    $isoVault = Join-Path $isoV 'my-wiki'
    New-Item -ItemType Directory -Path (Join-Path $isoV '.claude') -Force | Out-Null
    New-Item -ItemType Directory -Path $isoVault -Force | Out-Null
    (@{ vault_path = ($isoVault -replace '\\', '/') } | ConvertTo-Json) | Set-Content -Encoding UTF8 (Join-Path $isoV '.claude/llm-wiki-config.json')

    # SC18: 설정+실재 → 경로와 "단정 금지" 문구가 함께 주입된다 (문구 리터럴 고정)
    $env:USERPROFILE = $isoV
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: vault 설정됨 상태 주입 (SC18)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨'
    Assert-Case -Name "session-context: vault 단정 금지 문구 (SC18b)" -R $r -ExpectExit 0 -ExpectContains '단정하지 마세요'

    # SC21 (델타): 설정+실재인데 비 pjc cwd(plan·AGENTS 전무) → 게이팅으로 미주입.
    #   vault는 cwd와 무관한 사용자 홈 자원이라, 게이팅이 없으면 위키를 쓰는 사용자의 모든 세션에 라인이 붙는다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비 pjc cwd는 vault 라인 미주입 (SC21)" -R $r -ExpectExit 0 -ExpectSilent $true

    # SC23 (델타): compact + 빈 cwd → 리마인더는 나오되 vault 라인은 미주입.
    #   리마인더는 cwd 블록 밖에서 append되므로 게이팅 신호가 아니다 — $lines.Count -gt 0 판정을 이 케이스가 검출한다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 리마인더는 vault 게이팅 신호 아님 (SC23)" -R $r -ExpectExit 0 -ExpectContains '요약 직후' -ExpectNotContains '위키 vault'

    # SC22 (델타): AGENTS.md만 있고 plan 없는 cwd → vault 라인이 주입되고 AGENTS 라인보다 **앞**에 온다.
    #   ① 게이팅을 AGENTS 진입 전 시점에 판정하면 이 케이스가 억제된다(과억제 검출).
    #   ② 순서 단정은 Assert-Case로 불가하다 — ExpectContains가 [regex]::Escape를 거쳐 전후 관계를 비교할 수단이 없으므로
    #      IndexOf 비교 후 결과를 직접 push한다(§11 (b) 패턴과 동일).
    #   기존 AGENTS 단독 픽스처($scBig 등)는 16KB 초과·비UTF-8이라 전문이 아니라 폴백을 출력하므로 소형 픽스처를 따로 둔다.
    $scVOnly = Join-Path $work 'sc-agents-only'; New-Item -ItemType Directory $scVOnly -Force | Out-Null
    @('# Guide', 'SC_VAULT_ORDER_MARKER 전문 주입 대상') | Set-Content -Encoding UTF8 (Join-Path $scVOnly 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scVOnly } | ConvertTo-Json -Compress)
    $iVault  = $r.out.IndexOf('위키 vault: 설정됨')
    $iAgents = $r.out.IndexOf('SC_VAULT_ORDER_MARKER')
    if (($r.code -eq 0) -and ($iVault -ge 0) -and ($iAgents -gt $iVault)) {
        $script:results.Add(@{ ok = $true; line = "[PASS] session-context: AGENTS 단독 cwd vault 주입 + AGENTS보다 앞 (SC22)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] session-context: SC22 주입·순서 위반 (exit=$($r.code), vault=$iVault, agents=$iAgents)" })
    }

    # SC19: 설정됐으나 폴더 부재(이동·삭제) → 부재 문구 주입 (경로 재확인 신호)
    $isoV2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-vault-gone-" + $suffix)
    New-Item -ItemType Directory -Path (Join-Path $isoV2 '.claude') -Force | Out-Null
    (@{ vault_path = ((Join-Path $isoV2 'moved-away') -replace '\\', '/') } | ConvertTo-Json) | Set-Content -Encoding UTF8 (Join-Path $isoV2 '.claude/llm-wiki-config.json')
    $env:USERPROFILE = $isoV2
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: vault 설정 경로 부재 주입 (SC19)" -R $r -ExpectExit 0 -ExpectContains '설정 경로 부재'

    # SC20 (무회귀): config 없는 홈 → vault 라인 미주입. 미설정은 무출력이 설계다(노이즈 방지).
    $env:USERPROFILE = $iso
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 미설정 홈은 vault 라인 미주입 (SC20)" -R $r -ExpectExit 0 -ExpectContains '미완료 2' -ExpectNotContains '위키 vault'

    # SC24~SC27: 스킬 개선 큐 잔량 주입 — [SKILL-IMPROVE] 큐가 하네스 세션마다 보이게 하는 축.
    #   구성은 SC18~SC23과 같은 원리다: 주입 1건(SC24) + 델타 3건(SC25 파일 부재·SC26 비하네스
    #   cwd 과다 주입·SC27 상위 탐색 금지). 통과만 확인하는 케이스는 게이팅을 고정하지 못한다.
    #   SC27이 특히 중요하다 — 상위 탐색을 넣으면 하네스 repo 하위 폴더에서 연 무관한 세션까지
    #   하네스로 오판하는데, plan-feature Step 1도 같은 기준이라 둘이 함께 어긋난다.
    $scHarn = Join-Path $work ("sc-harness-" + $suffix)
    New-Item -ItemType Directory -Path (Join-Path $scHarn 'plugins/pjc/.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $scHarn 'sub') -Force | Out-Null
    '{ "name": "pjc" }' | Set-Content -Encoding UTF8 (Join-Path $scHarn 'plugins/pjc/.claude-plugin/plugin.json')
    "- [ ] T1. 미완료`n- [ ] T2. 미완료" | Set-Content -Encoding UTF8 (Join-Path $scHarn 'plan.md')
    "- [ ] T1. 미완료`n- [ ] T2. 미완료" | Set-Content -Encoding UTF8 (Join-Path $scHarn 'sub/plan.md')
    "- [2026-07-22] [SKILL-IMPROVE] implement-task: 요지 1.`n- [2026-08-02] [SKILL-IMPROVE] plan-feature: 요지 2." |
        Set-Content -Encoding UTF8 (Join-Path $isoVault 'skill-feedback.md')
    $env:USERPROFILE = $isoV

    # SC24: 하네스 repo cwd + 큐 2건 → 건수·최고령이 1줄로 주입된다(본문은 미주입 — 예산 보호).
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scHarn } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 스킬 개선 큐 잔량 주입 (SC24)" -R $r -ExpectExit 0 -ExpectContains '스킬 개선 큐'
    Assert-Case -Name "session-context: 큐 건수 집계 (SC24b)" -R $r -ExpectExit 0 -ExpectContains '대기 2건'
    # 체류 축은 D9ⓑ의 "append 시점에만 평가되는 사각"을 닫으려고 넣은 것이라, 문자열이 사라지거나
    #   형식이 깨지면 그 취지가 조용히 죽는다. 값은 날짜 의존이지만 '최고령' 라벨은 고정 가능하다.
    Assert-Case -Name "session-context: 큐 체류(최고령) 축 (SC24d)" -R $r -ExpectExit 0 -ExpectContains '최고령'
    Assert-Case -Name "session-context: 큐 본문 미주입 (SC24c)" -R $r -ExpectExit 0 -ExpectNotContains '요지 1'

    # SC26 (델타): 비하네스 cwd(plugin.json 없음) + 큐 존재 → vault 라인은 나오되 큐 라인은 미주입.
    #   게이팅이 없으면 위키를 쓰는 모든 프로젝트 세션에 하네스 개선 항목이 끌려온다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비하네스 cwd는 큐 라인 미주입 (SC26)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '스킬 개선 큐'

    # SC27 (델타): 하네스 repo의 **서브디렉터리** cwd → 상위 탐색을 하지 않으므로 큐 라인 미주입.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = (Join-Path $scHarn 'sub') } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 서브디렉터리 cwd는 상위 탐색 안 함 (SC27)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '스킬 개선 큐'

    # SC25 (델타): 하네스 cwd인데 큐 파일 부재 → 큐 라인만 미주입(vault 라인은 유지, fail-open).
    #   **번호와 실행 순서가 다른 이유**: 이 케이스만 큐 파일을 삭제하는 파괴적 조작이라 SC24·26·27이
    #   그 파일을 쓰고 난 뒤 마지막에 둔다(순서를 번호대로 바꾸면 뒤 케이스들이 파일 없는 상태를 본다).
    Remove-Item -Force (Join-Path $isoVault 'skill-feedback.md') -ErrorAction SilentlyContinue
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scHarn } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 큐 파일 부재 시 미주입 (SC25)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '스킬 개선 큐'

    Remove-Item -Recurse -Force $isoV, $isoV2, $scHarn -ErrorAction SilentlyContinue
}   # ---- §13 게이트 끝 (session-context) ----

