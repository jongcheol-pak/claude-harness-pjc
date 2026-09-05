---
name: pjc-systematic-debugging
description: Use whenever the user reports a bug, test/build failure, runtime error, exception, crash, unexpected behavior, performance regression, memory leak, race condition, deadlock, or CI/CD issue. Triggers on Korean (버그/에러/오류/예외/크래시/안 됨/동작 안 함/이상해/왜 이래/왜 안 돼/이상한 현상/테스트 실패/빌드 실패/재현/디버깅) and English (bug/fix/debug/error/exception/crash/fails/broken/regression). Root cause investigation is mandatory before any patch. If the compiler/stack trace pinpoints the cause (file·line·reason) and the fix is a small single-file change, use the lightweight path, not a skip. Not for non-bug "fix" requests (reformatting/renaming — trivial edits, not debugging). Skip ONLY when the user explicitly asks to apply a fix they already diagnosed ("그냥 이 한 줄만 수정해줘, 원인 다 안다"). pjc/DDD-integrated variant (regression-test-first fix, spec-compliance review, cross-project llm-wiki lookup); prefer over generic systematic-debugging in pjc projects.
argument-hint: "<버그 또는 에러 설명>"
---

# Systematic Debugging

## Iron Law (절대 원칙)

> **근본 원인을 찾기 전에는 어떤 수정도 시도하지 않는다.**
> 증상 수정(symptom patch)은 실패다.

**추측으로** 원인을 정한 채 Phase 4로 건너뛰지 않는다 — 원인은 증거로 확정돼야 한다. 근거는 `references/debugging-rationale.md` §1.

### 경량 경로 (원인이 이미 확정된 경우)

다음을 **모두** 만족하면 축약한다:

- **컴파일러/스택트레이스가 원인을 특정**한다 — 파일·라인·원인이 메시지에 그대로 드러난다(예: `CS0103: 'foo' 없음`, `NullReferenceException at File.cs:42`의 명백한 미초기화). 추측이 아니라 **도구가 원인을 짚어 준 경우**다.
- **수정이 단일 파일·소규모**다(다중 파일 파급·설계 변경 없음).

**1-A + Phase 4**로 축약하고(1-B~1-D·2·3 생략) **보고에 「경량 경로」를 명시**한다 — 서식은 `references/investigation-log.md`.

**수정 중 다중 파일 파급이 드러나거나 원인이 처음 판단과 불일치하면 즉시 표준 경로로 승격한다**(§2). 조건을 하나라도 못 채우면 처음부터 표준 4단계다.

## Phase 1 — 근본 원인 조사

**Phase 1 완료 전에는 수정 코드를 작성하지 않는다.**

### 1-A. 에러 메시지·스택트레이스 정독

- 에러 메시지를 **처음부터 끝까지** 읽는다. 첫 줄만 보고 추측하지 않는다.
- 스택트레이스는 **최하단**(가장 깊은 호출)부터 분석한다.
- 예외 체인(`InnerException`·aggregate)을 모두 펼친다.
- 메시지의 모든 식별자(파일명·클래스명·라인)를 코드에서 확인한다.

### 1-B. 재현 + 피드백 루프

- **신뢰성 있게 재현 가능한 절차**를 확보한다. 산발적이면 빈도를 측정한다.
- 최소 재현 케이스로 좁힌다.
- **재현에서 멈추지 말고 피드백 루프까지 만든다** — "이 버그에서만 레드로 가는 자동 pass/fail 신호". 조사의 최우선 지렛대이며 루프 유형 5종과 근거는 §3.
- 절차를 조사 로그(`references/investigation-log.md`)에 기록한다.

**재현 불가능하면** 아래 가설을 각각 검증한다 — 환경 차이(OS·런타임 버전·시간대·로케일·권한) · 타이밍 의존(race·부팅 직후·첫 실행) · 데이터 의존(특정 입력) · 외부 시스템 상태(DB row·네트워크).

### 1-C. 최근 변경 검사

명령은 `references/investigation-log.md`의 「최근 변경 검사 명령 (1-C)」에 있다.


검사 대상: 최근 커밋 · 설정 파일 · 의존성 버전(lock 파일) · 환경 변수 · 빌드 파이프라인.

