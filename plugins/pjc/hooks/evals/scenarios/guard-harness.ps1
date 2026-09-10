# scenarios/guard-harness.ps1 — guard-harness 시나리오 (§2b — 설치본 hook·헬퍼 개조 차단, 개발 repo 무영향) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ⚠ 예외 — RM2·RM3(회차 53)은 guard-write·post-write-checks 케이스인데 이 파일에 있다. 셋 다 같은
#   「규칙 json 부재」 사본 트리를 공유하고 그 트리를 만드는 비용이 케이스당 반복되기 때문이다.
#   그래서 아래 게이트가 세 이름을 다 받는다 — `-Filter guard-write` 로도 RM2 가 돈다.
# 같은 hook의 다른 파일: scenarios/guard-harness-installed.ps1 (설치본 캐시 경로 개조 차단 — 본체에서 비인접 블록이라 분리).
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 2b) guard-harness 시나리오 (Write/Edit로 하니스 게이트 무력화 차단 — 경로 문자열만 검사, 무상태)
#   .claude 하위 설치본 hook 스크립트·hooks.json 개조만 차단.
#   .claude 없는 개발 repo 소스·일반 .claude 설정은 통과(하니스 자기 개발은 plan 게이트로 관리).
# =====================================================================
if (Test-HookSelected @('guard-harness', 'guard-write', 'post-write-checks')) {
$ph = Join-Path $work 'ph'; New-Item -ItemType Directory $ph -Force | Out-Null
$fakeInstall = Join-Path $ph '.claude/plugins/cache/pjc-harness/pjc/1.89.0'
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/block-destructive.ps1'))
Assert-Case -Name "guard-harness: 설치본 hook 스크립트 Write 차단 (차단 사유 문구 고정)" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조 시도 감지'
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'hooks/hooks.json'))
Assert-Case -Name "guard-harness: 설치본 hooks.json Write 차단" -R $r -ExpectExit 2

