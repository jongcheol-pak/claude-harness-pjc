---
name: record-project-fact
description: This skill should be used when recording a CONFIRMED project fact (build/run command, DB access method, file/artifact location, test/verify command, intentionally untested layers) into an EXISTING AGENTS.md — either right after the suggest-agents-record hook emits "[AGENTS 기록 제안]" and the user accepts, or when the user explicitly asks to record such a fact. Triggers on "AGENTS.md에 기록", "프로젝트 사실 기록", "빌드 명령 기록해줘", "이 명령 AGENTS에 추가", "DB 접근법 적어둬", "테스트 명령 기록", "테스트 비대상 기록", "AGENTS.md에서 이 항목 빼줘", "더 이상 안 쓰는 명령 지워줘", or accepting the hook's suggestion. The fact may be added, updated, or removed. Do NOT trigger for — creating a new AGENTS.md from scratch (use bootstrap-agents-md), planning or writing code (plan-feature/implement-task). Records into AGENTS.md ONLY — never the global/project CLAUDE.md — and ONLY after showing the exact change and getting user approval (no silent writes). Real secrets/connection strings/credentials are forbidden — environment variable names only.
argument-hint: "(자동 — hook 제안 수락 또는 사용자 요청)"
---

# Record Project Fact

작업 중 **확인된 프로젝트 사실**(빌드·실행 명령, DB 접근 방법, 파일·산출물 위치, 테스트·검증 명령, 의도적 테스트 비대상 계층)을
**기존 `AGENTS.md`에 추가·갱신·제거**한다. 다음 작업부터 같은 정보를 재발견(grep·파일 읽기)하지 않게 하고, 틀려진 정보가 남아 오도하지 않게 하는 것이 목적이다.

> AGENTS.md는 세션 시작 시 자동 로드되므로, **한 번 기록하면 다음 세션부터 재확인이 사라진다.**
> 이 스킬은 "기록 측"만 담당한다(소비 측은 자동 로드가 이미 해결).

## 언제 작동하나

| 시점 | 경로 |
|---|---|
| `suggest-agents-record` hook이 `[AGENTS 기록 제안]`을 띄움 | 사용자에게 "기록할까요?" 묻고, **승인 시** 이 스킬로 기록 |
| 사용자가 직접 "이 명령 AGENTS.md에 기록해줘" 등 | 이 스킬로 추가·갱신 |
| 사용자가 "AGENTS.md에서 이 항목 빼줘/제거" 등 (stale·오기록·시크릿 제거) | 이 스킬로 삭제 |

bootstrap-agents-md(최초 생성)·plan-feature/implement-task(코드 작업)와 **역할이 다르다** — 이 스킬은 **이미 있는 AGENTS.md에 사실을 누적**하는 전담이다.

## 절대 규칙 (Hard Rules)

1. **승인 없이 쓰지 않는다.** 기록 전, **어느 섹션에 무엇을 추가/갱신/제거하는지** 정확히 보여주고 사용자 승인을 받은 뒤에만 Edit한다. hook 제안은 "기록 제안"일 뿐 자동 기록 위임이 아니다. 삭제도 동일하게 승인 게이트를 거친다.
2. **AGENTS.md만 대상.** 프로젝트 루트의 `AGENTS.md`에만 기록한다. **글로벌/프로젝트 `CLAUDE.md`는 수정하지 않는다**(지침 파일이라 위험).
3. **실제 시크릿 금지.** DB 연결 문자열·비밀번호·API 키·토큰·내부 IP/호스트를 기록하지 않는다. **환경변수 이름·설정 키 이름만** 적고 실제 값은 `.env`(gitignore)로. (예: `접속: 환경변수 DB_CONNECTION` — 실제 문자열 금지.)
4. **확인된 사실만.** 직접 실행·확인한 명령/경로만 기록한다. 추측("아마 이 명령일 것")은 기록하지 않는다.
4-1. **"의도적 비대상"은 사용자 확인으로만 성립한다.** 테스트가 없는 계층을 발견한 것만으로는 "비대상"이 아니다 — 빠뜨린 것일 수도 있다. **사용자가 의도라고 확인한 경우에만** 기록한다(추측 기록 금지 — 규칙 4의 연장).
5. **중복은 추가가 아니라 갱신.** 같은 항목이 이미 있으면 새 줄을 늘리지 말고 기존 줄을 갱신한다.
6. **삭제는 stale·잘못된·시크릿이 든 항목만.** 더 이상 유효하지 않거나 틀린 항목(예: 바뀐 빌드 명령의 옛 줄), 실수로 들어간 실제 값(연결문자열·비밀번호 등)을 제거할 때만 삭제한다. **멀쩡한 정보를 임의로 지우지 않는다** — 무엇을 왜 지우는지 승인받는다(규칙 1).
7. **AGENTS.md가 없으면** 먼저 `pjc:bootstrap-agents-md`로 생성을 안내한다(이 스킬은 갱신 전담 — 생성은 bootstrap 몫).

