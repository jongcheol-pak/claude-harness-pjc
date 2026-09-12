# 픽스처 — 「관련 파일 파서 동기」 축이 대조하는 PowerShell 쪽 최소 구현이다.
#   실제 판정을 하지 않는다. 축이 재는 것은 **네 요소가 양쪽에 다 있는가**뿐이다.
function Get-StaleFeatures {
    $sec = [regex]::Match($body, '(?ms)^##\s*관련 파일\b(.*?)(?=^##\s|\z)')
    $inFence = $false
    foreach ($rawLine in ($sec.Groups[1].Value -split "\n")) {
        if ($rawLine.TrimStart() -like '```*') { $inFence = -not $inFence; continue }
        if ($inFence -or $rawLine.TrimStart() -notlike '-*') { continue }
        if ($tok -notmatch '[/\\]') { continue }
    }
}
