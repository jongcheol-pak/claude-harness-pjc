# `session-ledger-signal` 판정 근거

> `session-ledger-signal.ps1`의 주석에서 옮긴 판정 근거다. 스크립트에는 각 자리에 이 문서의 절을 가리키는 1줄만 남겼다.
> **문면을 요약하지 않고 이동만 했다** — 이관은 이동이지 요약이 아니다.

## §1 session-ledger-signal.ps1 — 세션 시작 주입의 Deferred 대장 최고령 신호 (dot-source 전용, hook 아님)

```
# session-ledger-signal.ps1 — 세션 시작 주입의 Deferred 대장 최고령 신호 (dot-source 전용, hook 아님)
#
# `session-context.ps1`이 dot-source해 호출한다. 별도 파일인 이유는 이 신호만 **대장 3파일을 파싱**하기
#   때문이다 — 항목별 날짜 부기를 형식으로 인식하고 미래 날짜를 배제하는 판정이라 다른 신호와 입력이 다르다.
#
# 반환: 주입할 1줄 또는 $null. 호출부가 그 줄을 넣고 `$cwdBaseCount`를 올린다.
# 근거는 `rules/session-context-rationale.md`의 대장 관련 절들.
```

