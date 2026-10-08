# scenarios/post-write-checks.ps1 — post-write-checks 시나리오 (§6 UTF-8·라인·시크릿 + §7 심볼 영향 + Pre.cs) (dot-source 전용, 단독 실행 금지)
# 호출자(run-hook-evals.ps1)의 공용 헬퍼(Assert-Case·Invoke-Hook·New-WriteJson·New-CommitJson)와 공유 변수($work·$iso·$gitOk·$pw·$vdCache)를 그대로 쓴다.
# 파일명은 검증 대상 hook 기준이고, Invoke-Hook에 넘기는 문자열은 scripts/ 아래 hook 파일명이다.
# ==== 아래는 본체에서 원문 그대로 옮긴 구간 (순수 이동 — 재조립 등가 검사의 경계) ====
# =====================================================================
# 6) post-write-checks 시나리오 (BOM·영문 주석·시크릿 7종·NotebookEdit·비차단)
#    ($pw 픽스처는 top-level 공유 정의 — §7 후속 Pre.cs 블록도 사용)
# =====================================================================
if (Test-HookSelected @('post-write-checks')) {
$csPath = Join-Path $pw 'Big.cs'
$body = (1..6 | ForEach-Object { "// english comment $_" }) + 'var password = "Sup3rSecret99";'
[System.IO.File]::WriteAllText($csPath, ($body -join "`n"), [System.Text.UTF8Encoding]::new($true))  # BOM 포함
$pj = @{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $csPath } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $pj
Assert-Case -Name "post-write: BOM 경고" -R $r -ExpectExit 0 -ExpectContains 'BOM'
Assert-Case -Name "post-write: 영문 주석 경고" -R $r -ExpectExit 0 -ExpectContains '영문'
Assert-Case -Name "post-write: password 값 경고" -R $r -ExpectExit 0 -ExpectContains 'password'
Assert-Case -Name "post-write: 비차단 exit 0" -R $r -ExpectExit 0

# ---- 시크릿 잔여 유형 (API key·DB 연결문자열·URI 자격증명·개인키·Bearer·IP) ----
# 전부 명백한 가짜 값. 개인키 마커·Bearer는 문자열 연결로 분리 기재 — 이 러너 파일 자체가
# 시크릿 스캐너·자사 post-write hook에 오탐되지 않게 한다.
$secPath = Join-Path $pw 'notes-secrets.md'
$fakeKeyMarker = '-----BEGIN RSA ' + 'PRIVATE KEY-----'
$fakeBearer = 'Bear' + 'er FAKETOKEN1234567890abc'
$secBody = @(
    'api_key = "FAKEKEY1234567890"',
    'conn: Server=dbhost;User=app;Password=fakepw123;',
    'uri: postgres://appuser:fakepass123@dbhost/appdb',
    $fakeKeyMarker,
    ('Authorization: ' + $fakeBearer),
    '운영 장비: 10.20.30.40'
) -join "`n"
[System.IO.File]::WriteAllText($secPath, $secBody, [System.Text.UTF8Encoding]::new($false))
$sjp = @{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $secPath } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $sjp
Assert-Case -Name "post-write: API key/token 값 경고" -R $r -ExpectExit 0 -ExpectContains 'API key/token 값'
Assert-Case -Name "post-write: DB 연결 문자열 경고" -R $r -ExpectExit 0 -ExpectContains 'DB 연결 문자열'
Assert-Case -Name "post-write: URI 자격증명 경고" -R $r -ExpectExit 0 -ExpectContains 'DB/서비스 URI 인증정보'

# [회차 44 T6] 참조형 연결 문자열·URI 는 경고하지 않는다(오탐 수정 음성) — 다른 트리거 없는 파일이라 완전 무출력 기대.
$secRefPath = Join-Path $pw 'notes-secrets-ref.md'
# 문자열은 조각으로 조립한다 — 한 리터럴에 붙여 두면 이 러너 파일 자체가 설치본 커밋 게이트(구 판정)에 차단된다(회차 44 실측).
$secRefBody = @(('conn: Ser' + 'ver=dbhost;User=app;Pass' + 'word=' + '${DB_PASSWORD};'), ('uri: post' + 'gres://appuser:' + '%DB_PASS%' + '@dbhost/appdb')) -join "`n"
[System.IO.File]::WriteAllText($secRefPath, $secRefBody, [System.Text.UTF8Encoding]::new($false))
$rRef = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $secRefPath } } | ConvertTo-Json -Compress)   # $r 은 아래 단언들이 계속 쓴다 — 덮어쓰지 않는다
Assert-Case -Name "post-write: 참조형 연결 문자열·URI 무경고 (회차 44 T6 오탐 수정 음성)" -R $rRef -ExpectExit 0 -ExpectSilent $true
Assert-Case -Name "post-write: 개인키 경고" -R $r -ExpectExit 0 -ExpectContains '개인키'
Assert-Case -Name "post-write: Bearer 토큰 경고" -R $r -ExpectExit 0 -ExpectContains 'Bearer 토큰'
Assert-Case -Name "post-write: IP 주소 경고" -R $r -ExpectExit 0 -ExpectContains 'IP 주소'

