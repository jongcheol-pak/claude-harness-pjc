# AGENTS.md — Agent Guide

> Go 프로젝트용 가이드.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.

## 위키

- **프로젝트 페이지**: `20_projects/<personal|work>/<프로젝트명>.md` (LLM WIKI vault)
- 프로젝트 성격·기술 스택·디렉터리 구조·**아키텍처 상세**·기능 목록은 **위키가 정본**이다. 이 파일에 중복 기재하지 않는다 (단 `## Conventions`의 **아키텍처 선언 1줄**은 여기 남는다).
- 위키에 등록되면 이 경로가 채워진다(등록은 `pjc:plan` Step 1 소관).

## Build & Test
- **Build**: `go build ./...` (또는 특정 cmd: `go build ./cmd/<app>`)
- **Run**: `go run ./cmd/<app>` 또는 `go run .`
- **Test**: `go test ./...`
- **Test (race detector)**: `go test -race ./...`
- **Test (coverage)**: `go test -cover ./...`
- **Lint**: `golangci-lint run ./...` (권장)
- **Vet**: `go vet ./...`
- **Format**: `gofmt -w .` 또는 `goimports -w .`

## 데이터 접근
- **DB/스토어**: <예: PostgreSQL / MySQL / SQLite / Redis / 없음>
- **드라이버/접속**: <database/sql + pgx / sqlx / GORM 등 — 연결 정보는 환경변수, 실제 값 금지 (예: `DATABASE_URL`)>
- **마이그레이션**: <예: `migrate -path ... up` (golang-migrate) / `goose up` / `atlas migrate apply`>
- **시드/조회**: <개발용 데이터 확인 방법>

> ⚠️ 실제 연결문자열·계정·비밀번호는 적지 않는다(환경변수 이름만). DB가 없으면 "없음".

## 산출물·파일 관리
- **빌드 산출물**: 빌드 바이너리(`<app>` · `*.exe`) · `bin/` (gitignore)
- **런타임 생성물**: <로그·리포트·업로드/다운로드 등 경로>
- **임시/캐시**: `$GOCACHE` · coverage 출력(`*.out`)

## Conventions
- **아키텍처**: `<Clean/Hexagonal | 계층형(트랜잭션 스크립트) | 기타 — 하나만 남기세요>`
  - **Clean/Hexagonal** — 의존: interfaces → application → domain ← infrastructure. 포트·어댑터로 경계를 잡는다. 도메인 규칙이 두터울 때.
  - **계층형(트랜잭션 스크립트)** — handler → service → store. Go의 관례에 가깝고, 규칙이 얇은 API·CLI면 **정당한 선택**이다. 인터페이스를 미리 파는 것은 Go에서 특히 안티패턴이다(사용처에서 정의).
  - ⚠️ **실제 구조와 다르게 적지 마세요.** 선언과 실제가 갈리면 리뷰어도 사람도 오도됩니다.
- **에러 처리**: `if err != nil` 명시적 처리. `errors.Is/As` 활용. `panic` 금지 (recover 가능한 곳 제외).
- **인터페이스**: 소비처에 정의 (`accept interfaces, return structs`).
- **동시성**: goroutine + channel. `context.Context` 전파 의무 (timeout/cancel).
- **테스트**: table-driven test 패턴 권장. `t.Parallel()` 활용.
- **로깅**: 구조화 로그 (slog, zap, zerolog). `fmt.Println` 금지.
- **파일**: 단일 책임 유지(분할은 줄 수가 아니라 책임·읽기 부담으로 판정), UTF-8, 주석은 한글 + godoc 컨벤션 (export 함수는 영어 첫 줄)

## DO NOT
- `vendor/` 커밋 (대부분 — `GOFLAGS=-mod=vendor` 정책 아니면 gitignore)
- `*.exe`, `*.test`, coverage 결과 커밋
- `init()`에서 무거운 작업 (DB 연결 등) — 명시적 setup 함수 사용
- 무명 import (`_ "package"`)로 부수효과 의존 — 명시적이지 않은 한 금지
- panic 사용 (예외: 초기화 실패 시 즉시 종료)
- 코드·문서·notes·plan 등 어떤 파일에도 실제 IP·계정·비밀번호·토큰·DB 연결문자열 기록 (환경변수 이름만 적고 값은 .env로)
- 검증·테스트 스크립트에 평문 자격증명·`-WindowStyle Hidden`·과도한 `-ExecutionPolicy Bypass` (백신이 공격 도구로 오인해 격리할 수 있음)

## Plan Location

```
PRD Location:  docs/prd.md (대규모 작업 시. 누적은 docs/prds/<YYYY-MM-DD>-<slug>.md)
```

- **plan은 루트 `plan.md` 하나**다(덮어쓰기). 위치 선택지가 없으므로 이 절에 `Plan Location:` 줄을 두지 않는다.
- task가 많아 나눠야 하면 파일을 쪼개지 말고 **회차를 나눈다** — 이번 plan은 앞부분만 담고 뒤는 `## Deferred / Follow-up`으로 미룬 뒤, 그 회차를 끝내 커밋하고 다음 plan을 새로 쓴다.

## 추가 정보
- Go 버전 고정: `go.mod`의 `go <version>`
- CI/CD: <GitHub Actions / GitLab CI>
- 배포: <Docker, binary, k8s 등>
