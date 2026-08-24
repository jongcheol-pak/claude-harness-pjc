# scenarios/suggest-agents-record.ps1 — suggest-agents-record 시나리오 (§5) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 5) suggest-agents-record 시나리오 (제안·억제 2중·마커 정리)
# =====================================================================
if (Test-HookSelected @('suggest-agents-record')) {
$aproj = Join-Path $work 'aproj'; New-Item -ItemType Directory $aproj -Force | Out-Null
"# AGENTS`n## Build & Test`n" | Set-Content (Join-Path $aproj 'AGENTS.md')
$sj = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 's1'; tool_input = @{ command = 'dotnet build MyApp.sln' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj
Assert-Case -Name "suggest: dotnet build 첫 실행 제안" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj
Assert-Case -Name "suggest: 같은 세션 2회째 억제" -R $r -ExpectExit 0 -ExpectSilent $true
"# AGENTS`n## Build & Test`n- dotnet build" | Set-Content (Join-Path $aproj 'AGENTS.md')
$sj2 = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 's2'; tool_input = @{ command = 'dotnet build MyApp.sln' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj2
Assert-Case -Name "suggest: AGENTS.md 기재 시 억제(self-terminating)" -R $r -ExpectExit 0 -ExpectSilent $true

# [T6] 오탐 2종 차단 — 명령의 대상이 이 프로젝트가 아니거나, 애초에 명령이 아닌 경우.
#   둘 다 실측에서 나왔다(2026-08-23): 다른 레포로 cd 해 돌린 명령과, AGENTS.md를 쓰는
#   heredoc 본문에 들어 있던 명령 문자열이 「이번에 실행한 명령」으로 잡혔다.
$bproj = Join-Path $work 'bproj'; New-Item -ItemType Directory $bproj -Force | Out-Null
"# AGENTS`n" | Set-Content (Join-Path $bproj 'AGENTS.md')
$sjCd = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6a'; tool_input = @{ command = ('cd "' + $bproj + '" && cargo build') } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjCd
Assert-Case -Name "suggest: 다른 레포 대상 명령은 제안 안 함 (오탐 차단)" -R $r -ExpectExit 0 -ExpectSilent $true
$sjHd = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6b'; tool_input = @{ command = ("python - <<'EOF'`ndoc = 'cargo build'`nEOF") } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjHd
Assert-Case -Name "suggest: heredoc 본문의 명령 문자열은 제안 안 함 (오탐 차단)" -R $r -ExpectExit 0 -ExpectSilent $true
# 델타 음성 — 새 경계가 정상 발화까지 막지 않는지 본다(통과만 확인하는 무회귀 케이스로는 근거가 안 된다).
$sjSame = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6c'; tool_input = @{ command = ('cd "' + $aproj + '" && cargo build') } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjSame
Assert-Case -Name "suggest: cd 대상이 이 프로젝트면 종전대로 제안 (델타 음성)" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
# 상대 경로는 **명령이 돈 위치** 기준으로 푼다 — hook 프로세스의 cwd로 풀면 `cd tests && dotnet test`
#   같은 흔한 형태가 해석 실패로 조용히 억제된다(리뷰가 잡은 결함).
#   그리고 경계는 **하위트리 포함**이다 — 같은 레포 안에서 옮겨 실행해도 판정 대상 AGENTS.md는
#   여전히 루트 그것이라 오탐이 아니다(FR-8이 겨냥한 것은 「다른 레포」).
New-Item -ItemType Directory (Join-Path $aproj 'sub') -Force | Out-Null
$sjRel = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6d'; tool_input = @{ command = 'cd sub && cargo build' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjRel
Assert-Case -Name "suggest: 상대 cd 하위폴더는 같은 레포라 제안 (델타 음성)" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
$sjDot = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6e'; tool_input = @{ command = 'cd . && cargo build' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjDot
Assert-Case -Name "suggest: 상대 cd . 은 같은 폴더라 종전대로 제안 (델타 음성)" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
# 여러 번 옮겼으면 **순서대로 누적**해 최종 위치를 구한다. 줄 시작이 아닌 `&&` 뒤 cd도 본다.
$sjChain = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6f'; tool_input = @{ command = ('npm ci && cd "' + $bproj + '" && cargo build') } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjChain
Assert-Case -Name "suggest: 체이닝된 cd 대상이 다른 레포면 제안 안 함" -R $r -ExpectExit 0 -ExpectSilent $true
# cd가 없으면 판정 대상은 cwd다 — 인자에 다른 경로가 있어도 종전 동작을 유지한다(범위를 넓히지 않는다).
$sjNoCd = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6g'; tool_input = @{ command = ('cargo build --manifest-path "' + $bproj + '\Cargo.toml"') } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjNoCd
Assert-Case -Name "suggest: cd 없는 명령은 종전대로 cwd 기준 (범위 미확대)" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
# **cd 등장 횟수**가 이 게이트의 실제 분기 변수다 — 0·1은 위에서 덮었고 여기서 2·3홉을 덮는다.
#   1홉만 보고 「마지막 cd를 cwd 기준으로 푼다」로 짰더니 2홉에서 틀렸다(`cd sub && cd ..`은 제자리인데
#   부모로 계산돼 정상 명령이 억제됐다). 케이스를 요구사항 문구가 아니라 분기 변수로 고른다.
New-Item -ItemType Directory (Join-Path $aproj 'sub\nested') -Force | Out-Null
$sjHop2Back = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6h'; tool_input = @{ command = 'cd sub && cd .. && cargo build' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjHop2Back
Assert-Case -Name "suggest: 2홉 cd가 제자리로 돌아오면 제안 (델타 음성)" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
$sjHop2Out = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6i'; tool_input = @{ command = 'cd sub && cd nested && cargo build' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjHop2Out
Assert-Case -Name "suggest: 2홉 cd로 더 깊이 들어가도 같은 레포면 제안 (델타 음성)" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'
# **접두가 겹치는 형제 경로**는 하위트리가 아니다 — 구분자를 붙여 비교하지 않으면 `<proj>`가
#   `<proj>-sibling`을 삼켜 다른 레포를 같은 레포로 오인한다(하위트리 판정을 넓힌 대가로 생기는 사각).
$sibling = $aproj + '-sibling'
New-Item -ItemType Directory $sibling -Force | Out-Null
$sjSib = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6k'; tool_input = @{ command = ('cd "' + $sibling + '" && cargo build') } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjSib
Assert-Case -Name "suggest: 접두만 겹치는 형제 경로는 제안 안 함 (하위트리 오인 차단)" -R $r -ExpectExit 0 -ExpectSilent $true
# **레포 밖으로 나가는 축**은 위 세 홉 케이스가 덮지 못한다 — 그것들은 전부 제자리로 돌아온다.
#   하위트리를 포함하도록 넓혔어도 상위로 벗어난 것은 여전히 이 프로젝트의 사실이 아니다.
$sjUp = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6l'; tool_input = @{ command = 'cd .. && cargo build' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjUp
Assert-Case -Name "suggest: cd ..로 레포 밖으로 나가면 제안 안 함" -R $r -ExpectExit 0 -ExpectSilent $true
$sjHop3 = @{ tool_name = 'Bash'; cwd = $aproj; session_id = 't6j'; tool_input = @{ command = 'cd sub && cd nested && cd ../.. && cargo build' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'suggest-agents-record.ps1' $sjHop3
Assert-Case -Name "suggest: 3홉 cd가 제자리로 돌아오면 제안 (델타 음성)" -R $r -ExpectExit 0 -ExpectContains 'AGENTS 기록 제안'

# [H5/T4] 30일 지난 상태 마커 자동 정리 — 수정 후 삭제가 기대
$stateDir = Join-Path $iso '.claude/.state/suggest-agents-record'
New-Item -ItemType Directory $stateDir -Force | Out-Null
$oldMarker = Join-Path $stateDir 'old_session_proj_build'
New-Item -ItemType File $oldMarker -Force | Out-Null
(Get-Item $oldMarker).LastWriteTime = (Get-Date).AddDays(-40)
$r = Invoke-Hook 'suggest-agents-record.ps1' $sj2   # 아무 실행이나 1회 (정리 트리거)
$cleaned = -not (Test-Path -LiteralPath $oldMarker)
Assert-Case -Name "suggest: 30일 경과 마커 자동 정리 (H5)" -R @{ code = ([int](-not $cleaned)); out = '' } -ExpectExit 0
}   # ---- §5 게이트 끝 (suggest-agents-record) ----

