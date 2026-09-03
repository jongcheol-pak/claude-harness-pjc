# PostToolUse hook - PowerShell 버전 — 근거는 `rules/suggest-record-rationale.md`의 「§1 PostToolUse hook - PowerShell 버전」

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로·명령이 깨져 cwd 판정·제안 대상 명령 인식이 어긋난다. 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 홈 경로 (Claude Code 홈과 정합 — Windows는 USERPROFILE, 없으면 $HOME) ----
$base = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }

# ---- stdin JSON 읽기 (tool_input.command / cwd / session_id 제공 — 공식 hook 입력 스펙) ----
$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
} catch {
    # 파싱 실패 시 통과 (제안 실패가 차단보다 안전)
    exit 0
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# 데이터 문맥 제거: heredoc 본문은 파일 내용이지 실행 명령이 아니다 — 근거는 `rules/suggest-record-rationale.md`의 「§2 데이터 문맥 제거: heredoc 본문은 파일 내용이지 실행 명령이 아니다」
$cmdScan = [regex]::Replace($cmd, "(?ms)<<-?\s*(['`"]?)(\w+)\1\r?\n.*?^\2\r?$", ' ')

# 데이터 문맥 제거 2단: 「메시지 인자」 플래그 뒤의 인용 블록도 데이터다 — 근거는 `rules/suggest-record-rationale.md`의 「§3 데이터 문맥 제거 2단: 「메시지 인자」 플래그 뒤의 인용 블록도 데이터다」
$msgFlags = if ($cmdScan -match '(?i)\bpy(thon[\w.]*)?(\.exe)?\s+(-\S+\s+)*-m\b') {
    '--message|-am|--body'
} else {
    '-m|--message|-am|--body'
}
# 구분자를 선택적으로 둬 `--message=`·`-m"…"` 붙임 표기까지 덮는다.
$quotedArgRx = "(?s)(^|\s)($msgFlags)(\s*=\s*|\s+)?('[^']*'|`"[^`"]*`")"
$cmdScan = [regex]::Replace($cmdScan, $quotedArgRx, '$1$2 ')

# 대상 레포 판정: 다른 폴더로 옮겨 실행한 명령은 이 프로젝트의 사실이 아니다 — 근거는 `rules/suggest-record-rationale.md`의 「§4 대상 레포 판정: 다른 폴더로 옮겨 실행한 명령은 이 프로젝트의 사실이 아니다」
$cdAll = [regex]::Matches($cmdScan, "(?im)(?:^|&&|;|\|)\s*cd\s+(?:'([^']+)'|`"([^`"]+)`"|([^\s&|;]+))")

# ---- 카테고리별 명령 패턴 (변경형 빌드/테스트/DB만) ----
# rx는 카테고리 간 배타적(build rx에 test 없음)이라 순서 무관. 매칭값을 '대표 토큰'으로 삼는다.
$categories = @(
    @{ name = 'build'; section = 'Build & Test'; label = '빌드/실행';
       rx = '(?i)\b(dotnet\s+(build|run|publish)|(npm|yarn|pnpm)\s+(run\s+)?build|go\s+build|cargo\s+build|(\./)?mvnw?\b[^\r\n]*\b(package|compile|install)|(\./)?gradlew?\b[^\r\n]*\bbuild|msbuild|cmake\s+--build|\bmake\b)' },
    @{ name = 'test'; section = 'Build & Test'; label = '테스트/검증';
       rx = '(?i)\b(dotnet\s+test|(npm|yarn|pnpm)\s+(run\s+)?test|pytest|python\s+-m\s+pytest|go\s+test|cargo\s+test|(\./)?gradlew?\b[^\r\n]*\btest|jest|vitest)\b' },
    @{ name = 'db'; section = '데이터 접근'; label = 'DB 접근';
       rx = '(?i)\b(psql|mysql|sqlcmd|sqlite3|mongosh|mongo|dotnet\s+ef|alembic|flyway|liquibase|prisma\s+(migrate|db)|sequelize|rails\s+db:migrate|php\s+artisan\s+migrate|knex\s+migrate)\b' }
)

$hits = New-Object System.Collections.Generic.List[object]
foreach ($cat in $categories) {
    $m = [regex]::Match($cmdScan, $cat.rx)
    if ($m.Success) {
        # 토큰 정규화: 옵션 — 근거는 `rules/suggest-record-rationale.md`의 「§5 토큰 정규화: 옵션」
        $tokParts = ($m.Value.Trim() -split '\s+') | Where-Object { $_ -and ($_ -notmatch '^[-/]') -and ($_ -notmatch '=') }
        $tok = ($tokParts -join ' ')
        if (-not $tok) { $tok = $m.Value.Trim() }
        $hits.Add([pscustomobject]@{ name = $cat.name; section = $cat.section; label = $cat.label; token = $tok })
    }
}
if ($hits.Count -eq 0) { exit 0 }

# ---- 작업 디렉터리 결정 (cwd → CLAUDE_PROJECT_DIR → 현재 위치; 다른 hook 들과 동형) ----
$projDir = $null
if ($data.cwd -and (Test-Path -LiteralPath $data.cwd -PathType Container)) {
    $projDir = $data.cwd
} elseif ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR -PathType Container)) {
    $projDir = $env:CLAUDE_PROJECT_DIR
} else {
    $projDir = (Get-Location).Path
}

# 명령이 `cd`로 이 프로젝트 밖을 지목했으면 그것은 이 프로젝트의 사실이 아니다. — 근거는 `rules/suggest-record-rationale.md`의 「§6 명령이 `cd`로 이 프로젝트 밖을 지목했으면 그것은 이 프로젝트의 사실이 아니다.」
if ($cdAll.Count -gt 0) {
    $projResolved = $null
    try { $projResolved = (Resolve-Path -LiteralPath $projDir -ErrorAction Stop).Path } catch {}
    if (-not $projResolved) { exit 0 }
    # 각 cd를 **순서대로** 풀고 직전 결과를 다음 기준으로 삼는다(홉 수에 무관한 일반해).
    #   상대경로의 기준은 hook 프로세스의 cwd가 아니라 **직전까지 옮겨 온 위치**다.
    $cdCur = $projResolved
    foreach ($cdM in $cdAll) {
        $cdRaw = @($cdM.Groups[1].Value, $cdM.Groups[2].Value, $cdM.Groups[3].Value) |
            Where-Object { $_ } | Select-Object -First 1
        try {
            $cdBase = if ([System.IO.Path]::IsPathRooted($cdRaw)) { $cdRaw } else { Join-Path $cdCur $cdRaw }
            $cdCur = (Resolve-Path -LiteralPath $cdBase -ErrorAction Stop).Path
        } catch { exit 0 }   # 해석 실패 = 판정 불가 → 제안하지 않는다
    }
    # 하위트리 판정 — **구분자를 붙여 비교한다**. 안 붙이면 `C:\proj`가 형제 `C:\project`를
    #   삼켜 다른 레포를 같은 레포로 오인한다. Windows 경로라 대소문자는 무시한다.
    $projRoot = $projResolved.TrimEnd('\', '/')
    $cdFinal = $cdCur.TrimEnd('\', '/')
    $inTree = $cdFinal.Equals($projRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
              $cdFinal.StartsWith($projRoot + [System.IO.Path]::DirectorySeparatorChar,
                                  [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $inTree) { exit 0 }
}

# AGENTS.md 없으면 제안하지 않음 — 그 파일 생성은 `pjc:plan` Step 1 전담이고 이 제안은 갱신용이다
$agentsPath = Join-Path $projDir 'AGENTS.md'
if (-not (Test-Path -LiteralPath $agentsPath)) { exit 0 }
$agentsRaw = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if (-not $agentsRaw) { $agentsRaw = '' }
# 공백 정규화 + 소문자 — self-terminating 토큰 비교용
$agentsHay = ($agentsRaw -replace '\s+', ' ').ToLower()

# ---- 상태 마커 준비 (세션·프로젝트·카테고리당 1회) ----
$stateDir = Join-Path $base '.claude/.state/suggest-agents-record'
try { New-Item -Force -ItemType Directory -Path $stateDir | Out-Null } catch {}
# 30일 지난 마커 자동 정리 — 마커는 세션×프로젝트×카테고리당 1개라 방치하면 무한 축적된다(하우스키핑).
# 오래된 마커 삭제로 같은 제안이 다시 뜰 수 있지만, 그 시점엔 세션도 오래돼 재제안이 오히려 유익하다.
try {
    Get-ChildItem -LiteralPath $stateDir -File -ErrorAction Stop |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}
$sid = if ($data.session_id) { [string]$data.session_id } else { '' }
$projLeaf = Split-Path -Leaf $projDir
# 파일명 안전 문자만 남김 (디렉터리명 공백·session_id 등)
$sidSafe = ($sid -replace '[^A-Za-z0-9._-]', '_')
$leafSafe = ($projLeaf -replace '[^A-Za-z0-9._-]', '_')

# ---- 제안 대상 추림: AGENTS.md에 토큰 없음 + 마커 없음 ----
$toSuggest = New-Object System.Collections.Generic.List[object]
foreach ($h in $hits) {
    $tok = ($h.token -replace '\s+', ' ').ToLower()
    if ($agentsHay.Contains($tok)) { continue }   # (1) self-terminating: 이미 기록됨
    $markerName = if ($sidSafe) { $sidSafe + '_' + $leafSafe + '_' + $h.name } else { $leafSafe + '_' + $h.name }
    $markerPath = Join-Path $stateDir $markerName
    if (Test-Path -LiteralPath $markerPath) { continue }   # (2) 세션·프로젝트·카테고리당 1회
    $toSuggest.Add($h)
    try { New-Item -Force -ItemType File -Path $markerPath | Out-Null } catch {}   # 생성 실패는 무시(비치명)
}
if ($toSuggest.Count -eq 0) { exit 0 }

# ---- 제안 출력 ----
$lines = @("[AGENTS 기록 제안] 이번에 실행한 명령이 AGENTS.md에 기록돼 있지 않습니다:")
foreach ($s in $toSuggest) {
    $lines += ("  - " + $s.label + ": `"" + $s.token + "`"  -> AGENTS.md '" + $s.section + "' 섹션")
}
$lines += ""
$lines += "다음 작업부터 이 정보를 재확인하지 않도록, record-project-fact 스킬로 AGENTS.md에 추가할지 사용자에게 물어보세요."
$lines += "자동 기록이 아닙니다 — 사용자가 승인하면 그때만 기록합니다. (DB는 실제 연결문자열 금지, 환경변수 이름만)"
$lines += "이 제안은 차단이 아닙니다."
$msg = $lines -join "`n"

# stderr: 사용자 가시성용
[Console]::Error.WriteLine($msg)

# stdout JSON: PostToolUse additionalContext로 모델에 전달 (exit 0 비차단)
$payload = @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
[Console]::Out.WriteLine($payload)

exit 0