# ---- IP 음성 3건 (예약 IP·버전 문자열 제외 로직 회귀 가드 — 다른 트리거 없는 파일이라 완전 무출력 기대) ----
$ipnegPath = Join-Path $pw 'ip-neg.md'
[System.IO.File]::WriteAllText($ipnegPath, '로컬 검증은 127.0.0.1 에서 수행.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $ipnegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 예약 IP(127.0.0.1) 무경고(음성)" -R $r -ExpectExit 0 -ExpectSilent $true
$lbnegPath = Join-Path $pw 'lb-neg.md'
[System.IO.File]::WriteAllText($lbnegPath, '보조 루프백 127.0.1.1 과 127.53.0.2 사용.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $lbnegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 루프백 대역(127.0.0.0/8) 무경고(음성)" -R $r -ExpectExit 0 -ExpectSilent $true
$vernegPath = Join-Path $pw 'ver-neg.md'
[System.IO.File]::WriteAllText($vernegPath, 'Version="1.2.3.4" 로 배포.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $vernegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 버전 문자열 IP 무경고(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [L5] 옥텟 초과(999.x)는 IP 아님 — 무경고 (옥텟 0-255 제한 회귀 가드) ----
$octnegPath = Join-Path $pw 'oct-neg.md'
[System.IO.File]::WriteAllText($octnegPath, '식별자 999.999.999.999 는 IP 아님.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $octnegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 옥텟 초과 999.x IP 무경고 (L5)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [T1] 라인 수 검사 제거 회귀 가드 (v1.172.0) ----
# 종전에는 고정 라인 임계를 넘으면 "분리 검토" 경고가 났다. 그 임계를 폐기하고 판정을 규칙 8로
# 옮겼으므로, 대용량 파일이어도 hook은 아무 말도 하지 않아야 한다. ExpectSilent로 고정하면
# 라인 수 경고 재유입뿐 아니라 다른 검사의 우발 발화까지 함께 잡힌다.
$bigPath = Join-Path $pw 'big-2000.md'
[System.IO.File]::WriteAllText($bigPath, (((1..2000 | ForEach-Object { "본문 $_ 번째 줄." }) -join "`n")), [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $bigPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 2000줄 파일 무경고(음성 — 라인 수 임계 폐기)" -R $r -ExpectExit 0 -ExpectSilent $true

# ---- [P1T2] password 값 제외 조건 (타입 선언·env 조회·키워드 — 오탐 방지, v1.98.0) ----
# hook이 권장하는 패턴(환경변수 조회)까지 'password 값'으로 경고하던 늑대소년화 수정의 회귀 가드.
$pwnegPath = Join-Path $pw 'pw-neg.md'
$pwnegBody = @(
    'interface Login { password: string }',
    'pwd = os.getcwd()',
    "db_password = os.getenv('DB_PASSWORD')",
    'password = None'
) -join "`n"
[System.IO.File]::WriteAllText($pwnegPath, $pwnegBody, [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $pwnegPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: password 타입선언·env조회·키워드 무경고 (P1T2 음성)" -R $r -ExpectExit 0 -ExpectSilent $true
# 평문 값은 경고 유지 (제외 조건이 실 시크릿을 놓치지 않는지 — 양성 유지 가드)
$pwposPath = Join-Path $pw 'pw-pos.md'
[System.IO.File]::WriteAllText($pwposPath, 'password = "hunter2fake"', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $pwposPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: password 평문 값 경고 유지 (P1T2 양성)" -R $r -ExpectExit 0 -ExpectContains 'password'

# ---- [P1T2] IP 전체 매치 순회 (first-match-only 양방향 결함 수정, v1.98.0) ----
# 첫 매치가 예약 IP(127.0.0.1)여도 뒤따르는 공인 IP를 검출한다(종전엔 검사가 통째로 끝나던 미탐).
$ipmixPath = Join-Path $pw 'ip-mix.md'
[System.IO.File]::WriteAllText($ipmixPath, '로컬 127.0.0.1 검증 후 8.8.4.4 로 전환.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $ipmixPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 예약 IP 뒤 공인 IP 검출 (P1T2 미탐 수정)" -R $r -ExpectExit 0 -ExpectContains 'IP 주소'
# 사설 대역은 별도 라벨(톤 완화)
$ipprivPath = Join-Path $pw 'ip-priv.md'
[System.IO.File]::WriteAllText($ipprivPath, '게이트웨이 192.168.0.10 설정.', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $ipprivPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 사설 IP 별도 라벨 (P1T2)" -R $r -ExpectExit 0 -ExpectContains 'IP 주소(사설)'

# ---- [H2] 하니스 hook 스크립트 변경 감지 (비차단 경고) ----
$hookPath = Join-Path $pw 'plugins/pjc/scripts/block-destructive.ps1'
New-Item -ItemType Directory (Split-Path $hookPath) -Force | Out-Null
[System.IO.File]::WriteAllText($hookPath, '# test', [System.Text.UTF8Encoding]::new($true))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $hookPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 하니스 hook 스크립트 변경 감지 (H2)" -R $r -ExpectExit 0 -ExpectContains 'hook 스크립트 변경'

# ---- [T2] H2 이름 집합에 고아 프로세스 회수 계열 합류 (차단 쪽 guard-harness와 대칭) ----
# 탐지·차단이 같은 술어를 공유하는 것이 규약이라 한쪽만 넓히면 대칭이 깨진다 — 두 이름을 각각 고정한다.
# Test-WarnOnce가 세션·파일당 1회 억제라 두 케이스는 **서로 다른 파일 경로**를 써야 둘 다 발화한다.
$orphanPath = Join-Path $pw 'plugins/pjc/scripts/session-end-cleanup-lib.ps1'
[System.IO.File]::WriteAllText($orphanPath, '# test', [System.Text.UTF8Encoding]::new($true))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $orphanPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: session-end-cleanup-lib 변경 감지 (T2 H2 집합 합류)" -R $r -ExpectExit 0 -ExpectContains 'hook 스크립트 변경'
$sessionEndPath = Join-Path $pw 'plugins/pjc/scripts/session-end-cleanup.ps1'
[System.IO.File]::WriteAllText($sessionEndPath, '# test', [System.Text.UTF8Encoding]::new($true))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $sessionEndPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: session-end-cleanup 변경 감지 (T2 H2 집합 합류)" -R $r -ExpectExit 0 -ExpectContains 'hook 스크립트 변경'
# [회차 44 T2] write-gate-exempt 합류 — 차단 쪽(guard-harness)과 같은 이름 집합을 읽으므로 탐지도 함께 넓어져야 대칭이 산다.
$exemptPath = Join-Path $pw 'plugins/pjc/scripts/write-gate-exempt.ps1'
[System.IO.File]::WriteAllText($exemptPath, '# test', [System.Text.UTF8Encoding]::new($true))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $exemptPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: write-gate-exempt 변경 감지 (회차 44 T2 H2 집합 합류)" -R $r -ExpectExit 0 -ExpectContains 'hook 스크립트 변경'

# ---- [v1.90.2 M2] .claude/settings.json 변경 감지 (enabledPlugins 하니스 전체 무력화면 — 비차단 경고) ----
$setPath = Join-Path $pw '.claude/settings.json'
New-Item -ItemType Directory (Split-Path $setPath) -Force | Out-Null
[System.IO.File]::WriteAllText($setPath, '{}', [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; tool_input = @{ file_path = $setPath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: .claude/settings.json 변경 경고 (v1.90.2 M2)" -R $r -ExpectExit 0 -ExpectContains 'enabledPlugins'

# ---- NotebookEdit — notebook_path 인식 후 검사 적용 (T1 매처·폴백 회귀 가드) ----
$nbPath = Join-Path $pw 'analysis.ipynb'
[System.IO.File]::WriteAllText($nbPath, '{"cells":[{"cell_type":"code","source":["password = ''Fake12345''"]}]}', [System.Text.UTF8Encoding]::new($false))
$nbj = @{ tool_name = 'NotebookEdit'; cwd = $pw; tool_input = @{ notebook_path = $nbPath; new_source = 'x' } } | ConvertTo-Json -Compress
$r = Invoke-Hook 'post-write-checks.ps1' $nbj
Assert-Case -Name "post-write: NotebookEdit notebook_path 인식 — password 경고" -R $r -ExpectExit 0 -ExpectContains 'password'

# ---- 시크릿 스캔 범위: 추적 파일은 추가 라인만 (v1.147.0) — 델타 2건 ----
# 위 시크릿 7종은 비 git 픽스처($pw)라 전재 폴백 경로로 통과한다(무회귀) — 그래서 새 동작을
#   고정하지 못한다. 아래 2건이 "추적 파일에서 실제로 좁혀졌음"을 실증하는 델타 케이스다:
#   ① HEAD에 이미 있는 시크릿을 재저장 → 무경고(종전에는 매 저장마다 경고)
#   ② 같은 파일에 새 시크릿 라인 추가 → 경고(탐지 능력 유지 — 미탐이 아님)
# git 임시 repo 구성은 §9 warn-commit-secrets 케이스(L910 근방)와 동일 패턴.
if ($gitOk) {
    $pwRepo = Join-Path $work 'pwrepo'; New-Item -ItemType Directory $pwRepo -Force | Out-Null
    $pwDoc = Join-Path $pwRepo 'doc.md'
    # 가짜 값은 문자열 연결로 분리 기재 — 러너 파일 자체가 자사 시크릿 스캐너에 오탐되지 않게(L854 관례)
    $fakeUri = 'postgres://' + 'u1' + ':' + 'p123456' + '@h/db'
    Push-Location $pwRepo
    git init -q; git config user.email t@t; git config user.name t
    ('예시: DATABASE_URL=' + $fakeUri) | Set-Content doc.md -Encoding UTF8
    git add doc.md; git commit -qm init
    Pop-Location
    $pwRepoJson = @{ tool_name = 'Write'; cwd = $pwRepo; tool_input = @{ file_path = $pwDoc } } | ConvertTo-Json -Compress

    # ① 델타: HEAD에 이미 있는 시크릿 → 추가 라인 0줄이라 무경고
    $r = Invoke-Hook 'post-write-checks.ps1' $pwRepoJson
    Assert-Case -Name "post-write: 추적 파일의 기존 시크릿 재신고 안 함 (범위 축소 델타)" -R $r -ExpectExit 0 -ExpectNotContains '민감 정보'

    # ② 델타: 새 시크릿 라인 추가 → 경고 (탐지 능력 유지 실증)
    Add-Content -LiteralPath $pwDoc -Value ('신규: DB_URL=' + $fakeUri) -Encoding UTF8
    $r = Invoke-Hook 'post-write-checks.ps1' $pwRepoJson
    Assert-Case -Name "post-write: 추적 파일의 신규 시크릿 라인은 경고 (미탐 아님)" -R $r -ExpectExit 0 -ExpectContains '민감 정보'

    Remove-Item -Recurse -Force $pwRepo -ErrorAction SilentlyContinue

    # ③ HEAD 없는 저장소(초기 커밋 전 staged) → 전재 폴백으로 경고 유지 (V-5 B1 회귀 가드)
    #   ls-files는 staged 파일이면 HEAD 없이도 성공하지만 `diff HEAD`는 exit 128로 실패한다 —
    #   그 실패를 무시하면 "추가 라인 0줄"과 구분되지 않아 스캔이 스킵되고 시크릿이 통째로 미탐된다.
    #   위 ①②는 항상 커밋된 저장소만 쓰므로 이 공백을 잡지 못한다(그래서 별도 케이스).
    $pwFresh = Join-Path $work 'pwfresh'; New-Item -ItemType Directory $pwFresh -Force | Out-Null
    $pwFreshDoc = Join-Path $pwFresh 'sec.md'
    Push-Location $pwFresh
    git init -q; git config user.email t@t; git config user.name t
    ('DATABASE_URL=' + $fakeUri) | Set-Content sec.md -Encoding UTF8
    git add sec.md                      # 커밋하지 않는다 — HEAD 부재 상태를 만든다
    Pop-Location
    $r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pwFresh; tool_input = @{ file_path = $pwFreshDoc } } | ConvertTo-Json -Compress)
    Assert-Case -Name "post-write: HEAD 없는 저장소는 전재 폴백 — 시크릿 경고 유지" -R $r -ExpectExit 0 -ExpectContains '민감 정보'
    Remove-Item -Recurse -Force $pwFresh -ErrorAction SilentlyContinue
}

# =====================================================================
# 7) impact-warn 시나리오 (git 필요 — caller 경고 양성·음성. §6과 같은 post-write-checks
#    게이트 안 — $gitOk는 top-level 정의라 필터 조합과 무관하게 항상 판정됨)
# =====================================================================
if ($gitOk) {
    $imp = Join-Path $work 'imprepo'; New-Item -ItemType Directory $imp -Force | Out-Null
    Push-Location $imp
    git init -q; git config user.email t@t; git config user.name t
    'namespace Demo { }' | Set-Content Widget.cs
    'var s = WidgetService.RefreshCache();' | Set-Content CallerFile.cs
    'namespace Demo2 { }' | Set-Content Lonely.cs
    git add .; git commit -qm 'base'
    # public 클래스·메서드 심볼 추가 수정 — caller(CallerFile.cs)가 있는 양성 케이스
    "public class WidgetService {`n    public static void RefreshCache() { }`n}" | Set-Content Widget.cs
    Pop-Location
    $ij = @{ tool_name = 'Write'; cwd = $imp; tool_input = @{ file_path = (Join-Path $imp 'Widget.cs') } } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'post-write-checks.ps1' $ij
    Assert-Case -Name "impact: public 심볼 변경 caller 경고" -R $r -ExpectExit 0 -ExpectContains 'IMPACT WARNING'
    Assert-Case -Name "impact: caller 파일 경로 제시" -R $r -ExpectExit 0 -ExpectContains 'CallerFile.cs'
    # caller 없는 심볼 — 완전 무출력(음성. BOM·주석·시크릿도 없는 파일이라 IMPACT 미출력이면 전체 무출력)
    Push-Location $imp
    "public class LonelyThing {`n}" | Set-Content Lonely.cs
    Pop-Location
    $ij2 = @{ tool_name = 'Write'; cwd = $imp; tool_input = @{ file_path = (Join-Path $imp 'Lonely.cs') } } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'post-write-checks.ps1' $ij2
    Assert-Case -Name "impact: caller 없는 심볼 무경고(음성)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [회차 3 T4] 대문자 확장자 caller — caller 검색 pathspec 의 icase 를 잰다 ----
    # caller 판정은 확장자를 소문자로 바꿔 대조하므로 `.CS` 도 코드 파일이다. `git grep` 에 확장자
    #   pathspec 을 붙이면서 대소문자를 가리면 이 caller 가 검색 단계에서 빠진다.
    $impU = Join-Path $work 'imprepo-upper'; New-Item -ItemType Directory $impU -Force | Out-Null
    Push-Location $impU
    git init -q; git config user.email t@t; git config user.name t
    'namespace D { }' | Set-Content Widget.cs
    'var s = Gadget.RecomputeIndex();' | Set-Content CallerUpper.CS
    git add .; git commit -qm base
    "public class Gadget {`n    public static void RecomputeIndex() { }`n}" | Set-Content Widget.cs
    Pop-Location
    $r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $impU; tool_input = @{ file_path = (Join-Path $impU 'Widget.cs') } } | ConvertTo-Json -Compress)
    Assert-Case -Name "impact: 대문자 확장자 caller(.CS)도 제시 (회차 3 T4)" -R $r -ExpectExit 0 -ExpectContains 'CallerUpper.CS'

    # ---- [P1T4] stop-list 흔한 식별자 제외 (Name/Type 등 — 무관 파일 다독 유도 방지) ----
    $imp2 = Join-Path $work 'imprepo-stop'; New-Item -ItemType Directory $imp2 -Force | Out-Null
    Push-Location $imp2
    git init -q; git config user.email t@t; git config user.name t
    'namespace D { class X { } }' | Set-Content Model.cs
    "// Name 은 여기저기 쓰인다`nvar a = ""Name"";`nvar b = Name;" | Set-Content Uses.cs
    git add .; git commit -qm base
    "public class Model {`n    public string Name { get; set; }`n}" | Set-Content Model.cs
    Pop-Location
    $r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $imp2; tool_input = @{ file_path = (Join-Path $imp2 'Model.cs') } } | ConvertTo-Json -Compress)
    Assert-Case -Name "impact: stop-list 심볼(Name) 무경고 (P1T4)" -R $r -ExpectExit 0 -ExpectSilent $true

    # ---- [P1T4] 세션·심볼당 1회 디듑 (같은 파일 2회 편집 시 2회차 impact 무경고) ----
    $imp3 = Join-Path $work 'imprepo-dedup'; New-Item -ItemType Directory $imp3 -Force | Out-Null
    Push-Location $imp3
    git init -q; git config user.email t@t; git config user.name t
    'namespace D { }' | Set-Content Widget.cs
    'var s = RefreshCache();' | Set-Content Caller.cs
    git add .; git commit -qm base
    "public class Svc {`n    public static void RefreshCache() { }`n}" | Set-Content Widget.cs
    Pop-Location
    $ijd = @{ tool_name = 'Write'; cwd = $imp3; session_id = 'dedup-sess'; tool_input = @{ file_path = (Join-Path $imp3 'Widget.cs') } } | ConvertTo-Json -Compress
    $r = Invoke-Hook 'post-write-checks.ps1' $ijd
    Assert-Case -Name "impact: RefreshCache 1회차 경고 (P1T4 디듑 전제)" -R $r -ExpectExit 0 -ExpectContains 'RefreshCache'
    $r = Invoke-Hook 'post-write-checks.ps1' $ijd
    Assert-Case -Name "impact: RefreshCache 2회차 무경고 (P1T4 세션 디듑)" -R $r -ExpectExit 0 -ExpectSilent $true
} else {
    Write-Host "[SKIP] impact-warn 시나리오 (git 없음)"
}

# ---- [P1T4] C# 전처리 지시문(#region/#if)은 영문 주석 오집계 제외 ----
$prePath = Join-Path $pw 'Pre.cs'
# 영문 // 주석 3줄(≤5) + 전처리 지시문 6개 — 종전 '//|#' 판정이면 지시문까지 세어 9줄(>5)로
# 영문주석 경고를 오탐했을 것. 새 판정(.cs는 //만)이면 3줄뿐이라 >5 미달로 무경고여야 한다.
# .cs이지만 BOM 없이 저장(BOM 경고와 분리해 영문주석 판정만 검증).
$preBody = @('#region Helpers', '#if DEBUG', '#pragma warning disable', '// one', '// two', '// three', '#else', '#endif', '#endregion') -join "`n"
[System.IO.File]::WriteAllText($prePath, $preBody, [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $pw; session_id = 'pre-sess'; tool_input = @{ file_path = $prePath } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: C# 전처리 지시문 영문주석 오집계 제외 (P1T4 — //3줄뿐이라 >5 미달로 무경고)" -R $r -ExpectExit 0 -ExpectSilent $true

# .state 디듑 마커 30일 정리는 2026-10-08 세션 시작 1회로 옮겼다 — 그 케이스는 scenarios/session-context.ps1 에 있다.

# ---- [회차 51] H3 저장 직후 줄바꿈 경고 ----
#   워킹트리 규약은 CRLF 인데 Write·Edit 도구는 LF 로 쓴다. AGENTS.md 「줄바꿈」이 확인을 요구하지만
#   회차 50 이 intent/ 를 쓰고 확인하지 않아 「줄바꿈 정합」 축이 red 를 냈다 — 저장한 자리에서 알린다.
#   ⚠ 차단이 아니라 경고다(exit 0 유지). 그리고 **git 추적 파일만** 본다 — plan.md·notes.md 는
#     gitignore 라 규약 대상이 아니고, 경고하면 편집마다 발화한다.
$eolRepo = Join-Path $work 'eolrepo'; New-Item -ItemType Directory $eolRepo -Force | Out-Null
Push-Location $eolRepo
git init -q; git config user.email t@t; git config user.name t
$eolLf = Join-Path $eolRepo 'lf.md'
$eolCrlf = Join-Path $eolRepo 'crlf.md'
[System.IO.File]::WriteAllText($eolLf, "첫 줄`n둘째 줄`n")
[System.IO.File]::WriteAllText($eolCrlf, "첫 줄`r`n둘째 줄`r`n")
# 판정은 추적 파일의 워킹트리 CRLF 비율(≥ 90% · 표본 ≥ 5)이다 — EOL1·EOL1b 가 양성이도록 CRLF 추적 파일을 채운다(CRLF 10 · LF 1).
1..9 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolRepo "crlf$_.md"), "줄`r`n") }
# 픽스처 제외 경로 — 실제 레포의 LF 18건이 전부 이 형태라 오탐하면 그 트리를 만질 때마다 발화한다.
$eolFx = Join-Path $eolRepo 'plugins/pjc/skills/llm-wiki/evals/fixtures/x'
New-Item -ItemType Directory $eolFx -Force | Out-Null
$eolFxFile = Join-Path $eolFx 'input.md'
[System.IO.File]::WriteAllText($eolFxFile, "픽스처는 LF 가 테스트 입력이다`n")
git add -A; git commit -qm init
Pop-Location

# EOL1 (양성): 추적 파일이 LF 면 경고한다.
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolRepo; session_id = 'eol-a'; tool_input = @{ file_path = $eolLf } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 추적 파일이 LF 면 경고 (EOL1)" -R $r -ExpectExit 0 -ExpectContains 'EOL WARNING'
# 이 hook 은 모든 레포에서 돈다 — 문구가 하네스 레포 문서를 가리키면 다른 레포에서 틀린 지시가 된다(2026-10-08 Karina).
Assert-Case -Name "post-write: EOL 경고 문구에 하네스 레포 참조가 없다 (EOL1)" -R $r -ExpectExit 0 -ExpectNotContains 'AGENTS.md'

# EOL2 (델타 음성 — CRLF): 규약대로 저장된 파일은 조용하다. 없으면 「항상 경고」로 바꿔도 green 이다.
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolRepo; session_id = 'eol-b'; tool_input = @{ file_path = $eolCrlf } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: CRLF 파일은 무경고 (EOL2)" -R $r -ExpectExit 0 -ExpectNotContains 'EOL WARNING'

# EOL1b (양성 — 신규 미추적 파일): **이번 사고 형태가 이것이다.** 회차 50 이 Write 로 만든
#   intent/*.md 가 LF 였다. 추적 여부로 거르면 새로 만든 파일이 통째로 빠져 그 형태에 발화하지
#   않는다(완료 리뷰 MAJOR) — 「줄바꿈 정합」 축과 같이 gitignore 만 제외한다.
$eolNew = Join-Path $eolRepo 'intent/2026-09-09-new.md'
New-Item -ItemType Directory (Split-Path -Parent $eolNew) -Force | Out-Null
[System.IO.File]::WriteAllText($eolNew, "새로 만든 intent 파일`n")
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolRepo; session_id = 'eol-d'; tool_input = @{ file_path = $eolNew } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 신규 미추적 파일이 LF 면 경고 (EOL1b)" -R $r -ExpectExit 0 -ExpectContains 'EOL WARNING'

# EOL4 (양성 — autocrlf 무관): 판정은 기계 설정 `core.autocrlf` 가 아니라 **추적 파일의 실제 워킹트리 eol** 이다.
#   autocrlf=false 여도 추적 파일 대부분이 CRLF 면 경고한다 — 「autocrlf 를 읽지 않는다」를 행동으로 잰다.
#   ⚠ 두 신호를 한 케이스에 담지 않는다(「검증 케이스의 축 분리」) — 속성은 EOL5, 혼합 비율은 EOL6 이 잰다.
$eolLfRepo = Join-Path $work 'eol-lf-repo'; New-Item -ItemType Directory $eolLfRepo -Force | Out-Null
Push-Location $eolLfRepo
git init -q; git config user.email t@t; git config user.name t; git config core.autocrlf false
1..5 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolLfRepo "c$_.md"), "줄`r`n") }
$eolLfDoc = Join-Path $eolLfRepo 'guide.md'
[System.IO.File]::WriteAllText($eolLfDoc, "가이드`r`n")
git add -A; git commit -qm init
Pop-Location
[System.IO.File]::WriteAllText($eolLfDoc, "LF 로 다시 저장`n")
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolLfRepo; session_id = 'eol-e'; tool_input = @{ file_path = $eolLfDoc } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: autocrlf=false 여도 추적 파일 대부분이 CRLF 면 경고 (EOL4)" -R $r -ExpectExit 0 -ExpectContains 'EOL WARNING'

# EOL5: core.autocrlf=**true** + `.gitattributes eol=lf` → **속성이 이긴다**.
#   Windows 기본값과 크로스플랫폼 .gitattributes 의 흔한 조합이고, autocrlf 만 보던
#   구현이 여기서 오탐했다(완료 리뷰 3R 관측). 따르면 eol=lf 레포를 CRLF 로 뒤집는다.
$eolAttrRepo = Join-Path $work 'eol-attr-repo'; New-Item -ItemType Directory $eolAttrRepo -Force | Out-Null
Push-Location $eolAttrRepo
git init -q; git config user.email t@t; git config user.name t; git config core.autocrlf true
[System.IO.File]::WriteAllText((Join-Path $eolAttrRepo '.gitattributes'), "* text eol=lf`n")
# 워킹트리 CRLF 추적 파일 5 — 속성 우선 분기가 없으면 비율 판정이 경고할 형상이라, 무경고는 속성이 이긴 결과다.
1..5 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolAttrRepo "c$_.md"), "줄`r`n") }
$eolAttrDoc = Join-Path $eolAttrRepo 'guide.md'
[System.IO.File]::WriteAllText($eolAttrDoc, "속성이 LF 를 규약으로 선언한다`n")
git add -A; git commit -qm init
Pop-Location
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolAttrRepo; session_id = 'eol-f'; tool_input = @{ file_path = $eolAttrDoc } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: .gitattributes eol=lf 가 autocrlf 를 이긴다 (EOL5)" -R $r -ExpectExit 0 -ExpectNotContains 'EOL WARNING'

# EOL6 (델타 음성 — 혼합 레포): 속성 없음 · 추적 CRLF 3 / LF 7(30%) → 규약이 없는 레포라 경고하지 않는다.
#   autocrlf=true(Windows 기본값) 를 규약으로 읽던 구현이 Karina(CRLF 34%)에서 오경보 11회를 냈다(2026-10-08).
$eolMixRepo = Join-Path $work 'eol-mix-repo'; New-Item -ItemType Directory $eolMixRepo -Force | Out-Null
Push-Location $eolMixRepo
git init -q; git config user.email t@t; git config user.name t; git config core.autocrlf true
1..3 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolMixRepo "c$_.md"), "줄`r`n") }
1..7 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolMixRepo "l$_.md"), "줄`n") }
git add -A 2>$null; git commit -qm init
Pop-Location
$eolMixRepoDoc = Join-Path $eolMixRepo 'l1.md'
[System.IO.File]::WriteAllText($eolMixRepoDoc, "LF 로 저장`n")
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolMixRepo; session_id = 'eol-g'; tool_input = @{ file_path = $eolMixRepoDoc } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: CRLF 가 소수인 혼합 레포에서는 무경고 (EOL6)" -R $r -ExpectExit 0 -ExpectNotContains 'EOL WARNING'

