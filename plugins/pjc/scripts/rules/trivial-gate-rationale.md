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

