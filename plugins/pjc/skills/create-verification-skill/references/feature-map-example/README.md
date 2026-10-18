# Notes 검증 지도

> 생성할 기능 지도의 형태 예시다 — `../../SKILL.md` 3단계가 가리킨다. 원문은 pstack `create-verification-skill/references/feature-map-example/README.md`(`https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/skills/create-verification-skill/references/feature-map-example/README.md`) · Copyright (c) 2026 Lauren Tan · MIT(`https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/LICENSE`). 한글로 옮겼고, 절 이름과 명령은 원문 그대로다.

이 폴더는 Notes 의 사용자 기능을 검증하는 유지 대상 정본이다. 앱을 조작하기 전에 이 색인을 읽고, 맞는 기능 파일을 조작법으로 쓴다.

## 기본 전제

- Notes 를 일회용 데이터 폴더로 `http://127.0.0.1:4173` 에 띄운다.
- 동시 실행이 상태를 나눠 쓰지 않게 `NOTES_DATA_DIR=/tmp/notes-verify-$RUN_ID` 를 둔다.
- `Quarterly plan`·`Grocery list` 제목의 노트를 시드한다.
- `control-notes` 와 `notes` CLI 를 `PATH` 에 둔다.
- `control-notes doctor` 를 돌려 기대 URL·데이터 폴더·빌드 리비전을 확인한다.
- 이번 검증 실행이 띄우지 않은 인스턴스는 조작하지 않는다.

## 조작 규칙

- 조작법은 전제가 따로 말하지 않으면 기본 상태에서 시작한다.
- CSS 셀렉터·DOM 위치보다 ARIA 역할과 접근 가능한 이름을 쓴다.
- 명령은 글자 그대로 쓴다. 따옴표 안 이름과 플래그를 바꾸지 않는다.
- 브라우저 조작은 `control-notes browser` 로 한다.
- 터미널 조작은 `control-notes cli -- <command>` 로 한다.
- 값을 바꾼 뒤에는 시드 데이터를 되돌린다. 정리할 때 증거 파일은 지우지 않는다.

## 증명과 건너뜀 보고

- 마지막 화면만이 아니라 사용자 조작과 그 결과 상태를 남긴다.
- UI 증명은 ARIA 스냅샷과, 앱 이름이 보이는 스크린샷이다.
- CLI 증명은 명령·표준 출력·표준 오류·종료 코드다.
- 값을 바꾼 증명에는 저장된 값을 다른 화면에서 읽기 전용으로 다시 본 결과가 있다.
- 증거마다 기능 ID 와 쓴 진입 경로를 적는다.
- 닿지 못한 경로는 시도한 명령과 채우지 못한 전제와 함께 보고한다.
- 건너뛴 진입 경로를 다른 경로로 검증했다고 보고하지 않는다.

## 기능 파일 규칙

기능 파일은 H1 제목과, 사용자에게 보이는 동작을 적은 한 문단으로 시작한다. 그 뒤에 H2 넷을 이 순서로 정확히 쓴다.

1. `Sub-features` — 짧은 ID 와 동작 한 줄씩
2. `How to get to it (user POV)` — 사용자의 모든 진입 경로
3. `Driving it with <harness>` — `Preconditions:` 로 시작하고, 사용자 조작마다 정확한 명령과 관측 가능한 결과를 짝지은 라벨 불릿
4. `Gotchas` — 검증 실행을 허비하거나 무효로 만들 함정

구현 세부는 지도에 넣지 않는다. 사용자 경로·안정된 손잡이·필요한 상태·명령·관측 가능한 증명만 적는다.

## 기능

- [노트 만들기](./create-note.md) — 브라우저·CLI 생성, 취소, 저장 유지, 정리
