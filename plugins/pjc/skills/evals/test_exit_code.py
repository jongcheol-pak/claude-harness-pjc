"""trigger_eval.exit_code 단위 케이스 — 관측 실패(error·timeout)가 통과로 흘러가지 않는지.

이 서브트리에는 골든 러너가 없다. `trigger_eval.py` 본체는 실제 모델을 호출해 비용이
크므로 회귀 축으로 쓸 수 없고, 종료 코드 판정만 순수 함수로 갈라 여기서 잰다.

    python plugins/pjc/skills/evals/test_exit_code.py

변이 실증(2026-09-08): `exit_code`의 `unobserved` 산출을 0으로 고정하면 관측 실패 축
3건이 red 가 된다 — 판정식을 `failed`만 보도록 되돌린 것과 같은 상태다.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "trigger_eval", os.path.join(_HERE, "trigger_eval.py"))
_TE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_TE)


def _summary(**kw):
    """run 요약의 종료 코드 관련 필드만 담은 최소 딕셔너리."""
    base = {"failed": 0, "error": 0, "timeout": 0}
    base.update(kw)
    return base


CASES = [
    # (이름, run 요약 목록, 기대 exit)
    ("error 1건 → 관측 실패", [_summary(error=1)], 2),
    ("timeout 1건 → 관측 실패", [_summary(timeout=1)], 2),
    ("fail 만 → 품질 저하", [_summary(failed=1)], 1),
    ("전부 0 → 통과", [_summary()], 0),
    ("--isolation both 한쪽만 error", [_summary(), _summary(error=1)], 2),
    ("--isolation both fail 만", [_summary(failed=2), _summary()], 1),
]


def main():
    failed = 0
    for name, summaries, want in CASES:
        got = _TE.exit_code(summaries)
        ok = got == want
        failed += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: exit {got} (기대 {want})")
    print(f"\n결과: {len(CASES) - failed}/{len(CASES)} PASS")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
