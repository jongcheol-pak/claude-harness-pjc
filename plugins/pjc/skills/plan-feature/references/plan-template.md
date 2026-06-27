# plan.md Template

## 위치 결정 가이드

| 프로젝트 규모 | 권장 위치 |
|---|---|
| 작은 프로젝트, 단일 작업 | `<repo>/plan.md` (덮어쓰기 방식) |
| 큰 프로젝트, 여러 plan 누적 | `<repo>/docs/plans/<YYYY-MM-DD>-<slug>.md` |

AGENTS.md에 `Plan Location: <plan.md | docs/plans/>`로 명시되어 있으면 그것을 따른다.

**예외 — plan 분할 시**: 긴 plan을 2개로 분할하면(plan-feature "긴 plan 분할 권고") `Plan Location: plan.md`(덮어쓰기)여도 `docs/plans/<YYYY-MM-DD>-<slug>-part1.md`/`-part2.md`에 둔다 — 분할은 복수 파일이라 단일 plan.md를 덮어쓸 수 없다(두 part가 충돌). 시작 part 식별: part1 = `**다음 plan**:` 있고 `**이전 plan**:` 없음 / part2 = 그 반대. 자동 plan 해소(인자 생략)는 복수 파일에서 모호하므로 각 part 경로를 명시해 `pjc:implement-task`를 호출한다.

## 작성 시 주의 — 민감 정보

plan.md는 **git에 commit되어 영구 보존**된다.
다음을 plan.md에 적지 않는다:

- API key, access token, secret
- password, connection string
- 개인정보(이메일·전화·실명 등)
- 내부 URL/도메인 중 외부 노출 시 민감한 것

필요하면 **환경변수 이름만** 적고 실제 값은 `.env`(gitignore)에서 관리.
예: `❌ DATABASE_URL=postgres://user:pass@host/db` → `✅ DATABASE_URL은 .env에 정의`

## Template

