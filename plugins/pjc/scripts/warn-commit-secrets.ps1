# PreToolUse hook (얇은 래퍼) - 커밋 시점 시크릿 스캔 (조건부 차단)
# Bash/PowerShell 도구로 'git commit' 직전, 스테이징될 변경에서 시크릿 패턴을 스캔한다.
#   고신뢰 라벨(개인키·DB 연결 문자열·DB/서비스 URI 인증정보·자격증명 쌍) → 차단(exit 2, v1.119.0).
#   그 외 라벨·.env 스테이징 → 경고(exit 0) — 오탐 여지가 있어 정상 작업을 막지 않는다.
# 편집 시점의 post-write-checks가 놓친 경로(Bash 리다이렉션 등)의 "커밋 직전 최종 방어선".
# 우회는 전용 변수 CLAUDE_HARNESS_ALLOW_SECRET=1 (사용자만, 시작 전 터미널에서) — QUICK으로는 안 꺼진다.
#
# 검사 로직은 bash-hook-lib.ps1의 Invoke-WarnCommitSecrets로 이관됐다(pre-bash-dispatch.ps1과
#   동일 함수 공유). 이 파일은 stdin 파싱 + 함수 호출 + 결과 번역(stderr/additionalContext/exit)만 한다.
# cwd 이동(git 실행용)은 Invoke-WarnCommitSecrets가 finally로 복원해 caller에 잔존하지 않는다.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로·명령이 깨져 git add 대상 스캔이 어긋난다(시크릿 차단 판정에 직결). 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

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
