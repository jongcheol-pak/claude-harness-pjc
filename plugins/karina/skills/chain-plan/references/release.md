# 닫기 (`karina:chain-plan` — succeeded 뒤)

> `../SKILL.md` 「워커 루프」가 `worker_done` 의 `succeeded` 를 받았을 때 이 파일을 연다 — 보고의 정본은 `--body` 라 곧바로 그 탭을 닫는다(「닫기」). 워커는 인계·plan 커밋을 마친 뒤 최종 보고 텍스트보다 먼저 `worker_done` 을 보내므로, 닫으면 잘리는 것은 아무도 다시 읽지 않는 화면 텍스트뿐이다. `continuation.md` 의 이어받기와 `cli-errors.md` 의 `duplicate_worker` 이 Run 갈래도 「닫기」 를 쓴다. 사후 완료 status 를 받았을 때도(`manual-resume.md`「사후 완료」) 「닫기」 를 쓴다.

## 닫기

- **병렬 그룹의 워커는 `parallel.md`「병합」 의 병합 커밋(PR 모드면 `pr-mode.md`「병렬」 의 fast-forward)이 끝난 뒤에 닫고, 그 탭의 마지막 dispatch(병합 준비를 재배정했으면 그 dispatch)로 닫는다** — 충돌을 그 탭에 되돌려야 할 수 있고, 앞 dispatch 의 release 도 같은 탭을 닫는다(`parallel.md`「닫기」).
- **먼저 `worker-release --dispatch <id>` 를 보내고 `outcome` 이 `released`·`already_released` 면 끝이다** — 입력창이 빈 탭은 여기서 닫힌다.
- **`retained` 면 `worker-stop --dispatch <id>` 로 닫는다 — 입력창에 문구가 남아 있어도 닫고, 그 문구는 탭과 함께 사라진다** — Karina 앱은 사람이 입력한 워커 탭(입력창에 남은 문구 포함)을 `retained` 로 올려 release 가 닫지 않게 하고, 그 워커는 같은 폴더 자리를 계속 쥐어 다음 `worker-start` 를 `duplicate_worker` 로 막는다. stop 은 그 표식과 무관하게 탭을 닫고, 배정이 이미 정산된 워커라 Task 는 바뀌지 않는다(Karina 앱 `close_worker`). 사용자가 「문구가 있어도 종료」를 지시했다(2026-10-08).
- **stop 응답이 `ok: false`(`cli-errors.md`「오류 응답」 의 복구 뒤에도)이거나 `outcome` 이 `release_unknown` 이면 `worker-release --dispatch <id>` 를 한 번 더 보낸다** — `release_unknown` 은 다시 불러도 안전하고(Karina 앱 가이드), 탭이 이미 없으면 `already_released` 로 자리가 풀린다.
- **그래도 `released`·`already_released` 가 아니면 멈추지 않고 `worker-abandon --dispatch <id>` 로 자리만 푼 뒤 `../SKILL.md` 「워커 루프」 의 succeeded 이후 순서(PR 모드 꺼짐·병렬 밖이면 `continuation.md`「코디네이터 검증」 부터)를 거쳐 다음 계획의 `worker-start` 로 간다 — 새 워커는 같은 폴더에 새 탭으로 뜨고 옛 탭은 남는다** — Karina 앱은 보고를 마친 워커도 state 를 `ready` 로 두어 abandon 이 정산 워커로 튕기지 않고, abandoned 워커는 자리를 쥐지 않는다. 다른 워크트리에 띄우면 브랜치가 갈려 뒤 계획이 앞 계획 커밋을 못 본다.
  - 남긴 탭은 보고의 남은 탭 줄에 「입력하지 말고 닫을 것 — 같은 폴더에서 다음 워커가 돈다」와 함께 싣는다 — 옛 세션은 입력창 문구를 가진 채 같은 워킹트리에 살아 있어, 그 문구를 제출하면 두 세션이 한 폴더를 함께 고친다.
- **abandon 뒤의 `worker-start` 가 또 같은 dispatch 로 `duplicate_worker` 면 `cli-errors.md`「오류 응답」 을 따른다** — 정지 판정의 정본은 그쪽 이 Run 갈래 하나다.
