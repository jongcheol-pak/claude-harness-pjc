# check-transcript-assumptions.ps1 — require-evidence 검사 4가 의존하는 transcript 스키마 가정을
#   실제 데이터로 재확인한다 (수동 실행 도구, hook 아님 — hooks.json 미배선).
#
# 왜: 골든(run-hook-evals.ps1)은 픽스처를 우리가 만들므로 **스키마가 바뀌어도 계속 green**이고,
#   이벤트 로그(report-hook-events.ps1)에는 "사용자가 직전에 무엇을 말했나"라는 맥락이 없다.
#   즉 두 자산 모두 이 축을 못 본다 — 검사 4의 skip 4종이 겨냥한 형태가 실환경에 실재하는지는
#   실 transcript 대조로만 확인된다. 이 스크립트가 그 대조를 자산으로 고정한다.
#
# 사용법:
#   pwsh -NoProfile -File plugins/pjc/hooks/evals/check-transcript-assumptions.ps1 [-ProjectDir <경로>] [-Sessions 6] [-Quick]
#
# 안전 계약:
#   ① 읽기 전용 — transcript를 수정·삭제하지 않는다.
#   ② **발화 내용을 출력하지 않는다.** transcript에는 실제 대화가 들어 있으므로 판정과 수치
#      (건수·길이·최댓값)만 낸다. 경로도 사용자명이 드러나지 않게 파일명만 표시한다.
#   ③ 판정 로직은 require-evidence.ps1을 import하지 않고 **자체 재현**한다(hook을 dot-source하면
#      stdin 대기·exit 부작용이 있다). 그래서 재현이 원본과 조용히 어긋날 위험이 있고,
#      가정 5(pin 검사)가 그 위험을 최소한으로 막는다 — **hook의 역순 스캔을 수정하면 이 파일의
#      Invoke-ReverseScan과 $skipPins를 함께 갱신할 것.**
#
# 종료 코드: DRIFT가 하나라도 있으면 1, 전건 OK(또는 정보 부족 SKIP)면 0, 대상을 못 찾으면 2.

param(
    # transcript(*.jsonl) 디렉터리. 미지정 시 현재 작업 디렉터리로 Claude 프로젝트 폴더를 추론한다.
    [string]$ProjectDir,
    # 최근 N개 세션 파일만 대상으로 한다(세션당 수 MB — 전량은 비싸다).
    [int]$Sessions = 6,
    # 가정 4를 종료 시점 1개만 재현한다(전수는 세션당 수백 회 스캔이라 수 분 걸린다).
    [switch]$Quick
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$evalsDir   = $PSScriptRoot
$pluginRoot = Split-Path (Split-Path $evalsDir -Parent) -Parent   # plugins/pjc
$hookPath   = Join-Path $pluginRoot 'scripts/require-evidence.ps1'

$drift = 0
function Write-Verdict {
    param([ValidateSet('OK', 'DRIFT', 'SKIP')][string]$Kind, [string]$Title, [string]$Detail)
    if ($Kind -eq 'DRIFT') { $script:drift++ }
    Write-Host ("[{0}] {1} — {2}" -f $Kind, $Title, $Detail)
}

# ---- 대상 디렉터리 해석 ----
# Claude Code는 프로젝트 경로의 비영숫자를 '-'로 바꾼 이름으로 ~/.claude/projects 아래에 둔다.
if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
    $homeBase = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
    $slug = ((Get-Location).Path -replace '[^A-Za-z0-9]', '-')
    $ProjectDir = Join-Path $homeBase (".claude/projects/" + $slug)
}
if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
    # 추측하지 않는다 — 경로를 지어내면 "대상 없음"을 "가정 충족"으로 오인할 수 있다.
    Write-Host "transcript 디렉터리를 찾지 못했습니다: $ProjectDir"
    Write-Host "  -ProjectDir <경로> 로 직접 지정하세요 (Claude 세션 *.jsonl이 들어 있는 폴더)."
    exit 2
}

$files = @(Get-ChildItem -LiteralPath $ProjectDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First $Sessions)

