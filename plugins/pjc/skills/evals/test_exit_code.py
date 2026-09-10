"""trigger_eval 의 순수 함수 단위 케이스 — `exit_code` 종료 코드 판정과 `summarize` 오발동 게이트.

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


def _neg(status, triggered, fired):
    """should-not-trigger 케이스 1건의 summarize 관련 필드만 담은 최소 딕셔너리."""
    return {"expect": "no-trigger", "status": status,
            "triggered": triggered, "fired": fired}


# 오발동 게이트 ②-b — `triggered` 가 채워진 `timeout` 을 대조에 포함하는가.
#   그 케이스는 **발동 관측이 이미 끝났고**(스킬이 떴다) 못 끝낸 것은 그 뒤의 턴뿐이라,
#   빼면 진짜 오발동이 관측 실패 뒤에 숨는다. 반대로 `triggered` 가 빈 순수 timeout 까지
#   넣으면 관측 실패가 품질 저하로 둔갑하므로 그쪽은 종전대로 뺀다.
# (이름, cases, 기대 judged_negative, 기대 false_trigger_rate)
SUMMARIZE_CASES = [
    ("triggered 채워진 timeout -> 대조 포함",
     [_neg("timeout", ["pjc:plan"], True)], 1, 1.0),
    ("triggered 빈 timeout -> 대조 제외",
     [_neg("timeout", [], False)], 0, None),
    ("판정된 pass + triggered 채워진 timeout -> 분모 2",
     [_neg("pass", [], False), _neg("timeout", ["pjc:plan"], True)], 2, 0.5),
    ("error 는 triggered 가 있어도 제외(관측 실패)",
     [_neg("error", ["pjc:plan"], True)], 0, None),
]


def main():
    failed = 0
    for name, summaries, want in CASES:
        got = _TE.exit_code(summaries)
        ok = got == want
        failed += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: exit {got} (기대 {want})")
    for name, cases, want_n, want_rate in SUMMARIZE_CASES:
        s = _TE.summarize(cases)
        got_n, got_rate = s["judged_negative"], s["false_trigger_rate"]
        ok = (got_n == want_n) and (got_rate == want_rate)
        failed += 0 if ok else 1
        mark = "PASS" if ok else "FAIL"
        print(f"[{mark}] {name}: judged_negative {got_n} (기대 {want_n})"
              f" · 오발동률 {got_rate} (기대 {want_rate})")
    total = len(CASES) + len(SUMMARIZE_CASES)
    print(f"\n결과: {total - failed}/{total} PASS")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
