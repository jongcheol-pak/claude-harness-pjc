# secret-patterns.ps1 — 공유 시크릿 패턴 모듈 — 근거는 `rules/secret-patterns-rationale.md`의 「§1 secret-patterns.ps1 — 공유 시크릿 패턴 모듈」

# 고신뢰 라벨 — 근거는 `rules/secret-patterns-rationale.md`의 「§2 고신뢰 라벨」
$script:HighConfidenceSecretLabels = @(
    '개인키',
    'DB 연결 문자열',
    'DB/서비스 URI 인증정보',
    '자격증명 쌍'
)

function Get-HighConfidenceSecretLabels {
    return $script:HighConfidenceSecretLabels
}

# 자격증명 쌍의 토큰 검증 — 근거는 `rules/secret-patterns-rationale.md`의 「§3 자격증명 쌍의 토큰 검증」
function Test-CredentialPairToken {
    param([string]$id, [string]$pw)

    # 플레이스홀더는 자격증명이 아니다 — 근거는 `rules/secret-patterns-rationale.md`의 「§4 플레이스홀더는 자격증명이 아니다」
    $placeholder = '^(xxx+|\*+|your[-_]|fake|example|dummy|sample|changeme$|test$|testing)'
    foreach ($t in @($id, $pw)) {
        if ($t -match "(?i)$placeholder") { return $false }
        if ($t -match '^<.*>$') { return $false }
    }

    # 경로·URL·파일명·버전은 자격증명이 아니다. 확장자를 열거하면 목록 밖 — 근거는 `rules/secret-patterns-rationale.md`의 「§5 경로·URL·파일명·버전은 자격증명이 아니다. 확장자를 열거하면 목록 밖」
    foreach ($t in @($id, $pw)) {
        if ($t -match '/') { return $false }                      # 경로·라우트
        if ($t -match '(?i)\.[a-z]{2,5}$') { return $false }       # 파일명(config.yml, appsettings.json …)
        if ($t -match '(?i)^v?\d+\.\d+') { return $false }         # 버전(v1.2)
    }

    # 비밀번호 자리: 6자 이상 + 숫자 또는 특수문자. '_'·'-'는 특수문자로 치지 않는다 —
    #   그러면 역할·열거형 문서(admin / super_admin, local / oauth2_pkce)가 전부 걸린다.
    if ($pw.Length -lt 6) { return $false }
    if ($pw -notmatch '[\d#$%!@^&*+=?~]') { return $false }

    # 값이 아니라 **참조**면 자격증명이 아니다 — 근거는 `rules/secret-patterns-rationale.md`의 「§6 값이 아니라 **참조**면 자격증명이 아니다」
    if ($pw -match '^\$' -or $pw -match '^%[\w.]+%$') { return $false }              # $env:X · ${X} · $X · %X%
    if ($pw -match '(?i)^(os\.|process\.env|Environment\.|System\.getenv|ENV\[|getenv\()') { return $false }
    if ($pw -match '^[A-Za-z][\w-]*(:[A-Za-z][\w-]*)+$') { return $false }           # 설정 키 경로(appsettings:Db:Pwd)
    if ($pw -match '(?i)^(환경변수|없음|미설정|\.env)') { return $false }            # 값 대신 안내를 적은 자리

    # 상태·에러코드 열거는 자격증명이 아니다 — 근거는 `rules/secret-patterns-rationale.md`의 「§7 상태·에러코드 열거는 자격증명이 아니다」
    if ($pw -match '^[\d._-]+$') { return $false }
    if ($pw -match '(?i)^(err(or)?|code|status|state|stat|ret|rc|exit|level|step|phase|type|kind|mode|grade|rank|tier|http|active|inactive|pending|enabled?|disabled?|success|fail(ed|ure)?|warn(ing)?|timeout|unknown)[._-]?\d+$') { return $false }

    return $true
}

