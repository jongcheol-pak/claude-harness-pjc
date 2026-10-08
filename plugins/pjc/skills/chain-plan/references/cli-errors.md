# CLI 오류 응답 (`pjc:chain-plan`)

> `../SKILL.md` 가 `<CLI>` 응답이 `ok: false` 일 때(「오류 응답」)와 「전제조건」에서 해석한 CLI 이름이 PATH 에 없을 때(「CLI 경로」)만 이 파일을 연다. 코드의 뜻과 처방의 정본은 Karina 가이드(`<CLI> skills get karina-orchestration`)의 Errors·Retrying Safely 절이고, 여기는 그 처방을 체인 맥락에 맞춘 것이다.

## 오류 응답

- **판정은 `ok: false` 와 `code` 다** — 오류도 stdout 의 JSON 으로 와서 `2>/dev/null` 아래에서도 보인다. `state: "outcome_unknown"` 은 `ok: true` 인 성공 응답이라 여기가 아니라 `worker-start.md`「시작 이상 응답」 이다.
- **가이드가 복구 동작을 정했고 코디네이터가 수행할 수 있는 코드는 그 동작을 따른다.**
  - `protocol_error` — 응답이 `--retry-request <id>` 를 이름 대면 같은 명령을 그 id 로 다시 보낸다. id 없이 다시 보내지 않는다 — 응답만 잃고 명령은 이미 실행됐을 수 있어, 새 id 로 보내면 워커·task 가 둘이 된다. id 가 없으면(읽기 명령) 같은 명령을 그대로 다시 실행한다.
  - `runtime_access_denied` — 샌드박스가 파이프를 막은 것이다. 같은 명령을 Bash 도구 `dangerouslyDisableSandbox: true` 로 다시 실행하고, 그 뒤의 `<CLI>` 는 처음부터 그렇게 실행한다. 샌드박스 밖에서도 같은 코드면 곧바로 멈춘다. Karina 를 재시작하지 않는다 — 재시작은 권한을 주지 못한다. 샌드박스 밖 실행이 권한 확인 화면을 띄우면 사용자 확인 대기로 본다.
  - `invalid_argument` — 플래그를 고쳐 다시 보낸다.
