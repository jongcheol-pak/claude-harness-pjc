# PreToolUse hook - PowerShell 버전
# Write/Edit/MultiEdit/NotebookEdit 로 하니스 자기 자신(안전 게이트)을 무력화하는 시도를 차단한다.
#   대상 (1) .claude/ 하위 설치본 hook 스크립트(scripts/*.ps1)·hooks.json 개조 → exit 0 삽입 등으로 게이트 무력화.
#        (2) 8.3 단축명(CLAUDE~N)으로 .claude 경로를 마스킹한 (1)의 우회 시도.
# exit 2 = block.
#
# 배경: require-plan-for-write 는 .claude 하위 쓰기를 무조건 허용하므로(하니스 설정 편의), 에이전트가
#   Write 도구로 설치본 hook 스크립트·hooks.json 을 개조해 안전 게이트를 스스로 끌 수 있었다(감독 계층
#   자기 해제). 이 hook이 그 Write/Edit 경로를 닫는다.
#
# ⚠️ 한계 (의도된 잔여 위험 — 문서화):
#   이 hook은 **Write/Edit 도구**를 통한 hook 개조만 차단한다.
#   Bash 명령을 통한 파일 쓰기(예: pwsh -c "Set-Content .../scripts/require-plan-for-write.ps1")는
#   block-destructive 의 명령치환 미탐과 동일한 정규식 한계로 완전 차단이 불가하다.
#   1차 방어선은 Claude Code 권한 시스템이며, 이 hook은 가장 흔한 Write 도구 우회를 닫는 심층방어다.
#
# ⚠️ 이 hook은 의도적으로 토글 불가합니다(block-destructive 와 동형).
#   - 안전 게이트 보호가 목적이므로 스스로 꺼지지 않습니다.
#   - 환경변수 CLAUDE_HARNESS_QUICK 도 무시합니다.
#
# 개발 repo 무영향: 경로에 '.claude' 가 없는 개발 소스(예: <repo>/plugins/pjc/scripts/*.ps1)는
#   차단하지 않는다 — 설치본(~/.claude/plugins/...)만 대상. 하니스 자기 개발은 require-plan 게이트로 관리한다.
#   판정은 경로의 '.claude' 세그먼트 존재로 하므로, 개발 repo 안에 테스트/픽스처용 `.claude/` 폴더를 두고
#   그 하위에 hook 스크립트명·hooks.json 을 쓰면 오탐 차단될 수 있다(드문 케이스 — 과잉 차단이 과소 차단보다
#   안전한 게이트 방향이며, 필요하면 픽스처를 `.claude` 밖 이름으로 두거나 개발 시 이 hook 경로만 조정).
#
# 8.3 단축명 처리(H3): Windows 8.3 단축명으로 `.claude`(CLAUDE~1)를 마스킹해 위 리터럴 매칭을 우회하는
#   설치본 hook 경로도 잡는다 — 단 실제 마스킹 형태(CLAUDE~N) + hook명 + `/plugins/cache/`(설치 캐시)일
#   때만 차단한다. ⚠️ hook명 단독으로 판정하면 안 된다 — `Claude…`로 시작하는 폴더는 8.3명이 CLAUDE~1
#   (이 repo 자신 포함)이라 개발 repo hook 소스(…/CLAUDE~1/plugins/pjc/scripts/*.ps1)를 오차단하기 때문.
#   실제 마스킹된 설치본 경로는 항상 설치 캐시(.claude/plugins/cache/…)를 포함하므로 이를 게이트로 요구해
#   개발 repo 무영향을 지킨다.

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
#   `~/.claude/./plugins/…/x.ps1`·`~/.claude/foo/../plugins/…/hooks.json` 같은 경로 표기
#   변형으로 아래 설치본 hook 스크립트·hooks.json 리터럴 매칭을 우회하는 것을 막는다(안전 게이트의 핵심 방어).
$slashed = $targetPath -replace '\\', '/'
$segs = New-Object System.Collections.Generic.List[string]
foreach ($s in ($slashed -split '/')) {
    if ($s -eq '' -or $s -eq '.') { continue }
    if ($s -eq '..') { if ($segs.Count -gt 0) { $segs.RemoveAt($segs.Count - 1) }; continue }
    $segs.Add($s)
}
$norm = '/' + ($segs -join '/')

# 하니스 hook·공유 헬퍼 이름 집합 — post-write-checks.ps1 H2 의 $harnessHookName 과 동일 유지(탐지↔차단 대칭).
# hook 신설 시 여기에 함께 추가할 것(v1.96.0 warn-commit-secrets 누락이 v1.97.2에서 뒤늦게 합류한 전례).
# secret-patterns는 hook이 아닌 dot-source 헬퍼지만, 설치본 개조 시 시크릿 경고 계층(post-write·
# warn-commit-secrets)이 동일하게 무력화되는 등가 우회라 보호 대상에 포함한다.
$harnessHookName = 'block-destructive|require-plan-for-write|require-task-checkbox|require-evidence|post-write-checks|warn-external-ops|suggest-agents-record|protect-harness|warn-commit-secrets|secret-patterns|pre-bash-dispatch|bash-hook-lib|warn-version-drift'

# (1) .claude/ 하위 설치본 hook 스크립트·hooks.json 개조
$isHookScript = ($norm -match ('/\.claude/.*/(' + $harnessHookName + ')\.ps1$')) -or
                ($norm -match '/\.claude/.*/hooks\.json$')
# (2) 8.3 단축명 마스킹 우회(H3) — .claude를 CLAUDE~1로 숨겨 위 리터럴 매칭을 우회하는 설치본 hook 경로를
#   잡는다. "실제 마스킹 형태(CLAUDE~N) + hook명 + 설치 캐시(/plugins/cache/)"로 판정한다.
#   일반 8.3 세그먼트(PROGRA~1·RUNNER~1)는 $has83 미매치라 무영향.
$has83 = ($norm -match '(?i)/CLAUDE~[0-9]+(/|$)')
$suspect83 = $has83 -and
    ($norm -match ('(?i)/(' + $harnessHookName + ')(\.ps1)?(/|$)')) -and  # .claude를 8.3로 숨겨도 hook명이 남음 —
    ($norm -match '(?i)/plugins/cache/')                                  #   단 설치 캐시(.claude/plugins/cache/) 컨텍스트일 때만(근거는 헤더 8.3 처리 참조).

if ($isHookScript -or $suspect83) {
    $why = if ($isHookScript) {
        '.claude/ 하위 설치본 하니스 hook 스크립트·hooks.json 개조'
    } else {
        '8.3 단축명(CLAUDE~1)으로 설치본 하니스 hook 경로를 마스킹한 개조 시도'
    }
    [Console]::Error.WriteLine("BLOCKED: 하니스 안전 hook 개조 시도 감지 — $why")
    [Console]::Error.WriteLine("대상: $targetPath")
    [Console]::Error.WriteLine("하니스 수정은 개발 repo(경로에 .claude 없음)에서 plan 게이트를 거쳐 진행하세요.")
    exit 2
}

exit 0
