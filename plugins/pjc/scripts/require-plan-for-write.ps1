# PreToolUse hook - PowerShell 버전
# Write/Edit 호출 시 plan.md (또는 docs/plans/) 부재면 차단.
# 문서/설정 파일은 항상 허용.
# 우회: $env:CLAUDE_HARNESS_QUICK = '1'
# 토글: harness-toggle 로 비활성 가능
# exit 2 = block.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 차단 사유가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 (harness-toggle skill로 on/off) ----
$disableFile = Join-Path $HOME ".claude/.disabled/require-plan-for-write"
if (Test-Path -LiteralPath $disableFile) { exit 0 }

# stdin JSON 읽기
$inputJson = [Console]::In.ReadToEnd()

try {
    $data = $inputJson | ConvertFrom-Json
    $targetPath = $data.tool_input.path
    if (-not $targetPath) { $targetPath = $data.tool_input.file_path }
} catch {
    # 파싱 실패 시 통과
    exit 0
}

# 파일 경로가 없으면 통과
if ([string]::IsNullOrWhiteSpace($targetPath)) { exit 0 }

# ---- 항상 허용되는 파일 타입 ----
# 문서, 설정, plan, 이미지·리소스는 plan 없이도 작성 가능
$alwaysAllowedExts = @(
    # 문서
    '.md', '.txt', '.rst',
    # 데이터/설정
    '.json', '.yml', '.yaml', '.toml', '.ini',
    '.editorconfig', '.gitignore', '.gitattributes',
    '.csproj', '.sln', '.props', '.targets',
    '.config',
    # 이미지
    '.svg', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.webp', '.bmp',
    # 리소스
    '.resx', '.resw'
    # 참고: .env.example/.env.sample은 GetExtension이 '.example'/'.sample'을 반환해
    #       확장자 매칭이 안 되므로 아래 파일명 기반 예외에서 처리한다(실제 .env는 제외).
)

$ext = [System.IO.Path]::GetExtension($targetPath).ToLower()
if ($alwaysAllowedExts -contains $ext) { exit 0 }

# .env 템플릿(.env.example/.env.sample)은 plan 없이 허용 (실제 시크릿 파일 .env는 제외)
$baseNameEarly = [System.IO.Path]::GetFileName($targetPath)
if ($baseNameEarly -match '^\.env\.(example|sample)$') { exit 0 }

# 파일명 기반 예외 (확장자 없는 trivial 파일)
$baseName = [System.IO.Path]::GetFileName($targetPath)
$trivialFileNames = @('README', 'CHANGELOG', 'LICENSE', 'CONTRIBUTING', 'NOTICE', 'AUTHORS')
foreach ($name in $trivialFileNames) {
    if ($baseName -match "^$name(\..+)?$") { exit 0 }
}

# Android strings.xml, iOS Localizable.strings, .NET resx 같은 리소스 파일명
if ($baseName -match '^(strings\.xml|Localizable\.strings|Info\.plist)$') { exit 0 }

# ---- 소스 코드 확장자 판정 (디렉터리명 화이트리스트 정밀화에 사용 — T7) ----
# 폴더명만 보고 우회시키면, 도메인 폴더명이 plans/build/docs/dist와 충돌할 때
# 실제 소스(예: src/Models/Plans/PlanService.cs, src/build/Builder.cs)가 plan 없이 통과한다.
# → 아래 '산출물/문서 디렉터리' 우회는 소스 코드 파일에는 적용하지 않는다.
# (문서·설정·이미지·리소스 확장자는 위 alwaysAllowedExts에서 이미 통과했으므로 여기 안 옴.)
$sourceCodeExts = @(
    '.cs', '.vb', '.fs', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.py', '.go', '.rs',
    '.java', '.kt', '.kts', '.cpp', '.cxx', '.cc', '.c', '.h', '.hpp', '.m', '.mm', '.swift',
    '.scala', '.rb', '.php', '.dart', '.lua', '.sql', '.razor', '.vue', '.svelte', '.xaml',
    '.ps1', '.psm1', '.sh', '.bash'
)
$isSourceCode = $sourceCodeExts -contains $ext

# .git, .vs, node_modules, bin, obj — 생성/벤더 디렉터리(손으로 쓰는 소스 아님) → 무조건 허용
if ($targetPath -match '[\\/](\.git|\.vs|node_modules|bin|obj)[\\/]') { exit 0 }

# Android 리소스 디렉터리 (res/values, res/drawable 등) — 무조건 허용
if ($targetPath -match '[\\/]res[\\/](values|drawable|mipmap|layout|raw|xml|color|font|menu|anim)') { exit 0 }

# .claude (하니스 설정·도구) — 무조건 허용
if ($targetPath -match '[\\/]\.claude[\\/]') { exit 0 }

