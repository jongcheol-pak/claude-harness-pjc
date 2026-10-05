# 중계 모드 — 드문 조건

> `relay-mode.md`「중계 모드」 의 트리거가 걸렸을 때만 해당 절을 읽는다 — 워커가 매번 읽는 중계 규칙에서 드문 조건에만 쓰는 규칙을 떼어 둔 자리다. `<CLI>` 와 `ask` 명령은 `relay-mode.md`「중계 모드」 의 것이다.

## 아키텍처 선언 부재

- **`AGENTS.md` 에 아키텍처 선언이 없으면 재진술 제약조건에 실린 선언을 쓰고, 거기도 없으면 `relay-mode.md`「중계 모드」 의 `ask` 로 묻는다** — `../SKILL.md` Step 1 은 그것을 Step 2 의 질문으로 확정하는데 중계 모드는 Step 2 를 건너뛰고, 코디네이터가 인터뷰에서 확정해 제약조건에 싣는다(`../../chain-plan/SKILL.md`「인터뷰」). `../../AGENTS-BOUNDARY.md`「AGENTS.md 최소 생성」이 말하는 「Step 2의 답」 자리도 이것이 대신한다.

## ask 만료

- **만료 응답(`answered:false`·`status:"pending"`)이면 `ask --resume <questionId>` 로 같은 질문을 이어 간다 — 다시 묻지 않는다** — 새로 `ask` 하면 같은 질문이 코디네이터에 둘 쌓인다. 시한을 Bash 도구 상한보다 짧게 잡는 것은 도구가 먼저 끊으면 `questionId` 가 출력되지 않기 때문이다.
- **이어 가기 전에 `<CLI> orchestration check --json 2>/dev/null` 로 코디네이터의 대기 신호(`status` 유형, 제목 `사용자 확인 대기 중`)를 본다 — 신호가 있으면 사용자 판단을 기다리는 중이라 상한 없이 이어 가고, 신호 없는 만료가 3회 연속이면 `worker_done --outcome failed`(사유: 코디네이터 무응답)로 멈춘다** — `ask` 는 막는 호출이라 무응답과 사용자 대기를 그 사이의 신호로만 가를 수 있다. 3회는 같은 수단을 세 번 반복해도 닿지 않을 때 멈추는 수다.
