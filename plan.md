# plan.md — plan.md 분할 메커니즘 연결 장치 빈틈 보강 (감사 ④)

## Goal
긴 plan을 2개로 분할했을 때 "둘째 plan 실행을 잊지 않게 하고(상기), 두 plan을 서로 식별·연결하며(포인터), task 번호 충돌을 없애고(재번호), 절반 구현을 거짓 BLOCKER로 오판하지 않게(통합 검증)" 만드는 연결 장치를 추가한다. 현재 분할 권고는 plan-feature/SKILL.md 3줄뿐이고 연결 장치가 전무하다.

## 배경 — 감사 결과 ④ (split-mechanism-audit 메모리)
하니스의 파일 분할 메커니즘 4개 중 PRD는 1.66.1에서 보강 완료. 이번은 **④ plan.md 분할**(MAJOR·우선 1). 라인 번호는 plan 시작 시 재확인 완료(아래 Investigation Log).

4개 Gap(메모리):
- **Gap1**: 둘째 plan 실행 상기 장치 없음.
- **Gap3**: 현재 plan 식별 포인터 부재(PRD `**PRD**:` 줄 대응물 없음) + 덮어쓰기 모드에서 둘째 plan 저장 위치 미정의.
- **Gap4**: 분할 본문 `T(M+1)~` 표기 vs implement-task 루프 "첫 실행은 T1" 전제 모순.
- **Gap5**: Phase F·plan-completion-reviewer가 단일 plan 범위만 검증 → 분할 plan Goal 작성법 미정의로 "절반 구현 = BLOCKER 거짓 판정" 위험.

## Investigation Log (라인 재확인 — grep/Read 직접 확인)
- `plan-feature/SKILL.md:271~285` — "긴 plan 분할 권고" 본문. L280 `B) 2개 plan으로 분할 (T1-<M>, T<M+1>-<N>)`, L284 "각 plan은 독립 실행 가능하도록".
- `plan-feature/SKILL.md:311~318` — Step 7 위치 결정 표(작은=plan.md 덮어쓰기 / 큰=docs/plans 누적).
- `implement-task/SKILL.md:139` — `loop ... 첫 실행은 T1, 재개면 지정/첫 미완료 task` (Gap4 유일 충돌 지점). argument-hint(L4)·L157·L161은 이미 "임의 시작 task / 첫 미완료부터"를 지원 → 모순은 약함.
- `implement-task/SKILL.md:507~539` — 최종 보고(Phase F 통과 후) 양식. L535 Follow-ups, L538 "다음 단계 안내".
- `plan-completion-reviewer.md:40~50` — "1. Goal 충족 (BLOCKER 후보)". Goal 미달성을 BLOCKER로 판정하는 지점(Gap5 핵심).
- `plan-template.md` — `**PRD**:` 줄(L30~32), `## Goal`(L34~35), `## Deferred / Follow-up`(L47~50), `## Next Steps`(L118~123).
- 빈도: 분할은 task 8개 초과 + 사용자가 B 선택 시에만 발생하는 드문 경로 → 최소·단순 장치로 보강(pjc "과한 추상화 금지").

