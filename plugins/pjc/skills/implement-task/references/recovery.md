# Recovery Mechanism — implement-task

Phase V 실패 시 복구 절차.

## 절차

Phase V에서 회복 불가 판단 시:

```bash
git reset --hard <checkpoint hash>
```

후 plan.md의 해당 task에 실패 원인 기록. Phase P부터 다른 접근으로 재시도.

## 한계

- 동일 task에서 **2회 복구 발생 시 Halt** (자동 중단 → 사용자 보고).
- 같은 BLOCKER/MAJOR가 **3회 연속 지적** → Halt (reviewer의 RECURRING 태그도 이 카운터에 포함).
- 같은 task에서 **리뷰 지적(BLOCKER/MAJOR) 수정 사이클이 누적 5회** → Halt. 매 사이클 지적이 서로 달라 '동일 3회'에 안 걸려도, 5번 고치고도 새 결함이 계속 나오면 구현 방향이 근본적으로 틀린 신호다(무한 수정 루프 방지).
- 빌드/테스트 **5회 연속 실패**, 원인 미상 → Halt.
- **카운터 영속화 (압축 생존, G5).** 위 카운터(복구 2회·동일 BLOCKER/MAJOR 3회·수정 사이클 누적 5회)는 대화 컨텍스트에만 두면 auto-compact·재개 시 리셋된다 → **재시도 발생 시 plan.md `## Retry Ledger`에 카운트를 기록**하고, 압축·재개 후 그 값에서 이어 센다 (SKILL.md 재시도 한계와 동일 규칙). 아래 "Failed attempts"가 무엇이 왜 실패했는지를 남긴다면, Retry Ledger는 몇 번째인지(카운트)를 남겨 둘이 보완한다.

## checkpoint 구조

각 task의 Phase I 시작 시 `git commit --allow-empty -m "checkpoint: T<N> start"` 생성.
중간에 큰 변경 후 추가 checkpoint 가능:

```bash
git commit -m "checkpoint: T<N> partial — <어디까지>"
```

복구 시 가장 최근 checkpoint로 reset. 그 이후 변경은 모두 폐기.

## 복구 후 행동

1. 실패 원인을 plan.md의 해당 task에 "Failed attempts" 섹션으로 기록
2. Phase P 재진입 (사용자에게 묻지 않음)
3. 다른 접근법 시도

이는 자율 루프의 일부이므로 사용자 개입 없이 자동 진행.
