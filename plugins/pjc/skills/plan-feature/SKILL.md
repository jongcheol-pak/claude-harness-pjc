---
name: plan-feature
description: This skill should be used when the user requests code change beyond trivial edits. Triggers on Korean dev phrases ("계획", "설계", "feature 추가", "기능 추가", "리팩토링", "구현", "수정", "변경", "문제 수정", "버그 수정", "여러 곳", "전체", "만들어줘", "앱 만들어", "도구 만들어") and English equivalents ("plan", "design", "implement", "fix", "refactor", "build an app", "create a tool"). Requests to build a whole new app or product trigger the large-scale path (PRD step) inside this skill. Also triggers when the request lists multiple sub-tasks (bullets or numbered items) even without explicit keywords - a bullet list of bug fixes plus refactoring is a clear signal. Use plan-feature when the change spans multiple files, alters logic flow, changes a signature, adds a new function/class/method, refactors a resource layer (i18n/i10n, theming, DI), or has unclear cross-file impact. DO NOT trigger for clearly trivial edits - single-line UI text/label changes, icon/image swaps, color/size token tweaks of 1-2 values, README/문서 typo fixes, comment additions, single-line config edits (.editorconfig, .gitignore), single-line resource edits (strings.xml, Resources.resx for a single key), or any small code edit of 3 lines or fewer that does NOT add a new function/class/method or change a signature. For those Claude edits directly via Write/Edit and the PostToolUse impact-warn hook validates cross-file impact. For ambiguous cases (single bug fix of unclear scope, refactoring whose extent is unknown) do NOT silently force a plan - ask the user "A) edit directly / B) make a plan" and follow their pick. See SKILL body for full Trivial Bypass criteria, decision rounds with categorized question grouping, and recommended-answer format with ★.
argument-hint: "<요청 설명>"
---

# Plan Feature

코드 작성 전에 작업을 분해하고, 모든 결정 분기를 사전 해결하고, 검증 가능한 수용 기준을 정의한다.

## Trivial Bypass — 이 skill을 건너뛰는 경우

다음 케이스는 **plan-feature를 호출하지 않고** Claude가 직접 Write/Edit으로 처리한다:

| 카테고리 | 예시 |
|---|---|
| UI 문구·라벨 | "확인 버튼 라벨을 'OK'로", "메시지 문구 변경" |
| 아이콘·이미지 교체 | "이 아이콘을 SVG 파일로 교체", "PNG 새 파일로 변경" |
| 색상·치수 토큰 1-2개 | "Primary 색상을 #336699로", "padding을 16px로" |
| 문서·README 오타 | "README 오타 수정", "줄바꿈 추가" |
| 주석 추가 | "이 메서드에 한글 주석 추가" |
| 단일 라인 설정 | ".editorconfig에 한 줄 추가", "gitignore에 폴더 추가" |
| 단일 라인 리소스 | "strings.xml의 키 한 개 값 변경" |
| **작은 코드 수정** | **변수 값·조건·문자열 변경 등 3줄 이내, 새 함수/클래스/시그니처 추가 아님** |

**Trivial 판정 기준** (모두 만족):
1. 변경이 **3줄 이내, 단일 위치**
2. **새 함수/클래스/메서드 추가 없음, 시그니처 변경 없음**
3. 사용자 요청이 **명백하고 단순** (의도 모호함 없음)

위 3개를 만족하면 코드 파일(`.cs`, `.xaml`, `.ts`, `.kt`, `.py` 등)이라도 직접 수정한다.
`require-plan-for-write` hook이 작은 변경을 자동 통과시키고, cross-file 영향은 `impact-warn` hook이 사후 검출한다.

### 애매한 경우 — 자동으로 plan 강제하지 말고 사용자에게 질문

요청이 trivial인지 plan이 필요한지 **판단이 애매하면, 임의로 plan-feature를 강제하지 않는다.** 대신 사용자에게 한 번 묻는다:

```
이 작업은 간단할 수도 있고 계획이 필요할 수도 있어 보입니다.

[요청 요약: <한 줄>]
[애매한 이유: <예: 영향 범위가 불확실 / 여러 파일 가능성 / 시그니처 변경 가능성>]

A) 바로 수정 (빠르게, plan 없이)
B) 계획부터 세우기 (plan-feature — 영향 분석 + 검증)
```

