# scenarios/session-end-cleanup-lib.ps1 — 고아 콘솔 프로세스 회수 시나리오 (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook)와 공유 변수($work·$iso)를 그대로 쓴다.
#
# 다른 시나리오와 다른 점: 이 시나리오는 hook에 stdin을 주입하는 대신 **헬퍼 함수를 직접 호출**한다.
#   회수 로직의 검증 대상이 판정(어떤 프로세스를 고아로 볼 것인가)이고, 그것은 실제 프로세스 없이
#   목 레코드로 닫히기 때문이다. **실제 프로세스를 만들지 않는다** — 프로세스는 격리 대상이 아니라
#   스위트가 실기계 상태에 의존하는 순간 결정성이 깨진다(eval-common이 수집 경로를 억제하는 것과 같은 이유).
#   SessionEnd hook만 stdin 주입으로 검증한다(그쪽은 hook 계약 확인이라 Invoke-Hook이 맞다).
if (Test-HookSelected @('session-end-cleanup')) {

# 경로는 eval-common이 계산해 둔 공유 변수를 쓴다 — 여기서 상대 순회로 재계산하면
# 디렉터리 구조가 바뀔 때 이 시나리오만 조용히 깨진다(다른 시나리오도 $scriptsDir를 쓴다).
. (Join-Path $scriptsDir 'session-end-cleanup-lib.ps1')

$opcNow = Get-Date
$opcSid = (Get-Process -Id $PID).SessionId

# ---- 판정 8종 (Select-OrphanProcesses — 순수 함수) ----
# ParentStartTime = $null 이 부모 부재(고아)를 뜻한다. 부모 조회 실패도 보수적으로 여기로 온다.
$opcMock = @(
    @{ Id=201; Name='more.com';    SessionId=$opcSid;     StartTime=$opcNow.AddMinutes(-10); ParentId=8001; ParentStartTime=$null;                    CpuSec=100 }  # 고아 more.com
    @{ Id=202; Name='find.exe';    SessionId=$opcSid;     StartTime=$opcNow.AddMinutes(-10); ParentId=8002; ParentStartTime=$null;                    CpuSec=200 }  # 고아 find.exe
    @{ Id=203; Name='find.exe';    SessionId=$opcSid;     StartTime=$opcNow.AddMinutes(-10); ParentId=8003; ParentStartTime=$opcNow.AddMinutes(-30);  CpuSec=0   }  # 부모 생존
    @{ Id=204; Name='more.com';    SessionId=$opcSid;     StartTime=$opcNow.AddMinutes(-10); ParentId=8004; ParentStartTime=$opcNow.AddMinutes(-2);   CpuSec=50  }  # PID 재사용
    @{ Id=205; Name='more.com';    SessionId=$opcSid + 7; StartTime=$opcNow.AddMinutes(-10); ParentId=8005; ParentStartTime=$null;                    CpuSec=0   }  # 타 세션
    @{ Id=206; Name='notepad.exe'; SessionId=$opcSid;     StartTime=$opcNow.AddMinutes(-10); ParentId=8006; ParentStartTime=$null;                    CpuSec=0   }  # 대상 아닌 이름
)
$opcSel = @(Select-OrphanProcesses -Records $opcMock -SessionId $opcSid)
$opcGot = (($opcSel | ForEach-Object { $_.Id }) | Sort-Object) -join ','
Assert-Case -Name "orphan-cleanup: 고아·PID재사용만 선택(두 이름 혼재)" `
    -R @{ code = 0; out = $opcGot } -ExpectExit 0 -ExpectContains '201,202,204'
Assert-Case -Name "orphan-cleanup: 부모 생존·타 세션·대상 외 이름은 제외" `
    -R @{ code = 0; out = $opcGot } -ExpectExit 0 -ExpectNotContains '203'

$opcEmpty = @(Select-OrphanProcesses -Records @() -SessionId $opcSid)
Assert-Case -Name "orphan-cleanup: 빈 입력 → 0건" `
    -R @{ code = 0; out = "count=$($opcEmpty.Count)" } -ExpectExit 0 -ExpectContains 'count=0'
$opcNull = @(Select-OrphanProcesses -Records $null -SessionId $opcSid)
Assert-Case -Name "orphan-cleanup: null 입력 → 0건" `
    -R @{ code = 0; out = "count=$($opcNull.Count)" } -ExpectExit 0 -ExpectContains 'count=0'

# ---- 억제 (D11) — 실기계 수집 경로만 멈추고 주입은 통과 ----
# eval-common이 CLAUDE_HARNESS_NO_PROC_CLEANUP=1을 세워 둔 상태가 이 스위트의 기본값이다.
$opcSup = Invoke-OrphanProcessCleanup -Hook 'golden-suppress'
Assert-Case -Name "orphan-cleanup: 억제 시 수집 경로 즉시 반환" `
    -R @{ code = 0; out = "suppressed=$($opcSup.Suppressed) scanned=$($opcSup.Scanned)" } `
    -ExpectExit 0 -ExpectContains 'suppressed=True scanned=0'

# ---- 주입 + DryRun (D15) — 회수 카운트와 이벤트 적재 ----
$opcDry = Invoke-OrphanProcessCleanup -Hook 'golden-dry' -Records $opcMock -DryRun
Assert-Case -Name "orphan-cleanup: 억제 중에도 주입 경로는 동작(회수 3건)" `
    -R @{ code = 0; out = "suppressed=$($opcDry.Suppressed) killed=$($opcDry.Killed)" } `
    -ExpectExit 0 -ExpectContains 'suppressed=False killed=3'

# 적재는 격리 홈($iso)의 hook-events jsonl에 쌓인다 — DryRun은 rule을 분리해 실회수 기록과 섞이지 않는다.
$opcLogDir = Join-Path $iso '.claude/.state/hook-events'
$opcLines = @()
if (Test-Path -LiteralPath $opcLogDir) {
    $opcLines = @(Get-ChildItem -LiteralPath $opcLogDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Encoding UTF8 })
}
$opcDryCount = @($opcLines | Where-Object { $_ -match 'orphan-process-dryrun' -and $_ -match 'golden-dry' }).Count
Assert-Case -Name "orphan-cleanup: DryRun 이벤트가 회수 건수만큼 적재" `
    -R @{ code = 0; out = "dry=$opcDryCount" } -ExpectExit 0 -ExpectContains 'dry=3'
$opcHookOk = @($opcLines | Where-Object { $_ -match '"hook"\s*:\s*"golden-dry"' }).Count
Assert-Case -Name "orphan-cleanup: hook 필드가 비지 않음(리포트에서 버려지지 않는다)" `
    -R @{ code = 0; out = "hook=$opcHookOk" } -ExpectExit 0 -ExpectContains 'hook=3'

