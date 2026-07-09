# Plan: 위키 스킬 개선 — [K-MISS] 큐·lint --fix·경량 큐 소비·K 참조 기록 (part2)

**이전 plan**: docs/plans/2026-07-09-harness-wiki-improve-part1.md

## 이전 part 핸드오프
- 함정: bash 도구로 `pwsh -Command "$var..."` 실행 시 `$` 변수를 bash가 삼킨다 — BOM 부여·파일 조작은 PowerShell 도구로 직접 실행할 것 (part1에서 1회 실패 후 전환).
- 함정: F-7 plan-completion-reviewer에게 골든·lint 러너 재실행을 시키지 말 것 — 장시간 명령으로 600초 스톨 발생(part1 실증). 검증 결과는 메인이 실행해 프롬프트로 전달.
- 기각된 접근: 시크릿 마스킹의 "값 치환" — Get-SecretMatches(secret-patterns.ps1)는 라벨만 반환하고 매치 위치를 주지 않아, cmd 필드 생략(fail-closed)으로 대체했다(part2 T2에서 secret 관련 로직 재사용 시 참고).
- 검증 지름길: AGENTS.md `### 검증 매핑` 표(part1 T4 신설) — `skills/llm-wiki/**` 변경은 check_consistency + run_lint_evals만 task 검증으로 충분(전체는 F-2).

## 요구 이해
- **원문 요청**: "위키, 하니스 모두 수정해줘" — 직전 대화에서 Claude가 제안한 개선 항목(하네스 5건 + 위키 4건)을 반영. 질문 라운드에서 사용자 확정: 전 항목 진행, plan 2분할(part1 하네스 / part2 위키).
- **이해한 요구**: llm-wiki 스킬에 ① 절차 K에서 위키 자료를 찾았는데 없었던 "미스"를 `[K-MISS]` 태그로 pending.md에 큐잉해 다음 ingest가 수요 기반으로 페이지를 만들게 하고, ② lint.py에 `--fix` 모드(판단 불필요한 참조 무결성 3종 한정)를 추가하고, ③ 풀 ingest/lint 없이 pending 큐만 소비하는 경량 절차 M을 신설하고, ④ plan-feature Step 1의 절차 K 참조 결과를 plan.md Investigation Log에 기록하게 한다.
- **포함하지 않는 것으로 이해**: lint --fix의 범위 확대(인덱스 행 신설·한/영 병기 등 내용 판단이 필요한 수정)는 하지 않는다 — 조사 결과 자동 수정 안전 대상은 3종뿐이며 사용자가 이 축소 범위로 확정(Q1).

## Goal
위키 스킬이 실사용 미스에서 수요를 학습하고([K-MISS]), 기계 수정을 스크립트에 위임하고(--fix), 큐 소비 마찰을 낮추고(절차 M), 계획 세션의 위키 참조가 plan에 남아 재조회가 없어진다.

**전체 목표**: 직전 대화에서 제안·확정된 하네스 5건 + 위키 4건 개선 전체 반영 (part1 = 하네스, part2 = 이 plan).

## Out of Scope
- **lint --fix의 내용 판단 수정**: 기능별 인덱스 행 생성(§7-6), 한/영 병기(§7-16), updated 날짜 기입(§7-9 — 날짜는 내용 변경 시점의 의미라 기계 기입이 오히려 오염), 깨진 wikilink 교정(§7-1 — 대상 판단 필요)은 --fix 대상에서 영구 제외. 자동 수정은 "판단이 0인 참조 무결성 동기"만.
- **[K-MISS]의 자동 페이지 생성**: 미스 큐가 곧바로 페이지를 만들지 않는다 — ingest 세션(B)이 레포 근거를 대조해 생성·기각을 판정한다(위키 품질 게이트 유지).

## Deferred / Follow-up
- (이월, v1.102.0 plan) 나머지 7개 프로젝트 메모리의 위키 순차 이전 — 각 프로젝트 절차 B 세션에서.
- (이월) suggest-agents-record grep 패턴 오탐("dotnet build" 문자열 오인) — part1 T2의 이벤트 로깅이 데이터를 쌓으면 근거 기반 수정 가능.
- (이월) plan-feature description 1,024자 한도 근접 — 다음 description 수정 시 여유 확보.
- lint --fix 대상 확대(§7-19 누락 행 추가 등) — 키워드 요약을 기계 생성할 근거가 생기면 재검토.
- suggest(제안) 이벤트의 로깅 확장 — part1 T2는 차단+경고만(사용자 확정 범위).
- (T2 리뷰 m2) lint.py `section()` 헬퍼를 Match 반환형으로 확장해 `section_span()`과 단일화 — 기존 호출부 리팩터링 동반이라 이번 diff 범위 밖, 다음 lint.py 정비 때.

