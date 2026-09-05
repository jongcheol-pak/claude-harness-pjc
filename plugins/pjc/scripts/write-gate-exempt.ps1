# write-gate-exempt.ps1 — PLAN-EXEMPT 면제 판정 — 근거는 `rules/plan-exempt-rationale.md`의 「§23 PLAN-EXEMPT 면제 판정」

function Invoke-PlanExemptGate {
    param($data, [string]$targetPath, [string]$projectRoot, [scriptblock]$OnAllow)
    $exFile = [System.IO.Path]::GetFileName($targetPath)
    $exParent = ''
    $exIsRootFile = $false
    try {
        $exDir = [System.IO.Path]::GetDirectoryName($targetPath)
        $exParent = [System.IO.Path]::GetFileName($exDir)
        if ($exDir -and $projectRoot) {
            $exIsRootFile = ($exDir.TrimEnd('\', '/') -ieq ([string]$projectRoot).TrimEnd('\', '/'))
        }
    } catch {}
    $exemptHit = $false
    $tppX = [string]$data.transcript_path
    if ((-not [string]::IsNullOrWhiteSpace($tppX)) -and (Test-Path -LiteralPath $tppX)) {
        try {
            $cmpIC = [System.StringComparison]::OrdinalIgnoreCase
            $exMarker = '[PLAN-EXEMPT]'
            $exTextRx = [regex]::new('"type"\s*:\s*"text"\s*,\s*"text"\s*:\s*"((?:[^"\\]|\\.)*)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $exStartRx = [regex]::new('(?:^|\\n)(?:[ ]|\\t)*(?:[-*>+|`]+(?:[ ]|\\t)*|\d+[.)](?:[ ]|\\t)*)?\[PLAN-EXEMPT\]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($ln in (Select-String -LiteralPath $tppX -Pattern $exMarker -SimpleMatch)) {
                $t = [string]$ln.Line
                if (-not [regex]::IsMatch($t, '(?<!\\)"type"\s*:\s*"assistant"')) { continue }
                if ([regex]::IsMatch($t, '"isSidechain"\s*:\s*true')) { continue }
                foreach ($fm in $exTextRx.Matches($t)) {
                $body = $fm.Groups[1].Value
                foreach ($m in $exStartRx.Matches($body)) {
                $rest = $body.Substring($m.Index + $m.Length)
                $exNl = $rest.IndexOf('\n')
                if ($exNl -ge 0) { $rest = $rest.Substring(0, $exNl) }
                foreach ($tok in ($rest -split '[\s·,;"''()`*<>「」]+')) {
                    if ([string]::IsNullOrWhiteSpace($tok)) { continue }
                    $tf = ''
                    $tp = ''
                    try {
                        $tf = [System.IO.Path]::GetFileName($tok)
                        $tp = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($tok))
                    } catch { continue }
                    if ([string]::IsNullOrEmpty($tf) -or (-not $tf.Equals($exFile, $cmpIC))) { continue }
                    if ([string]::IsNullOrEmpty($tp)) {
                        if ($exIsRootFile) { $exemptHit = $true; break }
                    } elseif ($tp.Equals($exParent, $cmpIC)) {
                        $exemptHit = $true
                        break
                    }
                }
                if ($exemptHit) { break }
                }
                if ($exemptHit) { break }
                }
                if ($exemptHit) { break }
            }
        } catch { $exemptHit = $false }
    }
    if ($exemptHit) {
        [Console]::Error.WriteLine("[HARNESS] PLAN-EXEMPT: 사용자 승인 면제($exFile). plan 검사 우회.")
        if ($OnAllow) { & $OnAllow }
        exit 0
    }
}