# [v1.225.0] 판정 데이터 보호 — 차단 패턴·이름 집합이 스크립트 밖 JSON 으로 나갔으므로 그 파일도 대상이다.
#   **양성 2 + 델타 음성 2** — 미탐 보완(차단 범위 확대)이라 새 경계가 실제로 발화하면서
#   오차단 0 임을 함께 보인다(AGENTS.md DO NOT 의 예외 ② 조건).
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/rules/destructive.json'))
Assert-Case -Name "guard-harness: 설치본 차단 패턴 데이터(rules/destructive.json) Write 차단" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조 시도 감지'
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/rules/harness-hooks.json'))
Assert-Case -Name "guard-harness: 설치본 자기보호 이름 집합(rules/harness-hooks.json) Write 차단" -R $r -ExpectExit 2
# 델타 음성 ① 개발 repo 의 같은 파일 — `.claude` 가 경로에 없으므로 통과해야 한다
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'plugins/pjc/scripts/rules/destructive.json'))
Assert-Case -Name "guard-harness: 개발 repo 의 rules/*.json 은 통과 (델타 음성)" -R $r -ExpectExit 0 -ExpectSilent $true
# 델타 음성 ② 설치본이라도 rules 밖 JSON 은 대상이 아니다
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/data/other.json'))
Assert-Case -Name "guard-harness: 설치본이라도 rules 밖 JSON 은 통과 (델타 음성)" -R $r -ExpectExit 0 -ExpectSilent $true
$phEdit = @{ tool_name = 'Edit'; cwd = $ph; tool_input = @{ file_path = (Join-Path $fakeInstall 'scripts/guard-harness.ps1'); old_string = 'exit 0'; new_string = 'exit 0 # x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-harness.ps1' $phEdit
Assert-Case -Name "guard-harness: 자기 자신 Edit 차단 (self-protect)" -R $r -ExpectExit 2
# 경로 표기 변형 우회 차단 (세그먼트 정규화 — B1): ./ · 이중슬래시 · ../ 삽입해도 설치본 hook 경로를 차단
$phFwd = $ph -replace '\\', '/'
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph "$phFwd/.claude/./plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "guard-harness: hook 경로 우회(./) 차단 (B1)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph "$phFwd/.claude//plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "guard-harness: hook 경로 우회(이중슬래시) 차단 (B1)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph "$phFwd/.claude/foo/../plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1")
Assert-Case -Name "guard-harness: hook 경로 우회(../) 차단 (B1)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $ph '.claude/settings.json'))
Assert-Case -Name "guard-harness: .claude/settings.json 통과(무경고)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'plugins/pjc/scripts/block-destructive.ps1'))
Assert-Case -Name "guard-harness: 개발 repo hook 스크립트(.claude 없음) 통과" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'src/app.ts'))
Assert-Case -Name "guard-harness: 일반 소스 통과" -R $r -ExpectExit 0 -ExpectSilent $true
# NotebookEdit — notebook_path 폴백으로 설치본 hook 경로 차단 (폴백 분기 검증)
$phNb = @{ tool_name = 'NotebookEdit'; cwd = $ph; tool_input = @{ notebook_path = "$phFwd/.claude/plugins/cache/pjc-harness/pjc/1.89.0/scripts/guard-write.ps1"; new_source = 'x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'guard-harness.ps1' $phNb
Assert-Case -Name "guard-harness: NotebookEdit notebook_path 폴백 차단" -R $r -ExpectExit 2
# [v1.90.2 H3] 8.3 단축명 마스킹 — 무관 8.3 세그먼트(RUNNER~1 등)는 hook명이 있어도 통과(개발 repo 무영향 보장).
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph 'C:/Users/RUNNER~1/myrepo/scripts/block-destructive.ps1')
Assert-Case -Name "guard-harness: 무관 8.3(RUNNER~1)+hook명 통과 (v1.90.2 H3 오탐 방지)" -R $r -ExpectExit 0 -ExpectSilent $true
# [v1.90.3 F2] CLAUDE~1 충돌 오탐 수정 — 'Claude…' 폴더의 8.3명 CLAUDE~1(이 repo 자신 포함) 아래 개발 소스
#   편집은 통과해야 한다(캐시 밖). 실제 마스킹된 설치본 hook 경로는 /plugins/cache/를 포함하므로 그때만 차단.
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/pjc/scripts/block-destructive.ps1")
Assert-Case -Name "guard-harness: 8.3 CLAUDE~1 개발 repo 소스(캐시 밖) 통과 (v1.90.3 F2 오탐 수정)" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/cache/pjc-harness/pjc/1.90.2/scripts/block-destructive.ps1")
Assert-Case -Name "guard-harness: 8.3 마스킹 설치본(캐시 컨텍스트) 차단 (v1.90.3 F2)" -R $r -ExpectExit 2 -ExpectContains '8.3'
# [v1.97.2] v1.96.0 신설분의 이름 집합 합류 — commit-secrets 계열 hook·secret-patterns(공유 헬퍼, 개조 시
#   시크릿 경고 계층 등가 무력화) 설치본 개조 차단. 집합 누락이 재발하면 이 두 케이스가 잡는다.
#   ⚠ 당시 hook 이름은 warn-commit-secrets 였고 현행은 guard-commit-secrets 다 — v1.225.0 개명 때
#   케이스 **대상만** guard-bash 로 바뀌고 이름이 안 따라와, 이름은 warn- 인데 대상은 guard-bash 를
#   재는 상태로 남아 있었다(회차 54 실측 — 같은 입력 3중복의 한 자리였다).
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/guard-commit-secrets.ps1'))
Assert-Case -Name "guard-harness: 설치본 guard-commit-secrets Write 차단 (v1.97.2 집합 합류)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/secret-patterns.ps1'))
Assert-Case -Name "guard-harness: 설치본 secret-patterns 헬퍼 Write 차단 (v1.97.2 등가 우회 봉쇄)" -R $r -ExpectExit 2
# [v1.99.0 T6] 디스패처·공유 lib 이름 집합 합류 — 개조 시 게이트가 등가로 무력화되는 자리다.
#   당시 대상 pre-bash-dispatch(hook)·bash-hook-lib(검사 로직 헬퍼) 두 파일은 v1.225.0이 삭제했고
#   guard-bash.ps1 하나로 통폐합됐다 — 그 결과 두 케이스가 **같은 파일을 재게 되어** 한쪽이
#   무회귀였다(회차 54). 축을 현행 구성에서 다시 골랐다: 진입점은 guard-bash, 등가 우회는
#   guard-write 의 dot-source 헬퍼다. 짝인 write-gate-exempt 는 아래에서 이미 재고 있어,
#   둘을 합쳐 AGENTS.md 「guard-write 는 게이트 2종이고 같은 정규식을 공유하므로 한쪽만
#   고치지 말 것 — 차이가 곧 우회 경로다」를 양쪽에서 덮는다.
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/guard-bash.ps1'))
Assert-Case -Name "guard-harness: 설치본 guard-bash Write 차단 (v1.99.0 T6 집합 합류)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/write-gate-trivial.ps1'))
Assert-Case -Name "guard-harness: 설치본 write-gate-trivial 헬퍼 Write 차단 (게이트 2종 등가 우회 봉쇄)" -R $r -ExpectExit 2

# ---- [v1.181.0 T7] 한글 경로 실증 ----
# v1.129.0 T2의 stdin UTF-8 수정으로 이 hook도 한글이 든 보호 경로를 비로소 정확히 매치하게 됐는데,
#   골든 케이스가 0건이라 그 수정이 **실증되지 않은 채** 남아 있었다(성격상 미탐 보완이고,
#   AGENTS.md `## DO NOT`의 block-destructive 조항이 미탐 보완에 실증을 요구한다).
# ⚠ 양성만으로는 부족하다 — 인코딩이 깨지면 「아무것도 매치하지 않아」 통과하므로, 같은 한글 경로의
#   **캐시 밖 개발 소스가 통과하는지**(음성)까지 봐야 경로 문자열이 실제로 온전히 전달됐음이 드러난다.
$phKo = Join-Path $work '한글경로 테스트'; New-Item -ItemType Directory $phKo -Force | Out-Null
$fakeInstallKo = Join-Path $phKo '.claude/plugins/cache/pjc-harness/pjc/1.181.0'
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $phKo (Join-Path $fakeInstallKo 'scripts/block-destructive.ps1'))
Assert-Case -Name "guard-harness: 한글 경로 설치본 hook Write 차단 (v1.181.0 T7 — 미탐 보완 실증)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $phKo (Join-Path $phKo '플러그인/scripts/block-destructive.ps1'))
Assert-Case -Name "guard-harness: 한글 경로 개발 소스(캐시 밖) 통과 (v1.181.0 T7 — 오차단 0 델타 음성)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [T2] 고아 프로세스 회수 계열 이름 집합 합류 ----
# session-end-cleanup(hook)과 session-end-cleanup-lib(회수 함수 모듈)이 집합에서 빠져 있어 설치본
#   개조가 차단되지 않았다 — 목록 주석이 경고하던 "hook 신설 시 함께 추가" 누락의 재발이다.
# ⚠ 차단 범위 확대이므로 AGENTS.md `## DO NOT` ②가 **델타 음성으로 오차단 0 실증**을 요구한다.
#   그래서 양성 3(리터럴 2 + 8.3 마스킹 1) 아래에 음성 3(개발 repo · 유사 이름 · 캐시 밖 8.3)을 둔다 —
#   새 이름이 발화하는 자리가 셋이므로(리터럴 `.claude` 분기 · 8.3 분기 · 그 둘의 경계) 각각을 친다.
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/session-end-cleanup-lib.ps1'))
Assert-Case -Name "guard-harness: 설치본 session-end-cleanup-lib 헬퍼 Write 차단 (T2 집합 합류)" -R $r -ExpectExit 2
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/session-end-cleanup.ps1'))
Assert-Case -Name "guard-harness: 설치본 session-end-cleanup Write 차단 (T2 집합 합류)" -R $r -ExpectExit 2
# ---- [회차 44 T2] write-gate-exempt 합류 — PLAN-EXEMPT 면제(plan 게이트를 **여는** 코드)가 집합에 없어 설치본 개조가 무방비였다.
#   델타 음성은 위 「개발 repo 의 rules/*.json 은 통과」·「개발 repo hook 스크립트(.claude 없음) 통과」가 같은 술어(.claude 경로 유무)를 덮는다.
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/write-gate-exempt.ps1'))
Assert-Case -Name "guard-harness: 설치본 write-gate-exempt 면제 헬퍼 Write 차단 (회차 44 T2 집합 합류)" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조 시도 감지'
# 새 이름은 $suspect83 분기에도 들어가므로 그 확대까지 양성으로 고정한다(캐시 컨텍스트가 게이트).
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/cache/pjc-harness/pjc/1.187.0/scripts/session-end-cleanup.ps1")
Assert-Case -Name "guard-harness: 8.3 마스킹 설치본 session-end-cleanup 차단 (T2 — 8.3 분기 확대 실증)" -R $r -ExpectExit 2 -ExpectContains '8.3'
# 델타 음성 ⓐ 개발 repo 소스(.claude 세그먼트 없음) — 이번 회차 자신이 편집한 경로와 같은 형태다.
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $ph 'plugins/pjc/scripts/session-end-cleanup-lib.ps1'))
Assert-Case -Name "guard-harness: 개발 repo session-end-cleanup-lib 통과 (T2 — 오차단 0 델타 음성)" -R $r -ExpectExit 0 -ExpectSilent $true
# ⓑ 유사 이름 — 회차 53 이 기대값을 뒤집었다. **이름 축으로는 여전히 미매치**지만(알터네이션 그룹
#   앞의 리터럴 '/'가 부분 매치를 막는다), 같은 회차가 더한 **경로 축**(`.claude/**/scripts/*.ps1`)이
#   그 위에서 먼저 잡는다 — 설치본 `scripts/` 아래 `.ps1` 은 hook 이든 그 헬퍼든 개조되면 안전망이
#   함께 무너지므로 **넓게 잡는 것이 의도다**(`rules/harness-guard-rationale.md` §7).
#   이름 축의 그룹 경계는 경로 축이 상위집합이 되어 이 자리에서는 더 이상 잴 수 없다.
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'scripts/my-session-end-cleanup.ps1'))
Assert-Case -Name "guard-harness: 유사 이름도 설치본 scripts/*.ps1 이면 경로 축이 잡는다 (회차 53 — 기대값 뒤집음)" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조 시도 감지'
# 이름 축의 그룹 경계는 `scripts/` **밖**에서만 잴 수 있다 — 경로 축이 그 안을 상위집합으로 덮기 때문이다.
#   짝으로 둔다: 정확한 이름은 이름 축 양성, 접두어가 붙은 유사 이름은 음성(알터네이션 앞의 리터럴 '/'가 부분 매치를 막는다).
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'hooks/session-end-cleanup.ps1'))
Assert-Case -Name "guard-harness: scripts/ 밖이어도 정확한 hook 이름은 이름 축이 잡는다 (회차 53 — 그룹 경계 양성)" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조 시도 감지'
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph (Join-Path $fakeInstall 'hooks/my-session-end-cleanup.ps1'))
Assert-Case -Name "guard-harness: scripts/ 밖의 유사 이름은 미매치 통과 (회차 53 — 그룹 경계 음성 복원)" -R $r -ExpectExit 0 -ExpectNotContains '개조 시도 감지'
# 델타 음성 ⓒ 캐시 밖 CLAUDE~1 — 이 repo 자신의 8.3명이라 오차단되면 하니스 자기 개발이 막힌다.
$r = Invoke-Hook 'guard-harness.ps1' (New-WriteJson $ph "$phFwd/CLAUDE~1/plugins/pjc/scripts/session-end-cleanup.ps1")
Assert-Case -Name "guard-harness: 8.3 CLAUDE~1 개발 소스(캐시 밖) session-end-cleanup 통과 (T2 — 델타 음성)" -R $r -ExpectExit 0 -ExpectSilent $true
# ---- [회차 53] 규칙 json 부재 — 로드 실패 가시화 + 이름과 독립된 경로 축 ----
#   세 hook 다 머리에서 $ErrorActionPreference = 'SilentlyContinue' 를 세우는데, 그 상태에서
#   Get-Content 의 파일 부재는 non-terminating error 라 try/catch 를 그냥 지나간다. 변수가 $null 이
#   되고 폴백이 조용히 걸려 **검사가 사라진 것을 아무도 모른다**(착수 실측: 셋 다 무출력 통과).
#   Invoke-Hook 은 $scriptsDir 고정이라 부재 상황은 사본 트리로만 재현된다.
$noJ = Join-Path $work 'rules-missing'; New-Item -ItemType Directory (Join-Path $noJ 'rules') -Force | Out-Null
Copy-Item (Join-Path $scriptsDir '*.ps1') $noJ -Force
Copy-Item (Join-Path $scriptsDir 'rules/*.md') (Join-Path $noJ 'rules') -Force -ErrorAction SilentlyContinue
$noJFwd = ($noJ -replace '\\', '/')
function Invoke-NoJson([string]$Script, [string]$Json) {
    $o = $Json | pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $noJ $Script) 2>&1
    return @{ code = $LASTEXITCODE; out = (($o | Out-String)).Trim() }
}
$rmWrite = { param($path) (@{ tool_name = 'Write'; tool_input = @{ file_path = $path; content = 'x' } } | ConvertTo-Json -Compress) }

