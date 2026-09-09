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

# ---- [P1T5] 제목이 아닌 본문·괄호의 T<N> 언급은 판정 제외 (제목 첫 줄만) ----
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn '문서: 릴리즈 노트 (T3: 스키마 변경 반영)')
Assert-Case -Name "rtc: 제목이 '문서:'이고 괄호에 T3 언급 → 통과 (P1T5 제목 한정)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcUn 'T3: 실제 완료 커밋')
Assert-Case -Name "rtc: 제목이 T3:로 시작 → 미완료 차단 유지 (P1T5)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

# ---- [회차 44 T4] 현행 제목 형식 `{유형}: T<N> — …` + 템플릿 볼드 하위 항목 `- [ ] **T3-1**` ----
#   종전 정규식은 구형 `T3:` 제목과 비볼드 체크박스만 받아 현행 회차에서 한 번도 발화하지 않았다(게이트 사문화).
#   양성 2(신형 제목 · heredoc 제목) + 완료 통과 1 + 델타 음성 1(유형 뒤가 T 가 아닌 제목).
$rtcBold = Join-Path $work 'rtc-bold'; New-Item -ItemType Directory $rtcBold -Force | Out-Null
"# plan`n### T3. 검색`n- [ ] **T3-1** 검색 요약`n- [x] **T3-2** 인덱스" | Set-Content (Join-Path $rtcBold 'plan.md')
$rtcBoldOk = Join-Path $work 'rtc-bold-ok'; New-Item -ItemType Directory $rtcBoldOk -Force | Out-Null
"# plan`n### T3. 검색`n- [x] **T3-1** 검색 요약`n- [x] **T3-2** 인덱스" | Set-Content (Join-Path $rtcBoldOk 'plan.md')
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcBold '기능: T3 — 검색 요약')
Assert-Case -Name "rtc: 신형 제목 기능: T3 — + 볼드 하위 항목 미완료 → 차단 (회차 44 T4)" -R $r -ExpectExit 2 -ExpectContains '완료 커밋인데 plan의 T'
$heredocMsg = [string]::Join("`n", @('$(cat <<''EOF''', '기능: T3 — 검색 요약', '', '본문', 'EOF', ')'))
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcBold $heredocMsg)
Assert-Case -Name "rtc: heredoc 제목(-m 뒤 cat heredoc 본문) 도 둘째 줄을 제목으로 읽어 차단 (회차 44 T4)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcBoldOk '기능: T3 — 검색 요약')
Assert-Case -Name "rtc: 볼드 하위 항목 전부 [x] → 신형 제목 통과(무출력) (회차 44 T4)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-CommitJson $rtcBold '설정: v1.258.0 — 회차 44: T3 정리')
Assert-Case -Name "rtc: 유형 뒤가 T<N> 이 아닌 제목은 판정 제외 (회차 44 T4 델타 음성)" -R $r -ExpectExit 0 -ExpectSilent $true

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

# ---- [회차 51] block-plan-write: plan.md 를 대상으로 하는 쓰기 명령 차단 ----
#   회차 50 이 Deferred 절 교체 스크립트로 plan.md 를 29줄만 남기고 잘랐다. plan.md 는 gitignore 라
#   git 으로 복구할 수 없어 경고가 아니라 차단이다. 판정은 「쓰기 구문의 **대상 인자**가 plan.md 인가」
#   하나이고, 「명령 어딘가에 plan.md 가 있는가」가 아니다 — 후자면 대장의 그 줄을 지우는 정상 작업이
#   막힌다(대장에 리터럴 plan.md 가 20회 있다). 그래서 음성 4건이 양성 1건과 짝을 이룬다.
function New-BashJson([string]$cmd) {
    return (@{ tool_name = 'Bash'; tool_input = @{ command = $cmd } } | ConvertTo-Json -Compress)
}

# BPW1 (양성): 회차 50 의 사고 명령 형태 — 변수를 거쳐 지시하므로 리터럴 매치로는 새어 나간다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "python - <<'PY'`np='plan.md'`ns=open(p).read()`nopen(p,'w').write(s)`nPY")
Assert-Case -Name "bpw: python open(p,'w') 로 plan.md 쓰기 차단 (BPW1)" -R $r -ExpectExit 2 -ExpectContains 'plan.md 를 스크립트로 쓰려 합니다'

# BPW2 (델타 음성 — 읽기): 조회는 막지 않는다. 막으면 실측·조사 자체가 불가능해진다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "grep -n 'Deferred' plan.md")
Assert-Case -Name "bpw: plan.md 읽기는 통과 (BPW2)" -R $r -ExpectExit 0 -ExpectSilent $true

