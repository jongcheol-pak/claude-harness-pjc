# 페이지 템플릿 모음 (llm-wiki)

> SKILL.md A-2/E/I에서 참조. 새 페이지 생성 시 해당 타입 템플릿을 복사해 채운다.
> 규칙·예산의 정본은 형제 문서 `wiki-schema.md`다 — SKILL.md가 모든 작업 시 선독을 지시하므로 여기서 다시 열 필요는 없다.

## 목차
- [source-stub](#source-stub)
- [project (허브)](#project-허브)
- [feature](#feature)
- [entity](#entity)
- [concept](#concept)
- [guide](#guide)
- [question](#question)
- [decision-log](#decision-log)

## source-stub
```markdown
---
type: source-stub
source_type: project-repo
project: 프로젝트명
category: personal | work
repo_path: "전체 경로"
ingested: YYYY-MM-DD
tags: [source, 프로젝트태그]
---

# 소스: 프로젝트명

- **유형**: 프로젝트 레포지토리
- **경로**: `전체 경로`
- **참조 파일**: 존재하는 문서 파일 목록
- **요약**: 한 줄 요약
- **기술 스택**: 프레임워크/라이브러리 이름만 나열 (SDK/패키지 major.minor 버전 숫자 제외 — 스텁은 불변이라 버전이 영구 stale, 버전 진실원천은 코드/csproj. `.NET 10`·`WinUI 3` 같은 제품 라인 major 식별자는 허용)
- **서브프로젝트**: (있으면) 목록
```

## project (허브)
```markdown
---
type: project
project: 프로젝트명
category: personal | work
tech_stack: ["기술1", "기술2"]
platform: windows-desktop | web | mobile | cli | cross
status: active
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
tags: [project, 카테고리, 프로젝트태그]
---

# 프로젝트명

한 줄 요약.

## 레포 정보
- **경로**: `전체 경로`
- **정본 문서**: 존재하는 문서 파일 목록
- **소스**: [[10_sources/{카테고리}/src-{태그}|소스 스텁]]

## 서브프로젝트
| 모듈 | 기술 | 역할 |
|------|------|------|

## 기능 목록
| 기능 | 한 줄 설명 | 상세 |
|------|-----------|------|
| 기능명 | 설명 | [[20_projects/{카테고리}/{프로젝트}/feat-{기능}\|상세]] |

## 관련 위키 지식
- [[30_knowledge/tech/해당기술|표시이름]] — 간단 설명

## 프로젝트 간 공유 패턴
- **패턴명**: 어떤 프로젝트와 어떻게 공유하는지

## 최근 주요 변경
- [YYYY-MM-DD] 변경 내용 한 줄
```

## feature
```markdown
---
type: feature
project: 프로젝트명
category: personal | work
feature_name: "기능명"
platform: windows-desktop | web | mobile | cli | cross
status: active   # 코드에서 제거 시 deprecated: YYYY-MM-DD 추가 (폐기 보존, wiki-schema §2.3)
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
tags: [feature, 기능태그, 프로젝트태그]
---

# 기능명

> 작성 전제: 아래 구현/동작/UI 서술은 해당 기능의 핵심 소스 파일을 실제로 읽은 뒤 작성한다(enumeration 스캔으로 대체 불가).

## 개요
기능이 무엇이고 왜 있는지.

## 관련 파일
<!-- 이 기능을 구성하는 파일의 한눈 지도 — 각주는 근거, 이 섹션은 지도 (lint §7-21이 경로 실존을 기계 검사).
     경로 표기: schema §2.3 규칙(정본) — 백틱 필수·물리 경로·brace 축약 금지 (상세는 §2.3) -->
- `ViewModels/{기능}ViewModel.cs` — 화면 로직
- `Views/{기능}Page.xaml` — 화면 레이아웃

## 동작(사용법)
사용자 관점 동작 흐름·옵션. 코드·문서로 확인된 내용만 단정 — 실행해야만 확인 가능한 서술은 `(미검증)` 표기.

## 구현 방법
핵심 클래스/패턴/데이터 흐름. 구현 상세 주장은 레포 근거 각주 `[^src-...]` 필수(각주에 소스 파일 경로 병기).
시간민감 사실은 `(as of YYYY-MM)` 표기.

## UI·UX
화면 구성, 인터랙션, 플랫폼별 UI 고려. 동작(사용법)과 동일한 근거 규칙 적용.

## 관련 지식·레시피
- [[30_knowledge/tech/기술|표시이름]] — 연결 설명

[^src-태그]: [[10_sources/{카테고리}/src-{태그}|소스: 프로젝트명]] — `ViewModels/{기능}ViewModel.cs`, `Views/{기능}Page.xaml` (근거 소스 파일 경로 병기)
```

## entity
```markdown
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

# 기술명

## 핵심
- 요약/특징

## 사용 프로젝트
| 프로젝트 | 특이점 |
|----------|--------|

## 공유 패턴 메모
- ...
```

## concept
```markdown
---
type: concept
concept_name: "패턴명"
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
related_projects: [프로젝트1, 프로젝트2]
tags: [concept, 패턴태그]
---

# 패턴명

## 개요
패턴이 무엇이고 왜 쓰는지.

## 적용 방법
핵심 기법·주의점.

## 프로젝트 사례
- [[20_projects/.../프로젝트|이름]] — 어떻게 적용했는지
```

## guide
```markdown
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

# 제목

(platform-bootstrap) ## 대상 플랫폼 / ## 기본 프로젝트 생성 / ## 권장 구조 / ## 필수 의존성 / ## UI/UX 기본 / ## 체크리스트
(ui-ux) UI/UX 규칙 섹션들
(recipe) ## 목적 / ## 적용 플랫폼 / ## 단계 / ## 코드 스니펫 / ## 사용 프로젝트 사례 / ## 주의점 / 함정(선택 — 함정형 recipe 권장, wiki-schema §2.6)
```

## question
```markdown
---
type: question
status: open | investigating | resolved
priority: high | medium | low
related_pages: ["[[경로|이름]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [question, 관련태그]
---

# 질문/모순 요약

- **상황**: 무엇이 충돌/미해결인가
- **관련 페이지**: [[...]]
- **현재 판단**: (잠정)
```

## decision-log
```markdown
---
type: decision-log
project: 프로젝트명
category: personal | work
updated: YYYY-MM-DD
tags: [decision-log, 프로젝트태그]
---

# 프로젝트명 결정 이력

<!-- 항목 불변: 기록된 결정은 수정·삭제하지 않는다 — 결정이 바뀌면 "번복" 항목을 새로 추가(같은 주제어 재사용, wiki-schema §2.8).
     어휘 고정: 채택 | 보류 | 기각 | 번복. 최신이 위. 예산 150줄 초과 시 오래된 항목부터 90_archive 원경로 이동.
     기록 수준: LLM이 이 기록만 보고 사용자에게 결정 배경을 설명할 수 있어야 함 — 사유가 다층적이거나
     재검토 조건이 있으면 하위 불릿 1~2줄 추가(하위 불릿 포함이 한 항목 — 롤오버 시 쪼개지 않음).
     롤오버 시 하단에 "## 아카이브" 포인터 1줄 유지·갱신 필수(§2.8 — 누락 시 오래된 결정 검색 유실, lint §7-24). -->
- [YYYY-MM-DD] {주제} — **{채택|보류|기각|번복}**: {요지·근거 1줄}
  - 재검토 조건·기각한 대안 등 보충 (필요한 결정만, 1~2줄)
```
