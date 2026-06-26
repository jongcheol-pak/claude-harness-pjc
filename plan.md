# plan.md — PRD 식별 기준 일관화 (있을 때/없을 때 계획·검증 정합)

## 목표
PRD 파일이 있을 때와 없을 때 plan-feature(계획)·implement-task(검증)·reviewer가 PRD를
일관되게 식별·검증하도록, 식별 기준을 plan.md 상단 `**PRD**:` 줄 단일 진실원천으로 통일한다.
(plan-template 규약: PRD 없으면 줄 자체를 생략 → 줄 = "이 작업의 PRD" 식별 신호.)

## 배경 (발견 문제 — 두 경로)
- **경로 C(오작동)**: 줄 없는 일상 작업인데 무관한 docs/prd.md가 레포에 남아 있으면
  Phase G·plan-completion-reviewer가 끌어와 거짓 BLOCKER → 자율 루프 교란(엉뚱한 task/Halt).
- **경로 D(누락)**: PRD 만들고 `**PRD**:` 줄 누락 시 plan-reviewer 항목12가 침묵 → 커버리지 검토 누락.
  + 1.60.0 H3가 입력에만 fallback을 넣어 항목12 본문과 내부 불일치.

## 범위
implement-task/SKILL.md(Phase G 진입조건·진행 다이어그램), agents/plan-completion-reviewer.md,
agents/plan-reviewer.md(항목12·입력). + 버전(plugin.json/README).
(plan-feature Step 0.5/7.5는 이미 줄 기준이라 무수정.)

## 승인 필요 사항
- [x] 줄 단일 기준 + 누락 경고 — 사용자 승인("줄 단일 기준 + 누락 경고")
- [x] 버전 업(1.60.1) + commit + GitHub 릴리즈 — 사용자 승인("1.60.1 + commit + 릴리즈")

## 작업 단계 (모두 검증 완료)
- [x] T1. implement-task Phase G 진입조건 docs fallback 제거 → 줄 단일 기준 (+ 진행 다이어그램 일치)
- [x] T2. plan-completion-reviewer 진입·입력을 "`**PRD**:` 줄이 가리키는 PRD"로
- [x] T3. plan-reviewer 항목12를 12-a(대조)/12-b(줄 누락 경고)로 분리 + 입력 줄 일치

## 검증 방법·결과
- 4경로(A 줄있음 / B 줄없음·docs없음 / C 줄없음·무관docs / D 줄누락) 재시뮬레이션 → 모두 일관·안전.
- grep으로 "줄 없어도 docs 진입" fallback 잔존 점검 → 0건.
- plan-feature Step 0.5 L164 "`**PRD**:` 줄 = Phase G 진입 신호"와 정합 확인.

## Out of Scope
- docs/prds/ 다중 PRD 자동 선택 로직 — 줄이 정확한 경로를 가리키므로 불필요(줄 기준이면 다중도 명확).

## Progress Log
- T1~T3 완료: 3개 파일 수정, 4경로 재시뮬레이션 통과, fallback 잔존 0 확인. notes.md 상세 기록.
