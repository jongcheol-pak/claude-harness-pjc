# Intent: 계획 체인에 계획 간 기준 대조·판정 비용·위임 답 전제 명시
Author: 사용자 요청(외부 사례 조사 뒤 「1, 2, 3 모두 계획 세워줘」). Status: approved.

## Problem
외부 사례(superpowers subagent-driven-development · GSD verifier · Claude Code agent teams·cross-session messaging 문서)와 대조하니 chain-plan 에 셋이 없다 — 뒤 계획이 앞 계획의 「성공의 모습」을 깨뜨려도 재는 자리가 없고, 체인 보고의 코디네이터 판정에 「틀리면 무엇을 치르는가」가 없어 사용자가 무엇부터 검토할지 모르며, 위임·판정 답이 승인으로 통하는 것이 Karina `ask` 경로에 기대는데 그 전제가 적혀 있지 않다. 인터뷰 Q/A: 대조 수단은 처음 「새 agent」를 골랐으나 `DESIGN.md` 3-2 「리뷰어는 2종·호출 2곳」과 충돌해 「A. 워커 Goal에 앞 계획 기준 싣기」로 바꿨다 · 검증 명령은 다시 돌리지 않는다(「의미 대조만」) · 착수 때 이미 거짓인 앞 계획 기준은 보고에만 싣는다(「보고에만 싣기」. 계획 판단 — 뒤 계획이 그 기준에 의존하면 기존 남은 일 판정대로 체인을 멈춘다).

## Proposed outcome
plan N(≥2) 워커의 `plan.md` Goal 에 이 Run 앞 계획들의 성공의 모습이 행으로 실려 `completion-reviewer` 가 재고, 착수 때 이미 거짓인 것은 체인 보고의 남은 일로 간다. 체인 보고의 코디네이터 판정마다 틀리면 치를 것과 되돌리는 법이 붙는다. 워커 쪽 중계 규약에서 위임 답이 승인으로 통하는 전제와, Claude Code 기본 세션 간 메시지로 옮기면 그것이 깨진다는 제약을 찾을 수 있다.

## Affected users and systems
계획 체인을 돌리는 사용자(코디네이터 세션)와 체인 워커 · `plugins/pjc/skills/chain-plan/`(SKILL.md spec 서식 · references 의 report·continuation) · `plugins/pjc/skills/plan/references/relay-mode.md` · README.

## Constraints
`chain-plan/SKILL.md` 게이트 12,000자를 넘지 않는다 · 리뷰어 2종·호출 2곳(`DESIGN.md` 3-2)을 지킨다 · 코디네이터는 파일을 고치지 않는다 · 검증 명령 재실행 없음 · CRLF 규약.

## Open questions
없음
