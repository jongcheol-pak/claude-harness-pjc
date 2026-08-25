# report-reviewer-usage.ps1 — spec-prefilter 판정 실적 집계 리포트 (수동 실행 도구, hook 아님)
#
# 왜: `spec-prefilter`(Haiku)의 존폐·모델 상향 판정에 필요한 것은 의견이 아니라 실적인데,
#   그 실적이 이미 커밋 본문에 쌓여 있는데도 세는 수단이 없었다 — `implement-task`가 Type B task의
#   완료 커밋 `Review:` 줄에 `(prefilter: PASS/ESCALATE…)`를 남기기 때문이다. 새 적재 경로를 만들면
#   그때부터 0건에서 시작하므로, 이미 있는 기록을 읽는 쪽을 택했다(plan D3).
#   PRD `docs/prds/2026-08-18-wiki-harness-restructure.md`가 이 건을 Out of Scope로 두며 요구한
#   *"계측 수단 도입이 선행돼야 한다"*의 그 수단이다.
# 사용법: pwsh -NoProfile -File plugins/pjc/scripts/report-reviewer-usage.ps1 [-Days 30] [-Since <sha>]
# 안전 계약:
#   ① 읽기 전용 — `git log`만 읽고 레포 파일을 수정하지 않는다.
#   ② 커밋 본문을 그대로 화면에 내지 않는다(SHA + 판정 라벨만) — 본문에 시크릿이 있을 가능성을
#      리포트가 되살리지 않기 위함이다. 실패경로는 SHA만 열거하고 원문 확인은 사용자가 한다.
#   ③ protect-harness 이름 집합 비대상 — 차단/경고 판정에 관여하지 않는 읽기 도구다
#      (report-hook-events.ps1과 같은 근거). validate.ps1의 $knownHelpers 에는 등재.

param(
    [int]$Days = 0,        # 0 = 전체 이력, >0 = 커밋 날짜 기준 최근 N일만
    [string]$Since         # 지정 시 그 커밋까지만 집계 (재현용 — 기준 SHA 고정)
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

Write-Host '== spec-prefilter 판정 실적 리포트 =='

$null = & git rev-parse --git-dir 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host 'git 저장소가 아닙니다 — 집계할 수 없습니다.'; exit 0 }

# 구분자로 나눈다 — 커밋 본문에 줄바꿈·비 ASCII가 섞여 있어 줄 단위 파싱은 경계가 어긋난다.
$logArgs = @('log', '--format=%H%x01%B%x02')
if ($Days -gt 0) { $logArgs += "--since=$Days.days.ago" }
if ($Since) { $logArgs += $Since }
$raw = (& git @logArgs 2>$null) -join "`n"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
    Write-Host '커밋 이력을 읽지 못했습니다.'; exit 0
}

$rangeDesc = if ($Since) { "기준 $Since 까지" } elseif ($Days -gt 0) { "최근 $Days`일" } else { '이력 전체' }

# 모수는 **`Review:`/`검증:` trailer에 prefilter가 적힌 줄**이다 — 본문 산문의 언급(규정 설명·
#   회고)은 판정 기록이 아니라 모수에서 뺀다. 이 구분이 없으면 스킬 문서를 고친 회차의 서술이
#   전부 실적으로 잡힌다(수동 집계 실측: 언급 59건 중 trailer는 34건).
$sample = 0; $pass = 0; $escalate = 0; $unclassified = 0
$failPath = New-Object System.Collections.Generic.List[string]
$unclassSha = New-Object System.Collections.Generic.List[string]

