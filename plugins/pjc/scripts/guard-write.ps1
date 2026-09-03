# guard-write.ps1 — PreToolUse hook: plan 없이 코드를 고치는 것을 차단 (exit 2) — 근거는 `rules/write-gate-rationale.md`의 「§1 guard-write.ps1 — PreToolUse hook: plan 없이 코드를 고치는 것을 차단 (exit 2)」

$ErrorActionPreference = 'SilentlyContinue'

# 한글 차단 사유가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로가 깨져 $targetPath·Find-PlanUpwards 판정이 어긋난다(정상 작업 오차단 위험).
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# stdin JSON 읽기
$inputJson = [Console]::In.ReadToEnd()

try {
    $data = $inputJson | ConvertFrom-Json
    $targetPath = $data.tool_input.path
    if (-not $targetPath) { $targetPath = $data.tool_input.file_path }
    if (-not $targetPath) { $targetPath = $data.tool_input.notebook_path }   # NotebookEdit (.ipynb)
} catch {
    # 파싱 실패 시 통과
    exit 0
}

# 파일 경로가 없으면 통과
if ([string]::IsNullOrWhiteSpace($targetPath)) { exit 0 }

# [이벤트 로깅] 차단(plan 없음)·경고(G4/H3) 이벤트를 오탐 리뷰 데이터로 적재 — 게이트 판정은 무변경,
#   실패 전면 격리(try/catch + Get-Command 가드).
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}
function Write-RpEvent {
    param([string]$Decision, [string]$Rule)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            Write-HookEvent 'require-plan-for-write' $Decision $Rule ([string]$script:data.tool_name + ' ' + [string]$script:targetPath)
        }
    } catch {}
}

# plan 작성 게이트 — 근거는 `rules/write-gate-rationale.md`의 「§3 plan 작성 게이트」
$planTaskRx = '(?m)^\s*([-*+]|\d+[.)])\s*\[[ /xX~-]\]'

