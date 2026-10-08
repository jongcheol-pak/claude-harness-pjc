# 멈춘 워커의 직접 재개 (`pjc:chain-plan`)

> `../SKILL.md` 가 두 자리에서 이 파일을 연다 — 체인이 stall(대기 스크립트 `RESULT: stall` 뒤 retain)이나 `failed` 로 멈춘 뒤 사용자가 그 계획의 워커를 탭에서 직접 이어 가게 했다고 알릴 때(「하지 않는 것」 → 「직접 재개」), 그리고 「워커 루프」가 제목이 `사후 완료 — ` 로 시작하는 `status` 를 받았을 때(「사후 완료」)다. 사용자가 「멈춰」로 멈춘 체인은 여기가 아니라 `interrupt.md`「사용자 중단」 이다.

## 직접 재개

- **사용자가 「plan <N> 워커 재개」처럼 멈춘 워커를 탭에서 이어 가게 했다고 알리면, 멈춘 그 dispatch 로 `../SKILL.md` 「워커 루프」의 둘째 줄 대기를 다시 띄우고 그 루프로 돌아간다** — 사용자가 부른 재개라 「하지 않는 것」이 금지한 자동 재개가 아니다. 대기 없이 두면 워커의 질문·승인 `ask` 를 받을 자리가 없어, 워커는 만료를 세다가 `failed` 로 멈춘다(2026-10-08 Karina 체인 — 540초×3 만료).
- **`failed` 로 멈췄던 dispatch 면 대기를 띄우기 전에 `<CLI> orchestration check --json` 을 한 번 돌려, 이미 와 있는 배치를 「워커 루프」 규칙대로 처리한다(사후 완료면 아래 「사후 완료」)** — 워커가 알림보다 먼저 끝났을 수 있다. 정산된 dispatch 도 `worker-read` 가 화면을 읽어 대기의 멈춤 판정은 그대로 돈다(Karina `worker_read` 는 배정이 활성인지 보지 않는다).
- **대기가 `RESULT: error` 면 `cli-errors.md`「오류 응답」 을 따른다.**
- **재개한 체인이 끝나거나 다시 멈추면 보고는 `report.md`「보고 서식」 을 처음부터 다시 채운다** — 앞서 낸 멈춤 보고는 그 시점의 것이라, 덧붙이면 끝난 계획이 멈춘 채로 남아 보인다.

## 사후 완료

- **`status` 의 제목이 `사후 완료 — plan <N>` 이면 `--body` 를 그 계획의 `worker_done`(succeeded) `--body` 로 받는다** — `failed` 로 정산된 배정에는 `worker_done` 이 `inactive_dispatch` 로 거절돼, 워커가 같은 본문을 이 유형으로 보낸다(`../../plan/references/relay-mode.md`「중계 모드」).
- **순서는 넷이다 — ① `<CLI> orchestration task-update --json --id <task id> --status completed --result "<결과 줄>"` ② `release.md`「완료 보고 확인」 ③ `release.md`「닫기」 ④ 「워커 루프」의 succeeded 이후(`남은 일` 이 「없음」이 아니면 `continuation.md`「남은 일 판정」, 아니면 다음 계획)** — ① 을 빼면 뒤 task 가 `--deps` 로 `failed` task 에 걸려 `worker-start` 가 `deps_not_ready` 로 막힌다. 응답의 `offTable: true` 는 표 밖 전이(failed → completed)를 알릴 뿐 정상이다. ② 는 이 status 도 `worker_done` 처럼 최종 보고 텍스트보다 먼저 와서 곧바로 닫으면 그 텍스트가 잘리기 때문이다. ③ 은 `failed` 때 retain 한 탭이라 `retained` 갈래로 닫힌다.
- **대기를 다시 띄우지 않는다** — `worker_done` 과 같은 예외다. 닫은 dispatch 를 기다리면 다음 계획 대신 그 탭을 지켜본다.
- **`ok: false` 는 `cli-errors.md`「오류 응답」 을 따르고, 복구되지 않으면 보고하고 멈춘다.**
- **보고의 그 plan 결과에 `사후 완료` 를 적고, `report.md`「인계 파일 정리」 에서는 succeeded 로 센다** — 계획은 끝까지 갔고, 실패로 닫힌 것은 보고 경로뿐이다.
