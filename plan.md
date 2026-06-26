# plan.md — llm-wiki 기계화 가능 빈틈 3건 수정 (F1/F2/F3) + 1.65.1 통합

## 목표
위키 조사에서 드러난 "기계화 가능한 빈틈" 3건을 수정한다:
- **F1**: lint이 `deprecated` 페이지를 전혀 인식 못 함 → 인식·집계·표기 정합 검사 추가.
- **F2**: 근거 각주 없는 "얕은 feature"가 lint을 통과 → feature 근거 각주 하드게이트 추가.
- **F3**: recipe 본문에 "함정/주의점" 전용 섹션 부재 → 스키마에 선택 섹션 추가.

직전 미커밋 1.65.1 변경(소제목 `### ` 명문화)을 **하나로 묶어** 통합 버전 **1.66.0**으로 릴리즈한다(사용자 결정). 전부 lint.py(코드)·wiki-schema·SKILL 문서 편집이며 외부 의존성·새 인프라 없음.

## 결정 (사용자 + 본 계획 확정)
- **범위 = 기계화 가능분만**(사용자 결정). read-only 위반/불가 항목은 수정 대신 "왜 자동화 안 하는가"를 문서로 명문화(아래 Out of Scope 위 "설계상 의도 명문화").
- **D1 — F1 deprecated**: 셋 다 적용 — ⓐ deprecated 페이지 INFO 집계(가시성), ⓑ deprecated인데 "코드에서 제거" 안내 문구 없으면 WARN(표기 정합), ⓒ 신선도(60/90일) 후보에서 제외(`paused`처럼). deprecated 판정 = `status: deprecated` **또는** `deprecated:` 필드 보유(schema §2.3 둘 다 허용).
- **D2 — F2 하드게이트 조건**: `type: feature` ∧ `## 구현 방법` 섹션 존재 ∧ `[^src-` 각주 0개 ∧ deprecated/archive 아님 → **WARN**(ERROR 아님 — 정당한 얕은 예외 여지). 무조건 전 feature가 아니라 "구현 방법 있는데 근거 0"에 한정(오탐 방지).
- **D3 — F3**: doc-only(schema §2.6 선택 섹션 + SKILL I-2 1줄). lint 강제 안 함(선택 섹션 강제는 과함).
- **D4 — §7 번호**: F1=§7-17, F2=§7-18로 **append**(기존 §7-1~16 번호 불변 → lint.py의 §7-N 주석 참조 무손상). recipe 함정은 §2.6 구조 변경이라 §7 신규 아님.
- **버전**: plugin.json `1.65.1(working tree) → 1.66.0`, README L10 → 1.66.0, wiki-schema `2.17 → 2.18`, notes 1.65.1 항목을 **1.66.0 통합 항목으로 병합**(### 명문화 + F1/F2/F3). 승인된 push 후 GitHub 릴리즈.

## 배경
- 직전 plan.md(sub-index 분할 신호, 1.65.0)는 완료·커밋(1f8b89e)·릴리즈. git 클린 후 1.65.1(소제목 `### ` 명문화) 작업이 **미커밋 상태**로 남음(검증 완료). 사용자 결정으로 1.65.1을 본 작업과 통합 → 새 계획으로 교체.
- **현 작업 트리 미커밋 5파일**(유지): wiki-schema.md(§4 `### ` + 2.17), lint.py(sub INFO `### `), plugin.json/README(1.65.1), notes.md(1.65.1 항목). 본 작업이 같은 파일을 이어서 편집해 1.66.0으로 통합.
- AGENTS.md 없음. CLAUDE.md가 컨벤션 원천(문서·스크립트 편집이라 bootstrap 강제 안 함).

## Impact Analysis (전수 확인)
- **lint.py**: 외부 `import` 호출자 0(독립 실행 스크립트, 앞선 조사 확인). main() 페이지 루프(L95~) 내에 검사 추가 + 루프 후 집계 INFO 추가. 시그니처 변경 없음 → cross-file 코드 영향 0.
  - F1 신선도 제외: L165 `fm.get("status") != "paused"` 조건에 deprecated 추가. F1 안내 WARN·집계: 루프 내 검사 + 루프 후 `infos`. 
  - F2: 루프 내 `type=="feature"` 분기에 각주 존재 검사 추가.
  - 기존 상수(BUDGET 등) 무변경 → 3중 동기화 수치 영향 없음. 변경은 §7 항목 문구(신규 17/18) + §2.3/§2.6/§8 산문.
- **wiki-schema.md**: §2.3(deprecated·각주 규칙 **이미 정의됨** — 강제만 추가, 정의 보강 최소), §2.6(recipe 함정 선택 섹션 신설), §7(17/18 append), §8(deprecated 신선도 제외 예외 추가 + "lint 제안만" 명문), version 2.18. 기존 §7-1~16·예산 수치 불변.
- **SKILL.md**: §7 미러 17/18 append, I-2 recipe 함정 1줄. 예산표·다른 절차 불변.
- **plugin.json/README/notes**: 1.66.0 통합. marketplace.json version 필드 없음(불변).
- **lint.py §7-N 참조 무손상**: 신규는 append라 기존 §7-11/12/16 등 참조가 가리키는 항목 번호 안 밀림.
- **테스트**: lint.py 전용 테스트 없음 → 임시 vault fixture 수동 검증(무단 테스트 추가 회피).

## 작업 단계 (T1 코드, T2~T4 문서/버전)

### T1 — lint.py: F1(deprecated) + F2(feature 각주 게이트)  [Type C]
- **F1 판정 변수(단일·먼저 계산)**: fm 파싱 직후(L100 `fm = frontmatter(text)` 근처)에 `is_dep = (fm.get("status") == "deprecated") or bool(fm.get("deprecated"))` 한 변수로 통일(함수형 안 씀). 이후 ⓐⓑⓒ가 모두 이 변수 사용.
- **F1-ⓒ 신선도 제외**: L165 조건 `... and fm.get("status") != "paused"` 끝에 `and not is_dep` 추가. deprecated 페이지는 frozen 이력이라 60/90일 후보에서 제외(paused와 동일 취급).
- **F1-ⓑ 안내 정합 WARN**: 루프 내, `is_dep and not in_archive and ("코드에서 제거" not in text)` → `warns.append("deprecated 표기 안내 누락: {r} ('⚠️ 코드에서 제거됨' 안내 권장, schema §2.3)")`. (in_archive 가드로 이력 페이지 제외 — F2와 동일.)
- **F1-ⓐ 집계 INFO**: 루프 동안 `is_dep and not in_archive`일 때만 `dep_count` 누적(현행 vault 한정, 90_archive 이력 페이지 제외 — 노이즈 방지) → 루프 후 `if dep_count: infos.append("deprecated 페이지 {dep_count}건 (이력 보존 — 현재 기능 아님, schema §2.3)")`.
- **F2 각주 게이트**: 루프 내, `typ=="feature"` ∧ not is_dep ∧ not in_archive ∧ `"## 구현 방법" in text` ∧ `"[^src-" not in text` → `warns.append("구현 근거 각주 누락: {r} (## 구현 방법 있으나 [^src-...] 0개 — 얕은 feature 의심, schema §2.3)")`.
- 주석은 한글 "왜" 중심. docstring 검사 목록(L5-7)에 "deprecated 표기 정합·feature 근거 각주" 한 구절 추가.
- **Edge cases**:
  - deprecated 표기 두 형식(`status: deprecated` / `deprecated:` 필드) 모두 인식 — 헬퍼로 통일. ✓
  - deprecated feature는 F2 각주 게이트에서 제외(frozen 이력에 각주 강제 안 함). ✓
  - `## 구현 방법` 섹션 없는 feature → F2 미발동(근거 누락이 아니라 섹션 부재 — 본 작업 범위 밖). ✓
  - 90_archive/ 페이지 → in_archive로 F1-ⓑ/F2 제외. ✓
  - `[^src-`가 코드펜스 안에 우연히 있는 경우 → 드묾(각주 마커), raw text 검색 허용(오탐 시 WARN이라 안전). 
- **Halt Forecast**: 없음(독립 스크립트, 추가 검사). 회귀 우려 → 기존 검사 출력 불변을 fixture로 확인.
- Acceptance: ① py_compile 0 ② fixture: deprecated 페이지(안내 有)→집계 INFO·WARN 없음 / deprecated(안내 無)→WARN / 구현 방법 있고 각주 0개 feature→WARN / 각주 1개+ feature→무경고 / 정상 deprecated는 60·90일 후보에서 빠짐 ③ 기존 검사(예산·링크·origin·신선도 비-deprecated) 출력 불변.

### T2 — wiki-schema.md: §2.6·§7-17/18·§8·version  [Type A]
- **§2.6 recipe 본문(L189)**: `## 사용 프로젝트 사례` 뒤에 ` / `## 주의점 / 함정`(선택)` 추가 + 한 줄 규칙("재사용 시 밟기 쉬운 함정·플랫폼 제약·성능/안정성 주의점. recipe 승격의 핵심 가치 — 단계 산문에 묻지 말고 별도 섹션으로. 선택이나 함정형 recipe엔 권장").
- **§7 검사 항목 append**:
  - `17. **deprecated 표기 정합·집계**: deprecated(`status: deprecated`/`deprecated:` 필드) 페이지를 INFO 집계(이력 가시성) + "⚠️ 코드에서 제거됨" 안내 누락 시 WARN + 신선도(60/90일) 후보에서 제외. (lint.py 검사)`
  - `18. **feature 구현 근거 각주**: `type: feature`이고 `## 구현 방법` 섹션이 있으나 `[^src-...]` 각주가 0개면 WARN(얕은 feature·근거 누락 의심). lint은 vault만 읽어 레포 파일 실재는 못 보므로 **각주 존재 여부까지** 검사하고, 서술↔코드 사실 정합은 §7-10(에이전트 표본)이 담당. (lint.py 검사)`
- **§8 신선도 예외**: L363 "예외 1: status: paused" 다음에 "예외 1-1: deprecated(`status: deprecated`/`deprecated:`)도 시간 기반 신선도 처리에서 제외(frozen 이력)" 추가.
- **lint 제안-only 명문(by-design)**: §7 또는 §8에 1줄 — "lint은 INFO/WARN **제안만** 하며 위키를 자동 수정하지 않는다 — confidence 하락·아카이브 이동 등 적용은 사용자 승인 또는 B/F 세션에서 수행(read-only 원칙)."(§8 L362 "사용자 승인 후 이동"과 정합 보강).
- **version**: 2.17 → 2.18.
- Acceptance: §2.6에 `## 주의점 / 함정` 선택 섹션 + 규칙; §7-17/18 신규 정의 존재(문구 위와 일치); §8 deprecated 신선도 예외 + lint 제안-only 1줄; version 2.18; frontmatter YAML 파싱 OK; 기존 §7-1~16·예산 수치 불변(추가만).
- Halt Forecast: 없음.

### T3 — SKILL.md: §7 미러 17/18 + recipe 함정 1줄  [Type A]
- **§7 미러(현재 16까지, L281 뒤)**에 17/18 append(SKILL 요약형): "17. deprecated 표기 정합·집계 — 이력 페이지 가시성+안내 누락 WARN+신선도 제외. lint.py 검사. / 18. feature 구현 근거 각주 — `## 구현 방법` 있으나 `[^src-` 0개면 WARN. lint.py 검사."
- **I-2 recipe(L349 부근)**: 본문 구성에 "주의점/함정(선택)" 추가 1줄(§2.6 참조).
- Acceptance: SKILL §7에 17/18 존재; I-2에 함정 섹션 언급; frontmatter YAML OK; 기존 절차·예산표 불변.
- Halt Forecast: 없음.

### T4 — 버전 통합 + 문서 갱신  [Type A]
- `plugin.json`: version `1.65.1 → 1.66.0`.
- `README.md` L10: `1.65.1 → 1.66.0`.
- `notes.md`: 현재 최상단 1.65.1 항목을 **1.66.0 통합 항목으로 병합·치환**(### 소제목 명문화 + F1 deprecated lint + F2 feature 각주 게이트 + F3 recipe 함정 섹션 / 무엇·왜·검증). 1.65.0 이하 기존 항목은 보존.
- Acceptance: plugin.json 1.66.0(JSON OK); README L10 1.66.0; notes 1.66.0 통합 항목(1.65.1 단독 항목 잔존 0); 잔존 1.65.1(이력 서술 제외) 없음.
- Halt Forecast: 없음.

## 검증 방법
1. **py_compile**: `python -m py_compile .../lint.py` → 0.
2. **usage 회귀**: 인자 없이 실행 → usage·exit 1(기존 동작 불변).
3. **fixture — F1**: deprecated 페이지(안내 有/無 2종) + 일반 60일+ feature 구성 → deprecated 집계 INFO·안내無 WARN·deprecated는 신선도 후보 제외, 일반 feature는 60일 후보 그대로.
4. **fixture — F2**: `## 구현 방법` 있고 각주 0개 feature → WARN / 각주 1개+ feature → 무경고 / deprecated feature → 무경고(제외).
5. **fixture — 오탐0**: 기존 검사(예산·링크·origin) 출력이 추가 전후 동일(신규 항목 외 변화 없음).
6. **문서 동기화**: §2.6 함정 섹션, §7-17/18(schema+SKILL 양쪽), §8 예외+lint제안-only, version 2.18 grep; frontmatter YAML 파싱.
7. **버전**: plugin.json JSON+1.66.0, README L10 1.66.0, notes 1.66.0 통합 항목.
8. 임시 fixture는 스크래치에만 생성·삭제(레포 vault 아님, 커밋 테스트 추가 아님).

## 설계상 의도 — 수정하지 않고 문서로만 명문화 (사용자 결정)
- **lint은 제안만, 자동 적용 안 함**(confidence 하락·아카이브) → read-only 원칙. T2에서 §7/§8에 1줄 명문.
- **위키↔코드 내용 사실 정합의 완전 기계화 불가**(lint은 vault만 읽음) → F2가 "각주 존재" 부분 슬라이스. 사실 정합은 §7-10(에이전트 표본) 책임. T2 §7-18 정의에 명시.

## 승인 필요 항목
- 본 plan(코드 1 + 문서 3 + 버전 통합) — 승인 게이트.
- commit/push 및 GitHub 릴리즈(v1.66.0) — 구현·검증 후 별도 승인(release-on-version-bump).

## Out of Scope (영구 제외)
- 코드 레포 파일 실재 검사(vault↔repo 분리로 lint 불가).
- confidence 자동 강등·아카이브 자동 이동(read-only 원칙 위반).
- A-3a 승격 거절 시 자동 함정 등록(사용자 게이트 유지 — 설계 의도).
- 위키 내용 사실성의 완전 기계 검증(§7-4 모순·§7-10 코드 정합은 에이전트 책임 유지).
- "deprecated여야 하는데 표기 누락" 탐지(코드 상태를 lint이 모름).

## Progress Log
- T1 완료 (Type C, 미커밋): lint.py — is_dep 판정 + F1ⓐ(dep_count INFO)·ⓑ(안내누락 WARN)·ⓒ(신선도 제외) + F2(feature 각주 게이트 WARN) + docstring. 기존 검사·상수 불변. 검증: py_compile OK, fixture F1 집계2/안내WARN/신선도제외+회귀유지, F2 얕은feature WARN/각주有·deprecated 무경고. spec-compliance OK(0/0/0).
- T2 완료 (Type A, 미커밋): wiki-schema §2.6 `## 주의점/함정`(선택)·§7-17/18 신규(append)·§8 예외 1-1(deprecated 신선도 제외)·§7 결과처리 lint 제안-only 명문·version 2.18.
- T3 완료 (Type A, 미커밋): SKILL §7-14·17·18 미러 + I-2 recipe 함정 1줄.
- T4 완료 (Type A, 미커밋): plugin.json·README → 1.66.0, notes 1.65.1 항목을 1.66.0 통합 항목으로 병합(### 명문화 + F1/F2/F3).
- **F-2 통합검증**: py_compile OK, plugin.json 1.66.0, schema 2.18/SKILL frontmatter YAML OK, 문서 동기화 grep 9/9, README L10 1.66.0·잔존 1.65.1(이력 외) 0, 편집 6파일 BOM 없음.
- **결정**: 1.65.1 ### 명문화를 1.66.0으로 통합(사용자), 기계화 가능분만(F1/F2/F3), read-only·코드정합 완전기계화는 §7 결과처리에 의도 명문(사용자).
- **미커밋 상태**: commit/push·릴리즈는 별도 승인 대기.

## Next Steps
- 권장 다음 액션: 검토 후 commit/push 승인 → push 후 GitHub 릴리즈(v1.66.0, release-on-version-bump).
- Suggested skills: (커밋 후) 공식 /code-review, 공식 /security-review.
