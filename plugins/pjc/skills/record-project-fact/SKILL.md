---
name: record-project-fact
description: Records a CONFIRMED project fact (build/run/test command, DB access, artifact location, untested layers) into an EXISTING AGENTS.md — on the suggest-agents-record hook's acceptance, or on request. Add, update, or remove. Triggers on "AGENTS.md에 기록", "빌드 명령 기록해줘", "DB 접근법 적어둬", "AGENTS.md에서 이 항목 빼줘". Also on injection-limit signals ("AGENTS.md가 너무 커졌어", "주입 상한 넘었어", the hook's "주입 상한 임박") — Step 5 relocates oversized sections and leaves a pointer. Also for RETROFIT ("AGENTS.md 정리해줘", "새 경계로 맞춰줘", "소급 정리") — measures, judges each section's destination, and hands off to pjc:plan instead of editing. Do NOT trigger for creating a new AGENTS.md - that file is created by pjc:plan Step 1 when it is missing - or for code work (pjc:plan/pjc:implement). Writes to AGENTS.md ONLY, never CLAUDE.md, and only after showing the change and getting approval; the sole exception is Step 5's verbatim relocation, which reports afterward. Retrofit is not exempt — it deletes, so the plan is approved first. Real secrets are forbidden — env var names only.
argument-hint: "(자동 — hook 제안 수락 또는 사용자 요청)"
---

# Record Project Fact

작업 중 **확인된 프로젝트 사실**(빌드·실행 명령, DB 접근 방법, 산출물 위치, 검증 명령, 의도적 테스트 비대상 계층)을 **기존 `AGENTS.md`에 추가·갱신·제거**한다. 다음 작업이 같은 정보를 재발견하지 않게 하고, 틀려진 정보가 남아 오도하지 않게 하는 것이 목적이다.

`AGENTS.md`는 SessionStart hook(`session-context`)이 세션마다 주입하므로 **한 번 기록하면 다음 세션부터 재확인이 사라진다.** 이 스킬은 「기록 측」만 담당한다.

## 절대 규칙

1. **승인 없이 쓰지 않는다** — 어느 섹션에 무엇을 추가/갱신/제거하는지 정확히 보여주고 승인받은 뒤에만 Edit한다. hook 제안은 「기록 제안」일 뿐 자동 위임이 아니다. 삭제도 같다. **예외는 Step 5 하나뿐**이다(근거는 `references/record-fact-rationale.md` §1).
2. **`AGENTS.md`만 대상** — `CLAUDE.md`는 수정하지 않는다(지침 파일이라 위험). **예외는 Step 5의 이관처 하나뿐**이며, **새 사실을 이관처에 직접 적는 것은 여전히 금지**다(§2).
3. **실제 시크릿 금지** — DB 연결 문자열·비밀번호·API 키·토큰·내부 IP/호스트를 적지 않는다. **환경변수 이름·설정 키 이름만** 적고 값은 `.env`(gitignore)로.
4. **확인된 사실만** — 직접 실행·확인한 명령/경로만. 추측("아마 이 명령일 것")은 적지 않는다.
5. **「의도적 비대상」은 사용자 확인으로만 성립한다** — 테스트가 없는 계층을 발견한 것만으로는 비대상이 아니다(빠뜨린 것일 수도 있다). 사용자가 의도라고 확인해야 적는다.
6. **중복은 추가가 아니라 갱신** — 같은 항목이 있으면 새 줄을 늘리지 말고 기존 줄을 고친다.
7. **삭제는 stale·틀린·시크릿이 든 항목만** — 멀쩡한 정보를 임의로 지우지 않는다. 무엇을 왜 지우는지 승인받는다.
8. **`AGENTS.md`가 없으면** `pjc:plan` Step 1의 최소 생성을 안내한다(이 스킬은 갱신 전담).

## 기록 대상 → 섹션 매핑

| 사실 종류 | 대상 섹션 |
|---|---|
| 빌드·실행 명령 · 테스트·검증 명령 | `## Build & Test` |
| DB 접근 방법 | `## 데이터 접근` |
| 파일·산출물 관리 | `## 산출물·파일 관리` |
| 테스트 비대상 계층·의도된 제약 | `## Conventions` |

**섹션이 없으면 신설한다.** 위치는 ① 그 `AGENTS.md`에 이미 있는 절 순서를 따르고 ② 판정할 순서가 없으면 `../AGENTS-BOUNDARY.md`의 **「생성물 골격」 뼈대 순서**를 따른다(§9). 섹션이 이미 있으면 그 안에 항목을 추가·갱신한다.

