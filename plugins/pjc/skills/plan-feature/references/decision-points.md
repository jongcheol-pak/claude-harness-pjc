# Decision Points — plan-feature Step 6 상세

## Type별 검토 범위

| Task Type | 검토 카테고리 |
|---|---|
| **A** (Doc/Config) | **skip** — Decision Points 적용 안 함 |
| **B** (Trivial Code) | 명명, 공개 범위, 에러 처리 (해당하는 1-2개만) |
| **C** (Normal Code) | 명명, 위치, 공개 범위, 에러 처리, 상태 관리, 테스트 전략 (5-6개) |
| **D** (Complex/Cross-cutting) | **11개 전체 검토** |

## 카테고리 11개

| 카테고리 | 결정 예시 |
|---|---|
| **명명** | 클래스/메서드/파일/네임스페이스 이름 |
| **위치** | 어느 레이어/프로젝트에 둘 것인가 |
| **공개 범위** | public/internal/private, 인터페이스 분리 |
| **에러 처리** | 예외 vs Result, 로깅 레벨, 재시도 |
| **상태 관리** | 보관 위치, 라이프사이클, 스레드 안전성 |
| **외부 계약** | API 시그니처, 이벤트 페이로드, 설정 키 |
| **마이그레이션** | 기존 데이터·설정 호환성 |
| **UI 동작** | 빈 상태, 로딩, 에러 표시, 단축키 |
| **성능 트레이드오프** | 메모리 vs 속도, 동기 vs 비동기 |
| **테스트 전략** | 단위 vs 통합, 모킹 범위 |
| **의존성** | 신규 라이브러리 vs 기존 재사용 |

## 기록 형식

각 결정은 Options/Chosen/Rationale/Source 형식:

```markdown
### D1. <결정 항목>
- **Options**: A) <대안1> / B) <대안2> / C) <대안3>
- **Chosen**: A
- **Rationale**: <왜 선택했는가>
- **Source**: AGENTS.md 또는 사용자 확인 또는 코드 확인 (파일:라인)
```

정보 부족으로 결정 불가능한 항목은 Open Questions로 모은다.
