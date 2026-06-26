---
type: schema
version: "2.16"
updated: 2026-06-26
language: ko
---

# 위키 규칙 — llm-wiki 번들 (규칙 진실원천)

> 이 파일은 위키의 헌법이다. llm-wiki 스킬은 모든 작업 시 이 파일을 먼저 읽고 규칙을 따른다.
> 실행 절차(A~K)는 `SKILL.md`에 있다. vault에는 이 규칙의 사본을 두지 않는다(번들만 사용).

## 목차
1. 위키 개요 / 핵심 원칙·3대 용도
2. 페이지 타입 정의 (source-stub/project/feature/entity/concept/guide/question)
3. 네이밍 / 태깅 / 링킹 / 통제 어휘 (platform·스택)
4. 파일 예산
5. Ingest 워크플로우
6. Query / 작업 참조 워크플로우
7. Lint 워크플로우
8. 압축 / 아카이브 규칙
9. 운영 세션 가이드
10. Obsidian 설정 요구사항
11. 사용자 검증

## 1. 위키 개요

LLM이 지속적으로 위키를 작성·유지·갱신하는 개인 지식베이스. 사람은 소스를 제공하고 질문하며, LLM은 마크다운 위키를 관리한다.

**3계층**: Raw Sources(불변 소스) → Wiki(LLM 관리) → Schema(이 파일)

**핵심 원칙**: 위키는 **자기완결적 상세 지식베이스**다. 레포 문서(CLAUDE.md/README.md/notes.md)를 출처로 삼되, 각 프로젝트의 **기능·구현 방법·UI/UX·동작(사용법)** 의 핵심 상세와 **신규 프로젝트 생성 가이드**를 검색·재사용 가능한 형태로 위키에 담는다. 단순 전체 복붙이 아니라 정제·구조화한다. 동시에 프로젝트 간 관계와 크로스-커팅 지식도 함께 축적한다.

**출처 우선순위(고정)**: **실제 코드 > 레포 문서(README/notes/CLAUDE.md) > 모델 추론(금지)**. 레포 문서와 실제 코드가 충돌하면 **코드를 따르고**, 충돌 사실을 `30_knowledge/questions/`에 기록한다(레포 문서 수정은 위키 작업 범위 밖). 모델 기억만으로 사실을 단정 서술하지 않는다.

**3대 용도**:
1. 기존 프로젝트의 기능/구현/UI/동작 상세 설명 (→ `feature`)
2. 신규 프로젝트용 플랫폼별 UI/UX·기본 생성법·필요 기능 가이드 (→ `guide`)
3. 필요 기능/정보를 위키에서 검색 (→ `index.md` 기능별 인덱스 + 태그 + `dashboard.md`)

---

## 2. 페이지 타입 정의

### 2.1 source-stub (소스 스텁)
- **위치**: `10_sources/{personal|work}/`
- **역할**: 원본 소스에 대한 불변 참조
- **예산**: ~30줄
- **불변 규칙**: 생성 후 수정 금지
- **휘발성 사실 금지**: "기술 스택" 줄에 SDK/패키지 **major.minor 이상 버전·수치를 적지 않는다**(프레임워크/라이브러리 **이름만** — 예 `.NET 10`, `WinUI 3`, `Windows App SDK`). 버전은 시간에 따라 바뀌는데 스텁은 불변이라 영구 stale이 된다. 정확한 버전의 진실원천은 **코드(csproj)**. (불변이므로 교차 sweep §5 대상에서 제외 — 그래서 휘발성 사실을 애초에 두지 않는다.)

```yaml
---
type: source-stub
source_type: project-repo | document | conversation | article
project: 프로젝트명
category: personal | work
repo_path: "D:/경로"
ingested: YYYY-MM-DD
tags: [source, 프로젝트태그]
---
```

### 2.2 project (프로젝트 허브)
- **위치**: `20_projects/{personal|work}/`
- **역할**: 프로젝트의 **허브** — 개요 + 기능 목록(feature 페이지 인덱스) + 크로스참조
- **예산**: ~120줄

```yaml
---
type: project
project: 프로젝트명
category: personal | work
tech_stack: ["기술1", "기술2"]
platform: windows-desktop | web | mobile | cli | cross
status: active | paused | archived
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
tags: [project, 카테고리, 프로젝트태그]
---
```

