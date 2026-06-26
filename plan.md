# plan.md — 외부 저장소 검토 차용 패턴 적용 (Understand-Anything · agentmemory)

## 목표
두 저장소(Understand-Anything, agentmemory) 심층 검토에서 도출한 **프롬프트 패턴 차용 3건**을 pjc 플러그인에 적용한다.
전부 스킬 문서(markdown) 편집/신규이며 코드 로직·외부 의존성·인프라 도입은 없다(두 저장소의 기능/코드는 비적용, 패턴만 차용).

## 결정 (사용자 승인 + 본 계획 확정)
- **#1 적용**: llm-wiki project 허브에 "온보딩/아키텍처 가이드" **선택 섹션** 추가(출처: Understand-Anything `understand-onboard`).
- **#2 적용**: 스킬 작성 스타일 가이드 신규 문서(출처: agentmemory 스킬 미시 구조). **위치 확정 = `plugins/pjc/skills/AUTHORING.md`**(스킬과 co-located, 발견 쉬움). 기존 8개 스킬 재작성 안 함.
- **#3 타겟만**: "빈 결과=사실대로 보고" 안티패턴은 **llm-wiki 절차 K에만** 추가. 절차 G는 이미 G-3("위키에 근거 없으면 '위키에 없음' 밝힘 + `(미검증)`")로 커버하므로 **G는 무수정**(중복 회피). 8개 스킬 일괄 적용은 안 함(전역 절대 금지 + implement-task V-8이 이미 커버).
- **버전**: plugin.json 1.63.0 → **1.64.0**(minor — 신규 문서 + wiki-schema 섹션). 승인된 push 후 GitHub 릴리즈.

## 배경
- 직전 plan.md(skill-creator 감사 8개 스킬)는 완료·커밋(0257c00)·릴리즈(v1.63.0). git 클린 → 새 계획으로 교체.
- AGENTS.md 없음. 프로젝트/글로벌 CLAUDE.md가 컨벤션 원천.

