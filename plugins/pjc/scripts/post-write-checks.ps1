# PostToolUse hook (병합) - PowerShell 버전
# Write/Edit/MultiEdit/NotebookEdit 후 두 검사를 한 프로세스에서 수행한다:
#   [check-utf8-and-lines] BOM 검사 · 1500라인 초과 경고 · 영문 주석 비율 · 민감 정보
#   [impact-warn]          변경된 public/internal 심볼의 caller 경고
#
# 두 검사는 각각 독립 토글로 끌 수 있다(.disabled/check-utf8-and-lines, .disabled/impact-warn).
# 한 검사의 오류가 다른 검사를 막지 않도록 각 섹션을 try/catch로 격리한다.
# 원래 2개 PostToolUse hook이 매 편집마다 PowerShell 프로세스를 2번 띄우던 것을 1번으로 통합(성능).
# exit 2 차단 없음(비차단) — 경고만 stderr + additionalContext로 출력. 토글: harness-toggle.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 (두 검사 각각 독립) ----
# 홈 경로: Claude Code 홈과 정합 — Windows는 USERPROFILE(없으면 $HOME 폴백), 비Windows는 $HOME
$base = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$disableUtf8   = Test-Path -LiteralPath (Join-Path $base ".claude/.disabled/check-utf8-and-lines")
$disableImpact = Test-Path -LiteralPath (Join-Path $base ".claude/.disabled/impact-warn")
# 두 토글이 모두 꺼져 있어도 조기 종료하지 않는다(T2) — 아래 H2(안전 게이트 자기 비활성화·hook 개조 감지)는
#   토글과 무관하게 항상 발화해야 한다. 두 검사(섹션 1/2)는 각자 $disableUtf8/$disableImpact 로 개별 가드하고,
#   H2만 토글 독립으로 stdin·경로 파싱 직후 실행한다. (둘 다 꺼졌고 H2 비대상이면 $allMsgs가 비어 무출력 exit 0.)

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

# ---- H2: 하니스 게이트 자기 비활성화·hook 개조 감지 (안전 게이트 감시, 비차단) ----
# require-plan은 .claude 하위 쓰기를 무조건 허용하므로, 에이전트가 Write로 .disabled 게이트 끄기 파일을
#   만들거나 hook 스크립트를 개조해 게이트를 무력화할 수 있다(H2). PostToolUse라 예방은 못 하지만
#   그 시도를 가시화한다. 정상 harness-toggle 경유 토글도 여기 걸리지만 경고(비차단)라 무해.
$normFileH2 = $file -replace '\\', '/'
$harnessHookName = 'block-destructive|require-plan-for-write|require-task-checkbox|require-evidence|post-write-checks|warn-external-ops|suggest-agents-record|harness-toggle|protect-harness'
# 8.3 단축명 마스킹 감지(H3) — protect-harness.ps1의 $suspect83과 동일 술어(탐지↔차단 대칭).
#   실제 마스킹 형태(CLAUDE~N·DISABL~N) + 방어 키워드(.claude/.disabled/hook명) 잔존일 때만 감지 —
#   일반 8.3 세그먼트(PROGRA~1·RUNNER~1)는 미매치라 개발 repo 편집에 무영향.
$has83H2 = ($normFileH2 -match '(?i)/(CLAUDE|DISABL)~[0-9]+(/|$)')
$suspect83H2 = $has83H2 -and (
    ($normFileH2 -match '(?i)\.disabled(/|$)') -or
    ($normFileH2 -match '(?i)\.claude(/|$)') -or
    ($normFileH2 -match ('(?i)/(' + $harnessHookName + ')(\.ps1)?(/|$)')))
