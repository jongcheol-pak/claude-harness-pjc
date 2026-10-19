#!/usr/bin/env python3
"""재실패 방지 회로 검사 — 작업 함정이 기록되고 다음 작업이 그것을 읽는가.

「같은 함정에 두 번 걸리지 않는다」는 기능은 아래 회로 목록의 지점이 한 줄로
이어져야 성립한다(수를 여기 적지 않는 이유는 목록만 늘리고 머리글을 두어
갈린 전력이 있기 때문이다).
어느 한 곳이 끊기면 기록은 남지만 다음 세션이 그것을 읽지 않거나, 읽으려 해도
기록이 도착하지 않는다. 그 연결을 파일 내용으로 검사한다.

함정의 기록처는 레포 docs/conventions.md 이고 규약 정본은 skills/REPO-CONVENTIONS.md 다
(2026-10-19 — 그 전에는 vault pending.md 의 [PROJECT-FACT] 를 거쳐 위키 conventions.md 로 갔다).

회로:
  1. implement/SKILL.md 가 완료 시 REPO-CONVENTIONS.md 를 따르라고 지시한다
  2. REPO-CONVENTIONS.md 가 2회 트리거와 1회차 기록 자리(plan.md)를 정의한다
  3. REPO-CONVENTIONS.md 「쓰기」 절이 docs/conventions.md 에 쓰라고 지시한다
  4. REPO-CONVENTIONS.md 「읽기」 절이 계획 단계(pjc:plan)에 docs/conventions.md 를 읽으라고 지시한다
  5. plan/SKILL.md 가 REPO-CONVENTIONS.md 와 docs/conventions.md 를 가리킨다
  6. REPO-CONVENTIONS.md 「읽기」 절이 파일 부재 시 위키(WIKI.md) 폴백을 지시한다
     — 위키 conventions 를 레포로 이관하기 전인 프로젝트의 함정이 끊기지 않게 한다
  7. 디버깅 조회(llm-wiki lookup-rules.md)가 docs/conventions.md 를 본다
  8. 완료 리뷰(agents/completion-reviewer.md)가 2회 기록을 docs/conventions.md 와 대조한다

판정은 「한 줄에 두 키워드」 또는 「한 절 안에」로 한다 — 파일 전체 `in` 판정은 서로 다른
맥락에 따로 있는 두 문자열로 참이 되는 거짓 통과를 낸 전력이 있다(옛 회로 4 — 소비 규칙이
그 파일을 떠난 뒤에도 다른 절이 두 문자열을 함께 담아 통과했다).

실행: python plugins/pjc/skills/evals/check_wiki_circuit.py [--skills <경로>]
종료 코드: 0 통과 / 1 실패
"""
import argparse
import re
import sys
from pathlib import Path

# Windows 콘솔(cp949)에서 한글·이모지 출력이 죽지 않도록 강제 (같은 폴더 러너 셋과 동일 관례)
# 이것이 없어 전 단계 PASS 뒤 성공 메시지의 em-dash 에서 죽어 exit 1 을 냈다 — 통과가 실패로 보였다.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

DEFAULT_SKILLS = Path(__file__).resolve().parents[1]

_parser = argparse.ArgumentParser(add_help=True)
_parser.add_argument(
    "--skills",
    type=Path,
    default=DEFAULT_SKILLS,
    help="스킬 디렉터리 경로 (기본: 이 스크립트의 상위). 검사기 자신을 검증할 때 쓴다.",
)
SKILLS = _parser.parse_args().skills.resolve()
AGENTS = SKILLS.parent / "agents"

# 회로를 잇는 두 이름. 이 값이 문서와 갈리면 기록이 도착하지 않는다.
SINK = "docs/conventions.md"
RULES = "REPO-CONVENTIONS.md"


def read(path: Path) -> str:
    """없으면 빈 문자열 — 그 파일에 기대는 항목만 FAIL 하고 나머지는 계속 잰다."""
    return path.read_text(encoding="utf-8") if path.exists() else ""


def section(text: str, title: str) -> str:
    """`## <title>` 절 본문(다음 `## ` 직전까지). 펜스 안의 `## ` 는 절로 세지 않는다."""
    out, inside, fence = [], False, False
    for line in text.splitlines():
        if re.match(r"(```|~~~)", line):
            fence = not fence
        if not fence and line.startswith("## "):
            inside = line[3:].strip() == title
            continue
        if inside:
            out.append(line)
    return "\n".join(out)


def any_line(text: str, *keys: str) -> bool:
    return any(all(k in line for k in keys) for line in text.splitlines())


def main() -> int:
    impl = read(SKILLS / "implement/SKILL.md")
    plan = read(SKILLS / "plan/SKILL.md")
    rules = read(SKILLS / RULES)
    lookup = read(SKILLS / "llm-wiki/references/lookup-rules.md")
    reviewer = read(AGENTS / "completion-reviewer.md")
    write_sec = section(rules, "쓰기")
    read_sec = section(rules, "읽기")

    checks = [
        ("1. implement 가 완료 시 REPO-CONVENTIONS.md 를 따르라고 지시",
         any_line(impl, RULES, "완료")),
        ("2-a. REPO-CONVENTIONS.md 가 2회 트리거를 정의",
         "2회 이상 막혔는가" in write_sec),
        ("2-b. REPO-CONVENTIONS.md 가 1회차 기록 자리(plan.md)를 지정 (2회차 판정의 전제)",
         any_line(write_sec, "1회차", "plan.md")),
        (f"3. 「쓰기」 절이 {SINK} 에 쓰라고 지시",
         any_line(write_sec, SINK, "기록")),
        (f"4. 「읽기」 절이 계획 단계에 {SINK} 를 읽으라고 지시",
         "pjc:plan" in read_sec and SINK in read_sec),
        (f"5. plan 이 {RULES} 와 {SINK} 를 가리킨다",
         any_line(plan, RULES, SINK)),
        ("6. 「읽기」 절이 파일 부재 시 위키 폴백(WIKI.md)을 지시",
         any_line(read_sec, "폴백", "WIKI.md")),
        (f"7. 디버깅 조회(lookup-rules)가 {SINK} 를 본다",
         any_line(lookup, SINK, RULES)),
        (f"8. 완료 리뷰가 2회 기록을 {SINK} 와 대조",
         any_line(reviewer, SINK, "2회")),
    ]

    failed = 0
    for label, ok in checks:
        print(f"{'PASS' if ok else 'FAIL'}  {label}")
        if not ok:
            failed += 1

    print()
    if failed:
        print(f"회로 단절 {failed}곳 — 기록이 다음 작업에 도달하지 않는다.")
        return 1
    print(f"회로 {len(checks)}단계 연결 확인 — 기록({SINK}) → 조회 경로가 닫혀 있다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
