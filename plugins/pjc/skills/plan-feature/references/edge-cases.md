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
  - (i) "DB 마이그레이션 정책?" → Decisions D3에서 결정 (Auto-migration on startup)
  - (i) "Unicode 정렬 규칙?" → Edge Cases에서 명시 (ICU 기반)
  - (i) "외부 서비스 mock?" → Verification Strategy에서 정의 (WireMock 사용)
  - (ii-a) "운영 DB 스키마 변경(비파괴 — CREATE/ADD)?" → `## 사전 승인 항목`에 등록 (plan 승인 시 일괄 위임)
  - (ii-b) "운영 DB DROP·데이터 손실 동반?" → `## 불가피한 Halt (위임 불가)` 명시 (파괴적 — 항상 Halt)
```

각 항목은 다음 3분류 중 하나로 적는다(**plan-feature Step 6.5 역매핑의 정본**):
- **(i) 사전 해소** — 자율 루프가 그 지점에서 멈추지 않도록 plan에 결정을 박아 둠(Step 6 Decision·Step 8 Open Question).
- **(ii-a) 사전 승인 가능** — 비파괴 의존성/구조/스키마·계획된 공개 API·시그니처 변경 등 알려진 승인 필요 항목 → `## 사전 승인 항목`에 등록, plan 승인 시 일괄 위임(멈추지 않음).
- **(ii-b) 위임 불가 Halt 명시** — **파괴적 작업(force push·rm -rf·DB DROP/TRUNCATE·WHERE 없는 DELETE/UPDATE·스키마 삭제·migration reset·권한/보안 변경)·외부/비가역(push·main 병합·태그·릴리즈·PR)·인증정보 필요 신규 외부 서비스·돌발 중대 결정** → `## 불가피한 Halt (위임 불가)`에 적고 사전결정으로 우회하지 않음(항상 Halt).

**파괴적 작업은 (ii-a)에 절대 넣지 않는다 — 항상 (ii-b).**

## 6.5-C. 자율 실행 준비도 자문

각 task에 대해 다음 3개 질문에 "예"라고 답할 수 있어야 함:

1. 이 task의 모든 결정이 plan에 적혀 있는가?
2. 이 task 구현 중 발생 가능한 에러 케이스가 모두 정의되었는가?
3. 다른 사람이 추가 질문 없이 이 task를 끝낼 수 있는가?

하나라도 "아니오"면 Step 6 (Decision Points) 또는 Step 4 (Impact Analysis)로 복귀.

단, (ii-b) 위임 불가 Halt(파괴적·외부/비가역·인증정보 필요 신규 외부 서비스·돌발 결정)가 명시된 task는 그 Halt 지점에서 승인을 위해 멈추는 것이 정상이며, 질문 3의 "추가 질문"이나 "준비도 미달"에 해당하지 않는다. **(ii-a) 사전 승인 항목은 plan 승인에 일괄 포함돼 그 지점에서 멈추지 않는다.** (자율 루프는 (ii-b)에서만 공시 후 멈추고, 그 외 전 구간은 멈춤 없이 진행한다.)
