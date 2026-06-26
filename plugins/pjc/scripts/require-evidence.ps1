# Stop hook - PowerShell 버전
# 에이전트가 작업 종료를 시도할 때 실행.
# 마지막 커밋에 검증 증거가 없으면 stderr 경고 (강제 차단 X).
# 토글: harness-toggle 로 비활성 가능.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 ----
$disableFile = Join-Path $env:USERPROFILE ".claude\.disabled\require-evidence"
if (Test-Path -LiteralPath $disableFile) { exit 0 }

# stdin JSON에서 cwd 추출 (Claude Code가 hook을 어디서 실행하든 프로젝트 루트로 이동)
$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
    if ($data.cwd -and (Test-Path -LiteralPath $data.cwd -PathType Container)) {
        Set-Location -LiteralPath $data.cwd
    }
} catch { }
if ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR -PathType Container)) {
    Set-Location -LiteralPath $env:CLAUDE_PROJECT_DIR
}

# git 저장소인지 확인 (현재 작업 디렉터리 기준)
$gitDir = & git rev-parse --git-dir 2>$null
if (-not $gitDir -or $LASTEXITCODE -ne 0) {
    exit 0
}

# 마지막 커밋 메시지 가져오기 (다중 줄 메시지는 배열로 캡처되므로 단일 문자열로 합침 — 배열에 -notmatch 하면 줄 단위 필터가 되어 오탐)
$lastMsgRaw = & git log -1 --pretty=%B 2>$null
if (-not $lastMsgRaw) { exit 0 }
$lastMsg = ($lastMsgRaw -join "`n")

$firstLine = ($lastMsg -split "`n")[0].Trim()

# 1. checkpoint만 있고 후속 커밋 없음
if ($firstLine -match '^checkpoint:') {
    [Console]::Error.WriteLine("STOP WARNING: 마지막 커밋이 checkpoint입니다 - task가 완료되지 않았을 수 있습니다.")
    [Console]::Error.WriteLine("implement-task의 Phase D를 완료하지 않은 채 종료하려 합니다.")
    [Console]::Error.WriteLine("정말 종료할 거면 사용자에게 현재 상태를 보고하세요.")
}

# 2. task 커밋이지만 증거 없음
if ($firstLine -match '^T\d+:') {
    if ($lastMsg -notmatch 'Build|Tests|Review') {
        [Console]::Error.WriteLine("STOP WARNING: task 커밋에 검증 증거(Build/Tests/Review)가 누락되었습니다.")
        [Console]::Error.WriteLine("Done = Proof 원칙 위반 가능 - 커밋 메시지를 갱신하거나 사용자에게 보고하세요.")
    }
}

exit 0