if ($normFileH2 -match '/\.claude/\.disabled/\S') {
    $allMsgs.Add("[HARNESS] 게이트 비활성화 파일 생성 감지: $file")
    $allMsgs.Add("  안전 게이트(plan·checkbox 등)를 끄는 동작일 수 있습니다 — 의도된 것인지 확인하세요(정상 harness-toggle 경유면 무시).")
    $allMsgs.Add("")
} elseif ($normFileH2 -match "/($harnessHookName)\.ps1$" -or $normFileH2 -match '/hooks/hooks\.json$') {
    $allMsgs.Add("[HARNESS] 하니스 hook 스크립트 변경 감지: $file")
    $allMsgs.Add("  안전 hook을 개조/약화하는 변경일 수 있습니다 — 의도된 것인지, 골든 회귀(run-hook-evals.ps1)로 검증했는지 확인하세요.")
    $allMsgs.Add("")
} elseif ($suspect83H2) {
    $allMsgs.Add("[HARNESS] 8.3 단축명(CLAUDE~1·DISABL~1) 마스킹 경로 감지: $file")
    $allMsgs.Add("  하니스 경로를 단축명으로 숨긴 게이트 무력화 시도일 수 있습니다 — 의도된 것인지 확인하세요.")
    $allMsgs.Add("")
} elseif ($normFileH2 -match '/\.claude/settings\.json$') {
    # M2: 홈·프로젝트 .claude/settings.json의 enabledPlugins는 하니스 전체를 끌 수 있다(hook보다 상위 무력화면).
    #   settings.local.json은 $ 앵커 정확 매칭이라 여기 걸리지 않는다.
    $allMsgs.Add("[HARNESS] .claude/settings.json 변경 감지: $file")
    $allMsgs.Add("  enabledPlugins로 하니스 전체를 끄는 변경일 수 있습니다 — 의도된 설정 변경인지 확인하세요.")
    $allMsgs.Add("")
}

