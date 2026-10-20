# record-work-start.ps1 — karina:plan·karina:chain-plan 발동 시각을 세션 상태에 쓰고 컨텍스트에 주입한다 — 근거는 `rules/work-start-rationale.md` §1

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# 대상 스킬 — hooks.json UserPromptExpansion matcher 와 같은 식이다 — 근거는 `rules/work-start-rationale.md` §2
$SkillRx = '^(karina:)?(plan|chain-plan)$'

# 판정 불가는 전부 침묵이다 — 근거는 `rules/work-start-rationale.md` §3
try { $data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
if (-not $data) { exit 0 }
$sid = [string]$data.session_id
if ([string]::IsNullOrWhiteSpace($sid)) { exit 0 }

$hookEvent = [string]$data.hook_event_name
$name = ''
if ($hookEvent -eq 'PreToolUse') {
    if ([string]$data.tool_name -ne 'Skill') { exit 0 }
    $name = [string]$data.tool_input.skill
} elseif ($hookEvent -eq 'UserPromptExpansion') {
    $name = [string]$data.command_name
} else { exit 0 }
if ($name -notmatch $SkillRx) { exit 0 }
$key = $Matches[2]

# 상태 파일은 세션 단위이고 발동마다 그 키를 덮어쓴다 — 근거는 `rules/work-start-rationale.md` §4
$base = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$stateDir = Join-Path $base '.claude/.state/work-start'
$statePath = Join-Path $stateDir (($sid -replace '[^A-Za-z0-9._-]', '_') + '.json')
$state = [ordered]@{}
try {
    $old = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($p in $old.PSObject.Properties) { $state[$p.Name] = [string]$p.Value }
} catch {}
$now = (Get-Date).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$state[$key] = $now
try {
    New-Item -Force -ItemType Directory -Path $stateDir -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath $statePath -Value ($state | ConvertTo-Json -Compress) -Encoding UTF8 -ErrorAction Stop
} catch { exit 0 }

# chain-plan 은 이 세션 plan 시각을 함께 싣는다 — 근거는 `rules/work-start-rationale.md` §5
$line = "[karina 작업 시작] karina:$key $now"
if ($key -eq 'chain-plan' -and $state.Contains('plan')) { $line += " · karina:plan $($state['plan'])" }
$out = @{ hookSpecificOutput = @{ hookEventName = $hookEvent; additionalContext = $line } }
Write-Output ($out | ConvertTo-Json -Compress -Depth 4)
exit 0
