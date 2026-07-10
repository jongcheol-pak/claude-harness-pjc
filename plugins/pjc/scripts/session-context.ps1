# session-context.ps1 — SessionStart: 로컬 plan/notes 상태 요약 컨텍스트 주입 (비차단)
#
# 왜: ① 글로벌 CLAUDE.md의 "작업 시작 전 plan.md·notes.md 최근 항목 확인" 규칙이 전적으로
#   모델 자율에 맡겨져 있어 긴 세션·새 세션에서 누락되기 쉽다 — 세션 시작 시점에 기계가
#   상태 요약 1~3줄을 주입해 규칙을 구조화한다(v1.112.0).
#   ② 컨텍스트 요약(auto-compact) 직후는 자율 루프(implement-task)의 절차 규칙·plan 상태가
#   요약으로 희석되는 최위험 지점 — source=compact일 때 재확인 리마인더를 추가 주입한다.
# 어떻게: stdin(SessionStart JSON)의 cwd에서 plan(루트 plan.md 우선, 없으면 docs/plans/ 최신
#   수정 5개 중 task 체크박스가 있는 파일 — 글로벌 CLAUDE.md의 확인 순서와 동일)과 notes.md를
#   찾아 미완료 task 수·최신 항목 날짜를 stdout으로 출력한다(SessionStart 규약: stdout=컨텍스트
#   주입, exit 0). plan·notes 둘 다 없으면 무출력(비 pjc 프로젝트 노이즈 방지) — 단 compact
#   리마인더는 plan 유무와 무관하게 출력한다(요약 직후엔 plan 없어도 스킬 규약 재확인 가치).
# 안전: 정보 주입 hook(차단·경고 아님 — hook-event-log 적재 대상 아님). 모든 실패 경로는
#   조용히 exit 0 (fail-open — 세션 시작을 절대 막지 않는다). warn-version-drift와 동일 골격.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

try {
    # ---- 입력 파싱 (cwd·source) ----
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $inp = $null
    try { $inp = $raw | ConvertFrom-Json } catch { exit 0 }
    $cwd = [string]$inp.cwd
    $source = [string]$inp.source   # startup|resume|clear|compact (부재 시 빈 문자열 → 비compact 취급)

    $lines = New-Object System.Collections.Generic.List[string]

    # ---- compact 리마인더 (plan 유무 무관) ----
    if ($source -eq 'compact') {
        $lines.Add("[pjc 세션 컨텍스트] 컨텍스트 요약 직후입니다 — 진행 중이던 작업이 있으면 plan.md의 현재 task와 활성 스킬(implement-task 등)의 Halt 조건·승인 게이트·커밋 프로토콜을 요약 기억에 의존하지 말고 SKILL 문서·plan.md 원문에서 재확인하세요.")
    }

    if (-not [string]::IsNullOrWhiteSpace($cwd) -and (Test-Path -LiteralPath $cwd -PathType Container)) {
        # ---- plan 탐색: 루트 plan.md 우선 → docs/plans/ 폴백 ----
        # docs/plans/에는 plan이 아닌 파일(deferred.md 등)도 있으므로 task 체크박스(- [ ] T<N>)가
        # 있는 파일만 plan으로 인정한다. 최신 수정 5개만 검사(세션 시작 지연 상한).
        $rootPlan = Join-Path $cwd 'plan.md'
        $planPath = $null
        $planLabel = $null
        if (Test-Path -LiteralPath $rootPlan -PathType Leaf) {
            $planPath = $rootPlan
            $planLabel = 'plan.md'
        } else {
            $plansDir = Join-Path $cwd 'docs/plans'
            if (Test-Path -LiteralPath $plansDir -PathType Container) {
                $cand = @(Get-ChildItem -LiteralPath $plansDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 5)
                foreach ($f in $cand) {
                    $t = $null
                    try { $t = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 } catch {}
                    if ($t -and $t -match '(?m)^- \[[ /x]\] T\d+') {
                        $planPath = $f.FullName
                        $planLabel = 'docs/plans/' + $f.Name
                        break
                    }
                }
            }
        }

        if ($planPath) {
            $planText = $null
            try { $planText = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 } catch {}
            if ($planText) {
                # task 라인만 카운트 (pjc plan 규약: "- [x] T1: ..." — 통과 체크리스트 등 다른 체크박스 제외)
                $all = [regex]::Matches($planText, '(?m)^- \[[ /x]\] T\d+').Count
                $open = [regex]::Matches($planText, '(?m)^- \[[ /]\] T\d+').Count
                if ($all -gt 0) {
                    if ($open -gt 0) {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 중 미완료 ${open}개 — 작업 시작 전 plan.md 진행 상태와 notes.md 최근 항목을 확인하세요.")
                    } else {
                        $lines.Add("[pjc 세션 컨텍스트] ${planLabel}: task ${all}개 전부 완료 — 새 작업이면 plan 교체 전 Deferred/Follow-up 잔여 항목을 확인하세요.")
                    }
                } else {
                    # task 체크박스가 없는 plan.md(비 pjc 형식) — 카운트 오보 대신 존재만 알림
                    $lines.Add("[pjc 세션 컨텍스트] ${planLabel} 존재 — 작업 시작 전 진행 상태를 확인하세요.")
                }
            }
        }

        # ---- notes.md 최신 항목 날짜 (## 최근 변경 첫 항목) ----
        $notesPath = Join-Path $cwd 'notes.md'
        if (Test-Path -LiteralPath $notesPath -PathType Leaf) {
            $notesText = $null
            try { $notesText = Get-Content -LiteralPath $notesPath -Raw -Encoding UTF8 } catch {}
            if ($notesText) {
                $m = [regex]::Match($notesText, '(?m)^- (\d{4}-\d{2}-\d{2})')
                if ($m.Success) {
                    $lines.Add("[pjc 세션 컨텍스트] notes.md 최근 항목: $($m.Groups[1].Value)")
                }
            }
        }
    }

    if ($lines.Count -gt 0) {
        # stdout → 세션 컨텍스트 주입 (SessionStart exit 0 규약 — warn-version-drift와 동일)
        Write-Output ($lines -join "`n")
    }
    exit 0
} catch {
    exit 0
}
