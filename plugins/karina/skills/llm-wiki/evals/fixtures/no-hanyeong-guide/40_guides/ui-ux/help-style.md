---
type: guide
guide_kind: ui-ux
description: "통합 표의 ui-ux 라벨이 한글 전용인 fixture — §7-16 양성 검출 검증"
platform: cross
origin: human-validated
confidence: high
updated: 2026-07-19
tags: [guide, ui-ux, demo]
---

# 도움말 스타일 안내 (fixture)

ui-ux 가이드는 통합 표(`index-guides.md`)의 한 행으로만 검색된다 — 라벨이 한글 전용이면
영문 grep이 못 잡으므로 §7-16이 WARN을 내야 한다. 그 검사가 이 행을 보려면
`is_feat_recipe_row`의 대상 조건이 `40_guides/` 전체를 포괄해야 하고, 이 fixture가 그것을 고정한다.
