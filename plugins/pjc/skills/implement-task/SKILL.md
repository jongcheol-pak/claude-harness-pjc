---
name: implement-task
description: This skill should be used when executing tasks from an approved plan.md. Triggers — ONLY when an approved plan.md already exists (or the user is approving a plan just presented) — on phrases like "구현", "implement", "이대로 진행", "진행해", "계속", "T<N> 진행", "go" (meaning "proceed with the plan"). If NO plan exists yet and the user asks to design or implement a non-trivial change, that is plan-feature first — it writes the plan, this skill runs it. Runs a FULLY AUTONOMOUS loop — processes ALL tasks (T1...Tn) without asking between tasks, stopping only when every task completes or a Halt Condition fires. Resuming mid-plan ("T6부터 계속") means T6 through the LAST task plus Phase F/G, not just T6. For trivial single-line edits without a plan, do NOT use this skill — Claude applies the change directly and lets hooks validate.
argument-hint: "<시작 task ID (거기부터 끝까지 자율 진행) | 생략 시 첫 미완료부터>"
disallowed-tools: AskUserQuestion
---

# Implement Task

승인된 plan.md의 작업을 PIV 루프(Plan-Implement-Validate)로 자율 실행한다.
각 task는 Type에 따라 적절한 단계 통과 후에만 완료된다.

## 자율성 모드: FULLY AUTONOMOUS

> **이 skill 안에서는 사용자에게 묻지 않는다.**
> plan-feature에서 모든 결정이 사전 해결되었음을 전제로 진행.
>
> 멈춤은 **Halt Condition**에서만 발생. 사소한 결정은 plan.md follow-up으로 기록 후 계속.

```
plan-feature                    | implement-task (이 skill)
USER-INTERACTIVE                | FULLY AUTONOMOUS
                                |
질문 OK (Open Questions에 모음) | 질문 금지 (Halt만 가능)
사용자 승인 1회 (게이트)         | plan = 전체 위임장
                                |
                  ↑ 모든 질문 해결 후 ─── 이 시점부터 자율 ───
```

> **질문 도구 제거는 보조 장치일 뿐 — 1차 방어선은 여전히 이 문서의 규칙이다.** 이 스킬의 frontmatter는 `disallowed-tools`로 질문 도구를 내려놓는다(공식 문서가 "자율 배경 루프의 `AskUserQuestion`"을 이 필드의 용례로 든다). **실동작은 확인됐다** — 설치본에서 이 스킬을 로드한 뒤 `AskUserQuestion`을 호출하면 거부된다(2026-07-30 실측). 다만 **그 제거는 사용자가 다음 메시지를 보내면 풀린다** — 한 turn 안에서만 유효한 보조 장치다. 그러니 **"도구가 막혀 있으니 안전하다"고 가정하지 말 것**: "task 사이에 묻지 않는다"·금지 표현 목록이 실제로 지키는 규칙이고, 필드는 실수를 한 겹 더 막아 줄 뿐이다.
>
> 이 제거는 **Halt 보고·리뷰어 과부하 시 선택 요청·최종 보고에 영향이 없다** — 그 셋은 모두 텍스트로 출력하고 사용자의 다음 입력을 기다리는 경로이지 질문 도구를 쓰는 경로가 아니다.

## 절대 규칙 (Hard Rules)

### 완료 정의
1. **Done = Proof.** 빌드 통과, 테스트 통과, 또는 재현 가능한 출력 없이는 완료 선언 금지.

2. **검증된 코드만 사용 (환각·예측 금지).**
   - 모르는 API/라이브러리/시그니처는 Read 또는 문서 확인 후 사용.
   - 정의를 못 찾으면 호출 코드 작성 금지.
   - "이 함수가 있을 것", "이 인자를 받을 것" 같은 추정은 환각 → 리뷰에서 BLOCKER.

3. **연관 파일 함께 수정 (Cross-File Consistency).**
   - 시그니처/타입/계약을 바꾸면 **모든 호출자/구현체/직렬화/테스트를 같은 task에서 함께 수정**.
   - a만 고치고 b·c를 두면 빌드 실패 또는 런타임 오류 → 완료 선언 금지.
   - Phase P-3에서 사전 식별, Phase V-5/V-7과 impact-warn hook에서 사후 검증.

### 변경 범위
4. **요청한 것만, 확인된 범위 안에서, 최소한으로 수정.**
   - 무관한 리팩토링·서식 변경·import 정리 금지.
   - 작업 중 발견한 다른 문제는 plan.md follow-up에 추가만. 발견한 것이 **pjc 스킬 자체의 결함·마찰**이면 `pjc:llm-wiki` 절차 K 5-1의 `[SKILL-IMPROVE]` 큐에도 1줄 기록한다(vault 없으면 그 규약의 폴백을 따름).
   - 한 번에 한 task만 수행.

### 아키텍처·코드 규율
5. **DDD 준수 + YAGNI.**
   - 비즈니스 로직은 Domain 레이어 (AGENTS.md가 다른 아키텍처를 명시하면 우선 적용).
   - 사용처 1곳인 헬퍼는 인라인. **3회 반복 확인된 코드만 공통화** (글로벌 CLAUDE.md의 "2회 이상" 문턱을 이 스킬이 강화한 값 — 성급한 DRY로 인한 과추상화를 더 늦게 트리거해 추적성을 우선한다. 지침 우선순위상 발동 스킬 규칙이 글로벌보다 우선하므로 자율 루프에서는 3회를 적용한다. code-quality-reviewer 항목 D도 동일 기준).

5-1. **명시적·직접적 코드 우선 (추적성).** 영리한 추상화보다 한눈에 동작이 보이는 코드(**"약간 장황해도 추측 없이 파악되는"**)를 쓴다 — 과한 간접화(불필요한 패턴·메타프로그래밍·깊은 제네릭·성급한 DRY)는 이후 수정 시 실제 동작 추적을 위해 여러 파일을 오가게 만들어 누락·환각·재작업을 늘린다. 단 좋은 이름·명시적 타입·명확한 구조·관련 로직의 지역성은 유지한다(명료성 훼손이 아님). 간접화가 정당한 경우(3회+ 반복·도메인 필수)는 예외 — 판단 기준은 "이 추상화를 빼면 코드가 더 단순해지는가".

6. **위생.** 불필요한 주석·죽은 코드·미사용 import·placeholder 문서 금지.

6-1. **민감 정보 금지 (코드·문서 공통).** 실제 비밀번호·API 키·토큰·시크릿·DB 연결 문자열·내부 IP/호스트·개인정보를 **코드는 물론 어떤 생성 문서(plan.md·notes.md·repro.md·PRD·위키 등)에도 적지 않는다.** 이 문서들은 git commit·스냅샷으로 영구 보존되므로 한 번 남으면 회수가 어렵다. 필요하면 **환경변수 이름만** 적고 실제 값은 `.env`(gitignore)에서 관리한다. (`check-utf8-and-lines` hook이 실제 값 패턴을 사후 경고하지만, 1차 책임은 작성 시 회피다.)

7. **주석은 한글.** "무엇"이 아닌 "왜". 코드로 의도가 드러나면 생략.

7-1. **주석·코드 동기화 (stale 주석 금지).** 코드를 수정하면 그 코드에 딸린 주석·docstring·XML 문서주석(`///`)이 새 동작과 일치하는지 **반드시 확인하고, 어긋나면 함께 수정**한다. 코드만 바꾸고 주석을 옛 내용 그대로 두면, 틀린 주석이 오히려 후속 작업(사람·LLM 모두)을 오도한다 — 틀린 주석은 주석이 없는 것보다 나쁘다.
   - 대상: 변경한 함수/메서드 위 주석, 파라미터·반환 설명, 인라인 주석, docstring/`///` 문서, 시그니처가 바뀌면 호출처 주석까지.
   - 더 이상 맞지 않는 주석은 갱신하거나(내용이 바뀐 경우) 삭제한다(코드로 자명해진 경우). "왜"가 바뀌었으면 그 이유를 갱신한다.
   - Phase V-8 자기점검과 code-quality 검토에서 stale 주석을 확인한다.

7-2. **UI 문구는 일반 사용자 친화적으로.** 화면에 표시되는 문구(레이블·버튼·메시지·오류·툴팁·플레이스홀더)는 **개발 용어가 아니라 일반 사용자가 이해하는 일상 언어**로 쓴다(개발/기술 용어·변수명·열거형 값 노출 금지, 오류는 원인+다음 행동 중심). 판단이 애매한 문구는 plan에 ⏳ HUMAN-VERIFY로 표시해 사용자 확인을 받는다. 문구는 리소스로 분리하되(다국어) 내용 자체가 사용자 친화적이어야 한다. **금지 용어·오류 예시·리소스 분리 상세: `references/authoring-detail.md`.**

7-3. **코드에 흔적이 남지 않는 결정은 그 자리에 1줄 근거 주석.** 있는 코드는 스스로 증거지만, **"의도적으로 넣지 않은 것"·"의도적으로 남긴 것"은 아무 흔적도 남기지 않아** 다음 세션(사람·LLM)이 설계 의도인지 미완성인지 코드로 판정할 수 없다. 아래 네 경우에만 그 판단이 걸린 **가장 가까운 코드 지점**에 `{무엇을/무엇을 안 함} — {왜}` 1줄을 남긴다: ① 값·선택지·분기를 **의도적으로 뺀 자리**(plan `## Decisions`·`## Out of Scope`·Design ④에 근거가 있는 것) ② **미사용인데 남기기로 판정한 심볼**(V-7 역방향의 고아 후보 — 하위호환·외부 계약) ③ **근거 없이는 임의로 보이는 튜닝 상수**(타임아웃·지연·재시도 횟수·크기/임계 한계) ④ **기본값을 바꿨지만 기존 저장 데이터엔 적용되지 않는 선언**.
   - **주석을 늘리라는 규칙이 아니다.** 규칙 7이 이미 요구하는 "왜" 중 **코드로 대체 불가능한 것만** 골라낸 것이며, 위 네 경우 밖에는 적용하지 않는다 — 코드를 읽으면 아는 것에 주석을 다는 것은 규칙 6 위반이다. **plan·코드 어디에도 근거가 없으면 지어내지 말고 주석도 쓰지 않는다**(근거 없는 "왜"는 환각이다). **WRONG/RIGHT 예시: `references/authoring-detail.md`.**

8. **파일·인코딩.** UTF-8 (BOM 없음). **파일은 하나의 명확한 책임을 갖는다** — 여러 독립 책임이 한 파일에 섞여 비대해지면 책임 단위로 분리한다. **1500라인은 강제 분리선이 아니라 "분리를 검토하라"는 신호다.** 단일 책임인데 길 뿐이면 억지로 쪼개지 않는다 (관련 로직을 여러 파일로 흩으면 지역성이 깨져 후속 추적·수정이 오히려 어려워진다 — 규칙 5-1). 분리할 때는 응집도를 유지해 관련 로직이 흩어지지 않게 한다. 분리가 필요하면 작업을 plan에 등록.

9. **언어 스타일.** 최신 LTS 권장 + 공식 문서 기준. AGENTS.md가 다른 버전 고정이면 우선.

### 안전
10. **파괴적 작업 · 새 의존성 → 자동 실행 금지, Halt.**
    - force push, history rewrite, rm -rf, DB drop, 권한·보안 변경 — **history rewrite는 공유·push된 이력 대상이다**: 로컬 미push 작업 브랜치에서 **Phase D ③이 규정한 pre-review 커밋 amend는 해당하지 않는다**(스킬 자신의 정상 절차 — 이 예외는 그 amend에만 한정되며 force push 등 다른 항목으로 확대 해석하지 않는다)
    - **DB 데이터 삭제·변조**: DROP/TRUNCATE, WHERE 없는(또는 전체 대상) DELETE·UPDATE, 스키마 삭제, migration reset/down, ORM 대량 삭제(RemoveRange·deleteMany({})·delete_all 등). 코드로 작성하든 명령으로 실행하든, 데이터 손실·전체 변조 가능 작업은 **사용자 승인 전 금지** (DB 데이터는 git으로 복구 불가). 단 `DELETE/UPDATE ... WHERE <특정 조건>` 같은 일상적·국소적 작업은 plan에 명시돼 있으면 진행 가능.
    - **새 라이브러리·외부 서비스 도입** — 단 plan의 `## 사전 승인 항목 (일괄 승인 대상)`에 등록·일괄 승인된 **비파괴 패키지/라이브러리 의존성 추가·버전 변경**은 그 지점에서 진행한다(Halt 안 함). **인증정보가 필요한 신규 외부 서비스 도입은 carve-out 제외 — Halt 유지**(자격증명 도입은 보안상 별개).
    - **기존 외부 서비스로의 비가역 부작용 호출**: 운영 API 쓰기·이메일/알림/SMS 발송·결제·외부 상태 변경 등. 신규 도입이 아니어도 검증·실행 중 이런 비가역 부작용 호출은 사용자 승인 전 금지(테스트는 mock·스테이징). plan에 명시·승인됐으면 진행 가능.
    - **사전 승인과의 관계 (위임 경계)**: 위임 O(사전승인)·항상 Halt·조건부의 **단일 표는 `references/halt-conditions.md` "위임 경계"** — 요지: 파괴적 작업(force push·DB drop/TRUNCATE·WHERE 없는 DELETE/UPDATE·스키마 삭제·migration reset·권한/보안)은 plan에 적혀 있어도 **항상 Halt(위임 불가)**, 위임되는 것은 비파괴 패키지 의존성·계획된 구조 변경·비파괴 스키마(CREATE/ADD)뿐이다.

