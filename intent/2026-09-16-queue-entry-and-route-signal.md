# Intent: `[PROJECT-FACT]` 큐 착수 지점과 절 라우팅 실패 신호
Author: 사용자. Status: approved.

## Problem

원문 요청: *"PROJECT-FACT 큐 착수 지점 추가하는 계획 세워줘"* → *"약점 1,2 계획 세워"*.

**약점 1** — 코드 레포 계획 세션은 `lookup-rules.md` K 2 가 두 큐 파일을 참조 대상에서 제외해, `pjc:implement` 가 완료 시점에 기록한 `[PROJECT-FACT]` 함정을 **다음 계획 세션이 읽을 경로가 없다**. `[SKILL-IMPROVE]` 는 `pjc:plan` Step 1-6 이 유일 착수 지점을 갖고 `[DECISION]` 은 존재 보고가 열려 있는데 이 태그에만 그 장치가 없다. 지금 실제로 **43건이 잠겨 있다**.

**약점 2**(범위 밖으로 이동) — 「절 단위 읽기」가 전문 Read 로 폴백한 사실을 `plan.md` 의 Investigation Log 에만 남기는데 그 파일은 `.gitignore` 라 신호가 회차가 끝나면 사라진다. **이번 회차에서 들어냈다** — 해결 수단(6번째 큐 태그 신설)이 3라운드 연속 BLOCKER 를 냈고, 원인은 태그 집합의 개별 열거가 9~13파일에 흩어져 있는데 그 전수를 재는 기계 검사가 없다는 것이다. 다음 회차가 그 검사 축을 먼저 만든 뒤 착수한다.

**추가 요구(승인 시점)** — 인터뷰가 화면에 내는 `신뢰도: 80%` 라벨이 무엇에 대한 신뢰인지 보이지 않는다. 원문: *"인터뷰 중에 '신뢰도:80%' 이렇게 표시되는데 신뢰도 문구를 인터뷰 문구로 수정"*.

## Proposed outcome

계획 세션이 대상 프로젝트의 `[PROJECT-FACT]` 를 함정 후보로 읽어 task 의 `**함정**` 줄로 배분한다. 지금 잠겨 있는 43건이 위키 세션을 기다리지 않고 다음 계획에 닿는다. 인터뷰 출력 라벨은 **「인터뷰 확신도」**가 된다.

## Affected users and systems

pjc 하니스를 쓰는 모든 코드 레포 세션. 걸리는 자산은 `llm-wiki/references/lookup-rules.md`·`wiki-schema.md`, `skills/WIKI.md`, `plan/SKILL.md`, `skills/evals/check_wiki_circuit.py`, `docs/harness-conventions.md`.

## Constraints

큐 내용은 **함정 후보**로만 쓰고 위키 지식처럼 인용하지 않는다(K 2 의 취지 유지). 큐 라벨이 대소문자로 갈려 있어(`Maid` 27 / `maid` 9) 조회는 대소문자를 무시해야 한다. `pending.md` 가 42,630 B 라 전문 Read 가 아니라 `grep` 한정으로 읽는다. **새 큐 태그를 만들지 않는다.**

## Open questions

없음.
