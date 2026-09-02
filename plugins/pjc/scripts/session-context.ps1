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
# 어떻게: stdin(SessionStart JSON)의 cwd에서 plan(루트 plan.md — 위치는 이 하나다)을 찾아
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

# [절 추출] 스킬 문서에서 지정 헤딩 사이를 잘라 낸다 — compact 직후 루프 제어 규칙 주입용.
#   왜 원문을 자르는가: 주입 텍스트를 여기 복제하면 정본이 둘이 되어 스킬을 고칠 때 갈린다.
#   앵커가 사라지면 주입이 조용히 폴백해 아무도 모르므로, `check-harness-consistency.py`가
#   「추출 앵커 도달성」 축으로 아래 앵커 리터럴을 파싱해 대상 파일과 기계 대조한다(v1.212.0 신설).
#   반환: 절 텍스트 / 실패(파일 부재·시작 앵커 미발견·과대)면 $null → 호출부는 종전 Read 지시로 폴백.
$sectionMaxBytes = 20000   # 추출 결과 상한 — 대상 절이 예상 밖으로 커졌을 때 주입이 세션을 잠식하는 것을 막는다
function Get-SkillSection {
    param([string]$Path, [string]$StartHeading, [string]$StopHeading)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($raw)) { return $null }
        # 헤딩 비교는 TrimEnd() 후 완전 일치 — 부분 일치를 쓰면 `###`가 같은 이름의 `##`를 먼저 문다.
        $lines = $raw -split "`r?`n"
        $startIdx = -1; $stopIdx = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].TrimEnd()
            if ($startIdx -lt 0) { if ($t -eq $StartHeading) { $startIdx = $i } }
            elseif ($t -eq $StopHeading) { $stopIdx = $i; break }
        }
        if ($startIdx -lt 0) { return $null }
        # 종료 앵커가 없으면 파일 끝까지 — 대상 절이 파일 마지막일 수 있다(에러가 아니다).
        $text = ($lines[$startIdx..($stopIdx - 1)] -join "`n").TrimEnd()
        if ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $sectionMaxBytes) { return $null }
        return $text
    } catch { return $null }
}

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
        $lines.Add("[pjc 세션 컨텍스트] 컨텍스트 요약 직후입니다 — 진행 중이던 작업이 있으면 plan.md의 현재 task와 활성 스킬(implement-task 등)의 Halt 조건·승인 게이트·커밋 프로토콜을 요약 기억에 의존하지 말고 SKILL 문서·plan.md 원문에서 재확인하세요. 그리고 **아직 plan.md에 적지 않은** 발견(이연할 항목·확인된 사실)이 요약 전에 있었다면 지금 plan.md에 적으세요 — 대화에만 있던 것은 요약을 지나면 근거 없이 사라집니다.")
    }

    if (-not [string]::IsNullOrWhiteSpace($cwd) -and (Test-Path -LiteralPath $cwd -PathType Container)) {
        # cwd 수집으로 라인이 늘었는지 판정하는 기준 개수 — vault 라인 게이팅에 쓴다.
        #   compact 리마인더는 이 블록 밖에서 append되므로, 이 기준과 비교하면 리마인더가
        #   자연히 게이팅 신호에서 제외된다($lines.Count -gt 0으로 판정하면 비 pjc 프로젝트의
        #   요약 직후 세션에도 vault 라인이 붙는다).
        $cwdBaseCount = $lines.Count

        # ---- plan 탐색: 루트 plan.md 하나 ----
        # plan 위치는 루트 단일계다(v1.210.0) — 과거 회차 plan이 쌓인 디렉터리로 폴백하면
        # 그 미완료분이 이번 세션의 상태로 주입된다.
        $rootPlan = Join-Path $cwd 'plan.md'
        $planPath = $null
        $planLabel = $null
        if (Test-Path -LiteralPath $rootPlan -PathType Leaf) {
            $planPath = $rootPlan
            $planLabel = 'plan.md'
        }

        # 압축 직후 절 원문 주입이 쓰는 스킬 폴더 — **구현 세션 분기와 계획 세션 분기가 배타적**이라(뒤쪽
        #   `-not $planPath -or $all -eq 0 -or $open -eq 0`) 어느 한쪽 안에서 대입하면 다른 쪽에서 $null이 되고,
        #   Join-Path가 파라미터 바인딩 오류를 내 바깥 try의 catch에 잡혀 **hook 출력이 통째로 사라진다**.
        #   그래서 양 분기 위에서 한 번만 정한다. 변수명은 바꾸지 않는다 — check-harness-consistency.py의
        #   「추출 앵커 도달성」 축이 `Join-Path $skillsDir '...'` 리터럴로 호출을 수집한다.
        $skillsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'

        if ($planPath) {
            $planText = $null
            try { $planText = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 } catch {}
            if ($planText) {
                # task 라인만 카운트 (pjc plan 규약: "- [x] T1: ..." — 통과 체크리스트 등 다른 체크박스 제외)
                $all = [regex]::Matches($planText, '(?m)^- \[[ /x]\] T\d+').Count
                $open = [regex]::Matches($planText, '(?m)^- \[[ /]\] T\d+').Count

                # ---- Deferred 미판정 계수 (task 체크박스와 별개 축) ----
                # 왜: plan.md는 gitignore + 다음 회차 교체라, `## Deferred / Follow-up` 항목이 대장
                #   (docs/plans/deferred.md)으로 옮겨지기 전에 회차가 끝나면 통째로 사라진다. task는
                #   위 두 정규식이 세지만 Deferred는 아무도 세지 않아, "task 전부 완료" 옆에 미이관
                #   항목이 남아도 완료로 흘러갔다. 마커 규정(F-6.5 「판정 결과를 plan 항목에 마커로
                #   남긴다」)이 그 상태를 기계 판독 가능하게 만들고 여기가 그것을 센다.
                # **판정은 plan 단위가 아니라 항목 단위다** — "마커가 하나도 없을 때만 폴백"으로 두면
                #   **마커 혼재 상태**(일부만 [등재], 나머지는 마커 없음 = 이관 도중 압축된 실제 형태)에서
                #   폴백이 안 걸리고 [미판정] 리터럴도 0건이라 부기가 조용히 사라진다.
                # 세는 것은 미판정뿐이다 — 이미 판정된 항목까지 매 세션 알리면 같은 수가 늘 떠 신호가
                #   무뎌진다(대장 [2026-08-03] 「늘 '해당 없음'으로 채워지면 형식만 남는다」와 같은 축).
                $defUnjudged = 0
                $defMatch = [regex]::Match($planText, '(?ms)^## Deferred / Follow-up\s*?$(.*?)(?=^## |\z)')
                if ($defMatch.Success) {
                    foreach ($defLine in ($defMatch.Groups[1].Value -split "`r?`n")) {
                        if ($defLine -notmatch '^- ') { continue }
                        # `- ` 접두와 **있으면** 마커까지 벗겨 낸 뒤 본문을 본다 — 마커 그룹이
                        #   `(?:...)?`로 옵셔널이어야 한다. 필수로 두면 **마커 없는 placeholder**
                        #   (템플릿 기본값 `- <이번엔 제외…>`)에서 치환이 통째로 불발해 문자열이
                        #   `- <…>` 그대로 남고 `^<`가 영영 거짓이 된다 — 갓 만든 모든 plan에서
                        #   미판정 1건이 상시 오발화한다(T2 spec 리뷰 1R B1이 재현으로 잡은 결함).
                        if (($defLine -replace '^- (?:\[[^\]]*\]\s*)?', '') -match '^<') { continue }   # 템플릿 placeholder
                        if ($defLine -match '^- \[등재\]') { continue }
                        # 기호는 **닫는 대괄호가 아닌 문자 1자 이상**이어야 한다 — 사유 없는
                        #   `[미등재]`·`[미등재:]`는 걸리지 않고 미판정으로 센다(게이트 ⓕ가 막으려는 형태).
                        # ⚠ `.+`를 쓰면 `.`이 `]`도 먹어, `- [미등재:] **X** 참고 [ref]`처럼 **같은 줄
                        #   뒤쪽에 대괄호가 있으면** 매치돼 판정된 것으로 빠진다(F-7 2R m3 재현).
                        if ($defLine -match '^- \[미등재:[^\]]+\]') { continue }
                        $defUnjudged++
                    }
                }
                # 기존 라인 **뒤에** 붙인다 — 앞에 끼우면 `미완료 2`·`전부 완료`·`존재`를 부분문자열로
                #   재는 기존 골든 7건이 살아남더라도 사람이 읽는 순서가 뒤집힌다.
                $defNote = if ($defUnjudged -gt 0) { " · **Deferred 미판정 ${defUnjudged}건** — 대장(docs/plans/deferred.md) 등재 판정이 남아 있습니다(F-6.5)." } else { "" }
                if ($all -gt 0) {
                    if ($open -gt 0) {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 중 미완료 ${open}개 — 작업 시작 전 plan.md 진행 상태를 확인하세요.${defNote}")
                        # 압축 직후 + 미완료 task = 자율 루프가 규칙을 잃은 채 재개될 최위험 조합.
                        #   스킬은 auto-compact 후 앞 5,000토큰만 재부착되므로 뒷부분(Phase 절차·Halt
                        #   조건·재시도 카운터)이 통째로 빠지는데, 동일 스킬 재invoke는 "이미 로드됨"만
                        #   반환해 복구되지 않는다 — Read만 유효하다. 그래서 위 일반 리마인더(재확인하라)에
                        #   더해 "무엇을" 읽을지를 기계가 못박는다.
                        # Phase 판정은 하지 않는다: hook이 plan 형식에 의존하게 되고 형식이 바뀌면 조용히
                        #   깨진다. 대신 Phase와 무관하게 늘 필요한 루프 제어 3종만 고정 지정하고,
                        #   Phase 특화 reference는 스킬 본문의 지시에 맡긴다.
                        if ($source -eq 'compact') {
                            # ⚠ 3경로 리터럴(implement-task/SKILL.md · references/halt-conditions.md · references/recovery.md)을
                            #   보존한다 — 골든 SC14·SC14b·SC14c가 각각을 ExpectContains로 재고 있어, 문면을 다듬다
                            #   경로 하나라도 빠지면 즉시 FAIL한다. 조정 대상은 경로를 감싸는 서술뿐이다.
                            $lines.Add("[pjc 세션 컨텍스트] 진행 중 plan이 있습니다 — 아래에 루프 제어 규칙 원문을 함께 주입했으니 그 두 절은 다시 읽지 않아도 됩니다. 그 밖의 Phase 절차·복구 규약이 필요하면 Read로 확인하세요(스킬 재invoke로는 복구되지 않습니다): implement-task/SKILL.md · implement-task/references/halt-conditions.md · implement-task/references/recovery.md. 진행 중인 Phase가 참조하는 reference 파일도 함께 읽으세요.")

                            # 경로만 지시하면 ① 실제로 읽었는지 검증할 장치가 없고 ② 세 파일 합 약 172KB를
                            #   다시 읽는 것은 압축으로 확보한 여유를 도로 소진한다. 그래서 루프 제어에 필요한
                            #   두 절만 원문에서 잘라 넣는다(약 14KB). Phase 절차·복구 규약은 여전히 파일에 있다.
                            # 추출 실패는 조용히 건너뛴다 — 위 Read 지시가 그대로 남아 폴백이 성립한다.
                            $secRules = Get-SkillSection -Path (Join-Path $skillsDir 'implement-task/SKILL.md') -StartHeading '### 🚨 자율 루프의 절대 규칙' -StopHeading '### 🧠 컨텍스트 관리 (장시간 작업 대비)'
                            if ($secRules) { $lines.Add("[pjc 세션 컨텍스트] 압축 직후 루프 제어 규칙 (원문 발췌 — implement-task/SKILL.md 「자율 루프의 절대 규칙」)`n$secRules") }
                            # 종료 앵커가 「"사소한 문제"…」인 것은 그 직전 절(「컨텍스트 한계는 Halt 사유가 아니다」)을
                            #   **포함하기 위해서**다 — 압축 직후에 가장 필요한 규칙이 *"컨텍스트가 과밀해도 멈추거나
                            #   새 세션을 묻지 않는다"* 인데, 그 절을 종료 앵커로 삼으면 배타적으로 잘려 빠진다.
                            #   회차 동기가 「compact 후 루프가 멈춘다」인데 정작 그 답이 주입 밖에 남던 것을 F-7이 잡았다.
                            $secHalt = Get-SkillSection -Path (Join-Path $skillsDir 'implement-task/references/halt-conditions.md') -StartHeading '## 중단 조건 표' -StopHeading '## "사소한 문제"는 중단 사유가 아니다'
                            if ($secHalt) { $lines.Add("[pjc 세션 컨텍스트] 압축 직후 루프 제어 규칙 (원문 발췌 — implement-task/references/halt-conditions.md 「중단 조건 표」·「위임 경계」·「컨텍스트 한계는 Halt 사유가 아니다」)`n$secHalt") }
                        }
                    } else {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 전부 완료 — 새 작업이면 plan 교체 전 Deferred/Follow-up 잔여 항목을 확인하세요.${defNote}")
                    }
                } else {
                    # task 체크박스가 없는 plan.md(비 pjc 형식) — 카운트 오보 대신 존재만 알림
                    $lines.Add("[pjc 세션 컨텍스트] ${planLabel} 존재 — 작업 시작 전 진행 상태를 확인하세요.${defNote}")
                }
            }
        }

        # ---- Deferred 대장 최고령 「마지막 판정일」 (하네스 레포 세션에서만) ----
        # 왜: 소진 batch 착수 조건 축 ②(최고령 > 30일)가 전적으로 손계산이었고 **같은 오산이 2회** 났다
        #   — v1.188.0은 날짜 접두 부기를 못 읽어 하루 전 판정된 항목을 39일로 봤고, v1.219.0·v1.220.0은
        #   항목 안의 **최신** 스탬프를 못 읽어 34일을 보고했다(실측 14일). check-harness-consistency.py는
        #   두 문서의 문면 동기만 대조하고 **값 자체를 재는 축이 없어** 손계산이 틀려도 전 축이 통과한다.
        #   오산이 난 자리가 계획 세션(plan-feature Step 1 ③)이라 검사기로는 늦다 — 세션 시작에 기계가 준다.
        # 판정 규칙(정본: implement-task references/phase-f-detail.md ⓪): 항목마다 「재확인 표기·부기 형식·
        #   등록일 중 가장 최신 날짜」를 정하고 그 **최솟값**이 최고령이다.
        # **파싱 단위는 「항목」이지 「줄」이 아니다** — 대장에는 하위 불릿이 실재하고, 거기에만 최신 스탬프가
        #   붙은 항목이 생기면 줄 단위는 판정일을 **과소평가**해 축 ②를 일찍 연다(v1.188.0 오산과 같은 방향).
        # 날짜 인식을 **여는 기호 직후**(`[` 또는 `(`)로 한정하는 이유: 본문에 인용된 날짜가 섞이면 그 항목의
        #   최댓값이 밀려 올라가 최고령 후보에서 영구히 빠진다(실측: 축 ② 예정일 2026-09-18을 본문에 적은 항목).
        #   **키워드 목록으로 잡지 않는다** — 새 부기 형태를 원리상 놓친다(실측: 「실적 계측」이 목록에 없어
        #   판정 부기 하나를 놓쳤다. 이번 회차가 겨냥한 실패 유형이 바로 그것이다).
        # 미래 날짜를 후보에서 빼는 것은 위 인용 방어의 짝이다(괄호 안에 예정일이 적히는 경우).
        # ⚠ `-match '^- \[…'` 형태를 쓰지 않는다 — check-harness-consistency.py의 「복제 리터럴 동기」 축이
        #   그 리터럴에서 마커 토큰을 뽑아 대조하므로, 날짜 정규식이 거기 걸리면 orphan으로 exit 1이 난다.
        # 하네스 레포 판정은 cwd 아래 plugin.json 존재이며 **상위 탐색을 하지 않는다**(아래 큐 라인과 같은 기준).
        # 전 구간 try/catch — 대장 읽기 실패가 세션 시작을 막지 않는다(fail-open).
        try {
            $ledgerPluginJson = Join-Path $cwd 'plugins/pjc/.claude-plugin/plugin.json'
            $ledgerPath = Join-Path $cwd 'docs/plans/deferred.md'
            if ((Test-Path -LiteralPath $ledgerPluginJson -PathType Leaf) -and (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
                $ledgerText = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8
                # 종료 앵커 `^## `는 현재 대장에 `## 대기` 하나뿐이라 실질적으로 `\z`로 끝난다.
                #   그래도 두는 이유는 `## 종결` 같은 절이 다시 생길 때를 대비한 것이고(v1.198.0 이전엔 실재),
                #   주제 그룹 헤딩은 `### `라 여기 걸리지 않아 그대로 스캔된다.
                $ledgerWait = [regex]::Match($ledgerText, '(?ms)^## 대기\s*?$(.*?)(?=^## |\z)')
                if ($ledgerWait.Success) {
                    $ledgerItemRx = [regex]'^- \[\d{4}-\d{2}-\d{2}'
                    $ledgerDateRx = [regex]'[\[(](\d{4}-\d{2}-\d{2})'
                    # vN 부기는 **형식이 둘**이다 — ⓐ 날짜 접두(정본 ⓪이 예시하는 형태) ⓑ 제목 뒤 괄호
                    #   (v1.185.0 T2가 「부기를 제목 뒤로」 옮기는 관례를 세운 뒤의 현행 형태). 한쪽만 보면
                    #   그 축이 조용히 죽는다 — 현행 대장의 실물은 전부 ⓑ다.
                    $ledgerVnPrefixRx = [regex]'^- \[\d{4}-\d{2}-\d{2}, '
                    $ledgerVnTailRx = [regex]'\(v\d+\.\d+\.\d+[^)]*해소\)'
                    $ledgerToday = (Get-Date).Date

                    $ledgerItems = New-Object System.Collections.Generic.List[string]
                    $ledgerCur = $null
                    foreach ($ledgerLine in ($ledgerWait.Groups[1].Value -split "`r?`n")) {
                        if ($ledgerItemRx.IsMatch($ledgerLine)) {
                            if ($null -ne $ledgerCur) { $ledgerItems.Add($ledgerCur) }
                            $ledgerCur = $ledgerLine
                        } elseif ($null -ne $ledgerCur) {
                            $ledgerCur = $ledgerCur + "`n" + $ledgerLine
                        }
                    }
                    if ($null -ne $ledgerCur) { $ledgerItems.Add($ledgerCur) }

                    $ledgerJudged = @()
                    $ledgerVnCount = 0
                    foreach ($ledgerItem in $ledgerItems) {
                        $ledgerBest = $null
                        foreach ($ledgerHit in $ledgerDateRx.Matches($ledgerItem)) {
                            $ledgerDate = $null
                            # 형식은 맞지만 의미가 무효인 문자열(2026-13-45 등)은 그 날짜만 건너뛴다 —
                            #   항목 자체를 버리면 그 항목이 최고령 후보에서 통째로 빠진다.
                            try { $ledgerDate = [datetime]::ParseExact($ledgerHit.Groups[1].Value, 'yyyy-MM-dd', $null) } catch { continue }
                            if ($ledgerDate -gt $ledgerToday) { continue }
                            if ($null -eq $ledgerBest -or $ledgerDate -gt $ledgerBest) { $ledgerBest = $ledgerDate }
                        }
                        if ($null -ne $ledgerBest) { $ledgerJudged += $ledgerBest }
                        $ledgerHead = ($ledgerItem -split "`n")[0]
                        if ($ledgerVnPrefixRx.IsMatch($ledgerHead) -or $ledgerVnTailRx.IsMatch($ledgerHead)) { $ledgerVnCount++ }
                    }

                    if ($ledgerItems.Count -gt 0 -and $ledgerJudged.Count -gt 0) {
                        # @() 로 감싸는 것이 요점이다 — 항목이 **1건이면** 파이프 결과가 배열이 아니라
                        #   스칼라라 [0] 이 엉뚱한 값을 준다(아래 스킬 개선 큐 라인이 같은 사고를 겪었다).
                        $ledgerOldest = @($ledgerJudged | Sort-Object)[0]
                        $ledgerAge = [int][math]::Floor(($ledgerToday - $ledgerOldest).TotalDays)
                        $ledgerVnNote = if ($ledgerVnCount -gt 0) { " (단 vN 부기 ${ledgerVnCount}건은 릴리즈 날짜를 반영하지 않았습니다 — 손계산 확인 필요.)" } else { "" }
                        $lines.Add("[pjc 세션 컨텍스트] Deferred 대장: 대기 $($ledgerItems.Count)건 / 최고령 ${ledgerAge}일($($ledgerOldest.ToString('yyyy-MM-dd'))) — 축 ② 임계 30일.${ledgerVnNote}")
                        # 이 라인은 **vault 게이팅 신호가 아니다** — 하네스 레포에는 plan·AGENTS.md가 있어
                        #   이미 게이팅을 통과하지만, 둘 다 없는 상태에서 이 라인만으로 vault 라인이 새지
                        #   않게 짝을 맞춘다(위 계획 세션 주입 4곳과 같은 처리).
                        $cwdBaseCount++
                    }
                }
            }
        } catch {}

        # ---- 계획 세션의 압축 리마인더 (plan이 없거나 · task 0개 · task가 전부 완료) ----
        # 위 블록은 `if ($planPath)` 안이라 **진행 중 plan이 있는 세션**만 닿는다. 계획을 세우던 중
        #   압축되면 plan이 아직 없거나 task 체크박스가 0개라 그 지시를 못 받는데, `plan-feature`도
        #   본체가 앞 5,000토큰 밖으로 밀리는 것은 같다(경계 82행 / 전체 526행 — 예산 표 실측) — Step 4 영향 범위,
        #   Step 5 작업 분해, Step 9 리뷰 게이트가 통째로 요약에 뭉개진 채 계획이 이어진다.
        # **`$open -eq 0`(전부 완료)도 대상이다.** 위 블록의 compact 재읽기 지시는 `$open -gt 0`
        #   분기에만 있고 「전부 완료」 분기(`else`)에는 없어서, **완료된 plan이 남은 채 새 계획을
        #   세우는 세션**은 두 분기 사이로 빠져 아무 재읽기 지시도 받지 못했다. 회차를 마치면 plan.md는
        #   task가 전부 [x]인 채 남고 다음 계획 세션이 그 위에서 시작하므로 이 상태가 오히려 흔하다.
        # 스킬 판정은 하지 않는다: 어느 스킬이 활성인지 알 방법이 없고 추측하면 틀린 파일을 지목한다.
        #   plan 상태로만 분기하는 것은 위 블록과 같은 축이다.
        # ⚠ plan도 AGENTS.md도 없는 **비 pjc 프로젝트에는 붙이지 않는다** — 위 `:16` 주석의 무출력
        #   규칙과 같은 취지다. 이 리마인더는 「계획을 세우던 중이었다면」이라 대상이 pjc 워크플로인데,
        #   무관한 폴더의 압축 세션에까지 뜨면 그냥 노이즈다(AGENTS.md 경로는 아래에서 다시 쓰지만
        #   여기서는 존재 판정만 필요해 직접 Test-Path 한다).
        if ($source -eq 'compact' -and (-not $planPath -or $all -eq 0 -or $open -eq 0) -and ($planPath -or (Test-Path -LiteralPath (Join-Path $cwd 'AGENTS.md')))) {
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

            # 경로만 지시하면 구현 세션에서와 같은 문제가 남는다 — 읽었는지 검증할 수 없고, 그 파일이
            #   100KB급이라 다시 읽는 것이 압축으로 확보한 여유를 도로 쓴다. 계획 판단이 처음부터
            #   틀어지는 것을 막는 것은 절대 규칙이므로 그 절만 원문으로 넣는다(실측 9,963B).
            #   Step 4·5·9는 계획 중반에 필요해 그때 Read해도 늦지 않아 대상이 아니다.
            # 추출 실패는 조용히 건너뛴다 — 위 경로 지시가 그대로 남아 폴백이 성립한다(구현 세션과 같은 설계).
            $secPlanRules = Get-SkillSection -Path (Join-Path $skillsDir 'plan-feature/SKILL.md') -StartHeading '## 절대 규칙 (Hard Rules)' -StopHeading '## 실행 단계'
            if ($secPlanRules) {
                $lines.Add("[pjc 세션 컨텍스트] 압축 직후 계획 규칙 (원문 발췌 — plan-feature/SKILL.md 「절대 규칙」)`n$secPlanRules")
                # 위 리마인더와 같은 이유로 기준선을 함께 올린다 — 이 분기는 「줄 1개 추가 = 기준선 1 증가」가
                #   짝이라, 두 번째 Add를 넣고 올리지 않으면 `$lines.Count -gt $cwdBaseCount`가 성립해
                #   plan 없이 AGENTS.md만 있는 압축 세션에 vault 라인이 새로 붙는다.
                #   주입은 $null 폴백이 있으므로 **성공했을 때만** 올린다.
                $cwdBaseCount++
            }

            # 같은 분기에서 큐 기록 규약도 넣는다 — 계획 세션의 배치 시점(Step 10 승인 직후)에
            #   `[DECISION]`·`[PROJECT-FACT]` 큐잉 형식이 필요한데, plan-feature Step 10은 그 절차를
            #   **가리키기만 하고 llm-wiki를 발동하지 않아** 압축되면 형식이 손에 남지 않는다.
            #   구현 세션을 대상에서 뺀 이유: F-6.5 ⓒ가 `pjc:llm-wiki`를 Skill 도구로 재발동해
            #   복구 경로가 이미 있다(그쪽은 주입 없이도 규약이 손에 들어온다).
            #   대상이 K 5-2~5-3인 것은 그 둘만 배치 시점 규약이기 때문이다 — K 5 전체(19,869B)로
            #   넓히면 임박선(16,000B)을 넘어 크기 축이 exit 1을 낸다.
            $secQueueRules = Get-SkillSection -Path (Join-Path $skillsDir 'llm-wiki/references/queue-rules.md') -StartHeading '### K 5-2. 결정 큐잉 ([DECISION])' -StopHeading '### K 5-4. 미스 큐잉 ([K-MISS])'
            if ($secQueueRules) {
                $lines.Add("[pjc 세션 컨텍스트] 압축 직후 큐 기록 규약 (원문 발췌 — llm-wiki/references/queue-rules.md 「K 5-2~5-3」)`n$secQueueRules")
                # 위 주입과 같은 짝 — 줄 1개 추가 = 기준선 1 증가(SC41e가 고정한 계약).
                $cwdBaseCount++
            }

            # 조회 절차는 원문을 싣지 않고 경로만 가리킨다(v1.220.0) — 절차 K가
            #   `references/lookup-rules.md`로 분리돼 그 파일 하나만 Read하면 K 1~5가 완결된다.
            #   종전엔 K 1~2 원문 15,402B를 실었는데 둘 다 문제였다: ⓐ 이 분기는 「계획 세션일
            #   것 같다」는 추정이라 위키를 열 일이 없는 세션까지 대상이었고 ⓑ 상한 때문에 K 3~4가
            #   잘려 나가 주입이 Read를 대체하지도 못했다.
            # ⚠ `Join-Path`를 쓰지 않는다 — 단일 인자로 줘도 구분자를 백슬래시로 정규화해
            #   경로 리터럴을 재는 골든(SC43b)이 Windows에서만 깨진다(실측 2026-09-02).
            #   보간으로 이어 붙여 뒤쪽 세그먼트를 슬래시로 고정한다 — Windows도 슬래시 경로를 인식하고,
            #   그래야 그 계약이 OS에 안 매인다.
            $lookupPath = "$skillsDir/llm-wiki/references/lookup-rules.md"
            $lines.Add("[pjc 세션 컨텍스트] 위키 조회 절차: $lookupPath — 위키를 참조하기 전에 이 파일을 Read하세요(절차 K 1~5 전체). vault 판정 게이트가 그 안에 있습니다.")
            # 위 둘과 같은 짝 — 라인이 하나 늘었으므로 기준선도 하나 올린다.
            #   주입과 달리 추출 실패 분기가 없어 무조건 올린다.
            $cwdBaseCount++
        }

        # ---- 위키 vault 설정 상태 판정 (라인 생성만 — 주입은 아래 수집 종료 후) ----
        # 왜 ①(원래 목적): 절차 K(코드 작업 전 위키 read-only 참조)는 "vault 미설정이면 조용히 통과"인데,
        #   확인 없이 미설정으로 단정해 **설정·실재하는 위키를 통째로 건너뛴** 사고가 있었다
        #   (2026-07-30). 기계가 상태를 1줄 주입하면 그 추측 여지 자체가 사라진다 —
        #   AGENTS.md 전문 주입(아래)과 같은 구조의 해법이다.
        # 왜 ②(v1.197.0 추가): 절차 K는 **호출측이 그 절차를 수행할 때만** 돈다(v1.220.0부터 스킬 발동이 아니라
        #   `lookup-rules.md` Read다 — plan-feature Step 1·implement-task
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
                        #   절차 K 3도 같은 값을 재지만 **그 절차를 수행한 세션에서만**이고, 그 결과는 내부
                        #   판정(서술을 낡은 것으로 취급)에만 쓰여 사용자 화면에는 뜨지 않는다.
                        # 허브는 **vault 쪽에서 역방향으로** 찾는다 — AGENTS.md의 '## 위키' 절을 읽는 설계면
                        #   그 절이 없는 프로젝트가 통째로 빠지는데, 실측상 가장 뒤처진 MOA가 그 경우다.
                        # 매칭 축은 둘이며 **URL 우선·경로 폴백**이다.
                        #   ① `repo_url`(허브 frontmatter) ↔ cwd 의 `git remote get-url origin`.
                        #      URL 은 PC·폴더명·개명 전부에 불변이라 vault 를 여러 PC 에서 공유해도 맞는다.
                        #      **경로 축과 달리 레포 내 임의 위치에서 성립한다** — `git -C` 가 상위를 찾으므로
                        #      하위 폴더 세션·같은 레포의 다른 clone·워크트리가 전부 이 허브에 매칭된다.
                        #      그것이 의도다: 하위 폴더의 **별도** git 레포는 자기 origin 을 내므로 남의 허브에
                        #      붙지 않는다(경로 prefix 확대가 일으키던 오탐과 성격이 다르다).
                        #   ② `- **경로**:` ↔ cwd **동일 경로만**(상위 탐색 없음). 허브에 URL 이 없는 구형이거나
                        #      cwd 가 git 레포가 아닐 때의 폴백이다. prefix 로 넓히지 않는 이유는 종전과 같다 —
                        #      참고용 clone·하위 워크트리가 남의 허브에 붙는다.
                        #   **cwd 의 URL 을 못 읽으면 URL 축을 통째로 끈다**(전 허브 경로 판정) — 그러지 않으면
                        #   remote 없는 로컬 전용 레포에서 허브에 URL 이 있다는 이유만으로 건너뛰어져 알림이
                        #   조용히 사라진다.
                        # 발화는 OR 3축(커밋 30 · 경과일 14 · K-DRIFT 1건). 뒤처짐 축이 둘 다 미달이면
                        #   그 수치를 빼고 잔량만 싣는다 — "0커밋 미반영"은 사실이 아니라 잡음이다.
                        # 전 구간 try/catch fail-open: 허브 무매치·synced_commit 부재·git 부재·파싱 실패는
                        #   조용히 통과한다(이 파일의 다른 경로와 같은 원칙 — 세션 시작을 막지 않는다).
                        try {
                            $hubDir = Join-Path $vaultPath '20_projects'
                            if (Test-Path -LiteralPath $hubDir -PathType Container) {
                                $cwdNorm = ($cwd -replace '\\', '/').TrimEnd('/')
                                # cwd 의 origin URL 은 **루프 밖에서 1회만** 읽는다 — 허브마다 부르면 git 이
                                #   파일 수만큼 뜬다. `git` 이 PATH 에 없으면 `&` 호출이 종료 오류를 던지므로
                                #   이 호출만 따로 감싼다(아래 rev-list 와 같은 선례) — 실패하면 빈 문자열이
                                #   되어 URL 축이 꺼지고 경로 축만 남는다.
                                # 정규화는 소문자화 + 후행 `.git` 제거 + 후행 `/` 제거(wiki-schema §2.2) —
                                #   같은 레포라도 값을 어디서 얻었느냐에 따라 표기가 갈리기 때문이다.
                                # **`scheme://…` 형태만 받는다**(https·git·ssh:// 등 포함 — 걸러지는 것은
                                #   `://` 가 없는 scp 형 SSH `git@host:owner/repo.git` 하나다).
                                #   그 형태를 받으면 허브의 https `repo_url` 과 영영 일치하지 않아, 경로로
                                #   폴백하던 세션이 «불일치»로 판정돼 조용히 미발화가 된다(URL 이 있으면
                                #   경로로 되짚지 않기 때문이다). 받지 않으면 $cwdUrl 이 비어 URL 축이
                                #   꺼지고 경로 축이 그대로 산다. 형식 간 상호 변환은 실증 대상이 없어
                                #   넣지 않았다(wiki-schema §2.2).
                                $cwdUrl = ''
                                try {
                                    $urlRaw = (& git -C $cwd remote get-url origin 2>$null | Select-Object -First 1)
                                    if ("$urlRaw" -match '^\S+://\S+$') {
                                        $cwdUrl = ("$urlRaw".Trim().ToLowerInvariant() -replace '\.git$', '').TrimEnd('/')
                                    }
                                } catch {}
                                # Depth 1 = `20_projects/<카테고리>/<프로젝트>.md` 까지. 그 아래 feature 파일
                                #   (`.../<프로젝트>/feat-*.md`)은 허브가 아니라 대상에서 자연히 빠진다.
                                foreach ($hubFile in (Get-ChildItem -LiteralPath $hubDir -Filter '*.md' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue)) {
                                    $hubText = $null
                                    try { $hubText = Get-Content -LiteralPath $hubFile.FullName -Raw -Encoding UTF8 } catch { continue }
                                    if (-not $hubText) { continue }

                                    # 축 ① URL — cwd 쪽 URL 을 읽은 경우에만 판정한다. 허브에 `repo_url` 이
                                    #   있으면 **일치/불일치가 곧 결론**이고 경로로 되짚지 않는다(URL 이 더 강한
                                    #   신호다). 허브에 없으면 아래 경로 축으로 내려간다.
                                    $hubUrl = ''
                                    if ($cwdUrl) {
                                        $urlMatch = [regex]::Match($hubText, '(?m)^repo_url:\s*"?([^"\r\n]+?)"?\s*$')
                                        if ($urlMatch.Success) {
                                            $hubUrl = ($urlMatch.Groups[1].Value.Trim().ToLowerInvariant() -replace '\.git$', '').TrimEnd('/')
                                        }
                                    }
                                    if ($hubUrl) {
                                        if ($hubUrl -ne $cwdUrl) { continue }
                                    } else {
                                        # 축 ② 경로 — URL 축이 꺼졌거나 허브에 `repo_url` 이 없을 때.
                                        $pathMatch = [regex]::Match($hubText, '(?m)^- \*\*경로\*\*:\s*`([^`]+)`')
                                        if (-not $pathMatch.Success) { continue }
                                        if ((($pathMatch.Groups[1].Value -replace '\\', '/').TrimEnd('/')) -ine $cwdNorm) { continue }
                                    }

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
                                        } else { "$label 위키 반영이 밀려 있습니다" }
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
