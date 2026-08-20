# eval-common.ps1 — 골든 러너 공용 격리 구성 + 헬퍼 (dot-source 전용, 단독 실행 금지)
#
# 무엇을: `run-hook-evals.ps1`(코디네이터)과 `run-scenario.ps1`(자식)이 **같은 정의를 공유**하도록
#   격리 환경 구성·공용 헬퍼·공유 픽스처를 한 곳에 모았다. v1.159.0 병렬화 전에는 이 내용이
#   run-hook-evals.ps1 본체에 있었고, 자식 프로세스를 도입하면서 복제하지 않고 추출했다 —
#   두 벌이 되면 갈리고, 갈린 쪽이 어느 케이스를 다르게 판정하는지 아무도 모른다.
#
# 호출자가 dot-source 전에 설정할 수 있는 입력(전부 선택):
#   $EvalFilter      [string[]] 부분 실행 필터(hook 기본명). 미설정이면 전체 실행.
#   $EvalOutJson     [string]   케이스 판정을 JSON 라인으로 append할 경로. 설정 시 증분 기록이 켜진다.
#   $EvalHomeSuffix  [string]   격리 홈·작업 폴더 이름의 접미. 병렬 자식이 서로 다른 값을 줘야 한다.
#
# 판정 출력은 이 파일이 하지 않는다 — 호출자가 $results를 받아 출력한다(종전 동작 보존).
#
# 정리는 호출자 책임이다 — 이 파일은 $EvalIso·$EvalWork를 만들고 경로를 노출하며,
#   지우는 시점은 호출자가 정한다(자식은 자기 것만, 코디네이터는 자기 것만).

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$evalsDir   = $PSScriptRoot
$pluginRoot = Split-Path (Split-Path $evalsDir -Parent) -Parent   # plugins/pjc
$scriptsDir = Join-Path $pluginRoot 'scripts'
$casesPath  = Join-Path $evalsDir 'hook-cases.json'

# ---- 실제 홈 보관 (테스트는 USERPROFILE을 격리 홈으로 바꾸므로 종료 시 원복용) ----
$realHome = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }

# ---- 세션 환경 오염 차단 ----
# CLAUDE_HARNESS_ALLOW_SECRET=1 세션에서 전체 실행하면 warn-commit-secrets의 차단 기대 케이스가
# 우회 완화되어 **거짓 FAIL 4건**이 난다(2026-07-23 실측 401/405). 자식 프로세스는 이 변수를
# 상속하므로 병렬화로 상속 경로가 넓어졌다 — 여기서 한 번 지워 모든 경로를 닫는다.
$env:CLAUDE_HARNESS_ALLOW_SECRET = $null

# 고아 프로세스 회수의 **실기계 수집 경로**를 끈다(D11). 골든은 hook .ps1을 실기계에서 돌리는데
# 프로세스는 격리 대상이 아니라(위 홈 격리는 USERPROFILE만 바꾼다) 억제가 없으면 스위트가 실제
# 프로세스를 죽이고 그 상태 변화가 판정에 섞인다. 목 레코드 주입(-Records)은 억제 대상이 아니므로
# 회수 로직 자체는 그대로 검증된다.
$env:CLAUDE_HARNESS_NO_PROC_CLEANUP = '1'

# ---- 격리 환경 구성 ----
# 홈 격리($EvalIso)는 임시 폴더에 둬도 되지만, 시나리오 프로젝트($EvalWork)는 반드시 임시 폴더 '밖'이어야
# 한다 — require-plan-for-write가 시스템 임시 폴더 하위를 무조건 통과시키므로(H3 의도된 완화),
# 픽스처가 temp 안에 있으면 차단 시나리오 전체가 우회로 무력화된다.
$suffix = if ($EvalHomeSuffix) { $EvalHomeSuffix } else { [guid]::NewGuid().ToString('N').Substring(0, 8) }
$EvalIso = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-" + $suffix)
$workBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $realHome }   # 비Windows 폴백
$EvalWork = Join-Path $workBase ("pjc-hook-evals-" + $suffix)
New-Item -ItemType Directory -Path $EvalIso -Force | Out-Null
New-Item -ItemType Directory -Path $EvalWork -Force | Out-Null
$env:USERPROFILE = $EvalIso        # 자식 hook 프로세스가 이 격리 홈의 .claude를 보게 함(.state 마커 등)
$env:CLAUDE_PROJECT_DIR = $null
Set-Location $EvalWork             # 중립 cwd — hook의 (Get-Location) 폴백이 레포 plan.md를 줍지 않게

# 시나리오가 직접 참조하는 이름(추출 전과 동일하게 유지 — 시나리오 14개를 수정하지 않기 위함)
$iso  = $EvalIso
$work = $EvalWork

$results = New-Object System.Collections.Generic.List[object]