- **같은 명령에 위 복구를 해도 세 번째까지 오류면 멈춘다** — 같은 수단을 3회 반복해도 닿지 않을 때 멈추는 수다. 마지막이 `protocol_error` 였으면 보고에 retry id 와 「명령이 이미 실행됐을 수 있다 — `worker-list` 로 확인」을 싣는다. 감독 없는 워커가 남았는지 사용자가 확인할 수단이 그것이다.
- **대기 스크립트가 낸 `RESULT: error` 에서 「같은 명령을 다시 실행」은 그 대기를 다시 띄우는 것이다(샌드박스 해제가 필요하면 같은 플래그로)** — 스크립트가 `<CLI>` 를 대신 부르므로, 위 3회 상한도 그 재기동 횟수로 센다.
- **`duplicate_worker` 는 멈추지 않고 이름 댄 dispatch 를 가른다 — 다른 세션 워커는 `worker-stop`·`worker-abandon` 하지 않는다** — 이 코드는 같은 작업 폴더·같은 agent 에 자리를 잡은 워커가 있다는 뜻이다(Karina `holds_place_at`). `stopped`·`abandoned` 워커는 자리를 놓는다 — `stop_unknown`·`release_unknown` 은 잡고 있다. 가이드는 닫거나 다른 폴더를 고르라 하지만, 다른 세션 것을 닫으면 그 세션의 체인이 끊기고 다른 폴더는 대상 레포가 아니다.
  - 먼저 `worker-list --json` 에서 그 dispatch 를 찾는다. 목록에 없으면 곧바로 `worker-start` 를 다시 보내고, 다시 같은 dispatch 를 이름 대면 보고하고 멈춘다
  - 이 체인 Run 의 것이고 그 Task 가 `completed`(`task-list --json`)면 — 앞 계획 워커의 탭이 입력창 문구로 `retained` 거나 닫기가 `release_unknown` 으로 남은 경우다 — 그 dispatch 에 `release.md`「닫기」 를 적용하고 `worker-start` 를 다시 보낸다. 또 같은 dispatch 거나 Task 가 `completed` 가 아니면 보고하고 멈춘다 — 보고를 마친 워커도 Karina 에서 state 가 `ready` 로 남아 `worker-list` 로는 끝났는지 못 가르고, 자리를 풀 수단이 더 없다
  - `workingDir` 가 대상 레포 경로와 다르면(끝 구분자를 떼고 `/` 를 `\` 로 바꾸고 소문자로 맞춰 비교한다) Karina 판정과 어긋난 것이라 보고하고 멈춘다
  - 같은 폴더의 다른 세션 워커면 기다린다 — 기다리기 시작할 때 사용자 화면에 그 dispatch·`state`·`terminalState` 를 한 번 알리고, `start_unknown`·`stop_unknown`·`retained`·`release_unknown` 이면 「그 탭을 사람이 닫거나 놓아야 풀린다」를 함께 적는다. 그 뒤 자리 대기 `python "<skill>/scripts/wait-worker.py" --cli <CLI> --place <그 dispatch>` 를 `../SKILL.md` 「워커 루프」 대기처럼 `run_in_background: true` 로 띄우고 turn 을 끝낸다 — 놓을 때까지 이 세션은 깨어나지 않는다. `RESULT: freed` 면 `worker-start` 를 다시 보내고, 또 `duplicate_worker` 면 이 갈래들을 처음부터 다시 가른다. 그 밖의 RESULT 는 첫 줄 지시를 따르고, RESULT 줄이 없으면 `../SKILL.md` 「워커 루프」 와 같다
  - 자리 대기는 같은 명령의 재시도가 아니라 상태 관찰이라 위 3회 상한이 걸리지 않는다
- **그 밖의 코드는 코드와 `error` 문장을 보고하고 멈춘다.** 응답이 이름 댄 탭·dispatch 는 `report.md` 「보고 서식」의 남은 탭 줄에 싣는다.
  - `worker_start_failed` — 원인이 사람이 답해야 하는 화면(trust·sign-in·권한)이거나 대기 만료라 코디네이터가 고칠 수 없다. 응답이 남긴 것으로 이름 댄 탭·dispatch 를 싣는다. `error` 가 `그런 터미널이 없습니다` 이면 대상 레포가 Karina 에 열려 있지 않다 — 사용자가 그 레포를 Karina 에서 열면 풀린다.
  - `task_not_startable` — 이 체인의 Task 를 살아 있는 다른 워커가 쥐고 있는 예상 밖 상태다. 이름 댄 dispatch 를 닫지 않고 싣는다.
  - `app_not_running` — CLI 는 앱을 띄우지 않는다. 앱 실행은 사용자 몫이다.
  - `no_bound_run`·`unknown_*`·`unsupported_capability` 등 — Run 바인딩이나 이 세션이 받은 id 가 어긋났거나 이 빌드에 없는 기능이라, 이어 가면 상태 추적이 깨진다.
- **예외 — `../SKILL.md` 「전제조건」의 Karina 앱 실행 확인(`run-current`)이 낸 `no_bound_run` 은 통과다** — Run 을 만들기 전의 탭은 이것을 내는 것이 정상이다. 그 밖의 코드는 위 규칙대로 복구하거나 멈춘다.

## CLI 경로

- `../SKILL.md` 「전제조건」에서 해석한 `<CLI>` 이름이 PATH 에 없으면 설치본 전체경로(release 기본 `$LOCALAPPDATA/Programs/Karina/karina-cli.exe`)를 쓰고, 그것도 없으면 「Karina 설정에서 CLI PATH 등록」을 안내하고 멈춘다. 전체경로는 슬래시로 적고 큰따옴표로 감싼 채 spec `CLI:` 줄에 싣는다 — Git Bash 의 `$LOCALAPPDATA` 는 역슬래시 경로라 `cygpath -m "$LOCALAPPDATA"` 로 바꿔 쓴다(역슬래시를 손으로 치환하면 경로가 깨진다).
- **다른 판 이름으로 폴백하지 않는다** — 다른 판 CLI 는 이 앱이 아니라 `app_not_running` 을 돌려주고, `../SKILL.md` 「전제조건」의 ⓐ 가 그것을 앱 미실행으로 오진한다.
