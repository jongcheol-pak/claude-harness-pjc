#!/usr/bin/env python3
"""위키 재실패 방지 회로 검사.

「같은 함정에 두 번 걸리지 않는다」는 기능은 문서 6곳이 한 줄로 이어져야 성립한다.
어느 한 곳이 끊기면 기록은 남지만 다음 세션이 그것을 읽지 않거나, 읽으려 해도
기록이 도착하지 않는다. 그 연결을 파일 내용으로 검사한다.

회로:
  1. implement/SKILL.md 가 완료 시 위키 기록을 지시한다
  2. WIKI.md 가 2회 트리거와 기록 형식을 정의한다
  3. 기록 태그가 llm-wiki 가 소비하는 태그다 (새 태그면 영원히 큐에 남는다)
  4. llm-wiki 가 그 태그를 conventions.md 로 라우팅한다
  5. WIKI.md 가 계획 단계에 conventions.md 를 읽으라고 지시한다
  6. plan/SKILL.md 가 WIKI.md 를 가리킨다

실행: python plugins/pjc/skills/evals/check_wiki_circuit.py [--skills <경로>]
종료 코드: 0 통과 / 1 실패
"""
import argparse
import sys
from pathlib import Path

DEFAULT_SKILLS = Path(__file__).resolve().parents[1]

_parser = argparse.ArgumentParser(add_help=True)
_parser.add_argument(
    "--skills",
    type=Path,
    default=DEFAULT_SKILLS,
    help="스킬 디렉터리 경로 (기본: 이 스크립트의 상위). 검사기 자신을 검증할 때 쓴다.",
)
SKILLS = _parser.parse_args().skills.resolve()

# 회로를 잇는 태그. 이 값이 llm-wiki 소비 측과 갈리면 기록이 도착하지 않는다.
QUEUE_TAG = "[PROJECT-FACT]"
SINK = "conventions.md"


def read(rel: str) -> str:
    p = SKILLS / rel
    if not p.exists():
        raise FileNotFoundError(f"파일 없음: {p}")
    return p.read_text(encoding="utf-8")


def main() -> int:
    checks = []

    try:
        wiki = read("WIKI.md")
        impl = read("implement/SKILL.md")
        plan = read("plan/SKILL.md")
        # llm-wiki 의 큐 소비 절차 — 이 레포에서 유일한 소비 측 정본
        consume = read("llm-wiki/references/procedures-content.md")
        queue_rules = read("llm-wiki/references/queue-rules.md")
    except FileNotFoundError as e:
        print(f"FAIL  파일 로드: {e}")
        return 1

    checks.append((
        "1. implement 가 완료 시 위키 기록을 지시",
        "위키 기록" in impl and "WIKI.md" in impl,
    ))
    checks.append((
        "2-a. WIKI.md 가 2회 트리거를 정의",
        "2회 이상 막혔는가" in wiki or "2회 이상 막힌" in wiki,
    ))
    checks.append((
        "2-b. WIKI.md 가 1회차 기록 자리를 지정 (2회차 판정의 전제)",
        "1회차" in wiki and "plan.md" in wiki,
    ))
    checks.append((
        f"3. 기록 태그 {QUEUE_TAG} 가 llm-wiki 가 아는 태그",
        QUEUE_TAG in wiki and QUEUE_TAG in queue_rules,
    ))
    checks.append((
        f"4. llm-wiki 가 {QUEUE_TAG} 를 {SINK} 로 라우팅",
        QUEUE_TAG in consume and SINK in consume,
    ))
    checks.append((
        f"5. WIKI.md 가 계획 단계에 {SINK} 를 읽으라고 지시",
        SINK in wiki and "읽기 — 계획 단계" in wiki,
    ))
    checks.append((
        "6. plan 이 WIKI.md 를 가리킨다",
        "WIKI.md" in plan,
    ))

    failed = 0
    for label, ok in checks:
        print(f"{'PASS' if ok else 'FAIL'}  {label}")
        if not ok:
            failed += 1

    print()
    if failed:
        print(f"회로 단절 {failed}곳 — 기록이 다음 작업에 도달하지 않는다.")
        return 1
    print(f"회로 {len(checks)}단계 연결 확인 — 기록 → 소비 → 조회 경로가 닫혀 있다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
