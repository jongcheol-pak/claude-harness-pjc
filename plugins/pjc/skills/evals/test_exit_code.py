"""trigger_eval 의 순수 함수 단위 케이스 — `exit_code` 종료 코드 판정 · `summarize` 오발동 게이트 ·
`judge_case` 첫 발동 판정 · `is_skill_call` 조기 종료 · `attach_diagnostics` 진단 부착.

이 서브트리에는 골든 러너가 없다. `trigger_eval.py` 본체는 실제 모델을 호출해 비용이
크므로 회귀 축으로 쓸 수 없고, 판정 로직만 순수 함수로 갈라 여기서 잰다.

    python plugins/pjc/skills/evals/test_exit_code.py

변이 실증(2026-09-08): `exit_code`의 `unobserved` 산출을 0으로 고정하면 관측 실패 축
3건이 red 가 된다 — 판정식을 `failed`만 보도록 되돌린 것과 같은 상태다.
변이 실증(2026-10-04): `judge_case` 의 trigger 판정을 종전의 `skill in triggered` 로 되돌리면
ⓑ(다른 스킬이 먼저 뜬 오라우팅)·ⓒ 2건이 red 가 된다.
"""
import importlib.util
import json
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


def _case(expect, route_to=None):
    """판정에 쓰이는 케이스 필드만 담은 최소 딕셔너리 — 목표 스킬은 늘 `pjc:plan`."""
    c = {"skill": "pjc:plan", "expect": expect}
    if route_to:
        c["route_to"] = route_to
    return c


_IMPL, _DBG, _TARGET = "pjc:implement", "pjc:pjc-systematic-debugging", "pjc:plan"
_MAXT = "error_max_turns"

# 판정 갈래 — 「목록 안에 있는가」가 아니라 **첫 발동이 누구인가**로 가르는가.
#   종전 판정은 목표가 둘째로 떠도 PASS 였다(다른 스킬이 먼저 뜬 오라우팅을 못 잡는다).
#   ⓑ·ⓘ·ⓙ 가 그 사각을 재는 축이고, 판정을 `skill in triggered` 로 되돌리면 ⓑ 가 red 가 된다.
# (이름, case, triggered, stop_reason, timed_out, 기대 status, 기대 fired)
JUDGE_CASES = [
    ("ⓐ trigger·목표 첫 발동 -> pass", _case("trigger"), [_TARGET], None, False, "pass", True),
    ("ⓑ trigger·다른 스킬 먼저 -> fail", _case("trigger"), [_IMPL, _TARGET], None, False, "fail", False),
    ("ⓒ trigger·무발동·턴 소진 -> inconclusive", _case("trigger"), [], _MAXT, False, "inconclusive", False),
    ("ⓓ trigger·무발동·정상 종료 -> fail", _case("trigger"), [], "success", False, "fail", False),
    ("ⓔ no-trigger·목표 발동 -> fail", _case("no-trigger"), [_TARGET], None, False, "fail", True),
    ("ⓕ no-trigger·다른 스킬 발동 -> pass", _case("no-trigger"), [_IMPL], None, False, "pass", False),
    ("ⓖ no-trigger·무발동·턴 소진 -> pass", _case("no-trigger"), [], _MAXT, False, "pass", False),
    ("ⓗ no-trigger·route_to 첫 발동 -> pass", _case("no-trigger", _IMPL), [_IMPL], None, False, "pass", False),
    ("ⓘ no-trigger·route_to·제3 스킬 먼저 -> fail", _case("no-trigger", _IMPL), [_DBG, _IMPL], None, False, "fail", False),
    ("ⓙ no-trigger·route_to·목표 먼저 -> fail", _case("no-trigger", _IMPL), [_TARGET], None, False, "fail", True),
    ("ⓚ no-trigger·route_to·무발동·턴 소진 -> inconclusive", _case("no-trigger", _IMPL), [], _MAXT, False, "inconclusive", False),
    ("ⓛ no-trigger·route_to·무발동·정상 종료 -> fail", _case("no-trigger", _IMPL), [], "success", False, "fail", False),
    ("ⓜ timeout·trigger·목표 첫 발동 -> timeout·fired", _case("trigger"), [_TARGET], None, True, "timeout", True),
    ("ⓝ timeout·no-trigger·목표 발동 -> timeout·fired", _case("no-trigger"), [_TARGET], None, True, "timeout", True),
]


def _line(*blocks):
    """stream-json 의 assistant 한 줄."""
    return json.dumps({"type": "assistant", "message": {"content": list(blocks)}})


# 조기 종료 갈래 — **어느 스킬이든** 첫 Skill 호출에서 끊는가. 목표 스킬만 보면
#   no-trigger 케이스가 다른 스킬이 뜬 뒤에도 끝까지 돌아 첫 발동 판정과 비용이 갈린다.
# (이름, 줄, 기대)
STOP_CASES = [
    ("ⓞ Skill tool_use 줄(목표 아닌 스킬) -> 끊는다",
     _line({"type": "tool_use", "name": "Skill", "input": {"skill": _DBG}}), True),
    ("ⓞ 다른 tool_use 줄 -> 계속", _line({"type": "tool_use", "name": "Read", "input": {}}), False),
    ("ⓞ 텍스트 줄 -> 계속", _line({"type": "text", "text": "Skill 을 부를까 한다"}), False),
]

# 진단 부착 갈래 — FAIL 이면 원인 분류 재료(`tool_calls`)가 결과에 남는가. 진단이
#   「미발동」에만 붙으면 오발동·오라우팅 FAIL 은 원인을 가를 재료 없이 남는다.
# (이름, status, 기대 tool_calls 존재)
DIAG_CASES = [
    ("ⓟ fail 결과 -> 진단 있음", "fail", True),
    ("ⓟ pass 결과 -> 진단 없음", "pass", False),
]


def _call(mod, name, *args):
    """대상 함수를 부르되 예외·부재를 값으로 돌려 그 케이스만 FAIL 로 세게 한다 —
    한 갈래의 예외가 나머지 갈래의 판정을 가리지 않게 한다."""
    try:
        return getattr(mod, name)(*args)
    except Exception as e:  # 판정 대상의 결함을 FAIL 로 보이기 위한 것이라 넓게 받는다
        return f"<{type(e).__name__}: {e}>"


def main():
    failed = 0
    for name, case, triggered, stop, timed_out, want_s, want_f in JUDGE_CASES:
        got = _call(_TE, "judge_case", case, triggered, stop, timed_out)
        ok = got == (want_s, want_f)
        failed += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: {got} (기대 {(want_s, want_f)})")
    for name, line, want in STOP_CASES:
        got = _call(_TE, "is_skill_call", line)
        ok = got == want
        failed += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: {got} (기대 {want})")
    for name, status, want in DIAG_CASES:
        result = {"status": status}
        _call(_TE, "attach_diagnostics", result, "success", ["Read", "Skill"], "끝")
        got = "tool_calls" in result
        ok = got == want
        failed += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: tool_calls {'있음' if got else '없음'}")
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
    total = (len(CASES) + len(SUMMARIZE_CASES) + len(JUDGE_CASES)
             + len(STOP_CASES) + len(DIAG_CASES))
    print(f"\n결과: {total - failed}/{total} PASS")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
