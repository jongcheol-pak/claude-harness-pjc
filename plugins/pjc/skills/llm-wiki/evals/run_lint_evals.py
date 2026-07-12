#!/usr/bin/env python3
"""llm-wiki lint.py 골든 회귀 러너.

사용법: python run_lint_evals.py   (llm-wiki/evals 폴더 기준, 인자 없음)

lint-cases.json의 각 case를 evals/fixtures/<fixture> vault에 대해 lint.py로 실행하고
결과를 대조한다:
  - expect_clean=true  → lint 출력에 '[ERR] 오류 0건'·'[WARN] 경고 0건'이 모두 있어야 PASS
                         (정상 vault를 경고하지 않는지 = 오탐 회귀 방지). INFO는 허용.
  - expect_keywords    → 나열된 키워드가 lint 출력에 모두 있으면 PASS (부분 매칭 —
                         lint 문구 미세 변경에 견고).
  - expect_absent      → (보조) 나열된 키워드가 lint 출력에 하나라도 있으면 FAIL —
                         "실재 경로는 경고하지 않는다" 같은 무경고 기대를 검증한다.
  - after_expect_keywords → (fix_mode 보조) --fix 후 재lint 출력에 전부 있어야 PASS —
                         "--fix가 건드리지 않아야 하는 위반의 잔존"(보수 동작)을 검증한다.
  - placeholder=true   → fixture를 임시 폴더로 복사한 뒤 .md 안의 __FIXTURE_ROOT__를
                         복사본 절대경로로 치환해 lint를 실행한다. §7-20처럼 '실재하는
                         절대경로'가 필요한 fixture를 기계 독립적으로 만든다 (opt-in —
                         기존 fixture는 그대로 원본 경로로 실행).

lint.py 자체는 수정하지 않고 subprocess로 호출만 한다(실사용 경로와 동일). 표준 라이브러리만
사용하며(테스트 프레임워크 없음 — AGENTS.md 정합), lint.py를 부른 것과 같은 인터프리터
(sys.executable)로 실행하므로 'python 부재'로 실패하지 않는다.

exit code: 전 case PASS면 0, 하나라도 FAIL이면 1.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

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


def run_lint(vault_path, extra_args=None):
    """lint.py를 subprocess로 실행하고 (stdout, returncode, stderr)를 반환한다.
    returncode를 함께 넘겨, lint.py 자체 크래시와 '위반 검출 결과'를 호출부가 구분하게 한다.
    extra_args: --fix 등 추가 인자(fix_mode 케이스용)."""
    proc = subprocess.run(
        [sys.executable, LINT_PY, vault_path] + (extra_args or []),
        capture_output=True, text=True, encoding="utf-8",
    )
    return proc.stdout, proc.returncode, proc.stderr


def prepare_placeholder_vault(fixture_dir):
    """fixture를 임시 폴더로 복사하고 .md 안의 __FIXTURE_ROOT__를 복사본 절대경로(슬래시
    정규화)로 치환한다. 반환: (정리용 임시 루트, lint에 넘길 vault 경로).
    §7-20 실존 검사는 허브 '레포 정보 > 경로'가 실재 디렉터리여야 동작하는데, 체크인된
    fixture에 절대경로를 박으면 다른 PC에서 깨지므로 실행 시점에 만들어 넣는다."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    root_token = dest.replace("\\", "/")
    for dirpath, _dirs, files in os.walk(dest):
        for name in files:
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            if "__FIXTURE_ROOT__" in text:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(text.replace("__FIXTURE_ROOT__", root_token))
    return tmp, dest


