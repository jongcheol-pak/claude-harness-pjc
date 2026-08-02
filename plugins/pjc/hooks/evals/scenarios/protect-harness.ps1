# scenarios/protect-harness.ps1 — protect-harness 시나리오 (§2b — 설치본 hook·헬퍼 개조 차단, 개발 repo 무영향) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# 같은 hook의 다른 파일: scenarios/protect-harness-installed.ps1 (설치본 캐시 경로 개조 차단 — 본체에서 비인접 블록이라 분리).
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 2b) protect-harness 시나리오 (Write/Edit로 하니스 게이트 무력화 차단 — 경로 문자열만 검사, 무상태)
#   .claude 하위 설치본 hook 스크립트·hooks.json 개조만 차단.
#   .claude 없는 개발 repo 소스·일반 .claude 설정은 통과(하니스 자기 개발은 plan 게이트로 관리).
# =====================================================================
if (Test-HookSelected @('protect-harness')) {
$ph = Join-Path $work 'ph'; New-Item -ItemType Directory $ph -Force | Out-Null
$fakeInstall = Join-Path $ph '.claude/plugins/cache/pjc-harness/pjc/1.89.0'
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/block-destructive.ps1'))
Assert-Case -Name "protect-harness: 설치본 hook 스크립트 Write 차단" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'hooks/hooks.json'))
Assert-Case -Name "protect-harness: 설치본 hooks.json Write 차단" -R $r -ExpectExit 2
$phEdit = @{ tool_name = 'Edit'; cwd = $ph; tool_input = @{ file_path = (Join-Path $fakeInstall 'scripts/protect-harness.ps1'); old_string = 'exit 0'; new_string = 'exit 0 # x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'protect-harness.ps1' $phEdit
Assert-Case -Name "protect-harness: 자기 자신 Edit 차단 (self-protect)" -R $r -ExpectExit 2
# 경로 표기 변형 우회 차단 (세그먼트 정규화 — B1): ./ · 이중슬래시 · ../ 삽입해도 설치본 hook 경로를 차단
$phFwd = $ph -replace '\\', '/'
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/.claude/./plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: hook 경로 우회(./) 차단 (B1)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/.claude//plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: hook 경로 우회(이중슬래시) 차단 (B1)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/.claude/foo/../plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: hook 경로 우회(../) 차단 (B1)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $ph '.claude/settings.json'))
Assert-Case -Name "protect-harness: .claude/settings.json 통과(무경고)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'plugins/pjc/scripts/block-destructive.ps1'))
Assert-Case -Name "protect-harness: 개발 repo hook 스크립트(.claude 없음) 통과" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'src/app.ts'))
Assert-Case -Name "protect-harness: 일반 소스 통과" -R $r -ExpectExit 0 -ExpectSilent $true
# NotebookEdit — notebook_path 폴백으로 설치본 hook 경로 차단 (폴백 분기 검증)
$phNb = @{ tool_name = 'NotebookEdit'; cwd = $ph; tool_input = @{ notebook_path = "$phFwd/.claude/plugins/cache/pjc-harness/pjc/1.89.0/scripts/require-plan-for-write.ps1"; new_source = 'x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'protect-harness.ps1' $phNb
Assert-Case -Name "protect-harness: NotebookEdit notebook_path 폴백 차단" -R $r -ExpectExit 2
# [v1.90.2 H3] 8.3 단축명 마스킹 — 무관 8.3 세그먼트(RUNNER~1 등)는 hook명이 있어도 통과(개발 repo 무영향 보장).
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph 'C:/Users/RUNNER~1/myrepo/scripts/block-destructive.ps1')
Assert-Case -Name "protect-harness: 무관 8.3(RUNNER~1)+hook명 통과 (v1.90.2 H3 오탐 방지)" -R $r -ExpectExit 0 -ExpectSilent $true
# [v1.90.3 F2] CLAUDE~1 충돌 오탐 수정 — 'Claude…' 폴더의 8.3명 CLAUDE~1(이 repo 자신 포함) 아래 개발 소스
#   편집은 통과해야 한다(캐시 밖). 실제 마스킹된 설치본 hook 경로는 /plugins/cache/를 포함하므로 그때만 차단.
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/pjc/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: 8.3 CLAUDE~1 개발 repo 소스(캐시 밖) 통과 (v1.90.3 F2 오탐 수정)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/cache/pjc-harness/pjc/1.90.2/scripts/block-destructive.ps1")
Assert-Case -Name "protect-harness: 8.3 마스킹 설치본(캐시 컨텍스트) 차단 (v1.90.3 F2)" -R $r -ExpectExit 2 -ExpectContains '8.3'
# [v1.97.2] v1.96.0 신설분의 이름 집합 합류 — warn-commit-secrets(hook)·secret-patterns(공유 헬퍼, 개조 시
#   시크릿 경고 계층 등가 무력화) 설치본 개조 차단. 집합 누락이 재발하면 이 두 케이스가 잡는다.
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/warn-commit-secrets.ps1'))
Assert-Case -Name "protect-harness: 설치본 warn-commit-secrets Write 차단 (v1.97.2 집합 합류)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/secret-patterns.ps1'))
Assert-Case -Name "protect-harness: 설치본 secret-patterns 헬퍼 Write 차단 (v1.97.2 등가 우회 봉쇄)" -R $r -ExpectExit 2
# [v1.99.0 T6] 디스패처·공유 lib 이름 집합 합류 — pre-bash-dispatch(hook)·bash-hook-lib(3 hook 검사 로직
#   헬퍼, 개조 시 3 게이트 등가 무력화) 설치본 개조 차단. 집합 누락 재발 시 이 두 케이스가 잡는다.
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/pre-bash-dispatch.ps1'))
Assert-Case -Name "protect-harness: 설치본 pre-bash-dispatch Write 차단 (v1.99.0 T6 집합 합류)" -R $r -ExpectExit 2
$r = Invoke-Hook 'protect-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/bash-hook-lib.ps1'))
Assert-Case -Name "protect-harness: 설치본 bash-hook-lib 헬퍼 Write 차단 (v1.99.0 T6 등가 우회 봉쇄)" -R $r -ExpectExit 2
}   # ---- §2b 게이트 끝 (protect-harness) ----

