# Plan: 하니스 품질 검토 후속 — part1: hook 스크립트·안전망 오탐/과잉제한 수정 (v1.98.0)

**다음 plan**: docs/plans/2026-07-08-harness-quality-part2.md

## 요구 이해
- **원문 요청**: "하니스에서 품질 하락을 발생 할 수 있는 부분이 있는지 검토 / 너무 많은 제한으로 llm이 최상의 성능을 제대로 하지 못 하는 부분이 있는지 검토" → 검토 보고 후 "모두 수정" (Q1~Q9 전부 추천안 확정).
- **이해한 요구**: 4개 영역 병렬 검토에서 확정된 발견 사항(hook 오탐·컨텍스트 오염·검증 계약 결함·과잉 절차) 전부를 수정한다. part1은 hook 스크립트·hooks.json(결정적 검증 가능 영역), part2는 스킬·에이전트 지침. 안전 차단은 약화하지 않고 오탐만 제거하며, 모든 hook 변경은 골든 회귀로 실증한다.
- **포함하지 않는 것으로 이해**: llm-wiki 본체 32KB의 구조 분리(별도 plan — Q9 확정), require-plan `docs/plans/` 존재만으로 영구 통과하는 문제의 "살아있는 plan" 판정 강화(게이트 강화는 이번 목적(과잉제한 완화)과 반대 방향 — Out of Scope).

## Goal
Bash/Write 도구 호출을 막거나 오염시키던 hook 오탐·반복 경고·프로세스 낭비를 제거하되, 위험 차단(홈/시스템 삭제·DB 파괴·시크릿)은 골든 케이스로 유지가 실증된 상태로 만든다.
**전체 목표**: 하니스 품질 검토에서 확정된 결함 전체(약 40건)를 hook(part1)·스킬/에이전트(part2)에서 수정해, 안전망이 스스로 품질을 깎는 5개 구조 패턴을 해소한다.

## Out of Scope
- require-plan-for-write의 `docs/plans/` 디렉터리 존재만으로 영구 통과하는 판정의 강화(mtime·미완료 체크박스) — 게이트 강화는 별도 논의.
- chown/attrib/icacls 차단 완화 — 이번은 chmod만 정밀화(빈도·필요성이 확인된 것만, Q4).
- block-destructive의 `rm -rf *`(cwd 글롭) 차단 해제 — 약화 방향이라 유지. find 상대경로 `-delete` 비대칭은 아래 D6 참조(문서화로 종결).

## Deferred / Follow-up
- **다음 분할 plan**: docs/plans/2026-07-08-harness-quality-part2.md — T1~T7 (스킬·에이전트 지침 수정, 미실행)
- **hook 검사 로직 in-process 통합(T6 이관)**: 4개 Bash-계열 hook(block-destructive·warn-external-ops·require-task-checkbox·warn-commit-secrets) 검사 로직을 함수 모듈로 리팩토링해 단일 pwsh 프로세스에서 dot-source 실행 → 도구 호출당 pwsh 콜드 스타트 4회를 1회로. 안전 임계 스크립트 구조 변경이므로 동등성 골든을 촘촘히 깐 별도 plan에서 진행(자식 spawn 방식은 성능·안전 모두 불리하므로 채택 안 함).
- block-destructive 기존 한계(T1 재리뷰에서 확인, 이번 diff 이전부터 존재): `cat <<EOF > script.sh`(데이터 싱크로 스트립) 후 같은 Bash 호출에서 `bash script.sh` 즉시 실행 시 위험 본문이 스캔에서 빠짐 — "파일 작성 + 동일 호출 실행" 조합 감지 개선 후보
- suggest-agents-record가 커밋 메시지(-m 값) 속 명령 문자열을 실행으로 오인(세션 중 실측) — -m 값 스트립 적용 후보
- .state 디듑 마커(post-write-warn·require-plan-warn·suggest-agents-record) 누적 정리 정책 부재(TTL/청소) — 공통 이슈, 별도 plan (T4 리뷰 m1)
- llm-wiki 본체에서 절차 K 초경량 분리 (Q9 — check_consistency 93항목·라우팅 표 연쇄라 별도 plan)
- 재설치(install.ps1) — 릴리즈 후 설치 캐시 갱신 전까지 설치본은 구 동작(기존 이월과 동일)

