---
type: guide
guide_kind: recipe
description: "옛 가이드 섹션의 recipe 행 fixture — §3 하위호환 형상 ① 제외(이중 요구 방지) 실증"
platform: cli
origin: human-validated
confidence: high
updated: 2026-08-21
tags: [guide, recipe, demo]
---

# 옛 섹션 레시피 (fixture)

alias가 한글 전용이라 §7-16 대상이면 병기 WARN이 나야 한다. 그러나 마커 없는 vault에서
recipe는 `## 기능별 인덱스`(첫 컬럼 평문)에도 실리므로 옛 섹션 행까지 받으면 이중 요구가 된다 —
그래서 §3 「하위호환 형상」 ①이 `40_guides/recipes/`를 제외한다. 이 fixture가 그 제외를 고정한다.
