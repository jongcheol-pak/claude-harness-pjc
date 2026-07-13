# secret-patterns.ps1 — 공유 시크릿 패턴 모듈 (dot-source 전용, hook 아님)
#
# 편집 시점 검사(post-write-checks.ps1)가 이 모듈을 dot-source해 시크릿 패턴을 사용한다.
#   커밋 시점 검사(warn-commit-secrets.ps1, 같은 plan의 후속 task에서 추가)와 패턴을 공유하기 위해
#   단일 진실 원천으로 분리했다 — 패턴이 갈라지면 "편집 땐 잡히는데 커밋 땐 안 잡히는" 보안 구멍이
#   생기므로, 한 곳만 고치면 두 검사에 반영되게 한다.
#
# 이 파일은 stdin을 읽지 않고 함수 정의만 한다(실행 부작용 없음) — hook 목록·hooks.json에 등록하지 않고,
#   validate.ps1의 $knownHelpers에 등록해 "미등록 스크립트" 경고를 피한다.
#
# 함수 계약: 내용 문자열 → 매치된 시크릿 라벨 배열. 스캔 대상 판단(.env 스킵 등)·경고 문구는
#   각 caller가 결정한다(이 함수는 "내용→매치"만).
# caller 3곳(전부 라벨 배열만 소비 — 반환 계약을 바꾸면 셋을 함께 고쳐야 한다):
#   post-write-checks.ps1(편집 시점 경고) · bash-hook-lib.ps1(커밋 시점) · hook-event-log.ps1(fail-closed 마스킹).

# 고신뢰 라벨 (v1.119.0) — warn-commit-secrets가 이 라벨을 커밋 차단(exit 2) 기준으로 쓴다.
#   오탐 여지가 거의 없는 것만 넣는다: 나머지 라벨(password 값·API key·Bearer·IP·비인용 쌍)은
#   테스트 픽스처·문서 예시에서 흔히 나와 차단하면 정상 작업이 막히므로 경고로 남긴다
#   (과잉 차단은 아래 '늑대소년화' 주석과 같은 실패 모드 — 이번엔 대가가 루프 정지라 더 크다).
$script:HighConfidenceSecretLabels = @(
    '개인키',
    'DB 연결 문자열',
    'DB/서비스 URI 인증정보',
    '자격증명 쌍'
)

function Get-HighConfidenceSecretLabels {
    return $script:HighConfidenceSecretLabels
}

# 자격증명 쌍의 토큰 검증 (v1.119.0) — 인용형·비인용형 두 패턴이 공유한다.
#   두 패턴이 서로 다른 기준을 쓰면 그 차이가 곧 오탐/미탐 구멍이므로 판정을 한 곳에 둔다
#   (모듈 헤더의 '패턴이 갈라지면 보안 구멍' 논리와 동일).
function Test-CredentialPairToken {
    param([string]$id, [string]$pw)

    # 플레이스홀더는 자격증명이 아니다 (문서의 예시 표기). 각괄호 형태(<PASSWORD>)는 인용형 pw의
    #   문자 클래스가 '<'를 허용하므로 여기서 걸러야 한다(id는 클래스가 이미 배제).
    $placeholder = '^(xxx+|\*+|your[-_]|fake|example|dummy|sample|test|changeme$)'
    foreach ($t in @($id, $pw)) {
        if ($t -match "(?i)$placeholder") { return $false }
        if ($t -match '^<.*>$') { return $false }
    }

    # 경로·URL·파일명·버전은 자격증명이 아니다. 확장자를 열거하면 목록 밖(.yml·.config 등)에서
    #   오탐이 되살아나므로 '마지막 점 뒤 2~5 영문자 = 파일명'이라는 일반 규칙으로 판정한다.
    # 트레이드오프(의도): 이 규칙은 pw에도 적용돼 'Secret1.io' 같은 도메인형 비밀번호를 미탐한다.
    #   그래도 유지하는 이유는 반대 방향의 대가가 더 크기 때문이다 — pw에서 배제를 빼면
    #   "계정: admin / config2.yml"류 파일명 쌍이 오탐되고, 이 라벨은 커밋 차단(exit 2) 기준이라
    #   오탐 하나가 자율 루프를 세운다. 미탐은 경고 계층(비인용 라벨)·리뷰어 보안 체크가 덮는다.
    foreach ($t in @($id, $pw)) {
        if ($t -match '/') { return $false }                      # 경로·라우트
        if ($t -match '(?i)\.[a-z]{2,5}$') { return $false }       # 파일명(config.yml, appsettings.json …)
        if ($t -match '(?i)^v?\d+\.\d+') { return $false }         # 버전(v1.2)
    }

    # 비밀번호 자리: 6자 이상 + 숫자 또는 특수문자. '_'·'-'는 특수문자로 치지 않는다 —
    #   그러면 역할·열거형 문서(admin / super_admin, local / oauth2_pkce)가 전부 걸린다.
    if ($pw.Length -lt 6) { return $false }
    if ($pw -notmatch '[\d#$%!@^&*+=?~]') { return $false }

    return $true
}