- 사용자가 **A** → 직접 Write/Edit (impact-warn hook이 사후 안전망)
- 사용자가 **B** → plan-feature 정식 진행
- 명백히 trivial(위 3기준 충족)하거나 명백히 큰 작업(다중 파일·시그니처·새 정의)이면 **묻지 말고** 각각 직접 수정 / plan 진행

즉 판단은 3갈래다:

| 상황 | 행동 |
|---|---|
| 명백히 trivial (3기준 충족) | 묻지 않고 직접 수정 |
| 명백히 큰 작업 | 묻지 않고 plan-feature |
| **애매** | **사용자에게 A/B 질문** |

질문은 작업당 한 번만. 사용자가 선택하면 그대로 진행한다.

**Trivial 작업의 안전망**: `impact-warn.ps1` PostToolUse hook이 자동 caller 영향 검출.

## 자율성 모드: USER-INTERACTIVE

> **이 skill 안에서는 사용자에게 물어도 된다.** 모호한 요구사항은 명확화 질문 권장.
>
> 그러나 **`implement-task` 단계로 넘어가기 전에 모든 질문이 해결**되어야 한다.
> implement-task는 FULLY AUTONOMOUS이므로 그 안에서는 사용자에게 묻지 않는다.

```
plan-feature (이 skill)         | implement-task
USER-INTERACTIVE                | FULLY AUTONOMOUS
                                |
질문 OK (Open Questions에 모음) | 질문 금지 (Halt만 가능)
사용자 승인 1회 (게이트)         | plan = 전체 위임장
                                |
↓ 모든 질문 해결 후 ──────────→ ↓
```

## 절대 규칙 (Hard Rules)

1. **이 Skill은 코드를 작성하지 않는다.** 산출물은 `plan.md` 하나.

2. **팩트 기반 — 예측 금지, 전수 확인.**
   - 모르는 것은 "확인 필요"로 표시. "아마도", "보통은", "일반적으로" 같은 가정은 금지.
   - 모든 주장은 Read 또는 grep으로 직접 확인한 결과여야 한다.
   - 사용처는 grep으로 **전수 조사**. "샘플 몇 개 확인 후 전체가 그럴 것"이라 결론짓지 않는다.
   - 확인 방법은 Investigation Log에 기록.

3. **근본 해결.** 증상 우회는 plan의 해결책이 될 수 없다.

4. **결정 사전화 — 자율 실행 전제.**
   `implement-task`는 plan.md를 받으면 **사용자 개입 없이 모든 task를 끝까지 실행**한다.
   - 모호한 요구사항은 **빠짐없이 모두** 사용자에게 미리 묻는다 (카테고리별로 묶어서 한 번에 제시, 개수 제한 없음).
   - 각 선택지에 **Claude 추천 ★** 표기로 사용자 결정 부담 ↓.
   - 답변 후 새 모호함 발견 시 **다음 라운드에서 추가 질문 가능** (라운드 통상 3-5회).
   - **답변 시간 < 재작업 시간**. 질문이 많아 보여도 plan 완전성을 우선한다. 추측으로 코드 작성하면 그게 재작업의 원인.
   - 구현 도중 결정해야 할 분기가 **하나도 남아 있지 않아야** 한다.
   - 자기 검증: **"이 plan을 다른 사람에게 넘겨도 추가 질문 없이 끝낼 수 있는가?"**

5. **연관 파일 의무 명시 (Cross-File Awareness).**
   - 변경 대상의 모든 호출자/구현체/직렬화/테스트를 task의 Files 목록에 **모두** 명시.
   - 누락 시 plan-reviewer 또는 spec-compliance-reviewer가 차단한다.

6. **요청 범위 밖 작업 금지.** "참고 김에 정리"는 plan에 새 task로 등록 후 사용자 확인.