## 결정 (사용자 확정)
- **Gap4 = 각 plan T1부터 재번호.** 분할 둘째 plan도 자기 안에서 T1~. 각 plan 자기완결·독립 실행. implement-task L139 "첫 실행 T1" 전제 **무수정**(분할 plan도 T1으로 시작하므로 정합). 분할 권고문의 `T<M+1>-<N>` 표기를 "둘째 plan은 T1부터 다시 번호"로 수정.
- **Gap3 = docs/plans/ 누적 + 상호 포인터 + 시작 part 식별.** 분할하면(덮어쓰기 모드여도) `docs/plans/<YYYY-MM-DD>-<slug>-part1.md` / `-part2.md` 누적 위치 강제(AGENTS.md `Plan Location: plan.md` override — 분할은 복수 파일이라 덮어쓰기 불가). 첫 plan 상단 `**다음 plan**:`, 둘째 상단 `**이전 plan**:` 상호 포인터(PRD `**PRD**:` 줄의 분할 대응물). **시작 part 식별(M1 해소)**: part1 = `**다음 plan**:` 있고 `**이전 plan**:` 없음 / part2 = 그 반대. docs/plans 복수 파일 자동 해소(인자 생략)는 모호하므로, 분할 plan은 **각 part 경로를 명시 지정해 implement-task 호출**한다(첫째=part1 경로, part1 완료 최종 보고가 part2 경로 안내 → part2 명시 호출).
- **Gap5 = Goal 범위 한정 + reviewer 분할 인지 (가벼운 안).** 분할 plan `## Goal`은 "이 plan 범위"만 쓰고 별도 `**전체 목표**:` 줄로 큰 그림 표기. plan-completion-reviewer는 분할 표식(`**이전/다음 plan**:`)이 있으면 Goal 충족을 "이 plan 범위" 기준으로 판정(전체 미완성을 BLOCKER로 안 봄), 마지막 분할 plan에서만 전체 통합 확인. **전용 통합 검증 단계는 신설하지 않음**(무거운 메커니즘 회피 — 사용자 B안 거절).
- **Gap1 = plan-template 강제 기록 + implement-task 최종 보고 안내 (이중).** 작성 시점(plan-template Deferred/Next Steps에 "다음 분할 plan" 강제) + 실행 완료 시점(implement-task 최종 보고에 "남은 분할 plan 실행" 안내) 양쪽.
- **수정 대상 4파일**: plan-template.md(규약 기준) → plan-feature/SKILL.md(권고문이 인용) → implement-task/SKILL.md(최종 보고) → plan-completion-reviewer.md(Goal 검토). 메모리의 3파일 + Gap5 "reviewer 분할 인지" 선택으로 reviewer 추가(사용자 명시 승인 범위).

## Impact Analysis (전수 확인)
- 수정 파일 **4개**, 전부 마크다운 지침 문서. 코드·시그니처·DI 영향 0.
- **상호 참조 정합(중요)**: T2 분할 권고문이 T1의 `**다음/이전 plan**:` 포인터 줄·`**전체 목표**:` Goal 작성법을 인용 → T1 먼저. T4 reviewer가 T1의 분할 표식(`**이전/다음 plan**:`)을 인용 → T1 먼저. 따라서 T1(plan-template)을 규약 기준으로 먼저 확정.
- **읽기 측 무손상**: Gap4가 T1 재번호로 결정돼 implement-task L139 루프 전제·argument-hint·재개 진입(L155~164)은 **무수정**(분할 plan도 T1~). T3는 최종 보고 양식에 안내 한 단락만 추가(루프 로직 불변). **시작 part 진입(M1)**은 루프 로직을 바꾸지 않고 "분할 plan은 경로 명시 호출" 규약(T2)으로 해소 — implement-task의 자동 plan 해소 동작 자체는 불변.
- **분할 표식 신규 도입**: `**다음 plan**:`/`**이전 plan**:` 줄은 신규 규약. 기존 `**PRD**:` 줄 규약과 충돌 없음(다른 키, 같은 상단 영역 공존). plan-template·SKILL·reviewer 3곳이 일관 인용해야 함(역대조에서 확인).
- 자동 생성·lock 파일 아님. 버전(plugin.json) 영향: 지침 문서 변경 → 버전 bump는 T5에서 판단.

## Tasks
<!-- 전부 Type A(마크다운 지침/문서). Decision Points·Edge Cases는 Type A라 skip, 상호참조 정합만 Acceptance에 명시. -->

