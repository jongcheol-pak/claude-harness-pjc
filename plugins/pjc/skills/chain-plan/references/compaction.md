# 압축 뒤 복원 (`pjc:chain-plan`)

> `../SKILL.md` 「Run·Task」가 이 파일을 연다 — 체인이 진행 중인데 체인 승인 답 원문·진행 중인 task id·dispatch id 중 하나라도 컨텍스트에 보이지 않을 때(컨텍스트 압축 뒤)만 읽는다. 이 세션은 파일을 고치지 않으므로 체인 상태는 Karina 의 Run·Task 기록에서만 되찾는다.

## 압축 뒤 복원

- **조회로 재구성하고 추측으로 메우지 않는다 — 압축 요약에 남은 값도 아래 출력과 다르면 출력을 따른다** — 요약은 압축 시점의 것이라 그 뒤 진행을 모른다.
  1. `<CLI> orchestration run-current --json` 으로 Run id 를 얻고, `<CLI> orchestration run-show --id <Run id> --json` 의 objective 를 읽는다 — 끝의 `[체인 승인: <답 원문>]` 이 체인 승인 답 원문이고, 그 앞에 `[위임 없음]` 이 있으면 외부 계약 위임이 꺼진 것이다.
  2. `<CLI> orchestration task-list --json` — 계획마다 task 하나이고, 이어받기는 같은 `plan <N>/` 제목의 task 를 더한다. `title`(`plan <N>/<총> — …`, 이어받기는 `plan <N>/<총> 이어받기 <k> — …`) · `status` · `spec`(재진술·원문·근거로 정한 것·실측 요지 — 「답하는 기준」의 재료) · `deps` 를 본다. `status` 가 `dispatched` 인 것이 진행 중인 계획이고, 그 계획의 이어받기 횟수는 같은 `plan <N>/` 제목 중 가장 큰 `<k>` 다(없으면 0). 이어받기 진척 대조(`continuation.md`「이어받기」)의 직전 항목 집합은 직전 이어받기 task spec 의 `실측 요지:` 다.
  3. `<CLI> orchestration worker-list --run <Run id> --json` — `state` 가 `starting`·`ready`·`start_unknown` 인 행의 `dispatchId` 가 진행 중인 워커다. 응답에 task id 가 없어 2의 `dispatched` task 와 짝짓는다 — 체인은 한 번에 워커 하나라 짝이 하나다.
- **짝이 하나로 서지 않으면 가른다 — 활성 워커가 하나인데 `dispatched` task 가 없고 직전 task 가 `completed` 면 succeeded 뒤 release 를 기다리던 자리로 보고 `../SKILL.md` 「워커 루프」의 succeeded 처리부터 잇고, 그 밖이면 출력을 보고하고 멈춘다** — 짝을 짐작으로 고르면 다른 계획의 워커에 답하거나 끝나지 않은 워커를 닫는다. worker_done 직후 task 의 `status` 는 실측하지 못했다(추정).
- **objective 에 `[체인 승인: …]` 이 없으면 승인 원문을 되찾지 못한 것이다 — 봉투 대조의 위임 답(`Y (체인 승인 위임 — …)`)과 외부 계약 위임을 쓰지 않고 그 판정을 사용자 몫으로 넘긴다** — 원문 없이 위임 답을 내면 사용자가 무엇을 승인했는지의 기록이 끊긴다.
- **되찾은 뒤에는 `<CLI> orchestration check --json` 으로 남은 배치를 먼저 처리하고 「워커 루프」의 대기를 다시 띄운다(앞 대기가 돌고 있었으면 스스로 물러난다)** — 압축 사이에 온 질문이 배치에 남아 있다.
- **이 조회로 되찾지 못하는 것 — 압축 전에 보낸 코디네이터 판정·사용자에게 넘긴 질문 수·코디네이터가 본 환경 마찰(이어받기는 빼고 위 2 의 이어받기 task 수로 센다) — 는 압축 요약에도 없으면 보고에 `모름(압축)` 으로 적는다** — 확인한 사실만 적는 `report.md` 의 규칙과 같다.
- **앞 판정·앞 사용자 답의 압축 처리는 `prior-answers.md`「앞선 답」 을 따른다.**
