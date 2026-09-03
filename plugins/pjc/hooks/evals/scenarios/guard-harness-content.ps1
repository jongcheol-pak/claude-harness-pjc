# scenarios/guard-harness.ps1 — guard-agents-content 시나리오 (AGENTS.md 내용 경계 게이트) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson)와 공유 변수($work)를 그대로 쓴다.
# 검사 대상: plan 진행 상태·세션 인계 서술(차단) · 디렉터리 트리 블록(차단) · 그 밖은 통과.
# 내용 경계의 정본은 plugins/pjc/skills/AGENTS-BOUNDARY.md 다.
#
# ⚠ 델타 음성이 이 시나리오의 핵심이다 — 차단 범위를 새로 만드는 hook이므로 AGENTS.md DO NOT이
#   "오차단 0 실증"을 요구한다. 정상 AGENTS.md 편집 · plan.md의 같은 문구 · 본문 산문의 스침 ·
#   명령 예시 파이프 · 마크다운 표가 전부 통과해야 한다.
# =====================================================================
if (Test-HookSelected @('guard-harness')) {
$gac = Join-Path $work 'gac'; New-Item -ItemType Directory $gac -Force | Out-Null
$gacFwd = $gac -replace '\\', '/'

# JSON 조립 헬퍼 — 이 시나리오는 경로가 아니라 **본문**을 검사하므로 New-WriteJson으로는 부족하다.
function New-GacWrite {
    param([string]$Path, [string]$Content, [string]$Tool = 'Write')
    @{ tool_name = $Tool; cwd = $gac; tool_input = @{ file_path = $Path; content = $Content } } | ConvertTo-Json -Compress
}
function New-GacEdit {
    param([string]$Path, [string]$NewString)
    @{ tool_name = 'Edit'; cwd = $gac; tool_input = @{ file_path = $Path; old_string = 'x'; new_string = $NewString } } | ConvertTo-Json -Compress
}

$agents = "$gacFwd/AGENTS.md"

# ---- 차단 양성 (1) plan 진행 상태·세션 인계 서술 ----
$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n## 현재 진행 상태`n`n| 단계 | 상태 |`n|---|---|`n| M5 | 진행 중 |`n")
Assert-Case -Name "guard-agents-content: 진행 상태 헤딩 차단" -R $r -ExpectExit 2 -ExpectContains '인계'

$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n**다음 작업**: T7 진행`n")
Assert-Case -Name "guard-agents-content: '다음 작업' 볼드 제목 차단" -R $r -ExpectExit 2

$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n> **part5가 남긴 것 — 다음 회차가 알아야 할 것**`n")
Assert-Case -Name "guard-agents-content: '남긴 것/다음 회차' 인용 볼드 차단" -R $r -ExpectExit 2

# ---- 차단 양성 (2) 디렉터리 트리 블록 ----
$tree = "# A`n`n``````" + "`n├── src/`n│   └── app/`n└── docs/`n" + "``````" + "`n"
$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents $tree)
Assert-Case -Name "guard-agents-content: 디렉터리 트리 차단" -R $r -ExpectExit 2 -ExpectContains '트리'

# Edit 도구 경로도 같은 판정 (new_string 검사)
$r = Invoke-Hook 'guard-harness.ps1' (New-GacEdit $agents "├── src/`n│   └── app/`n└── docs/`n")
Assert-Case -Name "guard-agents-content: Edit new_string 트리 차단" -R $r -ExpectExit 2

# ---- 델타 음성 (오차단 0 실증) ----
$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n## Build & Test`n- Build: ``dotnet build```n`n## DO NOT`n- 시크릿 커밋`n")
Assert-Case -Name "guard-agents-content: 정상 AGENTS.md 통과" -R $r -ExpectExit 0 -ExpectSilent $true

$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite "$gacFwd/plan.md" "## Next Steps`n`n**다음 작업**: T7 진행`n")
Assert-Case -Name "guard-agents-content: plan.md의 같은 문구 통과 (대상 파일 한정)" -R $r -ExpectExit 0 -ExpectSilent $true

$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n## Conventions`n- 커밋 전 빌드하고 다음 작업으로 넘어간다.`n")
Assert-Case -Name "guard-agents-content: 본문 산문의 '다음 작업' 스침 통과 (헤딩 아님)" -R $r -ExpectExit 0 -ExpectSilent $true