### T1 — plan-template.md: 분할 포인터 줄 + Goal 작성법 + Deferred/Next Steps 강제 규약  [Type A]
대상: `plugins/pjc/skills/plan-feature/references/plan-template.md`
- **분할 포인터 줄 규약** (상단 `**PRD**:` 줄 영역 L30~32 근처): 분할 plan이면 첫 plan에 `**다음 plan**: <part2 경로>`, 둘째 plan에 `**이전 plan**: <part1 경로>` 줄을 둔다는 주석 + placeholder 줄 추가. 단일 plan이면 줄 생략. "plan-completion-reviewer가 이 표식으로 분할 인지" 명시. **저장 위치(M1)**: 분할 plan은 `docs/plans/<날짜>-<slug>-part1.md`/`-part2.md`에 둔다(AGENTS.md `Plan Location: plan.md`여도 분할은 복수 파일이라 docs/plans override) — 위치 결정 가이드(L3~10)에 이 예외 1줄 추가.
- **포인터 동기화 주석(m2)**: 같은 part2 경로가 상단 `**다음 plan**:`·Deferred·Next Steps 3곳에 나타나므로(식별/상기/핸드오프로 목적은 다름), "세 곳이 같은 경로를 가리킨다 — 갱신 시 함께" 동기화 주석 1줄을 상단 포인터 줄 주석에 포함.
- **Goal 작성법** (`## Goal` L34~35 주석): 분할 plan이면 `## Goal`은 "이 plan 범위"만 한 문장으로, 바로 아래 `**전체 목표**: <분할 전 전체 기능>` 줄을 둔다. reviewer가 분할 표식 있으면 Goal 충족을 "이 plan 범위" 기준으로 판정함을 명시.
- **Deferred 강제** (`## Deferred / Follow-up` L47~50 주석): 분할 첫 part면 `**다음 분할 plan**: <part2 경로> — T1~ (전체의 후반부, 미실행)`을 반드시 기록(둘째 plan 누락 방지).
- **Next Steps 라인** (`## Next Steps` L118~123 주석): 분할 첫 part 완료 시 "남은 분할 plan: <part2 경로> — pjc:implement-task로 별도 실행" 라인 포함.
- Edge cases(Type A): ⓐ 기존 템플릿 섹션 순서·개수 불변(주석/줄 추가만) ⓑ `**PRD**:` 줄 규약과 공존(충돌 없음) ⓒ 코드블록(L27~127) 내부 마크다운 구문 유지.
- Halt Forecast: 없음.
- Acceptance:
  1. 상단에 `**다음 plan**:`/`**이전 plan**:` 분할 포인터 줄 규약(주석 + 예시) 존재 + "세 곳 동기화"(m2) 주석 포함.
  2. `## Goal` 주석에 "분할 plan은 이 plan 범위 + `**전체 목표**:` 줄" 작성법 존재.
  3. `## Deferred / Follow-up` 주석에 "다음 분할 plan 강제 기록", `## Next Steps` 주석에 "남은 분할 plan 라인" 존재.
  4. 위치 결정 가이드(L3~10)에 "분할 plan은 docs/plans -part1/-part2(Plan Location override)" 예외 1줄.
  5. 기존 섹션(Out of Scope/Investigation Log/Impact/Tasks 등) 개수·순서 불변.
  6. UTF-8(BOM 없음), 코드블록·표 구문 정상.

