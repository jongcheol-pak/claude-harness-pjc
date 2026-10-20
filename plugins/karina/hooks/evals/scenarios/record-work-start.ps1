# scenarios/record-work-start.ps1 — record-work-start 시나리오 (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook)와 공유 변수($iso·$pluginRoot)를 그대로 쓴다.
# 무엇을 재는가: 기록·주입 2이벤트(Skill 도구·슬래시 직접 입력) · 이름 두 형태 · chain-plan 의 plan 시각 동반 ·
#   덮어쓰기 · hookEventName · sid 정규화 · 배선(hooks.json matcher) · 침묵 3경로. 판정 근거는
#   `plugins/karina/scripts/rules/work-start-rationale.md` 다.
# 세션 id 를 케이스마다 다르게 쓴다 — 상태 파일이 세션 단위라 앞 케이스의 기록이 뒤 케이스를 오염시키지 않게 한다.
if (Test-HookSelected @('record-work-start')) {

$rwState = Join-Path $iso '.claude/.state/work-start'
$rwTimeRx = '\d{4}-\d{2}-\d{2} \d{2}:\d{2}'
function New-RwSkillJson([string]$sid, [string]$skill) {
    return (@{ session_id = $sid; hook_event_name = 'PreToolUse'; tool_name = 'Skill'; tool_input = @{ skill = $skill } } | ConvertTo-Json -Compress)
}
function New-RwUpeJson([string]$sid, [string]$cmd) {
    return (@{ session_id = $sid; hook_event_name = 'UserPromptExpansion'; command_name = $cmd; command_args = ''; prompt = '/' + $cmd } | ConvertTo-Json -Compress)
}
function Read-RwState([string]$file) {
    $p = Join-Path $rwState $file
    if (-not (Test-Path -LiteralPath $p)) { return @{ code = 0; out = 'state=none' } }
    $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{ code = 0; out = "plan=[$($j.plan)] chain=[$($j.'chain-plan')]" }
}
function Get-RwContext([hashtable]$R) {
    try { $o = $R.out | ConvertFrom-Json -ErrorAction Stop } catch { return @{ code = $R.code; out = 'not-json' } }
    return @{ code = $R.code; out = "event=$($o.hookSpecificOutput.hookEventName) ctx=$($o.hookSpecificOutput.additionalContext)" }
}

# ---- 기록·주입 ----
$r = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw-s1' 'karina:plan')
Assert-Case -Name "record-work-start: Skill karina:plan 이 시작 줄을 주입한다" -R (Get-RwContext $r) -ExpectExit 0 -ExpectContains 'ctx=[karina 작업 시작] karina:plan 20'
Assert-Case -Name "record-work-start: Skill karina:plan 이 plan 키를 시각 서식으로 쓴다" -R (Read-RwState 'rw-s1.json') -ExpectContains 'plan=[20'
$st = Read-RwState 'rw-s1.json'
Assert-Case -Name "record-work-start: 기록 시각이 YYYY-MM-DD HH:mm 서식이다" -R @{ code = 0; out = "match=$($st.out -match ('plan=\[' + $rwTimeRx + '\]'))" } -ExpectContains 'match=True'

$r = Invoke-Hook 'record-work-start.ps1' (New-RwUpeJson 'rw-u1' 'plan')
Assert-Case -Name "record-work-start: 슬래시 plan(무접두)도 주입한다" -R (Get-RwContext $r) -ExpectExit 0 -ExpectContains 'ctx=[karina 작업 시작] karina:plan 20'
$r = Invoke-Hook 'record-work-start.ps1' (New-RwUpeJson 'rw-u2' 'karina:plan')
Assert-Case -Name "record-work-start: 슬래시 karina:plan 도 주입한다" -R (Get-RwContext $r) -ExpectExit 0 -ExpectContains 'ctx=[karina 작업 시작] karina:plan 20'
$r = Invoke-Hook 'record-work-start.ps1' (New-RwUpeJson 'rw-u3' 'chain-plan')
Assert-Case -Name "record-work-start: 슬래시 chain-plan(무접두)도 주입한다" -R (Get-RwContext $r) -ExpectExit 0 -ExpectContains 'ctx=[karina 작업 시작] karina:chain-plan 20'
$r = Invoke-Hook 'record-work-start.ps1' (New-RwUpeJson 'rw-u4' 'karina:chain-plan')
Assert-Case -Name "record-work-start: 슬래시 karina:chain-plan 도 주입한다" -R (Get-RwContext $r) -ExpectExit 0 -ExpectContains 'ctx=[karina 작업 시작] karina:chain-plan 20'

# ---- hookEventName 은 받은 이벤트 ----
$r = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw-e1' 'karina:plan')
Assert-Case -Name "record-work-start: PreToolUse 로 받으면 hookEventName 이 PreToolUse" -R (Get-RwContext $r) -ExpectContains 'event=PreToolUse ctx='
$r = Invoke-Hook 'record-work-start.ps1' (New-RwUpeJson 'rw-e2' 'karina:plan')
Assert-Case -Name "record-work-start: UserPromptExpansion 으로 받으면 hookEventName 이 UserPromptExpansion" -R (Get-RwContext $r) -ExpectContains 'event=UserPromptExpansion ctx='

# ---- chain-plan 은 이 세션 plan 시각을 함께 싣는다 ----
$null = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw-c1' 'karina:plan')
$r = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw-c1' 'karina:chain-plan')
Assert-Case -Name "record-work-start: chain-plan 발동이 이 세션 plan 시각을 함께 싣는다" -R (Get-RwContext $r) -ExpectContains ' · karina:plan 20'
Assert-Case -Name "record-work-start: chain-plan 발동 뒤 두 키가 모두 남는다" -R (Read-RwState 'rw-c1.json') -ExpectContains 'chain=[20' -ExpectNotContains 'plan=[]'
$r = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw-c2' 'karina:chain-plan')
Assert-Case -Name "record-work-start: plan 기록이 없으면 chain-plan 시각만 싣는다" -R (Get-RwContext $r) -ExpectContains 'ctx=[karina 작업 시작] karina:chain-plan 20' -ExpectNotContains 'karina:plan'

# ---- 덮어쓰기 — 상태 파일은 늘 마지막 발동 값이다 ----
New-Item -ItemType Directory -Path $rwState -Force | Out-Null
'{"plan":"2000-01-01 00:00"}' | Set-Content -LiteralPath (Join-Path $rwState 'rw-o1.json') -Encoding UTF8
$r = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw-o1' 'plan')
Assert-Case -Name "record-work-start: 재발동이 옛 plan 시각을 덮어쓴다" -R (Read-RwState 'rw-o1.json') -ExpectContains 'plan=[20' -ExpectNotContains '2000-01-01'

# ---- sid 정규화 — session-context 가 같은 식으로 파일을 찾는다 ----
$r = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw/n1:x' 'karina:plan')
Assert-Case -Name "record-work-start: 특수문자 sid 는 [^A-Za-z0-9._-] 를 _ 로 바꾼 파일명에 쓴다" -R (Read-RwState 'rw_n1_x.json') -ExpectContains 'plan=[20'

# ---- 침묵 ----
$r = Invoke-Hook 'record-work-start.ps1' (New-RwSkillJson 'rw-n2' 'karina:implement')
Assert-Case -Name "record-work-start: Skill karina:implement 는 무출력" -R $r -ExpectExit 0 -ExpectSilent $true
Assert-Case -Name "record-work-start: Skill karina:implement 는 상태 파일을 만들지 않는다" -R (Read-RwState 'rw-n2.json') -ExpectContains 'state=none'
$r = Invoke-Hook 'record-work-start.ps1' (@{ session_id = 'rw-n3'; hook_event_name = 'PreToolUse'; tool_name = 'Bash'; tool_input = @{ command = 'ls' } } | ConvertTo-Json -Compress)
Assert-Case -Name "record-work-start: Skill 이 아닌 도구는 무출력" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'record-work-start.ps1' 'not json'
Assert-Case -Name "record-work-start: 깨진 stdin 은 exit 0 무출력" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'record-work-start.ps1' (@{ hook_event_name = 'PreToolUse'; tool_name = 'Skill'; tool_input = @{ skill = 'karina:plan' } } | ConvertTo-Json -Compress)
Assert-Case -Name "record-work-start: session_id 가 없으면 exit 0 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- 배선 — 위 케이스는 스크립트에 JSON 을 직접 넣어 hooks.json matcher 를 거치지 않는다 ----
#   글자·|만으로 된 matcher 는 「정확 일치 목록」이라 정확 일치로 흉내 낸다(loop-continue 시나리오의 배선 케이스와 같은 방식).
$rwHooks = Get-Content -LiteralPath (Join-Path $pluginRoot 'hooks/hooks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$rwUpe = $rwHooks.hooks.UserPromptExpansion | Where-Object { ($_.hooks.command -join ' ') -match 'record-work-start' } | Select-Object -First 1
$rwUpeMatcher = [string]$rwUpe.matcher
$rwExactOnly = $rwUpeMatcher -match '^[A-Za-z0-9_ ,|-]*$'
$rwHit = @('karina:plan', 'plan', 'karina:chain-plan', 'chain-plan', 'karina:implement', 'implement' | Where-Object {
    if (-not $rwUpe) { $false }
    elseif ($rwExactOnly) { ($rwUpeMatcher -split '[|,]' | ForEach-Object { $_.Trim() }) -contains $_ }
    else { $_ -match $rwUpeMatcher }
})
Assert-Case -Name "record-work-start: UserPromptExpansion matcher 가 plan·chain-plan 두 형태씩 받고 implement 는 받지 않는다" -R @{ code = 0; out = "hits=$($rwHit -join ',')" } -ExpectContains 'hits=karina:plan,plan,karina:chain-plan,chain-plan' -ExpectNotContains 'implement'
$rwPre = @($rwHooks.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Skill' -and (($_.hooks.command -join ' ') -match 'record-work-start') })
Assert-Case -Name "record-work-start: PreToolUse Skill 블록이 이 스크립트를 부른다" -R @{ code = 0; out = "blocks=$($rwPre.Count)" } -ExpectContains 'blocks=1'

}
