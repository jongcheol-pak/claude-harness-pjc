# scenarios/guard-stale-docs.ps1 — warn-stale-docs 시나리오 (커밋 직전 낡음 고지) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook)와 공유 변수($work·$gitOk)를 쓴다.
# 검사 대상은 `guard-bash.ps1` 이다 — `guard-stale-docs.ps1` 은 dot-source 되는 구현이라 디스패처를 통해 판정한다.
#
# 이 검사는 **판정 재료가 워킹트리 상태(스테이징 목록·git 이력)** 라 선언형 `hook-cases.json` 으로 못 담는다.
#   그래서 환경을 만들어 주는 시나리오다 — `warn-commit-secrets` 가 같은 사정으로 시나리오인 것과 같다.
if (Test-HookSelected @('guard-bash', 'guard-stale-docs')) {
if (-not $gitOk) {
    Write-Host '[SKIP] guard-stale-docs: git 없음 — 스테이징 판정이 성립하지 않는다'
} else {
$sdRoot = Join-Path $work 'sd-repo'
try {
    # ---- 하니스 레포로 위장한 git 저장소 ----
    #  마커 2종이 동시에 있어야 이 검사가 발동한다(`warn-version-drift` 와 같은 판정).
    New-Item -ItemType Directory (Join-Path $sdRoot 'plugins/pjc/.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $sdRoot '.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $sdRoot 'docs') -Force | Out-Null
    '{ "name": "pjc", "version": "1.0.0" }' | Set-Content (Join-Path $sdRoot 'plugins/pjc/.claude-plugin/plugin.json')
    '{ "name": "pjc-harness" }' | Set-Content (Join-Path $sdRoot '.claude-plugin/marketplace.json')
    '# 규약' | Set-Content (Join-Path $sdRoot 'docs/harness-conventions.md')
    & git -C $sdRoot init -q 2>$null
    & git -C $sdRoot add -A 2>$null
    & git -C $sdRoot -c user.email=t@t -c user.name=t commit -q -m 'init' 2>$null

    $sdCommit = @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $sdRoot
                   tool_input = @{ command = 'git commit -m "x"' } } | ConvertTo-Json -Compress

    # 1) 델타 음성 — 스테이징이 비었고 낡음도 없으면 침묵한다.
    #    이 케이스가 없으면 "무엇이든 경고하는" 구현이 그대로 통과한다.
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdCommit } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 낡음 없음 무출력' -R $r -ExpectExit 0 -ExpectSilent $true

    # 2) 층 3 양성 — `docs/harness-conventions.md` 를 스테이징하면 「산문 서술」 축을 고지한다.
    #    경로로만 판정하므로 내용은 무엇이든 상관없다.
    '# 규약' + [Environment]::NewLine + '변경' | Set-Content (Join-Path $sdRoot 'docs/harness-conventions.md')
    & git -C $sdRoot add docs/harness-conventions.md 2>$null
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdCommit } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 산문 서술 축 고지' -R $r -ExpectExit 0 -ExpectContains '산문 서술'

    # 3) **차단하지 않는다** — 고지가 붙어도 exit 0 이다. `exit 2` 를 내는 hook 은 넷뿐이고
    #    이 검사는 거기 들지 않는다. 등급이 뒤집히면 커밋이 통째로 막힌다.
    Assert-Case -Name 'stale-docs: 고지는 비차단(exit 0)' -R $r -ExpectExit 0

    # 3-b) **층 1 양성** — 축 ⑰ 대역이 `[WOULD-FIX]` 를 내면 그것을 고지에 싣는다.
    #      대역을 두는 이유: 실물 검사기를 픽스처에 복사하면 레포 전체를 요구한다. 여기서
    #      재는 것은 **「층 1 출력을 실어 나르는가」**이지 검사기의 판정이 아니다.
    #      이 케이스가 없으면 층 1 코드를 통째로 지워도 이 시나리오가 green 이다.
    New-Item -ItemType Directory (Join-Path $sdRoot 'plugins/pjc/evals') -Force | Out-Null
    @'