**본문 구조**:
- 한 줄 요약
- 레포 경로 / 정본 문서 / 소스 스텁 링크
- 기술 스택 요약 + 아키텍처 한 줄
- `## 기능 목록`: 이 프로젝트의 feature 페이지 링크 표 (기능명 / 한 줄 설명 / feature 링크)
- `## 관련 위키 지식`: 존재하는 `30_knowledge/`·`40_guides/` 페이지 링크
- `## 프로젝트 간 공유 패턴`: 다른 프로젝트와 공유하는 기술/패턴
- `## 최근 주요 변경`: 3~5개 (날짜 + 한 줄)
- `## 온보딩 / 아키텍처 가이드` **(선택 — 큰 프로젝트 권장)**: 신규 기여자·세션이 구조를 빠르게 잡도록 돕는 섹션. 세 부분으로 구성한다:
  - **아키텍처 레이어**: 레이어명 + 책임 한 줄 (3~7개)
  - **주요 흐름 / 가이드 투어**: 핵심 진입점 → 동작 흐름 N단계 (학습 경로)
  - **복잡도 핫스팟**: 특히 주의해서 볼 영역(복잡·고위험 파일/모듈)과 이유 한 줄

> **온보딩 섹션 규칙**: **선택 항목**(필수 아님 — lint가 강제하지 않는다). 내용은 **실제 코드/구조를 읽고 작성**하며 추측하지 않는다(origin/confidence 규칙 동일 적용). 온보딩을 추가할 때는 다른 본문(기능 목록 등)을 압축해 **project 예산 ~120줄을 지킨다**(예산은 불변).

> **tech_stack 휘발성 버전 금지**: frontmatter `tech_stack`·본문에 SDK/패키지 major.minor 이상 버전을 적지 않는다(이름만 — `.NET 10`·`WinUI 3` 같은 제품 라인 major 식별자는 허용). 정확한 버전 진실원천은 코드(csproj). entity `## 핵심` 구성줄도 동일.

### 2.3 feature (기능 상세) — 신규
- **위치**: `20_projects/{personal|work}/{프로젝트명}/feat-{기능명}.md`
- **역할**: 한 프로젝트의 특정 기능에 대한 **상세** 설명 (목표 ①)
- **예산**: ~180줄 (초과 시 하위 기능으로 분리)

```yaml
---
type: feature
project: 프로젝트명
category: personal | work
feature_name: "기능명"
platform: windows-desktop | web | mobile | cli | cross
status: active | paused | archived
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
tags: [feature, 기능태그, 프로젝트태그]
---
```

**작성 전제(필수)**: 구현 방법·동작(사용법)·UI·UX 섹션은 해당 기능의 **핵심 소스 파일을 실제로 읽은 뒤** 작성한다 — A-1식 진입점 enumeration 스캔(파일명·클래스명 열거)으로 대체할 수 없다. 파일명·클래스명만 보고 내부 동작을 추론해 서술하는 것 금지.

**본문 필수 섹션**:
- `## 개요`: 기능이 무엇이고 왜 있는지
- `## 동작(사용법)`: 사용자 관점 동작 흐름·옵션. **코드·레포 문서로 확인된 내용만 단정 서술** — 실행해야만 확인 가능한 서술(런타임 체감·실측 거동 등)은 `(미검증)` 표기
- `## 구현 방법`: 핵심 클래스/패턴/데이터 흐름 (구현 상세 주장은 레포 근거 각주 `[^src-...]` 필수 + **각주에 근거 소스 파일 경로(레포 상대경로) 병기**)
- `## UI·UX`: 화면 구성, 인터랙션, 플랫폼별 UI 고려. 동작(사용법)과 동일한 근거 규칙 적용
- `## 관련 지식·레시피`: 연결되는 entity/concept/guide 링크

**폐기 표시(옵션 필드)**: 코드에서 제거된 기능은 삭제 대신 옵션 필드 `deprecated: YYYY-MM-DD`(또는 `status: deprecated`)로 보존할 수 있다(SKILL B-1a — 이력 보존용, 절차 K 참조 시 현재 기능과 구분). 폐기 시 페이지 상단에 "⚠️ 코드에서 제거됨" 안내를 적고, **프로젝트 허브에서는 "## 폐기된 기능" 구역으로 옮겨 링크를 유지**한다(허브에서 링크를 완전히 제거하면 Lint 허브 동기화가 누락으로 오인). project 허브도 동일 방식으로 폐기 표시할 수 있다.

### 2.4 entity (엔티티)
- **위치**: `30_knowledge/tech/`
- **역할**: 특정 기술/라이브러리에 대한 크로스 프로젝트 지식
- **예산**: ~100줄

```yaml
---
type: entity
entity_name: "기술명"
domain: tech
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
used_by: [프로젝트1, 프로젝트2]
tags: [entity, 기술태그]
---
```

