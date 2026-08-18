#!/usr/bin/env python3
"""index.md의 표시 라벨을 각 페이지 frontmatter의 `index_label`로 역이관한다 (1회성).

사용법: python migrate-index-labels.py "<vault_path>" [--apply]

기본은 dry-run이다 — 무엇을 넣을지만 출력하고 파일은 건드리지 않는다. `--apply`를 줘야 쓴다.

왜 필요한가: `lint.py --build-index`는 `index_label`을 라벨의 원천으로 삼는데, 기존 페이지는
그 필드를 갖고 있지 않다. 반면 현행 `index.md`에는 사람이 손으로 다듬은 한/영 병기 라벨이
들어 있다(그것이 §7-16·§7-27이 요구하는 표기다). 생성기를 먼저 돌리면 폴백 라벨(feature_name·
H1)이 그 병기 라벨을 덮어써 **입력 자체가 사라진다.** 그래서 순서가 정해져 있다:

    ① 이 스크립트 --apply        (인덱스 → frontmatter, 라벨을 페이지로 되돌린다)
    ② lint.py --build-index      (frontmatter → 인덱스, 이제 원천이 페이지에 있다)
    ③ index.md 교체              (생성 결과를 확인하고 반영)

**순서를 바꾸면 ①의 입력이 없어진다.** 되돌리기 기능은 만들지 않는다 — vault가 git이므로
`git checkout`이 그 역할을 한다(git이 아닌 vault라면 --apply 전에 사본을 떠 둘 것).

`lint.py`를 import하지 않고 독립 실행한다. 1회성 스크립트가 상시 도구에 결합하면 그 도구의
개정이 이 파일에 발목을 잡힌다.
"""
import glob
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

# 인덱스 표의 라벨은 두 형상 중 하나다.
#  ⓐ 첫 컬럼이 평문 라벨이고 다른 컬럼에 링크가 있다 (기능별 인덱스: `| 기능 | ... | [[경로|feature]] |`)
#  ⓑ 첫 컬럼 자체가 `[[경로|라벨]]` 링크다 (프로젝트·가이드·지식·질문 표)
# 표 행을 컬럼으로 쪼갤 때 wikilink 안의 이스케이프 `\|`를 잠시 치워 두는 표식.
#  본문에 등장할 수 없는 문자여야 한다(널 문자는 소스에 넣을 수 없어 제어문자를 쓴다).
SENTINEL = chr(1)

LINK_RX = re.compile(r"\[\[([^\]|]+)(?:\\?\|([^\]]*))?\]\]")


def normalize_target(t):
    """wikilink 대상 정규화 — 이스케이프 백슬래시 제거·#앵커 제거·트림 후 `.md` 부착."""
    t = t.replace("\\", "").split("#")[0].strip()
    if not t:
        return ""
    return t if t.endswith(".md") else t + ".md"


def labels_from_indexes(vault):
    """`index.md`·`index-*.md`의 표 행에서 {페이지 경로: [라벨, ...]}를 모은다.
    같은 페이지가 여러 인덱스에 나오면 라벨을 모두 담는다 — 불일치를 사람이 보게 하기 위함이다
    (조용히 첫 값을 쓰면 어느 쪽이 맞는지 아무도 모른 채 하나가 사라진다)."""
    found = {}
    for path in sorted(glob.glob(os.path.join(glob.escape(vault), "index*.md"))):
        try:
            with open(path, "rb") as fh:
                text = fh.read().decode("utf-8-sig")
        except (UnicodeDecodeError, OSError) as e:
            print("[SKIP] 인덱스 읽기 실패(%s): %s" % (type(e).__name__, os.path.basename(path)))
            continue
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        # 증상별 인덱스는 라벨 원천이 아니다 — 그 표의 첫 컬럼은 기능명이 아니라 **증상**(관찰
        #  표현)이고 행의 첫 링크는 해법 페이지다. 빼지 않으면 증상 문장이 그 feature의
        #  index_label로 들어간다(wiki-schema §6 「기능별 인덱스 행 검사에서 제외」와 같은 축).
        text = re.sub(r"^##\s*증상별 인덱스\b.*?(?=^##\s|\Z)", "", text, flags=re.M | re.S)
        for line in text.split("\n"):
            s = line.strip()
            if not s.startswith("|") or set(s) <= set("|- "):
                continue          # 표 행이 아니거나 구분선
            # 이스케이프 `\|`(wikilink 안의 구분자)는 컬럼 경계가 아니다 -- 그대로 split하면
            #  첫 컬럼이 `[[경로\` 로 잘려 링크를 놓치고, 잘린 조각이 라벨로 채택된다.
            cols = [c.strip().replace(SENTINEL, r"\|")
                    for c in s.replace(r"\|", SENTINEL).strip("|").split("|")]
            if not cols:
                continue
            links = LINK_RX.findall(s)
            if not links:
                continue
            first_links = LINK_RX.findall(cols[0])
            if first_links:
                # ⓑ 첫 컬럼이 링크 — 표시이름이 곧 라벨(없으면 라벨 원천이 아니다)
                target, alias = first_links[0]
                label = (alias or "").strip()
            else:
                # ⓐ 첫 컬럼이 평문 라벨 — 행의 첫 링크가 그 페이지다
                target, _alias = links[0]
                label = cols[0]
            rel = normalize_target(target)
            if not rel or not label:
                continue
            found.setdefault(rel, [])
            if label not in found[rel]:
                found[rel].append(label)
    return found


