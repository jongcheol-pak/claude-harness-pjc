# Halt Conditions — implement-task

자율 루프 중단 조건과 사용자 보고 양식.

## 중단 조건 표

다음 중 하나라도 해당하면 **즉시 정지하고 사용자에게 보고**한다.

| 카테고리 | 조건 |
|---|---|
| 계획 결함 | plan.md에 없는 결정 분기 발견 |
| 계획 결함 | plan.md의 가정이 실측과 불일치 |
| 계획 결함 | acceptance가 검증 불가능함이 드러남 |
| **계획 결함** | **Phase P-3에서 plan.md Files에 없는 호출자/구현체 발견 (수정 범위 큰 경우)** |
| 루프 실패 | 동일 task에서 checkpoint 복구 2회 |
| 루프 실패 | Review subagent가 동일 이슈를 3회 연속 지적 |
| 루프 실패 | 빌드/테스트 5회 연속 실패, 원인 미상 |
| 범위 초과 | 변경이 plan.md에 없는 모듈로 번짐 |
| 파괴적 작업 | force push, history rewrite, 데이터 삭제, 권한·보안 설정 변경 |
| 외부 의존 | 새 라이브러리·외부 서비스·인증정보 도입 필요 |
| 환경 의존 | 검증을 위한 실제 디바이스·환경 접근 필요 |
| 비용 폭증 | 한 task 처리에 비정상적 토큰/시간 소비 |
| **컨텍스트 한계** | **장시간 작업으로 컨텍스트가 과밀해져 품질 저하 우려 — 중간 체크포인트 보고** |

## 컨텍스트 한계 근접 시 (중간 체크포인트)

장시간 자율 루프 중 컨텍스트가 과밀하다고 판단되면:

1. 현재까지 진행을 plan.md `## Progress Log`에 기록
2. 모든 변경 commit
3. 사용자에게 중간 보고:

```markdown
## ⏸️ 중간 체크포인트 (컨텍스트 관리)

진행: T<N>/<TOTAL> 완료
컨텍스트가 누적되어 후반 품질 유지를 위해 일시 정지합니다.

완료된 task: T1 ~ T<N> (모두 commit + 검증 통과)
남은 task: T<N+1> ~ T<TOTAL>

**재개 방법**: 새 세션에서 "T<N+1>부터 계속해줘"
(plan.md의 Progress Log와 git log로 상태 복구됨)
```

이는 실패가 아니라 **품질 보존을 위한 정상적 분할**이다.

## "사소한 문제"는 중단 사유가 아니다

- 단발성 빌드 오류 → 자체 수정
- 테스트 1–2개 실패 → 원인 분석 후 수정
- 린트 경고 → 수정
- 환경 변수 누락 → AGENTS.md/plan.md 참조하여 자체 해결

## 중단 보고 형식

```markdown
## ⛔ 작업 중단: T<N>

**Reason**: <Halt Condition 카테고리>
**Details**: <팩트 기반 상황 설명>
**State**:
- Last checkpoint: <commit hash>
- Files touched: <목록>
- Tests: <상태>
**Options for user**:
  A) <대안 1>
  B) <대안 2>
  C) plan.md 재작성 (plan-feature로 복귀)
```
