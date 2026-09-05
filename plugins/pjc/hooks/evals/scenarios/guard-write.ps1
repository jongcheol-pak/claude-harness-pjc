# scenarios/guard-write.ps1 — guard-write 시나리오 (§2 plan 유무·trivial·temp·NotebookEdit + §2c 작성 게이트) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 2) guard-write 시나리오 (plan 유무·trivial·temp·NotebookEdit)
# =====================================================================
# 섹션 게이트: 본문 재들여쓰기 없이 if 블록으로만 감싼다(디프 최소화 — 게이트 추가가 케이스
# 내용 변경으로 보이지 않게). 이하 모든 섹션 게이트 동일.
if (Test-HookSelected @('guard-write')) {
$noplan = Join-Path $work 'proj-noplan';  New-Item -ItemType Directory $noplan -Force | Out-Null
$withplan = Join-Path $work 'proj-plan';  New-Item -ItemType Directory $withplan -Force | Out-Null
"# plan`n- [ ] T1: work" | Set-Content (Join-Path $withplan 'plan.md')
$doneplan = Join-Path $work 'proj-done';  New-Item -ItemType Directory $doneplan -Force | Out-Null
"# plan`n- [x] T1: done" | Set-Content (Join-Path $doneplan 'plan.md')
$emptyplan = Join-Path $work 'proj-empty';  New-Item -ItemType Directory $emptyplan -Force | Out-Null
"# plan`n요약만 있고 task 체크박스가 하나도 없음" | Set-Content (Join-Path $emptyplan 'plan.md')
# 별표('*') 불릿으로 완료된 plan — G4/H3 카운팅이 '-'만 보던 버그 회귀 가드:
#   '*' 불릿을 못 세면 done=0으로 오판해 H3 '빈 plan'을 오탐한다. 통일 후엔 G4 '완료 plan'이어야 한다.
$starplan = Join-Path $work 'proj-star';  New-Item -ItemType Directory $starplan -Force | Out-Null
"# plan`n* [x] T1: done" | Set-Content (Join-Path $starplan 'plan.md')

$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'A.cs'))
Assert-Case -Name "guard-write: plan 없이 .cs Write 차단 (차단 사유 문구 고정)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'x.md'))
Assert-Case -Name "require-plan: plan 없이 .md 통과" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $withplan (Join-Path $withplan 'A.cs'))
Assert-Case -Name "require-plan: plan 있으면 .cs 통과" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $doneplan (Join-Path $doneplan 'A.cs'))
Assert-Case -Name "require-plan: 완료 plan 경고+비차단 (in-scope 후속 안내 포함)" -R $r -ExpectExit 0 -ExpectContains '범위 내 후속'
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $emptyplan (Join-Path $emptyplan 'A.cs'))
Assert-Case -Name "require-plan: 빈 plan(체크박스 0) 경고+비차단 (H3)" -R $r -ExpectExit 0 -ExpectContains '빈/플레이스홀더'
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $starplan (Join-Path $starplan 'A.cs'))
Assert-Case -Name "require-plan: 별표('*') 완료 plan은 G4(완료)로 판정, H3(빈) 오탐 아님" -R $r -ExpectExit 0 -ExpectContains '완료된 것으로'
$trivial = @{ tool_name = 'Edit'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'A.cs'); old_string = 'int x = 1;'; new_string = 'int x = 2;' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $trivial
Assert-Case -Name "require-plan: trivial Edit 통과" -R $r -ExpectExit 0 -ExpectContains 'Trivial'
$newsym = @{ tool_name = 'Edit'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'A.cs'); old_string = '// x'; new_string = 'public class Foo { }' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $newsym
Assert-Case -Name "require-plan: 새 클래스 정의 Edit 차단" -R $r -ExpectExit 2

# [H3] 시스템 임시 폴더의 검증 스크립트 — plan 없이도 통과가 기대(회귀 가드)
$tempFile = Join-Path (Join-Path (Get-EvalRoot -Base 'Temp') $script:EvalParentName) 'scratch/check.py'
New-Item -ItemType Directory (Split-Path $tempFile) -Force | Out-Null
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson (Split-Path $tempFile) $tempFile)
Assert-Case -Name "require-plan: 시스템 임시폴더 .py 통과 (H3)" -R $r -ExpectExit 0