# BPW3 (델타 음성 — 읽어서 다른 파일로): 리다이렉션 **대상**이 plan.md 가 아니다.
#   이 케이스가 없으면 「명령에 plan.md 와 `>` 가 있으면 막는다」로 구현해도 전건 green 이다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'head -12 plan.md > /tmp/plan_head.txt')
Assert-Case -Name "bpw: plan.md 를 읽어 다른 파일로 내보내는 형태는 통과 (BPW3)" -R $r -ExpectExit 0 -ExpectSilent $true

# BPW4 (델타 음성 — 다른 파일 쓰기): plan.md 를 언급조차 하지 않는 스크립트 쓰기.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "python - <<'PY'`nopen('notes.md','w').write('x')`nPY")
Assert-Case -Name "bpw: 다른 파일을 쓰는 인라인 스크립트는 통과 (BPW4)" -R $r -ExpectExit 0 -ExpectSilent $true

# BPW5 (델타 음성 — 대상은 다른 파일인데 명령 텍스트에 plan.md 가 있다): 계획 리뷰 BLOCKER 를 고정한다.
#   sed -i 의 대상은 **마지막 위치 인자**이고 패턴 문자열 안의 plan.md 는 대상이 아니다.
#   초안 설계(「언급 ∧ 쓰기 신호」)면 회차 51 자신의 T4-1 이 이 형태라 스스로 차단됐다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "sed -i '/plan.md 를 스크립트로 후편집/d' docs/plans/deferred.md")
Assert-Case -Name "bpw: sed -i 패턴 안의 plan.md 는 대상이 아니다 (BPW5)" -R $r -ExpectExit 0 -ExpectSilent $true

# BPW6 (델타 음성 — 쓰기 동사를 본문에 담은 조회): 완료 리뷰 BLOCKER 를 고정한다.
#   쓰기 동사를 세그먼트 어디서나 찾으면 이 조회가 막힌다. 하필 이 회차의 plan.md·rationale 이
#   그 단어들을 담고 있어, 다음 세션이 자기 plan 을 grep 하는 순간 차단됐다(실측 5형태).
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "grep -n 'Copy-Item' plan.md")
Assert-Case -Name "bpw: 쓰기 동사를 본문에 담은 plan.md 조회는 통과 (BPW6)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "grep -n Set-Content plan.md")
Assert-Case -Name "bpw: 쓰기 cmdlet 이름을 찾는 조회도 통과 (BPW6b)" -R $r -ExpectExit 0 -ExpectSilent $true