## 기록 대상 → AGENTS.md 섹션 매핑

| 사실 종류 | 대상 섹션 | 비고 |
|---|---|---|
| 빌드·실행 명령 | `## Build & Test` | 기존 섹션 보강 |
| 테스트·검증 명령 | `## Build & Test` | 기존 섹션 보강 |
| DB 접근 방법 | `## 데이터 접근` | 없으면 `## Build & Test` **뒤에** 신설 |
| 파일·산출물 관리 | `## 산출물·파일 관리` | 없으면 `## Repository Structure` **뒤에** 신설 |
| 테스트 비대상 계층·의도된 제약 | `## Conventions` | 테스트를 **의도적으로 쓰지 않는 계층**(예: ViewModel·UI 바인딩 — 수동 확인으로 대체), 의도된 UX·기능 제약 등 **"빠뜨린 것이 아니라 그렇게 정한 것"**. 기록해두지 않으면 리뷰어가 "테스트 누락"으로 오판한다(spec-compliance-reviewer 테스트 예외가 이 표기를 근거로 삼는다) |

> 섹션 신설 위치는 bootstrap 템플릿과 동일하게 맞춘다(데이터 접근=Build & Test 뒤, 산출물·파일 관리=Repository Structure 뒤). 섹션이 이미 있으면 그 안에 항목을 추가/갱신한다.

## 실행 절차

### Step 1. AGENTS.md 확인
- 프로젝트 루트 `AGENTS.md`를 Read. 없으면 → "AGENTS.md가 없습니다. `pjc:bootstrap-agents-md`로 먼저 생성하시겠어요?" 안내 후 종료.

### Step 2. 기록 내용 구성
- 기록할 사실을 위 매핑 표에 따라 섹션·항목으로 정리.
- 대상 섹션이 없으면 신설 위치를 정한다.
- 시크릿이 섞여 있으면 환경변수 이름으로 치환(규칙 3).
- 같은 항목이 이미 있으면 갱신안으로(규칙 5).
- 삭제 요청이면 제거 대상 줄을 정확히 특정한다(stale·오기록·시크릿 — 규칙 6). 멀쩡한 항목·다른 줄은 건드리지 않는다.

### Step 3. 변경안 제시 + 승인 (게이트)
```
다음을 AGENTS.md에 반영합니다:

[섹션] ## Build & Test
[추가/갱신/제거] - Test: dotnet test tests/

반영할까요? [Y/수정/취소]
```
- `Y` → Step 4. `수정` → 사용자 지시 반영 후 다시 제시. `취소` → 종료.
- 삭제면 `[제거]`로 표시하고 어느 줄을 왜 지우는지 함께 보여준다.
- **hook 제안 수락 경로 간소화**: 이 스킬이 `suggest-agents-record` hook의 `[AGENTS 기록 제안]`을 사용자가 수락해 발동됐고, 여기서 만든 **변경안이 그 hook 제안 내용과 동일**하면 — 사용자는 이미 그 내용에 동의(수락)한 것이므로 그 수락을 **Step 3 승인으로 간주**하고 Step 4로 진행한다(변경안 제시 자체는 유지 — 무엇을 반영하는지는 보여준다). 즉 **변경안을 보여주되 동일 내용을 다시 "반영할까요?"로 재문답하지 않는다**(이중 확인 제거). 단 변경안이 hook 제안과 **다르면**(스킬이 내용을 보강·수정) 종전대로 승인을 받는다 — 사용자가 동의한 것과 다른 것을 쓰지 않기 위함이다.

### Step 4. Edit 후 보고
- AGENTS.md를 Edit(추가·갱신·제거). 섹션 신설 시 매핑 표의 위치 규칙을 따른다. 삭제는 해당 줄만 제거(다른 줄·섹션 불변).
- UTF-8(BOM 없음) 유지, 기존 문구·다른 섹션 불변(최소 변경).
- "반영 완료: `<섹션>`에 `<항목>` 추가/갱신/제거" 보고.

## 출력 형식

```markdown
## 📝 record-project-fact

**대상**: AGENTS.md
**반영 내용**:
- [<섹션>] <추가/갱신/제거할 항목>

(승인 후) ✅ 기록 완료 — 다음 세션부터 이 정보는 자동 로드되어 재확인이 불필요합니다.
```

## 안티패턴 (금지)

| 잘못된 동작 | 올바른 동작 |
|---|---|
| 승인 없이 AGENTS.md를 바로 Edit | 변경안 제시 → 승인 → Edit |
| 실제 DB 연결 문자열·비밀번호 기록 | 환경변수 이름만 |
| CLAUDE.md 수정 | AGENTS.md만 |
| 같은 명령을 새 줄로 중복 추가 | 기존 줄 갱신 |
| 추측한 명령 기록 | 직접 확인한 것만 |
| 멀쩡한 항목을 임의 삭제 | stale·오기록·시크릿만, 승인 후 제거 |
| AGENTS.md 없는데 새로 만들어 기록 | bootstrap-agents-md로 안내 |
