# PreToolUse hook - 커밋 시점 시크릿 스캔 (경고, 비차단)
# Bash/PowerShell 도구로 'git commit'을 실행하기 직전, 스테이징될 변경에서 시크릿 패턴을 스캔해
#   stderr + additionalContext로 경고한다(exit 0 비차단). 편집 시점의 post-write-checks가 놓친
#   경로(하니스 밖 편집·이미 편집된 파일)의 "커밋 직전 최종 방어선".
#
# [설계: 왜 비차단(exit 0)인가]
#   정규식 시크릿 탐지는 오탐(설정의 IP·테스트 픽스처 등)이 있어, 차단하면 정상 커밋을 막는다.
#   차단(exit 2)은 안전 임계 hook 4종(block-destructive·protect-harness·require-plan-for-write·
#   require-task-checkbox)에만 두는 하니스 컨벤션과도 맞춰, 이 hook은 경고만 한다(AGENTS.md hook 출력 규약).
#
# [스캔 범위 — plan D3 '철저']
#   ① git diff --cached (명시적 스테이징분)의 추가(+) 줄
#   ② git commit -a/-am/--all 이면 git diff HEAD 도 스캔(추적 파일 자동 스테이징분)
#   ③ 스테이징된 .env/.env.* 파일명 자체를 경고(시크릿의 정당한 위치가 커밋되는 것이 곧 유출)
#
# [알려진 한계]
#   git -C <다른repo> commit 은 cwd repo를 스캔한다(다른 repo 미스캔 — 드묾).
#   .env 파일명 경고는 --cached(명시적 git add -f 스테이징분)만 대상 — untracked .env는 통상
#   gitignore라 -am가 스테이징하지 않아 실사용 gap 없음.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- stdin JSON 읽기 (command) ----
$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
} catch {
    exit 0   # 파싱 실패 시 통과 (경고 실패가 차단보다 안전)
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# ---- git commit 명령이 아니면 즉시 통과 (fast path) ----
# 프리픽스 패턴은 warn-external-ops·require-task-checkbox와 동일(git -C <dir> / git -c k=v commit 매칭 유지).
if ($cmd -notmatch 'git\s+((-c|-C)\s+\S+\s+)*commit\b') { exit 0 }
# 실제 커밋이 아닌 형태는 스캔 불필요: --dry-run(모의)·-h/--help(도움말).
if ($cmd -match '--dry-run' -or $cmd -match '--help' -or $cmd -match '(^|\s)-h(\s|$)') { exit 0 }

# ---- 작업 디렉터리 결정 (post-write-checks와 동일 폴백) ----
if ($data.cwd -and (Test-Path -LiteralPath $data.cwd -PathType Container)) {
    Set-Location -LiteralPath $data.cwd
} elseif ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR -PathType Container)) {
    Set-Location -LiteralPath $env:CLAUDE_PROJECT_DIR
}

# ---- git repo 아니면 통과 (fail-open) ----
$gitDir = & git rev-parse --git-dir 2>$null
if (-not $gitDir -or $LASTEXITCODE -ne 0) { exit 0 }

# ---- 스테이징 추가(+) 줄 수집 ----
# --unified=0: 컨텍스트 줄 없이 추가/삭제만. +++ 헤더는 제외하고 실제 추가 내용 줄만 모은다.
# @(...)로 매번 배열 고정 — 파일 1개·줄 1개일 때 스칼라로 언랩돼 뒤 파이프/조인이 오작동하는 것을 막는다.
$addedLines = @(@(& git diff --cached --unified=0 2>$null) |
    Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })

# -a/-am/--all 이면 추적 파일 자동 스테이징분(git diff HEAD)도 스캔.
# --amend는 자동 스테이징이 아니므로 여기 해당 안 됨(-[..]a[..] 단문자 클러스터 또는 --all만).
# 먼저 커밋 메시지(-m/--message) '값'만 제거한다 — 메시지 텍스트 속 '-a'를 자동 스테이징 플래그로
#   오인(예: git commit -m 'fix -a bug')하지 않게 하되, 플래그 토큰 자체(-am의 a)는 보존해
#   실제 -am의 자동 스테이징 신호는 유지한다(block-destructive의 메시지 스트립과 동일 기법 — 값만 제거).
$cmdFlags = $cmd -replace '(?i)(^|\s)(-[a-zA-Z]*m|--message)(=|\s+)("[^"]*"|''[^'']*''|\S+)', '$1$2'
$autoStage = ($cmdFlags -match '(^|\s)-[a-zA-Z]*a[a-zA-Z]*(\s|$)') -or ($cmdFlags -match '(^|\s)--all(\s|$)')
if ($autoStage) {
    $addedLines += @(@(& git diff HEAD --unified=0 2>$null) |
        Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })
}

# 선행 '+' 제거 후 내용만 이어붙여 스캔.
$scanText = (@($addedLines | ForEach-Object { $_.Substring(1) }) -join "`n")

# ---- 시크릿 패턴 스캔 (공유 모듈) ----
. (Join-Path $PSScriptRoot 'secret-patterns.ps1')
$hits = @(Get-SecretMatches $scanText)

# ---- 스테이징된 .env 파일명 검사 ----
$envFiles = New-Object System.Collections.Generic.List[string]
$staged = & git diff --cached --name-only 2>$null
if ($staged) {
    foreach ($n in $staged) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $base = [System.IO.Path]::GetFileName($n)
        if ($base -match '^\.env(\..*)?$') { $envFiles.Add($n) }
    }
}

if ($hits.Count -eq 0 -and $envFiles.Count -eq 0) { exit 0 }

# ---- 경고 출력 (비차단) ----
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("[COMMIT SECRET WARNING] 커밋될 스테이징된 변경에서 민감 정보로 보이는 내용이 감지되었습니다:")
foreach ($h in ($hits | Select-Object -Unique)) { $lines.Add("  - $h") }
foreach ($e in $envFiles) { $lines.Add("  - .env 파일 스테이징: $e (시크릿 파일이 커밋에 포함되려 합니다)") }
$lines.Add("")
$lines.Add("실제 값을 커밋하지 말고, .env(gitignore)로 분리하거나 스테이징에서 제외(git restore --staged <파일>)하세요.")
$lines.Add("이 경고는 차단이 아닙니다 — 검토 후 진행하세요.")
$msg = ($lines -join "`n")

# stderr: 사용자 가시성용
[Console]::Error.WriteLine($msg)

# stdout JSON: PreToolUse additionalContext로 모델에 전달 (exit 0 비차단).
$payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
[Console]::Out.WriteLine($payload)

exit 0
