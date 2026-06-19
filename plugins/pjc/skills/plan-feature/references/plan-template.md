# plan.md Template

## 위치 결정 가이드

| 프로젝트 규모 | 권장 위치 |
|---|---|
| 작은 프로젝트, 단일 작업 | `<repo>/plan.md` (덮어쓰기 방식) |
| 큰 프로젝트, 여러 plan 누적 | `<repo>/docs/plans/<YYYY-MM-DD>-<slug>.md` |

AGENTS.md에 `Plan Location: <plan.md | docs/plans/>`로 명시되어 있으면 그것을 따른다.

## 작성 시 주의 — 민감 정보

plan.md는 **git에 commit되어 영구 보존**되며, PreCompact hook이 스냅샷도 백업한다.
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

## Goal
<한 문장 — 사용자 관점>

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
     사용자가 "이번엔 빼고 다음에 하자"고 한 것은 Out of Scope가 아니라 반드시 여기로. -->
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
     큰 묶음 표시는 주석으로만: 예) T1~T3 (데이터 계층) -->
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
    - <발생 가능한 멈춤 시나리오> → <plan의 어느 항목에서 해결됨>
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
<!-- implement-task가 2 task마다 갱신. 장시간 작업의 컨텍스트 누적 대비. -->
<!-- 예: -->
<!-- - T1-T2 완료 (커밋 abc123, def456): <핵심 변경 요약> -->

## Next Steps
<!-- 중간 체크포인트·세션 종료 시 implement-task가 갱신. 다음 작업자(또는 미래의 본인)가 재개하기 위한 안내. -->
<!-- 예: -->
<!-- - 권장 다음 액션: T7부터 implement-task 재개 -->
<!-- - 또는: 모든 task 완료, PR 생성 후 공식 /code-review 호출 -->
<!-- - Suggested skills: pjc:implement-task / 공식 /code-review / /security-review -->

## Open Questions
- [ ] Q1: <질문> (사용자 답변 후 plan 갱신)
```
