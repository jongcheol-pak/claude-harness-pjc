# pjc 스킬 eval

스킬 변경의 효과를 **감이 아니라 수치로** 재기 위한 계측 도구다. 여기의 러너는 기존 검증 경로(`run-hook-evals.ps1`·`check_consistency.py`)와 달리 **실제 모델을 호출**하므로 분·비용 단위 비용이 든다 — 그래서 Phase F 등 기본 검증 경로에 편입하지 않고 **명시 호출 전용**으로 둔다.

## 러너

| 러너 | 재는 것 | 입력 | 출력 |
|---|---|---|---|
| `trigger_eval.py` | 스킬 **트리거 정확도** (should-trigger 발동률 / should-not-trigger 오발동률) | `trigger-cases.json` 56건 (8스킬 × 최소 5건, `plan-feature`는 16건) | `trigger-<isolation>-<run_id>.json` |
| `rubric_eval.py` | plan **산출물 품질** (`rubric.md` 8항목 × 1-10점 + 근거) | `docs/plans/`의 과거 plan | `rubric-<run_id>.json` |
| `compare_evals.py` | 두 run의 **증감·회귀** | 위 두 러너의 결과 JSON 2개 | stdout 증감표 |

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

`trigger-cases.json`의 `cases[]`에 `id`·`skill`·`expect`·`workspace`·`query`·`why`를 넣는다.

**`workspace`는 5종**이며 러너가 케이스 파일에서 쓰이는 종류만 골라 만든다(목록을 코드에 박지 않는다 — 새 종류를 추가하면 러너가 자동으로 만든다):
- `no_plan` — AGENTS.md·소스만 있는 기본 프로젝트(Python 단일 스크립트).
- `with_plan` — 거기에 **미완료 task가 있는 plan.md**를 더한 것. `implement-task`는 승인된 plan이 있을 때만 발동하므로 plan 유무가 곧 트리거 조건의 일부다.
- `no_agents_md` — **AGENTS.md가 없는** 프로젝트. `bootstrap-agents-md`는 그 파일의 **부재**가 발동 조건이다.
- `ddd_project` — Domain/Application/Infrastructure 레이어 + DDD를 명시한 AGENTS.md. `add-domain-service`용.
- `xaml_project` — Views/ViewModels + WinUI·CommunityToolkit.Mvvm을 명시한 AGENTS.md. `add-viewmodel`용.

> **⚠ 워크스페이스가 스킬의 발동 조건과 어긋나면 "발동 안 함"이 스킬 결함이 아니라 픽스처 결함이 된다.** 뒤의 세 종류는 전부 그래서 생겼다 — 실제로 1차 측정에서 `add-domain-service`·`add-viewmodel`이 **0/3**이었는데, 두 스킬 description이 *"scripts·single-project apps"*·*"non-XAML stacks"*를 **명시적 제외**로 두므로 기본 워크스페이스(Python 스크립트)에서는 **미발동이 정상**이었다. 새 스킬 케이스를 추가할 때는 **그 스킬의 제외 조건부터 읽고** 워크스페이스가 거기 걸리지 않는지 확인할 것.

**케이스 설계 시**: 질의를 description 문구에서 그대로 베끼지 않는다 — 그러면 발동률이 아니라 **복창률**을 재게 된다. 실측으로도 그렇게 나왔다 — `bootstrap-agents-md` 양성 3건이 description 예시를 거의 그대로 쓴 상태에서 **3/3**이었는데, 그중 2건을 같은 의도의 자연스러운 발화로 바꾸자 **1/3~2/3**으로 내려갔다(재작성 직후 스모크 1/3, 최종 전량 측정 2/3). **개별 수치를 고정 사실로 읽지 말 것** — 트리거 판정은 케이스당 1회라 런마다 흔들린다. 읽어야 할 것은 "베낀 질의가 더 잘 발동한다"는 방향이며, 그 차이가 곧 복창으로 얻은 발동이다.

**질의에 스택·환경을 쓰지 않는다** — 그것은 워크스페이스(AGENTS.md)가 정한다. 워크스페이스가 WinUI인데 질의에 "MAUI 프로젝트에"라고 쓰면 **전제가 모순돼 미발동이 정상**이 되고, 그 FAIL은 트리거 품질과 무관하다(실제로 `vm-pos-3`이 그렇게 실패했다). `no-trigger`는 **인접 스킬과 갈리는 경계**를 고르는 것이 가장 값지다(예: `bootstrap-agents-md`의 "AGENTS.md 새로 만들어줘" ↔ `record-project-fact`의 "AGENTS.md에 한 줄 추가해줘" — 두 방향을 모두 케이스로 두면 라우팅이 실제로 갈리는지 보인다). `why`는 러너가 읽지 않는 판정 근거이며, 케이스가 왜 그 기대값을 갖는지 후속 세션이 알 수 있게 남긴다.