$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n## Build & Test`n- ``ls | grep x```n- ``cat a | wc -l```n")
Assert-Case -Name "guard-agents-content: 명령 예시 파이프 통과 (트리 오탐 방지)" -R $r -ExpectExit 0 -ExpectSilent $true

$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n| 항목 | 값 |`n|---|---|`n| a | b |`n| c | d |`n")
Assert-Case -Name "guard-agents-content: 마크다운 표 통과 (트리 오탐 방지)" -R $r -ExpectExit 0 -ExpectSilent $true

$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite "$gacFwd/AGENTS-old.md" "## 현재 진행 상태`n")
Assert-Case -Name "guard-agents-content: 파일명 불일치(AGENTS-old.md) 통과" -R $r -ExpectExit 0 -ExpectSilent $true

# 하위 경로의 AGENTS.md 는 **대상이다** — 판정은 basename 이고 경로를 보지 않는다.
#   내용 경계는 파일의 위치가 아니라 그 파일이 무엇인가에 딸린 규약이므로 모노레포 하위도 같은 정책을 받는다.
$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite "$gacFwd/packages/x/AGENTS.md" "# A`n`n## 현재 진행 상태`n")
Assert-Case -Name "guard-agents-content: 하위 경로 AGENTS.md 도 차단 (basename 판정)" -R $r -ExpectExit 2

# ---- 우회 변수 (require-plan-for-write의 AGENTS 게이트와 같은 CLAUDE_HARNESS_QUICK) ----
$savedQuick = $env:CLAUDE_HARNESS_QUICK
try {
    $env:CLAUDE_HARNESS_QUICK = '1'
    $r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n## 현재 진행 상태`n")
    Assert-Case -Name "guard-agents-content: CLAUDE_HARNESS_QUICK=1 우회" -R $r -ExpectExit 0
} finally {
    $env:CLAUDE_HARNESS_QUICK = $savedQuick
}

# ---- protect-harness 공존 (같은 matcher에 직렬로 걸린다) ----
# ⓐ 정상 AGENTS.md Write — 두 hook 모두 통과해야 한다.
$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $agents "# A`n`n## Build & Test`n- Build: x`n")
Assert-Case -Name "guard-agents-content: 공존ⓐ protect-harness도 정상 AGENTS.md 통과" -R $r -ExpectExit 0 -ExpectSilent $true
# ⓑ 설치본 hook 경로 Write — protect-harness가 차단하고, 신규 hook은 그 판정을 가리지 않는다(파일명 불일치로 통과).
$installed = "$gacFwd/.claude/plugins/cache/pjc-harness/pjc/1.89.0/scripts/block-destructive.ps1"
$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $installed "x")
Assert-Case -Name "guard-agents-content: 공존ⓑ 설치본 hook 경로는 protect-harness가 차단" -R $r -ExpectExit 2
# v1.225.0: 두 hook 이 guard-harness 하나로 합쳐져 「신규 hook 은 통과」는 성립하지 않는다 —
#   같은 프로세스에서 자기보호 게이트가 먼저 차단하기 때문이다. 그 대신 **차단 사유가 자기보호 쪽임**을
#   확인해 게이트 순서를 고정한다(AGENTS.md 경계 사유로 잘못 차단하면 이 어서션이 잡는다).
$r = Invoke-Hook 'guard-harness.ps1' (New-GacWrite $installed "x")
Assert-Case -Name "guard-harness: 설치본 hook 경로는 자기보호 게이트가 먼저 차단한다(게이트 순서 고정)" -R $r -ExpectExit 2 -ExpectContains '하니스 안전 hook 개조'

# ---- fail-open ----
$r = Invoke-Hook 'guard-harness.ps1' 'not-a-json'
Assert-Case -Name "guard-agents-content: JSON 파싱 실패 fail-open" -R $r -ExpectExit 0 -ExpectSilent $true
$r = Invoke-Hook 'guard-harness.ps1' (@{ tool_name = 'Write'; cwd = $gac; tool_input = @{ file_path = $agents } } | ConvertTo-Json -Compress)
Assert-Case -Name "guard-agents-content: content 없음 통과" -R $r -ExpectExit 0 -ExpectSilent $true
}
