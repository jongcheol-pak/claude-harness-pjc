# plan.md — lint.py sub-index 분할 신호 검사 추가 (llm-wiki)

## 목표
llm-wiki의 `lint.py`가 `index.md` 본체뿐 아니라 **sub-index 파일(`index-*.md`)의 크기(본문 줄수·기능별 인덱스 행수)도 "분할 신호"로 측정**해, 임계 초과 시 INFO로 알리도록 검사를 추가한다.
현재 sub-index 비대는 어떤 신호로도 감지되지 않는 사각지대다(아래 배경). 전부 markdown/python 문서·스크립트 편집이며 외부 의존성·새 인프라 도입은 없다.

## 결정 (사용자 권장 기본 + 본 계획 확정)
- **D1 — 임계 재사용**: sub-index도 `index.md`와 **동일 임계**(`INDEX_BODY_LINES` 400 / `INDEX_FEAT_ROWS` 200)를 쓴다. 별도 상수 신설 안 함(일관·3중 동기화 단순). 사용자 권장 기본.
- **D2 — 권고 메시지 = 소제목 구역화, 레벨 = INFO**: sub-index는 personal/work 2분할이 종착점이고 §4가 "새 분류 금지"라 추가 **파일** 분할 경로가 없다. 따라서 초과 INFO 메시지는 "추가 파일 분할 대신 **소제목 구역화로 정리**"를 권고한다(현 2단계 종착 설계 유지, 최소 변경). `index.md` 분할 신호와 동일하게 **INFO**(차단 아님). 사용자 권장 기본.
- **D3 — §7-14 확장**: 신규 §7-N를 만들지 않고 기존 **§7-14("index.md 분할 신호")를 "index.md 및 sub-index 분할 신호"로 확장** 정의한다. 사용자 권장 기본.
- **D4 — 헤딩 가정 명문화(본 계획 발굴)**: `feature_index_rows()`는 `## 기능별 인덱스` 헤딩을 정규식으로 찾는다. §4가 분할 시 기능별 인덱스 표기를 sub-index에 적용한다고 했으므로 sub-index도 같은 헤딩을 보유한다는 전제다. 이 전제가 깨지면 sub의 행수 측정이 조용히 0이 되므로, **§4에 "sub-index는 `## 기능별 인덱스` 섹션을 그대로 보유한다"는 한 줄을 명문화**해 lint 정규식의 계약을 문서로 고정한다. (본문 줄수 검사는 헤딩과 무관하게 항상 동작 — 헤딩 가정이 어긋나도 줄수 신호는 살아 있음.)
- **버전**: plugin.json `1.64.0 → 1.65.0`(minor — lint 동작 변경=신규 검사). wiki-schema frontmatter `2.15 → 2.16`. README L10·notes 갱신. 승인된 push 후 GitHub 릴리즈(release-on-version-bump).

## 배경
- 직전 plan.md(외부 저장소 검토 차용 3건)는 완료·커밋(9bb50a1)·릴리즈(v1.64.0). git 클린 → 새 계획으로 교체.
- **사각지대 근거(조사 실측)**: `lint.py:207-212`에서 `idx_lines`/`feat_rows`를 `index.md` 본체에만 적용("sub 합치기 전 index.md 본체로 측정"). sub-index 내용은 `lint.py:223-227`에서 그 *이후*에 `itext`로 합쳐지나 이는 오직 "기능별 인덱스 ↔ feature 동기화" 검사용. 즉 sub-index 파일 자체의 줄수/행수는 어떤 분할 신호로도 측정되지 않는다.
- **분할 종착 설계**: `wiki-schema.md §4`(line 262)는 `index.md` → (1단계)소제목 구역화 → (2단계)personal/work category 파일 분할까지만 정의하고 "새 분류를 만들지 말라"고 못박음 → sub-index의 추가 파일 분할 경로 없음(D2 근거).
- AGENTS.md 없음. 프로젝트/글로벌 CLAUDE.md가 컨벤션 원천(문서·스크립트 편집이라 bootstrap 강제 안 함).

