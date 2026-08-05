#!/usr/bin/env python3
"""하니스 전역 정합 셀프체크 — 문서 로드 예산 · 리뷰어 각주 · 포인터 도달성 · 마커 목록 · Deferred 집계.

사용법: python plugins/pjc/evals/check-harness-consistency.py   (인자 없음 — repo 루트를 스스로 찾는다)

무엇을: 이 repo는 마크다운이 곧 실행 규칙이라, 문서가 서로 어긋나면 그것이 곧 동작 결함이다.
아래 다섯 축은 사람이 손으로 맞춰 온 지점들이며 실제로 어긋난 전례가 있다:

  ① 문서 로드 예산  — 스킬·리뷰어 파일의 바이트가 `docs/hook-conventions.md` 「문서 로드 예산
     기준선」 표와 일치하는가. 그 표는 조건부 절차를 references로 밀어낸 절감이 유지되는지를
     수치로 고정한다. 파일을 고친 task가 표를 갱신하지 않으면 여기서 잡힌다.
  ② 리뷰어 각주 앵커 — 리뷰어 4종이 복제 보유하는 규약 블록에 동기 신호(각주)가 전부 있는가.
     subagent는 자기 파일만 로드해 단일 소스화가 불가하므로 각주가 유일한 드리프트 신호다.
     **본문 동일성은 검사하지 않는다** — 네 파일의 같은 블록은 역할 차이로 실제로 다르다.
  ③ 포인터 도달성   — `<경로>` … 「<절 이름>」 형태의 크로스파일 포인터가 실제 헤딩에 닿는가.
     조건부 절차를 references로 이관하면 이 포인터가 유일한 연결이라, 끊기면 규칙이 사라진다.
  ④ 마커 목록 동기  — 정당 정지 마커의 전수 목록(정본)과 `implement-task/SKILL.md`의 대표 예시가
     어긋나지 않는가. v1.154.0 이전에 정본 6곳 ↔ 사본 8곳으로 역전돼 있었고, 그 차이가 곧
     오차단 경로였다.
  ⑤ Deferred 집계   — 대장의 「현행 잔량」 앵커가 실제 항목 수와 일치하는가. "정리 직후 수치만
     적고 등재분을 반영하지 않는" 실수가 이 대장의 반복 패턴이다.

왜 하드코딩하지 않는가: 검사 대상 목록·기대값을 코드에 박으면 문서가 바뀌어도 검사가 낡는다.
모든 기대값은 문서에서 파싱하며, 앵커를 못 찾으면 통과가 아니라 `[ANCHOR FAIL]`(exit 2)이다 —
"검사할 것을 못 찾았다"와 "검사했더니 일치한다"를 구분하지 않으면 공허한 green이 된다.

exit: 0 일치 / 1 불일치 / 2 앵커 파싱 실패   (llm-wiki `check_consistency.py`와 같은 규약)
"""
import os
import re
import sys

# repo 루트 = 이 파일의 3단계 상위 (plugins/pjc/evals/ → repo)
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

CONV_MD = os.path.join(ROOT, "docs", "hook-conventions.md")
LEDGER_MD = os.path.join(ROOT, "docs", "plans", "deferred.md")
IMPL_MD = os.path.join(ROOT, "plugins", "pjc", "skills", "implement-task", "SKILL.md")

# 9,000B 경계 = auto-compact 후 스킬이 앞 5,000토큰만 재부착된다는 사양에서 온 값.
# 이 상수만은 문서가 아니라 여기 둔다 — 표의 "경계 행" 열이 이 값으로 계산된 결과이므로,
# 문서에서 읽으면 계산식과 결과를 같은 곳에서 가져와 대조가 자기순환이 된다.
HEAD_BUDGET_BYTES = 9000


def die(msg):
    """앵커를 못 찾았다 — 검사 자체가 성립하지 않으므로 통과로 처리하지 않는다."""
    print("[ANCHOR FAIL] %s" % msg)
    sys.exit(2)


def read(path):
    if not os.path.exists(path):
        die("파일 없음: %s" % os.path.relpath(path, ROOT))
    return open(path, encoding="utf-8").read()


def section(text, heading_re, stop_re=r"^#{1,6} ", label=""):
    """헤딩으로 시작하는 절의 본문을 잘라낸다. 못 찾으면 ANCHOR FAIL."""
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if re.match(heading_re, l)), None)
    if start is None:
        die("절을 찾지 못함: %s" % (label or heading_re))
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(stop_re, lines[j]):
            end = j
            break
    return "\n".join(lines[start:end])


def measure(path):
    """파일 바이트(CRLF 포함) · 행 수 · 9,000B 경계 행."""
    size = os.path.getsize(path)
    lines = open(path, encoding="utf-8").read().split("\n")
    acc, edge = 0, 0
    for i, ln in enumerate(lines):
        acc += len(ln.encode("utf-8")) + 2  # CRLF
        if acc > HEAD_BUDGET_BYTES:
            edge = i + 1
            break
    return size, len(lines), edge