### 2.5 concept (개념)
- **위치**: `30_knowledge/patterns/`
- **역할**: 여러 프로젝트에 걸친 범용 패턴/원칙. synthesis(종합)도 이 타입.
- **예산**: ~80줄
- **생성 조건**: 2개 이상 프로젝트에서 실증된 패턴만.

```yaml
---
type: concept
concept_name: "패턴명"
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
related_projects: [프로젝트1, 프로젝트2]
tags: [concept, 패턴태그]
---
```

### 2.6 guide (가이드/레시피) — 신규
- **위치**: `40_guides/platforms/` · `40_guides/ui-ux/` · `40_guides/recipes/{스택}/`
- **역할**: 신규 프로젝트용 **선행형** 지식 + **특정 기능 추가**(프로젝트 추가 아님) 시의 기능 구현 지식 (목표 ②). 기존 프로젝트에서 추출하지 않아도 선제 작성 가능.
- **recipe 폴더 분류**: recipe는 항상 **스택 하위 폴더**(`winui`/`csharp`/`unity` 등)에 둔다. 특정 기능 추가 요청은 그 기능이 속한 스택 폴더에 recipe로 적재한다.
- **실증 면제**: concept과 달리 "2개 프로젝트 실증" 조건을 적용하지 않는다. 출처는 공식 문서 + 실제 프로젝트 사례.
- **예산**: platform-bootstrap ~200줄, ui-ux ~150줄, recipe ~120줄

```yaml
---
type: guide
guide_kind: platform-bootstrap | ui-ux | recipe
platform: windows-desktop | web | mobile | cli | cross
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
related_projects: [프로젝트1]
tags: [guide, recipe, 플랫폼태그]
---
```

**본문 — platform-bootstrap**: `## 대상 플랫폼` / `## 기본 프로젝트 생성` / `## 권장 구조` / `## 필수 의존성` / `## UI/UX 기본` / `## 체크리스트`
**본문 — recipe**: `## 목적` / `## 적용 플랫폼` / `## 단계` / `## 코드 스니펫` / `## 사용 프로젝트 사례`

**코드 스니펫 출처 규칙(전 guide 공통)**: 스니펫은 ① **실제 프로젝트 소스에서 추출**(각주에 소스 파일 경로 병기) 또는 ② **공식 문서 예제 인용**(출처 링크 각주)만 허용. **모델 기억만으로 스니펫 작성 금지** — 불가피하게 포함할 때는 `(미검증)` 표기 + `confidence: low`.

### 2.7 question (질문)
- **위치**: `30_knowledge/questions/`
- **역할**: 미해결 질문, 모순, 탐구 필요 사항
- **예산**: ~40줄
- resolved 시 관련 페이지에 내용을 흡수하고 frontmatter를 `status: resolved`로 표시한다. **페이지 자체는 삭제하지 않고 보존한다**(해결 이력도 지식 — 같은 질문 재조사 방지). 이는 SKILL B-2 3-1·Lint §7-12(`status != resolved` 집계)와 일치한다.

```yaml
---
type: question
status: open | investigating | resolved
priority: high | medium | low
related_pages: ["[[경로|이름]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [question, 관련태그]
---
```

---

## 3. 네이밍 / 태깅 / 링킹 / 통제 어휘

### 파일 네이밍
| 대상 | 규칙 | 예시 |
|------|------|------|
| 소스 스텁 | `src-{영문소문자}.md` | `src-devdashboard.md` |
| 프로젝트 허브 | `{영문소문자하이픈}.md` | `devdashboard-winui.md` |
| feature | `{프로젝트폴더}/feat-{영문소문자하이픈}.md` | `devdashboard-winui/feat-project-cards.md` |
| entity | `{영문소문자하이픈}.md` | `winui3.md` |
| concept | `{영문소문자하이픈}.md` | `multi-monitor-dpi.md` |
| guide (platform/ui-ux) | `{platforms|ui-ux}/{영문소문자하이픈}.md` | `platforms/winui3-bootstrap.md` |
| guide (recipe) | `recipes/{스택}/{영문소문자하이픈}.md` | `recipes/winui/startup-autostart.md` |
| 질문 | `q-{YYYYMMDD}-{짧은설명}.md` | `q-20260607-scrollview-issue.md` |

