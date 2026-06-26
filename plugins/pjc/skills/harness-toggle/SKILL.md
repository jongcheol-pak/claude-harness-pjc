---
name: harness-toggle
description: This skill should be used ONLY when the user explicitly wants to enable, disable, toggle, or check status of pjc harness hooks. Triggers REQUIRE explicit context words "harness" or "hook" combined with on/off/status intent. Examples that SHOULD trigger - "harness 끄기", "harness 켜기", "hook 끄기", "hook 상태", "harness status", "harness 토글", "plan 강제 꺼" (with "강제" indicating hook), "require-plan off", "require-plan on", "evidence 검사 꺼", "utf8 검사 꺼". Examples that should NOT trigger - "이 기능 끄는 코드 만들어줘", "기능 켜기", "버튼 끄기" (those are code changes via plan-feature, not harness toggle). When in doubt, do NOT trigger this skill.
argument-hint: "<hook 이름> <on|off|toggle|status>"
---

# Harness Toggle

개별 harness hook을 런타임에 on/off. **Claude Code 재시작 불필요, settings.json 수정 불필요.**

## 동작 원리

각 hook 스크립트는 시작 시 `~/.claude/.disabled/<hook-name>` 파일 존재 여부를 확인합니다.
- 파일 있음 → 즉시 통과 (검사 안 함)
- 파일 없음 → 정상 검사 수행

이 skill이 그 파일을 만들거나 삭제합니다.

## 토글 가능한 hook

| Hook 이름 | 역할 |
|---|---|
| `require-plan-for-write` | plan.md 없이 코드 Write/Edit 차단 |
| `require-evidence` | Stop 시 증거 없는 완료 경고 |
| `check-utf8-and-lines` | UTF-8/1500라인/한글주석 검사 |
| `impact-warn` | public 심볼 변경 시 caller 경고 |

**`block-destructive` 는 안전상 토글 불가** (파괴적 명령 차단은 항상 동작).

## 실행 매뉴얼

사용자 의도를 파악하고 다음 PowerShell 명령 중 **하나**를 Bash 도구로 실행하세요.

### 상태 확인
사용자 표현: "harness 상태", "hook 상태", "status", "어떤 hook이 켜져 있나"

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\harness-toggle.ps1" "" status
```

### 개별 hook 비활성화
사용자 표현 → hook 이름 매핑:

| 사용자 표현 | hook 이름 |
|---|---|
| "plan 강제 꺼", "plan 차단 꺼", "require-plan off" | `require-plan-for-write` |
| "evidence 꺼", "증거 검사 꺼", "stop 경고 꺼" | `require-evidence` |
| "utf8 검사 꺼", "주석 검사 꺼", "라인 검사 꺼" | `check-utf8-and-lines` |
| "impact 경고 꺼", "caller 경고 꺼", "impact-warn off" | `impact-warn` |

명령:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\harness-toggle.ps1" <hook이름> off
```

### 개별 hook 활성화
"plan 강제 켜" / "require-plan on" 등:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\harness-toggle.ps1" <hook이름> on
```

### 토글
"plan 강제 토글":
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\harness-toggle.ps1" <hook이름> toggle
```

## 사용자에게 알릴 사항

명령 실행 후:
- 결과(이 명령의 stdout)를 그대로 사용자에게 보여줍니다.
- "이 변경은 즉시 반영됩니다. 다음 hook 실행 시부터 적용됩니다." 라고 안내.
- 비활성화한 hook이 있다면 "작업이 끝나면 다시 켜는 것을 권장합니다." 라고 덧붙입니다.

## 안티패턴 (금지)

| 잘못된 동작 | 올바른 동작 |
|---|---|
| `block-destructive` 를 끄려고 시도 | 거부하고 사유 설명 (안전상 토글 불가) |
| settings.json 직접 수정 | 이 skill 사용 |
| 사용자 확인 없이 모든 hook을 한꺼번에 끄기 | 필요한 것만 끄기 |
| 작업 완료 후에도 비활성 상태 유지 | 작업 종료 시 다시 켜기 권장 |

## 예시 대화

```
사용자: "plan 강제 잠깐 꺼줘"
Claude: [Bash 도구로 harness-toggle.ps1 require-plan-for-write off 실행]
        [OFF] require-plan-for-write 비활성화됨
        즉시 반영됩니다. 작업 끝나면 'plan 강제 켜'로 다시 활성화하세요.

사용자: "harness 상태"
Claude: [Bash 도구로 harness-toggle.ps1 "" status 실행]
        [OFF] require-plan-for-write
        [ON]  require-evidence
        [ON]  check-utf8-and-lines
        [ON]  impact-warn
        [ON]  block-destructive (안전상 토글 불가)

사용자: "plan 강제 다시 켜줘"
Claude: [Bash 도구로 harness-toggle.ps1 require-plan-for-write on 실행]
        [ON]  require-plan-for-write 활성화됨
```