## Impact Analysis (전수 확인)
- **`lint.py`**: 외부에서 `import`하는 코드 없음 — `python lint.py "<vault>"`로 실행되는 독립 스크립트(파일 listing·grep 확인, 호출자 0). 따라서 함수 시그니처·상수 변경의 cross-file 코드 영향 0. `feature_index_rows()`(`lint.py:69`)는 임의 text를 받는 순수 함수라 sub-index 텍스트에 그대로 재사용 가능.
- **상수 불변**: D1로 기존 `INDEX_BODY_LINES`/`INDEX_FEAT_ROWS`(`lint.py:35-37`)를 재사용 → `BUDGET`/`GUIDE_BUDGET` 등 예산 상수 **무변경** → SKILL 예산표 수치·wiki-schema §4 예산 테이블 수치 **무변경**. 3중 동기화 영향은 **§7-14 문구 + §4 line 262 산문**뿐(수치 동기화 아님).
- **신규 검사는 순수 추가**: 기존 index.md 분할 신호(L208-212)·sub-index 목록 정합(L214-221)·동기화 검사(L223-236)·한영 병기(L238+)는 건드리지 않고, sub_files(`lint.py:202`에서 이미 수집) 위를 도는 **읽기 전용 루프 1개 추가** + `infos`에 append. 기존 검사 결과·등급 불변.
- **문서 동기화 대상**: ① `wiki-schema.md` §4 line 262(sub-index 비대 종결 규칙 + 헤딩 명문화) ② `wiki-schema.md` §7-14(line 341, 확장) ③ `wiki-schema.md` frontmatter version 2.16 ④ `SKILL.md` §7-14 미러(line 279) + 예산표 index.md 행(line 428) 문구 ⑤ `lint.py` 상단 주석/검사 목록(L5-7)에 sub-index 분할 신호 한 줄.
- **plugin.json / README L10 / notes.md**: 1.64.0 → 1.65.0. marketplace.json은 version 필드 없음(손대지 않음 — 이전 plan에서 확인).
- **테스트**: lint.py 전용 테스트 파일 없음(무단 추가 금지 규칙). → 커밋 테스트 추가 대신 **임시 vault fixture로 수동 검증**(검증 방법 참조).

## 작업 단계 (T1 코드, T2~T4 문서/버전)

### T1 — lint.py: sub-index 분할 신호 검사 추가  [Type C]
- 위치: `lint.py` index.md 검사 블록(`if os.path.isfile(idx):` 내부), **index.md 분할 신호 검사(L208-212) 직후**에 sub-index 분할 신호 루프 추가(모든 "분할 신호" 로직을 한곳에 모음).
- 구현(명시적·직접적):
  ```python
  # sub-index 분할 신호 (§7-14): 각 index-*.md 자체 크기도 측정.
  # index.md → personal/work 2분할이 종착이라 추가 파일 분할 경로가 없으므로
  # 초과 시 '소제목 구역화'를 권고한다(wiki-schema §4).
  for sp in sub_files:
      try:
          with open(sp, encoding="utf-8") as sfh:
              stext = sfh.read()
      except OSError:
          continue
      s_lines = stext.count("\n") + 1
      s_rows = feature_index_rows(stext)
      if s_lines > INDEX_BODY_LINES or s_rows > INDEX_FEAT_ROWS:
          infos.append(
              f"{os.path.basename(sp)} 분할 검토: 본문 {s_lines}줄(임계 {INDEX_BODY_LINES}), "
              f"기능별 인덱스 {s_rows}행(임계 {INDEX_FEAT_ROWS}) — sub-index는 추가 파일 분할 "
              f"대신 소제목 구역화로 정리(wiki-schema §4)")
  ```
- `lint.py` 상단 docstring 검사 목록(L5-7)에 "sub-index 분할 신호" 취지 한 구절 추가(주석 정합).
- **Decision 반영**: D1(동일 임계 재사용), D2(소제목 구역화·INFO=`infos`), D3은 문서(T2), D4는 문서(T2)+이 루프가 `feature_index_rows` 재사용으로 전제.
- **Edge cases**:
  - sub_files 빈 배열(미분할 vault) → 루프 미실행, 기존 동작 그대로. ✓
  - sub에 `## 기능별 인덱스` 헤딩 없음/빈 표 → `feature_index_rows`=0 → 본문 줄수 신호만 적용(degrade-safe, 오류 아님). D4가 헤딩을 문서로 고정.
  - 임계 경계값 → `>`(strictly greater)로 index.md 검사와 동일 의미. ✓
  - 읽기 실패(OSError) → 해당 sub 건너뜀(기존 병합 루프 L228 try/except와 동일 정책). ✓
