# Recovery Mechanism — implement-task

Phase V 실패 시 복구 절차.

## 절차

Phase V에서 회복 불가 판단 시:

```bash
git reset --hard <checkpoint hash>
```

**순서 주의 (카운터 유실 방지)**: `git reset --hard`는 **추적(tracked) plan.md도 checkpoint 시점으로 되돌린다**. 따라서 Retry Ledger 카운트 증가·"Failed attempts" 기록은 **반드시 reset 이후에** 수행한다 — reset 전에 적으면 바로 그 reset이 방금 센 카운트를 지워, "checkpoint 복구 2회 → Halt" 가드가 매 복구마다 0으로 리셋돼 **영원히 발동하지 못한다**(무한 복구 루프). 순서: ① `git reset --hard <checkpoint>` → ② plan.md `## Retry Ledger` 복구 카운트 +1 및 해당 task에 실패 원인 기록 → ③ Phase P부터 다른 접근으로 재시도. (plan.md가 gitignore인 repo에선 reset이 plan.md를 안 건드리므로 순서 무관 — SKILL.md의 stale `[x]` 주석과 반대 방향의 같은 원리.)

## 한계

- 동일 task에서 **2회 복구 발생 시 Halt** (자동 중단 → 사용자 보고).
- 같은 BLOCKER/MAJOR가 **3회 연속 지적** → Halt (reviewer의 RECURRING 태그도 이 카운터에 포함).
- 같은 task에서 **리뷰 지적(BLOCKER/MAJOR) 수정 사이클이 누적 5회** → Halt. 매 사이클 지적이 서로 달라 '동일 3회'에 안 걸려도, 5번 고치고도 새 결함이 계속 나오면 구현 방향이 근본적으로 틀린 신호다(무한 수정 루프 방지).
- 빌드/테스트 **5회 연속 실패**, 원인 미상 → Halt.
- 한 task에서 **빌드·수정 사이클 10회 이상** 반복하고도 미완 → Halt (무한 그라인딩). 위 두 캡이 못 잡는 시나리오를 막는다 — 빌드 5회 캡은 "원인 미상"이어야 걸리고 수정 사이클 5회 캡은 "리뷰 지적"에만 걸리므로, **원인은 매번 파악되지만 끝나지 않는** 그라인딩은 이 상한이 유일하게 잡는다.
- **카운터 영속화 (압축 생존, G5).** 다음 카운터는 대화 컨텍스트에만 두면 auto-compact·재개 시 리셋된다 → **발생 시 plan.md `## Retry Ledger`에 카운트를 기록**하고, 압축·재개 후 그 값에서 이어 센다 (SKILL.md 재시도 한계와 동일 규칙):
  - **task 단위**: checkpoint 복구 2회·동일 BLOCKER/MAJOR 3회·수정 사이클 누적 5회·**빌드·수정 사이클 10회(무한 그라인딩)**. (checkpoint 복구 카운트는 **reset 후에** 기록해야 생존한다 — 위 "순서 주의".)
  - **Phase 단위 재루프**: Phase G 재루프 최대 2회(`phase-g-detail.md` G-3)·Phase F-7 재진입 최대 3회(`phase-f-detail.md` F-7). 이 둘도 컨텍스트 관리 규칙 4의 "압축 통과" 시나리오 안에서 도는 루프이므로 함께 영속화하지 않으면 압축이 카운트를 0으로 리셋해 "최대 2회·3회" 무한루프 가드가 무력화된다.
  아래 "Failed attempts"가 무엇이 왜 실패했는지를 남긴다면, Retry Ledger는 몇 번째인지(카운트)를 남겨 둘이 보완한다.

## checkpoint 구조

각 task의 Phase I 시작 시 `git commit --allow-empty -m "checkpoint: T<N> start"`(빈 커밋) 생성.
구현 완료 후 Phase V 진입 직전 `git commit -m "checkpoint: T<N> pre-review"`(실변경 — 리뷰 대상 diff 고정, SKILL Phase V 서두) 생성.
pre-review 이후의 수정분(리뷰 지적·V-1~V-3 실패 수정)은 `git commit -m "checkpoint: T<N> review-fix"`로 이어 커밋(재리뷰 HEAD 갱신 — SKILL Phase V 서두·Phase D ① 판정 신호).
중간에 큰 변경 후 추가 checkpoint 가능:

```bash
git commit -m "checkpoint: T<N> partial — <어디까지>"
```

**복구 reset 대상**: 회복 불가 판단 시점에 따라 다르다 — 구현 자체를 폐기하고 다시 짜야 하면 `checkpoint: T<N> start`(빈 커밋)로, 리뷰 지적 수정이 꼬여 pre-review 시점으로만 되돌리면 되는 경우엔 `checkpoint: T<N> pre-review`로 reset한다(가장 최근의 적절한 checkpoint). 그 이후 변경은 모두 폐기.

## 복구 후 행동

1. 실패 원인을 plan.md의 해당 task에 "Failed attempts" 섹션으로 기록
2. Phase P 재진입 (사용자에게 묻지 않음)
3. 다른 접근법 시도

