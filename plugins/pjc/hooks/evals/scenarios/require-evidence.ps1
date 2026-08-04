# scenarios/require-evidence.ps1 — require-evidence 시나리오 (§4 — 검사 1~3 경고 + 검사 4 자율 루프 정지 차단) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 4) require-evidence 시나리오 (git 필요 — 부재 시 skip. $gitOk는 top-level 공유 정의)
# =====================================================================
if (Test-HookSelected @('require-evidence')) {
if ($gitOk) {
    $repo = Join-Path $work 'evrepo'; New-Item -ItemType Directory $repo -Force | Out-Null
    Push-Location $repo
    git init -q; git config user.email t@t; git config user.name t
    'x' | Set-Content a.txt; git add .; git commit -qm 'checkpoint: T1 start'
    Pop-Location
    $json = @{ cwd = $repo } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'require-evidence.ps1' $json
    Assert-Case -Name "evidence: checkpoint 커밋 경고" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    Push-Location $repo; 'y' | Set-Content a.txt; git add .; git commit -qm 'T1: 작업 완료'; Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' $json
    Assert-Case -Name "evidence: T커밋 증거 없음 경고" -R $r -ExpectExit 0 -ExpectContains '증거'
    Push-Location $repo; 'z' | Set-Content a.txt; git add .; git commit -qm "T2: done`n`nBuild OK, Tests 3/3 passed"; 'w' | Set-Content b.cs; Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' $json
    Assert-Case -Name "evidence: 미커밋 코드(.cs) 경고" -R $r -ExpectExit 0 -ExpectContains '커밋되지 않은 코드'

    # ---- [P1T5] require-evidence 신규 동작 골든 (traceRx 스크립트 빌드 · 세션 Write/Edit 게이트) ----
    # 깨끗한 트리 + 증거 있는 T커밋으로 재설정(미커밋·checkpoint 경고 배제하고 traceRx만 검증).
    $ev2 = Join-Path $work 'evrepo2'; New-Item -ItemType Directory $ev2 -Force | Out-Null
    Push-Location $ev2
    git init -q; git config user.email t@t; git config user.name t
    'x' | Set-Content a.txt; git add .; git commit -qm "T1: done`n`nBuild OK, Tests 2/2 passed"
    Pop-Location
    # (A1) transcript에 표준·스크립트 빌드 흔적 없음 → '실행 흔적 못 찾음' 경고 발생
    $trA1 = Join-Path $work 'tr-a1.jsonl'
    '{"type":"tool_use","name":"Bash","input":{"command":"git status"}}' | Set-Content -Encoding UTF8 $trA1
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trA1 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: transcript에 빌드 흔적 없음 → 실행흔적 경고 (P1T5 대조군)" -R $r -ExpectExit 0 -ExpectContains '실행 흔적'
    # (A2) transcript에 스크립트 빌드(build.ps1) 흔적 → 실행흔적 경고 억제(traceRx 확장 검증). 깨끗한 트리라 전체 무출력.
    $trA2 = Join-Path $work 'tr-a2.jsonl'
    '{"type":"tool_use","name":"Bash","input":{"command":"pwsh -NoProfile -File ./build.ps1"}}' | Set-Content -Encoding UTF8 $trA2
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trA2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: transcript에 build.ps1 흔적 → 실행흔적 경고 억제 (P1T5 traceRx)" -R $r -ExpectExit 0 -ExpectSilent $true
    # (B) 미커밋 .cs + transcript에 Write/Edit 없음 → 미커밋 경고 억제(세션 게이트). build.ps1 흔적으로 실행흔적 경고도 배제.
    Push-Location $ev2; 'w' | Set-Content orphan.cs; Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trA2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 미커밋 .cs + Write/Edit 없는 세션 → 미커밋 경고 억제 (P1T5 세션 게이트)" -R $r -ExpectExit 0 -ExpectSilent $true
    # (B 대조군) 같은 미커밋 상태 + transcript에 Write 흔적 → 미커밋 경고 발생(억제가 무차별 아님)
    $trB2 = Join-Path $work 'tr-b2.jsonl'
    @('{"type":"tool_use","name":"Bash","input":{"command":"pwsh -File ./build.ps1"}}', '{"type":"tool_use","name":"Write","input":{"file_path":"orphan.cs"}}') | Set-Content -Encoding UTF8 $trB2
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev2; transcript_path = $trB2 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 미커밋 .cs + Write 흔적 세션 → 미커밋 경고 유지 (P1T5 게이트 무차별 아님)" -R $r -ExpectExit 0 -ExpectContains '커밋되지 않은 코드'

    # ---- [v1.138.0 T5] 세션 디듑 골든 (같은 세션·같은 프로젝트의 동일 종류 경고는 1회) ----
    # 별도 repo(evrepo3)로 격리한다 — 마커 키가 cwd를 포함하므로 위 케이스들(evrepo·evrepo2)과 겹치지 않는다.
    #   (이 키 설계가 기존 골든 무회귀의 조건이다: 507의 evrepo 미커밋 경고와 534의 evrepo2 미커밋 경고가 둘 다 살아야 한다.)
    $ev3 = Join-Path $work 'evrepo3'; New-Item -ItemType Directory $ev3 -Force | Out-Null
    Push-Location $ev3
    git init -q; git config user.email t@t; git config user.name t
    'x' | Set-Content a.txt; git add .; git commit -qm 'checkpoint: T1 start'
    Pop-Location
    $jd1 = @{ cwd = $ev3; session_id = 'sd1' } | ConvertTo-Json -Compress
    # (D1) 같은 세션 1회차 → 경고 발생
    $r = Invoke-Hook 'require-evidence.ps1' $jd1
    Assert-Case -Name "evidence: 세션 디듑 1회차 → 경고 발생 (T5 red)" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    # (D2) 같은 세션 2회차 → 억제(무출력). T5의 핵심 동작.
    $r = Invoke-Hook 'require-evidence.ps1' $jd1
    Assert-Case -Name "evidence: 세션 디듑 2회차 → 억제 (T5 green)" -R $r -ExpectExit 0 -ExpectSilent $true
    # (D3) 다른 세션 → 다시 발생(디듑 단위가 세션임을 실증 — 영구 억제가 아니다)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev3; session_id = 'sd2' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 다른 세션 → 경고 재발생 (T5 세션 단위)" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    # (D4) 같은 세션·다른 종류 → 독립 발생(checkpoint는 억제된 상태에서 미커밋 경고는 살아 있어야 한다)
    Push-Location $ev3; 'w' | Set-Content orphan.cs; Pop-Location
    $trD = Join-Path $work 'tr-d.jsonl'
    '{"type":"tool_use","name":"Write","input":{"file_path":"orphan.cs"}}' | Set-Content -Encoding UTF8 $trD
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev3; session_id = 'sd1'; transcript_path = $trD } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 같은 세션 다른 종류 → 독립 발생 (T5 종류별 키)" -R $r -ExpectExit 0 -ExpectContains '커밋되지 않은 코드'
    # (D5) 마커 디렉터리 생성 불가 → fail-open(경고 유지). 상태 경로에 동명 '파일'을 두어 디렉터리 생성을 막는다.
    $reMarkerDir = Join-Path $iso '.claude/.state/require-evidence-warn'
    if (Test-Path -LiteralPath $reMarkerDir) { Remove-Item -Recurse -Force $reMarkerDir }
    New-Item -ItemType File -Path $reMarkerDir -Force | Out-Null
    $r = Invoke-Hook 'require-evidence.ps1' $jd1
    Assert-Case -Name "evidence: 마커 생성 불가 → fail-open 경고 유지 (T5)" -R $r -ExpectExit 0 -ExpectContains 'checkpoint'
    Remove-Item -Force -LiteralPath $reMarkerDir

    # ---- [v1.148.0 T3 / v1.149.0 T3] 자율 루프 미완료 정지 차단 골든 (검사 4 — 유일한 차단 경로) ----
    # 검사 1~3은 비차단 경고라 stderr만 보지만, 검사 4는 stdout에 {"decision":"block"}을 낸다.
    #   Invoke-Hook이 2>&1로 합치므로 ExpectContains로 그 리터럴을 직접 고정한다.
    # 잡는 정지는 4유형 — ② 진행 예고 / ③ 세션 전환 제안 / ④ 중간 수동 실행 요청 /
    #   ⑤ 순수 진행 요약으로 turn 종료(v1.150.0).
    # 음성을 두텁게(v1.148.0의 7건 + v1.149.0의 10건 = **17건**) 까는 이유: 오차단이 이 검사의
    #   최악 실패다(사용자가 세션을 못 끝낸다).
    #   음성은 ExpectSilent가 아니라 ExpectNotContains를 쓴다 — 검사 1~3의 stderr 경고가 함께
    #   나올 수 있어 무출력이 아니며, 여기서 확인할 것은 "차단되지 않았다"뿐이다.
    # ③④⑤는 Weak 신호(물음표·"확인 요청")를 통과 근거로 인정하지 않으므로 오차단 표면이 ②보다
    #   넓다. 그래서 **정당 개입 지점은 Strong 마커(⛔🎉⏸️)로 구분**하는데, 그 경계가 실제로
    #   작동하는지는 **마커 유무만 다른 델타 짝**(L20~L22)으로만 실증된다 — 애초에 정규식에
    #   닿지 않는 문면을 음성으로 깔면 그건 무회귀 케이스일 뿐 경계의 근거가 되지 못한다
    #   (AGENTS.md `## DO NOT`의 미탐 보완 조항이 요구하는 실증 형식).
    $loopMsg = '여기까지 진행 상황을 정리 합니다. 계속 T5부터 이어서 진행하겠습니다.'
    $loopBlock = '"decision":"block"'
    # 정상 transcript: implement-task 발동 흔적 + 평범한 사용자 발화
    $loopTr = Join-Path $work 'tr-loop.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"진행"}}'
    ) | Set-Content -Encoding UTF8 $loopTr

    # 미완료 task가 있는 저장소 2종 — task 형식 ⓑ(heading)와 ⓐ(템플릿).
    #   한 형식만 픽스처로 두면 다른 형식에서의 무발화가 검출되지 않는다(plan 2회차 BLOCKER).
    #   커밋 메시지에 'Build: OK'를 넣어 검사 2(증거 없음)가 함께 발동하지 않게 한다.
    $ev4 = Join-Path $work 'evrepo4'; New-Item -ItemType Directory $ev4 -Force | Out-Null
    Push-Location $ev4
    git init -q; git config user.email t@t; git config user.name t
    "# plan`n`n### T1 - first`n- [x] **Type**: C`n`n### T2 - second`n- [ ] **Type**: C`n" | Set-Content -Encoding UTF8 plan.md
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: first (Build: OK)'
    Pop-Location

    $ev5 = Join-Path $work 'evrepo5'; New-Item -ItemType Directory $ev5 -Force | Out-Null
    Push-Location $ev5
    git init -q; git config user.email t@t; git config user.name t
    "# plan`n`n- [x] T1. first`n- [ ] T2. second`n" | Set-Content -Encoding UTF8 plan.md
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: first (Build: OK)'
    Pop-Location

    # (L1) 양성 ⓑ — heading 형식 + **실제 사고 문장 원문**.
    #   리터럴 4문구가 아니라 어간 매칭이어야 걸린다(원문은 "여기까지 진행 상황을 정리 합니다"처럼
    #   어절이 삽입돼 있어, 리터럴 "여기까지 정리합니다"로는 매치되지 않는다).
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp1'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 미완료 + 예고 문구(heading 형식·실제 사고 원문) → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L2) 양성 ⓐ — 템플릿 형식(`- [ ] T2. second`)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev5; session_id = 'lp2'; transcript_path = $loopTr; last_assistant_message = '이어서 진행하겠습니다' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 미완료 + 예고 문구(템플릿 형식) → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L3) 음성 — stop_hook_active=true (재귀 차단 방지: 이 hook이 건 block으로 Stop이 다시 돌 때)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp3'; transcript_path = $loopTr; last_assistant_message = $loopMsg; stop_hook_active = $true } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: stop_hook_active=true → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L4) 음성 — 미완료 task 0 (전부 [x])
    $ev6 = Join-Path $work 'evrepo6'; New-Item -ItemType Directory $ev6 -Force | Out-Null
    Push-Location $ev6
    git init -q; git config user.email t@t; git config user.name t
    "# plan`n`n### T1 - only`n- [x] **Type**: C`n" | Set-Content -Encoding UTF8 plan.md
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: only (Build: OK)'
    Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev6; session_id = 'lp4'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 미완료 task 0 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L5) 음성 — 정당한 정지 신호(Halt 보고 마커)가 함께 있음
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp5'; transcript_path = $loopTr; last_assistant_message = "## ⛔ 작업 중단: T2`n이어서 진행하겠습니다만 중단합니다" } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: Halt 보고 마커 동반 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L6) 음성 — **사용자가 중단을 지시**했다. 이 검사에서 가장 중요한 안전 조건:
    #   어시스턴트 발화만 보면 사용자가 멈추라고 한 세션에 루프 재개를 강요하게 된다.
    $loopTrStop = Join-Path $work 'tr-loop-stop.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"오늘은 그만 하자"}}'
    ) | Set-Content -Encoding UTF8 $loopTrStop
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp6'; transcript_path = $loopTrStop; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 사용자가 중단 지시 → 미차단 (T3 음성·최우선 안전 조건)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L7) 음성 — `docs/plans/deferred.md`만 있는 저장소는 plan으로 인정하지 않는다.
    #   대장에는 task 패턴(ⓐ·ⓑ)이 없으므로 파일 수준 게이트에서 탈락해야 한다.
    $ev7 = Join-Path $work 'evrepo7'; New-Item -ItemType Directory $ev7 -Force | Out-Null
    Push-Location $ev7
    git init -q; git config user.email t@t; git config user.name t
    New-Item -ItemType Directory (Join-Path $ev7 'docs/plans') -Force | Out-Null
    "# Deferred 대장`n`n## 대기`n`n- [2026-07-30] 미처리 항목`n" | Set-Content -Encoding UTF8 (Join-Path $ev7 'docs/plans/deferred.md')
    'x' | Set-Content a.txt; git add .; git commit -qm 'T1: first (Build: OK)'
    Pop-Location
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev7; session_id = 'lp7'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: deferred.md만 있는 repo → plan 미인정, 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L8) 음성 — 직전 user 엔트리가 tool_result뿐이면 사용자 발화 추출 0건 → fail-open.
    #   tool_result를 사용자 발화로 오인하면 이 조건이 항상 참이 되어 (L6)의 방어가 무너진다.
    $loopTrTool = Join-Path $work 'tr-loop-tool.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x1","content":"ok"}]}}'
    ) | Set-Content -Encoding UTF8 $loopTrTool
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp8'; transcript_path = $loopTrTool; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: user 엔트리가 tool_result뿐 → fail-open 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L9) 음성 — 예고 문구가 없는 평범한 종료(positive 매치가 실제 게이트로 작동하는지)
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp9'; transcript_path = $loopTr; last_assistant_message = '요청하신 조사를 마쳤습니다.' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 예고 문구 없는 종료 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L10) 음성 — stdin 필드가 없어도 transcript 폴백으로 판정한다(양성) / 그 폴백에서도 사용자
    #   중단 지시는 억제된다. 필드 미제공 환경에서 검사가 죽은 코드가 되지 않음을 고정한다.
    $loopTrFb = Join-Path $work 'tr-loop-fb.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"진행"}}',
        (New-TranscriptLine -Type assistant -Text $loopMsg)
    ) | Set-Content -Encoding UTF8 $loopTrFb
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lpA'; transcript_path = $loopTrFb } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: stdin 필드 부재 + transcript 폴백 → 차단 (T3 양성·폴백)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L11) 상한 — 같은 세션·같은 plan에서 4회째는 차단하지 않는다(판정이 어긋나도 세션을 끝낼 수 있게).
    $capJson = @{ cwd = $ev5; session_id = 'lpCap'; transcript_path = $loopTr; last_assistant_message = '계속 진행합니다' } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 1회차 → 차단 (T3)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 2회차 → 차단 (T3)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 3회차 → 차단 (T3)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' $capJson
    Assert-Case -Name "evidence: 차단 상한 4회차 → 미차단 (T3 상한 실증)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L12) 문서↔코드 동일성 대조 — SKILL.md 금지 표현 ②③④⑤ **네 절**의 문구 목록을 파일에서
    #   읽어 각 문구가 실제로 차단을 유발하는지 확인한다.
    #   여기서 문구를 하드코딩하면 안 된다: SKILL.md가 정본이므로 그쪽이 바뀌었는데 hook의
    #   정규식($rxAdvance·$rxHandoff·$rxManualAsk·$rxProgressOnly)이 안 따라가면 "규칙에 있는데 안 잡히는"
    #   상태가 되는데, 하드코딩 사본은 그 드리프트를 영원히 못 본다(사본이 낡은 채로 계속 green).
    #   어느 절이든 추출이 0건이면 그 자체가 FAIL이라 SKILL.md 구조 변경도 신호로 잡힌다.
    $skillMdPath = Join-Path $pluginRoot 'skills/implement-task/SKILL.md'
    $skillTxt = ''
    try { $skillTxt = Get-Content -LiteralPath $skillMdPath -Raw -Encoding UTF8 } catch {}
    # 절 헤더 리터럴은 SKILL.md가 정본이며 여기가 추종한다(T1이 고정한 문자열).
    # key는 세션 id 조립용 **ASCII** 식별자다 — 절 헤더의 원 문자(②③④⑤)를 쓰면 안 된다:
    #   hook이 session_id를 `[^\w.-]` → `_`로 정규화하는데 이 넷은 전부 `\w`가 아니라
    #   네 절이 모두 같은 id(`lpP_1`…)로 뭉개진다. 그러면 차단 3회 상한 카운터를 공유해
    #   **네 번째 절의 문구가 상한 초과로 미차단**되어 거짓 FAIL이 난다(⑤ 추가 시 실측으로 드러남 —
    #   3절까지는 3회차라 우연히 통과하던 잠재 결함이다).
    foreach ($sec in @(
            @{ label = '② 평서형 예고'; head = '② 평서형 예고'; key = 'a' },
            @{ label = '③ 세션 전환 제안'; head = '③ 세션 전환'; key = 'b' },
            @{ label = '④ 수동 실행 요청'; head = '④ 중간 수동'; key = 'c' },
            @{ label = '⑤ 순수 진행 요약'; head = '⑤ 순수 진행'; key = 'd' })) {
        $phraseList = @()
        try {
            # 개행 클래스는 [\r\n]로 쓴다 — SKILL.md가 CRLF라 `\n+`는 `\r\n\r\n` 사이의 `\r`에 막힌다.
            $secM = [regex]::Match($skillTxt, ('(?ms)\*\*' + [regex]::Escape($sec.head) + '[^\r\n]*[\r\n]+((?:- "[^"]+"[\r\n]+)+)'))
            if ($secM.Success) {
                $phraseList = @([regex]::Matches($secM.Groups[1].Value, '- "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
            }
        } catch {}
        if ($phraseList.Count -eq 0) {
            $script:results.Add(@{ ok = $false; line = "[FAIL] evidence: SKILL.md 금지 표현 $($sec.label) 문구 추출 실패 (T3 문서<->코드 대조 - 목록 구조가 바뀌었는지 확인)" })
            continue
        }
        $phIdx = 0
        foreach ($ph in $phraseList) {
            $phIdx++
            # 문서의 자리표시자(T\<N\>)를 실제 번호로 바꿔 프로브 문장을 만든다.
            $probe = ($ph -replace '\\<N\\>', '5') -replace '<N>', '5'
            # 세션 id는 절·문구마다 고유해야 한다 — 차단 3회 상한 카운터가 세션·cwd 해시 단위라
            #   재사용하면 4번째 케이스부터 상한에 걸려 거짓 FAIL이 난다(위 key 주석 참조).
            $sid = 'lpP' + $sec.key + $phIdx
            $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = $sid; transcript_path = $loopTr; last_assistant_message = $probe } | ConvertTo-Json -Compress)
            Assert-Case -Name "evidence: SKILL.md $($sec.label) 문구 $phIdx/$($phraseList.Count) '$probe' → 차단 (T3 문서<->코드 동일성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
        }
    }

    # (L13) [v1.148.0 T8 / F-7 M2] transcript가 tail 상한(3000줄)을 넘어도 발동 흔적을 찾는가.
    #   흔적을 **맨 앞**에 두고 뒤를 3000줄 이상으로 채운다 — 조건 ③이 tail만 보면 흔적이 밖으로
    #   밀려 거짓이 되는데, **하필 그 긴 루프가 이 검사가 필요한 바로 그 상황**이다
    #   (실측: 이 repo transcript 최대 2817줄 = 상한의 94%).
    $loopTrBig = Join-Path $work 'tr-loop-big.jsonl'
    $bigLines = New-Object System.Collections.Generic.List[string]
    [void]$bigLines.Add('{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}')
    for ($bi = 0; $bi -lt 3200; $bi++) { [void]$bigLines.Add('{"type":"assistant","message":{"content":[{"type":"text","text":"filler"}]}}') }
    [void]$bigLines.Add('{"type":"user","message":{"content":"진행"}}')
    $bigLines | Set-Content -Encoding UTF8 $loopTrBig
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lpBig'; transcript_path = $loopTrBig; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: transcript 3000줄 초과 + 발동 흔적이 앞부분 → 차단 (T8 M2 회귀)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L14) [v1.148.0 T8 / F-7 m1] 차단 시 이벤트 로그에 block으로 적재되는가.
    #   오차단이 최악인 검사라 **사후 검토 수단**이 살아 있어야 한다(protect-harness와 같은 관례).
    #   stdout만 단언하면 적재 누락이 조용히 통과한다.
    $evLogFile = Join-Path $iso ('.claude/.state/hook-events/' + (Get-Date).ToString('yyyy-MM') + '.jsonl')
    $blkBefore = 0
    if (Test-Path -LiteralPath $evLogFile) { $blkBefore = @(Select-String -LiteralPath $evLogFile -Pattern '"decision":"block"' -SimpleMatch).Count }
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lpEv'; transcript_path = $loopTr; last_assistant_message = $loopMsg } | ConvertTo-Json -Compress)
    $blkAfter = 0
    if (Test-Path -LiteralPath $evLogFile) { $blkAfter = @(Select-String -LiteralPath $evLogFile -Pattern '"decision":"block"' -SimpleMatch).Count }
    if ($blkAfter -gt $blkBefore) {
        $script:results.Add(@{ ok = $true; line = "[PASS] evidence: 차단 시 이벤트 로그에 block 적재 (T8 m1)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] evidence: 차단 시 이벤트 로그에 block 적재 안 됨 (T8 m1) — before=$blkBefore after=$blkAfter, 로그=$evLogFile" })
    }

    # ---- [v1.149.0 T3] ③④ 확대 골든 (L15~L22) ----
    # 실제 사고 원문과 그 형제 유형을 고정하고, 오차단 표면을 음성으로 두텁게 덮는다.
    $script:sess = 0
    function New-LoopCase {
        # 케이스마다 고유 세션 id를 발급한다(차단 3회 상한 카운터가 세션·cwd 해시 단위).
        param([string]$Msg, [string]$Cwd = $ev4, [string]$Tr = $loopTr)
        $script:sess++
        return (@{ cwd = $Cwd; session_id = ('lp149_' + $script:sess); transcript_path = $Tr; last_assistant_message = $Msg } | ConvertTo-Json -Compress)
    }

    # (L15) 양성 ③ — **실제 관측된 사고 문장**. 이 확대의 존재 이유이므로 원문 그대로 고정한다.
    $realIncident = '한 가지 알려드릴 것: 이 세션이 상당히 길어져 남은 8개 task를 이 컨텍스트에서 끝까지 끌고 가면 후반 품질이 떨어질 수 있습니다. 이대로 계속할지, 새 세션으로 옮길지 알려주세요.'
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase $realIncident)
    Assert-Case -Name "evidence: ③ 관측 사고 원문(세션 전환 제안) → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L16) 양성 ③ 폴백 — 같은 문장을 stdin 필드 없이 transcript 마지막 assistant 텍스트로만 준다.
    #   last_assistant_message의 실환경 제공 여부가 미실증이라 **폴백이 프로덕션 주 경로일 수 있다** —
    #   stdin 경로만 검증하면 ③④가 실환경에서 영구 무발화한 채 골든만 green이 된다(L10과 같은 취지).
    $loopTrHandoff = Join-Path $work 'tr-loop-handoff.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"진행"}}',
        (New-TranscriptLine -Type assistant -Text $realIncident)
    ) | Set-Content -Encoding UTF8 $loopTrHandoff
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp149fb'; transcript_path = $loopTrHandoff } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: ③ stdin 필드 부재 + transcript 폴백 → 차단 (T3 양성·폴백)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L17) 양성 ③ — /clear 제안.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '/clear 후 새로 시작하시면 같은 지점에서 이어집니다.')
    Assert-Case -Name "evidence: ③ /clear 제안 → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L18) 양성 ④ — 중간 수동 실행 요청(3요소 결합).
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '여기서 한번 직접 실행해 보시겠어요?')
    Assert-Case -Name "evidence: ④ 중간 수동 실행 요청 → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L19) 양성 혼합 — ②어휘 + ③어휘 + 물음표. **조기 반환 금지의 회귀 고정**:
    #   ②가 Weak(물음표)로 통과 판정된 뒤 ③ 검사에 닿지 못하면 이 문장이 그대로 새어 나간다.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '컨텍스트가 찼습니다. 새 세션으로 옮길까요? 이어서 진행하겠습니다.')
    Assert-Case -Name "evidence: ②어휘+③어휘+물음표 혼합 → 차단 (T3 양성·조기반환 금지)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L20~L22) **델타 짝** — 마커 유무만 다른 두 문면이 미차단/차단으로 갈리는지 확인한다.
    #   이것이 성립해야 "D7 Strong 마커가 정당 개입 지점의 경계를 만든다"가 실증된다.
    #   짝의 본문은 반드시 ③ 또는 ④ positive에 매치되는 것이어야 한다 — 애초에 안 걸리는 문면을
    #   음성으로 두면 마커와 무관하게 통과하므로 아무것도 증명하지 못한다.
    foreach ($pair in @(
            @{ name = 'Phase 0 사전 승인 확인'; marker = '## ⏸️ 사전 승인 확인'; body = '사전 승인 항목을 한번 직접 확인해 주시겠어요?' },
            @{ name = '규칙 12 외부 작업 승인'; marker = '## ⏸️ 외부 작업 승인 요청'; body = '새 세션에서 릴리즈를 진행할지 알려주세요.' },
            @{ name = 'plan-feature 세션 확인'; marker = '## ⏸️ 세션 확인'; body = '컨텍스트가 많이 찼습니다. 새 세션으로 옮길까요, 이대로 계속할지 알려주세요.' })) {
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase ($pair.marker + "`n" + $pair.body))
        Assert-Case -Name "evidence: $($pair.name) — Strong 마커 있음 → 미차단 (T3 음성·델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase $pair.body)
        Assert-Case -Name "evidence: $($pair.name) — 마커 제거 시 → 차단 (T3 양성·델타 짝)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    }

    # (L23) 음성 — ③ 문구에 Halt 마커(⛔)가 동반되면 통과(Strong 존중).
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase "## ⛔ 작업 중단: T2`n새 세션으로 옮길지 알려주세요")
    Assert-Case -Name "evidence: ③ + Halt 마커 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L24) 음성 — 미완료 task 0이면 ③ 문구여도 통과(조건 ① 불성립).
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '새 세션으로 옮길지 알려주세요' $ev6)
    Assert-Case -Name "evidence: ③ + 미완료 task 0 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L25) 음성 — **사용자가 먼저** 세션 전환을 꺼낸 대화에서는 억제한다(D3-ⓑ).
    #   이 검사에서 가장 위험한 오작동인 "사용자 의사 무시"를 ③에서도 막는 조건이다.
    $loopTrUserSess = Join-Path $work 'tr-loop-usersess.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"새 세션으로 옮기자"}}'
    ) | Set-Content -Encoding UTF8 $loopTrUserSess
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '알겠습니다. 새 세션에서 이어가시면 같은 지점에서 재개됩니다.' $ev4 $loopTrUserSess)
    Assert-Case -Name "evidence: 사용자가 먼저 세션 전환 제안 → 미차단 (T3 음성·D3-ⓑ)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L26) 음성 — ④ 어휘가 있으나 3요소 미충족(위임 부사 없음)인 정상 안내. 오차단 반례 회귀 고정.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '설치 후 동작을 확인해 주세요.')
    Assert-Case -Name "evidence: ④ 3요소 미충족 정상 보고 → 미차단 (T3 음성·오차단 반례)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L27) 음성 — 규칙 4를 수행하는 정상 보고. ③ ⓐ에서 상태 서술 명사를 뺀 이유의 회귀 고정.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '컨텍스트 관리 규칙에 따라 plan.md를 갱신했습니다. 이제 다음 작업자가 이어가시면 됩니다.')
    Assert-Case -Name "evidence: 규칙 4 수행 보고 → 미차단 (T3 음성·오차단 반례)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L28) 음성 — **Strong 마커가 ④도 억제하는가**. 위 델타 3짝은 Phase 0·규칙 12·plan-feature를
    #   다루므로 F-8 확인 게이트가 빠져 있었다. ③뿐 아니라 ④ 어휘에도 마커가 통하는지 고정한다.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase "## ⏸️ 구현 완료 — 확인 대기`n화면 표시는 여기서 한번 직접 확인해 보시겠어요?")
    Assert-Case -Name "evidence: F-8 확인 게이트 마커 + ④ 어휘 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L29) 음성 — **루프 종료 후의 일반 대화**. 6조건은 "지금 루프가 도는가"가 아니라 세션에
    #   발동 흔적이 있는지만 보므로(전 파일 스캔), 루프가 Halt·중단으로 끝난 뒤의 평범한 답변도
    #   미완료 task가 남아 있으면 판정 대상이 된다. ④를 3요소로 좁힌 이유가 이 표면을 ② 수준의
    #   희소성까지 줄이는 것이었고, 이 케이스가 그 잔여를 고정한다.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '그 설정은 config.toml에서 바꿉니다. 여기서 직접 수정하시면 반영됩니다.')
    Assert-Case -Name "evidence: 루프 종료 후 일반 대화 → 미차단 (T3 음성·④ 잔여 표면)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L30) [F-7 M1] 음성 — **VS16(U+FE0F) 없는 `⏸`** 마커도 Strong으로 인정되는가.
    #   파일에 `⏸️`로 쓰면 U+23F8+U+FE0F 2문자라, 모델이 VS16 없이 출력하면 미매치가 된다.
    #   Weak를 ③④⑤에서 없앤 뒤로는 마커가 유일한 방어이므로 한 코드포인트 차이가 곧 오차단이다.
    #   프로브 문면은 ③ positive에 실제로 매치되는 것이어야 마커의 효과를 검증할 수 있다.
    #   [char]0x23F8로 조립한다 — 소스에 리터럴로 쓰면 편집 과정에서 VS16이 다시 붙어 검사가 무의미해진다.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase ('## ' + ([char]0x23F8) + " 사전 승인 확인`n새 세션에서 이어가시면 같은 지점부터 재개됩니다."))
    Assert-Case -Name "evidence: VS16 없는 U+23F8 마커 + ③ 문면 → 미차단 (F-7 M1 회귀)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L31) [F-7 M2] 음성 — **사용자가 지연·종료를 지시한 뒤**의 정상 안내는 차단하지 않는다.
    #   ③ 확대가 만든 신규 오차단 표면이다(v1.148.0에는 이 문장이 $rxAdvance에 안 걸렸다).
    #   차단 reason이 "사용자 보고 없이 계속하라"라서, 사용자가 멈춘 작업을 재개하도록 밀어붙이는
    #   최악의 오작동이 된다 — userStop 어휘에 지연 표현을 넣어 막는다.
    $loopTrTomorrow = Join-Path $work 'tr-loop-tomorrow.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"오늘은 여기까지, 내일 하자"}}'
    ) | Set-Content -Encoding UTF8 $loopTrTomorrow
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase '알겠습니다. 남은 T4~T6은 새 세션에서 이어가시면 같은 지점부터 재개됩니다.' $ev4 $loopTrTomorrow)
    Assert-Case -Name "evidence: 사용자 지연 지시 후 ③ 문면 → 미차단 (F-7 M2 회귀)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # ---- [v1.150.0 T3] ⑤ 순수 진행 요약 골든 (L32~L44) ----
    # ⑤는 ②③④와 결정적으로 다르다 — **정상 진행 보고와 문면이 같다**. 차이는 "그 뒤에 도구
    #   호출이 있었나"뿐이고 Stop hook 시점엔 그 부재가 확정이라 문면만으로 판정하지만,
    #   그만큼 오차단 표면이 넓어 음성·억제 케이스를 두텁게 깐다.

    # (L32) 양성 5건 — 사용자가 "중간 보고를 하면 무조건 루프가 멈춘다"고 보고한 실제 형태들.
    #   관측·설계 근거이므로 문면을 바꾸지 않는다.
    foreach ($pos in @(
            @{ n = '순수 진행 요약'; m = 'T3 완료. 변경 파일 3개, 빌드 통과. 리뷰 지적 2건 수정했습니다.' },
            @{ n = '1줄 마커형'; m = 'T1 완료 (1/10) 다음은 T2 시작' },
            @{ n = '구현 완료 서술형'; m = 'T2 구현을 마쳤습니다. 빌드와 테스트 모두 통과했습니다.' },
            @{ n = '범위 요약형'; m = '현재까지 T1~T3을 마쳤고 남은 작업은 T4~T6입니다.' },
            @{ n = '화살표형'; m = 'T2 완료 -> T3 시작' })) {
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase $pos.m)
        Assert-Case -Name "evidence: ⑤ $($pos.n) → 차단 (T3 양성)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    }

    # (L33) 양성 — ①(질문형 확인 요청) 접두형의 **부수 차단**을 명시적으로 고정한다.
    #   ②는 Weak(물음표)로 통과시키던 문면이지만 ⑤는 Weak를 안 보므로 잡힌다. 우연이 아니라
    #   설계된 확장이며, plan Out of Scope가 "①의 전용 차단은 안 하되 이 접두형은 ⑤로 잡힌다"로
    #   경계를 적어 둔 것의 실증이다. 이 케이스가 red면 Weak 정책이 ⑤로 새어 들어온 것이다.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 계속할까요?')
    Assert-Case -Name "evidence: ⑤ ① 접두형 부수 차단 → 차단 (T3 양성·경계)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L34) 양성 폴백 — stdin 필드 없이 transcript 마지막 assistant 텍스트로만 판정하는 경로.
    #   last_assistant_message의 실환경 제공 여부가 미실증이라 **폴백이 프로덕션 주 경로일 수 있다**
    #   (L16과 같은 취지 — stdin 경로만 검증하면 ⑤가 실환경에서 영구 무발화한 채 골든만 green).
    $loopTrProg = Join-Path $work 'tr-loop-progress.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"진행"}}',
        '{"type":"assistant","message":{"content":[{"type":"text","text":"T3 완료. 변경 파일 3개, 빌드 통과."}]}}'
    ) | Set-Content -Encoding UTF8 $loopTrProg
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp150fb'; transcript_path = $loopTrProg } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: ⑤ stdin 필드 부재 + transcript 폴백 → 차단 (T3 양성·폴백)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L35) 음성 5건 — **(?-i)\b 경계 회귀**. 이 다섯은 경계를 넣기 전 정규식에서 실제로 차단됐던
    #   문면이다(plan 1회차 BLOCKER, 실측 재현). `-match`가 기본 case-insensitive라
    #   `part1`·`test2`·`GPT5`·`checkpoint1`이 전부 T<N>으로 인정됐고, 문장부호 배제가 없으면
    #   마침표 너머의 완료 어휘까지 끌어왔다. 경계를 되돌리면 여기서 즉시 red가 된다.
    foreach ($neg in @(
            @{ n = 'part1'; m = 'part1 작업을 마쳤습니다' },
            @{ n = 'test2'; m = 'test2 케이스를 마무리했습니다' },
            @{ n = 'GPT5'; m = 'GPT5 비교 조사를 마쳤습니다' },
            @{ n = 'checkpoint1'; m = 'checkpoint1 단계를 끝냈습니다' },
            @{ n = '문장 경계 넘김'; m = 'T3 관련 조사는 진행 중입니다. 다른 건 다 끝났습니다.' })) {
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase $neg.m)
        Assert-Case -Name "evidence: ⑤ 경계 회귀 $($neg.n) → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
    }

    # (L36) 음성 5건 — 정규식 게이트가 애초에 닿지 않는 문면(T토큰만 있거나 완료 어휘만 있는 경우).
    #   위 L35(경계 회귀)와 목적이 다르다: 이쪽은 "⑤가 정상 대화를 잡지 않는다"를 센다.
    foreach ($neg in @(
            @{ n = '호출부 설명'; m = '이 함수의 호출부는 3곳이며 모두 Domain 레이어에 있습니다.' },
            @{ n = 'config 안내'; m = '그 설정은 config.toml에서 바꿉니다.' },
            @{ n = 'acceptance 서술'; m = 'T3의 acceptance는 빌드 통과이고 Files는 3개입니다.' },
            @{ n = 'plan 추가'; m = 'plan.md에 T4와 T5를 추가했습니다.' },
            @{ n = '조사 완료'; m = '요청하신 조사를 마쳤습니다.' })) {
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase $neg.m)
        Assert-Case -Name "evidence: ⑤ 정상 대화 $($neg.n) → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
    }

    # (L37) 델타 짝 — Strong 마커가 ⑤에도 통하는가. 본문은 ⑤ positive에 실제로 매치되는 것이어야
    #   마커의 효과가 검증된다(애초에 안 걸리는 문면은 아무것도 증명하지 못한다 — L20~L22의 교훈).
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase "## ⛔ 작업 중단: T3`nT3 완료. 파괴적 작업이 필요해 승인을 기다립니다.")
    Assert-Case -Name "evidence: ⑤ + Halt 마커 → 미차단 (T3 음성·델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 파괴적 작업이 필요해 승인을 기다립니다.')
    Assert-Case -Name "evidence: ⑤ 마커 제거 시 → 차단 (T3 양성·델타 짝)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L38) 델타 짝 — 질문 답변 억제($userAsking). 사용자가 방금 물어봤으면 그 답이 "T<N> … 완료"
    #   형태여도 정지가 아니라 대화다. 짝의 다른 쪽(지시 `진행`)은 차단이어야 억제가 탐지력을
    #   죽이지 않았음이 실증된다.
    $loopTrAsk = Join-Path $work 'tr-loop-ask.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"T3 어디까지 됐어?"}}'
    ) | Set-Content -Encoding UTF8 $loopTrAsk
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $loopTrAsk)
    Assert-Case -Name "evidence: ⑤ 사용자 질문 뒤 답변 → 미차단 (T3 음성·억제 델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.')
    Assert-Case -Name "evidence: ⑤ 지시 뒤 같은 문면 → 차단 (T3 양성·억제 델타 짝)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L39) 양성 2건 — **활성 게이트($loopActiveAfterUser) 회귀. 이 블록에서 가장 중요하다.**
    #   자율 루프 중에는 tool_result가 user에서 제외되므로 "마지막 user 텍스트"가 루프 시작
    #   지시로 고정된다. 그 지시에 질문 어휘가 섞여 있으면($rxUserAsk 매치) 게이트가 없을 때
    #   억제가 **루프 전 구간 상수 참**이 되어 ⑤가 한 번도 발동하지 못한다 — 골든이 green인 채로
    #   프로덕션에서만 무발화하는 형태다. 게이트만 제거해도 이 두 케이스는 즉시 red가 된다.
    #   픽스처 순서가 핵심: 발동 엔트리가 **마지막 user 뒤**에 와야 게이트가 켜진다.
    foreach ($gate in @(
            @{ n = '왜 멈췄어 계속해'; u = '왜 멈췄어 계속해' },
            @{ n = 'T6부터 어떻게 이어갈지'; u = 'T6부터 어떻게 이어갈지 알아서 진행' })) {
        $trGate = Join-Path $work ('tr-loop-gate-' + $gate.u.Length + '.jsonl')
        @(
            (New-TranscriptLine -Type user -Text $gate.u),
            '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}'
        ) | Set-Content -Encoding UTF8 $trGate
        $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trGate)
        Assert-Case -Name "evidence: ⑤ 질문 어휘 재개 지시 + 루프 활성($($gate.n)) → 차단 (T3 양성·게이트 회귀)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
    }

    # (L40) 음성 — 게이트 판정이 **assistant 엔트리에 한정**되는가. 이 레포 개발 세션에서는
    #   골든 파일을 읽은 tool_result가 발동 패턴 리터럴을 그대로 담는데, 그것으로 게이트가 켜지면
    #   억제가 꺼져 질문 답변이 차단된다(오차단 방향). tool_result는 user 타입이라 $isAsst 한정에
    #   걸러져야 한다 — 한정을 빼면 이 케이스가 차단으로 red가 된다(**mutation 테스트로 실증**:
    #   $isAsst 조건만 제거한 사본에서 미차단→차단으로 뒤집히는 것을 확인했다).
    #   content는 **게이트 정규식에 실제로 매치되는 리터럴**이어야 한다 — 사람이 읽는 설명문
    #   ("skill: pjc:implement-task 리터럴이 든 내용")으로 바꾸면 어느 패턴에도 안 닿아
    #   한정을 제거해도 green인 always-pass 케이스가 된다(초안이 실제로 그랬고 리뷰가 잡았다).
    #   JSON 내부라 따옴표형(`"skill":"..."`)은 이스케이프로 깨지므로 `Launching skill:` 형태를 쓴다.
    $loopTrTR = Join-Path $work 'tr-loop-toolresult.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"T3 어디까지 됐어?"}}',
        '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"Launching skill: pjc:implement-task"}]}}'
    ) | Set-Content -Encoding UTF8 $loopTrTR
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $loopTrTR)
    Assert-Case -Name "evidence: ⑤ tool_result 발동 리터럴은 게이트 미점화 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L41) 양성 — **수용된 잔여 표면**(plan Risks ⓐ). 사용자가 질문형이 아닌 명령형으로 상태를
    #   요구하면($rxUserAsk 미매치) 그 답변이 차단된다. 억제 패턴을 넓히면 자율 루프 지시
    #   ("진행해줘")와 표면이 겹치기 시작해 의도적으로 수용한 것이며, 나중에 이 형태의 오차단이
    #   보고되면 이 케이스가 판단 근거가 된다(그때 red로 바꿔 좁힌다).
    $loopTrOrder = Join-Path $work 'tr-loop-order.jsonl'
    @(
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}',
        '{"type":"user","message":{"content":"현재 상태 정리해봐"}}'
    ) | Set-Content -Encoding UTF8 $loopTrOrder
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $loopTrOrder)
    Assert-Case -Name "evidence: ⑤ 명령형 상태 요구 뒤 답변 → 차단 (T3 양성·수용된 잔여 표면)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L42) 음성 — 미완료 task 0이면 ⑤ 문면이어도 통과(조건 ① 불성립). L24의 ⑤ 버전.
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev6)
    Assert-Case -Name "evidence: ⑤ + 미완료 task 0 → 미차단 (T3 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # ---- [v1.151.0 T2] 사용자 발화 추출 오염 차단 (skip 4종) ----
    # 검사 4 조건 5가 읽는 '마지막 사용자 발화'에서 시스템 주입 텍스트를 걸러내는가.
    # **픽스처 규약 2가지 — 어기면 케이스가 조용히 무의미해진다**:
    #   ⓐ 줄 순서: 스캔이 역순이라 **오염 엔트리가 진짜 발화보다 아래(=더 최근)** 에 와야 재현된다.
    #   ⓑ 발동 흔적: 모든 픽스처에 `"skill":"pjc:implement-task"` 리터럴이 있어야 한다. 없으면
    #      조건 2($loopSkill)가 거짓이라 **무엇을 넣어도 미차단**이 되어, 음성은 always-pass로
    #      전락하고 양성의 red도 사라진다(L40 주석이 기록한 것과 같은 함정).
    # **진짜 델타는 G1·G2·G6·G7 넷**이고 G3·G4·G5는 무회귀 고정이다(델타로 세지 않는다).
    # red 실증은 skip별로 나뉜다 — ①(isMeta) 제거 → G1·G6 FAIL / ②(알림) 제거 → G2 FAIL /
    #   ③④(assistant 파싱) 제거 → G7 FAIL.
    $metaPayload = '{"type":"user","isMeta":true,"message":{"content":"Base directory for this skill. Halt Condition 중단 조건과 새 세션 권유 규칙을 담은 스킬 본문이다."}}'
    $skillEntry  = '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pjc:implement-task"}}]}}'
    # 알림 본문은 $rxUserAsk·$userStop 어휘를 피한 중립 문면이어야 한다 — 물음표나 '중단'이 섞이면
    #   skip 제거 시에도 억제가 걸려 G2의 red가 조용히 사라진다.
    $notifEntry  = '{"type":"user","message":{"content":"<task-notification><task-id>b1</task-id><summary>Agent finished</summary></task-notification>"}}'

    # (L43) 양성 G1 — 스킬 발동 페이로드가 마지막 user 텍스트 자리를 빼앗던 결함 본체.
    #   skip ①을 빼면 페이로드 본문의 '중단'·'새 세션'이 $userStop을 켜 미차단으로 red가 된다.
    $trG1 = Join-Path $work 'tr-g1-meta.jsonl'
    @('{"type":"user","message":{"content":"진행"}}', $skillEntry, $metaPayload) | Set-Content -Encoding UTF8 $trG1
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trG1)
    Assert-Case -Name "evidence: 스킬 페이로드(isMeta) 뒤 ⑤ → 차단 (T2 양성·델타)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L44) 음성 G2 — subagent 알림이 **사용자 중단 지시를 가리지 않는가**(D2의 핵심 이득).
    #   skip ②를 빼면 알림이 마지막 발화가 되어 $userStop이 꺼지고 차단으로 red가 된다 —
    #   그것이 곧 "사용자가 멈추라 한 작업에 재개를 강요하는" 최악 오작동이다.
    $trG2 = Join-Path $work 'tr-g2-notif.jsonl'
    @('{"type":"user","message":{"content":"오늘은 그만 하자"}}', $skillEntry, $notifEntry) | Set-Content -Encoding UTF8 $trG2
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trG2)
    Assert-Case -Name "evidence: 알림 뒤에도 사용자 중단 지시 유효 → 미차단 (T2 음성·델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L45) 음성 G3 — **skip ①의 델타 음성**(F-7 M1). 페이로드를 걷어낸 뒤 그 **앞**의 진짜 중단
    #   지시를 찾아내는가 = "제외가 사용자 의사를 삼키지 않는가". 이 축이 이번 변경에서 가장
    #   위험한 방향(오차단)인데 초안에는 델타가 없었다.
    #   ⚠ 페이로드 본문이 **중립이어야 델타가 성립한다** — `중단`이 들어 있으면 skip ① 제거 시에도
    #   그 어휘가 $userStop을 켜서 미차단이 유지되고(무회귀 전락), 초안이 실제로 그랬다.
    #   중립 문면이면 skip ① 제거 → 페이로드가 마지막 발화 → $userStop=false → **차단 = red**.
    $metaNeutral = '{"type":"user","isMeta":true,"message":{"content":"Base directory for this skill. 스킬 문서 본문이 여기에 이어진다."}}'
    $trG3 = Join-Path $work 'tr-g3-meta-stop.jsonl'
    @('{"type":"user","message":{"content":"오늘은 그만 하자"}}', $skillEntry, $metaNeutral) | Set-Content -Encoding UTF8 $trG3
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trG3)
    Assert-Case -Name "evidence: 페이로드 뒤에도 사용자 중단 지시 유효 → 미차단 (T2 음성·델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L46) 음성 G4 — 슬래시 커맨드 원문은 isMeta=false라 **사용자 의사로 보존**된다.
    #   앞에 중립 발화(`진행`)를 한 줄 두는 이유(F-7 M1): 커맨드 원문이 제외 대상에 잘못 추가되는
    #   회귀가 나면 그 앞의 `진행`이 잡혀 **차단으로 red**가 된다. 앞줄이 없으면 삼켜져도
    #   $userFound=false로 fail-open 미차단이라 **PASS가 나서 회귀를 못 잡는다**.
    $trG4 = Join-Path $work 'tr-g4-slash.jsonl'
    @('{"type":"user","message":{"content":"진행"}}', '{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}', $skillEntry) | Set-Content -Encoding UTF8 $trG4
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trG4)
    Assert-Case -Name "evidence: 슬래시 커맨드 원문은 사용자 의사로 인정 → 미차단 (T2 음성·델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L47) 음성 G5 — 제외 후 진짜 사용자 발화가 하나도 없으면 $userFound=false로 fail-open이다.
    #   제외가 이 hook의 fail-open 원칙을 깨지 않음을 고정한다(무회귀).
    $trG5 = Join-Path $work 'tr-g5-metaonly.jsonl'
    @($skillEntry, $metaPayload) | Set-Content -Encoding UTF8 $trG5
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trG5)
    Assert-Case -Name "evidence: 페이로드만 있고 진짜 발화 0 → fail-open 미차단 (T2 음성·무회귀)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L48) 양성 G6 — **활성 게이트 정상화**(plan Risks ②). 페이로드가 $userFound를 즉시 켜면
    #   게이트 판정 창이 0이 되어, 루프가 도는 중에도 게이트가 꺼진 채 $userAsking 억제가 걸린다.
    #   skip ①로 창이 넓어져야 발동 엔트리를 보고 게이트가 켜진다.
    #   ⚠ 이 케이스의 red(skip ① 제거)는 $userStop과 게이트가 **동시에** 뒤집히는 compound다 —
    #   게이트 효과의 분리 실증이 아니라 **green 상태에서 게이트를 pin하는 것**이 이 케이스의 값이다
    #   (게이트 자체를 제거하면 억제가 걸려 미차단으로 red가 된다 — 그 축은 L39가 담당).
    $trG6 = Join-Path $work 'tr-g6-gate.jsonl'
    @('{"type":"user","message":{"content":"T3 어디까지 됐어?"}}', $skillEntry, $metaPayload) | Set-Content -Encoding UTF8 $trG6
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trG6)
    Assert-Case -Name "evidence: 질문 발화 + 페이로드 + 루프 활성 → 차단 (T2 양성·게이트 정상화)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L49) 양성 G7 — **파싱 예산 방어**. 텍스트 없는 assistant가 상한(200)을 태우면 $userFound를
    #   잃어 조용한 fail-open이 된다(실측 104개 시점). skip ③④가 그 낭비를 걷어낸다.
    #   250줄인 이유: 상한 200을 확실히 넘겨야 skip 제거 시 red가 뜬다. 엔트리는 반드시
    #   **텍스트 없는 형태**(tool_use만)여야 한다 — "type":"text"가 섞이면 skip ④가 적용되지 않아
    #   이 케이스가 검증하려는 축이 사라진다.
    #   ⚠ 픽스처에 isMeta 페이로드를 **넣지 않는다** — 넣으면 이 케이스가 skip ①에도 의존해
    #   R1(isMeta 제거) 회차에서도 FAIL하고, 그러면 "무엇이 이 케이스를 red로 만드는가"가 흐려진다
    #   (초안이 그랬고 red 실증 R1에서 드러났다). 케이스 하나는 축 하나만 검증한다.
    $trG7 = Join-Path $work 'tr-g7-budget.jsonl'
    $g7 = New-Object System.Collections.Generic.List[string]
    $g7.Add('{"type":"user","message":{"content":"진행"}}')
    1..250 | ForEach-Object { $g7.Add($skillEntry) }
    $g7 | Set-Content -Encoding UTF8 $trG7
    $r = Invoke-Hook 'require-evidence.ps1' (New-LoopCase 'T3 완료. 빌드 통과.' $ev4 $trG7)
    Assert-Case -Name "evidence: 텍스트 없는 assistant 250줄 너머의 사용자 발화 도달 → 차단 (T2 양성·예산)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L50) 양성 G8 — **skip ④ 단독 red**. 위 G7은 New-LoopCase가 last_assistant_message를 넣어
    #   $needAsst가 거짓으로 시작하므로, 250줄이 skip ③(`$isAsst -and -not $needAsst`)에도 걸린다 —
    #   즉 **skip ④만 지워도 red가 뜨지 않는** 무회귀 케이스이고 그 줄의 방어는 주석뿐이었다.
    #   폴백 경로(stdin 필드 미제공 → $needAsst=true)에서는 skip ③이 원리적으로 발동하지 않아
    #   250줄을 걸러내는 것이 오직 skip ④이고, 그때 비로소 그 줄이 단독으로 red가 된다.
    #   ⚠ 줄 순서가 이 케이스의 전부다 — 텍스트 없는 250줄이 **가장 최근**이어야 역순 스캔이
    #   $needAsst가 켜져 있는 구간에서 그것을 만난다. assistant 텍스트를 250줄보다 뒤(더 최근)에
    #   두면 첫 엔트리에서 $needAsst가 꺼져 250줄이 skip ③으로 넘어가고 skip ④는 아무 일도 하지
    #   않는다(G7이 그렇게 무회귀로 전락했다). 대장 원문의 "그 너머" = 더 오래된 쪽이다.
    #   red(skip ④ 제거): 250줄이 $parsed를 200 상한까지 태워 break → assistant 텍스트·사용자
    #   발화에 도달 못 함 → $stopKind=''·$userFound=false → **미차단 = FAIL**.
    #   축 분리(skip ③ 제거): 250줄 구간은 $needAsst가 참이라 원래 skip ③이 발동하지 않으므로
    #   판정 불변 → **PASS**. 이 비대칭이 곧 "이 케이스는 skip ④ 전용"의 실증이다.
    $trG8 = Join-Path $work 'tr-g8-fallback-budget.jsonl'
    $g8 = New-Object System.Collections.Generic.List[string]
    $g8.Add('{"type":"user","message":{"content":"진행"}}')
    $g8.Add('{"type":"assistant","message":{"content":[{"type":"text","text":"T3 완료. 빌드 통과."}]}}')
    1..250 | ForEach-Object { $g8.Add($skillEntry) }
    $g8 | Set-Content -Encoding UTF8 $trG8
    # New-LoopCase를 쓰지 않는다 — 그 헬퍼는 last_assistant_message를 항상 넣어 폴백 경로 자체가
    #   성립하지 않는다(기존 폴백 케이스 L10·L16·L34와 같은 이유로 stdin JSON을 직접 구성한다).
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp151g8'; transcript_path = $trG8 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 폴백 경로 + 텍스트 없는 assistant 250줄 → 차단 (T2 양성·skip④ 단독 red)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # ---- [v1.154.0 T2] 루프 활성 화이트리스트 (조건 3의 문면 무관 판정) ----
    # 검사 4의 조건 3이 "정지 문구 4유형 매치"에서 "**루프 활성이면 문면 무관하게 참**"으로 바뀌었다.
    # **이 블록의 픽스처가 기존 것과 다른 단 하나의 지점은 줄 순서다** — 아래 $loopTrActive는
    #   `user → skill` 순서이고 위쪽 표준 픽스처 $loopTr은 `skill → user` 순서인데, 그 차이가
    #   활성/폴백 두 경로를 가르는 **유일한 장치**다:
    #     역순 스캔은 user를 만나면 $userFound를 켜고 (stdin 필드가 있으면) 즉시 break하므로,
    #     $loopTr처럼 skill이 user보다 **위(더 오래된 쪽)** 에 있으면 게이트 조건
    #     (`$isAsst -and -not $userFound`)에 영원히 닿지 못해 $loopActiveAfterUser가 거짓이 된다.
    #     실제 자율 루프 transcript는 반대 순서다("진행" 발화 → 스킬 발동 → 수백 turn).
    #   ⚠ **두 픽스처를 "같은 것"으로 보고 통합하지 말 것** — 통합하는 순간 기존 음성 케이스들이
    #     폴백 경로를 실증하지 못하게 되고(전부 활성 경로로 쏠린다), 무회귀의 근거가 사라진다.
    # red 실증 축은 셋이다 — 화이트리스트 분기 제거 → L51·L53 FAIL / 진입 조건을 종전으로 되돌림
    #   → L51·L53 FAIL(스캔 미진입으로 게이트가 영영 거짓) / 게이트의 tool_use 조건 제거 → L60 FAIL.
    $loopTrActive = Join-Path $work 'tr-loop-active.jsonl'
    @('{"type":"user","message":{"content":"진행"}}', $skillEntry) | Set-Content -Encoding UTF8 $loopTrActive

    # (L51) 양성 — **이 전환의 존재 이유인 실제 관측 사고 문장**. 4정규식 **전부를 빗나간다**
    #   (`여기까지`≠`여기서` · `T\d+ (부터|까지)` 아님 · ⓐ에 컨텍스트 명사 없음 · 완료 어휘 부재).
    #   즉 이 케이스가 PASS하는 이유는 오직 화이트리스트뿐이라 축이 단독으로 분리된다.
    $incident154 = 'T9~T13을 진행했습니다. 컨텍스트가 상당히 차서 여기서 상황을 정리해 보고합니다.'
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154a'; transcript_path = $loopTrActive; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 활성 + 관측 사고 원문(4정규식 전부 미매치) → 차단 (T4 양성·화이트리스트)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L52) 양성 — **활성이어도 4정규식이 먼저 특정한 유형은 유지된다**(`-and -not $stopKind` 분기).
    #   L51·L53과 축이 다르다: 저쪽은 "문면이 안 걸려도 잡는가", 이쪽은 "걸리면 그 유형을 쓰는가"다.
    #   reason 문면으로 구분한다 — ⑤로 판정되면 '금지 표현 5'가, 화이트리스트면 그 문구가 없다.
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154b'; transcript_path = $loopTrActive; last_assistant_message = 'T3 완료. 빌드 통과.' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 활성 + ⑤ 문면 → 차단하되 ⑤ 유형 유지 (T4 양성·유형 보존)" -R $r -ExpectExit 0 -ExpectContains '금지 표현 5'

    # (L53) 양성 — 정지 의도가 어휘에 전혀 없는 평서문. 종전이라면 통과했을 문면이다.
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154c'; transcript_path = $loopTrActive; last_assistant_message = '조사 결과를 정리했습니다.' } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 활성 + 임의 평서문 → 차단 (T4 양성·문면 무관)" -R $r -ExpectExit 0 -ExpectContains $loopBlock

    # (L54~L56) 음성 델타 — **Strong 마커가 화이트리스트 경로에서도 유일한 통과 근거인가.**
    #   문면은 L51과 동일하고 마커 유무만 다르다(마커가 없으면 L51처럼 차단되므로 델타가 성립).
    foreach ($mk in @(
            @{ n = 'Halt 보고'; s = 'lp154d'; m = "## ⛔ 작업 중단: T2`n$incident154" },
            @{ n = '최종 보고'; s = 'lp154e'; m = "🎉 구현 완료`n$incident154" },
            @{ n = 'Phase 0 사전 승인'; s = 'lp154f'; m = "## ⏸️ 사전 승인 확인`n$incident154" })) {
        $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = $mk.s; transcript_path = $loopTrActive; last_assistant_message = $mk.m } | ConvertTo-Json -Compress)
        Assert-Case -Name "evidence: 루프 활성 + $($mk.n) 마커 → 미차단 (T4 음성·델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock
    }

    # (L57) 음성 — 사용자가 중단을 지시했으면 활성이어도 차단하지 않는다(조건 5 — 최우선 안전 조건).
    #   차단 reason이 "계속하라"이므로, 이 방향의 오차단은 **사용자가 멈춘 작업에 재개를 강요**한다.
    $trActiveStop = Join-Path $work 'tr-active-stop.jsonl'
    @('{"type":"user","message":{"content":"오늘은 그만 하자"}}', $skillEntry) | Set-Content -Encoding UTF8 $trActiveStop
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154g'; transcript_path = $trActiveStop; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 활성 + 사용자 중단 지시 → 미차단 (T4 음성·최우선 안전 조건)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L58) 경계 음성 — **폴백 경로 무회귀의 직접 실증**. 같은 문장을 표준 픽스처($loopTr = skill→user)로
    #   주면 게이트가 꺼져 4정규식만 적용되고, L51의 문면은 그 넷 어디에도 안 걸리므로 통과해야 한다.
    #   L51과 이 케이스의 차이는 **픽스처 줄 순서 하나뿐**이라, 둘이 짝으로 경로 분기를 고정한다.
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154h'; transcript_path = $loopTr; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 비활성(폴백) + 같은 문장 → 미차단 (T4 음성·경로 분기 델타)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L59) 경계 음성 — 활성이어도 미완료 task가 0이면 조건 1이 불성립이라 통과한다.
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev6; session_id = 'lp154i'; transcript_path = $loopTrActive; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 루프 활성 + 미완료 task 0 → 미차단 (T4 음성)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L60) 경계 음성 — **게이트 오점화 방어(D6)**. assistant가 발동 리터럴을 *인용*만 한 텍스트
    #   엔트리는 게이트를 켜면 안 된다. 전환 전에는 이 오점화가 ⑤ 억제 해제(미탐 방향)로만 나타나
    #   수용 가능했지만, 이제 게이트가 곧 차단 신호라 **인용 한 번이 오차단**이 된다.
    #   이 레포는 그 리터럴을 산문으로 논하는 레포(hook 주석·이 파일·plan)라 실재하는 표면이다.
    #   ⚠ **커버 경계**: 이 케이스는 **순수 텍스트 엔트리만** 고정한다. 이 레포에서 훨씬 흔한
    #     "다른 도구의 input에 실린 리터럴"은 **아래 L61**이 담당한다(그쪽이 실제 주요 표면이다).
    #   red(게이트의 tool_use 조건 제거): 인용 엔트리가 게이트를 켜 활성으로 오판 → 차단 = FAIL.
    #   ⚠ **줄 순서가 이 케이스의 전부다** — 진짜 발동 엔트리는 사용자 발화보다 **위(더 오래된 쪽)**
    #     에 둔다. 조건 2($loopSkill)는 전 파일 스캔이라 그 위치에서도 참이지만, 게이트는
    #     `-not $userFound` 구간에서만 켜지므로 발동 엔트리가 user 아래(더 최근)에 있으면
    #     **tool_use 조건과 무관하게** 켜져 이 케이스가 always-fail이 된다.
    $trQuote = Join-Path $work 'tr-active-quote.jsonl'
    @($skillEntry,
      '{"type":"user","message":{"content":"진행"}}',
      '{"type":"assistant","message":{"content":[{"type":"text","text":"게이트는 Launching skill: pjc:implement-task 리터럴로 판정합니다"}]}}') |
        Set-Content -Encoding UTF8 $trQuote
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154j'; transcript_path = $trQuote; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 발동 리터럴 인용(tool_use 없음)은 게이트 미점화 → 미차단 (T4 음성·D6)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L61) 경계 음성 — **오점화의 주요 표면: 다른 도구의 input에 실린 발동 리터럴**(D8).
    #   위 L60은 순수 `"type":"text"` 인용만 고정하는데, **실제로 이 레포에서 압도적으로 흔한 형태는
    #   그게 아니라 이것**이다 — hook·골든·plan을 Edit/Write/Bash로 편집·검색할 때마다 발동 리터럴이
    #   도구 input에 실린다(전 세션 실측: 리터럴 보유 assistant 엔트리 중 **32건이 이 형태**
    #   — Edit 11 · Write 10 · Bash 8 · Agent 2 · PowerShell 1). **그 32건도 전부 `tool_use` 동반**이라
    #   D6의 "tool_use 동반 요구"로는 **하나도 걸러지지 않았다**(초안의 오판 — "83건 전건 tool_use
    #   동반"이라는 참인 관측을 "83건이 전부 발동"이라는 거짓 전제와 묶었다).
    #   해소는 D8이고 **방어가 두 겹이라 케이스도 둘로 나눈다** — 한 케이스로 뭉치면 어느 겹이
    #   실제로 막았는지 구분되지 않는다(대장 [SKILL-IMPROVE] "케이스 하나가 축 하나만 검증하는가").
    #     L61-a **평문 패턴 제거** — 실 데이터의 32건이 이 형태다. 새 게이트는 평문을 후보로
    #             삼지 않으므로 **후보 진입 자체를 안 한다**(구조 판정까지 가지도 않는다).
    #     L61-b **구조 판정** — 후보 필터(`"skill":"pjc:implement-task"`)에 **걸리는데도**
    #             tool_use 블록의 `name`이 `Skill`이 아니라서 거부되는 경로. 이 축이 없으면
    #             `name -eq 'Skill'` 조건을 지워도 골든이 전부 green이다(리뷰 B1이 지적한 공백).
    $trToolInput = Join-Path $work 'tr-active-toolinput.jsonl'
    @($skillEntry,
      '{"type":"user","message":{"content":"진행"}}',
      '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"scenarios/require-evidence.ps1","new_string":"Launching skill: pjc:implement-task"}}]}}') |
        Set-Content -Encoding UTF8 $trToolInput
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154k'; transcript_path = $trToolInput; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 다른 도구 input의 평문 발동 리터럴 → 후보 미진입, 미차단 (T6 음성·D8-a)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L61-b) 경계 음성 — **구조 판정 경로를 실제로 태우는 케이스**. 후보 필터에 걸리는 JSON 리터럴이
    #   Skill이 **아닌** 도구의 input에 있다(실 데이터에서는 도구 input의 따옴표가 JSON 직렬화 시
    #   이스케이프돼 이 형태가 드물지만, **원리적으로 가능하고 구조 판정이 막아야 할 바로 그 축**이다).
    #   red(`$gateBlk.name -eq 'Skill'` 조건 제거): tool_use이기만 하면 점화 → 차단 = FAIL.
    $trFakeSkill = Join-Path $work 'tr-active-fakeskill.jsonl'
    @($skillEntry,
      '{"type":"user","message":{"content":"진행"}}',
      '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"skill":"pjc:implement-task"}}]}}') |
        Set-Content -Encoding UTF8 $trFakeSkill
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154m'; transcript_path = $trFakeSkill; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: Skill이 아닌 도구의 input.skill은 구조 판정이 거부 → 미차단 (T6 음성·D8-b)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L61-c) 경계 음성 — **사용자가 범위를 "한정"한 경우도 조건 5가 받아야 한다**(F-7 M2).
    #   종전 `T\d+\s*만`은 *"T5까지만 진행해줘"* 를 놓쳤다(`T5` 다음이 `까`). 전환 전에는 그 조합이
    #   어차피 통과였지만(문면이 4정규식에 안 걸린다), **화이트리스트에서는 게이트가 켜져 있어
    #   문면 무관 차단**이므로 사용자가 한정한 작업에 "계속하라"를 들이대게 된다.
    #   red(`T\d+[^\r\n]{0,4}만` → `T\d+\s*만` 복원): $userStop이 거짓이 되어 차단 = FAIL.
    $trLimited = Join-Path $work 'tr-active-limited.jsonl'
    @('{"type":"user","message":{"content":"T5까지만 진행해줘"}}', $skillEntry) | Set-Content -Encoding UTF8 $trLimited
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154n'; transcript_path = $trLimited; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 사용자 한정 지시(T5까지만) → 미차단 (T6 음성·F-7 M2)" -R $r -ExpectExit 0 -ExpectNotContains $loopBlock

    # (L62) 양성 델타 짝 — 같은 위치에 **진짜 Skill tool_use**를 두면 게이트가 켜져 차단된다.
    #   L61과 이 케이스의 차이는 **tool_use 블록의 `name`·`input` 구조 하나뿐**이라, 둘이 짝으로
    #   "구조 판정이 실제로 그 축을 본다"를 고정한다(문자열 존재 여부는 양쪽 동일).
    $trRealSkill = Join-Path $work 'tr-active-realskill.jsonl'
    @('{"type":"user","message":{"content":"진행"}}', $skillEntry) | Set-Content -Encoding UTF8 $trRealSkill
    $r = Invoke-Hook 'require-evidence.ps1' (@{ cwd = $ev4; session_id = 'lp154l'; transcript_path = $trRealSkill; last_assistant_message = $incident154 } | ConvertTo-Json -Compress)
    Assert-Case -Name "evidence: 진짜 Skill tool_use는 게이트 점화 → 차단 (T6 양성·D8 델타 짝)" -R $r -ExpectExit 0 -ExpectContains $loopBlock
} else {
    Write-Host "[SKIP] require-evidence 시나리오 (git 없음)"
}
}   # ---- §4 게이트 끝 (require-evidence) ----

