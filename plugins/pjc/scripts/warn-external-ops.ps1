# PreToolUse hook - PowerShell 버전
# Bash/PowerShell 도구로 '외부·비가역' 작업(push·merge·tag·gh release/pr) 실행 시
# stderr + additionalContext 경고 (차단 X — 비차단). 자율 루프 권한 밖(규칙 12)이므로
# 사용자에게 별도 승인받았는지 모델에 상기시킨다.
#
# [설계: 왜 비차단(exit 0)인가]
#   일반 push는 사용자 승인 후 정당하게 일어나야 하므로 hard block하면 워크플로가 깨진다.
#   force push·history rewrite 등 진짜 파괴적 작업은 block-destructive가 exit 2로 차단하고,
#   이 hook은 '일반' 외부/비가역 작업에 "별도 승인 확인"을 모델에 상기시키는 soft 경고다.
#   따라서 의도적으로 exit 0 + stderr + PreToolUse additionalContext로 둔다(차단으로 바꾸지 말 것).
#
# 토글: harness-toggle 로 비활성 가능 (warn-external-ops).

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---- 토글 체크 ----
# 홈 경로: Claude Code 홈과 정합 — Windows는 USERPROFILE(없으면 $HOME 폴백), 비Windows는 $HOME
$base = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
$disableFile = Join-Path $base ".claude/.disabled/warn-external-ops"
if (Test-Path -LiteralPath $disableFile) { exit 0 }

# stdin JSON 읽기 (Bash·PowerShell 도구 모두 tool_input.command 필드를 가진다)
$inputJson = [Console]::In.ReadToEnd()
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
} catch {
    # 파싱 실패 시 통과 (경고 실패가 차단보다 안전)
    exit 0
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# ---- 외부·비가역 작업 패턴 (변경형만 — 조회는 제외) ----
# git tag: 조회(git tag / git tag -l / git tag -n)는 제외, 생성/삭제(-a/-s/-f/-m/-d/태그명)만.
$externalOps = @(
    @{ rx = 'git\s+push\b';                   label = 'git push (원격 반영)' },
    @{ rx = 'git\s+merge\b';                  label = 'git merge (브랜치 병합)' },
    @{ rx = 'git\s+tag\s+(--delete\b|-[asfmd]|[^\s-])';  label = 'git tag (태그 생성/삭제)' },
    @{ rx = 'gh\s+release\s+create';          label = 'gh release create (릴리즈 발행)' },
    @{ rx = 'gh\s+pr\s+create';               label = 'gh pr create (PR 생성)' },
    @{ rx = 'gh\s+pr\s+merge';                label = 'gh pr merge (PR 병합)' }
)

$hits = New-Object System.Collections.Generic.List[string]
foreach ($op in $externalOps) {
    if ($cmd -match $op.rx) {
        # git push --dry-run 은 조회성(원격 반영 아님) — 제외
        if ($op.label -like 'git push*' -and $cmd -match '--dry-run') { continue }
        $hits.Add($op.label)
    }
}

if ($hits.Count -eq 0) { exit 0 }

# ---- 경고 출력 ----
$lines = @("[EXTERNAL OP WARNING] 외부·비가역 작업이 감지되었습니다:")
foreach ($h in $hits) { $lines += "  - $h" }
$lines += ""
$lines += "이 작업들은 자율 루프 권한 밖입니다 (규칙 12 — push·병합·태그·릴리즈·PR)."
$lines += "사용자에게 '그 행위를 이름으로 적어' 별도 승인받았는지 확인하세요. 승인 없이 실행하지 마세요."
$lines += "이 경고는 차단이 아닙니다. 끄려면: harness-toggle warn-external-ops off"
$msg = $lines -join "`n"

# stderr: 사용자 가시성용
[Console]::Error.WriteLine($msg)

# stdout JSON: PreToolUse additionalContext로 모델에 전달 (exit 0 비차단).
$payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
[Console]::Out.WriteLine($payload)

exit 0
