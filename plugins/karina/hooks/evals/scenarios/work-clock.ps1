# scenarios/work-clock.ps1 — work-clock 시나리오 (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case)와 공유 변수($pluginRoot)를 그대로 쓴다.
# 무엇을 재는가: 소요 출력 2경로(하루 넘김·날짜 경계) · 현재 시각만 1경로 · 실패 2경로(파싱 불가·미래 시작) ·
#   정상 경로에 ERROR 가 없음 · stdin 을 기다리지 않음. 출력 서식의 근거는 스크립트 머리 주석이다.
# 대상은 hook 이 아니라 스킬 로컬 헬퍼라 `Invoke-Hook`(stdin JSON 1개 · scripts/ 기준)을 쓰지 않고
#   인자를 넘기는 자식 pwsh 를 직접 띄운다.
if (Test-HookSelected @('work-clock')) {

$wcPath = Join-Path $pluginRoot 'skills/implement/scripts/work-clock.ps1'
function Invoke-WorkClock([string[]]$ClockArgs) {
    Assert-EvalParentAlive
    $out = pwsh -NoProfile -ExecutionPolicy Bypass -File $wcPath @ClockArgs 2>&1
    return @{ code = $LASTEXITCODE; out = (($out | Out-String)).Trim() }
}

# ---- 소요 2경로 ----
$r = Invoke-WorkClock @('-Since', '2026-10-15 09:00', '-Now', '2026-10-16 10:35')
Assert-Case -Name "work-clock: 하루를 넘긴 소요를 시간·분으로 낸다" -R $r -ExpectExit 0 -ExpectContains 'karina-clock 2026-10-16 10:35 25h 35m'
$r = Invoke-WorkClock @('-Since', '2026-10-15 23:50', '-Now', '2026-10-16 00:10')
Assert-Case -Name "work-clock: 자정을 넘긴 소요를 낸다" -R $r -ExpectExit 0 -ExpectContains 'karina-clock 2026-10-16 00:10 0h 20m'

# ---- 현재 시각만 ----
$r = Invoke-WorkClock @('-Now', '2026-10-16 10:35')
Assert-Case -Name "work-clock: 인자가 -Now 뿐이면 현재 시각 한 줄만 낸다" -R @{ code = $r.code; out = "[$($r.out)]" } -ExpectExit 0 -ExpectContains '[karina-clock 2026-10-16 10:35]'

# ---- 실패 2경로 — 실패해도 현재 시각을 같은 줄에 낸다 ----
$r = Invoke-WorkClock @('-Since', 'garbage', '-Now', '2026-10-16 10:35')
Assert-Case -Name "work-clock: 시작을 읽지 못하면 현재 시각과 ERROR 를 내고 exit 1" -R $r -ExpectExit 1 -ExpectContains 'karina-clock 2026-10-16 10:35 ERROR '
$r = Invoke-WorkClock @('-Since', '2026-10-17 09:00', '-Now', '2026-10-16 10:35')
Assert-Case -Name "work-clock: 시작이 현재보다 뒤면 ERROR 를 내고 exit 1" -R $r -ExpectExit 1 -ExpectContains 'karina-clock 2026-10-16 10:35 ERROR '

# ---- 음성 짝 ----
$r = Invoke-WorkClock @('-Since', '2026-10-16 10:35', '-Now', '2026-10-16 10:35')
Assert-Case -Name "work-clock: 정상 경로(소요 0분)에는 ERROR 가 없다" -R $r -ExpectExit 0 -ExpectContains '0h 0m' -ExpectNotContains 'ERROR'
# stdin 을 읽는 구현이면 리다이렉트 없는 자식이 입력을 기다려 끝나지 않는다 — 시한 안에 끝나는지로 잰다.
$wcJob = Start-Job -ScriptBlock { param($p) pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Now '2026-10-16 10:35' } -ArgumentList $wcPath
$wcDone = Wait-Job $wcJob -Timeout 30
$wcOut = if ($wcDone) { (Receive-Job $wcJob | Out-String).Trim() } else { 'TIMEOUT' }
Remove-Job $wcJob -Force -ErrorAction SilentlyContinue
Assert-Case -Name "work-clock: stdin 을 기다리지 않고 끝난다" -R @{ code = 0; out = $wcOut } -ExpectContains 'karina-clock 2026-10-16 10:35' -ExpectNotContains 'TIMEOUT'

}