## Impact Analysis (전수 확인)
- **wiki-schema.md §2.2(project 허브)**: 진실원천 규칙 문서. 본문 구조 목록(현재 `한 줄 요약`~`## 최근 주요 변경`, line 84~91)에 **선택 섹션 1개 추가**. lint.py는 schema를 런타임에 안 읽음 → 동작 영향 0. 선택 섹션이라 기존 project 페이지 lint 위반 유발 안 함(필수 아님). version 2.14 → 2.15.
- **llm-wiki SKILL.md**: 절차 A/B에 1줄 안내(#1) + 절차 K에 안티패턴 1줄(#3). frontmatter·다른 절차 불변. 절차 G는 무수정.
- **신규 `plugins/pjc/skills/AUTHORING.md`**: 신규 파일. 어떤 스킬도 이 파일을 참조하지 않음(독립 참고 문서) → cross-file 영향 0. 플러그인 로더가 스킬로 오인하지 않도록 SKILL.md가 아닌 일반 문서로 둠(frontmatter 없음 또는 일반 md).
- **plugin.json / README L10 / notes.md**: 버전 1.63.0 → 1.64.0. marketplace.json은 version 필드 없음(손대지 않음).
- 코드 호출자·시그니처·직렬화 변경 없음. 레포 소스 편집은 현재 세션 캐시본(1.62.0)에 무영향(다음 갱신 시 적용).

## 작업 단계 (모두 Type A — markdown/json)

### T1 — #1 llm-wiki 온보딩/아키텍처 선택 섹션  [Type A]
- `references/wiki-schema.md` §2.2(project 허브) 본문 구조에 **선택 섹션** 추가 정의:
  - `## 온보딩 / 아키텍처 가이드 (선택 — 큰 프로젝트 권장)`
    - **아키텍처 레이어**: 레이어명 + 책임 한 줄 (3~7개)
    - **주요 흐름 / 가이드 투어**: 핵심 진입점 → 흐름 N단계 (신규 기여자 학습 경로)
    - **복잡도 핫스팟**: 특히 주의해서 봐야 할 영역(복잡·고위험 파일/모듈)
  - 규칙 명시: **선택 항목**(필수 아님), 내용은 **실제 코드/구조를 읽고 작성**(추측 금지 — origin/confidence 규칙 동일 적용), **온보딩 추가 시 다른 본문(기능 목록 등)을 압축해 project 예산 ~120줄을 지킨다 — 예산은 불변**.
- `SKILL.md` 절차 A의 **프로젝트 허브 생성 단계(A-2 2)**와 절차 B의 **허브 갱신 단계(B-2 1)** 직하에 "프로젝트 허브 작성/갱신 시 위 온보딩 섹션을 선택적으로 포함(큰 프로젝트 권장, 코드 기반·추측 금지)" **1줄 안내** 추가.
- `references/wiki-schema.md` frontmatter version 2.14 → 2.15.
- Acceptance: §2.2에 온보딩 선택 섹션 정의 존재 + "선택"·"추측 금지" 명시; SKILL 절차 A·B에 1줄 안내; schema version 2.15; YAML(schema frontmatter) 파싱 정상.
- Halt Forecast: 없음(문서). 예산 초과 우려 → "선택·압축" 명시로 완화.

### T2 — #2 스킬 작성 스타일 가이드 신규 문서  [Type A]
- 신규 파일 `plugins/pjc/skills/AUTHORING.md` 작성(일반 마크다운 문서, 플러그인 로더가 스킬로 오인 않도록 SKILL.md 형식·skill frontmatter 미사용).
- 내용:
  - **목적**: pjc 신규/개정 스킬 작성 시 참고하는 스타일 가이드(기존 8개 스킬 소급 재작성 의무 아님).
  - **권장 섹션 골격**: Quick start(구체 호출 예시 먼저) → Why(왜) → Workflow(번호 절차) → Anti-patterns(WRONG/RIGHT 구체 대비) → Checklist(검증 가능한 완료 기준) → See also(형제 스킬) → Troubleshooting.
  - **작성 원칙**: ① 추상 규칙(MUST 나열)보다 **실제 함정을 코드/예시(WRONG/RIGHT)로** 보여준다, ② **"왜"를 설명**(pjc 공통 지침과 일치), ③ **빈 결과 = 사실대로 보고**(없으면 "없음", 지어내지 않음), ④ 한글 작성·승인 워크플로우 등 pjc 공통 지침 준수.
  - **pjc 정합 주의**: 이 가이드는 description=트리거 1차 메커니즘, Type 분류, 자율 루프 등 pjc 고유 규칙을 대체하지 않고 보완한다(상충 시 CLAUDE.md/기존 스킬 규칙 우선).
- Acceptance: 파일 존재; 권장 섹션 골격 7개 항목 + 작성 원칙 4개 포함; skill frontmatter(`name:`/`description:` 형태의 스킬 등록용) 미포함(오탐지 방지) — grep로 확인; 한글 작성.
- Halt Forecast: ① 플러그인이 AUTHORING.md를 스킬로 로드? → SKILL.md가 아니고 skills 디렉터리의 일반 .md라 스킬 등록은 SKILL.md만 대상(구조상 무관). 우려 시 파일 상단에 "스킬 아님 — 작성 가이드 문서" 명시.

### T3 — #3 타겟: llm-wiki 절차 K 빈결과 안티패턴 1줄  [Type A]
- `SKILL.md` 절차 K(작업 참조)에 안티패턴 1줄 추가: K-3(한/영 양방향 검색) 인근에 "양방향 검색 후에도 무매칭이면 **'관련 위키 자료 없음'을 사실대로 보고하고 코드를 1차 출처로 진행**한다 — 위키에 자료가 있는 것처럼 합성·추측하지 않는다(WRONG: 무매칭인데 '위키에 ~가 있다'고 지어냄 / RIGHT: '관련 위키 자료 없음, 코드로 진행')."
- 절차 G는 **무수정**(G-3가 이미 동일 취지 커버 — 본 계획 결정).
- Acceptance: 절차 K에 "관련 위키 자료 없음"·"합성·추측하지 않는다" 취지 1줄 존재; 절차 G 변경 없음(diff에 G 미포함); YAML 파싱 정상.
- Halt Forecast: 없음.

### T4 — 버전 업 + 문서 갱신  [Type A]
- `plugins/pjc/.claude-plugin/plugin.json`: version `1.63.0` → `1.64.0`.
- `README.md` L10 `**버전**: 1.63.0` → `1.64.0`.
- `notes.md` `## 최근 변경` 최상단에 1.64.0 항목 추가(무엇/왜/검증 — 두 저장소 검토 차용 3건).
- Acceptance: plugin.json 1.64.0(JSON 파싱 OK); README L10 1.64.0; notes 1.64.0 항목; 잔존 1.63.0(이력 제외) 없음.
- Halt Forecast: 없음.

## 검증 방법
1. **wiki-schema**: version 2.15 확인 + §2.2 온보딩 선택 섹션 존재 + "선택"·"추측 금지" 문구 grep.
2. **llm-wiki SKILL.md**: 절차 A·B 1줄 안내(#1) + 절차 K 빈결과 안티패턴(#3) grep; 절차 G 무변경 확인(git diff 범위); frontmatter `yaml.safe_load` 파싱 OK.
3. **AUTHORING.md**: 파일 존재 + 섹션 골격 7개/원칙 4개 포함 grep + skill frontmatter 미포함 확인.
4. **버전**: plugin.json JSON 파싱 + 1.64.0; README L10 1.64.0; notes 1.64.0 항목.
5. wiki-schema·SKILL.md 변경이 기존 lint 정의(§7)·규칙 정의를 건드리지 않음(추가만) 확인.

## 승인 필요 항목
- 본 plan(문서 3건 + 버전) — ExitPlanMode 게이트.
- commit/push 및 GitHub 릴리즈 — 구현·검증 후 별도 승인(release-on-version-bump).

## Out of Scope (영구 제외)
- 두 저장소의 기능/인프라: knowledge-graph.json·Tree-sitter·대시보드·SQLite·MCP·벡터DB·iii-engine·캡처형 훅 일체.
- handoff/recap류 신규 재개 스킬(implement-task "T<N>부터 계속" + plan.md Next Steps로 이미 커버).
- "빈 결과" 안티패턴 8개 스킬 일괄 적용(전역 절대 금지 + V-8 중복).
- 기존 8개 스킬을 #2 미시 템플릿으로 소급 재작성(대량 개편 금지 — AUTHORING.md는 향후 참고용).

## Progress Log
- T1 완료 (Type A): #1 wiki-schema §2.2에 "온보딩/아키텍처 가이드" 선택 섹션(레이어·흐름·핫스팟) + 선택·추측금지·예산120 규칙 + version 2.15. SKILL 절차 A-2 2·B-2 1에 1줄 안내.
- T3 완료 (Type A): #3 타겟 — llm-wiki 절차 K에 "무매칭=관련 자료 없음 사실보고, 합성 금지" WRONG/RIGHT 1줄. 절차 G 무수정(G-3 이미 커버).
- T2 완료 (Type A): #2 신규 plugins/pjc/skills/AUTHORING.md — 섹션 골격 7 + 작성 원칙 4. skill frontmatter 미사용(스킬 오탐 방지). 기존 스킬 소급 재작성 안 함.
- T4 완료 (Type A): plugin.json·README → 1.64.0, notes 1.64.0 항목.
- **검증 실증**: wiki-schema v2.15+온보딩 섹션+선택/추측금지 grep OK, SKILL A/B 안내 2곳+K 안티패턴 OK, AUTHORING 골격 7/7 + skill frontmatter 없음 OK, plugin.json JSON 1.64.0·README·notes OK, llm-wiki/wiki-schema frontmatter yaml 파싱 OK, 절차 G diff 무변경 OK.
- **결정**: #3은 K만(G는 G-3 커버), #2 위치=skills/AUTHORING.md, 온보딩=선택·예산120 유지 — 사용자 승인 + 계획 확정.
