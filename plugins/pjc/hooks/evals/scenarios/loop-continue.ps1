# scenarios/loop-continue.ps1 — loop-continue 시나리오 (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook)와 공유 변수($work·$iso)를 그대로 쓴다.
# 무엇을 재는가: 발동 마커 3경로 · 주입 1경로 · 침묵 7경로 · 집합 변경 재주입. 판정 근거는
#   `plugins/pjc/scripts/rules/loop-continue-rationale.md` 의 §2·§6 이다.
# 세션 id 를 케이스마다 다르게 쓴다 — 마커·카운터가 세션 단위라 앞 케이스의 상태가 뒤 케이스를 오염시키지 않게 한다.
if (Test-HookSelected @('loop-continue')) {

$lcState = Join-Path $iso '.claude/.state/loop-continue'
$lcProj = Join-Path $work 'lcproj'; New-Item -ItemType Directory $lcProj -Force | Out-Null
$lcPlan = Join-Path $lcProj 'plan.md'
"- [x] **T1-1** 끝`n- [ ] **T2-1** 남음`n- [/] **T2-2** 진행 중" | Set-Content -LiteralPath $lcPlan -Encoding UTF8
$lcDone = Join-Path $work 'lcdone'; New-Item -ItemType Directory $lcDone -Force | Out-Null
"- [x] **T1-1** 끝" | Set-Content -LiteralPath (Join-Path $lcDone 'plan.md') -Encoding UTF8

function New-LcSkillJson([string]$sid, [string]$skill) {
    return (@{ session_id = $sid; hook_event_name = 'PreToolUse'; tool_name = 'Skill'; tool_input = @{ skill = $skill } } | ConvertTo-Json -Compress)
}
function New-LcStopJson([string]$sid, [string]$cwd, [hashtable]$extra = @{}) {
    $o = @{ session_id = $sid; hook_event_name = 'Stop'; cwd = $cwd; stop_hook_active = $false; background_tasks = @() }
    foreach ($k in $extra.Keys) { $o[$k] = $extra[$k] }
    return ($o | ConvertTo-Json -Compress -Depth 4)
}
function Test-LcMarker([string]$sid) {
    return @{ code = 0; out = "marker=$(Test-Path -LiteralPath (Join-Path $lcState ($sid + '.active')))" }
}

# ---- 발동 마커 3경로 ----
$r = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-m1' 'pjc:implement')
Assert-Case -Name "loop-continue: Skill pjc:implement 는 무출력" -R $r -ExpectExit 0 -ExpectSilent $true
Assert-Case -Name "loop-continue: Skill pjc:implement 가 마커를 세운다" -R (Test-LcMarker 'lc-m1') -ExpectContains 'marker=True'
$r = Invoke-Hook 'loop-continue.ps1' (@{ session_id = 'lc-m2'; hook_event_name = 'UserPromptExpansion'; command_name = 'pjc:implement' } | ConvertTo-Json -Compress)
Assert-Case -Name "loop-continue: /pjc:implement 직접 입력이 마커를 세운다" -R (Test-LcMarker 'lc-m2') -ExpectContains 'marker=True'
$r = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-m3' 'pjc:record-project-fact')
Assert-Case -Name "loop-continue: 다른 스킬은 마커를 세우지 않는다" -R (Test-LcMarker 'lc-m3') -ExpectContains 'marker=False'

# ---- 주입 1경로 ----
$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-i1' 'implement')
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-i1' $lcProj)
Assert-Case -Name "loop-continue: 마커+미완이면 additionalContext 로 주입" -R $r -ExpectExit 0 -ExpectContains '"additionalContext"'
Assert-Case -Name "loop-continue: 주입 안내가 미완 ID 를 적는다" -R $r -ExpectExit 0 -ExpectContains 'T2-1, T2-2'
Assert-Case -Name "loop-continue: 완료 task 는 안내에 없다" -R $r -ExpectExit 0 -ExpectNotContains 'T1-1'

# ---- 침묵 경로 ----
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s1' $lcProj)
Assert-Case -Name "loop-continue: 마커 없으면 침묵" -R $r -ExpectExit 0 -ExpectSilent $true

$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-s2' 'pjc:implement')
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s2' $lcDone)
Assert-Case -Name "loop-continue: 미완 0 이면 침묵" -R $r -ExpectExit 0 -ExpectSilent $true

$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-s3' 'pjc:implement')
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s3' $lcProj @{ stop_hook_active = $true })
Assert-Case -Name "loop-continue: stop_hook_active 면 침묵" -R $r -ExpectExit 0 -ExpectSilent $true

$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-s4' 'pjc:implement')
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s4' $lcProj @{ background_tasks = @(@{ id = 't1'; type = 'shell'; status = 'running' }) })
Assert-Case -Name "loop-continue: background_tasks 가 있으면 침묵" -R $r -ExpectExit 0 -ExpectSilent $true

$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-s5' 'pjc:implement')
$null = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s5' $lcProj)
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s5' $lcProj)
Assert-Case -Name "loop-continue: 같은 집합 2회째는 주입(상한 2)" -R $r -ExpectExit 0 -ExpectContains '"additionalContext"'
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s5' $lcProj)
Assert-Case -Name "loop-continue: 같은 집합 3회째는 침묵" -R $r -ExpectExit 0 -ExpectSilent $true

$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-s6' 'pjc:implement')
$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-s6' 'pjc:plan')
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-s6' $lcProj)
Assert-Case -Name "loop-continue: pjc:plan 발동 뒤에는 침묵(마커 제거)" -R $r -ExpectExit 0 -ExpectSilent $true

$r = Invoke-Hook 'loop-continue.ps1' 'not json {'
Assert-Case -Name "loop-continue: 잘못된 stdin 은 침묵" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- 집합 변경 재주입 — 상한이 세션 전체가 아니라 미완 집합 단위임을 본다 ----
$lcProj2 = Join-Path $work 'lcproj2'; New-Item -ItemType Directory $lcProj2 -Force | Out-Null
"- [ ] **T1-1** a`n- [ ] **T1-2** b" | Set-Content -LiteralPath (Join-Path $lcProj2 'plan.md') -Encoding UTF8
$null = Invoke-Hook 'loop-continue.ps1' (New-LcSkillJson 'lc-c1' 'pjc:implement')
$null = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-c1' $lcProj2)
$null = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-c1' $lcProj2)
"- [x] **T1-1** a`n- [ ] **T1-2** b" | Set-Content -LiteralPath (Join-Path $lcProj2 'plan.md') -Encoding UTF8
$r = Invoke-Hook 'loop-continue.ps1' (New-LcStopJson 'lc-c1' $lcProj2)
Assert-Case -Name "loop-continue: 집합이 바뀌면 다시 주입" -R $r -ExpectExit 0 -ExpectContains 'T1-2'

}
