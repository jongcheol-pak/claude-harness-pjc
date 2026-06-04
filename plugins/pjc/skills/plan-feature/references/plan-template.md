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

## Goal
<한 문장 — 사용자 관점>

## Out of Scope
- <명시적으로 안 함>

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
