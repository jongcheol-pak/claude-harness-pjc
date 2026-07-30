# Stop hook - PowerShell 버전
# 에이전트가 작업 종료를 시도할 때 실행.
# 마지막 커밋에 검증 증거가 없으면 stderr 경고 (강제 차단 X — 의도된 비차단).
#
# [설계: 검사 1~3은 비차단(exit 0 + stderr) — 공식 Stop hook 시맨틱 확인 결과]
#   Stop hook 피드백 경로는 셋: exit 2(=종료 차단 + stderr를 모델에 전달) /
#   stdout JSON(decision=block → 종료 차단 + reason을 모델에 전달, 또는 additionalContext →
#   종료 안 막고 컨텍스트 주입) / exit 0 + stderr(=비차단, 사용자 transcript용, 모델엔 미전달).
#   이 hook은 implement-task 종료뿐 아니라 '모든' 종료 시도(일반 대화·질문 답변 후 포함)에
#   발동하므로, **검사 1~3처럼 조건이 넓은 것**을 차단으로 바꾸면 무관한 종료까지 막는다.
#   따라서 1~3은 의도적으로 exit 0 + stderr 소프트 리마인더로 둔다(사용자가 transcript에서
#   보고 판단; 모델 강제는 안 함). **이 셋을 차단으로 바꾸지 말 것.**
#
# [예외: 검사 4만 조건부 차단 (v1.148.0)]
#   아래 검사 4는 위 금지의 예외다 — 조건을 6개 AND로 좁혀 "무관한 종료에는 애초에 발동하지
#   않기" 때문에 위 근거("모든 종료에 발동한다")가 성립하지 않는다. 자율 루프가 예고만 남기고
#   멈추는 것은 경고로는 못 고친다(stderr는 모델에 전달되지 않아 루프가 되살아나지 않는다).
#   판정 불가는 전부 fail-open이며, 차단해도 세션·plan당 3회가 상한이다.

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로가 깨져 cwd 이동·git 검사 대상이 어긋난다. 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

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

# [이벤트 로깅] STOP WARNING 방출을 오탐 리뷰 데이터로 적재 — 경고 판정 무변경, 실패 전면 격리.
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}
function Write-ReEvent {
    param([string]$Rule)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            Write-HookEvent 'require-evidence' 'warn' $Rule ''
        }
    } catch {}
}

# ---- [세션 디듑] 같은 세션·같은 프로젝트의 동일 종류 경고를 1회로 억제 (v1.138.0) ----
# 이 hook은 '모든' 종료 시도에 발동하므로, 상태가 그대로여도 같은 경고가 매 종료마다 반복 방출됐다
#   (실측: 'checkpoint 미완료 종료' 415건·'미커밋 코드 변경' 193건 — 읽히지 않는 반복은 신호가 아니라 소음이다).
# 판정·문구·exit 코드는 무변경이다 — 첫 발화는 종전과 동일하고 2번째 이후 동일 경고만 조용해진다.
# 키에 cwd를 포함하는 이유: 세션이 같아도 **프로젝트가 다르면 별개 상황**이라 각각 알려야 한다
#   (post-write-checks가 키에 파일 경로를 넣는 것과 같은 이유).
$reBase = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$reStateDir = Join-Path $reBase '.claude/.state/require-evidence-warn'
try { New-Item -Force -ItemType Directory -Path $reStateDir | Out-Null } catch {}
$reSid = if ($data.session_id) { ([string]$data.session_id) -replace '[^\w.-]', '_' } else { 'nosid' }
$reCwd = if ($data.cwd) { [string]$data.cwd } else { (Get-Location).Path }
function Test-EvWarnOnce {
    param([string]$Kind)
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($reCwd + '|' + $Kind)) | ForEach-Object { $_.ToString('x2') }) -join ''
        $mk = Join-Path $reStateDir ($reSid + '_' + $hash)
        if (Test-Path -LiteralPath $mk) { return $false }
        New-Item -Force -ItemType File -Path $mk | Out-Null
        return $true
    } catch { return $true }   # 마커 실패 시 경고 누락보다 중복이 낫다(fail-open)
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
if ($firstLine -match '^checkpoint:' -and (Test-EvWarnOnce 'checkpoint')) {
    [Console]::Error.WriteLine("STOP WARNING: 마지막 커밋이 checkpoint입니다 - task가 완료되지 않았을 수 있습니다.")
    [Console]::Error.WriteLine("implement-task의 Phase D를 완료하지 않은 채 종료하려 합니다.")
    [Console]::Error.WriteLine("정말 종료할 거면 사용자에게 현재 상태를 보고하세요.")
    Write-ReEvent 'checkpoint 미완료 종료'
}