### T2 — plan-feature/SKILL.md: 분할 권고문 보강 + Step 7 위치 표 분할 규약  [Type A]
대상: `plugins/pjc/skills/plan-feature/SKILL.md` (분할 권고 L271~285, Step 7 위치 표 L311~318)
- **분할 권고문 보강** (L275~285): B안 분할 시 규약 5개 명문화 — ① 각 분할 plan은 **T1부터 재번호**(독립 실행, 권고문 `T<M+1>-<N>` 표기 교체) ② 저장은 `docs/plans/<YYYY-MM-DD>-<slug>-part1.md`/`-part2.md` 누적(덮어쓰기 모드여도 — Plan Location override) ③ 첫 plan `**다음 plan**:`, 둘째 `**이전 plan**:` 상호 포인터(T1 규약 인용) ④ 각 plan Goal은 "이 plan 범위" + `**전체 목표**:`, 첫 plan Deferred/Next Steps에 다음 plan 기록(T1 규약 인용) ⑤ **시작 part 진입(M1)**: 분할 plan은 자동 plan 해소(인자 생략)에 의존하지 말고 **각 part 경로를 명시 지정해 `pjc:implement-task` 호출**(첫째=part1 경로, part1 완료 보고가 part2 경로 안내) — docs/plans 복수 파일 자동 해소 모호성 회피.
- **Step 7 위치 표** (L311~318): 표 아래에 "단, plan을 분할하면(긴 plan 분할 권고) 덮어쓰기 모드여도 `docs/plans/` 누적 위치를 쓴다(두 plan 충돌 방지)" 한 줄 추가.
- Edge cases(Type A): ⓐ 권고문 코드블록(L275~282) 형식 유지 ⓑ Step 5~7 다른 문장 불변 ⓒ 인용한 plan-template 규약 명칭(`**다음/이전 plan**:`, `**전체 목표**:`)이 T1 실제 문구와 일치.
- Halt Forecast: 없음.
- Acceptance:
  1. 분할 권고문에 "각 plan T1부터 재번호" 규약 + `T<M+1>-<N>` 표기 제거.
  2. 분할 권고문에 "docs/plans/ -part1/-part2 누적" 저장 규약.
  3. 분할 권고문에 상호 포인터(`**다음/이전 plan**:`) + Goal 범위 한정/Deferred 기록 안내(T1 인용).
  4. 분할 권고문에 "시작 part는 경로 명시 호출"(M1) 규칙 존재.
  5. Step 7 위치 표에 "분할 시 docs/plans 누적" 한 줄.
  6. 인용 명칭이 T1 plan-template 실제 문구와 일치. UTF-8(BOM 없음).

### T3 — implement-task/SKILL.md: 최종 보고에 남은 분할 plan 실행 안내  [Type A]
대상: `plugins/pjc/skills/implement-task/SKILL.md` (최종 보고 양식 L507~539)
- 최종 보고 양식(L535 Follow-ups~L538 영역)에 분할 안내 추가: plan.md 상단에 `**다음 plan**:` 줄이 있으면(= 이 plan이 분할 첫 part) 최종 보고에 "**남은 분할 plan**: `<다음 plan 경로>` — `pjc:implement-task`로 별도 실행 필요" 라인을 포함한다. `**이전 plan**:`만 있고 `**다음 plan**:` 없으면 마지막 part(분할 완료) 안내.
- L139 루프 전제는 **무수정 확인**(분할 plan도 T1~ 재번호라 "첫 실행 T1"과 정합) — plan에 무수정 근거 명시.
- **m3(self-contained)**: implement-task 쪽(argument-hint L4 또는 재개 진입 L155~164 근처)에 "분할 plan은 plan 경로를 명시해 호출 가능(첫째=part1, 완료 후 part2 경로)" 한 줄 추가 — implement-task 문서만 읽는 사용자도 M1의 경로 명시 호출 능력을 알게(기존 임의 경로 plan 해소 능력 위에서 성립, 신규 로직 아님).
- Edge cases(Type A): ⓐ 최종 보고 코드블록(L509~539) 구문 유지 ⓑ 분할 아닌 일반 plan은 이 라인 미출력(조건부) ⓒ Phase F/G·다른 절 불변.
- Halt Forecast: 없음.
- Acceptance:
  1. 최종 보고 양식에 "`**다음 plan**:` 있으면 남은 분할 plan 실행 안내" 조건부 라인 존재.
  2. 마지막 part(`**이전 plan**:`만) 구분 안내 존재.
  3. implement-task 쪽에 "분할 plan 경로 명시 호출 가능" 한 줄 존재(m3).
  4. L139 루프 전제·재개 진입 로직 무수정(분할 안내·m3 문구 외 루프 동작 불변 — git diff로 확인).
  5. UTF-8(BOM 없음), 코드블록 구문 정상.

