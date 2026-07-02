#!/usr/bin/env python3
"""llm-wiki lint.py 골든 회귀 러너.

사용법: python run_lint_evals.py   (llm-wiki/evals 폴더 기준, 인자 없음)

lint-cases.json의 각 case를 evals/fixtures/<fixture> vault에 대해 lint.py로 실행하고
결과를 대조한다:
  - expect_clean=true  → lint 출력에 '[ERR] 오류 0건'·'[WARN] 경고 0건'이 모두 있어야 PASS
                         (정상 vault를 경고하지 않는지 = 오탐 회귀 방지). INFO는 허용.
  - expect_keywords    → 나열된 키워드가 lint 출력에 모두 있으면 PASS (부분 매칭 —
                         lint 문구 미세 변경에 견고).

lint.py 자체는 수정하지 않고 subprocess로 호출만 한다(실사용 경로와 동일). 표준 라이브러리만
사용하며(테스트 프레임워크 없음 — AGENTS.md 정합), lint.py를 부른 것과 같은 인터프리터
(sys.executable)로 실행하므로 'python 부재'로 실패하지 않는다.

exit code: 전 case PASS면 0, 하나라도 FAIL이면 1.
"""
import json
import os
import subprocess
import sys

# Windows 콘솔(cp949)에서도 한글·em-dash가 깨지지 않도록 UTF-8 출력 강제 (lint.py와 동일)
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

EVALS_DIR = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(EVALS_DIR)
LINT_PY = os.path.join(SKILL_DIR, "scripts", "lint.py")
FIXTURES_DIR = os.path.join(EVALS_DIR, "fixtures")
CASES_JSON = os.path.join(EVALS_DIR, "lint-cases.json")


def run_lint(vault_path):
    """lint.py를 subprocess로 실행하고 (stdout, returncode, stderr)를 반환한다.
    returncode를 함께 넘겨, lint.py 자체 크래시와 '위반 검출 결과'를 호출부가 구분하게 한다."""
    proc = subprocess.run(
        [sys.executable, LINT_PY, vault_path],
        capture_output=True, text=True, encoding="utf-8",
    )
    return proc.stdout, proc.returncode, proc.stderr


def check_case(case):
    """한 case를 실행·대조해 (passed, detail) 반환."""
    fixture = case["fixture"]
    vault = os.path.join(FIXTURES_DIR, fixture)
    if not os.path.isdir(vault):
        return False, f"픽스처 폴더 없음: {vault}"
    # case 스키마 방어: 기대 조건이 하나도 없으면 오타로 조용히 PASS되는 것을 막는다.
    if "expect_clean" not in case and "expect_keywords" not in case:
        return False, "case에 expect_clean·expect_keywords 둘 다 없음(lint-cases.json 오타 의심)"

    out, rc, err = run_lint(vault)
    # lint.py 자체 크래시(런타임 예외 → nonzero exit)를 '위반 미검출'과 구분해 진단한다.
    #  lint.py는 정상 실행 시 위반이 있어도 exit 0이므로, rc!=0은 실제 예외를 의미한다.
    if rc != 0:
        tail = err.strip().splitlines()[-1] if err.strip() else "(stderr 없음)"
        return False, f"lint.py 비정상 종료(exit {rc}): {tail}"

    if case.get("expect_clean"):
        # 정상 vault: ERR·WARN 0이어야 한다(INFO는 허용).
        ok = ("[ERR] 오류 0건" in out) and ("[WARN] 경고 0건" in out)
        if ok:
            return True, "WARN/ERR 0 (정상)"
        return False, "위반 0을 기대했으나 ERR/WARN 발생"

    missing = [kw for kw in case.get("expect_keywords", []) if kw not in out]
    if missing:
        return False, "미검출 키워드: " + ", ".join(missing)
    return True, "검출: " + ", ".join(case.get("expect_keywords", []))


def main():
    if not os.path.isfile(LINT_PY):
        print(f"lint.py를 찾을 수 없음: {LINT_PY}")
        sys.exit(2)
    try:
        with open(CASES_JSON, encoding="utf-8") as fh:
            cases = json.load(fh)["cases"]
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print(f"lint-cases.json 로드 실패: {e}")
        sys.exit(2)

    print("== llm-wiki lint 골든 회귀 ==")
    passed = 0
    for case in cases:
        ok, detail = check_case(case)
        mark = "PASS" if ok else "FAIL"
        print(f"[{mark}] {case['fixture']} — {detail}")
        if ok:
            passed += 1

    total = len(cases)
    print(f"\n결과: {passed}/{total} PASS")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
