#!/usr/bin/env python3
"""llm-wiki Lint 보조 스크립트.

사용법: python lint.py "<vault_path>"
검사: 깨진/경로 없는 wikilink / 예산 초과 / platform·origin·confidence 통제어휘 위반·누락
      / 고아 페이지(간이) / 신선도(60·90일)·미래 날짜 / 기능별 인덱스·허브 동기화 / 네이밍 규칙 / 타입 미지정
      / tech_stack 휘발성 버전 / index·sub-index 분할 신호(INFO) / deprecated 표기 정합·집계 / feature 구현 근거 각주
      / log 아카이브 인덱스 정합
      / (미검증)·미해결 question 집계(INFO).
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
# log.md는 문자 수 예산(줄 수 아님 — 한 항목이 길면 줄 수가 실제 분량을 못 담음, wiki-schema §4·§8)
SPECIAL_BUDGET = {"log.md": 6000}
# 신선도·고아·타입 검사에서 제외하는 인프라 타입 (위키 본문 페이지가 아님)
INFRA_TYPES = {"index", "log", "dashboard", "schema"}
# 신선도: 90일 아카이브 후보에서 제외하는 타입 (wiki-schema.md §8 예외 2)
ARCHIVE_EXEMPT_TYPES = {"feature", "guide"}
# index.md 분할 신호 임계 (wiki-schema.md §4 — 초과 시 INFO로 2단계 파일 분할 제안)
INDEX_BODY_LINES = 400   # index.md 전체 줄 수(frontmatter 포함)
INDEX_FEAT_ROWS = 200    # '## 기능별 인덱스' 표의 feature/recipe 행 수


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


def strip_code(text):
    """wikilink 오탐 방지용: 코드펜스(```...```)·인라인코드(`...`)를 같은 길이 공백으로 치환한 사본 반환.
    코드 스니펫 안 정규식(예: `![](...)`·`[[..]]`)이 wikilink로 오인되는 것을 막는다.
    줄바꿈은 보존해 다른 줄 단위 검사(예산 등)와 줄 수가 어긋나지 않게 한다(이 사본은 wikilink 추출 전용)."""
    blank = lambda m: re.sub(r"[^\n]", " ", m.group(0))  # 줄바꿈만 남기고 공백화
    text = re.sub(r"```.*?```", blank, text, flags=re.S)   # 펜스 블록
    text = re.sub(r"```[^\n]*\Z", blank, text, flags=re.S)  # 미닫힘 펜스 → 끝까지 코드 간주(보수적)
    text = re.sub(r"`[^`\n]*`", blank, text)                # 인라인 코드
    return text


def feature_index_rows(text):
    """index.md '## 기능별 인덱스' 섹션의 feature/recipe 링크 표 행 수(분할 신호 측정용)."""
    m = re.search(r"^##\s*기능별 인덱스\b.*?(?=^##\s|\Z)", text, re.M | re.S)
    if not m:
        return 0
    return sum(1 for line in m.group(0).splitlines()
               if line.lstrip().startswith("|") and ("feature]]" in line or "recipe]]" in line))


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
    dep_count = 0                             # deprecated 페이지 집계 (wiki-schema §7-17)
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

        # deprecated 판정 (status: deprecated 또는 deprecated 필드 — schema §2.3 둘 다 허용)
        is_dep = (fm.get("status") == "deprecated") or bool(fm.get("deprecated"))
        if is_dep and not in_archive:
            dep_count += 1  # F1-ⓐ 현행 vault deprecated 집계(이력 가시성, §7-17)
            # F1-ⓑ 폐기 안내 정합: deprecated인데 "코드에서 제거" 안내가 없으면 경고
            if "코드에서 제거" not in text:
                warns.append(f"deprecated 표기 안내 누락: {r} ('⚠️ 코드에서 제거됨' 안내 권장, schema §2.3)")
        # F2 구현 근거 각주 게이트: feature가 '## 구현 방법'을 갖는데 [^src-...] 각주가 0개면 얕은 feature
        #  의심. lint은 vault만 읽어 레포 파일 실재는 못 보고 각주 '존재'만 검사; 서술↔코드 사실 정합은
        #  §7-10(에이전트 표본)이 담당 (§7-18).
        if typ == "feature" and not is_dep and not in_archive and "## 구현 방법" in text and "[^src-" not in text:
            warns.append(f"구현 근거 각주 누락: {r} (## 구현 방법 있으나 [^src-...] 0개 — 얕은 feature 의심, schema §2.3)")

        # wikilink: 깨진 링크(경로형) + 경로 없는 링크(명시적 경로 필수 위반)
        # 코드펜스/인라인코드 안 텍스트는 제외(스니펫 정규식이 [[..]]로 오인되는 오탐 방지 — strip_code)
        for m in re.findall(r"\[\[([^\]|]+)", strip_code(text)):
            t = m.replace("\\", "").split("#")[0].strip()
            if not t:
                continue
            link_targets.add(t)
            if "/" in t:
                if t not in existing:
                    errors.append(f"깨진 링크: {r} -> [[{t}]]")
            elif t not in existing:  # 루트 파일(index 등)로도 해석되지 않으면 위반
                warns.append(f"경로 없는 wikilink(명시적 경로 필수): {r} -> [[{t}]]")

        # 예산 — log.md는 문자 수(len), 그 외 타입은 줄 수
        if r in SPECIAL_BUDGET:
            chars = len(text)
            if chars > SPECIAL_BUDGET[r]:
                warns.append(f"예산 초과: {r} {chars}/{SPECIAL_BUDGET[r]}자 "
                             f"— 오래된 항목을 90_archive/log/로 롤오버 필요 (wiki-schema §8)")
        else:
            budget = None
            if typ == "guide":
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
            elif typ not in INFRA_TYPES and not in_archive and fm.get("status") != "paused" and not is_dep:
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

    # index.md: 분할 신호(줄수/행수) + sub-index 목록 정합 + 기능별 인덱스 ↔ feature 동기화
    idx = os.path.join(vault, "index.md")
    sub_files = sorted(glob.glob(os.path.join(vault, "index-*.md")))
    if os.path.isfile(idx):
        with open(idx, encoding="utf-8") as fh:
            itext = fh.read()

        # 분할 신호 (wiki-schema §4) — sub 합치기 전 index.md 본체로 측정
        idx_lines = itext.count("\n") + 1
        feat_rows = feature_index_rows(itext)
        if idx_lines > INDEX_BODY_LINES or feat_rows > INDEX_FEAT_ROWS:
            infos.append(f"index.md 분할 검토: 본문 {idx_lines}줄(임계 {INDEX_BODY_LINES}), "
                         f"기능별 인덱스 {feat_rows}행(임계 {INDEX_FEAT_ROWS}) (wiki-schema §4 2단계)")

        # sub-index 분할 신호 (§7-14): 각 index-*.md 자체 크기도 측정.
        # index.md → personal/work 2분할이 종착이라 추가 파일 분할 경로가 없으므로
        # 초과 시 '소제목 구역화'를 권고한다(wiki-schema §4). 본문 줄수는 헤딩과 무관하게,
        # 행수는 sub-index가 보유한 '## 기능별 인덱스' 헤딩 기준으로 측정(wiki-schema §4 명문).
        for sp in sub_files:
            try:
                with open(sp, encoding="utf-8") as sfh:
                    stext = sfh.read()
            except OSError:
                continue
            s_lines = stext.count("\n") + 1
            s_rows = feature_index_rows(stext)
            if s_lines > INDEX_BODY_LINES or s_rows > INDEX_FEAT_ROWS:
                infos.append(
                    f"{os.path.basename(sp)} 분할 검토: 본문 {s_lines}줄(임계 {INDEX_BODY_LINES}), "
                    f"기능별 인덱스 {s_rows}행(임계 {INDEX_FEAT_ROWS}) — sub-index는 추가 파일 분할 "
                    f"대신 `### ` 하위 소제목으로 구역화(wiki-schema §4)")

        # sub-index 목록 정합: 실재하는 index-*.md가 index.md에 언급(등록)됐는지.
        #  A(실재 파일) − B(index.md 언급) = 미등록 → WARN. 역방향(언급은 있으나 파일 없음)은
        #  wikilink면 위 깨진/경로없음 검사가 이미 잡으므로 신규 WARN을 내지 않는다(중복·모순 차단).
        mentioned = set(re.findall(r"index-[a-z]+", itext))
        for sp in sub_files:
            stem = os.path.basename(sp)[:-3]  # 예: 'index-personal'
            if stem not in mentioned:
                warns.append(f"sub-index 미등록: {stem}.md가 index.md 목록에 없음(절차 K·검색 누락 위험)")

        # 인덱스가 sub-index로 분할된 경우 그 내용도 합쳐서 동기화 검사 (분할 시 누락 오탐 방지)
        for sub in sub_files:
            try:
                with open(sub, encoding="utf-8") as sfh:
                    itext += "\n" + sfh.read()
            except OSError:
                pass
        # 코드펜스/인라인코드 제외 후 feature 링크 추출 (index/sub의 스니펫 예시 오탐 방지)
        for m in re.findall(r"\[\[([^\]|]+)", strip_code(itext)):
            t = m.replace("\\", "").split("#")[0].strip()  # #앵커 제거(메인 루프 링크 파싱과 일치)
            if "/feat-" in t:
                index_feat_links.add(t)
        for f in sorted(feat_files - index_feat_links):
            warns.append(f"기능별 인덱스 누락: {f} (feature인데 index 미등록)")

        # 한/영 양방향 병기: 기능별 인덱스 행 첫 컬럼(기능명)에 한글·영문 중 한쪽만 있으면 WARN.
        #  한글 등록이든 영문 등록이든 양방향 검색이 되게(wiki-schema §3·§7-16). feature_index_rows는
        #  건드리지 않고 별도 순회(분할 시 sub-index까지 합친 itext 대상). 첫 컬럼은 이후 컬럼 wikilink의
        #  \| 이스케이프에 영향받지 않으므로 split("|")[1]로 안전.
        han, lat = re.compile(r"[가-힣]"), re.compile(r"[A-Za-z]")
        for line in itext.splitlines():
            s = line.lstrip()
            if not s.startswith("|") or ("feature]]" not in s and "recipe]]" not in s):
                continue
            parts = s.split("|")
            if len(parts) < 2 or not parts[1].strip():
                continue
            name = parts[1].strip()
            has_h, has_l = bool(han.search(name)), bool(lat.search(name))
            if has_h != has_l:
                warns.append(f"한/영 병기 누락: '{name}' ({'한글만' if has_h else '영문만'} — 양방향 검색 위해 한글·영문 모두 병기)")

    # log 아카이브 인덱스 정합 (wiki-schema §7-19): log.md '## 아카이브 인덱스'에 등록된
    #  {YYYY-MM}.md ↔ 실재 90_archive/log/{YYYY-MM}.md 양방향 대조. sub-index 정합(위)과 유사하나
    #  양방향 — 아카이브 인덱스 항목은 wikilink가 아니라, 역방향(파일 있으나 미등록)이 깨진링크
    #  검사로 안 잡히므로 양쪽 다 WARN(검색 누락·깨진 참조 방지).
    if "log.md" in pages:
        log_text = pages["log.md"][2]
        sec = re.search(r"^##\s*아카이브 인덱스\b.*?(?=^##\s|\Z)", log_text, re.M | re.S)
        indexed = set(re.findall(r"(\d{4}-\d{2})\.md", sec.group(0))) if sec else set()
        archived = set()
        for p in md:
            am = re.fullmatch(r"90_archive/log/(\d{4}-\d{2})\.md", rel(p))
            if am:
                archived.add(am.group(1))
        for ym in sorted(archived - indexed):
            warns.append(f"log 아카이브 미등록: 90_archive/log/{ym}.md가 log.md '## 아카이브 인덱스'에 없음(검색 누락 위험)")
        for ym in sorted(indexed - archived):
            warns.append(f"log 아카이브 인덱스 깨짐: log.md가 {ym}.md를 가리키나 90_archive/log/{ym}.md 없음")

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
    if dep_count:
        infos.append(f"deprecated 페이지 {dep_count}건 (이력 보존 — 현재 기능 아님, schema §2.3)")

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
