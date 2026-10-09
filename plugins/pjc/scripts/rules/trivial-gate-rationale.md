# `write-gate-trivial` 판정 근거

> `write-gate-trivial.ps1`의 주석에서 옮긴 판정 근거다. 스크립트에는 각 자리에 이 문서의 절을 가리키는 1줄만 남겼다.
> **문면을 요약하지 않고 이동만 했다** — 이관은 이동이지 요약이 아니다.

## §1 write-gate-trivial.ps1 — 작은 변경 통과 판정

```
# write-gate-trivial.ps1 — 작은 변경 통과 판정 (dot-source 전용, hook 아님)
#
# `guard-write.ps1`이 dot-source해 호출한다. 통과 조건에 맞으면 **이 함수가 직접 exit 0**으로
#   프로세스를 끝낸다 — 원본에서도 같은 자리에서 exit 했고, 반환값으로 바꾸면 호출부가
#   그 값을 잊었을 때 게이트가 조용히 열린다.
#
# 근거는 `rules/write-gate-rationale.md`의 「§12 작은 변경 통과」·「§15 신규 파일 Trivial 통과」.
```

## §2 새 정의 감지 — 언어별 형태

**종전 세 정규식은 접두 키워드가 있는 정의만 잡았다** — `class`·`interface` 류, 접근 제한자로 시작하는 메서드, `def`·`func`·`fun`·`function`. 그래서 아래 다섯 형태는 3줄 이하면 「새 정의 없음」으로 plan 없이 통과했다(2026-10-09 실측 — 표본 18줄 중 이 다섯 형태 10줄이 전부 미검출). 이것은 미탐 보완이다(`AGENTS.md` 「DO NOT」의 허용 범주).

| 형태 | 적용 확장자 | 예 |
|---|---|---|
| Rust `fn` | `.rs` | `fn parse(s: &str) -> i32 {` · `pub fn run<T>(x: T) {` |
| Go 리시버 메서드 | `.go` | `func (r *T) Name() int {` — 리시버 괄호가 이름 앞에 와서 `func\s+\w+\s*\(` 에 안 걸렸다 |
| 화살표 함수·함수식 대입 | JS/TS 6종 | `const f = (a) => …` · `let h = x => …` · `export const g = async () => {` |
| 이름만 있는 메서드 | JS/TS 6종 | `render() {` · `async load(id: string): Promise<void> {` |
| 반환형만 있는 메서드 | `.cs .java .c .cpp .cc .h .hpp` | `void Foo() {` · `int Bar(int x) {` · 올맨식 `void Foo()` 다음 줄 `{` |

**확장자를 가리는 이유** — 같은 문형이 다른 언어에서는 정의가 아니다. Swift `VStack(spacing: 8) {`·Kotlin `repeat(3) {` 는 이름만 메서드 형태와, Go `go func() {`·`defer func() {` 는 반환형만 메서드 형태와 글자가 같은 호출·클로저다(2026-10-09 계획 리뷰 지적). 그 언어들은 각자의 `func`·`fun` 규칙으로만 판정한다.

**두 메서드 규칙을 좁히는 장치는 셋이다** — ① 줄 머리 앵커 ② 첫 단어가 제어·문장 키워드면 제외(`if`·`for`·`while`·`switch`·`catch`·`return`·`new`·`else`·`await`·`throw`·`using`·`lock`·`var` 등 — 목록은 스크립트의 정규식 원문이 정본) ③ 인자 괄호 안에 괄호가 없을 것 — `describe('x', () => {`·`useEffect(() => {`·`it('x', function () {` 처럼 콜백을 넘기는 호출이 여기서 걸러진다.

**실증** — 골든 `scenarios/guard-write.ps1` 의 `(SYM1~11)` 양성과 `(SYMN1~28)` 델타 음성. 음성은 새 규칙이 실제로 발화할 수 있는 같은 확장자의 제어문·호출문이다. 계획 단계에서 로컬 레포 7개(1,052파일)에 돌려 규칙마다 무작위 30건을 판독했다.

**알려진 오검출** — ① Rust 문자열 리터럴 안의 `fn` (`"fn one() -> usize { 1 }"` — 판독 표본 30건 중 1건) ② 반환형만 메서드 규칙이 생성자 정의(`public FolderEditDialog()`)도 잡는다 — 접근 제한자를 반환형 자리로 읽기 때문이다. 생성자도 새 정의라 판정은 맞고, 종전 제한자 규칙은 반환형과 이름을 둘 다 요구해 생성자를 놓쳤다. 둘 다 plan 검사로 넘어갈 뿐 편집을 영구히 막지 않는다.

**놓치는 형태** — 인자에 괄호가 든 정의(`foo(a = f()) {`) · 튜플 반환형(`(int, int) Foo()`) · 클래스 필드 화살표(`foo = () => …`, `const` 없음) · 익명 `export default function () {` · 위 확장자 밖 언어(Ruby·PHP·Dart 등)의 접두 키워드 없는 정의.

## §3 요청 단위 누적 판정