11. **plan에 답이 없는 중대 결정 → 추측 금지, Halt** (예외 안전망 — 정상적으로는 계획 단계가 미리 해결하므로 드물어야 하며, 발생 시 계획 부실 신호). plan·AGENTS.md·코드 어디에도 근거 없는 **중대한** 결정(아키텍처·비가역 데이터 형식·API 계약·동작 의미가 갈리는 분기)은 추측 없이 Halt해 묻는다. **사소한** 결정(변수명·국소 구현 등 가역)은 follow-up 기록 후 진행. **애매하면 보수적으로 Halt** — 안전·수정 범위·공개 API 계약·비가역성에 닿으면 승인받고(글로벌 "애매하면 승인"과 정합), 순수 국소·가역 결정만 follow-up 후 진행. Halt 시 보고에 "이 결정이 계획에서 누락된 이유" 한 줄을 적어 차후 계획을 강화한다.

12. **외부/비가역 작업 → 자율 루프 권한 밖, 별도 명시 승인.** push·main 병합·태그·GitHub 릴리즈·PR 생성은 자율 루프가 자동 수행하지 않는다. 루프 권한은 로컬 작업 브랜치(`task/<id>-<slug>`) commit까지다. 이 작업들은 'plan 승인'·'구현 진행' 승인에 **포함되지 않으며**, 각각 그 행위를 이름으로 적어 별도 승인받는다. 애매하면 승인 필요로 본다. 이 항목들은 plan의 `## 불가피한 Halt (위임 불가)`로 명시되며 일괄 사전승인(Phase 0)에 포함되지 않는다.

> **상세 안티패턴 표는 `references/antipatterns.md` 참조.**
> **중단 조건 전체 표 + 중단 보고 양식은 `references/halt-conditions.md` 참조 — Halt 여부가 애매하면 먼저 확인.**

## 자율 루프 (Autonomous Loop)

### ⚙️ 세션 effort 확인 (루프 시작 전, 1회)

**이 세션의 effort: `${CLAUDE_EFFORT}`**

위 값이 **`low` 또는 `medium`이면** 루프 시작 전에 한 줄로 알린다:

> "현재 세션 effort가 `<값>`입니다. 자율 루프는 task마다 Phase P~V를 돌며 caller 추적·리뷰 지적 판정을 하므로 `high` 이상을 권합니다. 이대로 진행하면 검증 깊이가 낮아질 수 있습니다."

알린 뒤에는 **답을 기다리지 않고 그대로 진행한다** — 이것은 경고이지 승인 요청이 아니다(사용자가 낮은 effort를 의도적으로 골랐을 수 있고, 여기서 멈추면 "task 사이에 묻지 않는다"가 무너진다). `high`·`xhigh`·`max`면 아무것도 출력하지 않는다.

<!-- 위 굵은 줄의 값은 Claude Code가 스킬 로드 시 치환해 넣는다(치환 변수: "CLAUDE_" + "EFFORT"를 `${...}`로 감싼 것 — 이 주석에 붙여 쓰면 여기도 치환되므로 쪼개 적는다). 치환은 원본 파일 전체에 1회 적용되며 코드펜스 안이라고 예외가 아니다. 단 **치환이 일어나는 것은 스킬 로드 경로뿐이다** — 압축 후 이 파일을 Read로 다시 읽으면(컨텍스트 관리 규칙 4) 위 굵은 줄은 미치환 리터럴로 보인다(2026-07-30 실측). effort 확인은 루프 시작 전 1회라 재확인 대상이 아니고, 리터럴은 low/medium 어느 쪽도 아니어서 경고가 오발화하지도 않는다. -->

### 🧭 시작 전 컨텍스트 공시 (구현 시작 직전, 1회 — 답을 기다리지 않는다)

**배치 순서**: 위 effort 확인 → 이 컨텍스트 공시 → Phase 0 → 루프.

자율 루프 **시작 전**, 이번 세션에 이미 auto-compact가 있었거나 대화가 매우 길게 누적됐으면(=시작 후 압축 반복으로 후반 task 품질 저하 위험) 한 줄로 알린다:
> "현재 대화가 길어 컨텍스트가 많이 찼습니다. 새 세션에서 시작하는 편이 후반 task 품질에 유리하지만(plan.md가 있어 'T1부터 진행'으로 이어집니다), **이대로 계속 진행합니다** — 옮기시려면 지금 중단해 주세요."

알린 뒤에는 **답을 기다리지 않고 그대로 루프를 시작한다** — 위 effort 확인과 같은 성격의 경고이지 승인 요청이 아니다.

- **이 절은 질문 형태를 쓰지 않는다.** 세션 전환을 물어 turn을 끝내면 그 자체가 아래 **금지 표현 ③**이며, 더 나쁜 것은 **압축 후 이 파일을 재읽기(컨텍스트 관리 규칙 4)했을 때 이 절이 루프 중간에 되살아난다**는 점이다 — 재읽기 시점엔 "이번 세션에 이미 auto-compact가 있었"는 조건이 항상 참이라, 질문형 템플릿이 여기 있으면 그것을 그대로 꺼내 루프를 세운다. 실제로 **T1 완료 후 T2 진행 중에 "이대로 계속할지, 새 세션으로 옮길지 알려주세요"로 정지한 사례**가 관측돼 이 절을 공시형으로 바꿨다.
- **컨텍스트가 여유로우면 아무것도 출력하지 않는다**(과잉 방지).
- **동일 세션에서 plan-feature를 막 거쳐온 경우는 생략**한다(plan-feature Step 0에서 이미 확인 — 중복). 새 세션 재개(implement-task 직접 호출)에서만 수행한다.

### 🚦 Phase 0 — 사전 승인 일괄 확인 (하이브리드 게이트)

자율 루프 시작 직전(첫 task 전, 1회). **배치 순서: 위 `🧭 시작 전 컨텍스트 공시` → Phase 0 → 루프.** 재개 진입(아래 "재개 진입")인 경우 task 식별을 마친 뒤·첫 Phase P 진입 전에 1회 수행한다.

1. plan.md의 `## 사전 승인 항목 (일괄 승인 대상)`을 읽는다. **비어 있거나(`- (없음)`) 섹션이 없으면 → Phase 0를 즉시 통과**하고 루프를 시작한다(이 기능 도입 전 plan과 무회귀).
2. 항목이 있으면:
   - **이번 대화에서 plan 승인을 이미 받았으면**(plan-feature Step 10 직후 같은 세션) → 재질문하지 않는다. "다음 사전 승인 항목이 plan 승인에 포함됨: [목록]. 이 지점들에서 멈추지 않고 진행합니다" **1줄 공시 후** 루프 시작.
   - **새 세션/재개라 이번 대화에 plan 승인이 없으면** → `## 사전 승인 항목` 목록을 **한 번에** 제시하고 일괄 승인을 받는다(이것이 그 경로의 "시작 전 1회" 승인). 승인 시 루프 시작. 특정 항목을 거부하면 그 항목은 제 지점에서 Halt로 되돌린다. **이 요청은 `## ⏸️ 사전 승인 확인` 헤더로 출력한다** — 정당한 개입 지점임을 나타내는 Strong 마커이며, 없으면 `require-evidence` 검사 4가 이 정지를 위반으로 판정할 수 있다(아래 금지 표현 예외 목록의 마커 규약).
3. Phase 0 이후 루프는 끝까지 진행하며, **`## 불가피한 Halt (위임 불가)`·규칙 10(파괴적·인증정보 필요 신규 외부 서비스)·규칙 11(돌발)·규칙 12(외부)** 에서만 멈춘다. 사전 승인된 항목(비파괴 의존성/구조/스키마)은 그 지점에서 멈추지 않는다.

> **이중 승인 방지**: 동일 세션에서 Step 10 승인 직후면 2의 "이미 받았으면" 분기로 공시만 하고, 새 세션 재개에서만 실제 재확인한다 — 어느 경로든 "시작 전 1회"가 보장된다.

### 🚨 자율 루프의 절대 규칙

**모든 task가 완료되거나 Halt Condition이 발동할 때까지 멈추지 않는다.**

- ❌ **task 사이에 사용자에게 묻지 않는다.**
- ❌ "다음 task로 진행할까요?", "T2를 시작할까요?" 같은 확인 요청 금지.
- ❌ MINOR follow-up이나 사소한 결정에 사용자 의견 묻지 않는다 (plan.md에 기록 후 계속 진행).
- ✅ **사용자 개입은 다음 경우에만**:
  0. **Phase 0 사전 승인 일괄 확인** — plan에 `## 사전 승인 항목`이 있고 이번 대화에 plan 승인이 없을 때(새 세션/재개), 루프 시작 전 1회 (위 Phase 0).
  1. Halt Condition 발동
  2. 모든 task 완료 (Phase F 통과 후 최종 보고)
  3. **리뷰 인프라 장애** — Sonnet reviewer(V-5/V-6)가 과부하(529) 재시도 소진 시의 선택 요청(재시도/자체 검증/대기 — 정본 `references/recovery.md` "Reviewer 호출 실패 대응" A. Halt가 아니라 선택 후 루프 계속). **이 요청은 `## ⏸️ 리뷰 인프라 선택 요청` 헤더로 출력한다**(Strong 마커 — 아래 예외 목록의 마커 규약). **도구 사용 불가**(subagent 호출이 물리적으로 불가능한 환경)도 같은 개입 지점이나 **선택 요청이 아니라 공시**다 — 같은 정본의 B 분기(체크리스트 대체 + 의무 3종)를 따르고 루프는 계속한다. **단 "세션 지침이 사용자 요청 없는 에이전트 호출을 금지"하는 상황은 개입 지점이 아니다** — plan 승인·스킬 발동이 곧 리뷰 호출 요청이므로 **묻지 않고 정상 호출**한다(정본 「Subagent 호출 규약」). 리뷰 지점마다 승인을 구하면 위 "task 사이에 묻지 않는다"가 무너져 루프가 멈춘다.

**사용자 승인은 plan-feature 단계에서 plan.md에 대해 단 1회만 받았다.** plan.md = 전체 작업의 위임장 — 이 위임에는 plan의 `## 사전 승인 항목 (일괄 승인 대상)`이 명시적으로 포함된다(Phase 0이 인정). 단 `## 불가피한 Halt (위임 불가)`(파괴적·외부/비가역·돌발)는 제외돼 그 지점에서 별도 승인받는다.

> **plan 승인 = 그 plan이 규정한 모든 절차의 수행 요청이다 (상위 지침 충돌 시 해석 규약).** 세션·상위 지침이 특정 도구나 행위를 *"사용자가 요청할 때만"*으로 제한하더라도, **plan에 명시돼 사용자가 승인한 절차**(리뷰 subagent 호출·checkpoint/task 완료 commit·`## 사전 승인 항목` 등록분)는 **그 요청이 이미 이뤄진 것**으로 보고 묻지 않고 수행한다. **도구별로 따로 규정하지 않는 이유**: subagent에만 예외를 두면 새 도구·새 제한이 등장할 때마다 같은 정지가 재발한다(실제로 이 규약은 "사용자 요청 없는 에이전트 호출 금지" 세션 지침에 루프가 첫 리뷰 지점에서 멈춘 뒤 만들어졌다). **적용 대상이 아닌 것**: `## 불가피한 Halt (위임 불가)`와 위임 경계 표의 '항상 Halt' 항목(파괴적 작업·외부/비가역 git·인증정보 필요 신규 외부 서비스) — 이들은 plan에 적혀 있어도 위임되지 않으므로 이 해석으로 열리지 않는다.

### 🧠 컨텍스트 관리 (장시간 작업 대비)

자율 루프가 길어지면 컨텍스트가 누적되어 후반 task의 품질이 저하될 수 있다. 다음을 지킨다:

