---
name: implement-task
description: This skill should be used when executing tasks from an approved plan.md. Triggers — ONLY when an approved plan.md already exists (or the user is approving a plan just presented) — on phrases like "구현", "implement", "이대로 진행", "진행해", "계속", "T<N> 진행", "go" (meaning "proceed with the plan"). If NO plan exists yet and the user asks to design or implement a non-trivial change, that is plan-feature first — it writes the plan, this skill runs it. Runs a FULLY AUTONOMOUS loop — processes ALL tasks (T1...Tn) without asking between tasks, stopping only when every task completes or a Halt Condition fires. Resuming mid-plan ("T6부터 계속") means T6 through the LAST task plus Phase F/G, not just T6. For trivial single-line edits without a plan, do NOT use this skill — Claude applies the change directly and lets hooks validate.
argument-hint: "<시작 task ID (거기부터 끝까지 자율 진행) | 생략 시 첫 미완료부터>"
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
   - 작업 중 발견한 다른 문제는 plan.md follow-up에 추가만.
   - 한 번에 한 task만 수행.

### 아키텍처·코드 규율
5. **DDD 준수 + YAGNI.**
   - 비즈니스 로직은 Domain 레이어 (AGENTS.md가 다른 아키텍처를 명시하면 우선 적용).
   - 사용처 1곳인 헬퍼는 인라인. 3회 반복 확인된 코드만 공통화.

5-1. **명시적·직접적 코드 우선 (추적성).** 영리한 추상화보다 한눈에 동작이 보이는 코드를 쓴다. 과한 간접화(불필요한 디자인 패턴·메타프로그래밍·깊은 제네릭·성급한 DRY)는 사람 눈엔 우아해 보여도, 이후 LLM이 수정할 때 실제 동작을 추적하려 여러 파일을 오가게 만들어 누락·환각·재작업을 늘린다. **"약간 장황해도 추측 없이 파악되는" 코드**를 우선한다.
   - 단, 이는 명료성을 해치라는 뜻이 아니다. 좋은 이름·명시적 타입·명확한 구조·관련 로직의 지역성은 사람·LLM 모두에게 좋으므로 유지한다.
   - 간접화가 정당한 경우(실제로 3회+ 반복, 도메인상 필수 추상화)는 예외다. 판단 기준은 "이 추상화가 없으면 코드가 더 단순해지는가" — 그렇다면 빼는 게 낫다.

6. **위생.** 불필요한 주석·죽은 코드·미사용 import·placeholder 문서 금지.

6-1. **민감 정보 금지 (코드·문서 공통).** 실제 비밀번호·API 키·토큰·시크릿·DB 연결 문자열·내부 IP/호스트·개인정보를 **코드는 물론 어떤 생성 문서(plan.md·notes.md·repro.md·PRD·위키 등)에도 적지 않는다.** 이 문서들은 git commit·스냅샷으로 영구 보존되므로 한 번 남으면 회수가 어렵다. 필요하면 **환경변수 이름만** 적고 실제 값은 `.env`(gitignore)에서 관리한다. (`check-utf8-and-lines` hook이 실제 값 패턴을 사후 경고하지만, 1차 책임은 작성 시 회피다.)

7. **주석은 한글.** "무엇"이 아닌 "왜". 코드로 의도가 드러나면 생략.

7-1. **주석·코드 동기화 (stale 주석 금지).** 코드를 수정하면 그 코드에 딸린 주석·docstring·XML 문서주석(`///`)이 새 동작과 일치하는지 **반드시 확인하고, 어긋나면 함께 수정**한다. 코드만 바꾸고 주석을 옛 내용 그대로 두면, 틀린 주석이 오히려 후속 작업(사람·LLM 모두)을 오도한다 — 틀린 주석은 주석이 없는 것보다 나쁘다.
   - 대상: 변경한 함수/메서드 위 주석, 파라미터·반환 설명, 인라인 주석, docstring/`///` 문서, 시그니처가 바뀌면 호출처 주석까지.
   - 더 이상 맞지 않는 주석은 갱신하거나(내용이 바뀐 경우) 삭제한다(코드로 자명해진 경우). "왜"가 바뀌었으면 그 이유를 갱신한다.
   - Phase V-8 자기점검과 code-quality 검토에서 stale 주석을 확인한다.

7-2. **UI 문구는 일반 사용자 친화적으로.** 화면에 표시되는 모든 문구(레이블·버튼·메시지·오류·툴팁·플레이스홀더)는 **개발 용어가 아니라 일반 사용자가 이해하는 일상 언어**로 쓴다. 최종 사용자는 개발자가 아니다.
   - **개발/기술 용어 노출 금지**: `null`, `exception`, `validation failed`, `timeout`, `400 Bad Request`, `parse error`, `commit`, `query`, `token`, 변수명·클래스명·열거형 값(`Status.PENDING`)을 그대로 화면에 쓰지 않는다.
   - **오류 메시지는 원인+다음 행동 중심**: 무엇이 잘못됐는지보다 사용자가 **무엇을 하면 되는지**를 알려준다. 예: `Error: connection refused` → "서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요." / `ValidationError: email invalid` → "이메일 주소 형식을 확인해 주세요."
   - **일상 표현 사용**: "삭제(delete)" 대신 "지우기", "동기화 실패" 대신 "최신 정보를 가져오지 못했습니다" 등 맥락에 맞는 자연스러운 표현. 단, 해당 도메인에서 사용자에게 익숙한 전문 용어(예: 회계 앱의 "분개")는 그대로 둔다.
   - **비난조·기술 추궁 금지**: "잘못된 입력", "유효하지 않음" 같은 딱딱한 표현 대신 부드럽게 안내한다.
   - 판단이 애매한 문구(전문 용어를 일상어로 바꿔도 되는지 등)는 plan에 ⏳ HUMAN-VERIFY로 표시해 사용자 확인을 받는다. 문구는 리소스로 분리하되(다국어 규칙), **분리한 문구의 내용 자체가 사용자 친화적**이어야 한다.

8. **파일·인코딩.** UTF-8 (BOM 없음). **파일은 하나의 명확한 책임을 갖는다** — 여러 독립 책임이 한 파일에 섞여 비대해지면 책임 단위로 분리한다. **1500라인은 강제 분리선이 아니라 "분리를 검토하라"는 신호다.** 단일 책임인데 길 뿐이면 억지로 쪼개지 않는다 (관련 로직을 여러 파일로 흩으면 지역성이 깨져 후속 추적·수정이 오히려 어려워진다 — 규칙 5-1). 분리할 때는 응집도를 유지해 관련 로직이 흩어지지 않게 한다. 분리가 필요하면 작업을 plan에 등록.

9. **언어 스타일.** 최신 LTS 권장 + 공식 문서 기준. AGENTS.md가 다른 버전 고정이면 우선.