# 2. task 커밋이지만 검증 '결과' 증거 없음
# 단어만(Build/Tests/Review)이 아니라 '결과 동반 패턴'을 요구한다(G4) — "Review: 안 함"처럼
# 단어만 있고 결과가 없는 빈 증거가 통과하지 못하게 한다.
# 결과 패턴: Build ...OK/성공, Tests N(개수), Review ...OK/spec/quality/통과 중 하나.
$evidenceRx = '(Build[^\r\n]*\b(OK|pass|passed|성공)\b)|(Tests?\s*[:=]?\s*\d)|(Review[^\r\n]*\b(OK|spec|quality|passed|통과)\b)'
$hasEvidence = $false
if ($firstLine -match '^T\d+:') {
    if ($lastMsg -notmatch $evidenceRx) {
        # 디듑은 '출력'에만 적용한다 — 아래 $hasEvidence 판정(2-1 transcript 대조의 진입 조건)은 억제와 무관하게 그대로 흐른다.
        if (Test-EvWarnOnce 'no-evidence') {
            [Console]::Error.WriteLine("STOP WARNING: task 커밋에 검증 '결과' 증거가 없습니다 (예: Build ...OK / Tests N / Review ...OK).")
            [Console]::Error.WriteLine("Done = Proof 원칙 위반 가능 - 단어만이 아니라 실제 결과를 커밋 메시지에 적거나 사용자에게 보고하세요.")
            Write-ReEvent '검증 증거 없음'
        }
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
            # 표준 빌드/테스트 + 스크립트 기반 검증(build.ps1/sh/py·tsc·프로젝트 정적검사 스크립트)까지
            #   포함한다(v1.98.0) — 종전엔 표준 명령만 있어 './build.ps1'·'tsc'로 검증한 정직한 세션이
            #   실행 흔적 없음으로 오경고됐다.
            $traceRx = '"command"\s*:\s*".{0,600}?(dotnet (build|test)|npm (test|run )|npx |yarn |pnpm |pytest|cargo (build|test)|gradlew?\b|go (build|test)|mvn |msbuild|make |ctest|python(3)? -m (py_compile|build|pytest)|ParseFile|[.\\/]*build\.(ps1|sh|py|js)|\btsc\b|\brun-hook-evals\b|check_consistency|\brun_lint_evals\b)'
            if (-not (($tail -join "`n") -match $traceRx) -and (Test-EvWarnOnce 'no-trace')) {
                [Console]::Error.WriteLine("STOP WARNING: 커밋에 검증 증거 텍스트는 있으나 이 세션 transcript에서 빌드/테스트 실행 흔적을 찾지 못했습니다.")
                [Console]::Error.WriteLine("증거가 실행 없이 적혔을 수 있습니다 - 실제로 빌드/테스트를 실행했는지 확인하세요 (이전 세션에서 실행했으면 무시).")
                Write-ReEvent '실행 흔적 없음'
            }
        }
    } catch { }
}

