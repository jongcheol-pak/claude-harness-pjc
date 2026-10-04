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
- **그 밖의 코드는 코드와 `error` 문장을 보고하고 멈춘다.** 응답이 이름 댄 탭·dispatch 는 `report.md` 「보고 서식」의 남은 탭 줄에 싣는다.
  - `worker_start_failed` — 원인이 사람이 답해야 하는 화면(trust·sign-in·권한)이거나 대기 만료라 코디네이터가 고칠 수 없다. 응답이 남긴 것으로 이름 댄 탭·dispatch 를 싣는다.
  - `duplicate_worker` — 이름 댄 dispatch 는 `worker-stop`·`worker-abandon` 하지 않는다. 이 체인이 끝낸 워커(`stopped` — release·retain 포함)는 같은 폴더의 다음 `worker-start` 를 막지 않으므로, 이름 대는 것은 같은 폴더를 쓰는 다른 세션의 워커이거나 ⓓ 에서 abandon 한 워커다. 다른 세션 것을 닫으면 그 세션의 체인이 끊긴다.
  - `task_not_startable` — 이 체인의 Task 를 살아 있는 다른 워커가 쥐고 있는 예상 밖 상태다. 이름 댄 dispatch 를 닫지 않고 싣는다.
  - `app_not_running` — CLI 는 앱을 띄우지 않는다. 앱 실행은 사용자 몫이다.
  - `no_bound_run`·`unknown_*`·`unsupported_capability` 등 — Run 바인딩이나 이 세션이 받은 id 가 어긋났거나 이 빌드에 없는 기능이라, 이어 가면 상태 추적이 깨진다.
- **예외 — `../SKILL.md` 「전제조건」 ⓐ 의 `run-current` 가 낸 `no_bound_run` 은 통과다** — Run 을 만들기 전의 탭은 이것을 내는 것이 정상이다. 그 밖의 코드는 위 규칙대로 복구하거나 멈춘다.
