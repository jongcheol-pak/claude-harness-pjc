# guard-harness.ps1 — PreToolUse hook: Write/Edit 대상이 하니스 자신·A — 근거는 `rules/harness-guard-rationale.md`의 「§1 guard-harness.ps1 — PreToolUse hook: Write/Edit 대상이 하니스 자신·A」

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $script:data = $inputJson | ConvertFrom-Json
    $script:targetPath = $script:data.tool_input.path
    if (-not $script:targetPath) { $script:targetPath = $script:data.tool_input.file_path }
    if (-not $script:targetPath) { $script:targetPath = $script:data.tool_input.notebook_path }
} catch {
    exit 0
}
if ([string]::IsNullOrWhiteSpace($script:targetPath)) { exit 0 }
$targetPath = $script:targetPath

function Write-GacEvent {
    param([string]$Decision, [string]$Rule)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            Write-HookEvent 'guard-harness' $Decision $Rule ([string]$script:data.tool_name + ' ' + [string]$script:targetPath)
        }
    } catch {}
}

# ---- 게이트 ① 하니스 자기 보호 (끌 수 없음) ----
$slashed = $targetPath -replace '\\', '/'
$segs = New-Object System.Collections.Generic.List[string]
foreach ($s in ($slashed -split '/')) {
    if ($s -eq '' -or $s -eq '.') { continue }
    if ($s -eq '..') { if ($segs.Count -gt 0) { $segs.RemoveAt($segs.Count - 1) }; continue }
    $segs.Add($s)
}
$norm = '/' + ($segs -join '/')

# 하니스 hook·공유 헬퍼 이름 집합 — post-write-checks.ps1 H2 의 $harnessHo — 근거는 `rules/harness-guard-rationale.md`의 「§2 하니스 hook·공유 헬퍼 이름 집합 — post-write-checks.ps1 H2 의 $harnessHo」
try {
    $hookNames = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rules/harness-hooks.json') -Raw -Encoding UTF8 | ConvertFrom-Json).names
    $harnessHookName = ($hookNames -join '|')
} catch {
    # 이름 집합을 못 읽어도 **경로 축은 그대로 검사한다** — 이름 없이도 `hooks.json`과
    #   `scripts/rules/*.json` 개조는 판정할 수 있고, 그 둘이 꺼지면 차단이 통째로 무력화된다.
    #   종전에는 여기서 exit 0 으로 빠져 자기보호가 통째로 fail-open 이었다.
    [Console]::Error.WriteLine('guard-harness: rules/harness-hooks.json 로드 실패 — 이름 기반 판정만 건너뜁니다(경로 축은 유지).')
    $harnessHookName = '(?!)'
}

# (1) .claude/ 하위 설치본 hook 스크립트·hooks.json·판정 데이터 개조
#   `scripts/rules/*.json`이 대상인 이유: v1.225.0이 차단 패턴과 자기보호 이름 집합을 스크립트
#   밖으로 내렸다. 그 파일을 고치면 차단이 통째로 꺼지는데 스크립트는 한 글자도 안 바뀐다 —
#   보호면이 데이터로 옮겨간 만큼 보호 대상도 따라가야 한다.
$isHookScript = ($norm -match ('/\.claude/.*/(' + $harnessHookName + ')\.ps1$')) -or
                ($norm -match '/\.claude/.*/hooks\.json$') -or
                ($norm -match '(?i)/\.claude/.*/scripts/rules/[^/]+\.json$')
# 규칙 — 근거는 `rules/harness-guard-rationale.md`의 「§3 규칙」
$has83 = ($norm -match '(?i)/CLAUDE~[0-9]+(/|$)')
$suspect83 = $has83 -and
    ($norm -match ('(?i)/(' + $harnessHookName + ')(\.ps1)?(/|$)')) -and  # .claude를 8.3로 숨겨도 hook명이 남음 —
    ($norm -match '(?i)/plugins/cache/')                                  #   단 설치 캐시(.claude/plugins/cache/) 컨텍스트일 때만(근거는 헤더 8.3 처리 참조).

