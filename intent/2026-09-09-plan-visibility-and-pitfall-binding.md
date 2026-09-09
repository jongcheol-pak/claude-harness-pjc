# Intent: 계획 가시성 · plan.md 쓰기 실패 · 위키 함정 구속
Author: 사용자. Status: approved.

## Problem

원문 요청: *"하니스 스킬 검토 — 현재 하니스는 계획을 잘 세우고 계획대로 작업을 잘 하는게 최우선 목표임. (1) 계획 작성 완료후 계획 내용을 제대로 표시하지 않는 문제가 있는데 T1,T2 이렇게 계획을 작성 했으면 T1에서하는 작업, T2에서 하는작업 을 표시하도록 함. 너무 길게 설명할 필요 없고 요약해서 표시. (2) 계획을 세우고 plan.md파일에 작성할 때 'Error writing file' 오류가 발생하던데 확인해서 수정. (3) 위키에 기록해 놓은 함정을 절대 지키지 않음 작업중 '위키가 이미 기록해 둔 함정을 다시 밟았습니다' 문구가 너무 많이 나옴. 위키에 기록해 놓은 함정을 확인했으면 그대로 작업을 하면 안되는데 그대로 작업을 해서 여러번 작업을 하는 문제가 있음."*

후속 지적: *"너무 규약이 많아 지는거 같은지 읽고 스스로 판단해서는 못 하나?"*

셋 다 승인 판단과 실행 정확도를 직접 깎는다. ③은 대장에 실해가 2건(`deferred.md:15`·`:16`) 이미 등재돼 있고 매 회차 재관측된다. ②는 인접 실해가 1건(`:26` — `plan.md` EOL 혼재로 편집이 조용히 실패) 있다. **지금 하는 이유**: 하니스의 최우선 목표가 「계획을 잘 세우고 계획대로 실행」인데 세 결함이 전부 그 축 위에 있다.

## Proposed outcome

계획이 끝나면 T별 요약이 **화면에** 나와 사용자가 파일을 열지 않고 승인 판단을 한다. `plan.md` 쓰기 실패가 조용히 지나가지 않는다. 위키 함정이 조회 결과로만 남지 않고 **그것이 걸리는 task의 일부**로 실려, 실행 시점에 눈앞에 있다. 그리고 이 셋을 **문면 총량을 늘리지 않고** 달성한다 — 손댄 문서 6개의 합계 바이트가 착수 시점 이하다.

## Affected users and systems

이 하니스로 작업하는 본인. 걸리는 자산: `skills/plan/SKILL.md` · `skills/plan/references/plan-template.md` · `skills/plan/references/interview.md` · `skills/implement/SKILL.md` · `skills/WIKI.md` · `agents/plan-reviewer.md`. 검사기 4종(`check-harness-consistency` · `check_wiki_circuit` · `check-stale-refs` · `run-evals`)이 대조 대상이다.

## Constraints

hook 신설 없음(함정은 자유 서술이라 기계 판정이 오차단을 부른다). 규약 총량 증가 없음 — 처방은 「추가」가 아니라 「쓰이는 자리로 이동 + 제자리 감축」이다. `SKILL.md` 12,000 B 게이트를 넘지 않는다(착수 여유: plan 500 B · implement 71 B). 전면 재설계 없음.

## Open questions

없음.