**3줄 기준은 `Edit` 호출 1회를 잰다 — 그래서 큰 변경을 3줄씩 나눠 고치면 매번 통과했다.** `pjc:plan` 의 「계획 없이 바로 편집한다 — 단 요청된 변경이 하나일 때만」을 hook 이 강제하지 못한 구멍이다. 이것은 미탐 보완이다(`AGENTS.md` 「DO NOT」의 허용 범주).

**단위는 사용자 요청 1건이다** — transcript 에서 마지막으로 나온 `"promptId":"…"` 값이 지금 요청이다. 그 필드는 user 줄(사람 프롬프트·tool_result)에만 실리고 사람 프롬프트마다 바뀐다(2026-10-09 실측 — 최근 transcript 60개 중 58개 보유). 세션 전체로 세면 긴 세션에서 서로 무관한 작은 수정이 쌓여 걸리고, 시간 창은 요청 경계와 무관하다.

**임계는 서로 다른 파일 3개째 또는 trivial 통과 4회째(같은 파일 포함) 중 먼저 닿는 쪽이다** — 파일 수는 여러 곳으로 번지는 변경을, 횟수는 한 파일을 나눠 고치는 변경을 잡는다(사용자 답). 센 것은 Edit trivial 통과 둘(3줄 이하 · 스타일 파일 값 치환)이고 신규 파일 Write 는 세지 않는다. **`pjc:plan` description 의 「바꾸는 값의 종류가 하나뿐인 단순 치환은 몇 곳이든 직접 편집」도 셋째 파일에서 걸린다** — 계획이 불필요하다는 판정은 그대로이고 면제 표식 절차가 붙을 뿐이다(사용자 답 「본문만 보강」 — `plan/SKILL.md` 「이 스킬을 건너뛰는 경우」).

**임계를 넘으면 차단하지 않고 `exit 0` 만 건너뛴다** — 함수가 반환하면 `guard-write` 가 plan 존재 → PLAN-EXEMPT → 차단 순으로 이어 판정한다. 새 `exit 2` 지점을 만들지 않아 차단 경로 수가 그대로이고, plan 이 있거나 표식에 적힌 파일은 기존 경로대로 통과한다. 차단될 때는 메시지에 「trivial 누적」 사유 줄이 붙어 「3줄인데 왜 막혔나」를 읽게 한다.

**판정 근거를 못 얻으면 fail-open 이다** — transcript 경로 없음 · 읽기 실패 · 꼬리 64KB(없으면 4MB) 안에 `promptId` 없음 · 상태 파일 쓰기 실패면 누적하지 않고 오늘처럼 통과시킨다. 이 판정은 통과를 *닫는* 쪽이라, 근거 없이 닫으면 오늘 통과하던 편집이 이유 없이 막힌다(`write-gate-rationale.md` 「§6 발동 흔적 판정 — pjc:plan」의 fail-open 과 같은 방향 · `plan-exempt-rationale.md` 「§23 PLAN-EXEMPT 면제 판정」의 fail-closed 는 통과를 *여는* 판정이라 반대다).

**기록** — `<홈>/.claude/.state/trivial-tally/<promptId>` 한 파일에 통과마다 대상 경로 한 줄(소문자 · `/` 정규화)을 덧붙인다. 홈은 `USERPROFILE`, 비면 `$HOME` 이다(`session-context.ps1` 과 같은 폴백 — 비 Windows 에서 cwd 아래에 폴더가 생기지 않게). 30일 지난 파일은 세션 시작에 `session-context.ps1` 이 걷는다(`session-context-rationale.md` §38 — 차단 hook 쪽에 정리 코드를 새로 넣지 않는다). 새 `.ps1` 을 만들지 않은 것은 `rules/harness-hooks.json` 보호 목록에 올라 `guard-harness` 범위가 바뀌기 때문이다.

**비용** — trivial 통과 후보에서만 꼬리를 한 번 읽는다. 256KB 콜드 253ms · 4MB 콜드 229ms(둘 다 프로세스 첫 IO 가 지배 · 웜 1~10ms) — 현행 hook 1.3~2.3s 대비 최대 약 +20%(2026-10-09 실측).

**실증** — 골든 `scenarios/guard-write.ps1` 의 `(TT1~7)`: 파일 임계 차단 · 횟수 임계 차단 · 임계 직전 통과 · 새 요청 재시작 · plan 있으면 통과 · 표식 있으면 통과 · `promptId` 없으면 fail-open. 갈래마다 고유 `promptId` 를 쓴다(그룹이 격리 홈 하나를 함께 쓴다).

**무엇을 막지 못하는가** — ⓐ 백그라운드 작업 알림(task-notification)도 새 `promptId` 를 받아 요청 경계가 된다(실측 402건 전부) ⓑ `loop-continue` 등 hook 이 넣는 이어가기 턴의 `promptId` 동작은 미측정 ⓒ 서브에이전트 편집의 hook 입력 `transcript_path` 가 무엇을 가리키는지 모름 — 부모 요청에 묶이거나 fail-open 이 된다 ⓓ 마지막 user 줄이 4MB 보다 큰 tool_result 뒤에 묻히면 fail-open ⓔ 한 요청 안의 편집이 임계 미만(파일 2개·3회)이면 여전히 나눠 통과한다 — 기준을 더 낮추지 않은 것은 사용자 답이다.

