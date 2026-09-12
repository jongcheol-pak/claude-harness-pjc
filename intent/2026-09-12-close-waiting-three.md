# Intent: Deferred 대장 대기 3건을 전부 닫는다
Author: 사용자 (대화 중 확정). Status: approved.

## Problem

사용자 원문은 *"회차 64(낡음 탐지의 층 3 축소)를 이어서 진행해줘"* 였다. **그 전제가 사실이 아니었다** — 회차 64는 `15a7a0f1`(intent) → `24a57039`(T6 v1.275.0) → 완료 리뷰 2라운드로 **이미 완료·릴리즈**돼 있었고, 회차 65 plan이 `[다음 회차] 회차 64 복귀 — 이 plan이 덮어썼다`로 적은 것은 거짓 기록이었다(회차 65의 intent 커밋 `aacb7942`가 회차 64 종료 **뒤**다). 그 사실을 보고하자 사용자가 **Deferred 대장 대기 3건으로 계획**을 선택했다.

**대기 3건.** ⓐ `check-harness-consistency.py` 축 ①「포인터 도달성」의 정규식이 `` `경로.md`「절」 `` 처럼 **경로가 선행하는** 형태만 보므로, `아래/위/같은 문서 「절 이름」` 형태의 **자기 파일 내부 참조는 `pat`에도 `pat_any`에도 안 걸려 계수조차 되지 않는다** — 절을 지우는 회차가 그 축으로 재확인하면 끊긴 참조가 있어도 「0건」으로 통과한다(2026-09-11 실해: 「예상 0건」 통과 뒤 실제로는 5곳이 끊겨 있었다). ⓑ 위키 `wiki-schema.md` §2.8「항목 불변」의 예외가 「판정 명료화(내용 불변)」 하나뿐이라 **틀린 사실을 고칠 경로가 없다**(2026-09-12 실해: `decisions.md`의 2026-09-11 항목 4건이 회차 번호를 +2로 오기했는데 그 세션이 고치지 못하고 큐잉만 했다). ⓒ `destructive.json`의 `\.RemoveRange\(` 가 수신자를 가리지 않아 **PowerShell 리스트 조작을 EF Core 대량 삭제로 오차단**한다(2026-09-12 실해: `$lines.RemoveRange($idx, 2)` 가 차단돼 같은 편집을 다른 수단으로 다시 짰다).

지금 하는 이유: 셋 다 **실해가 관측된** 항목이고 편집면이 겹치지 않는다(검사기 · 위키 스킬 문서 · 차단 규칙). 대기 3건을 한 회차에 닫으면 대장이 0이 된다.

## Proposed outcome

- 축 ①이 **자기 파일 내부 참조**를 같은 축에서 잰다 — 앵커 모델을 **불릿 항목·표 셀·헤딩의 기계 생성 접두**까지 넓혀 정당한 참조가 오탐으로 red 되지 않게 하고, **양방향 부분 일치는 쓰지 않는다**(참조 문장 자신이 앵커가 되어 거짓 통과를 낸다 — 실측).
- 끊긴 자기 참조가 전수 수리된다 — 다른 파일에 있는 절은 **경로 동반 표기**로 바뀌어 기존 축 ①이 받고, 낡은 절 이름은 현행 이름으로 고쳐진다.
- `wiki-schema.md` §2.8에 **「사실 오기 정정」 예외**가 생긴다 — 조건 셋(사실 기술에 한정 · 정본 근거 필수 · 정정 이력 표기)과 **번복과의 갈림선**(*결정이 바뀐 것은 번복, 기록이 틀린 것은 정정*)을 함께 못박는다.
- `.RemoveRange()` 가 **DB 컨텍스트 단서를 동반할 때만** 차단된다 — 오탐 통과 케이스와 **차단 유지 음성 대조 케이스**가 둘 다 골든에 붙는다.
- 대장 `## 대기`가 **3 → 0** 이 되고 불변식이 선다.

## Affected users and systems

이 레포의 모든 코드 세션(커밋 직전 검사·차단 hook)과 위키 쓰기 세션이 대상이다. `check-harness-consistency.py` · `harness-consistency-rationale.md` · `evals/cases.json`+픽스처 · `destructive.json` · `destructive-rationale.md` · `hook-cases.json` · `wiki-schema.md` · `docs/harness-conventions.md` · `docs/golden-runner.md` · `plugins/pjc/skills/AGENTS-BOUNDARY.md` · `implement/SKILL.md` · `session-context-rationale-plan.md` · `lint-rationale.md` · 대장이 걸린다. **위키 vault 에는 `skill-feedback.md` 1줄 소비 외에 쓰지 않는다.**

## Constraints

- **vault 실물을 정정하지 않는다** — §2.8 예외는 만들되 `decisions.md`의 오기 4건은 다음 위키 세션이 새 규약으로 수행한다(사용자 확정). 이 레포는 코드 세션이고 vault 쓰기는 llm-wiki 절차가 정본이다.
- **양방향 부분 일치를 채택하지 않는다** — `golden-runner.md:15`의 굵은텍스트가 참조 문장 통째(80자 이내)라 그 안의 「실행·대기 절차 (정본)」이 자기 자신에 도달한 것으로 판정된다. 실제 헤딩은 `### 실행 절차 (정본)`이고 「실행·대기」는 낡은 이름 — **진짜 끊김을 삼킨다**.
- **`block-destructive` 는 `exit 2` 를 내는 넷 중 하나다** — `AGENTS.md`「DO NOT」 대상이고 **오탐 수정만 허용되며 골든 실증이 붙는다**. 차단 유지 음성 대조가 없으면 차단을 통째로 지운 것과 골든상 구분되지 않는다.
- **케이스 총계의 사본을 함께 갱신한다** — hook 골든은 러너 `$GoldenTotalBaseline` · `harness-conventions.md` 기준선 · `golden-runner.md` 실측 셋이고, evals 골든은 `harness-conventions.md`의 기준선 줄을 축 ⑰이 기계 대조한다.
- **`pat_any`(절 이름 없는 참조 748건)를 판정으로 올리지 않는다** — 이번에 여는 것은 자기 파일 내부 참조뿐이다.
- **축을 신설하지 않고 기존 축 ①에 합친다** — 재는 것이 같고, 별도 축은 기준선 문서 사본을 하나 더 만든다.

## Open questions

없음.
