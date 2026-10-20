# scenarios/warn-version-drift.ps1 — warn-version-drift 시나리오 (§10) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 10) warn-version-drift 시나리오 (SessionStart — 설치본↔레포 버전 비교)
# =====================================================================
# 설치본은 $env:CLAUDE_PLUGIN_ROOT 픽스처로, 레포는 마커 2종(plugins/karina/.claude-plugin/plugin.json +
# .claude-plugin/marketplace.json) 픽스처로 위장한다. 실행 후 CLAUDE_PLUGIN_ROOT는 원복(다른 시나리오 오염 방지).
if (Test-HookSelected @('warn-version-drift')) {
$vdRealRoot = $env:CLAUDE_PLUGIN_ROOT
try {
    # 가짜 설치본 (v1.0.0)
    $vdInst = Join-Path $work 'vd-installed'
    New-Item -ItemType Directory (Join-Path $vdInst '.claude-plugin') -Force | Out-Null
    '{ "name": "karina", "version": "1.0.0" }' | Set-Content (Join-Path $vdInst '.claude-plugin/plugin.json')
    $env:CLAUDE_PLUGIN_ROOT = $vdInst

    # 가짜 하네스 레포 (v9.9.9 — 불일치)
    $vdRepo = Join-Path $work 'vd-repo'
    New-Item -ItemType Directory (Join-Path $vdRepo 'plugins/karina/.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $vdRepo '.claude-plugin') -Force | Out-Null
    '{ "name": "karina", "version": "9.9.9" }' | Set-Content (Join-Path $vdRepo 'plugins/karina/.claude-plugin/plugin.json')
    '{ "name": "karina-harness" }' | Set-Content (Join-Path $vdRepo '.claude-plugin/marketplace.json')

    $vdJson = @{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $vdRepo } | ConvertTo-Json -Compress
    # 1) 불일치 → 드리프트 경고 (exit 0 — 비차단)
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: 설치본≠레포 경고" -R $r -ExpectExit 0 -ExpectContains '버전 드리프트'
    Assert-Case -Name "version-drift: 재설치 안내가 /plugin update 를 가리킨다" -R $r -ExpectExit 0 -ExpectContains '/plugin update'

    # 2) 일치 → 무출력
    '{ "name": "karina", "version": "1.0.0" }' | Set-Content (Join-Path $vdRepo 'plugins/karina/.claude-plugin/plugin.json')
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: 버전 일치 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

    # 3) 비레포 cwd(마커 없음) → 무출력
    $r = Invoke-Hook 'warn-version-drift.ps1' (@{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $work } | ConvertTo-Json -Compress)
    Assert-Case -Name "version-drift: 비레포 cwd 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

    # 4) CLAUDE_PLUGIN_ROOT 부재 → 무출력 (fail-open)
    #   v1.158.0 주의: 이 케이스가 검증하는 것은 **드리프트 경고의 fail-open**이지 "hook 전체가 아무것도
    #   안 한다"가 아니다. 릴리즈 누락 검사는 설치본 판정보다 앞에 있어 이 상태에서도 돈다 — 다만 $vdRepo가
    #   git 저장소가 아니라 조용히 통과해 결과적으로 무출력이다(아래 5~7이 그 검사를 직접 건다).
    $env:CLAUDE_PLUGIN_ROOT = $null
    '{ "name": "karina", "version": "9.9.9" }' | Set-Content (Join-Path $vdRepo 'plugins/karina/.claude-plugin/plugin.json')
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: CLAUDE_PLUGIN_ROOT 부재 무출력(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- 릴리즈 누락 감지 (v1.158.0) ----
    # 규약("버전 전용 PR merge·버전 커밋 push 뒤 곧바로 릴리즈")을 기계가 보게 한 검사. 판정 기준은 워킹트리가 아니라
    # **origin/main에 올라간 plugin.json 버전**이라, 픽스처도 git 저장소 + origin/main ref로 만든다.
    if ($gitOk) {
        $vdGit = Join-Path $work 'vd-gitrepo'
        New-Item -ItemType Directory (Join-Path $vdGit 'plugins/karina/.claude-plugin') -Force | Out-Null
        New-Item -ItemType Directory (Join-Path $vdGit '.claude-plugin') -Force | Out-Null
        '{ "name": "karina", "version": "2.3.4" }' | Set-Content (Join-Path $vdGit 'plugins/karina/.claude-plugin/plugin.json')
        '{ "name": "karina-harness" }' | Set-Content (Join-Path $vdGit '.claude-plugin/marketplace.json')
        Push-Location -LiteralPath $vdGit
        try {
            & git init -q 2>$null
            & git config user.email eval@example.com 2>$null
            & git config user.name eval 2>$null
            & git add -A 2>$null
            & git commit -q -m 'v2.3.4' 2>$null
            & git update-ref refs/remotes/origin/main HEAD 2>$null
        } finally { Pop-Location }
        $vdGitJson = @{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $vdGit } | ConvertTo-Json -Compress

        # 5) 로컬 태그 없음 + `origin` remote 자체가 없음 → 원격 조회가 exit 128로 실패 → 무출력 (fail-open)
        #    v1.205.0 전에는 이 자리가 「릴리즈 누락 경고(태그 부재)」였다 — 판정이 로컬 태그뿐이라 이 픽스처로
        #    발화를 잴 수 있었다. 폴백이 생긴 뒤로는 같은 상태가 **조회 실패**에 해당하므로 기대값이 뒤집힌다.
        #    발화 축은 사라지지 않고 아래 bare origin 픽스처의 「원격에도 태그 없음」이 이어받는다.
        #    이 케이스가 지키는 것: 조회 실패를 「태그 없음」으로 오판하지 않는가 + stderr가 새지 않는가
        #    (`2>$null`을 빼면 `fatal: 'origin' does not appear to be a git repository`가 출력에 섞여 FAIL한다).
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdGitJson
        Assert-Case -Name "version-drift: 원격 조회 실패 무출력(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true

        # 6) 태그를 만들면 → 무출력
        Push-Location -LiteralPath $vdGit
        try { & git tag v2.3.4 2>$null } finally { Pop-Location }
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdGitJson
        Assert-Case -Name "version-drift: 태그 존재 시 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

        # 7) origin/main ref가 없으면(미push 레포) → 무출력 (fail-open — 개발 중 오탐 방지)
        Push-Location -LiteralPath $vdGit
        try { & git update-ref -d refs/remotes/origin/main 2>$null; & git tag -d v2.3.4 2>$null } finally { Pop-Location }
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdGitJson
        Assert-Case -Name "version-drift: origin/main 부재 무출력(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true

        # 7-1) [미배포 판정] 버전 커밋 뒤 plugins/ 커밋이 있어도, 태그 sha 를 얻지 못하면(로컬 태그 없음 · 빈 캐시 ·
        #      origin 원격 없음) 판정을 건너뛴다(무출력). plugin.json 마지막 커밋으로 폴백하는 구현이면 여기서 발화한다 —
        #      그 폴백은 오프라인에서 이미 배포된 변경을 미배포로 센다(계획 리뷰 2R).
        Push-Location -LiteralPath $vdGit
        try {
            New-Item -ItemType Directory 'plugins/karina/skills' -Force | Out-Null
            'x' | Set-Content 'plugins/karina/skills/a.md'
            & git add -A 2>$null; & git commit -q -m 'plugins 변경' 2>$null
            & git update-ref refs/remotes/origin/main HEAD 2>$null
        } finally { Pop-Location }
        $vdCacheDir = Join-Path $env:USERPROFILE '.claude/.state/version-drift'
        New-Item -ItemType Directory $vdCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $vdCacheDir 'released-v2.3.4') -Value ''
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdGitJson
        Assert-Case -Name "version-drift: 미배포 — 태그 sha 를 못 얻으면 판정을 건너뛴다(오프라인·빈 캐시 무출력)" -R $r -ExpectExit 0 -ExpectSilent $true
        Remove-Item -Recurse -Force $vdCacheDir -ErrorAction SilentlyContinue

        # ---- 원격 태그 폴백 (v1.205.0) ----
        # 위 5~7은 `origin` remote가 **없는** 픽스처라 원격 조회 경로를 밟지 못한다(전부 exit 128로 끝난다).
        # 여기서는 bare 레포를 실제 `origin`으로 붙여 그 경로를 건다 — `gh release create`가 태그를 원격에만
        # 만드는 상황(로컬 태그 없음 + 원격 태그 있음)이 이번 오탐의 형태이고, 그것을 재는 유일한 자리다.
        # 픽스처는 하나이므로 케이스를 **단조 전이 순서**로 배치한다(①원격에도 없음 → ②로컬 태그만 생성 →
        # ③태그 push 후 로컬 삭제). 순서를 바꾸면 원격 태그를 지우는 단계가 따로 필요해진다.
        $vdBare = Join-Path $work 'vd-bare-origin.git'
        $vdWork = Join-Path $work 'vd-remote-work'
        & git init -q --bare $vdBare 2>$null
        New-Item -ItemType Directory (Join-Path $vdWork 'plugins/karina/.claude-plugin') -Force | Out-Null
        New-Item -ItemType Directory (Join-Path $vdWork '.claude-plugin') -Force | Out-Null
        '{ "name": "karina", "version": "3.4.5" }' | Set-Content (Join-Path $vdWork 'plugins/karina/.claude-plugin/plugin.json')
        '{ "name": "karina-harness" }' | Set-Content (Join-Path $vdWork '.claude-plugin/marketplace.json')
        $vdRemoteReady = $false
        Push-Location -LiteralPath $vdWork
        try {
            & git init -q 2>$null
            & git config user.email eval@example.com 2>$null
            & git config user.name eval 2>$null
            & git add -A 2>$null
            & git commit -q -m 'v3.4.5' 2>$null
            & git remote add origin $vdBare 2>$null
            # 브랜치명을 기본값에 맡기지 않는다 — 기본이 `master`인 환경에서는 `origin/main`이 없어 hook이
            # `git show origin/main:...` 단계에서 조기 종료하고, 그러면 침묵을 기대하는 케이스가 전부 공허 통과한다
            # (위 5~7이 `update-ref`로 이 의존을 피한 것과 같은 이유 — 여기는 실제 push라 명시가 필요하다).
            & git push -q origin HEAD:main 2>$null
            & git update-ref refs/remotes/origin/main HEAD 2>$null
            # 픽스처 사전 조건: origin/main ref가 있고 원격에 v3.4.5 태그가 **아직** 없어야 한다.
            $vdHasRef = -not [string]::IsNullOrWhiteSpace(((& git rev-parse --verify -q refs/remotes/origin/main 2>$null) -join ''))
            $vdNoTag  = [string]::IsNullOrWhiteSpace(((& git ls-remote --tags origin 'v3.4.5' 2>$null) -join ''))
            $vdRemoteReady = ($vdHasRef -and $vdNoTag)
        } finally { Pop-Location }
        # 픽스처가 어긋나면 아래 세 케이스가 조용히 공허 통과하므로, 준비 자체를 케이스로 세운다.
        Assert-Case -Name "version-drift: [픽스처] bare origin 준비(origin/main ref + 태그 부재)" `
            -R @{ code = $(if ($vdRemoteReady) { 0 } else { 1 }); out = '' } -ExpectExit 0 -ExpectSilent $true

        $vdRemoteJson = @{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $vdWork } | ConvertTo-Json -Compress

        # 8) ① 로컬 태그 없음 + 원격에도 없음 → 릴리즈 누락 발화 (구 케이스 5의 축을 이어받는다)
        #    버전 문자열이 문구에 실려야 한다 — 한글 조사가 붙은 `v$var가`는 PowerShell이 변수명으로 삼켜
        #    빈 값이 된다(v1.158.0 구현 중 실제로 밟았다).
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 로컬·원격 모두 태그 없음 → 릴리즈 누락 발화" -R $r -ExpectExit 0 -ExpectContains '릴리즈 누락'
        Assert-Case -Name "version-drift: 릴리즈 누락 문구에 버전 실림" -R $r -ExpectExit 0 -ExpectContains 'v3.4.5'
        # 문면 고정 — v1.205.0이 판정 소스를 둘로 늘리며 문구를 「로컬·원격 어디에서도 찾지 못했다」로 좁혔다.
        # 이 어서션이 없으면 문면이 옛 표현(「태그가 없습니다」)으로 되돌아가도 골든이 green이다.
        # v1.204.0 F-7이 같은 형태를 지적해 SC33d(잔량 단독 문구 고정)를 더한 선례가 있다.
        Assert-Case -Name "version-drift: 릴리즈 누락 문구가 두 소스를 밝힌다" -R $r -ExpectExit 0 -ExpectContains '로컬·원격'
        # 문면 고정 — v1.385.0 이 Release 를 버전 전용 PR 로 바꿨다. 옛 규약(「버전 업 커밋 push 뒤」)으로
        # 되돌아가면 경고가 사용자를 옛 절차로 안내하므로 새 규약 낱말을 단언한다.
        Assert-Case -Name "version-drift: 릴리즈 누락 문구가 버전 전용 PR 을 밝힌다" -R $r -ExpectExit 0 -ExpectContains '버전 전용 PR'

        # 8-1) [회차 3 T7] ①과 ② 사이 — 확인된 태그 캐시가 있으면 원격을 보지 않는다
        #     원격에는 아직 태그가 없으므로, 원격을 조회하면 위 ①처럼 발화한다. 무출력이면 원격을 보지
        #     않았다는 증거다. 캐시는 손으로 심고 확인 뒤 지운다 — ②·③ 이 캐시 없는 상태에서 돌아야 한다.
        $vdCacheDir = Join-Path $env:USERPROFILE '.claude/.state/version-drift'
        New-Item -ItemType Directory $vdCacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $vdCacheDir 'released-v3.4.5') -Value ''
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 확인된 태그 캐시가 있으면 원격 조회 없이 무출력 (회차 3 T7)" -R $r -ExpectExit 0 -ExpectSilent $true
        Remove-Item -Recurse -Force $vdCacheDir -ErrorAction SilentlyContinue

        # 9) ② 로컬 태그만 생성(push하지 않음 — 원격에는 여전히 없다) → 무출력
        #    **원격 상태를 「없음」으로 못박는 것이 이 케이스의 전부다** — 원격에도 같은 태그가 있으면
        #    「원격 전용」 구현으로 바꿔도 결과가 같아 로컬 우선 분기를 전혀 고정하지 못한다.
        Push-Location -LiteralPath $vdWork
        try { & git tag v3.4.5 2>$null } finally { Pop-Location }
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 로컬 태그 히트 시 원격 무시(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true

        # 10) ③ 태그를 push한 뒤 로컬 태그 삭제 → 무출력 (**이번 오탐의 정확한 형태**)
        #     `gh release create`는 태그를 원격에만 만들므로 로컬은 비어 있다. 폴백 이전 코드에서는
        #     이 케이스가 「릴리즈 누락」을 발화해 FAIL한다 — 변이 확인의 대상이다.
        Push-Location -LiteralPath $vdWork
        try { & git push -q origin v3.4.5 2>$null; & git tag -d v3.4.5 2>$null } finally { Pop-Location }
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 원격에만 태그 있음(로컬 부재) → 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

        # 10-1) [회차 3 T7] ③ 바로 뒤 — 원격에서 태그를 찾은 결과는 캐시로 남는다
        $vdCacheHit = Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude/.state/version-drift/released-v3.4.5')
        Assert-Case -Name "version-drift: 원격에서 찾은 태그를 캐시로 남긴다 (회차 3 T7)" -R @{ code = ([int](-not $vdCacheHit)); out = "캐시 파일=$vdCacheHit" } -ExpectExit 0
        Remove-Item -Recurse -Force (Join-Path $env:USERPROFILE '.claude/.state/version-drift') -ErrorAction SilentlyContinue

        # ---- 미배포 판정 — 마지막 릴리즈 태그 커밋 뒤의 plugins/ 커밋 ----
        # 이어지는 단조 전이: 태그(원격 전용)는 v3.4.5 커밋 위 → docs 만 바뀐 커밋 → plugins 커밋 → 태그를 HEAD 로 옮김.
        $vdPushCommit = {
            param($path, $msg)
            Push-Location -LiteralPath $vdWork
            try {
                New-Item -ItemType Directory (Split-Path $path) -Force | Out-Null
                $msg | Set-Content $path
                & git add -A 2>$null; & git commit -q -m $msg 2>$null
                & git push -q origin HEAD:main 2>$null
                & git update-ref refs/remotes/origin/main HEAD 2>$null
            } finally { Pop-Location }
        }
        $vdCacheFile = Join-Path $env:USERPROFILE '.claude/.state/version-drift/released-v3.4.5'

        # 11) 태그 뒤 docs/ 만 바뀐 커밋 → 무출력 (음성 짝)
        & $vdPushCommit 'docs/note.md' 'docs 변경'
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 미배포 — 태그 뒤 plugins 밖 변경만 있으면 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

        # 12) 이어서 plugins/ 커밋 → 미배포 발화
        & $vdPushCommit 'plugins/karina/skills/b.md' 'plugins 변경'
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 미배포 — 태그 뒤 plugins/ 커밋이 있으면 발화" -R $r -ExpectExit 0 -ExpectContains '미배포'

        # 13) 원격 태그를 HEAD 로 옮겨도(주석 달린 태그) 캐시에 옛 sha 가 있으면 캐시를 쓴다 → 발화
        #     원격을 다시 물었다면 HEAD 를 기준으로 삼아 조용했을 것이다 — 캐시를 썼다는 증거다.
        Push-Location -LiteralPath $vdWork
        try { & git tag -a -m 'v3.4.5' v3.4.5 HEAD 2>$null; & git push -q -f origin v3.4.5 2>$null; & git tag -d v3.4.5 2>$null } finally { Pop-Location }
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 미배포 — 캐시의 태그 sha 를 원격보다 먼저 쓴다" -R $r -ExpectExit 0 -ExpectContains '미배포'

        # 14) 캐시를 지우면 원격의 주석 달린 태그를 peel 해 HEAD 를 기준으로 삼는다 → 무출력
        #     (릴리즈가 버전 커밋 뒤 커밋에 붙은 경우 — plugin.json 마지막 커밋 기준이면 발화한다)
        Remove-Item -Recurse -Force (Split-Path $vdCacheFile) -ErrorAction SilentlyContinue
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 미배포 — 릴리즈 태그가 버전 커밋 뒤 커밋에 있으면 무출력" -R $r -ExpectExit 0 -ExpectSilent $true

        # 15) 빈 캐시 파일(종전 형식) → 미배포 판정만 원격을 다시 물어 sha 를 채운다(무출력 · 캐시에 sha)
        New-Item -ItemType Directory (Split-Path $vdCacheFile) -Force | Out-Null
        Set-Content -LiteralPath $vdCacheFile -Value ''
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdRemoteJson
        Assert-Case -Name "version-drift: 미배포 — 빈 캐시는 원격 조회로 sha 를 채우고 무출력" -R $r -ExpectExit 0 -ExpectSilent $true
        $vdCacheSha = ((Get-Content -LiteralPath $vdCacheFile -Raw -ErrorAction SilentlyContinue) -join '').Trim()
        Assert-Case -Name "version-drift: 미배포 — 빈 캐시에 태그 커밋 sha 를 적는다" -R @{ code = $(if ($vdCacheSha -match '^[0-9a-f]{40}$') { 0 } else { 1 }); out = "캐시=$vdCacheSha" } -ExpectExit 0
        Remove-Item -Recurse -Force (Split-Path $vdCacheFile) -ErrorAction SilentlyContinue
    }
} finally {
    $env:CLAUDE_PLUGIN_ROOT = $vdRealRoot
}
}   # ---- §10 게이트 끝 (warn-version-drift) ----

