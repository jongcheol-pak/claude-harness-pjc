---
type: feature
project: x
category: personal
feature_name: "경로없음"
platform: windows-desktop
status: active
origin: agent-synthesized
confidence: medium
updated: 2026-07-02
tags: [feature, relempty]
---
# 경로없음 (relempty)

## 개요
'## 관련 파일' 섹션은 있으나 백틱 경로 항목이 0개 — §7-21 형식 누락을 잡아야 한다.

## 관련 파일
- 핵심 로직은 Thing 클래스가 담당 (경로 백틱 없음)

## 구현 방법
Thing 클래스가 처리한다[^src-x].

[^src-x]: 픽스처용 각주 — `src/X/Thing.cs`