def frontmatter_span(text):
    """frontmatter 블록의 (시작, 끝) 인덱스. 없으면 None — 신설은 이 스크립트의 일이 아니다."""
    m = re.match(r"^---\n(.*?\n)---\n", text, re.S)
    return (m.start(1), m.end(1)) if m else None


def insert_label(text, label):
    """frontmatter 끝에 `index_label` 한 줄을 넣은 사본. 본문은 건드리지 않는다."""
    span = frontmatter_span(text)
    assert span, "frontmatter 없는 페이지는 호출 전에 걸러진다"
    head, body = text[:span[1]], text[span[1]:]
    return head + 'index_label: "%s"\n' % label.replace('"', "'") + body


def main():
    if len(sys.argv) < 2:
        print('사용법: python migrate-index-labels.py "<vault_path>" [--apply]')
        return 1
    vault = sys.argv[1].rstrip("/\\")
    apply_changes = "--apply" in sys.argv[2:]

    labels = labels_from_indexes(vault)
    if not labels:
        print("인덱스 표에서 라벨을 하나도 찾지 못했습니다 — vault 경로나 index.md 형식을 확인하세요.")
        return 1

    planned, already, no_label, no_fm, conflicts = [], [], [], [], []
    for p in sorted(glob.glob(os.path.join(glob.escape(vault), "**", "*.md"), recursive=True)):
        rel = os.path.relpath(p, vault).replace("\\", "/")
        if rel.startswith("90_archive/") or rel.startswith("index") or "/" not in rel:
            continue          # 아카이브·인덱스 자신·루트 파일(큐·log)은 대상이 아니다
        try:
            with open(p, "rb") as fh:
                text = fh.read().decode("utf-8-sig")
        except (UnicodeDecodeError, OSError):
            continue
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        span = frontmatter_span(text)
        if span is None:
            no_fm.append(rel)
            continue
        fm_text = text[span[0]:span[1]]
        if re.search(r"^index_label\s*:", fm_text, re.M):
            already.append(rel)
            continue
        cands = labels.get(rel)
        if not cands:
            no_label.append(rel)
            continue
        if len(cands) > 1:
            conflicts.append((rel, cands))
        planned.append((rel, cands[0], p, text))

    print("== index_label 역이관 %s ==" % ("--apply (파일 변경)" if apply_changes else "dry-run (파일 미변경)"))
    print("대상 %d건 · 라벨 미발견 %d건 · 이미 있음 %d건 · frontmatter 없음 %d건 · 라벨 충돌 %d건"
          % (len(planned), len(no_label), len(already), len(no_fm), len(conflicts)))
    print()
    for rel, label, _p, _t in planned:
        print("  %s\n      index_label: \"%s\"" % (rel, label))
    if conflicts:
        print("\n-- 라벨 충돌 (인덱스마다 다른 라벨 — 첫 값을 쓰되 사람이 확인할 것) --")
        for rel, cands in conflicts:
            print("  %s: %s" % (rel, " / ".join(cands)))
    if no_label:
        print("\n-- 라벨 미발견 (어느 인덱스 행에도 없다 — 미등록이거나 링크 형식이 다르다) --")
        for rel in no_label:
            print("  %s" % rel)
    if no_fm:
        print("\n-- frontmatter 없음 (신설은 이 스크립트의 일이 아니다) --")
        for rel in no_fm:
            print("  %s" % rel)
    if already:
        print("\n-- 이미 index_label 보유 (덮어쓰지 않는다 — 재실행 안전) --")
        for rel in already:
            print("  %s" % rel)

    if not apply_changes:
        print("\ndry-run이라 아무것도 쓰지 않았습니다. 적용하려면 --apply를 주세요.")
        print("적용 순서: ① 이 스크립트 --apply → ② lint.py --build-index → ③ index.md 교체")
        return 0

    written, failed = 0, []
    for rel, label, p, text in planned:
        try:
            with open(p, "wb") as fh:
                fh.write(insert_label(text, label).encode("utf-8"))
            written += 1
        except OSError as e:
            failed.append((rel, type(e).__name__))
    print("\n적용: %d건 기록%s" % (written, (" · 실패 %d건" % len(failed)) if failed else ""))
    for rel, err in failed:
        print("  [FAIL] %s (%s)" % (rel, err))
    print("다음: ② lint.py --build-index → ③ index.md 교체")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