### 안전
10. **파괴적 작업 · 새 의존성 → 자동 실행 금지, Halt.**
    - force push, history rewrite, rm -rf, DB drop, 권한·보안 변경
    - **DB 데이터 삭제·변조**: DROP/TRUNCATE, WHERE 없는(또는 전체 대상) DELETE·UPDATE, 스키마 삭제, migration reset/down, ORM 대량 삭제(RemoveRange·deleteMany({})·delete_all 등). 코드로 작성하든 명령으로 실행하든, 데이터 손실·전체 변조 가능 작업은 **사용자 승인 전 금지** (DB 데이터는 git으로 복구 불가). 단 `DELETE/UPDATE ... WHERE <특정 조건>` 같은 일상적·국소적 작업은 plan에 명시돼 있으면 진행 가능.
    - **새 라이브러리·외부 서비스 도입** — 단 plan의 `## 사전 승인 항목 (일괄 승인 대상)`에 등록·일괄 승인된 **비파괴 패키지/라이브러리 의존성 추가·버전 변경**은 그 지점에서 진행한다(Halt 안 함). **인증정보가 필요한 신규 외부 서비스 도입은 carve-out 제외 — Halt 유지**(자격증명 도입은 보안상 별개).
    - **기존 외부 서비스로의 비가역 부작용 호출**: 운영 API 쓰기·이메일/알림/SMS 발송·결제·외부 상태 변경 등. 신규 도입이 아니어도 검증·실행 중 이런 비가역 부작용 호출은 사용자 승인 전 금지(테스트는 mock·스테이징). plan에 명시·승인됐으면 진행 가능.
    - **사전 승인과의 관계 (위임 경계)**: 위 파괴적 작업(force push·rm -rf·DB drop/DROP/TRUNCATE·WHERE 없는 DELETE/UPDATE·스키마 삭제·migration reset·권한/보안 변경)은 **plan의 `## 사전 승인 항목`에 적혀 있어도 일괄 사전승인 대상이 아니다 — 항상 Halt(위임 불가)**. 사전승인으로 진행되는 것은 비파괴 패키지 의존성·구조 변경(파일 분리·병합에 따른 계획된 파일 삭제·이동 포함)·비파괴 스키마(CREATE/ADD)뿐이다.

11. **plan에 답이 없는 중대 결정 → 추측 금지, Halt** (예외 안전망). 정상적으로는 계획 단계(Step 6 Decision·6.5 Edge Case·8 Open Questions·9 reviewer)가 모든 중대 결정을 미리 해결하므로 이 상황은 거의 없어야 한다 — 발생하면 **계획 부실의 신호**다. 실행 중 plan·AGENTS.md·코드 어디에도 근거 없는 **중대한** 결정(아키텍처, 비가역적 데이터 형식·API 계약, 동작 의미가 갈리는 분기)을 만나면 추측하지 말고 Halt해 묻는다. **사소한** 결정(변수명·국소 구현 등 쉽게 되돌림)은 follow-up 기록 후 진행(자율성 유지). 애매하면 **보수적으로** 본다 — 안전·수정 범위·공개 API 계약·비가역성에 닿는 결정은 Halt해 승인받고(글로벌 "애매하면 승인 필요로 본다"와 정합), 순수 국소·가역 결정(변수명 등)만 follow-up 후 진행한다. Halt 시 보고에 "이 결정이 계획에서 누락된 이유"를 한 줄 적어 차후 계획 단계를 강화한다.

12. **외부/비가역 작업 → 자율 루프 권한 밖, 별도 명시 승인.** push·main 병합·태그·GitHub 릴리즈·PR 생성은 자율 루프가 자동 수행하지 않는다. 루프 권한은 로컬 작업 브랜치(`task/<id>-<slug>`) commit까지다. 이 작업들은 'plan 승인'·'구현 진행' 승인에 **포함되지 않으며**, 각각 그 행위를 이름으로 적어 별도 승인받는다. 애매하면 승인 필요로 본다. 이 항목들은 plan의 `## 불가피한 Halt (위임 불가)`로 명시되며 일괄 사전승인(Phase 0)에 포함되지 않는다.

> **상세 안티패턴 표는 `references/antipatterns.md` 참조.**
> **중단 조건 전체 표 + 중단 보고 양식은 `references/halt-conditions.md` 참조 — Halt 여부가 애매하면 먼저 확인.**

## 자율 루프 (Autonomous Loop)

### 🧭 시작 전 컨텍스트 확인 (구현 시작 직전, 1회)

자율 루프를 **시작하기 전에**, 현재 대화가 이미 길어 컨텍스트가 많이 찼는지 본다. **이번 세션에서 이미 auto-compact가 일어났거나 매우 긴 대화가 누적된 상태**라면, 이대로 구현을 시작하면 루프 도중 압축이 반복돼 후반 task 품질이 저하될 수 있다. 이럴 때는 첫 task를 시작하기 전에 사용자에게 알린다:
> "현재 대화가 길어 컨텍스트가 많이 찬 상태입니다. 이대로 구현을 시작하면 도중에 압축이 일어나 품질이 떨어질 수 있습니다. **새 세션에서 `pjc:implement-task`로 구현을 시작**하는 것을 권합니다(plan.md가 있으므로 'T1부터 진행'으로 그대로 이어집니다). 이대로 진행할까요, 새 세션으로 옮길까요?"

- **시작 전은 멈춰도 안전한 분기점**이므로 새 세션 권유가 적절하다. (작업 *중간*에는 멈추지 않고 압축을 통과하는 절대 규칙 4와 구분된다 — 시작 전 권유 vs 중간 통과.)
- **컨텍스트가 여유로우면 묻지 않고 바로 T1부터 시작**한다(과잉 방지). 압축 이력 없고 대화도 길지 않으면 이 확인은 조용히 통과.
- 사용자가 "이대로 진행"을 택하면 그대로 자율 루프를 시작한다(선택 존중).
- **동일 세션에서 plan-feature를 막 거쳐온 경우(plan 작성·승인 직후 연속 구현)는 이 확인을 생략한다** — plan-feature Step 0에서 이미 같은 컨텍스트 확인을 했으므로 중복이다(과잉 방지). 새 세션 재개(plan-feature를 안 거치고 implement-task 직접 호출)에서만 수행한다.

### 🚦 Phase 0 — 사전 승인 일괄 확인 (하이브리드 게이트)

자율 루프 시작 직전(첫 task 전, 1회). **배치 순서: 위 `🧭 시작 전 컨텍스트 확인` → Phase 0 → 루프.** 재개 진입(아래 "재개 진입")인 경우 task 식별을 마친 뒤·첫 Phase P 진입 전에 1회 수행한다.