# 3. 코드 파일 미커밋 변경 검출 (G6) — 구현 후 commit 누락 가능성 경고 (비차단)
# 일반 대화·문서(.md)만 변경한 종료에는 안 뜨도록 '코드 확장자' 변경만 본다.
# (v1.98.0) 세션 성격 가드: 원래 dirty한 워킹트리에서 질문·리뷰만 한 세션에도 매 종료마다 뜨던
#   반복 노이즈를 줄인다 — 이 세션 transcript에 Write/Edit 도구 사용 흔적이 있을 때만 경고한다
#   (transcript 없거나 읽기 실패면 종전대로 경고 — fail-open, 안전측).
$sessionEdited = $true
try {
    $tp3 = if ($data) { $data.transcript_path } else { $null }
    if ($tp3 -and (Test-Path -LiteralPath $tp3 -PathType Leaf)) {
        $tail3 = Get-Content -LiteralPath $tp3 -Tail 3000 -ErrorAction Stop
        $sessionEdited = (($tail3 -join "`n") -match '"name"\s*:\s*"(Write|Edit|MultiEdit|NotebookEdit)"')
    }
} catch { }
$codeExts = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.go', '.rs', '.cpp', '.c', '.h', '.hpp', '.fs', '.kt', '.swift', '.vb', '.razor', '.xaml', '.vue', '.svelte')
$porcelain = if ($sessionEdited) { & git status --porcelain 2>$null } else { $null }
if ($porcelain) {
    $codeChanges = New-Object System.Collections.Generic.List[string]
    foreach ($pl in $porcelain) {
        if ($pl.Length -lt 4) { continue }
        $p = $pl.Substring(3).Trim().Trim('"')
        if ($p -match '->') { $p = ($p -split '->')[-1].Trim().Trim('"') }   # rename은 새 경로 기준
        $e = [System.IO.Path]::GetExtension($p).ToLower()
        if ($codeExts -contains $e) { [void]$codeChanges.Add($p) }
    }
    if ($codeChanges.Count -gt 0 -and (Test-EvWarnOnce 'uncommitted')) {
        [Console]::Error.WriteLine("STOP WARNING: 커밋되지 않은 코드 파일 변경이 $($codeChanges.Count)개 있습니다 - 구현 후 commit을 누락했을 수 있습니다.")
        foreach ($c in ($codeChanges | Select-Object -First 8)) { [Console]::Error.WriteLine("  - $c") }
        [Console]::Error.WriteLine("구현이 끝났으면 Phase D(commit)를 수행하거나, 의도된 미커밋이면 사용자에게 상태를 보고하세요.")
        Write-ReEvent '미커밋 코드 변경'
    }
}

