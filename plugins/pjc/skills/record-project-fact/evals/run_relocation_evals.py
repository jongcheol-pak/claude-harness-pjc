# -*- coding: utf-8 -*-
"""AGENTS.md 이관 골든 러너 — `relocation-cases.json` + `fixtures/`를 돈다.

각 케이스는 픽스처를 **임시 복사본으로** 뜨고 거기서 수행한다(픽스처 원본 무수정).
모드는 둘이다:
  - 기본: `relocate()`를 돌리고 stdout 키워드·결과 파일 내용을 대조한다.
  - `verify_only`: `verify()`를 직접 불러 **검증이 실제로 잡는가**를 본다 — 정상 경로만
    돌리면 검증 함수는 늘 통과라 「잡는다」가 증명되지 않는다(델타 음성).

전 case PASS면 exit 0, 하나라도 FAIL이면 1.
"""
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile

# Windows 콘솔(cp949)에서도 한글·줄표가 깨지지 않도록 UTF-8 출력 강제.
#  형제 스크립트(`llm-wiki/evals/run_lint_evals.py`·`evals/check-harness-consistency.py`)와
#  같은 관례다 — 이것이 없으면 문서가 안내한 그대로 실행할 때 UnicodeEncodeError로 죽는다.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "relocate-agents.py")
FIXTURES = os.path.join(HERE, "fixtures")
CASES = os.path.join(HERE, "relocation-cases.json")


def load_script():
    spec = importlib.util.spec_from_file_location("relocate_agents", os.path.normpath(SCRIPT))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_case(mod, case):
    fx = os.path.join(FIXTURES, case["fixture"])
    if not os.path.isdir(fx):
        return False, "픽스처 없음: " + case["fixture"]
    tmp = tempfile.mkdtemp(prefix="reloc-eval-")
    dest = os.path.join(tmp, case["fixture"])
    shutil.copytree(fx, dest)
    try:
        if case.get("verify_only"):
            # 검증 함수를 직접 태운다 — 인자는 픽스처 파일에서 읽는다.
            agents = open(os.path.join(dest, "AGENTS.md"), "rb").read()
            dpath = os.path.join(dest, case["dest_rel"].replace("/", os.sep))
            draw = open(dpath, "rb").read() if os.path.exists(dpath) else b""
            ok, problems = mod.verify(agents, draw, case["dest_rel"],
                                      case.get("limit", 16384), agents)
            want = case.get("expect_ok", False)
            if ok != want:
                return False, "검증 결과 불일치 — 기대 %s / 실제 %s (%s)" % (
                    want, ok, "; ".join(problems) or "문제 없음")
            for needle in case.get("expect_problems", []):
                if not any(needle in p for p in problems):
                    return False, "기대한 문제 미검출: " + needle
            return True, "검증 대조: " + ("통과" if ok else "; ".join(problems))

        before = {}
        for rel in case.get("expect_unchanged", []):
            before[rel] = open(os.path.join(dest, rel.replace("/", os.sep)), "rb").read()
        orig_verify = mod.verify
        if case.get("sabotage_verify"):
            # 검증을 강제로 실패시켜 **원복 경로**를 태운다. 정상 경로만 돌리면 그 코드는
            #  한 번도 실행되지 않고, 결함이 있어도 골든이 침묵한다.
            mod.verify = lambda *a, **k: (False, ["강제 실패(원복 경로 검증용)"])
        try:
            code, log = mod.relocate(dest, case.get("dry_run", False))
        finally:
            mod.verify = orig_verify
        out = "\n".join(log)
        if code != case.get("expect_rc", 0):
            return False, "종료 코드 불일치 — 기대 %d / 실제 %d (%s)" % (
                case.get("expect_rc", 0), code, out[:120])
        missing = [k for k in case.get("expect_keywords", []) if k not in out]
        if missing:
            return False, "출력 미검출: " + ", ".join(missing)
        present = [k for k in case.get("expect_absent", []) if k in out]
        if present:
            return False, "출력에 금지 키워드: " + ", ".join(present)
        for rel, needles in (case.get("expect_file_contains") or {}).items():
            fp = os.path.join(dest, rel.replace("/", os.sep))
            if not os.path.exists(fp):
                return False, "결과 파일 없음: " + rel
            ft = io.open(fp, encoding="utf-8-sig").read()
            miss = [n for n in needles if n not in ft]
            if miss:
                return False, "%s에 기대 문자열 없음: %s" % (rel, ", ".join(miss))
        for rel in case.get("expect_absent_files", []):
            if os.path.exists(os.path.join(dest, rel.replace("/", os.sep))):
                return False, "원복 후에도 남아 있다: " + rel
        for rel, raw in before.items():
            now = open(os.path.join(dest, rel.replace("/", os.sep)), "rb").read()
            if now != raw:
                return False, "원복되지 않았다: " + rel
        return True, out.splitlines()[0] if out else "(무출력)"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    mod = load_script()
    cases = json.load(io.open(CASES, encoding="utf-8"))["cases"]
    failed = 0
    for case in cases:
        ok, msg = run_case(mod, case)
        print("[%s] %s — %s" % ("PASS" if ok else "FAIL", case["fixture"], msg))
        if not ok:
            failed += 1
    print("\n결과: %d/%d PASS" % (len(cases) - failed, len(cases)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
