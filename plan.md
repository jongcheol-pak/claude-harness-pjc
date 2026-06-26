# plan.md — PRD FR 라이프사이클 도입 (폐기·누적·중복·부활)

## 목표
"PRD가 역사적 기록이면 잘못된 정보(삭제된 기능)가 있을 때 검증 시 거짓 재구현이 발생할 수 있다"는
지적을 해결한다. PRD FR에 라이프사이클(active → REMOVED → 부활)을 도입하고, 검증 지점이 REMOVED FR을
제외하도록 한다. 추가로 누적 비대화·중복 FR·부활 처리를 일관 설계한다.

## 배경 (검증 문제)
하나의 PRD를 여러 plan으로 점진 구현 중 일부 FR 기능이 삭제되면, PRD의 그 FR이 "Must"로 남아
Phase G가 미충족으로 잡고 G-2가 사용자 확인 없이 재구현을 자동 시도 → 삭제된 기능을 되살리는 거짓 재작업.
(다른 작업의 무관 PRD는 v1.60.1로 차단됐으나, 같은 PRD 내 stale FR은 미처리였음.)

## 범위
prd-template.md, implement-task/SKILL.md(Phase G G-1), agents/plan-completion-reviewer.md,
agents/plan-reviewer.md(항목12). + 버전(plugin.json/README).

## 설계 결정 (사용자 승인)
- 부활: **새 FR ID로 추가**(옛 ID는 REMOVED 유지) — ID 안정성·이력 명확.
- REMOVED 표시: **표에 취소선 유지 → 쌓이면 `## 폐기 이력` 섹션 이동** — 맥락 유지 + 누적 시 정리.

## 승인 필요 사항
- [x] 4가지(폐기·누적·중복·부활) 라이프사이클 도입 — 사용자 승인("고쳐주고 추가로 확인")
- [x] 버전 업(1.61.0) + commit + GitHub 릴리즈 — 사용자 승인("1.61.0 + commit + 릴리즈")

## 작업 단계 (모두 검증 완료)
- [x] ① 폐기: prd-template 작성원칙5 + 3개 검증 지점(Phase G·plan-completion·plan-reviewer) REMOVED 제외
- [x] ② 누적: 작성원칙7 분할 + `## 폐기 이력` 섹션 템플릿 추가
- [x] ③ 중복: 작성원칙6 + plan-reviewer 항목12 중복 FR MINOR 경고
- [x] ④ 부활: 작성원칙8 새 ID + 옛 행 재도입 메모 + 사용자 승인

## 검증 방법·결과
- grep으로 REMOVED/폐기 이력/취소선 용어가 4개 파일에서 일관, 3개 검증 지점이 동일 제외 기준 사용 확인.
- 4가지 요구사항 모두 커버 확인. 빌드 대상 없는 문서 수정.

## Progress Log
- ①~④ 완료: 4개 파일 수정, grep 검증으로 용어·제외 기준 일관 확인. notes.md 상세 기록.