1. **각 task는 독립적으로 처리.**
   - 이전 task에서 읽은 파일 내용·빌드 로그에 의존하지 말고, 필요한 정보는 **plan.md와 git에서 다시 확인**한다 — 둘 다 영구 저장되므로 이전 task 상세를 기억해 두려 애쓸 필요가 없다.
   - **plan이 작업을 "Phase 1~N", "단계 1~N", "Step 1~N" 등으로 나눴더라도(T<N>이 아닌 명칭) 동일하게 자율 처리한다.** 그 묶음 사이에서 멈춰 "Phase 2 진행할까요?"라고 묻지 않는다. plan의 "Phase N"은 pjc 내부의 Phase(P/I/V/D·F·G)와 무관한, 사용자 작업 묶음일 뿐이다. 모든 작업 단위를 마지막까지 자율로 진행한다.

2. **빌드/테스트 로그는 핵심만 유지.**
   - 전체 로그 원문을 컨텍스트에 길게 남기지 않는다.
   - "Build OK / Tests 12/12 passed" 같은 결과 + 실패 시 핵심 에러만.

3. **2개 task마다 Progress Log 갱신.**
   - plan.md의 `## Progress Log`에 완료 task 요약 1-2줄 기록.
   - 이후 task는 전체 대화 history 대신 이 요약 + git log 참조.

4. **컨텍스트 한계 근접 시 멈추지 않는다 — 압축을 통과해 계속 진행한다.** 현재 task를 Phase V/D까지 완료(중간 절단 금지 — 절반 수정 상태는 복구 불완전)하고 plan.md에 상태를 완전 기록(Progress Log + Next Steps + 다음 task 시작점)한 뒤, 사용자 보고 없이 계속 진행한다(auto-compact가 대화 히스토리만 요약, plan.md는 보존). **여기서 "상태를 완전 기록"은 plan.md에 *쓰는* 것이지 대화에 진행 요약을 *출력하는* 것이 아니다** — 체크포인트 요약을 말로 늘어놓고 turn을 끝내면 압축을 통과하기는커녕 거기서 루프가 멈춘다(금지 표현 ② 평서형 예고). 기록은 파일에, 진행은 같은 turn의 다음 도구 호출로. **압축 감지 시 첫 행동은 이 SKILL.md(implement-task) + plan.md + AGENTS.md 재읽기다** — 긴 루프에서 압축되면 이 지침 본문(V-5~V-8 절차·Halt 조건·재시도 카운터 규칙)이 요약으로 뭉개져 후반 task에서 규칙이 유실되므로, plan/AGENTS뿐 아니라 지침 자체를 다시 읽어 요약 기억만으로 이어가지 않는다(진행 중 Phase가 reference를 참조하면 그 reference 파일도 함께 재읽기 — 예: Phase F 중이면 `references/phase-f-detail.md`). 컨텍스트 한계 자체는 Halt 사유가 아니다(파괴적 작업·동일 실패 반복 등 다른 Halt 조건만 해당 — `references/halt-conditions.md`).

### 진행 흐름

```
Phase 0 → 사전 승인 일괄 확인 (하이브리드 — 루프 시작 전 1회; 사전 승인 항목 없으면 즉시 통과)
loop over plan.md tasks (시작 task부터 Tn까지 — 첫 실행은 T1, 재개면 지정/첫 미완료 task):
  Phase P → 변경 전략 확정, caller 사전 추적
  Phase I → 최소 변경으로 구현
  Phase V → Type별 fast-path (V-1~V-7, + V-9 디자인 정합·화면 이식 작업 시 — V-8이 최종 관문. V-9의 ⏳ 미확인 행은 F-8로 인계)
  Phase D → 완료 커밋(T<N>:) → (2 task마다 Progress Log) → 즉시 다음 task로

# 모든 task 완료 후
Phase F → 전체 plan 통합 검증 (조건부 진입)
Phase G → PRD 요구 재검증 (plan.md 상단에 `**PRD**:` 줄 있을 때만 — 갭 발견 시 task 추가 후 자율 재진입, 최대 2회)
F-8   → 시각 충실도·참조 정합 최종 관문 (plan에 `## 시각 요소 분해` 있을 때만 — ⏳ 미확인 또는 인벤토리 미달 잔존 시 완료 선언 보류)
→ 최종 보고 (첫 사용자 개입 지점)
```

## Phase P — Plan (작업 단위)

각 task에 대해 Phase I 진입 전 다음 확인.

### 재개 진입 (중간 체크포인트에서 이어하기)

"T<N>부터 계속" 같은 요청으로 시작하는 경우:
1. plan.md의 `## Progress Log`를 읽어 완료 task 파악
2. `git log`로 마지막 commit 상태 확인
3. plan.md의 task 체크박스로 미완료 task 식별
4. **첫 Phase P 진입 전 Phase 0(사전 승인 일괄 확인)을 1회 수행** — 새 세션 재개는 이번 대화에 plan 승인이 없으므로 재확인 분기(위 Phase 0). 그 뒤 지정된 task(또는 첫 미완료 task)부터 Phase P 시작
5. **경량 위키 참조 (절차 K, 세션당 1회)**: 첫 Phase P 진입 전, `pjc:llm-wiki` 절차 K(read-only)로 이번 plan과 관련된 feature/recipe/patterns를 참조한다 — 재개 세션은 plan-feature Step 1(위키 참조)을 거치지 않아 위키의 재사용 레시피·함정 지식이 빠지기 쉽다. vault가 있으면 index 기능별 인덱스·`30_knowledge/patterns/`에서 관련 항목만 식별해 Read하고(전체 정독 금지), vault가 없거나 관련 자료가 없으면 조용히 통과한다(K 준용 — vault·자료 없으면 조용히 통과, 무매칭 시 합성 금지). **단 "vault가 없다"는 판정은 절차 K 1의 `⚠ 판정 게이트`를 거친 확인 결과여야 한다** — 그 확인 없이 미설정으로 단정하고 통과하지 않는다(주입된 vault 상태 라인이 있으면 그것으로 갈음, **라인의 부재는 판정 근거가 아니다**). 건너뛴 경우의 기록도 K 1 형식을 따른다. **plan.md Investigation Log에 `위키 참조:` 기록이 있으면 그 페이지들을 우선 식별 대상으로 삼는다**(계획 세션이 이미 찾아둔 근거 — 인덱스 재검색 생략). 동일 세션에서 plan-feature를 막 거쳐온 경우(Step 1에서 이미 참조)는 중복이므로 생략한다.
6. 이전 task 상세는 Progress Log + git으로만 참조 (전체 history 불필요)

**세 신호(Progress Log·git log·체크박스)가 어긋나면 git log를 신뢰한다.** git log는 매 task commit(`T<N>: ...`)으로 항상 최신이고, Progress Log는 2 task마다, 체크박스는 갱신 누락 가능성이 있다. 또 지정 task의 선행(`Depends on`) task가 git log에 안 보이면 그 선행부터 다시 확인한 뒤 진행한다.

**task 내부 재개 판정 (checkpoint 커밋으로).** git log 마지막 커밋이 그 task의 완료 커밋(`T<N>: ...`)이 아니라 checkpoint면 task가 미완료 중단된 것이다 — `checkpoint: T<N> start`(빈 커밋)면 구현부터, **`checkpoint: T<N> pre-review`면 구현은 끝났고 V-5/V-6 리뷰가 미완료**인 것으로 보고 그 task의 Phase V부터 재개한다(구현을 다시 하지 않는다). **`checkpoint: T<N> review-fix`면 수정분까지 커밋됐고 재리뷰가 미확인** — 그 HEAD로 V-5/V-6 재리뷰부터 재개한다(직전에 재리뷰가 이미 통과했을 가능성은 있으나 중복 리뷰를 감수한다 — 무회귀 우선, pre-review 재개와 동일 철학). **`checkpoint: T<N> partial`이면 구현 중 중단** — Phase I를 이어 진행한다. 제목이 checkpoint 계열도 완료 커밋도 아니면(수동 개입 등) `checkpoint: T<N> pre-review`의 존재 여부로 폴백한다(있으면 Phase V부터, 없으면 구현부터). Phase Ledger 마커는 Phase F/G 위치만 다루므로, task 내부의 이 판정은 마지막 checkpoint 커밋 종류로 한다.

**Phase Ledger로 진행 위치 판정 (Phase F/G 중복 실행 방지).** plan.md에 `## Phase Ledger` 줄이 있으면 그것으로 **어느 Phase까지 왔는지**(예: `전 task 완료` / `Phase F 통과 (HEAD <sha>)` / `Phase G 재루프 N회차`)를 판정한다. **이미 Phase F를 통과한 상태로 재개하면**(예: Phase G가 추가한 task를 처리하다 압축된 경우) 남은 task만 P→I→V→D로 처리하고 **Phase F(F-7 Opus 포함)를 재실행하지 않는다** — Phase G 재루프는 완료 task 후 G-1 재대조만 하지 Phase F 전체를 다시 돌지 않기 때문이다(phase-g-detail G-2). 마커가 **없는** 기존 plan은 안전하게 "처음부터(전 미완료 task + Phase F/G)"로 폴백한다(무회귀). 마커가 git log·체크박스와 어긋나면 task 완료 판정은 git log를 신뢰하되, **Phase 진행 위치**는 마커 + Progress Log로 판정한다.

**재개도 완전 자율 루프다.** "T6부터 계속"은 "T6 하나만"이 아니라 **"T6부터 마지막 task까지 + Phase F/G까지"를 의미한다.** 첫 세션의 T1 시작과 재개 세션의 T6 시작은 시작점만 다를 뿐 동일한 루프이며, 금지 표현 규칙("T7 진행할까요?" 금지)도 동일하게 적용된다. task 사이에 멈춰 사용자에게 묻는 것은 재개 세션에서도 위반이다. 단일 task만 실행하는 경우는 사용자가 "T6만" 처럼 명시적으로 한정했을 때뿐이다.

**분할 plan 호출**: plan이 2개로 분할된 경우(plan-feature "긴 plan 분할" — `docs/plans/...-part1.md`/`-part2.md`), 각 part는 **plan 경로를 명시해 호출**한다(예: "`docs/plans/<날짜>-<slug>-part2.md` 구현"). `docs/plans` 복수 파일은 자동 plan 해소가 모호하므로 경로를 지정한다. 각 분할 plan은 자기 안에서 T1부터 시작하며(분할은 각 plan을 독립 실행), part1 완료 최종 보고가 part2 경로를 안내한다. **plan 상단에 `## 이전 part 핸드오프` 섹션이 있으면 첫 task 전에 먼저 읽는다** — 이전 part 세션이 남긴 함정·기각된 접근·검증 지름길(final-report-template.md의 분할 안내가 생성)로, `/clear`로 유실된 암묵지를 회수한다.

### P-1. plan.md 해당 task 정독
- task의 Acceptance, Design(있으면 — 구현이 따를 구조 명세), Files, Edge Cases, Halt Forecast, Type 모두 확인.

### P-2. Files 목록 직접 Read
- task의 Files에 있는 모든 파일을 Read 도구로 직접 열어 현재 상태 확인. 파일들은 서로 독립이므로 **한 턴에 병렬 Read**한다(읽는 내용은 동일, 턴 수만 절약 — 순차 Read는 낭비).
- 가정 금지. 파일 내용은 항상 직접 읽어 검증.

### P-3. 심볼 사용처 전수 추적
- 변경 대상 심볼에 대해 `grep -rn "\b<symbol>\b"` 실행. 심볼이 여럿이면 `grep -rnE "\b(sym1|sym2|...)\b"` **1회 배치 실행** 후 결과를 심볼별로 재귀속한다(결과 동일, 호출 수만 절약 — post-write-checks hook의 배치 grep과 동일 기법).
- 결과를 모두 Read로 확인.
- **읽기 비례 원칙 (hit 과다 시).** hit가 **30건을 초과**하면(배치 실행 시 재귀속 후 **심볼별 hit** 기준) 전건 전체 Read 대신, 먼저 `grep -rn -C <n>`(문맥 포함)으로 각 hit의 **영향 여부를 1차 판정**한다 — 영향이 의심되는 파일만 전체 Read로 정밀 확인한다. **판정 근거를 남긴다**(예: "hit 47건 중 12건이 시그니처 호출부 → 전체 Read, 나머지 35건은 문자열 매칭/주석 → 문맥으로 영향 없음 확인"). 단순 grep 카운트만으로 끝내는 것은 금지(영향 판정이 반드시 있어야 함). **위임 금지 가드는 유지** — 이 축약은 메인이 직접 수행하며 explorer 등에 넘기지 않는다(아래 가드). hit가 30건 이하면 종전대로 전건 Read.
- task의 Files 목록과 대조 → 누락된 caller 발견 시 **자율 처리가 기본**: plan.md의 해당 task Files에 누락 caller를 추가하고 함께 수정한다 (멈추지 않음). caller 갱신은 절대 규칙 3(Cross-File Consistency)의 정상 작업이다.
  - **예외 (Halt → 재승인)**: ① 누락 caller가 여러 모듈로 연쇄(대략 5개 파일 이상)해 plan 범위를 크게 벗어나거나, ② plan에 없던 **공개(public) 멤버 시그니처 변경**이 새로 필요해지거나(공개 API 계약 변경은 plan 승인 범위 밖 — 글로벌 "공개 멤버 시그니처 변경 승인 필요"와 정합), ③ 파괴적 변경·새 의존성을 유발하는 경우에는 Halt해 재승인받는다. plan이 이미 의도한 변경의 **단순 caller 갱신(시그니처 동일·내부 호출부 수정)**은 Cross-File Consistency의 정상 작업이라 Halt 아님.