## Investigation Log
- **기존 4태그 열거 지점 전수 grep** (`K-DRIFT|SKILL-IMPROVE|PROJECT-FACT|네 태그|세 태그`, 2026-07-09 실행): [K-MISS] 합류 시 정합 필요 지점 —
  - `SKILL.md`(llm-wiki): K 5·5-1·5-2·5-3(동형 규약), K 6 :140("네 태그 공용" → 다섯 태그), K 2 :115(pending 참조 제외 — [K-MISS]는 [DECISION] 예외에 해당 없음, 열거 무변경 확인)
  - `wiki-schema.md`: §5 0a :337(큐 소비 요약), §6 :381("네 태그 공용" 장문), §7-25 :414(태그별 잔량 집계), §9 :478(코드 세션 쓰기 예외 열거) — 4곳 모두 직접 Read로 원문 확인 완료. §2.2 :106~108은 [PROJECT-FACT] 전용 서술 — 무변경.
  - `procedures-content.md`: B-1 0 :83~92(소비 규정 — 직접 Read 완료, [K-MISS] 불릿 추가 위치는 :92 [PROJECT-FACT] 불릿 뒤), C-4 :164("등" 포괄 — 무변경).
  - `procedures-ops.md`: F-0 :13(잔량 집계 열거 + 인라인 소비 재열거 — 둘 다), F-2 :51(소비 열거), G :57(참조 제외 괄호 열거) — 3곳 갱신.
  - `lint.py`: :12(헤더 주석), :607~610(§7-25 태그 튜플 — 1행 추가).
  - `lint-cases.json` pending-backlog 케이스 + `evals/fixtures/pending-backlog/pending.md` — 집계 실증 1건 추가.
- **lint.py 구조** (explorer 조사 + 검사 항목 표 대조): main() :223, 인자는 vault 경로 positional 1개뿐(플래그 없음), 출력 [ERR]/[WARN]/[INFO] :764~774, exit — ERR 있으면 1 (:778~779). **현재 완전 read-only**(open은 "rb"·utf-8-sig 읽기만). §7-23 검사 :485~506(open question ↔ index 미해결 질문 양방향), §7-24 :619~645(decisions 아카이브 포인터 양방향 + 결정 어휘), §7-19 :578~596(log 아카이브 인덱스 양방향).
- **--fix 안전 대상 판정**: 25항목 중 판단 없이 자동 수정 가능한 것 — §7-23(질문 행 추가·제거: wikilink `[[30_knowledge/questions/<파일>|<제목>]]` 기계 조립 가능, 제목은 frontmatter/파일명), §7-24(아카이브 포인터 행 추가·제거: 실파일 목록에서 기계 조립), §7-19(stale 행 **제거만** — 누락 행 추가는 그 달 키워드 요약이 필요해 판단 개입). 그 외는 전부 내용 판단 필요 → Out of Scope.
- **run_lint_evals.py 구조** (직접 확인): `prepare_placeholder_vault()` :55~ 가 fixture를 임시 폴더로 copytree하는 메커니즘 실재 — --fix 케이스는 이 패턴을 재사용해 원본 fixture를 오염시키지 않고 임시본에 --fix 실행 → 재lint 결과 대조 가능. case 스키마: expect_clean/expect_keywords/expect_absent/placeholder.
- **절차 신설의 check_consistency 자동 검사** (AGENTS.md :31 확인): 본체 `## 절차 목차` 라우팅 표 전 행 ↔ procedures-*.md 절차 헤딩 실존·1곳·위치 일치를 **동적 캡처**로 검사 — 절차 M 신설 시 라우팅 표 행 + `### M.` 헤딩만 맞으면 자동 검사에 포함(스크립트 수정 불필요).
- **SKILL.md(llm-wiki) 여유**: 175줄(한도 500) — K 5-4 신설 ~8줄 + 목차 1행 + 예산표 무변경으로 충분. description 478자(한도 1,024) — 절차 M 트리거 문구 추가 여유 충분.
- **plan-feature SKILL.md 434줄 / implement-task SKILL.md 492줄** (wc -l 실측): plan-feature Step 1 불릿 1~2줄 추가 무해. implement-task는 **500줄 한도까지 8줄** — part2 T4의 :172 추가 1줄 + part1 T3·T4 추가분과 합산 주의(Edge Case에 등재).
- **implement-task 재개 진입 :172 직접 Read**: 재개 시 경량 K 참조(세션당 1회) 규정 실재 — "plan Investigation Log의 위키 참조 기록 우선" 1줄의 삽입 위치.
- **G 절차(procedures-ops :54~63) 직접 Read**: Query의 pending 제외 규정이 K 2 준용 — [K-MISS] 태그명만 열거 합류하면 됨.
- **B-1 0 소비 규정 직접 Read (:83~92)**: [DECISION]/[PROJECT-FACT] 불릿이 "대상 프로젝트 즉시 소비 / 타 프로젝트 동의 게이트 / 중복 검사 / 미등록 표식 / 제거 시점 재읽기-병합" 골격 공유 — [K-MISS] 불릿도 동형 골격으로 추가 가능.

