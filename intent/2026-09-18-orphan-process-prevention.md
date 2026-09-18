# Intent: 골든·eval 러너의 고아 프로세스 방지
Author: 사용자. Status: approved.

## Problem

사용자 요청 원문: *"위키/하니스 스킬 사용중 고아 프로세스가 발생하지 않도록 종료를 하고 있는지 검토해줘"* → 검토 결과 3건의 갭이 확인되자 *"①②③ 다 고치는 계획 세워줘"*. 실사용 hook 경로는 `session-end-cleanup-lib.ps1` 이 `more.com`·`find.exe` 를 회수하지만, **골든 러너가 띄우는 자식 pwsh 와 python 러너의 subprocess 는 어느 회수에도 걸리지 않는다** — 코디네이터가 도구 타임아웃·크래시로 죽으면 자식이 그대로 남고, 회수 대상 이름 목록에 없어 SessionStart·SessionEnd 회수가 걷지 않는다. 지금 하는 이유는 골든 러너가 매 회차 검증에서 돌고 실측 소요(450~930초)가 Bash 도구 10분 캡 경계에 있어 강제 종료 경로가 상시 열려 있기 때문이다.

## Proposed outcome

코디네이터가 어떻게 죽든(Ctrl+C · 도구 타임아웃 · 크래시) 자식 pwsh 가 스스로 종료하고, python 러너·검사기의 모든 `subprocess` 호출이 상한 시간 안에 끝나거나 실패로 판정된다.

## Affected users and systems

하니스 레포에서 검증을 돌리는 세션. 걸리는 자산: `plugins/pjc/hooks/evals/` 의 코디네이터·자식 러너·공용 헬퍼, `plugins/pjc/evals/` 의 골든 러너와 검사기 2종, `llm-wiki`·`record-project-fact` 의 eval 러너.

## Constraints

- 골든 923케이스의 판정·케이스 수를 바꾸지 않는다(기준선 불변).
- `run-scenario.ps1` 은 코디네이터 없이 직접 실행도 가능해야 한다 — 감시는 선택적이다.
- 안전 임계 hook 4종의 차단 동작은 건드리지 않는다.

## Open questions

없음.