print("[WOULD-FIX] fixture/cases.json baseline 1 -> 2")
'@ | Set-Content (Join-Path $sdRoot 'plugins/pjc/evals/check-harness-consistency.py')
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdCommit } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 층1 계수 불일치 고지' -R $r -ExpectExit 0 -ExpectContains 'baseline 1 -> 2'

    # 3-c) **층 2 양성(러너 총계 갈림)** — 러너 상수와 문서 기준선이 다르면 고지한다.
    New-Item -ItemType Directory (Join-Path $sdRoot 'plugins/pjc/hooks/evals') -Force | Out-Null
    '$GoldenTotalBaseline = 111' | Set-Content (Join-Path $sdRoot 'plugins/pjc/hooks/evals/run-hook-evals.ps1')
    '**기준선 222케이스**다' | Set-Content (Join-Path $sdRoot 'docs/harness-conventions.md')
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdCommit } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 층2 러너 총계 갈림 고지' -R $r -ExpectExit 0 -ExpectContains '러너 상수 111 ↔ 문서 222'

    # 3-d) 같은 값이면 그 줄은 안 뜬다(층 2 델타 음성).
    '**기준선 111케이스**다' | Set-Content (Join-Path $sdRoot 'docs/harness-conventions.md')
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdCommit } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 층2 총계 일치 시 침묵' -R $r -ExpectExit 0 -ExpectNotContains '러너 상수'

    # 층 1·2 대역을 걷어 나머지 케이스를 원래 조건으로 되돌린다.
    Remove-Item (Join-Path $sdRoot 'plugins/pjc/evals/check-harness-consistency.py') -Force
    Remove-Item (Join-Path $sdRoot 'plugins/pjc/hooks/evals/run-hook-evals.ps1') -Force

    # 4) 비커밋 Bash 호출은 무출력 — 조사만 하는 턴에 발화하면 소음이 된다.
    $sdOther = @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $sdRoot
                  tool_input = @{ command = 'git status' } } | ConvertTo-Json -Compress
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdOther } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 비커밋 호출 무출력' -R $r -ExpectExit 0 -ExpectSilent $true

    # 5) `--dry-run` 커밋도 무출력 — 실제로 이력에 남지 않는 호출이다.
    $sdDry = @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $sdRoot
                tool_input = @{ command = 'git commit --dry-run' } } | ConvertTo-Json -Compress
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdDry } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: --dry-run 무출력' -R $r -ExpectExit 0 -ExpectSilent $true

    # 5b) heredoc **본문**의 커밋 문구는 커밋이 아니다 — `guard-commit-secrets` 와 판정을
    #   맞춘 자리다. 두 검사가 한 프로세스에서 같은 `$cmd` 를 보므로 한쪽만 고치면
    #   「한쪽만 도는 조합」이 생긴다(2026-09-11 완료 리뷰 MAJOR — 실제로 생겼다).
    $sdHd = @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $sdRoot
               tool_input = @{ command = "cat > note.md <<EOF`n규약: git commit -- <경로>`nEOF" } } | ConvertTo-Json -Compress
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdHd } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: heredoc 본문의 커밋 문구는 커밋이 아니다' -R $r -ExpectExit 0 -ExpectSilent $true

    # 5c) 델타 음성 — 같은 heredoc **뒤에** 진짜 커밋이 오면 종전대로 고지한다.
    $sdHdReal = @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $sdRoot
                   tool_input = @{ command = "cat > note.md <<EOF`nx`nEOF`ngit commit -m x" } } | ConvertTo-Json -Compress
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdHdReal } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: heredoc 뒤의 진짜 커밋은 그대로 고지한다' -R $r -ExpectExit 0 -ExpectContains '산문 서술'

    # 5d) 비-data-sink heredoc 도 같다 (회차 58) — `guard-commit-secrets` 의 HD3 과 짝이다.
    #   두 검사가 같은 `$cmd` 를 보므로 **여기서도 함께** 재지 않으면 한쪽만 도는 조합이 또 생긴다.
    $sdHdPy = @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $sdRoot
                 tool_input = @{ command = "python3 - <<PY`nprint('규약: git commit -- <경로>')`nPY" } } | ConvertTo-Json -Compress
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdHdPy } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 비-data-sink heredoc 본문의 커밋 문구는 커밋이 아니다' -R $r -ExpectExit 0 -ExpectSilent $true

    # 5e) 델타 음성 — 같은 `python3 - <<PY` 뒤에 진짜 커밋이 오면 종전대로 고지한다.
    $sdHdPyReal = @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $sdRoot
                     tool_input = @{ command = "python3 - <<PY`nprint(1)`nPY`ngit commit -m x" } } | ConvertTo-Json -Compress
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdHdPyReal } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 비-data-sink heredoc 뒤의 진짜 커밋은 그대로 고지한다' -R $r -ExpectExit 0 -ExpectContains '산문 서술'

    # 6) 비하니스 레포는 무출력 — 마커 하나를 지우면 발동하지 않는다.
    Remove-Item (Join-Path $sdRoot '.claude-plugin/marketplace.json') -Force
    & git -C $sdRoot add -A 2>$null
    Push-Location $sdRoot
    try { $r = Invoke-Hook 'guard-bash.ps1' $sdCommit } finally { Pop-Location }
    Assert-Case -Name 'stale-docs: 비하니스 레포 무출력' -R $r -ExpectExit 0 -ExpectSilent $true
} finally {
    if (Test-Path $sdRoot) { Remove-Item $sdRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
}
}