## Investigation Log
- 검토는 하위 에이전트 4개(hook/plan-feature/implement-task/기타 스킬) 병렬 정독으로 수행, 이후 메인이 발견 사항의 실행 근거를 직접 grep/Read로 재확인:
  - `block-destructive.ps1:66` — `$dangerTarget`에 `\$env:\S*`(깊이 무제한). 같은 정규식 안에서 `~`/`$HOME`/`C:\Users`는 깊이 cap 적용(주석 :55-65가 v1.90.3 수정 경위 명시) — `$env:`만 비대칭임을 직접 확인.
  - `block-destructive.ps1:97-104` — 열거 파이프 사전검사: `$beforePipe -match $dangerTarget`에 단독 `.`/`./` 토큰이 매치, `$delRecurseForce`는 `$cmd` 전체 스캔(:103) → `Get-ChildItem . -Recurse -Filter *.tmp | Remove-Item -Force`·`find . -name "*.pyc" | xargs rm -f` 오차단. :76 주석("find .은 제외")과 자기모순 확인.
  - `block-destructive.ps1:158` — `'^\s*(sudo\s+)?chmod\s'` 전면 차단. :143-144 `migrate\s+reset`/`db\s+reset` 무조건 차단, 등가 `--force-reset` 패턴 부재(:115-149 전수 확인). :127 `DROP\s+TABLE`은 데이터 스트립이 heredoc/Set-Content 미포함이라 SQL 파일 "작성"도 차단.
  - `secret-patterns.ps1:23` — password 정규식이 `os.getenv(...)`·`password: string` 값 형태도 매치(값 제외 조건 없음). :31-40 — IP 예외가 `[regex]::Match`(첫 매치)만 검사 후 `continue`로 패턴 전체 skip(양방향 결함), 사설대역 미구분.
  - `require-plan-for-write.ps1:118` — trivial 판정이 `tool_name -eq 'Edit' -or 'MultiEdit'`(Write 새 파일 제외). :30-54 allowedExts에 .xml/.html/.css 부재(:68 파일명 3종만 예외). :314-326 차단 메시지가 QUICK env var를 직접 안내. G4/H3 경고 디듑 부재(형제 suggest-agents-record는 세션 마커 사용).
  - `post-write-checks.ps1:185` — impact-warn diff 기준이 `git diff HEAD`(누적) → 커밋 전까지 편집마다 동일 경고 재주입. :116 영문 주석 판정 `^\s*(//|#)`가 C# 전처리 지시문 포함. :36-45 hook 소스 편집 경고에 dev repo 구분 없음.
  - `require-task-checkbox.ps1:41-42` — "첫 매치가 곧 제목" 가정을 주석으로 확인(제목 중간 `(T3: ...)` 언급에 깨짐).
  - `warn-external-ops.ps1:32-46` — `-m` 값 스트립 부재, :33 `merge\b`가 `--abort`도 매치, :70 dry-run 예외가 git push 한정.
  - `require-evidence.ps1` — traceRx가 표준 빌드 명령만(스크립트 빌드 미포함), 미커밋 경고가 세션 성격 무관 발동(하위 에이전트 정독 확인).
  - `hooks.json:4-70` — Bash|PowerShell PreToolUse 4항목이 각각 별도 `powershell` 프로세스 기동(+`Get-Command pwsh` 프로브) 확인.
- 선례·제약: `AGENTS.md` DO NOT "block-destructive·protect-harness 차단 동작 변경 금지" → Q3~Q5로 사용자 예외 승인 확정. `notes.md` 2026-07-05(v1.90.3)에서 `~`/`$HOME` 깊이 cap이 동일 계열 오탐 수정으로 승인·수행된 선례 확인. 골든 러너 185케이스(`run-hook-evals.ps1`)·validate.ps1이 검증 수단(AGENTS.md Build & Test).
- 기존 plan.md(v1.97.2)는 전 task `[x]`·커밋 완료, Deferred 3건은 notes.md 2026-07-08/v1.97.0 항목에 이미 보존됨을 확인 → 유실 없이 교체 가능.

## Risks & Unknowns
| 위험 | 영향 | 완화책 |
|---|---|---|
| 차단 완화가 실제 위험 명령을 통과시킴 | 안전망 약화(치명) | 변경마다 "위험 유지" 골든 케이스 선작성 — 기존 차단 케이스 전부 PASS 유지 + 신규 통과 케이스는 수정 전 러너에서 FAIL 실증(음성 대조) |
| T6 디스패처 통합의 stdin/exit code 전달 결함 | 4개 안전망 동시 무력화 | 개별 스크립트 무수정(배선만 변경), 디스패처 동등성 골든(차단 exit 2 전파·경고 stderr 병합·클린 exit 0) 신설, 실패 시 hooks.json 원복만으로 롤백 가능 |
| 경고 디듑 마커(.state)가 세션 간 오염 | 경고 누락 | suggest-agents-record의 기존 세션 마커 방식 재사용(검증된 패턴), 마커 키에 session_id 포함 |
| protect-harness가 hook 소스 편집을 경고 | 작업 소음(무해) | dev repo 편집은 비차단 — 정상 진행(이번 T4에서 문구 자체도 중립화) |

