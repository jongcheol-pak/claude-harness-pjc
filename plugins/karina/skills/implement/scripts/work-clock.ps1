# work-clock.ps1 — 완료 보고의 현재 시각·소요를 한 줄로 낸다 (모델이 부르는 헬퍼 — hook 아님)
#
# 출력은 늘 `karina-clock ` 으로 시작하는 한 줄이다:
#   인자 없음          → karina-clock <현재 YYYY-MM-DD HH:mm>
#   -Since <시작>      → karina-clock <현재> <H>h <M>m
#   시작 판독 실패·미래 → karina-clock <현재> ERROR <사유>   (exit 1)
# 왜 태그 줄인가: 이 호출을 `git ls-files`·`worker-list` 같은 다른 명령에 `;` 로 이어 붙이면 그 명령의
#   stderr 가 섞인다. 「stderr 가 나오면 실패」로 가르면 정상 경우에도 실패로 읽혀, 판정을 이 태그 줄 하나로 한다.
# 왜 실패에도 현재 시각을 내는가: 시작을 못 읽어도 완료 시각은 기록해야 해, 다시 부르는 왕복을 없앤다.
# 왜 미래 시작을 실패로 보는가: 음수 소요는 서식에 맞는 엉뚱한 값이 되어 보고에 그대로 실린다.
# 왜 출력에 한글이 없는가: Git Bash 를 거친 PowerShell 출력에서 한글이 깨진다.
# 왜 -Now 를 받는가: 현재 시각을 바깥에서 넣지 못하면 날짜 경계·소요 계산을 재현할 방법이 없다(골든이 쓴다).
# stdin 은 읽지 않는다 — 모델이 리다이렉트 없이 부르면 입력을 기다리며 멈춘다.
# PS 5.1·7 양쪽에서 돈다 — Windows 에는 5.1 만 있을 수 있다.
param([string]$Since = '', [string]$Now = '')

$fmt = 'yyyy-MM-dd HH:mm'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertFrom-ClockText([string]$Text) {
    $value = [datetime]::MinValue
    $ok = [datetime]::TryParseExact($Text.Trim(), $fmt, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$value)
    if ($ok) { return $value }
    return $null
}

$nowValue = Get-Date
if ($Now) {
    $parsedNow = ConvertFrom-ClockText $Now
    if ($null -eq $parsedNow) {
        Write-Output ('karina-clock ' + $nowValue.ToString($fmt, $inv) + ' ERROR now-unparsed')
        exit 1
    }
    $nowValue = $parsedNow
}
$nowText = $nowValue.ToString($fmt, $inv)

if (-not $Since) {
    Write-Output ('karina-clock ' + $nowText)
    exit 0
}

$start = ConvertFrom-ClockText $Since
if ($null -eq $start) {
    Write-Output ('karina-clock ' + $nowText + ' ERROR start-unparsed')
    exit 1
}
if ($start -gt $nowValue) {
    Write-Output ('karina-clock ' + $nowText + ' ERROR start-in-future')
    exit 1
}

$minutes = [int][math]::Floor(($nowValue - $start).TotalMinutes)
Write-Output ('karina-clock ' + $nowText + ' ' + [math]::Floor($minutes / 60) + 'h ' + ($minutes % 60) + 'm')
exit 0