## rubric_eval.py

```
python rubric_eval.py                     # docs/plans/의 전 plan을 2회씩 채점
python rubric_eval.py --repeats 1         # 편차 측정 없이 1회만 (스모크)
python rubric_eval.py --filter harness     # plan 파일명 부분 일치 필터
python rubric_eval.py --plans-dir <경로>   # 입력 세트 지정
```

`rubric.md`의 8개 항목을 judge에게 그대로 실어 보내 각 plan을 채점한다. 채점 대상은 파일명이 `YYYY-MM-DD-<slug>.md`인 것만이다 — `deferred.md` 같은 대장 문서를 plan으로 오인해 채점하지 않기 위한 필터다.

### 이 러너가 반드시 지키는 것

1. **근거 없는 점수는 점수로 세지 않는다** — 항목마다 `파일:라인` 근거를 받고, 근거가 없으면 러너가 그 점수를 `N/A`로 내린다(judge가 숫자를 냈더라도). 근거 없는 숫자는 A/B 비교의 기준이 되지 못한다.
2. **기본 2회 채점 + 편차 보고** — judge 채점은 실행마다 흔들린다. 편차를 모르면 "1점 올랐다"가 개선인지 잡음인지 구분할 수 없다. 편차는 **전 회차의 폭(최댓값 - 최솟값)** 이라 `--repeats`를 3 이상으로 올려도 뒤 회차가 통계에서 빠지지 않는다. 한 회차라도 `N/A`인 항목은 편차를 계산하지 않는다(`N/A`를 0점으로 취급하면 "채점 못 함"이 "최하점"으로 둔갑한다).
3. **중립 cwd + 격리 `CLAUDE_CONFIG_DIR`** — 프로젝트 `AGENTS.md`나 글로벌 `CLAUDE.md`가 채점 기준에 끼어들면 같은 plan이 환경에 따라 다른 점수를 받는다. 플러그인은 싣지 않는다(judge는 스킬을 쓰지 않는다).
4. **절단을 숨기지 않는다** — 입력 상한 30,000자를 넘으면 잘라내되 `truncated`와 `issues`에 남긴다. 조용한 절단은 "뒷부분이 부실해서 낮은 점수"와 "안 보여줘서 낮은 점수"를 구분 불가능하게 만든다.

### 루브릭을 고칠 때

항목 키는 `rubric.md`의 `### N. 이름 (key)` 형식에서 **동적으로 추출**한다 — 루브릭을 고쳤는데 러너가 옛 항목을 기대해 전부 "불일치"로 집계되는 어긋남을 막기 위해서다. 다만 **항목을 더하거나 빼면 과거 run과의 점수 비교가 깨지므로**, 그럴 때는 새 `run_id` 세대로 구분하고 옛 run과 직접 비교하지 않는다.

## compare_evals.py

```
python compare_evals.py <before.json> <after.json>
```

두 러너의 결과 JSON **만** 읽는다 — 러너를 호출하지 않으므로 모델 비용이 들지 않고 언제든 다시 돌릴 수 있다. `kind`에 따라 비교 방식이 갈린다(트리거는 케이스별 발동 여부, 루브릭은 plan × 항목 점수).

- **회귀를 따로 모아 보여준다** — 총점이 올라도 특정 케이스가 무너졌으면 그것이 알아야 할 사실이다.
- **교집합만 비교하고 빠진 것을 반드시 출력한다** — 조용히 빼면 "비교했다"가 거짓이 된다. 공통 항목이 0건이면 그 사실을 경고로 알린다.
- **한쪽이 `N/A`인 항목은 증감을 만들지 않는다** — 없는 점수를 0으로 두면 허위 낙폭이 생긴다.
- 통계 검정도 시각화도 하지 않는다. 차이가 잡음인지 신호인지는 러너가 함께 보고하는 **편차 수치**를 보고 사람이 판단한다(2026-07-29 기준선의 편차는 최대 1점).
- exit code: 비교 완료 `0` / 입력 오류·`kind` 불일치 `1`.

`kind`가 다른 run, D4 상위 구조가 아닌 파일, 없는 파일은 전부 명확한 메시지와 함께 `exit 1`로 거부한다.

## 비용

`trigger_eval.py --isolation both`는 케이스 수 × 2회의 세션을 띄운다(56건 → 112세션). `rubric_eval.py`는 plan 수 × `--repeats`회의 judge 호출을 하며, plan 1건 채점에 1분 내외가 걸린다. 스모크 확인은 `--filter`(+ `--repeats 1`)로 1건만 돌린다.
