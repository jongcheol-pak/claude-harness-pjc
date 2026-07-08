# PreToolUse hook (얇은 래퍼) - 커밋 시점 시크릿 스캔 (경고, 비차단)
# Bash/PowerShell 도구로 'git commit' 직전, 스테이징될 변경에서 시크릿 패턴을 스캔해 경고(exit 0).
# 편집 시점의 post-write-checks가 놓친 경로의 "커밋 직전 최종 방어선".
#
# 검사 로직은 bash-hook-lib.ps1의 Invoke-WarnCommitSecrets로 이관됐다(pre-bash-dispatch.ps1과
#   동일 함수 공유). 이 파일은 stdin 파싱 + 함수 호출 + 결과 번역(stderr/additionalContext/exit)만 한다.
# cwd 이동(git 실행용)은 Invoke-WarnCommitSecrets가 finally로 복원해 caller에 잔존하지 않는다.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
} catch {
    exit 0   # 파싱 실패 시 통과 (경고 실패가 차단보다 안전)
}

. (Join-Path $PSScriptRoot 'bash-hook-lib.ps1')
$r = Invoke-WarnCommitSecrets $data

foreach ($l in $r.Stderr) { [Console]::Error.WriteLine($l) }
if ($r.Context) {
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $r.Context } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}
if ($r.Block) { exit 2 } else { exit 0 }
