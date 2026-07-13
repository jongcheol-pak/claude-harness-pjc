# Deferred 대장

> 미처리 Deferred의 단일 추적 대장 (형식 정본: implement-task `references/phase-f-detail.md` F-6.5).
> 항목은 `- [등록일] {요지 1줄} (출처)`, 종결 시 삭제가 아니라 `## 종결`로 이동한다.
> plan-feature Step 1이 계획 때 `## 대기`를 조회하고, implement-task F-6.5가 완료 때 신규분을 append한다.

## 대기

- [2026-07-13] README 버전 이력의 **서술 정책 확정**(시점 스냅샷 vs 현행 반영) — v1.117.0에서 과거 v1.100.0 블록의 문장을 현재 동작으로 소급 수정하고 "(v1.117.0에서 …)" 각주를 달았는데, 이 repo의 다른 이력 블록은 append-only 관례다. 그 블록이 "Subagents(검토 담당)" 섹션 안에 있어 독자가 현재 기능 설명으로 읽는 위치라 이번엔 stale 방치보다 정확성을 택했으나, 정책 자체가 미확정 (출처: v1.117.0 T1 quality 리뷰 m1)
- [2026-07-10] 골든 러너 `-Filter "a,b"` 단일 문자열 바인딩 시 콤마 split 안 됨(배열 전달만 동작) — 기존 동작, 다음 러너 정비 때 (출처: v1.112.0 T1 quality 리뷰 m2)
- [2026-07-10] AGENTS 게이트 임시폴더 예외 분기 골든 케이스 추가 — 러너 $work가 LOCALAPPDATA라 현재 스위트 사각(fail-open 방향·저위험), 다음 hook 정비 때 (출처: v1.111.0 F-7 m1)
- [2026-07-08] block-destructive: `cat <<EOF > file`(데이터 싱크 스트립) 후 같은 Bash 호출에서 즉시 실행 시 위험 본문 미스캔 — "파일 작성+동일 호출 실행" 조합 감지 개선 (출처: harness-quality-part1)
- [2026-07-08] suggest-agents-record 명령 오인 오탐 2류 — ① 커밋 -m 값 속 명령 문자열 ② grep 패턴 문자열 속 "dotnet build" — hook 이벤트 로그 데이터 축적 후 근거 기반 수정 (출처: harness-quality-part1·v1.101.0)
- [2026-07-08] .state 디듑 마커(post-write-warn·require-plan-warn·suggest-agents-record) 누적 정리 정책(TTL/청소) 부재 (출처: harness-quality-part1)
- [2026-07-08] (저신뢰 audit) block-destructive 열거 `.` 제외의 이름필터 판정에서 `-Include *.tmp,*` 콤마 배열 catch-all 원소 통과 여지 — 차기 hook 정비 때 감사 케이스로 검토 (출처: harness-quality-part1 F-7)
- [2026-07-09] suggest(제안) 이벤트의 로깅 확장 — v1.105.0 T2는 차단+경고만(사용자 확정 범위) (출처: harness-wiki-part1)
- [2026-07-09] lint.py --fix 대상 확대(§7-19 누락 행 추가 등) — 키워드 요약을 기계 생성할 근거가 생기면 재검토 (출처: harness-wiki-part2)
- [2026-07-09] lint.py `section()` 헬퍼 Match 반환형 확장으로 `section_span()`과 단일화 — 호출부 리팩터링 동반, 다음 lint.py 정비 때 (출처: harness-wiki-part2 T2 리뷰 m2)
- [2026-07-09] 나머지 7개 프로젝트 메모리의 위키 순차 이전(AI-Agents·neighborhood-walk-rpg·Obsidian-Vault-WIKI·bitleader-dev-HomePage·Web-HomePage·ProjectDashboard·DevDashboard-WinUI) — 각 프로젝트 위키 절차 B 세션에서 (출처: v1.102.0)
- [2026-07-09] SessionStart hook의 위키 허브 컨텍스트 자동 주입 — v1.102.0 미채택(지침 방식 선택), 지침 방식 실효성이 낮다고 관찰되면 재검토 (출처: v1.102.0)
- [2026-07-09] 위키 허브 `## 작업 규약·주의사항`이 수십 건으로 커지면 전용 페이지(worknotes류) 승격 검토 (출처: v1.103.0)
- [2026-07-10] warn-external-ops가 `gh release create --notes "…git merge…"` 노트 값 속 텍스트를 오탐 — 커밋 `-m`/`--message` 값은 스트립하나 `--notes` 값은 미스트립이라 노트 본문의 push/merge/tag 텍스트가 규칙에 걸림(비차단), `--notes`(및 유사 값 옵션) 스트립 또는 `git ` 접두 요구로 개선, 다음 hook 오탐 정비 라운드에서 (출처: v1.113.1 릴리즈 발행 시 실관찰)

