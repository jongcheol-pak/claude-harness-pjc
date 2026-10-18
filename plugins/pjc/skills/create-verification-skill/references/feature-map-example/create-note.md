# 노트 만들기

> 기능 파일 예시다. 원문은 pstack `create-verification-skill/references/feature-map-example/create-note.md`(`https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/skills/create-verification-skill/references/feature-map-example/create-note.md`) · Copyright (c) 2026 Lauren Tan · MIT(`https://github.com/cursor/plugins/blob/d1715e03a8b1a2f03fdbe336d40c4a56b81f3c8f/pstack/LICENSE`). 한글로 옮겼고, 절 이름·명령·UI 문자열은 원문 그대로다.

사용자는 브라우저나 CLI 에서 제목 있는 노트를 저장하고, 끝내지 않은 초안을 취소하고, 저장된 노트를 사용자에게 보이는 다른 화면에서 확인할 수 있다.

## Sub-features

- `create-open` — 브라우저의 진입 경로마다 빈 편집기를 연다.
- `create-save` — 제목과 본문을 저장한다.
- `create-cancel` — 끝내지 않은 브라우저 초안을 버린다.
- `create-cli` — 터미널에서 같은 모양의 노트를 만든다.

## How to get to it (user POV)

- 브라우저 툴바의 `New note` 버튼을 고른다.
- 편집 가능한 칸 밖에 포커스가 있을 때 브라우저에서 `n` 을 누른다.
- 터미널에서 `notes create --title <title> --body <body>` 를 실행한다.

## Driving it with control-notes

Preconditions:

- Notes 가 `http://127.0.0.1:4173` 에서 정상이다.
- `Release checklist` 제목의 노트가 없다.
- `control-notes doctor` 가 기대 URL 과 일회용 데이터 폴더를 보고한다.

- **편집기 열기.** `New note` 를 고른다. `control-notes browser click --role button --name "New note"` 를 실행한다. `Note editor` 이름의 폼이 나타나고 포커스가 `Title` 텍스트 칸에 있다.
- **내용 입력.** 제목과 본문을 쓴다. `control-notes browser fill --role textbox --name "Title" --value "Release checklist"` 와 `control-notes browser fill --role textbox --name "Body" --value "Tag and publish"` 를 실행한다. `Save note` 버튼이 활성화된다.
- **저장.** `Save note` 를 고른다. `control-notes browser click --role button --name "Save note"` 를 실행한다. `Note saved` 이름의 상태가 나타나고 제목이 `Release checklist` 로 보인다.
- **저장 유지 확인.** 노트 목록으로 돌아가 노트를 다시 연다. `control-notes browser click --role link --name "All notes"` 와 `control-notes browser click --role link --name "Release checklist"` 를 실행한다. 편집기에 저장한 두 값이 보인다.
- **초안 취소.** 새 노트를 열고 `Discard me` 를 쓴 뒤 `Cancel` 을 고른다. `control-notes browser click --role button --name "New note"`, `control-notes browser fill --role textbox --name "Title" --value "Discard me"`, `control-notes browser click --role button --name "Cancel"` 을 실행한다. 노트 목록으로 돌아오고 `Discard me` 링크가 없다.
- **CLI 진입.** 두 번째 노트를 만든다. `control-notes cli -- notes create --title "CLI note" --body "Created from terminal" --format json` 을 실행한다. 종료 코드 `0` 이고 표준 출력에 새 노트 ID 와 제목이 있다.
- **증명.** `All notes` 에서 저장한 두 노트를 다시 연다. `control-notes browser snapshot --aria --path artifacts/create-note/list.aria.txt` 와 `control-notes browser screenshot --path artifacts/create-note/list.png` 를 실행한다. 두 증거에 `Release checklist` 와 `CLI note` 가 보인다.

## Gotchas

- 텍스트 칸에 포커스가 있을 때 `n` 을 누르면 새 편집기가 열리지 않고 글자가 입력된다.
- 제목은 저장할 때 앞뒤 공백이 잘린다. 초안 입력값이 아니라 화면에 그려진 제목으로 판정한다.
- 저장 상태 표시만으로는 증명이 부족하다. 목록에서 노트를 다시 연다.
- fixture 정리 때 `Release checklist` 와 `CLI note` 는 지우되 그 증거는 남긴다.
