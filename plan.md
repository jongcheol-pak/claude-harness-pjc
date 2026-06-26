# plan.md — 기능별 인덱스 한/영 양방향 검색 보장

## 목표
기능별 인덱스에서 **한글로 등록하면 영문도, 영문으로 등록하면 한글도** 함께 검색되도록 한/영 양방향 병기를
규칙·lint·데이터 3중으로 보장한다. (e)에서 한글→영문 병기는 마쳤고, 이번은 그 양방향화 + lint 강제 + 잔여 보정.

## 배경
- 직전 작업(llm-wiki 결함 a~e)이 미커밋 워킹트리 상태. **같은 '한/영 검색 정합' 주제라 이어서 진행, 최종 한 커밋(1.62.0)으로 묶는다.**
- 현재 규칙(A-3 1)은 "한글 기능명 + 영문 식별자 병기"로 **한글→영문 방향만** 명시. 영문→한글 방향은 미명시.
- lint은 병기 여부를 **기계 검사하지 않음** → 규칙을 빠뜨리면 누락이 조용히 쌓임((e) 결함의 발생 원인).
- **데이터 현황 조사(전수)**: 기능별 인덱스 feature 66행=한글·영문 모두 보유(완성), recipe 53행 중 **영문없음 2행**, 한글없음 0행. 즉 영문→한글 보정 대상은 0(규칙·lint로 미래 대비), 한글→영문 잔여 보정은 recipe 2행.

## 설계 결정 (추천 — 승인 게이트에서 조정 가능)
- **검사/보정 대상**: 기능별 인덱스 **전체 행(feature + recipe)**. "기능별 인덱스에서"라는 요청대로 recipe도 검색 대상이므로 포함.
- **판정 기준**: 행의 **첫 컬럼(기능명)**에 한글(`[가-힣]`) **AND** 영문(`[A-Za-z]`)이 모두 있어야 통과. 한쪽만이면 WARN. (플랫폼·프로젝트 컬럼은 늘 영문이라 첫 컬럼만 검사해야 의미 있음.)
- **severity = WARN**: 기존 "기능별 인덱스 누락"이 WARN이라 일관. 강제력 확보(INFO는 묻힘).
- **영문→한글 보정**: 현재 위반 0건이라 데이터 보정 없음. 규칙·lint만 양방향으로 만들어 앞으로 영문만 등록 시 잡히게 한다(자동 번역은 추측 금지 — 한글 키워드는 등록자가 수동 병기).
- **버전**: 직전 작업에서 1.61.0→1.62.0 완료. 같은 커밋이므로 추가 bump 없이 1.62.0 유지.

