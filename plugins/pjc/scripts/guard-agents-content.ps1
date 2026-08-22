# PreToolUse hook - AGENTS.md 내용 경계 게이트
# Write/Edit/MultiEdit 로 AGENTS.md 에 **거기 있으면 안 되는 것**을 넣는 시도를 차단한다.
#   대상 (1) plan 진행 상태·세션 인계 서술("다음 작업"·"다음 회차"·"남긴 것"·진행 상태 표)
#        (2) 디렉터리 트리 블록(프로젝트 구조 — 위키가 정본)
# exit 2 = block.
#
# 배경: AGENTS.md 는 SessionStart 가 **매 세션 전문을 주입**하는데(session-context.ps1), 무엇을
#   넣으면 안 되는지의 규정이 없어 계속 자랐다. 실측으로 한 프로젝트의 AGENTS.md 가 174,642B(주입
#   상한 16,384B 의 10.7배)까지 커졌고 그 안에 plan 인계 서술이 224줄 들어 있었다. 상한을 넘기면
#   전문 대신 목차만 주입되므로 **그 세션은 빌드 명령도 금지선도 모른 채 돈다**.
#   내용 경계의 정본은 docs/harness-conventions.md 「AGENTS.md 내용 경계」다.
#
# ⚠️ 이 hook 은 토글 가능하다(block-destructive·protect-harness 와 다른 점).
#   - 안전 임계가 아니라 **내용 품질 게이트**라 정당한 편집을 막을 여지가 있다.
#   - 우회 변수는 CLAUDE_HARNESS_QUICK — require-plan-for-write 의 AGENTS bootstrap 게이트가
#     같은 파일을 대상으로 이미 그 변수를 쓰므로, 여기서 다른 변수를 쓰면 사용자가 둘을 구분해야 한다.
#
# ⚠️ 판정 범위 (의도적으로 좁게 잡음 — 오차단이 미탐보다 비싸다):
#   - 파일명이 정확히 AGENTS.md 인 경우만 본다(AGENTS-old.md·docs/AGENTS.md 등은 비대상).
#   - 트리 블록은 **박스 드로잉 문자가 3줄 이상 연속**할 때만 잡는다 — 명령 예시의 단발 파이프나
#     한두 줄짜리 경로 나열을 트리로 오인하지 않기 위함이다.
#   - 인계 서술은 **헤딩·볼드 제목 형태**일 때만 잡는다 — 본문 산문에 "다음 작업"이 스쳐 지나가는
#     것까지 막으면 정상 문장이 걸린다.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 차단 사유가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin 도 UTF-8 로 디코딩 — 한글이 든 경로·본문이 깨지면 판정이 어긋난다.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# [이벤트 로깅] 차단 이벤트를 오탐 리뷰 데이터로 적재 — 게이트 판정은 무변경, 실패 전면 격리.
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}
function Write-GacEvent {
    param([string]$Decision, [string]$Rule)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            Write-HookEvent 'guard-agents-content' $Decision $Rule ([string]$script:data.tool_name + ' ' + [string]$script:targetPath)
        }
    } catch {}
}

$inputJson = [Console]::In.ReadToEnd()

try {
    $script:data = $inputJson | ConvertFrom-Json
    $script:targetPath = $script:data.tool_input.path
    if (-not $script:targetPath) { $script:targetPath = $script:data.tool_input.file_path }
} catch {
    exit 0    # 파싱 실패 시 통과 (다른 hook 과 동형 — fail-open)
}

if ([string]::IsNullOrWhiteSpace($script:targetPath)) { exit 0 }

# 사용자 우회 (require-plan-for-write 의 AGENTS 게이트와 같은 변수)
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

# ---- (1) plan 진행 상태·세션 인계 서술 ----
# 헤딩(`## …`) 또는 볼드 제목(`**…**`) 또는 목록 제목 형태일 때만 잡는다.
#   본문 산문에 스쳐 지나가는 "다음 작업"까지 막으면 정상 문장이 걸린다.
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
    [Console]::Error.WriteLine("  3) 경계 전체 -> docs/harness-conventions.md 「AGENTS.md 내용 경계」")
    [Console]::Error.WriteLine("  4) 긴급 우회는 사용자만 가능 (Claude Code 시작 전 터미널에서):")
    [Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
    Write-GacEvent 'block' '인계 서술'
    exit 2
}

# ---- (2) 디렉터리 트리 블록 ----
# **박스 드로잉 문자를 포함한 줄이 3줄 이상 연속**일 때만.
#   ⚠ ASCII 파이프(`|`)는 판정에 넣지 않는다 — `ls | grep x` 같은 명령 예시와 마크다운 표가
#     전부 걸린다. 트리를 그리는 실제 문자는 박스 드로잉이고, ASCII 트리(`|-- src/`)를 놓치는
#     대신 오차단 0을 택했다(이 게이트는 미탐보다 오탐이 비싸다).
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
    [Console]::Error.WriteLine("  3) 경계 전체 -> docs/harness-conventions.md 「AGENTS.md 내용 경계」")
    [Console]::Error.WriteLine("  4) 긴급 우회는 사용자만 가능 (Claude Code 시작 전 터미널에서):")
    [Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
    Write-GacEvent 'block' '디렉터리 트리'
    exit 2
}

exit 0
