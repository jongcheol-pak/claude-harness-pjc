# AGENTS.md — Agent Guide

> **Generic 템플릿 — 어떤 언어·플랫폼에서도 동작합니다.** 전용 템플릿이 있는 stack(.NET·Android·Node/TS·Python·Go·Rust) 외의 모든 언어(Flutter·Swift·Kotlin·Java·C++·Ruby·Elixir·PHP·Zig 등)에 사용합니다. pjc의 계획·검증·자율 루프는 언어를 가리지 않으며, 빌드/테스트 명령만 알면 작동합니다.
> **이 템플릿은 빈 칸만 채우면 그대로 동작합니다.** 더 정확한 작업을 원하면 프로젝트 고유의 규칙·함정·컨벤션을 추가하세요 — Claude가 추측을 줄여 더 안정적으로 일합니다.
> 가능한 한 빈 칸을 모두 채워주세요 — Claude가 추측하지 않아도 됩니다.

## Stack
- **언어/플랫폼**: <예: Flutter / Swift / Ruby / Elixir / Zig / 기타>
- **버전**: <SDK 버전 또는 언어 버전>
- **주요 프레임워크**: <있다면 명시>
- **테스트 도구**: <pytest, jest, rspec, exunit 등>

## Build & Test
- **Build**: `<빌드 명령>`
- **Run (개발)**: `<실행 명령>`
- **Test**: `<테스트 명령>`
- **Lint/Format**: `<있으면 명시>`
- **Clean**: `<있으면 명시>`

> ⚠️ Build/Test 명령이 비어있으면 `pjc:plan-feature`의 Verification Strategy가 무의미해집니다.
> 최소한 위 두 줄은 반드시 채우세요.

## Repository Structure

```
<repo>/
├── (실제 디렉터리 구조 직접 기록)
```

## Conventions
- **아키텍처**: <Layered / Clean / MVC / 기타 — 명시>
- **에러 처리**: <정책 명시>
- **테스트 위치**: <어디에, 어떤 명명>
- **포맷터/Linter**: <도구 + 명령>
- **파일 크기**: 1500라인 내외 (또는 프로젝트 정책)
- **인코딩**: UTF-8 (BOM 없음 권장)
- **주석**: 한글, "왜"를 설명 ("무엇"은 코드로)
- **이름 규칙**: <camelCase / snake_case / PascalCase 등 영역별 명시>

## DO NOT
- 환경변수 파일(`.env*`), secrets, 인증서 커밋
- 빌드 산출물 디렉터리(`build/`, `dist/`, `target/`, `out/` 등) 커밋
- <그 외 stack별 금지사항>

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- OS/플랫폼: <Windows / Linux / macOS / iOS / Android / Web 등>
- CI/CD: <있으면 명시>
- 배포 방법: <있으면 명시>

---

## 작성 가이드 (이 섹션은 작성 후 삭제)

Claude가 효과적으로 작업하려면 위 항목 중 **최소 다음 4개**는 반드시 채워주세요:

1. ✅ **Build 명령** — V-1 빌드 검증의 기반
2. ✅ **Test 명령** — V-2 테스트 검증의 기반  
3. ✅ **아키텍처** — implement-task가 어디에 코드를 둘지 결정
4. ✅ **파일 위치 컨벤션** — Files 목록 정확도

나머지는 채우면 좋지만, 위 4개가 비어 있으면 plugin의 Phase V가 거의 무의미해집니다.
