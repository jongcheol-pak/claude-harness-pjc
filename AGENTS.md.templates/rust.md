# AGENTS.md — Agent Guide

> Rust 프로젝트용 가이드.

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

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- Rust 버전 고정: `rust-toolchain.toml`
- MSRV (Minimum Supported Rust Version): <명시 시>
- CI/CD: <GitHub Actions / GitLab CI>
- 배포: <Docker, binary, crates.io>
