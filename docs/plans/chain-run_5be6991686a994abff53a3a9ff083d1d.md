# 계획 체인 인계 — run_5be6991686a994abff53a3a9ff083d1d

## plan 1

- **BASE**: da19fe0a · **intent**: `intent/2026-10-18-wiki-feature-slim.md` · **커밋**: 6b4f478b…9410dd30
- **바꾼 파일·새 심볼**:
  - `plugins/pjc/skills/llm-wiki/scripts/lint.py` — §7-18 게이트 제거 · **§7-38 「feature 폐지 절 보유」** WARN 신설(`ABOLISHED_FEATURE_RX` — 펜스 밖 줄 머리 `## 구현 방법`·`## 동작(사용법)`·`## UI·UX`, feature·비 deprecated·비 `90_archive/`, 페이지당 1건, 메시지 `폐지 절 보유: <vault 상대경로> (## <이름들> — …)`) · `TYPE_REQUIRED_SECTIONS["feature"] = ("개요", "관련 파일")`
  - `references/schema-types.md` §2.3 · `templates.md` feature — 3절(개요 2~3문장 · 관련 파일 = 진입·핵심 파일만 · 관련 지식·레시피 = 코드로 알 수 없는 함정·채택 이유·제약, 필수 게이트 아님)
  - `references/schema-lint.md` §7 — 18 폐지 · 37 결번 · 38 신설(「1~38 중 폐지·결번 4 → 34개 검사」) · `lint-rationale.md` 「§7-18」(폐지 경위)·「§7-38」
  - `references/wiki-schema.md` §1 「삭제 우선 · 근거 보존 4요소」(옛 「압축 금지 4요소」) · `schema-budget.md` §4·§7-2·§8 — 예산에 닿으면 세션이 「레포 사본 서술 삭제 → `--auto-split`」 순 · 규칙 번들 version 2.52
  - `references/procedures-content.md` — B-1a 트리거 = `git diff --name-status <synced_commit>..HEAD` 의 A/D/R · B-2 0 sweep = 사라진 이름만 · 1-1a 링크된 recipe 만(옛 1-1b 통합) · 「없음」 기록 의무 제거 · 1-1 에서 남은 폐지 절을 이번에 걷음
  - `llm-wiki/SKILL.md` — 예산 처방 절 라우팅 조건 `A·B·E·F-2·I` · `WIKI.md` §2 · `lookup-rules.md` K 3 문면
  - 골든: `evals/fixtures/feat-abolished-section/`(옛 `feature-no-footnote/`) · 픽스처 feature 82쪽의 폐지 헤딩을 같은 글자 수 이름으로 개명(`설계 메모`·`흐름(사용법)`·`화면 구성`) · 케이스 수 150 유지 · `check_consistency.py` `TRIGGER_ALLOWLIST_BASELINE` 88
- **내린 결정과 근거**: §7 번호 재사용 금지라 새 축은 38(37 은 2026-09-13 되돌린 축 번호 — 이력 인용과 갈림) · 삭제 우선은 세션 규칙이고 `--auto-split`(이동)·재분할 무제한은 그대로(무엇이 사본인지 기계가 판단 못 함 · 상한은 WARN 영구 잔존) · 버전 올림·릴리즈는 체인 끝 한 번(이 계획은 안 함)
- **뒤 계획이 지킬 제약**:
  - **plan 2 정리 스크립트의 판정 술어는 §7-38 과 같다** — 펜스 밖 줄 머리 헤딩이 정확히 세 이름일 때. 정본 포인터만 남은 헤딩도 대상(헤딩 존재 기준). deprecated·`90_archive/` 는 lint 대상 밖
  - 실 vault 현재 상태: feature 376쪽 전부 §7-38 WARN(그 밖 WARN 9건 · 새 lint `--auto-split` 은 폐지 절을 하위로 옮길 수 있음 — 같은 술어로 잡힌다)
  - 폐지 절의 함정·채택 이유·제약은 `## 관련 지식·레시피` 로 옮기고 나머지(코드가 답하는 「어떻게」)는 지운다 — 근거 보존 4요소(성립 조건·예외·적용 범위·채택 이유와 기각 대안)는 지우지 않는다
  - `queue-rules.md` 는 plan 3 몫이라 이 계획이 건드리지 않았다
- **미해결 사항**: 없음

## plan 2

- **BASE**: vault 535b135 · **intent**: `intent/2026-10-18-wiki-vault-feature-cleanup.md`(하니스 커밋 43bf0740 — vault 안 intent 는 lint WARN 2건을 더해 하니스에 둠) · **커밋**: vault 27cbd5f…d52637a (둘 다 push 완료 — `main -> main`)
- **바꾼 파일**: (vault) `20_projects/**/feat-*.md` 268쪽 남김(조각 파일 118 삭제 = 폐지 계보 92 + 부모로 합친 관련 지식·관련 파일 조각 26, 남긴 조각 25) · 허브 행 · `30_knowledge/patterns` 4쪽·`40_guides/recipes` 1쪽·`index.md` 증상 표(지운 조각 링크를 살아남는 상위로 재지정) · `index*.md`(`--build-index` 재생성) · `log.md` 1줄. feature 문자 3,843,062 → 1,539,272. 정리 스크립트는 레포 밖(scratchpad)이라 하니스·vault 에 새 심볼 없음
- **내린 결정과 근거**: 지우는 절 = §7-38 세 이름 + 옛 이름 `## 동작`·`## 동작 (사용법)` + 접두 `구현 방법 — ` 등(인계 술어는 lint 신호와 맞추는 하한) · 폐지 절 본문은 함정·이유까지 전부 삭제(코디네이터 판정 A — 「옮긴다」는 새 ingest 규칙) · 관련 지식·관련 파일 절은 조각 안 본문까지 전부 보존(폐지 계보 조각에 실제 관련 절이 있으면 관련 조각으로 전환) · 합침은 lint `budget_state` 가 over·critical 이 아닐 때만 · 페이지 `updated`·허브 `synced_commit` 은 건드리지 않음 · vault 커밋은 경로 한정(`pending.md` 제외)
- **뒤 계획이 지킬 제약**: vault feature 에는 폐지 절이 0이다(lint §7-38 WARN 0) — plan 3 이 기록 규칙을 바꿔도 lint 기준선은 정리 뒤 WARN 8(karina conventions·decisions 예산 초과 7 + karina feat-orchestration 진입점 심볼 1)이다 · vault 를 대상으로 하는 pjc:plan 은 vault 루트에 `intent/` 를 만들면 lint WARN(타입 미지정·고아)이, 위키링크가 든 `plan.md` 는 깨진 링크 ERR 이 난다
- **미해결 사항**: vault `AGENTS.md` 의 「요약·압축 저장 금지 · 나눠서 옮긴다 · 설계 결정 삭제 금지」 문면이 plan 1 의 삭제 우선 규칙과 어긋난다(같은 파일 20행 `index-personal.md` 도 실제는 `-1/-2`) · vault 대상 plan 의 intent 위치·lint 스캔 제외 규약 부재 · 뿌리 3쪽의 표준 밖 `##` 절과 `90_archive/` 의 지운 조각 링크 13건은 남김
