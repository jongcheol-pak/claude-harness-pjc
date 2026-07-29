# pjc 스킬 eval

스킬 변경의 효과를 **감이 아니라 수치로** 재기 위한 계측 도구다. 여기의 러너는 기존 검증 경로(`run-hook-evals.ps1`·`check_consistency.py`)와 달리 **실제 모델을 호출**하므로 분·비용 단위 비용이 든다 — 그래서 Phase F 등 기본 검증 경로에 편입하지 않고 **명시 호출 전용**으로 둔다.

## 러너

| 러너 | 재는 것 | 입력 | 출력 |
|---|---|---|---|
| `trigger_eval.py` | 스킬 **트리거 정확도** (should-trigger 발동률 / should-not-trigger 오발동률) | `trigger-cases.json` 20건 | `trigger-<isolation>-<run_id>.json` |

## 공통 출력 계약

모든 러너는 상위 구조가 같은 JSON을 낸다. `cases[]` 내부 필드는 `kind`별로 다르다.

```json
{ "run_id": "20260729-141500", "kind": "trigger", "summary": { }, "cases": [ ] }
```

결과는 기본적으로 **시스템 임시 폴더**(`%TEMP%/pjc-evals/`)에 저장한다 — 측정 산출물이라 레포에 남기지 않는다. 보관하려면 `--out-dir`로 위치를 지정한다.

## trigger_eval.py

```
python trigger_eval.py                    # 격리 모드 전 케이스
python trigger_eval.py --isolation both   # 격리·비격리 각 1회 + 대조표
python trigger_eval.py --filter impl-     # id 접두 필터 (스모크용)
python trigger_eval.py --model opus       # 측정 모델 (기본 opus)
```

각 케이스를 `claude -p <query> --output-format stream-json`으로 실행하고 **Skill 도구 호출**을 관측해 발동 여부를 판정한다. 워크스페이스(`plan.md` 유무)는 실행 시점에 임시 폴더에 만든다 — repo `.gitignore`가 `plan.md`를 무시해 픽스처로 체크인할 수 없다.

### 이 러너가 반드시 지키는 것

1. **pjc 로드 단언** — `init` 이벤트의 `plugins` 배열에 `pjc`가 없으면 즉시 `exit 2`. 플러그인이 안 실렸는데 실행만 성공해 전 케이스가 "미발동"으로 집계되는 **은닉 실패**를 막는 축이다. `--plugin-dir`에 상위 디렉터리를 주면 실제로 이 상태가 된다(스킬 0개인데 exit 0).
2. **`PYTHONUTF8=1` 자체 설정** — 미설정 시 Windows에서 한글 출력이 `cp949` 인코딩 오류로 러너를 죽인다.
3. **watchdog kill** — 케이스당 180초 상한. 프로세스 트리까지 정리하며, timeout은 성공·실패 어느 쪽으로도 집계하지 않는다(판정을 못 한 것이지 결과가 아니다).

`expect: trigger` 케이스는 목표 스킬 발동을 관측하는 즉시 세션을 끊는다 — 판정에 필요한 정보를 이미 얻었으므로 남은 턴은 시간·토큰만 쓴다. `expect: no-trigger`는 "발동이 없었음"을 확인해야 하므로 끝까지 돌린다. 그래서 **턴 소진(`error_max_turns`)은 오류가 아니라 정상 종료**로 집계한다.

### 격리 모드가 재는 것 — 비격리보다 낮게 나오는 게 정상이다

격리 모드는 `CLAUDE_CONFIG_DIR`을 비우므로 실설치 pjc 스킬만이 아니라 **글로벌 `CLAUDE.md`와 다른 플러그인도 함께 사라진다.** 그래서 두 수치는 다른 것을 잰다:

- **격리** = 스킬 `description`만으로의 발동률 (문구 변경의 순수 효과 — A/B 비교의 기준)
- **비격리** = 실사용 환경의 발동률 (글로벌 지침이 발동을 거들어 더 높게 나온다)

2026-07-29 기준선에서 격리 0.6 / 비격리 0.9로 갈렸다. **한쪽 수치만 보고 "트리거가 나쁘다/좋다"로 결론짓지 말 것** — A/B 비교는 같은 모드끼리만 유효하다.

### 판정 규칙

- `expect: trigger` — `skill`이 발동해야 PASS
- `expect: no-trigger` — `skill`이 발동하지 않아야 PASS. **다른 스킬이 대신 발동하는 것은 무방**하다(라우팅이 목적이므로 오발동만 본다)
- `status`: `pass` / `fail` / `timeout`(상한 초과) / `error`(1회 재시도 후에도 실패)
- 발동률·오발동률은 **판정된 케이스만** 분모로 삼는다 — timeout·error를 실패로 섞으면 환경 장애가 트리거 품질 저하로 둔갑한다

### 케이스 추가

`trigger-cases.json`의 `cases[]`에 `id`·`skill`·`expect`·`workspace`·`query`·`why`를 넣는다. `why`는 러너가 읽지 않는 판정 근거이며, 케이스가 왜 그 기대값을 갖는지 후속 세션이 알 수 있게 남긴다.

## 비용

`--isolation both`는 케이스 수 × 2회의 세션을 띄운다(20건 → 40세션). 스모크 확인은 `--filter`로 1~2건만 돌린다.