7. **"이번 제외"와 "영구 제외"를 구분해 기록.** 작업을 빼기로 한 경우 둘 중 어디인지 정확히 판단한다 — 잘못 적으면 다음에 할 일이 영영 누락된다:
   - 사용자가 **"이번엔 빼고 다음에 하자"** → plan.md의 `## Deferred / Follow-up`에 기록 (향후 진행 대상).
   - 사용자가 **"이 기능은 안 만든다"** → `## Out of Scope`에 기록 (영구 제외).
   - 애매하면 사용자에게 "이번만 제외인가요, 아예 제외인가요?" 확인. 기본 가정은 **Deferred**(다음에) — 영구 제외는 명시적일 때만.

7. **모든 task에 검증 가능한 acceptance.** "잘 동작한다" 같은 모호한 기준 금지.

## 실행 단계

### Step 0.5. 대규모 작업 판정 — PRD 필요 여부

다음 중 하나라도 해당하면 **대규모 작업**이다. plan.md 작성 전에 PRD를 먼저 만든다:

- 앱/제품을 새로 만드는 요청 ("메모장 앱 만들어줘", "OO 도구 만들어줘")
- 예상 task가 10개 이상인 대형 feature
- 요구사항 자체가 미정의 상태 (사용자가 "필요한 기능을 검토해서" 같은 위임 표현 사용)

**대규모가 아니면 이 단계를 건너뛰고 Step 1로** (일상 기능 추가·수정·버그는 plan.md만으로 충분).

대규모 작업 PRD 절차:
1. `references/prd-template.md` 템플릿으로 PRD 초안 작성 — 기능 요구(FR)·비기능 요구(NFR)·Out of Scope·성공 기준
2. **질문 라운드 의무 (1회 이상).** 대규모 작업은 요구 위임 자체가 모호함을 의미한다 — "모호하지 않다"고 판단해 질문을 생략하는 것 금지. Step 9와 같은 형식(카테고리 묶음 + 추천 ★)으로:
   - Claude가 자명하게 도출한 Must 후보 → 사용자 확인 요청
   - 갈림길 요구 (저장 방식, 플랫폼, 검색·다국어 여부 등) → 선택지 + 추천 ★
   - 우선순위(Must/Should/Could) 배정 → 사용자 확정
   - 질문 없이 초안만으로 승인 요청하는 것은 추측 코드와 같은 위반이다.
3. **PRD 사용자 승인 게이트** — 승인 후 PRD는 고정 (이후 임의 수정 금지, 변경은 사용자 합의 필수)
4. plan.md의 각 task는 PRD 요구 ID를 역참조 (`T3 (FR-1, FR-2 충족)`) + **plan.md 상단에 `**PRD**: <경로>` 줄 의무 기록** (implement-task의 Phase G 진입 신호)
5. PRD가 있으면 implement-task의 **Phase G (요구 재검증)** 가 활성화된다

**승인 후 기능 변경 처리 (PRD 우선 갱신)**: plan 작성·구현 중 PRD의 요구(FR/NFR)를 바꿔야 할 필요가 생기면 —
- plan이나 코드를 **먼저 바꾸지 않는다.** PRD와 어긋나면 Phase G 재검증의 기준 자체가 틀려 검증이 무의미해진다.
- 변경 필요를 **사용자에게 보고하고 PRD 갱신을 제안 → 승인**받는다 (PRD는 승인 후 고정이므로).
- 승인 시 순서: ① PRD 갱신 → ② 영향받는 plan task 조정 → ③ plan.md의 `**PRD**:` 줄 유지.
- 변경 이력을 PRD에 간단히 기록한다 (무엇을·왜 바꿨는지 한 줄).
- **금지**: 사용자 승인 없이 PRD를 임의 변경 / PRD는 그대로 둔 채 plan·코드만 어긋나게 변경. 변경은 항상 PRD → plan → 코드 순으로 위에서 아래로 흐른다.

### Step 1. 컨텍스트 수집
- `AGENTS.md` (또는 `CLAUDE.md`) 읽기
  - **없으면**: `pjc:bootstrap-agents-md` skill 자동 호출 → 사용자 승인 후 plan-feature 계속
  - 사용자가 bootstrap을 거부하면 추측 모드로 진행 (build/test 명령 모름 → 작업 중 Halt 빈번)
