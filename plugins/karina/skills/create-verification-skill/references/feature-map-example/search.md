# 노트 검색

> 기능 파일 예시다. 원문은 pstack `create-verification-skill/references/feature-map-example/search.md`(`https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/skills/create-verification-skill/references/feature-map-example/search.md`) · Copyright (c) 2026 Lauren Tan · MIT(`https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/LICENSE`). 한글로 옮겼고, 절 이름·명령·UI 문자열은 원문 그대로다. 증거 경로는 `../../SKILL.md` 의 Evidence 규칙(레포 밖)에 맞춰 바꿨다.

사용자는 제목이나 본문 텍스트로 노트를 찾고, 매치된 노트를 열어 보고, 매치 없음과 검색 불가를 구별할 수 있다.

## Sub-features

- `search-open` — 브라우저의 지원되는 진입 경로마다 검색을 연다.
- `search-match` — 노트 데이터를 바꾸지 않고 제목·본문 매치를 돌려준다.
- `search-open-result` — 결과를 노트 편집기에서 연다.
- `search-empty` — 매치가 없는 질의에 완전한 빈 상태를 보인다.
- `search-clear` — 질의를 지우고 최근 노트 화면으로 돌아간다.
- `search-cli` — 터미널에서 같은 매치 노트를 돌려준다.

## How to get to it (user POV)

- 브라우저 툴바의 `Search` 버튼을 고른다.
- 편집 가능한 칸 밖에 포커스가 있을 때 브라우저에서 `/` 를 누른다.
- 터미널에서 `notes search <query>` 를 실행한다.

## Driving it with control-notes

Preconditions:

- Notes 가 `http://127.0.0.1:4173` 에서 정상이다.
- 일회용 데이터 폴더에 본문이 `Draft budget` 인 `Quarterly plan` 노트가 있다.
- `control-notes doctor` 가 기대 URL 과 데이터 폴더를 보고한다.

- **툴바 진입.** `Search` 버튼을 고른다. `control-notes browser click --role button --name "Search"` 를 실행한다. `Search notes` 이름의 대화상자가 나타나고 포커스가 그 searchbox 에 있다.
- **키보드 진입.** 대화상자를 닫고 페이지에 포커스를 둔 뒤 `/` 를 누른다. `control-notes browser press --key "/"` 를 실행한다. 같은 대화상자가 나타나고 페이지에 슬래시가 입력되지 않는다.
- **제목 매치.** `quarterly` 를 입력한다. `control-notes browser fill --role searchbox --name "Search notes" --value "quarterly"` 를 실행한다. `Search results` 목록에 `Quarterly plan` 이 있고 `Grocery list` 는 없다.
- **본문 매치.** 질의를 `budget` 으로 바꾼다. `control-notes browser fill --role searchbox --name "Search notes" --value "budget"` 을 실행한다. `Quarterly plan` 결과가 본문 매치 발췌와 함께 그대로 보인다.
- **결과 열기.** `Quarterly plan` 을 고른다. `control-notes browser click --role link --name "Quarterly plan"` 을 실행한다. 대화상자가 닫히고 편집기 제목이 `Quarterly plan` 이다.
- **빈 상태.** 검색을 다시 열고 `volcano` 를 입력한다. `control-notes browser fill --role searchbox --name "Search notes" --value "volcano"` 를 실행한다. 검색이 끝난 뒤 `No matching notes` 이름의 상태가 나타난다.
- **질의 지우기.** `Clear search` 를 고른다. `control-notes browser click --role button --name "Clear search"` 를 실행한다. searchbox 가 비고 `Recent notes` 영역이 결과 목록을 대신한다.
- **CLI 매치.** 터미널에서 검색한다. `control-notes cli -- notes search "quarterly" --format json` 을 실행한다. 종료 코드 `0` 이고 표준 출력에 제목이 `Quarterly plan` 인 객체 하나가 있다.
- **CLI 매치 없음.** 없는 값을 검색한다. `control-notes cli -- notes search "volcano" --format json` 을 실행한다. 종료 코드 `0` 이고 표준 출력은 `[]` 다.
- **증명.** 결과가 채워진 상태를 남긴다. `control-notes browser snapshot --aria --path %TEMP%/verify-notes/<실행 id>/search/results.aria.txt` 와 `control-notes browser screenshot --path %TEMP%/verify-notes/<실행 id>/search/results.png` 를 실행한다. 두 증거에 Notes·질의·`Quarterly plan` 이 보인다.

## Gotchas

- 편집기나 searchbox 에 포커스가 있을 때 `/` 를 누르면 검색이 열리지 않고 글자가 입력된다.
- 결과는 짧은 디바운스 뒤에 갱신된다. 고정 sleep 이 아니라 결과 목록이나 빈 상태를 기다린다.
- 보관된 노트는 사용자가 `Include archived` 를 켜지 않으면 제외된다.
- CLI 는 기본이 사람이 읽는 출력이다. 안정된 단언에는 `--format json` 을 쓴다.
- 결과를 열면 브라우저 상태가 바뀐다. 다른 질의를 증명하기 전에 검색을 다시 연다.
