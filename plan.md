# plan.md — 위키 recipe 귀속 빈틈 보강 (감사 ③)

## Goal
LLM WIKI의 `index.md`가 sub-index(`index-personal.md`/`index-work.md`)로 분할됐을 때, personal/work category가 없는 항목(recipe=cross-stack, 프로젝트 테이블)을 어느 sub-index에 귀속할지 미정의였던 **쓰기(귀속) 측 빈틈**을, ① §4에 "분할 대상=project feature 기능별 인덱스 행만, recipe·프로젝트 테이블은 index.md 본체 유지" 규약을 명문화하고 ② 쓰기 절차 B/C/D/I에 분할 귀속 처리를 개별 명시해 메운다.

## 배경 — 감사 ③ (split-mechanism-audit 메모리)
하니스 파일 분할 메커니즘 4개 중 ①PRD(1.66.1)·④plan.md 분할(1.66.2) 보강 완료. 이번은 **③ 위키 recipe 귀속**(MAJOR·남은 것 중 우선 1). 1.66.1 PRD 귀속 빈틈과 동형 — 읽기·검색·lint 전수성은 견고하나 쓰기(귀속) 절차가 빈틈.

3개 빈틈(explorer read-only 조사로 전수 확인):
- **F3(MAJOR)**: recipe는 `40_guides/recipes/{스택}/`에 스택 분류로 적재되고 frontmatter에 `category` 필드가 없다(wiki-schema L176~186) → §4 분할(category 자동 결정) 기준으로 recipe 기능별 인덱스 행을 어느 sub-index에 넣을지 미정의.
- **F1(MINOR)**: 쓰기 절차 B/C/D/I가 "index.md"만 적고 sub-index 처리 명시 누락. A/G/K는 이미 명시 보유(L116·296·389).
- **F5(MINOR~MAJOR)**: 프로젝트 테이블(`## 개인/업무 프로젝트`)의 분할 귀속도 §4 미규정.

## Investigation Log (직접 grep/Read + explorer 조사)
- `wiki-schema.md` version `2.18`(L3). §4 파일 예산 표(L249~263), 분할 규약은 L263 한 셀(긴 텍스트): "분할 상태에서는 모든 `index.md` 기능별 인덱스 갱신/제거/표기 지시가 해당 category sub-index에 적용 … 단 `## 미해결 질문`처럼 category로 분할되지 않는 섹션은 `index.md` 본체에 그대로 두고 거기서 닫는다." → recipe·프로젝트 테이블 예외가 빠져 있음.
- `wiki-schema.md` §2.6 recipe(L168~193): 위치 `40_guides/recipes/{스택}/`, frontmatter에 `category` 없음(`platform`/`related_projects`만).
- `llm-wiki/SKILL.md` 절차 A~K. **A/G/K(L116·296·389)는 sub-index 처리 명시 보유**(F1 가설 검증). **B/C/D/I 누락**:
  - B(ingest): L176(새 feature → 허브+`index.md` 기능별 인덱스 동기화)·L167(B-1a 폐기 표기 → `index.md` 기능별 인덱스) — 분할 시 sub-index 명시 없음.
  - C(삭제): L209(`index.md` 프로젝트 테이블 행 제거 + 기능별 인덱스에서 feature 제거) — 분할 시 sub-index 명시 없음.
  - D(상태 변경): L228(프로젝트 테이블 "상태" 열 갱신) — 프로젝트 테이블만, 기능별 인덱스 미언급.
  - I(가이드/레시피): L360(`index.md` "가이드/레시피" 섹션 링크 + recipe는 "기능별 인덱스"에도 등록) — 분할 시 처리 없음.
- lint §7-14/15(L342·343): 분할 신호·sub-index 목록 정합만 검사, recipe 귀속 정합은 미검사.