# =====================================================================
# 섹션 1: check-utf8-and-lines (BOM · 라인 수 · 영문 주석 · 민감 정보)
#   절대경로($file)만 쓰므로 cwd에 의존하지 않는다 → 섹션 2의 Set-Location 앞에 둔다.
# =====================================================================
if (-not $disableUtf8) {
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

        # ---- 파일 내용 1회 읽기 (라인 수·영문 주석·시크릿 검사가 공유) ----
        $raw = $null
        $content = $null
        try {
            $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop
            if ($null -ne $raw) { $content = $raw -split '\r?\n' }
        } catch {
            # 바이너리 등 읽기 불가 파일은 각 검사의 $null 가드로 조용히 통과
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

        if ((-not $isGenerated) -and $null -ne $content) {
            # $content 는 끝 개행 뒤 빈 요소를 포함할 수 있어 Get-Content 기준으로 보정 (라인 수 정확도 유지)
            $lineCount = @($content).Count
            if ($raw.EndsWith("`n")) { $lineCount-- }
            if ($lineCount -gt 1500) {
                $utf8Warnings.Add("파일 라인 수 $lineCount (>1500). 분리 '검토' 신호 - 여러 독립 책임이 섞였으면 책임 단위로 분리, 단일 책임인데 길 뿐이면 그대로 둔다(억지 분리는 지역성을 해침). 분리 시 plan에 등록.")
            }
        }

        # ---- 3. 영문 주석 비율 (코드 파일만) ----
        # 주석 검사용 코드 확장자 — impact 섹션의 caller 검색용 목록($codeExtsImpact)과 다르므로 분리 유지.
        $extComment = [System.IO.Path]::GetExtension($file).ToLower()
        $codeExtsComment = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.go', '.rs', '.cpp', '.c', '.h', '.hpp', '.fs', '.kt', '.swift')

        if (($codeExtsComment -contains $extComment) -and $null -ne $content) {
            # 내용은 위에서 1회 읽은 $content 재사용 (// 또는 # 로 시작하는 라인)
            $commentLines = $content | Where-Object { $_ -match '^\s*(//|#)' }
            $totalComments = @($commentLines).Count

            if ($totalComments -gt 5) {
                # 한글 음절 유니코드 범위 (AC00-D7AF)
                $hangulRegex = [regex]'[가-힯]'
                $engComments = @($commentLines | Where-Object { -not $hangulRegex.IsMatch($_) }).Count

                if ($engComments -gt ($totalComments / 2)) {
                    $utf8Warnings.Add("주석이 대부분 영문($engComments/$totalComments). 한글 주석 규칙 위반 가능.")
                }
            }
        }

        # ---- 민감 정보 검사 (문서·코드 모두, 경고만) ----
        # notes.md/plan.md/wiki 등 생성 문서나 코드에 실제 시크릿 값이 남는 것을 방지.
        # 실제 '값' 패턴만 잡고 단순 언급(예: "password 필드 추가")은 통과시켜 과잉 경고를 피한다.
        $skipSecretScan = $file -match '\.(env|env\..*)$' -or $file -match '(^|[\\/])\.git[\\/]'
        if ((-not $skipSecretScan) -and $raw) {
            $secretPatterns = @(
                @{ rx = '(?i)(password|passwd|pwd)\s*[:=]\s*["'']?[^\s"''<>{}$]{3,}'; label = 'password 값' },
                @{ rx = '(?i)(api[_-]?key|apikey|access[_-]?token|secret[_-]?key|auth[_-]?token|client[_-]?secret)\s*[:=]\s*["'']?[A-Za-z0-9_\-]{8,}'; label = 'API key/token 값' },
                @{ rx = '(?i)(Server|Data Source)=[^;]+;\s*(User|Uid|Password|Pwd)='; label = 'DB 연결 문자열' },
                @{ rx = '(?i)(mongodb(\+srv)?|postgres|postgresql|mysql|redis|amqp)://[^\s]+:[^\s]+@'; label = 'DB/서비스 URI 인증정보' },
                @{ rx = '-----BEGIN [A-Z ]*PRIVATE KEY-----'; label = '개인키' },
                @{ rx = '(?i)Bearer\s+[A-Za-z0-9_\-\.]{16,}'; label = 'Bearer 토큰' },
                @{ rx = '\b(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\b'; label = 'IP 주소' }   # L5: 옥텟 0-255 제한 — 999.999.999.999 등 IP 아닌 숫자열 오탐 완화
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
                    $utf8Warnings.Add("민감 정보로 보이는 내용 감지: $($sp.label). 실제 값을 파일에 남기지 말고, 환경변수 이름만 기록하거나 .env(gitignore)로 분리하세요. (이 파일은 git/스냅샷으로 보존될 수 있음)")
                }
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
}

# =====================================================================
# 섹션 2: impact-warn (변경된 public/internal 심볼의 caller 경고)
#   git 명령이 .git을 찾도록 cwd로 이동(섹션 1은 절대경로라 cwd 무관 → 이동 순서 안전).
# =====================================================================
if (-not $disableImpact) {
    try {
        if ($data.cwd -and (Test-Path -LiteralPath $data.cwd -PathType Container)) {
            Set-Location -LiteralPath $data.cwd
        } elseif ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR -PathType Container)) {
            Set-Location -LiteralPath $env:CLAUDE_PROJECT_DIR
        }

        # 코드 파일만 검사 (caller 검색 대상 — 주석 검사용 목록보다 넓다: .vb/.xaml/.razor/.vue/.svelte/.sql 포함)
        # .vb는 전용 VB regex로 심볼 추출. .xaml/.razor/.sql은 추출 패턴이 없어 심볼 0이지만
        # 코드 심볼의 'caller 검색 대상'으로 포함된다(예: C# 메서드가 .xaml 이벤트·.razor·.sql에서 참조되는지 검출).
        # .vue/.svelte는 전용 패턴 없음 — 기존 TS export 패턴이 <script> 블록의 export 심볼을 일부 추출 가능.
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
                                # 너무 짧거나 일반적인 이름은 제외 (false positive 방지)
                                if ($sym.Length -ge 4 -and $sym -notmatch '^(get|set|is|has)$') {
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
                            $allMsgs.Add("이 경고는 차단이 아닙니다. 끄려면: harness-toggle impact-warn off")
                        }
                    }
                }
            }
        }
    } catch {
        # 섹션 2 실패는 섹션 1 결과(이미 $allMsgs에 있음)에 영향 없음(격리).
    }
}

# =====================================================================
# 출력: 두 섹션 경고를 합쳐 단일 stderr + 단일 additionalContext (exit 0 비차단)
# =====================================================================
if ($allMsgs.Count -gt 0) {
    $msg = ($allMsgs -join "`n")

    # stderr: 사용자 가시성용
    [Console]::Error.WriteLine($msg)

    # stdout JSON: PostToolUse additionalContext로 모델에 전달 (exit 0 비차단).
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
    [Console]::Out.WriteLine($payload)
}

exit 0