# ---- -Filter 정규화 + 섹션 선택 헬퍼 ----
# 섹션 태그 원칙: 각 시나리오 섹션은 자기가 실행하는 hook 전부를 태그로 갖고, 필터에 하나라도
# 걸리면 섹션 전체를 실행한다(소량 초과 실행 허용 — 케이스 단위 정밀 필터보다 구조 단순 우선).
# 이름 목록·정규화 규칙의 정본은 `filter-spec.ps1` — 복제하면 정규화가 갈릴 때 코디네이터의
# `-Resume` 스코프 키와 실제 게이트가 어긋난다(서로 다른 필터가 같은 스코프로 매핑되는 경로).
. (Join-Path $evalsDir 'filter-spec.ps1')

$script:FilterSet = Get-NormalizedFilter -Filter $EvalFilter
if ($script:FilterSet) { Write-UnknownFilterWarning -NormalizedFilter $script:FilterSet }

function Test-HookSelected {
    # $Hooks: 이 케이스/섹션이 실행하는 hook 기본명 목록. 필터 미지정이면 항상 실행.
    param([string[]]$Hooks)
    if (-not $script:FilterSet) { return $true }
    foreach ($h in $Hooks) {
        if ($script:FilterSet -contains $h.ToLowerInvariant()) { return $true }
    }
    return $false
}

# ---- 크로스섹션 공유 정의 (필터 게이트 밖 — 반드시 top-level) ----
# 섹션 게이트가 어떤 조합으로 건너뛰어도 후속 섹션이 깨지지 않도록, 둘 이상의 섹션이 쓰는
# 변수·함수·픽스처는 여기서 무조건 정의한다. 특히 $gitOk는 게이트로 건너뛰면 오류 없이
# falsy가 되어 §7 impact·§9가 침묵 skip되는 사각이므로(plan-reviewer M1) top-level 고정.
$gitOk = $null -ne (Get-Command git -ErrorAction SilentlyContinue)   # §4·§7·§9 게이트
$pw = Join-Path $work 'pwproj'; New-Item -ItemType Directory $pw -Force | Out-Null   # §6·§7 후속·Pre.cs 픽스처
$vdCache = Join-Path $iso '.claude/plugins/cache/pjc-harness/pjc/1.0.0/scripts'      # §10 개조 차단·§11(d) 경로

function New-WriteJson([string]$cwd, [string]$file, [string]$tool = 'Write', [hashtable]$extra = @{}, [hashtable]$top = @{}) {
    # §2 require-plan·§2b protect-harness·§6 post-write 등 다수 섹션 공용
    # $top: tool_input이 아니라 stdin JSON 최상위에 병합할 필드 (예: transcript_path — AGENTS 게이트)
    $ti = @{ file_path = $file; content = 'class A {}' } + $extra
    return ((@{ tool_name = $tool; cwd = $cwd; tool_input = $ti } + $top) | ConvertTo-Json -Compress)
}