# ─────────────────────────────────────────────────────────────
# ① 문서 로드 예산
# ─────────────────────────────────────────────────────────────
def check_doc_budget(conv):
    sec = section(conv, r"^## 문서 로드 예산 기준선", label="문서 로드 예산 기준선")
    rows = re.findall(r"^\| `([^`]+)` \| ([\d,]+) \| (\d+) \| (\d+) \|$", sec, re.M)
    if not rows:
        die("「문서 로드 예산 기준선」 표에서 데이터 행을 추출하지 못함")
    issues = []
    for path, b, n, edge in rows:
        full = os.path.join(ROOT, path.replace("/", os.sep))
        if not os.path.exists(full):
            issues.append("예산 기준선: 파일 없음 %s" % path)
            continue
        real = measure(full)
        want = (int(b.replace(",", "")), int(n), int(edge))
        if real != want:
            issues.append("예산 기준선 %s — 표 %s / 실측 %s (바이트·행·경계행)"
                          % (path, want, real))
    return issues, len(rows)


# ─────────────────────────────────────────────────────────────
# ② 리뷰어 각주 앵커
# ─────────────────────────────────────────────────────────────
def check_reviewer_footnote(conv):
    sec = section(conv, r"^## 리뷰어 4종 공통 규약", label="리뷰어 4종 공통 규약")
    m = re.search(r"```\n([^\n]+)\n```", sec)
    if not m:
        die("「리뷰어 4종 공통 규약」에서 앵커 문자열(코드펜스)을 추출하지 못함")
    anchor = m.group(1).strip()
    blocks = re.findall(r"^\| \d+ \| `([^`]+)`", sec, re.M)
    if not blocks:
        die("「리뷰어 4종 공통 규약」에서 블록 목록 표를 추출하지 못함")
    files = sorted(re.findall(r"`(plan-reviewer|spec-compliance-reviewer|"
                              r"code-quality-reviewer|plan-completion-reviewer)`", sec))
    files = sorted(set(files))
    if len(files) != 4:
        die("「리뷰어 4종 공통 규약」에서 리뷰어 4종 이름을 추출하지 못함 (찾은 것: %s)" % files)
    issues = []
    for name in files:
        p = os.path.join(ROOT, "plugins", "pjc", "agents", name + ".md")
        if not os.path.exists(p):
            issues.append("리뷰어 각주: 파일 없음 %s.md" % name)
            continue
        cnt = read(p).count(anchor)
        if cnt != len(blocks):
            issues.append("리뷰어 각주 %s.md — 앵커 %d회 / 기대 %d회(블록 수)"
                          % (name, cnt, len(blocks)))
    return issues, len(files) * len(blocks)


# ─────────────────────────────────────────────────────────────
# ③ 포인터 도달성
# ─────────────────────────────────────────────────────────────
def _md_files():
    skip = {".git", "node_modules", "__pycache__", "notes-archive"}
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in skip]
        for n in names:
            if n.endswith(".md"):
                yield os.path.join(base, n)


def check_pointer_reachability():
    """`<경로>` … 「<절 이름>」 형태의 포인터가 대상 파일의 실제 헤딩에 닿는지 본다.

    세 축을 한 규칙으로 덮는다 — ⓐ 본체→references ⓑ 본체 내부(자기 경로 표기)
    ⓒ agents/·docs/·references/·다른 SKILL.md → 대상 파일. 경로가 명시된 참조만
    대상으로 삼는 이유는, 경로 없는 「…」는 강조 표기와 구분되지 않아 오탐이 크기 때문이다.
    """
    # `경로.md` 뒤 40자 안에 「절 이름」이 오는 형태
    pat = re.compile(r"`([A-Za-z0-9_./-]+\.md)`(?:[^「\n]{0,40})「([^」\n]{2,60})」")
    heading_cache = {}
    issues, checked = [], 0

    def anchors_of(path):
        """도달 대상 = 헤딩 ∪ 굵은 텍스트.

        이 repo는 절 앵커로 헤딩만 쓰지 않는다 — `**분해 전 — 기준 확보 …**`,
        `**▶ 현행 잔량(기계 대조 대상)**`, 표 행의 `**컨트롤 타입 대체 불가피 (V-9)**`처럼
        굵은 텍스트를 앵커로 삼는 관례가 실재한다. 헤딩만 보면 그 참조가 전부 오탐이 된다.
        """
        if path not in heading_cache:
            try:
                txt = open(path, encoding="utf-8").read()
            except OSError:
                heading_cache[path] = None
                return None
            hs = set()
            for line in txt.split("\n"):
                mm = re.match(r"^#{1,6} +(.+?)\s*$", line)
                if mm:
                    hs.add(mm.group(1).strip())
            hs.update(b.strip() for b in re.findall(r"\*\*([^*\n]{2,80})\*\*", txt))
            heading_cache[path] = hs
        return heading_cache[path]

    for src in _md_files():
        rel_src = os.path.relpath(src, ROOT).replace(os.sep, "/")
        # 과거 plan·로컬 노트는 그 시점의 기록이라 갱신 대상이 아니다(대장 관례)
        if rel_src.startswith("docs/plans/2026-") or rel_src in ("plan.md", "notes.md"):
            continue
        text = open(src, encoding="utf-8").read()
        for ref_path, sec_name in pat.findall(text):
            cand = []
            if ref_path.startswith(("docs/", "plugins/", ".claude-plugin/")):
                cand.append(os.path.join(ROOT, ref_path.replace("/", os.sep)))
            else:  # 상대 표기 — 원본 파일 기준, 그다음 repo 루트
                cand.append(os.path.join(os.path.dirname(src), ref_path.replace("/", os.sep)))
                cand.append(os.path.join(ROOT, ref_path.replace("/", os.sep)))
            target = next((c for c in cand if os.path.exists(c)), None)
            if target is None:
                continue  # 파일 자체를 못 찾는 경우는 이 축의 대상이 아니다(경로 표기 다양성)
            hs = anchors_of(target)
            if hs is None:
                continue
            checked += 1
            # 전체 일치 또는 앵커가 그 이름으로 시작(부제·괄호 꼬리 허용)
            if not any(h == sec_name or h.startswith(sec_name) for h in hs):
                issues.append("포인터 끊김: %s → `%s` 「%s」 (대상에 그 헤딩 없음)"
                              % (rel_src, ref_path, sec_name))
    if checked == 0:
        die("포인터 도달성: 검사 대상 포인터를 하나도 찾지 못함 (패턴이 낡았는지 확인)")
    return issues, checked