### 1-D. 컴포넌트 경계 증거 수집

**무엇이 문제인지** 추측하지 말고 **어디가 문제인지**부터 확인한다. 각 컴포넌트 경계에서 들어오는 데이터·나가는 데이터·환경 설정 값·레이어 상태를 로깅한다(예시는 `references/investigation-log.md`).

먼저 증거를 모으고, **그 다음에** 분석한다.

### Phase 1 통과 조건

**1-A~1-D를 모두 마쳐야 Phase 2로 간다** — 넷 중 하나라도 답을 못 적으면 그 항목으로 돌아간다.

## Phase 2 — 패턴 분석

### 2-A. 유사 사례 검색

- 같은 에러가 코드베이스 다른 곳에서 어떻게 처리되는가? 동일 라이브러리/API를 쓰는 다른 모듈은 정상인가?(차이가 단서) git log에 비슷한 수정 이력이 있는가?
- **코드베이스 조사는 `grep`으로 직접 훑는다** — 대상이 특정돼 있으면 직접 읽는 편이 빠르고 정확하다.
- **위키 교차 검색**(vault 있을 때) — 같은 증상·에러를 다른 프로젝트가 이미 해결했는지 찾는다. **스킬을 발동하지 말고 `llm-wiki/references/lookup-rules.md` 하나를 Read한다**(절차 K, read-only). vault 판정은 `../WIKI.md` 0절, 검색 순서·재구현 원칙·`deprecated` 제외는 §8이 정본이다.

### 2-B. 가설 후보 작성

여러 가설을 **나열**하고 각각에 **예측**(무엇을 바꾸면 증상이 사라지나/악화되나)과 검증 방법을 붙인다 — **예측을 못 적으면 그 가설은 아직 모호하다는 신호다.** 서식·좋은 예와 나쁜 예는 `references/investigation-log.md`.

**가장 그럴듯한 하나에만 매몰되지 않는다.** Occam's razor는 좋지만 빠른 결론은 디버깅의 함정이다. 가설이 둘 이상이면 각 가설의 관련 심볼·호출부·설정을 `grep`으로 직접 찾는다 — **가설의 검증·판정은 위임하지 않는다.**

### Phase 2 통과 조건

- [ ] 최소 2개 이상의 가설이 있고, 각각의 검증 방법이 정의됨
- [ ] 가설 중 하나가 "환경/타이밍/외부"라면, 내부 원인 가설을 적어도 하나 더 작성

> **단일 원인 확정 예외** — 증거가 단일 원인을 확정적으로 지목하면 가설 1개로 통과한다(§5).

## Phase 3 — 가설 검증

각 가설을 **최소 변경**으로 검증한다. 수정이 아니라 **진단**이다.

### 3-A. 진단 우선

**각 프로브는 특정 가설을 겨냥한다** — 심기 전에 "이 프로브가 어느 가설을 확정/기각하는가"를 먼저 정한다(§4).

가설 검증 수단: 임시 로그(예측이 성립하는 지점 **한 곳**에) · 단위 테스트 · breakpoint · 격리된 작은 스크립트.

**아직 수정 코드(fix)를 작성하지 않는다.**

### 3-B. 검증 결과 기록

가설마다 ✅ 확정 / ❌ 기각(이유 명시) / ⚠️ 부분 기여로 표기한다. **가설이 모두 기각되면 Phase 1로 복귀한다** — 증거가 부족했다는 신호다.

### 3-C. 진단 코드 정리

영구 유지할 가치가 있는 것만 남기고(defense-in-depth) 나머지는 제거한다.

### Phase 3 통과 조건

- [ ] 근본 원인이 명확히 특정되었는가?
- [ ] **왜** 그것이 원인인지 설명할 수 있는가? (메커니즘 이해)
- [ ] 단순 상관관계가 아니라 인과관계인가?

## Phase 4 — 수정 구현

**Phase 1–3을 모두 통과한 뒤에만 진입.**

### 4-A. 회귀 테스트 먼저

수정 코드 **전에** 실패 케이스를 재현하는 테스트를 작성한다(RED) → 수정으로 통과시킨다(GREEN) → 필요하면 리팩토링.

