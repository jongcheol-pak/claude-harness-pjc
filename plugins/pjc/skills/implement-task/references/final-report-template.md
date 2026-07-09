# 최종 보고 양식 (implement-task)

> SKILL.md "최종 보고" 섹션에서 참조. Phase F 통과 후(PRD 있으면 Phase G까지 통과 후) 아래 양식을 그대로 사용한다. 권한 경계(push·main 병합·태그·릴리즈·PR은 루프 권한 밖 — 별도 승인)는 SKILL.md 절대 규칙 12와 최종 보고 섹션 참조.

```markdown
## 🎉 모든 task 완료 + Phase F 통과 (+ Phase G 통과, PRD 있을 때)

**Plan**: <plan.md 경로>
**Tasks**: <N>/<TOTAL> 완료

**Summary of changes**
- T1 (Type <A/B/C/D>): <한 줄>
- ...

**Phase F 결과**
- F-2 전체 빌드: OK
- F-2 전체 테스트: <X/Y passed>
- F-7 plan-completion-reviewer: OK (또는 MINOR n개 follow-up 등록)

**Phase G 결과 (PRD 있을 때만 — G-1 충족표 전체 포함)**
- Must: <n>/<n> 충족 (기계 검증)
- 재루프: <0-2>회
- ⏳ 사용자 확인 필요 (HUMAN-VERIFY): <FR-x UI 체감, ...> ← 기계 검증 불가 항목, 직접 확인 부탁

**Plan 변경 내역** (구현 중 plan.md에 가해진 수정 — 사용자가 plan.md를 열지 않고도 계획이 잘 갱신됐는지 검수할 수 있게. 아래 4줄 중 변경이 하나도 없으면 전체를 "계획 원안대로 완료 (plan 수정 없음)" 1줄로 대체)
- 추가된 task: <구현 중 추가된 T<N> + 사유 (Phase G 갭, F 결함 보강, caller 연쇄 등) — 없으면 "없음">
- Files 추가: <P-3 caller 누락 발견 등으로 task Files에 추가된 파일 — 없으면 "없음">
- 신규 Deferred / Decisions: <구현 중 새로 생긴 항목 요약 (상세는 아래 Follow-ups) — 없으면 "없음">
- 체크박스: <N>/<N> [x] 확인

**Execution stats**
- Type 분포: A=<n>, B=<n>, C=<n>, D=<n>
- Prefilter PASS율 (Type B): <n/n>

**Follow-ups** (있으면)
- <항목 1>

**분할 plan 안내** (plan.md 상단에 `**다음 plan**:` 또는 `**이전 plan**:` 표식이 있을 때만)
- `**다음 plan**:` 있음 (이 plan = 분할 첫 part) → 아래 2줄을 **경로를 실제 값으로 치환해** 복붙 실행 가능한 형태로 명시한다 (사용자가 경로를 찾아 조립할 필요가 없어야 한다):
  - "**남은 분할 plan**: `<다음 plan 경로>` — 전체 기능의 후반부, 미실행"
  - "다음 part 진행: `/clear`로 컨텍스트를 비운 뒤(권장 — part2 품질 확보) 아래 한 줄을 붙여넣으세요: `<다음 plan 경로> 구현`"
- `**이전 plan**:`만 있음 (마지막 part) → "분할 plan 완료 (part1+part2 전체 구현됨)"을 안내한다.

**여기서 멈춥니다.** push·main 병합·태그·릴리즈·PR 등 외부로 나가는 작업은 자율 루프 권한 밖이라 각각 별도 승인이 필요합니다 — 필요하면 그 행위를 이름으로 적어 따로 여쭙겠습니다 (예: "이제 push·v1.x.x 릴리즈 할까요?"). 어떻게 진행할지 알려주세요.
```
