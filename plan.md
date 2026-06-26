# plan.md — 분할 PRD 귀속 빈틈 보강 (방안 ①+②)

## Goal
PRD 파일이 여러 개로 분할됐을 때 "새 작업을 어느 PRD 파일에 귀속시킬지 / 같은 요구가 이미 있는지" 판정하는 절차가 없는 **쓰기(귀속) 측 빈틈**을, ① 단일 `docs/prd.md` 기본화로 빈틈 발생을 억제하고 ② PRD 작성 전 기존 PRD 확인·귀속 판정 절차를 추가해 메운다.

## 배경 — 영향 범위 전수 조사 결과 (확인 완료)
PRD 시스템은 두 측으로 나뉘며, 한쪽만 빈틈이다:

- **읽기(식별) 측 — 이미 견고 (수정 불필요).** `plan.md`의 `**PRD**:` 줄이 "이 작업의 PRD" 단일 진실. 4곳이 일관:
  - `plan-feature/references/plan-template.md:32` — `**PRD**:` 줄 규약
  - `implement-task/SKILL.md:432` — Phase G가 이 줄로만 진입(레포의 다른 PRD는 의도적 무시)
  - `agents/plan-reviewer.md:184` (12-a/12-b) — 줄 없으면 자동 대조 안 함
  - `agents/plan-completion-reviewer.md:25` — 줄 기준, 없으면 대조 생략
- **쓰기(귀속) 측 — 빈틈 (이번 수정 대상).**
  - `plan-feature/SKILL.md` Step 0.5 (PRD 절차, L156~165) — 초안 작성만, "기존 PRD가 여러 개일 때 어디에 쓸지" 분기 없음
  - `prd-template.md` 원칙 6 (L72) — 중복 FR 검사 범위가 "한 파일 내"로 암묵 한정
  - `prd-template.md` 원칙 7 (L73) + 위치 규약 (L5~8) — "쪼개라"만, 쪼갠 뒤 귀속 매칭 부재 + 단일/누적을 동등 제시

## 결정 (사용자 확정)
- **채택 = 방안 ①+② 조합, 방안 ③(INDEX.md) 제외.**
  - ① 단일 `docs/prd.md`를 기본으로 못박아 빈틈 발생 자체를 억제 (대부분의 pjc 사용처는 단일로 충분).
  - ② 그래도 분할되는 큰 경우를 위해 PRD 작성 전 기존 PRD 확인·귀속 판정 절차 추가.
  - ③ INDEX 매핑표는 새 산출물=drift 동기화 부담 + pjc "과한 추상화·불필요 레이어 금지" 철학과 충돌 → 미도입.
- **방안 ② 위치 = Step 1이 아니라 Step 0.5 (PRD 절차) 안.** 귀속 판정은 PRD가 있는 대규모 작업에만 필요하므로, 일반 컨텍스트 수집(Step 1)이 아닌 PRD 전용 절차(Step 0.5)에 둔다 (사용자 원안 "Step 1"에서 조정 — 승인 시 확정).
- **implement-task/SKILL.md·reviewer 2개·plan-template.md는 수정하지 않는다.** 읽기 측은 이미 견고하고, ①+②는 쓰기 측 보강이라 읽기 측 규약을 건드릴 이유가 없다(범위 확장 회피).
- **README.md 미커밋 1줄(hook 설명)은 무관 잔재 → 그대로 두고 진행** (T1·T2는 README 미수정, 커밋 단위 안 섞임). **단 T3에서 버전 bump를 선택하면 README가 수정되므로**, 그 경우 stale 1줄을 먼저 별도 처리(별도 커밋 또는 사용자 위임)해 커밋 단위를 분리한다(m1 대응).

