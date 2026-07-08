# Plan: T6 이관분 — Bash 계열 PreToolUse hook in-process 통합 (v1.99.0)

## 요구 이해
- **원문 요청**: "t6 진행" — part1에서 안전·성능 트레이드오프로 스킵하고 별도 plan으로 이관한 T6(Bash hook 프로세스 절감)를 이제 구현.
- **이해한 요구**: Bash/PowerShell 도구 호출마다 PreToolUse hook 4개가 각각 pwsh를 콜드스타트(~4회, 도구 호출당 지연)하는 것을, 검사 로직을 공유 함수 모듈로 옮겨 단일 pwsh 디스패처에서 실행해 줄인다. **결정 B 확정**: 가장 위험한 게이트 `block-destructive`는 무수정·독립 실행으로 남기고(마지막 방어선 독립성 100% 보존), 나머지 3개(warn-external-ops·require-task-checkbox·warn-commit-secrets)만 모듈화+디스패처 → pwsh 콜드스타트 4→2. **관측 동작 동등**(골든의 keyword+exit code 동일 — 디스패처는 warn 2개를 단일 additionalContext로 병합하므로 바이트 동일이 아니라 관측 동작 동등), 안전 차단 무약화.
- **포함하지 않는 것으로 이해**: block-destructive의 통합(결정 B로 독립 유지 — Out of Scope), Write/Edit 계열·PostToolUse·Stop hook의 통합(이번 대상은 Bash-매처 PreToolUse만).

## Goal
Bash 도구 호출당 pwsh 콜드스타트를 4→2로 줄이되, block-destructive는 독립 유지하고 나머지 3 hook의 검사 동작은 골든으로 무회귀 실증한다.

## Out of Scope
- block-destructive의 디스패처 편입 (결정 B — 마지막 방어선 독립성 보존이 목적. pwsh 1회까지 줄이는 옵션 A는 채택 안 함)
- Write/Edit(require-plan·protect-harness)·PostToolUse·Stop hook 통합 (별도 논의 — 이들은 매처가 달라 같은 도구 호출에 동시 발동하지 않음, 절감 효과 작음)

## Deferred / Follow-up
- part2(스킬·에이전트 지침) — `docs/plans/2026-07-08-harness-quality-part2.md`
- .state 디듑 마커 TTL 정리, block-destructive cat+즉시실행 조합 감지 (part1 이월)

## Investigation Log
- 4개 Bash hook 구조 직접 Read 확인:
  - `block-destructive.ps1`: stdin 1회 읽기→`$cmd` 파싱→검사, block 시 `exit 2`(stderr만), pass `exit 0`. stdout JSON 없음. **cwd 미사용**. → 결정 B로 무수정 독립 유지.
  - `warn-external-ops.ps1`: stdin→`$cmd`, 항상 `exit 0`, hit 시 stderr + stdout JSON additionalContext. **cwd 미사용**.
  - `require-task-checkbox.ps1`: stdin→`$cmd`+`$data.cwd`(plan 상향 탐색 startDir, `Set-Location` 안 함:89-96), block `exit 2`(stderr), pass `exit 0`. stdout JSON 없음. QUICK env 우회.
  - `warn-commit-secrets.ps1`: stdin→`$cmd`+`$data.cwd`(**`Set-Location` 수행**:43-47), git 명령, 항상 `exit 0`, hit 시 stderr + stdout JSON. `$PSScriptRoot`로 secret-patterns.ps1 dot-source(:75).
