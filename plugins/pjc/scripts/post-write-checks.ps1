# PostToolUse hook — 근거는 `rules/post-write-rationale.md`의 「§1 PostToolUse hook」

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로·명령이 깨진다(경로 판정·경고 문구가 함께 손상). 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- stdin JSON 1회 읽기 (두 검사 공유 — 같은 입력을 두 번 읽지 않음) ----
$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
    $file = $data.tool_input.path
    if (-not $file) { $file = $data.tool_input.file_path }
    if (-not $file) { $file = $data.tool_input.notebook_path }   # NotebookEdit (require-plan-for-write와 동일 폴백 사슬)
} catch {
    exit 0
}
if ([string]::IsNullOrWhiteSpace($file)) { exit 0 }
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 0 }

# 두 검사의 경고를 합쳐 단일 stderr + 단일 additionalContext로 출력한다(모델 수신 정보는 분리 hook 때와 동일).
$allMsgs = New-Object System.Collections.Generic.List[string]

# 경고 디듑 마커 — 근거는 `rules/post-write-rationale.md`의 「§2 경고 디듑 마커」
$pwStateDir = Join-Path $env:USERPROFILE '.claude/.state/post-write-warn'
try { New-Item -Force -ItemType Directory -Path $pwStateDir | Out-Null } catch {}
# 30일 지난 마커 자동 정리 — 마커는 세션×파일×경고 종류당 1개라 방치하면 무한 축적된다 — 근거는 `rules/post-write-rationale.md`의 「§3 30일 지난 마커 자동 정리 — 마커는 세션×파일×경고 종류당 1개라 방치하면 무한 축적된다」
try {
    Get-ChildItem -LiteralPath $pwStateDir -File -ErrorAction Stop |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}
$pwSid = if ($data.session_id) { ([string]$data.session_id) -replace '[^\w.-]', '_' } else { 'nosid' }
function Test-WarnOnce {
    param([string]$Key)
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Key)) | ForEach-Object { $_.ToString('x2') }) -join ''
        $mk = Join-Path $pwStateDir ($pwSid + '_' + $hash)
        if (Test-Path -LiteralPath $mk) { return $false }
        New-Item -Force -ItemType File -Path $mk | Out-Null
        return $true
    } catch { return $true }   # 마커 실패 시 경고 누락보다 중복이 낫다(fail-open)
}

# H2: 하니스 hook 개조 감지 — 근거는 `rules/post-write-rationale.md`의 「§4 H2: 하니스 hook 개조 감지」
$normFileH2 = $file -replace '\\', '/'
# 이름 집합은 `rules/harness-hooks.json`이 단일 정본이다 — 탐지(이 파일)와 차단(guard-harness)이
#   같은 값을 써야 대칭이 성립하는데, 복제하면 hook 신설 시 한쪽만 갱신돼 그 이름이 무방비가 된다.
$harnessHookName = ''
try {
    $harnessHookName = ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rules/harness-hooks.json') -Raw -Encoding UTF8 | ConvertFrom-Json).names -join '|')
} catch {}
# 8.3 단축명 마스킹 감지 — 근거는 `rules/post-write-rationale.md`의 「§5 8.3 단축명 마스킹 감지」
$has83H2 = ($normFileH2 -match '(?i)/CLAUDE~[0-9]+(/|$)')
$suspect83H2 = $has83H2 -and
    ($normFileH2 -match ('(?i)/(' + $harnessHookName + ')(\.ps1)?(/|$)')) -and
    ($normFileH2 -match '(?i)/plugins/cache/')
