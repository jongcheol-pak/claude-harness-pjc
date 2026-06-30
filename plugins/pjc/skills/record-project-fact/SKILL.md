---
name: record-project-fact
description: This skill should be used when recording a CONFIRMED project fact (build/run command, DB access method, file/artifact location, test/verify command) into an EXISTING AGENTS.md — either right after the suggest-agents-record hook emits "[AGENTS 기록 제안]" and the user accepts, or when the user explicitly asks to record such a fact. Triggers on "AGENTS.md에 기록", "프로젝트 사실 기록", "빌드 명령 기록해줘", "이 명령 AGENTS에 추가", "DB 접근법 적어둬", "테스트 명령 기록", or accepting the hook's suggestion. Do NOT trigger for: creating a new AGENTS.md from scratch (use bootstrap-agents-md), turning hooks on/off (use harness-toggle), planning or writing code (plan-feature/implement-task). Records into AGENTS.md ONLY — never the global/project CLAUDE.md — and ONLY after showing the exact change and getting user approval (no silent writes). Real secrets/connection strings/credentials are forbidden — environment variable names only.
argument-hint: "(자동 — hook 제안 수락 또는 사용자 요청)"
---

# Record Project Fact

작업 중 **확인된 프로젝트 사실**(빌드·실행 명령, DB 접근 방법, 파일·산출물 위치, 테스트·검증 명령)을
**기존 `AGENTS.md`에 추가·갱신**한다. 다음 작업부터 같은 정보를 재발견(grep·파일 읽기)하지 않게 하는 것이 목적이다.

> AGENTS.md는 세션 시작 시 자동 로드되므로, **한 번 기록하면 다음 세션부터 재확인이 사라진다.**
> 이 스킬은 "기록 측"만 담당한다(소비 측은 자동 로드가 이미 해결).

## 언제 작동하나

| 시점 | 경로 |
|---|---|
| `suggest-agents-record` hook이 `[AGENTS 기록 제안]`을 띄움 | 사용자에게 "기록할까요?" 묻고, **승인 시** 이 스킬로 기록 |
| 사용자가 직접 "이 명령 AGENTS.md에 기록해줘" 등 | 이 스킬로 기록 |

bootstrap-agents-md(최초 생성)·harness-toggle(hook on/off)·plan-feature/implement-task(코드 작업)와 **역할이 다르다** — 이 스킬은 **이미 있는 AGENTS.md에 사실을 누적**하는 전담이다.

## 절대 규칙 (Hard Rules)

1. **승인 없이 쓰지 않는다.** 기록 전, **어느 섹션에 무엇을 추가/갱신하는지** 정확히 보여주고 사용자 승인을 받은 뒤에만 Edit한다. hook 제안은 "기록 제안"일 뿐 자동 기록 위임이 아니다.
2. **AGENTS.md만 대상.** 프로젝트 루트의 `AGENTS.md`에만 기록한다. **글로벌/프로젝트 `CLAUDE.md`는 수정하지 않는다**(지침 파일이라 위험).
3. **실제 시크릿 금지.** DB 연결 문자열·비밀번호·API 키·토큰·내부 IP/호스트를 기록하지 않는다. **환경변수 이름·설정 키 이름만** 적고 실제 값은 `.env`(gitignore)로. (예: `접속: 환경변수 DB_CONNECTION` — 실제 문자열 금지.)
4. **확인된 사실만.** 직접 실행·확인한 명령/경로만 기록한다. 추측("아마 이 명령일 것")은 기록하지 않는다.
5. **중복은 추가가 아니라 갱신.** 같은 항목이 이미 있으면 새 줄을 늘리지 말고 기존 줄을 갱신한다.
6. **AGENTS.md가 없으면** 먼저 `pjc:bootstrap-agents-md`로 생성을 안내한다(이 스킬은 갱신 전담 — 생성은 bootstrap 몫).

## 기록 대상 → AGENTS.md 섹션 매핑

| 사실 종류 | 대상 섹션 | 비고 |
|---|---|---|
| 빌드·실행 명령 | `## Build & Test` | 기존 섹션 보강 |
| 테스트·검증 명령 | `## Build & Test` | 기존 섹션 보강 |
| DB 접근 방법 | `## 데이터 접근` | 없으면 `## Build & Test` **뒤에** 신설 |
| 파일·산출물 관리 | `## 산출물·파일 관리` | 없으면 `## Repository Structure` **뒤에** 신설 |

> 섹션 신설 위치는 bootstrap 템플릿과 동일하게 맞춘다(데이터 접근=Build & Test 뒤, 산출물·파일 관리=Repository Structure 뒤). 섹션이 이미 있으면 그 안에 항목을 추가/갱신한다.

## 실행 절차

### Step 1. AGENTS.md 확인
- 프로젝트 루트 `AGENTS.md`를 Read. 없으면 → "AGENTS.md가 없습니다. `pjc:bootstrap-agents-md`로 먼저 생성하시겠어요?" 안내 후 종료.

### Step 2. 기록 내용 구성
- 기록할 사실을 위 매핑 표에 따라 섹션·항목으로 정리.
- 대상 섹션이 없으면 신설 위치를 정한다.
- 시크릿이 섞여 있으면 환경변수 이름으로 치환(규칙 3).
- 같은 항목이 이미 있으면 갱신안으로(규칙 5).

### Step 3. 변경안 제시 + 승인 (게이트)
```
다음을 AGENTS.md에 기록합니다:

[섹션] ## Build & Test
[추가] - Test: dotnet test tests/

기록할까요? [Y/수정/취소]
```
- `Y` → Step 4. `수정` → 사용자 지시 반영 후 다시 제시. `취소` → 종료.

### Step 4. Edit 후 보고
- AGENTS.md를 Edit(추가 또는 갱신). 섹션 신설 시 매핑 표의 위치 규칙을 따른다.
- UTF-8(BOM 없음) 유지, 기존 문구·다른 섹션 불변(최소 변경).
- "기록 완료: `<섹션>`에 `<항목>` 추가/갱신" 보고.

## 출력 형식

```markdown
## 📝 record-project-fact

**대상**: AGENTS.md
**기록 내용**:
- [<섹션>] <추가/갱신할 항목>

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
| AGENTS.md 없는데 새로 만들어 기록 | bootstrap-agents-md로 안내 |
