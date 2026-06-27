# Stop hook - PowerShell 버전
# 에이전트가 작업 종료를 시도할 때 실행.
# 마지막 커밋에 검증 증거가 없으면 stderr 경고 (강제 차단 X — 의도된 비차단).
#
# [설계: 왜 비차단(exit 0 + stderr)인가 — 공식 Stop hook 시맨틱 확인 결과]
#   Stop hook 피드백 경로는 셋: exit 2(=종료 차단 + stderr를 모델에 전달) /
#   stdout JSON additionalContext(=종료 안 막고 '대화 계속' → 모델에 컨텍스트 주입) /
#   exit 0 + stderr(=비차단, 사용자 transcript용, 모델엔 미전달).
#   이 hook은 implement-task 종료뿐 아니라 '모든' 종료 시도(일반 대화·질문 답변 후 포함)에
#   발동하므로, 차단(exit 2)이나 대화-계속(additionalContext)으로 바꾸면 무관한 종료까지
#   막거나 루프를 유발한다. 따라서 의도적으로 exit 0 + stderr 소프트 리마인더로 둔다
#   (사용자가 transcript에서 보고 판단; 모델 강제는 안 함). 이 동작을 차단으로 바꾸지 말 것.
#
# 토글: harness-toggle 로 비활성 가능.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 ----
# 홈 경로: Claude Code 홈과 정합 — Windows는 USERPROFILE(없으면 $HOME 폴백), 비Windows는 $HOME
$base = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$disableFile = Join-Path $base ".claude/.disabled/require-evidence"
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