if ($normFileH2 -match "/($harnessHookName)\.ps1$" -or $normFileH2 -match '/hooks/hooks\.json$') {
    # 문구 중립화 + 세션·파일당 1회 (v1.98.0): 개발 repo의 정상 hook 개발 편집에도 "개조 시도" 프레임이
    #   매번 붙던 것을 검증 리마인더로 낮춘다(설치본 개조 '차단'은 protect-harness 소관 — 여긴 리마인더).
    if (Test-WarnOnce ('hooksrc|' + $normFileH2)) {
        $allMsgs.Add("[HARNESS] 하니스 hook 스크립트 변경: $file")
        $allMsgs.Add("  hook 동작 변경은 골든 회귀(run-hook-evals.ps1)로 검증하세요. (세션·파일당 1회 리마인더)")
        $allMsgs.Add("")
    }
} elseif ($suspect83H2) {
    $allMsgs.Add("[HARNESS] 8.3 단축명(CLAUDE~1) 마스킹 경로 감지: $file")
    $allMsgs.Add("  설치본 hook 경로를 단축명으로 숨긴 개조 시도일 수 있습니다 — 의도된 것인지 확인하세요.")
    $allMsgs.Add("")
} elseif ($normFileH2 -match '/\.claude/settings\.json$') {
    # M2: 홈·프로젝트 .claude/settings.json의 enabledPlugins는 하니스 전체를 끌 수 있다(hook보다 상위 무력화면).
    #   settings.local.json은 $ 앵커 정확 매칭이라 여기 걸리지 않는다.
    $allMsgs.Add("[HARNESS] .claude/settings.json 변경 감지: $file")
    $allMsgs.Add("  enabledPlugins로 하니스 전체를 끄는 변경일 수 있습니다 — 의도된 설정 변경인지 확인하세요.")
    $allMsgs.Add("")
}

