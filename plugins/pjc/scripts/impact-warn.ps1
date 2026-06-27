# PostToolUse hook - PowerShell 버전
# Write/Edit 후 변경된 public/internal/export 심볼의 caller를 grep으로 찾아
# stderr 경고 출력 (차단 X).
# Claude가 이 경고를 받고 자동으로 caller 검증하도록 유도.
#
# 토글: harness-toggle 로 비활성 가능 (impact-warn)

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 ----
$disableFile = Join-Path $HOME ".claude/.disabled/impact-warn"
if (Test-Path -LiteralPath $disableFile) { exit 0 }

# stdin JSON 읽기
$inputJson = [Console]::In.ReadToEnd()

try {
    $data = $inputJson | ConvertFrom-Json
    $file = $data.tool_input.path
    if (-not $file) { $file = $data.tool_input.file_path }
} catch {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($file)) { exit 0 }
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 0 }

# Claude Code가 hook을 어디서 실행하든 프로젝트 루트로 이동 (git 명령이 .git을 찾을 수 있도록)
if ($data.cwd -and (Test-Path -LiteralPath $data.cwd -PathType Container)) {
    Set-Location -LiteralPath $data.cwd
} elseif ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR -PathType Container)) {
    Set-Location -LiteralPath $env:CLAUDE_PROJECT_DIR
}

# 코드 파일만 검사
$codeExts = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.go', '.rs', '.cpp', '.c', '.h', '.hpp', '.fs', '.kt', '.swift')
$ext = [System.IO.Path]::GetExtension($file).ToLower()
if ($codeExts -notcontains $ext) { exit 0 }

# git 저장소가 아니면 통과
$gitDir = & git rev-parse --git-dir 2>$null
if (-not $gitDir -or $LASTEXITCODE -ne 0) { exit 0 }

# ---- 변경된 public/internal 심볼 추출 ----
# git diff에서 +로 시작하는 라인 중 선언 패턴 검색

$diffLines = & git diff HEAD -- $file 2>$null
if (-not $diffLines -or $LASTEXITCODE -ne 0) { exit 0 }

$symbols = New-Object System.Collections.Generic.HashSet[string]

foreach ($line in $diffLines) {
    if (-not $line.StartsWith('+')) { continue }
    if ($line.StartsWith('+++')) { continue }

    # 언어별 패턴
    $patterns = @(
        # C#: public/internal/protected 메서드/클래스/속성
        '^\+.*\b(public|internal|protected)\s+(?:static\s+|virtual\s+|override\s+|sealed\s+|abstract\s+|async\s+|partial\s+)*(?:[\w<>\[\],\?]+\s+)?(?<sym>[A-Z][a-zA-Z0-9_]*)\s*[\(\<\{]',
        # TypeScript/JavaScript: export function/class/const/interface
        '^\+\s*export\s+(?:default\s+)?(?:async\s+)?(?:function|class|const|interface|type|enum)\s+(?<sym>[a-zA-Z_][a-zA-Z0-9_]*)',
        # Python: def/class (underscore prefix 제외)
        '^\+\s*(?:async\s+)?(?:def|class)\s+(?<sym>[A-Za-z][a-zA-Z0-9_]*)',
        # Kotlin: fun/class (internal/public 또는 명시 없음)
        '^\+\s*(?:(?:public|internal|open|sealed|abstract|data)\s+)*(?:fun|class|interface|object)\s+(?<sym>[A-Z][a-zA-Z0-9_]*)',
        # Go: 대문자 시작 함수
        '^\+\s*func\s+(?:\([^)]*\)\s+)?(?<sym>[A-Z][a-zA-Z0-9_]*)\s*\(',
        # Rust: pub fn/struct/enum
        '^\+\s*pub\s+(?:fn|struct|enum|trait)\s+(?<sym>[a-zA-Z_][a-zA-Z0-9_]*)'
    )

    foreach ($pattern in $patterns) {
        $m = [regex]::Match($line, $pattern)
        if ($m.Success) {
            $sym = $m.Groups['sym'].Value
            # 너무 짧거나 일반적인 이름은 제외 (false positive 방지)
            if ($sym.Length -ge 4 -and $sym -notmatch '^(get|set|is|has)$') {
                [void]$symbols.Add($sym)
            }
        }
    }
}

if ($symbols.Count -eq 0) { exit 0 }

# ---- 변경된 심볼에 대해 caller grep ----

# 변경 파일 자체의 디렉터리 + 상위 src/tests 디렉터리 검색
$searchRoot = '.'
if (Test-Path -LiteralPath 'src') { $searchRoot = 'src' }

$warnings = New-Object System.Collections.Generic.List[string]
$normalizedFile = $file -replace '\\', '/'

foreach ($sym in $symbols) {
    # grep으로 \b<sym>\b 검색
    $grepOut = & git grep -n --untracked -E "\b$sym\b" 2>$null
    if (-not $grepOut) { continue }

    # 결과에서 변경 파일 자신과 binary/no-match 라인 제외
    $callers = @()
    foreach ($g in $grepOut) {
        if ($g -match '^([^:]+):(\d+):') {
            $callerFile = $matches[1] -replace '\\', '/'
            if ($callerFile -eq $normalizedFile) { continue }

            # 같은 확장자나 코드 파일만 (test도 포함)
            $callerExt = [System.IO.Path]::GetExtension($callerFile).ToLower()
            if ($codeExts -notcontains $callerExt) { continue }

            $callers += "$($matches[1]):$($matches[2])"
        }
    }

    if ($callers.Count -gt 0) {
        $warnings.Add("심볼 '$sym' 참조 발견 (caller가 함께 갱신되었는지 확인):")
        foreach ($c in ($callers | Select-Object -First 8)) {
            $warnings.Add("  - $c")
        }
        if ($callers.Count -gt 8) {
            $warnings.Add("  ... 그 외 $($callers.Count - 8)개")
        }
    }
}

# ---- 출력 ----
if ($warnings.Count -gt 0) {
    $lines = @("[IMPACT WARNING] $file 의 public/internal 심볼이 변경되었습니다.")
    $lines += $warnings
    $lines += ""
    $lines += "위 caller 파일들의 동작이 변경되었을 수 있습니다."
    $lines += "각 파일을 Read로 열어 영향을 검증하고, 필요 시 함께 수정하세요."
    $lines += "이 경고는 차단이 아닙니다. 끄려면: harness-toggle impact-warn off"
    $msg = $lines -join "`n"

    # stderr: 디버그/사용자 가시성용
    [Console]::Error.WriteLine($msg)

    # stdout JSON: PostToolUse additionalContext로 모델에 전달 (exit 0 비차단).
    # stderr는 exit 2일 때만 모델로 가므로, 비차단 경고는 이 경로로 모델에 닿게 한다.
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}

exit 0
