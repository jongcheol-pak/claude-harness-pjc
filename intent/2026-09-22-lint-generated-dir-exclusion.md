# Intent: lint 이 vault 의 생성물 폴더 `gemma-wiki/` 를 보지 않게 한다
Author: 사용자. Status: approved.

## Problem

Karina 의 온디바이스 위키(FR-130)가 LLM WIKI vault 루트에 `gemma-wiki/` 를 만들어 카드·개념·대화 기록 md 17개를 쌓는데, `lint.py` 가 그것을 사람이 쓴 지식 페이지로 훑어 **WARN 38건**(타입 미지정 17 · 경로 없는 wikilink 등)을 낸다. 실 vault 의 WARN 47건 중 38건이 이 한 폴더에서 나와, 실제 고칠 지적 4건이 그 더미에 묻힌다.

사용자가 처음에는 *"gemma-wiki 폴더 위치를 변경하고 싶은데 어디로 변경하는 게 좋을까?"* 로 물었으나, 조사 결과 **위치가 아니라 제외 목록이 문제**였다 — lint 의 제외 축은 `90_archive/` · `pending.md` · `index*` 셋뿐이고 전부 하드코딩이라, `90_archive/` 말고 어디로 옮겨도 그대로 훑는다. 그래서 폴더를 옮기지 않고 제외를 더하는 쪽으로 합의했다.

## Proposed outcome

`lint.py` 가 `gemma-wiki/` 를 **vault 에 없는 것처럼 완전 배제**한다. 실 vault lint 의 WARN 이 4건으로 줄고 ERR 0 · rc 0 을 유지하며, 깨진 링크는 0건 그대로다. 위키를 여는 다른 에이전트도 vault `AGENTS.md` 에서 그 폴더의 정체를 읽을 수 있다.

## Affected users and systems

이 vault 로 lint 를 돌리는 모든 위키 세션. 걸리는 것은 `lint.py` 의 vault 전역 스캔 5자리, 그 축을 서술하는 산문 정본 2곳(`wiki-schema.md` · `lint-rationale.md`), 골든 자산(픽스처 + `lint-cases.json`), 그리고 vault 쪽 파일 둘(답 노트 1개 이동 · `AGENTS.md` 1줄)이다.

## Constraints

**「완전 배제」는 링크 대상 우주(`existing`)도 줄인다** — `main()` 에서 `md` 목록이 곧 `existing` 의 원천이라, 배제하면 그쪽을 가리키던 **경로형** 링크가 깨진 링크 ERR 이 된다. 걸리는 파일은 Karina 답 노트 1개뿐이고 그것을 `gemma-wiki/` 안으로 옮겨 해소한다. 아웃바운드는 전부 `gemma-wiki/` 안을 가리켜 실제 페이지가 고아로 오탐되지 않는다.

> **⚠ 이 문단은 한 번 틀렸다가 실측으로 돌아왔다** — 초안이 *"그 3링크는 전부 bare 라 ERR 분기에 닿지 않는다"* 라 적었고 plan 리뷰 2R 이 그 위에서 결론을 뒤집었다. **그 근거가 불완전한 측정이었다**: 그 파일의 wikilink 는 3개가 아니라 **6개**이고 형태가 둘로 갈린다 — frontmatter `5~7행` 은 bare, **본문 `27~29행` 은 경로형**(`[[gemma-wiki/cards/…|…]]`). `grep -l`(파일 목록)과 `head -20`(frontmatter)으로 멈춰 뒤쪽을 못 봤다. T1 직후 실제로 **ERR 3 · rc 1** 이 관측돼 초안 판단이 옳았음이 확인됐다. **링크를 셀 때는 `grep -n` 으로 전 줄을 본다.** (줄 번호도 낡았다 — 그 분기는 현재 `lint.py:3045-3049` 다.)

**제외를 추가하면 기존 골든 케이스의 다른 축이 함께 꺼질 수 있다**(위키 패턴 `test-case-axis-isolation`). 사전 판정에서 제외 기준에 걸리는 기존 픽스처가 0건임을 확인했고, red 실증에서 다른 케이스 증감 0 을 함께 잰다.

**설치 캐시가 따로 있다** — 레포를 고쳐도 재설치 전에는 사용자의 위키 세션에 반영되지 않는다.

## Open questions

없음 — 인터뷰에서 셋을 확정했다: 제외의 의미(완전 배제) · 답 노트 처리(`gemma-wiki/` 로 이동) · vault `AGENTS.md` 한 줄 추가(더한다).
