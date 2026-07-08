# Plan: 하니스 품질 검토 후속 — part2: 스킬·에이전트 지침 결함 수정 (v1.100.0)

<!-- 버전 메모: 초안은 1.98.0→1.99.0였으나, T6 이관분이 1.99.0을 사용해 part2는 1.99.0→1.100.0으로 순증(minor). -->


**이전 plan**: docs/plans/2026-07-08-harness-quality-part1.md

## 요구 이해
- **원문 요청**: "하니스에서 품질 하락을 발생 할 수 있는 부분 / 너무 많은 제한으로 llm이 최상의 성능을 못 내는 부분 검토" → "모두 수정" (Q1~Q9 추천안 확정).
- **이해한 요구**: 검토에서 확정된 스킬·에이전트 지침 결함 — 검증 계약 결함(HEAD_SHA), 규칙 유실(auto-compact 재읽기), 조작 유발 규정(가설 2개 강제·표현 검출), 과잉 절차(매 task 전체 테스트·전수 Read·질문 의무), 검증 구멍(prefilter 키워드 PASS) — 을 지침 계약 수준에서 수정한다. llm-wiki는 경량 완화만(본체 분리는 별도 plan).
- **포함하지 않는 것으로 이해**: 스킬 구조 개편(파일 분할·통합)이나 모델 라우팅의 전면 변경(explorer는 effort만 상향, haiku 유지)은 하지 않는다.

## Goal
implement-task 자율 루프의 검증 게이트가 결정적으로 동작하고(빈 diff 리뷰·규칙 유실 제거), 리뷰·계획 지침이 "형식 채우기"가 아닌 "근거 검증"을 요구하며, 과잉 절차 5건이 비례 원칙을 갖게 만든다.
**전체 목표**: 하니스 품질 검토에서 확정된 결함 전체를 hook(part1)·스킬/에이전트(part2)에서 수정해, 안전망이 스스로 품질을 깎는 5개 구조 패턴을 해소한다.

## Out of Scope
- explorer 모델 상향(haiku→sonnet) — 비용 급증, effort 상향으로 충분한지 먼저 관찰.
- plan-feature Trivial Bypass 기준 자체의 확대 — 기존 "3갈래(명백 trivial/명백 대형/애매=A·B 질문)" 규정이 이미 있어, 이번은 애매 케이스 예시 보강만.
- 검토에서 "잘 설계됨"으로 확인된 장치들(Retry Ledger 영속화·confidence 문턱 자체·REMOVED FR 제외 등)의 변경.

## Deferred / Follow-up
- llm-wiki 본체에서 절차 K(+5-1·5-2) 초경량 분리 — 별도 plan (Q9 확정. check_consistency 93항목·라우팅 표·wiki-schema 연쇄)
- explorer 위임 품질 관찰 후 필요 시 모델 상향 재검토
- 재설치(install.ps1) — 릴리즈 후