Write-Host '== require-evidence 검사 4 — transcript 스키마 가정 점검 =='
Write-Host ("대상: 최근 {0}개 세션 (요청 {1}) | 모드: {2}" -f $files.Count, $Sessions, $(if ($Quick) { 'Quick(종료 시점만)' } else { '전수 스캔' }))

if (-not $files.Count) {
    # 정보 부족은 드리프트가 아니다 — 여기서 exit 1을 내면 "새 PC라 로그가 없다"가 스키마 변경으로 둔갑한다.
    Write-Verdict -Kind SKIP -Title '전체' -Detail 'transcript 파일 0개 — 판정할 데이터가 없습니다.'
    exit 0
}

# ---- 로드 (한 번만 읽어 전 가정이 공유한다) ----
$sessionData = @()
foreach ($f in $files) {
    $lines = @()
    try { $lines = @(Get-Content -LiteralPath $f.FullName -ErrorAction Stop) } catch { continue }
    $sessionData += ,@{ name = $f.Name; lines = $lines }
}
$totalLines = ($sessionData | ForEach-Object { $_.lines.Count } | Measure-Object -Sum).Sum
Write-Host ("로드: {0}세션 / {1}줄" -f $sessionData.Count, $totalLines)
Write-Host ''

# =====================================================================
# 가정 1 — isMeta:true user 엔트리가 실재하고, 전건이 시스템 주입인가 (skip ①의 전제)
# =====================================================================
# "시스템 주입"의 기계 판정: 스킬 발동 페이로드·주입 문서는 사람이 타이핑한 발화와 길이 차이가
#   크다. 짧은 isMeta 엔트리가 나오면 사용자 발화가 그 형태로 기록되고 있을 수 있고, 그러면
#   skip ①이 **사용자 의사를 삼킨다**(이 검사에서 가장 위험한 방향).
$metaShortLimit = 300
$metaTotal = 0; $metaShort = 0
foreach ($s in $sessionData) {
    foreach ($ln in $s.lines) {
        if ($ln -notmatch '"type"\s*:\s*"user"') { continue }
        if ($ln -notmatch '"isMeta"\s*:\s*true') { continue }
        $metaTotal++
        if ($ln.Length -lt $metaShortLimit) { $metaShort++ }
    }
}
if ($metaTotal -eq 0) {
    Write-Verdict -Kind SKIP -Title '가정 1 (isMeta 주입 실재)' -Detail 'isMeta:true user 엔트리 0건 — 이 세션들엔 스킬 발동 페이로드가 없습니다.'
} elseif ($metaShort -gt 0) {
    Write-Verdict -Kind DRIFT -Title '가정 1 (isMeta 주입 실재)' -Detail "isMeta:true ${metaTotal}건 중 ${metaShort}건이 ${metaShortLimit}자 미만 — 사용자 발화가 isMeta로 기록될 가능성. skip ①이 사용자 의사를 삼킬 수 있습니다."
} else {
    Write-Verdict -Kind OK -Title '가정 1 (isMeta 주입 실재)' -Detail "isMeta:true user 엔트리 ${metaTotal}건, 전건이 ${metaShortLimit}자 이상(시스템 주입 형태)."
}

# =====================================================================
# 가정 2 — subagent 완료 알림이 `"content":"<task-notification>` 형태로 기록되는가 (skip ②의 전제)
# =====================================================================
# 판정 정규식이 **필드 시작 위치**를 보므로, 알림 리터럴은 있는데 그 형태가 아니면 skip ②가
#   무발동이 된다(형태 변경 = 조용한 드리프트).
$notifShape = 0; $notifLoose = 0
foreach ($s in $sessionData) {
    foreach ($ln in $s.lines) {
        if ($ln -notmatch '"type"\s*:\s*"user"') { continue }
        if ($ln -match '"(content|text)"\s*:\s*"<task-notification>') { $notifShape++ }
        elseif ($ln -match 'task-notification') { $notifLoose++ }
    }
}
if ($notifShape -eq 0 -and $notifLoose -eq 0) {
    Write-Verdict -Kind SKIP -Title '가정 2 (알림 형태)' -Detail '알림 엔트리 0건 — 이 세션들엔 subagent 호출이 없었습니다.'
} elseif ($notifShape -eq 0) {
    Write-Verdict -Kind DRIFT -Title '가정 2 (알림 형태)' -Detail "알림 리터럴 ${notifLoose}건이 있으나 `"content`":`"<task-notification> 형태 0건 — 판정 정규식이 놓칩니다."
} else {
    $note = if ($notifLoose) { " (그 외 위치에 리터럴만 있는 엔트리 ${notifLoose}건 — 사용자가 언급한 발화일 수 있어 제외 대상 아님)" } else { '' }
    Write-Verdict -Kind OK -Title '가정 2 (알림 형태)' -Detail "필드 시작 형태 ${notifShape}건 실재.$note"
}