## Risks & Unknowns
| 위험 | 영향 | 완화책 |
|---|---|---|
| lint.py에 쓰기 코드 도입 — 버그 시 vault 파일 훼손 | 사용자 위키 데이터 손상 | --fix는 명시 플래그일 때만 동작(기본 read-only 불변), 수정 전 대상 파일을 `90_archive/backup/{날짜}/`에 백업(스킬 사전 백업 규약과 동일 위치), 수정 내역을 stdout에 diff 요약으로 출력, 골든에서 임시본 실행으로 실증 |
| [K-MISS] 큐 노이즈(사소한 미스 남발) | pending 비대·ingest 부담 | 큐잉 조건을 "작업에 실제 필요해 검색한 지식"으로 한정 + 기존 중복 억제·잔량 경고(20건) 공용 |
| implement-task SKILL.md 500줄 근접(492) | 공식 권장 위반 | part1·part2 합산 추가를 ≤6줄로 설계, 초과 시 V-1/V-2 fallback 이관 전례(v1.101.0 T6)대로 references 이관 |
| 절차 M이 B-1 0과 소비 규칙 중복 서술 → 드리프트 | 규정 이중화 | M은 진입·종료만 정의하고 소비 규칙은 "B-1 0 정본 부분 Read" 포인터로 재사용(F-2 :51 전례와 동형) |

## Impact Analysis
### 4-A. 심볼/타입 추적 결과
| 심볼/앵커 | 영향 받는 파일 | 영향 종류 |
|---|---|---|
| 큐 태그 열거(4→5) | llm-wiki SKILL.md, wiki-schema.md(§5·§6·§7-25·§9), procedures-content.md(B-1 0), procedures-ops.md(F-0·F-2·G), lint.py(:12·:607~610) | 열거 합류(동형 확장) |
| lint.py main/출력 | lint.py, run_lint_evals.py, lint-cases.json | --fix 플래그·케이스 추가 |
| `## 절차 목차` 라우팅 표 | llm-wiki SKILL.md, procedures-ops.md, check_consistency.py(수정 없음 — 동적 캡처) | 절차 M 행·헤딩 추가 |
| plan-feature Step 1 위키 참조 불릿 | plan-feature/SKILL.md, plan-template.md, implement-task/SKILL.md(:172) | 기록 규정 1~2줄 |

### 4-B. 계약·직렬화 변경
- pending.md 큐 항목 형식에 태그 1종 추가(`[K-MISS]`) — 기존 태그 파싱은 태그명 문자열 매칭이라 무영향(lint.py 튜플에 1행 추가만).
- lint.py CLI 계약: 기존 `lint.py <vault>` 무변경 유지, `--fix`는 opt-in 플래그(기본 동작 완전 동일 — 무회귀).

### 4-C. 테스트 파일
- `plugins/pjc/skills/llm-wiki/evals/lint-cases.json` + `evals/fixtures/pending-backlog/` (T1), 신규 fixture `fix-mode/` (T2)
- `plugins/pjc/skills/llm-wiki/evals/run_lint_evals.py` (T2 — fix 케이스 타입)
- `plugins/pjc/skills/llm-wiki/evals/check_consistency.py` (T3 — 수정 없이 통과 확인)