# [H5] NotebookEdit — notebook_path 인식 후 plan 게이트 적용이 기대(회귀 가드)
$nb = @{ tool_name = 'NotebookEdit'; cwd = $noplan; tool_input = @{ notebook_path = (Join-Path $noplan 'n.ipynb'); new_source = 'x=1' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $nb
Assert-Case -Name "require-plan: NotebookEdit plan 없음 차단 (H5)" -R $r -ExpectExit 2

# [T2] 실행 자산(.github/workflows/*.yml·package.json)은 plan 게이트 적용, 일반 .json/.yml은 계속 통과
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan '.github/workflows/ci.yml'))
Assert-Case -Name "require-plan: .github/workflows/*.yml plan 없이 차단 (T2)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'package.json'))
Assert-Case -Name "require-plan: package.json plan 없이 차단 (T2)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'tsconfig.json'))
Assert-Case -Name "require-plan: tsconfig.json 통과 (T2 회귀 가드)" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'docker-compose.yml'))
Assert-Case -Name "require-plan: docker-compose.yml 통과 (T2 회귀 가드)" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'package-lock.json'))
Assert-Case -Name "require-plan: package-lock.json 통과 (T2 basename 불일치)" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'dist/package.json'))
Assert-Case -Name "require-plan: dist/package.json plan 없이 차단 (T2 산출물디렉터리 우회 전파)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'packages/plans/package.json'))
Assert-Case -Name "require-plan: packages/plans/package.json plan 없이 차단 (T2)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'dist/config.json'))
Assert-Case -Name "require-plan: dist/config.json 통과 (T2 비실행자산은 산출물 우회 유지)" -R $r -ExpectExit 0
# 선행 구분자 없는 순수 상대경로 — 정규식 (^|[\\/])의 ^ 분기 직접 검증 (cwd=noplan, file_path만 상대)
$relYml = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = '.github/workflows/rel.yml'; content = 'on: push' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $relYml
Assert-Case -Name "require-plan: 상대경로 .github/workflows/rel.yml plan 없이 차단 (T2 ^ 분기)" -R $r -ExpectExit 2

# ---- [P1T3] 신규 파일 Trivial (테스트·재현 스크립트 조건부 허용, v1.98.0) ----
$c20 = (1..20 | ForEach-Object { "line$_ = $_" }) -join "`n"
$c31 = (1..31 | ForEach-Object { "line$_ = $_" }) -join "`n"
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'tests/repro_bug.py'); content = $c20 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $wj
Assert-Case -Name "require-plan: tests/ 신규 20줄 Write 통과 (P1T3)" -R $r -ExpectExit 0 -ExpectContains 'Trivial write'
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'src/service.py'); content = $c20 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $wj
Assert-Case -Name "require-plan: 일반 소스 신규 20줄 Write 차단 유지 (P1T3)" -R $r -ExpectExit 2
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'tests/big_test.py'); content = $c31 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $wj
Assert-Case -Name "require-plan: tests/ 신규 31줄 Write 차단 (P1T3 상한)" -R $r -ExpectExit 2
$wj = @{ tool_name = 'Write'; cwd = $noplan; tool_input = @{ file_path = (Join-Path $noplan 'repro-crash.sh'); content = $c20 } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-write.ps1' $wj
Assert-Case -Name "require-plan: repro* 네이밍 신규 Write 통과 (P1T3)" -R $r -ExpectExit 0 -ExpectContains 'Trivial write'

# ---- [P1T3] 마크업·스타일 확장자 허용 (.xml/.html/.css) ----
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'config/app.xml'))
Assert-Case -Name "require-plan: .xml plan 없이 통과 (P1T3)" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'site/page.html'))
Assert-Case -Name "require-plan: .html plan 없이 통과 (P1T3)" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $noplan (Join-Path $noplan 'site/style.css'))
Assert-Case -Name "require-plan: .css plan 없이 통과 (P1T3)" -R $r -ExpectExit 0

# ---- [P1T3] G4/H3 경고 세션당 1회 디듑 (.state 마커) ----
# 위에서 doneplan·emptyplan에 각각 1회 경고했으므로, 같은 격리 홈(세션)에서 두 번째 호출은 무출력이어야 한다.
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $doneplan (Join-Path $doneplan 'B.cs'))
Assert-Case -Name "require-plan: G4 완료 plan 경고 2회차 무출력 (P1T3 디듑)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $emptyplan (Join-Path $emptyplan 'B.cs'))
Assert-Case -Name "require-plan: H3 빈 plan 경고 2회차 무출력 (P1T3 디듑)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [v1.182.0 T3] .state 디듑 마커 30일 TTL 청소 ----
# 검증 축은 「초과분만 지워지는가」다 — 전부 지우면 위 디듑이 깨지고, 아무것도 안 지우면 축적이 그대로다.
# 청소는 plan 파일을 찾은 분기 안에 있으므로 $doneplan(= G4 경로)으로 hook을 한 번 더 태워 발동시킨다.
$rpMarkerDir = Join-Path $iso '.claude/.state/require-plan-warn'
New-Item -ItemType Directory $rpMarkerDir -Force | Out-Null
$rpOldMk = Join-Path $rpMarkerDir 'ttl-old-marker'
$rpNewMk = Join-Path $rpMarkerDir 'ttl-new-marker'
Set-Content -LiteralPath $rpOldMk -Value '' ; (Get-Item $rpOldMk).LastWriteTime = (Get-Date).AddDays(-31)
Set-Content -LiteralPath $rpNewMk -Value '' ; (Get-Item $rpNewMk).LastWriteTime = (Get-Date).AddDays(-3)
$null = Invoke-Hook 'guard-write.ps1' (New-WriteJson $doneplan (Join-Path $doneplan 'C.cs'))
if ((-not (Test-Path -LiteralPath $rpOldMk)) -and (Test-Path -LiteralPath $rpNewMk)) {
    $script:results.Add(@{ ok = $true; line = '[PASS] require-plan: .state 마커 30일 초과분만 청소 (T3)' })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] require-plan: .state TTL 청소 — 31일 마커 잔존=$(Test-Path -LiteralPath $rpOldMk) / 3일 마커 소실=$(-not (Test-Path -LiteralPath $rpNewMk))" })
}

}   # ---- §2 게이트 끝 (guard-write) ----

