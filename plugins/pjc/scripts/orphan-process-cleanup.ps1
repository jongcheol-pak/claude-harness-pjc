# orphan-process-cleanup.ps1 — 고아 콘솔 프로세스 회수 (dot-source 전용, 로드 시 부작용 없음)
#
# 왜: Bash 도구의 시간 캡(10분)에 걸려 셸이 죽어도 그 자식 콘솔 프로세스는 함께 죽지 않는다
#   (Windows는 부모 종료 시 자식을 따라 죽이지 않고, MSYS 셸 강제 종료 시 신호도 전파되지 않는다).
#   결과로 남는 고아가 CPU를 상시 점유한다 — 2026-08-20 실측: more.com 4개가 각 74%,
#   find.exe 12개가 각 27%로 합계 코어 6개 상당을 먹고 있었다(누적 63.7 코어시간).
# 무엇을: 부모가 죽은 more.com·find.exe를 Stop/SessionStart/SessionEnd 시점에 회수한다.
#   살아 있는 셸이 쓰는 페이저·검색은 부모가 있으므로 대상이 아니다.
# 안전 계약:
#   ① 이 함수의 어떤 실패도 호출한 hook의 판정·출력에 영향을 주지 않는다(전 경로 fail-open).
#   ② 화면에 아무것도 쓰지 않는다 — 회수 사실은 hook-event-log에만 적재한다.
#      (session-context의 무출력 규약을 깨지 않기 위함이며, 골든의 ExpectSilent 케이스와도 무관해진다.)
#   ③ 5.1 호환 유지 — pwsh 7의 Process.Parent 속성을 쓰지 않고 CIM으로 부모를 조회한다.

# 회수 대상. 실측된 고아가 이 둘뿐이라 목록을 넓히지 않는다(오차단 위험만 늘고, 고아 조건이 이미 강한 가드다).
#
# ⚠ 이름이 두 벌인 이유 — **이름공간이 둘이고 규칙이 서로 다르다.**
#   · CIM(`Win32_Process.Name`)은 확장자를 그대로 준다      → 'more.com', 'find.exe'
#   · .NET(`Get-Process -Name` / `ProcessName`)은 **.exe만 벗긴다** → 'more.com', 'find'
#   실측: notepad은 ProcessName='Notepad'라 `-Name 'notepad.exe'`가 0건이고, more.com은 .com이
#   안 벗겨져 그대로 'more.com'이다. 한 배열을 양쪽에 쓰면 `find.exe`가 선검사에서 영원히 안 잡혀
#   **고아 find만 있을 때 조기 반환으로 회수가 통째로 죽는다**(F-7 BLOCKER 실측 — 어제 관측된 바로 그 상태).
$script:OrphanTargetNames  = @('more.com', 'find.exe')   # CIM 조회용
$script:OrphanPreScanNames = @('more.com', 'find')       # Get-Process 선검사용(.exe 벗겨짐)

# 골든 스위트는 hook을 실기계에서 돌리는데 프로세스는 격리 대상이 아니다.
# 이 변수가 서면 '실기계 수집' 경로만 즉시 반환한다 — 목 레코드 주입(-Records)은 억제하지 않는다.
# 전 호출을 억제하면 골든이 비억제 경로를 한 번도 밟지 못해 검증이 통째로 사라진다.
$script:OrphanCleanupSuppressVar = 'CLAUDE_HARNESS_NO_PROC_CLEANUP'

try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}

function Get-OrphanMarkerDir {
    # 죽지 않는 프로세스의 PID를 적어 다음 회수에서 건너뛰는 마커 디렉터리.
    $homeBase = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
    if ([string]::IsNullOrEmpty($homeBase)) { return $null }
    return (Join-Path $homeBase '.claude/.state/orphan-unkillable')
}

function Get-SystemBootStamp {
    # 마커 무효화 기준. 재부팅하면 그 PID들은 더 이상 존재하지 않으므로 마커도 함께 무의미해진다.
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return $os.LastBootUpTime.ToString('yyyyMMddHHmmss')
    } catch { return $null }
}

