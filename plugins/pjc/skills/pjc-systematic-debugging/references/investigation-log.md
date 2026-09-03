# 조사 로그 서식

> `pjc-systematic-debugging`의 조사 결과를 `plan.md`(또는 별도 `debug-<날짜>.md`)에 남기는 형식.
> **조사를 시작할 때 이 서식을 열어 그대로 채운다** — 빈 칸이 곧 아직 안 한 일이다.

```markdown
# Debug: <증상 요약>

## Symptom
<무엇이 어떻게 잘못되는가>

## Reproduction
<재현 절차 — 다른 사람이 따라할 수 있게>

## Phase 1 — Evidence
- Error: <메시지 핵심 단서>
- Stack: <핵심 프레임>
- Recent changes: <git log 요약>
- Failing layer: <어디서 실패>

## Phase 2 — Hypotheses
- H1: <가설> — 예측: <무엇을 바꾸면 증상이 사라지나/악화되나> — 검증: <어떻게> → 결과: ✅/❌/⚠️
- H2: ...

## Phase 3 — Root Cause
<왜 그것이 원인인지 메커니즘 설명>

## Phase 4 — Fix
- Test added: <테스트 파일:케이스>
- Change: <파일:라인 + 한 줄 요약>
- Defense in depth: <선택, 있다면>

## Verification
- Build: OK
- Tests: <X/Y>
- Manual repro: 더 이상 재현 안 됨
```

## 가설 작성 예

**예측 필드가 가설을 반증 가능하게 만든다.** "무엇을 바꾸면 증상이 사라지거나 악화되는가"를 미리 못 적으면 그 가설은 아직 모호하다는 신호다 — 검증할 것이 없기 때문이다.

```
WRONG: H1: 캐시가 문제인 것 같다 — 검증: 캐시를 본다
RIGHT: H1: 만료된 캐시 항목을 stale로 반환한다 — 예측: TTL을 0으로 두면 증상이 사라진다 — 검증: TTL=0으로 재현 시도
```

## Phase 1-D 경계 로깅 예 (WinUI 3 — "데이터가 화면에 안 보임")

```csharp
// 레이어 1: API/Repository
_logger.LogInformation("[Repo] Fetched count={Count}", items.Count);
// 레이어 2: Application/Domain
_logger.LogInformation("[Domain] After filter count={Count}", filtered.Count);
// 레이어 3: ViewModel
_logger.LogInformation("[VM] Items.Count={Count}", Items.Count);
// 레이어 4: View binding — XAML 디버깅 출력 또는 Live Visual Tree
```

이러면 **어느 레이어가 실패하는지** 드러난다(예: Repo ✓ → Domain ✓ → VM ✗ → 바인딩 문제).

## 경량 경로를 썼을 때

**보고에 「경량 경로」를 명시하고 어떤 단계를 왜 생략했는지 적는다.** 위 서식에서 `## Phase 2 — Hypotheses`·`## Phase 3`을 비우는 대신 한 줄로 대체한다:

```markdown
## 경량 경로
- 근거: <컴파일러/스택트레이스가 짚은 파일:라인:원인>
- 생략: Phase 1-B~1-D · 2 · 3 (원인이 이미 확정)
```
