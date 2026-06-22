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

## F-6.5. 문서 갱신 (notes/README) + notes 아카이브

검증 통과 후, 완료된 작업을 문서에 반영한다. (공통 지침 CLAUDE.md의 "문서 관리"를 따르되, notes 처리는 다음을 명시한다.)

**notes 기록**: 이번 작업을 `notes.md`의 `## 최근 변경` 맨 위에 추가한다. plan.md는 다음 작업 때 교체되므로, notes 항목은 **plan.md 수준의 상세**(무엇을·왜·어떻게·검증 결과·변경 파일)로 적는다 — notes가 유일한 영구 기록이다.

**notes 아카이브 (1주일 경과분)**: `notes.md`에서 **1주일 지난 항목**을 `notes-archive/{YYYY-MM}.md`(월별 묶음)로 **이동**한다 (삭제 아님). 이동 시 `notes.md` 하단 `## 아카이브 인덱스`에 `- {YYYY-MM}.md: {주요 작업 키워드}`를 추가/갱신한다.
- 현재 날짜를 확인할 수 없으면 이동하지 않고 그대로 둔다 (잘못된 정리 방지).
- notes-archive 이동·인덱스 갱신은 승인 불필요(공통 지침 예외).

**과거 작업 참조 시**: 아카이브 전체를 정독하지 않는다. `notes.md`의 아카이브 인덱스로 월을 특정하거나 `grep notes-archive/`로 파일을 특정한 뒤, **그 파일만** 읽는다.

**민감 정보**: notes·archive·README 어디에도 실제 IP·계정·비밀번호·토큰을 적지 않는다 (절대 규칙 6-1). 일반 표현 또는 환경변수 이름만 기록.

**위키 반영 능동 확인 (llm-wiki 사용 중 + 프로젝트 등록 시)**: 최종 완료 보고 시, 이번 작업에 **위키에 남길 내용이 있으면 사용자에게 능동적으로 묻는다** (Next Steps 목록에 한 줄로 묻어두지 말 것). 묻는 조건은 다음 중 하나라도 해당할 때:
- 기능·구현·동작이 바뀌어 feature 페이지 갱신이 필요하다.
- 다른 프로젝트에도 적용될 **재사용 가능한 개선 교훈**이 있다 (llm-wiki 절차 B-2 2-1의 patterns 추출 후보).

질문 형식 예: *"이번 작업에 위키에 반영할 내용이 있습니다: [한 줄 요약 — 무엇을/어떤 교훈]. 별도 위키 세션에서 `pjc:llm-wiki` 절차 B로 반영할까요?"* 사용자가 동의하면 별도 세션에서 진행한다 (구현 세션은 위키를 직접 수정하지 않음 — read-only 원칙).

**단, 묻지 않는 경우**: 문서·설정 변경(Type A)이나 trivial 단일 수정처럼 위키에 남길 가치가 없는 작업은 묻지 않는다 (질문 남발 방지). 위키 반영 가치가 명확할 때만 능동 질문한다.

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