# ============================================================ — 근거는 `rules/post-write-rationale.md`의 「§6 ============================================================」
    try {
        $utf8Warnings = New-Object System.Collections.Generic.List[string]

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
                    $utf8Warnings.Add("BOM 발견 - UTF-8 (BOM 없음)으로 저장 필요")
                }
            } catch {
                # 읽기 실패 시 무시
            }
        }

        # ---- 파일 내용 1회 읽기 (영문 주석·시크릿 검사가 공유) ----
        $raw = $null
        $content = $null
        try {
            $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop
            if ($null -ne $raw) { $content = $raw -split '\r?\n' }
        } catch {
            # 바이너리 등 읽기 불가 파일은 각 검사의 $null 가드로 조용히 통과
        }

        # ---- 2. 영문 주석 비율 (코드 파일만) ----
        # 주석 검사용 코드 확장자 — impact 섹션의 caller 검색용 목록($codeExtsImpact)과 다르므로 분리 유지.
        $extComment = [System.IO.Path]::GetExtension($file).ToLower()
        $codeExtsComment = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.go', '.rs', '.cpp', '.c', '.h', '.hpp', '.fs', '.kt', '.swift')

        if (($codeExtsComment -contains $extComment) -and $null -ne $content) {
            # 언어별 주석 접두 (v1.98.0): 종전 '// 또는 #' 일괄 판정은 C 계열의 전처리 지시문
            #   (#region/#if/#pragma — 주석 아님)을 영문 주석으로 오집계했다. .py만 #, 나머지는 //.
            $commentPrefix = if ($extComment -eq '.py') { '^\s*#' } else { '^\s*//' }
            $commentLines = $content | Where-Object { $_ -match $commentPrefix }
            $totalComments = @($commentLines).Count

            if ($totalComments -gt 5) {
                # 한글 음절 유니코드 범위 (AC00-D7AF)
                $hangulRegex = [regex]'[가-힯]'
                $engComments = @($commentLines | Where-Object { -not $hangulRegex.IsMatch($_) }).Count

                # 세션·파일당 1회 (v1.98.0): 의도적으로 영어를 쓰는 프로젝트(OSS 등)에서 그 파일을 만질
                #   때마다 반복 주입돼 기존 영어 주석의 한글화(범위 초과 수정)로 오도하던 것 억제.
                if ($engComments -gt ($totalComments / 2) -and (Test-WarnOnce ('engcomment|' + ($file -replace '\\', '/')))) {
                    $utf8Warnings.Add("주석이 대부분 영문($engComments/$totalComments). 한글 주석 규칙 위반 가능 — 단 프로젝트가 의도적으로 영어 주석을 쓰면 그 관례를 따르세요(기존 주석의 일괄 한글화는 범위 초과). (세션·파일당 1회)")
                }
            }
        }

        # # ---- 민감 정보 검사 — 근거는 `rules/post-write-rationale.md`의 「§7 # ---- 민감 정보 검사」
        $skipSecretScan = $file -match '\.(env|env\..*)$' -or $file -match '(^|[\\/])\.git[\\/]'
        if ((-not $skipSecretScan) -and $raw) {
            # # ---- 스캔 범위: 추적 파일은 HEAD 대비 미커밋 추가 라인만 — 근거는 `rules/post-write-rationale.md`의 「§8 # ---- 스캔 범위: 추적 파일은 HEAD 대비 미커밋 추가 라인만」
            $scanText = $raw
            try {
                $fileDir = Split-Path -Parent $file
                if ($fileDir -and (Test-Path -LiteralPath $fileDir -PathType Container)) {
                    $null = & git -C $fileDir ls-files --error-unmatch -- $file 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $diffOut = @(& git -C $fileDir diff HEAD --unified=0 -- $file 2>$null)
                        # # diff 성공 여부를 반드시 확인한다: ls-files는 staged 파일이면 HEAD 없이도 — 근거는 `rules/post-write-rationale.md`의 「§9 # diff 성공 여부를 반드시 확인한다: ls-files는 staged 파일이면 HEAD 없이도」
                        if ($LASTEXITCODE -eq 0) {
                            $added = @($diffOut |
                                Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') } |
                                ForEach-Object { $_.Substring(1) })
                            # 추가 라인 0줄(삭제만 있거나 HEAD와 동일) = 스캔할 신규 내용이 없다
                            $scanText = if ($added.Count -gt 0) { $added -join "`n" } else { '' }
                        }
                        # diff 실패면 $scanText는 위에서 넣은 $raw 그대로 — 전재 폴백
                    }
                }
            } catch {
                $scanText = $raw   # git 호출 실패는 전재 폴백 (fail-open)
            }

            . (Join-Path $PSScriptRoot 'secret-patterns.ps1')
            foreach ($label in @(Get-SecretMatches $scanText)) {
                $utf8Warnings.Add("민감 정보로 보이는 내용 감지: $label. 실제 값을 파일에 남기지 말고, 환경변수 이름만 기록하거나 .env(gitignore)로 분리하세요. (이 파일은 git/스냅샷으로 보존될 수 있음)")
            }
        }

        # 섹션 1 경고를 기존 check-utf8 출력 형식 그대로 묶어 합산 리스트에 추가
        if ($utf8Warnings.Count -gt 0) {
            $allMsgs.Add("POST-WRITE WARNINGS for ${file}:")
            foreach ($w in $utf8Warnings) { $allMsgs.Add("  [!] $w") }
            $allMsgs.Add("")
            $allMsgs.Add("수정 후 다시 저장하거나, 이유와 함께 plan.md에 follow-up으로 기록하세요.")
        }
    } catch {
        # 섹션 1 전체 실패는 섹션 2 실행을 막지 않는다(격리 — 분리 프로세스였을 때와 동일하게 독립).
    }