function Get-UnkillableMarkers {
    # 반환: 현재 부팅 세션에서 '죽지 않는다'고 확인된 PID 집합.
    # 부팅 시각이 다른 마커와 30일 초과 마커는 여기서 정리한다
    # (기존 .state 자산이 예외 없이 하우스키핑을 갖는 관례 — 마커 30일·jsonl 90일).
    param([string]$BootStamp)
    $set = @{}
    $dir = Get-OrphanMarkerDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -ErrorAction SilentlyContinue)) { return $set }
    try {
        $cutoff = (Get-Date).AddDays(-30)
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction Stop)) {
            $parts = $f.Name -split '_'
            $stale = ($f.LastWriteTime -lt $cutoff) -or
                     ($parts.Count -ne 2) -or
                     ($BootStamp -and $parts[1] -ne $BootStamp)
            if ($stale) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                continue
            }
            $set[$parts[0]] = $true
        }
    } catch {}
    return $set
}

function Add-UnkillableMarker {
    param([int]$ProcessId, [string]$BootStamp)
    if (-not $BootStamp) { return }   # 부팅 시각을 못 얻으면 마커 기능만 생략(회수 자체는 정상 진행)
    $dir = Get-OrphanMarkerDir
    if (-not $dir) { return }
    try {
        if (-not (Test-Path -LiteralPath $dir -ErrorAction SilentlyContinue)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -ItemType File -Path (Join-Path $dir ("$ProcessId" + '_' + $BootStamp)) -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

function Select-OrphanProcesses {
    <#
      순수 판정 — 프로세스 레코드 배열에서 회수 대상만 골라 반환한다.
      레코드: @{ Id; Name; SessionId; StartTime; ParentId; ParentStartTime }
        ParentStartTime = $null 이면 부모 부재(고아).
      판정: 대상 이름 AND 세션 일치 AND (부모 부재 OR 부모가 자식보다 나중에 생성됨).
      마지막 조건이 PID 재사용 방어다 — 죽은 부모의 PID가 재할당되면 '부모 생존'으로 오판해
      영영 회수되지 않는다.
    #>
    param(
        [object[]]$Records,
        [int]$SessionId,
        [hashtable]$SkipPids = $null
    )
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Records) { return @() }
    foreach ($r in $Records) {
        if ($null -eq $r) { continue }
        if (-not ($script:OrphanTargetNames -contains ([string]$r.Name).ToLowerInvariant())) { continue }
        if ([int]$r.SessionId -ne $SessionId) { continue }
        if ($SkipPids -and $SkipPids.ContainsKey([string]$r.Id)) { continue }
        $orphan = $false
        if ($null -eq $r.ParentStartTime) {
            $orphan = $true                                   # 부모 부재 — 조회 실패도 여기로 온다(보수적)
        } elseif ($r.ParentStartTime -gt $r.StartTime) {
            $orphan = $true                                   # 부모 PID가 재사용됨
        }
        if ($orphan) { $out.Add($r) }
    }
    return $out.ToArray()
}

function Get-OrphanProcessCandidates {
    <#
      수집 전담. 반환: @{ Records; CimQueried }
      선검사(Get-Process, 실측 평균 76ms)로 대상 이름이 하나도 없으면 CIM(평균 272ms)을 부르지 않는다 —
      평상시(고아 0)에 CIM 비용을 물지 않기 위한 조기 반환이다.
    #>
    $empty = @{ Records = @(); CimQueried = $false }
    try {
        $pre = @(Get-Process -Name $script:OrphanPreScanNames -ErrorAction SilentlyContinue)
        if ($pre.Count -eq 0) { return $empty }
    } catch { return $empty }

    $records = New-Object System.Collections.Generic.List[object]
    try {
        $filter = ($script:OrphanTargetNames | ForEach-Object { "Name='$_'" }) -join ' OR '
        $procs = @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction Stop)
        foreach ($p in $procs) {
            $parentStart = $null
            try {
                $par = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $p.ParentProcessId) -ErrorAction Stop
                if ($par) { $parentStart = $par.CreationDate }
            } catch {}
            $records.Add(@{
                Id              = [int]$p.ProcessId
                Name            = ([string]$p.Name).ToLowerInvariant()
                SessionId       = [int]$p.SessionId
                StartTime       = $p.CreationDate
                ParentId        = [int]$p.ParentProcessId
                ParentStartTime = $parentStart
                CpuSec          = [math]::Round(($p.KernelModeTime + $p.UserModeTime) / 10000000, 0)
            })
        }
    } catch {
        return @{ Records = $records.ToArray(); CimQueried = $true }
    }
    return @{ Records = $records.ToArray(); CimQueried = $true }
}

