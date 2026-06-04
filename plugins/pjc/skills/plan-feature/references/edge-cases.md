# Edge Cases & Halt Forecast — plan-feature Step 6.5 상세

`implement-task`가 사용자 개입 없이 끝까지 가야 하므로, **구현 중 발생 가능한 모든 멈춤 지점**을 사전 예측하고 plan에 대응책을 적는다.

## 6.5-A. Edge Case 커버리지 (Type별)

### Type별 검토 범위

| Task Type | 검토 카테고리 |
|---|---|
| **A** (Doc/Config) | **skip** |
| **B** (Trivial Code) | 입력 받는 task면 "빈/null 입력" + "경계값"만 |
| **C** (Normal Code) | 5-6개 (해당하는 것만) |
| **D** (Complex/Cross-cutting) | **10개 전체** |

### 카테고리 10개

| 카테고리 | 예시 질문 |
|---|---|
| 빈/null 입력 | 빈 리스트, null, 빈 문자열일 때? |
| 경계값 | 0, 음수, 최대값, Unicode/이모지 |
| 동시성 | 동시 호출, race condition, 부분 실패 |
| 권한·인증 | 권한 없음, 토큰 만료, 익명 사용자 |
| 네트워크 | 타임아웃, 끊김, 재시도 |
| 영속화 실패 | 디스크 풀, DB 락, 트랜잭션 롤백 |
| 외부 의존 부재 | 서비스 다운, 응답 형식 변경 |
| 마이그레이션 | 기존 데이터 형식과의 호환 |
| 취소 | 사용자 취소, CancellationToken |
| 멱등성 | 같은 작업 중복 실행 |

### 기록 형식

각 task에 적용 가능한 항목을 골라 `Edge Cases` 섹션에 명시:

```markdown
- T2 Edge Cases:
  - 빈 사용자명 입력 → 검증 실패, "이름은 필수입니다" 토스트
  - 동일 이름 동시 저장 → DB Unique 제약 충돌, 사용자에게 재입력 안내
  - 저장 도중 취소 → 트랜잭션 롤백, UI 원래 상태로 복귀
```

## 6.5-B. Halt Forecast — 구현 중 발생 가능한 멈춤 시나리오

각 task에 대해 다음을 자문:

| 시나리오 | 사전 대응 |
|---|---|
| "이 부분 어떻게 처리할까?" 발생 | Decisions 섹션에 미리 결정 |
| "이 라이브러리 추가해야 할까?" | Decisions 또는 Open Question |
| "이 케이스는 무시해도 될까?" | Edge Cases에 명시적 정의 |
| 빌드/테스트 환경이 없거나 부족 | Verification Strategy에 대안 명시 |
| 외부 시스템 접근 필요 | Mock 전략 또는 Open Question |
| 권한·인증 정보 필요 | Open Question로 미리 받기 |
| 기존 코드가 plan 가정과 다름 | Investigation Log에서 실측으로 검증 완료해야 함 |

### 기록 형식

```markdown
- T2 Halt Forecast:
  - "DB 마이그레이션 정책?" → Decisions D3에서 결정 (Auto-migration on startup)
  - "Unicode 정렬 규칙?" → Edge Cases에서 명시 (ICU 기반)
  - "외부 서비스 mock?" → Verification Strategy에서 정의 (WireMock 사용)
```

## 6.5-C. 자율 실행 준비도 자문

각 task에 대해 다음 3개 질문에 "예"라고 답할 수 있어야 함:

1. 이 task의 모든 결정이 plan에 적혀 있는가?
2. 이 task 구현 중 발생 가능한 에러 케이스가 모두 정의되었는가?
3. 다른 사람이 추가 질문 없이 이 task를 끝낼 수 있는가?

하나라도 "아니오"면 Step 6 (Decision Points) 또는 Step 4 (Impact Analysis)로 복귀.
