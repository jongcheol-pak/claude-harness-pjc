# scenarios/hook-event-log.ps1 — hook 이벤트 로깅 시나리오 (§11 적재·격리·시크릿 fail-closed + §12) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 11) hook 이벤트 로깅 (hook-event-log.ps1 — 적재·격리·시크릿 fail-closed)
# =====================================================================
# 로그는 격리 홈($iso)의 .claude/.state/hook-events/{YYYY-MM}.jsonl에 쓰인다.
# 게이트 태그 4개: 이벤트 로깅 검증이 block-destructive(차단 적재)·pre-bash-dispatch(warn 적재)·
# protect-harness(헬퍼 개조 차단)를 실행 수단으로 쓴다 — 그 hook들의 필터에서도 커버 유지.
if (Test-HookSelected @('hook-event-log', 'block-destructive', 'pre-bash-dispatch', 'protect-harness')) {

# (a) 쓰기 불가 격리 — 로그 경로가 막혀도 차단 동작은 정상 (별도 격리 홈에서 hook-events 자리를 파일로 선점).
#     ※ (b)보다 먼저: $iso에는 앞 섹션들의 경고 로깅으로 이미 디렉터리가 생겨 있을 수 있어 새 홈을 쓴다.
$iso2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-lockedlog-" + $suffix)
New-Item -ItemType Directory -Path (Join-Path $iso2 '.claude/.state') -Force | Out-Null
'lock' | Set-Content (Join-Path $iso2 '.claude/.state/hook-events')   # 디렉터리 자리에 파일 — 로깅만 실패 유도
$env:USERPROFILE = $iso2
$r = Invoke-Hook 'block-destructive.ps1' (@{ tool_name = 'Bash'; tool_input = @{ command = 'rm -rf /' } } | ConvertTo-Json -Compress)
Assert-Case -Name "event-log: 로그 경로 쓰기 불가여도 차단 정상(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
$env:USERPROFILE = $iso
Remove-Item -Recurse -Force $iso2 -ErrorAction SilentlyContinue

# (b) 차단 이벤트 적재 실증 — block-destructive 차단 1건 후 로그 라인 존재.
$r = Invoke-Hook 'block-destructive.ps1' (@{ tool_name = 'Bash'; tool_input = @{ command = 'rm -rf /' } } | ConvertTo-Json -Compress)
$evDir = Join-Path $iso '.claude/.state/hook-events'
$evText = ''
try { $evText = (Get-ChildItem -LiteralPath $evDir -Filter '*.jsonl' -ErrorAction Stop | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" } catch {}
if (($r.code -eq 2) -and ($evText -match '"hook":"block-destructive"') -and ($evText -match '"decision":"block"')) {
    $script:results.Add(@{ ok = $true; line = "[PASS] event-log: 차단 이벤트 jsonl 적재" })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] event-log: 차단 이벤트 적재 누락 (exit=$($r.code), 로그검색 실패)" })
}

# (c) 시크릿 fail-closed — warn 명령에 시크릿 값 포함 시 로그에 평문 부재 (cmd 필드 생략).
$fakeKey = 'ZXCV9876QWER5432'   # 가짜 값 (러너 자체 오탐 방지용 분리 기재 불필요 — 패턴 좌변 없음)
$secCmd = 'git push origin main && export api_key="' + $fakeKey + '"'
$r = Invoke-Hook 'pre-bash-dispatch.ps1' (@{ tool_name = 'Bash'; tool_input = @{ command = $secCmd } } | ConvertTo-Json -Compress)
$evText2 = ''
try { $evText2 = (Get-ChildItem -LiteralPath $evDir -Filter '*.jsonl' -ErrorAction Stop | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" } catch {}
if (($r.code -eq 0) -and ($evText2 -match '"hook":"warn-external-ops"') -and ($evText2 -notmatch [regex]::Escape($fakeKey))) {
    $script:results.Add(@{ ok = $true; line = "[PASS] event-log: 시크릿 포함 명령 fail-closed (평문 미기록)" })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] event-log: 시크릿 fail-closed 위반 또는 warn 미적재 (exit=$($r.code))" })
}

# (d) protect-harness: 설치본 hook-event-log(헬퍼) 개조 차단 (이름 집합 합류 실증)
$elTarget = (Join-Path $vdCache 'hook-event-log.ps1') -replace '\\', '/'
$r = Invoke-Hook 'protect-harness.ps1' (@{ tool_name = 'Write'; tool_input = @{ file_path = $elTarget; content = 'x' } } | ConvertTo-Json -Compress)
Assert-Case -Name "protect-harness: 설치본 hook-event-log 개조 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
}   # ---- §11 게이트 끝 (hook-event-log 외) ----

# =====================================================================
# 12) report-hook-events.ps1 스모크 (이벤트 로그 집계 리포트 — hook 아님, 직접 실행)
# =====================================================================
# 리포트는 stdin이 아니라 USERPROFILE 기반 로그 디렉터리를 읽으므로 Invoke-Hook을 쓰지 않고
# 전용 격리 홈에 통제된 fixture jsonl을 심어 결정적으로 검증한다($iso는 앞 섹션들의 실제
# 이벤트로 오염돼 건수 단정 불가).
if (Test-HookSelected @('hook-event-log')) {
    $repScript = Join-Path $scriptsDir 'report-hook-events.ps1'

    # (a) fixture 3건(block 1 + warn 2) → 집계 키워드·건수 확인
    $isoR = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-report-" + $suffix)
    $repDir = Join-Path $isoR '.claude/.state/hook-events'
    New-Item -ItemType Directory -Path $repDir -Force | Out-Null
    @(
        '{"ts":"2026-07-01T10:00:00+09:00","hook":"block-destructive","decision":"block","rule":"rm -rf 루트","cmd":"rm -rf /"}',
        '{"ts":"2026-07-02T11:00:00+09:00","hook":"warn-external-ops","decision":"warn","rule":"git push"}',
        '{"ts":"2026-07-03T12:00:00+09:00","hook":"warn-external-ops","decision":"warn","rule":"git push"}'
    ) | Set-Content -Encoding UTF8 (Join-Path $repDir '2026-07.jsonl')
    $env:USERPROFILE = $isoR
    $outRep = & pwsh -NoProfile -ExecutionPolicy Bypass -File $repScript 2>&1
    $rRep = @{ code = $LASTEXITCODE; out = (($outRep | Out-String)).Trim() }
    $env:USERPROFILE = $iso
    Assert-Case -Name "report-hook-events: fixture 3건 총계 집계" -R $rRep -ExpectExit 0 -ExpectContains '총 이벤트: 3건 (차단 1 · 경고 2 · 회수 0)'
    Assert-Case -Name "report-hook-events: hook×판정·규칙 집계 표기" -R $rRep -ExpectExit 0 -ExpectContains 'warn-external-ops'
    Remove-Item -Recurse -Force $isoR -ErrorAction SilentlyContinue

    # (b) 로그 없는 빈 홈 → 안내 + exit 0 (오류로 죽지 않음)
    $isoR2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pjc-hook-evals-report-empty-" + $suffix)
    New-Item -ItemType Directory -Path $isoR2 -Force | Out-Null
    $env:USERPROFILE = $isoR2
    $outRep2 = & pwsh -NoProfile -ExecutionPolicy Bypass -File $repScript 2>&1
    $rRep2 = @{ code = $LASTEXITCODE; out = (($outRep2 | Out-String)).Trim() }
    $env:USERPROFILE = $iso
    Assert-Case -Name "report-hook-events: 로그 없음 안내 + exit 0" -R $rRep2 -ExpectExit 0 -ExpectContains '적재된 이벤트 없음'
    Remove-Item -Recurse -Force $isoR2 -ErrorAction SilentlyContinue
}   # ---- §12 게이트 끝 (hook-event-log) ----

