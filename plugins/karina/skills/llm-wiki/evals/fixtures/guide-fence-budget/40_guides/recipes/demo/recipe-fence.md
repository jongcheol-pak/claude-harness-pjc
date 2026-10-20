---
type: guide
guide_kind: recipe
description: "recipe는 펜스 포함 판정 유지 — 문자 수 예산(8500자) 초과 WARN이 나야 하는 음성 대조 fixture"
platform: cli
origin: agent-synthesized
confidence: medium
updated: 2026-07-19
tags: [guide, recipe, demo]
---

# recipe 펜스 예산 (fixture)

## 목적
recipe(8500자)는 스니펫이 본체라 펜스 내부를 제외하지 않는다 — 이 파일은 펜스 포함 판정으로 예산 초과 WARN이 나야 한다(문자 수 전환 v1.138.0: 펜스 내부 문자가 예산에 카운트됨).

## 적용 플랫폼
CLI.

## 단계
1. 데모 단계.

## 코드 스니펫

```bash
echo "snippet-line-1: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-2: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-3: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-4: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-5: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-6: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-7: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-8: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-9: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-10: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-11: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-12: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-13: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-14: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-15: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-16: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-17: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-18: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-19: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-20: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-21: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-22: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-23: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-24: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-25: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-26: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-27: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-28: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-29: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-30: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-31: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-32: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-33: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-34: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-35: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-36: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-37: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-38: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-39: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-40: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-41: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-42: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-43: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-44: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-45: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-46: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-47: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-48: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-49: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-50: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-51: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-52: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-53: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-54: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-55: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-56: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-57: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-58: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-59: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-60: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-61: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-62: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-63: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-64: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-65: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-66: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-67: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-68: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-69: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-70: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-71: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-72: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-73: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-74: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-75: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-76: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-77: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-78: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-79: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-80: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-81: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-82: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-83: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-84: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-85: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-86: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-87: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-88: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-89: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
echo "snippet-line-90: padding content to exceed the 8500-char recipe budget under fence-inclusive judgement"
```