1. plan.md의 `## 사전 승인 항목 (일괄 승인 대상)`을 읽는다. **비어 있거나(`- (없음)`) 섹션이 없으면 → Phase 0를 즉시 통과**하고 루프를 시작한다(이 기능 도입 전 plan과 무회귀).
2. 항목이 있으면:
   - **이번 대화에서 plan 승인을 이미 받았으면**(plan-feature Step 10 직후 같은 세션) → 재질문하지 않는다. "다음 사전 승인 항목이 plan 승인에 포함됨: [목록]. 이 지점들에서 멈추지 않고 진행합니다" **1줄 공시 후** 루프 시작.
   - **새 세션/재개라 이번 대화에 plan 승인이 없으면** → `## 사전 승인 항목` 목록을 **한 번에** 제시하고 일괄 승인을 받는다(이것이 그 경로의 "시작 전 1회" 승인). 승인 시 루프 시작. 특정 항목을 거부하면 그 항목은 제 지점에서 Halt로 되돌린다.
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

**사용자 승인은 plan-feature 단계에서 plan.md에 대해 단 1회만 받았다.** plan.md = 전체 작업의 위임장 — 이 위임에는 plan의 `## 사전 승인 항목 (일괄 승인 대상)`이 명시적으로 포함된다(Phase 0이 인정). 단 `## 불가피한 Halt (위임 불가)`(파괴적·외부/비가역·돌발)는 제외돼 그 지점에서 별도 승인받는다.

### 🧠 컨텍스트 관리 (장시간 작업 대비)

자율 루프가 길어지면 컨텍스트가 누적되어 후반 task의 품질이 저하될 수 있다. 다음을 지킨다:

1. **각 task는 독립적으로 처리.**
   - 이전 task에서 읽은 파일 내용·빌드 로그에 의존하지 않는다.
   - 필요한 정보는 **plan.md와 git에서 다시 확인** (둘 다 영구 저장됨).
   - 이전 task 상세를 기억하려 애쓰지 말 것 — 이미 commit과 plan.md에 있음.
   - **plan이 작업을 "Phase 1~N", "단계 1~N", "Step 1~N" 등으로 나눴더라도(T<N>이 아닌 명칭) 동일하게 자율 처리한다.** 그 묶음 사이에서 멈춰 "Phase 2 진행할까요?"라고 묻지 않는다. plan의 "Phase N"은 pjc 내부의 Phase(P/I/V/D·F·G)와 무관한, 사용자 작업 묶음일 뿐이다. 모든 작업 단위를 마지막까지 자율로 진행한다.

2. **빌드/테스트 로그는 핵심만 유지.**
   - 전체 로그 원문을 컨텍스트에 길게 남기지 않는다.
   - "Build OK / Tests 12/12 passed" 같은 결과 + 실패 시 핵심 에러만.

3. **2개 task마다 Progress Log 갱신.**
   - plan.md의 `## Progress Log`에 완료 task 요약 1-2줄 기록.
   - 이후 task는 전체 대화 history 대신 이 요약 + git log 참조.

4. **컨텍스트 한계 근접 시 멈추지 않는다 — 압축을 통과해 계속 진행한다.** 현재 task를 Phase V/D까지 완료(중간 절단 금지 — 절반 수정 상태는 복구 불완전)하고 plan.md에 상태를 완전 기록(Progress Log + Next Steps + 다음 task 시작점)한 뒤, 사용자 보고 없이 계속 진행한다(auto-compact가 대화 히스토리만 요약, plan.md는 보존). 압축 감지 시 첫 행동은 plan.md + AGENTS.md 재읽기(요약 기억만으로 이어가지 않음). 컨텍스트 한계 자체는 Halt 사유가 아니다(파괴적 작업·동일 실패 반복 등 다른 Halt 조건만 해당). **상세: `references/halt-conditions.md`.**

### 진행 흐름

