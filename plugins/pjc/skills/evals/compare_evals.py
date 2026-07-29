#!/usr/bin/env python3
"""eval A/B 비교 — 두 run JSON의 증감표를 낸다.

사용법:
  python compare_evals.py <before.json> <after.json>

`trigger_eval.py`·`rubric_eval.py`가 저장한 결과 JSON **만** 읽는다. 러너를 호출하지 않으므로
모델 비용이 들지 않으며, 같은 입력으로 언제든 다시 돌릴 수 있다.

스킬 문구를 바꾼 뒤 "좋아진 것 같다"가 아니라 **무엇이 몇 점 오르고 무엇이 내렸는지**를 보기
위한 도구다. 그래서 개선만이 아니라 **회귀(악화) 항목을 따로 모아 보여준다** — 총점이 올라도
특정 케이스가 무너졌으면 그것이 알아야 할 사실이다.

통계 검정도 시각화도 하지 않는다(증감표 텍스트만). 편차가 잡음인지 신호인지는 러너가 함께
보고하는 편차 수치(rubric의 `deviation`)를 보고 사람이 판단한다.

exit code: 비교 완료 0 / 입력 오류·kind 불일치 1.
"""
import argparse
import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# 두 러너가 공유하는 것은 이 상위 구조뿐이다(코드는 공유하지 않는다).
REQUIRED_KEYS = ("run_id", "kind", "cases")