## Impact Analysis
### 4-A. 심볼/타입 추적 결과
| 심볼/파일 | 영향 받는 파일 | 영향 종류 |
|---|---|---|
| `$dangerTarget`·사전검사 2종·`$patterns`·데이터 스트립 (block-destructive.ps1) | 같은 파일 내 컴파운드 검사(:290)와 공유 — 외부 참조 없음 | 정규식 수정 |
| `Get-SecretMatches` (secret-patterns.ps1) | `post-write-checks.ps1`(dot-source)·`warn-commit-secrets.ps1`(dot-source) — 호출부 2곳, 함수 시그니처 불변(내부 정밀화만) | 동작 정밀화 |
| `$harnessHookName` (post-write/protect-harness 동일 유지 alternation) | 무변경 (이름 집합 불변) | — |
| hooks.json PreToolUse Bash 4항목 | `run-hook-evals.ps1`(개별 스크립트 직접 호출 — 배선 무관), `validate.ps1`(hooks.json 등록 검사 — T6에서 갱신 필요) | 배선 변경 |
| 각 hook 스크립트 | `run-hook-evals.ps1` 케이스·`hook-cases.json` | 골든 갱신 |

### 4-B. 계약·직렬화 변경
- hook stdin JSON 계약 불변. T6 디스패처는 stdin을 1회 캡처해 각 스크립트에 재공급(캡처 방식은 기존 스크립트의 `[Console]::In` 읽기와 호환되는 파이프 전달) — 개별 스크립트의 입출력 계약 무변경.

### 4-C. 테스트 파일
- `plugins/pjc/hooks/evals/run-hook-evals.ps1` + `hook-cases.json` (T1~T6 각각 케이스 추가/갱신)

### 4-D. 재사용 확인
| 신규 심볼 | 유사 기존 구현 검색 결과 | 재사용/신규 사유 |
|---|---|---|
| `pre-bash-dispatch.ps1` (T6) | 기존 스크립트 중 다중 hook 호출 없음 (post-write-checks가 "2프로세스→1 통합" 선례 — 주석 확인) | 신규 — 4스크립트 배선 통합 전용, 검사 로직은 기존 스크립트 재사용(무수정 호출) |
| 세션 경고 마커 (T3·T4) | `suggest-agents-record.ps1`의 `.state` 세션 마커 | 기존 방식 재사용(신규 심볼 아님 — 동일 패턴 이식) |

### Verified by
- grep `secret-patterns` → dot-source 2곳(post-write-checks·warn-commit-secrets) + validate.ps1 $knownHelpers + protect-harness 이름 집합, 모두 위 표 반영
- grep `dangerTarget|delRecurseForce|findDangerRoot` → block-destructive.ps1 내부 전용 확인

## Decisions
### D1. 작업 구성 (Q1·Q2)
- **Chosen**: 2개 plan 분할(part1 hook / part2 스킬), PRD 생략(검토 발견 목록이 명세 역할).
- **Source**: 사용자 확정 (2026-07-08).

### D2. block-destructive 오탐 수정 4건 + AGENTS.md DO NOT 예외 (Q3)
- **Chosen**: ① `$env:` 깊이 cap(홈과 동일 규칙 — 루트·직속 전체글롭만 위험, 하위 경로 통과) ② 열거 파이프 사전검사에서 단독 `.`/`./` 제외 + `$delRecurseForce`를 파이프 뒤(삭제측) 세그먼트에만 적용 ③ 데이터 스트립에 파일 리다이렉트 heredoc(`<<EOF … > file`)·`Set-Content/Add-Content -Value` 추가 ④ 컴파운드 삭제 별칭 매치에서 직전 토큰 `git` 제외(`git rm`은 git 추적으로 복구 가능).
- **Rationale**: 오탐 제거는 차단 약화가 아님 — v1.90.3 `~`/`$HOME` cap과 동일 계열. ③은 heredoc이 **파일로 리다이렉트될 때만** 스트립(DB 클라이언트로 파이프되는 `psql <<EOF`류는 실행이므로 스트립 금지).
- **Source**: 사용자 승인(Q3 A — DO NOT 예외 포함).