# EOL7 (델타 음성 — 표본 부족): 속성 없음 · 추적 CRLF 2 → 표본 5 미만이라 규약을 단정하지 않는다.
$eolFewRepo = Join-Path $work 'eol-few-repo'; New-Item -ItemType Directory $eolFewRepo -Force | Out-Null
Push-Location $eolFewRepo
git init -q; git config user.email t@t; git config user.name t; git config core.autocrlf true
1..2 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolFewRepo "c$_.md"), "줄`r`n") }
git add -A 2>$null; git commit -qm init
Pop-Location
$eolFewRepoDoc = Join-Path $eolFewRepo 'new.md'
[System.IO.File]::WriteAllText($eolFewRepoDoc, "새 파일`n")
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolFewRepo; session_id = 'eol-h'; tool_input = @{ file_path = $eolFewRepoDoc } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 추적 파일 표본이 5 미만이면 무경고 (EOL7)" -R $r -ExpectExit 0 -ExpectNotContains 'EOL WARNING'

# EOL8 (양성 — 쓴 파일 제외): 추적 CRLF 6 중 하나를 LF 로 다시 저장 → 제외하면 5/5 라 경고.
#   쓴 파일을 표본에 넣으면 5/6 = 83% 로 무경고가 된다 — 방금 쓴 파일의 w/ 는 새 내용이라 규약 신호가 아니다.
#   autocrlf=false 를 명시한다 — 시스템 값(true)을 물려받으면 옛 구현도 경고해 구현 전 RED 가 서지 않는다.
$eolSelfRepo = Join-Path $work 'eol-self-repo'; New-Item -ItemType Directory $eolSelfRepo -Force | Out-Null
Push-Location $eolSelfRepo
git init -q; git config user.email t@t; git config user.name t; git config core.autocrlf false
1..6 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolSelfRepo "c$_.md"), "줄`r`n") }
git add -A 2>$null; git commit -qm init
Pop-Location
$eolSelfRepoDoc = Join-Path $eolSelfRepo 'c1.md'
[System.IO.File]::WriteAllText($eolSelfRepoDoc, "LF 로 다시 저장`n")
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolSelfRepo; session_id = 'eol-i'; tool_input = @{ file_path = $eolSelfRepoDoc } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: 쓴 파일은 표본에서 빼고 판정한다 (EOL8)" -R $r -ExpectExit 0 -ExpectContains 'EOL WARNING'

