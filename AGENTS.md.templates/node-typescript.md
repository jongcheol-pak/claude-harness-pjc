# AGENTS.md — Agent Guide

> Node.js / TypeScript / JavaScript 프로젝트용 가이드.

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

## Repository Structure

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

## Conventions
- **아키텍처**: Layered / Clean. 의존 방향: interfaces → application → domain ← infrastructure
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

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- Node 버전 고정: `.nvmrc` 또는 `engines` in package.json
- CI/CD: <GitHub Actions / Vercel / Netlify 등>
- 배포: <Vercel, Docker, npm publish, etc.>