# ============================================================ — 근거는 `rules/post-write-rationale.md`의 「§10 ============================================================」
    try {
        if ($data.cwd -and (Test-Path -LiteralPath $data.cwd -PathType Container)) {
            Set-Location -LiteralPath $data.cwd
        } elseif ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR -PathType Container)) {
            Set-Location -LiteralPath $env:CLAUDE_PROJECT_DIR
        }

        # # 코드 파일만 검사 — 근거는 `rules/post-write-rationale.md`의 「§11 # 코드 파일만 검사」
        $codeExtsImpact = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.go', '.rs', '.cpp', '.c', '.h', '.hpp', '.fs', '.kt', '.swift', '.vb', '.xaml', '.razor', '.vue', '.svelte', '.sql')
        $extImpact = [System.IO.Path]::GetExtension($file).ToLower()

        if ($codeExtsImpact -contains $extImpact) {
            # git 저장소일 때만 진행
            $gitDir = & git rev-parse --git-dir 2>$null
            if ($gitDir -and $LASTEXITCODE -eq 0) {
                # ---- 변경된 public/internal 심볼 추출 (git diff의 + 라인) ----
                $diffLines = & git diff HEAD -- $file 2>$null
                if ($diffLines -and $LASTEXITCODE -eq 0) {
                    $symbols = New-Object System.Collections.Generic.HashSet[string]

                    foreach ($line in $diffLines) {
                        if (-not $line.StartsWith('+')) { continue }
                        if ($line.StartsWith('+++')) { continue }

                        # 언어별 선언 패턴
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
                            '^\+\s*pub\s+(?:fn|struct|enum|trait)\s+(?<sym>[a-zA-Z_][a-zA-Z0-9_]*)',
                            # VB.NET: Public/Friend/Protected Sub/Function/Class/Property 등 (C# 자매 언어)
                            '^\+\s*(?:Public|Friend|Protected(?:\s+Friend)?)\s+(?:Shared\s+|Overrides\s+|Overridable\s+|MustOverride\s+|NotOverridable\s+|ReadOnly\s+|WriteOnly\s+)*(?:Sub|Function|Class|Property|Interface|Structure|Enum|Module)\s+(?<sym>[A-Z][a-zA-Z0-9_]*)'
                        )

                        foreach ($pattern in $patterns) {
                            $m = [regex]::Match($line, $pattern)
                            if ($m.Success) {
                                $sym = $m.Groups['sym'].Value
                                # # 너무 짧거나 일반적인 이름은 제외 — 근거는 `rules/post-write-rationale.md`의 「§12 # 너무 짧거나 일반적인 이름은 제외」
                                if ($sym.Length -ge 4 -and
                                    $sym -notmatch '^(?i)(get|set|is|has|name|type|data|text|value|item|key|count|index|result|state|status|title|content|message)$') {
                                    [void]$symbols.Add($sym)
                                }
                            }
                        }
                    }

                    if ($symbols.Count -gt 0) {
                        $impactWarnings = New-Object System.Collections.Generic.List[string]
                        $normalizedFile = $file -replace '\\', '/'

                        # 모든 변경 심볼을 한 번의 git grep으로 검색 (심볼당 git 프로세스를 N번 띄우지 않고 1번으로 통합).
                        # 결과는 아래서 심볼별로 재귀속한다 — 출력(심볼별 caller 목록)은 분리 hook 때와 동일하다.
                        $symAlt = ($symbols | ForEach-Object { [regex]::Escape($_) }) -join '|'
                        $grepOut = & git grep -n --untracked -E "\b($symAlt)\b" 2>$null

                        foreach ($sym in $symbols) {
                            # 배치 grep 결과에서 이 심볼에 해당하는 caller만 추림
                            $callers = @()
                            foreach ($g in $grepOut) {
                                if ($g -match '^([^:]+):(\d+):(.*)$') {
                                    # -match 가 $matches 를 덮어쓰므로 그룹을 먼저 지역 변수로 보관
                                    $callerFileRaw = $matches[1]
                                    $callerLine = $matches[2]
                                    $callerContent = $matches[3]

                                    $callerFile = $callerFileRaw -replace '\\', '/'
                                    # git grep 경로는 cwd 상대라 절대경로($normalizedFile)와 그대로 비교되지 않음 —
                                    # 절대경로로 정규화해 비교해야 "자기 파일을 자기 caller로 오탐"하지 않는다.
                                    $callerAbs = if ([System.IO.Path]::IsPathRooted($callerFileRaw)) { $callerFile }
                                                 else { (Join-Path (Get-Location).Path $callerFileRaw) -replace '\\', '/' }
                                    if ($callerAbs -ieq $normalizedFile) { continue }

                                    # 같은 확장자나 코드 파일만 (test도 포함)
                                    $callerExt = [System.IO.Path]::GetExtension($callerFile).ToLower()
                                    if ($codeExtsImpact -notcontains $callerExt) { continue }

                                    # 배치 grep이라 한 라인이 여러 심볼을 매치할 수 있으므로, 이 라인이 현재 심볼을 포함할 때만 귀속
                                    if ($callerContent -notmatch "\b$sym\b") { continue }

                                    $callers += "${callerFileRaw}:${callerLine}"
                                }
                            }

                            if ($callers.Count -gt 0) {
                                # # 세션·파일·심볼당 1회 — 근거는 `rules/post-write-rationale.md`의 「§13 # 세션·파일·심볼당 1회」
                                if (-not (Test-WarnOnce ('impact|' + $normalizedFile + '|' + $sym))) { continue }
                                # 매치 상한 (v1.98.0): 참조 30건 초과는 흔한 이름/광범위 심볼 — caller 나열이
                                #   무관 파일 다독을 유도하므로 나열 대신 요약 1줄만 남긴다.
                                if ($callers.Count -gt 30) {
                                    $impactWarnings.Add("심볼 '$sym' 참조 $($callers.Count)건 (>30) — 흔한 이름이거나 광범위 심볼로 판단해 caller 나열을 생략합니다. 시그니처·계약을 바꿨다면 직접 grep으로 확인하세요.")
                                    continue
                                }
                                $impactWarnings.Add("심볼 '$sym' 참조 발견 (caller가 함께 갱신되었는지 확인):")
                                foreach ($c in ($callers | Select-Object -First 8)) {
                                    $impactWarnings.Add("  - $c")
                                }
                                if ($callers.Count -gt 8) {
                                    $impactWarnings.Add("  ... 그 외 $($callers.Count - 8)개")
                                }
                            }
                        }

                        # 섹션 2 경고를 기존 impact-warn 출력 형식 그대로 묶어 합산 리스트에 추가
                        if ($impactWarnings.Count -gt 0) {
                            $allMsgs.Add("[IMPACT WARNING] $file 의 public/internal 심볼이 변경되었습니다.")
                            foreach ($w in $impactWarnings) { $allMsgs.Add($w) }
                            $allMsgs.Add("")
                            $allMsgs.Add("위 caller 파일들의 동작이 변경되었을 수 있습니다.")
                            $allMsgs.Add("각 파일을 Read로 열어 영향을 검증하고, 필요 시 함께 수정하세요.")
                            $allMsgs.Add("이 경고는 차단이 아닙니다 — 검토 후 진행하세요.")
                        }
                    }
                }
            }
        }
    } catch {
        # 섹션 2 실패는 섹션 1 결과(이미 $allMsgs에 있음)에 영향 없음(격리).
    }

# ============================================================ — 근거는 `rules/post-write-rationale.md`의 「§14 ============================================================」
if ($allMsgs.Count -gt 0) {
    $msg = ($allMsgs -join "`n")

    # stderr: 사용자 가시성용
    [Console]::Error.WriteLine($msg)

    # [이벤트 로깅] 경고 방출 시 1건 적재 — 검사 판정 무변경, 실패 전면 격리.
    try {
        . (Join-Path $PSScriptRoot 'hook-event-log.ps1')
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            Write-HookEvent 'post-write-checks' 'warn' ([string]$allMsgs[0]) ([string]$file)
        }
    } catch {}

    # stdout JSON: PostToolUse additionalContext로 모델에 전달 (exit 0 비차단).
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}

exit 0
