# 착수 브리프 — 하네스 품질 검토 Deferred 후속 2건

> **이 문서는 정식 plan이 아니라 착수 브리프다.** 별도 세션에서 `pjc:plan-feature`로 정식 plan을 작성해 진행한다. 아래는 콜드 스타트를 없애기 위한 배경·근거·열어둔 질문 정리다.
>
> **출처**: 2026-07-08 하네스 품질 검토 part2(v1.100.0)의 `## Deferred / Follow-up`. 두 항목은 서로 독립이라 각각 별도 plan으로 진행해도 되고, 한 plan에 T1·T2로 묶어도 된다(둘 다 소규모).
>
> **주의**: 두 항목 모두 **"해야 한다"가 확정된 작업이 아니다.** plan-feature 단계에서 **"할 가치가 있는가"부터 판정**한다(아래 각 항목의 "선결 판단" 참조). 근거 없이 착수하면 오히려 기존 설계를 훼손할 수 있다.

---

## 후속 1. explorer 모델 상향 검토 (D5 잔여)

### 결론 (2026-07-08 종결)

- **결정: 현행 유지 (A안 — `model: haiku`, `effort: medium`).** D5 Deferred는 "검토 완료, 현행 유지"로 종결한다.
- **근거**:
  - effort medium 반영(part2 T3, v1.100.0)이 **2026-07-08 14:37 커밋**으로 검토 당일이라, "medium이 부족하다"는 반영 후 관찰 근거가 존재할 수 없음(관찰 기간 0).
  - 사용자 확인(plan Step 8): explorer가 locating을 놓치거나 부정확하게 답한 관찰 사례 **없음**.
  - 브리프 자체 원칙("근거 없으면 상향하지 않는다 — 비용만 증가")과 일치. C안(agent 분리)은 브리프도 비권장.
- **재검토 조건**: plan-feature locating 위임에서 explorer가 위치·패턴을 놓치거나 부정확하게 답한 **실사례가 관찰되면**, 그때 `model: sonnet` 상향(B안)을 새 논의로 시작한다(README 모델 라우팅 표 동기 포함). 상시 대기 항목이 아니다.

### 배경
- part2 T3에서 `plugins/pjc/agents/explorer.md`를 `effort: low → medium`으로 올리고, 문구("완결적으로 답하되 코드 덤프 금지")·Bash 범위(조회형 git만, 빌드/테스트 제외)를 정비했다.
- **모델 상향(`haiku` → 상위)은 그때 Deferred**했다 — effort medium만으로 locating 품질이 충분한지 **관찰 후 판단**하기로 함.

### 현재 상태 (확인됨)
- `explorer.md` frontmatter: `model: haiku`, `effort: medium`, `maxTurns: 20`.
- 역할: plan-feature Step 1·Step 4의 read-only locating(위치·패턴 찾기)만. **판단·전체 파일 정독은 위임 대상 아님**(explorer.md·plan-feature "위임 품질 경계"에 명시 — 메인이 직접).

### 선결 판단 (plan-feature에서 먼저)
1. **effort medium이 실제로 부족하다는 근거가 있는가?** — explorer가 locating을 놓치거나 부정확하게 답한 실사례가 관찰됐는지. 근거 없으면 상향하지 않는다(비용만 증가).
2. locating은 이미 "판단 없는 위치 찾기"로 범위가 좁다 — haiku의 약점(깊은 추론)이 이 좁은 범위에서 실제로 문제인가?

### 해결 방향 후보
- (A) 유지 — 관찰상 문제 없으면 상향하지 않음(기본값, 근거 없으면 이쪽).
- (B) `model: sonnet`으로 상향 — locating 정확도 우선, 비용 증가 감수. 상향 시 plan-feature 병렬 explorer 호출 비용이 오르므로 "독립 locating 2개 이상일 때만 위임" 원칙과의 비용 균형 재확인.
- (C) 조건부 — 특정 유형(대규모 심볼 추적)만 상위 모델, 단순 조회는 haiku. (agent frontmatter는 단일 model이라 구현상 별도 agent 분리가 필요 → 복잡도↑, 권장 낮음.)

### 관련 파일
- 주: `plugins/pjc/agents/explorer.md`
- 참조(비용·역할 정합): `plugins/pjc/skills/plan-feature/SKILL.md`(Step 1 explorer 위임·품질 경계), README Subagents 모델 라우팅 표(상향 시 문구 동기), `docs/AGENTS.md`가 아니라 README의 모델 표.

### 열어둔 질문 (plan-feature Decision으로 확정)
- Q1. 상향 여부(A/B/C) — 관찰 근거 유무가 결정.
- Q2. 상향 시 대상 모델(sonnet?) 및 README 모델 라우팅 표 문구 갱신 범위.

---