### D3. chmod 조건부 차단 (Q4)
- **Chosen**: 차단 조건을 ① 재귀(`-R`) ② 위험 모드(777·666·u+s/g+s) ③ 대상이 시스템/위험 루트(`$dangerTarget` 재사용)로 한정. 프로젝트 내 단일 파일 `+x`는 통과. chown/attrib/icacls는 현행 유지.
- **Source**: 사용자 승인(Q4 A).

### D4. migrate/db reset — 차단 유지 + 등가 강화 (Q5)
- **Chosen**: `migrate reset`·`db reset` 차단 유지, 등가 파괴 명령 `db push … --force-reset`(prisma)·`--force-reset` 계열을 차단 패턴에 **추가**.
- **Source**: 사용자 승인(Q5 A — 약화 없이 대칭 강화).

### D5. require-plan 신규 파일 trivial + 확장자 (Q6)
- **Chosen**: Write(신규 파일)도 ① 내용 30줄 이하 ② 경로가 `tests/`·`__tests__/`·`spec/`·`test/` 하위이거나 파일명이 `repro*`·`scratch*`·`tmp*` 이면 통과. `.xml`·`.html`·`.htm`·`.css`·`.scss`를 허용 확장자에 추가.
- **Rationale**: 재현 스크립트·테스트 신규 작성이 "plan 급조"로 우회되는 것보다 조건부 허용이 안전. 마크업·스타일은 오차단 비용 > 게이트 가치.
- **Source**: 사용자 승인(Q6 A).

### D6. rm/find 비대칭 — 문서화로 종결
- **Chosen**: `find . -mindepth 1 -delete`(상대경로) 차단 추가는 하지 않음(정당한 로컬 정리 오탐이 더 큼). 대신 block-destructive 주석의 "알려진 미탐" 목록에 이 비대칭을 명시(감사 가능성 확보).
- **Rationale**: 양방향 모두 비용이 있는 트레이드오프 — 차단 확대는 오탐(이번 작업의 반대 방향), 해제는 약화. 현상 유지 + 문서화가 최소 침습.

### D2-보완. 열거 파이프 — delRecurseForce의 afterPipe 한정은 미적용 (구현 중 결정)
- **Chosen**: D2 ②의 "delRecurseForce를 파이프 뒤 세그먼트에만 적용"은 구현하지 않음. 단독 `.`/`./` 토큰 제외로 acceptance의 오탐이 해소되고, afterPipe 한정은 `Get-ChildItem C:\ -Recurse | Remove-Item`(강제 플래그 없는 삭제측) 차단을 잃는 **약화**임을 구현 중 확인.
- **Rationale**: 더 안전한 쪽 선택. 골든 음성 대조로 실증.
- **리뷰 B2 보강**: 무조건 `.` 제외는 무필터 전체 삭제(`Get-ChildItem . -Recurse | Remove-Item -Force` = `rm -rf ./*` 등가)까지 통과시키는 약화임이 code-quality 리뷰에서 실행 대조로 실증됨 → `.` 제외를 **이름 필터(-Filter/-Include/-Exclude/-name/-iname) 있는 선택적 열거로 한정**(-type f는 비선택 — 전 파일 삭제). 무필터 차단 유지 골든 2건 추가.
- **리뷰 B1 보강**: heredoc 스트립의 `>` 존재 판정이 `bash <<EOF > log.txt`(실행자 + stdout 리다이렉트) 우회를 만들던 것 → 스트립을 데이터-싱크(cat+`>`, tee) 허용목록으로 한정. 차단 유지·tee 통과 골든 2건 추가.

### D7. 경고 디듑 방식
- **Chosen**: suggest-agents-record의 `.state` 세션 마커 패턴 재사용. G4/H3(require-plan)·impact-warn 심볼·영문 주석·hook 소스 경고에 "세션당 1회(또는 파일·심볼당 1회)" 적용.
- **Source**: 코드 선례(suggest-agents-record.ps1) — 자체 확정.

### D8. hooks.json 디스패처 (Q8)
- **Chosen**: Bash|PowerShell PreToolUse 4종(block-destructive→warn-external-ops→require-task-checkbox→warn-commit-secrets 순서 유지 — 차단이 경고보다 먼저)을 `pre-bash-dispatch.ps1` 1항목으로 통합. 개별 스크립트는 무수정, 디스패처가 stdin 캡처 후 순차 호출·exit 2 즉시 전파·stderr/컨텍스트 병합. Write 계열 2종·PostToolUse·Stop은 현행 유지.
- **Source**: 사용자 승인(Q8 A). post-write-checks 통합 선례(주석).