```
Phase 0 → 사전 승인 일괄 확인 (하이브리드 — 루프 시작 전 1회; 사전 승인 항목 없으면 즉시 통과)
loop over plan.md tasks (시작 task부터 Tn까지 — 첫 실행은 T1, 재개면 지정/첫 미완료 task):
  Phase P → 변경 전략 확정, caller 사전 추적
  Phase I → 최소 변경으로 구현
  Phase V → Type별 fast-path (V-1~V-8, + V-9 디자인 정합 작업 시)
  Phase D → checkpoint commit → (2 task마다 Progress Log) → 즉시 다음 task로

# 모든 task 완료 후
Phase F → 전체 plan 통합 검증 (조건부 진입)
Phase G → PRD 요구 재검증 (plan.md 상단에 `**PRD**:` 줄 있을 때만 — 갭 발견 시 task 추가 후 자율 재진입, 최대 2회)
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
5. 이전 task 상세는 Progress Log + git으로만 참조 (전체 history 불필요)

**세 신호(Progress Log·git log·체크박스)가 어긋나면 git log를 신뢰한다.** git log는 매 task commit(`T<N>: ...`)으로 항상 최신이고, Progress Log는 2 task마다, 체크박스는 갱신 누락 가능성이 있다. 또 지정 task의 선행(`Depends on`) task가 git log에 안 보이면 그 선행부터 다시 확인한 뒤 진행한다.

**재개도 완전 자율 루프다.** "T6부터 계속"은 "T6 하나만"이 아니라 **"T6부터 마지막 task까지 + Phase F/G까지"를 의미한다.** 첫 세션의 T1 시작과 재개 세션의 T6 시작은 시작점만 다를 뿐 동일한 루프이며, 금지 표현 규칙("T7 진행할까요?" 금지)도 동일하게 적용된다. task 사이에 멈춰 사용자에게 묻는 것은 재개 세션에서도 위반이다. 단일 task만 실행하는 경우는 사용자가 "T6만" 처럼 명시적으로 한정했을 때뿐이다.

**분할 plan 호출**: plan이 2개로 분할된 경우(plan-feature "긴 plan 분할" — `docs/plans/...-part1.md`/`-part2.md`), 각 part는 **plan 경로를 명시해 호출**한다(예: "`docs/plans/<날짜>-<slug>-part2.md` 구현"). `docs/plans` 복수 파일은 자동 plan 해소가 모호하므로 경로를 지정한다. 각 분할 plan은 자기 안에서 T1부터 시작하며(분할은 각 plan을 독립 실행), part1 완료 최종 보고가 part2 경로를 안내한다.

### P-1. plan.md 해당 task 정독
- task의 Acceptance, Files, Edge Cases, Halt Forecast, Type 모두 확인.

### P-2. Files 목록 직접 Read
- task의 Files에 있는 모든 파일을 Read 도구로 직접 열어 현재 상태 확인.
- 가정 금지. 파일 내용은 항상 직접 읽어 검증.

### P-3. 심볼 사용처 전수 추적
- 변경 대상 심볼에 대해 `grep -rn "\b<symbol>\b"` 실행.
- 결과를 모두 Read로 확인.
- task의 Files 목록과 대조 → 누락된 caller 발견 시 **자율 처리가 기본**: plan.md의 해당 task Files에 누락 caller를 추가하고 함께 수정한다 (멈추지 않음). caller 갱신은 절대 규칙 3(Cross-File Consistency)의 정상 작업이다.
  - **예외 (Halt → 재승인)**: ① 누락 caller가 여러 모듈로 연쇄(대략 5개 파일 이상)해 plan 범위를 크게 벗어나거나, ② plan에 없던 **공개(public) 멤버 시그니처 변경**이 새로 필요해지거나(공개 API 계약 변경은 plan 승인 범위 밖 — 글로벌 "공개 멤버 시그니처 변경 승인 필요"와 정합), ③ 파괴적 변경·새 의존성을 유발하는 경우에는 Halt해 재승인받는다. plan이 이미 의도한 변경의 **단순 caller 갱신(시그니처 동일·내부 호출부 수정)**은 Cross-File Consistency의 정상 작업이라 Halt 아님.

### P-4. 외부 식별자 확인 (환각 방지)
- 호출할 외부 API/메서드/타입의 정의 위치를 직접 확인.
- 못 찾으면 호출 코드 작성 금지. plan에 "확인 필요" 등록.

### P-5. 변경 전략 명시
- 어떤 순서로 변경할지 한 줄로 작성 (자기 점검용).

> **위임 금지 가드 (품질-임계 읽기).** P-2(Files 정독)·P-3(caller 전수 추적)·V-7(caller 재검증)은 `explorer` 등 발췌-읽기 subagent에 **위임하지 않는다**. explorer는 haiku로 "필요한 파일만 Read(전체 읽기 지양)"하므로 전체 판단·cross-file 검증에 부적합 — 이 단계는 메인이 직접 전체 Read한다. (병렬 위임은 plan 단계의 위치·패턴 찾기에서만; 구현 단계의 caller 검증은 메인 직접.)

## Phase I — Implement

- 시작 시 **checkpoint** 생성:
  ```bash
  git status                            # clean 확인
  git checkout -b task/<id>-<slug>      # 작업 브랜치 (이미 있으면 스킵)
  git commit --allow-empty -m "checkpoint: T<N> start"
  ```
- 기존 코딩 컨벤션 따름 (AGENTS.md > 주변 코드 모방)
- 최소 변경 원칙
- 변경 후 즉시 빌드. 오류는 다음 변경 전에 해결.

### Sub-skill 호출 (해당 시)

| Task 산출물 | 호출 sub-skill | 조건 |
|---|---|---|
| WinUI 3/WPF/MAUI ViewModel + View | `pjc:add-viewmodel` | AGENTS.md에 WinUI/CommunityToolkit.Mvvm 명시 시 |
| Domain Service / Application Service | `pjc:add-domain-service` | AGENTS.md에 DDD/Clean 아키텍처 명시 시 |
| 그 외 | (sub-skill 없음, 직접 구현) | |

**Android의 Jetpack ViewModel은 `add-viewmodel` 비대상** — 직접 구현 또는 별도 skill 필요.

## Phase V — Validate

순서대로 실행. 실패 시 Phase I로 1회 복귀 후 재시도.

> **검증 스크립트 작성 시 Windows 보안 안전 규칙 (PowerShell).** 빌드·테스트·런타임 실증용 임시 스크립트를 작성할 때, 아래 패턴이 한 스크립트에 모이면 Windows Defender·백신이 **credential stealer / 공격 도구로 오인**해 스크립트나 산출물을 격리(삭제)할 수 있다. 다음을 지킨다:
> - **자격증명을 하드코딩하지 않는다.** 로그인 테스트의 비밀번호·토큰·API 키는 환경변수(`$env:TEST_PW` 등)에서 읽는다. (절대 규칙 6-1과 동일 — 보안 + 백신 회피 양쪽.) 평문 `Password='...'`은 금지.
> - **`-WindowStyle Hidden`을 쓰지 않는다.** 검증/테스트는 숨길 이유가 없다 — "숨김 실행"은 멀웨어 핵심 신호다.
> - **`-ExecutionPolicy Bypass`는 최소화.** 꼭 필요할 때만, 그리고 위 다른 위험 신호와 겹치지 않게 한다.
> - **위험 신호를 한 스크립트에 모으지 않는다.** "정책 우회 + 숨김 실행 + 자격증명 + 토큰 스크래핑 + 프로세스 강제 종료"가 동시에 있으면 휴리스틱에 걸린다. 빌드 검증과 로그인/런타임 테스트는 가능하면 분리한다.
> - 그래도 격리되면 사용자에게 "개발 작업 폴더를 Windows Defender 예외(`Add-MpPreference -ExclusionPath`)에 추가"를 **안내만** 한다 — 보안 설정 변경은 사용자가 직접 한다(자동 실행 금지, block-destructive·승인 게이트 대상).

### 🚀 Fast-Path — Task Type에 따른 단계 선택

| Type | 실행 단계 | 생략 단계 |
|---|---|---|
| **A** (Doc/Config) | V-8만 (코드 빌드에 영향 주는 설정이면 V-1 추가) | V-1(대개)~V-7 |
| **B** (Trivial Code) | V-1 + V-2 + V-5(**prefilter Haiku**) + V-7 + V-8 (prefilter PASS 시 V-7은 grep 1회로 축소) | V-3, V-6 |
| **C** (Normal Code) | V-1 + V-2 + V-3 + V-5(compliance Sonnet) + V-7 + V-8 | V-6 (plan에 `(quality-review)` 없으면 생략) |
| **D** (Complex/Cross-cutting) | V-1 ~ V-8 **전체** (V-5는 compliance Sonnet) | 생략 없음 |

**Task Type 미명시** → D로 간주 (안전 우선).
**V-4(PostToolUse hook)는 자동 실행** — 모든 Type에서 작동 (UTF-8 + impact-warn).
**V-9(시각 충실도)는 Type과 무관하게 조건부** — plan에 Step 2.5 시각 요소 분해 표가 있는 디자인 정합 작업일 때만 수행 (없으면 모든 Type에서 생략).
**V-5·V-6 병렬** — Type D(및 `(quality-review)` 플래그가 붙은 Type C)에서 V-5(compliance)·V-6(quality)는 동일 BASE/HEAD에 병렬 호출하고, 둘 다 OK일 때만 진행한다 (상세는 V-5).

#### Type A 빌드 판단
- 순수 문서·주석·README·`.gitignore` 등 **빌드에 영향 없는 파일** → V-1도 skip, V-8만.
- `.csproj`/`build.gradle`/`package.json` 등 **빌드 구성에 영향 주는 설정** → V-1 빌드 실행.

#### Type B prefilter PASS 시 V-7 축소
- spec-prefilter(Haiku)가 PASS → 변경 심볼이 trivial이므로 V-7 caller 재검증을 **변경 심볼 grep 1회**로 축소 (전체 재추적 불필요).
- prefilter가 ESCALATE → 정상 V-5(Sonnet) + V-7 전체 수행.
- **Type 오분류 피드백 (경미)**: spec-prefilter가 Type B task에서 ESCALATE를 반복(여러 task에 걸쳐 잦게)하면 plan의 Type 분류가 실제보다 가볍다는 신호다 — 해당 task는 그대로 진행하되 plan.md `## Deferred / Follow-up`에 "Type 분류 재검토 (prefilter ESCALATE 잦음)"를 1줄 남긴다(다음 계획 단계 강화용, 루프는 멈추지 않음).