# RM1~3 (가시화): 규칙 json 이 없으면 **그 사실이 stderr 로 보인다** — 침묵 fail-open 이 아니다.
$r = Invoke-NoJson 'guard-harness.ps1' (& $rmWrite "$noJFwd/.claude/plugins/cache/p/scripts/x.ps1")
Assert-Case -Name "rm-json: guard-harness 로드 실패가 stderr 로 보인다 (RM1)" -R $r -ExpectExit 2 -ExpectContains 'rules/harness-hooks.json 로드 실패'
$r = Invoke-NoJson 'guard-write.ps1' (& $rmWrite (Join-Path $noJ 'src/x.cs'))
Assert-Case -Name "rm-json: guard-write 로드 실패가 stderr 로 보인다 (RM2)" -R $r -ExpectExit 0 -ExpectContains '쓰기 게이트를 건너뜁니다'
$realMd = Join-Path $noJ 'real.md'; 'x' | Set-Content -LiteralPath $realMd
$r = Invoke-NoJson 'post-write-checks.ps1' (& $rmWrite $realMd)
Assert-Case -Name "rm-json: post-write-checks 로드 실패가 stderr 로 보인다 (RM3)" -R $r -ExpectExit 0 -ExpectContains '개조 탐지를 건너뜁니다'

