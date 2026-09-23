# Intent: 자율 루프 조기 정지에 Stop hook 계속 주입을 되살린다
Author: 사용자. Status: approved.

## Problem
원문 요청: *"2항 Stop hook 재도입도 계획 세워줘"* — Opus 5.5 가이드 대조 검토의 2항이다. `pjc:implement` 루프가 plan 에 미완 task 를 남긴 채 텍스트로만 turn 을 끝내는 정지는 지금 스킬 문면(`loop-stop-patterns.md`)만 막고, 문면에 없던 형태로 멈춘 실측이 있다. Opus 5.5 는 진행 보고로 turn 을 끝내는 경향이 늘었고, 가이드가 하네스 쪽 해법(체크리스트 미완 + 텍스트 종료 → 항목을 명시한 계속 메시지, 같은 작업 2~3회 상한)을 제시했다. v1.225.0 이 제거한 `require-evidence` 는 transcript·문면 정규식 판정으로 비대해졌고 fail-open 결함이 반복됐다.

## Proposed outcome
implement 가 발동한 세션에서 plan.md 에 미완 task 가 남아 있고 백그라운드 작업이 없을 때 turn 이 끝나면, 미완 항목을 명시한 계속 안내가 주입된다. 발동하지 않은 세션·미완 0·상한 도달에서는 아무것도 하지 않는다. 문면 방어와 hook 이 이중으로 선다.

## Affected users and systems
pjc 플러그인으로 implement 를 돌리는 모든 레포의 사용자. `plugins/pjc/hooks/hooks.json` · 새 hook 스크립트와 근거 문서 · hook 골든 · 하니스 등록부(자기보호 목록·validate) · `DESIGN.md` §5 E12 · implement 정지 문면 · README.

## Constraints
transcript 를 스캔하지 않는다. 문면(어휘) 판정을 하지 않는다. `exit 2` 를 쓰지 않는다 — 계속 주입은 `exit 0` + `additionalContext` 이고 「차단 hook 넷」 규약을 유지한다. 판정 불가는 침묵(fail-open). `.ps1` 은 UTF-8 BOM.

## Open questions
없음 — 인터뷰에서 활성 판정(발동 마커)·출력 형태(additionalContext)를 확정했다.
