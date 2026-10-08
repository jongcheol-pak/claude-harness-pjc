# loop-continue.ps1 — 자율 루프가 plan 미완 task 를 남기고 멈추면 계속을 주입한다 — 근거는 `rules/loop-continue-rationale.md`의 「§1 담당 조항과 설계」

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$base = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$stateDir = Join-Path $base '.claude/.state/loop-continue'
# 같은 미완 집합에 주입하는 횟수의 상한 — 근거는 `rules/loop-continue-rationale.md`의 「§2 주입 조건과 상한」
$MaxPerSet = 2
$ImplementRx = '^(pjc:)?implement$'
$PlanRx = '^(pjc:)?plan$'

# 판정 불가는 전부 침묵이다 — 근거는 `rules/loop-continue-rationale.md`의 「§3 fail-open 은 침묵이다」
try { $data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
if (-not $data) { exit 0 }
$sid = [string]$data.session_id
if ([string]::IsNullOrWhiteSpace($sid)) { exit 0 }
$sidSafe = $sid -replace '[^A-Za-z0-9._-]', '_'
$marker = Join-Path $stateDir ($sidSafe + '.active')

function Set-ActiveMarker {
    try { New-Item -Force -ItemType Directory -Path $stateDir -ErrorAction Stop | Out-Null } catch { return }
    try { Set-Content -LiteralPath $marker -Value (Get-Date -Format o) -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Clear-ActiveMarker {
    try { Remove-Item -LiteralPath $marker -Force -ErrorAction Stop } catch {}
}

# plan 탐색과 미완 판정식 — session-context.ps1 과 같은 글자의 사본이다 — 근거는 `rules/loop-continue-rationale.md`의 「§4 미완 판정식과 plan 탐색」
$planBulletRx = '(?m)^\s*([-*+]|\d+[.)])\s*'
function Find-PlanFileUpwards([string]$StartDir, [int]$MaxDepth = 8) {
    if ([string]::IsNullOrEmpty($StartDir)) { return $null }
    $base = [System.IO.Path]::GetFullPath($StartDir).TrimEnd('\', '/')
    $dir = $base
    for ($i = 0; $i -lt $MaxDepth; $i++) {
        if (-not $dir) { break }
        foreach ($cand in @('plan.md', 'PLAN.md', 'docs/plan.md')) {
            $pf = Join-Path $dir $cand
            if (Test-Path -LiteralPath $pf -PathType Leaf) {
                $label = if ($dir -eq $base) { $cand } else { $pf }
                return @{ Path = $pf; Label = $label }
            }
        }
        if ((Test-Path -LiteralPath (Join-Path $dir '.git')) -or
            (Test-Path -LiteralPath (Join-Path $dir '.claude') -PathType Container)) {
            return $null
        }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-OpenTaskIds([string]$planText) {
    $ms = [regex]::Matches($planText, $planBulletRx + '\[[ /]\][ \t]*\**(?<id>T\d+(?:-\d+)?)')
    return @($ms | ForEach-Object { $_.Groups['id'].Value })
}

function Get-SetKey([string[]]$ids) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($ids -join ',')))
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)
}

$hookEvent = [string]$data.hook_event_name

# 발동 마커는 Skill 도구 호출과 슬래시 직접 입력 두 경로에서 선다 — 근거는 `rules/loop-continue-rationale.md`의 「§6 발동 마커의 두 경로」
if ($hookEvent -eq 'PreToolUse') {
    if ([string]$data.tool_name -ne 'Skill') { exit 0 }
    $skill = [string]$data.tool_input.skill
    if ($skill -match $ImplementRx) { Set-ActiveMarker }
    elseif ($skill -match $PlanRx) { Clear-ActiveMarker }
    exit 0
}
if ($hookEvent -eq 'UserPromptExpansion') {
    $cmdName = [string]$data.command_name
    if ($cmdName -match $ImplementRx) { Set-ActiveMarker }
    elseif ($cmdName -match $PlanRx) { Clear-ActiveMarker }
    exit 0
}
if ($hookEvent -ne 'Stop') { exit 0 }

if (-not (Test-Path -LiteralPath $marker)) { exit 0 }
if ($data.stop_hook_active -eq $true) { exit 0 }
$bg = @($data.background_tasks | Where-Object { $_ })
if ($bg.Count -gt 0) { exit 0 }

$cwd = [string]$data.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { exit 0 }
$planHit = Find-PlanFileUpwards -StartDir $cwd
if (-not $planHit) { exit 0 }
try { $planText = Get-Content -LiteralPath $planHit.Path -Raw -Encoding UTF8 -ErrorAction Stop } catch { exit 0 }
$ids = @(Get-OpenTaskIds $planText)
if ($ids.Count -eq 0) { exit 0 }

$counter = Join-Path $stateDir ($sidSafe + '.' + (Get-SetKey $ids) + '.count')
$n = 0
try { $n = [int](Get-Content -LiteralPath $counter -Raw -ErrorAction Stop).Trim() } catch { $n = 0 }
if ($n -ge $MaxPerSet) { exit 0 }
try { Set-Content -LiteralPath $counter -Value ($n + 1) -Encoding UTF8 -ErrorAction Stop } catch { exit 0 }

$shown = ($ids | Select-Object -First 5) -join ', '
$more = if ($ids.Count -gt 5) { " 외 $($ids.Count - 5)개" } else { '' }
$msg = "[pjc loop-continue] $($planHit.Label) 에 미완 task 가 남은 채 turn 이 끝났습니다: ${shown}${more}. " +
    "사용자 답에 의존하지 않는 다음 task 를 이어서 진행하십시오. 막혔다면 무엇이 막는지 한 줄로 말하십시오 — " +
    "implement 「멈추는 넷」·「목록 밖의 넷」에 해당하는 정지(승인 대기 등)라면 그 정지를 유지합니다."
$out = @{ hookSpecificOutput = @{ hookEventName = 'Stop'; additionalContext = $msg } }
[Console]::Out.Write(($out | ConvertTo-Json -Compress -Depth 4))
exit 0
