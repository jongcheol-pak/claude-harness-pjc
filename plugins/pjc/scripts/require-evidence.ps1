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

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

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

# 2. task 커밋이지만 검증 '결과' 증거 없음
# 단어만(Build/Tests/Review)이 아니라 '결과 동반 패턴'을 요구한다(G4) — "Review: 안 함"처럼
# 단어만 있고 결과가 없는 빈 증거가 통과하지 못하게 한다.
# 결과 패턴: Build ...OK/성공, Tests N(개수), Review ...OK/spec/quality/통과 중 하나.
$evidenceRx = '(Build[^\r\n]*\b(OK|pass|passed|성공)\b)|(Tests?\s*[:=]?\s*\d)|(Review[^\r\n]*\b(OK|spec|quality|passed|통과)\b)'
$hasEvidence = $false
if ($firstLine -match '^T\d+:') {
    if ($lastMsg -notmatch $evidenceRx) {
        [Console]::Error.WriteLine("STOP WARNING: task 커밋에 검증 '결과' 증거가 없습니다 (예: Build ...OK / Tests N / Review ...OK).")
        [Console]::Error.WriteLine("Done = Proof 원칙 위반 가능 - 단어만이 아니라 실제 결과를 커밋 메시지에 적거나 사용자에게 보고하세요.")
    } else {
        $hasEvidence = $true
    }
}

# 2-1. transcript 실행 흔적 대조 — 커밋의 증거 '텍스트'가 실제 실행 없이 적혔을 가능성 검출.
# T커밋에 증거 텍스트가 있을 때만, 이 세션 transcript(JSONL)에서 빌드/테스트 명령 호출 흔적을 찾는다.
# 판정은 휴리스틱이다: tool 호출의 "command" 필드 근처 명령 패턴만 세어, 본문·문서에 적힌 명령
# 텍스트로 인한 오탐을 줄이되 완전하지는 않다(정교한 위조 방어가 아니라 정직한 누락의 소프트 리마인더).
# transcript 포맷은 비공식 내부 형식이므로 파일 부재·읽기 실패·포맷 변경 시 조용히 건너뛴다(비차단 유지).
# 최근 활동은 파일 끝에 있으므로 끝쪽 3000줄만 본다(대형 transcript 전체 스캔 캡 — 무매치 경로가 최악이라 상한 필수).
if ($hasEvidence) {
    try {
        $tp = if ($data) { $data.transcript_path } else { $null }
        if ($tp -and (Test-Path -LiteralPath $tp -PathType Leaf)) {
            $tail = Get-Content -LiteralPath $tp -Tail 3000 -ErrorAction Stop
            $traceRx = '"command"\s*:\s*".{0,600}?(dotnet (build|test)|npm (test|run )|npx |yarn |pnpm |pytest|cargo (build|test)|gradlew?\b|go (build|test)|mvn |msbuild|make |ctest|python(3)? -m (py_compile|build|pytest)|ParseFile)'
            if (-not (($tail -join "`n") -match $traceRx)) {
                [Console]::Error.WriteLine("STOP WARNING: 커밋에 검증 증거 텍스트는 있으나 이 세션 transcript에서 빌드/테스트 실행 흔적을 찾지 못했습니다.")
                [Console]::Error.WriteLine("증거가 실행 없이 적혔을 수 있습니다 - 실제로 빌드/테스트를 실행했는지 확인하세요 (이전 세션에서 실행했으면 무시).")
            }
        }
    } catch { }
}

# 3. 코드 파일 미커밋 변경 검출 (G6) — 구현 후 commit 누락 가능성 경고 (비차단)
# 일반 대화·문서(.md)만 변경한 종료에는 안 뜨도록 '코드 확장자' 변경만 본다.
$codeExts = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.go', '.rs', '.cpp', '.c', '.h', '.hpp', '.fs', '.kt', '.swift', '.vb', '.razor', '.xaml', '.vue', '.svelte')
$porcelain = & git status --porcelain 2>$null
if ($porcelain) {
    $codeChanges = New-Object System.Collections.Generic.List[string]
    foreach ($pl in $porcelain) {
        if ($pl.Length -lt 4) { continue }
        $p = $pl.Substring(3).Trim().Trim('"')
        if ($p -match '->') { $p = ($p -split '->')[-1].Trim().Trim('"') }   # rename은 새 경로 기준
        $e = [System.IO.Path]::GetExtension($p).ToLower()
        if ($codeExts -contains $e) { [void]$codeChanges.Add($p) }
    }
    if ($codeChanges.Count -gt 0) {
        [Console]::Error.WriteLine("STOP WARNING: 커밋되지 않은 코드 파일 변경이 $($codeChanges.Count)개 있습니다 - 구현 후 commit을 누락했을 수 있습니다.")
        foreach ($c in ($codeChanges | Select-Object -First 8)) { [Console]::Error.WriteLine("  - $c") }
        [Console]::Error.WriteLine("구현이 끝났으면 Phase D(commit)를 수행하거나, 의도된 미커밋이면 사용자에게 상태를 보고하세요.")
    }
}

exit 0