function Get-SecretMatches {
    param([string]$content)

    # 자동 변수 $matches($content -match ...가 덮어씀)와 충돌하지 않도록 $found 사용.
    $found = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($content)) { return @() }

    # 실제 '값' 패턴만 잡고 단순 언급 — 근거는 `rules/secret-patterns-rationale.md`의 「§8 실제 '값' 패턴만 잡고 단순 언급」
    $secretPatterns = @(
        @{ rx = '(?i)(password|passwd|pwd)\s*[:=]\s*["'']?(?!(os\.|process\.env|Environment\.|System\.getenv|ENV\[|getenv\(|string\b|str\b|int\b|bool\b|char\b|secure(string)?\b|none\b|null\b|nil\b|true\b|false\b))[^\s"''<>{}$]{3,}'; label = 'password 값' },
        # 한글 키워드 (v1.119.0) — 종전엔 영문 password 계열만 봐서 "비밀번호: <값>"이 통째로 미탐이었다.
        #   환경변수 이름만 적으라는 이 hook의 권고를 따른 문장("비밀번호: 환경변수 X로 지정")은 제외한다.
        @{ rx = '(?i)(비밀번호|패스워드|암호)\s*[:=]\s*["''`]?(?!(환경변수|없음|미설정|변경|설정|\$env|os\.|process\.env|Environment\.|<))[^\s"''`<>{}$]{3,}'; label = 'password 값' },
        @{ rx = '(?i)(api[_-]?key|apikey|access[_-]?token|secret[_-]?key|auth[_-]?token|client[_-]?secret)\s*[:=]\s*["'']?[A-Za-z0-9_\-]{8,}'; label = 'API key/token 값' },
        # 중간 키·`User Id` 공백 표기 수용 — 근거는 `rules/secret-patterns-rationale.md`의 「§9 중간 키·`User Id` 공백 표기 수용」
        @{ rx = '(?i)(Server|Data Source)[ \t]*=[^;\r\n]+;(?:[^;\r\n]*;)*[ \t]*(User[ \t]*Id|User|Uid|Password|Pwd)[ \t]*='; label = 'DB 연결 문자열' },
        @{ rx = '(?i)(mongodb(\+srv)?|postgres|postgresql|mysql|redis|amqp)://[^\s]+:[^\s]+@'; label = 'DB/서비스 URI 인증정보' },
        @{ rx = '-----BEGIN [A-Z ]*PRIVATE KEY-----'; label = '개인키' },
        @{ rx = '(?i)Bearer\s+[A-Za-z0-9_\-\.]{16,}'; label = 'Bearer 토큰' },
        @{ rx = '\b(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\b'; label = 'IP 주소' }   # L5: 옥텟 0-255 제한 — 999.999.999.999 등 IP 아닌 숫자열 오탐 완화
    )
    foreach ($sp in $secretPatterns) {
        if ($content -match $sp.rx) {
            # IP는 전체 매치를 순회한다 — 근거는 `rules/secret-patterns-rationale.md`의 「§10 IP는 전체 매치를 순회한다」
            if ($sp.label -eq 'IP 주소') {
                $pubHit = $false; $privHit = $false
                foreach ($ipm in [regex]::Matches($content, $sp.rx)) {
                    $m = $ipm.Value
                    if ($m -eq '127.0.0.1' -or $m -eq '0.0.0.0' -or $m -eq '255.255.255.255' -or $m -like '0.0.0.*') { continue }
                    # 버전 문자열(AssemblyVersion/FileVersion/<Version>/v1.0.0.0 등) 오탐 제외
                    if ($content -match "(?i)(version|v)\s*[>=:]?\s*[`"']?$([regex]::Escape($m))") { continue }
                    if ($m -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') { $privHit = $true } else { $pubHit = $true }
                }
                if ($pubHit)  { $found.Add($sp.label) }
                if ($privHit) { $found.Add('IP 주소(사설)') }
                continue
            }
            $found.Add($sp.label)
        }
    }

    # ---- 자격증명 쌍 — 근거는 `rules/secret-patterns-rationale.md`의 「§11 ---- 자격증명 쌍」
    $pairKwCore  = '(?:(?:\b(?:admin|account|credentials?|login|username|ID/PW)\b)|계정|아이디|로그인|사용자명)'
    $pairKeyword = "($pairKwCore)[^\r\n:]{0,40}:\s*"
    $pairQuoted   = $pairKeyword + '(["''`])([A-Za-z0-9._-]{3,32})\2\s*/\s*(["''`])([^\s"''`]{6,64})\4'
    $pairUnquoted = $pairKeyword + '([A-Za-z0-9._-]{3,32})\s*/\s*([A-Za-z0-9._\-#$%!@^&*+=?~]{6,64})'

    # 줄 분리형·마크다운 표 — 근거는 `rules/secret-patterns-rationale.md`의 「§12 줄 분리형·마크다운 표」
    $pairPwKw  = '(?:\b(?:password|passwd|pwd)\b|비밀번호|패스워드)'
    $pairSplit = $pairKwCore + '[ \t*`]{0,4}[:|][ \t]*(["''`])([A-Za-z0-9._-]{3,32})\1[^\r\n]*\r?\n[ \t|>*`-]{0,6}' + $pairPwKw + '[ \t*`]{0,4}[:|][ \t]*(["''`])([^\s"''`]{6,64})\3'

    # 인용형·줄 분리형을 먼저 판정하고, 매치되면 비인용형은 보지 않는다 (두 라벨은 상호 배타 —
    #   한 문자열이 두 라벨을 함께 반환하면 caller의 차단 판정이 흐려진다).
    $quotedHit = $false
    foreach ($m in [regex]::Matches($content, "(?i)$pairQuoted")) {
        # 그룹: 1=키워드 2=id 인용부호 3=id 4=pw 인용부호 5=pw (닫는 쪽은 \2·\4 역참조 — 새 그룹 아님)
        if (Test-CredentialPairToken $m.Groups[3].Value $m.Groups[5].Value) { $quotedHit = $true; break }
    }
    if (-not $quotedHit) {
        foreach ($m in [regex]::Matches($content, "(?i)$pairSplit")) {
            # 그룹: 1=id 인용부호 2=id 3=pw 인용부호 4=pw (키워드는 non-capturing — 번호가 밀리지 않는다)
            if (Test-CredentialPairToken $m.Groups[2].Value $m.Groups[4].Value) { $quotedHit = $true; break }
        }
    }
    if ($quotedHit) {
        $found.Add('자격증명 쌍')
    } else {
        foreach ($m in [regex]::Matches($content, "(?i)$pairUnquoted")) {
            if (Test-CredentialPairToken $m.Groups[2].Value $m.Groups[3].Value) {
                $found.Add('자격증명 쌍(비인용)')
                break
            }
        }
    }

    return $found.ToArray()
}