## Impact Analysis (전수 확인)
- 수정 파일 **2개**, 둘 다 마크다운 지침 문서. 코드·시그니처·DI 영향 0.
  - `plugins/pjc/skills/plan-feature/references/prd-template.md` — 위치 규약(L5~8), 원칙 6(L72), 원칙 7(L73). 기존 원칙 번호 1~8 불변(문구 보강만).
  - `plugins/pjc/skills/plan-feature/SKILL.md` — Step 0.5 PRD 절차에 "0번 단계" 추가. 기존 1~5번 절차 불변(앞에 0번 prepend), 다른 Step 불변.
- **상호 참조 정합(중요)**: Step 0.5 새 0번 단계가 prd-template 원칙 6/7을 참조하므로 두 파일 문구가 일치해야 한다(T2가 T1 문구를 인용). T1 먼저, T2 나중.
- **읽기 측 무손상 확인**: `**PRD**:` 줄 = 단일 진실 규약을 건드리지 않으므로 plan-template·implement-task·reviewer 2개의 동작 불변. (역대조에서 재확인)
- 자동 생성·lock 파일 아님. 버전(plugin.json) 영향: 지침 문서 변경이므로 버전 bump 여부는 T3에서 판단.

## 작업 단계 (T1·T2 문서, T3 버전/문서)

### T1 — prd-template.md: 단일 기본화(①) + 중복 검사 범위 확장(②)  [Type A]
대상: `plugins/pjc/skills/plan-feature/references/prd-template.md`
- **① 위치 규약 (L5~8)**: "단일 또는 누적"을 동등 제시 → **"기본은 `docs/prd.md` 단일, 분할은 원칙 7 임계 초과 시에만 쓰는 예외"** 로 명문화. 분할 경로의 `<slug>`를 `<기능군>`으로 통일(원칙 7과 일치).
- **① 원칙 7 (L73)**: "PRD가 커지면 분할"의 기조를 **"기본은 단일 파일 유지, 분할은 단일 파일이 너무 커져 Phase G 대조가 얕아질 때의 마지막 수단"** 으로 강화. 임계(40항목/250줄) 유지. **"분할하면 작성 시 원칙 6 + Step 0.5의 기존 PRD 확인이 필수가 된다"** 는 연결 문장 1줄 추가(②와 묶음).
- **② 원칙 6 (L72)**: 중복 FR 검사 대상을 **"기존 FR(active + REMOVED) + PRD가 분할돼 여러 파일이면 분할된 다른 PRD 파일까지"** 로 확장. "한 파일만 보면 다른 조각의 같은 요구를 놓친다"는 이유 1줄.
- **Edge cases (Type A·문서)**: ⓐ 기존 원칙 번호 1~8 불변(문구만 보강) ⓑ 폐기 이력/부활(원칙 5·8) 규약과 모순 없음 ⓒ 위치 규약 예시 코드블록(L7) 형식 유지.
- **Halt Forecast**: 없음.
- Acceptance:
  1. 위치 규약에 "기본=단일 docs/prd.md, 분할=예외" 취지 문구 존재 + 분할 경로가 `<기능군>` 표기.
  2. 원칙 7에 "기본 단일 유지·분할은 마지막 수단" 기조 + "분할 시 원칙 6/Step 0.5 필수" 연결 문장.
  3. 원칙 6에 "분할된 다른 PRD 파일까지 중복 확인" 문구.
  4. 원칙 번호 1~8 개수·순서 불변, 폐기/부활(5·8) 규약 잔존.
  5. UTF-8(BOM 없음), 마크다운 표·코드블록 구문 깨짐 없음.