### 4-D. 재사용 확인
| 신규 심볼 | 유사 기존 구현 검색 결과 | 재사용/신규 사유 |
|---|---|---|
| `[K-MISS]` 큐 규약(K 5-4) | K 5·5-1·5-2·5-3 (SKILL.md :121~139) | 동형 골격 재사용(형식·중복 억제·폴백·하네스 레포 예외), 태그·소비처만 신규 |
| lint.py `--fix` | 쓰기 코드 없음(read-only 확인) | 신규 — 단 백업 위치는 스킬 사전 백업 규약(`90_archive/backup/`) 재사용 |
| 절차 M | F-0/F-2 소비 경로, B-1 0 소비 규칙 | 소비 규칙은 B-1 0 정본 재사용(포인터), M은 경량 진입 경로만 신규 |
| fix-mode eval | `prepare_placeholder_vault()` copytree 패턴 | 임시본 실행 패턴 재사용 |

### Verified by
- grep `K-DRIFT|SKILL-IMPROVE|PROJECT-FACT|네 태그|세 태그` → plugins/pjc 전체 hit 전수 분류(위 Investigation Log — 갱신 대상/무변경 판정 포함)
- wiki-schema :337·:381·:414·:478, procedures-content :83~92, procedures-ops :13·:51·:57, SKILL.md K 전문 — 직접 Read

## Decisions
### D1. [K-MISS] 큐잉 시점·조건
- **Options**: A) 절차 K 3(무매칭 보고) 시점에 자동 큐잉 / B) 사용자 수동 요청 시만
- **Chosen**: A (+수동 병행)
- **Rationale**: 미스는 K 3 무매칭 판정 순간에만 확실하다 — 세션 종료 후엔 유실(기존 K 5 drift 큐잉과 동일 논리). 조건은 "작업에 실제 필요해 검색한 지식"으로 한정해 노이즈 방지.
- **Source**: SKILL.md K 3 :119(무매칭 합성 금지 규정 — 큐잉 삽입점), K 5 :121(발견 유실 방지 근거)

### D2. [K-MISS] 소비 규칙
- **Options**: A) ingest(B-1 0)에서 수요 신호로 소비 — 레포 근거 대조 후 feature/recipe 생성·보강 검토, 생성 부적합이면 기각 제거 / B) lint(F)에서만
- **Chosen**: A (F는 기존 구조대로 F-0 집계·F-2 승인 소비에 합류)
- **Rationale**: 페이지 생성은 레포 대조가 필요한 ingest의 일 — B-1 0의 [DECISION]/[PROJECT-FACT] 동형 골격(대상 프로젝트 즉시 소비·타 프로젝트 동의·중복 검사·재읽기-병합)에 합류가 최소 변경.
- **Source**: procedures-content.md B-1 0 :83~92 직접 Read

### D3. --fix 안전 대상 3종 한정
- **Options**: A) §7-23 양방향 + §7-24 양방향 + §7-19 stale 제거만 / B) 인덱스 행 생성·updated 기입까지 확대
- **Chosen**: A (사용자 Q1 확정 — 축소 진행)
- **Rationale**: 3종만 "판단 0"으로 기계 조립 가능. B는 내용 판단(설명 문구·날짜 의미)이 필요해 자동 수정이 오염원이 됨.
- **Source**: lint.py :485~506(§7-23)·:619~645(§7-24)·:578~596(§7-19) explorer locating 후 검사 로직 확인

### D4. --fix 안전장치
- **Options**: A) 수정 전 파일을 `90_archive/backup/{YYYY-MM-DD}/`에 백업 + 수정 내역 stdout 요약 + 플래그 없으면 완전 무변경 / B) 백업 없이 diff 출력만
- **Chosen**: A
- **Rationale**: vault는 비 git일 수 있음 — 스킬의 사전 백업 규약과 같은 위치를 쓰면 절차 L(복구)이 그대로 적용된다. 목적지 존재 시 미덮어쓰기(§8 규약)도 동일 준수.
- **Source**: SKILL.md 사전 준수 사항 :85(비 git vault 사전 백업 규약), procedures-ops.md L :96~105

### D5. 절차 M의 위치·구성
- **Options**: A) procedures-ops.md에 `### M. 큐 소비 (경량)` 신설, 소비 규칙은 B-1 0 정본 부분 Read 포인터 / B) SKILL.md 본체 수록
- **Chosen**: A
- **Rationale**: M은 위키 운영 절차(빈도 낮음) — 본체는 K(최빈 경로)만 수록하는 기존 설계 유지. 소비 규칙 재서술 금지(F-2 :51 "B-1 0 부분 Read" 전례 동형 — 드리프트 방지). check_consistency가 라우팅 표를 동적 캡처하므로 표 행 + 헤딩만 정합하면 됨.
- **Source**: SKILL.md :44(K 본체 수록 근거), procedures-ops.md F-2 :51, AGENTS.md :31