### Wikilink 규칙
- 형식: `[[경로/파일명|한글 표시이름]]` (명시적 경로 필수)
- 존재하지 않는 페이지로의 링크 생성 금지
- Obsidian 테이블 안에서는 `\|`로 파이프 이스케이프
- 출처 표기: 인라인 각주 `[^src-이름]` + 소스 스텁 링크 병기. **구현 상세 각주에는 근거 소스 파일 경로(레포 상대경로, 백틱)를 병기**한다 — 예: `[^src-foo]: [[10_sources/personal/src-foo|소스: Foo]] — ViewModels/BarViewModel.cs, Views/BarPage.xaml`

### 기능별 인덱스 한/영 양방향 병기 (검색 정합, 필수)
- `index.md`(또는 sub-index) 기능별 인덱스 행의 **첫 컬럼(기능명)에 한글 키워드와 영문 키워드를 모두 병기**한다 — 한글로 등록하든 영문 기술용어로 등록하든 **한쪽만 적지 않는다**(한글 검색·영문 검색 어느 쪽이든 한 줄에서 잡히게). 영문은 feature 파일명·코드 식별자에서, 한글은 기능 설명에서 가져온다. lint이 병기 누락을 검사(§7-16).

### 태그 / 통제 어휘
- 계층 태그: `project`, `feature`, `entity`, `concept`, `guide`, `recipe`, `question`, `source`
- 기술 태그: `winui3`, `rust`, `dotnet`, `tauri`, `mvvm`, `sqlite`, `wpf` …
- 기능 태그: `tray`, `dpi`, `notification`, `launcher`, `drag-drop`, `import-export` …
- UI 태그: `xaml`, `navigation`, `theming`, `dialog`, `localization` …
- **`platform` 통제 어휘(고정)**: `windows-desktop` | `web` | `mobile` | `cli` | `cross`
- **`origin` 통제 어휘(고정)**: `agent-synthesized` | `human-validated` — project/feature/entity/concept/guide 공통 필수 필드
- **`confidence` 통제 어휘(고정)**: `high` | `medium` | `low` — project/feature/entity/concept/guide 공통 필수 필드
- **`스택`(recipe 폴더 분류, 개방 목록)**: 프레임워크/언어 기준 — `winui` | `wpf` | `csharp` | `dotnet` | `unity` | `rust` | `web` | `tauri` … 가장 구체적인 것을 선택(예: WinUI 전용은 `winui`, 언어 일반은 `csharp`).

---

## 4. 파일 예산

| 파일 유형 | 최대 줄 수 | 초과 시 행동 |
|-----------|-----------|-------------|
| source-stub | 30줄 | 초과 불가 (불변) |
| project (허브) | 120줄 | 최근 변경 내역 압축 |
| feature | 180줄 | 하위 기능을 별도 feature 페이지로 분리 |
| entity | 100줄 | 하위 주제를 별도 페이지로 분리 |
| concept | 80줄 | 핵심만 남기고 상세는 링크로 대체 |
| guide (platform-bootstrap) | 200줄 | 하위 주제 분리 |
| guide (ui-ux) | 150줄 | 분리 |
| guide (recipe) | 120줄 | 분리 |
| question | 40줄 | resolved 시 관련 페이지에 흡수 + `status: resolved` 표시(보존, §2.7) |
| log.md | 60줄 | 오래된 기록 한 줄 압축 |
| index.md | 제한 없음 (**1단계(소제목 구역화 — 사람 판단 가이드)**: 기능별 인덱스가 비대해지면(대략 본문 80% ≈ 320줄 또는 기능별 인덱스 160행) 소제목으로 구역을 나눈다. **2단계(파일 분할 — lint 기계 신호)**: **본문(frontmatter 포함 전체) 400줄 초과 또는 기능별 인덱스 200행 초과**면 lint이 INFO로 분할을 제안한다(`INDEX_BODY_LINES`/`INDEX_FEAT_ROWS`). 이때 **vault의 기존 category 기준**(`index-personal.md`/`index-work.md`)으로 파일 분할 — 새 분류를 만들지 말고 이미 확립된 personal/work를 따라야 feature가 어느 sub-index인지 그 프로젝트 category로 자동 결정된다. 분할 시 **`index.md` 상단에 sub-index 파일 목록을 반드시 유지** — 절차 K·검색이 `index.md`만 보고도 분할 파일을 찾을 수 있어야 함. **분할 상태에서는 이 문서의 모든 "`index.md` 기능별 인덱스 갱신/제거/표기" 지시가 해당 category의 sub-index 파일에 적용된다** — 기능별 인덱스 항목의 추가·삭제·폐기 표기는 항상 그 항목이 속한 sub-index에서 수행한다. 단 `## 미해결 질문`처럼 category(personal/work)로 분할되지 않는 섹션은 `index.md` 본체에 그대로 두고 거기서 닫는다. `index.md` 본체는 sub-index 목록 + 이런 비분할 섹션만 최신으로 유지한다. **sub-index 비대 시(3단계 없음)**: 분할된 `index-*.md` 자체가 임계(본문 400줄/기능별 인덱스 200행)를 넘으면 lint이 INFO로 알린다 — personal/work는 종착 분류이므로 추가 파일 분할이 아니라 **소제목 구역화(1단계)로 정리**한다(새 분류를 만들지 않는다는 원칙 유지). 분할된 sub-index는 `## 기능별 인덱스` 섹션을 그대로 보유한다 — lint의 행수 측정·동기화 검사가 이 헤딩을 기준으로 한다.) | - |

