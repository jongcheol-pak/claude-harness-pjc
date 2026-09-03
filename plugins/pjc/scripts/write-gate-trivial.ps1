# write-gate-trivial.ps1 — 작은 변경 통과 판정 — 근거는 `rules/trivial-gate-rationale.md`의 「§1 write-gate-trivial.ps1 — 작은 변경 통과 판정」

function Invoke-TrivialEditGate {
    param($data, [string]$targetPath, [string]$ext, [bool]$isSourceCode, $wgRules)
    $baseName = [System.IO.Path]::GetFileName($targetPath)
    # 작은 변경 통과 — 근거는 `rules/write-gate-rationale.md`의 「§12 작은 변경 통과」
    if ($data.tool_name -eq 'Edit' -or $data.tool_name -eq 'MultiEdit') {
        $oldStr = $data.tool_input.old_string
        $newStr = $data.tool_input.new_string

        # MultiEdit은 edits 배열 — 전체 합산
        if ($data.tool_name -eq 'MultiEdit' -and $data.tool_input.edits) {
            $oldStr = ($data.tool_input.edits | ForEach-Object { $_.old_string }) -join "`n"
            $newStr = ($data.tool_input.edits | ForEach-Object { $_.new_string }) -join "`n"
        }

        if ($null -ne $oldStr -and $null -ne $newStr) {
            $oldLines = ($oldStr -split "`n").Count
            $newLines = ($newStr -split "`n").Count
            $maxLines = [Math]::Max($oldLines, $newLines)
            $maxLen = [Math]::Max($oldStr.Length, $newStr.Length)

            # 새 정의(함수/클래스/메서드) 추가 패턴 — 이건 trivial 아님
            $definesNewSymbol = $newStr -match '(?m)\b(class|interface|struct|enum|record)\s+\w' -or
                                $newStr -match '(?m)\b(public|private|protected|internal|static)\s+[\w<>\[\],\s]+\s+\w+\s*\(' -or
                                $newStr -match '(?m)\b(def|func|fun|function)\s+\w+\s*\('

            # 순수 값 치환 감지 — 근거는 `rules/write-gate-rationale.md`의 「§13 # 순수 값 치환 감지」
            $normValue = {
                param([string]$s)
                $c = [char]1 + 'C'   # 소스에 안 나타나는 제어문자 기반 토큰 (PS 5.1 호환)
                $n = [char]1 + 'N'
                $s = [regex]::Replace($s, '#[0-9a-fA-F]{3,8}\b', $c)            # hex 색상 먼저
                $s = [regex]::Replace($s, '\b\d+(\.\d+)?(px|rem|em|pt|%|vh|vw|dp|sp|fr|ch|ex|cm|mm|in|deg)?\b', $n)
                return $s
            }
            $normOld = & $normValue $oldStr
            $normNew = & $normValue $newStr
            # 값치환 우회는 스타일/마크업 파일에만 적용한다 — 근거는 `rules/write-gate-rationale.md`의 「§14 # 값치환 우회는 스타일/마크업 파일에만 적용한다」
                    $styleExts = @($wgRules.styleExts)
            $isStyleFile = $styleExts -contains $ext
            # 스타일 파일 + 값이 하나라도 정규화됨(치환 대상 존재) + 정규화 후 동일(구조 동일) + 새 정의 아님
            $isPureValueSwap = $isStyleFile -and (-not $definesNewSymbol) -and ($normOld -ne $oldStr) -and ($normOld -eq $normNew)

            # 작은 변경(3줄 + 300자, 새 정의 없음) 또는 순수 값 치환 → trivial 통과
            if (($maxLines -le 3 -and $maxLen -le 300 -and -not $definesNewSymbol) -or $isPureValueSwap) {
                $why = if ($isPureValueSwap) { '순수 값 치환(리터럴만 변경, 구조 동일)' } else { '<=3줄, 새 정의 없음' }
                # M7: 소스 파일의 3줄 이하 통과 중 상수·수치·로직 변경(타임아웃·한계·포트 등)은 plan 없이 새므로
                #   impact-warn(사후 caller 검출)에 더해 검토 권장을 상기한다(차단 아님).
                $extra = if ($isSourceCode) { ' 소스의 상수·수치·로직 변경이면 pjc:plan 검토를 권장합니다.' } else { '' }
                [Console]::Error.WriteLine("[HARNESS] Trivial edit ($why): plan 검사 우회. 영향은 impact-warn hook이 검증합니다.$extra")
                exit 0
            }
        }
    }

    # 신규 파일 Trivial 통과 — 근거는 `rules/write-gate-rationale.md`의 「§15 신규 파일 Trivial 통과」
    if ($data.tool_name -eq 'Write' -and $null -ne $data.tool_input.content) {
        $wContent = [string]$data.tool_input.content
        $wLines = ($wContent -split "`n").Count
        $isTestPath = ($targetPath -match '(?i)[\\/](tests?|__tests__|spec)[\\/]') -or
                      ($baseName -match '(?i)^(repro|scratch|tmp)[\w.-]*$')
        if ($wLines -le 30 -and $isTestPath) {
            [Console]::Error.WriteLine("[HARNESS] Trivial write (테스트·재현 파일, ${wLines}줄 <= 30): plan 검사 우회. 영향은 impact-warn hook이 검증합니다.")
            exit 0
        }
    }
}
