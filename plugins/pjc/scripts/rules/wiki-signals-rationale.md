# `session-wiki-signals` 판정 근거

> `session-wiki-signals.ps1`의 주석에서 옮긴 판정 근거다. 스크립트에는 각 자리에 이 문서의 절을 가리키는 1줄만 남겼다.
> **문면을 요약하지 않고 이동만 했다** — 이관은 이동이지 요약이 아니다.

## §1 session-wiki-signals.ps1 — 세션 시작 주입의 위키 신호 3종

```
# session-wiki-signals.ps1 — 세션 시작 주입의 위키 신호 3종 (dot-source 전용, hook 아님)
#
# `session-context.ps1`이 dot-source해 호출한다. 별도 파일인 이유는 이 셋만 **vault를 훑기 때문**이다 —
#   허브 파일 전수 스캔·git rev-list·pending.md 파싱이라 판정 입력이 다른 신호들과 완전히 다르다.
#
# 반환: @{ VaultLine; StaleLine; FeedbackLine } — 각 항목은 주입할 1줄이거나 $null이다.
# 근거는 `rules/session-context-rationale.md`의 위키 관련 절들.
```

