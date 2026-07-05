# PreToolUse hook - PowerShell 버전
# Bash/PowerShell 도구로 '외부·비가역' 작업(push·merge·tag·gh release/pr) 또는
# '로컬 비가역' 작업(git reset --hard·stash clear·checkout -- — 미커밋 변경 영구 소실) 실행 시
# stderr + additionalContext 경고 (차단 X — 비차단). 외부 작업은 자율 루프 권한 밖(규칙 12)이므로
# 사용자에게 별도 승인받았는지, 로컬 비가역은 의도된 되돌리기인지 모델에 상기시킨다.
#
# [설계: 왜 비차단(exit 0)인가]
#   일반 push는 사용자 승인 후 정당하게 일어나야 하므로 hard block하면 워크플로가 깨진다.
#   force push·history rewrite 등 진짜 파괴적 작업은 block-destructive가 exit 2로 차단하고,
#   이 hook은 '일반' 외부/비가역 작업에 "별도 승인 확인"을 모델에 상기시키는 soft 경고다.
#   따라서 의도적으로 exit 0 + stderr + PreToolUse additionalContext로 둔다(차단으로 바꾸지 말 것).

$ErrorActionPreference = 'SilentlyContinue'

# 한글 경고가 cp949 콘솔에서 깨지지 않도록 UTF-8 출력
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

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
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*push\b';   label = 'git push (원격 반영)' },
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*merge\b';  label = 'git merge (브랜치 병합)' },
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*tag\s+(--delete\b|-[asfmd]|[^\s-])';  label = 'git tag (태그 생성/삭제)' },
    @{ rx = 'gh\s+release\s+create';          label = 'gh release create (릴리즈 발행)' },
    @{ rx = 'gh\s+release\s+delete';          label = 'gh release delete (릴리즈 삭제 — 비가역)' },
    @{ rx = 'gh\s+pr\s+create';               label = 'gh pr create (PR 생성)' },
    @{ rx = 'gh\s+pr\s+merge';                label = 'gh pr merge (PR 병합)' },
    # 패키지·이미지 배포 (공개 레지스트리 반영은 되돌리기 어려움 — H5 커버리지 확장).
    # npm run publish-xxx 같은 스크립트 실행과 구분하기 위해 배포 동사가 CLI 바로 뒤일 때만 매칭.
    @{ rx = '\b(npm|pnpm|yarn)\s+publish\b';  label = '패키지 배포 (npm/pnpm/yarn publish)' },
    @{ rx = '\bdotnet\s+nuget\s+push\b';      label = 'NuGet 배포 (dotnet nuget push)' },
    @{ rx = '(^|\s)nuget\s+push\b';           label = 'NuGet 배포 (nuget push)' },
    @{ rx = '\bcargo\s+publish\b';            label = 'crates.io 배포 (cargo publish)' },
    @{ rx = '\btwine\s+upload\b';             label = 'PyPI 배포 (twine upload)' },
    @{ rx = '\bdocker\s+push\b';              label = '이미지 배포 (docker push)' }
)

# ---- 로컬 비가역 작업 패턴 (M4 — 원격 반영은 아니지만 미커밋 변경을 영구 소실시킴) ----
# 조회형(git stash list)·비파괴형(git reset --soft/--mixed)은 미매치. git restore는 --staged
#   (언스테이징 = 비파괴) 오탐을 피하기 위해 의도적으로 제외한다(checkout 형만 경고).
# reset 패턴: reset과 --hard 사이는 [^&;|\r\n]*로 한정 — .*(탐욕적)이면 한 줄 안 뒤쪽 다른 명령
#   (예: `git reset --soft HEAD~1 && git commit -m "undo --hard ..."`)의 커밋 메시지 속 --hard까지 스팬해
#   비파괴 --soft에도 오경고했다. 셸 구분자(&&·;·|·개행)를 넘지 않아 실제 `git reset ... --hard` 세그먼트만 매치.
# checkout 패턴: `checkout -- <path>`·`checkout .` 외에 `checkout <ref> -- <path>`(ref 지정 폐기)도 포함 —
#   git checkout HEAD -- x·git checkout main -- x 도 미커밋 워킹트리 변경을 폐기하므로 경고 대상.
#   `checkout -b`·`checkout <branch>`(-- 없음)는 브랜치 전환이라 미매치.
$localOps = @(
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*reset\s+[^&;|\r\n]*--hard\b';   label = 'git reset --hard (워킹트리·인덱스 되돌리기)' },
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*stash\s+clear\b';              label = 'git stash clear (스태시 전체 삭제)' },
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*checkout\s+--\s';              label = 'git checkout -- <path> (워킹트리 변경 폐기)' },
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*checkout\s+\S+\s+--\s';        label = 'git checkout <ref> -- <path> (워킹트리 변경 폐기)' },
    @{ rx = 'git\s+((-c|-C)\s+\S+\s+)*checkout\s+\.(\s|$)';          label = 'git checkout . (워킹트리 전체 변경 폐기)' }
)

$hits = New-Object System.Collections.Generic.List[string]
foreach ($op in $externalOps) {
    if ($cmd -match $op.rx) {
        # git push --dry-run 은 조회성(원격 반영 아님) — 제외
        if ($op.label -like 'git push*' -and $cmd -match '--dry-run') { continue }
        $hits.Add($op.label)
    }
}
$hitsLocal = New-Object System.Collections.Generic.List[string]
foreach ($op in $localOps) {
    if ($cmd -match $op.rx) { $hitsLocal.Add($op.label) }
}

if ($hits.Count -eq 0 -and $hitsLocal.Count -eq 0) { exit 0 }

# ---- 경고 출력 (external/local 분기 — external만 있으면 기존 출력과 동일해 골든 무회귀) ----
$lines = @()
if ($hits.Count -gt 0) {
    $lines += "[EXTERNAL OP WARNING] 외부·비가역 작업이 감지되었습니다:"
    foreach ($h in $hits) { $lines += "  - $h" }
}
if ($hitsLocal.Count -gt 0) {
    $lines += "[LOCAL OP WARNING] 로컬 비가역 작업이 감지되었습니다:"
    foreach ($h in $hitsLocal) { $lines += "  - $h" }
}
$lines += ""
if ($hits.Count -gt 0) {
    $lines += "이 작업들은 자율 루프 권한 밖입니다 (규칙 12 — push·병합·태그·릴리즈·PR)."
    $lines += "사용자에게 '그 행위를 이름으로 적어' 별도 승인받았는지 확인하세요. 승인 없이 실행하지 마세요."
}
if ($hitsLocal.Count -gt 0) {
    $lines += "로컬 비가역: 미커밋 변경이 영구 소실될 수 있습니다 — reflog로는 커밋된 것만 일부 복구됩니다. 진행 전 의도된 되돌리기인지 확인하세요."
}
$lines += "이 경고는 차단이 아닙니다."
$msg = $lines -join "`n"

# stderr: 사용자 가시성용
[Console]::Error.WriteLine($msg)

# stdout JSON: PreToolUse additionalContext로 모델에 전달 (exit 0 비차단).
$payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 5
[Console]::Out.WriteLine($payload)

exit 0