## 결정 (사용자 확정)
- **F3+F5 = index.md 본체에 남김.** 분할(sub-index) 대상은 **"project feature 기능별 인덱스 행"으로 한정**. recipe 기능별 인덱스 행(cross-stack, category 없음)·프로젝트 테이블(전체 조망용)은 personal/work로 안 나뉘므로 `index.md` 본체에 둔다(§4 `## 미해결 질문` 비분할 원칙의 연장). 새 분류(`index-guides.md` 등)를 만들지 않고 recipe frontmatter도 변경하지 않는다(cross-stack 철학·마이그레이션 회피).
- **F1 = 절차별 개별 명시.** B/C/D/I 각각에 분할 귀속을 한 마디씩 명시(A/G/K 개별 패턴과 대칭, 절차 단위로 읽을 때 바로 보여 실수 방지). 방향은 절차마다 다름: **B = sub-index**(project feature 기능별 인덱스), **C = 혼합**(기능별 인덱스 feature 제거=sub-index / 프로젝트 테이블 행 제거=본체), **D = 본체**(프로젝트 테이블 상태 열), **I = 본체**(recipe).
- **F3 lint = 명문화만 (이번 범위).** recipe 귀속의 lint 기계 검사는 추가하지 않는다 — recipe는 category가 없어 자동 식별이 까다롭고 분할은 드문 경로. §4 규약 + 절차 명시(사람·에이전트가 따르는 규칙)로 충분(pjc 최소·과한 기계화 회피). lint 추가는 영구 제외가 아니라 이번 제외(Deferred).
- **수정 대상 2파일 + 버전**: `wiki-schema.md`(§4 규약 기준 — T1 먼저) → `llm-wiki/SKILL.md`(절차가 §4 따름 — T2). 버전 patch 1.66.2 → 1.66.3.

## Impact Analysis (전수 확인)
- 수정 파일 **2개**(+버전 3파일), 전부 마크다운 지침 문서. 코드·시그니처·DI 영향 0. 위키 vault 자체는 미변경(운영 스킬 지침만).
- **상호 참조 정합**: T2 절차들이 T1 §4 규약("분할 대상=project feature 행, recipe·테이블 본체")을 따른다 → T1 먼저 확정. 절차 인용 표현(sub-index/본체)이 §4와 일치해야 함(역대조).
- **읽기 측 무손상**: A/G/K(읽기·등록)·G/K(검색)·lint §7-14/15는 이미 견고 → 무수정. 분할 자동 결정(project feature는 category로)도 불변.
- **신규 규약 일관성**: "recipe·프로젝트 테이블은 본체" 규칙이 §4(T1)·절차 I·C·D(T2)에서 동일 취지로 들어가야 함(드리프트 방지 — 역대조).
- 자동 생성·lock 파일 아님. wiki-schema 자체 `version`(2.18) + plugin.json/README(1.66.2) 양쪽 bump.

## Tasks
<!-- 전부 Type A(마크다운 지침 문서). Decision Points·Edge Cases는 Type A라 skip, 상호참조 정합만 Acceptance에 명시. -->

### T1 — wiki-schema.md §4: 분할 귀속 규약 명문화 + version bump  [Type A]
대상: `plugins/pjc/skills/llm-wiki/references/wiki-schema.md` (§4 L263 표 셀, version L3)
- **§4 분할 규약(L263)에 귀속 예외 명문화**: 현재 "모든 `index.md` 기능별 인덱스 지시가 sub-index에 적용 … 단 `## 미해결 질문`은 본체" 문장에, **"분할(sub-index) 대상은 project feature(20_projects, category 보유)의 기능별 인덱스 행으로 한정한다. recipe(`40_guides`, category 없는 cross-stack)의 기능별 인덱스 행과 프로젝트 테이블(`## 개인/업무 프로젝트`)은 personal/work로 분할되지 않으므로 `index.md` 본체에 남긴다(`## 미해결 질문`과 같은 비분할 취급). recipe는 새 분류를 만들지 않고 본체 기능별 인덱스·`## 가이드/레시피` 섹션에서 관리한다."** 를 추가.
- **기존 "모든/항상" 표현 한정 수정(m3)**: L263의 기존 "**모든** `index.md` 기능별 인덱스 갱신/제거/표기 지시가 … **항상** 그 sub-index에서 수행" 문구를 "**project feature 기능별 인덱스** 지시는 … sub-index에서 수행"으로 한정해, 신규 예외(recipe·테이블 본체)와의 "모든/항상 ↔ 예외" 내부 긴장을 제거한다(단순 append만 하지 않고 기존 절대 표현을 함께 조정).
- **이 귀속은 절차 규칙이며 lint 기계 검사 대상이 아님**을 한 마디 명시(F3 lint 미추가 결정 — 혼동 방지).
- **version**: `2.18` → `2.19` (L3).
- Edge cases(Type A): ⓐ §4 표 구조·다른 셀 불변(L263 셀 텍스트만 보강) ⓑ 기존 "category 자동 결정"(project feature) 문장과 모순 없음 ⓒ `## 미해결 질문` 비분할 예시와 같은 계열로 자연스럽게 연결.
- Halt Forecast: 없음.
- Acceptance:
  1. §4에 "분할 대상=project feature 기능별 인덱스 행 한정" 문구 존재.
  2. §4에 "recipe·프로젝트 테이블은 index.md 본체 유지(비분할)" 문구 존재.
  3. §4에 "recipe 귀속은 절차 규칙·lint 미검사" 한 마디 존재.
  4. 기존 "모든/항상" 절대 표현이 "project feature 기능별 인덱스"로 한정 수정됨(절대 표현 잔존 없음, m3).
  5. version 2.18 → 2.19.
  6. §4 표 구조·다른 셀 불변. UTF-8(BOM 없음), 표·코드블록 구문 정상.

