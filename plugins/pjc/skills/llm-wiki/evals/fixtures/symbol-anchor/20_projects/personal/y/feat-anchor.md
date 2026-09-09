---
type: feature
project: y
category: personal
feature_name: "심볼앵커"
platform: windows-desktop
status: active
origin: agent-synthesized
confidence: medium
updated: 2026-09-09
tags: [feature, anchor]
---
# 심볼앵커 (symbol anchor)

## 개요
§7-21 진입점 심볼 픽스처 — 실재 심볼(`AnchorService`)은 무경고, 부재 심볼(`VanishedService`)은
WARN 이어야 한다. 심볼을 안 적은 행(`src/Anchor.cs` 재기재 없이)은 검사 대상이 아니다.

## 관련 파일
- `src/Anchor.cs` — 실재 심볼 (진입점: `AnchorService`)
- `src/Anchor.cs` — 부재 심볼 (진입점: `VanishedService`)

## 구현 방법
AnchorService 가 처리한다[^src-y].

[^src-y]: 픽스처 각주 — `src/Anchor.cs`