function New-CommitJson([string]$cwd, [string]$msg) {
    # §8 rtc·§8b dispatch 동등성 공용
    return (@{ tool_name = 'Bash'; cwd = $cwd; tool_input = @{ command = "git commit -m `"$msg`"" } } | ConvertTo-Json -Compress)
}

function New-TranscriptLine {
    # transcript JSONL 한 줄을 만든다(§4 폴백·게이트 픽스처 공용).
    # 왜 헬퍼인가: 값을 문자열 이어붙이기로 끼우면 따옴표·백슬래시가 든 텍스트에서 JSON이
    #   조용히 깨진다 — 깨진 픽스처는 hook이 파싱에 실패해도 그냥 미차단으로 통과하므로
    #   그 케이스가 무엇을 검증하는지 알 수 없게 된다. 이스케이프를 ConvertTo-Json에 맡긴다.
    # [ordered]와 -Depth 10은 장식이 아니다: 일반 해시테이블은 키 순서가 보장되지 않고 기본
    #   Depth 2는 중첩 content[{type,text}]를 잘라내, 둘 중 하나만 빠져도 기존 리터럴과의
    #   문자열 동일성이 깨진다(전환 등가성의 성립 조건).
    # isMeta·tool_use 형태는 인자로 받지 않는다 — 이번에 전환한 3곳이 쓰지 않아서다.
    #   그 형태의 픽스처를 전환할 때 파라미터를 함께 추가한다.
    param(
        [ValidateSet('user', 'assistant')][string]$Type,
        [string]$Text
    )
    # 두 형태를 변수 하나로 합치지 않는다: 배열을 변수에 담아 넘기면 단일 요소가 언랩되어
    #   content가 `[{...}]`가 아니라 `{...}`로 직렬화된다(실측). hook은 @()로 감싸 읽어서
    #   골든은 green이지만 기존 리터럴과의 문자열 동일성은 그 자리에서 깨진다.
    if ($Type -eq 'assistant') {
        $entry = [ordered]@{ type = 'assistant'; message = [ordered]@{ content = @([ordered]@{ type = 'text'; text = $Text }) } }
    } else {
        $entry = [ordered]@{ type = 'user'; message = [ordered]@{ content = $Text } }
    }
    return ($entry | ConvertTo-Json -Compress -Depth 10)
}

function Invoke-Hook {
    param([string]$ScriptName, [string]$InputJson)
    # 자식 프로세스 출력을 **UTF-8로 디코딩**한다(v1.182.0). `2>&1`이 stderr를 이미 $R.out에
    #   합치지만, 콘솔 코드페이지가 UTF-8이 아닌 기동 경로(러너는 Start-Process로 새 콘솔에서
    #   뜬다 — 실측 ks_c_5601-1987)에서는 hook의 한글 경고가 `?패`처럼 깨져 들어와
    #   `expect_contains`로 assert할 수 없었다. 영문 앵커만 걸 수 있던 것이 그 때문이다.
    #   실측: 같은 경로에서 한글 앵커 매칭 False → 이 설정 후 True(영문 앵커는 양쪽 다 True).
    # 진입부가 아니라 **이 함수**에 두는 이유는 자식을 띄우는 유일한 자리이고, 러너가 시나리오를
    #   병렬 자식 프로세스로 나눠 돌아 진입부 설정의 상속이 환경 의존이기 때문이다.
    #   프로세스당 1회만 설정한다 — 이 setter는 스트림을 다시 여는 비용이 있어 호출마다 켰다
    #   껐다 하면 케이스 수만큼 그 비용이 붙는다. 실패해도 종전 동작을 유지하도록 감싼다.
    if (-not $script:hookOutEncFixed) {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
        $script:hookOutEncFixed = $true
    }
    $path = Join-Path $scriptsDir $ScriptName
    $out = $InputJson | pwsh -NoProfile -ExecutionPolicy Bypass -File $path 2>&1
    return @{ code = $LASTEXITCODE; out = (($out | Out-String)).Trim() }
}

function Assert-Case {
    param(
        [string]$Name, [hashtable]$R,
        [int]$ExpectExit = 0, [string]$ExpectContains = '', [bool]$ExpectSilent = $false,
        [string]$ExpectNotContains = '', [bool]$PendingFix = $false
    )
    $green = ($R.code -eq $ExpectExit)
    if ($green -and $ExpectContains) { $green = ($R.out -match [regex]::Escape($ExpectContains)) }
    # ExpectContains와 대칭 — 지정 시 해당 문자열이 출력에 '없어야' green (기본값 ''이면 미발동, 기존 호출 무영향)
    if ($green -and $ExpectNotContains) { $green = -not ($R.out -match [regex]::Escape($ExpectNotContains)) }
    if ($green -and $ExpectSilent)   { $green = [string]::IsNullOrWhiteSpace($R.out) }

    if ($PendingFix) {
        if ($green) {
            Add-EvalResult $false "[FAIL] $Name — pending_fix인데 이미 green(마킹 제거 필요: stale)" $Name
        } else {
            Add-EvalResult $true "[PENDING] $Name — red 기대대로 (수정 task 완료 시 마킹 제거)" $Name
        }
        return
    }
    if ($green) {
        Add-EvalResult $true "[PASS] $Name" $Name
    } else {
        $detail = "exit $($R.code) (기대 $ExpectExit)"
        if ($ExpectContains) { $detail += ", 기대 키워드 '$ExpectContains'" }
        if ($ExpectNotContains) { $detail += ", 미포함 기대 '$ExpectNotContains'" }
        if ($ExpectSilent)   { $detail += ", 무출력 기대" }
        $head = ($R.out -split "`r?`n" | Select-Object -First 2) -join ' / '
        Add-EvalResult $false "[FAIL] $Name — $detail | 출력: $head" $Name
    }
}

function Add-EvalResult {
    # 판정 1건을 누적하고, $EvalOutJson이 설정돼 있으면 **즉시 파일에 append**한다.
    # 증분 기록이 필요한 이유: 종전 러너는 결과를 메모리에만 모아 맨 끝에 일괄 출력했고,
    #   30분대 실행이 중단·kill되면 그때까지의 판정이 통째로 사라져 재실행이 곧 전량 재소요였다
    #   (백그라운드 kill로 프로세스가 동반 사망한 것이 2회 관측됐다).
    # **화면 출력은 하지 않는다** — 종전 러너가 판정을 메모리에 모아 맨 끝에 일괄 출력하는 동작을
    #   그대로 보존한다(`docs/harness-conventions.md` 「골든 러너 운용」의 "실행 중 파일은 START 마커 +
    #   헤더뿐"이 이 동작을 전제한다 — v1.159.0 T7이 그 서술을 AGENTS.md에서 그 문서로 옮겼다).
    #   출력 시점을 바꾸면 순차·병렬 등가 대조에서 형식이 어긋난다.
    param([bool]$Ok, [string]$Line, [string]$Name)
    $script:results.Add(@{ ok = $Ok; line = $Line })
    if ($EvalOutJson) {
        # 판정 문자열(line)을 그대로 싣는다 — 코디네이터가 종전과 같은 화면 출력을 재현할 수 있어야 한다.
        $rec = [ordered]@{ ok = $Ok; line = $Line; name = $Name; scenario = $script:EvalCurrentScenario }
        Add-Content -LiteralPath $EvalOutJson -Value ($rec | ConvertTo-Json -Compress) -Encoding utf8NoBOM
    }
}
