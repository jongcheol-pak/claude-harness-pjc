# session-context.ps1 — SessionStart: 로컬 plan 상태 요약 + AGENTS.md 전문 컨텍스트 주입 (비차단)
#
# 왜: ① 글로벌 CLAUDE.md의 "작업 시작 전 plan.md 확인" 규칙이 전적으로
#   모델 자율에 맡겨져 있어 긴 세션·새 세션에서 누락되기 쉽다 — 세션 시작 시점에 기계가
#   상태 요약 1~3줄을 주입해 규칙을 구조화한다(v1.112.0).
#   ② 컨텍스트 요약(auto-compact) 직후는 자율 루프(implement-task)의 절차 규칙·plan 상태가
#   요약으로 희석되는 최위험 지점 — source=compact일 때 재확인 리마인더를 추가 주입한다.
#   여기에 더해 **미완료 task가 있는 plan을 찾은 경우에만** 재읽기 대상 경로를 못박는다:
#   스킬은 압축 후 앞 5,000토큰만 재부착되고 동일 스킬 재invoke는 "이미 로드됨"만 반환해
#   복구되지 않으므로, "재확인하라"는 지시만으로는 무엇을 읽을지가 비어 있다.
# 어떻게: stdin(SessionStart JSON)의 cwd에서 plan(루트 plan.md 우선, 없으면 docs/plans/ 최신
#   수정 5개 중 task 체크박스가 있는 파일 — 글로벌 CLAUDE.md의 확인 순서와 동일)을 찾아
#   미완료 task 수를 stdout으로 출력한다(SessionStart 규약: stdout=컨텍스트
#   주입, exit 0). 추가로 프로젝트 루트 AGENTS.md가 있으면 전문(16KB 초과 시 목차+Read 지시)을
#   함께 주입한다 — AGENTS.md는 에이전트용 가이드라 plan이 없어도 존재하면 주입한다.
#   plan·AGENTS.md가 모두 없으면 무출력(비 pjc 프로젝트 노이즈 방지) — 단 compact
#   리마인더는 유무와 무관하게 출력한다(요약 직후엔 plan 없어도 스킬 규약 재확인 가치).
# 안전: 정보 주입 hook(차단·경고 아님 — hook-event-log 적재 대상 아님). 모든 실패 경로는
#   조용히 exit 0 (fail-open — 세션 시작을 절대 막지 않는다). warn-version-drift와 동일 골격.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
# stdin도 UTF-8로 디코딩 (v1.129.0) — Claude Code는 UTF-8 바이트로 보내는데 콘솔 기본 코드페이지(cp949)로
#   읽으면 한글 경로가 깨져 plan 탐색이 어긋난다. 실패해도 종전 동작 유지.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# [고아 프로세스 회수] 세션 시작 시점에 이전 세션이 남긴(부모가 죽은) more.com·find.exe를 걷는다 —
#   판정·출력에 영향 0. 이 경로가 백스톱인 이유: SessionEnd는 크래시·강제 종료 시 발화가 보장되지 않는다.
#   $ErrorActionPreference 설정 뒤에 두는 이유: 회수 경로의 비종결 오류가 stderr로 새면 이 hook의
#   출력 계약이 깨진다(헬퍼도 자기완결적으로 막지만 삽입 위치로 한 겹 더 막는다).
try { . (Join-Path $PSScriptRoot 'orphan-process-cleanup.ps1'); $null = Invoke-OrphanProcessCleanup -Hook 'session-context' } catch {}

