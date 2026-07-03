---
type: feature
project: Demo
category: personal
feature_name: "것"
platform: windows-desktop
status: active
origin: agent-synthesized
confidence: medium
updated: 2026-07-02
tags: [feature, thing, demo]
---
# 것 (thing)

## 개요
데모 기능이다. 픽스처 검증용 최소 feature.

## 관련 파일
- `src/Demo/Thing.cs` — 핵심 로직

## 동작(사용법)
버튼을 누르면 동작한다.

## 구현 방법
Thing 클래스가 처리한다[^src-thing].

## UI·UX
버튼 하나로 구성.

## 관련 지식·레시피
없음.

시크릿 스캔 오탐 방지 확인용(모두 무경고여야 — 코드 꼴·플레이스홀더):
- 코드 꼴 값: password: getUserConfigValue
- 긴 camelCase 식별자(20자+): secret: getUserConfigurationFromEnvironment
- 한글 라벨 코드 꼴: 비밀번호: config.userSecret
- 플레이스홀더: password: YOUR_PASSWORD_HERE

[^src-thing]: [[10_sources/personal/src-demo\|소스: Demo]] — `src/Demo/Thing.cs`