### D9. 버전
- **Chosen**: part1 완료 시 1.97.2 → **1.98.0** (minor — hook 동작 규칙 다수 변경, 하위호환).
- **Source**: 저장소 버전 관례(notes.md 선례) — 자체 확정.

## Tasks

- [x] T1. block-destructive 오탐 수정 + 정책 반영 (D2·D3·D4·D6)
  - **Type**: D
  - **Acceptance**: Given 골든 러너, When 실행, Then ① 통과 신설: `Remove-Item -Recurse -Force $env:TEMP\claude\x\scratchpad`·`rm -r $env:TEMP/claude/x`·`Get-ChildItem . -Recurse -Filter *.tmp | Remove-Item -Force`·`find . -name "*.pyc" | xargs rm -f`·`chmod +x build.sh`·`git rm -r .`(캐시드 해제 형태)·`cat <<EOF > m.sql`+`DROP TABLE old;` 파일 작성 ② 차단 유지: `rm -rf $env:TEMP`·`Remove-Item $env:USERPROFILE -Recurse -Force`·`Get-ChildItem C:\ -Recurse | Remove-Item -Force`·`ls / | xargs rm -rf`·`chmod -R 777 /etc`·`chmod u+s ./x`·`prisma migrate reset`·`prisma db push --force-reset`(신규)·`psql <<EOF`+`DROP TABLE` 실행형 ③ 기존 차단 케이스 전부 PASS ④ 신규 통과 케이스는 수정 전 러너에서 차단(FAIL) 실증(음성 대조) ⑤ parse OK
  - **Files**:
    - 주: `plugins/pjc/scripts/block-destructive.ps1`
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1` 또는 `hook-cases.json` (케이스 ~16건)
  - **Edge Cases**: 인용부호 감싼 경로(`"$env:TEMP"`), `$env:` 뒤 변수명만(`$env:TEMP` 루트 — 차단 유지), heredoc 여러 개 혼재, 대소문자(`CHMOD`), `git -C x rm`
  - **Halt Forecast**:
    - (i) 정규식 수정이 기존 케이스를 깨뜨림 → 골든 185케이스가 즉시 검출, 케이스 단위로 원인 특정 가능
    - (ii-a) AGENTS.md DO NOT 예외에 따른 차단 동작 변경 → `## 사전 승인 항목` 등록(Q3~Q5 승인 완료)
  - **비고(리뷰 MINOR m1 등록)**: 4개 의미 변경(D2·D3·D4·D6)을 한 task로 묶음 — 골든 케이스 단위 격리로 수용, 특정 변경이 반복 실패하면 그 변경만 분리해 진행
  - **Depends on**: -

