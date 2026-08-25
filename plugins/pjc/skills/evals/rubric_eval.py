#!/usr/bin/env python3
"""plan 산출물 품질 루브릭 judge 러너.

사용법:
  python rubric_eval.py                       # docs/plans/의 전 plan을 2회씩 채점
  python rubric_eval.py --repeats 1           # 편차 측정 없이 1회만
  python rubric_eval.py --plans-dir <경로>    # 입력 세트 지정
  python rubric_eval.py --out-dir <경로>      # 결과 JSON 저장 위치

`rubric.md`의 8개 항목을 judge에게 그대로 실어 보내 각 plan을 1-10점으로 채점하고, **항목마다
근거 `파일:라인`을 함께 받는다.** 근거를 지목하지 못한 항목은 점수 대신 `N/A`로 남긴다 —
근거 없는 점수는 그럴듯한 숫자일 뿐이라 A/B 비교의 기준이 되지 못한다.

**동일 입력을 기본 2회 채점해 편차를 함께 보고한다.** judge 채점은 실행마다 흔들리므로, 편차를
모르면 "1점 올랐다"가 개선인지 잡음인지 구분할 수 없다.

judge 호출은 **중립 임시 cwd + 격리 CLAUDE_CONFIG_DIR**에서 한다. 프로젝트의 AGENTS.md·글로벌
CLAUDE.md가 채점 기준에 끼어들면 같은 plan이 환경에 따라 다른 점수를 받는다. 플러그인은
싣지 않는다 — judge는 스킬을 쓰지 않고 채점만 한다.

표준 라이브러리만 사용한다(pip install 불필요 — AGENTS.md 정합).

exit code: 전 plan 채점 완료 0 / 채점 실패가 있으면 1 / 환경·입력 실패 2.
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

EVALS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(EVALS_DIR))))
RUBRIC_MD = os.path.join(EVALS_DIR, "rubric.md")
DEFAULT_PLANS_DIR = os.path.join(REPO_ROOT, "docs", "plans")

# judge 호출 상한. plan 1건 채점은 도구 없이 한 턴에 끝나므로 턴은 1이면 충분하다.
MAX_TURNS = 1
# 30KB급 plan을 통째로 읽고 8항목을 채점하는 데 걸린 실측(1~2분)보다 넉넉히 잡는다.
JUDGE_TIMEOUT_SEC = 300
# 입력 상한(문자). 초과분은 잘라내되 **잘랐다는 사실을 리포트에 남긴다** — 조용한 절단은
# "뒷부분이 부실해서 낮은 점수"인지 "안 보여줘서 낮은 점수"인지 구분할 수 없게 만든다.
MAX_PLAN_CHARS = 30000

# plan 아카이브 파일명 규약(YYYY-MM-DD-<slug>.md). deferred.md 계열 대장 문서(v1.198.0부터
# deferred-closed.md·deferred-history.md 포함)를 plan으로 오인해 채점하지 않기 위한 필터다
# — 판정이 파일명 규약이라 대장이 몇 개로 갈리든 동작은 같다.
PLAN_NAME_RX = re.compile(r"^\d{4}-\d{2}-\d{2}-.+\.md$")
RUBRIC_KEY_RX = re.compile(r"^### \d+\..*\(([a-z_]+)\)\s*$", re.MULTILINE)


def load_rubric():
    """rubric.md 전문과 그 안에 정의된 항목 키 목록을 반환한다.

    키를 하드코딩하지 않고 rubric.md에서 뽑는 이유는, 루브릭을 고쳤는데 러너가 옛 항목을
    기대해 전부 '불일치'로 집계되는 어긋남을 막기 위해서다.
    """
    with open(RUBRIC_MD, encoding="utf-8") as fh:
        text = fh.read()
    keys = RUBRIC_KEY_RX.findall(text)
    if not keys:
        print(f"[중단] rubric.md에서 항목 키를 찾지 못했습니다: {RUBRIC_MD}")
        sys.exit(2)
    return text, keys


def collect_plans(plans_dir):
    """채점 대상 plan 파일 경로를 이름순으로 반환한다."""
    if not os.path.isdir(plans_dir):
        return []
    return [os.path.join(plans_dir, n) for n in sorted(os.listdir(plans_dir))
            if PLAN_NAME_RX.match(n)]


def build_prompt(rubric_text, plan_name, plan_text):
    """judge 프롬프트를 만든다. plan 본문에 라인 번호를 붙여 근거 지목을 가능하게 한다."""
    numbered = "\n".join(f"{i:5d}| {line}"
                         for i, line in enumerate(plan_text.splitlines(), 1))
    return (
        "당신은 소프트웨어 계획 문서를 평가하는 심사자입니다. 아래 루브릭에 따라 plan을 채점하세요.\n"
        "근거를 지목할 수 없는 항목은 점수 대신 \"N/A\"를 쓰고, 출력은 지정된 JSON 한 덩어리만 하세요.\n\n"
        "===== 루브릭 =====\n"
        f"{rubric_text}\n\n"
        f"===== 채점 대상: {plan_name} (각 줄 앞의 번호가 라인 번호입니다) =====\n"
        f"{numbered}\n"
    )


def extract_json(text):
    """judge 응답 텍스트에서 JSON 객체를 뽑는다.

    '코드펜스 없이 JSON만'을 지시해도 설명이 앞뒤로 붙는 경우가 있어, 첫 '{'부터 마지막 '}'까지를
    잘라 파싱한다(관대한 파싱 — 형식 흔들림으로 채점 자체를 잃지 않기 위해).
    """
    if not text:
        return None
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return None


def normalize_scores(raw, keys):
    """judge 응답을 루브릭 키 순서에 맞춰 정규화하고 (scores, 불일치 목록)을 반환한다.

    judge가 항목을 빠뜨리면 부족분을 N/A로 채우고 그 사실을 남긴다 — 조용히 채우면 '근거 없이
    낮은 점수'와 '채점되지 않음'이 구분되지 않는다.
    """
    got = (raw or {}).get("scores") or {}
    scores, issues = {}, []
    for key in keys:
        item = got.get(key)
        if not isinstance(item, dict):
            scores[key] = {"score": "N/A", "evidence": None, "note": "judge 응답에 항목 없음"}
            issues.append(f"항목 누락: {key}")
            continue
        score = item.get("score")
        if isinstance(score, bool) or not isinstance(score, (int, float)):
            score = "N/A"
        elif not 1 <= score <= 10:
            issues.append(f"범위 밖 점수({key}={score}) → N/A 처리")
            score = "N/A"
        evidence = item.get("evidence")
        if score != "N/A" and not evidence:
            # 루브릭 1번 규칙: 근거 없는 점수는 점수가 아니다.
            issues.append(f"근거 없는 점수({key}) → N/A 처리")
            score = "N/A"
        scores[key] = {"score": score, "evidence": evidence, "note": item.get("note")}
    for extra in got:
        if extra not in keys:
            issues.append(f"루브릭에 없는 항목: {extra}")
    return scores, issues


def prepare_isolated_config():
    """빈 CLAUDE_CONFIG_DIR을 만들고 인증 파일만 복사한다(채점 환경 고정)."""
    cfg = tempfile.mkdtemp(prefix="pjc-rubric-cfg-")
    src = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")
    if os.path.isfile(src):
        shutil.copy2(src, os.path.join(cfg, ".credentials.json"))
    return cfg


def kill_tree(proc):
    """자식까지 함께 종료한다. proc.kill()만으로는 claude가 띄운 하위 프로세스가 남는다.

    POSIX는 프로세스 그룹째 죽인다 — 그러려면 Popen이 `start_new_session=True`로 자식을 별도
    세션에 띄워야 하며(score_one이 그렇게 한다), 그래야 killpg가 러너 자신을 말려들게 하지 않는다.
    러너 간 코드를 공유하지 않는 설계라 trigger_eval.py와 같은 역할의 함수를 각자 갖는다.
    """
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                           capture_output=True, timeout=20)
        else:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (OSError, subprocess.SubprocessError):
        try:
            proc.kill()
        except OSError:
            pass


def score_one(prompt, model, config_dir, cwd):
    """judge를 1회 호출해 (파싱된 응답, 오류 문자열)을 반환한다. 오류 시 1회 재시도한다."""
    cmd = ["claude", "-p", "--output-format", "json",
           "--max-turns", str(MAX_TURNS), "--permission-mode", "manual"]
    if model:
        cmd += ["--model", model]
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    env["CLAUDE_CONFIG_DIR"] = config_dir

    last_err = "(사유 없음)"
    for _ in range(2):  # 네트워크·API 오류는 1회만 재시도 (trigger_eval.py와 동일 정책)
        proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", cwd=cwd, env=env,
            start_new_session=(os.name != "nt"),  # kill_tree의 POSIX 그룹 킬 전제
        )
        try:
            stdout, stderr = proc.communicate(input=prompt, timeout=JUDGE_TIMEOUT_SEC)
        except subprocess.TimeoutExpired:
            # 직계만 죽이면 claude가 띄운 하위 프로세스가 남아, 여러 plan을 순회하는 동안
            # 고아가 누적되고 임시 폴더 정리까지 조용히 실패한다.
            kill_tree(proc)
            try:
                proc.communicate(timeout=20)  # 파이프 정리
            except subprocess.SubprocessError:
                pass
            last_err = f"timeout ({JUDGE_TIMEOUT_SEC}s)"
            continue
        try:
            envelope = json.loads(stdout)
        except json.JSONDecodeError:
            last_err = (stderr.strip().splitlines() or ["stdout 파싱 실패"])[-1][:200]
            continue
        if envelope.get("is_error"):
            last_err = str(envelope.get("subtype") or envelope.get("result"))[:200]
            continue
        parsed = extract_json(envelope.get("result") or "")
        if parsed is None:
            last_err = "judge 응답에서 JSON을 찾지 못함"
            continue
        return parsed, None
    return None, last_err


def deviation(runs, keys):
    """같은 plan을 반복 채점했을 때 항목별로 벌어진 폭(최댓값 - 최솟값)을 낸다.

    2회면 두 점수의 절대차와 같고, `--repeats`를 3회 이상으로 올리면 전 회차의 폭을 본다 —
    앞 두 회차만 보면 세 번째 이후의 흔들림이 편차 통계에서 조용히 빠진다.
    한 회차라도 N/A면 계산하지 않고 그 사실을 남긴다 — N/A를 0점으로 취급하면 '채점 못 함'이
    '최하점'으로 둔갑한다.
    """
    if len(runs) < 2:
        return {}
    out = {}
    for key in keys:
        values = [r["scores"].get(key, {}).get("score") for r in runs]
        nums = [v for v in values if isinstance(v, (int, float)) and not isinstance(v, bool)]
        out[key] = max(nums) - min(nums) if len(nums) == len(runs) else "N/A"
    return out


def summarize(cases, keys):
    """전체 평균 점수와 편차 통계를 집계한다."""
    nums, devs = [], []
    for case in cases:
        for run in case.get("runs", []):
            nums += [s["score"] for s in run["scores"].values()
                     if isinstance(s["score"], (int, float))]
        devs += [d for d in case.get("deviation", {}).values() if isinstance(d, (int, float))]
    return {
        "plans": len(cases),
        "scored": sum(1 for c in cases if c["status"] == "scored"),
        "error": sum(1 for c in cases if c["status"] == "error"),
        "na_items": sum(1 for c in cases for r in c.get("runs", [])
                        for s in r["scores"].values() if s["score"] == "N/A"),
        "mean_score": round(sum(nums) / len(nums), 2) if nums else None,
        "mean_abs_deviation": round(sum(devs) / len(devs), 2) if devs else None,
        "max_abs_deviation": max(devs) if devs else None,
        "comparable_items": len(devs),
    }


def main():
    ap = argparse.ArgumentParser(description="pjc plan 산출물 품질 루브릭 eval")
    ap.add_argument("--plans-dir", default=DEFAULT_PLANS_DIR, help="채점 대상 plan 디렉터리")
    ap.add_argument("--repeats", type=int, default=2, help="plan당 채점 횟수 (기본 2 — 편차 측정)")
    ap.add_argument("--model", default="opus", help="judge 모델 (기본 opus — 기준선 재현성)")
    ap.add_argument("--filter", default="", help="plan 파일명 부분 일치 필터")
    ap.add_argument("--out-dir", default=os.path.join(tempfile.gettempdir(), "pjc-evals"),
                    help="결과 JSON 저장 위치 (기본: 시스템 임시 폴더)")
    args = ap.parse_args()

    if shutil.which("claude") is None:
        print("[중단] claude CLI를 찾을 수 없습니다. PATH를 확인하세요.")
        sys.exit(2)
    rubric_text, keys = load_rubric()
    plans = collect_plans(args.plans_dir)
    if args.filter:
        plans = [p for p in plans if args.filter in os.path.basename(p)]
    if not plans:
        print(f"[중단] 채점할 plan이 없습니다: {args.plans_dir}")
        sys.exit(2)

    run_id = time.strftime("%Y%m%d-%H%M%S")
    config_dir = prepare_isolated_config()
    neutral_cwd = tempfile.mkdtemp(prefix="pjc-rubric-cwd-")
    print(f"== plan 루브릭 eval — plan {len(plans)}건 × {args.repeats}회 (항목 {len(keys)}개) ==")

    cases = []
    try:
        for idx, path in enumerate(plans, 1):
            name = os.path.basename(path)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            truncated = len(text) > MAX_PLAN_CHARS
            if truncated:
                text = text[:MAX_PLAN_CHARS]
            prompt = build_prompt(rubric_text, name, text)

            case = {"plan": name, "chars": len(text), "truncated": truncated,
                    "runs": [], "issues": []}
            if truncated:
                case["issues"].append(f"입력이 {MAX_PLAN_CHARS}자로 절단됨(뒷부분 미채점)")
            started = time.time()
            for rep in range(args.repeats):
                parsed, err = score_one(prompt, args.model, config_dir, neutral_cwd)
                if err:
                    case["issues"].append(f"{rep + 1}회차 실패: {err}")
                    continue
                scores, issues = normalize_scores(parsed, keys)
                case["runs"].append({"scores": scores})
                case["issues"] += [f"{rep + 1}회차 {i}" for i in issues]
            case["duration_sec"] = round(time.time() - started, 1)
            case["deviation"] = deviation(case["runs"], keys)
            case["status"] = "scored" if case["runs"] else "error"

            if case["runs"]:
                shown = case["runs"][0]["scores"]
                brief = " ".join(f"{k.split('_')[0][:4]}={shown[k]['score']}" for k in keys)
                devs = [d for d in case["deviation"].values() if isinstance(d, (int, float))]
                dev_txt = f" | 편차 최대 {max(devs)}" if devs else ""
                print(f"[OK ] {idx}/{len(plans)} {name}  {case['duration_sec']:5.1f}s")
                print(f"       {brief}{dev_txt}")
            else:
                print(f"[ERR] {idx}/{len(plans)} {name} — {case['issues'][-1] if case['issues'] else '사유 미상'}")
            for issue in case["issues"]:
                print(f"       · {issue}")
            cases.append(case)
    finally:
        shutil.rmtree(config_dir, ignore_errors=True)
        shutil.rmtree(neutral_cwd, ignore_errors=True)

    summary = summarize(cases, keys)
    payload = {
        "run_id": run_id,
        "kind": "rubric",
        "model": args.model,
        "rubric_items": keys,
        "repeats": args.repeats,
        "plans_dir": args.plans_dir,
        "max_plan_chars": MAX_PLAN_CHARS,
        "retry_policy": "judge 호출 실패 시 1회 재시도 후 해당 회차 실패 처리",
        "summary": summary,
        "cases": cases,
    }
    os.makedirs(args.out_dir, exist_ok=True)
    out_path = os.path.join(args.out_dir, f"rubric-{run_id}.json")
    try:
        with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
    except OSError as e:
        print(f"[중단] 결과 JSON 저장 실패: {e}")
        sys.exit(1)

    print(f"\n  채점 {summary['scored']}/{summary['plans']} (error {summary['error']})")
    print(f"  평균 점수: {summary['mean_score']} · N/A 항목 {summary['na_items']}개")
    print(f"  편차 평균 {summary['mean_abs_deviation']} / 최대 {summary['max_abs_deviation']} "
          f"({summary['comparable_items']}개 항목 비교 가능)")
    print(f"  저장: {out_path}")
    sys.exit(1 if summary["error"] else 0)


if __name__ == "__main__":
    main()