if ($isHookScript -or $suspect83) {
    $why = if ($isHookScript) {
        '.claude/ 하위 설치본 하니스 hook 스크립트·hooks.json·판정 데이터(rules/*.json) 개조'
    } else {
        '8.3 단축명(CLAUDE~1)으로 설치본 하니스 hook 경로를 마스킹한 개조 시도'
    }
    [Console]::Error.WriteLine("BLOCKED: 하니스 안전 hook 개조 시도 감지 — $why")
    [Console]::Error.WriteLine("대상: $targetPath")
    [Console]::Error.WriteLine("하니스 수정은 개발 repo(경로에 .claude 없음)에서 plan 게이트를 거쳐 진행하세요.")
    # [이벤트 로깅] 차단 판정 완료 후 exit 직전 — 로드·호출 실패 전면 격리(차단 동작 무영향).
    try {
        . (Join-Path $PSScriptRoot 'hook-event-log.ps1')
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            Write-HookEvent 'guard-harness' 'block' $why ([string]$targetPath)
        }
    } catch {}
    exit 2
}

# ---- 게이트 ② AGENTS.md 신규 생성은 bootstrap 스킬로만 ----
# AGENTS.md bootstrap 게이트 — 근거는 `rules/write-gate-rationale.md`의 「§2 AGENTS.md bootstrap 게이트」
if ($script:data.tool_name -eq 'Write' -and
    [System.IO.Path]::GetFileName($targetPath) -eq 'AGENTS.md' -and
    -not (Test-Path -LiteralPath $targetPath) -and
    $env:CLAUDE_HARNESS_QUICK -ne '1') {

    # 시스템 임시 폴더는 비대상 — 프로젝트 AGENTS.md가 아니다(아래 임시 폴더 완화와 동일 취지)
    $agentsInTemp = $false
    try {
        $tempRootA = [System.IO.Path]::GetTempPath().TrimEnd('\', '/') -replace '/', '\'
        $tpNormA = $targetPath -replace '/', '\'
        if ($tempRootA -and $tpNormA.StartsWith($tempRootA + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $agentsInTemp = $true }
    } catch { }

    if (-not $agentsInTemp) {
        $bootstrapLaunched = $false
        $tp = [string]$script:data.transcript_path
        if ([string]::IsNullOrWhiteSpace($tp) -or -not (Test-Path -LiteralPath $tp)) {
            $bootstrapLaunched = $true   # fail-open — transcript를 확인할 수 없으면 차단하지 않는다
        } else {
            try {
                $bootstrapLaunched = [bool](Select-String -LiteralPath $tp -Quiet -Pattern @(
                    '"skill"\s*:\s*"pjc:bootstrap-agents-md"',
                    'Launching skill: pjc:bootstrap-agents-md'))
            } catch { $bootstrapLaunched = $true }   # 읽기 실패도 fail-open
        }
        if (-not $bootstrapLaunched) {
            [Console]::Error.WriteLine("[HARNESS] BLOCKED: AGENTS.md 신규 생성은 pjc:bootstrap-agents-md 스킬로만 합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("직접 Write는 스택 템플릿 자산과 사용자 승인 게이트([Y/E/N])를 통째로 우회합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("해결 방법:")
            [Console]::Error.WriteLine("  1) Skill 도구로 pjc:bootstrap-agents-md 호출 → 스택 감지·템플릿 채움 → 사용자 승인 후 저장")
            [Console]::Error.WriteLine("  2) 사용자가 특정 내용을 직접 지정한 경우에도 위 스킬의 [E] 편집 경로로 반영")
            [Console]::Error.WriteLine("  3) 스킬을 호출할 수 없는 상황(도구 제한 등)이면 사용자에게 확인 요청")
            [Console]::Error.WriteLine("  4) 긴급 우회는 사용자만 가능 (Claude Code 시작 전 터미널에서):")
            [Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
            [Console]::Error.WriteLine("     ※ Claude가 Bash 도구로 설정해도 hook 프로세스에 전파되지 않아 무효입니다 — 시도하지 말고,")
            [Console]::Error.WriteLine("       필요하면 사용자에게 위 설정(후 Claude Code 재시작)을 안내하세요.")
            Write-GacEvent 'block' 'AGENTS bootstrap 게이트'
            exit 2
        }
    }
}

# ---- 게이트 ③ AGENTS.md 내용 경계 ----
if ($env:CLAUDE_HARNESS_QUICK -eq '1') { exit 0 }

# 대상 판정 — 파일명이 정확히 AGENTS.md 일 때만
$leaf = ($script:targetPath -replace '\\', '/') -split '/' | Select-Object -Last 1
if ($leaf -ne 'AGENTS.md') { exit 0 }

# 검사할 텍스트 수집 — Write 는 content, Edit 는 new_string, MultiEdit 는 edits[].new_string.
#   **기존 파일에 이미 있던 것은 보지 않는다** — 이 게이트가 막는 것은 "새로 넣는 행위"다.
$chunks = New-Object System.Collections.Generic.List[string]
try {
    $ti = $script:data.tool_input
    if ($ti.content)    { $chunks.Add([string]$ti.content) }
    if ($ti.new_string) { $chunks.Add([string]$ti.new_string) }
    if ($ti.edits) {
        foreach ($e in $ti.edits) { if ($e.new_string) { $chunks.Add([string]$e.new_string) } }
    }
} catch { exit 0 }

if ($chunks.Count -eq 0) { exit 0 }
$text = ($chunks -join "`n")
if ([string]::IsNullOrWhiteSpace($text)) { exit 0 }

# 규칙 — 근거는 `rules/harness-guard-rationale.md`의 「§4 규칙」
$handoffRx = '(?m)^\s{0,3}(#{1,6}\s*|\*\*\s*|[-*+]\s+\*\*\s*|>\s*\*\*\s*)[^\r\n]{0,40}' +
             '(다음\s*작업|다음\s*회차|현재\s*진행\s*상태|진행\s*상황|남긴\s*것|이어서\s*할\s*것|인계|핸드오프|다음\s*세션)'

if ($text -match $handoffRx) {
    [Console]::Error.WriteLine("[차단] AGENTS.md 에 plan 진행 상태·세션 인계 서술을 넣으려 합니다.")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("  검출: `"$($Matches[0].Trim())`"")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("AGENTS.md 는 매 세션 전문이 주입되는 파일이라 진행 상태가 쌓이면 상한(16,384B)을 넘어")
    [Console]::Error.WriteLine("전문 대신 목차만 주입됩니다 — 그 세션은 빌드 명령도 금지선도 모른 채 돕니다.")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("해결 방법:")
    [Console]::Error.WriteLine("  1) 진행 중인 상태 -> plan.md 의 ``## Progress Log``·``## Next Steps``")
    [Console]::Error.WriteLine("  2) 끝난 회차의 기록 -> git 커밋 본문 (영구 기록의 정본)")
    [Console]::Error.WriteLine("  3) 경계 전체 -> plugins/pjc/skills/AGENTS-BOUNDARY.md")
    [Console]::Error.WriteLine("  4) 긴급 우회는 사용자만 가능 (Claude Code 시작 전 터미널에서):")
    [Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
    Write-GacEvent 'block' '인계 서술'
    exit 2
}

# 규칙 — 근거는 `rules/harness-guard-rationale.md`의 「§5 규칙」
$treeLineRx = '[│├└┬┼┤┌┐┘└─]'
$lines = $text -split "`r?`n"
$run = 0
$treeHit = $null
foreach ($ln in $lines) {
    if ($ln -match $treeLineRx) {
        $run++
        if ($run -ge 3) { $treeHit = $ln.Trim(); break }
    } else {
        $run = 0
    }
}

if ($treeHit) {
    [Console]::Error.WriteLine("[차단] AGENTS.md 에 디렉터리 트리를 넣으려 합니다.")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("  검출: `"$treeHit`" (박스 드로잉 3줄 이상 연속)")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("프로젝트 구조는 위키 프로젝트 허브가 정본입니다 — 손으로 유지하는 사본은 리팩토링 때마다")
    [Console]::Error.WriteLine("조용히 낡습니다. 코드를 열면 항상 정확한 것을 AGENTS.md 가 중복 보유할 이유가 없습니다.")
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("해결 방법:")
    [Console]::Error.WriteLine("  1) 구조 설명 -> 위키 허브(``20_projects/…``)의 온보딩 절")
    [Console]::Error.WriteLine("  2) AGENTS.md 에는 위키 포인터 1줄만")
    [Console]::Error.WriteLine("  3) 경계 전체 -> plugins/pjc/skills/AGENTS-BOUNDARY.md")
    [Console]::Error.WriteLine("  4) 긴급 우회는 사용자만 가능 (Claude Code 시작 전 터미널에서):")
    [Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
    Write-GacEvent 'block' '디렉터리 트리'
    exit 2
}

exit 0
