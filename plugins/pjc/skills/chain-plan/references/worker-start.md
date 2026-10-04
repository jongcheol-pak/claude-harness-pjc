# 워커 시작 이상 응답 (`pjc:chain-plan`)

> `../SKILL.md` 「워커 루프」가 `worker-start` 응답의 `turnStart` 가 `permission` 이거나 `injected: false` 거나 `state: "outcome_unknown"` 일 때만 이 파일을 연다. 셋 다 `ok: true` 인 응답이라 오류 처방 파일이 아니라 여기다.

## 시작 이상 응답

- **`turnStart: "permission"`** → `worker-stop --dispatch <id>` 후 `../SKILL.md` 「전제조건」의 agent 권한 모드가 꺼져 있다고 보고하고 멈춘다
- **`injected: false`** → 배정문 제출이 실패해 워커가 일을 받지 못했다. `worker-stop --dispatch <id>` 후 사유를 보고하고 멈춘다
- **`state: "outcome_unknown"`** → `worker-show`·`worker-read` 로 살펴 살아 있으면 `../SKILL.md` 「워커 루프」의 대기를 띄우고, 아니면 `worker-abandon --dispatch <id>` 후 보고하고 멈춘다