# ---- Unkillable 계상 + 마커 (D18) ----
# System(PID 4)은 종료되지 않는다 — Stop-Process가 실패하고 CIM 재조회에서는 계속 존재하므로
# "성공 반환을 소멸의 근거로 쓰지 않는다"는 경로가 그대로 발화한다. 실제로 죽는 프로세스를 쓰면
# 스위트가 실기계 상태를 바꾸게 되므로 죽지 않는 것을 고른다.
$opcSys = Get-CimInstance Win32_Process -Filter "ProcessId=4" -ErrorAction SilentlyContinue
if ($opcSys) {
    $opcDead = @(@{ Id=4; Name='find.exe'; SessionId=$opcSid; StartTime=$opcSys.CreationDate; ParentId=9999; ParentStartTime=$null; CpuSec=0 })
    $opcUn = Invoke-OrphanProcessCleanup -Hook 'golden-unkill' -Records $opcDead
    Assert-Case -Name "orphan-cleanup: 소멸 실패는 Killed가 아니라 Unkillable" `
        -R @{ code = 0; out = "killed=$($opcUn.Killed) unkillable=$($opcUn.Unkillable)" } `
        -ExpectExit 0 -ExpectContains 'killed=0 unkillable=1'

    $opcMarkerDir = Join-Path $iso '.claude/.state/orphan-unkillable'
    $opcMk = if (Test-Path -LiteralPath $opcMarkerDir) { @(Get-ChildItem -LiteralPath $opcMarkerDir -File -ErrorAction SilentlyContinue).Count } else { 0 }
    Assert-Case -Name "orphan-cleanup: 마커 생성" `
        -R @{ code = 0; out = "marker=$opcMk" } -ExpectExit 0 -ExpectContains 'marker=1'

    # 마커가 있으면 다음 회수에서 그 PID를 건너뛴다 — 죽지 않는 프로세스에 kill을 반복하지 않기 위함.
    $opcUn2 = Invoke-OrphanProcessCleanup -Hook 'golden-unkill' -Records $opcDead
    Assert-Case -Name "orphan-cleanup: 마커 이후 재시도 억제" `
        -R @{ code = 0; out = "killed=$($opcUn2.Killed) unkillable=$($opcUn2.Unkillable)" } `
        -ExpectExit 0 -ExpectContains 'killed=0 unkillable=0'
}

# ---- SessionEnd hook 계약 (stdin 주입) ----
# 회수 사실은 이벤트 로그에만 남으므로 이 hook은 어떤 사유로 불려도 무출력·exit 0이어야 한다.
foreach ($opcReason in @('clear', 'logout', 'prompt_input_exit', 'other')) {
    $opcJson = @{ hook_event_name = 'SessionEnd'; session_id = 'golden'; cwd = $work; session_end_reason = $opcReason } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'session-end-cleanup.ps1' $opcJson
    Assert-Case -Name "session-end-cleanup: $opcReason → exit 0 무출력" -R $r -ExpectExit 0 -ExpectSilent $true
}

}
