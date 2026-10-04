# CLI 오류 응답 (`pjc:chain-plan`)

> `../SKILL.md` 가 `<CLI>` 응답이 `ok: false` 일 때만 이 파일을 연다. 코드의 뜻과 처방의 정본은 Karina 가이드(`<CLI> skills get karina-orchestration`)의 Errors·Retrying Safely 절이고, 여기는 그 처방을 체인 맥락에 맞춘 것이다.

## 오류 응답

- **판정은 `ok: false` 와 `code` 다** — 오류도 stdout 의 JSON 으로 와서 `2>/dev/null` 아래에서도 보인다. `state: "outcome_unknown"` 은 `ok: true` 인 성공 응답이라 여기가 아니라 `worker-start.md`「시작 이상 응답」 이다.
- **가이드가 복구 동작을 정했고 코디네이터가 수행할 수 있는 코드는 그 동작을 따른다.**
  - `protocol_error` — 응답이 `--retry-request <id>` 를 이름 대면 같은 명령을 그 id 로 다시 보낸다. id 없이 다시 보내지 않는다 — 응답만 잃고 명령은 이미 실행됐을 수 있어, 새 id 로 보내면 워커·task 가 둘이 된다. id 가 없으면(읽기 명령) 같은 명령을 그대로 다시 실행한다.
  - `runtime_access_denied` — 샌드박스가 파이프를 막은 것이다. 같은 명령을 Bash 도구 `dangerouslyDisableSandbox: true` 로 다시 실행하고, 그 뒤의 `<CLI>` 는 처음부터 그렇게 실행한다. 샌드박스 밖에서도 같은 코드면 곧바로 멈춘다. Karina 를 재시작하지 않는다 — 재시작은 권한을 주지 못한다. 샌드박스 밖 실행이 권한 확인 화면을 띄우면 사용자 확인 대기로 본다.
  - `source_changed` — 커서가 다른 출처의 것이다. 커서 없이 다시 읽는다(`../SKILL.md` 「워커 루프」의 체크포인트).
  - `invalid_argument` — 플래그를 고쳐 다시 보낸다.
- **같은 명령에 위 복구를 해도 세 번째까지 오류면 멈춘다** — 같은 수단을 3회 반복해도 닿지 않을 때 멈추는 수다. 마지막이 `protocol_error` 였으면 보고에 retry id 와 「명령이 이미 실행됐을 수 있다 — `worker-list` 로 확인」을 싣는다. 감독 없는 워커가 남았는지 사용자가 확인할 수단이 그것이다.
- **`duplicate_worker` 는 멈추지 않고 이름 댄 dispatch 를 가른다 — 그 dispatch 는 `worker-stop`·`worker-abandon` 하지 않는다** — 이 코드는 같은 작업 폴더·같은 agent 에 자리를 잡은 워커가 있다는 뜻이다(Karina `holds_place_at`). `stopped`·`abandoned` 워커는 자리를 놓는다 — `stop_unknown`·`release_unknown` 은 잡고 있다. 가이드는 닫거나 다른 폴더를 고르라 하지만, 다른 세션 것을 닫으면 그 세션의 체인이 끊기고 다른 폴더는 대상 레포가 아니다.
  - 먼저 `worker-list --json` 에서 그 dispatch 를 찾는다. 목록에 없으면 곧바로 `worker-start` 를 다시 보내고, 다시 같은 dispatch 를 이름 대면 보고하고 멈춘다
  - 이 체인 Run 의 것이면(앞 계획 워커의 release 가 `release_unknown` 으로 남은 경우) 그 dispatch 에 `worker-release` 를 한 번 다시 보내고(되풀이해 불러도 안전하다) `worker-start` 를 다시 보낸다. 또 같은 dispatch 면 보고하고 멈춘다
  - `workingDir` 가 대상 레포 경로와 다르면(끝 구분자를 떼고 `/` 를 `\` 로 바꾸고 소문자로 맞춰 비교한다) Karina 판정과 어긋난 것이라 보고하고 멈춘다
  - 같은 폴더의 다른 세션 워커면 기다린다 — 기다리기 시작할 때 사용자 화면에 그 dispatch·`state`·`terminalState` 를 한 번 알리고, `start_unknown`·`stop_unknown`·`retained`·`release_unknown` 이면 「그 탭을 사람이 닫거나 놓아야 풀린다」를 함께 적는다. 그 뒤 `check --wait --timeout-ms 540000` 체크포인트마다 `worker-list --run <그 dispatch 의 run> --json` 으로 다시 확인하고, 자리를 놓았으면(`state` 가 starting·ready·start_unknown·stopping·stop_unknown 밖이거나 `terminalState` 가 released) `worker-start` 를 다시 보낸다. 경과는 다음 `check --wait` 와 같은 메시지에 싣는다
  - 이 기다림에는 위 3회 상한도 `../SKILL.md` 「워커 루프」의 화면 3회 연속 규칙도 걸리지 않는다 — 같은 명령의 재시도가 아니라 상태 관찰이고, 지켜볼 자기 dispatch 가 없다
- **그 밖의 코드는 코드와 `error` 문장을 보고하고 멈춘다.** 응답이 이름 댄 탭·dispatch 는 `report.md` 「보고 서식」의 남은 탭 줄에 싣는다.
  - `worker_start_failed` — 원인이 사람이 답해야 하는 화면(trust·sign-in·권한)이거나 대기 만료라 코디네이터가 고칠 수 없다. 응답이 남긴 것으로 이름 댄 탭·dispatch 를 싣는다. `error` 가 `그런 터미널이 없습니다` 이면 대상 레포가 Karina 에 열려 있지 않다 — 사용자가 그 레포를 Karina 에서 열면 풀린다.
  - `task_not_startable` — 이 체인의 Task 를 살아 있는 다른 워커가 쥐고 있는 예상 밖 상태다. 이름 댄 dispatch 를 닫지 않고 싣는다.
  - `app_not_running` — CLI 는 앱을 띄우지 않는다. 앱 실행은 사용자 몫이다.
  - `no_bound_run`·`unknown_*`·`unsupported_capability` 등 — Run 바인딩이나 이 세션이 받은 id 가 어긋났거나 이 빌드에 없는 기능이라, 이어 가면 상태 추적이 깨진다.
- **예외 — `../SKILL.md` 「전제조건」의 Karina 앱 실행 확인(`run-current`)이 낸 `no_bound_run` 은 통과다** — Run 을 만들기 전의 탭은 이것을 내는 것이 정상이다. 그 밖의 코드는 위 규칙대로 복구하거나 멈춘다.
