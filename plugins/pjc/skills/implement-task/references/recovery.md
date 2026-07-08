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
- **카운터 영속화 (압축 생존, G5).** 다음 카운터는 대화 컨텍스트에만 두면 auto-compact·재개 시 리셋된다 → **발생 시 plan.md `## Retry Ledger`에 카운트를 기록**하고, 압축·재개 후 그 값에서 이어 센다 (SKILL.md 재시도 한계와 동일 규칙):
  - **task 단위**: checkpoint 복구 2회·동일 BLOCKER/MAJOR 3회·수정 사이클 누적 5회. (checkpoint 복구 카운트는 **reset 후에** 기록해야 생존한다 — 위 "순서 주의".)
  - **Phase 단위 재루프**: Phase G 재루프 최대 2회(`phase-g-detail.md` G-3)·Phase F-7 재진입 최대 3회(`phase-f-detail.md` F-7). 이 둘도 규칙 4의 "압축 통과" 시나리오 안에서 도는 루프이므로 함께 영속화하지 않으면 압축이 카운트를 0으로 리셋해 "최대 2회·3회" 무한루프 가드가 무력화된다.
  아래 "Failed attempts"가 무엇이 왜 실패했는지를 남긴다면, Retry Ledger는 몇 번째인지(카운트)를 남겨 둘이 보완한다.

## checkpoint 구조

각 task의 Phase I 시작 시 `git commit --allow-empty -m "checkpoint: T<N> start"`(빈 커밋) 생성.
구현 완료 후 Phase V 진입 직전 `git commit -m "checkpoint: T<N> pre-review"`(실변경 — 리뷰 대상 diff 고정, SKILL Phase V 서두) 생성.
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

## Reviewer 과부하(529) 대응 — 모든 subagent 호출 공통

reviewer subagent 호출이 **과부하(HTTP 529)로 실패**하면 다음을 따른다 (V-5/V-6, Phase F-7, plan-feature의 plan-reviewer 등 모든 reviewer 호출에 적용):

1. **짧게 대기 후 재시도** (최대 2회). 일시적 과부하는 대부분 재시도로 해소된다.
2. 재시도도 계속 529면 **모델 등급에 따라 분기**:
   - **Opus reviewer**(`plan-reviewer`, `plan-completion-reviewer`): **Sonnet으로 대체 실행 가능**. 단 *"Opus 과부하로 Sonnet 대체 실행 — 검증 깊이가 평소보다 낮을 수 있음"*을 사용자에게 **명시**하고, 그 reviewer의 결과/완료 보고에 ⚠️ 표시를 남긴다. 중요 게이트(F-7 등)를 건너뛰지 않기 위함이며, 대체로 통과해도 "Opus 미검증 영역 가능"을 plan.md Next Steps에 기록한다.
   - **Sonnet reviewer**(`spec-compliance-reviewer`, `code-quality-reviewer`): **Haiku 대체 금지** (검증 신뢰도가 크게 떨어짐). 재시도가 모두 실패하면 사용자에게 *"검증 subagent가 과부하로 실행 불가 — 잠시 후 재시도 / 이번은 자체 검증으로 진행 / 대기"* 중 선택을 요청한다. 자체 검증으로 진행하더라도 그 사실을 보고에 명시한다.
   - **Haiku reviewer**(`spec-prefilter`, `explorer`): 재시도만. 계속 실패하면 해당 단계의 상위 흐름(Sonnet reviewer 직접 호출 등)으로 진행한다.
3. **모델 대체·검증 생략은 항상 사실을 명시한다** (투명성). 검증이 평소보다 약화됐다는 신호를 사용자가 알 수 있어야 한다 — 조용히 대체하지 않는다.
