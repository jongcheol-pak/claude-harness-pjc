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
    return $found.ToArray()
}
