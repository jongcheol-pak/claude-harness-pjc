# scenarios/pre-bash-dispatch.ps1 — pre-bash-dispatch 로드 가드 시나리오 (lib 부재 시 fail-open 가시화) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
if (Test-HookSelected @('pre-bash-dispatch')) {
# [v1.101.0 T4] 디스패처 로드 가드 — bash-hook-lib.ps1 부재(로드 실패) 시 침묵 fail-open 대신
#   stderr 경고 1줄 + exit 0(비차단)을 실증한다. lib 없는 임시 사본에서 디스패처를 단독 실행
#   (Invoke-Hook은 $scriptsDir 고정이라 lib가 항상 옆에 있음 — 부재 상황은 사본으로만 재현 가능).
$noLib = Join-Path $work 'dispatch-nolib'; New-Item -ItemType Directory $noLib -Force | Out-Null
Copy-Item (Join-Path $scriptsDir 'pre-bash-dispatch.ps1') $noLib -Force
$noLibJson = @{ tool_name = 'Bash'; tool_input = @{ command = 'git commit -m "T1: x"' } } | ConvertTo-Json -Compress
$outNoLib = $noLibJson | pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $noLib 'pre-bash-dispatch.ps1') 2>&1
$rNoLib = @{ code = $LASTEXITCODE; out = (($outNoLib | Out-String)).Trim() }
Assert-Case -Name "pre-bash-dispatch: lib 부재 시 로드 가드 경고 + exit 0 (v1.101.0 T4 fail-open 가시화)" -R $rNoLib -ExpectExit 0 -ExpectContains '로드 실패'
}   # ---- 로드 가드 게이트 끝 (pre-bash-dispatch) ----