### V-1. 빌드
- AGENTS.md의 build 명령 실행. exit 0 확인. 오류 시 Phase I로 1회 복귀 후 재시도.
- **AGENTS.md 없거나 build 명령 미정의** → 표식 파일로 자동 추론:
  - `*.csproj`/`*.sln` → `dotnet build`
  - `build.gradle*` → `./gradlew assembleDebug`
  - `package.json` → `npm run build` (script 있을 때) 또는 skip
  - `pyproject.toml` → `python -m build`
  - `go.mod` → `go build ./...`
  - `Cargo.toml` → `cargo build`
  - 위 어느 것도 아님 → AGENTS.md에 build 명령이 있으면 그것 사용. 없으면 Halt → 사용자에게 build 명령 요청 (또는 `pjc:bootstrap-agents-md`로 AGENTS.md 생성 제안)

### V-2. 테스트
- AGENTS.md의 test 명령 실행. 통과 케이스 수 기록.
- **AGENTS.md 없거나 test 명령 미정의** → 표식 파일 fallback:
  - `*.csproj` → `dotnet test`
  - `build.gradle*` → `./gradlew test`
  - `package.json` (test script 있음) → `npm test`
  - `pyproject.toml` → `pytest`
  - `go.mod` → `go test ./...`
  - `Cargo.toml` → `cargo test`
  - 위 어느 것도 아님 → Halt

### V-3. 린트/정적 분석
- 프로젝트 표준 도구 실행. 신규 경고 0 확인.

### V-4. 자동 검증 hook
- PostToolUse hook 자동 실행 (`check-utf8-and-lines`, `impact-warn`).
- impact-warn 경고 발생 시: caller 파일을 Read로 즉시 열어 영향 검증.
  - 영향 받으면 같은 task에서 함께 수정.
  - 영향 없으면 commit 메시지에 "영향 없음 확인" 명시.

### Reviewer 과부하(529) 대응 — 모든 subagent 호출 공통

reviewer subagent 호출이 **과부하(HTTP 529)로 실패**하면 다음을 따른다 (이 규칙은 V-5/V-6, Phase F-7, plan-feature의 plan-reviewer 등 모든 reviewer 호출에 적용):

1. **짧게 대기 후 재시도** (최대 2회). 일시적 과부하는 대부분 재시도로 해소된다.
2. 재시도도 계속 529면 **모델 등급에 따라 분기**:
   - **Opus reviewer**(`plan-reviewer`, `plan-completion-reviewer`): **Sonnet으로 대체 실행 가능**. 단 *"Opus 과부하로 Sonnet 대체 실행 — 검증 깊이가 평소보다 낮을 수 있음"*을 사용자에게 **명시**하고, 그 reviewer의 결과/완료 보고에 ⚠️ 표시를 남긴다. 중요 게이트(F-7 등)를 건너뛰지 않기 위함이며, 대체로 통과해도 "Opus 미검증 영역 가능"을 plan.md Next Steps에 기록한다.
   - **Sonnet reviewer**(`spec-compliance-reviewer`, `code-quality-reviewer`): **Haiku 대체 금지** (검증 신뢰도가 크게 떨어짐). 재시도가 모두 실패하면 사용자에게 *"검증 subagent가 과부하로 실행 불가 — 잠시 후 재시도 / 이번은 자체 검증으로 진행 / 대기"* 중 선택을 요청한다. 자체 검증으로 진행하더라도 그 사실을 보고에 명시한다.
   - **Haiku reviewer**(`spec-prefilter`, `explorer`): 재시도만. 계속 실패하면 해당 단계의 상위 흐름(Sonnet reviewer 직접 호출 등)으로 진행한다.
3. **모델 대체·검증 생략은 항상 사실을 명시한다** (투명성). 검증이 평소보다 약화됐다는 신호를 사용자가 알 수 있어야 한다 — 조용히 대체하지 않는다.

### V-5. Spec Compliance Review (subagent 필수)

Task Type에 따라 다른 흐름:

**Type B**: `spec-prefilter` (Haiku) 먼저 호출.
- PASS → V-5 완료, **V-7(축소)·V-8 진행** (Type B는 V-6 생략 — Sonnet 호출 안 함. Fast-Path 표와 일치).
- ESCALATE → `spec-compliance-reviewer` (Sonnet) **단독** 호출 (Type B ESCALATE도 V-6 생략 → 병렬 대상 아님). BLOCKER/MAJOR → Phase I 복귀·수정 후 재호출, MINOR → follow-up, OK → V-7로.

**Type C/D**: `spec-compliance-reviewer` (Sonnet) 호출.
- 전달: task ID, plan.md 해당 섹션, BASE_SHA, HEAD_SHA.
- **V-6이 함께 수행되는 경우(Type D 항상, Type C는 plan Type 라인에 `(quality-review)`가 있을 때)에는 V-5(compliance)와 V-6(quality)를 동일 BASE_SHA·HEAD_SHA에 병렬(한 turn 동시) 호출한다.** 두 리뷰는 독립 read-only라 동시 실행해도 충돌이 없다. V-6을 생략하는 경우(플래그 없는 Type C, 기본)는 V-5만 단독 호출.
- **둘 중 하나라도 BLOCKER/MAJOR → Phase I로 복귀, 수정 후 (수행된) 리뷰를 다시 병렬 재실행.** 둘 다 OK/MINOR일 때만 다음 단계 (MINOR → follow-up 등록). **follow-up 등록은 최종 통과 run 기준** — 중간 run에서 본 MINOR는 최종 run에서 재평가하며(수정으로 위치가 바뀔 수 있음), 중간 결과로 중복 등록하지 않는다.
- 두 리뷰는 항상 **최종 diff에 전체 수행** — 어느 것도 생략·약화하지 않는다 (단 아래 529 인프라 장애 fallback은 예외이며, 그 경우 약화 사실을 반드시 명시한다). 실패 경로에서 V-6이 재실행되는 토큰 비용은 품질 우선으로 감수한다.
- **529 과부하는 각 reviewer에 독립 적용** — 병렬 중 한쪽만 529면 그 reviewer만 "Reviewer 과부하(529) 대응" fallback을 따른다 (다른 쪽 결과 유지).
- **reviewer가 "incomplete"(turn 예산 소진 등으로 acceptance 일부만 검토)로 응답하면 통과(OK)로 보지 않는다** — 미검토 항목을 메인이 diff에서 직접 대조(해당 acceptance가 충족되는 위치 지목)하거나 reviewer를 재호출해 나머지를 마저 검토한 뒤에야 다음 단계로 간다. incomplete를 조용히 OK 처리하고 다음 task로 넘어가는 것은 금지. (Phase G의 incomplete 처리 원칙을 per-task V-5/V-6에도 동일 적용 — Type B ESCALATE의 spec-compliance-reviewer 호출 포함 모든 reviewer 응답에 적용.)