def prepare_bad_encoding_vault(fixture_dir):
    """fixture를 임시 폴더로 복사하고 CP949(비 UTF-8) .md 파일 1개를 주입한다(M-2 격리 검증).
    비 UTF-8 파일을 레포에 체크인하면 git·에디터가 손상시킬 수 있어 실행 시점에 만든다.
    반환: (정리용 임시 루트, lint에 넘길 vault 경로)."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-badenc-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    bad = os.path.join(dest, "20_projects", "personal", "demo", "feat-badenc.md")
    with open(bad, "wb") as fh:
        fh.write("---\ntype: feature\n---\n한글 CP949 본문".encode("cp949"))
    return tmp, dest


def check_case(case):
    """한 case를 실행·대조해 (passed, detail) 반환."""
    fixture = case["fixture"]
    vault = os.path.join(FIXTURES_DIR, fixture)
    if not os.path.isdir(vault):
        return False, f"픽스처 폴더 없음: {vault}"
    # case 스키마 방어: 기대 조건이 하나도 없으면 오타로 조용히 PASS되는 것을 막는다.
    if "expect_clean" not in case and "expect_keywords" not in case:
        return False, "case에 expect_clean·expect_keywords 둘 다 없음(lint-cases.json 오타 의심)"

    # fix_mode 케이스: fixture를 임시 복사본에서 --fix 실행 → 재lint로 위반 해소를 대조한다.
    #  원본 fixture는 절대 수정하지 않는다(placeholder copytree 패턴 재사용). 대조 3단 —
    #  ① --fix 실행 출력에 expect_keywords([FIXED] 요약) 전부 존재
    #  ② 수정 후 재lint 출력에 after_expect_absent(원 위반 문구) 전부 부재
    #  ③ 수정 후 재lint 출력에 after_expect_keywords 전부 존재 — "--fix가 건드리지 않아야 하는
    #     위반이 그대로 남았는가"(보수 동작: §7-24 섹션 밖 비제거 등)를 실증하는 보조 필드
    if case.get("fix_mode"):
        tmp = tempfile.mkdtemp(prefix="lint-eval-fix-")
        dest = os.path.join(tmp, os.path.basename(vault))
        shutil.copytree(vault, dest)
        out1, rc1, err1 = run_lint(dest, ["--fix"])
        out2, rc2, err2 = run_lint(dest)
        shutil.rmtree(tmp, ignore_errors=True)
        if "== llm-wiki Lint:" not in out1 or "== llm-wiki Lint:" not in out2:
            tail = (err1 or err2).strip().splitlines()[-1] if (err1 or err2).strip() else "(stderr 없음)"
            return False, f"lint.py 비정상 종료(fix={rc1}/재실행={rc2}): {tail}"
        missing = [kw for kw in case.get("expect_keywords", []) if kw not in out1]
        if missing:
            return False, "--fix 출력 미검출 키워드: " + ", ".join(missing)
        residual = [kw for kw in case.get("after_expect_absent", []) if kw in out2]
        if residual:
            return False, "수정 후 재lint에 위반 잔존: " + ", ".join(residual)
        missing2 = [kw for kw in case.get("after_expect_keywords", []) if kw not in out2]
        if missing2:
            return False, "수정 후 재lint 기대 키워드 미검출(비제거 대상이 사라짐 의심): " + ", ".join(missing2)
        return True, "--fix 적용·재lint 해소 확인: " + ", ".join(case.get("expect_keywords", []))

    tmp = None
    if case.get("placeholder"):
        tmp, vault = prepare_placeholder_vault(vault)
    elif case.get("bad_encoding"):
        tmp, vault = prepare_bad_encoding_vault(vault)
    out, rc, err = run_lint(vault)
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    # lint.py는 ERR가 있으면 exit 1(L-5 — A-4/B-3 자동 게이트용), 없으면 0, 사용법 오류 2다.
    #  정상 실행은 stdout에 리포트 헤더('== llm-wiki Lint:')를 내므로, 헤더가 있으면 rc와 무관하게
    #  결과를 파싱한다(exit 1이 곧 ERR 검출이라 위반 fixture는 정상이다). 헤더가 없는 종료만
    #  진짜 크래시(런타임 예외)로 보고 FAIL 처리한다.
    if "== llm-wiki Lint:" not in out:
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
    present = [kw for kw in case.get("expect_absent", []) if kw in out]
    if present:
        return False, "부재 기대 키워드가 출력에 존재(오탐): " + ", ".join(present)
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