# RM4~5 (양성 — 이름 축이 죽은 상태에서도 경로만으로 막는다): 착수 시점엔 둘 다 rc=0 무출력이었다.
$r = Invoke-NoJson 'guard-harness.ps1' (& $rmWrite "$noJFwd/.claude/plugins/cache/pjc-harness/pjc/1.265.0/scripts/guard-bash.ps1")
Assert-Case -Name "rm-json: 이름 목록 없이도 설치본 hook 스크립트 개조 차단 (RM4)" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조 시도 감지'
# ⚠ 소유를 가리지 않는 것이 의도다 — 가르려면 플러그인 이름 목록이 필요한데 그 목록이야말로
#   로드 실패로 사라지는 바로 그것이라 자기순환이다(`rules/harness-guard-rationale.md` §7).
$r = Invoke-NoJson 'guard-harness.ps1' (& $rmWrite "$noJFwd/.claude/plugins/cache/other-plugin/scripts/foo.ps1")
Assert-Case -Name "rm-json: 비-pjc 설치본의 scripts/*.ps1 도 막는다 — 소유를 가리지 않는다 (RM5)" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조 시도 감지'

# RM6~8 (델타 음성 — 새 경계에서 **한 조각씩만** 어긋난 근접형): 무관 경로는 T2-1 이전에도
#   통과했으므로 아무것도 재지 않는다. 세 케이스가 각각 `.claude` · 확장자 · `scripts/` 를 뺀다.
$r = Invoke-NoJson 'guard-harness.ps1' (& $rmWrite "$noJFwd/plugins/pjc/scripts/guard-bash.ps1")
Assert-Case -Name "rm-json: 개발 repo 경로(.claude 세그먼트 없음)는 통과 (RM6)" -R $r -ExpectExit 0 -ExpectNotContains '개조 시도 감지'
$r = Invoke-NoJson 'guard-harness.ps1' (& $rmWrite "$noJFwd/.claude/plugins/cache/pjc-harness/pjc/1.265.0/scripts/foo.txt")
Assert-Case -Name "rm-json: scripts/ 아래여도 .ps1 이 아니면 통과 (RM7)" -R $r -ExpectExit 0 -ExpectNotContains '개조 시도 감지'
$r = Invoke-NoJson 'guard-harness.ps1' (& $rmWrite "$noJFwd/.claude/plugins/cache/pjc-harness/pjc/1.265.0/lib/foo.ps1")
Assert-Case -Name "rm-json: .claude 아래여도 scripts/ 하위가 아니면 통과 (RM8)" -R $r -ExpectExit 0 -ExpectNotContains '개조 시도 감지'

}   # ---- §2b 게이트 끝 (guard-harness) ----

