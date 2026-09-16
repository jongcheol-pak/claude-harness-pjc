#!/usr/bin/env python3
"""위키 재실패 방지 회로 검사.

「같은 함정에 두 번 걸리지 않는다」는 기능은 아래 회로 목록의 지점이 한 줄로
이어져야 성립한다(수를 여기 적지 않는 이유는 목록만 늘리고 머리글을 두어
갈린 전력이 있기 때문이다).
어느 한 곳이 끊기면 기록은 남지만 다음 세션이 그것을 읽지 않거나, 읽으려 해도
기록이 도착하지 않는다. 그 연결을 파일 내용으로 검사한다.

회로:
  1. implement/SKILL.md 가 완료 시 위키 기록을 지시한다
  2. WIKI.md 가 2회 트리거와 기록 형식을 정의한다
  3. 기록 태그가 llm-wiki 가 소비하는 태그다 (새 태그면 영원히 큐에 남는다)
  4. llm-wiki 가 그 태그를 conventions.md 로 라우팅한다
  5. WIKI.md 가 계획 단계에 conventions.md 를 읽으라고 지시한다
  6. plan/SKILL.md 가 WIKI.md 를 가리킨다
  7. plan/SKILL.md 가 **소비 전** pending.md 조회도 지시한다
  8. [K-ROUTE] 회로 — WIKI.md 가 폴백 시 큐잉을 지시하고, queue-rules 에 K 5-6 이 있고,
     queue-consume-rules 가 소비를 규정하고, plan/SKILL.md 가 repo 경로 항목을 조회한다

7 이 없으면 회로는 「소비가 끝난 뒤」에만 닫힌다 — 소비 시점은 사용자가 위키
세션을 열 때라 규약이 정하지 못한다. 실측(2026-09-16)으로 그 사이에
[PROJECT-FACT] 43 건이 잠겨 있었고 다른 여섯 태그는 전부 0 건이었다.

8 은 [PROJECT-FACT] 회로와 **네 문면이 서로 다른 파일에 흩어져 있어** 어느 하나를
지워도 나머지 셋이 그대로 통과한다는 점이 같다. 특히 이 태그는 기록처가 회차마다
교체되는 plan.md 였던 것을 큐로 옮긴 것이라, 조회 지점이 끊기면 **옮긴 의미가 사라진다**.

실행: python plugins/pjc/skills/evals/check_wiki_circuit.py [--skills <경로>]
종료 코드: 0 통과 / 1 실패
"""
import argparse
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

# 회로를 잇는 태그. 이 값이 llm-wiki 소비 측과 갈리면 기록이 도착하지 않는다.
QUEUE_TAG = "[PROJECT-FACT]"
SINK = "conventions.md"
# 8단계가 잇는 태그. 기록처가 회차마다 교체되는 plan.md 였던 것을 큐로 옮긴 것이라,
#  네 문면 중 하나만 끊겨도 옮긴 의미가 사라진다.
ROUTE_TAG = "[K-ROUTE]"


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
        # llm-wiki 의 큐 소비 절차 — **태그별 소비 규칙의 정본**이다.
        #  회차 65 에 `procedures-content.md` 의 B-1 0 에서 갈라져 나왔고, 그 전까지
        #  이 변수는 `procedures-content.md` 를 읽었다. 그때 check 4 는 거짓 통과였다 —
        #  A-2(:50) 가 두 문자열을 함께 담고 있어 **라우팅 규칙이 그 파일을 떠나도**
        #  `in` 판정이 참으로 남았다. 소비 규칙이 사는 파일을 직접 읽어야 그 회로를 잰다.
        consume = read("llm-wiki/references/queue-consume-rules.md")
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
    # 7. 소비 전 조회 경로. **한 줄 안에 두 키워드가 함께 있는지**를 본다 —
    #  파일 전체 `in` 판정이면 `pending.md` 와 `PROJECT-FACT` 가 서로 다른
    #  맥락에 따로 있어도 참이 되고, 이 검사기는 실제로 그 형태의 거짓 통과를
    #  낸 전력이 있다(위 consume 주석의 A-2 사건). 둘이 같은 줄에 있다는 것은
    #  「그 큐 파일에서 그 태그를 읽으라」는 한 규정이 실재한다는 뜻이다.
    checks.append((
        "7. plan 이 소비 전 pending.md 의 [PROJECT-FACT] 조회를 지시",
        any(
            "pending.md" in line and "PROJECT-FACT" in line
            for line in plan.splitlines()
        ),
    ))

    # 8. [K-ROUTE] 회로. 네 문면이 네 파일에 흩어져 있어 **어느 하나를 지워도 나머지가
    #  통과한다** — 7 과 같은 형태의 사각이다. 기록처를 plan.md(회차마다 교체)에서 큐로
    #  옮긴 것이 이 태그의 존재 이유라, 조회 지점이 끊기면 옮긴 의미가 사라진다.
    #  7 과 같은 이유로 **한 줄 안에 두 키워드가 함께 있는지**를 본다(파일 전체 `in` 은
    #  서로 다른 맥락의 두 단어로도 참이 된다).
    checks.append((
        f"8-a. WIKI.md 의 절 단위 읽기 폴백이 {ROUTE_TAG} 큐잉을 지시",
        any(
            ROUTE_TAG in line and "폴백" in line
            for line in wiki.splitlines()
        ),
    ))
    checks.append((
        f"8-b. queue-rules 에 {ROUTE_TAG} 의 큐 규약(K 5-6)이 있다",
        "### K 5-6." in queue_rules and ROUTE_TAG in queue_rules,
    ))
    checks.append((
        f"8-c. queue-consume-rules 가 {ROUTE_TAG} 의 소비를 규정",
        any(
            ROUTE_TAG in line and "절 제목" in line
            for line in consume.splitlines()
        ),
    ))
    checks.append((
        f"8-d. plan 이 {ROUTE_TAG} 의 repo 경로 항목 조회를 지시",
        any(
            ROUTE_TAG in line and "repo 경로" in line
            for line in plan.splitlines()
        ),
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
