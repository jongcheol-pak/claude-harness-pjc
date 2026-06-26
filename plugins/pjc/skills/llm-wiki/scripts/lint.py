#!/usr/bin/env python3
"""llm-wiki Lint 보조 스크립트.

사용법: python lint.py "<vault_path>"
검사: 깨진/경로 없는 wikilink / 예산 초과 / platform·origin·confidence 통제어휘 위반·누락
      / 고아 페이지(간이) / 신선도(60·90일)·미래 날짜 / 기능별 인덱스·허브 동기화 / 네이밍 규칙 / 타입 미지정
      / tech_stack 휘발성 버전 / (미검증)·미해결 question 집계(INFO).
출력: 사람이 읽는 보고(오류/경고/정보). 파일은 수정하지 않는다(읽기 전용).
규칙 진실원천은 references/wiki-schema.md. 예산/통제어휘가 바뀌면 이 상수도 함께 갱신할 것
(SKILL.md H-2: SKILL 예산표·wiki-schema §3~§4·이 파일 3중 동기화).
"""
import os, re, sys, glob, datetime

# Windows 콘솔(cp949)에서도 한글이 깨지지 않도록 UTF-8 출력 강제
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

BUDGET = {  # type -> 최대 줄 수 (wiki-schema.md §4와 일치 유지)
    "source-stub": 30, "project": 120, "feature": 180,
    "entity": 100, "concept": 80, "question": 40,
}
GUIDE_BUDGET = {"platform-bootstrap": 200, "ui-ux": 150, "recipe": 120}
PLATFORM_VOCAB = {"windows-desktop", "web", "mobile", "cli", "cross"}
ORIGIN_VOCAB = {"agent-synthesized", "human-validated"}
CONFIDENCE_VOCAB = {"high", "medium", "low"}
# origin/confidence 필수 타입 화이트리스트 (wiki-schema.md §3 — source-stub/question/인프라 타입 제외)
ORIGIN_REQUIRED_TYPES = {"feature", "project", "entity", "concept", "guide"}
SPECIAL_BUDGET = {"log.md": 60}
# 신선도·고아·타입 검사에서 제외하는 인프라 타입 (위키 본문 페이지가 아님)
INFRA_TYPES = {"index", "log", "dashboard", "schema"}
# 신선도: 90일 아카이브 후보에서 제외하는 타입 (wiki-schema.md §8 예외 2)
ARCHIVE_EXEMPT_TYPES = {"feature", "guide"}


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    fm = {}
    if m:
        for line in m.group(1).splitlines():
            mm = re.match(r"\s*([A-Za-z_]+)\s*:\s*(.*)", line)
            if mm:
                fm[mm.group(1)] = mm.group(2).strip().strip('"')
    return fm


def parse_date(s):
    try:
        return datetime.date.fromisoformat(s)
    except Exception:
        return None


