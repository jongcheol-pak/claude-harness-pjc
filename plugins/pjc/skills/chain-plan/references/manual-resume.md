# 멈춘 워커의 직접 재개 (`pjc:chain-plan`)

> `../SKILL.md` 가 세 자리에서 이 파일을 연다 — 체인이 stall(대기 스크립트 `RESULT: stall` 뒤 retain)이나 `failed` 로 멈춘 뒤 사용자가 그 계획의 워커를 탭에서 직접 이어 가게 했다고 알릴 때(「하지 않는 것」 → 「직접 재개」), 「워커 루프」가 사유에 「코디네이터 무응답」 이 있는 `failed` 를 받았을 때(「무응답 실패 뒤 늦은 답」), 그리고 「워커 루프」가 제목이 `사후 완료 — ` 로 시작하는 `status` 를 받았을 때(「사후 완료」)다. 사용자가 「멈춰」로 멈춘 체인은 여기가 아니라 `interrupt.md`「사용자 중단」 이다.

## 직접 재개

- **사용자가 「plan <N> 워커 재개」처럼 멈춘 워커를 탭에서 이어 가게 했다고 알리면, 멈춘 그 dispatch 로 `../SKILL.md` 「워커 루프」의 둘째 줄 대기를 다시 띄우고 그 루프로 돌아간다** — 사용자가 부른 재개라 「하지 않는 것」이 금지한 자동 재개가 아니다. 대기 없이 두면 워커의 질문·승인 `ask` 를 받을 자리가 없어 워커가 그 질문에서 계속 기다린다(2026-10-08 Karina 체인 — 그때 규칙으로는 540초×3 만료 뒤 `failed`).
- **`failed` 로 멈췄던 dispatch 면 대기를 띄우기 전에 `<CLI> orchestration check --json` 을 한 번 돌려, 이미 와 있는 배치를 「워커 루프」 규칙대로 처리한다(사후 완료면 아래 「사후 완료」)** — 워커가 알림보다 먼저 끝났을 수 있다. 정산된 dispatch 도 `worker-read` 가 화면을 읽어 대기의 멈춤 판정은 그대로 돈다(Karina `worker_read` 는 배정이 활성인지 보지 않는다).
- **대기가 `RESULT: error` 면 `cli-errors.md`「오류 응답」 을 따른다.**
- **재개한 체인이 끝나거나 다시 멈추면 보고는 `report.md`「보고 서식」 을 처음부터 다시 채운다** — 앞서 낸 멈춤 보고는 그 시점의 것이라, 덧붙이면 끝난 계획이 멈춘 채로 남아 보인다.

## 무응답 실패 뒤 늦은 답

> v1.368.0 미만 설치본 워커 전용 경로다 — 그 워커가 남지 않았으면 이 절과 머리말의 이 절 포인터, `SKILL.md` 의 두 진입 문장을 함께 지운다.

- **`failed` 사유에 「코디네이터 무응답」 이 있으면 체인을 멈추지 않고 그 워커 탭에서 잇는다 — 새 워커를 띄우지 않는다** — 갱신 전 규칙의 워커가 사용자 답을 기다리다 만료를 센 것이라 계획은 그 탭의 컨텍스트에 그대로 있고, 새 워커는 계획을 처음부터 다시 실측한다(2026-10-13 Karina 체인 plan 2).
  1. 사용자에게 넘긴 그 질문에 아직 `reply` 하지 않았으면 사용자 답을 받아 그 질문 메시지 id 로 `reply` 한다 — 그 id 가 워커의 `questionId` 이고, 정산된 dispatch 뒤에도 `reply`·`ask --resume` 은 통한다
  2. 탭은 「워커 루프」 의 `failed` 대로 `worker-retain` 한다
  3. 사용자에게 「plan <N> 워커 탭에 아래를 입력하면 그 자리부터 잇는다」 와 코드블록 `코디네이터가 답했다 — ask --resume <questionId> 로 답을 받아 이어 가라` 를 한 번 낸다
  4. 사용자의 「plan <N> 워커 재개」 를 기다리지 않고 위 「직접 재개」 를 그대로 따른다
  5. 그 대기가 `RESULT: stall` 이면 사용자가 아직 입력하지 않은 것이라 같은 대기를 다시 띄운다 — 2회까지이고, 세 번째 stall 이면 「직접 재개」 안내(`report.md` 「보고 서식」 의 멈춘 사유)로 보고하고 멈춘다. 입력 전 화면은 그대로라 대기 하나가 약 27분 뒤 stall 을 낸다. 2회는 `../../implement/SKILL.md`「멈추는 넷」 4번의 3회(첫 대기 포함)다

## 사후 완료

- **`status` 의 제목이 `사후 완료 — plan <N>` 이면 `--body` 를 그 계획의 `worker_done`(succeeded) `--body` 로 받는다** — `failed` 로 정산된 배정에는 `worker_done` 이 `inactive_dispatch` 로 거절돼, 워커가 같은 본문을 이 유형으로 보낸다(`../../plan/references/relay-edge-cases.md`「사후 완료」).
- **순서는 셋이다 — ① `<CLI> orchestration task-update --json --id <task id> --status completed --result "<결과 줄>"` ② `release.md`「닫기」 ③ 「워커 루프」의 succeeded 이후(PR 모드 꺼짐·병렬 밖이면 `continuation.md`「코디네이터 검증」 을 먼저 하고, `남은 일` 이 「없음」이 아니면 `continuation.md`「남은 일 판정」, 아니면 다음 계획)** — ① 을 빼면 뒤 task 가 `--deps` 로 `failed` task 에 걸려 `worker-start` 가 `deps_not_ready` 로 막힌다. 응답의 `offTable: true` 는 표 밖 전이(failed → completed)를 알릴 뿐 정상이다. ② 는 `failed` 때 retain 한 탭이라 `retained` 갈래로 닫힌다.
- **병렬 그룹의 계획이면 ③ 대신 `parallel.md`「중단·이어받기·사후 완료」 를 따른다** — 다음 계획 전에 그 worktree 브랜치를 병합해야 한다.
- **`ok: false` 는 `cli-errors.md`「오류 응답」 을 따르고, 복구되지 않으면 보고하고 멈춘다.**
- **보고의 그 plan 결과에 `사후 완료` 를 적고, `report.md`「인계 파일 정리」 에서는 succeeded 로 센다** — 계획은 끝까지 갔고, 실패로 닫힌 것은 보고 경로뿐이다.