- 예산 80% 도달 시 압축 시작
- 압축 형식: `[YYYY-MM-DD] 한줄요약`
- **log.md 항목은 2~3문장 이내 요지만 기록**(갱신 파일 목록·세부 근거는 해당 페이지에 — log는 무엇을 했는지만). 토큰 비대 방지: log는 모든 위키 작업에서 읽히는 파일이다
- **상세 콘텐츠(feature/guide)는 삭제 대신 하위 페이지 분리가 원칙.** 날짜·결론·핵심 코드 스니펫은 절대 삭제 금지.
- 소스 스텁, 설계 결정의 핵심은 절대 삭제 금지

---

## 5. Ingest 워크플로우

> 새 소스(프로젝트 변경분, 문서 등)를 위키에 반영할 때

### 필수 단계
0. **교차 sweep (stale 드리프트 차단)**: 변경된 사실이 여러 페이지에 중복 기재됐을 수 있으니, 갱신 전 그 사실을 위키 전체에서 `grep`해 **나온 곳을 모두 일괄 갱신**한다. **단 `10_sources/` 소스 스텁은 불변(§2.1)이라 sweep 대상에서 제외** — 그러므로 휘발성 사실(SDK/패키지 버전 등)을 애초에 스텁에 두지 않는다(이름만). (절차: 스킬 "B-2 0번")
1. 이 규칙 문서 읽기
2. 대상 프로젝트의 레포 문서(notes.md, README.md, CLAUDE.md) 변경분 확인 + **신규 프로젝트 등록 시 UI/기능 진입점 소스 스캔(Views/ViewModels/라우트 등)으로 문서 미기재 기능까지 열거**(전체 기능 목록 도출). feature 망라·누락 검증의 기준이 된다.
2a. **기존 프로젝트 갱신 시 망라 재대조(경량, 필수)**: 델타만으로는 조용히 제거·이름변경된 기능을 놓치므로, A-1식 진입점 enumeration(Grep/Glob, deep read 아님)으로 현재 기능을 열거해 위키 feature/index와 대조한다. **추가**는 feature 생성, **제거/이름변경 후보**는 **자동 삭제 금지·사용자 확인**(승인 시에만 §C-3에 준해 정리), 불확실 시 question 기록. 무거운 정합은 Lint의 **코드 정합 샘플링**(§7-10, 에이전트 수행)에 위임. (절차: 스킬 "B-1a")
2b. **델타 신뢰도 점검**: 위키 허브의 `updated`가 **30일 초과**면 레포 notes.md(1개월 보존 규칙)에서 그 사이 변경분이 이미 삭제됐을 수 있다 — git 저장소면 `git log`로 보완하고, git이 아니면 notes 델타를 신뢰하지 말고 갱신 대상 feature의 **소스 직접 대조**로 강도를 올린다. (임계 30일은 notes 보존 기간에서 유도 — Lint 신선도 60/90일과는 목적이 다른 별개 임계)
3. 해당 프로젝트 허브(`20_projects/`) 및 관련 feature 페이지(`20_projects/{proj}/`) 갱신. **feature의 구현/동작/UI 서술은 신규 작성·갱신 모두 해당 기능의 소스 파일을 실제로 읽은 뒤 작성한다**(§2.3 작성 전제 — enumeration 스캔으로 대체 불가)
3a. **recipe 승격 확인 (필수 게이트)**: feature 망라/신규 생성 후, 재사용 가능한 비자명 함정(구현 트랩·플랫폼 제약·성능/안정성 트릭)을 후보로 모아 **코드 스니펫 recipe 승격 여부를 항상 사용자에게 묻는다**(에이전트 단독 자동 승격 금지). 승인 시 §2.6 recipe로 작성(스택 폴더 + `[^src-...]` 각주 + index 등록 + feature 상호링크), 거절 시 feature 산문 유지. 후보 0개면 그 사실만 보고하고 질문 생략. (절차: 스킬 "A-3a")
4. **기능별 인덱스 동기화**: 새/변경 feature는 `index.md`의 "기능별 인덱스"에 행 추가·갱신
5. 크로스 프로젝트 패턴 발견 시 관련 지식 페이지(`30_knowledge/`) 갱신
6. `log.md`에 1줄 기록 추가

