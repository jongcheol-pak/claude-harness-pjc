# AGENTS.md — Agent Guide

> Node.js / TypeScript / JavaScript 프로젝트용 가이드.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.


## Stack
- **런타임**: Node.js <version> (또는 Bun / Deno)
- **언어**: TypeScript <version> (또는 JavaScript)
- **패키지 매니저**: npm / pnpm / yarn (실제 사용하는 것)
- **주요 프레임워크**: <Next.js / Express / NestJS / Fastify / React / Vue 등>
- **테스트**: <Vitest / Jest / Mocha>

## Build & Test
- **설치**: `npm install` (또는 `pnpm install`, `yarn`)
- **Build**: `npm run build`
- **Dev (개발 서버)**: `npm run dev`
- **Test**: `npm test` 또는 `npm run test`
- **Lint**: `npm run lint`
- **Format**: `npm run format` (Prettier)
- **Type check**: `npm run typecheck` (또는 `tsc --noEmit`)

## 데이터 접근
- **DB/스토어**: <예: PostgreSQL / MySQL / MongoDB / Redis / SQLite / 없음>
- **ORM/접속**: <Prisma / TypeORM / Drizzle / Mongoose 등 — 연결 정보는 `.env`, 실제 값 금지 (예: `DATABASE_URL`)>
- **마이그레이션**: <예: `prisma migrate dev` / `knex migrate:latest` / `sequelize db:migrate`>
- **시드/조회**: <예: `prisma db seed` / 개발용 조회 방법>

> ⚠️ 실제 연결문자열·계정·비밀번호는 적지 않는다(환경변수 이름만). DB가 없으면 "없음".

## Repository Structure

> 아래는 **Clean/DDD를 택했을 때**의 구조다. 계층형을 택했으면 실제 구조로 바꾼다(예: `routes/`·`services/`·`db/`). **선택한 아키텍처에 맞게 조정하세요.**

```
<repo>/
├── src/
│   ├── domain/           # 비즈니스 로직 (순수 TS, no framework deps)
│   ├── application/      # UseCases, Services
│   ├── infrastructure/   # DB, External API
│   └── interfaces/       # Express routes, React components 등
├── tests/                # 또는 src/**/*.test.ts
├── package.json
├── tsconfig.json
└── .eslintrc / eslint.config.js
```

## 산출물·파일 관리
- **빌드 산출물**: `dist/` · `build/` · `.next/` (gitignore)
- **런타임 생성물**: <로그·업로드/다운로드·리포트 등 경로>
- **임시/캐시**: `node_modules/` · `coverage/` · `.cache/`

## Conventions
- **아키텍처**: `<Clean/DDD | 계층형(트랜잭션 스크립트) | 기타 — 하나만 남기세요>`
  - **Clean/DDD** — 의존 방향: interfaces → application → domain ← infrastructure. 도메인 규칙(검증·상태 전이·계산)이 두터울 때.
  - **계층형(트랜잭션 스크립트)** — route/controller → service → repository. 규칙이 얇은 CRUD·API 위주면 **정당한 선택**이다. 로직이 없는데 레이어만 나누면 과한 추상화다.
  - ⚠️ **실제 구조와 다르게 적지 마세요.** 선언만 DDD면(도메인 객체는 타입뿐, 로직은 전부 서비스) 리뷰어도 사람도 "지켜지고 있다"고 착각합니다.
- **모듈 시스템**: ESM 권장 (`"type": "module"`). CommonJS는 legacy만.
- **타입**: `any` 금지. `unknown` 사용 후 좁히기.
- **에러 처리**: `Result<T, E>` 패턴 또는 throw + global handler. 정책 일관.
- **비동기**: `async`/`await`. `.then()` 체인 금지.
- **테스트**: 단위는 `tests/<domain>.test.ts` 또는 `src/<file>.test.ts`. 통합은 별도.
- **파일**: 1500라인 내외, UTF-8, 주석은 한글
- **Import**: 절대 경로(`@/`) 또는 baseUrl 설정 일관

## DO NOT
- `.env`, `.env.local` 커밋 (gitignore 필수)
- `node_modules/`, `dist/`, `.next/`, `coverage/` 커밋
- `console.log` production 코드 잔존 (logger 사용)
- Top-level `await` in CJS, synchronous I/O (`readFileSync` 등) hot path
- 코드·문서·notes·plan 등 어떤 파일에도 실제 IP·계정·비밀번호·토큰·DB 연결문자열 기록 (환경변수 이름만 적고 값은 .env로)
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass` (백신이 공격 도구로 오인해 격리할 수 있음)

## Plan Location

```
Plan Location: <plan.md | docs/plans/>   ← 하나만 남기세요
PRD Location:  docs/prd.md (대규모 작업 시. 누적은 docs/prds/<YYYY-MM-DD>-<slug>.md)
```

- `plan.md` = 단일 파일 덮어쓰기(작은 프로젝트) / `docs/plans/` = `<YYYY-MM-DD>-<slug>.md` 날짜별 누적(히스토리 보존)
- 미설정 시 기본: `docs/plans/`가 이미 있으면 그것, 없으면 `plan.md`

## 추가 정보
- Node 버전 고정: `.nvmrc` 또는 `engines` in package.json
- CI/CD: <GitHub Actions / Vercel / Netlify 등>
- 배포: <Vercel, Docker, npm publish, etc.>