## Investigation Log
- 메인이 직접 grep/Read로 확인한 근거 (하위 에이전트 검토 결과의 재검증):
  - `implement-task/SKILL.md:301` — V-5가 `BASE_SHA, HEAD_SHA` 전달·리뷰어는 `git diff <BASE_SHA> <HEAD_SHA>`(spec-compliance-reviewer.md:25) 실행. 그러나 실변경 커밋은 Phase D(:385 양식)가 처음이고 Phase I는 `--allow-empty` checkpoint(:211)뿐 → Phase V 시점 HEAD는 빈 커밋(계약 결함).
  - `implement-task/SKILL.md:143`(컨텍스트 관리 규칙) — 압축 감지 시 재읽기 목록에 plan.md·AGENTS.md만, SKILL.md 자신 부재.
  - `implement-task/SKILL.md:229·258` — "실패 시 Phase I로 1회 복귀 후 재시도" vs halt-conditions.md "빌드/테스트 5회 연속 실패 Halt" — 2회차 실패 시 행동 미규정.
  - `implement-task/SKILL.md:385·393` + `final-report-template.md` — 커밋·보고에 `Elapsed`·`Turn ~<N>`(모델이 알 수 없는 수치) 기록 강제.
  - `implement-task/SKILL.md:242` — "Task Type 미명시 → D로 간주". :53 "3회 반복 확인된 코드만 공통화"(글로벌 2회와 불일치). :210 브랜치 규약(task별/plan별) 모호. :192 "결과를 모두 Read로 확인"(P-3, 비례 원칙 부재).
  - `spec-prefilter.md:39` — "acceptance 관련 변경 있는가? (키워드 일치)", :56 "리터럴 값 … grep 생략 가능", :68 출력 `PASS | ESCALATE`만(turn 소진 규정 부재).
  - `spec-compliance-reviewer.md:112-113` — 테스트 없으면 MAJOR/BLOCKER (테스트 인프라 없는 프로젝트 예외 부재 — 글로벌 "무단 추가 금지"와 충돌).
  - `plan-reviewer.md:250` — "cross-file 검증은 grep 1-2회로 제한" vs 항목 3(Impact Coverage 전 심볼 대조) 물리적 불가. :260 "confidence 50-79 → MINOR로 강등"(BLOCKER 후보 예외 없음). :179-185 빈 Halt Forecast MAJOR.
  - `explorer.md:6-7` — `model: haiku`+`effort: low`, :58 "의심되면 작게 답하고", :31 "빌드·테스트만"(read-only 선언과 모순).
  - `plan-feature/SKILL.md:64`(절대 규칙 1 "산출물은 plan.md 하나" — Step 0.5 PRD·Step 1/10 큐 기록과 모순), :67·400("아마도" 금지+0회 검출), :76("빠짐없이 모두" 질문), :179(Step 2.5 "현재 값" 열), :233("1–4시간"), :111(Step 0.2 4중 분기 단문).
  - `pjc-systematic-debugging/SKILL.md:129`("최소 2개 이상의 가설")·:239("가설이 1개뿐" → STOP)·:173(RED 선작성 — 빌드 실패 예외 부재)·:255("영문 디버깅 로그→한글 로그").
  - `llm-wiki/SKILL.md:8·44` — 절차 K가 본체 수록·plan-feature Step 1에서 자동 호출(본체 전체 로드). K 5-2가 상시 감시 의무(:109-129 하위 규칙 다수). `procedures-content.md` B-1 0(타 프로젝트 [DECISION] 전 소비)·B-1a(망라 재대조 필수)·`procedures-ops.md` F-0(lint 전 큐 소비) — 하위 에이전트 정독 확인.
  - 기타: `record-project-fact/SKILL.md:65`(hook 수락 후 재문답), `bootstrap-agents-md/SKILL.md:69`(비재귀 `Get-ChildItem -Filter` vs :78 csproj는 `-Recurse` — 불일치), `add-domain-service/SKILL.md:144-149`(IUnitOfWork 하드코딩), `add-viewmodel/SKILL.md:134`(`RowDefinitions="Auto,*"` 인라인 — WPF 미지원인데 차이 주석 누락), `AUTHORING.md:45`("약간 pushy하게").