- 공통: 전부 `[Console]::In.ReadToEnd()` 1회 + `ConvertFrom-Json` → `$data`. `exit`가 top-level라 in-process 격리 불가(part1 T6 스킵 사유) → 함수 반환 방식으로 전환 필요.
- 참조처 전수 grep(코드): `hooks.json`(4 Bash 배선), `run-hook-evals.ps1`·`hook-cases.json`(골든 — 파일명으로 Invoke-Hook), `validate.ps1`(`$hooks` 9종 목록:150·`$knownHelpers`:151), `protect-harness.ps1`·`post-write-checks.ps1`(`$harnessHookName` alternation — 설치본 개조 차단·H2 감시). README·AGENTS.md scripts 목록. require-plan/secret-patterns/implement-task는 주석·산문 언급만(동작 무관).
- validate.ps1 `$hooks`(9종)에 없고 `$knownHelpers`에도 없는 scripts/*.ps1은 WARN(:166) → 신규 2파일 등록 필요.
- 워킹트리: part1 브랜치 `task/harness-quality-part1`, 전 커밋 완료·깨끗. 이 작업은 그 위에 이어짐(같은 릴리즈에 합류).

## Risks & Unknowns
| 위험 | 영향 | 완화책 |
|---|---|---|
| 함수 전환 중 로직 미세 변형 → 동작 회귀 | 검사 누락/오탐 | 로직을 **문장 단위로 이동**(재작성 아님), 기존 골든 241 전부 무수정 통과가 1차 게이트 + 래퍼 경유·디스패처 경유 양쪽 골든 |
| warn-commit-secrets의 Set-Location이 디스패처 내 다른 검사·후속에 잔존 | cwd 오염 | 함수 내부 Push-Location/finally Pop-Location으로 자기완결(전역 cwd 불변) |
| 디스패처가 require-task-checkbox block(exit 2)을 못 전파 | 체크박스 게이트 무력화 | block 결과 시 즉시 stderr+exit 2, 골든에 "디스패처 경유 미완료 T커밋 차단" 케이스 |
| additionalContext 2개(warn-external·commit-secrets) 병합 형식 오류 | 모델 컨텍스트 전달 실패 | 단일 JSON payload로 병합(두 메시지 개행 결합), 골든에 "둘 다 hit 시 병합 출력" 케이스 |
| $harnessHookName 집합 누락 → 신규 스크립트 설치본 개조 미차단 | 자기보호 구멍 | v1.97.2 규약대로 두 파일 집합에 dispatch·lib 추가 + protect-harness 골든 |
| block-destructive 독립성 훼손(실수로 디스패처 편입) | 마지막 방어선 결합 | block-destructive는 hooks.json 독립 엔트리 유지·스크립트 무수정(diff 0 확인) |

## Impact Analysis
### 4-A. 심볼/타입 추적 결과
| 대상 | 영향 받는 파일 | 영향 종류 |
|---|---|---|
| warn-external-ops·require-task-checkbox·warn-commit-secrets 파일명 (hook 배선) | `hooks.json`(Bash 4→2 재배선)·`validate.ps1`($hooks 유지, dispatch 추가)·`run-hook-evals.ps1`(래퍼 경유 기존 케이스 유지 + 디스패처 경유 신규) | 배선·테스트 |
| 3 hook 검사 로직 | 각 스크립트(→얇은 래퍼)·신규 `bash-hook-lib.ps1`(함수 이관) | 구조 리팩토링 |
| `$harnessHookName` (protect-harness.ps1:70·post-write-checks.ps1:56 동일 유지) | 두 파일에 `pre-bash-dispatch`·`bash-hook-lib` 추가 | 집합 확장 |
| block-destructive.ps1 | (무변경 — 독립 유지) | 없음 |
| secret-patterns.ps1 dot-source(`$PSScriptRoot`) | warn-commit-secrets 함수가 lib로 이동해도 `$PSScriptRoot`=scripts/ 동일 | 무영향(확인) |

### 4-B. 계약·직렬화 변경
- hook stdin JSON 계약 불변. 함수 반환 계약 신설(내부): `@{ Action='block'|'warn'|'pass'; ExitCode; Stderr=[string[]]; Context=[string] }`. 래퍼·디스패처가 이를 stderr/stdout JSON/exit로 번역 — 외부(Claude Code) 관측 동작은 불변.

### 4-C. 테스트 파일
- `run-hook-evals.ps1` + `hook-cases.json`: 기존 warn-external-ops·require-task-checkbox·warn-commit-secrets 케이스는 래퍼 경유로 그대로 통과(무회귀) + 디스패처 경유 동등성 케이스 신설.

### 4-D. 재사용 확인
| 신규 심볼 | 유사 기존 구현 검색 결과 | 재사용/신규 사유 |
|---|---|---|
| `bash-hook-lib.ps1`(Invoke-WarnExternalOps/RequireTaskCheckbox/WarnCommitSecrets) | 기존 공유 헬퍼는 `secret-patterns.ps1`(패턴만) — 검사 로직 모듈 없음 | 신규 — 3 hook 로직 단일 출처(dot-source), secret-patterns와 동일 헬퍼 패턴 |
| `pre-bash-dispatch.ps1` | 없음(post-write-checks의 "2 검사 1프로세스"는 단일 스크립트 내 통합) | 신규 — Bash hook 3종 in-process 오케스트레이션 전용 |

### Verified by
- grep 3 스크립트 파일명 → 코드 참조 6곳(hooks.json·validate·run-hook-evals·hook-cases·protect-harness·post-write) 전부 위 표 반영
- grep `$harnessHookName` → protect-harness.ps1:70·post-write-checks.ps1:56 두 곳(동일 문자열 유지 규약)

## Decisions
### D1. 통합 범위 = 결정 B (사용자 확정)
- **Chosen**: block-destructive 독립 직접 실행 유지(무수정) + 나머지 3개만 lib+디스패처. pwsh 4→2.
- **Rationale**: 마지막 방어선(rm -rf·DB 파괴 차단)을 공유 모듈 로드 실패에 결합시키지 않음. 성능 이득 대부분(4→2) 확보하면서 refactor 대상을 비치명적 3 hook으로 한정해 작업 위험 최소화.
- **Source**: 사용자 확정 (2026-07-08).

### D2. 래퍼 보존 (골든 인터페이스 유지)
- **Chosen**: 3개 스크립트를 삭제하지 않고 **얇은 래퍼**로 남긴다 — stdin 읽기→파싱→lib 함수 호출→결과를 stderr/stdout/exit로 번역. 골든 러너가 파일명으로 호출하는 기존 케이스가 그대로 통과(무회귀 1차 게이트) + standalone 실행 경로 보존(디버깅·격리 테스트).
- **Rationale**: 래퍼 경유(개별)와 디스패처 경유 두 경로가 같은 lib 함수를 호출 → 동작 단일 출처.
- **Source**: 자체 확정(골든 무회귀 최우선).

### D3. cwd 격리 (warn-commit-secrets)
- **Chosen**: WarnCommitSecrets 함수는 내부에서 `Push-Location $cwd` / `try { ... } finally { Pop-Location }`로 자기완결. 디스패처·다른 함수에 cwd 잔존 안 함.
- **Source**: 코드 확인(Set-Location:43-47) — 자체 확정.

### D4. 디스패처 실행 순서·집계
- **Chosen**: 순서 = warn-external-ops → require-task-checkbox → warn-commit-secrets(원 hooks.json 순서에서 block-destructive만 앞으로 뺀 것). 세 결과 수집 후 — Action=block이 있으면 그 stderr 출력 + `exit 2`(도구 차단), 없으면 warn Context들을 단일 additionalContext JSON으로 병합 출력 + `exit 0`. 각 함수 호출은 try/catch로 격리(한 검사 예외가 나머지를 막지 않음).
- **Rationale**: block 우선 전파(체크박스 게이트 보존), 경고 병합(원래 2 hook의 additionalContext를 한 payload로 — Claude Code는 hook당 1 JSON 파싱).
- **의도된 트레이드오프(리뷰 m3)**: block(require-task-checkbox 차단) 발생 시 같은 호출의 warn 경고(시크릿 등)는 출력하지 않는다 — 원본 다중-hook 구성에선 별도 프로세스가 warn stderr를 낼 수 있으나, 차단된 커밋이라 안전 회귀는 아니고 차단 해소 후 재시도 시 warn이 노출된다.
- **Source**: 자체 확정.

### D5. 파일 위치·명명
- **Chosen**: `plugins/pjc/scripts/bash-hook-lib.ps1`(dot-source 헬퍼 → validate `$knownHelpers`), `plugins/pjc/scripts/pre-bash-dispatch.ps1`(hook → validate `$hooks`). 둘 다 `$harnessHookName` 집합에 추가.
- **Source**: 기존 레이아웃(scripts/ 평면·secret-patterns 선례) — 자체 확정.

### D6. 버전
- **Chosen**: 1.98.0(part1) → **1.99.0**(minor — hook 배선 구조 변경). part2는 완료 시 그다음 minor로 재부여(문서에 반영).
- **Source**: 저장소 관례 — 자체 확정.

## Tasks

- [x] T1. bash-hook-lib.ps1 모듈 추출 + 3개 스크립트를 얇은 래퍼로 전환 (D2·D3)
  - **Type**: D
  - **Acceptance**: Given 3 hook, When lib로 로직 이관, Then ① `bash-hook-lib.ps1` 신설 — `Invoke-WarnExternalOps($data)`·`Invoke-RequireTaskCheckbox($data)`·`Invoke-WarnCommitSecrets($data)`가 각 스크립트의 검사 로직을 **문장 단위 이동**(재작성 아님)해 결과 객체 반환(`Action`/`ExitCode`/`Stderr`/`Context`), `exit`→`return`, `[Console]` 직접 출력 제거 ② WarnCommitSecrets는 Push/finally Pop-Location으로 cwd 자기완결 ③ 3개 스크립트는 stdin 읽기+파싱+lib 함수 호출+결과 번역만 남은 래퍼 ④ **기존 골든(warn-external-ops·require-task-checkbox·warn-commit-secrets 관련 전 케이스)이 래퍼 경유로 무수정 통과** ⑤ 전 ps1 parse OK, .ps1 UTF-8 BOM 유지
  - **Files**:
    - 주: `plugins/pjc/scripts/bash-hook-lib.ps1`(신규)
    - 동반: `plugins/pjc/scripts/warn-external-ops.ps1`·`require-task-checkbox.ps1`·`warn-commit-secrets.ps1`(→래퍼)
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1`(기존 케이스 무수정 통과 확인)
  - **Edge Cases**: stdin 파싱 실패(래퍼가 exit 0)·빈 command·QUICK env(require-task-checkbox)·secret-patterns dot-source 경로($PSScriptRoot=scripts/)·git repo 없음(warn-commit-secrets fail-open)
  - **Halt Forecast**:
    - (i) 로직 이동 중 미세 변형 → 기존 골든 241 무수정 통과가 즉시 검출(케이스별 격리)
    - (ii-a) 구조 변경(신규 lib 파일·3 스크립트 재구성) → `## 사전 승인 항목`
  - **Depends on**: -

- [x] T2. pre-bash-dispatch.ps1 디스패처 (D4)
  - **Type**: D
  - **Acceptance**: Given Bash 도구 호출, When 디스패처 실행, Then ① stdin 1회 읽기+파싱 후 lib 함수 3개를 순서(warn-external→require-task-checkbox→warn-commit-secrets)대로 호출, 각 try/catch 격리 ② Action=block 있으면 그 stderr + `exit 2`(도구 차단), 없으면 warn Context 병합 단일 additionalContext JSON + `exit 0` ③ 클린 명령 무출력 exit 0 ④ block-destructive는 이 디스패처와 무관(별도 엔트리) ⑤ parse OK·BOM
  - **Files**:
    - 주: `plugins/pjc/scripts/pre-bash-dispatch.ps1`(신규)
    - 동반: `plugins/pjc/scripts/bash-hook-lib.ps1`(dot-source)
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1`
  - **Edge Cases**: 세 검사 모두 무hit(무출력)·한 함수 예외(나머지 계속)·block+warn 동시(block 우선 exit 2)·warn 2개 동시(병합)·stdin 빈 문자열
  - **Halt Forecast**:
    - (i) additionalContext 병합/exit 전파 오류 → T4 동등성 골든이 검출
  - **Depends on**: T1

- [ ] T3. hooks.json 재배선 + validate·자기보호 집합 갱신 (D5)
  - **Type**: C
  - **Acceptance**: ① hooks.json PreToolUse Bash|PowerShell = block-destructive(무변경) + pre-bash-dispatch 2엔트리(warn-external-ops·require-task-checkbox·warn-commit-secrets 개별 엔트리 제거) — 래퍼 스크립트 파일은 존치 ② validate.ps1 `$hooks`에 `pre-bash-dispatch.ps1` 추가(3 래퍼는 목록 유지)·`$knownHelpers`에 `bash-hook-lib.ps1` 추가 ③ protect-harness.ps1·post-write-checks.ps1 `$harnessHookName`에 `pre-bash-dispatch`·`bash-hook-lib` 추가(두 파일 동일 문자열) ④ block-destructive.ps1 diff 0(무수정 확인) ⑤ JSON 매니페스트 파싱 OK
  - **Files**:
    - 주: `plugins/pjc/hooks/hooks.json`
    - 동반: `validate.ps1`·`plugins/pjc/scripts/protect-harness.ps1`·`plugins/pjc/scripts/post-write-checks.ps1`
  - **Edge Cases**: 디스패처 command 래퍼(pwsh 프로브 패턴 기존과 동일)·hooks.json 순서(block-destructive 먼저)
  - **Halt Forecast**:
    - (i) $harnessHookName 누락 → T4 protect-harness 골든이 검출
  - **Depends on**: T2

- [ ] T4. 동등성 골든 + 자기보호 골든 (무회귀 실증)
  - **Type**: C
  - **Acceptance**: Given 골든 러너, When 실행, Then ① **디스패처 전수 동등성(리뷰 m4)** — warn-external-ops·require-task-checkbox·warn-commit-secrets 관련 **기존 케이스 전량**을 같은 stdin JSON으로 `pre-bash-dispatch.ps1`에도 재공급하는 루프를 추가해, 각 케이스의 exit code·keyword가 개별 hook 경유와 일치함을 실증(대표 선별이 아닌 전수 — 프로덕션 배선이 디스패처이므로). 단 warn 병합 케이스는 관측 동작 동등(keyword+exit) 기준(바이트 동일 아님) ② block+warn 동시 exit 2·warn 2개 병합·전 검사 무hit 무출력 등 디스패처 고유 분기 케이스 추가 ③ 기존 개별 케이스(래퍼 경유) 전부 유지 PASS ④ protect-harness 골든에 설치본 `pre-bash-dispatch.ps1`·`bash-hook-lib.ps1` Write 차단(exit 2) 2건 신설 ⑤ 전 골든 PASS ⑥ validate.ps1 green(WARN 0 — 신규 2파일 등록 확인)
  - **Files**:
    - 주: `plugins/pjc/hooks/evals/run-hook-evals.ps1`·`plugins/pjc/hooks/evals/hook-cases.json`
    - 테스트: (자기 자신)
  - **Edge Cases**: 디스패처 stdin 재공급이 개별 hook과 관측 동작 동등(keyword+exit, warn 병합은 바이트 비동일)·격리 홈 마커(warn 없음)·git repo 필요 케이스(warn-commit-secrets)
  - **Halt Forecast**:
    - (i) 동등성 불일치 → 원인 국소화(어느 함수/번역 단계인지 케이스가 지목), 반복 실패 시 recovery 카운터
  - **Depends on**: T3

- [ ] T5. 버전·문서·통합 검증 (D6)
  - **Type**: C
  - **Acceptance**: ① plugin.json·README 1.98.0→1.99.0 ② README Hooks/호환환경 서술이 디스패처 반영(Bash hook 프로세스 절감·block-destructive 독립)·AGENTS.md Repository Structure scripts 목록에 pre-bash-dispatch·bash-hook-lib 추가 ③ 통합 재검증: 전 ps1 parse OK·JSON 매니페스트 3종·hook 골든 전 케이스 PASS·validate.ps1 WARN 0 ④ notes.md 기록 + part1 plan의 T6 항목·Deferred 갱신(이관 완료 표시) ⑤ part2 버전 재부여 메모
  - **Files**:
    - 주: `plugins/pjc/.claude-plugin/plugin.json`·`README.md`·`AGENTS.md`·`notes.md`·`docs/plans/2026-07-08-harness-quality-part1.md`
  - **Edge Cases**: README 버전 배너 이중 표기 확인
  - **Halt Forecast**: (없음 — 문서·버전, T1~T4 결과의 기계적 반영)
  - **Depends on**: T1~T4

## 사전 승인 항목 (일괄 승인 대상)
- T1 — 구조 리팩토링(신규 lib 파일·3 스크립트를 래퍼로 재구성): 안전 hook 3종 구조 변경, 골든 무회귀로 실증
- T2 — 신규 디스패처 스크립트 추가
- T3 — hooks.json 배선 구조 변경(4→2)·validate·자기보호 집합 갱신
- 각 task 완료 시 로컬 작업 브랜치 commit

## 불가피한 Halt (위임 불가 — 일괄 사전승인 불가)
- push·main 병합·태그·GitHub 릴리즈 v1.99.0 — 최종 보고에서 별도 승인
- T4 동등성 검증 반복 실패 시 원복(hooks.json 4엔트리 복귀) 후 사용자 판단

## Verification Strategy
- 빌드: 전 ps1 PSParser parse
- 테스트: JSON 매니페스트 3종 + hook 골든 `run-hook-evals.ps1`(T1 후 무회귀·T4 후 동등성)
- 통합: `validate.ps1`(재설치 후 — 신규 2파일 등록·WARN 0)
- 무수정 실증: block-destructive.ps1 `git diff` 0

## Phase Ledger

## Retry Ledger

## Progress Log
- T1 완료 (커밋 4e86483): bash-hook-lib.ps1 모듈(3함수) + 3 스크립트 래퍼화. 골든 241/241 무회귀(래퍼 경유). spec/quality 리뷰 진행 중.
- T2 완료 (커밋 대기): pre-bash-dispatch.ps1 디스패처 — 3함수 순차 호출, block 우선 exit 2·warn 병합. 스모크 6케이스(push 경고·클린·merge-abort·커밋메시지·rtc 차단/통과) 개별 hook과 동일. 전수 동등성은 T4 골든.

## Next Steps
- plan 승인 후 `pjc:implement-task`를 이 경로로 호출
- 완료 후: v1.99.0 push·릴리즈(part1+T6 합류) 별도 승인 → part2 실행

## Open Questions
- (없음 — 결정 B 사용자 확정, 나머지 자체 확정)