### V-6. Code Quality Review (subagent, Type D 항상 · Type C는 `(quality-review)` 플래그 시) — V-5와 병렬 수행
- `code-quality-reviewer` subagent 호출 (위 V-5에서 **병렬로 함께 호출**). 자체 검토 금지.
- 검토 기준: DDD, 환각, 한글 주석, 파일 응집도(1500은 분리 검토 신호), UTF-8, 보안, 동시성.
- 결과 처리: V-5와 통합 — 둘 중 하나라도 BLOCKER/MAJOR면 수정 후 둘 다 재실행, 둘 다 OK일 때만 진행.

### V-7. Caller Re-verification

변경된 모든 public/internal 심볼에 대해:
- `grep -rn "\b<symbol>\b"` 실행.
- hit 위치가 모두 diff에 포함되어 있거나, 변경 영향 없음이 명백한가.
- 누락 발견 → Phase I 복귀.

빌드가 통과해도 잡는 cross-file 마지막 관문.

**Type B + prefilter PASS 시 축소**: 변경 심볼이 trivial하므로 변경한 심볼에 대한 grep 1회만 수행 (전체 심볼 재추적 생략). impact-warn hook(V-4)이 이미 자동 검출했으므로 중복을 줄인다.

### V-8. Self-Honesty Check

Phase D 진입 직전 자기 정직성 검증. 모두 "예"여야 진행 가능:

- [ ] 빌드 명령을 실제로 실행했고 exit 0을 봤는가?
- [ ] 테스트 명령을 실제로 실행했고 통과 수를 봤는가?
- [ ] (V-3 수행 task) 신규 린트 경고 0을 실제로 확인했는가? — 리뷰 지적 수정 후에도 재확인.
- [ ] acceptance 각 항목에 대해 diff 어디서 충족되는지 지목할 수 있는가?
- [ ] 변경한 심볼의 caller가 모두 함께 갱신되었는가?
- [ ] "동작 확인됨" 주장의 근거가 빌드 통과 외에 있는가?
- [ ] 이 task에서 추측으로 작성한 코드가 하나도 없는가?
- [ ] 수정한 코드의 주석·docstring이 새 동작과 일치하는가 (옛 내용 그대로 둔 stale 주석이 없는가)?

하나라도 "아니오" → Phase I 복귀.

**자기기만 패턴**: "아마 동작할 것이다", "테스트는 안 돌렸지만 빌드 통과했으니 OK", "비슷한 코드를 본 적 있어서 맞을 것" → Phase I 즉시 복귀.

### V-9. 시각 충실도 검증 (디자인 정합 작업만)

plan에 Step 2.5의 **시각 요소 분해 표가 있을 때만** 수행한다 (디자인 정합 작업이 아니면 건너뜀).

1. **요소 전수 대조**: 분해 표의 각 요소·속성을 구현 결과와 하나씩 대조한다. 공유·재사용 컴포넌트도 빠짐없이 — "행만 맞추고 헤더·검색·칩은 맞겠지" 금지. 표의 "현재 값"·"일치" 칸을 실제 구현으로 채운다.
2. **빌드 ≠ 시각 일치를 명시**: 빌드 통과·테스트·코드리뷰는 **CSS 시각 충실도를 검증하지 못한다** (폰트 크기, 간격, 정렬, 아이콘 유무, 레이아웃 어긋남은 빌드가 못 잡는다). 따라서 빌드만으로 "디자인과 동일"을 선언하지 않는다.
3. **시각 확인 처리**:
   - 렌더 캡처가 가능하면(로그인 불필요·캡처 환경 있음) 디자인과 캡처를 요소별로 대조하고 결과를 표에 기록.
   - **렌더 확인이 불가하면**(로그인 필요·캡처 환경 없음) 작업을 멈추지 말고 진행하되, 완료 보고에 **⏳ HUMAN-VERIFY: "시각 충실도는 빌드로 미검증 — 화면을 직접 확인 필요"**를 분해 표와 함께 명시한다. "동일하게 맞췄다"고 단정하지 않는다.
4. 분해 표에서 ❌(불일치)가 남아 있으면 Phase I로 복귀해 수정 후 재대조한다.

> 핵심: "디자인과 동일하게"는 화면 전체를 요소 단위로 대조하고 렌더로 확인해야 하는 작업이다. 일부만 보고 "맞겠지"로 끝내면 사용자가 볼 때만 어긋남이 드러난다.

### 재시도 한계 (Halt 트리거 — 무한 루프 차단)
- 같은 task에서 **동일 BLOCKER/MAJOR 3회 연속** → Halt (reviewer의 RECURRING 태그 포함).
- 같은 task에서 **리뷰 지적(BLOCKER/MAJOR) 수정 사이클 누적 5회** → Halt (매번 다른 지적으로 도는 무한 수정 루프 방지).
- 이 둘 + 나머지 카운터(checkpoint 복구 2회·빌드 5회 연속 실패), **카운터 영속화**(plan.md `## Retry Ledger`에 기록해 auto-compact·재개에서 그 값부터 이어 셈 — G5), 상세 복구 절차는 모두 `references/recovery.md`에 일원화(단일 출처).

## Phase D — Done

```bash
git add -A
git commit -m "T<N>: <한 줄 요약>

<변경 요약>
Type: <A/B/C/D>
Build: <명령> → OK
Tests: <X/Y passed>
Review: spec OK (prefilter: <PASS/ESCALATE→OK>), quality <OK/SKIPPED>
Caller-recheck: <확인한 심볼 수>개 심볼, 누락 0
Self-honesty: PASS
Elapsed: <Hm Ms> | Turn ~<N>
"
```