def main():
    if len(sys.argv) < 2:
        print("사용법: python lint.py \"<vault_path>\"")
        sys.exit(1)
    vault = sys.argv[1].rstrip("/\\")
    md = [f for f in glob.glob(os.path.join(vault, "**", "*.md"), recursive=True)]
    rel = lambda p: os.path.relpath(p, vault).replace("\\", "/")
    existing = {rel(p)[:-3] for p in md}  # 확장자 제거한 상대경로 집합
    today = datetime.date.today()

    errors, warns, infos = [], [], []
    unverified_hits, unverified_files = 0, 0  # (미검증) 집계 (wiki-schema §7-12)
    open_questions = 0                        # 미해결 question 집계 (〃)
    feat_files, index_feat_links = set(), set()
    link_targets = set()   # 위키 전체에서 링크된 대상 (고아 검사용)
    pages = {}             # rel -> (frontmatter, type, 본문 텍스트)

    for p in md:
        r = rel(p)
        with open(p, encoding="utf-8") as fh:
            text = fh.read()
        lines = text.count("\n") + 1
        fm = frontmatter(text)
        typ = fm.get("type", "")
        pages[r] = (fm, typ, text)
        is_root = "/" not in r
        in_archive = r.startswith("90_archive/")

        # wikilink: 깨진 링크(경로형) + 경로 없는 링크(명시적 경로 필수 위반)
        for m in re.findall(r"\[\[([^\]|]+)", text):
            t = m.replace("\\", "").split("#")[0].strip()
            if not t:
                continue
            link_targets.add(t)
            if "/" in t:
                if t not in existing:
                    errors.append(f"깨진 링크: {r} -> [[{t}]]")
            elif t not in existing:  # 루트 파일(index 등)로도 해석되지 않으면 위반
                warns.append(f"경로 없는 wikilink(명시적 경로 필수): {r} -> [[{t}]]")

        # 예산
        budget = None
        if r in SPECIAL_BUDGET:
            budget = SPECIAL_BUDGET[r]
        elif typ == "guide":
            budget = GUIDE_BUDGET.get(fm.get("guide_kind", ""), 200)
        elif typ in BUDGET:
            budget = BUDGET[typ]
        if budget and lines > budget:
            warns.append(f"예산 초과: {r} {lines}/{budget}줄 (type={typ})")

        # platform 통제어휘
        plat = fm.get("platform")
        if plat and plat not in PLATFORM_VOCAB:
            errors.append(f"platform 통제어휘 위반: {r} -> '{plat}'")

        # tech_stack 휘발성 버전 검사 (wiki-schema §2.1·§2.2·§7-11):
        #  ⓐ 소스 스텁 "기술 스택" 본문 줄, ⓑ project 허브 tech_stack frontmatter 값에서
        #  major.minor 이상 버전(\d+\.\d+) 발견 시 경고. ".NET 10"·"WinUI 3" 등 major-only는 미매칭(허용).
        if r.startswith("10_sources/"):
            for line in text.splitlines():
                if "기술 스택" in line and re.search(r"\d+\.\d+", line):
                    warns.append(f"소스 스텁 휘발성 버전 기재: {r} (기술 스택은 이름만, 버전 제외)")
                    break
        if typ == "project":
            ts = fm.get("tech_stack", "")
            if re.search(r"\d+\.\d+", ts):
                warns.append(f"허브 tech_stack 휘발성 버전 기재: {r} (이름만, 버전 진실원천은 코드)")

        # origin/confidence: 화이트리스트 타입만 검사 (type 매칭만으로 수행, 신선도 로직과 무관)
        if typ in ORIGIN_REQUIRED_TYPES and not in_archive:
            for key, vocab in (("origin", ORIGIN_VOCAB), ("confidence", CONFIDENCE_VOCAB)):
                val = fm.get(key)
                if not val:
                    warns.append(f"{key} 누락: {r} (type={typ})")
                elif val not in vocab:
                    errors.append(f"{key} 통제어휘 위반: {r} -> '{val}'")

        # 미래/이상 날짜 + 신선도 (updated 필드 보유 페이지만)
        raw_upd = fm.get("updated", "")
        upd = parse_date(raw_upd) if raw_upd else None
        if raw_upd and upd is None:
            warns.append(f"updated 형식 이상: {r} -> '{raw_upd}'")
        if upd:
            if upd > today:
                errors.append(f"미래 날짜: {r} updated={upd}")
            elif typ not in INFRA_TYPES and not in_archive and fm.get("status") != "paused":
                days = (today - upd).days
                if days >= 90 and typ not in ARCHIVE_EXEMPT_TYPES:
                    infos.append(f"90일+ 미편집(아카이브 후보): {r} ({days}일)")
                elif days >= 60:
                    infos.append(f"60일+ 미편집(confidence 하락 후보): {r} ({days}일)")

        # 네이밍 규칙
        base = os.path.basename(r)
        if r.startswith("10_sources/") and not re.fullmatch(r"src-[a-z0-9-]+\.md", base):
            warns.append(f"네이밍 위반(src-*): {r}")
        if typ == "feature" and not re.fullmatch(r"feat-[a-z0-9-]+\.md", base):
            warns.append(f"네이밍 위반(feat-*): {r}")
        if r.startswith("30_knowledge/questions/") and not re.fullmatch(
                r"(q-\d{8}-[a-z0-9-]+|lint-\d{8})\.md", base):
            warns.append(f"네이밍 위반(q-YYYYMMDD-* / lint-YYYYMMDD): {r}")

        # 타입 미지정 (루트 인프라 파일·아카이브 제외)
        if not typ and not is_root and not in_archive:
            warns.append(f"타입 미지정 파일: {r}")

        # (미검증)·미해결 question 집계 (§7-12) — 20_/30_/40_ 본문만(frontmatter 제외),
        # 10_sources(불변 스텁, 검증 루프 대상 아님)·90_archive·루트 인프라는 범위 밖
        if r.startswith(("20_", "30_", "40_")):
            body = re.sub(r"^---\n.*?\n---", "", text, count=1, flags=re.S)
            hits = body.count("(미검증)")
            if hits:
                unverified_hits += hits
                unverified_files += 1
            if typ == "question" and fm.get("status") != "resolved":
                open_questions += 1

        if typ == "feature":
            feat_files.add(r[:-3])

    # 기능별 인덱스 ↔ feature 동기화
    idx = os.path.join(vault, "index.md")
    if os.path.isfile(idx):
        with open(idx, encoding="utf-8") as fh:
            itext = fh.read()
        # 인덱스가 sub-index 파일(index-*.md)로 분할된 경우 그 내용도 합쳐서 검사 (분할 시 누락 오탐 방지)
        for sub in sorted(glob.glob(os.path.join(vault, "index-*.md"))):
            try:
                with open(sub, encoding="utf-8") as sfh:
                    itext += "\n" + sfh.read()
            except OSError:
                pass
        for m in re.findall(r"\[\[([^\]|]+)", itext):
            t = m.replace("\\", "").split("#")[0].strip()  # #앵커 제거(메인 루프 링크 파싱과 일치)
            if "/feat-" in t:
                index_feat_links.add(t)
        for f in sorted(feat_files - index_feat_links):
            warns.append(f"기능별 인덱스 누락: {f} (feature인데 index 미등록)")

    # 허브 "기능 목록" ↔ feature 동기화 (feat 파일이 허브 본문에 링크돼 있는지)
    for r, (fm, typ, text) in pages.items():
        if typ != "project":
            continue
        hub_base = r[:-3]
        hub_text = text.replace("\\", "")
        for f in sorted(feat_files):
            if f.startswith(hub_base + "/") and f not in hub_text:
                warns.append(f"허브 기능 목록 누락: {r} -> {f}")

    # 고아 페이지(간이): 어디서도 링크되지 않는 페이지 (루트 인프라·아카이브 제외)
    for r, (fm, typ, _) in sorted(pages.items()):
        if "/" not in r or r.startswith("90_archive/") or typ in INFRA_TYPES:
            continue
        if r[:-3] not in link_targets:
            warns.append(f"고아 페이지(어디서도 링크되지 않음): {r}")

    # (미검증)·미해결 question 집계 리포트 — 사용자 검증 후보 (0건이면 생략, wiki-schema §11)
    if unverified_hits:
        infos.append(f"(미검증) 표기 {unverified_hits}건 / {unverified_files}개 파일 — 사용자 검증 후보")
    if open_questions:
        infos.append(f"미해결 question {open_questions}건 — 사용자 검증 후보")

    # 보고
    print(f"== llm-wiki Lint: {vault} ==")
    print(f"검사 파일: {len(md)}개")
    for label, items, mark in (("오류", errors, "[ERR]"), ("경고", warns, "[WARN]"),
                               ("정보", infos, "[INFO]")):
        print(f"\n{mark} {label} {len(items)}건")
        for it in items:
            print(f"  - {it}")
    if not errors and not warns:
        print("\n[OK] 오류·경고 없음.")


if __name__ == "__main__":
    main()