이렇게 해야 수정이 실제로 효과 있는지 객관적으로 증명되고 재발이 자동 차단된다. 테스트가 어려운 경우(UI·환경 의존)는 수동 재현 절차를 조사 로그에 남긴다.

> **RED 예외** — 버그가 빌드·컴파일 실패면 RED를 먼저 만들 수 없다. 대체 절차는 §6.

### 4-B. 최소 수정

근본 원인에만 직접 대응한다. 무관한 리팩토링·서식 변경 금지. **변경 범위가 plan의 task 범위를 넘으면 Halt.**

### 4-C. 방어 심층화 (선택)

**재발 가능 시나리오가 있을 때만** 다른 레이어에 입력 검증·단언·로깅을 더한다. "혹시 모르니" 식의 광범위한 방어는 YAGNI 위반이다.

### 4-D. 검증

`pjc:implement`의 검증 절차를 따른다 — 빌드 / 테스트 / 변경 파일에 해당하는 정적 검사.

- **4-A에서 버그를 재현하던 회귀 테스트가 통과하는지 확인한다** — 이것이 이 수정의 유일한 직접 증거다.
- 이번 수정이 건드린 심볼의 **다른 사용처가 여전히 성립하는지** 확인한다.
- **수정마다 리뷰 서브에이전트를 부르지 않는다**(§7).

### 4-E. 위키 기록 (선택)

vault·등록 **두 판정을 순서대로** 거친 뒤에만 제안한다(§9) — 이번 버그의 **증상·근본 원인·해결책**을 `pjc:llm-wiki` 절차 B로 반영할 것을 제안한다. 디버깅 세션은 위키를 직접 쓰지 않는다.

**`[SYMPTOM]` 큐잉(자동)** — 근본 원인이 확정·검증된 이 시점에서 이 증상↔원인 매핑이 재사용 가치가 있으면 절차 K 5-5의 큐에 1줄 append한다. 형식·제약은 §10.

## Phase 4.5 — 아키텍처 의심

**같은 버그를 3회 이상 고쳤는데 재발하거나, 한 곳을 고치니 다른 곳이 깨지면** Phase 1 로 복귀하지 말고
`references/architecture-doubt.md`의 「아키텍처 의심 (Phase 4.5)」를 읽는다 — 신호 5종과 사용자 보고 절차가 거기 있다.

## 안티패턴

| 안티패턴 | 올바른 행동 |
|---|---|
| **"아마 ~ 때문일 거야"로 수정에 진입** | 증거로 원인을 확정한 뒤 진입 — 아니면 Phase 1로 복귀 |
| **수정 코드가 try-catch로 에러를 가림** | 근본 원인 수정 |
| 빈 catch로 에러 삼키기 | 근본 원인 수정 |
| **우회로 덮기** — 재시도 루프·if 분기로 특수 케이스 회피·버전 다운그레이드·캐시 클리어·재부팅 | 왜 그 상태가 되는지 추적해 원인을 고친다 |
| 테스트 비활성화·주석 처리 | 테스트가 옳고 코드가 틀린지 검증 |
| 에러 메시지에 "Unknown error" 추가 | 메시지를 구체화 |
| "환경 차이" 결론으로 종결 | 환경 차이의 구체적 메커니즘 명시 |
| 프로젝트 로그 관례를 무시한 로그 | 기존 관례 우선(영/한 혼용·구조화 로그 등), 없으면 한글 |

## Halt 조건

다음 발생 시 사용자에게 보고한다:

- 3회 이상 수정 시도 실패 → Phase 4.5 트리거
- 재현이 불가능하고 가설도 모두 검증되지 않음
- 외부 시스템(제3자 API·인프라) 결함으로 좁혀짐
- 보안·데이터 손실 위험이 있는 수정이 필요
- 근본 원인이 다른 사람·팀의 코드에 있음

## See also

- `references/investigation-log.md` — 조사 로그 서식·가설 작성 예·경계 로깅 예
- `references/debugging-rationale.md` — 이 절차가 왜 이렇게 생겼는가
- `../WIKI.md` — vault 판정과 위키 읽기·쓰기 시점
