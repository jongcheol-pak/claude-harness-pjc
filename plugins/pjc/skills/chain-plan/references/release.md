# 완료 보고 확인·닫기 (`pjc:chain-plan` — succeeded 뒤)

> `../SKILL.md` 「워커 루프」가 `worker_done` 의 `succeeded` 를 받았을 때 이 파일을 연다 — 워커가 최종 보고 텍스트를 다 그렸는지 가른 뒤(「완료 보고 확인」) 그 탭을 닫는다(「닫기」). `continuation.md` 의 이어받기와 `cli-errors.md` 의 `duplicate_worker` 이 Run 갈래도 「닫기」 를 쓴다.

## 완료 보고 확인

- `worker-read` 는 `--limit` 과 무관하게 지금 보이는 터미널 화면만 준다 — 제목은 `● 완료 보고` 처럼 보이고, 보고 뒤에 인계 프롬프트 코드블록이 붙으면 화면 위로 밀려 안 보인다. 그래서 판정은 둘 중 하나다: `완료 보고` 부분 문자열이 보이거나, 아래 대기 앞뒤로 읽은 화면이 같다(작업 중이면 스피너의 경과 시간이 매초 바뀌어 같을 수 없다).
- 아니면 `check --wait --timeout-ms 30000` 으로 기다린 뒤 다시 본다 — 그 사이 온 메시지 배치는 `../SKILL.md` 「워커 루프」 규칙대로 처리하고 ack 한다(이 대기는 전경이라 대기 스크립트를 띄우지 않는다). 3회 안에 판정이 서지 않으면 `--body` 가 정본이라 그대로 아래 「닫기」 로 간다.

## 닫기

- **먼저 `worker-release --dispatch <id>` 를 보내고 `outcome` 이 `released`·`already_released` 면 끝이다** — 입력창이 빈 탭은 여기서 닫힌다.
- **`retained` 면 `worker-stop --dispatch <id>` 로 닫는다 — 입력창에 문구가 남아 있어도 닫고, 그 문구는 탭과 함께 사라진다** — Karina 는 사람이 입력한 워커 탭(입력창에 남은 문구 포함)을 `retained` 로 올려 release 가 닫지 않게 하고, 그 워커는 같은 폴더 자리를 계속 쥐어 다음 `worker-start` 를 `duplicate_worker` 로 막는다. stop 은 그 표식과 무관하게 탭을 닫고, 배정이 이미 정산된 워커라 Task 는 바뀌지 않는다(Karina `close_worker`). 사용자가 「문구가 있어도 종료」를 지시했다(2026-10-08).
- **stop 응답이 `ok: false`(`cli-errors.md`「오류 응답」 의 복구 뒤에도)이거나 `outcome` 이 `release_unknown` 이면 `worker-release --dispatch <id>` 를 한 번 더 보낸다** — `release_unknown` 은 다시 불러도 안전하고(Karina 가이드), 탭이 이미 없으면 `already_released` 로 자리가 풀린다.
- **그래도 `released`·`already_released` 가 아니면 멈추지 않고 `worker-abandon --dispatch <id>` 로 자리만 푼 뒤 다음 계획의 `worker-start` 로 간다 — 새 워커는 같은 폴더에 새 탭으로 뜨고 옛 탭은 남는다** — Karina 는 보고를 마친 워커도 state 를 `ready` 로 두어 abandon 이 정산 워커로 튕기지 않고, abandoned 워커는 자리를 쥐지 않는다. 다른 워크트리에 띄우면 브랜치가 갈려 뒤 계획이 앞 계획 커밋을 못 본다.
  - 남긴 탭은 보고의 남은 탭 줄에 「입력하지 말고 닫을 것 — 같은 폴더에서 다음 워커가 돈다」와 함께 싣는다 — 옛 세션은 입력창 문구를 가진 채 같은 워킹트리에 살아 있어, 그 문구를 제출하면 두 세션이 한 폴더를 함께 고친다.
- **abandon 뒤의 `worker-start` 가 또 같은 dispatch 로 `duplicate_worker` 면 `cli-errors.md`「오류 응답」 을 따른다** — 정지 판정의 정본은 그쪽 이 Run 갈래 하나다.
