# plan.md — 스킬 연동 점검·정합 수정

## 목표
PRD 점검과 같은 방식(연동 대상 "있을 때/없을 때" 두 경로 시뮬레이션 → 누락/오작동/식별기준 불일치)으로
다른 스킬 연동(sub-skill 호출 · llm-wiki 참조/갱신 · 스킬 핸드오프)을 점검해 발견한 결함을 수정한다.

## 배경 (발견 — 7종 연동 두 경로 점검)
- V1(MAJOR): add-viewmodel 적용 범위가 SKILL/implement-task("WinUI/WPF/MAUI")와 bootstrap 템플릿("WinUI 3 전용")에서 불일치.
- V2(MINOR): llm-wiki 참조(K)가 vault stale 시 경로 재확인 질문으로 코드 작업 흐름 교란.
- V3(MINOR): llm-wiki 갱신(B) "프로젝트 등록 여부" 판단 메커니즘 미명시.
- V4(MINOR): systematic→Phase V 핸드오프 시 plan.md 없을 때 검증 기준 모호.

## 범위
bootstrap-agents-md templates(wpf.md/android.md/multi-stack-example.md), llm-wiki/SKILL.md,
implement-task/references/phase-f-detail.md, pjc-systematic-debugging/SKILL.md. + 버전(plugin.json/README).

## 승인 필요 사항
- [x] 4건 전부 수정 — 사용자 승인("4건 전부 수정")
- [x] 버전 업(1.60.2) + commit + GitHub 릴리즈 — 사용자 승인("1.60.2 + commit + 릴리즈")

## 작업 단계 (모두 검증 완료)
- [x] V1 (MAJOR) add-viewmodel 범위를 WinUI/WPF/MAUI로 통일 (템플릿 3개·4곳, Android만 비대상)
- [x] V2 (MINOR) llm-wiki 절차 K — vault 미설정·stale 시 질문 없이 조용히 건너뛰기
- [x] V3 (MINOR) llm-wiki 갱신(B) — 등록 여부를 vault 20_projects/ read-only 확인으로 판단 (F-6.5·4-E)
- [x] V4 (MINOR) systematic 4-D — plan.md 없을 때 변경 파일+회귀 테스트를 acceptance 기준으로

## 검증 방법·결과
- grep으로 "add-viewmodel WinUI 3 전용" 잔존 점검 → 0건. 전 언급(SKILL·implement-task·evals·템플릿)이 WinUI/WPF/MAUI로 일관.
- 7종 연동 두 경로 재점검 — 누락/오작동/식별기준 불일치 해소.

## 정합 확인 (무수정)
- add-domain-service 범위(.NET/Kotlin), bootstrap 연동, plan-feature→implement-task 핸드오프, reviewer 과부하 대체.

## Out of Scope
- Kotlin add-domain-service 코드 예시 추가 — "적용 가능"만 명시돼 있고 C# 예시뿐이나, 개념 적용이라 이번 범위 아님.

## Progress Log
- V1~V4 완료: 6개 파일 수정, grep 검증으로 범위 표현 일관 확인. notes.md 상세 기록.