# =====================================================================
# 2c) [v1.118.0] plan 작성 게이트 + plan 존재 판정 강화
#   PG = plan 작성 게이트(Write 축) / PE = 체크박스 도입 Edit 축 / PD = plan 존재 판정(docs/plans)
#   TE = temp 예외 분기(plan·AGENTS 두 게이트 — 종전 스위트 사각, 2026-07-10 deferred 종결)
#   §2 픽스처에 의존하지 않고 자기 픽스처를 자기 안에서 만든다(-Filter 부분 실행에서 깨지지 않게).
# =====================================================================
if (Test-HookSelected @('guard-write')) {
# transcript 스텁 — 발동 흔적 판정은 스킬명 문자열을 매치하므로 이 게이트 전용 스텁을 자기 안에서 만든다
$trPlanNo = Join-Path $work 'tr-plan-none.jsonl'
'{"type":"assistant","text":"pjc:plan 스킬 이야기만 하는 산문 언급"}' | Set-Content $trPlanNo
$trPlanIn = Join-Path $work 'tr-plan-input.jsonl'
'{"type":"assistant","tool_use":{"name":"Skill","input":{"skill":"pjc:plan"}}}' | Set-Content $trPlanIn
$trImplRes = Join-Path $work 'tr-impl-result.jsonl'
'{"type":"tool_result","content":"Launching skill: pjc:implement"}' | Set-Content $trImplRes

$pg = Join-Path $work 'proj-plangate'; New-Item -ItemType Directory $pg -Force | Out-Null
$pgPlan = Join-Path $pg 'plan.md'
$pgPlansDir = Join-Path $pg 'docs/plans'; New-Item -ItemType Directory $pgPlansDir -Force | Out-Null

function New-PlanWriteJson([string]$cwd, [string]$file, [string]$content, [string]$tr) {
    $top = @{}
    if ($tr) { $top = @{ transcript_path = $tr } }
    return ((@{ tool_name = 'Write'; cwd = $cwd; tool_input = @{ file_path = $file; content = $content } } + $top) | ConvertTo-Json -Compress)
}
function New-PlanEditJson([string]$cwd, [string]$file, [string]$old, [string]$new, [string]$tr) {
    $top = @{}
    if ($tr) { $top = @{ transcript_path = $tr } }
    return ((@{ tool_name = 'Edit'; cwd = $cwd; tool_input = @{ file_path = $file; old_string = $old; new_string = $new } } + $top) | ConvertTo-Json -Compress)
}

# --- PG: Write 축 ---
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: plan.md 신규 Write + 흔적 없음 차단 (PG1 — 차단 사유 문구 고정)" -R $r -ExpectExit 2 -ExpectContains 'plan 작성은 pjc:plan 스킬로만 합니다'
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $trPlanIn)
Assert-Case -Name "plan게이트: plan.md Write + pjc:plan 흔적 통과 (PG2)" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $trImplRes)
Assert-Case -Name "plan게이트: plan.md Write + pjc:implement 흔적 통과 (PG3)" -R $r -ExpectExit 0
# PG4: 기존 plan.md도 Write면 차단 (신규/기존 무관 — 통째 재작성이므로)
"# 기존 plan`n- [x] T1: done" | Set-Content $pgPlan
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg $pgPlan "# 재작성`n- [ ] T1: y" $trPlanNo)
Assert-Case -Name "plan게이트: 기존 plan.md Write도 차단 — 재작성 게이트 (PG4)" -R $r -ExpectExit 2
# PG5: 체크박스 '상태 변경' Edit은 통과 (old에도 체크박스 있음 — 정당 갱신 경로의 핵심 회귀 가드)
$r = Invoke-Hook 'guard-write.ps1' (New-PlanEditJson $pg $pgPlan '- [ ] T1: x' '- [x] T1: x' $trPlanNo)
Assert-Case -Name "plan게이트: plan.md 체크박스 [ ]->[x] Edit 통과 (PG5)" -R $r -ExpectExit 0
# PG6: docs/plans/deferred.md(체크박스 0) Write 통과 — 대장 오차단 방지
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg (Join-Path $pgPlansDir 'deferred.md') "# Deferred 대장`n- [2026-07-10] 항목 하나" $trPlanNo)
Assert-Case -Name "plan게이트: docs/plans/deferred.md(체크박스 0) Write 통과 (PG6)" -R $r -ExpectExit 0
# PG7/PG8: docs/plans/*.md에 체크박스 있으면 차단 (별표 불릿 표기 변형 포함)
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg (Join-Path $pgPlansDir '2026-07-13-x.md') "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: docs/plans/ 체크박스 plan Write 차단 (PG7)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg (Join-Path $pgPlansDir 'y.md') "# plan`n* [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: docs/plans/ 별표('*') 불릿 plan도 차단 (PG8)" -R $r -ExpectExit 2
# PG9: transcript 미제공 → fail-open
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $pg $pgPlan "# plan`n- [ ] T1: x" $null)
Assert-Case -Name "plan게이트: transcript 미제공 fail-open 통과 (PG9)" -R $r -ExpectExit 0

