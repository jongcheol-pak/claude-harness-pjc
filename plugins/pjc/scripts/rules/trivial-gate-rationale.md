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

