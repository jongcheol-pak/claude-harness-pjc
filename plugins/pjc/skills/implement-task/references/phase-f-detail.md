# Phase F (Finalize) — 상세 절차

모든 task 완료 후 plan 전체 통합 검증.

## 진입 조건

| Plan 구성 | Phase F |
|---|---|
| 1 task + Type A만 | **생략** (간단 보고만) |
| 1 task + Type B | F-1, F-2, F-6만 (F-7 Opus 생략) |
| 2+ tasks 또는 Type C/D 포함 | **전체 (F-1~F-7)** |

## F-1. plan Goal 재확인 (자체 검증)

- plan.md의 `## Goal` 문장을 다시 읽고, 누적된 diff 전체가 그것을 충족하는지 자문
- Goal에 있는 단어/개념마다 diff 어디에서 충족되는지 지목
- 미충족 발견 → 추가 task로 보강하거나 follow-up 등록

## F-2. 전체 빌드 + 전체 테스트 (per-task 아닌 전체)

- **빌드 중복 제거**: 마지막 task의 V-1 빌드가 성공했고 그 이후 **코드 변경이 전혀 없으면** (commit만 했고 추가 수정 없음) 전체 빌드를 **skip**한다. 이미 최신 빌드 상태이므로 재빌드는 무의미.
  - 단 마지막 task 이후 어떤 파일이라도 수정했다면 빌드 다시 실행.
  - 확신이 안 서면 빌드 실행 (안전 우선).
- AGENTS.md의 test 명령 실행. 전체 통과 수 기록. **(테스트는 항상 전체 1회 실행 — 누적 회귀 최종 확인)**
- per-task에서 통과했던 테스트가 누적 변경 후에도 여전히 통과하는지 확인.

## F-3. Impact Analysis 회귀 점검 (자체 검증)

- plan.md `## Impact Analysis`의 각 영역에 대해
  - 실제 처리되었는지 grep으로 재확인
  - 명시되었으나 흔적이 없으면 사유 확인 또는 follow-up 등록

## F-4. Follow-ups 완전성 확인

- 모든 commit 메시지에서 "follow-up", "TODO", "MINOR" 언급된 사항이 plan.md `## Follow-ups`에 기록되었는지
- 누락 시 plan.md 갱신

## F-5. Risks & Unknowns 실현 검토

- plan.md `## Risks & Unknowns`의 각 위험이 실제 발생했는지
- 완화책이 작동했는지
- 새로 발견된 위험은 follow-up에 등록

## F-6. 자기 정직성 최종 체크

- [ ] plan의 모든 acceptance가 diff에서 충족됨을 지목할 수 있는가
- [ ] 도중에 약화·축소한 acceptance가 있는가
- [ ] 빌드/테스트 출력을 직접 봤는가 (commit 메시지만 의존하지 않음)
- [ ] "거의 동작함" 같은 모호한 표현으로 마무리하지 않았는가

F-1 ~ F-6 중 어느 하나라도 결함 발견 → **추가 task 등록 후 Phase P 재진입** 또는 **사용자 보고 (Halt)**.

## F-7. plan-completion-reviewer subagent (필수)

위 자체 검증 통과 후 **`plan-completion-reviewer` subagent에 적대적 검토 위임.** 자체 검토만으로 마무리 금지.

호출 시 전달:
- plan.md 경로
- BASE_SHA (implement-task 시작 전 커밋)
- HEAD_SHA (마지막 task 완료 후 커밋)
- AGENTS.md 위치

결과 처리:
- **BLOCKER** 있음 → 추가 task 등록 후 Phase P 재진입 (이슈 0까지, 최대 3회)
- **MAJOR** 있음 → 동일 (또는 사용자 보고)
- **MINOR** 있음 → plan.md follow-up에 기록하고 진행
- **재호출 3회 연속 동일 BLOCKER** → Halt → 사용자에게 보고
