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

    # SC4: 루트 plan 없음 → docs/plans/에 체크박스 plan이 있어도 주입하지 않는다 (v1.210.0 — 폴백 제거).
    #   과거 회차 plan의 미완료분이 이번 세션의 상태로 주입되던 경로를 닫은 것이라, 기대는 '무출력'이다.
    $scDocs = Join-Path $work 'sc-docs'
    New-Item -ItemType Directory (Join-Path $scDocs 'docs/plans') -Force | Out-Null
    @('- [x] T1: a', '- [ ] T2: b') | Set-Content -Encoding UTF8 (Join-Path $scDocs 'docs/plans/2026-07-01-feature.md')
    '- [2026-07-10] deferred 항목 (T 체크박스 아님)' | Set-Content -Encoding UTF8 (Join-Path $scDocs 'docs/plans/deferred.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDocs } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: docs/plans 과거 plan은 주입하지 않는다 (SC4)" -R $r -ExpectExit 0 -ExpectSilent $true

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
    # 초과 폴백은 "왜 안 들어왔는지"만 알리고 해소 경로를 안 줬다 — 그 상태로는 다음 세션도 같은 폴백을 받는다.
    Assert-Case -Name "session-context: 초과 폴백에 이관 절차 안내 (SC9d)" -R $r -ExpectExit 0 -ExpectContains 'record-project-fact'

    # SC9a~SC9c: 주입 상한 임박 경고 (v1.190.0) — 초과한 뒤에 알리면 그 세션은 이미 가이드를 잃은 채 돈다.
    #   임계는 llm-wiki 예산 신호와 같은 2축(95% OR 여유 500B)이지만, 16KB 예산에서는 **잔여축이 비율축에
    #   항상 포함된다**(여유 500B 미만 = 15,885B 이상 = 이미 96.9%). 그래서 양성 케이스는 비율축 하나만
    #   고정하고, 임계 자체가 살아 있는지는 아래 음성 케이스(SC9c)가 지킨다.
    # SC9a (양성): 상한의 95% 이상 — 전문은 그대로 주입되고 꼬리에 임박 경고가 붙는다.
    $scNear = Join-Path $work 'sc-agents-near'; New-Item -ItemType Directory $scNear -Force | Out-Null
    # '가나다라마 반복 채우기 줄'은 UTF-8 36B + CRLF 2B = 38B/줄. 헤더 2줄 30B + 410줄 = 15,610B(실측, 95.3%)
    (@('# Near Guide', '## Section One') + (1..410 | ForEach-Object { '가나다라마 반복 채우기 줄' })) | Set-Content -Encoding UTF8 (Join-Path $scNear 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scNear } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: AGENTS.md 주입 상한 임박 경고 — 비율축 (SC9a)" -R $r -ExpectExit 0 -ExpectContains '주입 상한 임박'
    Assert-Case -Name "session-context: 임박이어도 전문은 그대로 주입 (SC9b)" -R $r -ExpectExit 0 -ExpectContains 'Near Guide' -ExpectNotContains '섹션:'

    # SC9c (음성·델타): 상한의 80%대 — 어느 축도 안 걸려 경고가 없어야 한다.
    #   이 케이스가 없으면 "항상 경고"로 바꿔도 SC9a가 통과해 임계 판정이 무력화된다.
    $scFar = Join-Path $work 'sc-agents-far'; New-Item -ItemType Directory $scFar -Force | Out-Null
    # 헤더 2줄 + 341줄 = 12,988B(실측, 79.3%) — 여유 3,396B로 두 축 모두 미달
    (@('# Far Guide', '## Section One') + (1..341 | ForEach-Object { '가나다라마 반복 채우기 줄' })) | Set-Content -Encoding UTF8 (Join-Path $scFar 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scFar } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 임박 미달이면 경고 없음 (SC9c)" -R $r -ExpectExit 0 -ExpectContains 'Far Guide' -ExpectNotContains '주입 상한 임박'

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

    # SC39~SC39d: compact 직후 루프 제어 규칙 **내용 주입** (v1.212.0 T1).
    #   경로만 지시하면 ① 실제로 읽었는지 검증할 장치가 없고 ② 지시한 3파일 합 약 172KB를 다시
    #   읽는 것이 압축으로 확보한 여유를 도로 소진한다. 그래서 두 절의 원문을 잘라 함께 주입한다.
    #   ⚠ 대조 문자열은 **주입 헤더 라벨에 없고 절 본문에만 있는 것**을 고른다 — 라벨에도 있는
    #   문자열(예: '중단 조건 표')로 재면 절이 통째로 빠져도 라벨만으로 통과해 검사가 무력해진다.
    #   $r은 위 SC14 호출(compact + $scProj) 결과를 그대로 쓴다.
    # SC39 (양성): SKILL.md 「자율 루프의 절대 규칙」 절이 실려 온다.
    Assert-Case -Name "session-context: compact 루프 규칙 절 주입 (SC39)" -R $r -ExpectExit 0 -ExpectContains 'task 사이에 사용자에게 묻지 않는다'
    # SC39b (양성): halt-conditions 「중단 조건 표」~「위임 경계」 절이 실려 온다.
    #   두 절을 각각 재는 이유 — 한쪽만 걸면 나머지가 빠져도 전건 통과한다.
    Assert-Case -Name "session-context: compact Halt 조건 절 주입 (SC39b)" -R $r -ExpectExit 0 -ExpectContains '위임 경계 (4분류'
    # SC39d (발췌 표기): 주입분이 전문이 아니라 발췌임을 밝힌다 — 없으면 모델이 이것을 전문으로
    #   오인해 "나머지는 없다"고 판단할 수 있다.
    Assert-Case -Name "session-context: 주입분에 원문 발췌 표기 (SC39d)" -R $r -ExpectExit 0 -ExpectContains '원문 발췌'

    # SC39c (델타 음성): startup에는 주입하지 않는다 — 압축 전용 보완이라 매 세션 14KB를 얹으면
    #   그 자체가 예산 낭비다. 이 케이스가 없으면 "항상 주입"으로 바꿔도 위 셋이 전부 통과한다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: startup엔 루프 규칙 미주입 (SC39c)" -R $r -ExpectExit 0 -ExpectContains '미완료 2' -ExpectNotContains 'task 사이에 사용자에게 묻지 않는다'
    # $r을 되돌리지 않는다 — 이어지는 SC28·SC29가 각각 자기 $r을 새로 만든다(불필요한 hook 실행 방지).

    # SC28/SC29: 계획 세션의 압축 리마인더 (v1.198.0 T8).
    #   SC14 계열은 `if ($planPath)` 안이라 **진행 중 plan이 있는 세션**만 닿는다. 계획을 세우던 중
    #   압축되면 plan이 없거나 task가 0개라 그 지시를 못 받는데, plan-feature도 본체가 앞 5,000토큰
    #   밖으로 밀리는 것은 같다. 두 케이스가 그 분기를 고정한다 — 양성 하나만 걸면 **델타 음성**이
    #   비어 "미완료 task 세션에도 계획 지시가 새는" 회귀를 못 잡는다.
    # SC28 (양성): compact + plan 없는 프로젝트 → 계획 재읽기 지시 발화
    $scPlanless = Join-Path $work 'sc-planless'; New-Item -ItemType Directory $scPlanless -Force | Out-Null
    '# Agent Guide' | Set-Content -Encoding UTF8 (Join-Path $scPlanless 'AGENTS.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scPlanless } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact + plan 없음 → 계획 재읽기 지시 (SC28)" -R $r -ExpectExit 0 -ExpectContains 'plan-feature/SKILL.md'

    # SC29 (델타 음성): compact + 미완료 task 있는 plan → implement-task 지시만, 계획 지시는 미발화
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact + 미완료 task엔 계획 지시 없음 (SC29)" -R $r -ExpectExit 0 -ExpectNotContains 'plan-feature/SKILL.md'

    # SC41~SC41e: 계획 세션에도 **절 원문 주입** (v1.217.0). SC41e는 vault 구간 안에 있다.
    #   SC28이 고정한 것은 경로 지시(`plan-feature/SKILL.md` 문자열)뿐이라, 주입을 지워도 그대로 통과한다.
    #   SC39 계열이 구현 세션에서 양성·델타 음성·발췌 표기를 나눠 건 것과 같은 구조로 넷을 건다.
    # SC41 (양성): compact + plan 없음 → 절대 규칙 **본문 문자열**이 실려 온다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scPlanless } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 계획 규칙 절 주입 (SC41)" -R $r -ExpectExit 0 -ExpectContains '증상 우회는 plan의 해결책이 될 수 없다'
    # SC41b (발췌 표기): 주입분이 전문이 아니라 발췌임을 밝힌다 — 없으면 모델이 이것을 전문으로 오인한다(SC39d와 같은 이유).
    Assert-Case -Name "session-context: 계획 주입에 발췌 표기 (SC41b)" -R $r -ExpectExit 0 -ExpectContains '원문 발췌 — plan-feature/SKILL.md'
    # SC41c (델타 음성): startup엔 주입하지 않는다 — 압축 전용 보완이라 매 세션 얹으면 예산 낭비다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scPlanless } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: startup엔 계획 규칙 미주입 (SC41c)" -R $r -ExpectExit 0 -ExpectNotContains '증상 우회는 plan의 해결책이 될 수 없다'
    # SC41d (델타 음성): compact + 미완료 task 세션엔 계획 주입이 새지 않는다.
    #   ⚠ 대조 문자열은 **주입 본문**이어야 한다 — `plan-feature/SKILL.md`로 걸면 SC29와 완전히 같아 새 회귀를 못 잡는다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 미완료 task 세션엔 계획 규칙 미주입 (SC41d)" -R $r -ExpectExit 0 -ExpectNotContains '증상 우회는 plan의 해결책이 될 수 없다'

    # SC42~SC42f: 계획 세션에 **큐 기록 규약(K 5-2~5-3) 원문 주입** (v1.218.0).
    #   위 SC41 계열과 같은 분기에서 돌지만 대상 문서가 다르므로 따로 건다 —
    #   한 쪽 주입을 지워도 다른 쪽 assert가 그대로 통과하기 때문이다.
    # SC42 (양성): compact + plan 없음 → K 5-2 **본문 문자열**이 실려 온다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scPlanless } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 큐 기록 규약 절 주입 (SC42)" -R $r -ExpectExit 0 -ExpectContains 'LLM이 나중에 이 항목만 보고'
    # SC42b (발췌 표기): SC41b와 같은 이유 — 주입분이 전문이 아니라 발췌임을 밝힌다.
    Assert-Case -Name "session-context: 큐 규약 주입에 발췌 표기 (SC42b)" -R $r -ExpectExit 0 -ExpectContains '원문 발췌 — llm-wiki/references/queue-rules.md'
    # SC42f (경계 계약): 추출 구간이 **K 5-3까지** 닿는다 — 종료 앵커가 `### K 5-4.`임을 고정한다.
    #   SC42는 K 5-2 본문만 보므로 앵커를 5-3 앞으로 잘못 옮겨도 그대로 통과한다.
    Assert-Case -Name "session-context: 큐 규약 주입이 K 5-3까지 포함 (SC42f)" -R $r -ExpectExit 0 -ExpectContains '레포 귀속 실행 사실'
    # SC42c (델타 음성): startup엔 주입하지 않는다(SC41c와 같은 취지).
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scPlanless } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: startup엔 큐 규약 미주입 (SC42c)" -R $r -ExpectExit 0 -ExpectNotContains 'LLM이 나중에 이 항목만 보고'
    # SC42d (델타 음성): compact + 미완료 task 세션엔 새지 않는다 — 그쪽은 F-6.5 ⓒ가 스킬을 재발동해 복구한다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 미완료 task 세션엔 큐 규약 미주입 (SC42d)" -R $r -ExpectExit 0 -ExpectNotContains 'LLM이 나중에 이 항목만 보고'

    # SC30 (델타 음성): compact + plan도 AGENTS.md도 없는 비 pjc 폴더 → 계획 지시 미발화.
    #   리마인더 대상이 pjc 워크플로라 무관한 폴더에 뜨면 노이즈다(`:16` 무출력 규칙과 같은 취지).
    #   기존 SC15·SC23이 같은 빈 픽스처를 쓰지만 각각 다른 문자열만 assert해 이 회귀를 못 잡는다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact + 비 pjc 폴더엔 계획 지시 없음 (SC30)" -R $r -ExpectExit 0 -ExpectNotContains 'plan-feature/SKILL.md'

    # SC15: compact + plan 없음 → 기존 일반 리마인더만, 경로 지정 없음 (무회귀)
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact plan 없음 경로 미지정 (SC15)" -R $r -ExpectExit 0 -ExpectContains '요약 직후' -ExpectNotContains 'halt-conditions'

    # SC16: compact + 전 task 완료 → **implement-task 3경로**는 지정하지 않는다. 재개할 루프가 없으면
    #   그 세 파일을 읽힐 이유가 없다(이 케이스가 재는 것은 그 미주입이고 그 판정은 불변이다).
    #   ⚠ v1.208.0부터 이 상태에도 **계획 재읽기 지시**(plan-feature/SKILL.md)는 나간다 — 완료된 plan이
    #   남은 채 새 계획을 세우는 세션이 두 분기 사이로 빠지던 사각을 닫았다(아래 SC38). assert가
    #   'halt-conditions' 부재만 보므로 이 케이스는 그대로 유효하다.
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
    $isoV = Join-Path $EvalRunTemp ("pjc-hook-evals-vault-" + $suffix)
    $isoVault = Join-Path $isoV 'my-wiki'
    New-Item -ItemType Directory -Path (Join-Path $isoV '.claude') -Force | Out-Null
    New-Item -ItemType Directory -Path $isoVault -Force | Out-Null
    (@{ vault_path = ($isoVault -replace '\\', '/') } | ConvertTo-Json) | Set-Content -Encoding UTF8 (Join-Path $isoV '.claude/llm-wiki-config.json')

    # SC18: 설정+실재 → 경로와 "단정 금지" 문구가 함께 주입된다 (문구 리터럴 고정)
    $env:USERPROFILE = $isoV
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scProj } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: vault 설정됨 상태 주입 (SC18)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨'
    Assert-Case -Name "session-context: vault 단정 금지 문구 (SC18b)" -R $r -ExpectExit 0 -ExpectContains '단정하지 마세요'

    # SC18c/SC18d: 라인이 "참조 가능"(권유)이 아니라 **행동 지시**를 담는지 고정한다 (v1.197.0).
    #   두 요소를 각각 재는 이유: 한쪽만 걸어두면 나머지가 지워져도 전건 통과한다.
    #   ① 허브 직행 — 스킬을 발동하지 않는 세션(trivial 수정·질문)에는 절차 K를 부르는 주체가
    #      없어, 이 라인이 프로젝트 맥락을 위키에서 얻게 하는 유일한 신호다.
    #   ② 글로벌 절 포인터 — 판정 규칙(인덱스 경유·낡음·코드 정본)은 글로벌 지침이 정본이고
    #      그것은 매 세션 상시 로드되므로 여기 복제하지 않는다(재진술은 예산만 늘린다).
    Assert-Case -Name "session-context: vault 라인의 허브 직행 지시 (SC18c)" -R $r -ExpectExit 0 -ExpectContains '허브를 먼저 Read'
    Assert-Case -Name "session-context: vault 라인의 글로벌 절 포인터 (SC18d)" -R $r -ExpectExit 0 -ExpectContains '위키를 먼저 본다'

    # SC21 (델타): 설정+실재인데 비 pjc cwd(plan·AGENTS 전무) → 게이팅으로 미주입.
    #   vault는 cwd와 무관한 사용자 홈 자원이라, 게이팅이 없으면 위키를 쓰는 사용자의 모든 세션에 라인이 붙는다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 비 pjc cwd는 vault 라인 미주입 (SC21)" -R $r -ExpectExit 0 -ExpectSilent $true

    # SC23 (델타): compact + 빈 cwd → 리마인더는 나오되 vault 라인은 미주입.
    #   리마인더는 cwd 블록 밖에서 append되므로 게이팅 신호가 아니다 — $lines.Count -gt 0 판정을 이 케이스가 검출한다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmpty } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 리마인더는 vault 게이팅 신호 아님 (SC23)" -R $r -ExpectExit 0 -ExpectContains '요약 직후' -ExpectNotContains '위키 vault'

    # SC41e (회귀 고정 — v1.217.0): 계획 규칙 **주입**의 `$cwdBaseCount` 짝 증가.
    #   이 분기는 「$lines.Add 1회 = $cwdBaseCount++ 1회」가 짝인데, 주입을 넣고 기준선을 올리지
    #   않으면 `$lines.Count -gt $cwdBaseCount`가 참이 되어 **vault 라인이 새로 붙는다**.
    #   ⚠ 픽스처의 AGENTS.md는 **0바이트여야 한다** — 분기 조건은 `Test-Path`로 존재만 보지만
    #   주입 블록은 `$agentsInfo.Length -gt 0`이라(session-context.ps1:474) 내용이 있으면
    #   AGENTS 라인이 먼저 들어가 그 자체가 정당한 vault 신호가 되고 델타가 0이 된다.
    #   (v1.217.0이 내용 있는 픽스처로 시도해 FAIL을 보고 「원리상 불가」로 오판했다가 F-7이 잡았다.)
    #   SC23은 계획 분기가 아예 발화하지 않는 빈 cwd이고 SC31b는 plan 라인이 이미 정당한 신호라,
    #   **둘 다 이 짝 증가를 잡지 못한다**.
    $scEmptyAg = Join-Path $work 'sc-empty-agents'; New-Item -ItemType Directory $scEmptyAg -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $scEmptyAg 'AGENTS.md') -Force | Out-Null
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scEmptyAg } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 계획 규칙 주입도 vault 게이팅 신호 아님 (SC41e)" -R $r -ExpectExit 0 -ExpectContains '증상 우회는 plan의 해결책이 될 수 없다' -ExpectNotContains '위키 vault'
    # SC42e (회귀 고정 — v1.218.0): 큐 규약 **주입**도 같은 짝을 지킨다.
    #   주입이 둘로 늘었으므로 `$cwdBaseCount++`도 둘이어야 한다 — 한 쪽만 올리면
    #   그 세션에 vault 라인이 새로 붙는다(SC41e가 고정한 것과 같은 형태의 회귀).
    Assert-Case -Name "session-context: 큐 규약 주입도 vault 게이팅 신호 아님 (SC42e)" -R $r -ExpectExit 0 -ExpectContains 'LLM이 나중에 이 항목만 보고' -ExpectNotContains '위키 vault'

    # SC31/SC31b (회귀 고정 — **vault가 설정된 구간에서 돌아야 의미가 있다**): compact + plan.md는 있으나
    #   task 체크박스 0개인 세션. 계획 지시가 뜨면서도 **vault 라인이 함께 유지**되어야 한다.
    #   계획 지시 줄이 $cwdBaseCount를 전체 재설정하면(`= $lines.Count`) 그 앞의 「plan 존재」 신호까지
    #   흡수돼 vault가 조용히 빠진다 — `++`여야 하는 이유를 SC31b가 고정한다.
    #   ⚠ 이 두 케이스를 vault 설정($env:USERPROFILE = $isoV) **앞**에 두면 $vaultLine이 $null이라
    #     게이팅 로직 자체가 안 돌아 회귀를 못 잡는다(초안이 그 자리에 있었고 리뷰 2종이 각각 잡았다).
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scNoT } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact + task 0개 plan에도 계획 지시 (SC31)" -R $r -ExpectExit 0 -ExpectContains 'plan-feature/SKILL.md'
    Assert-Case -Name "session-context: 계획 지시가 vault 신호를 삼키지 않음 (SC31b)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨'

    # SC38/SC38b (v1.208.0 — 완료 plan 사각): compact + task가 **전부 완료**된 plan. 종전에는
    #   위 `$open -gt 0` 분기(implement-task 3경로)에도, 아래 계획 리마인더(`-not $planPath -or $all -eq 0`)
    #   에도 걸리지 않아 **아무 재읽기 지시도 나가지 않았다.** 회차를 마치면 plan.md는 task가 전부 [x]인
    #   채 남고 다음 계획 세션이 그 위에서 시작하므로 이 상태가 오히려 흔하다.
    #   ⚠ SC16이 같은 상태를 쓰지만 **vault 설정 구간 밖**이라 SC38b(vault 신호 유지)를 잴 수 없다 —
    #     SC31b와 같은 배치 제약이며, 여기 두어야 $cwdBaseCount 회귀가 실제로 검사된다.
    $scDone2 = Join-Path $work 'sc-done2'; New-Item -ItemType Directory $scDone2 -Force | Out-Null
    @('# Plan', '- [x] T1: done', '- [x] T2: done') | Set-Content -Encoding UTF8 (Join-Path $scDone2 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scDone2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact + 전 task 완료 plan에도 계획 지시 (SC38)" -R $r -ExpectExit 0 -ExpectContains 'plan-feature/SKILL.md'
    Assert-Case -Name "session-context: 완료 plan 계획 지시가 vault 신호를 삼키지 않음 (SC38b)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨'
    Assert-Case -Name "session-context: 완료 plan엔 implement-task 3경로 미주입 (SC38c)" -R $r -ExpectExit 0 -ExpectNotContains 'references/halt-conditions.md'

    # SC40~SC40i: plan `## Deferred / Follow-up`의 **미판정 건수 주입** (v1.214.0 T3).
    #   plan.md는 gitignore + 다음 회차 교체라, 대장(docs/plans/deferred.md)으로 옮기지 못한 항목은
    #   회차와 함께 사라진다. task 체크박스는 위 케이스들이 재지만 Deferred는 아무도 세지 않았다.
    #   마커 3종([등재]/[미등재:<게이트 기호>]/[미판정] — 형식 정본은 phase-f-detail.md F-6.5)이
    #   그 상태를 기계 판독 가능하게 만들고, hook이 **미판정만** 센다.
    #   ⚠ 대조 문자열은 부기 리터럴 'Deferred 미판정'이다 — 숫자만 재면 문면이 바뀌어도 통과한다.
    $scDefBase = Join-Path $work 'sc-def'

    # SC40 (양성): 미판정 2건 → 건수가 실린다. 기본형.
    $scDef1 = Join-Path $scDefBase 'unjudged'; New-Item -ItemType Directory $scDef1 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo', '', '## Deferred / Follow-up', '- [미판정] **A**', '- [미판정] **B**', '', '## Out of Scope') | Set-Content -Encoding UTF8 (Join-Path $scDef1 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef1 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: Deferred 미판정 건수 주입 (SC40)" -R $r -ExpectExit 0 -ExpectContains 'Deferred 미판정 2건'

    # SC40b (델타 음성): 전부 판정됨([등재]/[미등재:기호]) → 부기 미발화.
    #   이 케이스가 없으면 "항상 부기"로 바꿔도 나머지가 전부 통과한다.
    $scDef2 = Join-Path $scDefBase 'judged'; New-Item -ItemType Directory $scDef2 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo', '', '## Deferred / Follow-up', '- [등재] **A**', '- [미등재:ⓓ] **B**', '', '## Out of Scope') | Set-Content -Encoding UTF8 (Join-Path $scDef2 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 전부 판정된 Deferred는 부기 미발화 (SC40b)" -R $r -ExpectExit 0 -ExpectContains '미완료 1' -ExpectNotContains 'Deferred 미판정'

    # SC40c (델타 음성): `## Deferred / Follow-up` 절 자체가 없는 plan → 부기 미발화·오류 없음.
    #   기존 픽스처 대부분이 이 형태라 무회귀의 근거이기도 하다.
    $scDef3 = Join-Path $scDefBase 'nosection'; New-Item -ItemType Directory $scDef3 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo') | Set-Content -Encoding UTF8 (Join-Path $scDef3 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef3 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: Deferred 절 부재면 부기 미발화 (SC40c)" -R $r -ExpectExit 0 -ExpectContains '미완료 1' -ExpectNotContains 'Deferred 미판정'

    # SC40d (양성 — 혼재 계수): 3건 중 1건만 [등재], 2건은 마커 없음 → **2건**으로 센다.
    #   이것이 "이관 도중 압축된" 실제 형태다. "plan에 마커가 하나라도 있으면 폴백을 끈다"로
    #   구현하면 이 케이스만 FAIL한다(D3이 막으려는 형태).
    $scDef4 = Join-Path $scDefBase 'mixed'; New-Item -ItemType Directory $scDef4 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo', '', '## Deferred / Follow-up', '- [등재] **A**', '- **B**', '- **C**', '', '## Out of Scope') | Set-Content -Encoding UTF8 (Join-Path $scDef4 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef4 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 마커 혼재 plan은 마커 없는 항목만 계수 (SC40d)" -R $r -ExpectExit 0 -ExpectContains 'Deferred 미판정 2건'

    # SC40e (폴백 고정): 마커가 전무한 구형 plan → 전 항목을 미판정으로 센다.
    #   마커 도입 전 plan이 조용히 0건으로 빠지지 않게 하는 축.
    $scDef5 = Join-Path $scDefBase 'legacy'; New-Item -ItemType Directory $scDef5 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo', '', '## Deferred / Follow-up', '- **A**', '- **B**', '', '## Out of Scope') | Set-Content -Encoding UTF8 (Join-Path $scDef5 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef5 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 마커 전무한 구형 plan은 전 항목 미판정 (SC40e)" -R $r -ExpectExit 0 -ExpectContains 'Deferred 미판정 2건'

    # SC40f (회귀 고정): task 전부 완료 + 미판정 있음 → `전부 완료` 라인과 건수가 **함께** 나온다.
    #   위 SC38 계열 픽스처는 Deferred 절이 없어 이 조합을 재지 못한다. 회차를 마친 plan이
    #   미이관 항목을 남긴 채 다음 세션으로 넘어가는 것이 이 회차가 막으려는 바로 그 상태다.
    $scDef6 = Join-Path $scDefBase 'done-unjudged'; New-Item -ItemType Directory $scDef6 -Force | Out-Null
    @('# Plan', '## Tasks', '- [x] T1. done', '', '## Deferred / Follow-up', '- [미판정] **A**', '', '## Out of Scope') | Set-Content -Encoding UTF8 (Join-Path $scDef6 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef6 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 전부 완료 plan에도 미판정 건수 (SC40f)" -R $r -ExpectExit 0 -ExpectContains '전부 완료'
    Assert-Case -Name "session-context: 전부 완료 + 미판정 동시 표기 (SC40f2)" -R $r -ExpectExit 0 -ExpectContains 'Deferred 미판정 1건'

    # SC40g (델타 음성 — placeholder): 템플릿 기본값(`- <이번엔 제외…>`)만 있는 절 → 부기 미발화.
    #   **갓 만든 모든 plan의 기본 상태**라, 꺾쇠 제외를 빠뜨리면 미판정 1건이 상시 오발화한다.
    #   T2 리뷰 1R이 실제로 이 결함을 재현으로 잡았다(마커 그룹이 필수라 치환 불발).
    $scDef7 = Join-Path $scDefBase 'placeholder'; New-Item -ItemType Directory $scDef7 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo', '', '## Deferred / Follow-up', '- <이번엔 제외, 향후 별도 plan으로 진행할 작업>', '', '## Out of Scope') | Set-Content -Encoding UTF8 (Join-Path $scDef7 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef7 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 템플릿 placeholder는 미판정으로 세지 않는다 (SC40g)" -R $r -ExpectExit 0 -ExpectContains '미완료 1' -ExpectNotContains 'Deferred 미판정'

    # SC40h (양성 — 기호 없는 미등재): `- [미등재] …`(게이트 기호 없음)는 **미판정으로 센다**.
    #   사유 없는 미등재는 게이트 ⓕ가 막으려는 「근거 미지목」과 같은 형태다. 이 케이스가 없으면
    #   구현자가 `[미등재]` 접두만 보고 제외해도 전건 green이다.
    #   ⚠ 둘째 항목이 **같은 줄 뒤쪽에 대괄호를 담는다** — 기호 정규식을 `.+`로 쓰면 `.`이 `]`도 먹어
    #     그 항목이 판정된 것으로 빠진다(F-7 2R m3). `[^\]]+`여야 이 픽스처가 2건으로 세어진다.
    $scDef8 = Join-Path $scDefBase 'no-gate'; New-Item -ItemType Directory $scDef8 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo', '', '## Deferred / Follow-up', '- [미등재] **A**', '- [미등재:] **B** 참고 [ref]', '', '## Out of Scope') | Set-Content -Encoding UTF8 (Join-Path $scDef8 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef8 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 기호 없는 미등재는 미판정으로 계수 (SC40h)" -R $r -ExpectExit 0 -ExpectContains 'Deferred 미판정 2건'

    # SC40i (양성 — 절이 파일 마지막): `## Deferred / Follow-up` 뒤에 다른 절이 없어 종료 앵커가
    #   없는 plan → 건수 정상 산출. 구간 추출이 종료 앵커를 못 찾아 **조용히 0건**이 되는 형태는
    #   이 회차가 막으려는 실패(미판정이 있는데 부기가 안 나감)와 같다.
    $scDef9 = Join-Path $scDefBase 'last-section'; New-Item -ItemType Directory $scDef9 -Force | Out-Null
    @('# Plan', '## Tasks', '- [ ] T1. todo', '', '## Deferred / Follow-up', '- [미판정] **A**') | Set-Content -Encoding UTF8 (Join-Path $scDef9 'plan.md')
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scDef9 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: Deferred 절이 파일 마지막이어도 계수 (SC40i)" -R $r -ExpectExit 0 -ExpectContains 'Deferred 미판정 1건'

    # SC40j (문면 고정 — E안): compact 리마인더에 「아직 plan.md에 적지 않은 발견을 지금 적으라」
    #   1구가 실린다. **대조 문자열은 기존 리마인더에 없는 신규 어휘**여야 한다 — 기존 '요약 직후'로
    #   재면 이 1구가 지워져도 통과한다. 같은 공백을 F-7이 두 번 지적해 사후 추가한 선례가 있다.
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'compact'; cwd = $scDef1 } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: compact 리마인더에 미기록 발견 지시 (SC40j)" -R $r -ExpectExit 0 -ExpectContains '아직 plan.md에 적지 않은'

    Remove-Item -Recurse -Force $scDefBase -ErrorAction SilentlyContinue

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

    # SC22b/SC22c: 위 SC22와 **같은 조건을 source=fork로** 한 번 더 — fork 경로에서 vault 라인과
    #   AGENTS.md 전문이 함께 주입되는지 고정한다. 앞의 SC2b는 plan 축만 보는데, fork matcher를 넣은
    #   목적은 그 세션에 plan·vault·AGENTS 셋이 다 들어가게 하는 것이라 나머지 두 축도 골든에 박아 둔다
    #   ($source는 이 두 블록을 게이팅하지 않으므로 startup과 결과가 같아야 한다 — 그 사실 자체가 검증 대상).
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'fork'; cwd = $scVOnly } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: fork도 vault 라인 주입 (SC22b)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨'
    Assert-Case -Name "session-context: fork도 AGENTS 전문 주입 (SC22c)" -R $r -ExpectExit 0 -ExpectContains 'SC_VAULT_ORDER_MARKER'

    # SC19: 설정됐으나 폴더 부재(이동·삭제) → 부재 문구 주입 (경로 재확인 신호)
    $isoV2 = Join-Path $EvalRunTemp ("pjc-hook-evals-vault-gone-" + $suffix)
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


    # SC32~SC36b: 위키 뒤처짐 알림 — cwd 에 대응하는 허브를 vault 에서 찾아 OR 3축
    #   (커밋 30 · 경과일 14 · [K-DRIFT] 1건)으로 발화한다.
    #   **축마다 단독 양성을 두는 것이 이 묶음의 요점이다** — 한 축만 양성으로 걸면 나머지
    #   축이 죽어도(날짜 파싱 실패 fail-open · AND 오구현) 전건이 통과한다. 경계 케이스
    #   (29/30커밋 · 13/14일)는 `-ge` ↔ `-gt` off-by-one 을 잡는 유일한 그물이다.
    # **픽스처는 git 레포 하나로 전부 덮는다** — 31커밋을 한 번 만들어 두고 허브의
    #   synced_commit 을 HEAD~30 / HEAD~29 / HEAD 로 바꾸면 30 / 29 / 0 커밋 뒤처짐이 된다.
    #   케이스마다 레포를 새로 파면 골든 러너에 git 프로세스가 수십 회 더 붙는다.
    # **git 게이트** — 이 묶음은 실제 레포 픽스처를 만들므로 git 이 없으면 통째로 건너뛴다.
    #   `& git` 은 명령을 못 찾으면 종료 오류를 던지는데 러너의 시나리오 루프에는 catch 가 없어
    #   그 예외가 스위트 전체를 중단시킨다(같은 이유로 `post-write-checks.ps1:138,181` 이
    #   git 시나리오를 이 게이트로 감싼다. $gitOk 는 `eval-common.ps1:98` 의 top-level 정의라
    #   필터 조합과 무관하게 항상 판정된다).
    if ($gitOk) {
    $scRepo = Join-Path $work ("sc-wiki-repo-" + $suffix)
    New-Item -ItemType Directory $scRepo -Force | Out-Null
    # 아래 remote add 와 SC37 계열 케이스가 공유하는 단일 출처 — 리터럴을 두 벌 두지 않는다.
    $scRepoUrl = 'https://example.invalid/scwiki/repo.git'
    # 격리 홈($isoV)에는 .gitconfig 가 없어 identity 를 인라인으로 준다 — 없으면 커밋이 선다
    #   (`scenarios/post-write-checks.ps1` 이 같은 형태를 쓴다).
    # Pop-Location 을 finally 에 두는 이유: 중간에서 터지면 위치 스택이 어긋난 채 남아
    #   뒤 시나리오가 엉뚱한 폴더에서 돈다.
    Push-Location $scRepo
    try {
        & git init -q 2>$null
        & git config user.email 't@t' 2>$null
        & git config user.name 't' 2>$null
        # 파일을 쓰지 않고 빈 커밋으로 수만 채운다 — 이 축이 재는 것은 커밋 «수» 뿐이다.
        for ($i = 1; $i -le 31; $i++) { & git commit -q --allow-empty -m "c$i" 2>$null }
        $scHeadSha = (& git rev-parse HEAD 2>$null | Select-Object -First 1)
        $scSha30   = (& git rev-parse 'HEAD~30' 2>$null | Select-Object -First 1)
        $scSha29   = (& git rev-parse 'HEAD~29' 2>$null | Select-Object -First 1)
        # SC37·SC37a·SC37b·SC37d 용 origin (SC37c 는 제외 — 그 케이스는 «origin 이 없는» 상태를
        #   재려고 아래에서 무-origin 픽스처를 따로 판다). 네트워크에 닿지 않는 `.invalid` TLD 를
        #   쓴다(픽스처가 실수로 fetch 를 유발하지 않게). hook 은 로컬 config 만 읽으므로
        #   실재할 필요가 없다.
        # **값은 $scRepoUrl 하나만 쓴다** — 여기와 케이스 쪽에 리터럴을 두 벌 두면 한쪽만 고쳤을 때
        #   URL 불일치로 SC37 계열이 조용히 깨진다(케이스는 «불일치 = 미발화»라 FAIL 이 아니라
        #   양성이 사라지는 형태로 나타나 알아채기 어렵다).
        & git remote add origin $scRepoUrl 2>$null
    } finally { Pop-Location }
    # 게이팅 충족용 — 삽입은 `if ($vaultLine -and ($lines.Count -gt $cwdBaseCount))` 안에서만
    #   일어나므로, plan·AGENTS 가 없는 cwd 에서는 양성이 전건 FAIL 하고 음성은 공허하게 통과한다.
    #   이 마커는 SC36 의 순서 비교 대상이기도 하다.
    @('# Guide', 'SC_STALE_ORDER_MARKER 전문 주입 대상') | Set-Content -Encoding UTF8 (Join-Path $scRepo 'AGENTS.md')

    $scHubDir = Join-Path $isoVault '20_projects/personal'
    New-Item -ItemType Directory $scHubDir -Force | Out-Null
    $scHubPath = Join-Path $scHubDir 'scwiki.md'
    $scPendPath = Join-Path $isoVault 'pending.md'

    # 허브를 쓰는 지역 헬퍼 — 아래에서 아홉 번 넘게 부른다(값만 바뀌고 형태는 같다).
    #   $Sha 가 빈 문자열이면 synced_commit 줄 자체를 빼 「필드 부재」 상태를 만든다.
    #   $RepoUrl 이 빈 문자열이면 repo_url 줄 자체를 빼 「구형 허브」(URL 축 이전) 상태를 만든다 —
    #   SC32~SC36b 가 전부 그 상태이며, 그래서 그 케이스들은 URL 축이 아니라 **경로 축**으로 통과한다.
    function Write-ScHub {
        param([string]$Path, [string]$RepoPath, [string]$Sha, [int]$DaysAgo, [string]$Project = 'SCWiki', [string]$RepoUrl = '')
        $upd = (Get-Date).AddDays(-$DaysAgo).ToString('yyyy-MM-dd')
        $lines = @('---', 'type: project', "project: $Project", "updated: $upd")
        if ($Sha) { $lines += "synced_commit: $Sha" }
        if ($RepoUrl) { $lines += "repo_url: `"$RepoUrl`"" }
        $lines += @('---', '', "# $Project", '', '## 레포 정보', ('- **경로**: `' + ($RepoPath -replace '\\', '/') + '`'))
        $lines | Set-Content -Encoding UTF8 $Path
    }
    function Invoke-ScRepoHook { Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scRepo } | ConvertTo-Json -Compress) }

    $env:USERPROFILE = $isoV

    # SC32 (양성 — 커밋 축 단독): 30커밋 · updated 오늘 · K-DRIFT 0
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scSha30 -DaysAgo 0
    Remove-Item -Force $scPendPath -ErrorAction SilentlyContinue
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 위키 뒤처짐 커밋 축 발화 (SC32)" -R $r -ExpectExit 0 -ExpectContains '위키 뒤처짐'
    Assert-Case -Name "session-context: 뒤처짐 커밋 수 표기 (SC32b)" -R $r -ExpectExit 0 -ExpectContains '30커밋 미반영'

    # SC32c (양성 — 일수 축 단독): 커밋 0 · updated 15일 전 · K-DRIFT 0.
    #   이 케이스가 없으면 경과일 판정이 죽어도 나머지가 전부 통과한다.
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scHeadSha -DaysAgo 15
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 위키 뒤처짐 일수 축 단독 발화 (SC32c)" -R $r -ExpectExit 0 -ExpectContains '위키 뒤처짐'
    Assert-Case -Name "session-context: 일수 축 경과일 표기 (SC32c2)" -R $r -ExpectExit 0 -ExpectContains '15일 경과'

    # SC32d (경계 — 커밋 축): 정확히 30이면 발화, 29면 미발화(다른 축 미달).
    #   `-ge` 를 `-gt` 로 바꾸면 앞이 깨지고, 임계를 낮추면 뒤가 깨진다.
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scSha30 -DaysAgo 0
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 커밋 축 경계 30 발화 (SC32d)" -R $r -ExpectExit 0 -ExpectContains '위키 뒤처짐'
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scSha29 -DaysAgo 0
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 커밋 축 경계 29 미발화 (SC32d2)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '위키 뒤처짐'

    # SC32e (경계 — 일수 축): 정확히 14면 발화, 13이면 미발화. 커밋 축은 0으로 눌러 둔다.
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scHeadSha -DaysAgo 14
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 일수 축 경계 14 발화 (SC32e)" -R $r -ExpectExit 0 -ExpectContains '위키 뒤처짐'
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scHeadSha -DaysAgo 13
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 일수 축 경계 13 미발화 (SC32e2)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '위키 뒤처짐'

    # SC33 (양성 — K-DRIFT 축 단독): 커밋·일수 둘 다 미달인데 잔량 1건 → 잔량만 실은 라인.
    #   뒤처짐 수치를 싣지 않는 것이 이 축의 계약이다("0커밋 미반영"은 사실이 아니다).
    "- [2026-08-01] [K-DRIFT] SCWiki: 무언가 어긋났다" | Set-Content -Encoding UTF8 $scPendPath
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: K-DRIFT 축 단독 발화 (SC33)" -R $r -ExpectExit 0 -ExpectContains '미반영 발견 1건'
    Assert-Case -Name "session-context: 잔량 단독이면 커밋 수치 미표기 (SC33b)" -R $r -ExpectExit 0 -ExpectNotContains '커밋 미반영'
    # 잔량 단독 문구 자체를 고정한다 — 이 문면을 재는 케이스가 없으면 바뀌어도 아무도 모른다
    #   (F-7 m1: 종전 문구는 뒤에 붙는 부기와 "미반영 발견"이 겹쳐 같은 말이 한 줄에 두 번 나왔다).
    Assert-Case -Name "session-context: 잔량 단독 문구 고정 (SC33d)" -R $r -ExpectExit 0 -ExpectContains '반영이 밀려'

    # SC33c (델타 음성 — 3축 전부 미달): 커밋 0 · updated 오늘 · 잔량 0 → 미발화.
    #   **세 축을 전부 이 자리에서 다시 세운다** — 앞 케이스가 남긴 상태(13일·잔량 1건)를
    #   물려받으면 이 케이스가 무엇을 눌러 둔 것인지 읽는 쪽에서 알 수 없고, 경계값(13일)과
    #   중복 커버리지가 되어 「임계에서 멀리 떨어진 값」이 검증되지 않는다.
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scHeadSha -DaysAgo 0
    Remove-Item -Force $scPendPath -ErrorAction SilentlyContinue
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 3축 전부 미달 미발화 (SC33c)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '위키 뒤처짐'

    # SC34 (델타 음성): cwd 에 대응하는 허브가 없다 → 미발화(vault 라인은 유지).
    Write-ScHub -Path $scHubPath -RepoPath (Join-Path $work 'sc-somewhere-else') -Sha $scSha30 -DaysAgo 30
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 허브 무매치 미발화 (SC34)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '위키 뒤처짐'

    # SC35 (델타 음성): synced_commit 필드 부재 + 일수 미달 + 잔량 0 → 미발화(fail-open).
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha '' -DaysAgo 0
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: synced_commit 부재 미발화 (SC35)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '위키 뒤처짐'

    # SC35b (양성 — 축 하나만 계산됨): synced_commit 부재(커밋 축 미계산) + 15일(일수 축 발화).
    #   미계산 sentinel(-1)이 문구로 새면 "-1커밋 미반영"이 나온다 — 실측으로 재현된 결함이라
    #   그 형태가 다시 나오지 않는지를 이 케이스가 고정한다.
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha '' -DaysAgo 15
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: 축 하나만 계산돼도 발화 (SC35b)" -R $r -ExpectExit 0 -ExpectContains '15일째 미반영'
    Assert-Case -Name "session-context: 미계산 sentinel 미노출 (SC35b2)" -R $r -ExpectExit 0 -ExpectNotContains '-1커밋'

    # SC36 (순서 — 비하네스 cwd): vault < 뒤처짐 < AGENTS 전문.
    #   Assert-Case 는 순서를 못 보므로 IndexOf 로 직접 판정한다(SC22 와 같은 패턴).
    #   비하네스라 $feedbackLine 이 $null 이고, 오프셋을 `+2` 로 못박았으면 여기서 밀려난다.
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scSha30 -DaysAgo 0
    $r = Invoke-ScRepoHook
    $iVault  = $r.out.IndexOf('위키 vault: 설정됨')
    $iStale  = $r.out.IndexOf('위키 뒤처짐')
    $iMarker = $r.out.IndexOf('SC_STALE_ORDER_MARKER')
    if (($r.code -eq 0) -and ($iVault -ge 0) -and ($iStale -gt $iVault) -and ($iMarker -gt $iStale)) {
        $script:results.Add(@{ ok = $true; line = "[PASS] session-context: 뒤처짐 라인이 vault 뒤·AGENTS 앞 (SC36)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] session-context: SC36 순서 위반 (exit=$($r.code), vault=$iVault, stale=$iStale, agents=$iMarker)" })
    }

    # SC36b (순서 — 하네스 cwd, 큐 라인 동반): vault < 큐 < 뒤처짐.
    #   **SC36 만으로는 $feedbackLine 이 항상 $null 인 구간만 돈다** — 오프셋 식의
    #   `[int][bool]$feedbackLine == 1` 분기를 밟는 케이스가 여기뿐이라, `+1` 하드코딩
    #   (큐 라인과 순서가 뒤바뀜)은 이 케이스가 없으면 아무도 못 잡는다.
    $scHarnRepo = Join-Path $work ("sc-wiki-harness-" + $suffix)
    New-Item -ItemType Directory -Path (Join-Path $scHarnRepo 'plugins/pjc/.claude-plugin') -Force | Out-Null
    '{ "name": "pjc" }' | Set-Content -Encoding UTF8 (Join-Path $scHarnRepo 'plugins/pjc/.claude-plugin/plugin.json')
    @('# Guide', 'SC_STALE_HARNESS_MARKER') | Set-Content -Encoding UTF8 (Join-Path $scHarnRepo 'AGENTS.md')
    Push-Location $scHarnRepo
    try {
        & git init -q 2>$null
        & git config user.email 't@t' 2>$null
        & git config user.name 't' 2>$null
        & git commit -q --allow-empty -m 'base' 2>$null
        $scHarnSha = (& git rev-parse HEAD 2>$null | Select-Object -First 1)
    } finally { Pop-Location }
    # 큐 라인이 뜨려면 skill-feedback.md 가 있어야 한다(SC25 가 지운 뒤라 다시 만든다).
    "- [2026-07-22] [SKILL-IMPROVE] implement-task: 요지." | Set-Content -Encoding UTF8 (Join-Path $isoVault 'skill-feedback.md')
    Write-ScHub -Path (Join-Path $scHubDir 'scharn.md') -RepoPath $scHarnRepo -Sha $scHarnSha -DaysAgo 20 -Project 'SCHarn'
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scHarnRepo } | ConvertTo-Json -Compress)
    $iVault2 = $r.out.IndexOf('위키 vault: 설정됨')
    $iQueue  = $r.out.IndexOf('스킬 개선 큐')
    $iStale2 = $r.out.IndexOf('위키 뒤처짐')
    if (($r.code -eq 0) -and ($iVault2 -ge 0) -and ($iQueue -gt $iVault2) -and ($iStale2 -gt $iQueue)) {
        $script:results.Add(@{ ok = $true; line = "[PASS] session-context: 큐 라인 동반 시 뒤처짐이 그 뒤 (SC36b)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] session-context: SC36b 순서 위반 (exit=$($r.code), vault=$iVault2, queue=$iQueue, stale=$iStale2)" })
    }

    # SC37~SC37d: 허브 매칭의 **URL 축** (v1.206.0 T3).
    #   위 SC32~SC36b 는 허브에 repo_url 이 없어 전부 **경로 축**으로 통과한다 — 그것이 축②
    #   (구형 허브 폴백)의 실증이고, 아래 넷이 축①과 그 경계를 덮는다.
    #   **양성만 늘리면 「URL 을 본다」는 근거가 안 된다** — SC37b(경로가 맞는데도 URL 이 달라
    #   미발화)가 이 묶음의 델타 음성이며, 그것이 없으면 경로로 통과한 것과 구분되지 않는다.
    # 두 신규 cwd 에도 게이팅 마커를 둔다 — 라인 삽입은 `$lines.Count -gt $cwdBaseCount` 안에서만
    #   일어나므로(위 SC32 준비의 같은 이유) AGENTS.md 가 없으면 양성 케이스가 전건 FAIL 한다.
    $scSubDir = Join-Path $scRepo 'sub/deep'
    New-Item -ItemType Directory $scSubDir -Force | Out-Null
    @('# Guide', 'SC_URL_SUB_MARKER') | Set-Content -Encoding UTF8 (Join-Path $scSubDir 'AGENTS.md')
    # origin 없는 둘째 픽스처 — SC37c 전용이다. 하나로 덮을 수 없는 이유는 SC37·SC37b 가
    #   origin 있는 레포를 요구하고 SC37c 는 없는 레포를 요구하기 때문이다(레포 추가는 여기 1개까지).
    $scRepoNoRemote = Join-Path $work ("sc-wiki-noremote-" + $suffix)
    New-Item -ItemType Directory $scRepoNoRemote -Force | Out-Null
    Push-Location $scRepoNoRemote
    try {
        & git init -q 2>$null
        & git config user.email 't@t' 2>$null
        & git config user.name 't' 2>$null
        & git commit -q --allow-empty -m 'base' 2>$null
    } finally { Pop-Location }
    @('# Guide', 'SC_URL_NOREMOTE_MARKER') | Set-Content -Encoding UTF8 (Join-Path $scRepoNoRemote 'AGENTS.md')

    # SC37 (양성 — URL 축 단독): repo_url 일치 · **경로는 엉뚱한 값**.
    #   경로가 틀렸는데도 발화한다는 것이 「URL 로 골랐다」의 유일한 직접 증거다.
    Write-ScHub -Path $scHubPath -RepoPath (Join-Path $work 'sc-not-this-path') -Sha $scSha30 -DaysAgo 0 -RepoUrl $scRepoUrl
    Remove-Item -Force $scPendPath -ErrorAction SilentlyContinue
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: URL 축 발화 — 경로 불일치여도 매칭 (SC37)" -R $r -ExpectExit 0 -ExpectContains '위키 뒤처짐'

    # SC37a (양성 — 정규화): 허브 값에 `.git` 없음 + 대문자 + 후행 슬래시.
    #   소문자화·`.git` 제거·TrimEnd('/') 셋이 다 살아 있어야 통과한다.
    Write-ScHub -Path $scHubPath -RepoPath (Join-Path $work 'sc-not-this-path') -Sha $scSha30 -DaysAgo 0 -RepoUrl 'HTTPS://Example.INVALID/scwiki/Repo/'
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: URL 정규화(대소문자·.git·슬래시) (SC37a)" -R $r -ExpectExit 0 -ExpectContains '위키 뒤처짐'

    # SC37b (델타 음성 — 이 묶음의 핵심): repo_url 이 **다른 레포** · 경로는 **일치**.
    #   URL 이 있으면 경로로 되짚지 않으므로 미발화여야 한다. 되짚는 구현이면 여기서 발화해 FAIL.
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scSha30 -DaysAgo 0 -RepoUrl 'https://example.invalid/other/repo.git'
    $r = Invoke-ScRepoHook
    Assert-Case -Name "session-context: URL 불일치면 경로가 맞아도 미발화 (SC37b)" -R $r -ExpectExit 0 -ExpectContains '위키 vault: 설정됨' -ExpectNotContains '위키 뒤처짐'

    # SC37c (양성 — cwd 에 origin 없음 → URL 축 off): 허브에 repo_url 이 있어도 경로로 판정한다.
    #   이 케이스가 없으면 「remote 없는 로컬 전용 레포가 조용히 침묵하는」 형태를 아무도 못 잡는다.
    Write-ScHub -Path $scHubPath -RepoPath $scRepoNoRemote -Sha '' -DaysAgo 15 -RepoUrl $scRepoUrl
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scRepoNoRemote } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: cwd origin 부재면 URL 축 off·경로로 발화 (SC37c)" -R $r -ExpectExit 0 -ExpectContains '15일째 미반영'

    # SC37d (양성 — 하위 폴더 cwd): `git -C` 가 상위를 찾으므로 레포 안 어디서 열어도 매칭된다.
    #   경로 축은 **동일 경로만** 보므로 하위 폴더에서는 매칭되지 않는다 — 그래서 이 케이스는
    #   URL 축이 실제로 범위를 넓혔다는 증거다(대장 `[2026-08-26]` 항목이 지적하던 공백).
    Write-ScHub -Path $scHubPath -RepoPath $scRepo -Sha $scSha30 -DaysAgo 0 -RepoUrl $scRepoUrl
    $r = Invoke-Hook 'session-context.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $scSubDir } | ConvertTo-Json -Compress)
    Assert-Case -Name "session-context: 하위 폴더 cwd 도 URL 로 매칭 (SC37d)" -R $r -ExpectExit 0 -ExpectContains '위키 뒤처짐'

    Remove-Item -Recurse -Force $scRepo, $scHarnRepo, $scRepoNoRemote -ErrorAction SilentlyContinue
    }   # ---- git 게이트 끝 (SC32~SC37d)

    Remove-Item -Recurse -Force $isoV, $isoV2, $scHarn -ErrorAction SilentlyContinue
}   # ---- §13 게이트 끝 (session-context) ----

