---
type: question
status: resolved
priority: low
updated: 2026-01-01
tags: [question]
---
# 코드펜스 이모지 제외 확인

이 페이지의 이모지는 코드펜스 안에만 있다 — §7-29는 strip_code로 코드를 제외하므로
아무 WARN도 나면 안 된다(그리고 이 페이지는 다른 검사도 통과해 이름이 출력에 새지 않아야 한다).

```py
print("emoji in code 🚀")
```
