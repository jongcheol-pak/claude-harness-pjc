# Intent: 위키 쓰기 세션의 고정 로드를 조건부로 바꾼다
Author: 사용자. Status: approved.

## Problem

위키 쓰기 세션은 절차 하나를 수행하려고 `SKILL.md`(9,032) + `wiki-ops-rules.md`(17,983) + `procedures-content.md`(29,491) = **56,506자**를 올린다. 그중 `wiki-ops-rules.md`는 `procedures-content.md:5`가 *"쓰기 세션은 반드시 읽어야 한다"*로 **전량 Read를 무조건 강제**해, C·D처럼 예산 처방도 파일 생성도 없는 절차까지 예산 신호 4,119자와 동시 실행 lock 2,259자를 진다. 사용자 요청: *"procedures-content.md 5행이 3파일 전량 로드를 강제하는 구조를 조건부로 바꾼다."* 지금 하는 이유는 1·2회차가 각각 hook 신호와 convention 분할 처방을 걷어 이 파일이 실제 로드 비용의 최대 잔량으로 남았기 때문이다.

## Proposed outcome

쓰기 절차가 `wiki-ops-rules.md`에서 **자기에게 걸리는 절만** 읽는다 — `SKILL.md`의 라우팅 표가 절차→절을 정하고, 기계 검사가 그 표의 절 이름이 실재하는지 잰다. 개정할 때만 필요한 근거 서술은 `wiki-ops-rationale.md`로 갈라져 실행 경로에서 빠진다. `lookup-rules.md` K 2의 `confidence` 해설 341자도 없어진다.

## Affected users and systems

위키 쓰기 세션(절차 A~F·H·I·J·L·M)과 그것을 여는 사용자. 걸리는 것은 `llm-wiki` 스킬 번들의 `SKILL.md`·`references/wiki-ops-rules.md`·`procedures-content.md`·`procedures-ops.md`·`lookup-rules.md`, 정합 검사기 `evals/check_consistency.py`, 그리고 `docs/harness-conventions.md`의 「조건부 참조 문서 크기 임계」 표다.

## Constraints

규칙 본문은 한 자도 잃지 않는다 — 옮기거나 가리킬 뿐이고 폐기는 하지 않는다. `lookup-rules.md`의 `confidence` **필드 자체는 유지**하며 419개 vault 페이지 소급은 하지 않는다. 절 이름이 바뀌면 라우팅 표가 조용히 낡으므로 기계 대조를 함께 둔다.

## Open questions

없음.
