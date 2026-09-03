# scenarios/protect-harness-installed.ps1 — protect-harness 설치본 캐시 경로 개조 차단 시나리오 (이름 집합 합류 실증) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# 같은 hook의 다른 파일: scenarios/guard-harness.ps1 (§2b 본편 — 본체에서 비인접 블록이라 분리).
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# ---- [T1] protect-harness: 신규 hook(warn-version-drift) 설치본 개조 차단 (이름 집합 합류 실증) ----
# ($vdCache는 top-level 공유 정의 — §11(d)도 사용)
if (Test-HookSelected @('guard-harness')) {
$vdTarget = (Join-Path $vdCache 'warn-version-drift.ps1') -replace '\\', '/'
$r = Invoke-Hook 'guard-harness.ps1' (@{ tool_name = 'Write'; tool_input = @{ file_path = $vdTarget; content = 'x' } } | ConvertTo-Json -Compress)
Assert-Case -Name "protect-harness: 설치본 warn-version-drift 개조 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
# session-context(v1.112.0 신설)도 동일 실증 — 이름 집합 합류 확인
$scTarget = (Join-Path $vdCache 'session-context.ps1') -replace '\\', '/'
$r = Invoke-Hook 'guard-harness.ps1' (@{ tool_name = 'Write'; tool_input = @{ file_path = $scTarget; content = 'x' } } | ConvertTo-Json -Compress)
Assert-Case -Name "protect-harness: 설치본 session-context 개조 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
}   # ---- 게이트 끝 (protect-harness) ----