### 선택 단계 (필요 시)
7. `index.md` 갱신 (새 페이지 생성 시)
8. 새 지식 페이지(entity/concept) 생성 — 2개 이상 프로젝트에서 실증된 경우만
9. 가이드/레시피 작성 — 선행형, 실증 면제 (스킬 `SKILL.md` "I. 가이드/레시피 작성" 참조)
10. 모든 수정 파일의 예산 준수 확인

### 소스 스텁 규칙
- 새 프로젝트 최초 등록 시에만 소스 스텁 생성, 생성 후 불변
- 기존 프로젝트의 변경분 반영은 허브/feature 페이지에서 처리

### 복리 효과 규칙
- **지식/레시피(entity/concept/guide)에만 적용**: 위키 소스 20개 이상이면 기존 지식 페이지 업데이트 우선(신규 최소화).
- **feature 페이지는 예외**: 기능 단위로 적극 생성한다(중복만 방지). 상세 축적이 목적이므로 신규 억제 규칙을 적용하지 않는다. **프로젝트 최초 등록 시 주요 기능/화면 전체를 망라**한다(핵심 일부만 만들고 미루지 않는다).

---

## 6. Query / 작업 참조 워크플로우

> 위키에 질문할 때

1. 이 규칙 문서 읽기
2. `index.md`의 "기능별 인덱스" / 카탈로그에서 관련 페이지 식별 (`index.md` 상단에 sub-index 파일 목록이 있으면 관련 카테고리 sub-index도 함께 읽음)
3. 관련 feature/guide/지식 페이지 읽고 답변 합성 (출처 각주 필수)
4. 답변이 유용한 종합이면 → concept 페이지 생성 고려 (2개 실증 시)
5. 모순 발견 시 → question 페이지 생성
6. `origin: agent-synthesized` 표시 (사용자 미검증)

### 작업 참조 (코드 작업 세션 read-only)

> 코드 프로젝트 세션에서 기능 구현·버그 수정 전에 위키를 참고할 때.
> **절차 전문은 스킬 `SKILL.md` "K. 작업 참조"에 단일 정의** — 인덱스 식별 → 식별 페이지만 read → 소스 점프 → `origin`/`confidence` 반영.
> 규칙 측 핵심(불변): 이 워크플로는 **read-only**다. 모순·드리프트(위키↔코드 불일치)를 발견해도 위키를 수정하지 않고 사용자에게 보고만 하며, `log.md`도 남기지 않는다(위키 무변경). 반영은 별도 세션 §5(ingest)/§7(lint)에서 처리한다.

---

## 7. Lint 워크플로우

> 주기적 건강 검진. 별도 세션에서 월 1회(로컬 스케줄 자동 실행 권장) 또는 수동 트리거.

