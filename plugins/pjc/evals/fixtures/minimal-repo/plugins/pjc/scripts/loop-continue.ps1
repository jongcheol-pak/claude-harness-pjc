# 픽스처용 loop-continue 최소 사본 — 복제 사본 동기 축의 **사본** 쪽이다(plan 탐색 함수 · 불릿 정규식).

# 실물의 판정 로직은 담지 않는다. 재는 것은 「사본이 원본과 같은가」다.
$planBulletRx = '(?m)^\s*([-*+]|\d+[.)])\s*'
function Find-PlanFileUpwards([string]$StartDir, [int]$MaxDepth = 8) {
    if ([string]::IsNullOrEmpty($StartDir)) { return $null }
    $base = [System.IO.Path]::GetFullPath($StartDir).TrimEnd('\', '/')
    $dir = $base
    for ($i = 0; $i -lt $MaxDepth; $i++) {
        if (-not $dir) { break }
        foreach ($cand in @('plan.md', 'PLAN.md', 'docs/plan.md')) {
            $pf = Join-Path $dir $cand
            if (Test-Path -LiteralPath $pf -PathType Leaf) {
                $label = if ($dir -eq $base) { $cand } else { $pf }
                return @{ Path = $pf; Label = $label }
            }
        }
        if ((Test-Path -LiteralPath (Join-Path $dir '.git')) -or
            (Test-Path -LiteralPath (Join-Path $dir '.claude') -PathType Container)) {
            return $null
        }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}
