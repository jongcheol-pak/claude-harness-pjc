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
- 같은 BLOCKER가 **3회 연속 지적** → Halt.
- 빌드/테스트 **5회 연속 실패**, 원인 미상 → Halt.

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