### T4 — plan-completion-reviewer.md: Goal 충족 검토에 분할 plan 인지  [Type A]
대상: `plugins/pjc/agents/plan-completion-reviewer.md` ("1. Goal 충족" L40~50)
- "1. Goal 충족 (BLOCKER 후보)" 섹션에 분할 인지 단락 추가: plan.md 상단에 `**이전 plan**:` 또는 `**다음 plan**:` 표식이 있으면 이 plan은 더 큰 기능의 일부다. Goal 충족은 plan.md `## Goal`(= 이 plan 범위) 기준으로 판정하고, `**전체 목표**:` 줄의 전체 기능이 아직 미완성인 것을 **BLOCKER로 보지 않는다**(분할은 의도된 절반 구현). 단 `**다음 plan**:`이 없고 `**이전 plan**:`만 있는 **마지막 분할 plan**에서는 `**전체 목표**:`의 통합 동작까지 확인한다 — **단 이때 전체 통합은 diff(BASE..HEAD)가 아니라 전체 트리 빌드/통합 테스트로 확인한다**(m1: 마지막 part의 diff엔 앞 part 컴포넌트가 없어 diff 기반 Goal 판정은 거짓 BLOCKER를 낳는다).
- Edge cases(Type A): ⓐ 기존 체크리스트 9개 항목 번호·순서 불변(1번 안에 단락 추가) ⓑ 인용한 표식 명칭이 T1 plan-template과 일치 ⓒ `**PRD**:` 줄 인지(L21) 로직과 모순 없음(분할 + PRD 동시 가능 — 독립).
- Halt Forecast: 없음.
- Acceptance:
  1. "1. Goal 충족"에 분할 표식 인지 + "전체 미완성을 BLOCKER로 안 봄" 단락 존재.
  2. "마지막 분할 plan에서 전체 통합 확인 + 전체 트리 빌드/통합 테스트로(diff 아님)" 문장 존재(m1).
  3. 인용 표식 명칭이 T1과 일치, 체크리스트 9항목 번호 불변. UTF-8(BOM 없음).

### T5 — 버전·문서 갱신  [Type A]
- `notes.md`: 본 작업(분할 메커니즘 연결 장치 ④ 보강) 항목 추가 — 무엇·왜·어떻게·검증.
- `plugin.json`·`README.md` 버전: **patch bump 1.66.1 → 1.66.2 추천**(1.66.1 분할 PRD 귀속 보강과 동형 빈틈 보강이라 patch 일관). 사용자 승인 시 확정. README 기능 목록 변경 없음(버전 줄만).
- Acceptance: notes.md에 본 작업 항목 1건; (bump 시) plugin.json·README 버전 일치, JSON 파싱 OK.
- Halt Forecast: 버전 종류(patch/minor) 미확정 → 승인 항목에서 결정.

## Verification Strategy
1. **문구 grep**: T1~T4 각 Acceptance 문구를 grep으로 확인(분할 포인터 줄·Goal 작성법·Deferred/Next Steps·권고문 규약·Step 7 줄·최종 보고 라인·reviewer 단락).
2. **상호 참조 정합**: `**다음 plan**:`/`**이전 plan**:`/`**전체 목표**:` 명칭이 plan-template(T1)·SKILL(T2)·reviewer(T4) 3곳에서 동일 표기인지 grep 대조.
3. **읽기 측 무손상**: implement-task L139 루프 **로직**이 수정 전후 불변(분할 안내·m3 경로 명시 한 줄 외 task 시작·재개 동작 변화 없음 — git diff로 확인). m3 한 줄은 기존 임의 경로 plan 해소 능력의 문서화일 뿐 루프 동작을 바꾸지 않음.
4. **인코딩·구문**: 4개 파일 BOM 없음, 마크다운 표·코드블록 깨짐 없음.
5. **역대조 표**: Gap1/3/4/5 각 결정 + plan-reviewer 반영분(M1 시작 part 명시 호출·Plan Location override / m1 마지막 part 전체 트리 빌드 / m2 포인터 동기화 주석)이 산출물에 실제 존재하는지, 거절된 "전용 통합 검증 단계"(B안) 흔적이 없는지 대조.