### T2 — plan-feature/SKILL.md: Step 0.5에 기존 PRD 확인·귀속 판정 절차 추가(②)  [Type A]
대상: `plugins/pjc/skills/plan-feature/SKILL.md` (Step 0.5 "대규모 작업 PRD 절차" L156~165)
- 현재 1~5번 절차 **앞에 0번 단계 prepend**:
  > `0.` **기존 PRD 확인·귀속 판정 (초안 작성 전 필수)** — 새 PRD를 만들기 전에 `docs/prd.md`와 `docs/prds/`를 확인한다:
  > - 기존 PRD 없음 → 신규 `docs/prd.md` 작성(원칙: 단일 기본).
  > - 기존 PRD 있고 이번 작업이 그 연장 → **새 파일 만들지 말고 기존 PRD를 갱신**(새 FR은 새 ID로, 원칙 4·8). 같은 요구가 이미 active/REMOVED FR에 있으면 중복 생성 금지(원칙 6).
  > - 분할된 PRD가 여러 개(`docs/prds/`) → 이번 작업이 속하는 **기능군 파일을 찾아 그 파일을 갱신**. 어느 기능군에도 안 맞는 새 기능군이면 새 분할 파일 생성(원칙 7). 중복 확인은 분할된 **모든** PRD 대상(원칙 6).
  > - 어느 PRD를 갱신/생성하든 그 경로를 plan.md 상단 `**PRD**:` 줄에 적어 이 작업의 PRD로 지목(읽기 측 단일 진실 — implement-task Phase G 진입 신호).
- 기존 1~5번은 번호만 유지(0번이 앞에 붙음). 다른 문장·Step 불변.
- **Edge cases**: ⓐ "대규모가 아니면 Step 1로" 분기(L154) 위쪽이므로 비-대규모 작업엔 영향 0 ⓑ 원칙 4·6·7·8 참조 번호가 T1의 prd-template와 일치하는지 확인 ⓒ `**PRD**:` 줄 규약 문구를 plan-template과 모순 없이 인용.
- **Halt Forecast**: 없음.
- Acceptance:
  1. Step 0.5 PRD 절차에 "0. 기존 PRD 확인·귀속 판정" 단계 존재(초안 작성 1번보다 앞).
  2. 4갈래(없음/연장/분할 다수/새 기능군) 판정 + `**PRD**:` 줄 지목 문장 포함.
  3. 참조 원칙 번호(4·6·7·8)가 T1 수정 후 prd-template과 일치.
  4. 기존 1~5번 절차 문구 잔존(누락 0), 다른 Step 불변.
  5. UTF-8(BOM 없음), frontmatter·마크다운 구문 정상.

### T3 — 버전·문서 갱신 판단  [Type A]
- `notes.md`: 본 작업(분할 PRD 귀속 빈틈 ①+② 보강) 항목 추가 — 무엇·왜·어떻게·검증.
- `plugin.json`·`README.md` 버전: **patch bump 1.66.0 → 1.66.1 확정(사용자 승인)**. plugin.json version + README 버전 줄(L10) 수정. README 기능 목록은 변경 없음(현 기능 그대로) → 버전 줄 외 미변경.
- **m1 대응(커밋 단위 분리)**: bump로 README를 수정하므로, 작업 트리에 남은 README stale hook 1줄이 같은 commit에 섞이지 않게 **commit 직전 사용자에게 처리 확인**(별도 커밋/위임 — 되돌리기는 변경 손실이라 Claude가 직접 실행 안 함). T1~T3 파일 수정·검증은 자율, commit 전 멈춰 m1 + commit 승인.
- Acceptance: notes.md에 본 작업 항목 1건; (bump 시) plugin.json·README 버전 일치, JSON 파싱 OK.
- Halt Forecast: 버전 bump 여부 미정 → 구현 중 결정 분기 발생 시 사용자 확인(아래 승인 항목).

## 검증 방법
1. **문구 반영 grep**: T1 3개 변경점(위치/원칙6/원칙7) + T2 0번 단계 — 각 acceptance 문구를 grep으로 확인.
2. **역대조(읽기 측 무손상)**: plan-template.md `**PRD**:` 규약, implement-task SKILL.md:432, plan-reviewer.md:184, plan-completion-reviewer.md:25 — 수정 전후 **변화 없음** 확인(이번에 안 건드림 → grep로 잔존 확인).
3. **상호 참조 정합**: T2가 인용한 원칙 번호(4·6·7·8)가 T1 수정 후 prd-template 실제 번호와 일치.
4. **인코딩·구문**: 두 파일 BOM 없음, 마크다운 표·코드블록·frontmatter 깨짐 없음.
5. **역대조 표**: 방안 ①(위치·원칙7)·②(원칙6·Step 0.5 0번) 각 항목이 산출물에 실제 존재하는지, ③(INDEX) 흔적이 없는지 대조.