### 검사 항목
1. **참조 무결성**: 깨진 wikilink 탐색 및 수정/제거 (`20_projects/{proj}/`, `40_guides/` 포함)
2. **예산 준수**: 모든 파일 줄 수 확인, 초과 시 압축/분리
3. **신선도**: `updated` 기준 60일 미편집 → confidence 하락, 90일 → 아카이브 후보 제시. **feature/guide는 검색형 핵심 콘텐츠이므로 시간기반 아카이브 제외**(confidence 하락만, 이동 금지)
4. **모순 탐색**: 동일 주제 상충 기술 → question 페이지 생성
5. **크로스참조 품질**: 누락된 연결 제안, 프로젝트 tech_stack ↔ entity `used_by` 일치 확인
6. **기능별 인덱스 동기화**: `index.md` 기능별 인덱스 ↔ 실제 feature 페이지 일치 확인
7. **통제 어휘 위반**: `platform` 값이 고정 어휘를 벗어났는지 검사
8. **고아/비표준 파일**: 어디서도 링크되지 않는 페이지, 타입 미지정 파일 탐색
9. **미래/이상 날짜**: `updated`·본문 날짜가 오늘보다 미래거나 비정상인지 검사 (데이터 위생)
10. **코드 정합 샘플링**: 프로젝트당 feature 1~2개를 표본으로 골라 ① 각주에 병기된 소스 파일 경로가 레포에 실재하는지 ② 핵심 서술(구현/동작)이 실제 코드와 일치하는지 대조. 불일치는 question 페이지에 기록. **보수 판정 정책**: 사실 오류만 flag(문서 누락·스타일은 무시), 최근 `log.md` 이력을 대조해 이미 수정된 이슈는 재-flag하지 않는다. (**에이전트 수행 — lint.py 범위 아님**)
11. **tech_stack 휘발성 버전**: 소스 스텁 "기술 스택" 줄 + project 허브 `tech_stack` frontmatter에 major.minor 이상 버전(`\d+\.\d+`)이 있으면 경고(§2.1·§2.2 — 이름만 기재, 버전 진실원천은 코드). entity/feature 본문 산문은 오탐 위험으로 기계 검사 제외(규칙으로 보완). (lint.py 검사)
12. **(미검증)·미해결 question 집계**: ⓐ `20_/30_/40_` 콘텐츠 페이지 본문(frontmatter 제외, `90_archive` 제외)의 `(미검증)` 표기 발생 수·파일 수 ⓑ `type: question` ∧ `status != resolved` 파일 수를 **정보(INFO) 등급**으로 집계 리포트(0건이면 생략). `10_sources`는 불변 스텁이라 검증 루프 대상이 아니므로 제외. (lint.py 검사 — §11 사용자 검증 후보 공급)
13. **잠재 연결 발견 (크로스-프로젝트 미연결 공통점)**: 전 프로젝트 허브의 `tech_stack`·기능 목록·"프로젝트 간 공유 패턴"을 가로질러, 아직 `30_knowledge/` 지식 페이지나 허브 "공유 패턴" 링크로 묶이지 않은 **2개 이상 프로젝트의 공통점**(공유 기술/패턴/접근/함정)을 발굴해 후보로 제안한다. 5번(크로스참조 품질)이 *기존* 지식 페이지의 정합성(tech_stack↔used_by) 점검이라면, 이 항목은 *신규* 연결의 발굴이다. 위키의 명시 목적(크로스-커팅 지식 축적)을 ingest 시점에만 의존하지 않고 주기적으로 회수하는 장치. **보수 정책**: tech_stack 일치·동일 명명 패턴 등 구체적 근거가 있는 공통점만 제안(추측 링크 금지), 기존 지식 페이지·공유 패턴 링크와 중복 제외, `log.md` 이력으로 이미 처리된 후보는 재-제안 금지. **자동 생성 금지** — 후보만 정보(INFO) 등급으로 제시하고, 사용자 승인 시에만 §2.5 concept(2개 실증 충족) 또는 §2.4 entity 생성, 혹은 허브 "프로젝트 간 공유 패턴" 상호링크로 반영. (에이전트 수행 — lint.py 범위 아님)
14. **index.md·sub-index 분할 신호**: index.md 본문(frontmatter 포함 전체) 줄 수 또는 기능별 인덱스 표 행 수, **그리고 각 sub-index(`index-*.md`)의 본문 줄 수·기능별 인덱스 행 수**가 임계(`INDEX_BODY_LINES` 400 / `INDEX_FEAT_ROWS` 200) 초과면 INFO로 분할을 제안한다(index.md는 §4 2단계 파일 분할, sub-index는 §4에 따라 소제목 구역화 — 추가 파일 분할 없음). (lint.py 검사)
15. **sub-index 목록 정합**: vault에 실재하는 sub-index 파일(`index-*.md`)이 `index.md`에 언급(목록 등록)됐는지 — 미등록이면 WARN(절차 K·검색이 분할 인덱스를 빠뜨리지 않게). 역방향(목록엔 있으나 파일 없음)은 깨진 wikilink 검사(1번)가 커버한다. (lint.py 검사)
16. **기능별 인덱스 한/영 병기**: 기능별 인덱스 행(feature/recipe)의 첫 컬럼(기능명)에 한글(`[가-힣]`)과 영문(`[A-Za-z]`)이 모두 있는지 — 한쪽만이면 WARN. 한글로 등록하든 영문 기술용어로 등록하든 양방향 검색이 한 줄에서 되도록(§3 기능별 인덱스 한/영 병기). (lint.py 검사)

### 결과 처리
- `log.md`에 Lint 결과 요약 1줄 추가
- 심각한 이슈 → question 페이지 생성
- 아카이브는 자동 이동이 아닌 "후보 목록" 제시

---

## 8. 압축 / 아카이브 규칙