function Get-SecretMatches {
    param([string]$content)

    # 자동 변수 $matches($content -match ...가 덮어씀)와 충돌하지 않도록 $found 사용.
    $found = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($content)) { return @() }

    # 실제 '값' 패턴만 잡고 단순 언급(예: "password 필드 추가")은 통과시켜 과잉 경고를 피한다.
    # password 값 제외 조건 (v1.98.0): 값 자리가 실제 비밀이 아닌 형태 — 타입 선언(password: string),
    #   환경변수 조회(os.getenv/process.env/Environment. — 이 hook이 권장하는 바로 그 패턴),
    #   언어 키워드(None/null/true/false) — 까지 경고하면 로그인·인증 코드를 만드는 모든 세션에서
    #   경고가 반복돼 진짜 시크릿 경고의 신뢰가 무너진다(늑대소년화). lookahead로 제외한다.
    $secretPatterns = @(
        @{ rx = '(?i)(password|passwd|pwd)\s*[:=]\s*["'']?(?!(os\.|process\.env|Environment\.|System\.getenv|ENV\[|getenv\(|string\b|str\b|int\b|bool\b|char\b|secure(string)?\b|none\b|null\b|nil\b|true\b|false\b))[^\s"''<>{}$]{3,}'; label = 'password 값' },
        # 한글 키워드 (v1.119.0) — 종전엔 영문 password 계열만 봐서 "비밀번호: <값>"이 통째로 미탐이었다.
        #   환경변수 이름만 적으라는 이 hook의 권고를 따른 문장("비밀번호: 환경변수 X로 지정")은 제외한다.
        @{ rx = '(?i)(비밀번호|패스워드|암호)\s*[:=]\s*["''`]?(?!(환경변수|없음|미설정|변경|설정|\$env|os\.|process\.env|Environment\.|<))[^\s"''`<>{}$]{3,}'; label = 'password 값' },
        @{ rx = '(?i)(api[_-]?key|apikey|access[_-]?token|secret[_-]?key|auth[_-]?token|client[_-]?secret)\s*[:=]\s*["'']?[A-Za-z0-9_\-]{8,}'; label = 'API key/token 값' },
        @{ rx = '(?i)(Server|Data Source)=[^;]+;\s*(User|Uid|Password|Pwd)='; label = 'DB 연결 문자열' },
        @{ rx = '(?i)(mongodb(\+srv)?|postgres|postgresql|mysql|redis|amqp)://[^\s]+:[^\s]+@'; label = 'DB/서비스 URI 인증정보' },
        @{ rx = '-----BEGIN [A-Z ]*PRIVATE KEY-----'; label = '개인키' },
        @{ rx = '(?i)Bearer\s+[A-Za-z0-9_\-\.]{16,}'; label = 'Bearer 토큰' },
        @{ rx = '\b(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\b'; label = 'IP 주소' }   # L5: 옥텟 0-255 제한 — 999.999.999.999 등 IP 아닌 숫자열 오탐 완화
    )
    foreach ($sp in $secretPatterns) {
        if ($content -match $sp.rx) {
            # IP는 전체 매치를 순회한다 (v1.98.0): 종전 first-match-only는 (a) 예외 검사가 첫 매치에만
            #   적용돼 문서 예시 IP 하나로 경고(오탐)하고 (b) 첫 매치가 127.0.0.1 등 예약 IP면 뒤따르는
            #   실제 IP는 검사 자체가 끝나는(미탐) 양방향 결함이 있었다. 각 매치에 예외를 적용하고
            #   잔여만 라벨링하며, 사설 대역(10./192.168./172.16-31.)은 외부 유출 위험이 낮아
            #   'IP 주소(사설)' 라벨로 구분해 톤을 낮춘다(공인 IP 경고의 신뢰 유지).
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

    # ---- 자격증명 쌍 (v1.119.0) ----
    # 실사고 형태: "**기본 관리자 계정**: `<id>` / `<pw>`" — 한글 라벨 + 슬래시 구분이라 위 패턴
    #   어디에도 걸리지 않았고, 그대로 공개 저장소에 커밋됐다.
    # 인용형(고신뢰 → 커밋 차단)과 비인용형(저신뢰 → 경고)을 나눈다: 인용부호 요건이 오탐을 크게
    #   줄이지만(코드 심볼·표·경로 배제) 백틱 없는 변형까지 차단하면 오탐 비용이 차단 이득을 넘는다.
    # 인용부호는 여는 것과 닫는 것이 같아야 한다(역참조) — 문자 클래스만 쓰면 짝이 안 맞는
    #   ("admin` / `pw") 형태까지 고신뢰 차단 라벨을 받는다.
    $pairKeyword = '\b(admin|계정|아이디|로그인|사용자명|ID/PW)\b[^\r\n:]{0,40}:\s*'
    $pairQuoted   = $pairKeyword + '(["''`])([A-Za-z0-9._-]{3,32})\2\s*/\s*(["''`])([^\s"''`]{6,64})\4'
    $pairUnquoted = $pairKeyword + '([A-Za-z0-9._-]{3,32})\s*/\s*([A-Za-z0-9._\-#$%!@^&*+=?~]{6,64})'

    # 인용형을 먼저 판정하고, 매치되면 비인용형은 보지 않는다 (두 라벨은 상호 배타 —
    #   한 문자열이 두 라벨을 함께 반환하면 caller의 차단 판정이 흐려진다).
    $quotedHit = $false
    foreach ($m in [regex]::Matches($content, "(?i)$pairQuoted")) {
        # 그룹: 1=키워드 2=여는 인용 3=id 4=닫는 인용 5=pw
        if (Test-CredentialPairToken $m.Groups[3].Value $m.Groups[5].Value) { $quotedHit = $true; break }
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