```markdown
# Plan: <기능명>

<!-- 대규모 작업(PRD 있는 경우)은 반드시 아래 줄 포함 — implement-task가 이 줄로 Phase G 진입을 판단한다.
     컨텍스트 압축·새 세션에서도 plan.md만 읽으면 PRD 존재를 알 수 있어야 한다. -->
**PRD**: <docs/prd.md 경로 — PRD 없으면 이 줄 자체를 생략>

<!-- plan을 2개로 분할한 경우(plan-feature "긴 plan 분할 권고")만 아래 분할 포인터 줄을 둔다(단일 plan이면 생략):
     - 첫 plan(part1): **다음 plan**: <part2 경로>
     - 둘째 plan(part2): **이전 plan**: <part1 경로>
     plan-completion-reviewer가 이 표식으로 분할 plan임을 인지해 Goal을 "이 plan 범위"로 해석한다(전체 미완성을 BLOCKER로 보지 않음).
     동기화 주의: part2 경로는 이 줄·아래 ## Deferred·## Next Steps 3곳에 나타난다 — 경로를 바꾸면 세 곳을 함께 고친다. -->
**다음 plan**: <분할 첫 part(part1)면 part2 경로 — 분할 아니거나 마지막 part면 이 줄 생략(part2는 대신 **이전 plan**: 사용)>

## Goal
<한 문장 — 사용자 관점>
<!-- 분할 plan이면: 위 Goal은 "이 plan 범위(이 part가 담당하는 부분)"만 한 문장으로 쓰고, 바로 아래에
     **전체 목표**: <분할 전 전체 기능 한 문장> 줄을 둔다.
     reviewer는 분할 표식(**다음/이전 plan**:)이 있으면 Goal 충족을 "이 plan 범위" 기준으로 판정한다(전체 미완성을 BLOCKER로 안 봄). -->


## PRD Coverage
<!-- PRD 있을 때만. plan-feature Step 7.5에서 작성. Phase G가 이 표로 재대조. -->
| PRD ID | 우선순위 | 대응 task | 상태 |
|--------|---------|----------|------|
| FR-1 | Must | T1 | ✅ 커버 |

## Out of Scope
<!-- 영구 제외 — 이 기능 자체를 만들지 않음. "다음에 할 것"은 여기 적지 말고 아래 Deferred에. -->
- <이 작업에서 의도적으로 만들지 않는 것 (영구)>

## Deferred / Follow-up
<!-- 이번 제외 — 이번 plan에선 안 하지만 향후 진행할 작업.
     사용자가 "이번엔 빼고 다음에 하자"고 한 것은 Out of Scope가 아니라 반드시 여기로.
     분할 plan의 첫 part(part1)면: "**다음 분할 plan**: <part2 경로> — T1~ (전체의 후반부, 미실행)"을
     반드시 여기 기록해 둘째 plan 실행을 잊지 않게 한다(동기화: 상단 **다음 plan**:·## Next Steps와 같은 경로). -->
- <이번엔 제외, 향후 별도 plan으로 진행할 작업>

## Investigation Log
- <확인 방법 + 결과>

## Risks & Unknowns
| 위험 | 영향 | 완화책 |
|---|---|---|

## Impact Analysis
### 4-A. 심볼/타입 추적 결과
| 심볼 | 영향 받는 파일 | 영향 종류 |
|---|---|---|

### 4-B. 계약·직렬화 변경
- <항목>

### 4-C. 테스트 파일
- <테스트 파일 목록>

### Verified by
- grep "<symbol>\." → N hits, 모두 위 표에 포함
- grep "<Interface>" → N 구현체, 모두 위 표에 포함

## Decisions
### D1. <결정 항목>
- **Options**: A) ... / B) ... / C) ...
- **Chosen**: A
- **Rationale**: ...
- **Source**: ...

## Tasks
<!-- 반드시 T1, T2, ... 형식. "Phase 1", "단계 1", "Step 1" 등으로 쓰지 말 것
     (implement-task 자율 루프가 T<N>를 전제, pjc 내부 Phase와 혼동 방지).
     큰 묶음 표시는 주석으로만: 예) T1~T3 (데이터 계층)
     placeholder 금지: 자율 루프는 plan.md만 보고 실행하므로 추측을 부르는 표현을 쓰지 말 것.
       ❌ "T3과 비슷하게" → 그 task에 할 일을 직접 명시
       ❌ "TBD/미정/추후 결정" → 계획 단계에서 확정
       ❌ "그 함수/관련 파일들/해당 부분" → 정확한 파일 경로·심볼명으로 -->
- [ ] T1. <작업명>
  - **Type**: A | B | C | D
  - **Acceptance**: <검증 가능한 조건>
  - **Files**:
    - 주: `src/Foo.cs`
    - 동반: `src/Bar.cs`
    - 테스트: `tests/FooTests.cs`
  - **Edge Cases**:
    - <빈 입력/경계값/동시성/권한/네트워크 등 적용 가능한 항목>
  - **Halt Forecast**:
    - (i) <발생 가능한 멈춤 시나리오> → <plan의 어느 항목에서 해결됨>
    - (ii) <불가피한 Halt — 파괴적 작업·새 의존성·외부 인증·승인 필수 등 자동 진행 금지 항목> → "불가피한 Halt"로 명시 (사전결정으로 우회하지 않음. 없으면 이 줄 생략)
  - **Depends on**: -
- [ ] T2. ...

## Known Workarounds (있는 경우만)
- <증상 + 사유 + 추후 근본 해결 계획>

## Verification Strategy
- 빌드: `<명령>`
- 단위 테스트: `<명령>`
- 통합 테스트: `<있다면>`
- 수동 검증 (필요 시): `<절차>`

## Progress Log
<!-- implement-task가 2 task마다 갱신. 장시간 작업의 컨텍스트 누적 대비.
     항목이 10개 넘게 쌓이면 오래된 것을 한 줄로 묶어 압축(상세는 git에). 최근 2-3개는 상세 유지. -->
<!-- 예: -->
<!-- - T1-T2 완료 (커밋 abc123, def456): <핵심 변경 요약> -->

## Next Steps
<!-- 중간 체크포인트·세션 종료 시 implement-task가 갱신. 다음 작업자(또는 미래의 본인)가 재개하기 위한 안내. -->
<!-- 예: -->
<!-- - 권장 다음 액션: T7부터 implement-task 재개 -->
<!-- - 또는: 모든 task 완료, PR 생성 후 공식 /code-review 호출 -->
<!-- - Suggested skills: pjc:implement-task / 공식 /code-review / /security-review -->
<!-- 분할 plan의 첫 part(part1) 완료 시: "남은 분할 plan: <part2 경로> — pjc:implement-task로 별도 실행" 라인 포함(동기화: 상단 **다음 plan**:·## Deferred와 같은 경로). -->

## Open Questions
- [ ] Q1: <질문> (사용자 답변 후 plan 갱신)
```
