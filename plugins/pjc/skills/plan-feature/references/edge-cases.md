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

> **Type 게이트 (plan-reviewer 항목 11과 정합)**: **Type C/D는 필수**. **Type A/B는 경감** — 파괴적 작업·새 의존성·외부/비가역·인증정보를 유발하는 시나리오가 있을 때만 명시하고, 없으면 **"없음 — <판단 근거 1줄>"**으로 통과한다(예: "없음 — 순수 문서 수정, 파괴적·외부 요소 없음"). **근거 한 줄은 붙인다** — plan-reviewer 항목 11이 "없음"+근거 1줄이면 Type 무관 통과시키고, 근거 없는 빈 "없음"은 MAJOR로 보기 때문이다(순수 문서 Type A·trivial Type B는 대개 멈춤 시나리오가 없다). 단 Type A/B라도 그런 시나리오가 하나라도 있으면 아래 (ii-a)/(ii-b)/(ii-c)로 **반드시** 적는다.

각 task에 대해 다음을 자문(C/D 필수, A/B는 해당 시나리오가 있을 때):

| 시나리오 | 사전 대응 |
|---|---|
| "이 부분 어떻게 처리할까?" 발생 | Decisions 섹션에 미리 결정 |
| "이 라이브러리 추가해야 할까?" | Decisions 또는 Open Question |
| "이 케이스는 무시해도 될까?" | Edge Cases에 명시적 정의 |
| 빌드/테스트 환경이 없거나 부족 | Verification Strategy에 대안 명시 |
| 외부 시스템 접근 필요 | Mock 전략 또는 Open Question |
| 권한·인증 정보 필요 | Open Question로 미리 받기 |
| 기존 코드가 plan 가정과 다름 | Investigation Log에서 실측으로 검증 완료해야 함 |

> **확인 이연 금지**: 위 표의 확인들 중 **설계·acceptance의 성립 여부를 좌우하는 확인**(부정되면 task 자체가 성립 불가)은 "구현 첫 단계에서 확인"으로 미루지 말고 계획 단계에서 완료한다 — plan-feature Step 6.5·plan-reviewer 항목 9와 정합(성립이 아니라 진행 방식만 바꾸는 확인은 이연 허용).

### 기록 형식

```markdown
- T2 Halt Forecast:
  - (i) "DB 마이그레이션 정책?" → Decisions D3에서 결정 (Auto-migration on startup)
  - (i) "Unicode 정렬 규칙?" → Edge Cases에서 명시 (ICU 기반)
  - (i) "외부 서비스 mock?" → Verification Strategy에서 정의 (WireMock 사용)
  - (ii-a) "운영 DB 스키마 변경(비파괴 — CREATE/ADD)?" → `## 사전 승인 항목`에 등록 (plan 승인 시 일괄 위임)
  - (ii-b) "운영 DB DROP·데이터 손실 동반?" → `## 불가피한 Halt (위임 불가)` 명시 (파괴적 — 항상 Halt)
  - (ii-c) "구현 중 생긴 낡은 헬퍼 정리?" → 없어도 acceptance 충족 → 미루고 최종 보고에서 일괄 승인 (plan에는 등재처 없음)
```

각 항목은 다음 4분류 중 하나로 적는다(**plan-feature Step 6.5 역매핑의 정본**):
- **(i) 사전 해소** — 자율 루프가 그 지점에서 멈추지 않도록 plan에 결정을 박아 둠(Step 6 Decision·Step 8 Open Question).
- **(ii-a) 사전 승인 가능** — 비파괴 의존성/구조/스키마·계획된 공개 API·시그니처 변경 등 알려진 승인 필요 항목 → `## 사전 승인 항목`에 등록, plan 승인 시 일괄 위임(멈추지 않음).
- **(ii-b) 위임 불가 Halt 명시** — **파괴적 작업(force push·rm -rf·DB DROP/TRUNCATE·WHERE 없는 DELETE/UPDATE·스키마 삭제·migration reset·권한/보안 변경)·외부/비가역(push·main 병합·태그·릴리즈·PR)·인증정보 필요 신규 외부 서비스·돌발 중대 결정** → `## 불가피한 Halt (위임 불가)`에 적고 사전결정으로 우회하지 않음(항상 Halt).
- **(ii-c) 완료 후 일괄 승인** — 승인이 필요하지만 **그 작업 없이 그 task의 acceptance가 충족되는** 것(계획에 없던 정리·위생 작업 등 부수 작업). 루프는 하지 않은 채 진행하고 최종 보고가 모아 승인받는다 — **`## 사전 승인 항목`에도 `## 불가피한 Halt`에도 등재하지 않는다**(승인을 구현 후에 받으므로 plan 승인 시점에 목록이 필요 없다. 등재처는 구현 중의 `## Progress Log`이고 그것은 계획이 아니라 실행 산출물이다). 판정 기준·배제 항목의 정본은 `implement-task`의 `references/halt-conditions.md` 「위임 경계」 표 4번째 행이다.

**파괴적 작업은 (ii-a)·(ii-c) 어느 쪽에도 절대 넣지 않는다 — 항상 (ii-b).** 두 분류 모두 *"루프가 그 지점에서 멈추지 않는다"*는 성질을 공유하므로 배제 조항이 양쪽에 걸린다.

## 6.5-C. 자율 실행 준비도 자문

> **Type 게이트 (plan-reviewer 항목 9와 정합)**: **Type B/C/D 필수**. **Type A(순수 문서/설정)는 자명하게 충족**되므로 생략 가능하다(plan-reviewer도 "Type A만" plan에는 항목 9를 적용하지 않는다). 단 Type A로 분류됐으나 **동작을 바꾸는 Config**면 이는 Type 오분류이므로(Step 5 Type A 가드) 재분류한 뒤 이 자문을 적용한다.

각 task(Type B 이상)에 대해 다음 3개 질문에 "예"라고 답할 수 있어야 함:

1. 이 task의 모든 결정이 plan에 적혀 있는가?
2. 이 task 구현 중 발생 가능한 에러 케이스가 모두 정의되었는가?
3. 다른 사람이 추가 질문 없이 이 task를 끝낼 수 있는가?

하나라도 "아니오"면 Step 6 (Decision Points) 또는 Step 4 (Impact Analysis)로 복귀.

단, (ii-b) 위임 불가 Halt(파괴적·외부/비가역·인증정보 필요 신규 외부 서비스·돌발 결정)가 명시된 task는 그 Halt 지점에서 승인을 위해 멈추는 것이 정상이며, 질문 3의 "추가 질문"이나 "준비도 미달"에 해당하지 않는다. **(ii-a) 사전 승인 항목은 plan 승인에 일괄 포함돼 그 지점에서 멈추지 않는다.** (자율 루프는 (ii-b)에서만 공시 후 멈추고, 그 외 전 구간은 멈춤 없이 진행한다.)