# =====================================================================
# 가정 3 — assistant의 원시 `"type":"text"` 판정이 실제 텍스트 보유와 1:1인가 (skip ④의 전제)
# =====================================================================
# 어긋나는 방향이 둘이다: ⓐ 원시로는 매치되는데 실제 텍스트가 없으면 파싱 예산만 낭비(무해),
#   ⓑ 원시로는 미매치인데 실제 텍스트가 있으면 **그 엔트리가 통째로 건너뛰어진다**(유해 —
#   조건 ④ 폴백이 정지 문구를 못 본다). ⓑ가 하나라도 있으면 DRIFT다.
$asstTotal = 0; $rawMatch = 0; $mismatchHarmful = 0; $mismatchBenign = 0
foreach ($s in $sessionData) {
    foreach ($ln in $s.lines) {
        if ($ln -notmatch '"type"\s*:\s*"assistant"') { continue }
        $asstTotal++
        $raw = ($ln -match '"type"\s*:\s*"text"')
        if ($raw) { $rawMatch++ }
        $txt = ''
        try {
            $obj = $ln | ConvertFrom-Json
            $mc = $obj.message.content
            if ($null -eq $mc) { $mc = $obj.content }
            if ($mc -is [string]) { $txt = $mc }
            elseif ($mc) { $txt = ((@($mc) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n") }
        } catch { continue }
        $hasText = -not [string]::IsNullOrWhiteSpace($txt)
        if ($raw -and -not $hasText) { $mismatchBenign++ }
        if (-not $raw -and $hasText) { $mismatchHarmful++ }
    }
}
if ($asstTotal -eq 0) {
    Write-Verdict -Kind SKIP -Title '가정 3 (원시 text 판정 1:1)' -Detail 'assistant 엔트리 0건.'
} elseif ($mismatchHarmful -gt 0) {
    Write-Verdict -Kind DRIFT -Title '가정 3 (원시 text 판정 1:1)' -Detail "assistant ${asstTotal}건 중 ${mismatchHarmful}건이 '원시 미매치인데 실제 텍스트 보유' — skip ④가 정지 문구를 담은 엔트리를 건너뜁니다."
} else {
    $note = if ($mismatchBenign) { " (원시 매치인데 텍스트 없음 ${mismatchBenign}건 — 예산만 소모, 무해)" } else { '' }
    Write-Verdict -Kind OK -Title '가정 3 (원시 text 판정 1:1)' -Detail "assistant ${asstTotal}건 중 원시 매치 ${rawMatch}건, 유해 불일치 0건.$note"
}

# =====================================================================
# 가정 4 — 전 시점 스캔: 파싱 예산($parsed 200) 잔여와 userFound 손실
# =====================================================================
# require-evidence.ps1:384-451의 역순 스캔을 재현한다(안전 계약 ③ — hook 수정 시 함께 갱신).
# **전 시점**을 재는 이유: 매 turn 끝이 Stop hook 발동 지점이라, 종료 시점 하나만 재면
#   중간에 예산을 태우고 userFound를 잃은 구간을 못 본다.
function Invoke-ReverseScan {
    param([string[]]$Lines, [int]$EndIndex, [bool]$HaveStdinMsg)
    $start = [Math]::Max(0, $EndIndex - 5999)   # hook의 Get-Content -Tail 6000과 같은 창 (v1.154.0에서 3000→6000)
    $needAsst = (-not $HaveStdinMsg)
    $parsed = 0
    $userFound = $false
    $budgetHit = $false
    for ($i = $EndIndex; $i -ge $start; $i--) {
        if ($userFound -and -not $needAsst) { break }
        if ($parsed -ge 200) { $budgetHit = $true; break }
        $ln = $Lines[$i]
        $isUser = ($ln -match '"type"\s*:\s*"user"')
        $isAsst = ($ln -match '"type"\s*:\s*"assistant"')
        # user·assistant가 아닌 엔트리(system·summary 등)는 예산을 쓰지 않는다. 이 줄이 빠지면
        #   그런 엔트리가 $parsed를 소모해 **원본보다 예산을 빨리 태우고**, 가정 4가 있지도 않은
        #   예산 소진을 보고한다(과탐). skip 4종만 pin하고 이 구조 필터를 빠뜨려 실제로 겪었다.
        if (-not $isUser -and -not $isAsst) { continue }
        if ($isUser -and ($ln -match '"type"\s*:\s*"tool_result"' -or $ln -match '"tool_use_id"')) { continue }
        if ($isUser -and ($ln -match '"isMeta"\s*:\s*true')) { continue }
        if ($isUser -and ($ln -match '"(content|text)"\s*:\s*"<task-notification>')) { continue }
        if ($isAsst -and -not $needAsst) { continue }
        if ($isAsst -and ($ln -notmatch '"type"\s*:\s*"text"')) { continue }
        $parsed++
        $obj = $null
        try { $obj = $ln | ConvertFrom-Json } catch { continue }
        $mc = $obj.message.content
        if ($null -eq $mc) { $mc = $obj.content }
        $txt = ''
        if ($mc -is [string]) { $txt = $mc }
        elseif ($mc) { $txt = ((@($mc) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n") }
        if ([string]::IsNullOrWhiteSpace($txt)) { continue }
        if ($isUser -and -not $userFound) { $userFound = $true }
        elseif ($isAsst -and $needAsst) { $needAsst = $false }
    }
    return @{ parsed = $parsed; userFound = $userFound; budgetHit = $budgetHit }
}

foreach ($mode in @(@{ n = 'stdin 필드 있음'; stdin = $true }, @{ n = 'transcript 폴백'; stdin = $false })) {
    $maxParsed = 0; $points = 0; $lost = 0; $budgetLoss = 0
    foreach ($s in $sessionData) {
        $idxs = @()
        if ($Quick) {
            if ($s.lines.Count) { $idxs = @($s.lines.Count - 1) }
        } else {
            # Stop hook은 assistant turn 끝에서 돈다 — 그 위치들만 발동 시점으로 잡는다.
            for ($i = 0; $i -lt $s.lines.Count; $i++) {
                if ($s.lines[$i] -match '"type"\s*:\s*"assistant"') { $idxs += $i }
            }
        }
        foreach ($ix in $idxs) {
            $r = Invoke-ReverseScan -Lines $s.lines -EndIndex $ix -HaveStdinMsg $mode.stdin
            $points++
            if ($r.parsed -gt $maxParsed) { $maxParsed = $r.parsed }
            if (-not $r.userFound) {
                $lost++
                # 예산이 먼저 소진돼 못 찾은 것만 skip의 책임이다.
                if ($r.budgetHit) { $budgetLoss++ }
            }
        }
    }
    if ($points -eq 0) {
        Write-Verdict -Kind SKIP -Title "가정 4 ($($mode.n))" -Detail '재현할 발동 시점이 없습니다.'
        continue
    }
    # 판정 기준은 "상한 도달"이 아니라 **"예산이 먼저 소진돼 사용자 발화를 놓쳤는가"** 다.
    #   200번째 파싱에서 발화를 찾은 시점도 최댓값은 200이지만 손실이 없으므로 결함이 아니다
    #   (도달만으로 DRIFT를 내면 도구가 거짓 경보를 내고, 거짓 경보를 내는 점검은 다음에 무시된다).
    #   반대로 손실 자체도 전부 결함은 아니다 — 세션 초반이라 창 안에 사용자 발화가 아직 없는
    #   경우가 있고, 그건 skip이 아니라 데이터의 사정이다.
    if ($budgetLoss -gt 0) {
        Write-Verdict -Kind DRIFT -Title "가정 4 ($($mode.n))" -Detail "발동 시점 ${points}개 중 ${budgetLoss}개에서 파싱 예산(200)이 먼저 소진돼 사용자 발화를 놓쳤습니다 — skip 4종이 예산을 못 지키고 있습니다(파싱 최댓값 ${maxParsed})."
    } else {
        $lostNote = if ($lost) { " (전부 예산 밖 사유 — 창 안에 사용자 발화가 없는 세션 초반 등)" } else { '' }
        Write-Verdict -Kind OK -Title "가정 4 ($($mode.n))" -Detail "발동 시점 ${points}개 · 파싱 최댓값 ${maxParsed}/200 · 예산 소진으로 인한 발화 손실 0건 · 전체 손실 ${lost}건.$lostNote"
    }
}

# =====================================================================
# 가정 5 — 재현 로직 pin: 예산에 관여하는 판정식이 hook 소스에 그대로 실재하는가
# =====================================================================
# 위 재현(Invoke-ReverseScan)은 hook의 사본이라 원본이 바뀌면 조용히 어긋난다. 판정식 리터럴을
#   직접 대조해, 하나라도 사라졌으면 이 스크립트 자체를 갱신하라는 신호를 낸다.
# pin 대상은 "skip 4종"이 아니라 **$parsed 예산에 관여하는 판정식 전부**다 — 구조 필터(user·assistant
#   아닌 엔트리 제외)가 빠진 재현은 예산을 원본보다 빨리 태워 없는 결함을 보고했고(초안이 실제로 그랬다),
#   반대로 tool_result 제외가 원본에서 사라지면 재현만 계속 걸러 **원본보다 적게 재어 드리프트를 놓친다**.
#   어긋남은 양방향이므로 한쪽만 pin하면 반쪽짜리다.
$skipPins = @(
    @{ n = '구조 필터 user/assistant'; lit = 'if (-not $isUser -and -not $isAsst) { continue }' },
    @{ n = 'tool_result 제외';         lit = '($ln -match ''"type"\s*:\s*"tool_result"'' -or $ln -match ''"tool_use_id"'')' },
    @{ n = 'skip ① isMeta';           lit = '($ln -match ''"isMeta"\s*:\s*true'')' },
    @{ n = 'skip ② task-notification'; lit = '($ln -match ''"(content|text)"\s*:\s*"<task-notification>'')' },
    @{ n = 'skip ③ needAsst';          lit = 'if ($isAsst -and -not $needAsst) { continue }' },
    @{ n = 'skip ④ type:text';         lit = '($ln -notmatch ''"type"\s*:\s*"text"'')' }
)
if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) {
    Write-Verdict -Kind DRIFT -Title '가정 5 (재현 pin)' -Detail "hook 소스를 찾지 못했습니다: scripts/require-evidence.ps1"
} else {
    $hookSrc = Get-Content -LiteralPath $hookPath -Raw
    $missing = @($skipPins | Where-Object { -not $hookSrc.Contains($_.lit) } | ForEach-Object { $_.n })
    if ($missing.Count) {
        Write-Verdict -Kind DRIFT -Title '가정 5 (재현 pin)' -Detail "판정식이 사라졌습니다: $($missing -join ', ') — 이 스크립트의 Invoke-ReverseScan을 함께 갱신하세요."
    } else {
        Write-Verdict -Kind OK -Title '가정 5 (재현 pin)' -Detail "예산 관여 판정식 $($skipPins.Count)종(구조 필터 · tool_result · skip ①~④) 전건 실재 — 재현 로직이 원본과 일치합니다."
    }
}

Write-Host ''
if ($drift) {
    Write-Host "결과: DRIFT ${drift}건 — 스키마가 바뀌었거나 skip이 제 일을 못 하고 있습니다."
    exit 1
}
Write-Host '결과: 전건 OK (또는 판정 데이터 부족으로 SKIP).'
exit 0
