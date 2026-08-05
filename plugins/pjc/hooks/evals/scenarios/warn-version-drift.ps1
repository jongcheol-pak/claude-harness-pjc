# scenarios/warn-version-drift.ps1 — warn-version-drift 시나리오 (§10) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 10) warn-version-drift 시나리오 (SessionStart — 설치본↔레포 버전 비교)
# =====================================================================
# 설치본은 $env:CLAUDE_PLUGIN_ROOT 픽스처로, 레포는 마커 2종(plugins/pjc/.claude-plugin/plugin.json +
# .claude-plugin/marketplace.json) 픽스처로 위장한다. 실행 후 CLAUDE_PLUGIN_ROOT는 원복(다른 시나리오 오염 방지).
if (Test-HookSelected @('warn-version-drift')) {
$vdRealRoot = $env:CLAUDE_PLUGIN_ROOT
try {
    # 가짜 설치본 (v1.0.0)
    $vdInst = Join-Path $work 'vd-installed'
    New-Item -ItemType Directory (Join-Path $vdInst '.claude-plugin') -Force | Out-Null
    '{ "name": "pjc", "version": "1.0.0" }' | Set-Content (Join-Path $vdInst '.claude-plugin/plugin.json')
    $env:CLAUDE_PLUGIN_ROOT = $vdInst

    # 가짜 하네스 레포 (v9.9.9 — 불일치)
    $vdRepo = Join-Path $work 'vd-repo'
    New-Item -ItemType Directory (Join-Path $vdRepo 'plugins/pjc/.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $vdRepo '.claude-plugin') -Force | Out-Null
    '{ "name": "pjc", "version": "9.9.9" }' | Set-Content (Join-Path $vdRepo 'plugins/pjc/.claude-plugin/plugin.json')
    '{ "name": "pjc-harness" }' | Set-Content (Join-Path $vdRepo '.claude-plugin/marketplace.json')

    $vdJson = @{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $vdRepo } | ConvertTo-Json -Compress
    # 1) 불일치 → 드리프트 경고 (exit 0 — 비차단)
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: 설치본≠레포 경고" -R $r -ExpectExit 0 -ExpectContains '버전 드리프트'

    # 2) 일치 → 무출력
    '{ "name": "pjc", "version": "1.0.0" }' | Set-Content (Join-Path $vdRepo 'plugins/pjc/.claude-plugin/plugin.json')
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
    '{ "name": "pjc", "version": "9.9.9" }' | Set-Content (Join-Path $vdRepo 'plugins/pjc/.claude-plugin/plugin.json')
    $r = Invoke-Hook 'warn-version-drift.ps1' $vdJson
    Assert-Case -Name "version-drift: CLAUDE_PLUGIN_ROOT 부재 무출력(fail-open)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- 릴리즈 누락 감지 (v1.158.0) ----
    # 규약("버전 업 커밋 push 뒤 곧바로 릴리즈")을 기계가 보게 한 검사. 판정 기준은 워킹트리가 아니라
    # **origin/main에 올라간 plugin.json 버전**이라, 픽스처도 git 저장소 + origin/main ref로 만든다.
    if ($gitOk) {
        $vdGit = Join-Path $work 'vd-gitrepo'
        New-Item -ItemType Directory (Join-Path $vdGit 'plugins/pjc/.claude-plugin') -Force | Out-Null
        New-Item -ItemType Directory (Join-Path $vdGit '.claude-plugin') -Force | Out-Null
        '{ "name": "pjc", "version": "2.3.4" }' | Set-Content (Join-Path $vdGit 'plugins/pjc/.claude-plugin/plugin.json')
        '{ "name": "pjc-harness" }' | Set-Content (Join-Path $vdGit '.claude-plugin/marketplace.json')
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

        # 5) origin/main에 버전이 있는데 태그 없음 → 릴리즈 누락 경고 (버전 문자열이 문구에 실려야 한다 —
        #    한글 조사가 붙은 `v$var가`는 PowerShell이 변수명으로 삼켜 빈 값이 된다: 구현 중 실제로 밟았다)
        $r = Invoke-Hook 'warn-version-drift.ps1' $vdGitJson
        Assert-Case -Name "version-drift: 릴리즈 누락 경고(태그 부재)" -R $r -ExpectExit 0 -ExpectContains '릴리즈 누락'
        Assert-Case -Name "version-drift: 릴리즈 누락 문구에 버전 실림" -R $r -ExpectExit 0 -ExpectContains 'v2.3.4'

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
    }
} finally {
    $env:CLAUDE_PLUGIN_ROOT = $vdRealRoot
}
}   # ---- §10 게이트 끝 (warn-version-drift) ----