## 기록하지 않는 것

**무엇을 담고 무엇을 담지 않는지의 전체 경계는 `../AGENTS-BOUNDARY.md`가 정본**이다. 아래는 그중 *기록 요청으로 유입되기 쉬운 것*만 골라 대체 저장처를 짝지은 것이다.

| 기록하지 않는 것 | 정본 |
|---|---|
| **진행 상태** — 어디까지 했는지, 완료/예정 표 | 진행 중은 `plan.md`, 끝난 것은 git 커밋 |
| **plan 인계·다음 회차 지시** | 같음 |
| **프로젝트 정보** — 기술 스택·디렉터리 구조·**아키텍처 상세**·기능 목록 | 위키 프로젝트 허브 |
| **검증 명령의 상세 설명** — 무엇을 대조하는가·함정 | 레포 상세 문서. `AGENTS.md`에는 **명령과 ⚠ 1줄만** |
| **작업 규약·함정의 누적 서술** | 위키 `conventions.md` |

- **`## Conventions`가 위 표와 매핑 표에 모두 나온다** — 이름은 같지만 대상이 다르다(§3).
- **기록 요청이 이 목록에 걸리면** 거절하지 말고 **대체 저장처를 제안**한다.
- **이미 들어가 있는 것을 발견하면** 규칙 7의 승인 게이트를 거쳐 제거를 제안한다.

## 실행 절차

### Step 1. `AGENTS.md` 확인

Read한다. 없으면 *"`pjc:plan`으로 작업을 시작하면 최소 `AGENTS.md`가 먼저 생깁니다 — 그렇게 하시겠어요?"* 안내 후 종료.

### Step 2. 기록 내용 구성

매핑 표에 따라 섹션·항목으로 정리한다. 대상 섹션이 없으면 신설 위치를 정한다. 시크릿은 환경변수 이름으로 치환한다(규칙 3). 같은 항목이 있으면 갱신안으로 만든다(규칙 6). 삭제 요청이면 **제거 대상 줄을 정확히 특정**한다 — 다른 줄은 건드리지 않는다.

### Step 3. 변경안 제시 + 승인 (게이트)

```
다음을 AGENTS.md에 반영합니다:

[섹션] ## Build & Test
[추가/갱신/제거] - Test: dotnet test tests/

반영할까요? [Y/수정/취소]
```

삭제면 `[제거]`로 표시하고 **어느 줄을 왜 지우는지** 함께 보여준다.

**hook 제안 수락 경로는 재문답하지 않는다** — `suggest-agents-record`의 제안을 사용자가 수락해 발동됐고 변경안이 **그 제안과 동일**하면, 그 수락을 Step 3 승인으로 본다(변경안 제시는 유지 — 무엇을 반영하는지는 보여준다). 변경안이 제안과 **다르면**(내용을 보강·수정했으면) 종전대로 승인을 받는다.

### Step 4. Edit 후 보고

해당 줄만 고친다 — 기존 문구·다른 섹션 불변(최소 변경), UTF-8(BOM 없음) 유지. *"반영 완료: `<섹션>`에 `<항목>` 추가/갱신/제거"*를 보고한다.

### Step 5. 주입 상한 점검·이관

> **이 단계만 승인 게이트가 없다** — 무손실 이동이라 판정할 것이 없고 사본으로 되돌아간다(§1). 대신 **사후 보고가 의무**다.

**판정의 정본은 스크립트다.** Step 4를 마친 뒤 아래를 실행한다 — 발동 여부·잔류 절·이관 대상·이관처·포인터·사본·검증·정지 조건이 전부 그 안에 있고 **이 문서는 그것을 복제하지 않는다**(같은 판정이 두 곳에 있으면 한쪽만 고쳐진다).

```
python "<skill>/scripts/relocate-agents.py" "<레포 루트>" [--dry-run]
```

- **판정 서술을 읽어야 하면** 그 스크립트의 모듈 docstring을 연다(ⓐ 발동 ~ ⓘ 이관 불가).
- **상한은 hook에서 읽는다** — `session-context.ps1`의 `$agentsMaxBytes`·`$agentsNearRatio`·`$agentsNearSlack`. 값을 스크립트에 박지 않으므로 hook이 임계를 바꾸면 판정도 따라간다.
- **종료 코드** 0 = 이관했거나 발동하지 않음 / 1 = 검증 실패로 원복했거나 입력 오류. 1이면 그 출력을 그대로 사용자에게 전달하고 **자동 재시도하지 않는다**.
- **회귀 자산** `<skill>/evals/run_relocation_evals.py` — 스크립트를 고치면 함께 돌린다.
- **「이관 불가」를 마커로 남기지 않는다** — Step 4가 끝날 때마다 다시 판정한다(§7).