### D6. K 참조 기록의 형식·위치
- **Options**: A) plan.md Investigation Log에 "위키 참조: <페이지> — <핵심 결론 1줄>" (무매칭이면 "관련 위키 자료 없음") / B) 별도 섹션 신설
- **Chosen**: A
- **Rationale**: Investigation Log는 이미 "확인 방법 + 결과"의 집이고 reviewer가 근거 매칭에 쓰는 섹션 — 새 섹션은 템플릿·reviewer 정합 연쇄만 늘림.
- **Source**: plan-template.md :84~85, plan-feature 통과 체크리스트(근거 매칭)

### D7. 버전
- **Chosen**: part2 완료 시 1.106.0 (minor — 기능 추가). part1(1.105.0)과 독립 상향.
- **Source**: 릴리즈 전례(notes.md — 버전 업 push 후 곧바로 릴리즈 발행 규약)

## Tasks

- [x] T1. [K-MISS] 큐 태그 신설 (큐잉 K 5-4 + 소비 B-1 0 + 열거 정합 + lint 집계 + 골든)
  - **Type**: D
  - **Acceptance**: Given 절차 K 3에서 한/영 양방향 검색 후 무매칭, When 작업에 실제 필요했던 지식이면, Then `- [YYYY-MM-DD] [K-MISS] {프로젝트}: {찾으려던 지식 1줄}`이 pending.md에 append되는 규약이 SKILL.md K 5-4에 존재(중복 억제·vault 폴백·하네스 레포 예외는 5-2와 동형 참조). And 태그 열거 지점 9곳(Investigation Log 목록) 전부에 [K-MISS] 합류. And `python evals/check_consistency.py` exit 0. And lint 골든에 pending-backlog K-MISS 집계 케이스 1건 추가돼 `run_lint_evals.py` 전 케이스 PASS.
  - **Files**:
    - 주: `plugins/pjc/skills/llm-wiki/SKILL.md` (K 3 큐잉 포인터 1줄 + K 5-4 신설 ~8줄 + K 6 :140 다섯 태그)
    - 동반: `plugins/pjc/skills/llm-wiki/references/wiki-schema.md` (§5 0a·§6·§7-25·§9), `plugins/pjc/skills/llm-wiki/references/procedures-content.md` (B-1 0 [K-MISS] 불릿 — [PROJECT-FACT] 불릿 :92 뒤), `plugins/pjc/skills/llm-wiki/references/procedures-ops.md` (F-0 :13·F-2 :51·G :57), `plugins/pjc/skills/llm-wiki/scripts/lint.py` (:12 주석·:607~610 튜플 1행)
    - 테스트: `plugins/pjc/skills/llm-wiki/evals/fixtures/pending-backlog/pending.md` (K-MISS 1건 추가), `plugins/pjc/skills/llm-wiki/evals/lint-cases.json` (expect_keywords에 "K-MISS 1건")
  - **Edge Cases**:
    - 무매칭이지만 "궁금해서 찾아본" 수준(작업 필요 아님) → 큐잉하지 않음(조건 명문화 — 노이즈 방지)
    - 같은 프로젝트+같은 지식 요지가 이미 pending에 있으면 append 생략(5-2 동형)
    - vault 미설정·append 실패 → 질문 없이 조용히 생략 + plan/notes 폴백(5-1 동형)
    - 소비 시 해당 지식이 레포에 실재하지 않음(요청 자체가 잘못) → 기각 사유 보고 후 제거
  - **Halt Forecast**:
    - (i) 열거 지점 누락 → Investigation Log의 전수 grep 목록이 기준(9곳), V-7 grep 재확인으로 해소
  - **Depends on**: -

