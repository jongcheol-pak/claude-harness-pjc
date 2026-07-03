---
type: feature
project: x
category: personal
feature_name: "경로검사"
platform: windows-desktop
status: active
origin: agent-synthesized
confidence: medium
updated: 2026-07-02
tags: [feature, path]
---
# 경로검사 (path)

## 개요
§7-20·21 실존 검사 픽스처 — 부재 경로 2건(각주 `src/Gone.cs`·관련 파일 `src/AlsoGone.cs`)은 WARN,
실재 경로(`src/Real.cs`)는 무경고여야 한다.

## 관련 파일
- `src/Real.cs` — 실재 (무경고 기대)
- `src/AlsoGone.cs` — 부재 (WARN 기대)

## 구현 방법
Real 클래스가 처리한다[^src-x].

[^src-x]: 픽스처 각주 — `src/Gone.cs`
