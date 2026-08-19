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
$spQ  = [char]39
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
    # [v1.182.0 T1] 대장 「secret-patterns 탐지 정밀도」 병합 4형태 중 ⓐⓒⓓ (ⓑ 도메인형 pw는 의도라 제외).
    #   연결 문자열 픽스처는 키와 '='를 반드시 분리 조립한다 — 붙여 두면 이 러너 파일 자신이
    #   확대된 DB 패턴에 걸려 커밋 게이트에 차단된다(아래 (d2) 주석과 같은 이유).
    @{ n = 'ⓐ 중간 키 + User Id 표기';        t = 'Server' + '=' + 'sqlhost' + ';' + 'Database' + '=' + 'appdb' + ';' + 'User Id' + '=' + 'sa' + ';'; e = 'DB 연결 문자열' }
    @{ n = 'ⓒ 줄 분리형 쌍';                  t = "관리자 계정: $spBt$spId$spBt`n비밀번호: $spBt$spPw$spBt";           e = 'password 값,자격증명 쌍' }
    @{ n = 'ⓒ 마크다운 표 쌍';                t = "| 계정 | $spBt$spId$spBt |`n| 비밀번호 | $spBt$spPw$spBt |";        e = '자격증명 쌍' }
    @{ n = 'ⓓ 음성: 상태·에러코드 열거';      t = '계정 상태: ' + 'ERR_401' + ' / ' + 'ERR_402';                       e = '' }
    # 델타 음성 3종 — 확대분(중간 키 허용)이 **실제로 평가되는** 형태만 고른다. 앵커(`Server=`·
    #   `Data Source=`)를 못 넘는 문자열은 확대분에 닿지도 못해 무회귀 케이스에 불과하다.
    @{ n = '음성 델타: 무관 키만 나열';        t = 'Server' + '=' + 'sqlhost' + ';' + 'Timeout' + '=' + '30' + ';';     e = '' }
    @{ n = '음성 델타: User Interface 키';     t = 'Server' + '=' + 'sqlhost' + ';' + 'User Interface' + '=' + 'dark' + ';'; e = '' }
    @{ n = '음성 델타: Data Source + Encrypt'; t = 'Data Source' + '=' + 'sqlhost' + ';' + 'Encrypt' + '=' + 'true' + ';'; e = '' }
    # [v1.182.0 T8] 줄 분리형 경계의 델타 음성 — **이 자리가 비어 있던 것이 F-7 BLOCKER의 실질**이다.
    #   확대 초안은 라벨 슬랙 40자 + 사이 줄 2줄을 허용해 아래 셋을 전부 차단 등급으로 잡았다.
    #   셋 다 평범한 문서 표기이고, 이 라벨은 exit 2라 오탐 하나가 자율 루프를 세운다.
    @{ n = 'T8 음성: 표의 무관한 두 라벨(계정 유형/비밀번호 규칙)';
       t = "| 계정 유형 | $spBt$spId$spBt |`n| 설명 | 관리자 계정 |`n| 비밀번호 규칙 | $spBt" + '8자이상#특수' + "$spBt |"; e = '' }
    @{ n = 'T8 음성: 콜론형 무관 라벨(계정 목록/최소 길이)';
       t = "계정 목록: $spBt$spId$spBt`n비고: 정책 참고`n비밀번호 최소 길이: $spBt" + '12자리이상#' + "$spBt"; e = '' }
    @{ n = 'T8 음성: 맞붙었지만 라벨이 다르다(비밀번호 파일)';
       t = "| 계정 | $spBt$spId$spBt |`n| 비밀번호 파일 | $spBt" + 'secrets.yml2' + "$spBt |"; e = '' }
    # [v1.182.0 T9] **값 축** 델타 음성 — 값이 아니라 **참조**를 적은 자리다. 이 형태는 hook 자신이
    #   차단 메시지에서 권장하는 것("환경변수 이름만 남긴 뒤 다시 commit")이라, 차단하면 안내를 따른
    #   문서가 도리어 막힌다. 경고 라벨(`password 값`)까지 없애는 것이 아니라 **차단 등급만** 뺀다.
    @{ n = 'T9 음성: $env: 참조';        t = "계정: $spQ$spId$spQ`n비밀번호: $spQ" + '$env:DB_PASSWORD' + $spQ; e = '' }
    @{ n = 'T9 음성: %VAR% 참조(표)';    t = "| 계정 | $spQ" + 'svcuser' + "$spQ |`n| 비밀번호 | $spQ" + '%DB_PASS%' + "$spQ |"; e = '' }
    @{ n = 'T9 음성: ${VAR} 참조';       t = "계정: $spQ$spId$spQ`n비밀번호: $spQ" + '${DB_PASSWORD}' + $spQ; e = '' }
    @{ n = 'T9 음성: process.env 조회';  t = "계정: $spQ$spId$spQ`n비밀번호: $spQ" + 'process.env.DB_PASS1' + $spQ; e = '' }
    @{ n = 'T9 음성: os.environ 조회';   t = "계정: $spQ$spId$spQ`n비밀번호: $spQ" + 'os.environ[DB_PASS1]' + $spQ; e = '' }
    @{ n = 'T9 음성: 설정 키 경로';      t = "계정: $spQ$spId$spQ`n비밀번호: $spQ" + 'appsettings:Db:Pwd1' + $spQ; e = 'password 값' }
    # 한 줄 슬래시형은 **v1.119.0부터** 같은 오차단을 갖고 있었다(BASE 실측 확인). 공유 판정에 제외를
    #   넣어 함께 닫혔으므로 그 경로도 고정한다.
    @{ n = 'T9 음성: 한 줄 슬래시 + $env: (기존 결함)';
       t = "계정: $spQ$spId$spQ / $spQ" + '$env:DB_PASSWORD' + $spQ; e = '' }
    # 제외가 과하지 않은지 — 실제 비밀번호가 `%`로 끝나거나 콜론을 품어도 그대로 검출돼야 한다.
    @{ n = 'T9 양성 가드: % 로 끝나는 실값'; t = "관리자 계정: $spBt$spId$spBt / ${spBt}Secret99%$spBt";  e = '자격증명 쌍' }
    @{ n = 'T9 양성 가드: 콜론 + 특수문자 실값'; t = "관리자 계정: $spBt$spId$spBt / ${spBt}Pa55:word!$spBt"; e = '자격증명 쌍' }
    # ⚠ **의도된 희생을 음성으로 명시한다** — 특수문자 없이 콜론으로 이어진 실값은 설정 키 경로와
    #   구조가 같아 함께 미탐된다. 위 양성 가드는 `!` 때문에 이 규칙을 **비껴가므로** 이 방어선을
    #   검증하지 못한다(그 사각을 T9 quality 리뷰가 지적했다). 경고 계층은 그대로 발화한다.
    @{ n = 'T9 음성(의도된 희생): 특수문자 없는 콜론 실값';
       t = "관리자 계정: $spBt$spId$spBt / ${spBt}Secret1:King2$spBt"; e = '' }
    # [F-7 2R m3] **인접 요구를 단독으로 검증**한다 — 라벨은 정확하고 사이 줄만 있다. 차단 등급은
    #   빠지고 경고(`password 값`)는 남는다. 이 케이스가 없으면 인접 요구를 되돌려도 골든이 green이다.
    @{ n = 'T9 음성: 라벨은 정확하나 사이 줄이 있다(인접 요구 단독)';
       t = "계정: $spBt$spId$spBt`n비고: 정책 참고`n비밀번호: $spBt$spPw$spBt"; e = 'password 값' }
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
    # 중간 키·공백 표기 수용은 v1.182.0 T1에서 닫혔고 위 $spCases가 함수 단위로 검증한다.
    #   여기서 보는 것은 그 라벨이 **hook 레벨에서 실제로 차단(exit 2)까지 가는가**이므로,
    #   패턴 형태는 가장 단순한 것을 쓴다(라벨 판정 자체는 위에서 이미 전수 대조된다).
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

    # ---- [v1.182.0 T5] $autoStage 오판정 — `git add -A`가 보완 스캔을 두 번 돌리던 문제 ----
    # 판정 대상이 **호출 횟수**라 hook 출력으로는 볼 수 없다. 자식 프로세스에서 lib를 dot-source하고
    #   `Get-DiffHeadAdded`를 세는 함수로 덮어써 실제 호출 수를 읽는다 — 러너 프로세스에서 덮어쓰면
    #   같은 세션의 다른 케이스가 그 가짜 함수를 쓰게 되므로 반드시 분리한다.
    $wcsF = Join-Path $work 'wcsautostage'; New-Item -ItemType Directory $wcsF -Force | Out-Null
    Push-Location $wcsF
    git init -q; git config user.email t@t; git config user.name t
    'v=1' | Set-Content app.js; git add .; git commit -qm init
    Add-Content app.js 'v=2'
    Pop-Location
    $t5Probe = Join-Path $work 't5-autostage-probe.ps1'
    @(
        'param([string]$Cwd, [string]$Cmd)',
        ('. ' + [char]39 + (Join-Path $scriptsDir 'bash-hook-lib.ps1') + [char]39),
        '$script:ghCalls = 0',
        'function Get-DiffHeadAdded { param([string[]]$PathArgs = @()) $script:ghCalls++; return @() }',
        '$null = Invoke-WarnCommitSecrets @{ cwd = $Cwd; tool_input = @{ command = $Cmd } }',
        '"CALLS=$script:ghCalls"'
    ) | Set-Content -LiteralPath $t5Probe -Encoding utf8
    $t5Cases = @(
        @{ n = "'add -A && commit -m' 보완 스캔 1회 (T5 — 종전 2회)"; c = 'git add -A && git commit -m x'; e = 1 }
        @{ n = "'commit -am' 자동 스테이징 분기 유지 (T5)";            c = 'git commit -am x';             e = 1 }
        @{ n = "'commit -m'만이면 보완 스캔 0회 (T5)";                 c = 'git commit -m x';              e = 0 }
        @{ n = "'add -A && commit -am' 두 분기 각각 정당 발화 (T5)";   c = 'git add -A && git commit -am x'; e = 2 }
        # 세그먼트 한정이 만든 두 회귀 경로 — 리뷰가 재현으로 잡았다. 순서(메시지 제거 → 분리)와
        #   줄 연속 정규화가 없으면 각각 오탐·미탐이 된다.
        @{ n = "메시지 속 세미콜론이 -a 오탐을 만들지 않음 (T5 M2)";  c = 'git commit -m "fix -a bug; deploy"'; e = 0 }
        @{ n = "백슬래시 줄 연속 'commit -am' 미탐 없음 (T5 M1)";     c = ("git commit " + [char]92 + "`n  -am " + [char]34 + 'msg' + [char]34); e = 1 }
        # 메시지 제거 정규식의 나머지 두 대안(작은따옴표·--message=) — 구조상 커버되지만 골든에
        #   없으면 회귀 시 조용히 깨진다(2R 리뷰 m1).
        @{ n = "작은따옴표 메시지 속 -a 오탐 없음 (T5 2R m1)";       c = ("git commit -m " + [char]39 + 'fix -a bug' + [char]39); e = 0 }
        @{ n = "--message= 형태 메시지 속 -a 오탐 없음 (T5 2R m1)";  c = ('git commit --message=' + [char]34 + 'fix -a bug' + [char]34); e = 0 }
    )
    foreach ($t5 in $t5Cases) {
        $t5Out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $t5Probe -Cwd $wcsF -Cmd $t5.c 2>&1
        $t5Got = ([regex]::Match(($t5Out -join "`n"), 'CALLS=(\d+)')).Groups[1].Value
        if ($t5Got -eq [string]$t5.e) {
            $script:results.Add(@{ ok = $true; line = "[PASS] commit-secrets: $($t5.n)" })
        } else {
            $script:results.Add(@{ ok = $false; line = "[FAIL] commit-secrets: $($t5.n) — 기대 $($t5.e), 실제 '$t5Got'" })
        }
    }

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
    # [v1.182.0 T6 ⓐ] stderr 한글 경고가 **깨지지 않고** 판정 대상에 담기는지 — 디코딩의 회귀 가드.
    #   종전에는 콘솔 코드페이지 탓에 이 문자열이 깨져 영문 앵커만 걸 수 있었다.
    Assert-Case -Name "commit-secrets: diff HEAD 실패 경고의 한글이 온전하다(h1, T6 디코딩 가드)" -R $r -ExpectExit 2 -ExpectContains '보완 스캔 미수행'

    # (h2) 같은 상태에서 무해한 내용이면 차단되지 않는다 — 폴백이 오차단을 만들지 않는다
    Push-Location $wcsE; Set-Content README.md @('# 프로젝트 소개', '설치 방법은 아래를 보세요.'); Pop-Location
    $r = Invoke-Hook 'warn-commit-secrets.ps1' (@{ tool_name = 'Bash'; cwd = $wcsE; tool_input = @{ command = 'git add -A && git commit -m init' } } | ConvertTo-Json -Compress)
    Assert-Case -Name "commit-secrets: HEAD 없는 저장소 무해 내용 무차단(h2, 폴백 오차단 0)" -R $r -ExpectExit 0

    # ---- [v1.182.0 T6 ⓑ] 폴백 경고의 1회 억제·리셋 ----
    # h1/h2로는 **구조상 검증할 수 없다** — 케이스마다 별도 pwsh 프로세스라 `$script:diffHeadFailNotified`가
    #   매번 새로 초기화되고, 그래서 리셋을 지워도 두 케이스 다 green이 된다(가드가 아니었다).
    # 한 프로세스에서 `Invoke-WarnCommitSecrets`를 2회 부르고 stderr를 StringWriter로 가로채 센다 —
    #   프로세스 밖으로 내보내지 않으므로 콘솔 인코딩이 판정에 끼어들지 않는다.
    # 명령은 `add -A && commit -am`이다: 한 호출 안에서 실패 경로가 둘(자동 스테이징·add 전체 스캔)이라
    #   억제가 없으면 1회 호출만으로 2회 나온다.
    $t6Probe = Join-Path $work 't6-notify-probe.ps1'
    @(
        'param([string]$Cwd, [int]$Calls = 1)',
        ('. ' + [char]39 + (Join-Path $scriptsDir 'bash-hook-lib.ps1') + [char]39),
        '$sw = New-Object System.IO.StringWriter',
        '$prevErr = [Console]::Error',
        '[Console]::SetError($sw)',
        'try {',
        '    for ($i = 0; $i -lt $Calls; $i++) {',
        # ⚠ 연결식은 반드시 괄호로 묶는다 — 배열 리터럴 안에서는 쉼표가 `+`보다 먼저 묶여
        #   `'a' + $c + 'b', 'd'`가 `'a' + $c + ('b','d')`로 읽히고, 그러면 한 줄이 여러 줄로 쪼개진다.
        ('        $null = Invoke-WarnCommitSecrets @{ cwd = $Cwd; tool_input = @{ command = ' + [char]39 + 'git add -A && git commit -am x' + [char]39 + ' } }'),
        '    }',
        '} finally { [Console]::SetError($prevErr) }',
        ('"COUNT=" + ([regex]::Matches($sw.ToString(), ' + [char]39 + 'git diff HEAD' + [char]39 + ')).Count')
    ) | Set-Content -LiteralPath $t6Probe -Encoding utf8
    foreach ($t6 in @(
        @{ n = '한 호출 안에서 폴백 경고는 1회만 (T6 ⓑ-2 억제)'; k = 1; e = 1 }
        @{ n = '두 번째 호출에서 경고가 다시 난다 (T6 ⓑ-1 리셋)'; k = 2; e = 2 }
    )) {
        $t6Out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $t6Probe -Cwd $wcsE -Calls $t6.k 2>&1
        $t6Got = ([regex]::Match(($t6Out -join "`n"), 'COUNT=(\d+)')).Groups[1].Value
        if ($t6Got -eq [string]$t6.e) {
            $script:results.Add(@{ ok = $true; line = "[PASS] commit-secrets: $($t6.n)" })
        } else {
            $script:results.Add(@{ ok = $false; line = "[FAIL] commit-secrets: $($t6.n) — 기대 $($t6.e), 실제 '$t6Got'" })
        }
    }

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