## 후속 2. llm-wiki 절차 K 본체→reference 분리 검토 (D7 잔여)

### 배경
- part2 T6에서 llm-wiki 절차 K의 **경량 완화**(K 5-2 결정 큐잉을 상시 감시 → 2배치 시점, B-1 0 동의 게이트, B-1a 축소, F-0 보고만)는 반영했다.
- **절차 K 본체 수록 → `references/`로 분리는 Deferred** — check_consistency.py 파싱 앵커(라우팅 표·절차 헤딩) 연쇄 영향이 커서 별도 plan으로 미룸.

### ⚠️ 선결 판단 (반드시 먼저 — 분리가 오히려 손해일 수 있음)
- **`llm-wiki/SKILL.md:44`가 K를 본체에 두는 것을 "의도적 설계"로 명시**한다:
  > "본체 수록 절차(J·K)는 이 문서만으로 완결된다(추가 Read 불필요) — 코드 작업 세션의 자동 참조(절차 K)가 **가장 빈번한 호출 경로**라서 K를 본체에 둔다(**컨텍스트 예산 절감의 핵심**)."
- 즉 K를 reference로 분리하면 **가장 빈번한 경로(코드 작업 세션의 위키 참조)마다 lazy-load Read가 1회 추가**된다 — 이는 현재 설계가 일부러 피한 비용이다.
- **따라서 "분리"는 자명한 개선이 아니다.** plan-feature에서 **트레이드오프를 먼저 저울질**한다:
  - 본체 유지 비용: SKILL.md 본체가 항상 K만큼 크다(모든 llm-wiki 세션이 로드).
  - 분리 비용: K 참조 경로마다 추가 Read(가장 빈번한 경로에서 반복).
- **결론이 "분리하지 않음"으로 나올 수 있다** — 그러면 D7 Deferred는 "검토 완료, 현행 유지"로 종결하고 그 근거를 남긴다(무작정 분리 금지).

### 만약 분리로 결정된다면 — 제약·범위
- **check_consistency.py 94항목 통과 필수** (AGENTS.md 게이트). K는 라우팅 표(`| K. 작업 참조 ... | (이 문서) |`, SKILL.md:35)와 `### K.` 헤딩(SKILL.md:105)이 파싱 앵커다 — 분리 시 라우팅 표의 "(이 문서)"를 참조 파일명으로 바꾸고, `references/`의 새 파일에 `### K.` 헤딩이 실존·1곳·위치 일치해야 한다(check_consistency의 "절차 배치" 검사).
- K는 하위 규칙이 많다(5·5-1 `[SKILL-IMPROVE]`·5-2 `[DECISION]`) — 어디까지 옮길지(K 전체 vs 5-x 하위만) 결정 필요.
- `procedures-content.md`/`procedures-ops.md` 중 어디로 갈지(K는 read-only 조회라 성격상 content 계열).
- 산문 크로스파일 포인터(다른 절차가 "절차 K"를 참조하는 곳)가 새 파일을 가리키도록 동기 — check_consistency의 "산문 포인터" 검사가 잡는다.

### 관련 파일
- 주: `plugins/pjc/skills/llm-wiki/SKILL.md`(절차 K 본체·라우팅 표·:44 설계 주석), `references/procedures-content.md`(분리 대상 후보 위치)
- 게이트: `plugins/pjc/skills/llm-wiki/evals/check_consistency.py`(94항목 — 매 수정 후 실행), `evals/run_lint_evals.py`
- 참조 동기: `references/wiki-schema.md`, K를 참조하는 다른 스킬(plan-feature Step 1·implement-task 재개 진입 절차 K 언급).

### 열어둔 질문 (plan-feature Decision으로 확정)
- Q1. **분리할 가치가 있는가?** (:44 설계와의 트레이드오프 — 이게 첫 관문. "아니오"면 여기서 종결.)
- Q2. 분리 시 범위(K 전체 / 5-x 하위 규칙만).
- Q3. 대상 파일(procedures-content.md 신설 절 vs 새 reference 파일).
- Q4. :44 설계 주석의 갱신 문구(분리하면 "본체 수록" 근거가 바뀌므로 그 주석도 함께 정정).

---

## 진행 방법 (별도 세션)
1. 이 브리프를 연 뒤 `pjc:plan-feature`로 정식 plan 작성(각 항목의 "선결 판단"을 Step 2 범위 명확화·Step 6 Decision으로 먼저 해소).
2. 두 항목 모두 **"현행 유지"가 정당한 결론일 수 있음** — 그 경우 근거를 남기고 종결(억지 변경 금지).
3. 진행 시 각각 소규모라 Type B~C 예상. llm-wiki 항목은 산문 한정·라우팅 표/헤딩 앵커 보존·매 수정 후 check_consistency 재실행이 필수.