### T2 — llm-wiki/SKILL.md: 절차 B/C/D/I에 분할 귀속 개별 명시  [Type A]
대상: `plugins/pjc/skills/llm-wiki/SKILL.md` (B L167·L176, C L209, D L228, I L360, +m1: A-2 L108·체크리스트 L436)
- **B(L176 새 feature 동기화, L167 폐기 표기)**: "`index.md` 기능별 인덱스" 갱신에 "(분할 상태면 해당 프로젝트 category의 sub-index에서 — §4)" 한 마디 추가. project feature이므로 sub-index 대상.
- **C(L209 feature 제거)**: "기능별 인덱스에서 feature 제거"에 "(분할 시 해당 category sub-index)" 추가. 단 "프로젝트 테이블 행 제거"는 본체이므로 변경 없음(또는 "프로젝트 테이블은 본체" 명시).
- **D(L228 상태 열 갱신)**: 프로젝트 테이블은 본체(분할 안 됨)임을 명시 — "프로젝트 테이블·상태 열은 `index.md` 본체에서 갱신(분할 대상 아님)".
- **I(L360 recipe 등록)**: recipe는 분할돼도 **`index.md` 본체** 기능별 인덱스·`## 가이드/레시피` 섹션에 등록함을 명시("recipe는 category가 없어 sub-index로 분할되지 않는다 — 본체 유지, §4").
- **추가 일관성(m1)**: A-2 L108(새 feature → 허브+`index.md` 기능별 인덱스 등록)·완료 전 체크리스트 L436(`index.md` 기능별 인덱스 등록 확인)에도 "(분할 시 해당 category sub-index)" 한 마디 부기 — A-3 L116과 A 절차 내 일관, 드리프트 방지. 쓰기 공백은 아니나(L108은 A-3이, L436은 lint §6이 커버) 완결성 차원.
- Edge cases(Type A): ⓐ 각 절차의 다른 단계·문장 불변(해당 줄에 괄호/짧은 절만 추가) ⓑ 인용한 §4 규약 표현이 T1과 일치 ⓒ A/G/K 기존 sub-index 명시 표현과 톤 일관.
- Halt Forecast: 없음.
- Acceptance:
  1. B(L176·L167)에 "분할 시 sub-index" 명시.
  2. C(L209)에 "기능별 인덱스 feature 제거는 분할 시 sub-index" 명시.
  3. D(L228)에 "프로젝트 테이블은 본체(분할 대상 아님)" 명시.
  4. I(L360)에 "recipe는 본체 기능별 인덱스(분할 안 됨)" 명시.
  5. A-2 L108·체크리스트 L436에 "(분할 시 sub-index)" 부기(m1).
  6. 인용 §4 표현이 T1과 일치. 각 절차 다른 단계 불변. UTF-8(BOM 없음).

### T3 — 버전·문서 갱신  [Type A]
- `notes.md`: 본 작업(위키 recipe 귀속 ③ 보강) 항목 추가 — 무엇·왜·어떻게·검증.
- `plugin.json`·`README.md`: 1.66.2 → 1.66.3 (patch — ①④와 동형 빈틈 보강). README 기능 목록 변경 없음(버전 줄만).
- Acceptance: notes.md에 본 작업 항목 1건; plugin.json·README 버전 일치, JSON 파싱 OK. (wiki-schema version은 T1에서 처리.)
- Halt Forecast: 없음.