# ---- 4. 자율 루프 미완료 정지 차단 (v1.148.0) — 이 hook에서 유일한 차단 경로 ----
# implement-task 자율 루프가 "예고만 남기고 turn을 끝내" 멈추는 것을 되돌린다.
#   관측 사례: "여기까지 진행 상황을 정리 합니다. 계속 T5부터 이어서 진행하겠습니다." 출력 후 정지.
#   질문이 아니라 평서문이라 "묻지 않는다" 규칙은 지킨 것처럼 보이지만, 도구 호출 없이 텍스트만
#   내면 turn이 끝나 사용자 입력을 기다리게 되므로 결과는 확인 요청과 같은 루프 정지다.
# [문구 정본] 아래 $rxAdvance가 잡는 문구의 정본은 implement-task/SKILL.md "🚫 금지 표현 ②"다.
#   그 목록을 고치면 여기도 함께 고친다 — 갈리면 규칙에 없는 것을 잡거나 잡아야 할 것을 놓친다.
# [6조건 AND] 하나라도 불충족이면 통과. 판정에 필요한 정보를 못 얻으면 전부 fail-open(통과).
if ($data.stop_hook_active -ne $true -and $env:CLAUDE_HARNESS_QUICK -ne '1') {

    # 조건 ②: plan에 미완료 task가 있는가.
    #   task 형식 두 가지를 모두 인정한다 — ⓐ 템플릿 '- [ ] T1. 제목'(plan-template.md)
    #   ⓑ heading '### T1 — 제목' + 그 안의 '- [ ] **Type**'(실사용 plan 형식).
    #   한쪽만 잡으면 다른 형식으로 쓰인 plan에서 이 검사가 통째로 무발화한다.
    #   plan 인정은 파일 수준 게이트로 한다 — docs/plans/에는 plan 아닌 문서(deferred.md)도 있다
    #   (session-context.ps1:50-52와 같은 취지, 패턴만 두 형식으로 넓혔다).
    $rxPlanAny  = '(?m)^\s*- \[[ /xX]\]\s*T\d+|^###\s*T\d+'
    $rxPlanOpen = '(?m)^\s*- \[[ /]\]\s*T\d+|^\s*- \[[ /]\]\s*\*\*Type\*\*'

    $loopPlanText = $null
    try {
        $cwdNow = (Get-Location).Path
        $rootPlan = Join-Path $cwdNow 'plan.md'
        if (Test-Path -LiteralPath $rootPlan -PathType Leaf) {
            # 루트 plan.md가 있으면 그것만 본다 — docs/plans/로 폴백하면 과거 plan의 미완료분으로
            #   무관한 세션을 차단할 수 있다(session-context.ps1:53-58과 동일 우선순위).
            $t = Get-Content -LiteralPath $rootPlan -Raw -Encoding UTF8 -ErrorAction Stop
            if ($t -match $rxPlanAny) { $loopPlanText = $t }
        } else {
            $plansDir = Join-Path $cwdNow 'docs/plans'
            if (Test-Path -LiteralPath $plansDir -PathType Container) {
                foreach ($pf in @(Get-ChildItem -LiteralPath $plansDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 5)) {
                    $t = $null
                    try { $t = Get-Content -LiteralPath $pf.FullName -Raw -Encoding UTF8 } catch {}
                    if ($t -and $t -match $rxPlanAny) { $loopPlanText = $t; break }
                }
            }
        }
    } catch { $loopPlanText = $null }   # 읽기 실패 → fail-open

    $loopOpen = ($null -ne $loopPlanText -and $loopPlanText -match $rxPlanOpen)

    # 조건 ④의 판정식 — 마지막 응답이 '진행 예고'인가(positive) + 정당한 정지 신호가 없는가(negative).
    #   positive를 요구하는 이유: 부재 기반(정당 신호가 없으면 정지로 간주)만 쓰면 목록에 없는
    #   모든 정상 종료 문구가 차단 후보가 된다. 실제 사고에는 예고 문구라는 양성 신호가 있다.
    #   매칭은 어간 기반이다 — 리터럴로 잡으면 "정리 합니다"(어절 삽입)·"진행할게요"(어미 변형)를
    #   전부 놓친다(실제 사고 문장이 리터럴 4문구 중 3개를 빗나갔다).
    #   negative는 넓게 잡는다 — 넓힐수록 미차단(안전측)으로 기운다.
    $rxAdvance = '(이어서|계속)\s*진행(하겠|할게|합니|하려)|여기까지[^\r\n]{0,20}정리\s*(하겠|합니|할게)|T\d+\s*(부터|까지)[^\r\n]{0,30}(진행|하겠|할게)'
    $rxLegit = '⛔|🎉|⏸️|\?|승인|확인 요청|확인 부탁|선택해|중단 보고|Halt'
    function Test-AdvancePromise {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
        return ($Text -match $script:rxAdvance -and $Text -notmatch $script:rxLegit)
    }

    # 조건 ④ 1차 — stdin의 last_assistant_message가 오면 그것으로 즉시 판정한다(문자열 매칭만,
    #   파일 I/O 0). 거짓이면 아래 transcript 읽기를 통째로 건너뛴다.
    # ⚠ 이 필드의 실환경 제공 여부는 미실증이다(공식 문서 기준으로는 존재). **없어도 검사가 죽지
    #   않도록** 아래에 transcript 폴백을 둔다 — 이 신호 하나에 기대면 필드가 안 올 때 검사 4가
    #   프로덕션에서 영구 무발화하는데, 골든은 필드를 직접 주입하므로 green이라 발견되지 않는다.
    $lastMsgL = if ($data) { [string]$data.last_assistant_message } else { '' }
    $haveStdinMsg = -not [string]::IsNullOrWhiteSpace($lastMsgL)
    $advancePromise = $false
    if ($haveStdinMsg) { $advancePromise = (Test-AdvancePromise $lastMsgL) }

    # 조건 ③⑤(+ 필요 시 ④ 폴백): transcript를 한 번만 tail해서 함께 처리한다.
    #   stdin 필드가 왔는데 ④가 거짓이면 여기 진입하지 않는다(불필요한 I/O 제거).
    $loopSkill = $false
    $userStop = $false
    $userFound = $false
    if ($loopOpen -and ($advancePromise -or -not $haveStdinMsg)) {
        $tpL = if ($data) { [string]$data.transcript_path } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($tpL) -and (Test-Path -LiteralPath $tpL -PathType Leaf)) {
            try {
                $tailL = @(Get-Content -LiteralPath $tpL -Tail 3000 -ErrorAction Stop)
                $loopSkill = (($tailL -join "`n") -match '"skill"\s*:\s*"pjc:implement-task"|Launching skill: pjc:implement-task')

                # 역순 1회 스캔으로 ⑤(마지막 user 텍스트)와 ④ 폴백(마지막 assistant 텍스트)을 함께 찾는다.
                # 조건 ⑤ 추출 규칙: "type":"user" 엔트리 중 실제 사용자 텍스트만 본다.
                #   tool_result도 user 역할로 기록되므로 반드시 제외한다 — 포함하면 마지막 user
                #   텍스트가 늘 도구 결과가 되어 이 조건이 항상 참이 되고, 사용자가 "그만"이라고
                #   한 세션에서도 차단이 걸린다(이 검사에서 가장 위험한 오작동).
                # 파싱 상한 200: hook timeout이 10초(hooks.json)인데 ConvertFrom-Json은 호출당 비용이
                #   있어, 텍스트 없는 엔트리가 수천 줄 이어지는 최악 입력에서 예산을 넘길 수 있다.
                #   최근 200개 후보면 '직전 발화' 판정에 충분하다(더 거슬러 올라갈 이유가 없다).
                $needAsst = (-not $haveStdinMsg)
                $parsed = 0
                for ($i = $tailL.Count - 1; $i -ge 0; $i--) {
                    if ($userFound -and -not $needAsst) { break }
                    if ($parsed -ge 200) { break }
                    $ln = $tailL[$i]
                    $isUser = ($ln -match '"type"\s*:\s*"user"')
                    $isAsst = ($ln -match '"type"\s*:\s*"assistant"')
                    if (-not $isUser -and -not $isAsst) { continue }
                    if ($isUser -and ($ln -match '"type"\s*:\s*"tool_result"' -or $ln -match '"tool_use_id"')) { continue }
                    $obj = $null
                    $parsed++
                    try { $obj = $ln | ConvertFrom-Json } catch { continue }
                    $mc = $obj.message.content
                    if ($null -eq $mc) { $mc = $obj.content }   # 스키마 변형 대비(최상위 content)
                    $txt = $null
                    if ($mc -is [string]) { $txt = $mc }
                    elseif ($mc) { $txt = ((@($mc) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n") }
                    if ([string]::IsNullOrWhiteSpace($txt)) { continue }
                    if ($isUser -and -not $userFound) {
                        $userFound = $true
                        # 사용자가 스스로 루프를 끝내거나 범위를 한정했으면 정상 종료다.
                        #   'T<N>만'은 SKILL.md '재개 진입'이 명시적으로 허용하는 단일 task 실행.
                        if ($txt -match '그만|중단|멈춰|멈춤|여기까지|이제 ?됐|나중에|\bstop\b|T\d+\s*만') { $userStop = $true }
                    } elseif ($isAsst -and $needAsst) {
                        # ④ 폴백 — stdin 필드가 없을 때만. 마지막 assistant 텍스트로 예고를 판정한다.
                        $needAsst = $false
                        $advancePromise = (Test-AdvancePromise $txt)
                    }
                }
            } catch { $loopSkill = $false }   # 읽기 실패 → fail-open
        }
    }

    if ($loopOpen -and $loopSkill -and $advancePromise -and $userFound -and (-not $userStop)) {

        # 조건 ② 교차 확인: 체크박스는 갱신 누락이 가능한 최약 신호다(SKILL.md '재개 진입' —
        #   "세 신호가 어긋나면 git log를 신뢰"). 미완료로 표시된 task 중 완료 커밋(T<N>:)이
        #   없는 것이 하나라도 있어야 실제 미완료로 본다. 조회는 200건으로 상한(hook 10초 타임아웃).
        $openNums = New-Object System.Collections.Generic.List[string]
        foreach ($mm in [regex]::Matches($loopPlanText, '(?m)^\s*- \[[ /]\]\s*T(\d+)')) { [void]$openNums.Add($mm.Groups[1].Value) }
        foreach ($sec in [regex]::Matches($loopPlanText, '(?ms)^###\s*T(\d+)\b(.*?)(?=^###\s|\z)')) {
            if ($sec.Groups[2].Value -match '(?m)^\s*- \[[ /]\]\s*\*\*Type\*\*') { [void]$openNums.Add($sec.Groups[1].Value) }
        }
        $stillOpen = $false
        if ($openNums.Count -gt 0) {
            $glogText = ''
            try { $glogText = ((& git log --oneline -n 200 2>$null) -join "`n") } catch {}
            foreach ($n in ($openNums | Select-Object -Unique)) {
                if ($glogText -notmatch ('T' + $n + ':')) { $stillOpen = $true; break }
            }
        }

        if ($stillOpen) {
            # 차단 상한 (세션·plan당 3회) — 판정이 어긋나 반복 차단되더라도 사용자가 세션을
            #   끝낼 수 없는 상태에 갇히지 않게 한다. 카운터는 경고 디듑과 같은 .state 계층.
            $blkFile = $null
            try {
                $md5b = [System.Security.Cryptography.MD5]::Create()
                $hb = ($md5b.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($reCwd + '|loop-block')) | ForEach-Object { $_.ToString('x2') }) -join ''
                $blkFile = Join-Path $reStateDir ($reSid + '_' + $hb + '.count')
            } catch {}
            $blkCount = 0
            if ($blkFile -and (Test-Path -LiteralPath $blkFile)) {
                try { $blkCount = [int]((Get-Content -LiteralPath $blkFile -Raw -ErrorAction Stop).Trim()) } catch { $blkCount = 0 }
            }

            if ($blkCount -lt 3) {
                try { if ($blkFile) { Set-Content -LiteralPath $blkFile -Value ([string]($blkCount + 1)) -Encoding ASCII } } catch {}
                try {
                    if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
                        Write-HookEvent 'require-evidence' 'block' '자율 루프 미완료 정지' ''
                    }
                } catch {}

                $reasonText = '[pjc] 자율 루프가 미완료 상태로 종료하려 합니다. plan에 미완료 task가 남아 있고(완료 커밋 없음), 마지막 응답이 진행 예고로 끝났습니다 - implement-task 금지 표현 2(예고를 마지막 말로 남기고 turn을 끝내지 말 것)에 해당합니다. 지금 다음 task의 Phase P를 시작하세요(Read/grep 등 도구 호출로 이어갈 것). 상태 기록이 필요하면 대화에 요약을 출력하지 말고 plan.md에 쓰십시오. 정말 멈춰야 하는 상황이면 Halt 보고 형식(## 작업 중단)으로 사유를 적으십시오.'
                [Console]::Out.WriteLine((@{ decision = 'block'; reason = $reasonText } | ConvertTo-Json -Compress))
                exit 0
            }
        }
    }
}

exit 0
