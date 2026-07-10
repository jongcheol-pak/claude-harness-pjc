# Deferred 대장

> 미처리 Deferred의 단일 추적 대장 (형식 정본: implement-task `references/phase-f-detail.md` F-6.5).
> 항목은 `- [등록일] {요지 1줄} (출처)`, 종결 시 삭제가 아니라 `## 종결`로 이동한다.
> plan-feature Step 1이 계획 때 `## 대기`를 조회하고, implement-task F-6.5가 완료 때 신규분을 append한다.

## 대기

- [2026-07-08] block-destructive: `cat <<EOF > file`(데이터 싱크 스트립) 후 같은 Bash 호출에서 즉시 실행 시 위험 본문 미스캔 — "파일 작성+동일 호출 실행" 조합 감지 개선 (출처: harness-quality-part1)
- [2026-07-08] suggest-agents-record 명령 오인 오탐 2류 — ① 커밋 -m 값 속 명령 문자열 ② grep 패턴 문자열 속 "dotnet build" — hook 이벤트 로그 데이터 축적 후 근거 기반 수정 (출처: harness-quality-part1·v1.101.0)
- [2026-07-08] .state 디듑 마커(post-write-warn·require-plan-warn·suggest-agents-record) 누적 정리 정책(TTL/청소) 부재 (출처: harness-quality-part1)
- [2026-07-08] (저신뢰 audit) block-destructive 열거 `.` 제외의 이름필터 판정에서 `-Include *.tmp,*` 콤마 배열 catch-all 원소 통과 여지 — 차기 hook 정비 때 감사 케이스로 검토 (출처: harness-quality-part1 F-7)
- [2026-07-09] suggest(제안) 이벤트의 로깅 확장 — v1.105.0 T2는 차단+경고만(사용자 확정 범위) (출처: harness-wiki-part1)
- [2026-07-09] lint.py --fix 대상 확대(§7-19 누락 행 추가 등) — 키워드 요약을 기계 생성할 근거가 생기면 재검토 (출처: harness-wiki-part2)
- [2026-07-09] lint.py `section()` 헬퍼 Match 반환형 확장으로 `section_span()`과 단일화 — 호출부 리팩터링 동반, 다음 lint.py 정비 때 (출처: harness-wiki-part2 T2 리뷰 m2)
- [2026-07-09] llm-wiki fixture `archive-exempt/.../oldproj.md` UTF-8 BOM 정리(무해하나 컨벤션 위반, v1.94.0부터) — 다음 fixture 정비 때 (출처: harness-wiki-part1)
- [2026-07-09] 나머지 7개 프로젝트 메모리의 위키 순차 이전(AI-Agents·neighborhood-walk-rpg·Obsidian-Vault-WIKI·bitleader-dev-HomePage·Web-HomePage·ProjectDashboard·DevDashboard-WinUI) — 각 프로젝트 위키 절차 B 세션에서 (출처: v1.102.0)
- [2026-07-09] SessionStart hook의 위키 허브 컨텍스트 자동 주입 — v1.102.0 미채택(지침 방식 선택), 지침 방식 실효성이 낮다고 관찰되면 재검토 (출처: v1.102.0)
- [2026-07-09] 위키 허브 `## 작업 규약·주의사항`이 수십 건으로 커지면 전용 페이지(worknotes류) 승격 검토 (출처: v1.103.0)
- [2026-07-08] (확인 필요) 위키 feat-safety-hooks의 보호 집합 서술("hook 스크립트 8종") 현행화 — 다음 하네스 ingest 세션에서 (출처: v1.97.2 후속)
- [2026-07-10] warn-external-ops가 `git merge-base`(읽기 전용 조회)를 "git merge"로 오탐 — 단어 경계 검사, hook 오탐 정비 라운드에서 (출처: v1.109.0 세션 실관찰)

## 종결

- [2026-07-09 → 2026-07-10] 하네스 최근 버전분(v1.102.0~) 위키 ingest — 반영(2026-07-10 위키 세션 2회: v1.102~1.108 feature 5페이지 상세 ingest + v1.109.0 델타·run_eval 함정·A~L 표기 드리프트 정정, lint 델타 0)
- [2026-07-08 → 2026-07-10] plan-feature description 1,018자 하드 한도(1,024) 근접 — 반영(v1.109.0 T5 — 981자로 무손실 압축(연결부만), 여유 43자. pjc-systematic-debugging 1,019→921자도 동일 처리. 전후 트리거 eval 동률 실증)
- [2026-07-09 → 2026-07-09] hook 이벤트 로그 자동 요약(3개월 축적 후) — 반영(v1.107.0 T2 `report-hook-events.ps1` 수동 리포트로 대체 — 자동 실행은 사용자 확정으로 채택 안 함)
- [2026-07-08 → 2026-07-08] llm-wiki 본체에서 절차 K 초경량 분리 — 기각(정식 검토 결과 분리하지 않음: 최빈 경로가 본체를 어차피 로드해 토큰 중립+Read 1회 지연만 추가. 재논의는 로드 경로가 바뀔 때만 — deferred-followups-closure)
- [2026-07-08 → 2026-07-08] explorer subagent 모델 상향(haiku→상위) — 기각(현행 유지: effort medium 반영 직후 관찰 기간 0·실패 실사례 없음. 재검토 조건: locating 실패·부정확 실사례 관찰 시 — deferred-followups-closure)

<!-- 초기 시드 sweep 근거 (2026-07-09, v1.107.0 T4): notes.md 현행 전 항목의 "미처리 Deferred" 목록 +
     docs/plans/*.md 6파일의 "## Deferred / Follow-up" 섹션 + notes-archive/2026-07.md 대조.
     중복은 최초 출처로 병합(suggest-agents-record 오탐 2류는 동일 수정 라운드라 1항목).
     "재설치(install.ps1)"는 반복 등장하나 작업 항목이 아니라 사용자 지시로 보류 중인 운영 행위라 제외.
     분할 plan 상호 포인터(다음 plan 안내)는 실행 완료된 안내문이라 제외. -->