## Verification Strategy
1. **문구 grep**: T1 §4 3개 문구(분할 한정·본체 유지·lint 미검사) + 기존 절대표현 한정 수정(m3) + version 2.19 / T2 B·C·D·I 4개 명시 + m1(A-2·체크리스트 부기) — 각 acceptance를 grep으로 확인.
2. **상호 참조 정합**: T2 절차가 인용한 §4 표현(분할 대상 한정·recipe/테이블 본체)이 T1 실제 문구와 일치.
3. **읽기 측 무손상**: A/G/K sub-index 명시(L116·296·389)·lint §7-14/15·분할 자동 결정 문장이 수정 전후 불변(git diff로 해당 영역 변화 없음).
4. **인코딩·구문**: 2개 파일 BOM 없음, §4 표·마크다운 구문 깨짐 없음.
5. **역대조 표**: F3(recipe 본체)·F5(테이블 본체)·F1(B/C/D/I 명시) 각 결정이 산출물에 실제 존재하는지, 거절/미채택안(recipe category 부여·index-guides 신설·lint 추가) 흔적이 없는지 대조.

## Out of Scope (이번 제외)
- **recipe frontmatter에 category 필드 추가** — cross-stack 철학 충돌 + 기존 recipe 마이그레이션. 영구 제외(본체 유지로 대체).
- **새 sub-index 분류(`index-guides.md` 등) 신설** — §4 "새 분류 안 만듦" 원칙 위반. 영구 제외.
- **감사 ② notes 아카이브 정합** — 별도 plan(메모리, ③ 다음 순서).

## Deferred / Follow-up
- **recipe 귀속 lint 기계 검사** (F3): 이번엔 §4 규약·절차 명문화까지. sub-index에 recipe 행이 잘못 들어갔는지 lint WARN은 향후 별도 검토(recipe 행 식별 로직 필요 — drift 가시화 가치 있으나 이번 범위 밖, 사용자 "명문화만" 결정).
- **감사 ② notes 아카이브 정합 검사** (MAJOR·우선 2): 본 plan 완료 후 별도 plan(메모리 split-mechanism-audit 보존).

## 승인 필요 항목
- 본 plan(지침 문서 2파일 보강 + notes/버전) — 승인 요청.
- T3 버전 bump — **patch 1.66.3 추천**, 사용자 확정 필요.
- commit/push 및 GitHub 릴리즈(v1.66.3) — 구현·검증 후 별도 승인.

## Progress Log
- T1~T3 완료 (미커밋 — 커밋 승인 대기): ① wiki-schema.md §4 분할 귀속 규약 명문화(절대표현 "모든/항상" 한정 + recipe·테이블 본체 예외 + lint 미검사 명시) + version 2.18→2.19. ② SKILL.md 절차 B/C/D/I 분할 귀속 개별 명시 + m1(A-2 L108·체크리스트 L436 부기). ③ notes 항목 + plugin.json·README 1.66.3. 전부 Type A.
  - 검증: T1 §4 문구 grep(분할 한정·본체·lint 미검사 각 1, 절대표현 잔존 0, version 2.19) / T2 B·C·D·I 4 + m1 2 grep / 두 파일 BOM 없음 / 읽기 측(A-3 L116·lint §7-14/15·분할 자동 결정) git diff 무변 / 역대조(index-guides·recipe category·lint 추가 흔적 0).
  - F-7 plan-completion-reviewer: BLOCKER 0 / MAJOR 0 / MINOR 1(§4 "가이드/레시피" 헤딩 공백 표기 드리프트) → 즉시 수정(`## 가이드 / 레시피` 통일, 무공백형 0건 확인).
  - 결정(사용자 확정 반영): recipe·프로젝트 테이블=본체 유지, 분할 대상=project feature 행 한정, recipe frontmatter category·index-guides 신설 안 함, recipe 귀속 lint는 Deferred.

## Next Steps
- 권장 다음 액션: 변경 5파일 commit(`기능: 위키 recipe 귀속 빈틈 보강(감사 ③) + 1.66.3`) → push → GitHub 릴리즈 v1.66.3 발행(메모리 release-on-version-bump). **commit/push·릴리즈는 사용자 승인 필요**(plan 승인 필요 항목).
- Suggested skills: (커밋 후) 공식 /code-review.

## Open Questions
- 없음 (F3+F5·F1·lint 결정 분기 모두 사용자 확정, 버전 종류만 승인 항목).