try {
    # ---- 입력 파싱 (cwd·source) ----
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $inp = $null
    try { $inp = $raw | ConvertFrom-Json } catch { exit 0 }
    $cwd = [string]$inp.cwd
    $source = [string]$inp.source   # startup|resume|clear|compact|fork (부재 시 빈 문자열 → 비compact 취급. fork는 compact가 아니라 startup과 같은 경로를 탄다)

    $lines = New-Object System.Collections.Generic.List[string]

    # ---- compact 리마인더 (plan 유무 무관) ----
    if ($source -eq 'compact') {
        $lines.Add("[pjc 세션 컨텍스트] 컨텍스트 요약 직후입니다 — 진행 중이던 작업이 있으면 plan.md의 현재 task와 활성 스킬(implement-task 등)의 Halt 조건·승인 게이트·커밋 프로토콜을 요약 기억에 의존하지 말고 SKILL 문서·plan.md 원문에서 재확인하세요.")
    }

    if (-not [string]::IsNullOrWhiteSpace($cwd) -and (Test-Path -LiteralPath $cwd -PathType Container)) {
        # cwd 수집으로 라인이 늘었는지 판정하는 기준 개수 — vault 라인 게이팅에 쓴다.
        #   compact 리마인더는 이 블록 밖에서 append되므로, 이 기준과 비교하면 리마인더가
        #   자연히 게이팅 신호에서 제외된다($lines.Count -gt 0으로 판정하면 비 pjc 프로젝트의
        #   요약 직후 세션에도 vault 라인이 붙는다).
        $cwdBaseCount = $lines.Count

        # ---- plan 탐색: 루트 plan.md 우선 → docs/plans/ 폴백 ----
        # docs/plans/에는 plan이 아닌 파일(deferred.md 등)도 있으므로 task 체크박스(- [ ] T<N>)가
        # 있는 파일만 plan으로 인정한다. 최신 수정 5개만 검사(세션 시작 지연 상한).
        $rootPlan = Join-Path $cwd 'plan.md'
        $planPath = $null
        $planLabel = $null
        if (Test-Path -LiteralPath $rootPlan -PathType Leaf) {
            $planPath = $rootPlan
            $planLabel = 'plan.md'
        } else {
            $plansDir = Join-Path $cwd 'docs/plans'
            if (Test-Path -LiteralPath $plansDir -PathType Container) {
                $cand = @(Get-ChildItem -LiteralPath $plansDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 5)
                foreach ($f in $cand) {
                    $t = $null
                    try { $t = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 } catch {}
                    if ($t -and $t -match '(?m)^- \[[ /x]\] T\d+') {
                        $planPath = $f.FullName
                        $planLabel = 'docs/plans/' + $f.Name
                        break
                    }
                }
            }
        }

        if ($planPath) {
            $planText = $null
            try { $planText = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 } catch {}
            if ($planText) {
                # task 라인만 카운트 (pjc plan 규약: "- [x] T1: ..." — 통과 체크리스트 등 다른 체크박스 제외)
                $all = [regex]::Matches($planText, '(?m)^- \[[ /x]\] T\d+').Count
                $open = [regex]::Matches($planText, '(?m)^- \[[ /]\] T\d+').Count
                if ($all -gt 0) {
                    if ($open -gt 0) {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 중 미완료 ${open}개 — 작업 시작 전 plan.md 진행 상태를 확인하세요.")
                        # 압축 직후 + 미완료 task = 자율 루프가 규칙을 잃은 채 재개될 최위험 조합.
                        #   스킬은 auto-compact 후 앞 5,000토큰만 재부착되므로 뒷부분(Phase 절차·Halt
                        #   조건·재시도 카운터)이 통째로 빠지는데, 동일 스킬 재invoke는 "이미 로드됨"만
                        #   반환해 복구되지 않는다 — Read만 유효하다. 그래서 위 일반 리마인더(재확인하라)에
                        #   더해 "무엇을" 읽을지를 기계가 못박는다.
                        # Phase 판정은 하지 않는다: hook이 plan 형식에 의존하게 되고 형식이 바뀌면 조용히
                        #   깨진다. 대신 Phase와 무관하게 늘 필요한 루프 제어 3종만 고정 지정하고,
                        #   Phase 특화 reference는 스킬 본문의 지시에 맡긴다.
                        if ($source -eq 'compact') {
                            $lines.Add("[pjc 세션 컨텍스트] 진행 중 plan이 있습니다 — 스킬 재invoke로는 복구되지 않으니 다음을 Read로 재확인하세요: implement-task/SKILL.md · implement-task/references/halt-conditions.md · implement-task/references/recovery.md. 진행 중인 Phase가 참조하는 reference 파일도 함께 읽으세요.")
                        }
                    } else {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 전부 완료 — 새 작업이면 plan 교체 전 Deferred/Follow-up 잔여 항목을 확인하세요.")
                    }
                } else {
                    # task 체크박스가 없는 plan.md(비 pjc 형식) — 카운트 오보 대신 존재만 알림
                    $lines.Add("[pjc 세션 컨텍스트] ${planLabel} 존재 — 작업 시작 전 진행 상태를 확인하세요.")
                }
            }
        }

        # ---- 계획 세션의 압축 리마인더 (plan이 없거나 task 0개) ----
        # 위 블록은 `if ($planPath)` 안이라 **진행 중 plan이 있는 세션**만 닿는다. 계획을 세우던 중
        #   압축되면 plan이 아직 없거나 task 체크박스가 0개라 그 지시를 못 받는데, `plan-feature`도
        #   본체가 앞 5,000토큰 밖으로 밀리는 것은 같다(경계 83행 / 전체 521행) — Step 4 영향 범위,
        #   Step 5 작업 분해, Step 9 리뷰 게이트가 통째로 요약에 뭉개진 채 계획이 이어진다.
        # 스킬 판정은 하지 않는다: 어느 스킬이 활성인지 알 방법이 없고 추측하면 틀린 파일을 지목한다.
        #   plan 상태로만 분기하는 것은 위 블록과 같은 축이다.
        # ⚠ plan도 AGENTS.md도 없는 **비 pjc 프로젝트에는 붙이지 않는다** — 위 `:16` 주석의 무출력
        #   규칙과 같은 취지다. 이 리마인더는 「계획을 세우던 중이었다면」이라 대상이 pjc 워크플로인데,
        #   무관한 폴더의 압축 세션에까지 뜨면 그냥 노이즈다(AGENTS.md 경로는 아래에서 다시 쓰지만
        #   여기서는 존재 판정만 필요해 직접 Test-Path 한다).
        if ($source -eq 'compact' -and (-not $planPath -or $all -eq 0) -and ($planPath -or (Test-Path -LiteralPath (Join-Path $cwd 'AGENTS.md')))) {
            $lines.Add("[pjc 세션 컨텍스트] 계획을 세우던 중이었다면 — plan-feature/SKILL.md를 Read로 재확인하세요(스킬 재invoke로는 복구되지 않습니다). 영향 범위 조사·작업 분해·리뷰 게이트가 앞 5,000토큰 밖이라 요약으로 뭉개집니다.")
            # 이 줄은 compact 리마인더라 **vault 게이팅 신호가 아니다** — 기존 리마인더(위 source 판정
            #   블록)가 $cwdBaseCount 산정 *이전*에 추가돼 자연히 제외되는 것과 같은 취지다. 여기는
            #   산정 이후라 기준선을 함께 올려야 한다. 안 올리면 plan도 AGENTS.md도 없는 프로젝트의
            #   압축 세션에 vault 라인이 붙는다(골든 SC23이 그 회귀를 잡는다).
            # ⚠ `= $lines.Count`가 아니라 `++`다 — 전체 재설정은 **이 줄 앞에 이미 쌓인 정당한 신호까지**
            #   기준선에 흡수한다. plan.md가 있는데 task 체크박스가 없는 세션에서는 위 「존재」 라인이
            #   먼저 들어가는데 그것은 실제 plan이 있다는 신호라 vault 라인이 붙어야 한다. 전체 재설정하면
            #   그 세션만 compact에서 vault가 조용히 빠진다(startup에서는 붙는데 — 소스별 비일관).
            $cwdBaseCount++
        }

        # ---- 위키 vault 설정 상태 판정 (라인 생성만 — 주입은 아래 수집 종료 후) ----
        # 왜 ①(원래 목적): 절차 K(코드 작업 전 위키 read-only 참조)는 "vault 미설정이면 조용히 통과"인데,
        #   확인 없이 미설정으로 단정해 **설정·실재하는 위키를 통째로 건너뛴** 사고가 있었다
        #   (2026-07-30). 기계가 상태를 1줄 주입하면 그 추측 여지 자체가 사라진다 —
        #   AGENTS.md 전문 주입(아래)과 같은 구조의 해법이다.
        # 왜 ②(v1.197.0 추가): 절차 K는 **스킬이 호출할 때만** 돈다(plan-feature Step 1·implement-task
        #   재개 진입·pjc-systematic-debugging 2-A). 그래서 **스킬을 발동하지 않는 세션**(trivial 수정·
        #   질문)은 프로젝트 맥락을 위키가 아니라 코드에서 다시 캐게 된다 — 허브 1개(실측 9,928자)면
        #   될 것을. 라인이 "참조 가능"(권유)이 아니라 **어디를 읽을지**를 말하게 해 그 경로를 메운다.
        # 판정 규칙(인덱스 경유 불필요·synced_commit 낡음·코드 세부는 코드가 정본)은 **여기 복제하지
        #   않는다** — 정본은 글로벌 지침의 「프로젝트 맥락은 위키를 먼저 본다」이고 그것은 매 세션
        #   상시 로드되므로, 같은 문면을 다시 실으면 예산만 늘고 두 자리가 갈린다(위키 decisions.md
        #   2026-08-15 「중복 문구 추가 기각」과 같은 판단). 이 라인이 남기는 값은 글로벌 절이 줄 수
        #   없는 둘 — 기계가 확인한 실제 경로와, 그 경로 옆이라는 위치다.
        # 허브 **본문**은 주입하지 않는다(대장 [2026-07-09] 잔존분) — 컨텍스트 비용이 크고 절차 K와
        #   역할이 겹친다. 지시만 주고 읽기는 세션이 판단한다.
        # 미설정(config 파일 없음)은 주입하지 않는다: 위키를 쓰지 않는 사용자에게 매 세션
        #   노이즈가 되고 절차 K의 "없으면 조용히 통과" 원칙과도 맞다. 그 대가로 "라인 부재"가
        #   다의적(미설정/게이팅/hook 미설치)이 되므로, 절차 K 1이 "부재는 판정 근거가 아니다"로
        #   받아 직접 확인하게 한다(문서와 hook이 한 쌍).
        # USERPROFILE만 본다($HOME 폴백 없음) — 골든이 이 변수로 홈을 격리하므로 폴백을 두면
        #   격리가 새고 실 사용자 홈을 읽을 수 있다.
        $vaultLine = $null
        $feedbackLine = $null              # 스킬 개선 큐 잔량 (하네스 레포 세션에서만 — 아래)
        $staleLine = $null                 # 위키 뒤처짐 (프로젝트를 가리지 않는다 — 아래)
        $vaultInsertAt = $lines.Count      # AGENTS 라인보다 앞 위치를 미리 기록(전문이 길어 뒤에 붙으면 묻힌다)
        $userHome = [string]$env:USERPROFILE
        if (-not [string]::IsNullOrWhiteSpace($userHome)) {
            $vaultCfg = Join-Path $userHome '.claude/llm-wiki-config.json'
            if (Test-Path -LiteralPath $vaultCfg -PathType Leaf) {
                $vaultPath = $null
                # 손상 JSON·BOM·권한 오류는 조용히 통과(fail-open) — 세션 시작을 막지 않는다
                try { $vaultPath = [string]((Get-Content -LiteralPath $vaultCfg -Raw -Encoding UTF8 | ConvertFrom-Json).vault_path) } catch {}
                if (-not [string]::IsNullOrWhiteSpace($vaultPath)) {
                    if (Test-Path -LiteralPath $vaultPath -PathType Container) {
                        $vaultLine = "[pjc 세션 컨텍스트] 위키 vault: 설정됨 ($vaultPath) — 프로젝트 맥락이 필요하면 AGENTS.md의 '## 위키'가 지목한 허브를 먼저 Read하세요(판정 단서는 글로벌 지침 「프로젝트 맥락은 위키를 먼저 본다」). 절차 K 참조 가능. `"미설정`"으로 단정하지 마세요."

                        # ---- 스킬 개선 큐 잔량 (하네스 레포 세션에서만) ----
                        # 왜: [SKILL-IMPROVE] 큐는 유입만 자동이고 착수 지점이 없어 12건이 최장 22일
                        #   방치됐다. plan-feature Step 1이 계획할 때 조회하지만 **계획을 열지 않는
                        #   세션에서는 잔량이 보이지 않는다** — 이 1줄이 하네스 세션마다 그 사각을 메운다.
                        #   특히 체류(최고령)를 함께 내는 이유는 실제 증상이 잔량이 아니라 체류이기
                        #   때문이다(1건이어도 반년을 묵으면 그것이 이 채널의 실패다).
                        # 하네스 레포 판정은 cwd 아래 plugin.json 존재이며 **상위 탐색을 하지 않는다**
                        #   — plan-feature Step 1과 같은 기준이어야 한다(갈리면 한쪽만 발화한다).
                        # 본문은 주입하지 않는다(건수·최고령만) — 컨텍스트 예산 보호.
                        # 전 구간 try/catch로 감싼다: 큐 읽기 실패가 세션 시작을 막지 않게(fail-open).
                        try {
                            $pluginJson = Join-Path $cwd 'plugins/pjc/.claude-plugin/plugin.json'
                            if (Test-Path -LiteralPath $pluginJson -PathType Leaf) {
                                $fbPath = Join-Path $vaultPath 'skill-feedback.md'
                                if (Test-Path -LiteralPath $fbPath -PathType Leaf) {
                                    $fbDates = @()
                                    foreach ($fbLine in (Get-Content -LiteralPath $fbPath -Encoding UTF8)) {
                                        $fbMatch = [regex]::Match($fbLine, '^\s*-\s*\[(\d{4}-\d{2}-\d{2})\]\s*\[SKILL-IMPROVE\]')
                                        if ($fbMatch.Success) { $fbDates += $fbMatch.Groups[1].Value }
                                    }
                                    if ($fbDates.Count -gt 0) {
                                        # @() 로 감싸는 것이 요점이다 — 항목이 **1건이면** 파이프 결과가
                                        #   배열이 아니라 스칼라 문자열이라 [0] 이 「첫 글자」('2')를 준다.
                                        #   그러면 아래 ParseExact 가 터지고 바깥 catch 가 삼켜 큐 라인이
                                        #   조용히 사라진다(2건 이상일 때만 동작해 오래 드러나지 않았다).
                                        $fbOldest = @($fbDates | Sort-Object)[0]
                                        $fbAge = [int]([math]::Floor(((Get-Date).Date - [datetime]::ParseExact($fbOldest, 'yyyy-MM-dd', $null)).TotalDays))
                                        $feedbackLine = "[pjc 세션 컨텍스트] 스킬 개선 큐(skill-feedback.md): 대기 $($fbDates.Count)건 / 최고령 ${fbAge}일 — plan-feature Step 1이 할 일 후보로 조회합니다."
                                    }
                                }
                            }
                        } catch {}

                        # ---- 위키 뒤처짐 알림 (프로젝트를 가리지 않는다) ----
                        # 왜: 위키가 밀렸다는 신호(`[K-DRIFT]` 큐·lint INFO)는 **위키 세션에서만** 보여,
                        #   정작 그 프로젝트에서 작업하는 세션에는 닿지 않는다 — 알림이 받아야 할 사람에게
                        #   가지 않는 순환이다(실측: MOA 181커밋·Maid 104커밋이 그렇게 방치됐다).
                        #   절차 K 3도 같은 값을 재지만 **스킬이 발동한 세션에서만**이고, 그 결과는 내부
                        #   판정(서술을 낡은 것으로 취급)에만 쓰여 사용자 화면에는 뜨지 않는다.
                        # 허브는 **vault 쪽에서 역방향으로** 찾는다 — AGENTS.md의 '## 위키' 절을 읽는 설계면
                        #   그 절이 없는 프로젝트가 통째로 빠지는데, 실측상 가장 뒤처진 MOA가 그 경우다.
                        # cwd 매칭은 **동일 경로만** 본다(상위 탐색 없음) — 하네스 판정과 같은 기준이다.
                        #   prefix로 넓히면 참고용 clone·하위 워크트리가 남의 허브에 붙는다.
                        # 발화는 OR 3축(커밋 30 · 경과일 14 · K-DRIFT 1건). 뒤처짐 축이 둘 다 미달이면
                        #   그 수치를 빼고 잔량만 싣는다 — "0커밋 미반영"은 사실이 아니라 잡음이다.
                        # 전 구간 try/catch fail-open: 허브 무매치·synced_commit 부재·git 부재·파싱 실패는
                        #   조용히 통과한다(이 파일의 다른 경로와 같은 원칙 — 세션 시작을 막지 않는다).
                        try {
                            $hubDir = Join-Path $vaultPath '20_projects'
                            if (Test-Path -LiteralPath $hubDir -PathType Container) {
                                $cwdNorm = ($cwd -replace '\\', '/').TrimEnd('/')
                                # Depth 1 = `20_projects/<카테고리>/<프로젝트>.md` 까지. 그 아래 feature 파일
                                #   (`.../<프로젝트>/feat-*.md`)은 허브가 아니라 대상에서 자연히 빠진다.
                                foreach ($hubFile in (Get-ChildItem -LiteralPath $hubDir -Filter '*.md' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue)) {
                                    $hubText = $null
                                    try { $hubText = Get-Content -LiteralPath $hubFile.FullName -Raw -Encoding UTF8 } catch { continue }
                                    if (-not $hubText) { continue }
                                    $pathMatch = [regex]::Match($hubText, '(?m)^- \*\*경로\*\*:\s*`([^`]+)`')
                                    if (-not $pathMatch.Success) { continue }
                                    if ((($pathMatch.Groups[1].Value -replace '\\', '/').TrimEnd('/')) -ine $cwdNorm) { continue }

                                    # ---- 이 허브가 현재 레포다 ----
                                    $projName = ''
                                    $projMatch = [regex]::Match($hubText, '(?m)^project:\s*"?([^"\r\n]+?)"?\s*$')
                                    if ($projMatch.Success) { $projName = $projMatch.Groups[1].Value }

                                    # 축 1 — synced_commit 이후 커밋 수(read-only 조회).
                                    $behind = -1
                                    $syncedSha = ''
                                    $shaMatch = [regex]::Match($hubText, '(?m)^synced_commit:\s*(\S+)')
                                    if ($shaMatch.Success) {
                                        $syncedSha = $shaMatch.Groups[1].Value
                                        # $LASTEXITCODE 를 게이트로 쓰지 않는다 — 이 hook은 앞서 다른 외부
                                        #   프로세스를 부르므로(고아 회수) 그 값이 이 호출의 결과라는 보장이 없다.
                                        #   실패하면 git 은 숫자를 내지 않으므로 **출력 형태 자체가 판정**이다.
                                        # **이 호출만 따로 감싸는 이유**: git 이 PATH 에 없으면 `&` 호출이
                                        #   CommandNotFoundException(종료 오류)을 던지는데, 바깥 catch 로 흘리면
                                        #   경과일·K-DRIFT 축까지 통째로 죽는다. 커밋 축만 미발화되어야 한다
                                        #   (레포가 아니거나 sha 가 이력에 없는 경우는 git 이 정상 실행돼 비-숫자만
                                        #   내므로 예외가 아니고, 그래서 이 세 경우의 결과가 여기서 같아진다).
                                        try {
                                            $countRaw = (& git -C $cwd rev-list --count "$syncedSha..HEAD" 2>$null | Select-Object -First 1)
                                            if ("$countRaw" -match '^\d+$') { $behind = [int]$countRaw }
                                        } catch {}
                                    }

                                    # 축 2 — 허브 updated 로부터의 경과일.
                                    $staleDays = -1
                                    $updMatch = [regex]::Match($hubText, '(?m)^updated:\s*(\d{4}-\d{2}-\d{2})')
                                    if ($updMatch.Success) {
                                        try {
                                            $updDate = [datetime]::ParseExact($updMatch.Groups[1].Value, 'yyyy-MM-dd', $null)
                                            $staleDays = [int]([math]::Floor(((Get-Date).Date - $updDate).TotalDays))
                                        } catch {}
                                    }

                                    # 축 3 — 이 프로젝트의 [K-DRIFT] 잔량. **대소문자를 무시**한다
                                    #   (큐 라벨이 허브 project 값과 대소문자만 다를 수 있다).
                                    $driftCount = 0
                                    if ($projName) {
                                        $pendPath = Join-Path $vaultPath 'pending.md'
                                        if (Test-Path -LiteralPath $pendPath -PathType Leaf) {
                                            $driftRx = '^\s*-\s*\[\d{4}-\d{2}-\d{2}\]\s*\[K-DRIFT\]\s*' + [regex]::Escape($projName) + '\s*:'
                                            foreach ($pendLine in (Get-Content -LiteralPath $pendPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
                                                if ($pendLine -imatch $driftRx) { $driftCount++ }
                                            }
                                        }
                                    }

                                    # **계산된 축만 문구에 싣는다.** 미계산 sentinel(-1)을 그대로 쓰면
                                    #   "-1커밋 미반영"처럼 내부 값이 사용자에게 새어 나간다 — 한 축이
                                    #   실패해도(synced_commit 부재 · sha 가 이력에 없음) 다른 축은 발화하므로
                                    #   그 조합이 실제로 생긴다.
                                    $behindKnown = ($behind -ge 0)
                                    $daysKnown = ($staleDays -ge 0)
                                    $behindHit = ($behindKnown -and ($behind -ge 30)) -or ($daysKnown -and ($staleDays -ge 14))
                                    if ($behindHit -or ($driftCount -ge 1)) {
                                        $label = if ($projName) { $projName } else { $hubFile.BaseName }
                                        # 뒤처짐 축이 둘 다 미달이면 수치를 싣지 않는다 — 잔량만이 신호다.
                                        $head = if ($behindHit) {
                                            if ($behindKnown -and $daysKnown) { "$label 위키가 ${behind}커밋 미반영 (synced: $syncedSha, ${staleDays}일 경과)" }
                                            elseif ($behindKnown) { "$label 위키가 ${behind}커밋 미반영 (synced: $syncedSha)" }
                                            else { "$label 위키가 ${staleDays}일째 미반영" }
                                        } else { "$label 위키에 미반영 발견이 남아 있습니다" }
                                        $driftPart = if ($driftCount -ge 1) { " · 미반영 발견 ${driftCount}건([K-DRIFT])" } else { '' }
                                        $staleLine = "[pjc 세션 컨텍스트] 위키 뒤처짐: ${head}${driftPart} — 기능 목록·아키텍처 서술은 지도로만 쓰고 코드를 1차 출처로 하세요. 반영하려면 `"위키 업데이트`"라고 하세요."
                                    }
                                    break   # 허브 하나면 족하다 — 같은 경로를 가리키는 둘째가 있어도 라인을 두 번 내지 않는다
                                }
                            }
                        } catch {}
                    } else {
                        # 파일을 가리키는 경우도 여기로 온다(-PathType Container 실패) — vault로 쓸 수 없으므로 부재와 동일 취급
                        $vaultLine = "[pjc 세션 컨텍스트] 위키 vault: 설정 경로 부재 ($vaultPath) — 절차 K는 조용히 통과하되 건너뛴 사실을 K 1 형식으로 1줄 기록하세요. 위키 작업 요청 시 경로 재확인이 필요합니다."
                    }
                }
            }
        }

        # ---- AGENTS.md 전문 주입 (가이드 판단이 "읽혔는지"에 좌우되지 않게) ----
        # 왜: 세션에서 AGENTS.md 앞부분만 읽고 "관련 내용 없음"으로 단정하는 오답을 구조적으로 없앤다 —
        #   전문이 컨텍스트에 있으면 "부분만 읽는" 상황 자체가 성립하지 않는다. plan과 달리
        #   AGENTS.md는 에이전트에게 읽히려고 두는 파일이라 plan이 없어도 존재하면 주입한다.
        #   16KB 초과 시에는 전문 대신 섹션 목차 + 전문 Read 지시로 폴백(주입 비용 상방 고정).
        # 크기 판정은 읽기 전 FileInfo 1회로 확정한다 — 읽은 뒤 재조회하면 그 사이 삭제·잠금 시
        #   null 크기가 상한 비교(-le)를 조용히 통과하고, 초대형 파일은 읽기 자체가 hook 타임아웃(10초)을
        #   위협해 이미 모은 plan 라인까지 통째로 유실시킨다.
        $agentsMaxBytes = 16384      # 전문 주입 상한 — 하니스 생성 템플릿·이 repo가 모두 전문 주입 범위에 들어가는 값 (v1.135.0 기준 실측 최대 약 12KB)
        $agentsTocMaxBytes = 1048576 # 목차 폴백 상한(1MB) — 초과 시 읽기·목차 스캔 자체를 생략 (비정상 대형 파일 방어)
        # 임박 신호 2축(비율 OR 잔여) — 값·판정 축은 llm-wiki 예산 신호에서 그대로 가져왔다
        #   (BUDGET_CRITICAL_RATIO=0.95 / BUDGET_CRITICAL_SLACK=500). 하니스 안에서 "임박"의 뜻이
        #   갈리면 판정 전에 어느 축인지부터 가려야 하므로 같은 값을 쓴다.
        # 왜 초과가 아니라 임박에서 알리는가: 초과한 뒤에는 이미 전문이 안 들어온 세션이라, 그 세션은
        #   가이드를 잃은 채로 돈다. 실제로 402B 초과인 채 목차만 주입되던 구간이 있었다(대장 2026-08-19).
        # llm-wiki의 80% 선행 게이트는 두지 않는다 — 그 게이트는 예산이 작은 타입(source-stub 1800자)에서
        #   잔여 조건이 저비율을 잡는 것을 막으려는 것인데, 여기는 단일 예산 16KB라 잔여 500B가 곧 96.9%다.
        # 잔여축은 이 예산에서 독립 발화하지 않는다 — 여유 500B 미만이면 15,885B 이상이라 비율축(15,565B)이
        #   이미 참이다. 그래도 남기는 이유는 두 축이 llm-wiki 예산 신호의 한 벌이기 때문이다: 상한이 낮아지면
        #   (예: 8KB로 조정) 잔여축이 먼저 걸리는 구간이 생기고, 그때 한쪽만 있으면 두 곳의 "임박"이 갈린다.
        $agentsNearRatio = 0.95
        $agentsNearSlack = 500
        $agentsPath = Join-Path $cwd 'AGENTS.md'
        $agentsInfo = Get-Item -LiteralPath $agentsPath -ErrorAction SilentlyContinue
        # 빈 파일(0B)은 조용히 스킵 (내용 없는 --- 블록 방지)
        if ($agentsInfo -and -not $agentsInfo.PSIsContainer -and $agentsInfo.Length -gt 0) {
            $agentsBytes = [long]$agentsInfo.Length
            if ($agentsBytes -gt $agentsTocMaxBytes) {
                $lines.Add("[pjc 세션 컨텍스트] AGENTS.md (${agentsBytes}B) — 크기 상한(16KB) 초과로 전문 미주입(자동 로드되지 않습니다). 참조 시 전문을 Read하세요 — 앞부분만 읽고 'AGENTS.md에 없다'고 단정하지 마세요.")
            } else {
                $agentsText = $null
                try { $agentsText = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8 } catch {}
                # 공백뿐인 파일·읽기 실패는 조용히 스킵
                if (-not [string]::IsNullOrWhiteSpace($agentsText)) {
                    if ($agentsText.IndexOf([char]0xFFFD) -ge 0) {
                        # U+FFFD 검출 = UTF-8 디코딩 실패(CP949 등 다른 인코딩) — 깨진 전문을 "정본"으로
                        #   주입하면 오히려 원문 Read를 막으므로, 주입 대신 직접 Read를 안내한다
                        $lines.Add("[pjc 세션 컨텍스트] AGENTS.md 존재 — UTF-8 디코딩 실패(다른 인코딩으로 보임)로 전문 미주입. 참조 시 파일을 직접 Read하세요 — 앞부분만 읽고 'AGENTS.md에 없다'고 단정하지 마세요.")
                    } elseif ($agentsBytes -le $agentsMaxBytes) {
                        # 임박이면 전문 주입은 그대로 하고 꼬리에 경고만 덧붙인다 — 아직 상한 안이라
                        #   가이드를 빼앗을 이유가 없고, 알리는 것만이 목적이다.
                        $agentsSlack = $agentsMaxBytes - $agentsBytes
                        $agentsNear = ($agentsBytes -ge ($agentsMaxBytes * $agentsNearRatio)) -or ($agentsSlack -lt $agentsNearSlack)
                        # 스킬 이름을 백틱으로 감싸지 않는다 — 이중 인용 문자열에서 백틱은 이스케이프 문자라
                        #   출력에서 그대로 사라진다(`n·`t 등으로 오해석될 여지도 있다). 작은따옴표로 표기한다.
                        $agentsNearMsg = if ($agentsNear) { " ⚠ 주입 상한 임박(${agentsBytes}/${agentsMaxBytes}B · 여유 ${agentsSlack}B) — 넘으면 이 전문이 목차로 대체됩니다. 'pjc:record-project-fact'의 「주입 상한 점검·이관」으로 큰 절을 별도 문서로 옮기세요." } else { "" }
                        $lines.Add("[pjc 세션 컨텍스트] AGENTS.md (${agentsBytes}B) 전문 — 이 repo 프로젝트 가이드의 정본입니다(재Read 불필요). AGENTS.md에 관한 판단은 아래 전문을 근거로 하세요 — '관련 내용이 없다'고 말하려면 아래 전문 전체를 근거로만 단정하고, 앞부분만 보고 단정하지 마세요.${agentsNearMsg}`n---`n${agentsText}`n---")
                    } else {
                        # 폴백: 전문 대신 헤딩 목차(§1~3단계) + Read 지시. 폴백 전환 사실을 명시(무신호 폴백 방지)
                        # 0열 코드 펜스(```) 블록을 먼저 제거해 펜스 안의 '# 주석' 줄이 섹션으로 오인되지 않게 한다
                        #   (닫히지 않은 펜스는 제거되지 않고 종전 동작 — fail-open)
                        $tocSource = [regex]::Replace($agentsText, '(?ms)^```[^\r\n]*\r?\n.*?^```[^\r\n]*', '')
                        $agentsHeadings = @([regex]::Matches($tocSource, '(?m)^#{1,3} .+') | ForEach-Object { ($_.Value -replace '^#{1,3}\s*', '').Trim() })
                        $agentsToc = if ($agentsHeadings.Count -gt 0) { "섹션: " + ($agentsHeadings -join ' · ') + " " } else { "" }
                        $lines.Add("[pjc 세션 컨텍스트] AGENTS.md (${agentsBytes}B) — 크기 상한(${agentsMaxBytes}B) 초과로 전문 미주입(자동 로드되지 않습니다). ${agentsToc}참조 시 offset/limit 없이 전문을 Read하세요 — 앞부분만 읽고 'AGENTS.md에 없다'고 단정하지 마세요. 해소하려면 'pjc:record-project-fact'의 「주입 상한 점검·이관」으로 큰 절을 별도 문서로 옮기고 포인터만 남기세요.")
                    }
                }
            }
        }

        # ---- vault 라인 주입 (수집 종료 후 — 게이팅 판정을 여기서 한다) ----
        # cwd 수집으로 라인이 하나라도 늘었을 때만 붙인다(plan·AGENTS 중 하나라도 있음
        #   = pjc 프로젝트 신호). 판정을 위(AGENTS 진입 전)에서 하면 AGENTS.md만 있고
        #   plan이 없는 프로젝트에서 라인이 억제되므로, 삽입 위치만 미리 기록하고
        #   판정은 반드시 여기서 한다.
        # 인덱스 클램프: 기록 후 라인은 AGENTS 블록만 추가하므로 초과할 수 없지만, Insert의
        #   범위 예외는 바깥 catch로 흘러 이미 모은 plan 라인까지 통째로 잃는다.
        if ($vaultLine -and ($lines.Count -gt $cwdBaseCount)) {
            $lines.Insert([Math]::Min($vaultInsertAt, $lines.Count), $vaultLine)
            # 스킬 개선 큐 라인은 vault 라인 바로 뒤에 둔다 — 같은 게이팅(cwd 수집분 존재)을
            #   공유하며, vault 라인 없이 단독으로 나오지 않는다(큐는 vault 안에 있으므로).
            if ($feedbackLine) {
                $lines.Insert([Math]::Min($vaultInsertAt + 1, $lines.Count), $feedbackLine)
            }
            # 뒤처짐 라인은 큐 라인 **다음**이다. 오프셋을 `+2`로 못박지 않는 이유: $feedbackLine 은
            #   하네스 레포에서만 만들어져 다른 프로젝트에서는 항상 $null 이라, 고정하면 그 세션에서
            #   클램프에 걸려 AGENTS.md 전문 뒤로 밀린다(전문이 길어 사실상 묻힌다).
            if ($staleLine) {
                $lines.Insert([Math]::Min($vaultInsertAt + 1 + [int][bool]$feedbackLine, $lines.Count), $staleLine)
            }
        }
    }

    if ($lines.Count -gt 0) {
        # stdout → 세션 컨텍스트 주입 (SessionStart exit 0 규약 — warn-version-drift와 동일)
        Write-Output ($lines -join "`n")
    }
    exit 0
} catch {
    exit 0
}