function Invoke-OrphanProcessCleanup {
    <#
      회수 본체. 화면 출력 없음(안전 계약 ②) — 회수 사실은 hook-event-log에만 적재한다.
        -Hook     적재할 hook 이름. 비면 report-hook-events가 엔트리를 버리므로 호출측이 반드시 준다.
        -Records  주면 수집을 건너뛰고 그 배열로 판정한다(골든 검증용 주입 seam).
        -DryRun   Stop-Process를 생략한다. 목 PID가 실재 프로세스와 겹칠 때 무관한 프로세스를
                  죽이는 것을 막는다. 이때 적재 rule을 분리해 실로그 오염도 막는다.
      반환: @{ Suppressed; Scanned; CimQueried; Killed; Unkillable; CpuSec }
    #>
    param(
        [string]$Hook = 'orphan-process-cleanup',
        [object[]]$Records = $null,
        [switch]$DryRun
    )
    $result = @{ Suppressed = $false; Scanned = 0; CimQueried = $false; Killed = 0; Unkillable = 0; CpuSec = 0 }
    try {
        # 안전 계약 ②를 이 파일만으로 자기완결시킨다 — 비종결 오류는 try/catch에 잡히지 않고 곧장
        # 오류 스트림으로 나가므로, 호출측이 SilentlyContinue를 세워 뒀을 것이라는 암묵 전제에 기대면
        # 새 호출자가 생기는 순간 session-context의 무출력 규약이 조용히 깨진다.
        # 함수 스코프 지역 설정이라 호출측 값은 복원 없이 그대로 유지된다.
        $ErrorActionPreference = 'SilentlyContinue'
        $injected = $PSBoundParameters.ContainsKey('Records')

        # 억제는 부작용이 있는 실기계 수집 경로에만 건다. 주입은 명시적 테스트 호출이라 대상이 아니다.
        if (-not $injected) {
            $suppress = [Environment]::GetEnvironmentVariable($script:OrphanCleanupSuppressVar)
            if (-not [string]::IsNullOrEmpty($suppress)) {
                $result.Suppressed = $true
                return $result
            }
        }

        $sessionId = 0
        try { $sessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId } catch {}

        if ($injected) {
            $cand = @{ Records = $Records; CimQueried = $false }
        } else {
            $cand = Get-OrphanProcessCandidates
        }
        $result.CimQueried = [bool]$cand.CimQueried
        $result.Scanned = @($cand.Records).Count
        if ($result.Scanned -eq 0) { return $result }

        $bootStamp = Get-SystemBootStamp
        $skip = Get-UnkillableMarkers -BootStamp $bootStamp
        $targets = @(Select-OrphanProcesses -Records $cand.Records -SessionId $sessionId -SkipPids $skip)
        if ($targets.Count -eq 0) { return $result }

        $rule = if ($DryRun) { 'orphan-process-dryrun' } else { 'orphan-process' }
        foreach ($t in $targets) {
            $gone = $false
            if ($DryRun) {
                $gone = $true
            } else {
                try { Stop-Process -Id $t.Id -Force -ErrorAction Stop } catch {}
                # Stop-Process의 성공 반환을 소멸의 근거로 쓰지 않는다 — 실측에서 성공을 반환하고도
                # 12/12가 살아남았다(종료 요청은 접수됐으나 커널 루프에 갇힌 상태). 재조회로 확인한다.
                # 재조회는 반드시 CIM으로 한다 — 그 상태의 프로세스는 유저 모드 객체가 이미 정리돼
                # Get-Process가 미검출하므로, 그것으로 확인하면 안 죽은 것을 죽었다고 계상한다(실측).
                # CreationDate까지 대조하는 것은 소멸 직후 같은 PID가 재할당된 경우를 가르기 위함이다.
                try {
                    $still = @(Get-CimInstance Win32_Process -Filter ("ProcessId=" + $t.Id) -ErrorAction Stop)
                    $gone = ($still.Count -eq 0) -or ($still[0].CreationDate -ne $t.StartTime)
                } catch { $gone = $true }
            }

            if ($gone) {
                $result.Killed++
                $result.CpuSec += [int]$t.CpuSec
            } else {
                $result.Unkillable++
                Add-UnkillableMarker -ProcessId $t.Id -BootStamp $bootStamp
                continue
            }

            if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
                try {
                    Write-HookEvent -Hook $Hook -Decision 'cleanup' -Rule $rule `
                        -CommandText ("pid=" + $t.Id + " name=" + $t.Name + " cpuSec=" + $t.CpuSec)
                } catch {}
            }
        }
    } catch {}
    return $result
}
