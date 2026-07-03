# PreToolUse hook - PowerShell 버전
# git commit 명령이 'T<N>:' 완료 커밋인데 plan의 해당 task 체크박스가 아직 [ ]/[/]면 차단.
# implement-task Phase D 규약("체크박스 [x] 갱신 → commit")을 지침이 아니라 구조로 강제한다
# (결정론적 검증 게이트 — 어기면 다음 단계로 진행 자체가 안 되게).
#
# [설계: fail-open — 판정이 모호하면 전부 침묵 통과]
#   이 hook은 플러그인이 켜진 모든 프로젝트의 Bash/PowerShell git commit에 발동하므로,
#   확실한 위반(단일 plan 파일에 해당 T<N> 미완료 체크박스가 실재)일 때만 차단한다.
#   - git commit 아님 / 메시지에 T<N>: 패턴 없음(checkpoint: T3 start 등) → 통과
#   - plan 파일 없음 / 읽기 실패 / stdin 파싱 실패 → 통과
#   - docs/plans/ 복수 plan만 존재 → 통과 (분할 plan은 T번호가 파일마다 재시작이라 판정 모호)
#   - plan에 해당 T<N> 체크박스 줄 자체가 없음 → 통과 (타 규약 프로젝트 보호)
#
# 우회: $env:CLAUDE_HARNESS_QUICK = '1'
# 토글: harness-toggle 로 비활성 가능 (require-task-checkbox)
# exit 2 = block.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 차단 사유가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 (harness-toggle skill로 on/off) ----
# 홈 경로: Claude Code 홈과 정합 — Windows는 USERPROFILE(없으면 $HOME 폴백), 비Windows는 $HOME
$base = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$disableFile = Join-Path $base ".claude/.disabled/require-task-checkbox"
if (Test-Path -LiteralPath $disableFile) { exit 0 }

# stdin JSON 읽기 (Bash·PowerShell 도구 모두 tool_input.command 필드를 가진다)
$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
} catch {
    # 파싱 실패 시 통과 (fail-open)
    exit 0
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# ---- git commit 명령이 아니면 즉시 통과 (fast path) ----
# 프리픽스 패턴은 warn-external-ops와 동일 (git -C <dir> commit / git -c k=v commit 매칭 유지).
if ($cmd -notmatch 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { exit 0 }

# ---- 완료 커밋 판정: 첫 'T<N>:' 매치만 사용 ----
# 대소문자 구분([regex]::Match 기본) — Phase D 규약은 대문자 T. 첫 매치만 보는 이유:
# Phase D 커밋 제목이 'T<N>: <요약>'으로 시작하고, 본문(Type:/Build:/Tests: 등)에는
# 'T<N>:' 패턴이 없어 첫 매치가 곧 제목이다. 본문의 타 task 언급 오탐을 막는다.
# 'checkpoint: T3 start'는 N 뒤에 콜론이 없어 자연 불일치. 'T1\b'은 T10을 오매치하지 않는다.
$m = [regex]::Match($cmd, '\bT(\d+)\s*:')
if (-not $m.Success) { exit 0 }
$taskNum = $m.Groups[1].Value

# ---- 우회 환경변수 ----
if ($env:CLAUDE_HARNESS_QUICK -eq '1') {
    [Console]::Error.WriteLine("[HARNESS] QUICK 모드: T$taskNum 체크박스 검사 우회")
    exit 0
}

# ---- 단일 plan 파일 탐색 (시작점들에서 거슬러 올라가며) ----
# require-plan-for-write와 동일한 상향 탐색이되, '단일 plan 파일'만 찾는다.
# docs/plans/ 디렉터리(복수 plan)는 어느 파일 기준인지 모호하므로 판정하지 않는다
# (선례: require-plan-for-write G4 완료-plan 경고도 단일 plan 파일만 판정).
function Find-SinglePlanUpwards {
    param([string]$StartDir, [int]$MaxDepth = 8)
    if ([string]::IsNullOrEmpty($StartDir)) { return $null }
    $dir = $StartDir
    for ($i = 0; $i -lt $MaxDepth; $i++) {
        if (-not $dir) { break }
        foreach ($cand in @('plan.md', 'PLAN.md', 'docs/plan.md')) {
            $pf = Join-Path $dir $cand
            if (Test-Path -LiteralPath $pf -PathType Leaf) { return $pf }
        }
        # .git 또는 .claude 만나면 거기까지가 프로젝트 루트 → 더 위로 안 감
        if ((Test-Path -LiteralPath (Join-Path $dir '.git') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $dir '.claude') -PathType Container)) {
            return $null  # 루트인데 단일 plan 파일 없음
        }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# 시작점은 '하나만' 쓴다 (cwd → CLAUDE_PROJECT_DIR → Get-Location 순 첫 유효값).
# require-plan-for-write는 여러 시작점 합집합을 쓰지만 그건 '찾으면 통과' 방향이라 안전하고,
# 이 hook은 '찾으면 차단' 방향이라 무관한 시작점(예: hook 프로세스의 Get-Location)에서 주운
# 다른 plan으로 오차단할 수 있다 — 커밋이 일어나는 프로젝트(cwd)만 신뢰한다 (fail-open).
$startDir = $null
if ($data.cwd) { $startDir = $data.cwd }
elseif ($env:CLAUDE_PROJECT_DIR) { $startDir = $env:CLAUDE_PROJECT_DIR }
else { $startDir = (Get-Location).Path }

$planFile = Find-SinglePlanUpwards -StartDir $startDir
if (-not $planFile) { exit 0 }

# ---- 체크박스 판정 ----
try {
    $planText = Get-Content -LiteralPath $planFile -Raw -Encoding UTF8
} catch {
    exit 0
}
if ([string]::IsNullOrWhiteSpace($planText)) { exit 0 }

# 미완료 마커 [ ]/[/] + 해당 task 번호 (줄 시작의 '- [ ] T<N>' 형태만).
# 'T$taskNum\b'라 T1이 T10에 오매치하지 않는다. [x]/[X]이거나 T<N> 줄 자체가 없으면 통과.
$unchecked = [regex]::Match($planText, "(?m)^\s*-\s*\[[ /]\]\s*T$taskNum\b")
if (-not $unchecked.Success) { exit 0 }

# ---- 차단 ----
$foundLine = $unchecked.Value.Trim()
if ($foundLine.Length -gt 80) { $foundLine = $foundLine.Substring(0, 80) + '...' }

[Console]::Error.WriteLine("[HARNESS] BLOCKED: T$taskNum 완료 커밋인데 plan의 T$taskNum 체크박스가 아직 미완료입니다.")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("plan 파일 : $planFile")
[Console]::Error.WriteLine("발견한 줄 : $foundLine")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("implement-task Phase D 규약: 완료 커밋 전에 해당 task 체크박스를 [x]로 갱신합니다.")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("해결 방법:")
[Console]::Error.WriteLine("  1) plan의 해당 줄을 '- [x] T$taskNum ...'으로 갱신한 뒤 다시 commit")
[Console]::Error.WriteLine("  2) 이 프로젝트가 pjc plan 규약(T<N> task)을 쓰지 않는다면:")
[Console]::Error.WriteLine("     harness-toggle require-task-checkbox off")
[Console]::Error.WriteLine("  3) 긴급 우회 (Claude Code 시작 전 PowerShell에서):")
[Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")

exit 2
