# Intent: 분할이 만든 비계를 예산에서 빼고, 예산 처리를 사용자에게 넘기지 않는다
Author: 사용자. Status: approved.

## Problem

`30_knowledge/patterns/verification-asset-self-check.md` 가 5,715/5,000자로 초과 WARN 을 내는데 `--auto-split --dry-run` 은 **수행 대상 없음**을 낸다. 실측 구성은 정본 포인터 줄 13개 2,579자 + `## 하위 문서` 목록 2,109자 + 실제 내용 1,027자 — **82%가 분할이 만들어낸 비계**다. 이 페이지는 이미 하위 13개로 다 내보내 본문이 전부 포인터 스텁이라, **더 나눌수록 비계가 늘어 예산이 더 초과된다**. 그래서 신호는 영구히 남고 세션도 처방을 못 내 사용자 몫으로 넘어간다.

원인은 둘이다. ① 예산이 **산문 비대**를 재는 자인데 비계를 함께 센다 ② auto-split 이 남기는 정본 포인터가 약 200자인데 옮긴 본문이 127~314자인 절이 8개였다 — **본문보다 포인터가 커서 옮길수록 파일이 커졌고**, 그래서 13개까지 쪼개졌다.

같은 병이 vault 에 더 있다(실측): 이 repo 의 위키 `conventions.md` 10,892자 중 **95%가 비계**(예산 12,000 근접), `40_guides/ui-ux/help-doc-writing.md` 2,873자 중 80%.

사용자 원문 요청: *"모든 파일 예산은 자동으로 직접 분할할 때가 되면 해줘. 사용자에게 예산이 얼마나 남았는지 알릴 필요 없음."*

## Proposed outcome

- 예산 판정이 **정본 포인터 줄과 `## 하위 문서` 목록을 뺀 유효 문자 수**로 이뤄진다(guide 의 코드 펜스 제외와 같은 축).
- auto-split 이 **옮겨도 줄지 않는 절**(본문이 남길 포인터보다 작거나 같은 절)을 옮기지 않는다.
- 예산 처방에 「사람이 정리한다」로 남은 자리가 없어진다 — 전 타입이 자동 경로 또는 세션 처방을 갖는다.
- 예산 수치(`N/M자`·여유·%)가 사용자 보고에 나가지 않는다.
- `verification-asset-self-check` 의 하위 13개가 본문으로 복원되고 그 파일들이 삭제된다.

## Affected users and systems

`plugins/pjc/skills/llm-wiki/scripts/lint.py`(예산 판정·분할 가드) · `references/wiki-schema.md`·`references/wiki-ops-rules.md`(3중 동기화의 나머지 둘) · `evals/lint-cases.json`+픽스처(골든) · LLM WIKI vault 의 `30_knowledge/patterns/verification-asset-self-check*.md` 와 `index.md`.

## Constraints

- **3중 동기화**: 예산 상수·판정 방식은 `wiki-ops-rules.md` 예산표 · `wiki-schema.md` §3~§4 · `lint.py` 상수가 함께 가고 `evals/check_consistency.py` 가 대조한다.
- 예산 **숫자**(5000·12000 …)는 바꾸지 않는다 — 바꾸는 것은 **재는 방식**이다.
- lint 의 WARN/INFO 출력 자체는 없애지 않는다 — 그것은 세션의 입력이다(`wiki-ops-rules.md` 「신호 층위」). 억제 대상은 **세션 → 사용자** 보고다.
- vault 병합은 1건(`verification-asset-self-check`)으로 한정한다 — `conventions.md` 는 병합하면 10,447자라 곧 다시 발동해 되돌릴 이유가 없다(사용자 판정).

## Open questions

없음.