# --- PE: 체크박스 '도입' Edit 축 (2단계 우회 차단) ---
$peFile = Join-Path $pgPlansDir 'sneak.md'
"# 그냥 메모" | Set-Content $peFile
$r = Invoke-Hook 'guard-write.ps1' (New-PlanEditJson $pg $peFile '# 그냥 메모' "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: 체크박스 도입 Edit 차단 — 2단계 우회 (PE1)" -R $r -ExpectExit 2 -ExpectContains 'pjc:plan'
$r = Invoke-Hook 'guard-write.ps1' (New-PlanEditJson $pg $peFile '# 그냥 메모' "# plan`n- [ ] T1: x" $trImplRes)
Assert-Case -Name "plan게이트: 체크박스 도입 Edit + pjc:implement 흔적 통과 (PE2)" -R $r -ExpectExit 0
# PE3: MultiEdit 순차 적용 우회 — edit#1이 도입, edit#2가 그 체크박스를 old로 참조.
#   합산 판정이면 old에 체크박스가 섞여 통과했을 것(false-negative). edit 단위 판정이라 차단된다.
$peMulti = @{ tool_name = 'MultiEdit'; cwd = $pg; transcript_path = $trPlanNo; tool_input = @{
    file_path = $pgPlan
    edits = @(
        @{ old_string = 'PLACEHOLDER'; new_string = '- [ ] T1: x' },
        @{ old_string = '- [ ] T1: x'; new_string = "- [ ] T1: x`n- [ ] T2: y" }
    )
} } | ConvertTo-Json -Compress -Depth 5
$r = Invoke-Hook 'guard-write.ps1' $peMulti
Assert-Case -Name "plan게이트: MultiEdit 순차 적용 우회 차단 — edit 단위 판정 (PE3)" -R $r -ExpectExit 2
# PE4/PE5 [v1.181.0 T7] — `$planTaskRx` 확장(`-`·`~`)의 **델타 음성**.
#   그 확장은 방향이 둘이다: plan 존재 판정에서는 완화지만 **이 작성 게이트에서는 차단이 넓어진다**.
#   확장 전 무매치였던 표기가 이제 새로 차단되는지(의도된 확대)와, 체크박스가 아닌 정상 문서가
#   여전히 통과하는지(오차단 0)를 함께 건다 — 양성만 보면 경계가 어디까지 넓어졌는지 알 수 없다.
$r = Invoke-Hook 'guard-write.ps1' (New-PlanEditJson $pg $peFile '# 그냥 메모' "# plan`n- [-] T1: 취소됨" $trPlanNo)
Assert-Case -Name "plan게이트: 취소 체크박스 [-] 도입 Edit 차단 (PE4, v1.181.0 확장 델타)" -R $r -ExpectExit 2 -ExpectContains 'pjc:plan'
$r = Invoke-Hook 'guard-write.ps1' (New-PlanEditJson $pg $peFile '# 그냥 메모' "# 메모`n- 항목 하나`n- [단순 대괄호] 링크 아님" $trPlanNo)
Assert-Case -Name "plan게이트: 체크박스 아닌 대괄호 문서는 통과 (PE5, 오차단 0)" -R $r -ExpectExit 0

# --- PD: plan 존재 판정 (루트 단일계 — v1.210.0) ---
# 이 블록은 「plan 위치는 루트 plan.md 하나」로 좁힌 경계를 고정한다. PD2가 **새 차단의 발화**,
#   PD3이 그 **해소**, PD4가 **정상 레포 무회귀**다 — 셋이 함께 있어야 오차단 0이 실증된다
#   (차단만 확인하면 「막혔다」는 알지만 「풀린다」·「멀쩡한 레포는 그대로다」를 모른다).
# PD1: docs/plans에 체크박스 없는 .md만 → 차단 + 진단 문구(위치가 루트 하나임을 알린다)
$pd1 = Join-Path $work 'proj-pd1'; New-Item -ItemType Directory (Join-Path $pd1 'docs/plans') -Force | Out-Null
"# 메모`n- [2026-07-10] 체크박스 아님" | Set-Content (Join-Path $pd1 'docs/plans/notes.md')
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pd1 (Join-Path $pd1 'A.cs'))
Assert-Case -Name "plan판정: docs/plans만 있고 루트 plan.md 없으면 차단 (PD1)" -R $r -ExpectExit 2 -ExpectContains '루트 plan.md 하나'
# PD2 (델타 음성 ① — 새 경계의 발화): docs/plans에 체크박스 plan이 있어도 루트 plan.md가 없으면 차단.
#   v1.210.0 이전에는 통과했다 — 완료된 과거 회차 plan이 게이트를 영구히 켜던 구멍이 여기였다.
$pd2 = Join-Path $work 'proj-pd2'; New-Item -ItemType Directory (Join-Path $pd2 'docs/plans') -Force | Out-Null
"# plan`n- [ ] T1: work" | Set-Content (Join-Path $pd2 'docs/plans/2026-07-13-a.md')
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pd2 (Join-Path $pd2 'A.cs'))
Assert-Case -Name "plan판정: docs/plans 체크박스 plan은 더 이상 판정을 켜지 않는다 (PD2, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '루트 plan.md 하나'
# PD3 (해소 — 무회귀 성격): 같은 레포에 루트 plan.md를 만들면 즉시 통과. 차단이 막다른 길이 아님을 실증.
#   구코드도 루트 plan.md를 폴백보다 먼저 봤으므로 이 케이스 자체는 변이에서 FAIL하지 않는다.
#   그래도 필요하다 — PD2의 차단만 두면 「막혔다」는 알아도 「어떻게 푸는가」가 회귀로 고정되지 않는다.
"# plan`n- [ ] T1: work" | Set-Content (Join-Path $pd2 'plan.md')
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pd2 (Join-Path $pd2 'A.cs'))
Assert-Case -Name "plan판정: 루트 plan.md를 만들면 차단이 풀린다 (PD3, 해소)" -R $r -ExpectExit 0
# PD4 (델타 음성 ③ — 무회귀): 루트 plan.md만 있는 정상 레포는 종전대로 통과 (오차단 0의 반대편).
$pd4 = Join-Path $work 'proj-pd4'; New-Item -ItemType Directory $pd4 -Force | Out-Null
"# plan`n- [ ] T1: work" | Set-Content (Join-Path $pd4 'plan.md')
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pd4 (Join-Path $pd4 'A.cs'))
Assert-Case -Name "plan판정: 루트 plan.md만 있는 정상 레포는 통과 (PD4, 무회귀)" -R $r -ExpectExit 0

