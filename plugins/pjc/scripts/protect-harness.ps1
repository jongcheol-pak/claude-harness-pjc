# PreToolUse hook - PowerShell 버전
# Write/Edit/MultiEdit/NotebookEdit 로 하니스 자기 자신(안전 게이트)을 무력화하는 시도를 차단한다.
#   대상 (1) ~/.claude/.disabled/<hook> 토글 파일 직접 생성 → harness-toggle skill을 우회한 게이트 끄기.
#        (2) .claude/ 하위 설치본 hook 스크립트(scripts/*.ps1)·hooks.json 개조 → exit 0 삽입 등으로 게이트 무력화.
#        (3) 8.3 단축명(CLAUDE~N·DISABL~N)으로 .claude/.disabled 경로를 마스킹한 (1)(2)의 우회 시도.
# exit 2 = block.
#
# 배경: require-plan-for-write 는 .claude 하위 쓰기를 무조건 허용하므로(하니스 설정 편의), 에이전트가
#   Write 도구로 `~/.claude/.disabled/require-plan-for-write` 를 만들거나 설치본 hook 스크립트를 개조해
#   안전 게이트를 스스로 끌 수 있었다(감독 계층 자기 해제). 이 hook이 그 Write/Edit 경로를 닫는다.
#
# ⚠️ 한계 (의도된 잔여 위험 — 문서화):
#   이 hook은 **Write/Edit 도구**를 통한 게이트 무력화만 차단한다.
#   Bash 명령을 통한 파일 쓰기(예: pwsh -c "Set-Content ~/.claude/.disabled/require-plan-for-write")는
#   block-destructive 의 명령치환 미탐과 동일한 정규식 한계로 완전 차단이 불가하다.
#   1차 방어선은 Claude Code 권한 시스템이며, 이 hook은 가장 흔한 Write 도구 우회를 닫는 심층방어다.
#
# ⚠️ 이 hook은 의도적으로 토글 불가합니다(block-destructive 와 동형).
#   - ~/.claude/.disabled/ 체크를 하지 않습니다 — 안전 게이트 보호가 목적이므로 스스로 꺼지지 않습니다.
#   - 환경변수 CLAUDE_HARNESS_QUICK 도 무시합니다.
#
# 개발 repo 무영향: 경로에 '.claude' 가 없는 개발 소스(예: <repo>/plugins/pjc/scripts/*.ps1)는
#   차단하지 않는다 — 설치본(~/.claude/plugins/...)만 대상. 하니스 자기 개발은 require-plan 게이트로 관리한다.
#   판정은 경로의 '.claude' 세그먼트 존재로 하므로, 개발 repo 안에 테스트/픽스처용 `.claude/` 폴더를 두고
#   그 하위에 hook 스크립트명·hooks.json 을 쓰면 오탐 차단될 수 있다(드문 케이스 — 과잉 차단이 과소 차단보다
#   안전한 게이트 방향이며, 필요하면 픽스처를 `.claude` 밖 이름으로 두거나 개발 시 이 hook 경로만 조정).
#
# 8.3 단축명 처리(H3): Windows 8.3 단축명으로 `.claude`(CLAUDE~1)·`.disabled`(DISABL~1)를 마스킹해
#   위 리터럴 매칭을 우회하는 경로도 잡는다 — 단 실제 마스킹 형태(CLAUDE~N·DISABL~N)에 한정하고
#   방어 키워드(.claude/.disabled/hook명) 중 하나가 잔존할 때만 차단해, 8.3 유저명(RUNNER~1 등)이 낀
#   개발 repo hook 소스 편집을 오차단하지 않는다(개발 repo 무영향 보장 유지).

$ErrorActionPreference = 'SilentlyContinue'

# 한글 차단 사유가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# stdin JSON 읽기
$inputJson = [Console]::In.ReadToEnd()

try {
    $data = $inputJson | ConvertFrom-Json
    $targetPath = $data.tool_input.path
    if (-not $targetPath) { $targetPath = $data.tool_input.file_path }
    if (-not $targetPath) { $targetPath = $data.tool_input.notebook_path }   # NotebookEdit (.ipynb)
} catch {
    # 파싱 실패 시 통과 (다른 hook과 동형 — 안전 최후선은 block-destructive)
    exit 0
}