# ─────────────────────────────────────────────────────────────
# ④ 마커 목록 동기
# ─────────────────────────────────────────────────────────────
def check_marker_sync(conv, impl):
    sec = section(conv, r"^### 조건 4 — 정당 정지 신호 2층", label="조건 4 — 정당 정지 신호 2층")
    canon = set(re.findall(r"`## ([⛔⏸️][^`]+)`", sec))
    if not canon:
        die("조건 4에서 마커 전수 목록을 추출하지 못함")
    copy = set(re.findall(r"`## ([⛔⏸️][^`]+)`", impl))
    issues = []
    orphan = copy - canon
    if orphan:
        issues.append("마커 동기: 사본에만 있는 지점 %s — 정본(조건 4)에 없다" % sorted(orphan))
    # 사본은 대표 예시이므로 정본보다 적은 것은 정상. 역전(사본 ⊄ 정본)만 결함이다.
    return issues, len(canon)


# ─────────────────────────────────────────────────────────────
# ⑤ Deferred 집계
# ─────────────────────────────────────────────────────────────
def check_deferred_stats(ledger):
    m = re.search(r"현행 잔량\(기계 대조 대상\)\*\*: 대기 (\d+) / 종결 (\d+)", ledger)
    if not m:
        die("대장에서 「현행 잔량」 전용 앵커를 찾지 못함")
    lines = ledger.split("\n")
    try:
        w = next(i for i, l in enumerate(lines) if l.strip() == "## 대기")
        d = next(i for i, l in enumerate(lines) if l.strip() == "## 종결")
    except StopIteration:
        die("대장에서 `## 대기` / `## 종결` 구간 헤딩을 찾지 못함")
    # 대기는 날짜 '접두'만 본다 — `[등록일, **vN에서 부분 해소**]` 부기 형식이 실재해
    # `\]`로 닫으면 조용히 누락된다. 종결은 `[등록일 → 종결일]` 범위 형식.
    wait = sum(1 for l in lines[w:d] if re.match(r"^- \[\d{4}-\d{2}-\d{2}", l))
    done = sum(1 for l in lines[d:] if re.match(r"^- \[\d{4}-\d{2}-\d{2} → \d{4}-\d{2}-\d{2}\]", l))
    issues = []
    if (wait, done) != (int(m.group(1)), int(m.group(2))):
        issues.append("Deferred 집계 — 앵커 대기 %s/종결 %s / 실측 대기 %d/종결 %d"
                      % (m.group(1), m.group(2), wait, done))
    return issues, wait + done


def main():
    conv = read(CONV_MD)
    ledger = read(LEDGER_MD)
    impl = read(IMPL_MD)

    all_issues, parts = [], []
    for label, (issues, n) in [
        ("예산 기준선", check_doc_budget(conv)),
        ("리뷰어 각주", check_reviewer_footnote(conv)),
        ("포인터 도달성", check_pointer_reachability()),
        ("마커 동기", check_marker_sync(conv, impl)),
        ("Deferred 집계", check_deferred_stats(ledger)),
    ]:
        all_issues.extend(issues)
        parts.append("%s %d항목" % (label, n))

    print("== 하니스 정합 셀프체크 (문서 예산 · 리뷰어 각주 · 포인터 · 마커 · Deferred) ==")
    if all_issues:
        for m in all_issues:
            print("[MISMATCH] %s" % m)
        print("\n결과: 불일치 %d건 — 해당 파일을 고친 task가 기준선·앵커를 함께 갱신해야 합니다"
              "(`docs/hook-conventions.md` 「문서 로드 예산 기준선」 서문 참조)." % len(all_issues))
        sys.exit(1)
    print("결과: 대조 전부 일치 (%s)" % " + ".join(parts))
    sys.exit(0)


if __name__ == "__main__":
    main()