# --- TE: 시스템 임시 폴더 예외 분기 (두 게이트 공통 — 종전 스위트 사각) ---
# 반드시 '흔적 없는' transcript를 주입한다 — 미주입이면 fail-open으로 exit 0이 되어
#   temp 예외를 검증하지 않고도 green이 된다(거짓 green).
$teDir = Join-Path $iso 'te-scratch'; New-Item -ItemType Directory $teDir -Force | Out-Null
$r = Invoke-Hook 'guard-write.ps1' (New-PlanWriteJson $teDir (Join-Path $teDir 'plan.md') "# plan`n- [ ] T1: x" $trPlanNo)
Assert-Case -Name "plan게이트: 시스템 임시폴더 plan.md Write 통과 — temp 예외 (TE1)" -R $r -ExpectExit 0
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $teDir (Join-Path $teDir 'AGENTS.md') 'Write' @{} @{ transcript_path = $trPlanNo })
Assert-Case -Name "AGENTS게이트: 시스템 임시폴더 AGENTS.md 신규 Write 통과 — temp 예외 (TE2)" -R $r -ExpectExit 0

# --- PX: PLAN-EXEMPT 면제 판정 (plan 존재 게이트) ---
# 표식은 어시스턴트 텍스트로 transcript 에 실린다 — 실제 경로와 같은 형태를 쓴다.
#   매칭 규칙은 「파일명 + 직속 부모 디렉터리 이름」이라 PX2/PX4 가 그 두 축을 각각 잰다.
$pxDir = Join-Path $work 'proj-exempt'
New-Item -ItemType Directory (Join-Path $pxDir 'src') -Force | Out-Null
New-Item -ItemType Directory (Join-Path $pxDir 'other') -Force | Out-Null
$trExempt = Join-Path $work 'tr-plan-exempt.jsonl'
(New-TranscriptLine -Type assistant -Text '[PLAN-EXEMPT] src/A.cs') | Set-Content $trExempt
$pxHit = Join-Path $pxDir 'src/A.cs'
$pxMiss = Join-Path $pxDir 'src/B.cs'
$pxSameName = Join-Path $pxDir 'other/A.cs'