### P-4. 외부 식별자 확인 (환각 방지)
- 호출할 외부 API/메서드/타입의 정의 위치를 직접 확인.
- 못 찾으면 호출 코드 작성 금지. plan에 "확인 필요" 등록.

### P-5. 변경 전략 명시
- 어떤 순서로 변경할지 한 줄로 작성 (자기 점검용).

> **위임 금지 가드 (품질-임계 읽기).** P-2(Files 정독)·P-3(caller 전수 추적)·V-7(caller 재검증)은 `explorer` 등 발췌-읽기 subagent에 **위임하지 않는다**. explorer는 haiku로 "필요한 파일만 Read(전체 읽기 지양)"하므로 전체 판단·cross-file 검증에 부적합 — 이 단계는 메인이 직접 Read한다(hit가 과다하면 P-3의 "읽기 비례 원칙"으로 축약하되, 그 축약도 메인이 직접 수행하고 explorer에 넘기지 않는다 — 위임 금지의 핵심은 "누가 판단하나"이지 "전건을 다 읽나"가 아니다). (병렬 위임은 plan 단계의 위치·패턴 찾기에서만; 구현 단계의 caller 검증은 메인 직접.)

> **위임 상한 (과위임 방지).** 위임은 공짜가 아니다 — subagent 하나마다 컨텍스트 왕복과 요약 손실이 생기고, 메인은 그 요약만 보게 된다. 아래 셋을 넘지 않는다.
> - **병렬 상한**: 한 turn에 띄우는 subagent는 **서로 독립이고 결과를 각각 쓸 것**만이다. 같은 질문을 여러 개에 나눠 던져 "더 확실히" 하려는 중복 위임은 답을 확인해 주는 게 아니라 서로 다른 요약을 만들어 판단을 흐린다.
> - **소작업 다중 위임 금지**: 파일 한둘을 읽거나 grep 한 번이면 끝나는 일에는 subagent를 쓰지 않는다. 직접 하는 편이 빠르고 정확하다.
> - **검증 목적 위임 금지**: 이 스킬이 규정한 리뷰(V-5·V-6·F-7)를 **제외한** "내가 한 게 맞는지 봐 달라"식 위임은 하지 않는다. 검증은 메인이 명령을 실제로 실행하고 diff를 대조해서 한다 — 남에게 물어 얻은 안심은 V-8이 요구하는 근거가 아니다.

## Phase I — Implement

- 시작 시 **checkpoint** 생성 (빈 커밋 — 구현 시작점 표시, recovery reset 대상):
  ```bash
  git status                            # clean 확인
  git checkout -b task/<id>-<slug>      # 작업 브랜치 (이미 있으면 스킵)
  git commit --allow-empty -m "checkpoint: T<N> start"
  ```
  **브랜치 규약: plan당 1개.** 작업 브랜치는 **첫 task(T1)의 Phase I에서 한 번 생성**하고, 이후 모든 task는 **같은 브랜치에 이어 커밋**한다(task마다 새 브랜치를 파지 않는다). 재개 세션에서 브랜치가 이미 있으면 `checkout -b`는 스킵하고 그 브랜치에서 계속한다. 브랜치명 `<slug>`는 plan 기준(첫 task 또는 plan slug)으로 정한다.
- 기존 코딩 컨벤션 따름 (AGENTS.md > 주변 코드 모방)
- 최소 변경 원칙
- 변경 후 즉시 빌드. 오류는 다음 변경 전에 해결.
- 구현이 끝나면 **Phase V 진입 직전에 pre-review 커밋을 만든다**(아래 Phase V 서두) — 리뷰어가 볼 diff를 커밋으로 고정하기 위함. Type A(리뷰 생략)는 이 커밋이 불필요하며 Phase D에서 바로 최종 커밋한다.

### Sub-skill 호출 (해당 시)

| Task 산출물 | 호출 sub-skill | 조건 |
|---|---|---|
| WinUI 3/WPF/MAUI ViewModel + View | `pjc:add-viewmodel` | AGENTS.md에 WinUI/CommunityToolkit.Mvvm 명시 시 |
| Domain Service / Application Service | `pjc:add-domain-service` | AGENTS.md에 DDD/Clean 아키텍처 명시 시 |
| 그 외 | (sub-skill 없음, 직접 구현) | |

**Android의 Jetpack ViewModel은 `add-viewmodel` 비대상** — 직접 구현 또는 별도 skill 필요.

## Phase V — Validate

**V 진입 직전 — pre-review 커밋 (리뷰 대상 diff 고정).** Type B/C/D(리뷰가 있는 Type)는 Phase V 리뷰(V-5/V-6) 전에 구현 변경을 커밋한다:
```bash
git add -A
git commit -m "checkpoint: T<N> pre-review"
```
이 커밋의 SHA를 V-5/V-6 리뷰어에게 **HEAD_SHA로 전달**한다(왜 커밋을 하나 더 만드는지의 근거는 `references/rationale.md`). BASE_SHA는 `checkpoint: T<N> start`(또는 직전 task 최종 커밋). **pre-review 커밋 이후의 모든 수정분(리뷰 지적 수정·V-1~V-3 실패 수정)은 Phase I로 돌아가 고친 뒤 `git commit -m "checkpoint: T<N> review-fix"`로 이어 커밋**(amend 아님 — 추가 커밋, 리뷰 스냅숏 이력 보존)하고, 그 새 HEAD로 재리뷰한다. Phase D의 최종 커밋이 pre-review(+review-fix) 커밋을 task 완료 커밋으로 정리한다(판정·명령은 Phase D ③). Type A는 이 커밋을 건너뛰고 Phase D에서 바로 최종 커밋한다.

순서대로 실행. 실패 시 Phase I로 복귀해 수정 후 재시도한다 — 반복 한도는 `references/recovery.md`의 카운터(빌드/테스트 5회 연속 실패·리뷰 수정 사이클 5회·복구 2회)를 따른다(카운터 없이 무한 반복하지 않으며, "1회만"이라는 뜻도 아니다). **V-1~V-3은 가능하면 한 도구 호출로 체이닝한다**(`<build> && <test> && <lint>` — 앞 단계 실패 시 뒤가 실행되지 않는 것이 "실패 시 Phase I 복귀"와 일치. 해당 Type에 없는 단계는 생략하고, V-2를 조건부 축소하면 그 필터 명령을 체인에 넣는다).

> **검증 스크립트 Windows 보안 (PowerShell).** 임시 검증 스크립트는 자격증명 하드코딩(→환경변수 `$env:TEST_PW`)·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass`를 피한다 — 이 위험 신호가 한 스크립트에 모이면 Windows Defender가 공격 도구로 오인해 격리(삭제)할 수 있다(빌드 검증과 로그인/런타임 테스트는 분리). 격리 시 사용자에게 Defender 예외 추가를 **안내만** 한다(설정 변경은 사용자 직접). **상세: `references/authoring-detail.md`.**

### 🚀 Fast-Path — Task Type에 따른 단계 선택

| Type | 실행 단계 | 생략 단계 |
|---|---|---|
| **A** (Doc/Config) | V-8만 (코드 빌드에 영향 주는 설정이면 V-1 추가) | V-1(대개)~V-7 |
| **B** (Trivial Code) | V-1 + V-2 + V-5(**prefilter Haiku**) + V-7 + V-8 (prefilter PASS 시 V-7은 정방향·역방향 각 grep 1회로 축소) | V-3, V-6 |
| **C** (Normal Code) | V-1 ~ V-8 **전체** (V-5는 compliance Sonnet) | 생략 없음 |
| **D** (Complex/Cross-cutting) | V-1 ~ V-8 **전체** (V-5는 compliance Sonnet) | 생략 없음 |

> Type C/D의 **실행 단계는 동일**하다(V-6 포함). C/D의 차이는 실행이 아니라 **계획 단계**(Decision 카테고리 12개 vs 5-6개·Edge 카테고리·Design 필드 의무)에 있다.
>
> **리뷰 실행 여부는 이 표의 Type이 결정한다 — "이 정도면 리뷰가 필요한가"를 구현 중에 판단하는 재량이 아니다.** Type C/D면 spec·quality 두 리뷰가 **항상** 돌고 opt-out 경로가 없으며, 생략은 "Reviewer 호출 실패 대응"의 세 fallback(과부하·도구 불가·거절)에서만 일어나고 그때도 반드시 명시한다. plan에 Type이 없으면 메인이 diff 규모로 판정하되 **애매하면 D**다(무거운 쪽).

**Task Type 판정**: plan이 Type을 명시하면 그것을 따른다. **plan에 Type이 없으면 메인이 diff 예상 규모로 B/C/D를 1줄로 판정해 plan.md 해당 task에 기입**한다(예: "단일 파일·caller 없음 → B", "다중 파일·시그니처 변경 → D"). 규모를 가늠하기 어렵거나 판정이 애매하면 **D로 간주**(안전 우선 — 무거운 쪽). **단 순수 값 치환은 예외 — 애매해도 B**: 색상·치수·간격·폰트 등 리터럴/디자인 토큰 값만 바꾸고 로직·조건·구조·시그니처 변화가 0인 task는 **파일·개수와 무관하게 Type B**로 기입한다(값만 바뀌어 위험이 낮고 화면에서 즉시 검출 — plan-feature Trivial Bypass 순수 값 치환 예외와 동일 기준). '애매하면 D' 상향은 로직·구조 변화 가능성이 있을 때의 안전 규칙이라 순수 값 치환에는 적용하지 않는다. 값 변경이 조건·레이아웃 구조·계산식 도입을 동반하면 순수 치환이 아니므로 이 예외 밖이다.
**V-4(PostToolUse hook)는 자동 실행** — 모든 Type에서 작동 (UTF-8 + impact-warn).
**V-9(시각 충실도·참조 정합)는 Type과 무관하게 조건부** — plan에 `## 시각 요소 분해` 섹션(Step 2.5 산출물)이 있는 디자인 정합·화면 이식 작업일 때만 수행 (없으면 모든 Type에서 생략).
**V-5·V-6 병렬** — Type C/D에서 V-5(compliance)·V-6(quality)는 동일 BASE/HEAD에 병렬 호출하고, 둘 다 OK일 때만 진행한다 (상세는 V-5). 여기서 병렬은 **동기 호출**(`run_in_background: false`) 2개를 한 메시지에 함께 보내는 것이며, 결과 수신 전에 다음 단계로 가지 않는다.

#### Type A 빌드 판단
- 순수 문서·주석·README·`.gitignore` 등 **빌드에 영향 없는 파일** → V-1도 skip, V-8만.
- `.csproj`/`build.gradle`/`package.json` 등 **빌드 구성에 영향 주는 설정** → V-1 빌드 실행.
- **동작 변경 Config 가드**: DI 배선·기능 플래그 기본값·라우팅 등 **런타임 동작을 바꾸는 설정**이 Type A로 분류돼 있으면 오분류다(plan-feature Step 5 Type A 가드). 순수 문서·비동작 설정만 Type A로 처리하고, diff가 런타임 동작을 바꾸면 최소 Type B로 격상해 V-5(prefilter)를 태운다 — Type A는 V-5/V-6이 없어 동작 변경이 무검증 통과되기 때문이다.

