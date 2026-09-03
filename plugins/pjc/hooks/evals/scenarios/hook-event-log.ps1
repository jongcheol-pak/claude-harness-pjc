# scenarios/hook-event-log.ps1 — hook 이벤트 로깅 시나리오 (§11 적재·격리·시크릿 fail-closed + §12) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 11) hook 이벤트 로깅 (hook-event-log.ps1 — 적재·격리·시크릿 fail-closed)
# =====================================================================
# 로그는 격리 홈($iso)의 .claude/.state/hook-events/{YYYY-MM}.jsonl에 쓰인다.
# 게이트 태그 4개: 이벤트 로깅 검증이 block-destructive(차단 적재)·guard-bash(warn 적재)·
# guard-harness(헬퍼 개조 차단)를 실행 수단으로 쓴다 — 그 hook들의 필터에서도 커버 유지.
if (Test-HookSelected @('hook-event-log', 'block-destructive', 'guard-bash', 'guard-harness')) {

# (a) 쓰기 불가 격리 — 로그 경로가 막혀도 차단 동작은 정상 (별도 격리 홈에서 hook-events 자리를 파일로 선점).
#     ※ (b)보다 먼저: $iso에는 앞 섹션들의 경고 로깅으로 이미 디렉터리가 생겨 있을 수 있어 새 홈을 쓴다.
$iso2 = Join-Path $EvalRunTemp ("pjc-hook-evals-lockedlog-" + $suffix)
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
$r = Invoke-Hook 'guard-bash.ps1' (@{ tool_name = 'Bash'; tool_input = @{ command = $secCmd } } | ConvertTo-Json -Compress)
$evText2 = ''
try { $evText2 = (Get-ChildItem -LiteralPath $evDir -Filter '*.jsonl' -ErrorAction Stop | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" } catch {}
if (($r.code -eq 0) -and ($evText2 -match '"hook":"warn-external-ops"') -and ($evText2 -notmatch [regex]::Escape($fakeKey))) {
    $script:results.Add(@{ ok = $true; line = "[PASS] event-log: 시크릿 포함 명령 fail-closed (평문 미기록)" })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] event-log: 시크릿 fail-closed 위반 또는 warn 미적재 (exit=$($r.code))" })
}

# (d) guard-harness: 설치본 hook-event-log(헬퍼) 개조 차단 (이름 집합 합류 실증)
$elTarget = (Join-Path $vdCache 'hook-event-log.ps1') -replace '\\', '/'
$r = Invoke-Hook 'guard-harness.ps1' (@{ tool_name = 'Write'; tool_input = @{ file_path = $elTarget; content = 'x' } } | ConvertTo-Json -Compress)
Assert-Case -Name "guard-harness: 설치본 hook-event-log 개조 차단" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
}   # ---- §11 게이트 끝 (hook-event-log 외) ----
# 12) report-hook-events 스모크는 v1.225.0에 삭제했다 — 그 수동 도구를 제거했기 때문이다.
#    이벤트 집계는 jsonl 을 직접 읽으면 되고(파이썬 6줄), 전용 스크립트를 유지할 근거가 없었다.