# PX1 (양성): 표식에 적힌 파일은 plan 없이 통과
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir $pxHit 'Write' @{} @{ transcript_path = $trExempt })
Assert-Case -Name "면제: 표식에 적힌 파일은 plan 없이 통과 (PX1)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'
# PX2 (음성 — 파일명 축): 같은 표식이어도 거기 없는 파일은 차단
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir $pxMiss 'Write' @{} @{ transcript_path = $trExempt })
Assert-Case -Name "면제: 표식에 없는 파일은 차단 (PX2, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX3 (음성 — fail-closed): transcript 미제공이면 면제 없음. 작성 게이트의 fail-open(PG9)과
#   방향이 반대라는 것이 이 케이스의 요점이다 — '통과를 여는' 판정이라 안전측이 차단이다.
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir $pxHit)
Assert-Case -Name "면제: transcript 미제공은 면제 없음 — fail-closed (PX3, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX4 (음성 — 부모 디렉터리 축): 파일명은 같고 부모가 다르면 차단. 파일명 단독 매칭이었다면
#   여기서 오통과했을 것이므로, 이 케이스가 D2 의 '부모까지 본다'를 실증한다.
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir $pxSameName 'Write' @{} @{ transcript_path = $trExempt })
Assert-Case -Name "면제: 부모 디렉터리가 다른 동명 파일은 차단 (PX4, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'

# PX5·PX6·PX7 — 매칭 정밀도 축(회차 12 완료 리뷰 BLOCKER 2건). PX2·PX4 는 충돌하지 않는
#   이름을 골라 이 경계를 재지 않는다: '표식으로 오인되는 산문'과 '부분문자열 충돌'이 그것이다.
#   ⚠ 픽스처에 **레포의 실재 경로를 쓰지 않는다** — 마커 뒤에 실재 경로를 두면 이 파일을 읽는
#   것만으로 그 파일의 면제가 발급된다(완료 재리뷰 MAJOR). 'px' 접두의 가짜 이름으로 부분문자열
#   기하('px.cs' ⊂ 'px-guard.cs' · 'pxscr' ⊂ 'pxscripts')만 재현한다.
$pxScripts = Join-Path $pxDir 'pxscripts'
$pxScr = Join-Path $pxDir 'pxscr'
New-Item -ItemType Directory $pxScripts -Force | Out-Null
New-Item -ItemType Directory $pxScr -Force | Out-Null
$trProse = Join-Path $work 'tr-plan-exempt-prose.jsonl'
# 대괄호 없는 산문 — 이 판정을 grep 한 결과가 그대로 실린 형태다(경로 접두가 함께 붙는다).
(New-TranscriptLine -Type assistant -Text 'pxscripts/px-guard.cs:324:# PLAN-EXEMPT 면제 판정') | Set-Content $trProse
$trPrefix = Join-Path $work 'tr-plan-exempt-prefix.jsonl'
(New-TranscriptLine -Type assistant -Text '[PLAN-EXEMPT] pxscripts/px-guard.cs') | Set-Content $trPrefix

# PX5 (델타 음성 — 마커 축): 대괄호 없는 산문 줄은 표식이 아니다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trProse })
Assert-Case -Name "면제: 대괄호 없는 산문 줄은 표식이 아니다 (PX5, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX6 (델타 음성 — 파일명 완전 일치): 'px.cs' 는 'px-guard.cs' 의 부분문자열이다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px.cs') 'Write' @{} @{ transcript_path = $trPrefix })
Assert-Case -Name "면제: 표식 파일명의 부분문자열인 다른 파일은 차단 (PX6, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX7 (델타 음성 — 부모 완전 일치): 'pxscr' 은 'pxscripts' 의 부분문자열이다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScr 'px-guard.cs') 'Write' @{} @{ transcript_path = $trPrefix })
Assert-Case -Name "면제: 표식 부모의 부분문자열인 다른 디렉터리는 차단 (PX7, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX8 (양성 — 위 셋의 해소 대조): 같은 표식으로 '적힌 그 파일'은 그대로 통과한다.
#   음성만 늘리면 「좁히다가 다 막아 버린」 상태와 구분되지 않는다.
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trPrefix })
Assert-Case -Name "면제: 좁힌 뒤에도 표식에 적힌 그 파일은 통과 (PX8)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'

# PX9·PX10 — 루트 파일 축(완료 재리뷰 MAJOR). 절대 경로에서는 부모가 항상 차므로
#   「루트 파일은 파일명만」이 죽은 분기였다. 대상이 프로젝트 루트일 때만 파일명 단독을 인정한다.
$trRootOnly = Join-Path $work 'tr-plan-exempt-rootonly.jsonl'
(New-TranscriptLine -Type assistant -Text '[PLAN-EXEMPT] PxRoot.cs') | Set-Content $trRootOnly
# PX9 (양성): 프로젝트 루트 파일은 파일명만 적은 표식으로 통과
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxDir 'PxRoot.cs') 'Write' @{} @{ transcript_path = $trRootOnly })
Assert-Case -Name "면제: 루트 파일은 파일명만 적은 표식으로 통과 (PX9)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'
# PX10 (델타 음성): 같은 표식으로 하위 디렉터리의 동명 파일은 차단 — 흔한 이름이 어디서든
#   열리지 않게 하는 경계다.
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'PxRoot.cs') 'Write' @{} @{ transcript_path = $trRootOnly })
Assert-Case -Name "면제: 파일명만 적은 표식은 하위 디렉터리 동명 파일을 열지 않는다 (PX10, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX11 (양성 — 장식 허용): 백틱이 붙은 표식도 인정한다. 조용히 차단되면 사용자는
#   승인했는데도 막히는 것으로 보인다.
$trDeco = Join-Path $work 'tr-plan-exempt-deco.jsonl'
(New-TranscriptLine -Type assistant -Text '[PLAN-EXEMPT] `pxscripts/px-guard.cs`') | Set-Content $trDeco
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trDeco })
Assert-Case -Name "면제: 백틱 장식이 붙은 표식도 인정 (PX11)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'

