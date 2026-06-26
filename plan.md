# plan.md — 위키·하네스 흐름 2차 audit 결함 수정

## 목표
위키(등록/검색/수정/갱신/저장 데이터/참조) 전반과, 계획·검증·코드작업·버그수정·완료검증의
역순 PRD 검증·자율 루프·계획/버그 작업 시 위키 참조 동작을 다각도(3개 병렬 시각 에이전트 + 직접 정독)로
검토해 발견한 정합성 결함을 진실원천 기준으로 수정한다.

## 범위
plugins/pjc 하위 — llm-wiki(SKILL.md/wiki-schema.md/templates.md), implement-task/SKILL.md,
agents/plan-reviewer.md. + 버전(plugin.json/README.md).
(lint.py·plugin 메타·hook 스크립트는 정합 확인 결과 무수정.)

## 승인 필요 사항
- [x] 9건(MAJOR 2 + MINOR 7) 전부 수정 — 사용자 "9건 전부 수정" 승인 완료
- [x] 버전 업(1.60.0) + commit + GitHub 릴리즈 — 사용자 승인("1.60.0 + commit + 릴리즈")

## 작업 단계 (모두 검증 완료)

### T1. 위키 정합 (Type A/문서)
- [x] W1 (MAJOR) question resolved를 "보존(status: resolved)"으로 통일 — wiki-schema §2.7·§4
- [x] W2 (MINOR) Lint 검사항목 4·8을 schema §7 순서로 교환 — llm-wiki SKILL F-1
- [x] W3 (MINOR) deprecated 옵션 필드를 schema §2.3·templates에 명세 + 허브 폐기구역(링크 유지) 처리 명확화

### T2. 하네스 흐름 정합 (Type A/문서)
- [x] H1 (MAJOR) Type B는 V-6 생략(V-7 축소·V-8)으로 정정 — implement-task V-5
- [x] H2 (MINOR) Phase G 진입조건 흐름 다이어그램을 본문과 일치 — implement-task L150
- [x] H6 (MINOR) Phase G G-1에 F-7 plan-completion-reviewer 결과 재사용·역할경계 명시

### T3. plan-reviewer 정합 (Type A/문서)
- [x] H3 (MINOR) PRD 탐지에 docs/prd.md·docs/prds/ fallback 추가
- [x] H4 (MINOR) Type C/D 표 통합 + Type B에 항목9·조건부10 추가
- [x] H5 (MINOR) 항목10 Edge 카테고리 8→10(외부 의존 부재·멱등성)

## 검증 방법·결과
- grep으로 stale 표현("흡수 후 삭제")·검사항목 번호 역참조·"V-6 진행" 잔존 점검 → 깨진 참조 0건.
- 수정 파일 간 교차 정합 재확인: schema §2.7/§4/§7-12 보존 일관, SKILL F-1 ↔ schema §7 번호 일치,
  Type B V-5 ↔ Fast-Path 표 일치 확인.
- vault 미설정으로 lint.py 실행 불가(lint.py 자체는 무수정). 빌드 대상 없는 문서 수정.

## Out of Scope
- lint.py에 STATUS_VOCAB(deprecated 포함) 기계 검사 추가 — 이번 범위 아님(규칙 문서화로 충분).
- G-1/F-7 PRD 대조의 완전 단일화(한쪽 제거) — 이중 안전망 유지가 안전, 역할경계 명시로 갈음.

## Progress Log
- T1~T3 완료: 6개 문서 파일 수정, grep 검증으로 깨진 참조 0 확인. notes.md 상세 기록.