#### Type B prefilter PASS 시 V-7 축소
- spec-prefilter(Haiku)가 PASS → 변경 심볼이 trivial이므로 V-7을 **정방향(변경 심볼)·역방향(삭제된 호출부 심볼) 각 grep 1회**로 축소 (전체 재추적 불필요).
- prefilter가 ESCALATE → **해당 task를 Type C로 격상** (격상 절차·이유는 V-5 Type B 절 정본 — V-3 + V-5·V-6 병렬 + V-7 전체).
- **Type 오분류 피드백 (경미)**: spec-prefilter가 Type B task에서 ESCALATE를 반복(여러 task에 걸쳐 잦게)하면 plan의 Type 분류가 실제보다 가볍다는 신호다 — 해당 task는 C 격상으로 진행하되(위 격상 규정) plan.md `## Deferred / Follow-up`에 "Type 분류 재검토 (prefilter ESCALATE 잦음)"를 1줄 남긴다(다음 계획 단계 강화용, 루프는 멈추지 않음).

### V-1. 빌드
- AGENTS.md의 build 명령 실행. exit 0 확인. 오류 시 Phase I로 복귀해 수정 후 재시도(한도: recovery.md 빌드 5회 연속 실패 카운터).
- **AGENTS.md 없거나 build 명령 미정의** → 표식 파일로 자동 추론 — **fallback 표(csproj→`dotnet build` 등 6종 + 그 외 Halt 규칙)는 `references/authoring-detail.md` "빌드/테스트 fallback 표" 정본** (저빈도 경로 — AGENTS.md에 명령이 있으면 이 표를 볼 일이 없다).

### V-2. 테스트
- AGENTS.md의 test 명령 실행. 통과 케이스 수 기록.
- **조건부 축소 (AGENTS.md 근거가 있을 때만)**: AGENTS.md에 **영향 범위 필터 명령**(변경 모듈만 도는 test 명령) 또는 **검증 매핑 표**(변경 파일 패턴 → 필수 검증)가 있으면, 이 task에서는 **변경 영향 모듈만** 테스트한다(매핑 표가 있으면 그 표로 선택 — 여러 패턴에 걸치면 해당 행 전부, 합집합). 전체 스위트는 **Phase F-2에서 1회 보장**되므로 매 task 전량 실행은 중복이다. **축소한 경우 커밋 메시지 `Tests:` 줄에 범위를 명시**한다(예: `Tests: 12/12 passed (module X만 — 전체는 F-2)`). **필터 명령도 검증 매핑 표도 없으면 스위트 크기와 무관하게 전체를 돈다**(기존 동작 — 축소는 AGENTS.md에 근거가 있을 때만 하며, 스위트가 크다는 이유로 임의 축소하지 않는다. 소요 시간은 실행해봐야 알 수 있어 판정 기준이 될 수 없다).
- **AGENTS.md 없거나 test 명령 미정의** → 표식 파일 fallback — **표(`dotnet test` 등 6종·package.json test script 없음은 skip·그 외 Halt)는 `references/authoring-detail.md` "빌드/테스트 fallback 표" 정본.**

### V-3. 린트/정적 분석
- 프로젝트 표준 도구 실행. 신규 경고 0 확인.

### V-4. 자동 검증 hook
- PostToolUse hook 자동 실행 (`check-utf8-and-lines`, `impact-warn`).
- impact-warn 경고 발생 시: caller 파일을 Read로 즉시 열어 영향 검증.
  - 영향 받으면 같은 task에서 함께 수정.
  - 영향 없으면 commit 메시지에 "영향 없음 확인" 명시.

### Reviewer 호출 실패 대응 (과부하·도구 불가·거절) — 모든 subagent 호출 공통

> 이 절은 **정상 경로(동기 호출 규약)**와 **실패 대응(A/B/C)**을 함께 담는다 — 바로 아래 첫 문단이 정상 경로이고, 실패 분기는 `A.`부터다.

**호출 규약(정상 경로) — 전부 동기.** 이 하니스의 subagent는 모두 **동기 호출**(`run_in_background: false`)로 부르고 **결과를 받아 판정한 뒤에만** 다음 단계로 간다. "한 turn 동시 호출"은 동기 호출을 한 메시지에 함께 보내는 것이지 백그라운드 실행이 아니다(호출 도구 기본값이 백그라운드라 명시하지 않으면 결과 없이 루프가 전진한다). 정본: `references/recovery.md` 「Subagent 호출 규약」.

**A. 과부하(HTTP 529)** — reviewer 호출이 529로 실패하면(V-5/V-6·F-7·plan-feature plan-reviewer 등 모든 reviewer 공통): 짧게 재시도(최대 2회) → 계속 529면 등급별 분기 — **Opus**(`plan-reviewer`·`plan-completion-reviewer`)는 Sonnet 대체 가능(단 "검증 깊이 낮을 수 있음" 명시 + ⚠️ 표시 + Next Steps 기록), **Sonnet**(`spec-compliance-reviewer`·`code-quality-reviewer`)은 **Haiku 대체 금지**(사용자 선택: 재시도/자체검증/대기), **Haiku**(`spec-prefilter`·`explorer`)는 재시도만 후 상위 흐름.

**B. 도구 사용 불가** — subagent 호출이 **물리적으로 불가**할 때(도구 미제공·즉시 거부·환경상 실행 불가). 재시도해도 환경은 바뀌지 않으므로 2회까지만 시도하고 **대체 절차**로 간다: 메인이 그 reviewer의 정의 파일(`agents/<이름>.md`)을 Read해 **판정 항목을 체크리스트로 직접 대조**하고 항목별 결과를 남긴다 + **의무 3종**(사용자 보고 · `## Progress Log` 기록 · 최종 보고에 "검증 깊이 저하 — reviewer 미실행" 명시). **"리뷰가 과하다"는 판단은 발동 조건이 아니다** — 애매하면 발동하지 않고 Halt한다. F-7을 이 분기로 대체하면 Phase G가 active Must FR 전체를 보완 재대조한다(`phase-g-detail.md` G-1 예외 ②와 동일). **세션 정책상 "사용자 요청 없는 에이전트 호출 금지"는 이 분기가 아니다** — 스킬 발동이 곧 그 요청이므로 묻지도 강등하지도 않고 정상 호출한다(정본 「Subagent 호출 규약」).

**C. 안전 분류기 거절(refusal)** — HTTP 오류 없이 **정상 응답으로 검토를 거부**한 경우. 같은 입력엔 같은 판단이 돌아오므로 **재시도는 무의미**하다: 범위를 좁히거나 테스트 픽스처임을 명시해 **1회 재의뢰**하고, 그래도 거절되면 B의 대체 절차를 쓰되 보고 사유를 **"거절 — 미검토 범위: <파일>"**로 적는다. **거절은 통과가 아니다**(리뷰어가 문제 삼지 않은 게 아니라 보지 않은 것).

**대체·검증 생략은 항상 명시(투명성) — 조용히 대체 금지.** 상세 매트릭스: `references/recovery.md`.

### V-5. Spec Compliance Review (subagent 필수)

> **subagent 호출 자체가 불가한 환경이면** 위 "Reviewer 호출 실패 대응" **B 분기**(체크리스트 대체 + 의무 3종)를 따른다 — 이 헤더에 예외를 적어두는 이유는, 도구가 막힌 세션에서 루프가 **첫 리뷰 지점인 여기서** 멈추기 때문이다(뒤쪽 V-6에만 적혀 있으면 탈출구가 보이지 않는다).
> **reviewer가 HTTP 오류 없이 정상 응답으로 검토를 거절하면** 같은 절의 **C 분기**(안전 분류기 거절)를 따른다 — 재시도가 아니라 **범위를 좁혀 1회 재의뢰**하고, 그래도 거절되면 B의 대체 절차를 쓰되 사유를 "거절 — 미검토 범위"로 적는다. **거절을 통과로 해석하지 않는다.**

Task Type에 따라 다른 흐름:

**Type B**: `spec-prefilter` (Haiku) 먼저 호출 (BASE_SHA·HEAD_SHA는 Type C/D와 동일 — HEAD_SHA = Phase V 서두의 **pre-review 커밋** SHA. prefilter도 그 diff를 본다. 나머지 전달물은 spec-prefilter 입력 계약대로 — acceptance 1줄·task Files 목록·AGENTS.md 위치). **동기 호출**(`run_in_background: false`) — PASS/ESCALATE 판정을 받아야 아래 분기가 정해지므로 결과 수신 전 진행 금지(ESCALATE 격상 경로의 재호출도 같다).
- PASS → V-5 완료, **V-7(축소)·V-8 진행** (Type B는 V-6 생략 — Sonnet 호출 안 함. Fast-Path 표와 일치).
- ESCALATE → **해당 task를 Type C로 격상**한다: plan.md의 그 task Type 라인을 `C (B→격상: prefilter ESCALATE)`로 갱신하고(기존 plan 부분 갱신 — 격상 흔적이 재개 세션의 C 처리 신호가 된다), 이후를 **Type C 기준으로 수행** — V-5(compliance)·V-6(quality)를 병렬 호출하고 V-3·V-7도 전체 수행한다(이미 통과한 V-1·V-2는 재실행 불필요. 왜 사유 불문 전건 격상인지는 `references/rationale.md`). 결과 처리는 아래 Type C/D와 동일.

**Type C/D**: `spec-compliance-reviewer` (Sonnet) 호출.
- 전달: task ID, plan.md 해당 섹션, BASE_SHA, HEAD_SHA(= **pre-review 커밋** SHA — Phase V 서두에서 만든 것, 빈 checkpoint가 아님), AGENTS.md 경로(V-6 병렬의 quality reviewer 컨벤션 대조 입력 — code-quality-reviewer 입력 계약), **그리고 plan에 `## 시각 요소 분해` 섹션이 있으면 그 섹션**(spec-compliance-reviewer 항목 I 입력 — 리뷰어가 이 task 귀속 행을 diff와 대조한다. **섹션이 없으면 전달을 생략**하며 항목 I도 skip되어 기존 동작과 동일하다). **그 섹션에 `### 참조 정합 인벤토리` 하위 표가 있으면 서두의 `**원본**:` 줄에서 원본 절대 경로를 읽어 함께 전달한다**(항목 I-2 입력 — 리뷰어가 원본 파일을 직접 Read해 문구·컨트롤 타입을 대조한다. 경로를 안 주면 리뷰어는 표에 적힌 값만 믿게 되는데, **표 자체가 추측으로 채워졌을 가능성이 바로 검증 대상**이라 그 리뷰는 의미가 없다).
- **V-5(compliance)와 V-6(quality)를 동일 BASE_SHA·HEAD_SHA에 병렬(한 turn 동시) 호출한다** — Type C/D 공통(V-6 항상 수행). 두 리뷰는 독립 read-only라 동시 실행해도 충돌이 없다. **여기서 "병렬"은 **동기 호출**(`run_in_background: false`) 2개를 한 메시지에 함께 보내는 것이다** — 백그라운드로 띄워 두고 결과 없이 진행하면 리뷰 게이트가 통째로 무력화된다(아래 재실행·재리뷰도 동일). 정본: `references/recovery.md` 「Subagent 호출 규약」.
- **둘 중 하나라도 BLOCKER/MAJOR → Phase I로 복귀, 수정 후 (수행된) 리뷰를 다시 병렬 재실행.** 둘 다 OK/MINOR일 때만 다음 단계 (MINOR → follow-up 등록). **follow-up 등록은 최종 통과 run 기준** — 중간 run에서 본 MINOR는 최종 run에서 재평가하며(수정으로 위치가 바뀔 수 있음), 중간 결과로 중복 등록하지 않는다. **quality 리뷰의 SUGGEST(설계 소견 — code-quality-reviewer 항목 J)도 동일하게 최종 run 기준**으로 plan.md `## Deferred / Follow-up`에 `[SUGGEST]` 접두 1줄씩 등록한다(동일 파일·동일 요지는 1건으로 디듑) — verdict 무영향이므로 수정·재리뷰 없이 루프를 계속한다.
- 두 리뷰는 항상 **최종 diff에 전체 수행** — 어느 것도 생략·약화하지 않는다 (단 "Reviewer 호출 실패 대응"의 **A(과부하 529)·B(도구 불가)·C(거절)** 세 fallback은 예외이며, 어느 쪽이든 약화 사실을 반드시 명시한다). 실패 경로에서 V-6이 재실행되는 토큰 비용은 품질 우선으로 감수한다.
- **529 과부하는 각 reviewer에 독립 적용** — 병렬 중 한쪽만 529면 그 reviewer만 "Reviewer 호출 실패 대응" A 분기를 따른다 (다른 쪽 결과 유지).
- **reviewer가 "incomplete"(turn 예산 소진 등으로 acceptance 일부만 검토)로 응답하면 통과(OK)로 보지 않는다** — 해소 경로는 리뷰 종류로 갈린다: **V-5(spec) incomplete**는 미검토 항목을 메인이 diff에서 직접 대조(해당 acceptance가 충족되는 위치 지목 — 기계적 대조라 허용)하거나 reviewer를 재호출한다. **V-6(quality) incomplete는 reviewer 재호출로만** 해소한다(부족분을 명시해 재의뢰, 연속 incomplete면 파일 단위로 범위를 좁혀 재의뢰 — 자기 코드의 품질을 메인이 스스로 판정하는 것은 V-6 "자체 검토 금지"와 모순이라 불허). **단 재호출이 기술적으로 불가한 환경이면**(도구 차단 등) "Reviewer 호출 실패 대응" **B 분기**로 해소한다 — 그 경우에도 임의 자체 판정이 아니라 **정의 파일의 판정 항목을 체크리스트로 대조 + 의무 3종 공시**를 거친다(재호출도 대체도 불가능하면 해소 경로가 0이 되어 루프가 완주할 수 없기 때문이며, 이 예외는 "재호출 가능한데 하기 싫을 때"로 확대되지 않는다). incomplete를 조용히 OK 처리하고 다음 task로 넘어가는 것은 금지. (Phase G의 incomplete 처리 원칙을 per-task V-5/V-6에도 동일 적용 — Type B ESCALATE(→C 격상)의 병렬 리뷰 호출 포함 모든 reviewer 응답에 적용.)
- **지적 이의 절차 (사실 오류 반증 — 무조건 수용 방지).** 리뷰 지적을 코드 수정으로 반영하는 것이 기본이지만, 메인이 그 지적을 **사실 오류로 판단하고 파일:라인 인용으로 반증할 수 있으면**(예: 리뷰어가 "caller 누락"이라 했으나 그 caller가 리플렉션·다른 파일에서 실제로 갱신됨을 grep으로 제시), 코드를 바꾸지 않고 **반증 근거를 첨부해 같은 리뷰어를 재호출**한다. **재호출에도 리뷰어가 같은 지적을 유지하면** 그 지적을 수용해 수정하거나(반증이 틀렸을 수 있음), 반증이 확실하면 Halt해 사용자 판단을 받는다 — 이 종결 규칙이 반박의 끝을 보장한다. **이 반증 재호출은 재시도 한계의 "수정 사이클"에 포함**되므로 상한은 그 카운터(수정 사이클 누적 5회·동일 지적 3회 연속)가 강제한다(별도 횟수 캡을 두지 않는 이유 — 상한이 이미 두 겹이다). 이 절차는 antipatterns.md "Review 묵살 금지"의 예외다 — **묵살(근거 없이 무시)이 아니라 근거 있는 반증**이며, 반증이 기각되면 수용한다. 반증 없이 "내 판단엔 틀렸다"로 넘어가는 것은 여전히 금지.