# PX12·PX13 — 마커는 텍스트 줄의 시작이어야 한다(회차 13). transcript 한 줄은 JSON 객체
#   하나라 텍스트 내부 개행은 리터럴 \n 두 글자로 실린다 — 그 뒤이거나 text 필드 시작일 때만
#   표식으로 본다. 이 규칙을 *설명하는* 산문은 마커로 줄을 시작하지 않는다.
$trMid = Join-Path $work 'tr-plan-exempt-mid.jsonl'
(New-TranscriptLine -Type assistant -Text ('훅은 ' + [char]96 + '[PLAN-EXEMPT] pxscripts/px-guard.cs' + [char]96 + ' 형태의 표식을 읽습니다.')) | Set-Content $trMid
$trNl = Join-Path $work 'tr-plan-exempt-nl.jsonl'
(New-TranscriptLine -Type assistant -Text "바로 수정하겠습니다.`n[PLAN-EXEMPT] pxscripts/px-guard.cs") | Set-Content $trNl

# PX12 (델타 음성 — 줄 중간 마커): 실제 경로가 함께 있어도 산문 안이면 표식이 아니다.
#   회차 12의 매칭은 줄 어디서든 마커를 찾아 이 형태가 열렸다.
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trMid })
Assert-Case -Name "면제: 줄 중간 마커(산문)는 표식이 아니다 (PX12, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX13 (양성 — 개행 뒤 마커): 설명 문장 다음 줄에 단독으로 낸 표식은 인정한다.
#   PX1 계열이 재는 'text 필드 시작'과 다른 갈래라 둘 다 필요하다.
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trNl })
Assert-Case -Name "면제: 개행 뒤 단독 줄 표식은 통과 (PX13)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'

# PX14·PX15 — 마커 줄 **뒤에 내용이 더 있는** 양성(회차 13 완료 리뷰 MAJOR). PX13 은 마커가
#   메시지의 마지막 줄이라 이 축을 재지 못했다 — 뒤에 문장이 오면 토큰이 'path\n문장'이 되고
#   Windows 에서 \ 가 경로 구분자라 GetFileName 이 'n문장'을 돌려줘 정상 표식이 차단됐다.
$BT3 = [string][char]96 * 3
$trTrail = Join-Path $work 'tr-plan-exempt-trail.jsonl'
(New-TranscriptLine -Type assistant -Text "확인했습니다.`n[PLAN-EXEMPT] pxscripts/px-guard.cs`n바로 수정하겠습니다.") | Set-Content $trTrail
$trFence = Join-Path $work 'tr-plan-exempt-fence.jsonl'
# 발급 지시(`plan/references/interview.md`)가 표식을 펜스 코드블록으로 보여 준다 — 모델이 그대로
#   흉내 낸 형태가 차단되면, 사용자는 승인했는데도 막히고 그 이유가 어디에도 안 뜬다.
(New-TranscriptLine -Type assistant -Text ("바로 수정합니다.`n" + $BT3 + "`n[PLAN-EXEMPT] pxscripts/px-guard.cs`n" + $BT3)) | Set-Content $trFence

# PX14 (양성): 마커 줄 뒤에 문장이 더 있어도 통과
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trTrail })
Assert-Case -Name "면제: 마커 줄 뒤에 문장이 더 있어도 통과 (PX14)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'
# PX15 (양성): 펜스 코드블록 안의 표식도 통과
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trFence })
Assert-Case -Name "면제: 펜스 코드블록 안의 표식도 통과 (PX15)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'

# PX16~PX19 — 채널 축과 장식 축(회차 13 재리뷰 MAJOR 2건).
#   채널: 첫째 갈래(리터럴 \n)는 필드를 가리지 않으므로 줄에 "assistant" 를 요구하지 않으면
#     user·tool_result 줄의 마커가 표식이 된다 — 그런 내용을 담은 파일을 읽는 것만으로 면제다.
#   장식: 모델은 마커를 볼드·백틱으로 감싸는 습관이 있다(이 회차 실측에서 ** 접두 10건).
#     허용하지 않으면 승인받은 표식이 조용히 차단되고 사용자는 이유를 알 수 없다.
$trUser = Join-Path $work 'tr-plan-exempt-user.jsonl'
(New-TranscriptLine -Type user -Text "확인.`n[PLAN-EXEMPT] pxscripts/px-guard.cs") | Set-Content $trUser
$trToolRes = Join-Path $work 'tr-plan-exempt-toolres.jsonl'
# tool_result 는 헬퍼가 만들지 않는 형태라 리터럴로 쓴다(파일을 cat 한 결과가 실린 모양).
('{""type"":""user"",""message"":{""content"":[{""type"":""tool_result"",""content"":""파일:\\n[PLAN-EXEMPT] pxscripts/px-guard.cs""}]}}') | Set-Content $trToolRes
$trBullet = Join-Path $work 'tr-plan-exempt-bullet.jsonl'
(New-TranscriptLine -Type assistant -Text "확인.`n- [PLAN-EXEMPT] pxscripts/px-guard.cs") | Set-Content $trBullet
$trBold = Join-Path $work 'tr-plan-exempt-bold.jsonl'
(New-TranscriptLine -Type assistant -Text "확인.`n**[PLAN-EXEMPT]** pxscripts/px-guard.cs") | Set-Content $trBold