- [x] T2. secret-patterns 오탐 정밀화 (password 값 제외 조건·IP 전체 순회)
  - **Type**: C
  - **Acceptance**: Given `Get-SecretMatches`, When 스캔, Then ① 미경고: `password: string`(타입 선언)·`pwd = os.getcwd()`·`password = os.getenv('DB_PASSWORD')`·`process.env.PASSWORD`·`password = None/null/true` ② 경고 유지: 평문 값(`password = "hunter2"`·`pwd: s3cret!`) ③ IP: 첫 매치가 127.0.0.1이어도 뒤따르는 비예외 IP 검출(전체 매치 순회), 사설대역(10./192.168./172.16-31.)은 `IP 주소(사설)` 라벨로 구분 ④ post-write·warn-commit-secrets 골든의 기존 양성/음성 케이스 전부 PASS + 신규 케이스 추가 ⑤ parse OK
  - **Files**:
    - 주: `plugins/pjc/scripts/secret-patterns.ps1`
    - 동반: `plugins/pjc/scripts/warn-commit-secrets.ps1`·`plugins/pjc/scripts/post-write-checks.ps1` (라벨 문구 소비부 확인 — 변경 필요 시만)
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1`
  - **Edge Cases**: `password=os.environ["X"]`(대괄호), `Password=` DB 연결문자열(별도 패턴 — 간섭 금지), 값이 3자 미만, 한 내용에 예외 IP+실 IP 혼재
  - **Halt Forecast**:
    - (i) 제외 조건이 실 시크릿을 놓침 → 양성 케이스(평문 값) 골든 유지로 검출
  - **Depends on**: -

- [x] T3. require-plan-for-write — 신규 파일 trivial·확장자 추가·경고 디듑·QUICK 문구 (D5·D7)
  - **Type**: C
  - **Acceptance**: Given plan 없는 repo, When Write, Then ① `tests/repro_bug.py`(20줄) 통과, `src/service.py`(20줄 신규) 차단 유지, 31줄 `tests/` 파일 차단 ② `.xml`/`.html`/`.css` Write/Edit 통과 ③ Given 완료 plan(전부 `[x]`), When 소스 Edit 3회, Then G4 경고는 세션당 1회만 additionalContext 주입(2·3회차 무경고) ④ 차단 메시지의 QUICK 안내에 "사용자만 설정 가능 — Claude가 Bash로 설정해도 hook에 전파되지 않음" 명시 ⑤ 골든 기존+신규 PASS·parse OK
  - **Files**:
    - 주: `plugins/pjc/scripts/require-plan-for-write.ps1`
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1`
  - **Edge Cases**: Write인데 기존 파일 덮어쓰기(신규 아님 — 기존 trivial 경로), 경로 구분자 혼용(`tests\repro.py`), 마커 파일 없는 첫 실행, `$env:CLAUDE_SESSION_ID` 부재 시 폴백
  - **Halt Forecast**:
    - (i) 신규 허용 경로가 소스 코드 게이트를 실질 무력화 → 30줄+디렉터리/네이밍 이중 조건으로 한정, 차단 유지 케이스 골든 명시
  - **Depends on**: -

- [x] T4. post-write-checks — impact-warn 상한·stop-list·디듑, 영문 주석 정밀화, hook 소스 경고 중립화 (D7)
  - **Type**: C
  - **Acceptance**: Given 흔한 식별자(`Name` 등) 포함 클래스 편집, When PostToolUse, Then ① 심볼별 repo 매치 30건 초과 시 caller 나열 대신 "흔한 이름 — 생략" 1줄 ② stop-list(`Name|Type|Data|Text|Value|Id|Key|Item|Count|Get|Set` 등 단독 식별자) 제외 ③ 같은 파일·같은 심볼 경고는 세션당 1회(HEAD 누적 diff로 인한 반복 주입 제거) ④ `.cs`의 `#region`/`#if`/`#pragma` 등 전처리 지시문은 영문 주석 집계 제외 + 영문 주석 경고 파일당 세션 1회 ⑤ hook 소스 편집 경고 문구를 개발/설치본 중립("검증 리마인더")으로 + 세션당 1회 ⑥ 골든 기존+신규 PASS·parse OK
  - **Files**:
    - 주: `plugins/pjc/scripts/post-write-checks.ps1`
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1`
  - **Edge Cases**: 심볼 0개 파일, stop-list 심볼만 있는 diff(경고 자체 생략), 마커 누적으로 .state 비대(세션 키 교체 시 정리), 비-cs 파일의 `#` 주석(파이썬 — 전처리 제외는 .cs만)
  - **Halt Forecast**:
    - (i) 디듑이 서로 다른 심볼의 경고까지 삼킴 → 마커 키를 파일+심볼 단위로 (acceptance ③이 검증)
  - **Depends on**: -