- **Halt Forecast**: 없음(독립 스크립트·추가 루프). 단 D4 헤딩 가정이 실제 vault와 어긋날 위험 → T2에서 schema 명문화로 계약 고정 + 본문 줄수 신호가 백업.
- Acceptance: ① `python -m py_compile lint.py` 0 에러 ② 임시 vault(아래 검증 3)에서 비대 sub-index에 대해 INFO 1줄 출력(파일명·줄수·행수·"소제목 구역화" 문구 포함) ③ 정상 크기 sub-index·미분할 vault에서는 sub 관련 INFO 미출력(오탐 0) ④ 기존 index.md 분할 신호·동기화·한영 병기 출력 불변.

### T2 — wiki-schema.md: §4·§7-14·version 갱신  [Type A]
- **§4 line 262**: `index.md` 행 설명 끝에 sub-index 비대 종결 규칙 + 헤딩 명문화 추가(원문 보존, 추가만):
  - "**sub-index 비대 시**: 분할된 `index-*.md` 자체가 임계(본문 400줄/기능별 인덱스 200행)를 넘으면 lint이 INFO로 알린다. 단 personal/work는 종착 분류이므로 **추가 파일 분할이 아니라 소제목 구역화(1단계)로 정리**한다(새 분류 금지 원칙 유지)."
  - "분할된 sub-index는 `## 기능별 인덱스` 섹션을 그대로 보유한다(lint 행수 측정·동기화 검사가 이 헤딩을 기준으로 함)." (D4 명문화)
- **§7-14(line 341)**: 제목·정의를 "index.md **및 sub-index** 분할 신호"로 확장 — "`index.md` 본문/기능별 인덱스 행수, **그리고 각 `index-*.md` 본문/기능별 인덱스 행수**가 임계 초과면 INFO로 분할(또는 sub-index는 소제목 구역화)을 제안한다."
- **frontmatter version**: `2.15 → 2.16`.
- Acceptance: §4에 sub-index 비대 규칙 + `## 기능별 인덱스` 헤딩 명문 존재; §7-14가 sub-index 포함으로 확장; version 2.16; frontmatter YAML 파싱 정상; 기존 §4 예산 수치·§7 다른 항목 불변(추가만, 삭제 0).
- Halt Forecast: 없음.

### T3 — SKILL.md: §7-14 미러 + 예산표 문구 동기화  [Type A]
- **§7-14 미러(line 279)**: wiki-schema와 동일 취지로 "sub-index 분할 신호" 포함하도록 확장(SKILL은 요약형 — "각 `index-*.md` 자체 크기도 측정, 초과 시 소제목 구역화 권고" 한 구절 추가).
- **예산표 index.md 행(line 428)**: 끝에 "(sub-index도 동일 임계 측정 — lint INFO)" 한 구절 추가.
- Acceptance: SKILL §7-14에 sub-index 측정 언급; 예산표에 sub-index 측정 언급; frontmatter YAML 파싱 정상; 기존 절차·다른 항목 불변.
- Halt Forecast: 없음.

### T4 — 버전 업 + 문서 갱신  [Type A]
- `plugins/pjc/.claude-plugin/plugin.json`: version `1.64.0 → 1.65.0`.
- `README.md` L10 `**버전**: 1.64.0 → 1.65.0`.
- `notes.md` `## 최근 변경` 최상단에 1.65.0 항목 추가(무엇=sub-index 분할 신호 검사 / 왜=비대 사각지대 / 어떻게=동일 임계 재사용·소제목 구역화 권고 / 검증 결과).
- Acceptance: plugin.json 1.65.0(JSON 파싱 OK); README L10 1.65.0; notes 1.65.0 항목; 잔존 1.64.0(이력 서술 제외) 없음.
- Halt Forecast: 없음.

