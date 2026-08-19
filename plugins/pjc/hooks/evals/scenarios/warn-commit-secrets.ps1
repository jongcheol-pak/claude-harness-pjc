# scenarios/warn-commit-secrets.ps1 — warn-commit-secrets 시나리오 (§9 — 라벨 판정·스캔 범위·등급별 차단) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 9) warn-commit-secrets 시나리오 (git 필요 — 커밋 시점 스테이징 스캔)
# =====================================================================
# 무상태 음성(비커밋·--dry-run)은 스테이징 상태가 필요 없지만, 양성(스테이징 시크릿·-am)은 git 상태 필요.
# 러너 파일 자체가 자사 시크릿 스캐너·post-write hook에 오탐되지 않게 가짜 값은 문자열 연결로 분리 기재.
# 게이트 태그 2개: 내부 dispatch 동등성·고유 분기가 이 섹션의 $wcs git 상태를 공유(초과 실행 허용).
if (Test-HookSelected @('warn-commit-secrets', 'pre-bash-dispatch')) {

# ---- [v1.119.0] secret-patterns 라벨 판정 (함수 단위 — hook 실행 전 단계) ----
# 실사고: README의 "관리자 계정: `<id>` / `<pw>`"가 종전 7패턴 어디에도 안 걸려 공개 커밋됐다.
# 자격증명 쌍은 오탐이 곧 커밋 차단(자율 루프 정지)이라, 양성만큼 음성(정상 문서)이 중요하다 —
#   경로·라우트·파일명·버전·역할 열거는 반드시 통과해야 한다.
. (Join-Path $scriptsDir 'secret-patterns.ps1')
$spId = 'ad' + 'min'
$spPw = 'Zq7' + '#mK21'
$spBt = [char]96
$spCases = @(
    @{ n = '인용 쌍 → 자격증명 쌍(고신뢰)';   t = "관리자 계정: $spBt$spId$spBt / $spBt$spPw$spBt";                  e = '자격증명 쌍' }
    @{ n = '비인용 쌍 → 경고 라벨';           t = "계정: $spId / $spPw";                                             e = '자격증명 쌍(비인용)' }
    @{ n = '한글 비밀번호 값';                t = '비밀번호: ' + 'Zq7' + '#mK21';                                    e = 'password 값' }
    @{ n = '음성: 한글 대비 문구';            t = '계정 종류: 관리자 / 일반 사용자';                                 e = '' }
    @{ n = '음성: 코드 심볼';                 t = 'AdminService / UserService_v2';                                    e = '' }
    @{ n = '음성: 표·경로';                   t = '| admin | /api/v1/users |';                                        e = '' }
    @{ n = '음성: 환경변수 안내';             t = '비밀번호: 환경변수 PD_ADMIN_PASSWORD로 지정';                     e = '' }
    @{ n = '음성: API 라우트';                t = '계정 생성 API: POST /api/v1/accounts';                             e = '' }
    @{ n = '음성: 파일 경로 쌍';              t = '관리자 계정 설정: appsettings.json / appsettings.Production.json'; e = '' }
    @{ n = '음성: 버전 쌍';                   t = '계정 서비스 v1.2 / v1.3';                                          e = '' }
    @{ n = '음성: 미열거 확장자';             t = '계정 설정 파일: config.yml / config.production.yml';               e = '' }
    @{ n = '음성: 역할 열거형';               t = '계정 유형: admin / super_admin';                                   e = '' }
    # T1 리뷰 지적분 — 골든에 없어 통과했던 구멍 3종
    @{ n = 'ID/PW 키워드 쌍';                 t = "ID/PW: $spBt$spId$spBt / $spBt$spPw$spBt";                        e = '자격증명 쌍' }
    @{ n = '음성: 각괄호 플레이스홀더';       t = "관리자 계정: $spBt$spId$spBt / $spBt<PASSWORD123>$spBt";          e = '' }
    @{ n = '음성: 인용부호 짝 불일치';        t = "관리자 계정: $($spBt)$spId`" / `"$spPw$spBt";                     e = '' }
    # F-7 지적분 — 공개 GitHub의 다수가 영문 README다. 한글 \b는 어절 경계와 어긋나 무공백을 놓쳤다.
    @{ n = '영문 account 쌍';                 t = "Default account: $spBt$spId$spBt / $spBt$spPw$spBt";               e = '자격증명 쌍' }
    @{ n = '영문 credentials 쌍';             t = "Credentials: $spBt$spId$spBt / $spBt$spPw$spBt";                   e = '자격증명 쌍' }
    @{ n = '무공백 관리자계정';               t = "관리자계정: $spBt$spId$spBt / $spBt$spPw$spBt";                    e = '자격증명 쌍' }
    @{ n = 'test 접두 실계정(testadmin)';     t = "계정: ${spBt}testadmin$spBt / $spBt$spPw$spBt";                    e = '자격증명 쌍' }
    @{ n = '음성: 영문 설정값(login: true)';  t = 'login: true / false';                                              e = '' }
    @{ n = '음성: 영문 라우트(account API)';  t = 'account API: GET /api/v1/accounts';                                e = '' }
    @{ n = '음성: 영문 예시 플레이스홀더';    t = "Login: ${spBt}example$spBt / ${spBt}your-password$spBt";           e = '' }
)
foreach ($sc in $spCases) {
    $got = (@(Get-SecretMatches $sc.t) -join ',')
    $ok = if ($sc.e -eq '') { $got -eq '' } else { $got -eq $sc.e }
    if ($ok) {
        $script:results.Add(@{ ok = $true; line = "[PASS] secret-patterns: $($sc.n)" })
    } else {
        $script:results.Add(@{ ok = $false; line = "[FAIL] secret-patterns: $($sc.n) — 기대 '$($sc.e)', 실제 '$got'" })
    }
}
# 고신뢰 라벨 집합 — warn-commit-secrets 차단 기준(T2). 집합이 조용히 바뀌면 차단 범위가 바뀐다.
$hcExpect = @('개인키', 'DB 연결 문자열', 'DB/서비스 URI 인증정보', '자격증명 쌍')
$hcGot = @(Get-HighConfidenceSecretLabels)
if (-not (Compare-Object $hcExpect $hcGot)) {
    $script:results.Add(@{ ok = $true; line = '[PASS] secret-patterns: 고신뢰 라벨 집합 4종' })
} else {
    $script:results.Add(@{ ok = $false; line = "[FAIL] secret-patterns: 고신뢰 라벨 집합 불일치 — 실제 '$($hcGot -join ',')'" })
}

if ($gitOk) {
    $wcs = Join-Path $work 'wcsrepo'; New-Item -ItemType Directory $wcs -Force | Out-Null
    Push-Location $wcs
    git init -q; git config user.email t@t; git config user.name t
    'v=1' | Set-Content app.js; git add .; git commit -qm init
    Pop-Location
    $fakeApi = 'api_key = "' + 'ABCDEF1234567890' + '"'
    $wcsJson = @{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m test' } } | ConvertTo-Json -Compress

    # 1) staged 시크릿 → 경고
    Push-Location $wcs; Set-Content secret.js $fakeApi; git add secret.js; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsJson
    Assert-Case -Name "commit-secrets: staged 시크릿 경고" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # 2) --dry-run → 스킵(무출력)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit --dry-run' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: --dry-run 스킵(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true

    # 3) .env 스테이징 → 파일명 경고
    Push-Location $wcs; Set-Content .env 'v=1'; git add -f .env; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsJson
    Assert-Case -Name "commit-secrets: .env 스테이징 경고" -R $r -ExpectExit 0 -ExpectContains '.env'

    # 4) 클린 스테이징(시크릿·.env 제거) → 무출력(음성)
    Push-Location $wcs
    git rm -q --cached secret.js .env; Remove-Item secret.js, .env -Force
    'clean=1' | Set-Content ok.txt; git add ok.txt; git commit -qm clean
    Pop-Location
    Push-Location $wcs; 'more=1' | Set-Content ok.txt; git add ok.txt; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsJson
    Assert-Case -Name "commit-secrets: 클린 스테이징 무출력(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

    # 5) -am 자동 스테이징분(추적 파일 시크릿) → 경고
    Push-Location $wcs; git commit -qm ok2; Add-Content app.js $fakeApi; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -am update' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: -am 자동스테이징 시크릿 경고" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # 6) 같은 미스테이징 변경 + -m(자동스테이징 아님) → 무출력(음성 — 메시지 속 -a 오탐 없음 포함)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m update' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: -m 미스테이징 미탐(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

    # 7) git commit 아님 → 통과(무출력, fast path)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git status' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: git commit 아님 통과(무출력)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [v1.119.0] 고신뢰 라벨 커밋 차단 (exit 2) ----
    # 상태 오염을 피하려고 별도 repo를 쓴다(위 $wcs는 케이스 1~7이 순서 의존으로 공유).
    # 픽스처는 러너 자신이 자사 스캐너·post-write hook에 걸리지 않게 문자열 연결로 분리 기재한다.
    $wcsB = Join-Path $work 'wcsblock'; New-Item -ItemType Directory $wcsB -Force | Out-Null
    Push-Location $wcsB
    git init -q; git config user.email t@t; git config user.name t
    'v=1' | Set-Content app.js; git add .; git commit -qm init
    Pop-Location
    $wcsBJson = @{ tool_name = 'Bash'; cwd = $wcsB; tool_input = @{ command = 'git commit -m test' } } | ConvertTo-Json -Compress
    $btB = [char]96
    $credLine = '기본 관리자 계정: ' + $btB + 'ad' + 'min' + $btB + ' / ' + $btB + 'Zq7' + '#mK21' + $btB

    # (a) 자격증명 쌍(고신뢰) 스테이징 → 차단 + 회복 경로 2종 안내
    Push-Location $wcsB; Set-Content README.md $credLine; git add README.md; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 자격증명 쌍 커밋 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    Assert-Case -Name "commit-secrets: 차단 메시지에 우회 변수 안내" -R $r -ExpectExit 2 -ExpectContains 'CLAUDE_HARNESS_ALLOW_SECRET'
    # 우회 변수는 세션 시작 전에만 설정 가능하다 — Bash 도구로 설정해도 hook에 전파되지 않는다(M8).
    Assert-Case -Name "commit-secrets: 차단 메시지에 세션 시작 전 설정 안내" -R $r -ExpectExit 2 -ExpectContains '시작 전 터미널'

    # (b) QUICK=1이어도 차단 유지 — 안전 임계 게이트는 QUICK에 종속되지 않는다(M6).
    $env:CLAUDE_HARNESS_QUICK = '1'
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: QUICK=1이어도 자격증명 차단 유지" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    $env:CLAUDE_HARNESS_QUICK = $null

    # (c) 전용 escape hatch → 통과(경고). 오탐 시 사용자가 빠져나갈 문이 있어야 한다.
    $env:CLAUDE_HARNESS_ALLOW_SECRET = '1'
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: ALLOW_SECRET=1 우회(경고, exit 0)" -R $r -ExpectExit 0 -ExpectContains 'ALLOW_SECRET'
    $env:CLAUDE_HARNESS_ALLOW_SECRET = $null

    # (d) 개인키(고신뢰) → 차단
    Push-Location $wcsB
    git rm -q --cached README.md; Remove-Item README.md -Force
    Set-Content key.pem ('-----BEGIN RSA ' + 'PRIVATE KEY-----'); git add key.pem
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 개인키 커밋 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (d2) DB 연결 문자열(고신뢰) → 차단. 고신뢰 4종 중 hook 레벨 실증이 빠지면 $highConf 필터
    #      버그를 함수 단위 테스트로는 못 잡는다.
    Push-Location $wcsB
    git rm -q --cached key.pem; Remove-Item key.pem -Force
    # 기존 DB 패턴은 'Server=<v>;' 바로 뒤 User/Pwd/Password 키를 요구한다(secret-patterns.ps1:29).
    #   'User Id='(공백)·중간 키(Database=…)가 끼면 미탐 — 기존 결함이라 plan Deferred에 등록했고,
    #   여기서는 패턴이 실제로 잡는 유효 형태로 차단 경로를 실증한다.
    # 키 이름과 '='를 반드시 분리해 조립한다 — 한 리터럴에 붙여 두면 이 러너 파일(과 그 주석!)
    #   자체가 자사 커밋 게이트에 차단된다(실측으로 두 번 걸렸다).
    $dbConn = 'Server' + '=' + 'prod-sql' + ';' + 'Pwd' + '=' + 'Zq7#mK21' + ';'
    Set-Content db.config $dbConn; git add db.config
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: DB 연결 문자열 커밋 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (e) 저신뢰(비인용 자격증명 쌍) → 경고만. 차단 범위가 넓어지면 여기서 잡힌다.
    Push-Location $wcsB
    git rm -q --cached db.config; Remove-Item db.config -Force
    Set-Content notes.md ('계정: ' + 'ad' + 'min' + ' / ' + 'Zq7' + '#mK21'); git add notes.md
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 비인용 쌍은 경고만(exit 0)" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # (e2) IP 주소만(저신뢰) → 경고만. 오차단 0의 핵심 회귀 감시 — 차단 범위가 IP까지 넓어지면
    #      문서·설정에 IP를 적는 모든 정상 커밋이 막힌다.
    Push-Location $wcsB
    git rm -q --cached notes.md; Remove-Item notes.md -Force
    Set-Content hosts.md ('배포 서버 ' + '203.0' + '.113.5' + ' 접속'); git add hosts.md
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: IP 주소만은 경고만(exit 0, 오차단 0)" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'

    # (f) 시크릿 제거 후 재커밋 → 통과. 차단이 막다른 골목이 아님을 실증한다.
    Push-Location $wcsB
    git rm -q --cached hosts.md; Remove-Item hosts.md -Force
    'clean=1' | Set-Content ok.txt; git add ok.txt
    Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 시크릿 제거 후 재커밋 통과(회복 가능)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [v1.119.0 F-7 B1] 선행 스테이징 경로 (untracked + 'git add' 한 호출) ----
    # PreToolUse는 명령 실행 '전'에 돈다 — add가 아직 안 돌았으므로 인덱스는 비어 있고 untracked는
    #   git diff HEAD에도 없다. 사고의 실제 경로(신규 프로젝트의 새 README)이자 자율 루프의 표준
    #   커밋 형태(`git add -A && git commit`)라, 여기서 안 잡히면 게이트 전체가 무의미하다.
    $wcsC = Join-Path $work 'wcsuntracked'; New-Item -ItemType Directory $wcsC -Force | Out-Null
    Push-Location $wcsC
    git init -q; git config user.email t@t; git config user.name t
    'v=1' | Set-Content seed.txt; git add .; git commit -qm init
    Set-Content README.md $credLine    # untracked 신규 파일 (스테이징 안 함)
    Pop-Location

    # (h) untracked + 'git add -A && git commit' 한 호출 → 차단
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add -A && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: untracked + 'add -A && commit' 차단(exit 2, F-7 B1)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (i) untracked + 'git add <파일> && git commit' → 차단 (경로 나열 형태)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add README.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: untracked + 'add <파일> && commit' 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (j) 'git add'만 있고 commit 없음 → 무검사 통과 (기존 fast-path 유지)
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add -A' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 'git add'만(commit 없음) 무검사 통과" -R $r -ExpectExit 0 -ExpectSilent $true

    # (j2) 'git add <디렉터리>' — 적대적 우회가 아니라 일상 형태다(`git add src/`). 파일이 아니라서
    #      스킵되면 디렉터리 한 단어로 게이트가 뚫린다(F-7 2회차 M1).
    Push-Location $wcsC; New-Item -ItemType Directory -Path 'docs' -Force | Out-Null; Set-Content 'docs/guide.md' $credLine; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add docs/ && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 'add <디렉터리>/ && commit' 차단(exit 2, F-7 M1)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (j3) 'git add <글롭>' — 파일로 존재하지 않는 인자라 git에게 전개를 맡겨야 한다
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add docs/*.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 'add <글롭> && commit' 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    Push-Location $wcsC; Remove-Item 'docs' -Recurse -Force; Pop-Location

    # (k) 시크릿 없는 신규 파일 + 'add -A && commit' → 통과 (오차단 0 — 정상 신규 커밋을 막지 않는다)
    Push-Location $wcsC; Remove-Item README.md -Force; 'hello world' | Set-Content notes.md; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsC; tool_input = @{ command = 'git add -A && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 시크릿 없는 신규 파일 'add -A && commit' 통과(오차단 0)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [v1.136.0] 경로 나열 Leaf 분기의 추적 인지 (T1 그물) ----
    # HEAD에 고신뢰 픽스처가 '이미' 커밋된 상태가 전제라 기존 repo($wcs·$wcsB·$wcsC — 케이스 순서
    #   의존 공유)와 얽히지 않게 전용 repo를 쓴다(§13 SC 픽스처 분리와 동일 원칙).
    $wcsD = Join-Path $work 'wcstracked'; New-Item -ItemType Directory $wcsD -Force | Out-Null
    Push-Location $wcsD
    git init -q; git config user.email t@t; git config user.name t
    Set-Content fixtures.md $credLine          # 이력 기존 내용 — 재신고 오탐의 원천이던 형태
    'ignored.txt' | Set-Content .gitignore
    git add .; git commit -qm init
    Pop-Location

    # (n1) 추적 파일 + HEAD 픽스처 + 무해 추가 라인 → 무차단 (핵심 델타 — 이력 기존 내용 재신고 제거)
    Push-Location $wcsD; git checkout -q -- .; Add-Content fixtures.md '무해한 안내 라인 추가'; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsD; tool_input = @{ command = 'git add fixtures.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 추적 파일 HEAD 픽스처 + 무해 추가 라인 무차단(n1, v1.136.0)" -R $r -ExpectExit 0 -ExpectSilent $true

    # (n2) 추적 파일 + 추가 라인에 자격증명 쌍 → 차단 유지 (신규 유입 보호 그물)
    Push-Location $wcsD; git checkout -q -- .; Add-Content fixtures.md ('신규 유입: ' + $credLine); Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsD; tool_input = @{ command = 'git add fixtures.md && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: 추적 파일 추가 라인 자격증명 차단(n2, exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (n3) ignored 파일 강제 add + 자격증명 → 차단 유지 (D1 (a) 근거 — untracked 전체 스캔 보존)
    Push-Location $wcsD; git checkout -q -- .; Set-Content ignored.txt $credLine; Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsD; tool_input = @{ command = 'git add -f ignored.txt && git commit -m test' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: ignored 강제 add 자격증명 차단(n3, exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # ---- [v1.181.0 T6] HEAD 없는 저장소 — `git diff HEAD` 실패 폴백 ----
    # `Get-DiffHeadAdded`가 exit≠0을 삼키지 않고 빈 배열 + stderr 경고로 처리한다. 이 경로가
    #   골든에 없으면 「보완 스캔이 조용히 사라져도 아무도 모른다」는 원 결함이 그대로 남는다.
    #   ⚠ 핵심은 **차단이 사라지지 않는 것**이다 — HEAD가 없어도 `--cached`·untracked 전체 스캔이
    #   그대로 돌아야 하고, 실패 경고가 stdout(JSON)을 오염시켜서도 안 된다.
    #   ⚠ 명령을 `git add -A`로 쓰는 것이 이 케이스의 전제다 — `git add <파일명>`은 untracked
    #   직독 경로로 빠져 `Get-DiffHeadAdded`를 아예 호출하지 않는다(2R 리뷰가 재현으로 지적).
    $wcsE = Join-Path $work 'wcsnohead'; New-Item -ItemType Directory $wcsE -Force | Out-Null
    Push-Location $wcsE
    git init -q; git config user.email t@t; git config user.name t   # 커밋 없음 — HEAD 부재
    Set-Content README.md $credLine
    Pop-Location

    # (h1) HEAD 없는 저장소에서도 신규 파일의 자격증명은 차단된다
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsE; tool_input = @{ command = 'git add -A && git commit -m init' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: HEAD 없는 저장소에서도 자격증명 차단(h1, diff HEAD 실패 폴백)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'

    # (h2) 같은 상태에서 무해한 내용이면 차단되지 않는다 — 폴백이 오차단을 만들지 않는다
    Push-Location $wcsE; Set-Content README.md @('# 프로젝트 소개', '설치 방법은 아래를 보세요.'); Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsE; tool_input = @{ command = 'git add -A && git commit -m init' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: HEAD 없는 저장소 무해 내용 무차단(h2, 폴백 오차단 0)" -R $r -ExpectExit 0

    # (g) 디스패처 경유도 동일 차단 — lib 함수 공유라 두 경로가 갈리면 안 된다(D3).
    Push-Location $wcsB; Set-Content README.md $credLine; git add README.md; Pop-Location
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' $wcsBJson
    Assert-Case -Name "commit-secrets: 디스패처 경유 자격증명 차단(exit 2)" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    Push-Location $wcsB; git rm -q --cached README.md; Remove-Item README.md -Force; Pop-Location

    # ---- [v1.99.0 T6] 디스패처 동등성 + 디스패처 고유 분기 (git repo 필요) ----
    # 현재 $wcs 상태: app.js에 시크릿(-am 자동스테이징 대상), ok.txt 미스테이징. 명시 스테이징 시크릿을 다시 심는다.
    Push-Location $wcs; Set-Content secret2.js $fakeApi; git add secret2.js; Pop-Location
    # (a) commit-secrets 양성 → 디스패처 경유도 경고 유지
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' $wcsJson
    Assert-Case -Name "dispatch=commit-secrets: staged 시크릿 경고" -R $r -ExpectExit 0 -ExpectContains 'COMMIT SECRET'
    # (b) 디스패처 고유: block(rtc 미완료) + warn(commit-secrets) 동시 → block 우선 exit 2, warn 경고는 버림(D4)
    "# plan`n- [ ] T7. 미완료" | Set-Content (Join-Path $wcs 'plan.md')
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m "T7: 완료"' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "dispatch: block(rtc)+warn(secret) 동시 → exit 2 차단 우선" -R $r -ExpectExit 2 -ExpectContains 'BLOCKED'
    if (($r.out -match 'COMMIT SECRET')) { $script:results.Add(@{ ok = $false; line = "[FAIL] dispatch: block 시 warn 경고 버림(D4) — COMMIT SECRET가 출력됨" }) }
    else { $script:results.Add(@{ ok = $true; line = "[PASS] dispatch: block 시 warn 경고 버림(D4 트레이드오프)" }) }
    Remove-Item (Join-Path $wcs 'plan.md') -Force -ErrorAction SilentlyContinue
    # (c) 디스패처 고유: warn 2개(external push + commit secret) 병합 → exit 0 + 두 keyword 모두
    $r = Invoke-Hook 'pre-bash-dispatch.ps1' (@{ tool_name = 'Bash'; cwd = $wcs; tool_input = @{ command = 'git commit -m x && git push origin main' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "dispatch: warn 2개 병합 (external) — exit 0" -R $r -ExpectExit 0 -ExpectContains 'EXTERNAL OP'
    if (($r.out -match 'COMMIT SECRET') -and ($r.out -match 'EXTERNAL OP')) { $script:results.Add(@{ ok = $true; line = "[PASS] dispatch: warn 2개(secret+external) additionalContext 병합" }) }
    else { $script:results.Add(@{ ok = $false; line = "[FAIL] dispatch: warn 병합 누락 | 출력: $(($r.out -split "`r?`n" | Select-Object -First 2) -join ' / ')" }) }
} else {
    Write-Host "[SKIP] warn-commit-secrets 시나리오 (git 없음)"
}
}   # ---- §9 게이트 끝 (warn-commit-secrets·pre-bash-dispatch) ----