# docs/plans/dist/build — 산출물·문서 디렉터리. 단 '소스 코드 파일이 아닐 때만' 우회한다.
# (폴더명 부분일치가 도메인 소스 폴더 — 예: src/Plans, src/build — 와 충돌해 소스가
#  plan 없이 새는 것을 막는다. 소스면 아래 plan 검사로 떨어진다.)
if (-not $isSourceCode -and (
        ($targetPath -match '[\\/]docs[\\/]') -or
        ($targetPath -match '[\\/]plans?[\\/]') -or
        ($targetPath -match '[\\/](dist|build)[\\/]'))) {
    exit 0
}

# ---- 작은 변경 통과 (Trivial Edit) ----
# Edit/MultiEdit의 변경 규모가 작으면 코드 파일이라도 plan 없이 허용.
# 문구 수정, 라벨 변경, 색상/값 1-2개 변경 등 1분이면 끝나는 작업.
# 시그니처/구조 변경의 cross-file 영향은 PostToolUse impact-warn hook이 별도 검출.
if ($data.tool_name -eq 'Edit' -or $data.tool_name -eq 'MultiEdit') {
    $oldStr = $data.tool_input.old_string
    $newStr = $data.tool_input.new_string

    # MultiEdit은 edits 배열 — 전체 합산
    if ($data.tool_name -eq 'MultiEdit' -and $data.tool_input.edits) {
        $oldStr = ($data.tool_input.edits | ForEach-Object { $_.old_string }) -join "`n"
        $newStr = ($data.tool_input.edits | ForEach-Object { $_.new_string }) -join "`n"
    }

    if ($null -ne $oldStr -and $null -ne $newStr) {
        $oldLines = ($oldStr -split "`n").Count
        $newLines = ($newStr -split "`n").Count
        $maxLines = [Math]::Max($oldLines, $newLines)
        $maxLen = [Math]::Max($oldStr.Length, $newStr.Length)

        # 새 정의(함수/클래스/메서드) 추가 패턴 — 이건 trivial 아님
        $definesNewSymbol = $newStr -match '(?m)\b(class|interface|struct|enum|record)\s+\w' -or
                            $newStr -match '(?m)\b(public|private|protected|internal|static)\s+[\w<>\[\],\s]+\s+\w+\s*\(' -or
                            $newStr -match '(?m)\b(def|func|fun|function)\s+\w+\s*\('

        # 순수 값 치환 감지 (plan-feature Trivial Bypass "순수 값 치환"과 정합):
        # 색상·치수·간격·폰트 크기 등 리터럴 '값'만 바뀌고 식별자·구조·키워드는 동일하면
        # 줄 수·글자 수에 무관하게 trivial로 통과한다(plan-feature는 값이 3개든 10개든 trivial로 봄).
        # old/new에서 hex 색상·숫자(+CSS/XAML 단위)를 토큰으로 정규화한 뒤 동일하면 값만 바뀐 것.
        # @media 신설·레이아웃 방향(flex→grid)·계산식(calc/var) 도입은 텍스트 구조가 바뀌어
        # 정규화 후에도 달라지므로 자동 제외된다.
        $normValue = {
            param([string]$s)
            $c = [char]1 + 'C'   # 소스에 안 나타나는 제어문자 기반 토큰 (PS 5.1 호환)
            $n = [char]1 + 'N'
            $s = [regex]::Replace($s, '#[0-9a-fA-F]{3,8}\b', $c)            # hex 색상 먼저
            $s = [regex]::Replace($s, '\b\d+(\.\d+)?(px|rem|em|pt|%|vh|vw|dp|sp|fr|ch|ex|cm|mm|in|deg)?\b', $n)
            return $s
        }
        $normOld = & $normValue $oldStr
        $normNew = & $normValue $newStr
        # 값이 실제로 하나라도 정규화됐고(치환 대상 존재) + 정규화 후 동일(구조 동일) + 새 정의 아님
        $isPureValueSwap = (-not $definesNewSymbol) -and ($normOld -ne $oldStr) -and ($normOld -eq $normNew)

        # 작은 변경(3줄 + 300자, 새 정의 없음) 또는 순수 값 치환 → trivial 통과
        if (($maxLines -le 3 -and $maxLen -le 300 -and -not $definesNewSymbol) -or $isPureValueSwap) {
            $why = if ($isPureValueSwap) { '순수 값 치환(리터럴만 변경, 구조 동일)' } else { '<=3줄, 새 정의 없음' }
            [Console]::Error.WriteLine("[HARNESS] Trivial edit ($why): plan 검사 우회. 영향은 impact-warn hook이 검증합니다.")
            exit 0
        }
    }
}

# ---- 우회 환경변수 ----
if ($env:CLAUDE_HARNESS_QUICK -eq '1') {
    [Console]::Error.WriteLine("[HARNESS] QUICK 모드: plan 검사 우회")
    exit 0
}

