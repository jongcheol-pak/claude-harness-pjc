# Intent: pjc:plan Step 1 의 읽기 목록에 intent/ 를 더한다
Author: 사용자. Status: approved.

## Problem
원문 요청: *"Step 1 읽기 목록에 intent/ 추가하는 계획 세워줘"* — 앞선 조사에서 `intent/` 를 읽는 경로가 셋(두 리뷰어 · 다음 회차 이월 확인)인데 셋 다 승인 전후에만 발화하고, **계획 세션이 시작하는 시점에는 아무도 열지 않는다**는 것이 드러났다. 이월 확인 지시는 `references/intent-rules.md` 안에 있어 Step 5 에서야 로드되므로, 요구 확정(Step 2)이 이미 끝난 뒤에 미해소 `Open questions` 를 만난다. **지금 하는 이유**: 회차 42 가 `intent/` 규약을 깔았고 그 파일이 아직 하나도 없어, 이월 경로가 처음 쓰이기 전에 고치면 소급 대상이 생기지 않는다.

## Proposed outcome
`plan/SKILL.md` Step 1 의 읽기 목록이 다섯 항목이 되고 다섯째가 `intent/` 의 최근 파일을 지목한다. 계획 세션은 요구를 확정하기 **전에** 미해소 `Open questions` 를 보고, 이월 여부를 그 회차의 요구에 반영한다. 무효화되는 근거 문장(`intent-rules.md` 의 *"Step 1 이 읽으라고 지목하는 넷에 `intent/` 가 없어"*)은 남지 않는다.

## Affected users and systems
`pjc:plan` 을 발동하는 모든 프로젝트의 계획 세션. 걸리는 파일은 `plugins/pjc/skills/plan/SKILL.md` 와 `plugins/pjc/skills/plan/references/intent-rules.md` 둘이다. 두 리뷰어와 `session-context.ps1` 은 대상이 아니다 — 읽는 시점이 다르다.

## Constraints
`plan/SKILL.md` 는 게이트 상한 12,000 B 를 넘지 않는다(착수 10,785 · 추가 후 11,031 예상). **90% 임박선(10,800) 초과는 인터뷰에서 명시 수용했다** — 통지 3건 → 4건. 워킹트리 CRLF 유지. 읽기 지시의 정본은 한 곳(Step 1)뿐이어야 한다.

## Open questions
없음.