def load_run(path):
    """run JSON을 읽고 D4 상위 구조를 검증한다. 어긋나면 즉시 종료한다."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError as e:
        print(f"[중단] 파일을 읽을 수 없습니다: {path} ({e})")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"[중단] JSON 파싱 실패: {path} ({e})")
        sys.exit(1)
    missing = [k for k in REQUIRED_KEYS if k not in data]
    if missing:
        print(f"[중단] eval 결과 JSON이 아닙니다: {path}")
        print(f"       필수 키 누락: {', '.join(missing)} (필요: {', '.join(REQUIRED_KEYS)})")
        sys.exit(1)
    if not isinstance(data["cases"], list):
        print(f"[중단] cases가 배열이 아닙니다: {path}")
        sys.exit(1)
    return data


def align(before, after, key_field):
    """두 run의 케이스를 식별자로 짝짓고 (짝지어진 목록, before 전용, after 전용)을 반환한다."""
    b_map = {c[key_field]: c for c in before["cases"] if key_field in c}
    a_map = {c[key_field]: c for c in after["cases"] if key_field in c}
    common = [k for k in b_map if k in a_map]
    return ([(k, b_map[k], a_map[k]) for k in common],
            sorted(set(b_map) - set(a_map)),
            sorted(set(a_map) - set(b_map)))


def trigger_verdict(case):
    """트리거 케이스의 판정을 한 단어로 만든다. 판정 불가(timeout/error)는 그대로 노출한다."""
    if case.get("status") in ("timeout", "error"):
        return case["status"]
    return "발동" if case.get("fired") else "미발동"


def compare_trigger(before, after):
    """트리거 run 두 개를 비교해 케이스별 변화와 회귀 목록을 낸다."""
    pairs, only_b, only_a = align(before, after, "id")
    rows, regressions, improvements = [], [], []
    for cid, b, a in pairs:
        bv, av = trigger_verdict(b), trigger_verdict(a)
        b_ok, a_ok = b.get("status") == "pass", a.get("status") == "pass"
        if b_ok and not a_ok:
            mark, bucket = "회귀", regressions
        elif a_ok and not b_ok:
            mark, bucket = "개선", improvements
        else:
            mark, bucket = "", None
        if bucket is not None:
            bucket.append(f"{cid} ({b.get('expect')}): {bv} → {av}")
        rows.append((cid, b.get("expect", ""), bv, av, mark))

    if not pairs:
        print("  ⚠ 두 run에 공통인 케이스가 없습니다 — 비교된 항목은 0건입니다.")
    print(f"{'case':14s} {'기대':>11s} {'before':>8s} {'after':>8s}  변화")
    for cid, expect, bv, av, mark in rows:
        print(f"{cid:14s} {expect:>11s} {bv:>8s} {av:>8s}  {mark}")

    print("\n[요약 지표]")
    for label, key in (("발동률(should-trigger)", "trigger_rate"),
                       ("오발동률(should-not)", "false_trigger_rate")):
        bs = (before.get("summary") or {}).get(key)
        as_ = (after.get("summary") or {}).get(key)
        delta = f"{as_ - bs:+.3f}" if isinstance(bs, (int, float)) and isinstance(as_, (int, float)) else "—"
        print(f"  {label:24s} {bs} → {as_}  ({delta})")
    return regressions, improvements, only_b, only_a


def mean_score(case, key):
    """한 plan의 특정 루브릭 항목 평균 점수. 채점되지 않았으면 None."""
    values = [run["scores"][key]["score"] for run in case.get("runs", [])
              if key in run.get("scores", {})
              and isinstance(run["scores"][key]["score"], (int, float))
              and not isinstance(run["scores"][key]["score"], bool)]
    return sum(values) / len(values) if values else None


def compare_rubric(before, after):
    """루브릭 run 두 개를 비교해 plan × 항목 증감표와 회귀 목록을 낸다."""
    pairs, only_b, only_a = align(before, after, "plan")
    # 항목 목록은 양쪽에서 각각 읽어 교집합을 낸다 — 한쪽 목록만 기준으로 삼으면 반대쪽에만
    # 있는 항목이 '비교 제외' 목록에도 안 잡혀 조용히 사라진다(케이스 레벨의 only_b/only_a와
    # 같은 대칭성을 항목 레벨에도 둔다).
    before_keys = before.get("rubric_items") or []
    after_keys = after.get("rubric_items") or []
    common_keys = [k for k in before_keys if k in after_keys]
    dropped_keys = sorted((set(before_keys) | set(after_keys)) - set(common_keys))

    if not pairs:
        print("  ⚠ 두 run에 공통인 plan이 없습니다 — 비교된 항목은 0건입니다.")

    regressions, improvements = [], []
    for plan, b, a in pairs:
        print(f"\n■ {plan}")
        for key in common_keys:
            bs, as_ = mean_score(b, key), mean_score(a, key)
            if bs is None or as_ is None:
                # 한쪽이 N/A면 증감을 만들지 않는다 — 없는 점수를 0으로 두면 허위 낙폭이 생긴다.
                # None 여부로 판정한다(falsy로 보면 0.0점이 N/A로 둔갑한다).
                b_txt = "N/A" if bs is None else f"{bs:.1f}"
                a_txt = "N/A" if as_ is None else f"{as_:.1f}"
                print(f"    {key:26s} {b_txt:>6s} → {a_txt:>6s}   (비교 불가)")
                continue
            delta = as_ - bs
            mark = "회귀" if delta < 0 else ("개선" if delta > 0 else "")
            if delta < 0:
                regressions.append(f"{plan} / {key}: {bs:.1f} → {as_:.1f} ({delta:+.1f})")
            elif delta > 0:
                improvements.append(f"{plan} / {key}: {bs:.1f} → {as_:.1f} ({delta:+.1f})")
            print(f"    {key:26s} {bs:6.1f} → {as_:6.1f}  {delta:+5.1f}  {mark}")

    print("\n[요약 지표]")
    bs = (before.get("summary") or {}).get("mean_score")
    as_ = (after.get("summary") or {}).get("mean_score")
    delta = f"{as_ - bs:+.2f}" if isinstance(bs, (int, float)) and isinstance(as_, (int, float)) else "—"
    print(f"  전체 평균 {bs} → {as_}  ({delta})")
    for label, key in (("편차 평균", "mean_abs_deviation"), ("편차 최대", "max_abs_deviation")):
        print(f"  {label} {(before.get('summary') or {}).get(key)} → {(after.get('summary') or {}).get(key)}")
    if dropped_keys:
        print(f"  ⚠ 한쪽에만 있는 루브릭 항목(비교 제외): {', '.join(dropped_keys)}")
    return regressions, improvements, only_b, only_a


def compare(before, after):
    """kind에 맞는 비교를 수행하고 (회귀, 개선, before 전용, after 전용)을 반환한다."""
    if before["kind"] != after["kind"]:
        print(f"[중단] kind가 다른 run은 비교할 수 없습니다: "
              f"{before['kind']} vs {after['kind']}")
        sys.exit(1)
    if before["kind"] == "trigger":
        return compare_trigger(before, after)
    if before["kind"] == "rubric":
        return compare_rubric(before, after)
    print(f"[중단] 비교 방법을 모르는 kind입니다: {before['kind']}")
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description="pjc eval 결과 A/B 비교")
    ap.add_argument("before", help="변경 전 run JSON")
    ap.add_argument("after", help="변경 후 run JSON")
    args = ap.parse_args()

    before, after = load_run(args.before), load_run(args.after)
    print(f"== eval 비교 ({before['kind']}) ==")
    print(f"  before: {os.path.basename(args.before)} (run {before['run_id']})")
    print(f"  after : {os.path.basename(args.after)} (run {after['run_id']})\n")

    regressions, improvements, only_b, only_a = compare(before, after)

    # 교집합만 비교하므로, 빠진 것을 반드시 드러낸다 — 조용히 빼면 "비교했다"가 거짓이 된다.
    if only_b or only_a:
        print("\n[비교에서 제외된 항목]")
        for name in only_b:
            print(f"  before에만 있음: {name}")
        for name in only_a:
            print(f"  after에만 있음:  {name}")

    print(f"\n[회귀 {len(regressions)}건]")
    for line in regressions or ["  (없음)"]:
        print(f"  {line}" if regressions else line)
    print(f"\n[개선 {len(improvements)}건]")
    for line in improvements or ["  (없음)"]:
        print(f"  {line}" if improvements else line)
    sys.exit(0)


if __name__ == "__main__":
    main()