## Out of Scope (이번 제외)
- **분할 plan 전용 통합 검증 단계 신설** — 사용자 B안 거절(무거운 메커니즘). Goal 범위 한정 + reviewer 인지(가벼운 안)로 대체.
- **T(M+1)~N 연속 번호 + implement-task L139 완화** — Gap4를 T1 재번호로 결정해 불필요.
- **감사 ③(위키 recipe 귀속)·②(notes 아카이브)** — 별도 plan(메모리 split-mechanism-audit, ④ 다음 순서).

## Deferred / Follow-up
- **감사 ③ 위키 recipe 귀속 빈틈** (MAJOR·우선 2), **② notes 아카이브 정합 검사** (MAJOR·우선 3) — 본 plan 완료 후 각각 별도 plan으로 진행(메모리 보존).

## 승인 필요 항목
- 본 plan(지침 문서 4파일 보강 + notes/버전) — 승인 요청.
- T5 버전 bump 종류 — **patch 1.66.2 추천**, 사용자 확정 필요.
- commit/push 및 GitHub 릴리즈 — 구현·검증 후 별도 승인.

## Progress Log
- T1 완료 (미커밋, Type A): `plan-template.md` — 분할 포인터 줄(`**다음/이전 plan**:`)+동기화 주석, Goal 작성법(`**전체 목표**:`), Deferred/Next Steps 분할 강제, 위치 가이드 docs/plans override. 코드펜스 균형·BOM 없음 확인.
- T2 완료 (미커밋, Type A): `plan-feature/SKILL.md` — 분할 권고문 5규약(T1 재번호/docs/plans 누적/상호 포인터/Goal 범위 한정/시작 part 경로 명시) + `T<M+1>-<N>` 표기 제거 + Step 7 위치 표 분할 한 줄. 인용 명칭 T1과 정합.
- T3 완료 (미커밋, Type A): `implement-task/SKILL.md` — 최종 보고 양식에 "남은 분할 plan 실행" 조건부 안내(`**다음 plan**:` 있을 때)+마지막 part 구분, 재개 진입에 "분할 plan 경로 명시 호출" 한 단락(m3). L139 루프 라인 git diff 불변 확인(무수정).
- T4 완료 (미커밋, Type A): `plan-completion-reviewer.md` — "1. Goal 충족"에 분할 인지 단락(분할 표식 있으면 Goal=이 plan 범위, 전체 미완성 BLOCKER 제외, 마지막 part는 전체 트리 빌드/통합 테스트로 — diff 아님, m1). 체크리스트 9항목 번호 불변.
- T5 완료 (미커밋, Type A): `plugin.json`·`README.md` 1.66.1 → 1.66.2, `notes.md` 본 작업 항목 추가. JSON 파싱 OK.
- **검증**: 4파일 문구 grep 전부 반영, 코드펜스 균형(plan-template 2/plan-feature 10/implement-task 18), BOM 없음, L139 루프 불변(읽기 측 무손상), 인용 명칭(`**다음/이전 plan**:`·`**전체 목표**:`) 4파일 정합. Phase F-7 plan-completion-reviewer OK(BLOCKER/MAJOR 0, MINOR 1 m1=Progress Log 지연→본 갱신으로 해소).
- **미커밋 상태**: commit/push·릴리즈는 별도 승인 대기(plan 승인 항목 3번).

## Next Steps
- 권장 다음 액션: commit/push 승인 → push 후 GitHub 릴리즈(v1.66.2, release-on-version-bump 메모리).
- Suggested skills: (커밋 후) 공식 /code-review, 공식 /security-review.

## Open Questions
- 없음 (Gap4/3/5 결정 분기 모두 사용자 확정, 버전 종류만 승인 항목으로).
