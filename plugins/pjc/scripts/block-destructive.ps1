# PreToolUse hook — Bash/PowerShell 도구 호출 시 파괴적 명령 차단 (exit 2 = block)
#
# 이 스크립트는 **판정 로직만** 담는다. 무엇을 차단하는가(정규식)는 `rules/destructive.json`이,
#   그 정규식이 그 모양인 이유는 `rules/destructive-rationale.md`가 정본이다.
#   셋을 함께 고친다 — 정규식만 바꾸고 근거 문서를 두면 다음 회차가 낡은 근거를 따른다.
#
# ⚠️ 이 hook은 항상 동작한다 (끌 수 없음). CLAUDE_HARNESS_QUICK도 무시한다.
#   파괴적 명령 차단은 마지막 방어선이라 우회 경로를 두지 않는다.

$ErrorActionPreference = 'Stop'

# 한글 차단 사유가 cp949 콘솔에서 깨지지 않도록 (Claude Code는 hook 입출력을 UTF-8로 다룬다)
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
} catch {
    exit 0   # 파싱 실패는 통과 — 차단 실패가 더 위험하다
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# ---- 규칙 로드 ----
# 로드 실패는 차단을 못 하는 상태이므로 조용히 통과하지 않고 stderr로 알린다(fail-open + 가시화).
try {
    $rules = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rules/destructive.json') -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine("block-destructive: 규칙 파일을 읽지 못해 검사를 건너뜁니다 — rules/destructive.json")
    exit 0
}
$dangerTarget    = $rules.dangerTarget
$delCmdAlt       = $rules.delCmdAlt
$findDangerRoot  = $rules.findDangerRoot
$enumSource      = $rules.enumSource
$delRecurseForce = $rules.delRecurseForce
$patterns = @($rules.patterns | ForEach-Object { $_.rx -replace '\{dangerTarget\}', $dangerTarget })

# ---- 이벤트 로깅 (판정에 영향 없음 — 마지막 방어선에 결합하지 않도록 전면 격리) ----
try { . (Join-Path $PSScriptRoot 'hook-event-log.ps1') } catch {}
function Write-BdEvent {
    param([string]$Rule, [string]$CmdText)
    try {
        if (Get-Command Write-HookEvent -ErrorAction SilentlyContinue) {
            Write-HookEvent 'block-destructive' 'block' $Rule $CmdText
        }
    } catch {}
}
function Deny {
    param([string]$Reason, [string]$Rule, [string]$Shown)
    [Console]::Error.WriteLine("BLOCKED: $Reason")
    [Console]::Error.WriteLine("Command: $Shown")
    [Console]::Error.WriteLine("필요하다면 사용자에게 명시적 확인을 받은 뒤 직접 실행하도록 보고하세요.")
    Write-BdEvent $Rule $Shown
    exit 2
}

# ---- heredoc 파일-리다이렉트 본문 스트립 ----
# 데이터-싱크(cat + '>' 리다이렉트 · tee)로 가는 heredoc 본문은 기록될 데이터라 실행되지 않는다.
#   실행자(bash·psql 등)로 가는 본문은 보존한다 — 허용목록 방식이라 모르는 명령은 보존이 기본이다.
$heredocRx = '(?m)^(?<line>[^\r\n]*<<-?\s*(?<q>["'']?)(?<tag>\w+)\k<q>[^\r\n]*)\r?\n(?<body>[\s\S]*?)\r?\n[ \t]*\k<tag>[ \t]*(?=\r?\n|$)'
$cmd = [regex]::Replace($cmd, $heredocRx, {
    param($m)
    $line = $m.Groups['line'].Value
    $isDataSink = ($line -match '(?i)^\s*cat\b' -and $line -match '>\s*\S') -or ($line -match '(?i)^\s*tee\b')
    if ($isDataSink) { $line } else { $m.Value }
})

# ---- Join-Path 정규화 ----
# $dangerTarget은 경로가 한 토큰이라고 전제하는데 Join-Path는 루트와 하위를 분리된 인자로 쪼갠다.
#   조합 결과를 문자열 형태로 되돌려 표기법에 따라 판정이 갈리는 비대칭을 없앤다.
#   구분자 \·/ 두 표기를 각각 만들어 어느 쪽이든 위험하면 차단한다(POSIX 알터네이션은 /만 받는다).
$joinPathTok = '"[^"]*"|''[^'']*''|[^\s()]+'
$joinPathRx  = '(?i)\(\s*Join-Path\s+(?:-Path\s+)?(?<a>' + $joinPathTok + ')\s+(?:-ChildPath\s+)?(?<b>' + $joinPathTok + ')\s*\)'
function Expand-JoinPath {
    param([string]$Text, [string]$Sep)
    [regex]::Replace($Text, $joinPathRx, {
        param($m)
        $a = $m.Groups['a'].Value.Trim('"', "'")
        $b = $m.Groups['b'].Value.Trim('"', "'")
        $plainChild = ($b -match '^[A-Za-z0-9_]') -and ($b -notmatch '[*?]') -and ($b -notmatch '(^|[\\/])\.\.([\\/]|$)')
        $plainRoot  = ($a -notmatch '[*?]')
        if (-not ($plainChild -and $plainRoot)) { return $m.Value }   # 미조인은 항상 안전한 쪽(현행 차단 유지)
        $joined = if ($a -match '[\\/]$') { $a + $b } else { $a + $Sep + $b }
        ' "' + $joined + '" '
    })
}
function Test-DangerTarget {
    param([string]$Text)
    ((Expand-JoinPath $Text '\') -match $dangerTarget) -or ((Expand-JoinPath $Text '/') -match $dangerTarget)
}

# ---- 사전검사 ① find로 위험 루트를 훑어 삭제 ----
# Split-TopLevel이 파이프로 쪼개면 삭제 sub에 대상 토큰이 없어(대상은 find가 stdin으로 공급)
#   아래 컴파운드 검사를 빠져나간다 → 전체 $cmd에서 직접 차단한다.
if ($cmd -match $findDangerRoot -and (
        ($cmd -match ('(?i)\|\s*xargs\b[^|]*\b(' + $delCmdAlt + ')\b')) -or
        ($cmd -match '(?i)-exec(dir)?\s+(rm|Remove-Item)\b') -or
        ($cmd -match '(?i)\bfind\b[^|]*\s-delete\b'))) {
    Deny "위험 루트(/, ~, `$HOME, 드라이브 루트)를 find로 훑어 삭제(xargs rm / -exec rm / -delete) 감지" 'find 위험루트 삭제' $cmd
}

# ---- 사전검사 ② 열거 명령으로 위험 루트를 훑어 삭제로 파이프 ----
# 위험 판정은 첫 파이프 앞(열거 소스 인자)에만 적용한다 — 상대경로·사용자 하위 2단계+는 통과.
#   이름 필터가 있는 선택적 열거만 .·./ 를 위험대상에서 뺀다(무차별 열거 삭제는 rm -rf ./* 등가).
$pipeToDelete = '(?i)\|\s*[^|]*\b(' + $delCmdAlt + ')\b'
$pipeXargsRm  = '(?i)\|\s*xargs\b[^|]*\b(' + $delCmdAlt + ')\b'
$beforePipe = ($cmd -split '\|', 2)[0]
$hasNameFilter = $beforePipe -match '(?i)\s-(Filter|Include|Exclude|i?name)\b'
$enumSrcScan = if ($hasNameFilter) { $beforePipe -replace '(^|\s)\.[\\/]?(?=\s|$)', ' ' } else { $beforePipe }
if (($beforePipe -match $enumSource) -and (Test-DangerTarget $enumSrcScan) -and (
        (($cmd -match $pipeToDelete) -and ($cmd -match $delRecurseForce)) -or
        ($cmd -match $pipeXargsRm))) {
    Deny "위험 루트를 열거 명령으로 훑어 삭제로 파이프(Get-ChildItem/ls/dir | Remove-Item/rm) 감지" '열거 파이프 삭제' $cmd
}

# ---- 최상위 구분자 분리 (따옴표 인식) ----
# 단순 -split는 따옴표 안의 구분자에서 쪼개 인용이 깨지고, 그러면 데이터 인자 제거가 작동하지 않아
#   오탐이 난다. 개행도 최상위 구분자다 — 아니면 둘째 줄의 파괴 명령이 ^앵커 패턴을 벗어난다.
function Split-TopLevel([string]$s) {
    $parts = New-Object System.Collections.Generic.List[string]
    $cur = ''
    $q = $null
    $chars = $s.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]
        if ($q -eq "'") {
            # 작은따옴표 안은 bash에서 이스케이프가 없다 — 다음 ' 까지 전부 리터럴
            $cur += $ch
            if ($ch -eq "'") { $q = $null }
        } elseif ($q -eq '"') {
            if ($ch -eq '\' -and $i + 1 -lt $chars.Length) {
                $cur += $ch; $cur += $chars[$i + 1]; $i++
            } else {
                $cur += $ch
                if ($ch -eq '"') { $q = $null }
            }
        } else {
            # 인용 밖 백슬래시도 다음 문자를 이스케이프한다 — \" 가 인용을 열어 구분자 분리를 깨뜨리던 미탐 방어
            if ($ch -eq '\' -and $i + 1 -lt $chars.Length) {
                $cur += $ch; $cur += $chars[$i + 1]; $i++
            } elseif ($ch -eq '"' -or $ch -eq "'") {
                $q = $ch; $cur += $ch
            } elseif ($ch -eq ';' -or $ch -eq '|' -or $ch -eq '&' -or $ch -eq "`n" -or $ch -eq "`r") {
                $parts.Add($cur); $cur = ''
            } else {
                $cur += $ch
            }
        }
    }
    $parts.Add($cur)
    return $parts
}

# 줄-이음(백틱/백슬래시 '직후' 개행만)은 셸이 한 명령으로 잇는다 — 분리 전에 합쳐 미탐을 막는다.
#   \s*를 넣지 않는 이유: '\ <개행>'은 줄-이음이 아니라 이스케이프된 공백 + 종결 개행이다.
$cmdJoined = $cmd -replace '`\r?\n', ' '
$cmdJoined = $cmdJoined -replace '\\\r?\n', ' '
$subs = Split-TopLevel $cmdJoined

foreach ($sub in $subs) {
    $sub = $sub.Trim()
    if ([string]::IsNullOrWhiteSpace($sub)) { continue }

    # ---- 데이터 인자 스트립 ----
    # git 커밋 메시지·echo/printf 출력·grep 패턴·sed/awk 스크립트·Set-Content -Value는 실행되지 않는
    #   텍스트다. 반대로 psql·bash -c·eval 등 실행자의 따옴표 내용은 실제 실행되므로 보존한다.
    $scan = $sub
    if ($scan -match '(?i)(^|\s)git(\s|$)') {
        $scan = $scan -replace '(?i)(^|\s)(-[a-z]*m|--message)(=|\s+)("[^"]*"|''[^'']*''|\S+)', ' '
    }
    if ($scan -match '(?i)(^|\s)(echo|printf)(\s|$)') {
        $scan = $scan -replace '(?i)(^|\s)(echo|printf)\b.*$', ' '
    }
    if ($scan -match '(?i)(^|\s)(grep|egrep|fgrep|rg|ag|ack|sed|awk)(\s|$)') {
        $scan = ($scan -replace '"[^"]*"', ' ') -replace "'[^']*'", ' '
    }
    if ($scan -match '(?i)(^|\s)(Set-Content|Add-Content|Out-File)(\s|$)') {
        $scan = $scan -replace '(?i)(^|\s)-Value(\s+|:)("[^"]*"|''[^'']*'')', ' '
    }

    # ---- 컴파운드 검사: 재귀 삭제 + 위험 루트 ----
    # 강제 플래그는 요구하지 않는다 — 위험루트 재귀 삭제는 -f 없이도 비가역이다.
    # 앞 경계에 ["'\] 를 넣는 이유: 인터프리터 문자열 안 삭제(bash -c "rm -rf /")와 별칭 우회(\rm)가
    #   (^|\s)만으로는 미탐이었다. 뒤 경계 (\s|$)는 넓히지 않는다 — 오탐 표면만 늘고 실익이 없다.
    $norm = $scan -replace '`\r?\n', ' '
    $norm = $norm -replace '\\\r?\n', ' '
    $delMatches = [regex]::Matches($norm, '(?i)(^|\s|["''\\])(' + $delCmdAlt + ')(\s|$)')
    foreach ($dm in $delMatches) {
        # git rm 제외 — git 인덱스가 추적해 git restore로 복구 가능한 비파괴 작업이다
        if ($dm.Groups[2].Value -ieq 'rm' -and
            $norm.Substring(0, $dm.Index + $dm.Groups[1].Length) -match '(?i)(^|[\s;&|])git\s+((-c|-C)\s+\S+\s+)*$') { continue }
        # 삭제 명령 토큰부터 다음 줄바꿈 전까지가 그 명령의 인자 윈도우
        $win = $norm.Substring($dm.Index).TrimStart()
        $nlIdx = $win.IndexOfAny([char[]]@("`n", "`r"))
        if ($nlIdx -ge 0) { $win = $win.Substring(0, $nlIdx) }

        $hasRecurse = ($win -match '(^|\s)-[rfRF]*r[rfRF]*(\s|$)') -or
                      ($win -match '(^|\s)-Recurse\b') -or
                      ($win -match '(^|\s)-(?!replace\b)[rR]e[a-z]*(\s|$)') -or
                      ($win -match '--recursive\b') -or
                      ($win -match '\s/s\b')
        if ($hasRecurse -and (Test-DangerTarget $win)) {
            Deny "재귀 삭제 + 위험 루트 대상 감지" '재귀 삭제 + 위험 루트' $sub
        }
    }

    foreach ($pattern in $patterns) {
        if ($scan -match $pattern) {
            Deny "파괴적 명령 패턴 감지: '$pattern'" "패턴: $pattern" $sub
        }
    }
}

exit 0