- 관련 모듈/파일 식별
- 기존 컨벤션, 테스트 위치, 빌드 명령 확인
- **위키 참조 (llm-wiki skill 사용 중이고 vault에 이 프로젝트가 등록돼 있으면)**: 구현할 기능과 관련된 feature/recipe/guide가 위키에 있으면 `pjc:llm-wiki`의 절차 K(read-only 조회)로 참조한다. 이미 정제된 구현 지식·과거 결정·크로스-커팅 정보를 계획에 반영하면 재조사를 줄인다. 위키는 읽기만 하고 수정하지 않는다 (위키 갱신은 별도 세션). 위키가 없거나 미등록 프로젝트면 건너뛴다.
- **대규모 탐색이 필요하면** `explorer` subagent에 위임 (메인 컨텍스트 보호)
  - **서로 독립적인 조사 질문이 여러 개면 explorer를 한 turn에 병렬 호출한다** (예: "DI 등록 위치" + "기존 테마 처리 방식" + "테스트 구조" → 3개 동시). read-only라 충돌이 없고 대기 시간만 줄어든다. Step 4(영향 범위 조사)에서도 동일 — 기능별 독립 조사는 병렬로.
  - 단, 앞 결과가 다음 질문을 결정하는 **의존 조사는 순차로** (예: "DI 컨테이너 종류 확인" → 그 결과에 따라 "해당 컨테이너의 등록 패턴 조사").

### Step 2. 범위 명확화

다음을 답할 수 없으면 사용자에게 질문:
- 영향을 주는 사용자 시나리오는?
- 명시적으로 out of scope는?
- 성공을 어떻게 측정하는가?

질문은 Step 9와 같은 형식(카테고리 묶음 + 선택지 + 추천 ★)으로 한다. 이 단계는 보통 1-3개 핵심 질문이지만, 필요하면 더 묻는다.

### Step 3. 위험 식별

- 외부 의존성 (API, OS, 드라이버, 권한)
- 동시성·상태 (멀티스레드, 비동기, 라이프사이클)
- 회귀 가능성 (기존 기능 영향)
- 알려지지 않은 영역 (가설로 명시)

### Step 4. 영향 범위 전수 조사 (Impact Analysis)

변경 대상의 모든 사용처를 **실제로 식별하고 읽어** 분석.

#### 4-A. 심볼/타입 추적
- [ ] 심볼 참조 grep — **결과를 모두 Read로 열어 확인** (요약만으로 끝내기 금지)
- [ ] 인터페이스 변경 시 — 모든 **구현체 파일** 식별
- [ ] 메서드 시그니처 변경 시 — 모든 **호출자 파일** 식별
- [ ] 타입/필드 변경 시 — 모든 **참조 위치** 식별
- [ ] DI 등록·이벤트 핸들러·옵저버 — 등록부와 사용처 모두

#### 4-B. 계약·직렬화 변경
- 시그니처, 이벤트 페이로드, 직렬화 형식 변경 → 호환성 확인
- 마이그레이션 필요 시 별도 task

#### 4-C. 영향 받는 테스트
- 변경 대상을 직접 호출하는 테스트
- 변경 대상에 간접 의존하는 통합 테스트
- 테스트가 없으면 추가 필요성 검토 (plan에 task로)

#### Halt 조건
- 사용처 추적이 단순 grep 카운트만으로 끝남 (실제 파일 Read 안 함)
- "기타 영향 있을 수 있음" 같은 모호한 표현
- 변경 대상이 인터페이스인데 구현체 식별이 누락됨

### Step 5. 작업 분해

- 각 작업은 1–4시간 단위, 독립 검증 가능
- **각 task는 `T1`, `T2`, ... 형식으로 번호를 매긴다.** "Phase 1", "단계 1", "Step 1" 등 다른 명칭으로 작업을 나누지 않는다 — implement-task의 자율 루프가 `T<N>` 형식을 전제하며, "Phase"는 pjc 내부 단계(Phase P/I/V/D·F·G)와 혼동된다. 작업을 큰 묶음으로 그룹화하고 싶으면 task 번호는 유지한 채 주석으로만 묶는다 (예: `T1~T3 (데이터 계층)`).
- 각 작업마다 acceptance criterion 1줄 명시
- 의존 관계 표시
- **각 task에 Type 분류 명시 (의무)** — implement-task가 fast-path 결정에 사용