- [x] T2. lint.py `--fix` 모드 (안전 3종 + 백업 + fix 골든)
  - **Type**: D
  - **Acceptance**: Given `--fix` 플래그 없이 실행, Then 기존과 바이트 동일 동작(무회귀 — 기존 골든 전 케이스 PASS). Given `--fix`로 실행, When §7-23 위반(open question 인덱스 미등록/resolved 잔존)·§7-24 위반(아카이브 포인터 누락/stale)·§7-19 stale 인덱스 행 존재, Then 해당 파일을 `90_archive/backup/{오늘}/`에 백업 후 수정하고 수정 내역을 stdout에 항목별 요약 출력, 재실행 lint에서 그 3종 위반 0. And 신규 fix-mode 골든 케이스(임시본 --fix → 재lint 대조) PASS.
  - **Files**:
    - 주: `plugins/pjc/skills/llm-wiki/scripts/lint.py` (argv 파싱 `--fix` + fix 함수 3종 + 백업 헬퍼)
    - 동반: `plugins/pjc/skills/llm-wiki/references/wiki-schema.md` (§7 서두에 --fix 대상·안전장치 명시), `plugins/pjc/skills/llm-wiki/references/procedures-ops.md` (F-2에 "승인 후 3종은 `--fix` 실행으로 대체 가능" 1줄)
    - 테스트: `plugins/pjc/skills/llm-wiki/evals/run_lint_evals.py` (fix 케이스 타입 — copytree 임시본에 --fix 실행 후 재lint 대조), 신규 fixture `evals/fixtures/fix-mode/` (3종 위반 각 1건 포함), `plugins/pjc/skills/llm-wiki/evals/lint-cases.json`
  - **Edge Cases**:
    - 백업 목적지에 같은 파일 존재 → 덮어쓰지 않음(§8 규약 — suffix 부여 또는 skip 후 보고)
    - index.md 자체가 없는 vault에서 --fix → §7-23 수정 불가, 건너뛰고 보고(기존 ERR 유지)
    - 수정 대상 파일이 읽기 전용/잠김 → 그 항목만 실패 보고, 나머지 계속, exit 규약 유지
    - --fix와 위반 0 조합 → "수정 대상 없음" 출력, 파일 무변경·백업 미생성
  - **Halt Forecast**:
    - (i) §7-19 누락 행 추가 욕구(키워드 필요) → D3에서 제거만으로 확정(추가는 Out of Scope)
  - **Depends on**: T1 (lint.py·lint-cases 동시 수정 — 충돌 방지 순차)

