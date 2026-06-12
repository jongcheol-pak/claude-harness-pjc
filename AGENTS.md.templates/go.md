# AGENTS.md — Agent Guide

> Go 프로젝트용 가이드.

## Stack
- **언어**: Go <1.22+>
- **모듈**: <go.mod의 module 경로>
- **주요 라이브러리**: <Gin / Echo / gRPC / sqlx 등 — 실제 사용 명시>
- **테스트**: 표준 testing + testify (선택)

## Build & Test
- **Build**: `go build ./...` (또는 특정 cmd: `go build ./cmd/<app>`)
- **Run**: `go run ./cmd/<app>` 또는 `go run .`
- **Test**: `go test ./...`
- **Test (race detector)**: `go test -race ./...`
- **Test (coverage)**: `go test -cover ./...`
- **Lint**: `golangci-lint run ./...` (권장)
- **Vet**: `go vet ./...`
- **Format**: `gofmt -w .` 또는 `goimports -w .`

## Repository Structure

```
<repo>/
├── cmd/<app>/           # 실행 진입점 (main.go)
├── internal/
│   ├── domain/          # 비즈니스 로직 (외부 import 차단됨)
│   ├── application/     # UseCases
│   ├── infrastructure/  # DB, External API
│   └── interfaces/      # HTTP handlers, gRPC servers
├── pkg/                 # 공개 라이브러리 (있을 때만)
├── go.mod
└── go.sum
```

## Conventions
- **아키텍처**: Clean / Hexagonal. 의존: interfaces → application → domain ← infrastructure
- **에러 처리**: `if err != nil` 명시적 처리. `errors.Is/As` 활용. `panic` 금지 (recover 가능한 곳 제외).
- **인터페이스**: 소비처에 정의 (`accept interfaces, return structs`).
- **동시성**: goroutine + channel. `context.Context` 전파 의무 (timeout/cancel).
- **테스트**: table-driven test 패턴 권장. `t.Parallel()` 활용.
- **로깅**: 구조화 로그 (slog, zap, zerolog). `fmt.Println` 금지.
- **파일**: 1500라인 내외, UTF-8, 주석은 한글 + godoc 컨벤션 (export 함수는 영어 첫 줄)

## DO NOT
- `vendor/` 커밋 (대부분 — `GOFLAGS=-mod=vendor` 정책 아니면 gitignore)
- `*.exe`, `*.test`, coverage 결과 커밋
- `init()`에서 무거운 작업 (DB 연결 등) — 명시적 setup 함수 사용
- 무명 import (`_ "package"`)로 부수효과 의존 — 명시적이지 않은 한 금지
- panic 사용 (예외: 초기화 실패 시 즉시 종료)

## Plan Location
- 단일 plan: `plan.md`
- 여러 plan 누적: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- PRD (대규모 작업 시): `docs/prd.md` 또는 `docs/prds/<YYYY-MM-DD>-<slug>.md`

## 추가 정보
- Go 버전 고정: `go.mod`의 `go <version>`
- CI/CD: <GitHub Actions / GitLab CI>
- 배포: <Docker, binary, k8s 등>
