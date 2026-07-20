# PreToolUse hook (얇은 래퍼) - PowerShell 버전
# git commit이 'T<N>:' 완료 커밋인데 plan의 해당 task 체크박스가 아직 [ ]/[/]면 차단(exit 2).
# implement-task Phase D 규약("체크박스 [x] 갱신 → commit")을 구조로 강제한다.
#
# 검사 로직은 bash-hook-lib.ps1의 Invoke-RequireTaskCheckbox로 이관됐다(pre-bash-dispatch.ps1과
#   동일 함수 공유). 이 파일은 stdin 파싱 + 함수 호출 + 결과 번역(stderr/exit)만 한다.
#
# [설계: fail-open — 판정이 모호하면 통과] git commit 아님·T<N>: 제목 아님·plan 없음·읽기 실패는
#   전부 통과(Invoke-RequireTaskCheckbox가 New-HookResult(Block=$false) 반환). 우회: $env:CLAUDE_HARNESS_QUICK='1'.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로·커밋 메시지가 깨져 plan 탐색·체크박스 판정이 어긋난다. 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
} catch {
    exit 0   # 파싱 실패 시 통과 (fail-open)
}

. (Join-Path $PSScriptRoot 'bash-hook-lib.ps1')
$r = Invoke-RequireTaskCheckbox $data

foreach ($l in $r.Stderr) { [Console]::Error.WriteLine($l) }
if ($r.Block) { exit 2 } else { exit 0 }
