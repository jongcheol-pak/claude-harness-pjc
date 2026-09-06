#!/usr/bin/env python3
"""`plugins/pjc/evals/` 세 검사기의 골든 러너 — `cases.json` + `fixtures/`를 돈다.

무엇을: 케이스마다 픽스처를 임시 복사본으로 뜨고, **대상 검사기를 그 트리의 같은 상대
경로에 복사해** subprocess 로 돌린 뒤 종료 코드와 출력 문구를 대조한다.

  왜 사본을 픽스처 안에 두는가: 세 검사기 모두 repo 루트를 **자기 파일의 3단계 상위**로
  고정한다(표기는 둘이 `Path(__file__).resolve().parents[3]`, `check-harness-consistency.py` 가
  `os.path.abspath(os.path.join(..., "..", "..", ".."))` — 라인 번호는 문서 편집으로 밀린다). 인자도 환경변수도 주입 지점이 없으므로, 검사기를
  `<픽스처>/plugins/pjc/evals/` 에 놓는 것이 ROOT 를 픽스처로 만드는 유일한 방법이다.
  이 방식은 **검사기 코드를 고치지 않는다** — 테스트를 위해 프로덕션 경로에 훅을 내면
  그 훅 자체가 감시 밖의 분기가 된다.

  왜 `git init` 하는가: 「줄바꿈 정합」 축이 `git -C ROOT ls-files` 로 대상을 열거하고,
  실패하면 `die()` 로 **exit 2**(앵커 파싱 실패)를 낸다. 임시 디렉터리는 repo 가 아니라
  그대로 두면 모든 케이스가 2 로 죽는다.

케이스 스키마 (`cases.json`):
  id              케이스 이름
  checker         harness | truncation | stale  (`--filter` 가 이 필드와 매치한다)
  fixture         `fixtures/` 아래 디렉터리 이름
  mutate          [{file, find, replace}] — 사본에 넣을 변이. 생략하면 정상 케이스.
  cli_args        검사기에 줄 인자 (예: ["--ledger"])
  expect_rc       기대 종료 코드 (기본 0)
  expect_keywords 출력에 있어야 하는 문구
  expect_absent   출력에 없어야 하는 문구

**변이는 픽스처 사본에만 넣는다** — 축마다 픽스처를 따로 두면 정상 형상이 여러 벌이 되고,
한쪽만 고친 채 갈린다. 정상 골격은 하나이고 케이스가 그것을 한 군데씩 망가뜨린다.

전 case PASS면 exit 0, 하나라도 FAIL이면 1.
"""
import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# Windows 콘솔(cp949)에서도 한글·줄표가 깨지지 않도록 UTF-8 출력 강제.
#  형제 러너(`llm-wiki/evals/run_lint_evals.py`·`record-project-fact/evals/run_relocation_evals.py`)와
#  같은 관례다 — 이것이 없으면 문서가 안내한 그대로 실행할 때 UnicodeEncodeError 로 죽는다.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")
CASES = os.path.join(HERE, "cases.json")

# 검사기 이름 → 실제 파일. 사본은 픽스처의 `plugins/pjc/evals/` 에 같은 이름으로 놓인다.
CHECKERS = {
    "harness": "check-harness-consistency.py",
    "truncation": "check-comment-truncation.py",
    "stale": "check-stale-refs.py",
}


def build_tree(case):
    """픽스처를 임시 디렉터리로 복사하고 검사기 사본과 git 저장소를 놓는다."""
    fx = os.path.join(FIXTURES, case["fixture"])
    if not os.path.isdir(fx):
        return None, "픽스처 없음: " + case["fixture"]
    tmp = tempfile.mkdtemp(prefix="pjc-evals-")
    root = os.path.join(tmp, "repo")
    shutil.copytree(fx, root)

    checker = CHECKERS[case["checker"]]
    dst_dir = os.path.join(root, "plugins", "pjc", "evals")
    os.makedirs(dst_dir, exist_ok=True)
    shutil.copyfile(os.path.join(HERE, checker), os.path.join(dst_dir, checker))

    for mut in case.get("mutate", []):
        p = os.path.join(root, mut["file"].replace("/", os.sep))
        if not os.path.exists(p):
            return None, "변이 대상 없음: " + mut["file"]
        # 파일 삭제 변이 — 참조 대상의 **부재**를 재는 축(핵심 포인터 실재의 ⓐ 분기)은
        #   치환으로 표현할 수 없다. `find`/`replace` 없이 `delete` 만 적는다.
        if mut.get("delete"):
            os.remove(p)
            continue
        # `newline=""` 로 읽고 쓴다 — 텍스트 모드 변환이 CRLF 를 LF 로 바꾸면
        #   변이와 무관한 「줄바꿈 정합」 축이 함께 발화해 케이스의 판정이 갈린다.
        with io.open(p, encoding="utf-8", newline="") as fh:
            body = fh.read()
        if mut["find"] not in body:
            return None, "변이 앵커 불일치: %s / %r" % (mut["file"], mut["find"][:40])
        body = body.replace(mut["find"], mut["replace"])
        with io.open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(body)

    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1",
               GIT_AUTHOR_NAME="eval", GIT_AUTHOR_EMAIL="eval@local",
               GIT_COMMITTER_NAME="eval", GIT_COMMITTER_EMAIL="eval@local")
    for args in (["init", "-q"], ["add", "-A"]):
        r = subprocess.run(["git", "-C", root] + args, capture_output=True, env=env)
        if r.returncode != 0:
            return None, "git %s 실패: %s" % (args[0], r.stderr.decode("utf-8", "replace")[:120])
    return root, None


