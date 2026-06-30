# AGENTS.md — Agent Guide

> Rust 프로젝트용 가이드.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.


## Stack
- **언어**: Rust <stable / 1.80+>
- **에디션**: <2021 / 2024>
- **주요 crates**: <tokio / actix-web / axum / serde / sqlx 등 — 실제 사용 명시>
- **빌드 도구**: Cargo

## Build & Test
- **Build (debug)**: `cargo build`
- **Build (release)**: `cargo build --release`
- **Run**: `cargo run --bin <binary>` 또는 `cargo run`
- **Test**: `cargo test`
- **Test (single thread)**: `cargo test -- --test-threads=1` (DB 테스트 등)
- **Lint**: `cargo clippy --all-targets -- -D warnings`
- **Format check**: `cargo fmt --check`
- **Format**: `cargo fmt`
- **Doc**: `cargo doc --no-deps --open`

## 데이터 접근
- **DB/스토어**: <예: PostgreSQL / MySQL / SQLite / Redis / 없음>
- **드라이버/접속**: <sqlx / SeaORM / Diesel 등 — 연결 정보는 환경변수, 실제 값 금지 (예: `DATABASE_URL`)>
- **마이그레이션**: <예: `sqlx migrate run` / `diesel migration run` / `sea-orm-cli migrate up`>
- **시드/조회**: <개발용 데이터 확인 방법>

> ⚠️ 실제 연결문자열·계정·비밀번호는 적지 않는다(환경변수 이름만). DB가 없으면 "없음".

## Repository Structure

```
<repo>/
├── Cargo.toml
├── Cargo.lock
├── src/
│   ├── main.rs              # 단일 binary인 경우
│   ├── lib.rs               # 라이브러리 진입점
│   ├── domain/              # 비즈니스 로직 (no_std 가능하면 좋음)
│   ├── application/         # UseCases
│   ├── infrastructure/      # DB, HTTP client
│   └── interfaces/          # HTTP handlers, CLI
├── tests/                   # 통합 테스트 (binary별로)
└── benches/                 # criterion benchmarks (있을 때)
```

Workspace 사용 시 `members = ["crates/*"]`로 구분.

## 산출물·파일 관리
- **빌드 산출물**: `target/` (debug·release, gitignore)
- **런타임 생성물**: <로그·리포트·업로드/다운로드 등 경로>
- **임시/캐시**: `target/` (빌드 캐시 겸) · criterion 결과(`target/criterion/`)

## Conventions
- **아키텍처**: Clean / Hexagonal. crate 경계로 layered 강제 가능.
- **에러 처리**: `Result<T, E>` + `thiserror` (도메인 에러), `anyhow` (애플리케이션). `unwrap()`, `expect()` 금지 (테스트·main 진입부 제외).
- **소유권**: 명시적. `clone()` 남발 금지 — borrow 우선.
- **동시성**: `tokio` (async). `Arc<Mutex<T>>`보다 채널·actor 우선.
- **테스트**: 단위는 `#[cfg(test)] mod tests`, 통합은 `tests/` 디렉터리.
- **문서화**: `///` doc comment + `//!` for module. 한글 가능하지만 코드 예시는 영문/실행 가능 형태.
- **파일**: 1500라인 내외 (Rust는 module 분리 강함), UTF-8, 주석은 한글

## DO NOT
- `target/` 커밋 (gitignore 필수)
- `Cargo.lock`은 binary는 커밋, library는 보통 무시 (정책에 따라)
- `unsafe` 무분별 사용 — 사유 주석 의무
- `println!` production 로깅 — `tracing` 또는 `log` 사용
- `panic!` 직접 호출 (예외: main에서 검증 실패)
- 코드·문서·notes·plan 등 어떤 파일에도 실제 IP·계정·비밀번호·토큰·DB 연결문자열 기록 (환경변수 이름만 적고 값은 .env로)
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass` (백신이 공격 도구로 오인해 격리할 수 있음)

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- Rust 버전 고정: `rust-toolchain.toml`
- MSRV (Minimum Supported Rust Version): <명시 시>
- CI/CD: <GitHub Actions / GitLab CI>
- 배포: <Docker, binary, crates.io>