- 정합 제약: llm-wiki 관련 파일 수정 시 `check_consistency.py` 93항목(라우팅 표·§ 정합) 통과 필수(AGENTS.md). agents/*.md 수정은 골든·consistency 무관(산문) — 검증은 문구 정합 grep + 상호 참조 확인으로.

## Risks & Unknowns
| 위험 | 영향 | 완화책 |
|---|---|---|
| 지침 산문 수정이 다른 절차 참조와 어긋남(스테일 포인터) | 규칙 상충 재발생 | task마다 "동일 개념 언급 전수 grep → 함께 갱신"을 acceptance에 포함(v1.93.0 T1 교훈 — 형제 파일 누락이 이 repo의 반복 결함 패턴) |
| pre-review checkpoint 커밋 의무화가 커밋 이력을 늘림 | 이력 소음(무해) | checkpoint는 기존 규약(빈 커밋)과 동형 — squash는 사용자 재량, plan에 명시만 |
| 완화 규정(테스트 축소·Read 재량)이 검증 약화로 읽힘 | 검증 구멍 | 각 완화에 보상 장치 명시(전체 테스트는 F-2 보장·grep -C 판정 후 의심 파일은 전체 Read) |
| llm-wiki 문구 수정이 consistency 검사 실패 | 게이트 실패 | 수정 범위를 산문(절차 본문)으로 한정, 라우팅 표·헤딩 무변경, 매 task 후 check_consistency 실행 |

## Impact Analysis
### 4-A. 심볼/타입 추적 결과 (지침 계약 — 개념 단위 추적)
| 변경 개념 | 영향 받는 파일 | 영향 종류 |
|---|---|---|
| V-5 diff 계약(HEAD_SHA) | implement-task/SKILL.md(:301·Phase I·Phase V 서두)·spec-compliance-reviewer.md(:25·:87)·code-quality-reviewer.md(동일 diff 명령)·spec-prefilter.md(:빠른 체크)·recovery.md(checkpoint 서술) | 계약 변경 — 5파일 동시 |
| 재시도 규칙("1회 복귀") | implement-task/SKILL.md(:229·:258)·references/halt-conditions.md·references/recovery.md | 단일화 |
| Elapsed/Turn 필드 | implement-task/SKILL.md(:385·:393)·references/final-report-template.md·require-evidence.ps1? (part1 T5에서 커밋 양식 파싱 없음 확인 — hook은 무관)·require-task-checkbox.ps1(제목 `T<N>:`만 봄 — 무관) | 필드 삭제 |
| 공통화 문턱(3회) | implement-task/SKILL.md(:53)·code-quality-reviewer.md(항목 D) | 정합 명시 |
| Halt Forecast 통과 기준 | plan-reviewer.md(항목 11)·plan-feature/references/edge-cases.md(6.5-B)·plan-feature/SKILL.md(통과 체크리스트) | 3파일 정합 |
| 표현 검출("아마도 0회") | plan-feature/SKILL.md(:67·:400)·plan-reviewer.md(항목 1) | 기준 교체 |
| explorer 위임 경계 | explorer.md·plan-feature/SKILL.md(Step 1 위임 품질 경계) | 정합 |
| [DECISION] 큐잉 트리거 | llm-wiki/SKILL.md(K 5-2)·plan-feature/SKILL.md(:394)·implement-task/SKILL.md(:446) | 트리거 축소 — 3파일 |
| Phase G 재루프 검증 세트 | references/phase-g-detail.md(G-2)·references/phase-f-detail.md(주석)·references/halt-conditions.md(표) | 규정 추가 |

### 4-B. 계약·직렬화 변경
- 없음 (전부 markdown 지침 — 직렬화·코드 계약 무관). 단 V-5 diff 계약은 "메인↔리뷰어 전달 계약"이라 위 표처럼 양쪽 동시 수정.

### 4-C. 테스트 파일
- `plugins/pjc/skills/llm-wiki/evals/check_consistency.py` 실행(무수정 — 통과 확인용)
- hook 골든(무관 — .ps1 무수정이나 T7 통합 검증에서 1회 재실행으로 무회귀 확인)

### 4-D. 재사용 확인
- 해당 없음 (신규 심볼 0개 — 전부 기존 지침 문구·계약 수정)

### Verified by
- grep `HEAD_SHA` → implement-task SKILL(:301·:302)·spec-compliance(:25·:87)·code-quality·spec-prefilter — 전부 위 표 포함. 잔여 hit 2건(plan-completion-reviewer.md·phase-f-detail.md)은 Phase F(전체 plan 최종 리뷰 — HEAD가 마지막 task 최종 커밋)라 per-task V-5 계약 변경과 무영향(제외 사유 명시)
- grep `Elapsed|Turn ~` → SKILL(:385·:393)·final-report-template — 포함
- grep `절차 K 5-2|\[DECISION\]` → llm-wiki SKILL·plan-feature:394·implement-task:446·wiki-schema:238·lint.py(집계 — 태그 자체는 유지라 무영향) — 포함

## Decisions
### D1. V-5 diff 계약 — pre-review checkpoint 필수화
- **Chosen**: Phase V 진입 직전 `git commit -m "checkpoint: T<N> pre-review"`(실변경 포함, --allow-empty 아님)를 필수 단계로 신설, 그 SHA를 HEAD_SHA로 전달. 리뷰어 지침에도 "HEAD_SHA 미전달·빈 diff면 즉시 incomplete 반환(임의 워킹트리 diff 금지)" 명시. Phase D 커밋은 "pre-review 이후 수정분 포함 최종화"로 재정의.
- **Rationale**: 워킹트리 diff 옵션(`git diff BASE`)보다 결정적(리뷰 대상 스냅숏 고정·재현 가능). recovery의 reset 지점도 명확해짐.
- **Source**: 검토 발견 #2 — 자체 확정(계약 결함 수정, 유일하게 결정적인 방향).

### D2. Elapsed/Turn — 삭제
- **Chosen**: 커밋 양식·최종 보고에서 두 필드 삭제 (모델이 알 수 없는 수치 — 환각 통계 영구 기록 방지).
- **Source**: 자체 확정(검증 불가 수치 기록은 저장소 자체 규율과 모순).

### D3. 공통화 문턱 — 3회 유지 + 근거 명시
- **Chosen**: 스킬 3회 유지(지침 우선순위상 스킬이 글로벌 2회보다 우선), SKILL에 "글로벌 2회의 스킬별 강화"임을 주석, code-quality-reviewer 항목 D에 동일 기준 명시.
- **Source**: 글로벌 CLAUDE.md 우선순위 규정 — 자체 확정.

### D4. 표현 검출 → 근거 매칭 중심
- **Chosen**: "아마도/보통 0회"는 **작성 지침**으로 유지하되, plan-reviewer 판정 기준을 "표현 단어 검출"에서 "핵심 주장 ↔ Investigation Log 근거 매칭(근거 없는 단정 = BLOCKER)"으로 교체. "확인 필요" 잔존은 BLOCKER 유지하되 "Open Questions로 옮겨 해소" 경로를 명시(은폐 대신 해소 유도).
- **Source**: 검토 발견(은폐 유도) — 자체 확정.

### D5. explorer — effort 상향 + 문구 교체, 모델 유지
- **Chosen**: `effort: low → medium`, "의심되면 작게 답하고" → "질문에 완결적으로 답하되 코드 덤프 금지", Bash 허용에서 빌드·테스트 실행 제외(조회형 git만). plan-feature Step 1에 "explorer 결과는 후보 위치 — Investigation Log 등재 전 메인이 확인 Read" 명시.
- **Source**: Q(자체 확정 목록으로 사전 고지, 이견 없음). 모델 상향은 Deferred.

### D6. 매 task 전체 테스트 (Q7)
- **Chosen**: V-2에 조건부 축소 — AGENTS.md에 영향 범위 필터 명령이 있거나 스위트가 큰 경우(>3분) task 영향 모듈만, 전체는 F-2에서 1회 보장. 축소 시 커밋 Tests: 줄에 범위 명시.
- **Source**: 사용자 승인(Q7 A).

### D7. llm-wiki — 경량 완화만 (Q9)
- **Chosen**: ① K 5-2 트리거를 "plan 승인 시점 1회 일괄 + implement-task 종료 시 신규분 1회"로 축소(상시 감시 의무 삭제 — plan-feature:394·implement-task:446은 이미 그 두 시점이라 문구 정합만) ② B-1 0: 타 프로젝트 [DECISION]은 잔량 보고 후 사용자 동의 시 소비 ③ B-1a에 생략 조건(허브 `updated` 14일 이내이고 변경 파일 ≤5개면 갱신 대상 기능만 대조) ④ F-0: 잔량 보고까지만, 소비는 F-2 승인에 합류. 본체 분리는 Deferred.
- **Source**: 사용자 승인(Q9 A).

### D8. 디버깅 스킬 경량 경로
- **Chosen**: ① 원인 자명(컴파일러/스택트레이스가 파일·라인·원인 특정 + 수정이 단일 파일 소규모) 시 Phase 1-A(재현 확인)+Phase 4(수정·검증)로 축약 가능 — 축약 사용 시 보고에 "경량 경로" 명시 ② 증거가 단일 원인을 확정하면 가설 1개+확정 근거로 Phase 2 통과 ③ 4-A RED 예외에 "빌드/컴파일 실패(테스트 실행 불가)" 명시 ④ 4-D: 단일 파일·10줄 이하+회귀 테스트 GREEN이면 spec-prefilter 경량 검증 허용 ⑤ 로그 언어는 "프로젝트 기존 로그 관례 우선, 관례 없으면 한글".
- **Source**: 자체 확정 목록 사전 고지(가설 조작·RED 불능은 규칙이 스스로 모순).

### D9. 버전
- **Chosen**: part2 완료 시 1.99.0 → **1.100.0** (minor — 절차 계약 변경 다수. T6가 1.99.0 사용해 순증).
- **Source**: 저장소 관례 — 자체 확정.

## Tasks

- [x] T1. implement-task — V-5 diff 계약·재읽기·반박 채널·재시도 단일화 (D1)
  - **Type**: D
  - **Acceptance**: ① Phase V 서두에 pre-review checkpoint 커밋 단계 신설 + V-5 전달문·Phase I·Phase D 서술 정합(“checkpoint(빈 커밋)→구현→pre-review 커밋(실변경)→리뷰→수정분은 Phase D에서 최종화” 흐름이 한 번에 읽힘) ② 컨텍스트 관리 규칙의 압축 후 재읽기 목록에 "이 SKILL.md + 진행 중 Phase의 reference 파일" 추가 ③ V-5/V-6 결과 처리에 이의 절차 1개 신설 — "지적이 사실 오류임을 파일:라인 인용으로 반증 가능하면 코드 수정 없이 반증 첨부 재호출 1회, 재차 동일 지적이면 Halt(사용자 판단)" + antipatterns.md "묵살 금지"와 상충하지 않게 그 항목에 예외 각주 ④ "1회 복귀" 문구 2곳을 "실패 시 Phase I 복귀 반복 — 한도는 recovery.md 카운터"로 교체 ⑤ grep 검증: `HEAD_SHA`·`1회 복귀` 전 출현 위치가 새 계약과 정합
  - **Files**:
    - 주: `plugins/pjc/skills/implement-task/SKILL.md`
    - 동반: `plugins/pjc/skills/implement-task/references/recovery.md`·`references/halt-conditions.md`·`references/antipatterns.md`
  - **Edge Cases**: 재개 세션이 pre-review 커밋 직후에서 이어질 때(Retry Ledger·Phase Ledger로 위치 식별 — 서술 1줄), Type A(리뷰 생략)는 pre-review 커밋 불필요 명시
  - **Halt Forecast**:
    - (i) checkpoint 이중화로 recovery reset 지점 혼동 → recovery.md에 "reset 대상은 직전 checkpoint(start)·pre-review 중 명시된 쪽" 규정 추가로 해소
  - **Depends on**: -

- [x] T2. implement-task — 과잉 절차 완화·모호 규정 정리 (D2·D3·D6)
  - **Type**: D
  - **Acceptance**: ① V-2 조건부 축소(D6 문구 — 전체는 F-2 보장·축소 시 Tests: 줄 범위 명시) ② P-3/V-7 읽기 비례 원칙: "hit 30건 초과 시 grep -C 문맥으로 영향 판정, 영향 의심 파일만 전체 Read(판정 근거 로그 남김)" — 위임 금지 가드는 유지 ③ 커밋 양식·final-report에서 Elapsed/Turn 삭제 ④ "Task Type 미명시 → D" 앞에 "메인이 diff 예상 규모로 B/C/D 1줄 판정해 plan에 기입(판정 불가 시 D)" 추가 ⑤ 브랜치 규약 "plan당 1개(첫 task에서 생성, 이후 동일 브랜치)" 명시 ⑥ 공통화 3회에 글로벌 관계 주석 ⑦ phase-g-detail G-2 재루프 task 완료 최소 세트 "G-1 재대조 + F-2 전체 테스트 1회(F-7 Opus만 면제)" + halt-conditions 표에 "Phase G Should 갭 — 조건부 보고" 행 추가 ⑧ grep 검증: `Elapsed|Turn ~` 잔존 0
  - **Files**:
    - 주: `plugins/pjc/skills/implement-task/SKILL.md`
    - 동반: `references/final-report-template.md`·`references/phase-g-detail.md`·`references/phase-f-detail.md`·`references/halt-conditions.md`
  - **Edge Cases**: AGENTS.md에 test 명령 자체가 없는 프로젝트(기존 V-2 fallback 유지 — 이번 완화와 간섭 없음 확인)
  - **Halt Forecast**: (없음 — 전부 사전 결정 완료된 문구 계약 수정. 파괴적·외부 요소 없음)
  - **Depends on**: T1 (같은 파일 — 순차 수정으로 충돌 방지)

- [x] T3. reviewer agents 4종 — 검증 구멍·예산·강등 규칙 (D4·D5)
  - **Type**: D
  - **Acceptance**: ⓪ spec-compliance·code-quality의 diff 실행 서술에 "HEAD_SHA 미전달·빈 diff면 즉시 incomplete 반환(임의 워킹트리 diff 금지)" 절 추가(D1 리뷰어측 가드) ① spec-prefilter: 체크 1을 "acceptance의 구체 값·조건을 diff 실값과 대조(키워드 존재만으로 PASS 금지)"로, 체크 4의 리터럴 값은 "grep 생략 가능하되 값 대조는 필수", "turn 소진·판정 미완 → 무조건 ESCALATE" 1줄 추가 ② spec-compliance H항목에 예외 — "프로젝트에 테스트 인프라가 없거나 plan이 테스트 제외를 명시하면 MAJOR/BLOCKER 대신 MINOR+사유" ③ plan-reviewer: grep 상한을 "변경 심볼당 1회(상한 심볼 10개, 초과분은 미검증 명시)"로, confidence 강등 규칙에 "BLOCKER 후보(호출자 누락·acceptance 미충족급)는 강등 금지 — 심각도 유지+확인 요청 표시", 항목 11을 "없음+판단 근거 1줄이면 Type 무관 통과"로, 항목 1 판정 기준을 D4(근거 매칭)로, 검토 항목에 우선순위(3·9 필수 완주, 미검토 항목 결과에 명시) ④ explorer: effort medium·문구 교체·빌드/테스트 제외(D5) ⑤ 상호 참조 grep: implement-task V-5의 prefilter 서술·plan-feature Step 9 서술과 어긋남 0
  - **Files**:
    - 주: `plugins/pjc/agents/spec-prefilter.md`·`plugins/pjc/agents/spec-compliance-reviewer.md`·`plugins/pjc/agents/plan-reviewer.md`·`plugins/pjc/agents/explorer.md`
    - 동반: `plugins/pjc/agents/code-quality-reviewer.md`(공통화 D항목 정합 — D3)
  - **Edge Cases**: 값 대조가 불가한 acceptance(정성 기준 — "존재 확인으로 대체" 명시), 심볼 0개 plan(항목 3 skip 기존 유지)
  - **Halt Forecast**: (없음 — 문구 계약 수정)
  - **Depends on**: T1 (V-5 계약 확정 후 리뷰어 diff 명령 서술 정합)

- [x] T4. plan-feature — 규칙 모순·과잉 정리 (D4)
  - **Type**: D
  - **Acceptance**: ① 절대 규칙 1을 "코드 파일을 작성·수정하지 않는다. 계획 산출물은 plan.md(+해당 시 PRD)·규약이 정한 큐 기록"으로 정정 ② 절대 규칙 2·Step 4에 읽기 비례 원칙(T2 ②와 동일 문구 — hit 30+ 시 축약 경로, Halt 조건 "단순 grep 카운트만" 판정과 정합) ③ 절대 규칙 4에 "코드·AGENTS.md 근거로 결정 가능한 항목은 Decisions에 Source와 함께 자체 확정 — 질문은 근거로 결정 불가한 항목만" + "구현 도중 결정 분기 0"의 대상을 "외부 관찰 가능 계약(API·스키마·UX·의존성)"으로 한정(내부 세부는 컨벤션 위임 허용) ④ Step 1 explorer 결과 취급(D5 문구) ⑤ Step 2.5 표에서 "현재 값·일치" 열 제거(디자인 값+확인 방법까지만 — 현재 값 대조는 V-9로 이관, plan-template 예시 동기) ⑥ Step 0.2 PRD 완료 판정을 "마커 상태→행동" 표로 치환 ⑦ Step 5 "1–4시간"을 "독립 검증 가능 + 주 파일 5개 이내" 구조 기준으로 ⑧ Step 9에 "Type A/B만으로 구성된 plan은 메인 자체 체크리스트 검토로 대체 가능" 예외 ⑨ 통과 체크리스트 "아마도/보통 0회"를 "근거 없는 단정 0(주장↔Investigation Log 매칭)"으로 교체 ⑩ 상호 참조 grep: plan-reviewer(T3)·edge-cases·plan-template·implement-task V-9와 어긋남 0
  - **Files**:
    - 주: `plugins/pjc/skills/plan-feature/SKILL.md`
    - 동반: `references/plan-template.md`(시각 표 예시·Halt Forecast 주석)·`references/edge-cases.md`(6.5-B "없음+근거 1줄" 정합)·`plugins/pjc/skills/implement-task/SKILL.md`(V-9가 "현재 값" 열을 표에서 기대하지 않게 — 표 존재+디자인 값 기준 대조로)
  - **Edge Cases**: 기존에 작성된 plan(현재 값 열 있는 시각 표)을 재개하는 세션 — V-9는 "열이 있으면 사용, 없으면 디자인 값 기준" 양쪽 수용 문구
  - **Halt Forecast**: (없음)
  - **Depends on**: T3 (plan-reviewer 기준 확정 후 체크리스트 정합)

- [x] T5. pjc-systematic-debugging — 경량 경로·가설·RED 예외 (D8)
  - **Type**: C
  - **Acceptance**: D8의 ①~⑤가 각각 해당 절(Phase 개요·Phase 2 통과 조건·즉시 STOP 조건·4-A·4-D·안티패턴 표)에 반영되고, description near-miss에 "원인 자명한 단순 오류(컴파일러가 위치·원인 특정)는 경량 경로 / 비버그 'fix'(포매팅 등)는 비대상" 경계 추가. 축약·완화 문구가 "근본 원인 조사 의무" 원칙 서술과 모순되지 않게 예외 조건이 명시적(grep으로 상충 표현 0 확인).
  - **Files**:
    - 주: `plugins/pjc/skills/pjc-systematic-debugging/SKILL.md`
  - **Edge Cases**: 원인 자명으로 시작했다가 수정이 커지는 경우 — "경량 경로 중 다중 파일·원인 불일치 발견 시 표준 경로로 승격" 1줄
  - **Halt Forecast**: (없음)
  - **Depends on**: -

- [x] T6. llm-wiki 경량 완화 + 기타 스킬 5건 (D7)
  - **Type**: C (quality-review)
  - **Acceptance**: ① llm-wiki: D7 ①~④ 반영(K 5-2 트리거 문구·B-1 0 동의 게이트·B-1a 생략 조건·F-0 시점) + `check_consistency.py` 93항목 exit 0 + plan-feature:394·implement-task:446 문구와 정합(grep) ② record-project-fact: "hook 제안과 변경안이 동일하면 수락을 Step 3 승인으로 간주(변경안 제시는 유지, 재문답 생략)" ③ bootstrap-agents-md: 표식 검색에 `-Recurse -Depth 3` (csproj 검사와 방식 통일) ④ add-domain-service: IUnitOfWork 줄에 조건 주석("UnitOfWork 패턴이 있을 때만 — 없으면 기존 영속화 컨벤션"), Halt를 "영속화 수반 Application Service인데 트랜잭션 경계 미명시"로 한정, description near-miss에 "레이어 분리 없는 단일 프로젝트·스크립트는 비대상" ⑤ add-viewmodel: WPF 차이 주석에 "RowDefinitions 축약·Grid Padding 불가 — `<Grid.RowDefinitions>` 전개+Margin", Halt의 ServiceLocator를 "제3자 라이브러리/전역 정적 컨테이너 남용"으로 구체화(App.GetService 관례 허용 명시) ⑥ AUTHORING: "pushy는 저빈도·전문 어휘에 한정 — 일상 고빈도 단어(fix/에러/추가)는 단독 트리거 금지, 맥락 조건과 결합"
  - **Files**:
    - 주: `plugins/pjc/skills/llm-wiki/SKILL.md`·`references/procedures-content.md`·`references/procedures-ops.md`
    - 동반: `plugins/pjc/skills/record-project-fact/SKILL.md`·`plugins/pjc/skills/bootstrap-agents-md/SKILL.md`·`plugins/pjc/skills/add-domain-service/SKILL.md`·`plugins/pjc/skills/add-viewmodel/SKILL.md`·`plugins/pjc/skills/AUTHORING.md`·`plugins/pjc/skills/plan-feature/SKILL.md`(:394 큐잉 문구 — 이미 정합해 무변경)·`plugins/pjc/skills/implement-task/SKILL.md`(:446 문구 — 이미 정합해 무변경)·`plugins/pjc/skills/llm-wiki/references/wiki-schema.md`(§2.8·§7-25 소비 서술 — Edge Cases 인가)·`plugins/pjc/skills/llm-wiki/scripts/lint.py`(INFO 문구 — F-0 소비 흐름 Cross-File 정합)
  - **Edge Cases**: llm-wiki 라우팅 표·절차 헤딩은 무변경(산문만 — consistency 파싱 앵커 보존), wiki-schema:238의 수집·소비 서술과 어긋나면 그 줄도 동기
  - **Halt Forecast**:
    - (i) consistency 검사 실패 → 산문 한정 수정 원칙 + 매 파일 수정 후 즉시 재실행으로 원인 국소화
  - **Depends on**: T4 (plan-feature 문구 확정 후 큐잉 정합)

- [ ] T7. 버전·문서·통합 검증 (D9)
  - **Type**: C
  - **Acceptance**: ① plugin.json·README 1.99.0→1.100.0 ② README의 검토자·워크플로 서술이 변경 반영(리뷰 이의 절차·테스트 축소 조건 등 사용자 노출 변경만) ③ 통합 재검증: check_consistency 93항목 OK·hook 골든 전 케이스 PASS(무회귀 확인)·JSON 3종 OK·BOM 규약(md 무BOM) ④ notes.md 기록 ⑤ 검토 보고의 40개 발견 ↔ part1/part2 task 역대조 표를 notes에 포함(누락·의도적 제외 구분)
  - **Files**:
    - 주: `plugins/pjc/.claude-plugin/plugin.json`·`README.md`·`notes.md`
  - **Edge Cases**: part1·T6가 먼저 릴리즈되지 않은 상태로 part2가 끝나는 경우 — 버전은 로컬 순증(1.99.0→1.100.0), 릴리즈는 최종 보고에서 일괄 승인(part1 1.98.0 + T6 1.99.0 + part2 1.100.0 합류)
  - **Halt Forecast**: (없음)
  - **Depends on**: T1~T6

## 사전 승인 항목 (일괄 승인 대상)
- T1~T4 — 절차 계약 변경(V-5 diff 계약·리뷰 이의 절차·검증 축소 조건·리뷰어 판정 기준): 스킬 워크플로 규정의 계획된 변경 — Q7·자체 확정 목록 사전 고지로 승인 범위 포함
- T6 — llm-wiki 절차 트리거 축소(Q9 A 승인)
- 각 task 완료 시 로컬 작업 브랜치 commit (implement-task 규약 위임 범위)

## 불가피한 Halt (위임 불가 — 일괄 사전승인 불가)
- push·main 병합·태그·GitHub 릴리즈 v1.100.0 — 최종 보고에서 별도 승인

## Verification Strategy
- 정적: 전 ps1 parse(무변경 확인용)·JSON 매니페스트 3종
- llm-wiki 정합: `python plugins/pjc/skills/llm-wiki/evals/check_consistency.py` (T6 및 최종)
- hook 골든: 최종 1회(무회귀 확인 — .ps1 무수정)
- 산문 정합: 각 task acceptance의 상호 참조 grep(스테일 포인터 0)
- 역대조: 검토 발견 목록 ↔ 반영 task 전수 대조 표 (T7)

## Phase Ledger
- T6까지 완료. Phase F/G 미도달 (전 task 완료 후 진입 — T7 후 Phase F).

## Retry Ledger
- (해당 없음 — checkpoint 복구·재루프 없음)

## Progress Log
- T1: implement-task pre-review 커밋 계약·압축 재읽기·지적 이의 절차·재시도 단일화. Phase D를 ①리뷰수정판정→②체크박스→③분기커밋(clean=amend/dirty=새커밋)으로 재배치. spec OK, quality OK(M1 MAJOR+2 MINOR 수정 후). 커밋 579219e.
- T2: V-2 조건부 축소(D6)·P-3/V-7 읽기 비례 원칙·Elapsed·Turn 삭제(D2)·Type 판정 문구·브랜치 규약(plan당 1개)·공통화 3회 글로벌 주석(D3)·G-2 재루프 최소세트(F-2 전체테스트 유지, F-7만 면제)·halt-conditions "Phase G Should 갭" 행. spec OK, quality OK(M1·M2 MAJOR 수정 후).
- T3: reviewer 4종 — spec-compliance·code-quality diff 가드(HEAD_SHA 미전달·빈 diff→incomplete, D1 리뷰어측)·spec-prefilter 값 대조/turn-exhaust ESCALATE·spec-compliance H 테스트 인프라 예외·plan-reviewer(grep 상한 10심볼·BLOCKER 강등 예외·항목1 D4 근거매칭·항목11 근거통과·항목 우선순위 3·9)·explorer effort medium+빌드/테스트 제외(D5)·code-quality D 공통화 3회(D3). spec OK, quality MINOR 2(서식) 수정.
- T4: plan-feature — 절대규칙 1(코드 미수정+PRD·큐 허용)·규칙2 읽기 비례·규칙4 자체확정/계약 한정(D4)·Step1 explorer 후보 취급(D5)·Step2.5 시각표 현재값·일치 열 제거·Step0.2 PRD 완료 판정 표·Step5 구조 기준(파일 5개)·Step9 Type A/B 자체검토 예외·통과 체크리스트 근거매칭. 동반 plan-template·edge-cases·implement-task V-9 정합. spec OK, quality OK.
- T5: pjc-systematic-debugging — 경량 경로(원인 자명 시 1-A+Phase4 축약)·Phase2 단일 원인 확정 예외·4-A RED 예외(빌드/컴파일 실패)·4-D 경량 검증(단일 파일 10줄+회귀 GREEN→prefilter)·로그 언어 관례 우선(D8) + description near-miss + STOP 조건 정합. Iron Law 모순 0. spec OK(Type C, V-6 생략).
- T6: llm-wiki K 5-2 트리거 2배치 축소·B-1 0 타프로젝트 [DECISION] 동의 게이트·B-1a 14일/5파일 축소·F-0 보고만+F-2 소비 합류(D7) + record-project-fact hook 수락 간소화·bootstrap -Recurse -Depth 3·add-domain-service IUnitOfWork 조건·add-viewmodel WPF/ServiceLocator·AUTHORING pushy 완화. B1(wiki-schema stale) 수정 위해 wiki-schema §2.8/§7-25·lint.py INFO 문구 Cross-File 정합(Files 확장). check_consistency 94항목·lint 골든 21/21 무회귀. spec OK, quality OK.

## Next Steps
- T7(버전·문서·통합 검증)부터 이어 진행. T7 후 Phase F(PRD 없음 → Phase G 미해당) → 최종 보고(릴리즈는 별도 승인).
- part1 완료 후 이 plan을 `pjc:implement-task`로 실행

## Open Questions
- (없음 — 사용자 확정 완료, 2026-07-08)
