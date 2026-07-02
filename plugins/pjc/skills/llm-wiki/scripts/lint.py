#!/usr/bin/env python3
"""llm-wiki Lint 보조 스크립트.

사용법: python lint.py "<vault_path>"
검사: 깨진/경로 없는 wikilink / 예산 초과 / platform·origin·confidence 통제어휘 위반·누락
      / 고아 페이지(간이) / 신선도(60·90일)·미래 날짜 / 기능별 인덱스·허브 동기화 / 네이밍 규칙 / 타입 미지정
      / tech_stack 휘발성 버전 / index·sub-index 분할 신호(INFO) / deprecated 표기 정합·집계 / feature 구현 근거 각주
      / feature 각주 경로 레포 실존(§7-20 — 허브 '레포 정보 > 경로'의 레포 접근 가능 시)
      / feature '## 관련 파일' 섹션 게이트 + 경로 실존(§7-21 — §7-20과 동일 레포 루트 캐시)
      / 시크릿 의심 패턴(§7-22 — password/API key/token/Bearer/DB 연결문자열/개인키/URI 자격증명)
      / pending.md 미처리 잔량 집계(INFO — 절차 K 큐, [K-DRIFT]/[SKILL-IMPROVE]/[DECISION] 태그별)
      / log 아카이브 인덱스 정합
      / 미해결 질문 인덱스 동기(§7-23 — open 미등록 유실 위험·resolved 잔존 stale)
      / index.md 부재(ERR — 인덱스 기반 검사 불능 신호)
      / (미검증)·미해결 question 집계(INFO).
출력: 사람이 읽는 보고(오류/경고/정보). 파일은 수정하지 않는다(읽기 전용).
범위: vault 파일 읽기 + §7-20의 레포 파일 '실존' 확인까지 — 코드 내용은 해석하지 않는다
      (서술↔코드 사실 정합은 §7-10 에이전트 표본이 담당).
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
    "decision-log": 150,  # 결정 이력 (wiki-schema §2.8 — 초과 시 90_archive 원경로 이동)
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

# 시크릿 의심 패턴 (wiki-schema §7-22 — 키워드+구분자+실값 형태만 매칭하는 보수 정규식.
#  post-write-checks.ps1의 민감정보 검사를 위키용으로 이식하되, IP 주소는 산문 오탐 위험으로 제외).
#  password/api key 계열은 값을 캡처해 아래 secret_value_is_codey()로 "코드 꼴" 값을 걸러낸다.
SECRET_PATTERNS = [
    ("password", re.compile(r"(?i)\b(password|passwd|pwd)\s*[:=]\s*['\"]?([^\s'\";,]{8,})")),
    ("api key/token", re.compile(r"(?i)\b(api[_-]?key|apikey|secret|access[_-]?key|auth[_-]?token)\s*[:=]\s*['\"]?([A-Za-z0-9_\-./+]{12,})")),
    ("bearer 토큰", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._\-]{20,}")),
    ("DB 연결문자열", re.compile(r"(?i)(server|data source|host)\s*=\s*[^;\n]+;.*(password|pwd)\s*=\s*[^;\n]{4,}")),
    ("개인키 블록", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("URI 자격증명", re.compile(r"(?i)\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^@\s]{4,}@")),
]
# 값 post-filter를 적용하는 라벨 (변수 대입·함수 호출 등 "코드 꼴" 값 제외 대상)
SECRET_VALUE_FILTER_LABELS = {"password", "api key/token"}
# 플레이스홀더/예시 값 오탐 제외 — 해당 줄에 이 표식이 있으면 시크릿이 아니라 규약 안내로 본다.
#  'example'은 단어 그대로일 때만(example.com 같은 도메인은 제외 표식 아님 — 위음성 방지).
SECRET_PLACEHOLDER_RX = re.compile(
    r"(YOUR_|<[^>]+>|\{[^}]+\}|\$env:|\$\{|%[A-Za-z_]+%|예\s*[:)]|환경변수|placeholder|example(?![.\w])|localhost|127\.0\.0\.1|\*\*\*|xxxx)",
    re.I)
# 알려진 시크릿 접두사 — 이 꼴이면 코드 꼴 판정과 무관하게 항상 실값 취급 (JWT eyJ 포함)
SECRET_KEY_PREFIX_RX = re.compile(r"^(sk_(live|test)_|ghp_|gho_|xox[bap]-|AKIA|AIza|eyJ)")
# 숫자·특수문자 없는 순수 식별자/프로퍼티 체인 꼴 (예: somePassword, input.password;)
SECRET_IDENTIFIER_LIKE_RX = re.compile(r"^[A-Za-z_][A-Za-z_.;,\[\]]*$")


def secret_value_is_codey(val):
    """§7-22 값 post-filter: 캡처된 값이 코드 스니펫의 변수·함수 호출 꼴(실값 아님)인지 판정.
    보수 정책 — 위양성(코드 오탐) 억제를 위음성보다 우선한다(plan T7 Edge Case).
    함수 호출(괄호 포함)·숫자 없는 순수 식별자/체이닝은 코드 꼴로 보고 제외하되,
    알려진 시크릿 접두사(sk_live_ 등)는 항상 실값으로 취급한다."""
    v = val.strip().strip("'\"")
    if SECRET_KEY_PREFIX_RX.match(v):
        return False
    if "(" in v or ")" in v:
        return True
    return bool(SECRET_IDENTIFIER_LIKE_RX.match(v))


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


def section(text, heading):
    """본문에서 '## {heading}' 섹션(헤딩 줄부터 다음 '## ' 헤딩 또는 문서 끝까지)을 반환, 없으면 None.
    기능별 인덱스(§7-6·14)·레포 정보(§7-20)·아카이브 인덱스(§7-19)·미해결 질문(§7-23) 공용 —
    섹션 경계 규칙(다음 ## 또는 \\Z)이 검사마다 어긋나지 않게 한 곳에서 유지한다."""
    m = re.search(r"^##\s*" + re.escape(heading) + r"\b.*?(?=^##\s|\Z)",
                  text, re.M | re.S)
    return m.group(0) if m else None


def wikilink_targets(text):
    """코드펜스/인라인코드를 제외(strip_code)한 텍스트에서 wikilink 대상([[대상|표시]]의 대상)을
    정규화(이스케이프 백슬래시 제거·#앵커 제거·트림)해 순서대로 반환. 빈 대상은 제외.
    깨진 링크(§7-1)·기능별 인덱스 동기(§7-6)·미해결 질문 동기(§7-23) 공용 —
    정규화 규칙이 검사마다 어긋나 서로 모순된 판정을 내는 것을 막는다."""
    out = []
    for m in re.findall(r"\[\[([^\]|]+)", strip_code(text)):
        t = m.replace("\\", "").split("#")[0].strip()
        if t:
            out.append(t)
    return out


def question_is_resolved(fm):
    """question 닫힘 판정(§7-12·§7-23 공용): `status: resolved` 또는 `resolved:` 필드(날짜)
    어느 쪽이든 닫힌 것으로 본다(SKILL B-2 3-1 이중 표기 허용 — §7-17 deprecated 판정과 동일 원칙)."""
    return fm.get("status") == "resolved" or bool(fm.get("resolved"))


def is_lint_report(rel_path):
    """lint-YYYYMMDD 리포트 페이지 판정: type: question을 쓰지만 '질문'이 아니라 lint 결과 보존물 —
    §7-12 미해결 집계와 §7-23 인덱스 등록 요구에서 같은 기준으로 제외한다(집계↔등록 모순 방지)."""
    return os.path.basename(rel_path).startswith("lint-")


def is_feat_recipe_row(line):
    """기능별 인덱스 유형의 feature/recipe 표 행 판정(§7-14 행수·§7-16 병기 공용 — 이중 구현 방지).
    형상+대상 기반이라 상세 컬럼 alias 표기(`\\|feature]]` 권장 관례, schema §3)에 의존하지 않는다:
    ① `|`로 시작 ② 첫 컬럼이 비어 있지 않은 평문(wikilink 미포함 — 프로젝트/기술/가이드 표처럼
    첫 컬럼이 링크인 행은 제외, `\\|` 이스케이프로 split이 경로만 잡는 오탐 차단) ③ 행 내 wikilink
    대상(정규화: 이스케이프 `\\`·`#`앵커 제거 — wikilink_targets와 동일 규칙)의 basename이
    `feat-` 시작(단축 링크 포함)이거나 대상에 `40_guides/recipes/` 포함."""
    s = line.lstrip()
    if not s.startswith("|"):
        return False
    parts = s.split("|")
    first = parts[1].strip() if len(parts) > 1 else ""
    if not first or "[[" in first:
        return False
    for m in re.findall(r"\[\[([^\]|]+)", s):
        t = m.replace("\\", "").split("#")[0].strip()
        if t.split("/")[-1].startswith("feat-") or "40_guides/recipes/" in t:
            return True
    return False


def feature_index_rows(text):
    """index.md '## 기능별 인덱스' 섹션의 feature/recipe 표 행 수(분할 신호 측정용, §7-14).
    행 판정은 is_feat_recipe_row 공용 — alias 무관(비표준 alias 행도 정확히 센다)."""
    sec = section(text, "기능별 인덱스")
    if not sec:
        return 0
    return sum(1 for line in sec.splitlines() if is_feat_recipe_row(line))


def repo_root_for_hub(hub_text):
    """project 허브 '## 레포 정보' 섹션의 '- **경로**: `...`' 백틱 값을 레포 루트로 반환(§7-20용).
    섹션/경로 줄이 없거나 그 디렉터리가 실재하지 않으면(다른 PC 등) None — 레포 접근 불가로 간주."""
    sec = section(hub_text, "레포 정보")
    if not sec:
        return None
    m = re.search(r"\*\*경로\*\*\s*:\s*`([^`\n]+)`", sec)
    if not m:
        return None
    root = os.path.expanduser(m.group(1).strip())
    return root if os.path.isdir(root) else None


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

    # WARN 프로젝트별 집계(§7 결과 처리): 메시지 문자열을 되파싱하지 않고, append 시점에
    #  경고 '대상 페이지'(vault 상대경로)로 집계한다 — 문구 수정·공백 포함 경로에 안전.
    #  20_projects는 category/프로젝트 키(허브 .md도 동일 키), 그 외는 최상위 디렉터리 키,
    #  루트 파일·페이지 무관 경고(sub-index 미등록·한/영 병기 등)는 집계 제외 —
    #  요약은 우선순위 파악용이라 총합과 다를 수 있다.
    warn_groups = {}

    def warn(msg, page=None):
        """WARN 추가 + 대상 페이지 기준 프로젝트별 집계(page 없으면 집계 제외)."""
        warns.append(msg)
        if not page or "/" not in page:
            return
        parts = page.split("/")
        if parts[0] == "20_projects" and len(parts) >= 3:
            key = "/".join(parts[1:3])   # feature: personal/{프로젝트}
            if key.endswith(".md"):      # 허브(20_projects/{cat}/{프로젝트}.md)도 동일 키
                key = key[:-3]
        else:
            key = parts[0]               # 40_guides 등: 최상위 디렉터리
        warn_groups[key] = warn_groups.get(key, 0) + 1

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
                warn(f"deprecated 표기 안내 누락: {r} ('⚠️ 코드에서 제거됨' 안내 권장, schema §2.3)", r)
        # F2 구현 근거 각주 게이트: feature가 '## 구현 방법'을 갖는데 [^src-...] 각주가 0개면 얕은 feature
        #  의심. 각주 '존재'는 여기서, 각주 경로의 레포 실존은 §7-20 블록(메인 루프 뒤)이 기계 검사;
        #  서술↔코드 사실 정합은 §7-10(에이전트 표본)이 담당 (§7-18).
        if typ == "feature" and not is_dep and not in_archive and "## 구현 방법" in text and "[^src-" not in text:
            warn(f"구현 근거 각주 누락: {r} (## 구현 방법 있으나 [^src-...] 0개 — 얕은 feature 의심, schema §2.3)", r)

        # wikilink: 깨진 링크(경로형) + 경로 없는 링크(명시적 경로 필수 위반)
        # 코드펜스/인라인코드 안 텍스트는 제외 — 추출·정규화는 wikilink_targets(§7-6·23과 공용)
        for t in wikilink_targets(text):
            link_targets.add(t)
            if "/" in t:
                if t not in existing:
                    errors.append(f"깨진 링크: {r} -> [[{t}]]")
            elif t not in existing:  # 루트 파일(index 등)로도 해석되지 않으면 위반
                warn(f"경로 없는 wikilink(명시적 경로 필수): {r} -> [[{t}]]", r)

        # 예산 — log.md는 문자 수(len), 그 외 타입은 줄 수
        if r in SPECIAL_BUDGET:
            chars = len(text)
            if chars > SPECIAL_BUDGET[r]:
                warn(f"예산 초과: {r} {chars}/{SPECIAL_BUDGET[r]}자 "
                     f"— 오래된 항목을 90_archive/log/로 롤오버 필요 (wiki-schema §8)", r)
        else:
            budget = None
            if typ == "guide":
                budget = GUIDE_BUDGET.get(fm.get("guide_kind", ""), 200)
            elif typ in BUDGET:
                budget = BUDGET[typ]
            if budget and lines > budget:
                warn(f"예산 초과: {r} {lines}/{budget}줄 (type={typ})", r)

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
                    warn(f"소스 스텁 휘발성 버전 기재: {r} (기술 스택은 이름만, 버전 제외)", r)
                    break
        if typ == "project":
            ts = fm.get("tech_stack", "")
            if re.search(r"\d+\.\d+", ts):
                warn(f"허브 tech_stack 휘발성 버전 기재: {r} (이름만, 버전 진실원천은 코드)", r)

        # origin/confidence: 화이트리스트 타입만 검사 (type 매칭만으로 수행, 신선도 로직과 무관)
        if typ in ORIGIN_REQUIRED_TYPES and not in_archive:
            for key, vocab in (("origin", ORIGIN_VOCAB), ("confidence", CONFIDENCE_VOCAB)):
                val = fm.get(key)
                if not val:
                    warn(f"{key} 누락: {r} (type={typ})", r)
                elif val not in vocab:
                    errors.append(f"{key} 통제어휘 위반: {r} -> '{val}'")

        # 미래/이상 날짜 + 신선도 (updated 필드 보유 페이지만)
        raw_upd = fm.get("updated", "")
        upd = parse_date(raw_upd) if raw_upd else None
        if raw_upd and upd is None:
            warn(f"updated 형식 이상: {r} -> '{raw_upd}'", r)
        if upd:
            if upd > today:
                errors.append(f"미래 날짜: {r} updated={upd}")
            # decision-log는 신선도 전체 면제(60·90 둘 다) — 이력 페이지는 미편집이 정상 (wiki-schema §2.8·§8 예외 1-2)
            elif (typ not in INFRA_TYPES and typ != "decision-log" and not in_archive
                  and fm.get("status") != "paused" and not is_dep):
                days = (today - upd).days
                if days >= 90 and typ not in ARCHIVE_EXEMPT_TYPES:
                    infos.append(f"90일+ 미편집(아카이브 후보): {r} ({days}일)")
                elif days >= 60:
                    infos.append(f"60일+ 미편집(confidence 하락 후보): {r} ({days}일)")

        # 네이밍 규칙
        base = os.path.basename(r)
        if r.startswith("10_sources/") and not re.fullmatch(r"src-[a-z0-9-]+\.md", base):
            warn(f"네이밍 위반(src-*): {r}", r)
        if typ == "feature" and not re.fullmatch(r"feat-[a-z0-9-]+\.md", base):
            warn(f"네이밍 위반(feat-*): {r}", r)
        if r.startswith("30_knowledge/questions/") and not re.fullmatch(
                r"(q-\d{8}-[a-z0-9-]+|lint-\d{8})\.md", base):
            warn(f"네이밍 위반(q-YYYYMMDD-* / lint-YYYYMMDD): {r}", r)

        # 타입 미지정 (루트 인프라 파일·아카이브 제외)
        if not typ and not is_root and not in_archive:
            warn(f"타입 미지정 파일: {r}", r)

        # 시크릿 의심 스캔 (§7-22) — 전 페이지 본문(frontmatter 제외, 아카이브 포함 — 시크릿은
        #  어디 있든 위험). 코드펜스도 스캔 대상(시크릿이 스니펫 안에 남는 경우가 많음).
        #  키워드+구분자+실값 형태만 매칭하고, 플레이스홀더 표식 줄은 제외해 오탐을 억제한다.
        sec_body = re.sub(r"^---\n.*?\n---", "", text, count=1, flags=re.S)
        fm_lines = text.count("\n") - sec_body.count("\n")  # 본문 시작 줄 오프셋(줄 번호 보고용)
        for li, line in enumerate(sec_body.splitlines(), start=fm_lines + 1):
            if SECRET_PLACEHOLDER_RX.search(line):
                continue
            for label, rx in SECRET_PATTERNS:
                m2 = rx.search(line)
                if not m2:
                    continue
                # password/api key 계열은 값이 코드 꼴(변수·함수 호출)이면 제외 (§7-22 보수 정책)
                if label in SECRET_VALUE_FILTER_LABELS and secret_value_is_codey(m2.group(2)):
                    continue
                warn(f"시크릿 의심({label}): {r} L{li} — 실제 값이면 즉시 제거하고 "
                     f"환경변수 이름만 기재 (schema §7-22)", r)
                break  # 같은 줄 다중 라벨 중복 경고 방지

        # (미검증)·미해결 question 집계 (§7-12) — 20_/30_/40_ 본문만(frontmatter 제외),
        # 10_sources(불변 스텁, 검증 루프 대상 아님)·90_archive·루트 인프라는 범위 밖.
        # resolved 판정·lint-* 제외는 §7-23과 공용 헬퍼로 동일 기준(집계↔등록 요구 모순 방지).
        if r.startswith(("20_", "30_", "40_")):
            body = re.sub(r"^---\n.*?\n---", "", text, count=1, flags=re.S)
            hits = body.count("(미검증)")
            if hits:
                unverified_hits += hits
                unverified_files += 1
            if typ == "question" and not question_is_resolved(fm) and not is_lint_report(r):
                open_questions += 1

        # 90_archive/ 하위(백업 사본 포함)는 인덱스 동기 대상이 아님 — §8 "백업 파일이 WARN을 만들지 않는다"
        if typ == "feature" and not r.startswith("90_archive/"):
            feat_files.add(r[:-3])

    # index.md: 분할 신호(줄수/행수) + sub-index 목록 정합 + 기능별 인덱스 ↔ feature 동기화
    idx = os.path.join(vault, "index.md")
    sub_files = sorted(glob.glob(os.path.join(vault, "index-*.md")))
    if os.path.isfile(idx):
        with open(idx, encoding="utf-8") as fh:
            itext = fh.read()

        # 미해결 질문 인덱스 동기 (wiki-schema §7-23): open question ↔ index.md '## 미해결 질문'
        #  (비분할 섹션 — 본체 기준 §4, 아래 sub-index 합산 '전'에 검사해야 하므로 이 위치).
        #  섹션 탐색도 strip_code 사본에서 수행해 코드펜스 안 예시 헤딩 오매칭을 막는다.
        #  lint-* 리포트는 질문이 아니라 등록 요구에서 제외(is_lint_report — §7-12 집계와 동일 기준).
        #  질문 '유실'(등록 누락으로 잊힘)과 'stale'(해결됐는데 미해결 목록 잔존)을 기계로 잡는다.
        #  resolved 페이지의 '삭제' 자체는 스냅샷 검사로 탐지 불가 — 삭제 금지는 절차 규칙
        #  (§2.7·SKILL 사전 준수)이 담당한다.
        q_section = section(strip_code(itext), "미해결 질문") or ""
        # 등록 판정: 규약(§3)은 무확장자 경로 링크가 원칙이나, `.md` 포함·파일명만 링크도 등록으로
        #  인정한다 — 그 형식 위반은 §7-1 링크 검사가 별도 보고하므로 여기서 겹치면 '미등록' 오탐.
        q_listed = {t[:-3] if t.endswith(".md") else t for t in wikilink_targets(q_section)}
        for qr, (qfm, qtyp, _) in sorted(pages.items()):
            if qtyp != "question" or qr.startswith("90_archive/"):
                continue
            resolved = question_is_resolved(qfm)
            listed = qr[:-3] in q_listed or os.path.basename(qr)[:-3] in q_listed
            if not resolved and not is_lint_report(qr) and not listed:
                warn(f"미해결 질문 index 미등록: {qr} "
                     f"(유실 위험 — index.md '## 미해결 질문'에 등록, schema §7-23)", qr)
            if resolved and listed:
                warn(f"해결된 질문이 index 미해결 목록에 잔존: {qr} "
                     f"(index에서 제거 — 페이지는 보존, B-2 3-1, schema §7-23)", qr)

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
                warn(f"sub-index 미등록: {stem}.md가 index.md 목록에 없음(절차 K·검색 누락 위험)")

        # 인덱스가 sub-index로 분할된 경우 그 내용도 합쳐서 동기화 검사 (분할 시 누락 오탐 방지)
        for sub in sub_files:
            try:
                with open(sub, encoding="utf-8") as sfh:
                    itext += "\n" + sfh.read()
            except OSError:
                pass
        # 코드펜스/인라인코드 제외 후 feature 링크 추출 — wikilink_targets(메인 루프 파싱과 공용)
        for t in wikilink_targets(itext):
            if "/feat-" in t:
                index_feat_links.add(t)
        for f in sorted(feat_files - index_feat_links):
            warn(f"기능별 인덱스 누락: {f} (feature인데 index 미등록)", f)

        # 한/영 양방향 병기: 기능별 인덱스 유형 행(is_feat_recipe_row — 형상+대상 기반, alias 무관)의
        #  첫 컬럼(기능명)에 한글·영문 중 한쪽만 있으면 WARN. 한글 등록이든 영문 등록이든 양방향
        #  검색이 되게(wiki-schema §3·§7-16). 스캔은 sub-index까지 합친 itext 전체 — `## ` 소분할
        #  뒤의 행도 누락하지 않는다(§4 보증). 첫 컬럼은 평문 행만 판정에 들어오므로(헬퍼 조건 ②)
        #  split("|")[1] 추출이 이후 컬럼 wikilink의 \| 이스케이프에 영향받지 않는다.
        han, lat = re.compile(r"[가-힣]"), re.compile(r"[A-Za-z]")
        for line in itext.splitlines():
            if not is_feat_recipe_row(line):
                continue
            name = line.lstrip().split("|")[1].strip()
            has_h, has_l = bool(han.search(name)), bool(lat.search(name))
            if has_h != has_l:
                warn(f"한/영 병기 누락: '{name}' ({'한글만' if has_h else '영문만'} — 양방향 검색 위해 한글·영문 모두 병기)")

    else:
        # 인덱스 기반 검사(§7-6·14·15·16·23) 전체가 불능인 구조 결함 — 침묵 대신 ERR 1건으로 신호
        #  (특히 §7-23은 index.md가 없으면 '질문 유실' 최악 시나리오를 못 잡는다).
        errors.append("index.md 없음: vault 루트에 index.md가 없어 인덱스 기반 검사"
                      "(§7-6·14·15·16·23)를 건너뜀 — 카탈로그 골격 생성 필요 (schema §4)")

    # log 아카이브 인덱스 정합 (wiki-schema §7-19): log.md '## 아카이브 인덱스'에 등록된
    #  {YYYY-MM}.md ↔ 실재 90_archive/log/{YYYY-MM}.md 양방향 대조. sub-index 정합(위)과 유사하나
    #  양방향 — 아카이브 인덱스 항목은 wikilink가 아니라, 역방향(파일 있으나 미등록)이 깨진링크
    #  검사로 안 잡히므로 양쪽 다 WARN(검색 누락·깨진 참조 방지).
    if "log.md" in pages:
        log_text = pages["log.md"][2]
        sec = section(log_text, "아카이브 인덱스")
        indexed = set(re.findall(r"(\d{4}-\d{2})\.md", sec)) if sec else set()
        archived = set()
        for p in md:
            am = re.fullmatch(r"90_archive/log/(\d{4}-\d{2})\.md", rel(p))
            if am:
                archived.add(am.group(1))
        for ym in sorted(archived - indexed):
            warn(f"log 아카이브 미등록: 90_archive/log/{ym}.md가 log.md '## 아카이브 인덱스'에 없음(검색 누락 위험)",
                 f"90_archive/log/{ym}.md")
        for ym in sorted(indexed - archived):
            warn(f"log 아카이브 인덱스 깨짐: log.md가 {ym}.md를 가리키나 90_archive/log/{ym}.md 없음",
                 f"90_archive/log/{ym}.md")

    # pending.md 미처리 잔량 집계 (절차 K 큐 — SKILL K-5/K 5-1/K 5-2/B-1 0): 잔량이 있으면 INFO로 알려
    #  다음 ingest/lint 세션이 소비하게 한다 (0건·파일 없음이면 생략). 태그별 분리 —
    #  [K-DRIFT]는 위키 세션이 반영 후 제거, [SKILL-IMPROVE]는 사용자 보고 대상(제거는 사용자 지시),
    #  [DECISION]은 해당 프로젝트 decisions.md에 추가 후 제거(자가 소비).
    #  (보고됨 ...) 표식 줄도 잔량이므로 집계에 포함.
    if "pending.md" in pages:
        pend_text = pages["pending.md"][2]
        parts = []
        for tag, label in (("K-DRIFT", "K-DRIFT {n}건"),
                           ("SKILL-IMPROVE", "SKILL-IMPROVE {n}건(플러그인 개선 후보 — 사용자 보고 대상)"),
                           ("DECISION", "DECISION {n}건(결정 이력 — ingest 세션이 decisions.md로 소비)")):
            n = sum(1 for line in pend_text.splitlines()
                    if re.match(r"^\s*-\s*\[\d{4}-\d{2}-\d{2}\]\s*\[" + tag + r"\]", line))
            if n:
                parts.append(label.format(n=n))
        if parts:
            infos.append("pending.md 미처리 잔량 — " + " / ".join(parts)
                         + " — 다음 ingest(절차 B-1 0)/lint(F-0)에서 소비")

    # 허브 "기능 목록" ↔ feature 동기화 (feat 파일이 허브 본문에 링크돼 있는지)
    # 90_archive/ 하위 허브 사본(백업)은 검사 제외 — §8 "백업 파일이 WARN을 만들지 않는다"
    for r, (fm, typ, text) in pages.items():
        if typ != "project" or r.startswith("90_archive/"):
            continue
        hub_base = r[:-3]
        hub_text = text.replace("\\", "")
        for f in sorted(feat_files):
            if f.startswith(hub_base + "/") and f not in hub_text:
                warn(f"허브 기능 목록 누락: {r} -> {f}", r)

    # feature 각주 경로 레포 실존 (wiki-schema §7-20) + '## 관련 파일' 섹션 게이트/경로 실존 (§7-21):
    #  §7-20 — feature의 [^src-...] 각주 정의 줄에 백틱으로 병기된 레포 상대경로가, 프로젝트 허브
    #  '## 레포 정보 > 경로'의 레포에 실재하는지 확인. §7-21 — '## 관련 파일' 섹션(기능 구성 파일
    #  지도, §2.3)이 없거나 경로 항목 0개면 WARN, 섹션 내 경로 토큰은 §7-20과 동일 로직으로 실존 확인.
    #  lint은 파일 '실존'만 보고 코드 내용은 해석하지 않는다(서술↔코드 정합은 §7-10 에이전트 표본).
    #  허브에 레포 경로가 없거나 디렉터리가 부재(다른 PC 등)면 프로젝트 단위 INFO 1건 후 건너뛴다
    #  (그 프로젝트의 ① 경로 실재 확인은 §7-10 에이전트가 폴백 수행).
    repo_cache = {}  # 허브 rel 경로 -> 레포 루트(str) 또는 None(접근 불가)
    exists_cache = {}  # (root, 상대경로) -> 실존 여부 — 여러 feature가 같은 경로를 병기할 때 중복 IO 제거
    for r, (fm, typ, text) in sorted(pages.items()):
        if typ != "feature" or r.startswith("90_archive/"):
            continue
        if (fm.get("status") == "deprecated") or bool(fm.get("deprecated")):
            continue  # deprecated는 frozen 이력 — 경로가 이미 제거된 게 정상 (§7-18과 동일 제외)
        # 각주 정의 줄 판별은 strip_code 사본으로(코드펜스 안 유사 줄 제외 — 줄 구조 보존),
        #  백틱 토큰 추출은 원문 줄에서(strip_code는 인라인코드를 공백화해 토큰이 사라지므로).
        raw_lines = text.splitlines()
        stripped_lines = strip_code(text).splitlines()
        tokens = []
        for i, sl in enumerate(stripped_lines):
            if not sl.lstrip().startswith("[^src-"):
                continue
            # 디렉터리 구분자 포함 토큰만 경로 후보 — 무구분자(`MainViewModel.LoadAsync` 등
            #  클래스·멤버명)는 오탐 방지 위해 제외 (plan D2)
            tokens += [t for t in re.findall(r"`([^`\n]+)`", raw_lines[i])
                       if "/" in t or "\\" in t]
        # §7-21: '## 관련 파일' 섹션 판별(strip_code 사본 — 코드펜스 안 유사 헤딩 제외) +
        #  섹션 내 '- ' 항목의 백틱 경로 토큰 수집(원문 줄에서).
        rel_tokens, rel_section_found = [], False
        in_rel = False
        for i, sl in enumerate(stripped_lines):
            s = sl.strip()
            if re.match(r"^##\s*관련 파일\b", s):
                rel_section_found = True
                in_rel = True
                continue
            if in_rel and s.startswith("## "):
                in_rel = False
            if in_rel and s.startswith("-"):
                rel_tokens += [t for t in re.findall(r"`([^`\n]+)`", raw_lines[i])
                               if "/" in t or "\\" in t]
        # 문구로 원인을 구분한다 — "섹션 자체 없음"과 "섹션은 있으나 백틱 경로 0개"(형식 누락:
        #  백틱 미사용·구분자 없는 토큰만 있는 경우)는 수리 방법이 달라 진단 단계를 줄인다.
        if not rel_section_found:
            warn(f"관련 파일 섹션 누락: {r} "
                 f"('## 관련 파일' 기능 구성 파일 지도 — 다음 ingest 시 채움, schema §7-21)", r)
        elif not rel_tokens:
            warn(f"관련 파일 경로 항목 0개: {r} "
                 f"(섹션은 있으나 백틱 경로 없음 — '- `경로` — 역할' 형식으로 기재, schema §7-21)", r)
        if not tokens and not rel_tokens:
            continue
        hub = r.rsplit("/", 1)[0] + ".md"  # 20_projects/{proj}/feat-x.md -> 20_projects/{proj}.md
        if hub not in repo_cache:
            hub_text = pages[hub][2] if hub in pages else ""
            repo_cache[hub] = repo_root_for_hub(hub_text) if hub_text else None
            if repo_cache[hub] is None:
                infos.append(f"레포 접근 불가(허브 레포 경로 미기재/부재): {hub} "
                             f"— 각주·관련 파일 경로 검증 건너뜀(§7-10 에이전트 폴백, schema §7-20·21)")
        root = repo_cache[hub]
        if root is None:
            continue
        # §7-20(각주)·§7-21(관련 파일)을 같은 실존 로직으로 검사하되 출처를 메시지에 구분
        for token_list, label, sec in ((tokens, "각주 경로", "§7-20"),
                                       (rel_tokens, "관련 파일 경로", "§7-21")):
            for t in token_list:
                p = t.replace("\\", "/").strip()
                if p.startswith("./"):
                    p = p[2:]
                if os.path.isabs(p) or re.match(r"^[A-Za-z]:", p):
                    continue  # 레포 '상대'경로만 검사 대상 — 절대경로 병기는 규약 밖이라 제외
                full = os.path.join(root, p)
                key = (root, p)
                if key not in exists_cache:  # 실행-내 memoization (한 실행 중 파일시스템 불변 전제)
                    exists_cache[key] = bool(glob.glob(full)) if "*" in p else os.path.exists(full)
                if not exists_cache[key]:
                    detail = "글롭 매치 0건 — 이동·삭제·오기 가능" if "*" in p \
                        else "이동·삭제·오기 가능 — 갱신 필요"
                    warn(f"{label} 레포에 없음: {r} -> '{t}' ({detail}, schema {sec})", r)

    # 고아 페이지(간이): 어디서도 링크되지 않는 페이지 (루트 인프라·아카이브 제외)
    for r, (fm, typ, _) in sorted(pages.items()):
        if "/" not in r or r.startswith("90_archive/") or typ in INFRA_TYPES:
            continue
        if r[:-3] not in link_targets:
            warn(f"고아 페이지(어디서도 링크되지 않음): {r}", r)

    # (미검증)·미해결 question 집계 리포트 — 사용자 검증 후보 (0건이면 생략, wiki-schema §11)
    if unverified_hits:
        infos.append(f"(미검증) 표기 {unverified_hits}건 / {unverified_files}개 파일 — 사용자 검증 후보")
    if open_questions:
        infos.append(f"미해결 question {open_questions}건 — 사용자 검증 후보")
    if dep_count:
        infos.append(f"deprecated 페이지 {dep_count}건 (이력 보존 — 현재 기능 아님, schema §2.3)")

    # 보고
    # WARN이 많을 때(10건+) 프로젝트별 집계 1줄 — 대규모 정비 세션에서 우선순위 파악용.
    #  집계 자체는 warn() 헬퍼가 append 시점에 수행(warn_groups) — 여기서는 출력 여부·정렬만.
    WARN_GROUP_MIN = 10
    warn_summary = ""
    if len(warns) >= WARN_GROUP_MIN and warn_groups:
        warn_summary = ", ".join(f"{k} {v}건" for k, v in
                                 sorted(warn_groups.items(), key=lambda kv: -kv[1]))
    print(f"== llm-wiki Lint: {vault} ==")
    print(f"검사 파일: {len(md)}개")
    for label, items, mark in (("오류", errors, "[ERR]"), ("경고", warns, "[WARN]"),
                               ("정보", infos, "[INFO]")):
        print(f"\n{mark} {label} {len(items)}건")
        if mark == "[WARN]" and warn_summary:
            print(f"  (프로젝트별: {warn_summary})")
        for it in items:
            print(f"  - {it}")
    if not errors and not warns:
        print("\n[OK] 오류·경고 없음.")


if __name__ == "__main__":
    main()