## Impact Analysis
- `lint.py`: 독립 CLI. 외부 호출은 `python lint.py "<vault>"` CLI뿐(시그니처 무관). 변경은 `main()`의 idx 처리 블록에 **별도 행 순회 검사 추가**. 기존 `feature_index_rows`(유일 호출자: main의 분할신호 검사 `feat_rows=feature_index_rows(itext)`)는 **시그니처·동작(int 반환) 불변 유지**(B1 회귀 차단 — 헬퍼 리팩토링 안 함). caller 코드 영향 없음.
- 규칙 문서(SKILL A-3 1·K-3, wiki-schema): 진실원천은 wiki-schema. 양방향 명문화를 세 곳에 일관 반영(H 자기규칙).
- 신규 lint 검사 항목 → SKILL F-1 + wiki-schema §7 둘 다 문서화(H-2 #5 규칙, 직전 M1 교훈).
- vault `index.md` recipe 2행: 표시 텍스트만 추가, wikilink 경로 불변 → 깨진 링크/동기화 무영향.
- **회귀 점검**: 새 검사는 첫 컬럼 한/영 판정만. 기존 검사(예산·신선도·고아·feature 동기화·분할 신호·sub-index 정합)와 독립.

## 작업 단계

### T1 — 규칙 양방향 명문화 (SKILL A-3 1·K-3 + wiki-schema)  [Type A]
- `SKILL.md` A-3 1: "한글 기능명 + 영문 식별자 병기"를 **"한글·영문을 양방향 병기 — 한글로 등록하든 영문으로 등록하든 첫 컬럼에 한글 키워드와 영문 키워드를 모두 적는다(한쪽만 적지 않음)"**로 강화. 예시 유지.
- `SKILL.md` K-3: 한/영 양방향 grep 문단에 "인덱스 행이 양방향 병기를 갖추는 것이 전제"임을 1줄 보강.
- `wiki-schema.md` **§3(태깅/링킹 — 검색 정합 규칙이므로 §3로 확정)**에 "기능별 인덱스 행은 한/영 양방향 병기 필수(한쪽만 금지)" 명문화. version 2.12→2.13.
- Acceptance: 세 곳에 "양방향 병기" 취지가 일관 기재되고 서로 모순 없음.
- Halt Forecast: 없음(문서).

### T2 — lint.py 기능별 인덱스 한/영 병기 검사  [Type C]
- **비파괴 방식 확정(B1)**: idx 처리 블록에 **별도 행 순회**를 추가한다. 기존 `feature_index_rows(itext)→int`는 시그니처·동작 불변(L209 분할신호 호출자 보존, 리팩토링 안 함). 새 검사는 같은 섹션 추출 정규식(`^##\s*기능별 인덱스\b...`)으로 섹션을 얻어 그 안의 `|`-시작 + `feature]]`/`recipe]]` 행만 순회.
- **첫 컬럼 추출 확정(M2)**: `line.lstrip().split("|")[1].strip()` — 첫 컬럼은 이후 컬럼 wikilink의 `\|` 이스케이프에 영향받지 않음(검증됨). 그 텍스트에 한글(`[가-힣]`)·영문(`[A-Za-z]`) 중 한쪽만 있으면 WARN("한/영 병기 누락: '{기능명}' — 양방향 검색 위해 한글·영문 모두 병기").
- `SKILL.md` F-1 + `wiki-schema.md` §7에 검사항목 16 문서화(H-2 #5 — 두 곳 동시).
- Acceptance: 보정 전 vault에 recipe 2행 WARN 발생, T3 보정 후 신규 한/영 WARN 0. 임시 vault로 한글만 행·영문만 행 각각 WARN(문구 일치), 양방향 행 통과 실증.
- Edge: index.md 없음/기능별 인덱스 섹션 없음 → 행 0(무발화). 첫 컬럼 공백·비정형 행(split 결과 부족) → skip(IndexError 방지).
- Halt Forecast: ① 한글 판정이 한자·기호 오인? → `[가-힣]` 완성형 음절만(한자·기호 제외)로 확정. ② 헬퍼 통합 분기? → 위 "비파괴 별도 순회"로 확정(헬퍼 불변), 추측 금지.

### T3 — vault index.md recipe 2행 영문 병기 보정  [Type A · 커밋 무관]
- 영문없음 recipe 2행(`작업 표시줄 변 부착 팝업 위치 계산`→taskbar-edge-popup-positioning, `단일 활성 창 + 무포커스 자식 팝업 체인`→popup-chain-unfocused-children)에 파일명 기반 영문 병기.
- `log.md`에 기록 1줄.
- Acceptance: recipe 영문없음 0. lint ERR 0/WARN 0. wikilink 경로 불변.
- Halt Forecast: 없음(데이터 2행).

### T4 — 문서 갱신  [Type A]
- `notes.md`: 1.62.0 항목에 한/영 양방향 강제 내용 추가(같은 버전·커밋). plugin.json·README 버전 변경 없음(1.62.0 유지).
- Acceptance: notes에 이번 작업 기록 존재.
- Halt Forecast: 없음.

## 검증 방법
1. `python plugins/pjc/skills/llm-wiki/scripts/lint.py "<vault>"` → (a~e 직후 baseline WARN 0 확인됨) T3 보정 후 신규 한/영 검사 WARN 0, ERR 0 유지.
2. 임시 테스트 vault: 한글만 행·영문만 행 각각 WARN 발화, 양방향 행은 통과 실증.
3. py_compile OK.
4. 규칙 3곳 + lint 검사항목(F-1·§7) 양방향 문구 일치 대조.

## 승인 필요 항목
- 본 plan(규칙+lint+데이터 수정) — 사용자가 "수정해줘"로 승인. commit/push는 (a~e)와 합쳐 별도 승인.

## Out of Scope
- 영문→한글 자동 번역 생성(추측 금지 — 한글 병기는 등록자 수동).
- feature 행 재보정((e)에서 완료, 위반 0).
- 기능별 인덱스 외 다른 섹션(프로젝트 테이블 등) 한/영 검사(이번은 기능별 인덱스만).

## Progress Log
- T1 완료 (Type A): SKILL A-3 1·K-3, wiki-schema §3 양방향 병기 명문화 + version 2.13.
- T2 완료 (Type C): lint.py 한/영 병기 검사(첫 컬럼 한글·영문 한쪽만 WARN, feature_index_rows 불변·별도 순회) + F-1/§7 #16. spec-compliance OK.
- T3 완료 (Type A·커밋무관): vault index.md recipe 2행 영문 병기 + log.md 기록. lint ERR 0/WARN 0.
- T4 완료 (Type A): notes.md 기록(버전 1.62.0 유지 — a~e와 같은 커밋).
- **검증 실증**: py_compile OK. 현재 vault 한/영 WARN 0(보정 후). 임시 vault로 한글만·영문만 각 WARN, 양방향 통과 실증.
- **결정**: 대상=기능별 인덱스 전체 행, severity=WARN — 사용자 승인.

## Next Steps
- 권장 다음 액션: a~e + 이번 작업을 합쳐 1.62.0 한 커밋 + GitHub 릴리즈(release-on-version-bump). vault(index.md·log.md)는 커밋 대상 아님.
