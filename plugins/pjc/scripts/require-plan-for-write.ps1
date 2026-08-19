# PreToolUse hook - PowerShell 버전
# 두 개의 독립된 게이트를 담는다:
#   ① plan 존재 게이트 — 코드 Write/Edit 시 plan.md(또는 docs/plans/의 체크박스 plan)가 없으면 차단.
#   ② plan 작성 게이트 (v1.118.0) — plan.md/docs/plans/*.md 자체를 Write하거나 체크박스를 새로 도입하는
#      Edit은 pjc:plan-feature(또는 implement-task) 발동 흔적 없이는 차단. 손으로 급조한 plan으로
#      ①을 켜서 리뷰·영향분석을 통째로 우회하던 구멍을 막는다.
#   (+ AGENTS.md bootstrap 게이트 — 신규 생성은 pjc:bootstrap-agents-md 경유만 허용.)
# 문서/설정 파일은 항상 허용.
# 우회: $env:CLAUDE_HARNESS_QUICK = '1'
# exit 2 = block.

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

# ---- AGENTS.md bootstrap 게이트 (v1.111.0) ----
# AGENTS.md '신규 생성'은 pjc:bootstrap-agents-md 스킬 경유가 정본 경로다(스택 템플릿 + [Y/E/N] 사용자
# 승인 게이트). 스킬 미발동 직접 Write는 그 자산·승인을 통째로 우회하므로 차단한다 — 아래 .md 무조건
# 허용보다 먼저 판정해야 하므로 이 위치에 둔다.
# 발동 판정: stdin JSON의 transcript_path에서 발동 흔적 2패턴 중 하나를 찾으면 통과 — ① Skill tool_use
#   입력 `"skill":"pjc:bootstrap-agents-md"` ② tool result `Launching skill: pjc:bootstrap-agents-md`
#   (실측 형태 — 산문 언급만으로는 매치되지 않음).
# fail-open: transcript_path 부재·파일 없음·읽기 실패는 통과. 실환경 Claude Code는 항상 제공하므로
#   실질 게이트는 유지되고, 골든 무상태 케이스·타 하니스·포맷 변화에서 오차단하지 않는다(파싱 실패
#   통과 관례와 동일). 범위: Write + 파일 미존재(신규)만 — 기존 파일 Write/Edit는 정당 편집 경로
#   (record-project-fact 등)라 게이트 비대상.
if ($data.tool_name -eq 'Write' -and
    [System.IO.Path]::GetFileName($targetPath) -eq 'AGENTS.md' -and
    -not (Test-Path -LiteralPath $targetPath) -and
    $env:CLAUDE_HARNESS_QUICK -ne '1') {

    # 시스템 임시 폴더는 비대상 — 프로젝트 AGENTS.md가 아니다(아래 임시 폴더 완화와 동일 취지)
    $agentsInTemp = $false
    try {
        $tempRootA = [System.IO.Path]::GetTempPath().TrimEnd('\', '/') -replace '/', '\'
        $tpNormA = $targetPath -replace '/', '\'
        if ($tempRootA -and $tpNormA.StartsWith($tempRootA + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $agentsInTemp = $true }
    } catch { }

    if (-not $agentsInTemp) {
        $bootstrapLaunched = $false
        $tp = [string]$data.transcript_path
        if ([string]::IsNullOrWhiteSpace($tp) -or -not (Test-Path -LiteralPath $tp)) {
            $bootstrapLaunched = $true   # fail-open — transcript를 확인할 수 없으면 차단하지 않는다
        } else {
            try {
                $bootstrapLaunched = [bool](Select-String -LiteralPath $tp -Quiet -Pattern @(
                    '"skill"\s*:\s*"pjc:bootstrap-agents-md"',
                    'Launching skill: pjc:bootstrap-agents-md'))
            } catch { $bootstrapLaunched = $true }   # 읽기 실패도 fail-open
        }
        if (-not $bootstrapLaunched) {
            [Console]::Error.WriteLine("[HARNESS] BLOCKED: AGENTS.md 신규 생성은 pjc:bootstrap-agents-md 스킬로만 합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("직접 Write는 스택 템플릿 자산과 사용자 승인 게이트([Y/E/N])를 통째로 우회합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("해결 방법:")
            [Console]::Error.WriteLine("  1) Skill 도구로 pjc:bootstrap-agents-md 호출 → 스택 감지·템플릿 채움 → 사용자 승인 후 저장")
            [Console]::Error.WriteLine("  2) 사용자가 특정 내용을 직접 지정한 경우에도 위 스킬의 [E] 편집 경로로 반영")
            [Console]::Error.WriteLine("  3) 스킬을 호출할 수 없는 상황(도구 제한 등)이면 사용자에게 확인 요청")
            [Console]::Error.WriteLine("  4) 긴급 우회는 사용자만 가능 (Claude Code 시작 전 터미널에서):")
            [Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
            [Console]::Error.WriteLine("     ※ Claude가 Bash 도구로 설정해도 hook 프로세스에 전파되지 않아 무효입니다 — 시도하지 말고,")
            [Console]::Error.WriteLine("       필요하면 사용자에게 위 설정(후 Claude Code 재시작)을 안내하세요.")
            Write-RpEvent 'block' 'AGENTS bootstrap 게이트'
            exit 2
        }
    }
}

# ---- plan 작성 게이트 (v1.118.0) ----
# plan은 pjc:plan-feature 경유가 정본 경로다(적대적 plan-reviewer 검토·영향 범위 전수 조사·Type 분류·
#   사전 승인 항목). 스킬을 거치지 않고 손으로 급조한 plan 하나로 그 자산이 통째로 우회되던 구멍을 막는다.
#   AGENTS bootstrap 게이트와 동형(transcript 흔적 판정·fail-open·temp 예외·QUICK 우회)이나, 조건이 다르다:
#   AGENTS.md는 기존 파일 편집이 정당 경로(record-project-fact)라 '신규 생성'만 게이트하지만, plan은
#   Write 자체가 통째 재작성이라 신규/기존을 가리지 않는다.
#
# 게이트의 축은 '도구'가 아니라 **체크박스를 새로 도입하는 행위**다 — Write만 막으면
#   ① 체크박스 없는 docs/plans/*.md를 Write(통과) → ② Edit으로 체크박스 추가 → ③ 아래
#   Test-PlanInDirectory가 plan으로 인정 = 스킬 0회로 게이트 ON, 이라는 2단계 우회가 성립한다.
#   그래서 Write(전부)와 '체크박스를 도입하는 Edit'을 같은 문으로 잠근다.
#
# $planTaskRx는 이 게이트와 Test-PlanInDirectory가 **공유**한다 — 두 기준이 갈리면 그 차이가 곧 구멍이다
#   (게이트는 통과하는데 plan 판정은 켜지는 파일이 생긴다). `-`·`*`·`+` 불릿과 ordered list(`1.`/`1)`),
#   `[x]`/`[X]`/`[/]`를 모두 인정한다: 좁게 잡으면 표기를 바꾼 급조 plan이 게이트를 빠져나가고,
#   동시에 정상 plan이 "plan 아님"으로 판정돼 그 프로젝트의 코드 Write가 전면 차단된다(오차단).
# `-`(취소)·`~`도 인정한다 — 그 표기만 쓰는 외부 레포는 종전에 `docs/plans/`가 있어도 plan 판정이
#   꺼져 **코드 Write가 전면 차단**됐다(v1.118.0 F-7 m3). 확장 대상을 이 둘로 한정하는 이유는
#   임의 문자(`[^\]]`)를 허용하면 체크박스가 아닌 문서를 plan으로 오판해 게이트가 잘못 켜지기 때문이다.
# ⚠ 이 확장은 방향이 둘이다 — plan **존재** 판정에서는 차단 완화지만, plan 파일 Write·체크박스 도입
#   Edit을 막는 **작성 게이트에서는 차단이 넓어진다**(그 표기를 쓰던 문서가 새로 게이트 대상이 된다).
# 이 줄은 .md 무조건 허용($alwaysAllowedExts)보다 반드시 앞에 있어야 한다 — 뒤면 plan.md가 먼저 통과한다.
$planTaskRx = '(?m)^\s*([-*+]|\d+[.)])\s*\[[ /xX~-]\]'

if ($env:CLAUDE_HARNESS_QUICK -ne '1') {
    $planFileName = [System.IO.Path]::GetFileName($targetPath)
    $isPlanFileName = ($planFileName -ieq 'plan.md')            # plan.md/PLAN.md — 경로 무관, 내용 무관
    # 선행 구분자를 **선택**으로 둔다 — 상대 경로(`docs/plans/x.md`)가 무매치라 게이트와 판정이
    #   비대칭이었다(게이트는 통과하는데 plan 판정은 안 켜지는 자리 = 곧 구멍).
    $isInPlansDir = ($targetPath -match '(?i)(^|[\\/])docs[\\/]plans[\\/][^\\/]+\.md$')

    $planGateTarget = $false
    if ($isPlanFileName) {
        # ⓐ plan 파일명 — Write면 내용과 무관하게 게이트(빈 plan 급조가 바로 차단 대상)
        if ($data.tool_name -eq 'Write') { $planGateTarget = $true }
    }
    if ($isPlanFileName -or $isInPlansDir) {
        # ⓑ docs/plans/*.md Write — 체크박스가 있을 때만 plan으로 본다
        #    (deferred.md 대장·brief 등 비 plan 문서를 오차단하지 않기 위함. 체크박스 없는 파일은
        #     통과시켜도 Test-PlanInDirectory가 plan으로 인정하지 않으므로 게이트가 새지 않는다.)
        if ($data.tool_name -eq 'Write' -and $isInPlansDir) {
            if ([string]$data.tool_input.content -match $planTaskRx) { $planGateTarget = $true }
        }
        # ⓒ 체크박스를 '새로 도입'하는 Edit/MultiEdit — 위 2단계 우회 차단.
        #    기존 plan의 정상 갱신은 전부 무매치다: 상태 변경([ ]→[x])은 old에도 체크박스가 있고,
        #    Progress Log·Retry Ledger·Deferred append는 체크박스를 도입하지 않는다.
        #    MultiEdit은 합산이 아니라 **edit 단위**로 본다 — edits는 순차 적용되므로 합산하면
        #    'edit#1이 도입한 체크박스'를 edit#2가 old로 참조하는 것만으로 old에 체크박스가 섞여
        #    무매치 조건이 깨진다(합산 판정의 false-negative).
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
        # 발동 흔적 판정 — plan-feature(정본 경로) 또는 implement-task(승인된 plan이 있어야 발동하는
        #   스킬이라 허용해도 우회로가 되지 않는다. 자율 루프가 예상 못 한 Write에서 차단되면 Halt 비용이
        #   크므로 안전 마진으로 허용). llm-wiki 등 plan 없이 발동 가능한 스킬은 넣지 않는다 —
        #   넣으면 "그 스킬을 켜서 게이트를 우회"하는 경로가 열린다.
        # fail-open: transcript 부재·읽기 실패는 통과(AGENTS 게이트와 동일 관례).
        $planSkillLaunched = $false
        $tpp = [string]$data.transcript_path
        if ([string]::IsNullOrWhiteSpace($tpp) -or -not (Test-Path -LiteralPath $tpp)) {
            $planSkillLaunched = $true
        } else {
            try {
                $planSkillLaunched = [bool](Select-String -LiteralPath $tpp -Quiet -Pattern @(
                    '"skill"\s*:\s*"pjc:plan-feature"',
                    'Launching skill: pjc:plan-feature',
                    '"skill"\s*:\s*"pjc:implement-task"',
                    'Launching skill: pjc:implement-task'))
            } catch { $planSkillLaunched = $true }
        }
        if (-not $planSkillLaunched) {
            [Console]::Error.WriteLine("[HARNESS] BLOCKED: plan 작성은 pjc:plan-feature 스킬로만 합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("직접 작성은 적대적 plan-reviewer 검토·영향 범위 전수 조사·Type 분류·사전 승인 항목을 통째로 우회합니다.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("해결 방법:")
            [Console]::Error.WriteLine("  1) Skill 도구로 pjc:plan-feature 호출 → 조사·검토·사용자 승인 후 plan 작성")
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
    '.resx', '.resw',
    # 마크업·스타일 (v1.98.0): .xml(설정·리소스 — strings.xml만 예외이던 것을 일반화)·
    #   .html/.htm(정적 페이지)·.css/.scss(스타일)는 오차단 비용 > 게이트 가치라 문서·설정과
    #   동급으로 허용한다(로직·구조 위험이 낮고, 시각 결과는 화면에서 즉시 드러남).
    #   .xaml은 코드 결합(바인딩·이벤트)이 강해 소스 코드로 유지.
    '.xml', '.html', '.htm', '.css', '.scss'
    # 참고: .env.example/.env.sample은 GetExtension이 '.example'/'.sample'을 반환해
    #       확장자 매칭이 안 되므로 아래 파일명 기반 예외에서 처리한다(실제 .env는 제외).
)

$ext = [System.IO.Path]::GetExtension($targetPath).ToLower()
# 실행 자산 예외 — .github/workflows/*.yml(CI: 임의 명령 실행)·package.json(scripts 실행)은
#   문서·설정처럼 무조건 허용하지 않고 plan 게이트를 적용한다. CI 파이프라인·빌드 스크립트를
#   plan 없이 바꾸는 구멍을 막는다. 일반 .json/.yml(tsconfig·docker-compose 등)은 계속 통과 —
#   실행 자산 2종만 정밀 타깃해 오탐(설정 파일 대량 차단)을 피한다. 선행 [\\/] 선택으로 상대·절대경로 모두 매치.
$execAssetName = [System.IO.Path]::GetFileName($targetPath)
$isExecAsset = ($targetPath -match '(^|[\\/])\.github[\\/]workflows[\\/][^\\/]+\.ya?ml$') -or
               ($execAssetName -eq 'package.json')
if (-not $isExecAsset -and ($alwaysAllowedExts -contains $ext)) { exit 0 }

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

# 시스템 임시 폴더(검증 스크립트·스크래치패드) — 무조건 허용 (의도된 완화).
# 글로벌 지침·하니스가 검증용 임시 스크립트를 시스템 임시 폴더에 쓰도록 지시하므로,
# plan 게이트(프로젝트 코드 보호)의 대상이 아니다 — 임시 산출물은 프로젝트에 커밋되지 않고,
# 파괴적 '실행'은 block-destructive가 별도 차단한다.
try {
    $tempRoot = [System.IO.Path]::GetTempPath().TrimEnd('\', '/') -replace '/', '\'
    $tpNorm = $targetPath -replace '/', '\'
    if ($tempRoot -and $tpNorm.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
} catch { }

# docs/plans/dist/build — 산출물·문서 디렉터리. 단 '소스 코드 파일이 아닐 때만' 우회한다.
# (폴더명 부분일치가 도메인 소스 폴더 — 예: src/Plans, src/build — 와 충돌해 소스가
#  plan 없이 새는 것을 막는다. 소스면 아래 plan 검사로 떨어진다.)
# 실행 자산 예외도 여기 전파한다 — dist/package.json·packages/plans/package.json 처럼 실행 자산이
#  산출물/문서 디렉터리명과 겹치면 이 우회로 plan 게이트가 새므로($isExecAsset 무시 시), 함께 배제한다.
if (-not $isExecAsset -and -not $isSourceCode -and (
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
        # 값치환 우회는 스타일/마크업 파일에만 적용한다 (T4 — require-plan 우회 차단):
        # 이 우회는 색상·치수 등 '값'만 바뀌는 CSS/XAML 작업용인데, 모든 소스에 적용하면
        # .cs의 `const int MaxRetries = 3;` → `100000` 같은 로직 변경(타임아웃·한계·포트)이 줄 수 무관하게
        # plan 없이 통과한다. → 스타일/마크업 확장자에서만 인정한다. (그 외 소스의 소규모 수치 변경은
        # 아래 '<=3줄' trivial 경로로 여전히 통과하므로 일상 작업엔 지장 없음.)
        $styleExts = @('.css', '.scss', '.sass', '.less', '.styl', '.pcss', '.xaml', '.axaml')
        $isStyleFile = $styleExts -contains $ext
        # 스타일 파일 + 값이 하나라도 정규화됨(치환 대상 존재) + 정규화 후 동일(구조 동일) + 새 정의 아님
        $isPureValueSwap = $isStyleFile -and (-not $definesNewSymbol) -and ($normOld -ne $oldStr) -and ($normOld -eq $normNew)

        # 작은 변경(3줄 + 300자, 새 정의 없음) 또는 순수 값 치환 → trivial 통과
        if (($maxLines -le 3 -and $maxLen -le 300 -and -not $definesNewSymbol) -or $isPureValueSwap) {
            $why = if ($isPureValueSwap) { '순수 값 치환(리터럴만 변경, 구조 동일)' } else { '<=3줄, 새 정의 없음' }
            # M7: 소스 파일의 3줄 이하 통과 중 상수·수치·로직 변경(타임아웃·한계·포트 등)은 plan 없이 새므로
            #   impact-warn(사후 caller 검출)에 더해 검토 권장을 상기한다(차단 아님).
            $extra = if ($isSourceCode) { ' 소스의 상수·수치·로직 변경이면 plan-feature 검토를 권장합니다.' } else { '' }
            [Console]::Error.WriteLine("[HARNESS] Trivial edit ($why): plan 검사 우회. 영향은 impact-warn hook이 검증합니다.$extra")
            exit 0
        }
    }
}

# ---- 신규 파일 Trivial 통과 (Write — 테스트·재현 스크립트, v1.98.0) ----
# 종전엔 trivial 우회가 Edit/MultiEdit 전용이라 5줄짜리 재현 스크립트·단위테스트 신규 작성도
#   plan 없이는 불가했다 — 그 경우 모델의 최저비용 합법 경로가 "빈 plan.md 급조"(형식적 plan 생산)가
#   되는 역효과가 있었다. 신규 파일도 ①내용 30줄 이하 ②경로가 테스트 디렉터리이거나 파일명이
#   repro/scratch/tmp 네이밍일 때만 조건부 통과한다(일반 소스 디렉터리 신규 파일은 여전히 게이트).
if ($data.tool_name -eq 'Write' -and $null -ne $data.tool_input.content) {
    $wContent = [string]$data.tool_input.content
    $wLines = ($wContent -split "`n").Count
    $isTestPath = ($targetPath -match '(?i)[\\/](tests?|__tests__|spec)[\\/]') -or
                  ($baseName -match '(?i)^(repro|scratch|tmp)[\w.-]*$')
    if ($wLines -le 30 -and $isTestPath) {
        [Console]::Error.WriteLine("[HARNESS] Trivial write (테스트·재현 파일, ${wLines}줄 <= 30): plan 검사 우회. 영향은 impact-warn hook이 검증합니다.")
        exit 0
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
# docs/plans/ 하위에 '실제 plan'(task 체크박스가 있는 .md)이 1개라도 있는가 (v1.118.0).
# 종전엔 디렉터리 존재만으로 plan 있음으로 판정했다 — 그러면 체크박스 없는 .md 하나를 거기 쓰는 것만으로
#   (위 게이트가 의도적으로 허용하는 파일이다) 디렉터리가 생겨 이후 모든 코드 Write가 plan 없이 통과했다.
#   즉 게이트를 우회해 plan 판정을 켜는 경로였다. 판정 기준을 게이트와 같은 $planTaskRx로 맞춰 그 틈을 없앤다.
# 비용: 이 함수는 코드 Write마다 검색 시작점(최대 4)×상향 8단계로 반복 호출되므로 무제한 정독은
#   hook 지연이 된다 → 최신 수정순 10개까지만, Select-String -Quiet로 매치 즉시 중단한다.
#   상한 밖에만 plan이 있으면 미검출되어 차단되지만(fail-closed), 그 경우 아래 차단 메시지가 사유를
#   알려주므로 사용자가 진단할 수 있다(진단 불가능한 fail-closed는 안전측이 아니다).
function Test-PlansDirHasPlan {
    param([string]$PlansDir)
    try {
        $files = @(Get-ChildItem -LiteralPath $PlansDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 10)
        foreach ($f in $files) {
            if (Select-String -LiteralPath $f.FullName -Quiet -Pattern $script:planTaskRx) { return $true }
        }
    } catch { }
    return $false
}

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
    # docs/plans/는 디렉터리 존재가 아니라 '체크박스 plan 실재'로 판정한다.
    $plansDir = Join-Path $Dir 'docs/plans'
    if (Test-Path -LiteralPath $plansDir -PathType Container) {
        return (Test-PlansDirHasPlan -PlansDir $plansDir)
    }
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
    # ---- 완료된/빈 plan 비차단 경고 (G4 + H3) ----
    # plan은 존재하지만 task 체크박스가 전부 [x](미완료 0)면 '완료된 옛 plan'에 기대는 변경일 수 있고,
    # 체크박스가 아예 0개면 '빈/플레이스홀더 plan'(내용 없는 plan.md로 게이트 무력화)일 수 있다
    # → 둘 다 plan-feature로 계획 작성/갱신 권유 (차단 아님).
    # 단일 plan 파일(plan.md/PLAN.md/docs/plan.md)만 판정한다. docs/plans 디렉터리(복수 plan)는
    # 어느 것이 이번 작업인지 모호하므로 경고하지 않는다(오탐 방지).
    $planFile = $null
    foreach ($cand in @('plan.md', 'PLAN.md', 'docs/plan.md')) {
        $pf = Join-Path $foundIn $cand
        if (Test-Path -LiteralPath $pf -PathType Leaf) { $planFile = $pf; break }
    }
    if ($planFile) {
        try {
            # 세션당 1회 디듑 (v1.98.0): G4(완료 plan)·H3(빈 plan) 경고가 상태 변화 없이 편집마다
            #   반복 주입되던 것을 suggest-agents-record와 동일한 .state 세션 마커로 억제한다 —
            #   같은 세션·같은 plan 파일·같은 경고 종류는 1회만. 반복 주입은 컨텍스트를 낭비하고
            #   "plan을 갱신하라"는 문구의 반복 노출이 불필요한 plan 재작성으로 오도할 수 있다.
            $warnStateDir = Join-Path $env:USERPROFILE '.claude/.state/require-plan-warn'
            try { New-Item -Force -ItemType Directory -Path $warnStateDir | Out-Null } catch {}
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
            # 미완료 마커 [ ] 또는 [/], 완료 마커 [x]/[X] (줄 시작의 '- [ ]'/'* [ ]' 형태).
            # 불릿은 마크다운 표준 '-'·'*' 둘 다 인식한다(require-task-checkbox M6와 정합 —
            #   '* [ ]' 불릿 plan을 체크박스 0개로 오판해 H3 '빈/플레이스홀더' 경고를 오탐하던 구멍 보완).
            $incomplete = [regex]::Matches($planText, '(?m)^\s*[-*]\s*\[[ /]\]').Count
            $done = [regex]::Matches($planText, '(?m)^\s*[-*]\s*\[[xX]\]').Count
            if ($incomplete -eq 0 -and $done -ge 1) {
                if (Test-WarnOnce -Kind 'G4') {
                    $warnMsg = "[HARNESS] 이 plan은 완료된 것으로 보입니다 (task 체크박스 ${done}개 전부 [x], 미완료 0). " +
                               "이번 코드 변경이 이 완료된 plan의 범위 내 후속 작업(리뷰 지적 수정·마무리·문서 갱신 등)이면 새 plan 없이 그대로 진행하세요. " +
                               "완료된 plan과 무관한 '새 작업'일 때만 plan-feature로 plan을 갱신하세요 — require-plan은 plan 존재만 보고 통과시키므로, 완료된 옛 plan으로 무관한 변경이 새는 것을 막지 못합니다. (이 경고는 세션당 1회)"
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
                               "require-plan은 plan 존재만 보고 통과시키므로, 내용 없는 plan으로 코드 변경이 통과하는 것을 막지 못합니다. plan-feature로 실제 task를 작성하세요. " +
                               "(단 이 plan.md가 분할 plan 포인터·스텁이면 실제 task는 docs/plans/ 하위 plan에 있으니 무시하세요. 이 경고는 세션당 1회)"
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
[Console]::Error.WriteLine("  - plan.md, PLAN.md, docs/plan.md, docs/plans/")
[Console]::Error.WriteLine("위 위치 어디에도 plan이 없습니다.")

# 진단 분기(v1.118.0): docs/plans/는 있는데 체크박스 plan이 없어 판정이 꺼진 경우, "plan이 없다"는
#   메시지만 보면 사용자는 눈앞에 .md가 보이는데 없다는 말을 듣게 되어 원인을 알 수 없다.
#   fail-closed는 진단 가능할 때만 안전측이므로 사유를 명시한다.
$plansDirDiag = Join-Path $projectRoot 'docs/plans'
if (Test-Path -LiteralPath $plansDirDiag -PathType Container) {
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("※ docs/plans/ 디렉터리는 있으나, task 체크박스(- [ ] / - [x])가 있는 plan 파일이 없습니다")
    [Console]::Error.WriteLine("   (최신 수정순 10개 검사). 체크박스가 없는 문서(대장·메모 등)는 plan으로 인식하지 않습니다.")
}
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("해결 방법:")
[Console]::Error.WriteLine("  1) plan-feature skill 호출:")
[Console]::Error.WriteLine("     사용자에게 '계획 작성해줘' 라고 요청하거나 /plan-feature <설명>")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("  2) 긴급 1줄 수정 우회 — 사용자만 설정 가능 (Claude Code 시작 전 터미널에서):")
[Console]::Error.WriteLine("     `$env:CLAUDE_HARNESS_QUICK = '1'")
[Console]::Error.WriteLine("     ※ Claude가 Bash 도구로 설정해도 hook 프로세스에 전파되지 않아 무효입니다 — 시도하지 말고,")
[Console]::Error.WriteLine("       필요하면 사용자에게 위 설정(후 Claude Code 재시작)을 안내하세요.")
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("  3) plan.md 위치 확인:")
[Console]::Error.WriteLine("     루트의 plan.md 파일 위치와 검색 시작점이 다른 경로일 수 있습니다.")
[Console]::Error.WriteLine("     모노레포라면 작업 디렉터리 위쪽에 plan.md 또는 docs/plans/ 가 있어야 합니다.")

Write-RpEvent 'block' 'plan 없음 차단'
exit 2