if ([string]::IsNullOrWhiteSpace($targetPath)) { exit 0 }

# 경로 정규화 — 백슬래시→슬래시 + 세그먼트 정규화('.'·빈 세그먼트 제거, '..'는 직전 세그먼트와 상쇄).
#   `~/.claude/./.disabled/x`·`~/.claude//​.disabled/x`·`~/.claude/foo/../.disabled/x` 같은 경로 표기
#   변형으로 아래 리터럴 매칭(`/\.claude/\.disabled/`)을 우회하는 것을 막는다(안전 게이트의 핵심 방어).
$slashed = $targetPath -replace '\\', '/'
$segs = New-Object System.Collections.Generic.List[string]
foreach ($s in ($slashed -split '/')) {
    if ($s -eq '' -or $s -eq '.') { continue }
    if ($s -eq '..') { if ($segs.Count -gt 0) { $segs.RemoveAt($segs.Count - 1) }; continue }
    $segs.Add($s)
}
$norm = '/' + ($segs -join '/')

# 하니스 hook 이름 집합 — post-write-checks.ps1 H2 의 $harnessHookName 과 동일 유지(탐지↔차단 대칭).
$harnessHookName = 'block-destructive|require-plan-for-write|require-task-checkbox|require-evidence|post-write-checks|warn-external-ops|suggest-agents-record|harness-toggle|protect-harness'

# (1) .claude/.disabled/ 하위 토글 파일 직접 생성 — harness-toggle skill 우회 게이트 끄기
$isDisabledToggle = $norm -match '/\.claude/\.disabled/\S'
# (2) .claude/ 하위 설치본 hook 스크립트·hooks.json 개조
$isHookScript = ($norm -match ('/\.claude/.*/(' + $harnessHookName + ')\.ps1$')) -or
                ($norm -match '/\.claude/.*/hooks\.json$')
# (3) 8.3 단축명 마스킹 우회(H3) — .claude/.disabled를 CLAUDE~1/DISABL~1로 숨겨도, 마스킹은 둘을
#   동시에 다 숨길 수 없다(하나를 숨기면 다른 방어 키워드가 남는다). "실제 마스킹 형태 존재 + 방어
#   키워드 잔존"으로 판정한다. 일반 8.3 세그먼트(PROGRA~1·RUNNER~1)는 $has83 미매치라 무영향.
$has83 = ($norm -match '(?i)/(CLAUDE|DISABL)~[0-9]+(/|$)')
$suspect83 = $has83 -and (
    ($norm -match '(?i)\.disabled(/|$)') -or                              # .claude를 8.3로 숨겼어도 .disabled가 남음
    ($norm -match '(?i)\.claude(/|$)') -or                                # .disabled를 8.3로 숨겼어도 .claude가 남음
    ($norm -match ('(?i)/(' + $harnessHookName + ')(\.ps1)?(/|$)')))      # 둘 다 숨겨도 hook명이 남음

if ($isDisabledToggle -or $isHookScript -or $suspect83) {
    $why = if ($isDisabledToggle) {
        '.claude/.disabled/ 게이트 토글 파일 직접 생성 (harness-toggle skill 우회)'
    } elseif ($isHookScript) {
        '.claude/ 하위 설치본 하니스 hook 스크립트·hooks.json 개조'
    } else {
        '8.3 단축명(CLAUDE~1·DISABL~1)으로 하니스 경로를 마스킹한 게이트 무력화 시도'
    }
    [Console]::Error.WriteLine("BLOCKED: 하니스 안전 게이트 무력화 시도 감지 — $why")
    [Console]::Error.WriteLine("대상: $targetPath")
    [Console]::Error.WriteLine("hook on/off는 harness-toggle skill로, 하니스 수정은 개발 repo(경로에 .claude 없음)에서 plan 게이트를 거쳐 진행하세요.")
    exit 2
}

exit 0
