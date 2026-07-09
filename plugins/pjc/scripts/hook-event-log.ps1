# hook-event-log.ps1 — 공유 이벤트 로깅 헬퍼 (dot-source 전용, hook 아님)
#
# 왜: hook 차단/경고 오탐은 발생 시점에만 데이터가 존재한다 — 회고 검토(v1.98.0, 발견 ~40건 수동 발굴)
#   대신 이벤트를 로컬 jsonl로 적재해 다음 오탐 수정 라운드를 실측 기반으로 만든다.
# 어디에: ~/.claude/.state/hook-events/{YYYY-MM}.jsonl (기존 .state 마커 패턴과 동일 계층,
#   월별 파일 — 90일 초과 파일은 append 시 자동 정리).
# 안전 계약 (절대 불변):
#   ① 이 함수의 어떤 실패도 호출한 hook의 차단/경고 판정에 영향을 주지 않는다 — 전체 try/catch로
#      삼키고, 호출측도 Get-Command 가드 + try/catch로 감싼다(로드 실패 = 로깅만 조용히 생략).
#   ② 로그에 시크릿 평문을 남기지 않는다 — 명령 원문은 secret-patterns.ps1(단일 출처) 검사를
#      통과할 때만 앞 200자를 기록하고, 시크릿 검출·판정 불가 시 cmd 필드 자체를 생략한다
#      (fail-closed — Get-SecretMatches는 라벨만 반환하므로 값 치환 대신 생략이 안전하고 단순하다).

function Write-HookEvent {
    param(
        [string]$Hook,          # hook 이름 (예: 'block-destructive')
        [string]$Decision,      # 'block' | 'warn'
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
