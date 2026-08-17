# 페이지 템플릿 모음 (llm-wiki)

> `references/procedures-content.md` A-2/E/I에서 참조. 새 페이지 생성 시 해당 타입 템플릿을 복사해 채운다.
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
- [convention](#convention)

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
description: "한 줄 요약 (권장 — wiki-schema §12, 검색·인덱스 스니펫용)"
tech_stack: ["기술1", "기술2"]
platform: windows-desktop | web | mobile | cli | cross
status: active
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
synced_commit: <레포 커밋 sha — 선택. 위키가 레포의 어디까지 담았는지. 등록(A)·ingest(B) 시 HEAD로 기록. 미설정도 유효. git 아닌 레포면 줄째로 생략 — §2.2·§7-26>
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
- [[20_projects/{카테고리}/{프로젝트}/decisions|결정 이력]] — 채택·보류·기각·번복 (생성 시 1회 추가)
- [[20_projects/{카테고리}/{프로젝트}/conventions|작업 규약]] — 이 프로젝트 작업 규약·함정 (생성 시 1회 추가)

## 프로젝트 간 공유 패턴
- **패턴명**: 어떤 프로젝트와 어떻게 공유하는지

<!-- 작업 규약·주의사항은 이 허브가 아니라 같은 폴더 conventions.md(wiki-schema §2.9)에 둔다 —
     규약은 계속 누적되는데 허브는 "한 장 요약"이라 한 파일에 두면 항목이 늘 때마다 압축이 강제된다.
     위 "관련 위키 지식"에서 링크만 하고, 절차 K가 매 작업 전에 그 파일을 읽는다. -->

## 최근 주요 변경
<!-- 3~5개 유지. 초과분은 압축하지 않고 가장 오래된 것부터
     90_archive/20_projects/{카테고리}/{프로젝트}/changes.md 로 롤오버(append) 후
     아래 "## 아카이브" 포인터 1줄을 갱신한다(§2.2·§8 — 포인터 정합은 lint §7-30ⓐ).
     설계·동작이 바뀐 것만 — 버전 bump·카운트 현행화·changelog 나열은 등재 금지(§5). -->
- [YYYY-MM-DD] 변경 내용 한 줄

## 아카이브
<!-- 롤오버가 한 번이라도 있었을 때만 둔다(없으면 이 섹션 자체를 생략). -->
- 이전 이력: 90_archive/20_projects/{카테고리}/{프로젝트}/changes.md (YYYY-MM-DD~YYYY-MM-DD, N건)
```

## feature
```markdown
---
type: feature
project: 프로젝트명
category: personal | work
feature_name: "기능명"
description: "한 줄 요약 (권장 — wiki-schema §12)"
platform: windows-desktop | web | mobile | cli | cross
status: active   # 코드에서 제거 시 deprecated: YYYY-MM-DD 추가 (폐기 보존, wiki-schema §2.3)
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
tags: [feature, 기능태그, 프로젝트태그]
---

# 기능명

> 작성 전제: 아래 구현/동작/UI 서술은 해당 기능의 핵심 소스 파일을 실제로 읽은 뒤 작성한다(enumeration 스캔으로 대체 불가).
> 지도는 두껍게, 산문은 얇게: 관련 파일·인덱스(지도)는 빠짐없이, 구현 방법 산문은 방향만+각주로 코드 가리킴 (schema §2.3).

## 개요
기능이 무엇이고 왜 있는지.

## 관련 파일
<!-- 이 기능을 구성하는 파일을 빠짐없이 담는 완전한 지도(지도는 두껍게) — 각주는 근거, 이 섹션은 지도 (lint §7-21이 경로 실존을 기계 검사).
     경로 표기: schema §2.3 규칙(정본) — 백틱 필수·물리 경로·brace 축약 금지 (상세는 §2.3) -->
- `ViewModels/{기능}ViewModel.cs` — 화면 로직
- `Views/{기능}Page.xaml` — 화면 레이아웃

## 동작(사용법)
사용자 관점 동작 흐름·옵션. 코드·문서로 확인된 내용만 단정 — 실행해야만 확인 가능한 서술은 `(미검증)` 표기.

## 구현 방법
핵심 클래스/패턴/데이터 흐름을 **얇게 — 방향만**(산문은 얇게). 코드를 문장으로 재서술하지 말고 세부는 각주로 코드를 가리킨다. 구현 상세 주장은 레포 근거 각주 `[^src-...]` 필수(각주에 소스 파일 경로 병기).
시간민감 사실은 `(as of YYYY-MM)` 표기.

## UI·UX
화면 구성, 인터랙션, 플랫폼별 UI 고려. 동작(사용법)과 동일한 근거 규칙 적용.

## 관련 지식·레시피
<!-- 구현 방법에서 아낀 지면은 여기에 — 코드로 재현 안 되는 함정·주의점(구현 트랩·플랫폼 제약·성능/안정성) -->
- [[30_knowledge/tech/기술|표시이름]] — 연결 설명

[^src-태그]: [[10_sources/{카테고리}/src-{태그}|소스: 프로젝트명]] — `ViewModels/{기능}ViewModel.cs`, `Views/{기능}Page.xaml` (근거 소스 파일 경로 병기)
```

## entity
```markdown
---
type: entity
entity_name: "기술명"
description: "한 줄 요약 (권장 — wiki-schema §12)"
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
description: "한 줄 요약 (권장 — wiki-schema §12)"
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
related_projects: [프로젝트1, 프로젝트2]
tags: [concept, 패턴태그]
# budget_split: none            # (선택) 나눌 하위 주제가 없을 때만 — wiki-schema §3·§4
# budget_split_chars: 0         #   lint 예산 판정과 같은 기준의 문자 수(=임박 메시지의 {현재} 값,
#                               #   ui-ux·platform-bootstrap guide는 펜스 제외). 부착 후 재측정해 수렴
# budget_split_reason: ""       #   왜 나눌 수 없는가 ("작아서"는 사유가 아니다)
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
description: "한 줄 요약 (권장 — wiki-schema §12)"
platform: windows-desktop | web | mobile | cli | cross
origin: agent-synthesized | human-validated
confidence: high | medium | low
updated: YYYY-MM-DD
related_projects: [프로젝트1]
tags: [guide, recipe, 플랫폼태그]
# budget_split: none            # (선택) 단일 레시피처럼 나눌 하위가 없을 때만 — wiki-schema §3·§4
# budget_split_chars: 0         #   lint 예산 판정과 같은 기준의 문자 수(=임박 메시지의 {현재} 값,
#                               #   ui-ux·platform-bootstrap guide는 펜스 제외). 부착 후 재측정해 수렴
# budget_split_reason: ""       #   왜 나눌 수 없는가 ("작아서"는 사유가 아니다)
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
     어휘 고정: 채택 | 보류 | 기각 | 번복. 최신이 위. wiki-schema §7-2 발동 시 오래된 항목부터 90_archive 원경로 이동.
     기록 수준: LLM이 이 기록만 보고 사용자에게 결정 배경을 설명할 수 있어야 함 — 사유가 다층적이거나
     재검토 조건이 있으면 하위 불릿 1~2줄 추가(하위 불릿 포함이 한 항목 — 롤오버 시 쪼개지 않음).
     롤오버 시 하단에 "## 아카이브" 포인터 1줄 유지·갱신 필수(§2.8 — 누락 시 오래된 결정 검색 유실, lint §7-24). -->
- [YYYY-MM-DD] {주제} — **{채택|보류|기각|번복}**: {요지·근거 1줄}
  - 재검토 조건·기각한 대안 등 보충 (필요한 결정만, 1~2줄)
```

## convention
```markdown
---
type: convention
project: 프로젝트명
category: personal | work
updated: YYYY-MM-DD
tags: [convention, 프로젝트태그]
---

# 프로젝트명 작업 규약

<!-- 이 프로젝트에서 작업할 때 알아야 할 크로스 세션 규약·함정. 절차 K가 매 작업 전에 읽는다.
     항목 불변이 아니다(decision-log와 다른 점) — 규약이 바뀌면 그 항목을 고치거나 지운다.
       낡은 규약을 남기면 다음 세션이 그것을 따른다.
     wiki-schema §7-2 발동 시: ① 무효 항목 제거 → ② ①로도 해소되지 않으면 주제별 하위 파일(conventions-{주제}.md) 분리
       → ③ 하위에서 §7-2가 다시 발동하면 같은 규칙으로 재분할(무제한, wiki-schema §4 "재분할 일반 규칙").
       90_archive로 롤오버하지 않는다 — 절차 K가 아카이브를 읽지 않아 이동이 곧 유실이다.
     담지 않는 것: 빌드/실행/테스트 명령·산출물 위치(그 레포 AGENTS.md가 정본) ·
       진행 상태(레포 plan.md가 정본) · 민감 정보(금지).
     유입은 pending.md [PROJECT-FACT] 큐 소비(B-1 0)가 기본 경로. 최신이 위. -->
- [YYYY-MM-DD] {규약·주의사항 한 줄} ({근거: 사용자 지시·실측 등})

## 하위 문서
<!-- 주제별 분리가 있었을 때만 둔다(없으면 이 섹션 자체를 생략).
     전 하위 파일을 나열해 조회 홉 1을 유지한다 — 목록 없이 쪼개면 분할이 곧 유실이다.
     목록↔실파일 정합은 lint §7-30ⓑ가 기계 검사한다.
     {담당 범위 1줄}은 의무이며 **판정 가능해야 한다** — 절차 K 2가 이 한 줄로 "이번 작업에 어느
       하위를 열지"를 정하므로, 주제 이름을 되풀이하는 것("릴리즈 규약")은 범위 서술이 아니다.
       "언제 이 파일을 읽어야 하는가"를 쓴다(예: "검사기를 건드릴 때·골든을 돌릴 때 먼저 읽는다").
       빠뜨리면 K가 그 파일을 무조건 읽는 폴백으로 떨어진다(schema §2.9). -->
- [[20_projects/{카테고리}/{프로젝트}/conventions-{주제}|{주제} 규약]] — {담당 범위 1줄}
```