## Out of Scope (이번 제외)
- **방안 ③ (docs/prds/INDEX.md 매핑표)** — 영구 제외(사용자 결정). 새 산출물 동기화 부담 + pjc 철학 충돌.
- **implement-task/SKILL.md, plan-template.md, plan-reviewer.md, plan-completion-reviewer.md 수정** — 읽기 측은 이미 견고. ①+②는 쓰기 측 보강이라 불필요.
- **방안 ② 강제 검증을 reviewer에 추가** — 이번엔 절차 명문화까지만. reviewer 강제는 별도 작업(Deferred).
- **README.md 미커밋 1줄(hook 설명)** — 무관 잔재, 그대로 둠.

## Deferred / Follow-up
- **분할 파일 간 중복 FR의 검토 단계 강제 net (m2)**: ①+②는 작성 시점 예방(write-side)만 메운다. plan-reviewer 12-a의 중복 FR 검사는 `**PRD**:` 줄이 가리키는 **단일 파일만** 읽으므로, 분할된 다른 파일 간 중복은 리뷰에서 안 잡힌다. 빈틈을 완전히 닫으려면 후속 plan에서 `plan-reviewer.md` 12-a의 PRD 로딩을 "분할 시 `docs/prds/` 동기 형제 파일까지 스캔"하도록 보강. (이번 범위는 절차 명문화까지 — 의식적 분리.)

## 승인 필요 항목
- 본 plan(문서 2파일 보강 + notes/버전) — **승인 완료**(사용자).
- T3 버전 bump — **patch bump 1.66.1 확정**(사용자).
- commit/push 및 GitHub 릴리즈(v1.66.1) — 구현·검증 후 별도 승인. commit 직전 m1(README stale 줄) 처리 확인.

## Progress Log
- T1 완료 (Type A, 미커밋): `prd-template.md` — ① 위치 규약 "기본=단일 `docs/prd.md`, 분할은 예외"로 명문화(분할 경로 `<기능군>` 통일), 원칙 7 "분할은 마지막 수단" 강화 / ② 원칙 6 중복 검사 "분할된 다른 PRD 파일까지" 확장. 작성원칙 번호 1~8 순서 유지.
- T2 완료 (Type A, 미커밋): `plan-feature/SKILL.md` Step 0.5 PRD 절차에 "0. 기존 PRD 확인·귀속 판정" 단계 추가(없음/연장/분할 다수/새 기능군 4갈래 + `**PRD**:` 줄 지목). 인용 원칙 4·6·7·8이 T1 후 prd-template과 정합 확인.
- T3 완료 (Type A, 미커밋): `plugin.json`·`README.md` 1.66.0 → 1.66.1, `notes.md` 본 작업 항목 추가.
- **검증**: 문구 grep 전부 반영, 두 수정 파일 BOM 없음, plugin.json JSON 유효, 읽기 측 4파일(implement-task/SKILL·plan-reviewer·plan-completion-reviewer·plan-template) git status 미수정(무손상). plan-reviewer OK(BLOCKER/MAJOR 0, MINOR 2: m1 plan 반영·m2 Deferred).
- **미커밋 상태**: commit/push·릴리즈는 별도 승인 대기. commit 직전 m1(README stale hook 1줄) 처리 확인 필요.

## Next Steps
- 권장 다음 액션: commit 전 m1(README stale 줄) 처리 확인 → commit/push 승인 → push 후 GitHub 릴리즈(v1.66.1, release-on-version-bump).
- Suggested skills: (커밋 후) 공식 /code-review, 공식 /security-review.