이는 자율 루프의 일부이므로 사용자 개입 없이 자동 진행.

## Reviewer 호출 실패 대응 (과부하·도구 불가) — 모든 subagent 호출 공통

reviewer subagent 호출이 실패하면 **실패 유형으로 분기**한다 (V-5/V-6, Phase F-7, plan-feature의 plan-reviewer 등 모든 reviewer 호출에 적용). 유형이 둘인 이유는 대응이 정반대이기 때문이다 — **과부하는 기다리면 풀리므로 재시도가 1순위**지만, **도구 자체를 못 쓰는 환경은 몇 번을 재시도해도 같으므로 즉시 대체 절차로 간다**.

### A. 과부하 (HTTP 529)

1. **짧게 대기 후 재시도** (최대 2회). 일시적 과부하는 대부분 재시도로 해소된다.
2. 재시도도 계속 529면 **모델 등급에 따라 분기**:
   - **Opus reviewer**(`plan-reviewer`, `plan-completion-reviewer`): **Sonnet으로 대체 실행 가능**. 단 *"Opus 과부하로 Sonnet 대체 실행 — 검증 깊이가 평소보다 낮을 수 있음"*을 사용자에게 **명시**하고, 그 reviewer의 결과/완료 보고에 ⚠️ 표시를 남긴다. 중요 게이트(F-7 등)를 건너뛰지 않기 위함이며, 대체로 통과해도 "Opus 미검증 영역 가능"을 plan.md Next Steps에 기록한다.
   - **Sonnet reviewer**(`spec-compliance-reviewer`, `code-quality-reviewer`): **Haiku 대체 금지** (검증 신뢰도가 크게 떨어짐). 재시도가 모두 실패하면 사용자에게 *"검증 subagent가 과부하로 실행 불가 — 잠시 후 재시도 / 이번은 자체 검증으로 진행 / 대기"* 중 선택을 요청한다. 자체 검증으로 진행하더라도 그 사실을 보고에 명시한다.
   - **Haiku reviewer**(`spec-prefilter`, `explorer`): 재시도만. 계속 실패하면 해당 단계의 상위 흐름(Sonnet reviewer 직접 호출 등)으로 진행한다.
3. **모델 대체·검증 생략은 항상 사실을 명시한다** (투명성). 검증이 평소보다 약화됐다는 신호를 사용자가 알 수 있어야 한다 — 조용히 대체하지 않는다.

### B. 도구 사용 불가 (subagent 호출 자체가 불가능)

**발동 조건 (좁게 한정)**: subagent 호출이 **기술적으로 불가능**할 때만이다 — 세션 정책이 subagent 사용을 금지·차단하거나, 도구가 제공되지 않거나, 호출이 즉시 거부되는 경우. **"리뷰가 과한 것 같다", "이 정도는 안 봐도 된다" 같은 판단은 발동 조건이 아니다** — 그 판단으로 여는 순간 이 분기는 검증을 건너뛰는 통로가 된다. 조건이 애매하면 발동하지 않고 Halt해 사용자에게 묻는다.

1. **재시도는 2회까지만** 하고(A와 같은 한도 — 일시적 오류와 구분하기 위함) 더 반복하지 않는다. 환경이 원인이면 재시도로 바뀌지 않는다.
2. **대체 절차**: 메인이 해당 reviewer의 **정의 파일(`agents/<이름>.md`)을 Read해 그 판정 항목을 체크리스트로 삼아 직접 대조**하고, **항목별 판정 결과를 남긴다**. 요약이 아니라 항목 단위 기록이어야 한다 — "대체로 괜찮다" 식의 뭉뚱그린 통과는 이 절차의 목적(무엇을 못 봤는지 드러내기)을 없앤다.
3. **의무 3종 (전부 필수)**:
   - 사용자에게 **그 자리에서 보고**한다("reviewer 호출 불가 → 체크리스트 대조로 대체").
   - plan.md `## Progress Log`에 대체 사실을 기록한다(압축·재개 후에도 남게).
   - **최종 보고에 "검증 깊이 저하 — reviewer 미실행"을 명시**한다. 이 표시가 없으면 사용자는 적대적 검토를 받은 산출물로 오인한다.
4. **Phase G 연동**: F-7을 이 분기로 대체했으면 **PRD 대조의 신뢰도가 낮아진 상태**이므로, `phase-g-detail.md` G-1 예외 ②(Sonnet 대체 시)와 **동일하게 active Must FR 전체를 메인이 보완 재대조**한다 — 체크리스트 대체는 Sonnet 대체보다 검증 깊이가 **더** 낮으므로 더 약한 경로가 더 느슨한 사후 검증을 받는 역전을 막는다.

> **이것은 "생략"이 아니라 "대체"다.** 안티패턴 표의 *"Review subagent 생략 — 절대 금지"*는 **호출할 수 있는데 안 하는 것**을 금지한다. 이 분기는 호출이 불가능한 환경에서 검증을 **다른 수단으로 수행하고 그 약화를 공시**하는 절차이므로 그 금지와 충돌하지 않는다.