foreach ($chunk in ($raw -split "`u{2}")) {
    if ($chunk -notmatch "`u{1}") { continue }
    $parts = $chunk -split "`u{1}", 2
    $sha = $parts[0].Trim()
    foreach ($line in ($parts[1] -split "`r?`n")) {
        if ($line -notmatch '(?i)prefilter') { continue }
        if ($line -notmatch '^\s*(Review|검증)\s*:') { continue }
        $sample++
        $isPass = $line -match '(?i)prefilter[^)]*?PASS'
        $isEsc = $line -match '(?i)ESCALATE|격상'
        # **배타 분기(if/elseif)를 쓰지 않는다** — 그러면 한 줄이 반드시 한 분류에만 들어가
        #   아래 합계 검사가 항상 참이 되어 죽은 코드가 된다. 독립 판정이라야 「한 줄이 두 분류에
        #   걸리는 표기」(예: 격상 후 재판정 PASS)가 합계 초과로 드러난다.
        if ($isPass) { $pass++ }
        if ($isEsc) { $escalate++ }
        if (-not $isPass -and -not $isEsc) { $unclassified++; $unclassSha.Add($sha.Substring(0, 8)) }
        # 실패경로는 위 3분류와 **직교**한다 — PASS로 끝났어도 그 과정에 빈 응답·재요청이 있었으면
        #   절감이 그만큼 상쇄되므로 따로 센다(합계에 더하지 않는다).
        if ($line -match '(?i)무응답|빈 응답|판정문 없이|incomplete|소진|D ?분기|재요청') {
            $failPath.Add($sha.Substring(0, 8))
        }
    }
}

Write-Host "집계 범위: $rangeDesc"
Write-Host ''

if ($sample -eq 0) {
    Write-Host 'prefilter 판정 기록이 없습니다 — Type B task 완료 커밋이 아직 없거나 얕은 클론입니다.'
    exit 0
}

$failRate = [math]::Round(($failPath.Count / $sample) * 100, 1)
Write-Host "표본(trailer 기재)       : $sample"
Write-Host "  PASS                   : $pass"
Write-Host "  ESCALATE               : $escalate"
Write-Host "  미분류                 : $unclassified  (판정문 없이 끝난 것·아직 모르는 표기)"
Write-Host "실패경로(직교 축)        : $($failPath.Count)  ($failRate%)"
Write-Host ''

# 자기검사 — 위 판정이 **독립**이라 한 줄이 PASS와 ESCALATE에 동시에 걸릴 수 있고, 그때 합이
#   표본을 넘는다. 그런 표기는 아직 관측된 적이 없으므로(현행 커밋 템플릿은 둘 중 하나만 적는다)
#   합계 초과는 곧 **새 표기가 도입됐다는 신호**이며, 그러면 이 파서의 분류 규칙을 손봐야 한다.
# **합이 표본보다 작은 경우는 검사하지 않는다** — `$sample++`이 항상 세 카운터 중 최소 하나를
#   동반하므로(둘 다 거짓이면 미분류가 받는다) 구조상 일어날 수 없다. 도달 불가능한 분기를 두고
#   주석으로 "계수 누락"이라 설명하면, 그 서술 자체가 다음 사람을 오도한다.
$sum = $pass + $escalate + $unclassified
if ($sum -gt $sample) {
    Write-Host "[WARN] 분류 합계($sum)가 표본($sample)을 넘습니다 — 한 줄이 두 분류에 걸렸습니다(새 표기 도입 의심). 파서 분기 확인 필요."
    Write-Host ''
}

# 미분류는 그 자체가 관측 대상이다 — 「판정문 없이 끝난 호출」이 여기 모이고, 새 표기가
#   생기면 여기로 흘러든다. SHA를 남겨야 어느 쪽인지 사람이 확인할 수 있다.
if ($unclassSha.Count) {
    Write-Host '미분류 커밋 (원문은 git show 로 확인):'
    foreach ($s in ($unclassSha | Select-Object -Unique)) { Write-Host "  - $s" }
    Write-Host ''
}

if ($failPath.Count) {
    Write-Host '실패경로 커밋 (원문은 git show 로 확인):'
    foreach ($s in ($failPath | Select-Object -Unique)) { Write-Host "  - $s" }
    Write-Host ''
}

Write-Host '※ 모수는 Type B task의 완료 커밋 trailer뿐입니다 — prefilter가 Type B 전용이라'
Write-Host '  이 수치는 "전체 리뷰 대비 절감률"이 아닙니다(그렇게 읽으면 과대평가입니다).'

# 명시적 종료 — 없으면 마지막 네이티브 호출(`git log`)의 $LASTEXITCODE에 암묵 의존하게 되고,
#   나중에 이 경로에 진단용 외부 명령이 하나 끼면 종료 코드가 조용히 바뀐다.
#   형제 도구 `report-hook-events.ps1`도 같은 관례다.
exit 0