### 압축 (Compaction)
- 예산 80% 도달 시 오래된 정보를 `[YYYY-MM-DD] 한줄요약`으로 압축
- 날짜와 핵심 결론은 반드시 보존
- **feature/guide는 압축(삭제) 대신 하위 페이지 분리**

### 아카이브
- 60일 미편집: confidence 한 단계 하락 (high → medium → low)
- confidence 하락은 `confidence` 필드를 보유한 모든 타입(project·feature 포함)에 적용된다
- 90일 미편집: `90_archive/`로 이동 후보 제시 (사용자 승인 후 이동)
- **예외 1**: `status: paused`인 페이지는 시간 기반 신선도 처리 전체(60일 confidence 하락, 90일 아카이브)에서 제외
- **예외 2**: `feature`·`guide` 타입은 시간 기반 아카이브 제외 (confidence 하락만 적용, 이동하지 않음)
- 아카이브 구조: 원래 경로를 `90_archive/` 하위에 재현
- 부활: 아카이브 페이지가 다시 참조되면 원래 위치로 복귀

---

## 9. 운영 세션 가이드

### wiki 전용 세션 (코드 작업과 분리)
- **시점**: 코드 작업 완료 후 별도로 wiki vault에서 세션 실행
- **트리거**: 수동 요청 (예: "위키 업데이트", "DevDashboard 변경분 반영")
- **빈도**: 주 1~2회 또는 주요 기능 구현 후

### 세션 흐름
1. 이 규칙 문서 읽기
2. 사용자가 지정한 프로젝트의 레포 문서 변경분 확인
3. Ingest 워크플로우 필수 단계 실행
4. 완료 보고 (갱신 파일 목록 + 변경 요약)

### 금지 사항
- 코드 작업 세션에서 wiki 갱신 혼합 금지 — 단 **read-only 참조(절차 K, §6)는 허용**(쓰기만 금지)
- Lint는 Ingest 세션과 별도로 실행

### 병렬 다중 에이전트 분업 규칙
> **한 위키 세션 내부**에서 다중 에이전트를 병렬 실행할 때의 동시성 통제(위 금지 사항은 세션 **간** 혼합 금지 — 차원이 다름).
- **쓰기 파일 소유권 분할**: 각 에이전트는 자기 담당 페이지(예: 자기 프로젝트의 `feat-*.md`, 자기 담당 신규 recipe)만 쓴다. 담당 분할은 겹침 없이 사전 지정.
- **공유 파일은 호스트 전담**: `index.md`·`log.md`·`plan.md`·`dashboard.md`·프로젝트 허브는 에이전트 쓰기 금지 — 호스트(메인 세션)가 에이전트 완료 후 일괄 갱신.
- **발견사항은 반환값으로만**: 코드에 없는 기능·모순·recipe 후보·index 등록 데이터는 파일 생성 대신 반환값으로 보고하고 호스트가 일괄 처리(question 페이지 동시 생성 충돌 방지).
- **공유 페이지는 단일 에이전트 전담**: 여러 프로젝트가 걸린 concept 등은 한 에이전트만 쓰기, 나머지는 read만.

---

## 10. Obsidian 설정 요구사항

### 필수 설정
- Settings → Files & Links → New link format: **Relative path to file**
- Settings → Files & Links → Use [[Wikilinks]]: **활성화**

### 권장 플러그인
- **Dataview**: dashboard.md의 동적 쿼리 사용 시 필요 (없어도 위키 동작에 지장 없음)
- **Graph View**: 기본 제공. 페이지 연결 시각화 및 고아 페이지 발견
- **Templates**: 새 페이지 생성 시 타입별 템플릿 활용 (이 파일의 frontmatter 참조)

---

## 11. 사용자 검증

- 적용 대상: `origin` 필드를 보유한 전 타입 — **project/feature 포함**, entity/concept/guide
- `origin: agent-synthesized`인 페이지는 미검증 상태
- LLM은 미검증 페이지 인용 시 `(미검증)` 표기
- 사용자 검증 후 `origin: human-validated`로 변경
- 코드 재대조 없이 작성·유지된 기존 feature/project 페이지는 `confidence: medium` 이하로 표시한다(재대조 후 상향)
- Lint 집계 INFO(§7-12 — `(미검증)` 표기·미해결 question)가 1건 이상이면 결과 보고 시 **사용자 검증 후보로 명시 보고**한다(표기만 하고 방치하지 않는 회수 장치)
- 이 규칙 번들의 **설계 방향 전환**은 사용자 명시적 요청 시에만 허용 (구조를 실제 위키 상태에 맞추는 자동 갱신은 스킬 "H" 범위)