if ($env:CLAUDE_HARNESS_QUICK -ne '1') {
    $planFileName = [System.IO.Path]::GetFileName($targetPath)
    $isPlanFileName = ($planFileName -ieq 'plan.md')            # plan.md/PLAN.md — 경로 무관, 내용 무관
    # 선행 구분자를 **선택**으로 둔다 — 상대 경로(`docs/plans/x.md`)도 잡아야 게이트가 균일하다.
    $isInPlansDir = ($targetPath -match '(?i)(^|[\\/])docs[\\/]plans[\\/][^\\/]+\.md$')

    $planGateTarget = $false
    if ($isPlanFileName) {
        # ⓐ plan 파일명 — Write면 내용과 무관하게 게이트(빈 plan 급조가 바로 차단 대상)
        if ($data.tool_name -eq 'Write') { $planGateTarget = $true }
    }
    if ($isPlanFileName -or $isInPlansDir) {
        # ⓑ docs/plans/*.md Write — 체크박스가 있을 때만 plan으로 본다 — 근거는 `rules/write-gate-rationale.md`의 「§4 # ⓑ docs/plans/*.md Write — 체크박스가 있을 때만 plan으로 본다」
        if ($data.tool_name -eq 'Write' -and $isInPlansDir) {
            if ([string]$data.tool_input.content -match $planTaskRx) { $planGateTarget = $true }
        }
        # ⓒ 체크박스를 '새로 도입'하는 Edit/MultiEdit — 위 2단계 우회 차단. — 근거는 `rules/write-gate-rationale.md`의 「§5 # ⓒ 체크박스를 '새로 도입'하는 Edit/MultiEdit — 위 2단계 우회 차단.」
        if ($data.tool_name -eq 'Edit' -or $data.tool_name -eq 'MultiEdit') {
            $editPairs = @()
            if ($data.tool_name -eq 'MultiEdit' -and $data.tool_input.edits) {
                $editPairs = @($data.tool_input.edits | ForEach-Object {
                    @{ old = [string]$_.old_string; new = [string]$_.new_string }
                })
            } else {
                $editPairs = @(@{ old = [string]$data.tool_input.old_string; new = [string]$data.tool_input.new_string })
            }
            foreach ($p in $editPairs) {
                if (($p.new -match $planTaskRx) -and ($p.old -notmatch $planTaskRx)) { $planGateTarget = $true; break }
            }
        }
    }

    # 시스템 임시 폴더(스크래치패드)는 비대상 — 프로젝트 plan이 아니다(AGENTS 게이트와 동일 완화)
    if ($planGateTarget) {
        try {
            $tempRootP = [System.IO.Path]::GetTempPath().TrimEnd('\', '/') -replace '/', '\'
            $tpNormP = $targetPath -replace '/', '\'
            if ($tempRootP -and $tpNormP.StartsWith($tempRootP + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $planGateTarget = $false
            }
        } catch { }
    }

    if ($planGateTarget) {
        # 발동 흔적 판정 — pjc:plan — 근거는 `rules/write-gate-rationale.md`의 「§6 # 발동 흔적 판정 — pjc:plan」
        $planSkillLaunched = $false
        $tpp = [string]$data.transcript_path
        if ([string]::IsNullOrWhiteSpace($tpp) -or -not (Test-Path -LiteralPath $tpp)) {
            $planSkillLaunched = $true
        } else {
            try {
                $planSkillLaunched = [bool](Select-String -LiteralPath $tpp -Quiet -Pattern @(
                    '"skill"\s*:\s*"pjc:plan"',
                    'Launching skill: pjc:plan',
                    '"skill"\s*:\s*"pjc:implement"',
                    'Launching skill: pjc:implement'))
            } catch { $planSkillLaunched = $true }
        }
        if (-not $planSkillLaunched) {
            [Console]::Error.WriteLine("[HARNESS] BLOCKED: plan 작성은 pjc:plan 스킬로만 합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("직접 작성은 적대적 plan-reviewer 검토·영향 범위 전수 조사·Type 분류·사전 승인 항목을 통째로 우회합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("해결 방법:")
            [Console]::Error.WriteLine("  1) Skill 도구로 pjc:plan 호출 → 조사·검토·사용자 승인 후 plan 작성")
            [Console]::Error.WriteLine("  2) 기존 plan의 부분 갱신(체크박스 [ ]->[x], Progress Log·Deferred 기록)은 이 게이트의 대상이 아닙니다")
            [Console]::Error.WriteLine("     — 체크박스를 '새로 도입'하는 편집만 막습니다.")
            [Console]::Error.WriteLine("  3) 긴급 우회는 사용자만 가능 (Claude Code 시작 전 터미널에서):")
            [Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
            [Console]::Error.WriteLine("     ※ Claude가 Bash 도구로 설정해도 hook 프로세스에 전파되지 않아 무효입니다.")
            Write-RpEvent 'block' 'plan 작성 게이트'
            exit 2
        }
    }
}

# ---- 항상 허용되는 파일 타입 ----
# 문서, 설정, plan, 이미지·리소스는 plan 없이도 작성 가능
$wgRules = $null
try { $wgRules = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rules/write-gate.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
if (-not $wgRules) { exit 0 }   # 목록을 못 읽으면 판정 근거가 없다 — 차단하지 않는다(fail-open)
$alwaysAllowedExts = @($wgRules.alwaysAllowedExts)

$ext = [System.IO.Path]::GetExtension($targetPath).ToLower()
# 실행 자산 예외 — .github/workflows/*.yml — 근거는 `rules/write-gate-rationale.md`의 「§8 실행 자산 예외 — .github/workflows/*.yml」
$execAssetName = [System.IO.Path]::GetFileName($targetPath)
$isExecAsset = ($targetPath -match '(^|[\\/])\.github[\\/]workflows[\\/][^\\/]+\.ya?ml$') -or
               ($execAssetName -eq 'package.json')
if (-not $isExecAsset -and ($alwaysAllowedExts -contains $ext)) { exit 0 }

# .env 템플릿(.env.example/.env.sample)은 plan 없이 허용 (실제 시크릿 파일 .env는 제외)
$baseNameEarly = [System.IO.Path]::GetFileName($targetPath)
if ($baseNameEarly -match '^\.env\.(example|sample)$') { exit 0 }

# 파일명 기반 예외 (확장자 없는 trivial 파일)
$baseName = [System.IO.Path]::GetFileName($targetPath)
$trivialFileNames = @($wgRules.trivialFileNames)
foreach ($name in $trivialFileNames) {
    if ($baseName -match "^$name(\..+)?$") { exit 0 }
}

# Android strings.xml, iOS Localizable.strings, .NET resx 같은 리소스 파일명
if ($baseName -match '^(strings\.xml|Localizable\.strings|Info\.plist)$') { exit 0 }

# 소스 코드 확장자 판정 — 근거는 `rules/write-gate-rationale.md`의 「§9 소스 코드 확장자 판정」
$sourceCodeExts = @($wgRules.sourceCodeExts)
$isSourceCode = $sourceCodeExts -contains $ext

# .git, .vs, node_modules, bin, obj — 생성/벤더 디렉터리(손으로 쓰는 소스 아님) → 무조건 허용
if ($targetPath -match '[\\/](\.git|\.vs|node_modules|bin|obj)[\\/]') { exit 0 }

# Android 리소스 디렉터리 (res/values, res/drawable 등) — 무조건 허용
if ($targetPath -match '[\\/]res[\\/](values|drawable|mipmap|layout|raw|xml|color|font|menu|anim)') { exit 0 }

# .claude (하니스 설정·도구) — 무조건 허용
if ($targetPath -match '[\\/]\.claude[\\/]') { exit 0 }

# 시스템 임시 폴더 — 근거는 `rules/write-gate-rationale.md`의 「§10 시스템 임시 폴더」
try {
    $tempRoot = [System.IO.Path]::GetTempPath().TrimEnd('\', '/') -replace '/', '\'
    $tpNorm = $targetPath -replace '/', '\'
    if ($tempRoot -and $tpNorm.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
} catch { }

# docs/plans/dist/build — 산출물·문서 디렉터리. 단 '소스 코드 파일이 아닐 때만' 우회한다. — 근거는 `rules/write-gate-rationale.md`의 「§11 docs/plans/dist/build — 산출물·문서 디렉터리. 단 '소스 코드 파일이 아닐 때만' 우회한다.」
if (-not $isExecAsset -and -not $isSourceCode -and (
        ($targetPath -match '[\\/]docs[\\/]') -or
        ($targetPath -match '[\\/]plans?[\\/]') -or
        ($targetPath -match '[\\/](dist|build)[\\/]'))) {
    exit 0
}

# 작은 변경 통과(Trivial Edit/Write) 판정은 `write-gate-trivial.ps1`이 담당한다 —
#   그 판정은 정규화·스타일 파일·줄 수 임계를 함께 보아 부피가 크고, 이 파일의 게이트 판정과
#   관심사가 다르다. 통과 조건에 맞으면 그 스크립트가 exit 0으로 끝낸다.
. (Join-Path $PSScriptRoot 'write-gate-trivial.ps1')
Invoke-TrivialEditGate $data $targetPath $ext $isSourceCode $wgRules

# ---- 우회 환경변수 ----
if ($env:CLAUDE_HARNESS_QUICK -eq '1') {
    [Console]::Error.WriteLine("[HARNESS] QUICK 모드: plan 검사 우회")
    exit 0
}

# 프로젝트 루트 결정 — 근거는 `rules/write-gate-rationale.md`의 「§16 프로젝트 루트 결정」
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

# plan 존재 확인 — 근거는 `rules/write-gate-rationale.md`의 「§17 plan 존재 확인」
function Test-PlanInDirectory {
    param([string]$Dir)
    if ([string]::IsNullOrEmpty($Dir)) { return $false }
    # 단일 plan 파일은 존재만으로 인정한다 — 신규 생성은 위 게이트 ⓐ가 내용과 무관하게 막으므로
    #   "합법 Write로 판정을 켜는" 경로가 없다(기존 빈 plan.md는 H3 경고 층위).
    if ((Test-Path -LiteralPath (Join-Path $Dir 'plan.md') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $Dir 'PLAN.md') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $Dir 'docs/plan.md') -PathType Leaf)) {
        return $true
    }
    # plan 위치는 루트 단일계뿐이다 — 근거는 `rules/write-gate-rationale.md`의 「§18 # plan 위치는 루트 단일계뿐이다」
    return $false
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

if ($foundIn) {
    # ---- 완료된/빈 plan 비차단 경고 — 근거는 `rules/write-gate-rationale.md`의 「§19 # ---- 완료된/빈 plan 비차단 경고」
    $planFile = $null
    foreach ($cand in @('plan.md', 'PLAN.md', 'docs/plan.md')) {
        $pf = Join-Path $foundIn $cand
        if (Test-Path -LiteralPath $pf -PathType Leaf) { $planFile = $pf; break }
    }
    if ($planFile) {
        try {
            # 세션당 1회 디듑 — 근거는 `rules/write-gate-rationale.md`의 「§20 # 세션당 1회 디듑」
            $warnStateDir = Join-Path $env:USERPROFILE '.claude/.state/require-plan-warn'
            try { New-Item -Force -ItemType Directory -Path $warnStateDir | Out-Null } catch {}
            # 30일 지난 마커 자동 정리 — 마커는 세션×plan×경고 종류당 1개라 방치하면 무한 축적된다 — 근거는 `rules/write-gate-rationale.md`의 「§21 # 30일 지난 마커 자동 정리 — 마커는 세션×plan×경고 종류당 1개라 방치하면 무한 축적된다」
            try {
                Get-ChildItem -LiteralPath $warnStateDir -File -ErrorAction Stop |
                    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            } catch {}
            $sidW = if ($data.session_id) { ([string]$data.session_id) -replace '[^\w.-]', '_' } else { 'nosid' }
            $planKey = ($planFile -replace '[^\w.-]', '_')
            function Test-WarnOnce {
                param([string]$Kind)
                $mk = Join-Path $warnStateDir ($sidW + '_' + $Kind + '_' + $planKey)
                if (Test-Path -LiteralPath $mk) { return $false }
                try { New-Item -Force -ItemType File -Path $mk | Out-Null } catch {}
                return $true
            }
            $planText = Get-Content -LiteralPath $planFile -Raw -Encoding UTF8
            # 미완료 마커 [ ] 또는 [/], 완료 마커 [x]/[X] — 근거는 `rules/write-gate-rationale.md`의 「§22 # 미완료 마커 [ ] 또는 [/], 완료 마커 [x]/[X]」
            $incomplete = [regex]::Matches($planText, '(?m)^\s*[-*]\s*\[[ /]\]').Count
            $done = [regex]::Matches($planText, '(?m)^\s*[-*]\s*\[[xX]\]').Count
            if ($incomplete -eq 0 -and $done -ge 1) {
                if (Test-WarnOnce -Kind 'G4') {
                    $warnMsg = "[HARNESS] 이 plan은 완료된 것으로 보입니다 (task 체크박스 ${done}개 전부 [x], 미완료 0). " +
                               "이번 코드 변경이 이 완료된 plan의 범위 내 후속 작업(리뷰 지적 수정·마무리·문서 갱신 등)이면 새 plan 없이 그대로 진행하세요. " +
                               "완료된 plan과 무관한 '새 작업'일 때만 pjc:plan으로 plan을 갱신하세요 — require-plan은 plan 존재만 보고 통과시키므로, 완료된 옛 plan으로 무관한 변경이 새는 것을 막지 못합니다. (이 경고는 세션당 1회)"
                    [Console]::Error.WriteLine($warnMsg)
                    Write-RpEvent 'warn' 'G4: 완료된 plan으로 새 변경'
                    # PreToolUse additionalContext로 모델에 전달 (exit 0 비차단)
                    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $warnMsg } } | ConvertTo-Json -Compress -Depth 5
                    [Console]::Out.WriteLine($payload)
                }
            } elseif ($incomplete -eq 0 -and $done -eq 0) {
                # H3: task 체크박스(- [ ]/[x])가 하나도 없음 = 빈/플레이스홀더 plan.
                #   0바이트·골격만 있는 plan.md 하나로 게이트를 무력화하는 약점을 가시화한다(비차단).
                if (Test-WarnOnce -Kind 'H3') {
                    $warnMsg = "[HARNESS] 이 plan.md에 task 체크박스(- [ ] / - [x])가 하나도 없습니다 — 빈/플레이스홀더 plan일 수 있습니다. " +
                               "require-plan은 plan 존재만 보고 통과시키므로, 내용 없는 plan으로 코드 변경이 통과하는 것을 막지 못합니다. pjc:plan으로 실제 task를 작성하세요. " +
                               "(이 경고는 세션당 1회)"
                    [Console]::Error.WriteLine($warnMsg)
                    Write-RpEvent 'warn' 'H3: 빈/플레이스홀더 plan'
                    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $warnMsg } } | ConvertTo-Json -Compress -Depth 5
                    [Console]::Out.WriteLine($payload)
                }
            }
        } catch {
            # plan 읽기 실패는 무시 (통과 자체는 유지)
        }
    }
    exit 0
}

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
[Console]::Error.WriteLine("  - plan.md, PLAN.md, docs/plan.md")
[Console]::Error.WriteLine("위 위치 어디에도 plan이 없습니다.")

# 진단 분기(v1.210.0): 과거 회차 plan이 쌓인 디렉터리를 보고 "plan이 있는데 왜 막지"라고 여길 수
#   있으므로, plan 위치가 루트 하나임을 명시한다. fail-closed는 진단 가능할 때만 안전측이다.
$legacyPlansDir = Join-Path $projectRoot 'docs/plans'
if (Test-Path -LiteralPath $legacyPlansDir -PathType Container) {
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("※ plan 위치는 루트 plan.md 하나입니다 — docs/plans/ 의 날짜별 파일은 완료된")
    [Console]::Error.WriteLine("   과거 회차의 기록이라 plan 판정에 쓰이지 않습니다(그 디렉터리는 Deferred 대장 전용).")
}
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("해결 방법:")
[Console]::Error.WriteLine("  1) pjc:plan skill 호출:")
[Console]::Error.WriteLine("     사용자에게 '계획 작성해줘' 라고 요청하거나 /pjc:plan <설명>")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("  2) 긴급 1줄 수정 우회 — 사용자만 설정 가능 (Claude Code 시작 전 터미널에서):")
[Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
[Console]::Error.WriteLine("     ※ Claude가 Bash 도구로 설정해도 hook 프로세스에 전파되지 않아 무효입니다 — 시도하지 말고,")
[Console]::Error.WriteLine("       필요하면 사용자에게 위 설정(후 Claude Code 재시작)을 안내하세요.")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("  3) plan.md 위치 확인:")
[Console]::Error.WriteLine("     루트의 plan.md 파일 위치와 검색 시작점이 다른 경로일 수 있습니다.")
[Console]::Error.WriteLine("     모노레포라면 작업 디렉터리 위쪽에 plan.md 가 있어야 합니다.")

Write-RpEvent 'block' 'plan 없음 차단'
exit 2