**사후 보고** — 스크립트 출력을 그대로 옮기지 말고 아래로 정리한다:

```
## 📦 AGENTS.md 주입 상한 이관
- 이관 전: <N>B / 상한 <M>B
- 옮긴 절: 「<절 이름>」 <K>B → `<이관처>`
- 남긴 포인터: AGENTS.md의 같은 자리 1줄
- 이관 후: <N'>B (여유 <M-N'>B)
- 되돌리려면: `docs/.agents-presplit/{날짜}/`의 **두 사본을 함께**
  (AGENTS.md만 되돌리면 포인터가 아직 옮겨지지 않은 절을 가리킨다)
```

## 소급 정리

> **Step 5와 다른 경로다 — 합치지 않는다.** 발동·승인·산출물이 전부 다르고, Step 5가 무승인인 근거는 소급 정리에 성립하지 않는다(§4).

**발동** — 사용자가 `"AGENTS.md 정리해줘"`·`"새 경계로 맞춰줘"`처럼 요청할 때. Step 5가 「이관 불가」를 낸 뒤 그 안내를 따라 들어오는 경우도 같다.

**산출물은 `plan.md`다 — 이 스킬이 직접 고치지 않는다**(§4).

1. **현황을 잰다** — 전체 바이트와 **절별 바이트**. 절 이름과 크기가 없으면 무엇부터 손댈지 정할 수 없다.
2. **절마다 목적지를 판정한다** — 위키 / 레포 상세 문서 / 삭제 / 잔류.
3. **정리안을 표로 제시하고 승인받는다** — 절 · 현재 바이트 · 처리 · **삭제면 정본 근거**. **근거 칸이 빈 삭제 항목이 하나라도 있으면 승인을 요청하지 않는다** — 그 항목의 정본을 먼저 실측하거나 삭제에서 뺀다.
4. **`pjc:plan`으로 넘긴다** — 승인된 정리안이 그 plan의 입력이다. 그때 **아래 도달 대조 명령을 그 plan의 검증 acceptance로 넣는다** — 「무손실 역대조를 건다」는 서술만 넘기면 실행자가 무엇을 돌릴지 몰라 대조가 통째로 빠진다.

   ```
   python <skill>/scripts/relocate-agents.py --verify-only <정리 전 원문> <정리 후 AGENTS.md> <이관처...> --declared <삭제 선언 파일>
   ```

   원문의 각 줄이 결과 어딘가에 도달했는지 세고, 도달하지 않았는데 `--declared`에도 없는 줄을 전건 출력한다(미도달 0이면 rc 0 · 있으면 rc 1 · 입력 오류는 rc 2). **`--declared`는 이 경로의 필수 인자다**(§8).

### 목적지 판정

**무엇이 어디에 담기는가의 정본은 `../AGENTS-BOUNDARY.md`다** — 여기서 재서술하지 않는다. 이 절이 정하는 것은 **이미 있는 내용을 옮길 때의 판정**이다.

**① 「옮긴다」와 「지운다」를 가른다 — 삭제는 정본 실측이 선행한다.** 지우려는 내용의 정본이 다른 곳에 실제로 있는지 확인한 근거(파일 경로·건수·명령 출력) 없이는 삭제하지 않는다(§5).

**② 목적지는 셋이다** — 위키 · 레포 상세 문서 · 삭제. 어느 절이 어디로 가는지는 경계 표의 행이 정한다. 삭제는 ①의 실측을 통과한 것만이다.

**레포 상세 문서가 없으면 만든다.** 이름은 그 내용이 무엇인지로 정하고(`docs/verification.md`·`docs/data-stores.md`처럼) `docs/` 아래 둔다. **한 파일에 몰아넣지 않는다**(§6). 각 문서 머리에 **어디서 옮겨 왔는지 1줄**을 남긴다.

**③ 잔류 절도 축약 대상이다** — 절 이름이 잔류라고 그 절 **전체**가 잔류인 것은 아니다. 판정 축과 실측 근거는 경계 표의 「증가 억제 규칙」이 정본이며 여기서 재서술하지 않는다.

## See also

- `../AGENTS-BOUNDARY.md` — 내용 경계의 정본
- `references/record-fact-rationale.md` — 이 절차가 왜 이렇게 생겼는가
