# PostToolUse hook - PowerShell 버전
# Write/Edit 후 자동 검증:
#   1) UTF-8 BOM 검사
#   2) 1500라인 초과 경고
#   3) 영문 주석 비율 경고
# exit 2로 차단하지 않고 stderr 경고만 출력.
# 토글: harness-toggle 로 비활성 가능.

$ErrorActionPreference = 'SilentlyContinue'

# ---- 토글 체크 ----
$disableFile = Join-Path $env:USERPROFILE ".claude\.disabled\check-utf8-and-lines"
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
            $warnings.Add("파일 라인 수 $lineCount (>1500). 기능 단위 분리 권장 - plan에 분리 task 등록.")
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

# ---- 출력 ----
if ($warnings.Count -gt 0) {
    [Console]::Error.WriteLine("POST-WRITE WARNINGS for ${file}:")
    foreach ($w in $warnings) {
        [Console]::Error.WriteLine("  [!] $w")
    }
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("수정 후 다시 저장하거나, 이유와 함께 plan.md에 follow-up으로 기록하세요.")
}

exit 0