# BPW7~9 (양성 — 나머지 신호): 신호마다 양성이 없으면 그 분기를 지워도 전건 green 이다
#   (완료 리뷰 MAJOR — 7신호 중 6개가 음성으로만 등장했다).
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "echo x > plan.md")
Assert-Case -Name "bpw: 리다이렉션 대상이 plan.md 면 차단 (BPW7)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "sed -i 's/a/b/' plan.md")
Assert-Case -Name "bpw: sed -i 의 대상이 plan.md 면 차단 (BPW8)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'
# ⚠ named parameter 형이 PowerShell 표준이다 — 위치 인자만 막으면 실사용 형태가 샌다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "Set-Content -Path plan.md -Value 'x'")
Assert-Case -Name "bpw: Set-Content -Path plan.md 차단 (BPW9)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "python -c ""p='plan.md'; open(p,'w').write('x')""")
Assert-Case -Name "bpw: 한 줄 -c 형태의 변수 대입도 역참조 (BPW10)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'

# ---- [회차 52] 따옴표 인식 분할(Split-TopLevel 이식) ----
#   착수 시점의 분할 넷은 전부 정규식이었고 따옴표 안의 구분자에서 쪼갰다. 그 결과 마지막 조각의
#   첫 토큰이 `"` 가 되어, 쓰기 동사를 첫 실효 토큰으로 판정하는 block-plan-write 가 새어 나갔다.
#   경고 검사 셋에는 이 축을 재는 케이스가 착수 0건이었다 — 아래 셋이 그 그물이다.

# ST1 (양성 — ②의 본체): 회차 51 이 실측한 유일한 MISS 형태.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'sed -i "s|a|b|" plan.md')
Assert-Case -Name "split: 따옴표 안의 | 가 든 sed -i 도 plan.md 쓰기로 차단 (ST1)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'

# ST2 (경고 축 — warn-global-find): 따옴표 안의 `;` 가 분할을 깨면 뒤 세그먼트의 find 를 놓친다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'echo "a;b" && find / -name x')
Assert-Case -Name "split: 따옴표 안 ; 뒤의 루트 전역 탐색을 여전히 잡는다 (ST2)" -R $r -ExpectExit 0 -ExpectContains '[GLOBAL FIND WARNING]'

# ST3 (경고 축 — warn-dangerous-assignment): 대입값 자체가 따옴표 안 구분자를 담은 형태.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'echo "x|y"; X=/; rm -rf $X')
Assert-Case -Name "split: 따옴표 안 | 가 있어도 위험 대입 경고가 산다 (ST3)" -R $r -ExpectExit 0 -ExpectContains '[DANGEROUS ASSIGNMENT WARNING]'

# ST4 (경고 축 — warn-external-ops): 같은 형태로 외부 작업 경고가 살아 있는지.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'echo "a|b" && git push origin main')
Assert-Case -Name "split: 따옴표 안 | 뒤의 git push 를 여전히 잡는다 (ST4)" -R $r -ExpectExit 0 -ExpectContains '[EXTERNAL OP WARNING]'

# ST5 (도구별 이스케이프): PowerShell 도구에서 `\` 는 리터럴이라 `"C:\"` 가 닫힌 문자열이고
#   뒤의 `;` 가 구분자로 선다. bash 규칙으로 읽으면 인용이 열린 채 남아 분리가 안 된다(회차 44).
$psJson = (@{ tool_name = 'PowerShell'; tool_input = @{ command = 'echo "C:\"; X=/; Remove-Item -Recurse -Force $X' } } | ConvertTo-Json -Compress)
$r = Invoke-Hook 'guard-bash.ps1' $psJson
Assert-Case -Name 'split: PowerShell 도구의 "C:\" 뒤 세그먼트를 잃지 않는다 (ST5)' -R $r -ExpectExit 0 -ExpectContains '[DANGEROUS ASSIGNMENT WARNING]'

# ST6 (메시지 스트립 — D6): warn-external-ops 만 $cmd 가 아니라 $scanCmd 를 분할한다.
#   $cmd 를 넘기면 따옴표 인식이 메시지를 **한 세그먼트로 보존**해 그 안의 push 에 오경고가 난다.
#   착수 시점에 이 형태(단일 세그먼트)를 재는 케이스가 0건이었다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'git commit -m "will git push later"')
Assert-Case -Name "split: 커밋 메시지 안의 git push 는 경고하지 않는다 (ST6)" -R $r -ExpectExit 0 -ExpectSilent $true

# ST7~9 (③ 양성 — 신호 3종): cp/mv · Copy-Item 계열 · [System.IO.File]::WriteAll* 는
#   착수 시점에 양성이 하나도 없어 **그 분기를 지워도 전건 green** 이었다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'cp notes.md plan.md')
Assert-Case -Name "bpw: cp 의 마지막 인자가 plan.md 면 차단 (ST7)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'Copy-Item notes.md plan.md')
Assert-Case -Name "bpw: Copy-Item 의 대상이 plan.md 면 차단 (ST8)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson "pwsh -c ""[System.IO.File]::WriteAllText('plan.md','x')""")
Assert-Case -Name "bpw: [System.IO.File]::WriteAllText 의 첫 인자가 plan.md 면 차단 (ST9)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'

# ST10 (짝 안 맞는 따옴표 — 미탐 쪽 못박기): 여는 따옴표가 닫히지 않으면 그 뒤 전부가 한
#   세그먼트로 남고, **첫 실효 토큰으로 판정하는 동사 신호**(ⓒsed -i·ⓔcp/mv·ⓓSet-Content)는
#   그 세그먼트의 첫 토큰이 `echo` 라 발화하지 않는다. ⚠ **block-plan-write 는 차단 게이트이므로
#   이것은 곧 plan.md 쓰기 차단의 미탐이다.** 통과가 옳아서가 아니라 **지금 그렇다는 것을 고정**
#   하는 케이스이고, 바꾸려면 미완결 인용의 셸 의미를 먼저 정해야 한다(실측: sed -i·cp·Set-Content
#   세 형태 모두 exit 0).
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'echo "unclosed; cp notes.md plan.md')
Assert-Case -Name "split: 닫히지 않은 따옴표 뒤의 동사 신호는 미탐이다 (ST10)" -R $r -ExpectExit 0 -ExpectSilent $true

# ST11 (같은 형태에서 리다이렉션 신호는 산다): ⓑ 는 세그먼트의 **첫 토큰**이 아니라 세그먼트 안의
#   `>` 대상을 보므로 인용이 열려 있어도 잡힌다. ST10 과 짝을 이뤄 **미탐의 경계가 어디인지**를
#   고정한다 — 「따옴표가 안 닫히면 다 샌다」가 아니다.
$r = Invoke-Hook 'guard-bash.ps1' (New-BashJson 'echo "unclosed; echo x > plan.md')
Assert-Case -Name "split: 닫히지 않은 따옴표 뒤여도 리다이렉션 대상은 잡는다 (ST11)" -R $r -ExpectExit 2 -ExpectContains '스크립트로 쓰려 합니다'

}   # ---- §8 게이트 끝 (guard-bash) ----

