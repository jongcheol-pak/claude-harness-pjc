# write-gate-trivial.ps1 — 작은 변경 통과 판정 — 근거는 `rules/trivial-gate-rationale.md`의 「§1 write-gate-trivial.ps1 — 작은 변경 통과 판정」

# 요청 단위 누적 판정 — 근거는 `rules/trivial-gate-rationale.md`의 「§3 요청 단위 누적 판정」
#   임계를 넘었으면 사유 문자열을, 아니거나 판정 근거를 못 얻으면 $null(fail-open)을 돌려준다.
function Get-TrivialTallyReason {
    param($data, [string]$targetPath)
    $tp = [string]$data.transcript_path
    if ([string]::IsNullOrWhiteSpace($tp)) { return $null }

    # 마지막 promptId = 지금 요청. user 줄에만 실리고 사람 프롬프트마다 바뀐다. 꼬리부터 읽는다.
    $promptId = $null
    try {
        $fs = [System.IO.File]::Open($tp, 'Open', 'Read', 'ReadWrite')
        try {
            foreach ($window in @(65536, 4194304)) {
                $n = [int][Math]::Min($fs.Length, $window)
                $null = $fs.Seek(-$n, 'End')
                $buf = New-Object byte[] $n
                $got = $fs.Read($buf, 0, $n)
                $tail = [System.Text.Encoding]::UTF8.GetString($buf, 0, $got)
                $m = [regex]::Matches($tail, '"promptId":"([0-9A-Za-z-]{8,64})"')
                if ($m.Count) { $promptId = $m[$m.Count - 1].Groups[1].Value; break }
                if ($n -ge $fs.Length) { break }
            }
        } finally { $fs.Close() }
    } catch { return $null }
    if (-not $promptId) { return $null }

    $homeBase = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }
    $tallyDir = Join-Path $homeBase '.claude/.state/trivial-tally'
    $tallyFile = Join-Path $tallyDir $promptId
    try {
        New-Item -ItemType Directory -Force -Path $tallyDir -ErrorAction Stop | Out-Null
        Add-Content -LiteralPath $tallyFile -Value (($targetPath -replace '\\', '/').ToLowerInvariant()) -Encoding utf8 -ErrorAction Stop
        $entries = @(Get-Content -LiteralPath $tallyFile -Encoding utf8 -ErrorAction Stop | Where-Object { $_ })
    } catch { return $null }

    $count = $entries.Count
    $fileCount = @($entries | Sort-Object -Unique).Count
    if ($fileCount -ge 3 -or $count -ge 4) { return "이 요청에서 trivial 통과 ${count}회 · 파일 ${fileCount}개" }
    return $null
}

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

            # 언어별 정의 형태 — 확장자를 가려 적용한다 — 근거는 `rules/trivial-gate-rationale.md`의 「§2 새 정의 감지 — 언어별 형태」
            if (-not $definesNewSymbol) {
                $jsExts = @('.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs')
                $langSymbolRules = @(
                    @{ Exts = @('.rs'); Rx = '(?m)\bfn\s+\w+\s*[<(]' },
                    @{ Exts = @('.go'); Rx = '(?m)^\s*func\s*\([^)]*\)\s*\w+\s*[(\[]' },
                    @{ Exts = $jsExts; Rx = '(?m)\b(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b|(?:\([^()]*\)|[A-Za-z_$][\w$]*)\s*(?::\s*[^=]+?)?\s*=>)' },
                    @{ Exts = $jsExts; Rx = '(?m)^\s*(?:(?:async|static|get|set|override|public|private|protected|readonly)\s+)*(?!(?:if|for|while|switch|catch|with|function|return|do|else|try|finally)\b)[A-Za-z_$#][\w$]*\s*\([^()]*\)\s*(?::\s*[^{;=()]+)?\{\s*$' },
                    @{ Exts = @('.cs', '.java', '.c', '.cpp', '.cc', '.h', '.hpp'); Rx = '(?m)^\s*(?!(?:return|new|else|throw|await|yield|case|goto|using|var|let|const|lock|fixed|if|for|foreach|while|switch|catch|do|try|sizeof|typeof|nameof|delete|in|out|ref|is|as|not|and|or)\b)[A-Za-z_][\w<>\[\],.?:*&]*\s+\**[A-Za-z_]\w*\s*\([^()]*\)\s*(?:const\s*)?(?:\{|=>|$)' }
                )
                foreach ($lr in $langSymbolRules) {
                    if (($lr.Exts -contains $ext) -and ($newStr -match $lr.Rx)) { $definesNewSymbol = $true; break }
                }
            }

            # 순수 값 치환 감지 — 근거는 `rules/write-gate-rationale.md`의 「§13 순수 값 치환 감지」
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
            # 값치환 우회는 스타일/마크업 파일에만 적용한다 — 근거는 `rules/write-gate-rationale.md`의 「§14 값치환 우회는 스타일/마크업 파일에만 적용한다」
                    $styleExts = @($wgRules.styleExts)
            $isStyleFile = $styleExts -contains $ext
            # 스타일 파일 + 값이 하나라도 정규화됨(치환 대상 존재) + 정규화 후 동일(구조 동일) + 새 정의 아님
            $isPureValueSwap = $isStyleFile -and (-not $definesNewSymbol) -and ($normOld -ne $oldStr) -and ($normOld -eq $normNew)

            # 작은 변경(3줄 + 300자, 새 정의 없음) 또는 순수 값 치환 → trivial 통과
            if (($maxLines -le 3 -and $maxLen -le 300 -and -not $definesNewSymbol) -or $isPureValueSwap) {
                # 누적 임계를 넘으면 exit 0 하지 않고 반환해 plan 존재·PLAN-EXEMPT 검사로 흘린다.
                #   사유는 guard-write 의 차단 메시지가 읽는다 — 근거는 `rules/trivial-gate-rationale.md`의 「§3 요청 단위 누적 판정」
                $script:TrivialTallyReason = Get-TrivialTallyReason $data $targetPath
                if ($script:TrivialTallyReason) { return }
                $why = if ($isPureValueSwap) { '순수 값 치환(리터럴만 변경, 구조 동일)' } else { '<=3줄, 새 정의 없음' }
                # M7: 소스 파일의 3줄 이하 통과 중 상수·수치·로직 변경(타임아웃·한계·포트 등)은 plan 없이 새므로
                #   impact-warn(사후 caller 검출)에 더해 검토 권장을 상기한다(차단 아님).
                $extra = if ($isSourceCode) { ' 소스의 상수·수치·로직 변경이면 pjc:plan 검토를 권장합니다.' } else { '' }
                [Console]::Error.WriteLine("[HARNESS] Trivial edit ($why): plan 검사 우회. 영향은 post-write-checks 의 impact-warn 규칙이 검증합니다.$extra")
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
            [Console]::Error.WriteLine("[HARNESS] Trivial write (테스트·재현 파일, ${wLines}줄 <= 30): plan 검사 우회. 영향은 post-write-checks 의 impact-warn 규칙이 검증합니다.")
            exit 0
        }
    }
}
