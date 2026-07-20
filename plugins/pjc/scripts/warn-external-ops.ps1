# PreToolUse hook (얇은 래퍼) - PowerShell 버전
# Bash/PowerShell 도구로 '외부·비가역' 작업(push·merge·tag·gh release/pr·배포) 또는
# '로컬 비가역'(git reset --hard·checkout -- 등) 실행 시 경고(비차단).
#
# 검사 로직은 bash-hook-lib.ps1의 Invoke-WarnExternalOps로 이관됐다(pre-bash-dispatch.ps1과
#   동일 함수 공유 — 래퍼·디스패처가 갈라지지 않음). 이 파일은 stdin 파싱 + 함수 호출 +
#   결과 번역(stderr/additionalContext/exit)만 한다.
#
# [설계: 왜 비차단(exit 0)인가] 일반 push는 승인 후 정당하게 일어나므로 hard block하면 워크플로가
#   깨진다. force push 등 파괴적 작업은 block-destructive가 exit 2로 차단하고, 이 hook은 soft 경고다.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글이 든 명령·경고 에코가 깨진다. 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
} catch {
    exit 0   # 파싱 실패 시 통과 (경고 실패가 차단보다 안전)
}

. (Join-Path $PSScriptRoot 'bash-hook-lib.ps1')
$r = Invoke-WarnExternalOps $data

foreach ($l in $r.Stderr) { [Console]::Error.WriteLine($l) }
if ($r.Context) {
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $r.Context } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}
if ($r.Block) { exit 2 } else { exit 0 }