## 검증 방법
1. **python 구문**: `python -m py_compile plugins/pjc/skills/llm-wiki/scripts/lint.py` → 에러 0.
2. **lint usage 회귀**: 인자 없이 `python lint.py` → 기존 usage 출력·exit 1(usage 에러 관례 — 기존 동작 불변, 본 변경은 vault 처리 경로에만 추가).
3. **임시 vault fixture 양성 검증**: 스크래치 디렉터리에 최소 vault 생성 — `index.md`(sub-index 목록 포함) + `index-personal.md`를 임계 초과(본문 401줄 또는 기능별 인덱스 201행)로 구성 → `python lint.py "<temp>"` 실행 → INFO에 "`index-personal.md` 분할 검토 … 소제목 구역화" 1줄 출현 확인.
4. **음성 검증(오탐 0)**: 같은 fixture에서 sub-index를 임계 미만으로 줄이면 sub 관련 INFO 미출현; sub-index 없는(미분할) vault에서도 sub INFO 미출현.
5. **문서 동기화**: wiki-schema version 2.16 + §4 sub-index 규칙·헤딩 명문 + §7-14 확장 grep; SKILL §7-14·예산표 문구 grep; wiki-schema·SKILL frontmatter YAML 파싱 OK.
6. **버전**: plugin.json JSON 파싱 + 1.65.0; README L10 1.65.0; notes 1.65.0 항목.
7. **임시 fixture는 스크래치에만 생성·삭제**(레포 vault 아님, 커밋 테스트 추가 아님 — 무단 테스트 추가 회피).

## 승인 필요 항목
- 본 plan(코드 1 + 문서 3 + 버전) — 승인 게이트.
- commit/push 및 GitHub 릴리즈 — 구현·검증 후 별도 승인(release-on-version-bump).

## Out of Scope (영구 제외)
- sub-index의 실제 자동 재분할 구현(파일을 코드로 쪼개기) — 본 작업은 **신호(INFO) 추가**까지.
- 새 category 도입(personal/work 외) — §4 "새 분류 금지" 유지.
- 대시보드·기타 lint 항목(§7 1~13, 15~16) 변경.
- sub-index 전용 별도 임계 상수(D1로 동일 임계 재사용 확정).

## Progress Log
- T1 완료 (Type C, 미커밋): lint.py index.md 분할 신호 검사 직후 sub_files 순회 루프 추가 + docstring 검사목록 갱신. D1 동일 임계 재사용·D2 소제목 구역화 INFO·D4 feature_index_rows 재사용. 검증: py_compile OK, fixture 양성2종(본문 402줄·기능별 인덱스 201행 모두 INFO)·음성(오탐 0), spec-compliance OK(0/0/0).
- T2 완료 (Type A, 미커밋): wiki-schema §4(sub-index 비대 규칙+`## 기능별 인덱스` 헤딩 명문)·§7-14 확장·version 2.15→2.16.
- T3 완료 (Type A, 미커밋): SKILL §7-14 미러 + 예산표 index.md 행에 sub-index 측정 문구.
- T4 완료 (Type A, 미커밋): plugin.json·README L10 → 1.65.0, notes 1.65.0 항목.
- **결정**: m1(이중 읽기)은 기본대로 별도 루프 유지(가독성 우선) — 사용자 승인.
- **F-2 통합검증**: py_compile OK, plugin.json JSON 1.65.0, schema/SKILL frontmatter YAML OK(schema 2.16), 문서 동기화 grep 6/6, README L10 1.65.0·잔존 1.64.0(이력 외) 0, 편집 6파일 BOM 없음.
- **미커밋 상태**: 사용자 지침대로 commit/push·릴리즈는 별도 승인 대기. 승인 시 main에서 작업 브랜치 생성 후 커밋.

## Next Steps
- 권장 다음 액션: 변경 검토 후 commit/push 승인 → push 후 GitHub 릴리즈(v1.65.0, release-on-version-bump).
- Suggested skills: (커밋 후) 공식 /code-review, 공식 /security-review.