**plan.md 체크박스 갱신 (매 task, 필수)**: 이 task의 본체 체크박스를 `[ ]`/`[/]` → `[x]`로 바꾼다. 이는 재개 시 미완료 task 식별의 1차 신호이므로 **task 완료마다 즉시** 갱신한다(Progress Log는 2 task마다지만 체크박스는 매 task). 이 단계를 빠뜨리면 재개('재개 진입')에서 체크박스가 전부 `[ ]`로 남아 git log·Progress Log와 어긋난다. 글로벌 CLAUDE.md에도 동일 규칙이 있으나, 이 스킬은 그에 의존하지 않고 자체적으로 강제한다.

진행 보고 (각 task 1줄, 사용자 확인 요청 금지):
```
✅ T<N> 완료 (<N>/<TOTAL>)  →  T<N+1> 시작
   Type: <A/B/C/D> | Tests: <X/Y> | Phase V: <적용 단계 요약>
   Elapsed (cumulative): <Hm Ms> | Turn ~<N>
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

컨텍스트 과밀 시 압축 대비 체크포인트(절대 규칙 4), Halt 보고, 그리고 Phase F 통과 최종 보고 시 plan.md의 `## Next Steps`에 다음을 기록:

```markdown
## Next Steps
- 권장 다음 액션: <명확한 한 줄> (예: T7부터 implement-task 재개 / PR 생성 후 /code-review 호출)
- Suggested skills: <쉼표 구분> (예: pjc:implement-task, 공식 /code-review, 공식 /security-review)
- 위키 갱신 (llm-wiki 사용 중이고 이 프로젝트가 등록돼 있을 때만): 위키 반영 여부는 F-6.5에서 **능동적으로 사용자에게 묻는다**(여기 Next Steps에 묻어두는 것으로 대체하지 않음). 동의 시 `pjc:llm-wiki` 절차 B를 별도 세션에서 진행 (구현 세션은 위키 직접 수정 안 함).
```

목적: ① 압축 직후의 Claude 자신이 plan.md만 읽고 정확히 재개할 수 있게 함 (압축 생존의 핵심), ② Halt·완료 시 종철님이 plan.md만 보고도 무엇을 호출할지 즉시 알 수 있게 함. handoff 패턴 차용.

### 🚫 금지 표현

- "T2 진행할까요?"
- "다음 작업으로 넘어가도 될까요?"
- "이대로 진행해도 괜찮을까요?"
- "T1 완료. 계속할까요?"
- "확인 부탁드립니다."
- "Phase 2 진행할까요?" / "다음 단계로 넘어갈까요?" / "2단계 시작할까요?" / "Step 2 진행할까요?"

→ 대신 "✅ T1 완료 (1/10) → T2 시작" 후 **즉시** T2 진행.

## Phase F — Finalize (모든 task 완료 후)

전체 plan 통합 검증. **진입 조건표(1 task+Type A=생략 / 1 task+Type B=F-1·F-2·F-6만 / 2+ tasks·Type C·D=전체 F-1~F-7)와 F-1~F-7 상세는 모두 `references/phase-f-detail.md`에 일원화.**

- 단, **F-6.5(notes 기록 + 오래된 항목 아카이브 이동)는 Phase F가 생략·축소돼도 코드 변경이 있었으면 항상 수행**한다(빌드 영향 없는 trivial 단일 수정은 공통 지침의 문서 갱신 생략 조건을 따름) — 누락 빈발 지점이라 본문에 남긴다.
- F-7은 `plan-completion-reviewer` subagent (Opus) 호출 — plan 전체 적대적 검토.

## Phase G — 요구 재검증 (PRD 있을 때만)

**진입 조건**: plan.md 상단의 `**PRD**: <경로>` 줄이 있으면 그 경로의 PRD로 진입한다 — 이 줄이 "이 작업의 PRD"를 가리키는 **단일 신호**다(plan-template 규약: PRD 없으면 줄 자체를 생략). **줄이 없으면 이 작업엔 PRD가 없는 것으로 보고 Phase G를 진입하지 않는다**(Phase F가 최종). `docs/prd.md`·`docs/prds/`에 PRD 파일이 있어도 줄이 없으면 진입하지 않는다 — 레포에 남은 무관한(과거·다른 작업의) PRD를 자기 작업 PRD로 오인해 거짓 미충족(전부 BLOCKER)을 보고하고 자율 루프를 교란하는 것을 막기 위함이다. (대규모 작업인데 PRD를 만들고도 줄을 빠뜨린 경우는 plan-reviewer가 plan 단계에서 경고로 잡는다.)

Phase F는 "plan.md에 적힌 것"을 검증한다. Phase G는 한 단계 위 — **"plan.md가 PRD 요구를 빠뜨리지 않았는가"** 를 검증한다.

### G-1. PRD 전수 대조

> **F-7 결과 재사용 (역할 경계)**: 바로 앞 Phase F-7의 `plan-completion-reviewer`가 PRD가 있으면 이미 FR/NFR 전수 대조를 수행했다(그 reviewer 역할에 포함 — agent 정의 참조). 그 판정(충족/미충족)을 **입력으로 받아** 여기서는 갭 처리(G-2~G-4)에 집중한다 — 동일 대조를 처음부터 반복하지 않는다. 단 reviewer가 turn 부족 등으로 PRD 대조를 미완료했으면(보고에 "incomplete" 표시) 누락 FR만 메인이 보완 대조한다.

**REMOVED FR은 제외**: PRD에서 `~~취소선~~`/`REMOVED` 표시된 FR(또는 `## 폐기 이력` 섹션의 항목)은 이미 폐기된(코드에서 제거된) 기능이므로 대조 대상이 아니다 — 미충족이어도 BLOCKER가 아니며, 자율 루프가 이를 다시 구현하려 시도하지 않는다(삭제된 기능을 되살리는 거짓 재구현 차단). **active FR/NFR만** 아래 절차로 대조한다.

active PRD의 각 FR/NFR에 대해:
1. 해당 요구를 구현한 task와 commit이 존재하는가? (plan.md task의 FR 역참조 + git log)
2. **검증 방법을 기계 검증 가능 여부로 구분하여 처리한다:**
   - **기계 검증 가능** (테스트·CLI 실행·파일 확인·grep): 실제 실행하고 출력을 근거로 기록.
   - **기계 검증 불가** (GUI 조작, 시각 확인, 사용자 체감): **절대 "확인했다"고 적지 않는다.** 대신 ⏳ `HUMAN-VERIFY`로 표기하고, 가능한 간접 근거(관련 단위 테스트 통과, 바인딩 코드 존재 지목)만 기록한다. GUI 동작을 실행해 보지 않고 "표시 확인됨"이라 쓰는 것은 환각이다.
3. 결과를 표로 기록:

