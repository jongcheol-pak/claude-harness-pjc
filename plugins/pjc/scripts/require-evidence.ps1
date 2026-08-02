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
#   아래 검사 4는 위 금지의 예외다 — 조건을 AND로 좁혀 "무관한 종료에는 애초에 발동하지
#   않기" 때문에 위 근거("모든 종료에 발동한다")가 성립하지 않는다. 자율 루프가 멈추는 것은
#   경고로는 못 고친다(stderr는 모델에 전달되지 않아 루프가 되살아나지 않는다).
#   판정 불가는 전부 fail-open이며, 차단해도 세션·plan당 3회가 상한이다.
#   잡는 정지는 **4유형**이다 — ② 진행 예고만 남기고 turn 종료 / ③ 세션 전환·컨텍스트 우려
#   제안 / ④ 중간 수동 실행·확인 요청 / ⑤ 순수 진행 요약으로 turn 종료.
#   유형별 판정 규칙은 검사 4 본문 참조.

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

# ---- 4. 자율 루프 미완료 정지 차단 (v1.148.0, ③④ 확대 v1.149.0, ⑤ 확대 v1.150.0) — 이 hook에서 유일한 차단 경로 ----
# implement-task 자율 루프가 미완료 상태로 멈추는 것을 되돌린다. 정지 4유형을 잡는다:
#   ② 진행 예고만 남기고 turn 종료 — "여기까지 진행 상황을 정리 합니다. 계속 T5부터 이어서
#      진행하겠습니다." 질문이 아니라 평서문이라 "묻지 않는다" 규칙은 지킨 것처럼 보이지만,
#      도구 호출 없이 텍스트만 내면 turn이 끝나 결과는 확인 요청과 같은 루프 정지다.
#   ③ 세션 전환·컨텍스트 우려 제안 — "이대로 계속할지, 새 세션으로 옮길지 알려주세요."
#      컨텍스트 한계는 Halt 사유가 아니다(정답은 압축 통과). 이 유형은 위임 자체를 반납해
#      사용자가 "새 세션으로"라고 답하면 대화 맥락이 통째로 버려진다.
#   ④ 중간 수동 실행·확인 요청 — "여기서 한번 직접 실행해 보시겠어요?" 기계 검증으로 되는
#      것은 직접 실행해야 하고, 안 되는 것은 ⏳ HUMAN-VERIFY로 최종 보고에 넘긴다.
#   ⑤ 순수 진행 요약으로 turn 종료 — "T3 완료. 변경 파일 3개, 빌드 통과." 묻지도 예고하지도
#      않아 규칙을 어긴 흔적이 없어 보이지만, 도구 호출 없이 텍스트만 내면 결과는 ②와 같다.
#      **정상 진행 보고와 문면이 같은 유일한 유형**이라 억제 신호를 함께 둔다(아래 $rxUserAsk).
# [문구 정본] 아래 $rxAdvance(②)·$rxHandoff(③)·$rxManualAsk(④)·$rxProgressOnly(⑤)가 잡는 문구의
#   정본은 implement-task/SKILL.md "🚫 금지 표현" ②③④⑤ 네 절이다. 그 목록을 고치면 여기도 함께
#   고친다 — 갈리면 규칙에 없는 것을 잡거나 잡아야 할 것을 놓친다(골든 L12가 SKILL.md에서
#   문구를 읽어 주입하므로 드리프트는 테스트 FAIL로 드러난다).
# [조건 AND] 하나라도 불충족이면 통과. 판정에 필요한 정보를 못 얻으면 전부 fail-open(통과).
# [QUICK 우회] 차단 성격의 hook은 모두 $env:CLAUDE_HARNESS_QUICK='1' 탈출구를 둔다
#   (require-plan-for-write·require-task-checkbox와 동일 관례) — 골든 러너·긴급 상황에서 차단을
#   끌 수단이 없으면 오작동 시 세션을 끝낼 방법이 사라진다. 6조건과 별개인 운영 스위치다.
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

    # ③ 세션 전환·컨텍스트 우려 제안 — 2요소 근접(어순 ⓐ→ⓑ 고정, 40자 이내).
    #   ⓐ 세션 전환 명사 → ⓑ 전환·판단 위임 어미.
    #   ⓐ에서 '컨텍스트'·'대화가 길-' 같은 **상태 서술 명사는 뺐다** — 그 명사는 규칙 4를
    #   수행하는 정상 보고("컨텍스트 관리 규칙에 따라 plan.md를 갱신했고 다음 작업자가
    #   이어가시면 됩니다")에도 자연스럽게 등장해, ⓑ의 흔한 존댓 어미와 만나면 **정답 행동이
    #   차단된다**(리뷰 재현 반례). 실제 위반문은 예외 없이 '새 세션'·'/clear'처럼
    #   **전환 대상을 명시**하므로 ⓐ를 좁힌 것만으로는 탐지력이 줄지 않는다(SKILL.md ③ 문구 전건
    #   매치로 실증). **단 ⓑ는 폐쇄 목록이라 미탐이 있다** — "새 세션에서 계속하는 게 좋겠습니다"·
    #   "새 세션으로 옮기는 것을 추천합니다" 같은 변형은 잡히지 않는다. ④와 같은 트레이드오프로
    #   **의도적으로 수용**한다: 1차 방어선은 문서 규칙이고, 어미를 넓히면 정상 보고를 덮치는
    #   오차단이 즉시 발생한다(F-7 m3).
    $rxHandoff = '(새\s*세션|/clear|새\s*대화|세션을?\s*(옮|바꾸|나눠))[^\r\n]{0,40}(옮길지|옮길까|계속할지|새로\s*시작하시|권합니다|알려주세요|이어가시)'

    # ④ 중간 수동 실행·확인 요청 — 3요소 결합(어순 ⓐ→ⓑ→ⓒ 고정, 각 25자 이내).
    #   ⓐ 위임 부사 → ⓑ 실행·확인 동사 → ⓒ 요청 어미. 2요소(ⓑ+ⓒ)만으로 잡으면
    #   "설치 후 동작을 확인해 주세요" 같은 **정상 보고가 전부 차단 후보**가 된다 —
    #   대장 73번이 "물음표가 든 문장을 차단하면 정상적인 확인 요청까지 막는다"로 경고한 지점.
    #   ⓒ에서 '주세요'·'주시'·'부탁' 단독을 뺀 이유도 같다 — 그 어미는 안내문에 워낙 흔해
    #   "설치 후 동작을 직접 확인해 주세요"까지 걸렸다(리뷰 재현 반례). **사용자에게 행위를
    #   넘기며 되묻는 형태**(보시겠·주시겠·보시는 게)로 좁힌다.
    #   미탐(2인칭 지칭형·어순 역전·평서형 요청)은 의도적으로 수용한다 — 1차 방어선은 문서
    #   규칙이고, 오차단은 즉시 피해인 반면 미탐은 규칙이 받는다.
    $rxManualAsk = '(직접|한번|한 번|여기서|대신)[^\r\n]{0,25}(실행|테스트|확인|돌려|띄워|구동)[^\r\n]{0,25}(보시겠|보실래|보시는\s*게|해\s*보세요|주시겠|주시면\s*좋)'

    # ⑤ 순수 진행 요약으로 turn 종료 — task 번호 + 완료 어휘 근접(어순 ⓐ→ⓑ 고정, 25자 이내).
    #   ②③④와 달리 **정상 진행 보고와 문면이 같다** — 차이는 "그 뒤에 도구 호출이 있었나"뿐인데,
    #   Stop hook이 도는 시점에는 그 부재가 이미 확정이라 문면만으로 판정해도 된다.
    #   `(?-i)`와 `\b`는 **필수다**: `-match`는 기본 case-insensitive라 이 둘이 없으면
    #   `part1`·`test2`·`GPT5`·`checkpoint1`이 전부 T<N>으로 인정된다(실측). 이 레포는 분할 plan
    #   `-part1/-part2`·`test*` 픽스처를 일상적으로 언급하므로 그대로 두면 정상 보고가 차단된다.
    #   **군더더기로 보고 지우지 말 것.**
    #   `.。!?…;` 배제는 근접 구간이 문장을 넘지 않게 한다 — 없으면 "T3은 아직 진행 중입니다!
    #   나머지는 다 끝났습니다"(T3는 미완료)까지 걸린다.
    #   의도적 미탐: task 번호 없는 완료 보고("구현을 마쳤습니다")·소문자 `t3`.
    #   문서 규칙(SKILL.md ⑤ 절)이 받는다 — 오차단이 즉시 피해인 반면 미탐은 규칙이 받는다.
    #   **범위 표기는 구분자와 무관하게 잡힌다**(`T1~T3`·`T1-T3` 모두 매치 — 실측): 앞 토큰
    #   `T1`만으로 `\bT\d+`가 성립하고 나머지는 근접 구간에 흡수되기 때문이다. `(~\s*T\d+)?`
    #   그룹은 물결표 범위를 근접 25자 예산에서 빼주는 역할일 뿐 매치 여부를 가르지 않는다.
    $rxProgressOnly = '(?-i)\bT\d+\s*(~\s*T\d+)?[^\r\n.。!?…;]{0,25}(완료|마쳤|마무리했|끝냈|끝났)'

    # ⑤ 전용 억제 — 마지막 사용자 발화가 질문·조회 요청이면 그 답변을 정지로 보지 않는다.
    #   6조건은 "지금 루프가 도는가"가 아니라 세션에 발동 흔적이 있는지만 보므로, 루프가 끝난 뒤의
    #   일반 대화도 판정 대상이 된다. ⑤ 문면("T<N> … 완료")은 이 레포의 표준 진행 어휘라
    #   ②③④보다 그 표면에 훨씬 자주 노출된다.
    $rxUserAsk = '\?|알려\s*(줘|주|달라)|보여\s*(줘|주)|설명|어디|어떻게|무엇|뭐(야|지|니|해)|왜|맞(나|아|지)|인가|일까|될까|됐(나|어|니)'

    # 정당 정지 신호 2층 (v1.149.0) — 기존 $rxLegit을 강도로 쪼갠 것이며 **합집합은 동일**하다.
    #   Strong: 루프가 정상 도달한 종착점·규칙이 명시한 개입 지점의 헤더 마커. 전 유형에 통과.
    #   Weak  : "질문했다"는 사실만 알려주는 표지. ②에만 통과 근거이고 ③④에는 인정하지 않는다 —
    #           ③④는 **질문 형태를 띠는 것이 곧 위반**이라 Weak를 인정하면 검사가 성립하지 않는다
    #           (물음표 하나로 영구 fail-open 되던 것이 이 확대 이전의 상태다).
    #   Weak를 버리는 대신 정당 개입 지점에는 Strong 마커를 문면으로 부여했다(SKILL.md 마커 규약)
    #   — Phase 0 사전 승인 확인·외부 작업 승인·리뷰 인프라 선택·plan-feature 세션 확인 등.
    #   ⏸는 **VS16(U+FE0F)을 선택적으로** 잡는다 — 파일에 `⏸️`로 쓰면 U+23F8+U+FE0F 2문자
    #   시퀀스가 되어, 모델이 VS16 없이 `⏸`만 출력하면 미매치다(실측). ⛔·🎉는 단일 코드포인트라
    #   이 문제가 없고 ⏸만 구조적으로 좁다. Weak를 ③④에서 없앤 뒤로는 **마커가 유일한 방어**라,
    #   한 코드포인트 차이로 Phase 0 승인 게이트가 차단될 수 있다(F-7 M1).
    $rxLegitStrong = '⛔|🎉|⏸️?|중단 보고|Halt'
    $rxLegitWeak = '\?|승인|확인 요청|확인 부탁|선택해'

    # 정지 유형 판정 — 매치되는 첫 유형의 이름을 반환하고, 없으면 빈 문자열(fail-open).
    #   **조기 반환 금지**: ②의 어휘가 매치됐더라도 Weak 때문에 ② 판정이 거짓이면 ③→④를
    #   반드시 이어서 평가한다. 안 그러면 "컨텍스트가 찼습니다. 새 세션으로 옮길까요?
    #   이어서 진행하겠습니다" 처럼 ②어휘+③어휘+물음표가 섞인 문장이 ②에서 통과 판정을 받고
    #   ③ 검사에 닿지 못해, 이 확대가 막으려던 바로 그 정지가 다시 새어 나간다.
    function Test-StopPhrase {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
        $strong = ($Text -match $script:rxLegitStrong)
        if ($strong) { return '' }
        if ($Text -match $script:rxAdvance -and $Text -notmatch $script:rxLegitWeak) { return 'advance' }
        if ($Text -match $script:rxHandoff) { return 'handoff' }
        if ($Text -match $script:rxManualAsk) { return 'manual' }
        # ⑤도 Weak를 보지 않는다 — 평서형이라 물음표·"확인 요청"이 정당성의 근거가 될 이유가 없고,
        #   인정하면 "T3 완료. 계속할까요?"(금지 표현 ①에도 해당)가 통과한다.
        if ($Text -match $script:rxProgressOnly) { return 'progress' }
        return ''
    }

    # 조건 ④ 1차 — stdin의 last_assistant_message가 오면 그것으로 즉시 판정한다(문자열 매칭만,
    #   파일 I/O 0). 거짓이면 아래 transcript 읽기를 통째로 건너뛴다.
    # ⚠ 이 필드의 실환경 제공 여부는 미실증이다(공식 문서 기준으로는 존재). **없어도 검사가 죽지
    #   않도록** 아래에 transcript 폴백을 둔다 — 이 신호 하나에 기대면 필드가 안 올 때 검사 4가
    #   프로덕션에서 영구 무발화하는데, 골든은 필드를 직접 주입하므로 green이라 발견되지 않는다.
    $lastMsgL = if ($data) { [string]$data.last_assistant_message } else { '' }
    $haveStdinMsg = -not [string]::IsNullOrWhiteSpace($lastMsgL)
    $stopKind = ''
    if ($haveStdinMsg) { $stopKind = (Test-StopPhrase $lastMsgL) }

    # 조건 ③⑤(+ 필요 시 ④ 폴백): transcript를 한 번만 tail해서 함께 처리한다.
    #   stdin 필드가 왔는데 ④가 거짓이면 여기 진입하지 않는다(불필요한 I/O 제거).
    $loopSkill = $false
    $userStop = $false
    $userFound = $false
    $userAsking = $false            # ⑤ 억제 — 마지막 사용자 발화가 질문·조회 요청인가
    $loopActiveAfterUser = $false    # ⑤ 억제의 활성 게이트 — 마지막 사용자 발화 이후 루프가 (재)발동됐는가
    if ($loopOpen -and ($stopKind -or -not $haveStdinMsg)) {
        $tpL = if ($data) { [string]$data.transcript_path } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($tpL) -and (Test-Path -LiteralPath $tpL -PathType Leaf)) {
            try {
                # 조건 ③은 **전 파일**을 스캔한다 — tail로 자르면 긴 자율 루프에서 발동 흔적(세션
                #   앞부분에 있다)이 잘려 조건이 거짓이 되는데, **하필 그 긴 루프가 이 검사가 필요한
                #   바로 그 상황**이다(실측: 이 repo transcript 최대 2817줄 = 상한 3000의 94%).
                #   -Quiet는 첫 매치에서 멈추므로 전량 로드가 아니다
                #   (require-plan-for-write.ps1:79-81의 발동 흔적 판정과 같은 관례).
                $loopSkill = [bool](Select-String -LiteralPath $tpL -Quiet -Pattern @(
                        '"skill"\s*:\s*"pjc:implement-task"',
                        'Launching skill: pjc:implement-task'))
                # 조건 ⑤·④폴백은 '직전' 발화를 찾는 것이라 tail이 맞다(전 파일 역순 파싱은 비용이 크다).
                $tailL = @(Get-Content -LiteralPath $tpL -Tail 3000 -ErrorAction Stop)

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
                    # ⑤ 억제의 활성 게이트 — 역순 스캔이라 user를 만나기 전 구간이 곧 '마지막 user 이후'다.
                    #   여기서 발동 엔트리를 보면 루프가 지금 도는 중이므로 아래 $userAsking 억제를 적용하지 않는다.
                    #   **이 게이트가 없으면 ⑤가 표준 진입 경로에서 영구 무발화한다**: tool_result는 user에서
                    #   제외되므로(바로 아래 줄) 루프 중 '마지막 user 텍스트'는 루프 시작 지시로 고정되고,
                    #   그 지시에 질문 어휘가 섞여 있으면("왜 멈췄어 계속해") 억제가 루프 전 구간 상수 참이 된다.
                    #   **`$isAsst` 한정이 핵심** — 전 줄을 보면 이 레포 개발 세션에서 골든 파일을 읽은
                    #   tool_result(발동 패턴 리터럴을 담는다)가 게이트를 켜서 억제가 꺼진다(오차단 방향).
                    #   반대로 tool_result 안의 'Launching skill:' 형태를 놓치는 쪽은 억제 과다 = 미탐 방향이라
                    #   이 hook의 fail-open 원칙과 맞다. JSON 파싱 전 원시 문자열 검사라 추가 I/O가 없다.
                    if ($isAsst -and -not $userFound -and
                        ($ln -match '"skill"\s*:\s*"pjc:implement-task"' -or $ln -match 'Launching skill: pjc:implement-task')) {
                        $loopActiveAfterUser = $true
                    }
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
                        #   세션 전환 어휘(v1.149.0): **사용자가 먼저** 새 세션·/clear를 꺼낸 대화에서
                        #   그 응답을 ③으로 차단하면, 이 검사에서 가장 위험한 오작동인 "사용자 의사
                        #   무시"가 된다. 유형 구분 없는 공통 조건이라 ②에도 함께 적용되는데, 그것도
                        #   의도다 — fail-open 방향이고, 사용자가 전환을 꺼낸 대화에서 ②를 막는 것
                        #   역시 같은 종류의 의사 무시다.
                        #   지연·종료 표현(내일·이만·다음에·쉬자)도 함께 잡는다 — ③ 확대 이후
                        #   "내일 하자" 뒤의 정상 안내("남은 T4~T6은 새 세션에서 이어가시면 재개됩니다")가
                        #   차단되는 것이 실측으로 재현됐다(F-7 M2). 차단 reason이 "사용자 보고 없이
                        #   계속하라"라서, **사용자가 중단시킨 작업을 재개하도록 밀어붙이는** 최악의
                        #   오작동이 된다. 이 조건은 fail-open 방향이라 넓히는 쪽이 안전하다.
                        if ($txt -match '그만|중단|멈춰|멈춤|여기까지|이제 ?됐|나중에|\bstop\b|T\d+\s*만|새\s*세션|/clear|세션[^\r\n]{0,4}(옮|바꾸|나눠|분리)|내일|이만|다음\s*에|쉬(자|죠|겠)') { $userStop = $true }
                        # ⑤ 전용 억제 신호(위 $userStop과 독립 — 둘 다 억제 방향이지만 묻는 것이 다르다:
                        #   저쪽은 "사용자가 멈추라고 했나", 이쪽은 "사용자가 물어봤나").
                        if ($txt -match $script:rxUserAsk) { $userAsking = $true }
                    } elseif ($isAsst -and $needAsst) {
                        # 조건 ④ 폴백 — stdin 필드가 없을 때만. 마지막 assistant 텍스트로 정지 유형을 판정한다.
                        $needAsst = $false
                        $stopKind = (Test-StopPhrase $txt)
                    }
                }
            } catch { $loopSkill = $false }   # 읽기 실패 → fail-open
        }
    }

    # ⑤ 억제 적용 — 루프가 도는 중이 아닌데(게이트 꺼짐) 사용자가 방금 질문했다면, 그 답변이
    #   "T<N> … 완료" 형태여도 정지가 아니라 대화다. ⑤에만 적용해 ②③④의 판정은 그대로 둔다.
    if (-not $loopActiveAfterUser -and $userAsking -and $stopKind -eq 'progress') { $stopKind = '' }

    if ($loopOpen -and $loopSkill -and $stopKind -and $userFound -and (-not $userStop)) {

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

                # reason은 유형별로 다르다 — ②의 문구를 ③④에 그대로 쓰면 모델이 무엇을 어겼는지
                #   오인해 엉뚱하게 교정한다(예고를 지우고 다시 세션 전환을 제안하는 식).
                $reasonHead = '[pjc] 자율 루프가 미완료 상태로 종료하려 합니다. plan에 미완료 task가 남아 있고(완료 커밋 없음), '
                $reasonTail = ' 정말 멈춰야 하는 상황이면 Halt 보고 형식(## 작업 중단)으로 사유를 적으십시오.'
                switch ($stopKind) {
                    'handoff' {
                        $reasonBody = '마지막 응답이 세션 전환·컨텍스트 우려 제안으로 끝났습니다 - implement-task 금지 표현 3에 해당합니다. 컨텍스트 한계는 Halt 사유가 아닙니다. 지금 할 일은 압축 통과입니다(컨텍스트 관리 규칙 4): 현재 task를 Phase V/D까지 끝내고 plan.md에 Progress Log/Next Steps/다음 task 시작점을 기록한 뒤, 사용자 보고 없이 같은 turn의 다음 도구 호출로 계속하십시오. 새 세션 권유는 루프 시작 전에만, 그것도 답을 기다리지 않는 공시로 합니다.'
                    }
                    'manual' {
                        $reasonBody = '마지막 응답이 사용자에게 실행·확인을 요청하며 끝났습니다 - implement-task 금지 표현 4에 해당합니다. 기계 검증(빌드/테스트/정적 검사)으로 확인되는 것은 직접 실행하십시오. 기계로 확인할 수 없는 것(화면 표시/조작감 등)은 멈추지 말고 plan에 HUMAN-VERIFY로 표기해 최종 보고로 넘기고 다음 단계를 계속하십시오.'
                    }
                    'progress' {
                        $reasonBody = '마지막 응답이 진행 상황 요약으로 끝났습니다 - implement-task 금지 표현 5에 해당합니다. 완료 사실만 서술해 규칙을 어긴 흔적이 없어 보이지만, 도구 호출 없이 텍스트만 내면 turn이 끝나 결과는 같은 루프 정지입니다. 한 줄 진행 마커는 같은 turn의 다음 도구 호출과 한 묶음일 때만 씁니다. 지금 다음 단계를 도구 호출로 시작하고, 남길 진행 상세는 대화가 아니라 plan.md의 Progress Log에 쓰십시오.'
                    }
                    default {
                        $reasonBody = '마지막 응답이 진행 예고로 끝났습니다 - implement-task 금지 표현 2(예고를 마지막 말로 남기고 turn을 끝내지 말 것)에 해당합니다. 지금 다음 task의 Phase P를 시작하세요(Read/grep 등 도구 호출로 이어갈 것). 상태 기록이 필요하면 대화에 요약을 출력하지 말고 plan.md에 쓰십시오.'
                    }
                }
                $reasonText = $reasonHead + $reasonBody + $reasonTail
                [Console]::Out.WriteLine((@{ decision = 'block'; reason = $reasonText } | ConvertTo-Json -Compress))
                exit 0
            }
        }
    }
}

exit 0