### V-6. Code Quality Review (subagent, Type C/D 항상) — V-5와 병렬 수행
- `code-quality-reviewer` subagent 호출 (위 V-5에서 **병렬로 함께 호출**). 자체 검토 금지 — **예외는 호출 자체가 불가한 환경뿐이며 그때는 "Reviewer 호출 실패 대응" B 분기**(체크리스트 대체 + 의무 3종). **기존 plan의 Type 라인에 남은 `(quality-review)` 플래그는 no-op**(종전 opt-in 표기 — 이미 기본이라 중복 명시일 뿐, 오류 아님). 호출은 V-5와 함께 **동기 호출**(`run_in_background: false`).
- 검토 기준: DDD, 환각, 한글 주석, 파일 응집도(1500은 분리 검토 신호), UTF-8, 보안, 동시성, 사용자 노출 UI 문구 친화성(항목 I — diff에 화면 표시 문구가 있을 때).
- 결과 처리: V-5와 통합 — 둘 중 하나라도 BLOCKER/MAJOR면 수정 후 둘 다 재실행, 둘 다 OK일 때만 진행.

### V-7. Caller Re-verification

**정방향 검사 (caller 갱신 확인)** — 변경된 모든 public/internal 심볼에 대해:
- `grep -rn "\b<symbol>\b"` 실행. 심볼이 여럿이면 P-3와 동일하게 `grep -rnE "\b(sym1|sym2|...)\b"` 1회 배치 후 심볼별 재귀속.
- hit 위치가 모두 diff에 포함되어 있거나, 변경 영향 없음이 명백한가.
- **hit 과다(30건 초과) 시 P-3의 "읽기 비례 원칙"을 동일 적용** — 문맥 grep으로 1차 판정 후 영향 의심분만 전체 Read(판정 근거 로그). 위임 금지 가드는 유지.
- 누락 발견 → Phase I 복귀.

빌드가 통과해도 잡는 cross-file 마지막 관문.

**역방향 검사 (고아 코드 탐지)** — 정방향이 "바꾼 심볼의 caller가 함께 갱신됐나"라면, 이 검사는 그 거울상 — "이번 수정으로 마지막 호출부가 사라져 **고아(orphan)가 된 코드**가 없나"를 본다 (빌드는 미사용 정의를 잡지 못한다):
- diff에서 **삭제·변경된 줄이 호출하던 심볼**(지운 호출부의 대상 함수/메서드/import) 목록을 도출한다.
- 각 심볼에 `grep -rn "\b<symbol>\b"` 실행(여럿이면 정방향과 동일 배치) — **잔여 참조가 0인데 정의가 남아 있으면 고아 후보**.
- 처리 강도: 같은 diff에서 호출부가 사라진 **미사용 import·같은 파일의 private 헬퍼**는 위생 규칙 6의 정상 정리로 이 task에서 함께 제거한다. **public/internal 심볼·다른 파일의 정의·대량(대략 5개 파일 이상)**은 자동 삭제하지 않는다 — 완료 보고에 "고아 코드 후보"로 보고해 사용자가 결정한다("plan에 없는 대량 삭제" Halt 규칙과 정합). **남기기로 판정한 고아 후보는 그 정의 옆에 남긴 이유를 1줄 주석으로 적는다**(규칙 7-3 ②) — 근거 없이 남은 미사용 심볼은 다음 세션이 "하위호환용 의도인가, 빼먹은 미완성인가"를 코드로 판정할 수 없어, **지우지도 쓰지도 못한 채 누적**된다.
- 주의: 잔여 참조 0은 **후보이지 확정이 아니다** — 리플렉션·DI 컨테이너·문자열 기반 참조는 grep에 잡히지 않는다. 제거 전 그 가능성을 확인하고, 불확실하면 제거 대신 보고로 돌린다.

**Type B + prefilter PASS 시 축소**: 변경 심볼이 trivial하므로 정방향은 변경한 심볼 grep 1회, 역방향은 삭제된 호출부 심볼 grep 1회만 수행 (전체 재추적 생략). impact-warn hook(V-4)이 이미 자동 검출했으므로 중복을 줄인다.

### V-8. Self-Honesty Check

Phase D 진입 직전 자기 정직성 검증. 모두 "예"여야 진행 가능:

- [ ] (V-1 수행 task) 빌드 명령을 실제로 실행했고 exit 0을 봤는가?
- [ ] (V-2 수행 task) 테스트 명령을 실제로 실행했고 통과 수를 봤는가?
- [ ] (V-3 수행 task) 신규 린트 경고 0을 실제로 확인했는가? — 리뷰 지적 수정 후에도 재확인.
- [ ] acceptance 각 항목에 대해 diff 어디서 충족되는지 지목할 수 있는가?
- [ ] 변경한 심볼의 caller가 모두 함께 갱신되었는가?
- [ ] 이 수정으로 마지막 호출부가 사라진 고아 심볼·미사용 import가 없는가 (V-7 역방향)?
- [ ] "동작 확인됨" 주장의 근거가 빌드 통과 외에 있는가?
- [ ] 이 task에서 추측으로 작성한 코드가 하나도 없는가?
- [ ] 수정한 코드의 주석·docstring이 새 동작과 일치하는가 (옛 내용 그대로 둔 stale 주석이 없는가)?
- [ ] (V-9 수행 task) 시각 요소 분해 표에 ❌ 잔존 0이고, **`⏳ 미확인` 행을 F-8 인계 목록에 등재**했는가 — 미확인은 ❌가 아니지만 **제외가 아니라 인계**다(등재 없이 넘어가면 F-8이 받을 목록이 비어 검증이 통째로 사라진다). V-9 미수행 task는 N/A?
- [ ] (인벤토리 표 있는 task) 인벤토리 **각 행에 원본 파일:라인과 구현 파일:라인을 둘 다 지목**했고, 정적 축에 `⏳`가 0건인가 — 한쪽만 지목한 행은 ✅가 아니다(원본을 지목 못 했다면 원본을 읽지 않은 것이고, 그 상태의 "동일"은 추측이다). 인벤토리 표 없는 task는 N/A?

하나라도 "아니오" → Phase I 복귀. **단 해당 단계를 실행하지 않은 task의 "N/A"는 "아니오"가 아니다** — Fast-Path가 그 단계를 생략한 경우(예: Type A 순수 문서는 V-1/V-2 미실행이므로 빌드·테스트 박스가 N/A로 통과; V-3 미수행이면 린트 박스도 N/A). N/A와 "실행했어야 하는데 안 함(=아니오)"을 혼동하지 않는다: V-1/V-2/V-3을 **수행한** task는 반드시 "예"여야 한다.

**자기기만 패턴**: "아마 동작할 것이다", "테스트는 안 돌렸지만 빌드 통과했으니 OK", "비슷한 코드를 본 적 있어서 맞을 것" → Phase I 즉시 복귀.

### V-9. 시각 충실도·참조 정합 검증 (디자인 정합·화면 이식 작업만)

plan에 **`## 시각 요소 분해` 섹션(Step 2.5 산출물)이 있을 때만** 수행한다 (디자인 정합·화면 이식 작업이 아니면 건너뜀 — 이 표준 제목으로 트리거를 판정한다). 수행 시점은 **V-7 이후·V-8 이전** — V-8("Phase D 진입 직전")이 V-9 결과까지 포괄하는 최종 관문이 되도록 한다. **수행 시 `references/phase-v9-detail.md`를 읽고 그 절차(요소 전수 대조·행별 diff 위치 지목·빌드≠시각 일치·**정적 판정 축 게이트**·렌더 3분기·불일치 시 Phase I 복귀)를 그대로 따른다.**

**정적 판정 축에는 `⏳ 미확인`을 쓸 수 없다 (인벤토리 표가 있을 때).** plan에 `### 참조 정합 인벤토리` 하위 표가 있으면 **항목 존재·개수·순서 / 라벨 문구 / 컨트롤 타입 / 선택지 / 기본값 / 활성·비활성 조건**은 원본 소스와의 대조로 결정되므로, 렌더 가용성과 무관하게 ✅/❌로 판정한다(각 행은 **원본 파일:라인 ↔ 구현 파일:라인 양쪽 지목**이 있어야 ✅). 렌더 3분기(`⏳` 경로)는 **시각 축에만** 적용한다 — 축을 나누지 않으면 소스만 보면 판정되는 것까지 미확인으로 쓸려가 "화면을 볼 수 없다"가 문구·컨트롤 미검증의 면죄부가 된다. **컨트롤 타입 대체는 ❌ 확정**이며("기능적 동등" 판정 금지), 대응 컨트롤 부재로 대체가 불가피하거나 `**원본**:` 경로에 접근할 수 없으면 Halt한다(`references/halt-conditions.md`).

**미확인 행은 F-8로 인계한다 (의무).** 렌더 확인이 불가한 행(데스크톱 UI·캡처 도구 부재 등)은 `⏳ 미확인`으로 표기하고 그 목록을 plan의 분해 표에 남긴다 — **Phase F-8이 완료 선언 직전에 이 목록을 받아 게이트를 건다.** task 루프는 멈추지 않지만, 인계는 검증의 이연이지 면제가 아니다(미확인을 보고에만 적고 완료를 선언하던 종전 경로를 F-8이 차단한다).

### 재시도 한계 (Halt 트리거 — 무한 루프 차단)
- 같은 task에서 **동일 BLOCKER/MAJOR 3회 연속** → Halt (reviewer의 RECURRING 태그 포함).
- 같은 task에서 **리뷰 지적(BLOCKER/MAJOR) 수정 사이클 누적 5회** → Halt (매번 다른 지적으로 도는 무한 수정 루프 방지).
- 한 task에서 **빌드·수정 사이클 10회 이상** 반복하고도 미완 → Halt (무한 그라인딩). 위 두 캡(리뷰 지적 한정)과 아래 "빌드 5회 연속 실패"(원인 미상 한정) 캡이 **모두 못 잡는** 시나리오 — 원인은 매번 알지만 끝나지 않는 그라인딩 — 를 이 상한이 유일하게 잡는다.
- 이 셋 + 나머지 카운터(checkpoint 복구 2회·빌드 5회 연속 실패), **카운터 영속화**(plan.md `## Retry Ledger`에 기록해 auto-compact·재개에서 그 값부터 이어 셈 — G5), 상세 복구 절차는 모두 `references/recovery.md`에 일원화(단일 출처).

