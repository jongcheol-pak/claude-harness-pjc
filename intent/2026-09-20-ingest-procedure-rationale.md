# Intent: ingest 절차 본문에서 근거 서술을 가른다
Author: 사용자. Status: approved.

## Problem

`procedures-content.md`(29,524자)의 절차 B(Ingest)가 12,804자이고 그중 **B-2 갱신 하나가 7,659자**로 파일 최대 블록이다. ingest 는 최빈 쓰기 절차라 이 블록의 실효 비용이 가장 크다. B-2 본문에는 *왜 그렇게 정했는가·어떤 실해가 있었는가*가 절차 지시와 섞여 있어, **절차를 수행하기만 하는 세션이 개정할 때만 필요한 서술을 매번 읽는다** — 표본 실측으로 0-0 은 675자 중 358자(53%), 「하위 문서 frontmatter」는 584자 중 404자(69%)가 근거다.

지금 하는 이유는 3회차가 규칙 문서(`wiki-ops-rules.md`)에 같은 수단을 적용해 −24% 를 실증했고, 그 회차가 B-2 를 `[다음 회차]` 로 남겼기 때문이다(vault `pending.md:49` `[DECISION]` 보류 항목).

## Proposed outcome

B-2 의 근거·실해 기록·기각한 대안이 신규 `references/procedures-rationale.md` 로 내려가고, 절차 본문에는 **무엇을 언제 어떻게 한다**만 남는다. ingest 세션이 읽는 B 블록이 줄고, 절차를 **고치는** 세션만 근거 파일을 연다. 수령처는 `procedures-content.md` 전 절차의 근거를 받을 수 있게 설계하되 이번 회차는 B-2 절만 채운다.

함께 확정되는 것 둘 — ⓐ `wiki-ops-rules.md` ≤12,000(3회차 G1)은 **폐기**한다: 그 파일은 `BUDGET_EXEMPT_PREFIX` 로 예산 표 밖이고 「조건부 참조 문서 크기 임계」 표에도 행이 없어 **재산정할 상한이 존재하지 않으며**, 라우팅 이후 파일 크기는 실로드의 대리 지표가 아니다. 비용의 정본은 `--route-report` 의 절차별 합계다. ⓑ `### J.` 분리는 **기각**한다: 어느 절차의 실로드도 줄이지 않는다.

## Affected users and systems

위키 ingest 세션(절차 B)과 그것을 여는 사용자. 걸리는 것은 `llm-wiki` 번들의 `references/procedures-content.md`·신규 `references/procedures-rationale.md`, 정합 검사기 `evals/check_consistency.py`(축 ⑪ 스캔 제외 목록).

## Constraints

- **절차 본문은 한 자도 잃지 않는다** — 옮기거나 가리킬 뿐이고 폐기는 하지 않는다.
- **B-2 하위 라벨(0·0-0·0-1·0-2·1·1-1·1-1a·1-1b·1-2·2·2-1·3·3-1·4)을 바꾸지 않는다** — 외부 **13곳**이 번호로 지목한다(`wiki-schema.md` 5곳 · `lint.py` 2곳 · `lint-rationale.md` 2곳 · `queue-rules.md` · `templates.md` · `debugging-rationale.md` · `check_consistency.py:402`). 재배치·병합·개번은 그 전부를 깨뜨린다.
- 단계 구조를 바꾸지 않는다 — 이번 수단은 근거 분리 하나이고, 조건부 블록 분리(`queue-consume-rules.md` 선례)는 채택하지 않았다(Read 왕복 증가 · 축 ⑧ 커버리지 순감).

## Open questions

없음.
