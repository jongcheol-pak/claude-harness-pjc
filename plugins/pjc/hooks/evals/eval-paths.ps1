# eval-paths.ps1 — 골든 러너 격리 폴더의 경로 계산 + 잔여 정리 (dot-source 전용, 부작용 없음)
#
# 왜 별 파일인가: `filter-spec.ps1`과 같은 이유다 — **코디네이터(`run-hook-evals.ps1`)와
#   `eval-common.ps1` 양쪽이 같은 경로를 필요로 한다.** 코디네이터는 sweep과 `$StateDir` 계산에,
#   `eval-common`은 `$EvalIso`·`$EvalWork` 생성에 쓴다. 두 곳에 복제하면 한쪽만 고쳤을 때
#   러너가 만드는 폴더와 sweep이 훑는 폴더가 갈리는데, 그 어긋남은 "정리가 안 된다"로만 보여
#   원인이 드러나지 않는다.
#
# 이 파일은 **함수와 상수만 정의한다** — 폴더를 만들거나 cwd를 바꾸지 않으므로
#   `eval-common`을 dot-source하지 않는 병렬 코디네이터 경로에서도 안전하게 읽을 수 있다.
#
# 5.1 호환: `??`·`?.`·삼항 등 pwsh 7 전용 문법을 쓰지 않는다 — 이 파일도 러너 전체를
#   Windows PowerShell 파서로 검사하는 축의 대상이다.

# 격리 폴더의 부모 이름. 실행마다 만드는 것을 이 한 폴더 아래로 모아
# `%LOCALAPPDATA%`·`%TEMP%` 최상위가 실행 흔적으로 덮이지 않게 한다.
$script:EvalParentName = 'pjc-hook-evals'

# dot-source 시점의 실제 홈을 잡아 둔다 — `eval-common`이 격리 중 `$env:USERPROFILE`을
# 격리 홈으로 바꾸므로, 그 뒤에 읽으면 비Windows 폴백이 격리 홈 자신을 가리키게 된다.
$script:EvalRealHome = if ([string]::IsNullOrEmpty($env:USERPROFILE)) { $HOME } else { $env:USERPROFILE }

function Get-EvalRoot {
    <#
      격리 폴더가 놓일 **베이스 경로**를 돌려준다(부모 폴더가 아니라 그 위 단계).
        Temp — 격리 홈·`-Resume` 상태·완화 경로 픽스처가 놓이는 시스템 임시 폴더.
        Work — 시나리오 작업 폴더가 놓이는 곳. **반드시 임시 폴더 '밖'이어야 한다** —
               `guard-write`가 temp 하위를 무조건 통과시키므로(H3 의도된 완화)
               픽스처가 temp 안에 있으면 차단 시나리오 전체가 우회로 무력화된다.
    #>
    param([Parameter(Mandatory = $true)][ValidateSet('Temp', 'Work')][string]$Base)

    if ($Base -eq 'Temp') { return ([System.IO.Path]::GetTempPath().TrimEnd('\', '/')) }
    if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) { return $env:LOCALAPPDATA }
    return $script:EvalRealHome   # 비Windows 폴백
}

function Invoke-EvalSweep {
    <#
      중단된 실행이 남긴 격리 폴더를 나이 기준으로 걷는다.

      정상 종료 경로는 자기 폴더를 스스로 지우므로(`run-hook-evals.ps1`·`run-scenario.ps1`의
      `finally`) 이 함수가 상대하는 것은 **kill·타임아웃으로 그 `finally`에 도달하지 못한
      실행분**뿐이다. 그 잔여물을 걷는 코드가 없어 2026-08-20 시점에 80개(9.7MB)가 쌓여 있었다.

      -Root 는 **베이스 경로 배열**이다(부모 폴더가 아니다). 대상 규칙 전부가 이 값에
        상대적으로 해석되므로, 검증에서 격리 경로를 주면 실물은 건드리지 않는다.
        기본값은 실경로 2종.
      -Days 는 보존 기간. 기본 3일인 이유는 둘이다 — ① 골든 최장 실측이 27분대라
        살아 있는 실행을 지울 위험이 없고 ② `run-scenario.ps1`이 폴더 이름 접미에 그룹명을
        넣어 만든 **"어느 그룹이 죽었는지" 진단 창**을 며칠 남겨야 한다. 즉시·당일 삭제는
        동시 실행 중인 다른 러너의 픽스처를 지우는 사고(실측된 유형)로 이어질 수 있다.
      -WhatIf 는 삭제 없이 대상만 계산한다(비가역 삭제 전 목록 확인용).

      반환: `Count`(대상 수)와 `Targets`(전체 경로 목록)를 가진 객체.
    #>
    param(
        [string[]]$Root,
        [ValidateRange(0, 3650)][int]$Days = 3,
        [switch]$WhatIf
    )

    if (-not $Root -or @($Root).Count -eq 0) {
        $Root = @((Get-EvalRoot -Base 'Work'), (Get-EvalRoot -Base 'Temp'))
    }

    $cutoff = (Get-Date).AddDays(-$Days)
    $targets = New-Object System.Collections.Generic.List[string]

    foreach ($r in @($Root)) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        if (-not (Test-Path -LiteralPath $r)) { continue }

        # ① 현행 구조 — <root>\pjc-hook-evals\run\<접미>
        #    같은 부모 안의 `state`(-Resume 입력)·`scratch`(완화 경로 픽스처)는 수명이 달라
        #    대상 목록에 넣지 않는다. 예외 분기가 아니라 애초에 훑지 않는 것으로 제외한다.
        $runDir = Join-Path (Join-Path $r $script:EvalParentName) 'run'
        if (Test-Path -LiteralPath $runDir) {
            foreach ($d in @(Get-ChildItem -LiteralPath $runDir -Directory -ErrorAction SilentlyContinue)) {
                if ($d.LastWriteTime -lt $cutoff) { $targets.Add($d.FullName) }
            }
        }

        # ② 레거시 평면 이름 — 부모 폴더 도입 이전에 최상위에 흩어져 만들어지던 것들.
        #    `pjc-hook-evals-<접미>`(작업 폴더·격리 홈·시나리오 보조 홈) · `pjc-hook-evals-state`
        #    (구 -Resume 상태 루트 — 새 코드는 부모 아래 `state`를 쓰므로 다시 읽지 않는다) ·
        #    `pjc-hook-eval-scratch`(단수형이라 위 패턴에 걸리지 않아 따로 든다).
        foreach ($d in @(Get-ChildItem -LiteralPath $r -Directory -Filter 'pjc-hook-eval*' -ErrorAction SilentlyContinue)) {
            # 새 부모는 이름에 하이픈이 없어 아래 정규식에 걸리지 않지만, 이름이 한 글자만
            # 달라져도 통째로 지워지는 자리라 명시적으로 한 번 더 막는다.
            if ($d.Name -eq $script:EvalParentName) { continue }
            if ($d.Name -notmatch '^pjc-hook-eval(s-.+|-scratch)$') { continue }
            if ($d.LastWriteTime -lt $cutoff) { $targets.Add($d.FullName) }
        }
    }

    if (-not $WhatIf) {
        foreach ($t in $targets) {
            # fail-open — 잠긴 파일 등으로 못 지워도 스위트를 멈추지 않는다(다음 실행이 재시도).
            Remove-Item -Recurse -Force -LiteralPath $t -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{ Count = $targets.Count; Targets = @($targets) }
}