def run_case(case):
    root, err = build_tree(case)
    if err:
        return False, err, None
    try:
        checker = os.path.join(root, "plugins", "pjc", "evals", CHECKERS[case["checker"]])
        env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
        r = subprocess.run([sys.executable, checker] + case.get("cli_args", []),
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", env=env, cwd=root)
        out = (r.stdout or "") + (r.stderr or "")
        want = case.get("expect_rc", 0)
        if r.returncode != want:
            return False, "종료 코드 — 기대 %d / 실제 %d" % (want, r.returncode), out
        miss = [k for k in case.get("expect_keywords", []) if k not in out]
        if miss:
            return False, "출력 미검출: " + " · ".join(miss), out
        bad = [k for k in case.get("expect_absent", []) if k in out]
        if bad:
            return False, "출력에 금지 문구: " + " · ".join(bad), out
        return True, "rc=%d" % r.returncode, out
    finally:
        shutil.rmtree(os.path.dirname(root), ignore_errors=True)


# 케이스 블록은 **두 줄 계약**이다 — `  {` 가 자기 줄에 홀로 있고 **다음 줄이 `    "` 로 시작**한다.
#   **두 줄을 다 재는 이유**: 회차 25·26 이 `  {    "id": …` 로 붙여 넣었고 어느 검사기도 잡지 않았다
#   (JSON 은 유효하고 `Test(JSON 3종)` 은 매니페스트만 보며 이 러너도 파싱만 했다). 회차 27 이
#   앞줄만 재는 검사를 넣자 **그 처방이 개행만 넣고 들여쓰기를 빠뜨려** 같은 결함이 형태만 바꿔
#   남았다(완료 리뷰 BLOCKER). 한쪽만 재는 계약은 반대쪽으로 새는 자리를 만든다.
CASE_OPEN_RX = re.compile(r"^  \{\s*\S")
CASE_KEY_RX = re.compile(r'^    "')


def check_case_format(n_cases):
    """`cases.json` 원문의 들여쓰기 서식을 검사해 위반 줄 번호를 돌려준다.

    **축이 아니라 여기 있는 이유**: 이 파일은 이 러너의 입력이라 지역성이 맞고,
    `check-harness-consistency.py` 에 축을 더하면 열한 축이 되면서 `AGENTS.md`·
    `harness-conventions.md`·그 docstring 세 곳의 「열 축」 표기를 또 동기해야 한다.
    """
    with io.open(CASES, encoding="utf-8", newline="") as fh:
        lines = fh.read().splitlines()
    bad = [i + 1 for i, l in enumerate(lines) if CASE_OPEN_RX.match(l)]
    bad += [i + 2 for i, l in enumerate(lines)
            if l == "  {" and i + 1 < len(lines) and not CASE_KEY_RX.match(lines[i + 1])]
    # 위 둘은 **`  {` 형태를 전제**한다 — 중괄호 줄 자신이 그 형태를 벗어나면(뒤 공백·3칸·0칸)
    #   양쪽이 함께 꺼진다. 개수를 대조해 그 자리를 닫는다(완료 리뷰 MINOR).
    opens = sum(1 for l in lines if l == "  {")
    if opens != n_cases:
        bad.append(-1)  # 줄 하나로 짚을 수 없는 결함이라 음수 표식을 쓴다
    return sorted(bad), opens


def main():
    ap = argparse.ArgumentParser(description="pjc evals 골든 러너")
    ap.add_argument("--filter", help="checker 필드로 좁힌다 (harness | truncation | stale)")
    ap.add_argument("--verbose", action="store_true", help="FAIL 케이스의 전체 출력을 낸다")
    a = ap.parse_args()

    with io.open(CASES, encoding="utf-8") as fh:
        cases = json.load(fh)

    # 서식 결함은 「어떤 케이스가 틀렸다」가 아니라 **입력을 신뢰할 수 없다**는 뜻이라,
    #   케이스 FAIL 이 아니라 `check-harness-consistency.py` 와 같은 exit 2 를 쓴다.
    bad, opens = check_case_format(len(cases))
    if bad:
        where = ", ".join(str(i) for i in bad if i > 0) or "-"
        print("[FORMAT FAIL] cases.json 케이스 블록의 두 줄 계약 위반 — 줄 %s" % where)
        if -1 in bad:
            print("  여는 중괄호 줄(`  {`) %d개 ≠ 케이스 %d건 — 중괄호 줄 자신의 들여쓰기를 확인하세요."
                  % (opens, len(cases)))
        print("케이스를 돌리지 않고 멈춥니다. `  {` 는 자기 줄에 홀로 두고 "
              "다음 줄을 `    \"id\"` 로 4칸 들여쓰세요.")
        return 2
    if a.filter:
        cases = [c for c in cases if c["checker"] == a.filter]
    if not cases:
        print("케이스 없음 — --filter 값을 확인하세요 (harness | truncation | stale)")
        return 1

    failed = 0
    for c in cases:
        ok, msg, out = run_case(c)
        print("%s %-28s %s" % ("[PASS]" if ok else "[FAIL]", c["id"], msg))
        if not ok:
            failed += 1
            if a.verbose and out:
                print("  ---- 출력 ----")
                for line in out.splitlines():
                    print("  " + line)
    print("\n결과: %d/%d OK" % (len(cases) - failed, len(cases)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
