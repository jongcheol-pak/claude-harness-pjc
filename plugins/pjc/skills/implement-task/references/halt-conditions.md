# Halt Conditions — implement-task

자율 루프 중단 조건과 사용자 보고 양식.

## 중단 조건 표

다음 중 하나라도 해당하면 **즉시 정지하고 사용자에게 보고**한다.

| 카테고리 | 조건 |
|---|---|
| 계획 결함 | plan.md에 없는 결정 분기 발견 |
| 계획 결함 | plan.md의 가정이 실측과 불일치 |
| 계획 결함 | acceptance가 검증 불가능함이 드러남 |
| **계획 결함** | **Phase P-3에서 plan.md Files에 없는 호출자/구현체 발견 — plan에 없던 공개 시그니처 변경이 새로 필요하거나 여러 모듈(대략 5개 파일 이상)로 번지는 경우** (단순 내부 caller 갱신은 자율 처리) |
| 루프 실패 | 동일 task에서 checkpoint 복구 2회 |
| 루프 실패 | Review subagent가 동일 이슈(BLOCKER/MAJOR, RECURRING 태그 포함)를 3회 연속 지적 |
| 루프 실패 | 같은 task의 리뷰 지적(BLOCKER/MAJOR) 수정 사이클이 누적 5회 (매번 다른 지적이어도 — 무한 수정 루프 방지) |
| 루프 실패 | 빌드/테스트 5회 연속 실패, 원인 미상 |
| 범위 초과 | 변경이 plan.md에 없는 모듈로 번짐 |
| 파괴적 작업 | force push, history rewrite, 데이터·파일·대량 삭제(DB DROP/TRUNCATE·WHERE 없는 DELETE/UPDATE·스키마 삭제·migration reset, rm -rf 등 재귀·대량 또는 plan에 없는 파일/디렉터리 삭제, plan에 없는 대량 코드 삭제), 권한·보안 설정 변경. **history rewrite는 공유·push된 이력 대상** — 로컬 미push 작업 브랜치의 Phase D ③ pre-review 커밋 amend는 해당 없음(amend에 한정, 다른 항목으로 확대 해석 금지) |
| 외부 의존 | 새 라이브러리·외부 서비스·인증정보 도입 필요 |
| 외부 부작용 | 기존 외부 서비스로의 **비가역 부작용 호출**(운영 API 쓰기·이메일/알림/SMS 발송·결제·외부 상태 변경) — 신규 도입이 아니어도 plan에 명시·승인되지 않았으면 |
| 환경 의존 | 검증을 위한 실제 디바이스·환경 접근 필요 |
| 비용 폭증 | 한 task가 다른 task 평균 대비 현저히(대략 3배 이상) 많은 토큰·시간을 쓰거나, 빌드·수정 사이클을 과도하게(예: 10회 이상) 반복하고도 미완 |
| **Phase G Should 갭 (조건부 보고)** | Phase G 재검증에서 **Should FR 미충족**이 남으면 하드 Halt가 아니라 **사용자에게 보고 후 선택을 받는다**("지금 진행 A / follow-up 등록 B"). Must 갭은 자율 재루프(최대 2회)이고 Could 갭은 follow-up 등록만이라 정지 아님 — Should만 이 보고 게이트에 해당한다(정본 `phase-g-detail.md` G-2 표). 루프를 조용히 끝내지 말 것 |

> **재시도 카운터 영속화 (압축 생존, G5).** 위 '루프 실패' 행 카운터(동일 BLOCKER/MAJOR 3회·수정 사이클 누적 5회·checkpoint 복구 2회) **및 Phase 단위 재루프(Phase G 최대 2회·F-7 재진입 최대 3회)**의 영속화(대화 컨텍스트에만 두면 auto-compact·재개 시 리셋 → plan.md `## Retry Ledger`에 기록 후 이어 셈)는 **정본 `recovery.md`** 참조.

### 위임 경계 (사전승인 O / 항상 Halt) — 단일 정본

> SKILL 규칙 10(사전승인과의 관계)·규칙 12·Phase 0는 이 표를 정본으로 참조한다.

| 구분 | 항목 |
|---|---|
| **위임 O** (Phase 0 일괄 승인 — 그 지점에서 Halt 안 함) | 비파괴 패키지/라이브러리 의존성 추가·버전 변경 · 구조 변경(파일 분리·병합에 따른 **계획된 표적 파일 삭제·이동** 포함) · 비파괴 스키마 CREATE/ADD. (위 '외부 의존' 행 중 **비파괴 패키지/라이브러리 의존성 부분만** carve-out — 규칙 10의 "새 라이브러리·외부 서비스 도입" 불릿과 정합. **인증정보 필요 신규 외부 서비스는 carve-out 제외** — 사전승인돼도 아래 '항상 Halt'다.) |
| **항상 Halt** (위임 불가 — plan `## 사전 승인 항목`에 적혀 있어도) | 위 **'파괴적 작업' 행**(force push·history rewrite(공유·push된 이력 대상 — 로컬 미push 브랜치의 Phase D ③ amend 제외)·rm -rf 등 재귀/대량 또는 plan에 없는 삭제·DB DROP/TRUNCATE·WHERE 없는 DELETE/UPDATE·스키마 삭제·migration reset·권한/보안 변경) · 외부/비가역 git(push·main 병합·태그·릴리즈·PR — 규칙 12) · 인증정보 필요 신규 외부 서비스 · 돌발 중대 결정(규칙 11) |
| **조건부 Halt** | 위 **'외부 부작용' 행**(기존 외부 서비스로의 비가역 호출)은 **plan에 명시·승인되지 않았을 때만** Halt(사전 승인 철학과 정합 — '항상 Halt'로 바꾸지 않음) |

즉 '파괴적 작업' 행의 "파일/디렉터리 삭제"는 **rm -rf 등 재귀·대량 또는 plan에 없는 삭제**를 가리키고, plan 사전승인의 **계획된 표적 파일 삭제(구조 변경)는 위임 대상**이다.

## 컨텍스트 한계는 Halt 사유가 아니다 (압축 통과)

컨텍스트가 과밀해도 멈추거나 "새 세션에서 계속할까요?"라고 묻지 않는다 — **압축 통과 절차의 정본은 SKILL.md 컨텍스트 관리 규칙 4**: 현재 task를 Phase V/D까지 완료(중간 절단 금지) → plan.md에 상태 완전 기록(Progress Log + Next Steps + 다음 task 시작점) → 사용자 보고 없이 계속 → 압축 감지 시 첫 행동은 이 SKILL.md(implement-task) + plan.md + AGENTS.md 재읽기(요약 기억만으로 이어가지 않음). 실패가 아니라 품질 보존을 위한 정상 흐름이며 루프는 마지막 task까지 끊기지 않는다.

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