## Phase D — Done

**① 리뷰 수정분 유무 판정 (HEAD 커밋 제목 기준)**: Phase D 진입 시 `git log -1 --format=%s`로 HEAD 커밋 제목을 확인한다.
- **HEAD = `checkpoint: T<N> pre-review`** = 리뷰가 첫 판에 OK라 pre-review 커밋이 곧 최종 코드(추가 수정 없음) → ③의 amend 분기.
- **그 외** = ③의 새 완료 커밋 분기 — `checkpoint: T<N> review-fix`가 쌓인 경우(수정분이 커밋으로 실재), Type A처럼 pre-review 없이 HEAD가 `checkpoint: T<N> start`인 경우 모두 여기.
- 판정 신호가 커밋 제목이므로 **②(체크박스 갱신)와 순서 무관**하다 — 체크박스 변경은 워킹트리에만 있어 HEAD 제목을 바꾸지 않는다(수정분이 review-fix로 커밋되는 프로토콜과 신호가 일치 — 워킹트리 상태로 판정하지 않는다). HEAD 제목이 checkpoint 계열도 `T<N>:`도 아니면(수동 개입 등) `checkpoint: T<N> pre-review` 커밋의 존재 여부로 폴백 판정한다(있으면 후속 커밋 유무로, 없으면 새 완료 커밋 분기).

**② plan.md 체크박스 갱신 (매 task, 필수 — commit보다 먼저)**: 이 task의 본체 체크박스를 `[ ]`/`[/]` → `[x]`로 바꾼 **뒤에** commit한다. 재개 시 미완료 task 식별의 1차 신호이므로 **task 완료마다 즉시** 갱신한다(Progress Log는 2 task마다지만 체크박스는 매 task). 이 단계를 빠뜨리면 재개('재개 진입')에서 체크박스가 전부 `[ ]`로 남아 git log·Progress Log와 어긋난다. 글로벌 CLAUDE.md에도 동일 규칙이 있으나, 이 스킬은 그에 의존하지 않고 자체적으로 강제한다.
- **`require-task-checkbox` hook이 이 순서를 기계 강제한다** — `T<N>:` 완료 커밋 시 plan의 해당 체크박스가 [x]가 아니면 commit이 차단(exit 2)된다. 지침 준수 부탁이 아니라 구조적 게이트다.
- 주의(stale [x]): 체크박스를 [x]로 바꾼 뒤 commit이 실패하면 체크박스만 [x]로 남을 수 있고, **plan.md가 gitignore인 repo에선 `git reset --hard <checkpoint>` 복구도 이를 되돌리지 못한다** — 이 신호 충돌은 '재개 진입'의 "git log 신뢰" 원칙이 그대로 해소한다(체크박스는 어긋날 수 있는 신호, git log가 진실).

**③ commit** — Phase V 서두에서 만든 `checkpoint: T<N> pre-review` 커밋을 이 task 완료 커밋으로 마무리한다. **①의 판정으로 분기**한다:

- **①에서 HEAD가 pre-review면**(수정분 없음) → 새 커밋 대신 **pre-review 커밋에 amend**한다(체크박스 변경만 흡수되고 메시지가 완료 메시지로 승격):
  ```bash
  git add -A                    # ②의 체크박스 변경만 staged됨
  git commit --amend -m "T<N>: <한 줄 요약>
  ... (아래 완료 메시지 본문) ..."
  ```
- **①이 그 외면**(review-fix 후속 커밋 있음 또는 Type A) → 새 완료 커밋을 만든다. pre-review·review-fix 커밋은 그 앞 단계로 남는다(squash하지 않음 — 리뷰 대상 diff 고정 이력 보존):
  ```bash
  git add -A                    # 남은 워킹트리 변경(체크박스 등)이 있으면 staged됨
  git commit --allow-empty -m "T<N>: <한 줄 요약>
  ... (아래 완료 메시지 본문) ..."
  ```
  `--allow-empty`인 이유: plan.md가 gitignore인 repo에서는 수정분이 전부 review-fix로 기커밋되고 체크박스 변경도 git에 안 보여 staged가 0일 수 있다 — 그 경우에도 완료 커밋(본문에 빌드/테스트/리뷰 기록)이 `nothing to commit`으로 실패하지 않게 한다(`checkpoint: T<N> start` 빈 커밋과 동일 선례). tracked plan repo에서는 체크박스 변경이 staged되므로 no-op(무해).

완료 메시지 본문(두 경로 공통):

```
T<N>: <한 줄 요약>

<변경 요약>
Type: <A/B/C/D>
Build: <명령> → OK
Tests: <X/Y passed>
Review: spec OK (prefilter: <PASS/ESCALATE→C격상> — Type B만, 그 외 필드 생략), quality <OK/SKIPPED>
Caller-recheck: <확인한 심볼 수>개 심볼, 누락 0
Self-honesty: PASS
```

진행 보고 (각 task 1줄, 사용자 확인 요청 금지):
```
✅ T<N> 완료 (<N>/<TOTAL>)  →  T<N+1> 시작
   Type: <A/B/C/D> | Tests: <X/Y> | Phase V: <적용 단계 요약>
```

이 보고는 **알림**이지 **확인 요청이 아니다**. 사용자 응답을 기다리지 말고 즉시 T<N+1>의 Phase P를 시작한다.

### Progress Log 갱신 (2 task마다 또는 큰 task 후)

장시간 작업의 컨텍스트 누적 대비. plan.md의 `## Progress Log`에 기록:

```markdown
## Progress Log
- T1-T2 완료 (커밋 abc123, def456): SettingsViewModel + Page 바인딩 추가. 빌드/테스트 OK.
  - 결정: 테마는 시스템 설정 우선, 수동 토글은 override (사용자 합의).
- T3-T4 완료 (커밋 ghi789, jkl012): ThemeService 추가 + App.xaml 적용. 회귀 없음.
```

- **완료 내역(무엇)만이 아니라, 작업 중 내린 결정·합의(왜/어떻게)도 함께 기록한다.** 대화 중 정한 것(예: "이 케이스는 무시키로 함", "A 방식 채택")은 압축되면 요약에서 흐려지거나 사라져, 압축 후 Claude가 그 결정을 잊고 다르게 진행하는 혼동의 주원인이 된다. plan.md에 남기면 압축돼도 복구된다.
- 큰 결정은 plan.md의 `## Decisions`에도 반영한다(Progress Log는 시간순 요약, Decisions는 결정 모음 — 압축 후 둘 다 참조).

이후 task는 전체 대화 history 대신 이 Progress Log + git log를 참조한다.
이렇게 하면 컨텍스트가 압축(auto-compact)되어도 plan.md에 진행 상황·결정이 남아 복구가 쉽다.

- **Progress Log 누적 압축 (plan.md 비대화 방지)**: 항목이 많이 쌓이면(대략 10개 초과) 오래된 항목들을 한 줄로 묶어 압축한다 — 예: `T1-T8 완료 (커밋 abc..xyz): 데이터 계층 + ViewModel 구축, 회귀 없음`. 상세는 git log·커밋에 남아 있으므로 plan.md엔 핵심만 둔다. **최근 2-3개 항목은 상세히 유지**(재개에 필요), 그보다 오래된 것만 압축. 중요한 결정은 압축해도 `## Decisions`에 별도 보존되므로 잃지 않는다. plan.md를 작게 유지해야 auto-compact 후 plan.md 재읽기 비용이 낮다(읽어서 다시 채우는 양이 작아짐).

### Next Steps 갱신 (압축 대비 체크포인트 + 최종 보고 시)

컨텍스트 과밀 시 압축 대비 체크포인트(컨텍스트 관리 규칙 4), Halt 보고, 그리고 Phase F 통과 최종 보고 시 plan.md의 `## Next Steps`에 다음을 기록:

```markdown
## Next Steps
- 권장 다음 액션: <명확한 한 줄> (예: T7부터 implement-task 재개 / PR 생성 후 /code-review 호출)
- Suggested skills: <쉼표 구분> (예: pjc:implement-task, 공식 /code-review, 공식 /security-review)
- 위키 갱신 (llm-wiki 사용 중이고 이 프로젝트가 등록돼 있을 때만): 위키 반영 여부는 F-6.5에서 **능동적으로 사용자에게 묻는다**(여기 Next Steps에 묻어두는 것으로 대체하지 않음). 동의 시 `pjc:llm-wiki` 절차 B를 별도 세션에서 진행 (구현 세션은 위키 직접 수정 안 함). **사용자가 미루면 그 사실을 `[K-DRIFT]` 큐에 1줄 남긴다**(F-6.5 — 묻고 끝내면 미반영이 대화와 함께 사라져 위키가 조용히 뒤처진다).
```

목적: ① 압축 직후의 Claude 자신이 plan.md만 읽고 정확히 재개할 수 있게 함 (압축 생존의 핵심), ② Halt·완료 시 종철님이 plan.md만 보고도 무엇을 호출할지 즉시 알 수 있게 함. handoff 패턴 차용.

### 🚫 금지 표현

**① 확인을 구하는 표현 (사용자 답을 기다리게 만든다)**

- "T2 진행할까요?"
- "다음 작업으로 넘어가도 될까요?"
- "이대로 진행해도 괜찮을까요?"
- "T1 완료. 계속할까요?"
- "확인 부탁드립니다."
- "Phase 2 진행할까요?" / "다음 단계로 넘어갈까요?" / "2단계 시작할까요?" / "Step 2 진행할까요?"

→ 대신 "✅ T1 완료 (1/10) → T2 시작" 후 **즉시** T2 진행.

**② 평서형 예고로 turn을 끝내는 것 (묻지 않았는데도 루프가 멈춘다)**

- "이어서 진행하겠습니다"
- "계속 진행합니다"
- "여기까지 정리합니다"
- "T\<N\>부터 이어서 진행하겠습니다"

**예고 자체가 금지가 아니라 *예고를 마지막 말로 남기고 turn을 끝내는 것*이 금지다.** ①과 달리 이 표현들은 질문이 아니어서 "묻지 않았다"는 규칙은 지킨 것처럼 보이지만, **도구 호출 없이 텍스트만 출력하면 turn이 거기서 끝나 사용자 입력을 기다리게 된다** — 결과는 확인 요청과 똑같이 루프 정지다. 실제로 *"여기까지 진행 상황을 정리 합니다. 계속 T5부터 이어서 진행하겠습니다."* 를 출력하고 멈춘 사례가 관측됐다.

→ **진행 의사를 밝혔으면 같은 turn 안에서 다음 도구 호출로 이어간다.** 다음 task의 Phase P(Read/grep)를 그 turn에서 시작하면 된다. 상태 기록이 필요하면 **말로 요약하지 말고 plan.md에 쓴다**(컨텍스트 관리 규칙 4).

**③ 세션 전환·컨텍스트 우려 제안 (루프 중간)**

- "이대로 계속할지, 새 세션으로 옮길지 알려주세요"
- "새 세션에서 이어가시면 온전한 컨텍스트로 재개됩니다"
- "컨텍스트가 길어져 후반 품질이 떨어질 수 있으니 새 세션을 권합니다"
- "/clear 후 새로 시작하시면 같은 지점에서 이어집니다"

**컨텍스트 한계는 Halt 사유가 아니다** — 정답은 압축을 통과하는 것이지 세션을 갈아타자고 제안하는 것이 아니다(`references/halt-conditions.md` 「컨텍스트 한계는 Halt 사유가 아니다」). ①②와 달리 이 유형은 **위임 자체를 반납하는 형태**라, 사용자가 "새 세션으로"라고 답하면 그때까지의 대화 맥락이 통째로 버려지고 루프도 거기서 끝난다. 실제 사고: T1 완료 후 T2 진행 중에 *"이 세션이 상당히 길어져 …이대로 계속할지, 새 세션으로 옮길지 알려주세요"* 를 출력하고 정지했다.

→ **컨텍스트 관리 규칙 4를 수행한다** — 현재 task를 Phase V/D까지 완료 → plan.md에 상태 완전 기록 → **사용자 보고 없이** 같은 turn의 다음 도구 호출로 계속. 새 세션 권유는 **루프 시작 전(위 `🧭 시작 전 컨텍스트 공시`)에만**, 그것도 답을 기다리지 않는 공시로 한다.

**④ 중간 수동 실행·확인 요청 (검증 책임의 전가)**