#### Task Type 분류 (필수)

| Type | 정의 | 적용 Phase V 단계 |
|---|---|---|
| **A** (Doc/Config) | `.md`, `.json`, `.yml`, `.csproj`, `.editorconfig` 등 코드 외 파일만 | V-8 (빌드 구성 영향 시에만 V-1 추가) |
| **B** (Trivial Code) | 단일 코드 파일, 단일 메서드/필드, **호출자 변경 없음** (typo, 주석) | V-1 + V-2 + V-5(prefilter) + V-7 + V-8 |
| **C** (Normal Code) | 단일 또는 2-3개 파일, caller 갱신 있음 | V-1 ~ V-3 + V-5 + V-7 + V-8 |
| **D** (Complex/Cross-cutting) | 다중 파일, 인터페이스 변경, 시그니처 변경, 직렬화 변경, DDD/아키텍처 영향 | V-1 ~ V-8 **전체 의무** |

확실하지 않으면 **한 단계 더 무거운 쪽 선택** (안전 우선).

#### 긴 plan 분할 권고 (컨텍스트 관리)

task가 **8개를 초과**하면 사용자에게 분할을 제안한다:

```
이 plan은 <N>개 task로 큽니다. implement-task의 자율 실행 중
컨텍스트가 누적되어 후반 task의 품질이 저하될 수 있습니다.

A) 그대로 진행 (Progress Log로 일부 완화됨)
B) 2개 plan으로 분할 (T1-<M>, T<M+1>-<N>)
   → 첫 plan 완료 후 두 번째 plan 별도 실행
```

분할 시 각 plan은 독립 실행 가능하도록 task 의존성을 고려해 경계를 정한다.
사용자가 A를 택하면 그대로 진행하되, implement-task가 Progress Log를 적극 활용.

### Step 6. Decision Points 발굴

각 task에 대해 결정 분기를 사전 해결.

**Type별 적용 범위**:
- Type A: skip
- Type B: 1-2개 (해당하는 것만)
- Type C: 5-6개
- Type D: 11개 전체

**상세 카테고리 11개 + 기록 형식은 `references/decision-points.md` 참조.**

### Step 6.5. Edge Case & Halt Forecast (자율 실행 대비)

`implement-task`가 사용자 개입 없이 끝까지 가야 하므로, 구현 중 발생 가능한 멈춤 지점을 사전 예측.

**Type별 적용 범위**:
- Type A: skip
- Type B: 빈/null 입력 + 경계값만
- Type C: 5-6개
- Type D: 10개 전체

**상세 카테고리 + Halt Forecast + 자율 실행 준비도 자문은 `references/edge-cases.md` 참조.**

### Step 7. plan.md 작성

**위치 결정** (AGENTS.md의 `Plan Location` 항목 우선):

| 프로젝트 규모 | 권장 위치 |
|---|---|
| 작은 프로젝트, 단일 작업 | `<repo>/plan.md` (덮어쓰기) |
| 큰 프로젝트, 여러 plan 누적 | `<repo>/docs/plans/<YYYY-MM-DD>-<slug>.md` |

**상세 plan.md 템플릿은 `references/plan-template.md` 참조.**

### Step 7.5. PRD 커버리지 확인 (PRD 있을 때만)

PRD가 있으면 (Step 0.5에서 작성), plan이 PRD를 빠짐없이 반영하는지 **구현 전에** 확인한다. 여기서 일치시키면 Phase G(구현 후 재검증)에서 누락이 발견돼 재구현하는 비용을 막는다.

1. **FR/NFR → task 매핑표 작성** — PRD의 각 요구에 대응하는 plan task를 적는다:
   ```
   | PRD ID | 우선순위 | 대응 task | 상태 |
   |--------|---------|----------|------|
   | FR-1 | Must | T1, T2 | ✅ 커버 |
   | FR-2 | Must | T3 | ✅ 커버 |
   | FR-3 | Should | (없음) | ⚠️ 누락 |
   ```
