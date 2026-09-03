# session-end-cleanup.ps1 — SessionEnd: 고아 콘솔 프로세스 회수 (비차단, 무출력)
#
# 왜 SessionEnd에도 두는가: Stop hook은 응답마다 돌아 마지막 응답 직후까지 훑고, SessionStart는
#   다음에 열 때 훑는다. 그 사이 — 마지막 응답 이후 세션이 닫힐 때까지 생긴 고아 — 를 다음 세션까지
#   기다리지 않고 그 자리에서 걷는 것이 이 hook의 몫이다. 세션당 1회라 콜드스타트 1회가 비용의 전부다.
#   단 크래시·강제 종료 시 발화 여부는 공식 문서에 없으므로 SessionStart가 백스톱으로 남는다
#   (이 hook은 SessionStart를 대체하지 않는다).
# 무엇을: orphan-process-cleanup.ps1의 회수 함수만 호출하는 얇은 래퍼다. 다른 책임을 얹지 않는다.
# 안전: SessionEnd는 세션 종료를 차단할 수 없고(공식 규약), stdout은 디버그 로그행이다.
#   회수 사실은 hook-event-log에만 남으므로 이 스크립트는 아무것도 출력하지 않는다.
#   모든 실패 경로는 조용히 exit 0 (fail-open).

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# payload(session_end_reason 등)는 쓰지 않지만 stdin은 비운다 — 읽지 않으면 파이프가 남을 수 있다.
try { $null = [Console]::In.ReadToEnd() } catch {}

try {
    . (Join-Path $PSScriptRoot 'session-end-cleanup-lib.ps1')
    $null = Invoke-OrphanProcessCleanup -Hook 'session-end-cleanup'
} catch {}

exit 0
