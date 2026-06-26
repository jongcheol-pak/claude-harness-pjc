# plan.md — 훅 연동 점검·정합 수정

## 목표
PRD/스킬 연동 점검과 같은 방식(훅 트리거 "충족/미충족" 두 경로 시뮬레이션 + 스킬 문서가
기대하는 훅 동작 ↔ 실제 훅 동작 대조)으로 6개 hook을 점검해 발견한 결함을 수정한다.

## 배경 (발견 — 6개 hook 두 경로 점검)
- H1(MAJOR): require-plan-for-write trivial 기준(3줄)이 plan-feature "순수 값 치환 무제한"과 어긋나 거짓 차단.
- H2(MINOR): plan-feature "git checkout -- 차단" 기대가 block-destructive 실제(패턴 없음)와 불일치.

## 범위
scripts/require-plan-for-write.ps1, skills/plan-feature/SKILL.md. + 버전(plugin.json/README).
(나머지 5개 hook + 토글 메커니즘은 정합 확인 결과 무수정.)

## 승인 필요 사항
- [x] 2건 전부 수정 — 사용자 승인("2건 모두 수정")
- [x] 버전 업(1.60.3) + commit + GitHub 릴리즈 — 사용자 승인("1.60.3 + commit + 릴리즈")

## 작업 단계 (모두 검증 완료)
- [x] H1 (MAJOR) require-plan-for-write에 순수 값 치환 감지 추가 (정규화 비교, 줄 수 무관 통과)
- [x] H2 (MINOR) plan-feature git checkout 문구를 block-destructive 실제 동작에 맞게 정정

## 검증 방법·결과
- **합성 테스트 7/7 PASS** (scratchpad에서 plan 격리 — CWD/CLAUDE_PROJECT_DIR을 plan 없는 곳으로):
  - 순수값 px 5줄·hex 4줄 → 통과(0)
  - calc 도입·flex→grid·새 함수·식별자 변경 5줄 → 차단(2)
  - 일반 2줄 → 통과(0, 기존 룰 유지)
- block-destructive 패턴 목록에 git checkout 없음 직접 확인 → 문구 정정.

## 정합 확인 (무수정)
- 토글 메커니즘 6경로(harness-toggle SKILL ↔ .ps1 $known ↔ 각 disable 체크 ↔ block-destructive 토글불가) 완전 일치.
- check-utf8 1500라인 경고, impact-warn advisory, require-evidence(배열버그 기수정), QUICK 모드·additionalContext.

## Out of Scope
- git checkout --를 block-destructive에 추가 — 정당한 파일 복원까지 막는 거짓 차단 위험이라 비채택(문구 정정으로 갈음).
- require-evidence Stop advisory 전달 한계 — 직전 audit에서 "설치 환경 실측 권장"으로 남긴 별개 항목.

## Progress Log
- H1~H2 완료: 2개 파일 수정, 합성 테스트 7/7 PASS. notes.md 상세 기록.