- [ ] T3. 경량 큐 소비 절차 M 신설
  - **Type**: C
  - **Acceptance**: Given "큐 정리"/"pending 정리" 요청, Then procedures-ops.md `### M. 큐 소비 (경량)`이 §0 시작 절차 → pending.md 읽기 → B-1 0 정본 부분 Read로 태그별 소비(게이트 포함) → log 1줄 → 잔량 보고로 완결(lint·ingest 미수행 명시). And SKILL.md 절차 목차 라우팅 표에 M 행 존재 + description에 트리거 문구 추가(총 1,024자 이내). And `check_consistency.py` exit 0 (라우팅 표 ↔ 헤딩 동적 캡처 통과).
  - **Files**:
    - 주: `plugins/pjc/skills/llm-wiki/references/procedures-ops.md` (### M 신설 ~15줄)
    - 동반: `plugins/pjc/skills/llm-wiki/SKILL.md` (절차 목차 표 1행 + description 트리거)
  - **Edge Cases**:
    - pending.md 없음/빈 파일 → "소비할 큐 없음" 보고 후 종료(부트스트랩·lint로 확대 금지)
    - 타 프로젝트 [DECISION]/[PROJECT-FACT]만 잔존 → B-1 0 동의 게이트 그대로(자동 소비 금지)
    - [SKILL-IMPROVE]만 잔존 → 보고만(제거는 사용자 지시 시 — B-1 0 그대로)
  - **Halt Forecast**: (해당 없음 — 소비 게이트는 B-1 0 정본이 이미 정의)
  - **Depends on**: T1 ([K-MISS] 포함된 B-1 0을 M이 포인터로 참조 — 태그 완성 후)

- [ ] T4. 절차 K 참조 내역 plan.md 기록
  - **Type**: C
  - **Acceptance**: Given plan-feature Step 1에서 절차 K로 위키 참조, Then 참조한 페이지·핵심 결론 1줄(무매칭이면 "관련 위키 자료 없음")을 plan.md Investigation Log에 기록하는 규정이 Step 1 위키 참조 불릿에 존재. And plan-template.md Investigation Log 주석에 기록 예시 1줄. And implement-task 재개 진입 :172에 "plan Investigation Log의 위키 참조 기록이 있으면 그 페이지를 우선 식별 대상으로" 1줄 (implement-task SKILL.md 총 행수 ≤500 유지).
  - **Files**:
    - 주: `plugins/pjc/skills/plan-feature/SKILL.md` (Step 1 위키 참조 불릿 1~2줄)
    - 동반: `plugins/pjc/skills/plan-feature/references/plan-template.md` (Investigation Log 주석), `plugins/pjc/skills/implement-task/SKILL.md` (:172 1줄)
  - **Edge Cases**:
    - vault 없음 → 기록도 생략(기존 "건너뛴다" 흐름 유지 — 빈 기록 강제 금지)
    - implement-task 500줄 초과 위험 → 1줄 초과 시 :172 문장 내 통합(신규 불릿 금지)
  - **Halt Forecast**: (해당 없음 — 지침 doc 1~2줄 추가, 500줄 위험은 Edge Case에서 선해소)
  - **Depends on**: -

- [ ] T5. 버전·README·통합 검증
  - **Type**: A
  - **Acceptance**: plugin.json·README 1.105.0→1.106.0(part1 선행 가정 — part1 미실행 상태면 1.104.0→1.106.0이 아니라 현재 버전에서 minor +1). README에 v1.106.0 변경 안내 1블록([K-MISS]·--fix·절차 M·K 참조 기록). 통합 검증 전부 green: 전 ps1 parse OK, JSON 매니페스트 3종 OK, `check_consistency.py` exit 0, `run_lint_evals.py` 전 케이스 PASS, .md 무BOM.
  - **Files**:
    - 주: `plugins/pjc/.claude-plugin/plugin.json`, `README.md`
  - **Edge Cases**: part1이 먼저 릴리즈되지 않았으면 버전 기점을 실측 후 결정(plugin.json 현재값 기준 minor +1)
  - **Halt Forecast**: (해당 없음 — 버전·문서 수정만, 파괴적·외부·의존성 요소 없음)
  - **Depends on**: T1~T4

## 사전 승인 항목 (일괄 승인 대상)
- T2 — lint.py에 파일 쓰기 코드 도입(--fix 한정, 기본 read-only 불변): 스크립트 동작 계약 확장
- T3 — llm-wiki description 문구 변경(트리거 추가): 스킬 발동 조건 확장
- T1~T5 — 로컬 작업 브랜치 commit(체크포인트·task 완료 commit, implement-task 규약)

## 불가피한 Halt (위임 불가 — 일괄 사전승인 불가)
- push·main 병합·태그·릴리즈 v1.106.0 발행 — 최종 보고 후 별도 승인
- 재설치(install.ps1) — 사용자 제외 지시 유지 중(설치 캐시 갱신은 사용자 판단)

## Known Workarounds (있는 경우만)
- (없음)

## Verification Strategy
- 빌드: `pwsh -NoProfile -Command "<AGENTS.md Build — 전 ps1 parse>"`
- 테스트: `pwsh ... plugins/pjc/hooks/evals/run-hook-evals.ps1` (hook 무관 task는 skip 가능 — 이 plan은 hook 미수정), `python plugins/pjc/skills/llm-wiki/evals/run_lint_evals.py`, `python plugins/pjc/skills/llm-wiki/evals/check_consistency.py`, JSON 매니페스트 3종
- 수동 검증: 실 vault(`D:/Personal Project/Obsidian Vault/LLM WIKI`)에 lint --fix를 **실행하지 않는다** — fixture 골든으로만 실증(실 vault는 사용자 위키 세션에서)

## Phase Ledger

## Retry Ledger

## Progress Log
- T1-T2 완료 (커밋 bc6283d + T2): [K-MISS] 다섯 태그 열거 정합(K 2 :115의 기존 5-3 누락도 정정) / lint.py --fix(안전 3종, apply_fixes가 본 lint 헬퍼 재사용·BOM/줄바꿈 원본 보존·백업 §8 미덮어쓰기, DEC_PTR_RX 모듈 상수 승격 — 리뷰 m1 반영, m2는 Deferred). 골든 22→23, check_consistency 94 유지. 리뷰 4건 OK(m1·m2 MINOR만).

## Next Steps
- part1(하네스) 완료 후 이 plan을 `docs/plans/2026-07-09-harness-wiki-improve-part2.md 구현`으로 실행

## Open Questions
- (없음 — Q1~Q4 사용자 확정 반영 완료)