- [x] T5. warn-external-ops·require-evidence·require-task-checkbox 정밀화
  - **Type**: C
  - **Acceptance**: ① warn-external-ops: `git commit -m "다음: git push 후 릴리즈"` 무경고(-m 값 스트립), `git merge --abort|--continue|--quit` 무경고, `npm publish --dry-run`·`dotnet nuget push … --dry-run`? 등 배포 계열 dry-run 무경고 — 실 push/merge/publish 경고 유지 ② require-task-checkbox: `git commit -m "문서: 릴리즈 노트 (T3: 반영)"`은 판정 제외(제목 첫 줄이 `^T\d+:`로 시작할 때만 게이트), `git commit -m "T3: 구현"` 게이트 유지 ③ require-evidence: traceRx에 스크립트 빌드(`./build.ps1`·`build.sh`·`python … build`·`tsc`·`make`·`gradle`·`mvn`) 추가, 미커밋 경고는 transcript에 Write/Edit 사용 흔적이 있을 때만 ④ 골든 기존+신규 PASS·parse OK
  - **Files**:
    - 주: `plugins/pjc/scripts/warn-external-ops.ps1`·`plugins/pjc/scripts/require-task-checkbox.ps1`·`plugins/pjc/scripts/require-evidence.ps1`
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1`
  - **Edge Cases**: `-m` 여러 개·`--message=` 형태, 멀티라인 커밋 메시지 첫 줄 판정, `git merge`(인자 없음 — 경고 유지), transcript 파일 부재(fail-open)
  - **Halt Forecast**:
    - (i) -m 스트립이 플래그 토큰까지 지움 → block-destructive의 검증된 스트립 기법 재사용(값만 제거·토큰 보존)
  - **Depends on**: -

- [~] T6. hooks.json Bash 계열 PreToolUse 4종 단일 디스패처 통합 (D8) — **스킵(별도 plan으로 이관)**
  - **스킵 사유(구현 착수 중 발견, 사용자 확인)**: 4개 스크립트가 전부 `[Console]::In.ReadToEnd()`로 stdin을 소비하고 `exit 2`로 종료하므로, "무수정" 제약에서 통합하려면 디스패처가 각 스크립트를 자식 프로세스로 재spawn해야 한다(in-process 격리 불가). 그 결과 ① 성능 목표 역행 — 무거운 비용인 pwsh 콜드 스타트 4회가 그대로 남고 디스패처 1개가 추가됨(4→5), 절감되는 건 셸 래퍼·pwsh 프로브뿐 ② 안전 저하 — 마지막 방어선(block-destructive) 앞에 단일 장애점(디스패처 crash→4게이트 fail-open) 신설. 진짜 이득(pwsh 4→1)은 4스크립트 로직을 함수 모듈로 리팩토링해 in-process dot-source하는 별도 설계로만 가능하며, 안전 임계 스크립트 구조 변경이라 이번 오탐 배치와 분리한다.
  - **Type**: D
  - **Acceptance**: Given Bash 도구 호출 1회, When PreToolUse, Then ① PowerShell 프로세스 1개만 기동(디스패처) ② 위험 명령은 exit 2 즉시 전파(후속 스크립트 미실행 — block-destructive 우선 순서 유지) ③ 경고 hook들의 stderr/컨텍스트 출력이 병합 전달 ④ 클린 명령 exit 0 ⑤ 개별 스크립트 무수정(파일 해시 대조) ⑥ 골든: 기존 4 hook의 대표 차단/경고/클린 케이스를 디스패처 경유로 재실행하는 동등성 케이스 신설 + 기존 개별 케이스 전부 PASS ⑦ validate.ps1이 새 배선(hooks.json 1항목 + 디스패처 등록)을 정상 인식
  - **Files**:
    - 주: `plugins/pjc/scripts/pre-bash-dispatch.ps1` (신규)
    - 동반: `plugins/pjc/hooks/hooks.json`·`validate.ps1`·`plugins/pjc/scripts/protect-harness.ps1`+`post-write-checks.ps1`($harnessHookName 집합에 `pre-bash-dispatch` 추가 — v1.97.2 규약 "hook 신설 시 함께 추가")
    - 테스트: `plugins/pjc/hooks/evals/run-hook-evals.ps1`
  - **Edge Cases**: stdin이 빈 경우, 스크립트 하나가 parse 실패(fail-open — 나머지 계속), pwsh/powershell 폴백 경로, timeout 예산(4스크립트 합산이 10s 내 — 프로세스 기동 3회 제거로 오히려 단축)
  - **Halt Forecast**:
    - (i) stdin 재공급 방식이 일부 스크립트의 읽기 방식과 불일치 → 구현 전 각 스크립트의 stdin 읽기 방식(`[Console]::In`/`$input`) grep 확인을 task 첫 단계로 명시, 불일치 시 파이프 전달로 통일
    - (ii-b) 통합 후 골든 동등성 실패가 반복되어 설계 자체 재검토 필요 시 → hooks.json 원복 후 사용자 보고(무리한 강행 금지)
  - **Depends on**: T1·T5 (개별 스크립트 수정 확정 후 배선 통합 — 순서 역전 시 골든 이중 갱신)

- [x] T7. 버전·문서·통합 검증 (D9)
  - **Type**: C
  - **Acceptance**: ① plugin.json·README 버전 1.97.2→1.98.0 ② README 안전장치·트러블슈팅 서술이 변경 반영(chmod 조건화·신규 파일 trivial·디스패처) ③ AGENTS.md DO NOT에 "오탐 수정은 골든 실증 하에 허용(2026-07-08 승인)" 단서 + scripts 목록에 pre-bash-dispatch 추가 ④ 통합 재검증: 전 ps1 parse OK·JSON 매니페스트 3종 OK·hook 골든 전 케이스 PASS ⑤ notes.md 기록
  - **Files**:
    - 주: `plugins/pjc/.claude-plugin/plugin.json`·`README.md`·`AGENTS.md`·`notes.md`
  - **Edge Cases**: README 버전 배너 이중 표기(과거 누락 전례 — 배너·본문 모두 확인)
  - **Halt Forecast**: (없음 — 문서·버전. 판단 근거: 동작 변경 없고 전 항목이 T1~T6 결과의 기계적 반영)
  - **Depends on**: T1~T6

## 사전 승인 항목 (일괄 승인 대상)
- T1 — block-destructive 차단 동작 변경(오탐 4건 수정·chmod 조건화·reset 등가 추가): AGENTS.md DO NOT 예외 — Q3·Q4·Q5로 사용자 승인 완료, 골든으로 위험 차단 유지 실증
- T3 — require-plan-for-write 게이트 완화(신규 파일 조건부 허용·확장자 추가): Q6 승인 완료
- T6 — 구조 변경(hooks.json 배선 4→1, 신규 스크립트 추가): Q8 승인 완료
- T7 — AGENTS.md DO NOT 문구 갱신(승인 이력 반영)
- 각 task 완료 시 로컬 작업 브랜치 commit (implement-task 규약 위임 범위)

## 불가피한 Halt (위임 불가 — 일괄 사전승인 불가)
- push·main 병합·태그·GitHub 릴리즈 v1.98.0 — 최종 보고에서 별도 승인
- T6 (ii-b): 디스패처 동등성 검증 반복 실패 시 원복 후 사용자 판단

## Verification Strategy
- 빌드: 전 ps1 PSParser parse (AGENTS.md Build 명령)
- 테스트: JSON 매니페스트 3종 + hook 골든 `pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/pjc/hooks/evals/run-hook-evals.ps1` (T1~T6 각 완료 시 + 최종 통합 1회)
- 음성 대조: 신규 "통과" 케이스는 수정 전 코드에서 차단됨을 실증(가드가 실제 변경을 검증함을 확인)
- 통합(재설치 후): `pwsh ./validate.ps1` — 릴리즈·재설치 후 별도

## Phase Ledger

## Retry Ledger
- T1: quality BLOCKER 2건(B1 heredoc 실행자 우회·B2 무필터 열거 삭제) → 수정 2dc1a56, 재리뷰 OK (수정 사이클 1/5, 종결)
- T5: spec MAJOR 1건(require-evidence 골든 누락) → 수정 a319783 / quality BLOCKER 2건(B1 dry-run·B2 merge 세그먼트 누수) → 수정 dfa89b6, 재검증 진행 중 (수정 사이클 2/5)

## Progress Log
- T1 완료 (커밋 fbc6835 + 수정 2dc1a56): block-destructive 오탐 4건+chmod 조건화+reset 등가. 리뷰 B1(heredoc 데이터-싱크 한정)·B2(. 제외 필터 조건화) 반영. 골든 212/212, 음성 대조 9건 OLD=2→NEW=0. spec OK.
- T2 완료 (커밋 82d1845): secret-patterns password lookahead 제외·IP 전체 순회·사설 라벨. 골든 4케이스. spec OK.
- T3 완료 (커밋 407b3da): require-plan 신규 파일 trivial(30줄+tests/repro)·xml/html/css 허용·G4/H3 세션 디듑·QUICK 문구. 골든 9케이스, 221/221. spec OK.
  - 결정: 디듑 마커는 suggest-agents-record와 동일한 $env:USERPROFILE/.claude/.state 방식(러너 격리 홈이 실행마다 재생성돼 골든 간섭 없음 확인).
- T1 재리뷰 OK (실행 대조로 B1·B2 해소 확인 — old 미탐 재현·HEAD 차단). T4 완료 (커밋 대기): impact 매치 상한 30·stop-list(Name/Type 등)·세션 심볼당 디듑·영문주석 .cs //만·hook 소스 경고 중립화+1회. 골든 7케이스, 225/225.

## Next Steps
- plan 승인 후 `pjc:implement-task`를 이 파일 경로로 호출
- part1 완료 후: 남은 분할 plan: docs/plans/2026-07-08-harness-quality-part2.md — pjc:implement-task로 별도 실행

## Open Questions
- (없음 — Q1~Q9 사용자 확정 완료, 2026-07-08)