## 종결

- [2026-07-08 → 2026-07-12] 위키 feat-safety-hooks 보호 집합 서술("hook 스크립트 8종") 현행화 — 확인 종결(2026-07-12 하네스 ingest 세션에서 grep 확인: "8종" 서술이 이미 없음 — 이전 ingest(v1.108~113 반영)가 "검사 10종 + 디스패처"로 현행화 완료)
- [2026-07-09 → 2026-07-12] llm-wiki fixture `archive-exempt/.../oldproj.md` UTF-8 BOM 정리 — 기각(v1.116.0 D6: 그 BOM은 lint-cases archive-exempt 케이스의 expect_absent "BOM"이 검증하는 **의도된 테스트 입력**(90_archive BOM 무경고 실증)이라 제거하면 검증이 공허해짐 — 컨벤션 위반이 아니라 테스트 대상 데이터)

- [2026-07-10 → 2026-07-10] warn-external-ops가 `git merge-base`(읽기 전용 조회)를 "git merge"로 오탐 — 반영(v1.113.1 T1 — bash-hook-lib.ps1:39 `merge\b`→`merge(?![-\w])`, merge-base·merge-tree·merge-file·merge-index plumbing 오탐 제거·실제 merge 경고와 --abort/continue/quit 제외 보존, 골든 merge-base·merge-tree 무경고 2건 추가)
- [2026-07-10 → 2026-07-10] 위키 feat-safety-hooks·feat-plan-feature에 v1.111.0 bootstrap 게이트·직접 작성 금지 반영 — 반영(2026-07-10 위키 ingest 세션 — feat-plan-feature Step 1 bootstrap 강화 + feat-safety-hooks require-plan 게이트 동작·지도 서술)
- [2026-07-10 → 2026-07-10] Type B 분류 정의가 구조 기준(단일 파일·메서드·호출자 없음)뿐이라 신규 비자명 로직이 B로 새어 검토(V-5 prefilter만·V-3/V-6 생략) 얕아짐 — 반영(v1.113.0 T1 — plan-feature:257에 경계 명문화(비자명 로직·알고리즘·제어흐름·상태변경 신규 심볼은 Type C 이상, 자명 접근자·상수·순수 위임은 B 유지) + plan-reviewer:39 오분류 검출 예시 병기, 방어선 2층)
- [2026-07-10 → 2026-07-10] SessionStart matcher `compact` 추가 + 요약 직후 재확인 컨텍스트 주입 — 반영(v1.112.0 T1 — session-context.ps1 신설, matcher 4종 + compact 리마인더, 골든 SC2)
- [2026-07-10 → 2026-07-10] post-write-checks notes.md 30,000자 초과 아카이브 경고 — 반영(v1.112.0 T2 — 섹션 2b, Test-WarnOnce 디듑, 골든 NA1~NA3)
- [2026-07-10 → 2026-07-10] SessionStart에 plan.md 존재·미완료 task 수·notes.md 최신 항목 날짜 주입(로컬 경량판) — 반영(v1.112.0 T1 — session-context.ps1에 compact 항목과 통합 구현, 골든 SC1·SC1b·SC3~SC5)
- [2026-07-10 → 2026-07-10] implement-task Phase D clean/dirty 판정×재리뷰 커밋 프로토콜 모순 + review-fix 커밋 메시지 미규정 — 반영(v1.110.0 T1 — Phase D ①을 HEAD 커밋 제목 판정으로 교체·review-fix checkpoint 규정·재개 트리 5분기+폴백·새 완료 커밋 --allow-empty)
- [2026-07-10 → 2026-07-10] plan-feature 분할×PRD 전수 커버×12-a 규정 교착 — 반영(v1.110.0 T2·T3 — part별 Coverage 스코프(`⏭️ 다음 part`/`✅ 이전 part 기구현` 행)+합집합=전수 게이트+두 part 동시 작성 명문화, 12-a 분할 인지+실질 MAJOR 게이트, 마지막 part Phase G/F-7 전수(전체 트리 기준))
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