2. **일치 판정**:
   - 모든 Must FR에 대응 task가 있으면 → plan과 PRD가 일치. Step 8로 진행.
   - **Must FR에 대응 task가 없으면 → 누락**. plan에 task를 추가해 일치시킨 뒤 진행 (plan↔PRD 불일치 상태로 구현에 들어가지 않는다).
   - Should/Could를 의도적으로 1차 범위에서 빼려면, PRD의 Out of Scope 또는 plan에 "이번 제외" 사유를 명시 (암묵적 누락과 명시적 제외를 구분).
3. 매핑표는 plan.md에 `## PRD Coverage` 섹션으로 남긴다 (Phase G가 이 표를 기준으로 재대조).

### Step 8. 리뷰 게이트 (subagent 필수)

**`plan-reviewer` subagent 호출.** 자체 검토 금지.
- 결과가 BLOCKER 또는 MAJOR면 plan 수정 후 재호출 (최대 3회).
- 통과 후에만 다음 단계.
- **과부하(529) 시**: `plan-reviewer`는 Opus라 과부하가 잦을 수 있다. `implement-task`의 "Reviewer 과부하(529) 대응" 규칙을 따른다 — 재시도 후 계속 실패하면 Sonnet 대체 실행 + "검증 깊이 저하 가능" 명시.

### Step 9. Open Questions 해결 — 일괄·완전 모드

질문이 있으면 **여기서** 사용자에게 묶어 질문하고, 답변을 plan.md에 반영한다.

#### 질문 형식 (카테고리별 묶음)

질문이 많아도 영역별로 그룹핑하여 가독성 확보. 개수 제한 없음.

```markdown
## Open Questions

이 plan에 N개 결정이 필요합니다. 카테고리별로 정리했습니다.

### [명명] (3)

Q1. UserService 클래스 이름?
  A) ★ UserService (현재 컨벤션과 일치, src/Application/Services 패턴)
  B) UserManager
  C) AccountService

Q2. ...

### [에러 처리] (4)

Q4. 검증 실패 처리 방식?
  A) ★ Result<T> 패턴 (AGENTS.md 명시, 프로젝트 일관성)
  B) 예외 throw
  C) null 반환

Q5. ...

### [테스트 전략] (2)
...

### [UI 동작] (3)
...
```

#### 원칙

- **각 선택지에 Claude 추천 ★** — 사용자가 그대로 동의하면 빠른 결정, 다른 선택을 원하면 명확한 비교 기준 제공.
- **추천 근거**를 한 줄로 명시 (AGENTS.md / 코드 컨벤션 / 영향 분석 등).
- **라운드 반복 가능** — 답변 후 새로 드러난 모호함이 있으면 추가 질문 라운드. 통상 3-5 라운드 이내 종료.
- 5 라운드를 넘으면 plan 자체가 너무 모호 → 사용자에게 작업 범위 재확인 권고.
- **답변 시간 부담을 두려워하지 말 것.** plan 미완성으로 추측 코드를 양산하는 비용이 훨씬 크다.

### Step 10. 사용자 승인 게이트

ExitPlanMode로 plan.md 제시. 승인 시 `implement-task` 호출.

## 통과 체크리스트

다음을 모두 만족해야 implement-task로 넘어갈 수 있다:

- [ ] "아마도/보통" 0회
- [ ] Impact Analysis 4개 항목 모두 ✓
- [ ] plan-reviewer 이슈 0 (또는 MINOR만 follow-up으로 등록)
- [ ] 각 task에 검증 가능한 acceptance 1개 이상
- [ ] Open Questions 모두 해결됨
- [ ] 코드 작성 중 사용자에게 물을 결정 분기 0
- [ ] 각 task에 Type(A/B/C/D) 분류 명시
- [ ] 각 task에 Edge Cases 명시 (해당하는 모든 카테고리)
- [ ] 각 task에 Halt Forecast 명시
- [ ] 자율 실행 준비도 자문 3개 질문 모두 "예"

## 참조 문서

- Decision Points 상세: `references/decision-points.md`
- Edge Cases + Halt Forecast: `references/edge-cases.md`
- plan.md 템플릿: `references/plan-template.md`
