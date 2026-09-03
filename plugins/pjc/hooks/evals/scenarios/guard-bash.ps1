# scenarios/guard-bash.ps1 — guard-bash 로드 가드 시나리오 (dot-source 대상 부재 시 fail-open 가시화) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
if (Test-HookSelected @('guard-bash')) {
# [v1.101.0 T4] 디스패처 로드 가드 — guard-bash.ps1 부재(로드 실패) 시 침묵 fail-open 대신
#   stderr 경고 1줄 + exit 0(비차단)을 실증한다. lib 없는 임시 사본에서 디스패처를 단독 실행
#   (Invoke-Hook은 $scriptsDir 고정이라 lib가 항상 옆에 있음 — 부재 상황은 사본으로만 재현 가능).
$noLib = Join-Path $work 'dispatch-nolib'; New-Item -ItemType Directory $noLib -Force | Out-Null
Copy-Item (Join-Path $scriptsDir 'guard-bash.ps1') $noLib -Force
$noLibJson = @{ tool_name = 'Bash'; tool_input = @{ command = 'git commit -m "T1: x"' } } | ConvertTo-Json -Compress
$outNoLib = $noLibJson | pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $noLib 'guard-bash.ps1') 2>&1
$rNoLib = @{ code = $LASTEXITCODE; out = (($outNoLib | Out-String)).Trim() }
Assert-Case -Name "guard-bash: guard-commit-secrets 부재 시 로드 가드 경고 + exit 0 (v1.101.0 T4 fail-open 가시화)" -R $rNoLib -ExpectExit 0 -ExpectContains '로드 실패'
}   # ---- 로드 가드 게이트 끝 (guard-bash) ----

# ---- require-task-checkbox 시나리오 흡수 (v1.225.0 — 그 hook이 guard-bash로 합쳐졌다) ----
# scenarios/guard-bash.ps1 — require-task-checkbox 시나리오 (§8 — 디스패처 동등성 포함) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 8) require-task-checkbox 시나리오 (plan 체크박스 게이트 — git 불요, plan 파일만)
# =====================================================================
# hook은 command 문자열 파싱 + plan 파일 Read만 하므로 git repo가 필요 없다.
# 무상태 음성(비커밋·checkpoint·merge 등)은 hook-cases.json, 여기는 plan 상태 필요분.
# 게이트 태그 2개: dispatch 동등성 블록이 이 섹션의 plan 픽스처($rtcUn·$rtcOk)를 재사용하므로
# guard-bash 필터에서도 섹션 전체를 실행한다(초과 실행 허용 원칙).
if (Test-HookSelected @('guard-bash')) {
$rtcUn = Join-Path $work 'rtc-unchecked'; New-Item -ItemType Directory $rtcUn -Force | Out-Null
"# plan`n- [ ] T3. 검색 기능`n- [x] T1. 완료분" | Set-Content (Join-Path $rtcUn 'plan.md')
$rtcIn = Join-Path $work 'rtc-inprog'; New-Item -ItemType Directory $rtcIn -Force | Out-Null
"# plan`n- [/] T3. 진행 중" | Set-Content (Join-Path $rtcIn 'plan.md')
$rtcOk = Join-Path $work 'rtc-checked'; New-Item -ItemType Directory $rtcOk -Force | Out-Null
"# plan`n- [x] T3. 검색 기능" | Set-Content (Join-Path $rtcOk 'plan.md')
$rtcMulti = Join-Path $work 'rtc-multi/docs/plans'; New-Item -ItemType Directory $rtcMulti -Force | Out-Null
"# 과거 회차 plan`n- [ ] T3. x" | Set-Content (Join-Path $rtcMulti '2026-07-01-a.md')

$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn 'T3: 검색 요약')
Assert-Case -Name "rtc: 미완료 [ ] T3 커밋 차단 (차단 사유 문구 고정)" -R $r -ExpectExit 2 -ExpectContains '완료 커밋인데 plan의 T'
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcIn 'T3: 검색 요약')
Assert-Case -Name "rtc: 진행중 [/] T3 커밋 차단" -R $r -ExpectExit 2 -ExpectContains 'T3'
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcOk 'T3: 검색 요약')
Assert-Case -Name "rtc: 완료 [x] T3 커밋 통과(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn 'T99: 없는 task')
Assert-Case -Name "rtc: plan에 없는 T번호 통과(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson (Join-Path $work 'rtc-multi') 'T3: x')
Assert-Case -Name "rtc: docs/plans 과거 plan만 존재하면 통과(루트 plan.md 없음)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn 'T1: 이미 완료된 task')
Assert-Case -Name "rtc: [x] T1은 통과·[ ] T3 무관(첫 매치만 판정)" -R $r -ExpectExit 0 -ExpectSilent $true
$rtcStar = Join-Path $work 'rtc-star'; New-Item -ItemType Directory $rtcStar -Force | Out-Null
"# plan`n* [ ] T3. 별표 불릿" | Set-Content (Join-Path $rtcStar 'plan.md')
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcStar 'T3: 요약')
Assert-Case -Name "rtc: 별표 불릿 * [ ] T3 커밋 차단 (M6)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

# plan 파일이 아예 없는 프로젝트 → 통과 (fail-open. 상위 탐색은 .git/.claude 경계에서 멈춤)
$rtcNo = Join-Path $work 'rtc-noplan'; New-Item -ItemType Directory $rtcNo -Force | Out-Null
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcNo 'T3: 검색 요약')
Assert-Case -Name "rtc: plan 파일 없음 통과(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [P1T5] 제목이 아닌 본문·괄호의 T<N>: 언급은 판정 제외 (제목 첫 줄만) ----
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn '문서: 릴리즈 노트 (T3: 스키마 변경 반영)')
Assert-Case -Name "rtc: 제목이 '문서:'이고 괄호에 T3 언급 → 통과 (P1T5 제목 한정)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn 'T3: 실제 완료 커밋')
Assert-Case -Name "rtc: 제목이 T3:로 시작 → 미완료 차단 유지 (P1T5)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

# QUICK 우회 — 별도 stderr 안내 출력이 있는 독립 분기 (silent 아님, exit 0)
$env:CLAUDE_HARNESS_QUICK = '1'
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn 'T3: 검색 요약')
Assert-Case -Name "rtc: QUICK=1 우회 (비차단 + 안내)" -R $r -ExpectExit 0 -ExpectContains 'QUICK'
$env:CLAUDE_HARNESS_QUICK = $null

# ---- [v1.99.0 T6] rtc 스테이트풀 케이스 디스패처 동등성 (plan cwd 필요분) ----
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn 'T3: 검색 요약')
Assert-Case -Name "dispatch=rtc: 미완료 [ ] T3 커밋 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcOk 'T3: 검색 요약')
Assert-Case -Name "dispatch=rtc: 완료 [x] T3 커밋 통과(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn '문서: 릴리즈 노트 (T3: 반영)')
Assert-Case -Name "dispatch=rtc: 제목 아닌 T3 언급 통과 (제목 한정)" -R $r -ExpectExit 0 -ExpectSilent $true
}   # ---- §8 게이트 끝 (guard-bash) ----