# EOL9 (양성 — 픽스처 제외): 추적 CRLF 9 · llm-wiki 픽스처 아래 추적 LF 2 · CRLF 하나를 LF 로 재저장 → 제외하면 8/8 이라 경고.
#   픽스처를 표본에 넣으면 8/10 = 80% 로 무경고 — 픽스처의 LF 는 의도된 테스트 입력이지 레포 규약이 아니다(EOL3 과 같은 이유).
#   autocrlf=false 명시 — EOL8 과 같은 이유.
$eolFxRepo = Join-Path $work 'eol-fx-repo'; New-Item -ItemType Directory $eolFxRepo -Force | Out-Null
Push-Location $eolFxRepo
git init -q; git config user.email t@t; git config user.name t; git config core.autocrlf false
1..9 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolFxRepo "c$_.md"), "줄`r`n") }
$eolFxDir = Join-Path $eolFxRepo 'plugins/pjc/skills/llm-wiki/evals/fixtures/x'
New-Item -ItemType Directory $eolFxDir -Force | Out-Null
1..2 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $eolFxDir "f$_.md"), "줄`n") }
git add -A 2>$null; git commit -qm init
Pop-Location
$eolFxRepoDoc = Join-Path $eolFxRepo 'c1.md'
[System.IO.File]::WriteAllText($eolFxRepoDoc, "LF 로 다시 저장`n")
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolFxRepo; session_id = 'eol-j'; tool_input = @{ file_path = $eolFxRepoDoc } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: llm-wiki 픽스처는 표본에서 빼고 판정한다 (EOL9)" -R $r -ExpectExit 0 -ExpectContains 'EOL WARNING'

# EOL3 (델타 음성 — 픽스처 제외): llm-wiki/evals/fixtures/ 아래 LF 는 의도된 테스트 입력이다.
$r = Invoke-Hook 'post-write-checks.ps1' (@{ tool_name = 'Write'; cwd = $eolRepo; session_id = 'eol-c'; tool_input = @{ file_path = $eolFxFile } } | ConvertTo-Json -Compress)
Assert-Case -Name "post-write: llm-wiki 픽스처의 LF 는 무경고 (EOL3)" -R $r -ExpectExit 0 -ExpectNotContains 'EOL WARNING'

}   # ---- §6·§7·Pre.cs 게이트 끝 (post-write-checks) ----