# ---- 프로젝트 루트 결정 ----
# 우선순위: stdin JSON의 cwd → $CLAUDE_PROJECT_DIR → targetPath 기반 git 루트 → 현재 CWD
# Claude Code가 hook을 호출할 때 PowerShell의 CWD가 프로젝트 루트라는 보장이 없으므로
# stdin JSON의 cwd 필드를 신뢰한다 (공식 문서).
$projectRoot = $null
if ($data.cwd) {
    $projectRoot = $data.cwd
}
if (-not $projectRoot -and $env:CLAUDE_PROJECT_DIR) {
    $projectRoot = $env:CLAUDE_PROJECT_DIR
}
if (-not $projectRoot -and (-not [string]::IsNullOrEmpty($targetPath)) -and [System.IO.Path]::IsPathRooted($targetPath)) {
    # targetPath 절대 경로면 거기서 거슬러 올라가 .git 또는 .claude 찾기
    $dir = [System.IO.Path]::GetDirectoryName($targetPath)
    while ($dir) {
        if ((Test-Path -LiteralPath (Join-Path $dir '.git') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $dir '.claude') -PathType Container)) {
            $projectRoot = $dir
            break
        }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
}
if (-not $projectRoot) {
    $projectRoot = (Get-Location).Path
}

# ---- plan 존재 확인 (다중 시작점에서 거슬러 올라가며 검색) ----
# Claude Code가 보낸 cwd가 부정확하거나 작업이 서브디렉터리에서 일어나도
# 부모 어딘가에 plan.md가 있으면 인식하도록 한다.
function Test-PlanInDirectory {
    param([string]$Dir)
    if ([string]::IsNullOrEmpty($Dir)) { return $false }
    # 다음 중 하나라도 있으면 plan 있음으로 간주
    return (Test-Path -LiteralPath (Join-Path $Dir 'plan.md') -PathType Leaf) -or
           (Test-Path -LiteralPath (Join-Path $Dir 'PLAN.md') -PathType Leaf) -or
           (Test-Path -LiteralPath (Join-Path $Dir 'docs\plan.md') -PathType Leaf) -or
           (Test-Path -LiteralPath (Join-Path $Dir 'docs\plans') -PathType Container)
}

function Find-PlanUpwards {
    param([string]$StartDir, [int]$MaxDepth = 8)
    if ([string]::IsNullOrEmpty($StartDir)) { return $null }
    $dir = $StartDir
    for ($i = 0; $i -lt $MaxDepth; $i++) {
        if (-not $dir) { break }
        if (Test-PlanInDirectory -Dir $dir) { return $dir }
        # .git 또는 .claude 만나면 거기까지가 프로젝트 루트 → 더 위로 안 감
        if ((Test-Path -LiteralPath (Join-Path $dir '.git') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $dir '.claude') -PathType Container)) {
            return $null  # 루트인데 plan 없음
        }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# 검색 시작점들 — 어느 하나라도 plan을 찾으면 통과
$searchStarts = @()
if ($data.cwd) { $searchStarts += $data.cwd }
if ($env:CLAUDE_PROJECT_DIR) { $searchStarts += $env:CLAUDE_PROJECT_DIR }
if ((-not [string]::IsNullOrEmpty($targetPath)) -and [System.IO.Path]::IsPathRooted($targetPath)) {
    $searchStarts += [System.IO.Path]::GetDirectoryName($targetPath)
}
$searchStarts += (Get-Location).Path
$searchStarts = $searchStarts | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

$foundIn = $null
foreach ($start in $searchStarts) {
    $found = Find-PlanUpwards -StartDir $start
    if ($found) { $foundIn = $found; break }
}

if ($foundIn) { exit 0 }

# ---- 차단 ----
[Console]::Error.WriteLine("[HARNESS] BLOCKED: 코드 변경 전에 plan이 필요합니다.")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("대상 파일       : $targetPath")
[Console]::Error.WriteLine("결정된 프로젝트 루트: $projectRoot")
[Console]::Error.WriteLine("검색한 시작점들:")
foreach ($s in $searchStarts) {
    [Console]::Error.WriteLine("  - $s")
}
[Console]::Error.WriteLine("찾는 위치 (각 시작점에서 부모로 최대 8단계):")
[Console]::Error.WriteLine("  - plan.md, PLAN.md, docs\plan.md, docs\plans\")
[Console]::Error.WriteLine("위 위치 어디에도 plan이 없습니다.")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("해결 방법:")
[Console]::Error.WriteLine("  1) plan-feature skill 호출:")
[Console]::Error.WriteLine("     사용자에게 '계획 작성해줘' 라고 요청하거나 /plan-feature <설명>")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("  2) 긴급 1줄 수정 우회 (Claude Code 시작 전 PowerShell에서):")
[Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("  3) plan.md 위치 확인:")
[Console]::Error.WriteLine("     루트의 plan.md 파일 위치와 검색 시작점이 다른 경로일 수 있습니다.")
[Console]::Error.WriteLine("     모노레포라면 작업 디렉터리 위쪽에 plan.md 또는 docs\plans\ 가 있어야 합니다.")

exit 2
