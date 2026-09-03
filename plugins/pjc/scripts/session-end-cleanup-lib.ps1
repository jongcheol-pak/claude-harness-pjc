# session-end-cleanup-lib.ps1 — 고아 콘솔 프로세스 회수 함수 — 근거는 `rules/orphan-cleanup-rationale.md`의 「§1 session-end-cleanup-lib.ps1 — 고아 콘솔 프로세스 회수 함수」

# 고아 콘솔 프로세스 회수 헬퍼 — 근거는 `rules/orphan-cleanup-rationale.md`의 「§2 고아 콘솔 프로세스 회수 헬퍼」

# 회수 대상. 실측된 고아가 이 둘뿐이라 목록을 넓히지 않는다 — 근거는 `rules/orphan-cleanup-rationale.md`의 「§3 회수 대상. 실측된 고아가 이 둘뿐이라 목록을 넓히지 않는다」
$script:OrphanTargetNames  = @('more.com', 'find.exe')   # CIM 조회용
$script:OrphanPreScanNames = @('more.com', 'find')       # Get-Process 선검사용(.exe 벗겨짐)

# 골든 스위트는 hook을 실기계에서 돌리는데 프로세스는 격리 대상이 아니다. — 근거는 `rules/orphan-cleanup-rationale.md`의 「§4 골든 스위트는 hook을 실기계에서 돌리는데 프로세스는 격리 대상이 아니다.」
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
    # 반환: 현재 부팅 세션에서 '죽지 않는다'고 확인된 PID 집합. — 근거는 `rules/orphan-cleanup-rationale.md`의 「§5 # 반환: 현재 부팅 세션에서 '죽지 않는다'고 확인된 PID 집합.」
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
        # 안전 계약 ②를 이 파일만으로 자기완결시킨다 — 비종결 오류는 try/catch에 잡히지 않고 곧장 — 근거는 `rules/orphan-cleanup-rationale.md`의 「§6 # 안전 계약 ②를 이 파일만으로 자기완결시킨다 — 비종결 오류는 try/catch에 잡히지 않고 곧장」
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
                # Stop-Process의 성공 반환을 소멸의 근거로 쓰지 않는다 — 실측에서 성공을 반환하고도 — 근거는 `rules/orphan-cleanup-rationale.md`의 「§7 # Stop-Process의 성공 반환을 소멸의 근거로 쓰지 않는다 — 실측에서 성공을 반환하고도」
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
