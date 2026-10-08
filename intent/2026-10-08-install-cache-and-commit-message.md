# Intent: 규약은 레포 plugins/ 에서 읽고, 커밋 메시지는 셸 치환 없이 넘긴다
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「6·7번 문서 묶음 계획 세워줘」 — Deferred 대장 2026-09-20 등재 2건. ① 스킬 문면을 설치본 캐시에서 읽어 이미 폐지된 태그를 근거로 대장에 커밋했다(설치본은 마지막 `/plugin update` 시점에 고정). ② `git commit -m "…"` 본문의 백틱이 명령 치환돼 본문이 사라졌다 — 2026-09-19 의 처방이 레포 문면에 없어 2026-09-20 에 재발했다. 두 사고 모두 세션이 `docs/harness-conventions.md` 를 열지 않은 채 났다.

## Proposed outcome
매 세션 로드되는 `AGENTS.md` 의 설치본 줄과 「병행 세션의 커밋」 줄이 각각 「규약 조회는 레포 `plugins/` 를 읽는다」·「커밋 메시지는 `-m "$(cat <<'MSG' … MSG)"` 로 넘긴다」를 말하고, 근거·재발 이력은 `docs/harness-conventions.md` 에 있다. `pjc:implement` 「커밋」도 모든 레포에서 메시지를 셸 치환 없이 넘기게 한다. 대장 처방의 `-F` 는 커밋 hook 이 메시지를 읽지 않아 task 체크박스 검사가 꺼지므로 쓰지 않는다(계획 리뷰 실측). 대장의 2026-09-20 등재 2건이 빠진다.

## Affected users and systems
이 하니스 레포에서 작업하는 세션과 `pjc:implement` 를 쓰는 모든 레포의 워커. `AGENTS.md`·`docs/harness-conventions.md`·`implement/SKILL.md`·Deferred 대장.

## Constraints
`AGENTS.md` 는 한 구씩만 늘리고 하드 게이트(16,384B) 아래를 유지한다. 차단 hook 은 고치지 않는다.

Q: 두 규칙을 어디에 둔지 정해 주세요. 선택지: AGENTS.md 한 구 + conventions 근거 (권장) / conventions에만. A: AGENTS.md 한 구 + conventions 근거 (권장)
후보 라운드: pjc:implement 「커밋」에 커밋 메시지 규칙 1줄(후보 제시 때는 `git commit -F` 형태) — 포함(권장). A: 권장대로

## Open questions
없음
