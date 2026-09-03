# hook-event-log.ps1 — 공유 이벤트 로깅 헬퍼 — 근거는 `rules/event-log-rationale.md`의 「§1 hook-event-log.ps1 — 공유 이벤트 로깅 헬퍼」

function Write-HookEvent {
    param(
        [string]$Hook,          # hook 이름 (예: 'block-destructive')
        [string]$Decision,      # 'block' | 'warn' | 'cleanup'(고아 프로세스 회수 — session-end-cleanup-lib)
        [string]$Rule,          # 발동 규칙 키워드 (오탐 리뷰 시 어떤 검사가 발동했는지 식별용)
        [string]$CommandText = ''   # 명령/대상 원문 (시크릿 검사 후 앞 200자만 기록, 없으면 생략)
    )
    try {
        $homeBase = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
        if ([string]::IsNullOrEmpty($homeBase)) { return }
        $dir = Join-Path $homeBase '.claude/.state/hook-events'
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        # 90일 초과 월 파일 정리 (suggest-agents-record의 30일 마커 정리와 동일 패턴 — best-effort)
        try {
            $cutoff = (Get-Date).AddDays(-90)
            Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {}

        $entry = [ordered]@{
            ts       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
            hook     = $Hook
            decision = $Decision
            rule     = if ($Rule -and $Rule.Length -gt 120) { $Rule.Substring(0, 120) } else { $Rule }
        }

        if (-not [string]::IsNullOrWhiteSpace($CommandText)) {
            # 시크릿 검사는 절단 전 원문 전체에 수행한다 (200자 경계 밖 시크릿도 판정에 반영 — 보수적).
            $safe = $false
            try {
                if (-not (Get-Command Get-SecretMatches -ErrorAction SilentlyContinue)) {
                    . (Join-Path $PSScriptRoot 'secret-patterns.ps1')
                }
                if (Get-Command Get-SecretMatches -ErrorAction SilentlyContinue) {
                    $hits = @(Get-SecretMatches $CommandText)
                    if ($hits.Count -eq 0) { $safe = $true }
                }
            } catch { $safe = $false }   # 판정 불가 → 기록 생략 (fail-closed)
            if ($safe) {
                $entry.cmd = if ($CommandText.Length -gt 200) { $CommandText.Substring(0, 200) } else { $CommandText }
            }
        }

        $line = $entry | ConvertTo-Json -Compress -Depth 3
        $file = Join-Path $dir ((Get-Date).ToString('yyyy-MM') + '.jsonl')
        Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    } catch {
        # 로깅 실패는 항상 무시 — hook 본연 동작(차단/경고)에 절대 영향 금지 (안전 계약 ①)
    }
}