- "여기서 한번 직접 실행해 보시겠어요?"
- "이 부분은 직접 확인해 주시겠어요?"
- "한번 빌드해서 돌려봐 주시면 좋겠습니다"

**위 목록은 hook이 잡는 형태만 담는다** — 골든이 이 문구들을 실제로 hook에 주입해 대조하기 때문이다. 그러나 **"이 부분은 직접 확인해 주세요"·"테스트는 그쪽에서 돌려봐 주세요"처럼 평서형·2인칭 지칭형으로 넘기는 것도 똑같이 금지**다. 그 형태는 정상 안내문과 어휘가 겹쳐 기계로 좁히면 오차단이 나므로 **의도적으로 hook 밖에 두었고, 이 규칙이 유일한 방어선이다**(③의 어미 변형도 같다).

**기계 검증(빌드·테스트·정적 검사)으로 확인되는 것은 직접 실행한다** — 사용자에게 대신 돌려 달라고 하지 않는다. 기계 검증이 불가능한 것(GUI 조작감·시각 확인·사용자 체감)은 **멈추지 말고 `⏳ HUMAN-VERIFY`로 표기해 최종 보고로 넘긴다**(정본 `references/halt-conditions.md` 「중간 수동 테스트 요청은 중단 사유가 아니다」). 이 표기는 정직한 보고 수단이지 중간 정지 신호가 아니다.

> **`require-evidence` Stop hook이 ②③④를 기계로 뒷받침한다** — 미완료 task가 남은 자율 루프에서 위 문구로 종료를 시도하면 종료를 막고(`decision: block`) 이어서 진행하도록 되돌린다. 문구는 **띄어쓰기·어미 변형까지 관용 매칭**하므로 표기를 바꿔도 걸린다(회피 대상이 아니라 지켜야 할 규칙이라는 뜻).
>
> 다만 **"hook이 막아 줄 테니 괜찮다"고 가정하지 말 것** — 그 검사는 오차단을 피하려 조건을 좁게 잡았고, 판정 불가는 전부 통과한다. **차단 조건·신호 분류·상한 수치의 정본은 `docs/hook-conventions.md`** 「`require-evidence`의 조건부란」이다(여기에 복제하지 않는다 — 수치를 양쪽에 적으면 hook을 고칠 때 문서만 낡는다). **1차 방어선은 여전히 이 문서 규칙**이고 hook은 실수를 한 겹 더 막아 줄 뿐이다.
>
> **이 ②③④ 목록이 hook 판정 문구의 정본**이므로 여기를 고치면 `require-evidence.ps1`의 `$rxAdvance`(②)·`$rxHandoff`(③)·`$rxManualAsk`(④) **셋 전부**를 함께 고친다. **방향은 문서 → 코드다** — 이 목록이 먼저 정해지고 정규식이 그것을 따라간다(골든 L12가 이 목록을 파일에서 직접 읽어 hook에 주입하므로, 둘이 어긋나면 테스트가 FAIL로 드러낸다).

**예외 — 아래는 정당한 정지이며 ②③④에 해당하지 않는다**: Halt 보고(`## ⛔ 작업 중단`) · 최종 보고(`🎉`) · F-8 확인 게이트(`## ⏸️ 구현 완료 — 확인 대기`) · Phase 0 사전 승인 확인(`## ⏸️ 사전 승인 확인`) · 규칙 12의 외부 작업 승인 요청(`## ⏸️ 외부 작업 승인 요청`) · 리뷰어 과부하 시 선택 요청(`## ⏸️ 리뷰 인프라 선택 요청`) · Phase G 재루프 한도 도달(`## ⛔ Phase G 재루프 한도 도달`) · `plan-feature` Step 0-0 세션 확인(`## ⏸️ 세션 확인`). 이들은 **루프가 정상적으로 도달한 종착점**이거나 규칙이 명시한 개입 지점이다. **마커를 단 지점의 전수 목록은 `docs/hook-conventions.md`가 정본**이다(여기 목록이 그것과 어긋나면 그쪽을 따른다 — 새 지점이 추가될 때 한 곳만 고치면 되게 한다).

> **마커 규약 (필수)**: **하니스 스킬의 모든 정당 개입 지점은 Strong 마커(`⛔`·`🎉`·`⏸️`)를 헤더에 달아야 한다** — hook이 위반과 정당한 정지를 구분할 수 있는 유일한 기계 신호이기 때문이다. 특히 ③④는 물음표·"확인" 같은 약한 표지를 통과 근거로 인정하지 않으므로(그 표지를 인정하면 "질문 형태를 띠는 것이 곧 위반"인 이 두 유형을 검사할 수 없다), **마커가 없으면 정당한 요청도 차단될 수 있다.** hook은 **어느 스킬이 말했는지 구분하지 못하고** 세션에 루프 발동 흔적이 있는지만 보므로, 이 규약은 `implement-task` 밖의 스킬(`plan-feature`의 새 세션 권유 등)에도 똑같이 적용된다. 새 개입 지점을 추가할 때는 마커를 함께 준다.
>
> **이 목록과 `halt-conditions.md`의 예외는 축이 다르다** — 여기는 **정지해도 되는 "말하기"**(어떤 형태의 발화가 허용되는가)를 세고, 그쪽은 **루프를 세워도 되는 "중단 사유"**(F-8·V-9 등 무엇이 정지를 정당화하는가)를 센다. 개수가 달라도 모순이 아니다.

## Phase F — Finalize (모든 task 완료 후)

전체 plan 통합 검증. **진입 조건표(1 task+Type A=생략 / 1 task+Type B=F-1·F-2·F-6만 / 2+ tasks 또는 Type C/D 포함=전체 F-1~F-8)와 F-1~F-8 상세는 모두 `references/phase-f-detail.md`에 일원화.**

- 단, **F-6.5(notes 기록 + 오래된 항목 아카이브 이동)는 Phase F가 생략·축소돼도 코드 변경이 있었으면 항상 수행**한다(빌드 영향 없는 trivial 단일 수정은 공통 지침의 문서 갱신 생략 조건을 따름) — 누락 빈발 지점이라 본문에 남긴다.
- 구현 중 **새로 생긴** plan `## Deferred / Follow-up`(보류)·`## Out of Scope`(기각) 항목은 `pjc:llm-wiki` 절차 K 5-2의 `[DECISION]` 큐에 1줄씩 기록한다(vault 없으면 그 규약의 폴백) — 계획 시점에 큐잉된 결정과 중복이면 생략. 같은 시점에 구현 중 확인된 **작업 규약·함정 사실**(레포에 안 담는 크로스 세션 지식)은 `[PROJECT-FACT]` 큐에 기록한다(형식·입도는 절차 K 5-3 정본 — 배치 트리거 ② implement-task 종료).
- F-7은 `plan-completion-reviewer` subagent (Opus) 호출 — plan 전체 적대적 검토. **동기 호출**(`run_in_background: false`) — 검토 결과를 받아 판정한 뒤에만 완료 선언으로 간다.
- **F-8(시각 충실도 최종 관문)은 plan에 `## 시각 요소 분해`가 있을 때만 수행**하며, F-6.5처럼 **Phase F가 생략·축소돼도 해당 시 항상 수행**한다. 수행 위치는 **완료 선언 직전** — PRD 없는 plan은 F-7 뒤, **PRD 연결 plan은 Phase G 통과 후**(Phase G 재루프가 시각 요소를 다시 바꿀 수 있어 선언 직전 1회로 모은다). V-9가 인계한 `⏳ 미확인` 행이 하나라도 남으면 **완료 선언을 보류하고 Halt**한다.
- **Phase Ledger 갱신**: Phase F를 통과하면 plan.md `## Phase Ledger`에 `Phase F 통과 (HEAD <sha>)`를 기록한다 — 이후 Phase G 재루프 중 압축·재개가 발생해도 Phase F(F-7 Opus)를 중복 재실행하지 않기 위한 마커다('재개 진입'의 Phase Ledger 판정 규칙 참조). **PRD 연결 plan은 Phase G까지 통과하면 추가로 `Phase G 통과 (Must 100%)`를 기록한다**(phase-g-detail G-4 — 새 세션 plan-feature Step 0.2가 완료를 판정하는 신호).

## Phase G — 요구 재검증 (PRD 있을 때만)

**진입 조건**: plan.md 상단의 `**PRD**: <경로>` 줄이 있을 때만 진입한다 — 이 줄이 단일 신호다. 줄이 없으면 레포에 PRD 파일(`docs/prd.md` 등)이 있어도 진입하지 않는다(무관한 과거 PRD를 자기 작업 PRD로 오인해 거짓 미충족을 보고하는 것 방지 — 그 경우 Phase F가 최종).

Phase F는 "plan.md에 적힌 것"을 검증한다. Phase G는 한 단계 위 — **"plan.md가 PRD 요구를 빠뜨리지 않았는가"** 를 검증한다. **진입 시 `references/phase-g-detail.md`를 읽고 그 절차(G-1~G-4)를 그대로 수행한다.** 루프 제어 핵심 요약:

- **G-1. PRD 전수 대조** — F-7 reviewer의 대조 결과를 재사용한다(동일 대조를 반복하지 않음, 보완 대조 예외 3가지는 상세 참조). REMOVED FR은 대상 제외. 기계 검증 불가 항목은 ✅가 아니라 ⏳ HUMAN-VERIFY로 표기한다(✅ 둔갑은 V-8 자기기만 패턴과 동일 위반).
- **G-2. 갭 처리 (자율 재루프)** — Must 미충족은 새 task 추가 후 Phase P부터 자율 재진입(사용자 확인 불필요), Should는 사용자 선택, Could는 follow-up만. 요구 자체를 바꿔야 하면 임의 변경 금지 — 사용자 승인 → PRD 갱신 → plan 조정 순서.
- **G-3. 종료 조건** — 재루프 최대 2회. 같은 FR 2회 연속 미충족이면 즉시 Halt. 한도 도달 시 상세의 의무 보고 형식으로 Halt하고 지시를 기다린다(그냥 완료 선언 금지).
- **G-4.** 최종 보고에 G-1 충족표 전체 + Must 충족률 100%를 명시한다.

### 최종 보고 (Phase F 통과 후 — PRD 있으면 Phase G까지 통과 후)

> **권한 경계 (필독).** 최종 보고 = 루프의 종착점이자 첫 사용자 개입 지점. 여기서 **멈춘다.** push·main 병합·태그·릴리즈·PR은 루프 권한 밖이라, 사용자가 그 행위를 명시 승인하기 전에는 하지 않는다. '진행'·'승인' 같은 답이라도 **직전 질문이 '구현'에 관한 것이었다면 그 범위는 구현이며 push/릴리즈 승인이 아니다** — 외부 작업은 **별도로**, 행위를 이름으로 적어 다시 묻는다 — **`## ⏸️ 외부 작업 승인 요청` 헤더로 출력**하고 그 아래 행위를 나열한다(예: "이제 origin/main에 push하고 v1.x.x 릴리즈를 발행할까요?"). 헤더의 Strong 마커는 이 정지가 규칙이 명시한 개입 지점임을 hook에 알리는 신호다(금지 표현 예외 목록의 마커 규약). 구현 승인 질문에 이 작업들을 묶지 않는다. (절대 규칙 12)

최종 보고는 `references/final-report-template.md`의 양식을 그대로 사용한다 — Tasks 완료 수·변경 요약·Phase F/G 결과(G-1 충족표 포함)·**Plan 변경 내역(구현 중 plan.md에 가해진 수정 — 추가 task·Files 추가·신규 Deferred/Decisions·체크박스 확인; 없으면 "계획 원안대로 완료" 1줄)**·실행 통계·follow-up·분할 plan 안내, 그리고 마지막의 "여기서 멈춥니다"(외부 작업은 각각 별도 승인) 고지까지 포함해 보고한다.

## 참조 문서

- 중단 조건 + 보고 양식: `references/halt-conditions.md`
- 복구 메커니즘 + Reviewer 호출 실패 대응(과부하 529·도구 불가·거절) 매트릭스: `references/recovery.md` — **subagent 동기 호출 규약**(정상 경로)도 이 파일이 정본이다.
- 안티패턴 표: `references/antipatterns.md`
- 저빈도 상세(빌드/테스트 fallback 표 · UI 문구 · 검증 스크립트 Windows 보안): `references/authoring-detail.md`
- Phase F 상세: `references/phase-f-detail.md`
- Phase G 상세: `references/phase-g-detail.md`
- Phase V-9 상세: `references/phase-v9-detail.md`
- 최종 보고 양식: `references/final-report-template.md`
- 규칙의 배경·이력(규칙 아님 — 판단이 필요할 때만): `references/rationale.md`
