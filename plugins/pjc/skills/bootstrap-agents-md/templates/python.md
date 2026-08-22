# AGENTS.md — Agent Guide

> Python 프로젝트용 가이드.

> **이 템플릿은 그대로 써도 동작합니다.** 다만 빈 칸(빌드/테스트 명령·아키텍처·컨벤션)을 프로젝트에 맞게 채우고, 프로젝트 고유의 규칙·함정·금지사항을 추가하면 Claude가 추측을 줄여 **더 정확하고 안정적으로** 작업합니다. 처음엔 빌드·테스트 명령만 채워 시작하고, 작업하며 점진적으로 다듬는 것을 권장합니다.

## 위키

- **프로젝트 페이지**: `20_projects/<personal|work>/<프로젝트명>.md` (LLM WIKI vault)
- 프로젝트 성격·기술 스택·디렉터리 구조·아키텍처·기능 목록은 **위키가 정본**이다. 이 파일에 중복 기재하지 않는다.
- 미등록이면 `pjc:plan-feature` Step 1이 자동 등록한다(경로는 그때 채워진다).

## Build & Test
- **가상환경 생성**: `python -m venv .venv` 또는 `uv venv` (poetry는 `poetry install` 시 자동 생성 — 활성화는 `poetry env activate`, `poetry shell`은 Poetry 2.x에서 제거됨)
- **설치**: `pip install -e .` 또는 `poetry install` / `uv pip install -e .`
- **Build (배포 패키지)**: `python -m build`
- **Test**: `pytest` 또는 `pytest tests/`
- **Test (coverage)**: `pytest --cov=src --cov-report=term-missing`
- **Lint**: `ruff check src tests`
- **Format**: `ruff format src tests` 또는 `black src tests`
- **Type check**: `mypy src` 또는 `pyright`

## 데이터 접근
- **DB/스토어**: <예: PostgreSQL / MySQL / SQLite / MongoDB / Redis / 없음>
- **ORM/접속**: <SQLAlchemy / Django ORM / Tortoise 등 — 연결 정보는 `.env`, 실제 값 금지 (예: `DATABASE_URL`)>
- **마이그레이션**: <예: `alembic upgrade head` / `python manage.py migrate` (Django)>
- **시드/조회**: <개발용 데이터 확인 방법>

> ⚠️ 실제 연결문자열·계정·비밀번호는 적지 않는다(환경변수 이름만). DB가 없으면 "없음".

## 산출물·파일 관리
- **빌드 산출물**: `dist/` · `build/` · `*.egg-info/` (gitignore)
- **런타임 생성물**: <로그·리포트·업로드/다운로드 등 경로>
- **임시/캐시**: `__pycache__/` · `.pytest_cache/` · `.mypy_cache/` · `.venv/`

## Conventions
- **타입 힌트 의무**. mypy/pyright strict 권장.
- **아키텍처**: `<Clean/DDD | 계층형(트랜잭션 스크립트) | 기타 — 하나만 남기세요>`
  - **Clean/DDD** — 의존: interfaces → application → domain ← infrastructure. 도메인 규칙이 두터울 때.
  - **계층형(트랜잭션 스크립트)** — view/handler → service → repository. 규칙이 얇은 CRUD·스크립트·도구면 **정당한 선택**이다. 레이어 분리 자체가 목적이 되면 과한 추상화다.
  - ⚠️ **실제 구조와 다르게 적지 마세요.** 선언만 DDD면 리뷰어도 사람도 "지켜지고 있다"고 착각합니다.
- **에러 처리**: 명시적 예외 클래스 또는 `Result` 패턴. Bare `except:` 금지.
- **비동기**: `async`/`await` (FastAPI 등). 동기/비동기 코드 혼용 주의.
- **테스트**: pytest fixture 활용. mock은 `pytest-mock` 또는 `unittest.mock`.
- **포맷**: PEP 8 + ruff/black. line length 100~120.
- **파일**: 단일 책임 유지(분할은 줄 수가 아니라 책임·읽기 부담으로 판정), UTF-8, 주석/docstring은 한글
- **Naming**: snake_case (함수/변수), PascalCase (클래스), UPPER_CASE (상수)

## DO NOT
- `.env`, secrets, `*.pem` 커밋
- `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `*.egg-info/` 커밋
- 모듈 import 시 부수효과 (top-level DB 연결 등)
- `global` 변수 사용
- `pickle` 신뢰할 수 없는 데이터 역직렬화
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
- Python 버전: `.python-version` 또는 `pyproject.toml`의 `requires-python`
- CI/CD: <GitHub Actions / GitLab CI>
- 배포: <PyPI / Docker / 서버 직배포>
