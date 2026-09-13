# Intent: 위키 조회 경로의 남은 공백 넷을 막는다

Author: 사용자. Status: approved.

## Problem

*"계획을 작성하고 위키에서 검색한 내용중 불필요한 내용이 같이 컨텍스트에 포함이 안되었으면 하고 실제로 검색이나 토큰에 이득이 있었으면 함. 추측으로 작성되면 안되고 제대로 못 찾는 문제 같은데 발생하면 안됨, 위키에 저장만 하고 읽어오는 부분이 없으 방치되는 부분도 있는거 같음"* — 요구 여섯 중 **①절 단위 읽기·②토큰 이득은 회차 68·69가 이미 해소했다**(`WIKI.md` 「절 단위 읽기」 신설 · 이관처 목차의 절 순번 주입 · `AGENTS.md` 재Read 제거). 남은 넷이 이 회차의 대상이고, 넷 다 **실해가 관측됐다**(2026-09-13 실측, 이 레포 + vault):

- **③ 위키 내용이 추측** — 허브 `claude-harness-pjc.md` 안에서 **같은 수치가 두 곳에 적히고 한쪽만 갱신**됐다. 36행(기능 목록)이 *"헬퍼 7"*·*"41패턴"*, 64행(아키텍처)이 *"dot-source 헬퍼 9"*·*"차단 패턴 48"*이고 repo 실측은 **9**(`scripts/*.ps1` 18 − 진입점 9)·**48**(`destructive.json` 항목 수)이라 **36행이 낡은 사본**이다. `synced_commit` 뒤처짐으로는 설명되지 않는다 — 같은 파일 안의 사본이라 ingest 1회가 양쪽을 함께 고쳐야 했다.
- **④ 못 찾는다** — `클릭 통과`로 vault 를 grep 하면 **0히트**이고 실제 라벨은 `투명 오버레이 클릭 투과`다. `lookup-rules.md` K 3의 「검색어 한/영 양방향 시도」와 lint §7-16(`index_label` 한/영 병기)은 **한글 내부의 동의어 변형**(통과/투과·표시/노출)을 덮지 않는다.
- **⑤ 저장만 하고 안 읽힌다** — `10_sources/` 17파일 17,808B 가 읽기 규약에서 **0회 언급**된다(`grep -c '10_sources'` → `lookup-rules.md` 0 · `WIKI.md` 0). 이 파일들이 담은 것이 하필 `repo_path`(`"D:/Personal Project/Windows/WorkWeatherLine"`)이고, **위키 슬러그 ≠ 폴더명**(`pjc-homepage` → `Web/HomePage` · `bitleader-dashboard` → `Web/bitleader-dev-HomePage`)을 푸는 매핑이 vault 에서 여기 하나뿐이다. 읽기 경로가 없으니 타 프로젝트 선례를 참조하는 세션은 경로를 **추측**한다 — ③과 같은 축이다.
- **⑥ 무제한 누적** — `90_archive/backup/` 134파일 2,903,093B. 폴더 33개가 **전부 규약 제외 접미사**(`-deleted`·`-pre-restore`·`-presplit`)이고 접미사 없는 것은 **0개**다. 즉 `wiki-ops-rules.md:19`의 *"다음 `--fix` 실행 시작 시 접미사 없는 이전 날짜 폴더를 제거"*는 정확히 작동 중이고, **제외 3종에 보존 한도가 없는 것**이 공백이다. 생성 속도는 2026-08 6개 → 2026-09 27개(9/11~9/13 사흘에 12개).

지금 하는 이유는 넷 다 **회차마다 악화**하기 때문이다 — 사본 드리프트는 ingest 마다 벌어지고, backup 은 `--fix` 마다 늘고, 읽히지 않는 계층은 계속 커진다.

## Proposed outcome

① 위키 페이지가 기계로 세어지는 수치를 **한 곳에만** 적고 lint 가 자기 페이지 내부의 사본 불일치를 잰다 ② 조회 세션이 한글 동의어 변형까지 시도한다 ③ 타 프로젝트 레포 경로를 `10_sources` 에서 얻고 추측하지 않는다 ④ backup 제외 3종에 보존 한도가 생긴다 ⑤ 「절 단위 읽기」가 `40_guides`·`30_knowledge/patterns` 157파일 892,838B 까지 덮는다.

## Affected users and systems

코드 작업 세션(계획·디버깅)과 위키 세션을 여는 사용자. `plugins/pjc/skills/WIKI.md` · `plugins/pjc/skills/llm-wiki/references/{lookup-rules,wiki-ops-rules,wiki-schema}.md` · `plugins/pjc/skills/llm-wiki/scripts/lint.py` · `plugins/pjc/skills/llm-wiki/evals/{lint-cases.json,fixtures/}`.

## Constraints

**vault 데이터는 이 회차에서 고치지 않는다** — 대상은 repo 의 규약·검사기이고, 데이터 수정(허브 기능 목록 중복 정리 · 함정 절 이름 정규화 · 기존 backup 33개 삭제)은 위키 세션의 일이라 대장·승인 항목으로 넘긴다. **절 이름 정규화를 「절 단위 읽기」 확장의 선행 조건으로 삼지 않는다** — 수단이 `grep -n '^## '` 로 목록을 먼저 얻는 순번 방식이라 절 이름이 4종으로 갈려 있어도(`주의점 / 함정` 44 · `주의사항` 19 · `주의` 6 · `함정` 2) 목록에서 고르면 성립한다. **동의어 사전을 신설하지 않는다** — 사전은 갱신 주체가 없어 곧 낡고, 조회 시도 규칙 1줄이 같은 일을 한다. **`lookup-rules.md` 를 분할하지 않는다**(`deferred-closed.md:155` 의 기각을 뒤집지 않는다).

## Open questions

없음.
