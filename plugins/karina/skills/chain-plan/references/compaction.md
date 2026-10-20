# 압축 뒤 복원 (`karina:chain-plan`)

> `../SKILL.md` 「Run·Task」가 이 파일을 연다 — 체인이 진행 중인데 체인 승인 답 원문·진행 중인 task id·dispatch id 중 하나라도 컨텍스트에 보이지 않을 때(컨텍스트 압축 뒤)만 읽는다. 이 세션은 레포 파일을 고치지 않으므로 체인 상태는 Karina 앱의 Run·Task 기록과 레포 밖 체인 결정 파일(`chain-decisions.md`「결정 기록」)에서만 되찾는다.

## 압축 뒤 복원

- **조회로 재구성하고 추측으로 메우지 않는다 — 압축 요약에 남은 값도 아래 출력과 다르면 출력을 따른다** — 요약은 압축 시점의 것이라 그 뒤 진행을 모른다.
  1. `<CLI> orchestration run-current --json` 으로 Run id 를 얻고, `<CLI> orchestration run-show --id <Run id> --json` 의 objective 를 읽는다 — 끝의 `[체인 승인: <답 원문>]` 이 체인 승인 답 원문이고, 그 앞의 `[체인 시작: <시각>]` 이 체인 시작 시각이다(`report.md` 머리의 `소요:`). 둘 사이의 `[미답 시한: <N>분]` 이 미답 시한이다(없으면 30분 — `user-relay.md`「미답 기본값」).
  2. `<CLI> orchestration task-list --json` — 계획마다 task 하나이고, 이어받기는 같은 `plan <N>/` 제목의 task 를 더한다. `title`(`plan <N>/<총> — …`, 이어받기는 `plan <N>/<총> 이어받기 <k> — …`) · `status` · `spec`(재진술·원문·근거로 정한 것·판정 원칙·실측 요지 — 「답하는 기준」의 재료) · `deps` 를 본다. `status` 가 `dispatched` 인 것이 진행 중인 계획이고, 그 계획의 이어받기 횟수는 같은 `plan <N>/` 제목 중 가장 큰 `<k>` 다(없으면 0). 이어받기 진척 대조(`continuation.md`「이어받기」)의 직전 항목 집합은 직전 이어받기 task spec 의 `실측 요지:` 다.
  3. `<CLI> orchestration worker-list --run <Run id> --json` — `state` 가 `starting`·`ready`·`start_unknown` 인 행의 `dispatchId` 가 진행 중인 워커다. 응답에 task id 가 없어 2의 `dispatched` task 와 짝짓는다 — 직렬 체인은 한 번에 워커 하나라 짝이 하나다. 병렬 그룹이면 활성 워커가 여럿이라 각 행의 `workingDir`(이름 `chain-<Run id 의 run_ 뒤 8자>-p<N>` — `-p<N>` 끝 고정)로 계획에 짝짓고, `git branch --no-merged <체인 브랜치>` 에 남은 그룹 브랜치는 `parallel.md`「병합」 을 기다리는 것이다. PR 모드 체인(objective 의 체인 승인 답이 `P`)이면 `--no-merged` 대신 `gh pr list --head <브랜치> --state all --json state,url` 로 가른다 — MERGED 면 `pr-mode.md`「병렬」 의 fast-forward 만 남았고, OPEN 이면 워커가 아직 ship 중이다(squash merge 된 브랜치는 `--no-merged` 에 남는다).
  4. 2 의 아무 task `spec` 의 `체인 결정:` 줄이 가리키는 파일을 Read 한다 — 압축 전에 보낸 사용자 답·코디네이터 판정·미답 기본값이 거기 있다(`prior-answers.md`「앞선 답」 의 재료 · `report.md` 의 `코디네이터 판정:`·`사용자에게 넘긴 질문:` 을 다시 채운다). 줄이 없는 spec(이 기능 전 체인)이거나 파일이 없으면 결정 기록 없음으로 둔다.
- **짝이 하나로 서지 않으면 가른다 — 활성 워커가 하나인데 `dispatched` task 가 없고 직전 task 가 `completed` 면 succeeded 뒤 release 를 기다리던 자리로 보고 `../SKILL.md` 「워커 루프」의 succeeded 처리부터 잇고, 활성 워커가 없고 직전 task 가 `completed` 인데 다음 task 가 아직 배정되지 않았으면 succeeded 뒤의 순서(PR 모드 꺼짐·병렬 밖이면 `continuation.md`「코디네이터 검증」 부터 — 검증은 다시 돌려도 같은 결과다)로 잇고, 그 밖이면 출력을 보고하고 멈춘다** — 짝을 짐작으로 고르면 다른 계획의 워커에 답하거나 끝나지 않은 워커를 닫는다. worker_done 직후 task 의 `status` 는 실측하지 못했다(추정).
- **PR 모드 체인이면 체인 브랜치를 2 의 task spec `PR 모드: 켬 — base <체인 브랜치>` 줄에서 읽는다 — objective 에 `[체인 브랜치: <이름>]`(재개가 옛 브랜치를 다시 쓸 때만 `[체인 승인:]` 앞에 있다 — `resume.md`「재개」)이 있으면 그것과 같아야 하고, 다르거나 2 가 실패해 spec 을 못 읽었는데 objective 에도 없으면 되찾지 못한 것이라 출력을 보고하고 멈춘다** — 이름이 Run id 로 정해져 run-create 의 objective 에 실을 수 없고(`pr-mode.md`「켜기」), 지금 브랜치는 워커가 바꿔 두어 체인 브랜치의 근거가 아니다.
- **체인 승인 답이 `T` 면 스택 체인이다 — 체인 브랜치는 plan 1 spec 의 base 이고, 나머지 복원은 `stack-mode.md`「재개·압축」 을 따른다.**
- **objective 에 `[체인 승인: …]` 이 없으면 승인 원문을 되찾지 못한 것이다 — 봉투 대조의 위임 답(`Y (체인 승인 위임 — …)`)을 쓰지 않고 그 판정을 사용자 몫으로 넘긴다** — 원문 없이 위임 답을 내면 사용자가 무엇을 승인했는지의 기록이 끊긴다.
- **되찾은 뒤에는 `<CLI> orchestration check --json` 으로 남은 배치를 먼저 처리하고 「워커 루프」의 대기를 다시 띄운다(앞 대기가 돌고 있었으면 스스로 물러난다) — 사용자에게 넘긴 ②·③·⑤ 질문이 열려 있는데 `--answer-by` 값이 안 보이면 지금부터 미답 시한으로 값을 새로 얻어 띄운다** — 압축 사이에 온 질문이 배치에 남아 있다. 새로 얻은 시한은 늘어날 뿐 앞당겨지지 않아 사용자가 답할 시간을 줄이지 않는다.
- **이 조회로 되찾지 못하는 것 — 결정 파일에 없는 코디네이터 판정·사용자에게 넘긴 질문 수 · 코디네이터가 본 환경 마찰(이어받기는 빼고 위 2 의 이어받기 task 수로 센다) · 코디네이터 검증 결과 — 는 압축 요약에도 없으면 보고에 `모름(압축)` 으로 적는다** — 확인한 사실만 적는 `report.md` 의 규칙과 같다.
- **앞 판정·앞 사용자 답의 압축 처리는 `prior-answers.md`「앞선 답」 을 따른다.**
