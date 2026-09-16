# 픽스처용 guard-bash 최소 사본 — 분할 헬퍼 동기 축의 **사본** 쪽이다.

# 픽스처용 최소 사본 — 축 ⑯「분할 헬퍼 동기」가 두 파일의 이 함수를 대조한다.
# 실물의 판정 로직 전부를 담을 필요는 없다. 재는 것은 「두 사본이 같은가」이지 분할 자체가 아니다.
function Split-TopLevel([string]$s, [bool]$PsQuoting = $false) {
    $parts = New-Object System.Collections.Generic.List[string]
    $cur = ''
    $q = $null
    foreach ($ch in $s.ToCharArray()) {
        if ($q) {
            $cur += $ch
            if ($ch -eq $q) { $q = $null }
        } elseif ($ch -eq '"' -or $ch -eq "'") {
            $q = $ch; $cur += $ch
        } elseif ($ch -eq ';' -or $ch -eq '|') {
            $parts.Add($cur); $cur = ''
        } else {
            $cur += $ch
        }
    }
    $parts.Add($cur)
    return $parts
}
