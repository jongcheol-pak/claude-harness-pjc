# Intent: 분할한 문서가 실제로 읽히게 하고, 남은 대기 둘을 비운다
Author: 사용자(H1·H2 두 세션 분담). Status: approved.

## Problem
문서가 커지면 분할하는데, **분할본은 주입·지목 밖으로 나가 다음 세션이 읽지 않는다** — `AGENTS.md`(9,991 B)는 매 세션 전문 주입되지만 그 분할본 `docs/harness-conventions.md`(75,797 B · 22절)는 포인터 12개로만 닿고 그중 2개는 절 이름조차 없다. Deferred 종결 대장 223건도 `pjc:plan` Step 1 이 지목하지 않아 이미 기각·보류한 것을 다음 회차가 모른다. 같은 축의 결함이 둘 더 있다 — 스킬 `description` 상한 1,024자에 997자(여유 27)까지 찬 스킬이 있는데 **예산 축이 파일 크기만 재고 frontmatter 필드는 안 보고**, Deferred 항목 상한 600 B 는 문면만 있고 재는 축이 없어 **현행 2항목이 1,175·1,160 B 로 2배까지 자랐다**. 그리고 대장 두 곳(Deferred 대기 2 · `skill-feedback` 4)이 아직 비지 않았다. 별개로 사용자가 **문서 예산을 자신에게 알리지 말 것**, **성능 하락·불필요한 도구 사용·`Invalid tool parameters` 오류를 점검할 것**을 함께 요청했다.

## Proposed outcome
분할본과 종결 대장이 **기계 또는 지목으로 다음 세션에 닿는다.** 재지 못하던 두 상한(`description` 길이 · 대장 항목 바이트)이 축으로 재어진다. `AGENTS.md` 「Conventions」 14항목이 경계표로 전건 판정되고, 경계표가 남긴 세 공백(포인터 허용 범위 · 「함정」을 레포/위키로 가르는 축 · 양쪽에 둘 만한 것은 기계가 재는 쪽)이 메워진다. 문서 예산 **통지**는 사용자에게 보고되지 않고 세션이 자체 처리한다. hook 비용이 실측돼 기록되고, `Invalid tool parameters` 가 다음에 뜨면 어느 도구·어느 인자였는지 로그로 읽을 수 있다. Deferred 대기와 `skill-feedback` 에 등재할 항목이 없거나, 잔여마다 「왜 못 닫았는가」가 적혀 있다.

## Affected users and systems
하니스 레포 전체(`AGENTS.md`·`docs/harness-conventions.md`·`plugins/pjc/skills/**`·`evals/**`·`scripts/session-context.ps1`·`scripts/hook-event-log.ps1`)와 위키 vault(`conventions.md`·두 큐). 읽는 쪽은 이후 모든 pjc 세션이다.

## Constraints
분할 자체를 되돌리지 않는다 — 주입 상한(16 KB)이 분할의 이유이고 그것은 유효하다. 규칙을 약화시키지 않는다(회차 56 리뷰가 잡은 실패). 대장·큐 파일은 H1 만 편집한다(커밋 삼킴 3회 재현 방지). Anthropic 공식 권장을 그대로 옮기지 않고 **우리가 이미 더 엄격한 축은 그대로 둔다**. **한 회차에 담기지 않으면 회차를 나눈다** — 회차 55·56 이 이보다 좁은 범위에서도 여력 부족으로 멈췄다.

## Open questions
없음 — `Invalid tool parameters` 의 재현 조건은 사용자가 「다른 프로젝트 세션에서 봤다」로 답했고, 이번 요구는 **원인 규명이 아니라 관측 장치**까지다. `neighborhood-walk-rpg` 메모리 3건의 처분(레포 소멸)은 2026-09-11 사용자 결정으로 **「그대로 둔다」** 로 확정됐다 — 대장에 사실만 적고 지우지 않는다.
