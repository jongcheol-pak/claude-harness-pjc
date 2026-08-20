# report-hook-events.ps1 — hook 차단/경고 이벤트 로그 집계 리포트 (수동 실행 도구, hook 아님)
#
# 왜: hook-event-log.ps1(Write-HookEvent)이 적재만 하고 소비 경로가 없으면 계측 투자가 놀게 된다 —
#   ~/.claude/.state/hook-events/*.jsonl 을 hook별·판정별·규칙별로 집계해 오탐 수정 라운드를
#   축적 대기 없이 언제든 실측 기반으로 만든다(v1.107.0 T2, 수동 실행 도구 — 사용자 확정 D3).
# 사용법: pwsh -NoProfile -File plugins/pjc/scripts/report-hook-events.ps1 [-Days 30] [-Hook block-destructive] [-Top 10]
# 안전 계약:
#   ① 읽기 전용 — 로그 파일을 수정·삭제하지 않는다(90일 자동 정리는 Write-HookEvent의 몫).
#   ② cmd 필드는 적재 시점에 이미 시크릿 위생 처리됨(hook-event-log.ps1 안전 계약 ② —
#      시크릿 검출·판정 불가 시 필드 자체 생략, fail-closed) → 리포트 측 추가 검사 없이 표시한다.
#   ③ protect-harness 이름 집합 비대상 — 차단/경고 판정에 관여하지 않는 읽기 도구라 개조돼도
#      게이트 무력화가 아니다(집합 취지 = 게이트·경고 계층 보호, plan D6). validate.ps1의
#      $knownHelpers 에는 등재(미등록 스크립트 WARN 방지).

param(
    [int]$Days = 0,        # 0 = 보존분 전체, >0 = ts 기준 최근 N일만
    [string[]]$Hook,       # hook 이름 필터 (.ps1 유무·대소문자 무관, 쉼표 복수)
    [int]$Top = 10         # hook별 발동 규칙 상위 N
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# 홈 해석은 hook-event-log.ps1(Write-HookEvent)과 동일 규약 — 같은 위치를 읽어야 한다.
$homeBase = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
if ([string]::IsNullOrEmpty($homeBase)) { Write-Host '홈 경로를 확인할 수 없어 리포트를 만들 수 없습니다.'; exit 0 }
$dir = Join-Path $homeBase '.claude/.state/hook-events'

Write-Host '== hook 이벤트 리포트 =='
Write-Host "로그 위치: $dir"

$files = @()
if (Test-Path -LiteralPath $dir) {
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -ErrorAction SilentlyContinue | Sort-Object Name)
}
if (-not $files.Count) {
    Write-Host '적재된 이벤트 없음 — hook 차단/경고가 아직 발생하지 않았거나 로그가 정리되었습니다.'
    exit 0
}

# ---- 파싱 (손상 라인은 skip 후 건수 보고 — 리포트가 한 줄 때문에 죽지 않게) ----
$hookFilter = $null
if ($Hook -and @($Hook).Count) {
    $hookFilter = @($Hook | ForEach-Object { ($_ -replace '\.ps1$', '').Trim().ToLowerInvariant() } | Where-Object { $_ })
}
$cutoff = if ($Days -gt 0) { (Get-Date).AddDays(-$Days) } else { $null }

$events = New-Object System.Collections.Generic.List[object]
$parseFail = 0
foreach ($f in $files) {
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $e = $line | ConvertFrom-Json
            if (-not $e.hook) { $parseFail++; continue }
            if ($cutoff) {
                # ConvertFrom-Json이 ISO ts를 [datetime]으로 자동 변환하므로 그대로 쓰고,
                # 문자열로 남은 경우만 Parse한다. 파싱 실패 라인은 기간 판정 불가 →
                # 보수적으로 포함(누락보다 초과 표시가 안전).
                $ts = $null
                try {
                    if ($e.ts -is [datetime]) { $ts = $e.ts } else { $ts = ([datetimeoffset]::Parse([string]$e.ts)).LocalDateTime }
                } catch {}
                if ($ts -and $ts -lt $cutoff) { continue }
            }
            if ($hookFilter -and ($hookFilter -notcontains ([string]$e.hook).ToLowerInvariant())) { continue }
            $events.Add($e)
        } catch { $parseFail++ }
    }
}

$rangeDesc = if ($Days -gt 0) { "최근 $Days`일" } else { '보존분 전체' }
$hookDesc = if ($hookFilter) { " | hook 필터: $($hookFilter -join ', ')" } else { '' }
Write-Host "대상 파일: $($files.Count)개 ($($files[0].BaseName) ~ $($files[-1].BaseName)) | 기간: $rangeDesc$hookDesc"

if (-not $events.Count) {
    Write-Host "조건에 맞는 이벤트 없음 (파싱 실패 $parseFail`건)."
    exit 0
}

$blockCount = @($events | Where-Object { $_.decision -eq 'block' }).Count
$warnCount = @($events | Where-Object { $_.decision -eq 'warn' }).Count
# 회수(cleanup)는 차단·경고와 다른 축이다 — 고아 콘솔 프로세스를 걷어낸 위생 기록.
$cleanupCount = @($events | Where-Object { $_.decision -eq 'cleanup' }).Count
$failNote = if ($parseFail) { " | 파싱 실패 $parseFail`건(집계 제외)" } else { '' }
Write-Host "총 이벤트: $($events.Count)건 (차단 $blockCount · 경고 $warnCount · 회수 $cleanupCount)$failNote"

# ---- hook × 판정 집계 ----
Write-Host ''
Write-Host '[hook × 판정]'
$byHook = $events | Group-Object hook | Sort-Object Count -Descending
foreach ($g in $byHook) {
    $b = @($g.Group | Where-Object { $_.decision -eq 'block' }).Count
    $w = @($g.Group | Where-Object { $_.decision -eq 'warn' }).Count
    $c = @($g.Group | Where-Object { $_.decision -eq 'cleanup' }).Count
    Write-Host ("  {0,-24} 차단 {1,4}  경고 {2,4}  회수 {3,4}  계 {4,4}" -f $g.Name, $b, $w, $c, $g.Count)
}

# ---- hook별 발동 규칙 상위 N ----
Write-Host ''
Write-Host "[발동 규칙 상위 $Top — hook별]"
foreach ($g in $byHook) {
    Write-Host "  $($g.Name):"
    $rules = $g.Group | Group-Object { if ([string]::IsNullOrWhiteSpace($_.rule)) { '(규칙 미기록)' } else { $_.rule } } |
        Sort-Object Count -Descending | Select-Object -First $Top
    foreach ($rg in $rules) {
        Write-Host ("    {0,4}건  {1}" -f $rg.Count, $rg.Name)
    }
}

# ---- hook별 최신 이벤트 예시 (cmd는 적재 시점 위생 처리 완료분만 존재) ----
Write-Host ''
Write-Host '[hook별 최신 이벤트]'
foreach ($g in $byHook) {
    $latest = $g.Group | Sort-Object ts | Select-Object -Last 1
    $cmdNote = if ($latest.PSObject.Properties['cmd'] -and $latest.cmd) { " cmd=$($latest.cmd)" } else { ' (명령 미기록 — 시크릿 감지 또는 대상 없음)' }
    Write-Host "  - $($g.Name)  $($latest.ts)  [$($latest.decision)] rule=$($latest.rule)$cmdNote"
}

exit 0
