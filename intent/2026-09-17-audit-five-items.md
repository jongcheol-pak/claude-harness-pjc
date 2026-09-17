# Intent: 감사 5건 — CC 네이티브 흡수분·Opus 5 가이드 위반·도달 불가 분기
Author: 사용자. Status: approved.

## Problem

사용자 요청 원문: *"claude code 최신 업데이트 기능을 확인해서 하니스 스킬에서 제거할 부분이 있는지 확인 / 삭제할 규칙이 있는지확인 / opus5가 알고 있는 내용이 규칙에 있는지 확인 / 동작하지 않는 기능이 있는지 확인 / 고아 항목이 있는지 확인 / 불필요하게 동작하는 기능이 있는지 확인 / 중복 기능이 있는지 확인."* 이어서 *"이대로 계획 세워줘"*.

감사 결과 검사기는 전부 green 이나 셋이 쌓였다 — ⓐ CC v2.1.274 가 네이티브로 흡수한 기능(`claude plugin eval`) ⓑ Opus 5 가이드가 명시적으로 빼라고 한 「서브에이전트로 자기 작업 검증」이 `DESIGN.md` §3-2 에 인용돼 있으면서 그대로 남아 있는 자기모순 ⓒ `MultiEdit` 이 모델에 제공되지 않는데 분기 20자리와 골든 1건이 그것을 계속 잰다. 지금 하는 이유는 ⓒ 가 골든을 헛돌리고 ⓑ 가 매 회차 비용을 물리기 때문이다.

## Proposed outcome

5건이 각각 「고쳤다 / 근거를 남겼다 / 다음 회차로 넘겼다」 중 하나로 닫히고, 그 판정 근거가 파일에 남는다. 전 검사기가 착수 시점과 같은 green 을 유지한다.

## Affected users and systems

이 하니스를 쓰는 본인과 GitHub 마켓플레이스 배포 대상. 걸리는 자산은 `skills/evals/README.md` · `agents/completion-reviewer.md` · `skills/DESIGN.md` · `skills/BUDGET.md` · `install.ps1` 과, MultiEdit 판정 조사 대상인 hook 스크립트 3종·골든 1건이다.

## Constraints

차단 hook 4종의 표면을 바꾸면 별도 승인과 골든 실증이 붙는다(`AGENTS.md` 「DO NOT」). 설치 캐시 실삭제는 실행 시점 재승인이다. eval 114KB 실제 이관과 `agents-md` 네이티브 활성화는 이번 범위 밖이다.

## Open questions

없음.