```markdown
| PRD ID | 우선순위 | 충족 | 근거 |
|--------|---------|------|------|
| FR-1 | Must | ✅ | T2 (commit abc123), MemoServiceTests 5/5 통과 |
| FR-2 | Must | ⏳ HUMAN-VERIFY | 자동저장 단위테스트 통과, 단 실제 UI 체감은 사용자 확인 필요 |
| FR-3 | Should | ❌ | 매칭 task 없음 — plan에서 누락 |
```

- `HUMAN-VERIFY` 항목은 미충족(❌)이 아니다 — 기계로 가능한 검증은 모두 통과했고 사람 확인만 남은 상태. 최종 보고의 "사용자 확인 필요" 목록으로 모아 제시한다.
- `HUMAN-VERIFY`를 ✅로 둔갑시키는 것은 V-8 자기기만 패턴과 동일한 위반이다.

### G-2. 갭 처리 — 자율 재루프

미충족 항목 발견 시:

| 우선순위 | 처리 |
|---|---|
| **Must 미충족** | plan.md에 새 task 추가 (`T<N+1> (FR-x 충족)`) → **Phase P부터 자율 재진입** (사용자 확인 불필요 — PRD가 이미 승인된 요구이므로) |
| Should 미충족 | 사용자에게 보고: "지금 진행 A / follow-up B" 선택 |
| Could 미충족 | follow-up 등록만, 재루프 없음 |
| **요구 자체가 바뀌어야 함** (FR이 현실과 안 맞거나 변경 필요) | plan/코드를 임의로 바꾸지 않는다. **사용자에게 PRD 변경 제안 → 승인 → PRD 갱신 → plan 조정** 순서. PRD를 두고 구현만 어긋나게 바꾸는 것은 금지 |

새 task도 동일한 P→I→V→D 루프 + 해당 task 완료 후 G-1 재대조.

### G-3. 종료 조건 (무한 루프 방지)

- **Phase G 재루프는 최대 2회.** 2회 후에도 Must 미충족이 남으면 Halt — 아래 형식으로 보고하고 사용자 지시를 기다린다. **그냥 끝내거나 완료 선언하지 않는다.**
- 같은 FR이 2회 연속 미충족이면 즉시 Halt (구현 접근 자체가 잘못됐을 가능성 — 재시도는 헛돎).
- PRD 범위를 벗어나는 새 요구 발견은 추가하지 않는다 (Out of Scope 가드). follow-up으로만 기록.

#### 한도 도달 Halt 보고 형식 (의무)

```markdown
## ⚠️ Phase G 재루프 한도 도달 (2회)

**충족**: <FR-1 ✅, FR-2 ✅, ...>
**미충족 (Must)**: <FR-x — 한 줄 설명>

**시도 이력** (같은 실패 반복 방지용 — plan.md에도 기록)
- 1차: <접근> → <실패 양상>
- 2차: <다른 접근> → <실패 양상>

**원인 분석**: <왜 안 됐는지 — 추정이면 추정이라고 명시>

선택해 주세요:
A) 다른 접근으로 1회 더 시도 (제안: <구체적 새 접근>)
B) <FR-x>를 follow-up으로 미루고 현재 상태로 완료 처리
C) <FR-x> 요구 자체를 조정 (예: <현실적 대안>)
D) 직접 지침 제공
```

- 시도 이력은 plan.md의 Progress Log에도 기록한다 — 새 세션에서 같은 접근을 반복하지 않도록.
- A 선택 시 사용자가 승인한 새 접근으로 1회만 추가 시도. 또 실패하면 재차 이 보고로 복귀 (자동 재시도 없음).

### G-4. 최종 보고에 PRD 충족표 포함

Phase G 통과 시 최종 보고에 G-1 표 전체 + Must 충족률 100% 명시.

### 최종 보고 (Phase F 통과 후 — PRD 있으면 Phase G까지 통과 후)

> **권한 경계 (필독).** 최종 보고 = 루프의 종착점이자 첫 사용자 개입 지점. 여기서 **멈춘다.** push·main 병합·태그·릴리즈·PR은 루프 권한 밖이라, 사용자가 그 행위를 명시 승인하기 전에는 하지 않는다. '진행'·'승인' 같은 답이라도 **직전 질문이 '구현'에 관한 것이었다면 그 범위는 구현이며 push/릴리즈 승인이 아니다** — 외부 작업은 **별도로**, 행위를 이름으로 적어 다시 묻는다(예: "이제 origin/main에 push하고 v1.x.x 릴리즈를 발행할까요?"). 구현 승인 질문에 이 작업들을 묶지 않는다. (절대 규칙 12)

```markdown
## 🎉 모든 task 완료 + Phase F 통과 (+ Phase G 통과, PRD 있을 때)

**Plan**: <plan.md 경로>
**Tasks**: <N>/<TOTAL> 완료

**Summary of changes**
- T1 (Type <A/B/C/D>): <한 줄>
- ...

**Phase F 결과**
- F-2 전체 빌드: OK
- F-2 전체 테스트: <X/Y passed>
- F-7 plan-completion-reviewer: OK (또는 MINOR n개 follow-up 등록)

**Phase G 결과 (PRD 있을 때만 — G-1 충족표 전체 포함)**
- Must: <n>/<n> 충족 (기계 검증)
- 재루프: <0-2>회
- ⏳ 사용자 확인 필요 (HUMAN-VERIFY): <FR-x UI 체감, ...> ← 기계 검증 불가 항목, 직접 확인 부탁

**Execution stats**
- Elapsed (total): <Hm Ms>
- Turns: ~<N>
- Type 분포: A=<n>, B=<n>, C=<n>, D=<n>
- Prefilter PASS율 (Type B): <n/n>

**Follow-ups** (있으면)
- <항목 1>

**분할 plan 안내** (plan.md 상단에 `**다음 plan**:` 또는 `**이전 plan**:` 표식이 있을 때만)
- `**다음 plan**:` 있음 (이 plan = 분할 첫 part) → "**남은 분할 plan**: `<다음 plan 경로>` — `pjc:implement-task`로 별도 실행 필요 (전체 기능의 후반부)"를 명시한다.
- `**이전 plan**:`만 있음 (마지막 part) → "분할 plan 완료 (part1+part2 전체 구현됨)"을 안내한다.

**여기서 멈춥니다.** push·main 병합·태그·릴리즈·PR 등 외부로 나가는 작업은 자율 루프 권한 밖이라 각각 별도 승인이 필요합니다 — 필요하면 그 행위를 이름으로 적어 따로 여쭙겠습니다 (예: "이제 push·v1.x.x 릴리즈 할까요?"). 어떻게 진행할지 알려주세요.
```

## 참조 문서

- 중단 조건 + 보고 양식: `references/halt-conditions.md`
- 복구 메커니즘: `references/recovery.md`
- 안티패턴 표: `references/antipatterns.md`
- Phase F 상세: `references/phase-f-detail.md`