# PX16 (델타 음성): user 줄의 마커는 표식이 아니다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trUser })
Assert-Case -Name "면제: user 줄의 마커는 표식이 아니다 (PX16, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX17 (델타 음성): tool_result 줄 — 파일을 읽은 결과로는 면제가 발급되지 않는다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trToolRes })
Assert-Case -Name "면제: tool_result 줄의 마커는 표식이 아니다 (PX17, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX18 (양성): 불릿 접두가 붙은 표식도 인정
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trBullet })
Assert-Case -Name "면제: 불릿 접두가 붙은 표식도 인정 (PX18)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'
# PX19 (양성): 볼드로 감싼 마커도 인정
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trBold })
Assert-Case -Name "면제: 볼드로 감싼 마커도 인정 (PX19)" -R $r -ExpectExit 0 -ExpectContains 'PLAN-EXEMPT'

# PX20 — 채널 조건의 우회 시도(회차 13 3차). 부분문자열 검사였다면 user 줄이 본문에
#   "type":"assistant" 를 언급하는 것만으로 통과했다 — JSON 안에서 그 언급은 이스케이프되므로
#   (?<!\\) 로 배제한다. 실측에서 이 형태가 든 줄이 실제 transcript 에 6건 있었다.
$trFakeChan = Join-Path $work 'tr-plan-exempt-fakechan.jsonl'
('{""type"":""user"",""message"":{""content"":""스키마는 \\\\""type\\\\"":\\\\""assistant\\\\"" 입니다.\\n[PLAN-EXEMPT] pxscripts/px-guard.cs""}}') | Set-Content $trFakeChan
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trFakeChan })
Assert-Case -Name "면제: 본문에 assistant 를 언급한 user 줄도 표식이 아니다 (PX20, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'

# PX21~PX23 — 채널을 assistant 줄이 아니라 **text 필드 구간**으로 한정한 축(회차 13 3차 리뷰 BLOCKER).
#   thinking·tool_use input·sidechain 은 전부 assistant 줄이라 줄 수준 조건만으로는 통과했다 —
#   모델이 속으로 떠올린 마커나 쓰려는 파일 내용이 게이트를 열었다.
$trThink = Join-Path $work 'tr-plan-exempt-thinking.jsonl'
('{""type"":""assistant"",""message"":{""content"":[{""type"":""thinking"",""thinking"":""메모.\\n[PLAN-EXEMPT] pxscripts/px-guard.cs""}]}}') | Set-Content $trThink
$trToolUse = Join-Path $work 'tr-plan-exempt-tooluse.jsonl'
('{""type"":""assistant"",""message"":{""content"":[{""type"":""tool_use"",""name"":""Write"",""input"":{""content"":""문서.\\n[PLAN-EXEMPT] pxscripts/px-guard.cs""}}]}}') | Set-Content $trToolUse
$trSide = Join-Path $work 'tr-plan-exempt-sidechain.jsonl'
('{""type"":""assistant"",""isSidechain"":true,""message"":{""content"":[{""type"":""text"",""text"":""확인.\\n[PLAN-EXEMPT] pxscripts/px-guard.cs""}]}}') | Set-Content $trSide

# PX21 (델타 음성): thinking 필드 — 사용자가 보지도 못한 텍스트로 면제가 발급되지 않는다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trThink })
Assert-Case -Name "면제: thinking 필드의 마커는 표식이 아니다 (PX21, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX22 (델타 음성): tool_use input — 쓰려는 파일 내용이 자기 게이트를 열지 않는다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trToolUse })
Assert-Case -Name "면제: tool_use input 의 마커는 표식이 아니다 (PX22, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
# PX23 (델타 음성): sidechain — 서브에이전트가 낸 표식은 사용자 승인이 아니다
$r = Invoke-Hook 'guard-write.ps1' (New-WriteJson $pxDir (Join-Path $pxScripts 'px-guard.cs') 'Write' @{} @{ transcript_path = $trSide })
Assert-Case -Name "면제: sidechain 줄의 마커는 표식이 아니다 (PX23, 델타 음성)" -R $r -ExpectExit 2 -ExpectContains '코드 변경 전에 plan이 필요합니다'
}   # ---- §2c 게이트 끝 ----

