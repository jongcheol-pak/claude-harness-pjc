# PostToolUse hook - PowerShell 버전
# Write/Edit 후 자동 검증:
#   1) UTF-8 BOM 검사
#   2) 1500라인 초과 경고
#   3) 영문 주석 비율 경고
# exit 2로 차단하지 않고 stderr 경고만 출력.
# 토글: harness-toggle 로 비활성 가능.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 ----
$disableFile = Join-Path $HOME ".claude/.disabled/check-utf8-and-lines"
if (Test-Path -LiteralPath $disableFile) { exit 0 }

$inputJson = [Console]::In.ReadToEnd()

try {
    $data = $inputJson | ConvertFrom-Json
    $file = $data.tool_input.path
    if (-not $file) { $file = $data.tool_input.file_path }
} catch {
    exit 0
}

# 파일 없거나 존재하지 않으면 통과
if ([string]::IsNullOrWhiteSpace($file)) { exit 0 }
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 0 }

$warnings = New-Object System.Collections.Generic.List[string]

# ---- 1. BOM 검사 ----
# .ps1 파일은 PowerShell 5.x 호환성 위해 BOM 필요. 검사에서 제외.
$extLower = [System.IO.Path]::GetExtension($file).ToLower()
if ($extLower -ne '.ps1') {
    try {
        $stream = [System.IO.File]::OpenRead($file)
        $bytes = New-Object byte[] 3
        $read = $stream.Read($bytes, 0, 3)
        $stream.Close()

        if ($read -eq 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $warnings.Add("BOM 발견 - UTF-8 (BOM 없음)으로 저장 필요")
        }
    } catch {
        # 읽기 실패 시 무시
    }
}

# ---- 2. 라인 수 검사 ----
# 자동 생성 파일은 수천 라인이 정상이므로 제외 (경고 노이즈 방지)
$isGenerated = $file -match '\.(Designer|designer)\.cs$' -or
               $file -match '\.g(\.i)?\.cs$' -or
               $file -match '\.generated\.\w+$' -or
               $file -match '\.(resx|resw)$' -or
               $file -match '(^|[\\/])(obj|bin)[\\/]' -or
               $file -match '\.min\.(js|css)$' -or
               $file -match '(package-lock\.json|yarn\.lock|Cargo\.lock|go\.sum)$'

try {
    if (-not $isGenerated) {
        $lineCount = (Get-Content -LiteralPath $file -ErrorAction Stop | Measure-Object -Line).Lines
        if ($lineCount -gt 1500) {
            $warnings.Add("파일 라인 수 $lineCount (>1500). 분리 '검토' 신호 - 여러 독립 책임이 섞였으면 책임 단위로 분리, 단일 책임인데 길 뿐이면 그대로 둔다(억지 분리는 지역성을 해침). 분리 시 plan에 등록.")
        }
    }
} catch {
    # 바이너리 등 읽기 불가 파일은 무시
}

# ---- 3. 영문 주석 비율 (코드 파일만) ----
$ext = [System.IO.Path]::GetExtension($file).ToLower()
$codeExts = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.go', '.rs', '.cpp', '.c', '.h', '.hpp', '.fs', '.kt', '.swift')

if ($codeExts -contains $ext) {
    try {
        $content = Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop

        # // 또는 # 로 시작하는 라인
        $commentLines = $content | Where-Object { $_ -match '^\s*(//|#)' }
        $totalComments = @($commentLines).Count

        if ($totalComments -gt 5) {
            # 한글 유니코드 범위 (AC00-D7AF: 가-힣)
            $hangulRegex = [regex]'[\uAC00-\uD7AF]'
            $engComments = @($commentLines | Where-Object { -not $hangulRegex.IsMatch($_) }).Count

            if ($engComments -gt ($totalComments / 2)) {
                $warnings.Add("주석이 대부분 영문($engComments/$totalComments). 한글 주석 규칙 위반 가능.")
            }
        }
    } catch {
        # 인코딩 문제 등은 무시
    }
}

# ---- 민감 정보 검사 (문서·코드 모두, 경고만) ----
# notes.md/plan.md/wiki 등 생성 문서나 코드에 실제 시크릿 값이 남는 것을 방지.
# 실제 '값' 패턴만 잡고 단순 언급(예: "password 필드 추가")은 통과시켜 과잉 경고를 피한다.
$skipSecretScan = $file -match '\.(env|env\..*)$' -or $file -match '(^|[\\/])\.git[\\/]'
if (-not $skipSecretScan) {
    try {
        $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop
        if ($raw) {
            $secretPatterns = @(
                @{ rx = '(?i)(password|passwd|pwd)\s*[:=]\s*["'']?[^\s"''<>{}$]{3,}'; label = 'password 값' },
                @{ rx = '(?i)(api[_-]?key|apikey|access[_-]?token|secret[_-]?key|auth[_-]?token|client[_-]?secret)\s*[:=]\s*["'']?[A-Za-z0-9_\-]{8,}'; label = 'API key/token 값' },
                @{ rx = '(?i)(Server|Data Source)=[^;]+;\s*(User|Uid|Password|Pwd)='; label = 'DB 연결 문자열' },
                @{ rx = '(?i)(mongodb(\+srv)?|postgres|postgresql|mysql|redis|amqp)://[^\s]+:[^\s]+@'; label = 'DB/서비스 URI 인증정보' },
                @{ rx = '-----BEGIN [A-Z ]*PRIVATE KEY-----'; label = '개인키' },
                @{ rx = '(?i)Bearer\s+[A-Za-z0-9_\-\.]{16,}'; label = 'Bearer 토큰' },
                @{ rx = '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b'; label = 'IP 주소' }
            )
            foreach ($sp in $secretPatterns) {
                if ($raw -match $sp.rx) {
                    # localhost/예약 IP 등 안전한 값은 IP 경고에서 제외
                    if ($sp.label -eq 'IP 주소') {
                        $m = [regex]::Match($raw, $sp.rx).Value
                        if ($m -eq '127.0.0.1' -or $m -eq '0.0.0.0' -or $m -eq '255.255.255.255' -or $m -like '0.0.0.*') { continue }
                        # 버전 문자열(AssemblyVersion/FileVersion/<Version>/v1.0.0.0 등) 오탐 제외
                        if ($raw -match "(?i)(version|v)\s*[>=:]?\s*[`"']?$([regex]::Escape($m))") { continue }
                    }
                    $warnings.Add("민감 정보로 보이는 내용 감지: $($sp.label). 실제 값을 파일에 남기지 말고, 환경변수 이름만 기록하거나 .env(gitignore)로 분리하세요. (이 파일은 git/스냅샷으로 보존될 수 있음)")
                }
            }
        }
    } catch {
        # 읽기 실패는 무시 (다른 검사에서 이미 처리)
    }
}

# ---- 출력 ----
if ($warnings.Count -gt 0) {
    $lines = @("POST-WRITE WARNINGS for ${file}:")
    foreach ($w in $warnings) { $lines += "  [!] $w" }
    $lines += ""
    $lines += "수정 후 다시 저장하거나, 이유와 함께 plan.md에 follow-up으로 기록하세요."
    $msg = $lines -join "`n"

    [Console]::Error.WriteLine($msg)

    # PostToolUse additionalContext로 모델에 전달 (exit 0 비차단)
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}

exit 0
