#!/usr/bin/env python3
"""SKILL.md ↔ wiki-schema.md ↔ lint.py 공유 상수 정합 셀프체크.

사용법: python check_consistency.py   (인자 없음 — 번들 내 상대 위치로 세 파일을 찾는다)

무엇을: llm-wiki의 공유 상수(파일 예산·통제 어휘)는 네 곳에 존재한다 —
  ① lint.py 상수(BUDGET·GUIDE_BUDGET·SPECIAL_BUDGET·INDEX_*·*_VOCAB)
  ② SKILL.md '## 파일 예산' 표
  ③ wiki-schema.md 타입별 '- **예산**: ~N줄' 줄 (§2.x)
  ④ wiki-schema.md §4 예산 표 (schema 내 이중 표현 — ③과 ④가 서로 어긋나는 것도 잡는다)
번들 규약 H-2(references/procedures-ops.md 하단 '(참고)' 블록)는 이들의 수동 동기화를
요구하는데, 사람이 한 곳을 고치고 나머지를 놓치면 드리프트가 조용히 생긴다.
이 스크립트가 그 드리프트를 기계로 잡는다.

추가로 ⑤ 절차 배치 정합을 검사한다 — SKILL.md는 지연 로드 분할(본체 + references/procedures-*.md)
구조라, 본체 '## 절차 목차' 라우팅 표의 **전 행**(문자 절차 A~ + 비문자 행: 0. 시작 절차·체크리스트)에
대해 대상 파일이 실존하고 해당 헤딩이 표의 위치에 존재해야 한다(문자 절차는 전체에서 정확히 1곳 —
파일 개명·헤딩 소실·중복·표에 없는 스트레이 헤딩 시 라우팅이 허공을 가리킴). 문자 집합은 표에서
동적으로 캡처한다([A-L] 하드코딩 금지 — 절차 M이 추가돼도 검사에서 조용히 빠지지 않게).

또한 ⑥ wiki-schema.md 목차(부분 Read 인덱스)의 § 번호 ↔ 실제 '## N.' 헤딩 정합을 검사한다 —
부분 Read 세션은 전체 정독이 금지라 목차가 낡아도 자가 교정 기회가 없으므로 기계로 잡는다.

그리고 ⑦ procedures-ops.md F-1 실행 순서 인덱스 ↔ wiki-schema.md §7 검사 항목의 번호 집합
1:1 정합을 검사한다 — F-1은 "번호 N = §7-N 정본" 규약인데 두 목록은 손으로 유지되므로,
한쪽에만 항목을 추가하면 실행 인덱스와 정본이 조용히 어긋난다(검사 사각지대). 기계로 잡는다.

⑧ 산문 크로스파일 포인터 회귀 가드 — 지연 로드 분할 후 '절차 라벨이 어느 파일에 있는지'
가리키는 파일-귀속 산문 포인터(references/procedures-*.md + 인접 절차 라벨)가 실제 헤딩 파일과
어긋나면 잡는다. 이 부류(v1.90.1·v1.90.2에서 손으로 고쳐온 스테일)는 앵커·번호 집합 어디에도
안 걸려 차기 재분할 시 조용히 재발하던 회귀 가드 공백을 메운다.

⑨ templates.md ↔ schema §2 타입 집합 정합 — H-2 "타입 바뀌면 templates 동기" 규약을 기계로 잡는다.
타입 신설·삭제·개명이라는 구조 드리프트만 대조(필드 단위 아님 — 오탐 방지).

⑩ 신규 타입 열거 누락 정합 — 새 페이지 타입을 도입할 때 **기존 타입이 산문으로 열거된 자리**가
조용히 낡는 사각을 잡는다(⑨는 타입 집합의 존재만 보고 산문 열거는 읽지 않는다). 두 그룹으로
나뉘고 기대 집합의 정본이 서로 다르다 — ⓐ 값의 정본이 lint.py 상수인 자리(§3 origin·confidence,
§7-3, §7-9, §7-28, §8 아카이브 예외, §11 적용 대상)는 상수 ↔ 산문을 집합 대조하고, ⓑ 정본이
schema §2 타입 집합인 자리(목차 §2 행, §3 계층 태그, templates.md 목차, §12 description 권장/비대상)는
전 타입 등장(§12는 권장·비대상 **분할 커버**)을 요구한다. 새 타입 누락을 강제로 잡는 것은 ⓑ다.
계기: v1.164.0이 `convention` 타입을 신설하며 이 자리들을 일회성 정규식 스캔으로 손수 찾아냈고,
그 스캔은 자산이 아니라 임시 스크립트였다.

판정:
  - 전 항목 일치 → 요약 출력 + exit 0
  - 불일치 → 항목별 소스 값 나열 + exit 1
  - 파싱 앵커 실패(섹션·표·어휘 줄을 못 찾음) → exit 2 (조용한 통과 금지 —
    앵커가 사라졌다는 것 자체가 문서 구조 변경 신호이므로 소리 내어 실패한다)

lint.py 상수는 재파싱하지 않고 importlib로 모듈을 로드해 직접 읽는다(정의가 곧 정본).
표준 라이브러리만 사용(AGENTS.md 정합).
"""
import importlib.util
import os
import re
import sys

# Windows 콘솔(cp949)에서도 한글이 깨지지 않도록 UTF-8 출력 강제 (lint.py와 동일)
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

EVALS_DIR = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(EVALS_DIR)
SKILL_MD = os.path.join(SKILL_DIR, "SKILL.md")
SCHEMA_MD = os.path.join(SKILL_DIR, "references", "wiki-schema.md")
OPS_MD = os.path.join(SKILL_DIR, "references", "procedures-ops.md")
TEMPLATES_MD = os.path.join(SKILL_DIR, "references", "templates.md")
LINT_PY = os.path.join(SKILL_DIR, "scripts", "lint.py")

# schema §2.x 헤딩 → 예산 키 (### 2.N 뒤 첫 토큰이 타입명)
SCHEMA_TYPE_HEADING_RX = re.compile(r"^### 2\.\d+\s+([a-z-]+)", re.M)

# SKILL 본체 라우팅 표 행: | A. 프로젝트 추가 | `references/procedures-content.md` | 또는 | ... | (이 문서) |
# 표의 모든 데이터 행을 잡고(비문자 행 포함), 문자 절차 여부는 라벨 선두 'X. '로 판별한다.
# [A-L] 하드코딩 금지 — 절차가 늘어도(M~) 행이 검사에서 조용히 빠지지 않게 [A-Z] 동적 캡처.
ROW_RX = re.compile(r"^\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|", re.M)
ROUTING_LETTER_RX = re.compile(r"^([A-Z])\.\s")
# 절차 헤딩(### 레벨 고정 — #### A-1. 하위 헤딩과 구분)
PROC_HEADING_RX = re.compile(r"^### ([A-Z])\. ", re.M)


def die(msg):
    print(f"[ANCHOR FAIL] {msg}")
    sys.exit(2)


def read(path):
    if not os.path.isfile(path):
        die(f"파일 없음: {path}")
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def load_lint():
    """lint.py를 모듈로 로드해 상수를 직접 읽는다 (__main__ 가드가 있어 CLI는 실행되지 않음)."""
    spec = importlib.util.spec_from_file_location("lint", LINT_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def norm_type(raw):
    """표의 타입 표기를 예산 키로 정규화: 'project (허브)'→'project', 'guide (ui-ux)'→'guide:ui-ux'."""
    raw = raw.strip()
    gm = re.match(r"^guide\s*\(([a-z-]+)\)$", raw)
    if gm:
        return "guide:" + gm.group(1)
    return re.sub(r"\s*\(.*\)$", "", raw)


def parse_budget_table(section_text, source_label):
    """마크다운 예산 표(SKILL '## 파일 예산' / schema §4 공용)에서 {키: 값}을 추출한다.
    일반 행은 선두 숫자(줄 수), log.md는 'N자', index.md는 산문 속 'N줄'·'N행' 2값."""
    rows = {}
    for line in section_text.splitlines():
        cm = re.match(r"^\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|", line)
        if not cm:
            continue
        typ_raw, val = cm.group(1), cm.group(2)
        if typ_raw in ("타입", "파일 유형") or set(typ_raw) <= set("-: "):
            continue  # 헤더·구분선
        key = norm_type(typ_raw)
        if key == "index.md":
            lm = re.search(r"(\d+)줄", val)
            rm = re.search(r"(\d+)행", val)
            if not (lm and rm):
                die(f"{source_label} index.md 행에서 'N줄'/'N행'을 찾지 못함")
            rows["index:body-lines"] = int(lm.group(1))
            rows["index:feat-rows"] = int(rm.group(1))
            continue
        nm = re.match(r"(\d+)", val)
        if not nm:
            die(f"{source_label} '{typ_raw}' 행에서 선두 숫자를 찾지 못함: {val[:40]}")
        rows[key] = int(nm.group(1))
    if not rows:
        die(f"{source_label} 예산 표에서 행을 하나도 파싱하지 못함")
    return rows


def parse_skill_budget(text):
    m = re.search(r"^## 파일 예산\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        die("SKILL.md '## 파일 예산' 섹션을 찾지 못함")
    return parse_budget_table(m.group(1), "SKILL.md 예산표")


def parse_schema_table_budget(text):
    m = re.search(r"^## 4\. 파일 예산\n(.*?)(?=^### |^## |\Z)", text, re.M | re.S)
    if not m:
        die("wiki-schema.md '## 4. 파일 예산' 섹션을 찾지 못함")
    return parse_budget_table(m.group(1), "schema §4 표")


def parse_schema_type_budget(text):
    """schema §2.x 각 타입 섹션의 '- **예산**' 줄에서 {키: 값} 추출 (log/index는 §2에 없음)."""
    rows = {}
    sections = list(SCHEMA_TYPE_HEADING_RX.finditer(text))
    if not sections:
        die("wiki-schema.md '### 2.N <type>' 헤딩을 찾지 못함")
    for i, hm in enumerate(sections):
        typ = hm.group(1)
        end = sections[i + 1].start() if i + 1 < len(sections) else len(text)
        body = text[hm.start():end]
        bm = re.search(r"^- \*\*예산\*\*:\s*(.+)$", body, re.M)
        if not bm:
            die(f"schema §2 '{typ}' 섹션에서 '- **예산**' 줄을 찾지 못함")
        val = bm.group(1)
        if typ == "guide":
            for gm in re.finditer(r"([a-z-]+)\s*~(\d+)자", val):
                rows["guide:" + gm.group(1)] = int(gm.group(2))
            if not any(k.startswith("guide:") for k in rows):
                die("schema §2.6 guide 예산 파싱 실패 (~N자 형식 기대 — v1.138.0 문자 수 전환)")
        else:
            nm = re.search(r"~(\d+)자", val)
            if not nm:
                die(f"schema §2 '{typ}' 예산 줄에서 '~N자'를 찾지 못함 (v1.138.0 문자 수 전환)")
            rows[typ] = int(nm.group(1))
    return rows


def lint_budget(mod):
    rows = {}
    rows.update(mod.BUDGET)
    for k, v in mod.GUIDE_BUDGET.items():
        rows["guide:" + k] = v
    rows["log.md"] = mod.SPECIAL_BUDGET["log.md"]
    rows["index:body-lines"] = mod.INDEX_BODY_LINES
    rows["index:feat-rows"] = mod.INDEX_FEAT_ROWS
    return rows


# schema §3 통제 어휘 줄 → lint 상수 매핑. 값은 ' — ' 산문 앞 구간의 백틱 토큰만
# (category 줄은 뒤 산문에 `{personal|work}` 백틱이 있어 자르지 않으면 오염된다).
VOCAB_LINES = {
    "platform": (r"\*\*`platform` 통제 어휘\(고정\)\*\*:(.+)", "PLATFORM_VOCAB"),
    "origin": (r"\*\*`origin` 통제 어휘\(고정\)\*\*:(.+)", "ORIGIN_VOCAB"),
    "confidence": (r"\*\*`confidence` 통제 어휘\(고정\)\*\*:(.+)", "CONFIDENCE_VOCAB"),
    "category": (r"\*\*`category` 통제 어휘\(고정\)\*\*:(.+)", "CATEGORY_VOCAB"),
    "decision": (r"\*\*결정 통제 어휘\(고정, decision-log 항목\)\*\*:(.+)", "DECISION_VOCAB"),
}


def parse_routing_table(text):
    """SKILL.md '## 절차 목차' 라우팅 표를 파싱한다.

    반환: (letters, named) —
      letters: {절차 문자: [위치, ...]} — 위치는 상대경로 또는 None(본체). 중복 행 검출을 위해 list.
      named: [(라벨, 위치)] — 문자 절차가 아닌 데이터 행(0. 시작 절차·체크리스트 등)도 검사 대상.
    앵커: 최소 집합 A~L이 없으면 파싱 실패로 본다(exit 2). 추가 문자(M~)는 그대로 캡처돼 검사된다."""
    m = re.search(r"^## 절차 목차\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        die("SKILL.md '## 절차 목차' 섹션을 찾지 못함")
    letters, named = {}, []
    for rm in ROW_RX.finditer(m.group(1)):
        label, loc = rm.group(1), rm.group(2).strip().strip("`")
        if label in ("절차", "위치") or set(label) <= set("-: "):
            continue  # 헤더·구분선
        loc = None if "이 문서" in loc else loc
        lm = ROUTING_LETTER_RX.match(label)
        if lm:
            letters.setdefault(lm.group(1), []).append(loc)
        else:
            named.append((label, loc))
    missing = [c for c in "ABCDEFGHIJKL" if c not in letters]
    if missing:
        die(f"라우팅 표에서 절차 {','.join(missing)} 행을 찾지 못함 (발견: {sorted(letters)})")
    return letters, named


def check_procedure_placement(skill_text):
    """⑤ 절차 배치 정합 — 라우팅 표 전 행 검사.

    문자 절차: 대상 파일 실존 + `### X. ` 헤딩이 스캔 대상 전체에서 정확히 1곳 + 표의 위치와 일치
    + 표에 없는 스트레이 헤딩 검출 + 같은 문자의 중복 행 검출. 비문자 행(0. 시작 절차·체크리스트):
    대상 파일에 라벨 선두부와 일치하는 헤딩 실존. 파일 실존은 고유 경로당 1회만 센다.
    반환: (불일치 목록, 대조 항목 수). 스캔 대상은 본체 + 표가 참조하는 파일로 한정한다
    (wiki-schema.md 등 규칙 문서는 절차 본문이 아니므로 제외 — §2.N 헤딩과의 오탐도 없다)."""
    issues = []
    checked = 0
    letters, named = parse_routing_table(skill_text)
    all_locs = set()
    for locs in letters.values():
        all_locs.update(loc for loc in locs if loc)
    all_locs.update(loc for _, loc in named if loc)
    files = {"SKILL.md": skill_text}
    for rel in sorted(all_locs):
        checked += 1
        path = os.path.join(SKILL_DIR, *rel.split("/"))
        if not os.path.isfile(path):
            issues.append(f"라우팅 위치 '{rel}' 파일 없음")
        else:
            files[rel] = read(path)
    found = {}
    for fname, text in files.items():
        for hm in PROC_HEADING_RX.finditer(text):
            found.setdefault(hm.group(1), []).append(fname)
    for letter in sorted(set(letters) | set(found)):
        checked += 1
        if letter not in letters:
            issues.append(f"절차 헤딩(### {letter}. )이 {found[letter]}에 있으나 라우팅 표에 행 없음")
            continue
        rows = letters[letter]
        if len(rows) > 1:
            issues.append(f"라우팅 표에 절차 {letter} 행이 {len(rows)}개 (중복 — 위치가 갈리면 독자가 오도됨)")
        expected = rows[-1] or "SKILL.md"
        locs = found.get(letter, [])
        if len(locs) != 1:
            issues.append(f"절차 {letter} 헤딩(### {letter}. )이 {len(locs)}곳 {locs} — 정확히 1곳이어야 함")
        elif locs[0] != expected:
            issues.append(f"절차 {letter} 헤딩 위치 '{locs[0]}' ≠ 라우팅 표 '{expected}'")
    for label, loc in named:
        checked += 1
        target = loc or "SKILL.md"
        text = files.get(target)
        if text is None:
            continue  # 파일 부재는 위 고유 경로 검사에서 이미 보고됨
        # 라벨은 요약 표기('0. 시작 절차 (…) · 사전 준수 사항')라 괄호·병기 앞 선두부만 헤딩과 대조
        key = label.split("(")[0].split("·")[0].strip()
        if not re.search(r"^#{2,4}\s+" + re.escape(key), text, re.M):
            issues.append(f"라우팅 행 '{label}'의 헤딩('{key}' 선두)이 '{target}'에 없음")
    return issues, checked


def check_schema_toc(schema_text):
    """⑥ schema 목차(부분 Read 인덱스) 정합 — 목차 표의 § 번호 ↔ 실제 '## N.' 헤딩 1:1.

    목차는 손으로 유지하는 표라 § 삽입·재번호 시 조용히 낡는데, 부분 Read 세션은 전체 정독이
    금지라 낡은 목차를 자가 교정할 기회가 없다 — 기계로 잡는다. 제목 문구는 대조하지 않는다
    (목차의 내용 열은 요약 표현을 허용). 반환: (불일치 목록, 대조 항목 수)."""
    m = re.search(r"^## 목차[^\n]*\n(.*?)(?=^## |\Z)", schema_text, re.M | re.S)
    if not m:
        die("wiki-schema.md '## 목차' 섹션을 찾지 못함")
    toc = {int(rm.group(1)) for rm in re.finditer(r"^\|\s*(\d+)\s*\|", m.group(1), re.M)}
    if not toc:
        die("wiki-schema.md 목차 표에서 § 행을 하나도 파싱하지 못함")
    heads = {int(hm.group(1)) for hm in re.finditer(r"^## (\d+)\.", schema_text, re.M)}
    if not heads:
        die("wiki-schema.md '## N.' 헤딩을 하나도 찾지 못함")
    issues = []
    for n in sorted(toc - heads):
        issues.append(f"schema 목차에 §{n} 행이 있으나 '## {n}.' 헤딩 없음")
    for n in sorted(heads - toc):
        issues.append(f"schema '## {n}.' 헤딩이 목차(부분 Read 인덱스)에 미등록")
    return issues, len(toc | heads)


def check_f1_schema7(ops_text, schema_text):
    """⑦ F-1 실행 순서 인덱스 ↔ schema §7 검사 항목 번호 1:1 정합.

    F-1(procedures-ops.md)은 'N. `[기계]`/`[에이전트]` ...' 실행 순서 인덱스이고 상세 정본은
    §7-N(wiki-schema.md 'N. **...**')이다 — 규약상 번호가 1:1인데 둘 다 수동 목록이라 한쪽만
    추가·삭제하면 조용히 어긋난다. 파싱 앵커는 각 섹션 내부로 한정한다(F-1은 다음 #### 전까지,
    §7은 다음 '## N.' 전까지 — 다른 절의 번호 목록·표와 충돌하지 않게). 반환: (불일치 목록, 대조 수).

    한계(LOW-3): 번호 **집합**만 대조한다 — 같은 번호의 내용 정합(F-1 N의 의미 = §7-N의 의미)은
    검사하지 않는다(번호를 보존한 채 두 항목의 의미만 맞바꾸면 통과). 내용 정합은 사람 몫."""
    fm = re.search(r"^#### F-1\..*?\n(.*?)(?=^#### |\Z)", ops_text, re.M | re.S)
    if not fm:
        die("procedures-ops.md '#### F-1.' 섹션을 찾지 못함")
    f1 = {int(n) for n in re.findall(r"^(\d+)\.\s+`\[(?:기계|에이전트)\]`", fm.group(1), re.M)}
    if not f1:
        die("F-1 인덱스에서 'N. `[기계]`/`[에이전트]`' 항목을 하나도 파싱하지 못함")
    sm = re.search(r"^## 7\..*?\n(.*?)(?=^## \d|\Z)", schema_text, re.M | re.S)
    if not sm:
        die("wiki-schema.md '## 7.' 섹션을 찾지 못함")
    s7 = {int(n) for n in re.findall(r"^(\d+)\.\s+\*\*", sm.group(1), re.M)}
    if not s7:
        die("schema §7에서 'N. **...**' 검사 항목을 하나도 파싱하지 못함")
    issues = []
    for n in sorted(f1 - s7):
        issues.append(f"F-1 인덱스 {n}번이 schema §7에 없음 (정본 §7-{n} 부재 — 상세·판정 기준 없는 실행 항목)")
    for n in sorted(s7 - f1):
        issues.append(f"schema §7-{n} 검사 항목이 F-1 실행 순서 인덱스에 없음 (lint 세션이 이 검사를 건너뜀)")
    return issues, len(f1 | s7)


# ⑧ 산문 크로스파일 포인터 회귀 가드용 정규식.
# 파일 귀속이 명시된 포인터만 잡는다 — 파일명과 절차 라벨이 '인접'(의·따옴표·괄호·대시)해야 매치.
#   라벨만 있거나 파일만 있는 언급, 범위 서술(`…md`(A~E·I) 처럼 괄호 안 나열)은 skip(오탐 방지).
#   base 절차 문자 단위로만 대조 — 재분할 시 '절차가 다른 파일로 갔는데 포인터가 옛 파일 지칭'을 잡는 게 목적.
# 경로는 문서 지배 관례가 백틱 래핑(`…md`)이라 선택적 백틱을 허용한다(안 그러면 L2F 다수를 놓침 — B1).
_PROC_FILE = r"`?references/procedures-(?:content|ops)\.md`?"
# base 문자는 [A-Z] 동적 캡처 — [A-L] 하드코딩 금지(파일 상단 ROUTING_LETTER_RX 원칙과 일관 — 절차 M+
#   추가 시에도 매치되게, 미정의 문자는 letter_file.get()이 None이라 자연히 skip). 하위라벨(B-1 0·A-3a·B-2 3-1·K 5-1).
_LABEL = r"([A-Z])(?:[-\s]\d+[a-z]?)*"
# 파일→라벨: `…md의 B-1`, `…md "G"`, `…md F-1` (파일 뒤 구분자는 의/따옴표/공백만 — 괄호 불가로 `(A~E·I)` 범위서술 제외)
POINTER_F2L_RX = re.compile(_PROC_FILE + r'(?:의)?\s*"?\s*' + _LABEL)
# 라벨→파일: `B-1 0(`…md`)`, `B-1 0 — `…md``, `L(`…md`)`, `F-2(`…md`)` (라벨 뒤 괄호/대시 뒤 바로 파일, 백틱 포함)
POINTER_L2F_RX = re.compile(r"(?<![A-Za-z0-9])" + _LABEL + r"\s*[(—-]\s*(?:—\s*)?" + _PROC_FILE)
# 매치 문자열에서 '어느 파일'인지 되뽑기(content|ops)
_WHICH_FILE_RX = re.compile(r"references/procedures-(content|ops)\.md")


def build_letter_file_map():
    """A~L 각 절차 문자의 실제 `### X.` 헤딩이 있는 파일을 {문자: {파일,…}}로 반환.
    ⑤(check_procedure_placement)의 지역변수 found 대신 본체 + 분할 2파일을 직접 스캔한다
    (독립 재계산 — 지역변수 공유 대신). PROC_HEADING_RX(### X. )를 ⑤와 동일하게 사용."""
    result = {}
    sources = {
        "SKILL.md": read(SKILL_MD),
        "references/procedures-content.md": read(
            os.path.join(SKILL_DIR, "references", "procedures-content.md")),
        "references/procedures-ops.md": read(OPS_MD),
    }
    for fname, text in sources.items():
        for hm in PROC_HEADING_RX.finditer(text):
            result.setdefault(hm.group(1), set()).add(fname)
    return result


def check_prose_pointers(skill_text, schema_text):
    """⑧ 산문 크로스파일 포인터 회귀 가드.

    지연 로드 분할 후, '절차 라벨이 어느 파일에 있는지' 가리키는 산문 포인터(references/procedures-*.md
    + 인접 절차 라벨)가 실제 그 절차 헤딩이 있는 파일과 어긋나면 잡는다 — v1.90.1·v1.90.2에서
    손으로 고쳐온 스테일 포인터 부류의 회귀를 기계로 예방한다. 이 부류는 앵커·번호 집합 어디에도
    안 걸려 차기 재분할 시 조용히 재발한다(회귀 가드 공백).

    보수적 스코프(오탐 방지): 파일명 AND 라벨이 '인접'(의·따옴표·괄호·대시로 직접 연결)할 때만
    검사한다. 한 줄에 여러 (라벨→파일)이 있어도 각 인접쌍만 대조하므로, `K 5-1(본체 SKILL.md)·
    B-1 0(references/procedures-content.md)`처럼 서로 다른 귀속이 한 줄에 있어도 B만 content로
    대조하고 K는 (procedures-*.md가 아니라 SKILL.md 귀속이라) 건드리지 않는다. base 문자 단위 대조
    — 하위라벨(B-1 0의 '1 0')까지 검증하진 않는다(재분할 파일 오귀속 포착이 목적).
    반환: (불일치 목록, 대조 항목 수)."""
    letter_file = build_letter_file_map()
    docs = {
        "SKILL.md": skill_text,
        "references/procedures-content.md": read(
            os.path.join(SKILL_DIR, "references", "procedures-content.md")),
        "references/procedures-ops.md": read(OPS_MD),
        "references/wiki-schema.md": schema_text,
    }
    issues = []
    checked = 0
    for fname, text in docs.items():
        for line in text.splitlines():
            pairs = []  # (which_file, base_letter) 인접쌍
            for m in POINTER_F2L_RX.finditer(line):
                wm = _WHICH_FILE_RX.search(m.group(0))
                pairs.append((wm.group(1), m.group(1)))
            for m in POINTER_L2F_RX.finditer(line):
                wm = _WHICH_FILE_RX.search(m.group(0))
                pairs.append((wm.group(1), m.group(1)))
            for which, letter in pairs:
                actual = letter_file.get(letter)
                if not actual:
                    continue  # 헤딩 못 찾음(J/K는 본체 SKILL.md, 또는 미정의) — 대조 대상 아님
                checked += 1
                claimed = "references/procedures-%s.md" % which
                if claimed not in actual:
                    issues.append(
                        f"{fname} 산문 포인터: 절차 {letter}를 '{claimed}'로 귀속하나 "
                        f"실제 `### {letter}.` 헤딩은 {sorted(actual)}에 있음")
    return issues, checked


def check_templates_types(schema_text):
    """⑨ templates.md ↔ schema §2 타입 집합 정합.

    H-2 규약은 "타입 템플릿·주석이 바뀌면 references/templates.md도 함께 동기"를 요구하나,
    check_consistency는 SKILL·schema·lint만 대조하고 templates.md는 전혀 읽지 않아, 타입이
    추가·제거·개명돼도 templates가 조용히 스테일될 수 있었다(검사 사각지대). templates의 각 타입
    frontmatter `type:` 값 집합 ↔ schema §2.N 타입(SCHEMA_TYPE_HEADING_RX) 집합을 대조한다.

    타입 **집합**만 대조한다(필드 단위 아님) — schema는 선택 필드까지 문서화하고 templates는
    예시라 frontmatter 필드 집합이 정당하게 달라 필드 대조는 오탐이 크다. 타입 신설·삭제·개명이라는
    구조 드리프트만 신뢰성 있게 잡는다. 반환: (불일치 목록, 대조 항목 수)."""
    tmpl_text = read(TEMPLATES_MD)
    tmpl_types = set(re.findall(r"^type:\s*([a-z][a-z-]*)$", tmpl_text, re.M))
    if not tmpl_types:
        die("templates.md에서 'type:' frontmatter 값을 하나도 찾지 못함")
    schema_types = {hm.group(1) for hm in SCHEMA_TYPE_HEADING_RX.finditer(schema_text)}
    if not schema_types:
        die("wiki-schema.md '### 2.N <type>' 헤딩을 찾지 못함(⑨)")
    issues = []
    for t in sorted(schema_types - tmpl_types):
        issues.append(f"schema §2 타입 '{t}'가 templates.md에 없음(템플릿 누락 — H-2 동기 위반)")
    for t in sorted(tmpl_types - schema_types):
        issues.append(f"templates.md 타입 '{t}'가 schema §2에 없음(스키마 미정의 또는 개명 스테일)")
    return issues, len(tmpl_types | schema_types)


# ⑩ 타입 열거 정합용 — 산문이 다른 상수를 **이름으로 참조**하는 자리의 치환표.
#  §7-9가 "origin 필수 타입 + question + ..."처럼 집합을 문장으로 더하므로, 토큰 추출 전에
#  그 리터럴을 실제 집합으로 바꿔 놓지 않으면 항상 5개가 모자라 불일치가 난다.
PROSE_SET_ALIASES = {"origin 필수 타입": "ORIGIN_REQUIRED_TYPES"}

# ⑩-ⓐ 코드↔문서 — 값의 정본이 lint.py 상수인 자리. {ID: (구간 앵커, lint 도출)}
#  앵커의 group(1)이 타입 토큰을 담은 구간이며, 매치가 없으면 die(앵커 파싱 실패 = exit 2).
#  구간을 넓게 잡으면 안 된다 — 이물 토큰이 섞이면 문서를 고쳐도 영원히 불일치가 된다(A4 주석 참조).
TYPE_ENUM_SITES_LINT = {
    # §3 origin/confidence 두 줄: '—' 뒤 ~ '공통 필수 필드' 앞. 그 뒤 괄호 부기
    #  ('(decision-log·convention은 대상 아님)')는 리터럴 뒤라 자동 배제된다.
    "A1-origin": (r"^- \*\*`origin` 통제 어휘\(고정\)\*\*:[^\n]*?—(.+?)공통 필수 필드",
                  lambda lint: lint.ORIGIN_REQUIRED_TYPES),
    "A1-confidence": (r"^- \*\*`confidence` 통제 어휘\(고정\)\*\*:[^\n]*?—(.+?)공통 필수 필드",
                      lambda lint: lint.ORIGIN_REQUIRED_TYPES),
    # §7-9: 상수명을 문서가 직접 인용하는 자리 (PROSE_SET_ALIASES 치환 대상)
    "A2-updated": (r"`UPDATED_REQUIRED_TYPES` = (.+?),", lambda lint: lint.UPDATED_REQUIRED_TYPES),
    # §7-3 신선도 항목 줄 전체 — 한 줄에 규칙 4개(아카이브 제외/전체 면제 3종)가 섞여 있어
    #  세부 앵커로 쪼개면 문구 의존이 심해진다. 합집합으로 대조하는 편이 견고하다.
    "A3-freshness": (r"^3\. \*\*신선도\*\*(.+)$",
                     lambda lint: lint.FRESHNESS_EXEMPT_TYPES | lint.ARCHIVE_EXEMPT_TYPES),
    # §7-28: '**제외**:' 뒤 ~ 첫 ' — ' 앞
    "A5-release": (r"\*\*제외\*\*: (.+?) — ", lambda lint: lint.RELEASE_MARKER_EXEMPT_TYPES),
    # §11 적용 대상 줄. '적용 대상'만으로 잡으면 §4의 '- **적용 대상**: 하위 페이지 분리 처방을
    #  가진 전 타입 — feature·entity·…'(볼드)를 먼저 물어 green에 도달할 수 없다 → §11로 스코프 한정.
    "A6-validation": (r"^## 11\.[\s\S]*?^- 적용 대상: (.+)$", lambda lint: lint.ORIGIN_REQUIRED_TYPES),
}

# ⑩-ⓑ 전 타입 커버 — 값의 정본이 schema §2 타입 집합인 자리. 기대 집합을 계산으로 도출하므로
#  코드에 타입 값을 적지 않는다(B2의 매핑 2건만 예외 — 태그 표기가 타입명과 갈리는 지점).
TYPE_ENUM_SITES_COVER = {
    "B1-toc": r"^\| 2 \| [^|(]*\(([^)]+)\)",          # 목차 §2 행 내용열의 괄호 안 타입 나열
    "B2-tags": r"^- 계층 태그: (.+)$",                 # §3 계층 태그
    # §12 description 권장/비대상 2줄. **절 스코프가 필수다** — 스코프 없이 '은 대상이 아니다'로
    #  잡으면 §2.8의 '구현 세부 결정(…)은 대상이 아니다'(:256)를 먼저 물어 비대상 집합이 통째로
    #  비어 버린다(구현 중 실측). A6이 §11로 스코프를 한정한 것과 같은 이유다.
    "B4-desc-recommended": r"^### description \(권장 필드\)[\s\S]*?^- (.+?5타입 frontmatter에)",
    "B4-desc-excluded": r"^### description \(권장 필드\)[\s\S]*?^- (.+?은 대상이 아니다)",
}
# B2 계층 태그는 §2 타입과 1:1이 아니다 — source-stub이 'source'로 표기되고 recipe(guide 하위
#  종류)가 추가된다. 이 둘이 축 ⑩ 전체에서 코드에 값을 적는 유일한 자리다.
TAG_ALIAS = {"source-stub": "source"}
TAG_EXTRA = {"recipe"}


def extract_type_tokens(text, vocab):
    """구간 text에서 어휘 vocab에 속하는 타입 토큰만 뽑아 집합으로 반환.

    길이 내림차순 alternation이 필수다 — 'source-stub'이 'source'로 잘리면 B2가 항상 불일치한다.
    앞뒤 경계로 [a-z-]를 배제해 'decision-log'가 'decision'으로 잘리는 것과 '20_projects'의
    'project' 오탐을 함께 막는다(뒤에 's'가 오면 매치되지 않는다). 백틱·볼드 마크업은 무시된다.
    숫자·언더스코어는 배제 클래스에 넣지 않았다 — 현재 10개 자리의 문면에 'project_'류 인접
    표기가 없어서이며, 그런 표기가 들어오는 자리가 생기면 [a-z0-9_-]로 넓힌다(\b를 쓰지 않는
    이유는 하이픈 복합 타입명 보존이다)."""
    if not vocab:
        return set()
    pat = "|".join(re.escape(t) for t in sorted(vocab, key=len, reverse=True))
    return set(re.findall(r"(?<![a-z-])(" + pat + r")(?![a-z-])", text))


def _enum_span(text, rx, label):
    """자리 앵커로 구간을 잡아 group(1)을 반환. 못 찾으면 die (exit 2 — 조용한 통과 금지)."""
    m = re.search(rx, text, re.M)
    if not m:
        die(f"⑩ 타입 열거 자리 '{label}' 앵커를 찾지 못함 (문서 문면 변경 신호)")
    return m.group(1)


def check_type_enumerations(schema_text, lint):
    """⑩ 신규 타입 열거 누락 정합.

    새 페이지 타입을 도입할 때 **기존 타입이 산문으로 열거된 자리**가 조용히 낡는 사각을 잡는다
    (v1.164.0이 `convention` 신설 때 그 자리들을 일회성 정규식 스캔으로 손수 찾아낸 것이 계기).
    두 그룹으로 나뉘며 기대 집합의 정본이 서로 다르다 —
      ⓐ 값의 정본이 lint.py 상수인 자리: 상수 ↔ 문서 산문을 집합 대조(축 ②와 같은 구조).
        새 타입이 그 자리에 없어도 lint 상수에 없으면 정상이므로 '미판정'은 검출하지 않는다.
      ⓑ 값의 정본이 schema §2 타입 집합인 자리: 전 타입이 등장(또는 분할 커버)해야 한다.
        새 타입 누락을 강제로 잡는 역할은 이쪽이 담당한다.
    반환: (불일치 목록, 대조 항목 수)."""
    types = {hm.group(1) for hm in SCHEMA_TYPE_HEADING_RX.finditer(schema_text)}
    if not types:
        die("wiki-schema.md '### 2.N <type>' 헤딩을 찾지 못함(⑩)")
    issues = []
    checked = 0

    # ⓐ 코드↔문서
    for label, (rx, derive) in sorted(TYPE_ENUM_SITES_LINT.items()):
        span = _enum_span(schema_text, rx, label)
        for alias, attr in PROSE_SET_ALIASES.items():
            if alias in span:
                span = span.replace(alias, " ".join(getattr(lint, attr)))
        checked += 1
        found = extract_type_tokens(span, types)
        expected = set(derive(lint))
        if found != expected:
            issues.append(f"타입 열거 '{label}' 불일치: 문서에만 {sorted(found - expected)} / "
                          f"lint 상수에만 {sorted(expected - found)}")

    # ⓐ A4 — §8 「아카이브」 예외 목록. 절 전체가 아니라 '- **예외' 줄만 모은다:
    #  같은 절에 'confidence 하락은 … 모든 타입(project·feature 포함)에 적용된다'가 있어
    #  절 전체를 구간으로 쓰면 project가 섞여 문서를 고쳐도 불일치가 풀리지 않는다.
    sec = re.search(r"^### 아카이브\n(.*?)(?=^### |\Z)", schema_text, re.M | re.S)
    if not sec:
        die("wiki-schema.md §8 '### 아카이브' 절을 찾지 못함(⑩ A4)")
    exc = [ln for ln in sec.group(1).splitlines() if re.match(r"^- \*\*예외", ln)]
    if not exc:
        die("§8 '### 아카이브' 절에서 '- **예외' 줄을 하나도 찾지 못함(⑩ A4)")
    checked += 1
    found = extract_type_tokens("\n".join(exc), types)
    expected = lint.FRESHNESS_EXEMPT_TYPES | lint.ARCHIVE_EXEMPT_TYPES
    if found != expected:
        issues.append(f"타입 열거 'A4-archive-exceptions' 불일치: 문서에만 {sorted(found - expected)} / "
                      f"lint 상수에만 {sorted(expected - found)}")

    # ⓑ 전 타입 커버
    cover_expected = {
        "B1-toc": types,
        "B2-tags": {TAG_ALIAS.get(t, t) for t in types} | TAG_EXTRA,
    }
    cover_vocab = {"B2-tags": types | set(TAG_ALIAS.values()) | TAG_EXTRA}
    for label in ("B1-toc", "B2-tags"):
        span = _enum_span(schema_text, TYPE_ENUM_SITES_COVER[label], label)
        checked += 1
        found = extract_type_tokens(span, cover_vocab.get(label, types))
        expected = cover_expected[label]
        if found != expected:
            issues.append(f"타입 열거 '{label}' 불일치: 문서에만 {sorted(found - expected)} / "
                          f"§2 타입 기준에만 {sorted(expected - found)}")

    # ⓑ B3 — templates.md 목차 ↔ 그 파일의 type: 값 집합. 기존 ⑨는 type:만 보고 목차는 읽지 않아
    #  목차 누락이 기계에 걸리지 않았다(v1.164.0이 사람 확인 항목으로 남긴 자리).
    tmpl_text = read(TEMPLATES_MD)
    tm = re.search(r"^## 목차\n(.*?)(?=^## )", tmpl_text, re.M | re.S)
    if not tm:
        die("templates.md '## 목차' 섹션을 찾지 못함(⑩ B3)")
    tmpl_types = set(re.findall(r"^type:\s*([a-z][a-z-]*)$", tmpl_text, re.M))
    if not tmpl_types:
        die("templates.md에서 'type:' frontmatter 값을 찾지 못함(⑩ B3)")
    checked += 1
    found = extract_type_tokens(tm.group(1), tmpl_types)
    if found != tmpl_types:
        issues.append(f"타입 열거 'B3-templates-toc' 불일치: 목차에만 {sorted(found - tmpl_types)} / "
                      f"템플릿 본문에만 {sorted(tmpl_types - found)}")

    # ⓑ B4 — §12 description 권장/비대상의 **분할 커버**. 합집합이 §2 전 타입이어야 하고
    #  교집합은 공집합이어야 한다(한 타입이 양쪽에 적히는 모순 검출). 새 타입이 어느 쪽에도
    #  들어가지 않으면 여기서 걸린다 — 이 축이 겨냥한 실패 모드다.
    rec = extract_type_tokens(
        _enum_span(schema_text, TYPE_ENUM_SITES_COVER["B4-desc-recommended"], "B4-desc-recommended"),
        types)
    exd = extract_type_tokens(
        _enum_span(schema_text, TYPE_ENUM_SITES_COVER["B4-desc-excluded"], "B4-desc-excluded"), types)
    checked += 1
    if rec | exd != types:
        issues.append(f"타입 열거 'B4-description' 분할 커버 위반: 어느 쪽에도 없는 타입 "
                      f"{sorted(types - (rec | exd))} / §2에 없는 표기 {sorted((rec | exd) - types)}")
    if rec & exd:
        issues.append(f"타입 열거 'B4-description' 중복: {sorted(rec & exd)}가 권장·비대상 양쪽에 있음")

    return issues, checked


def parse_schema_vocab(text):
    out = {}
    for key, (rx, _attr) in VOCAB_LINES.items():
        m = re.search(rx, text)
        if not m:
            die(f"wiki-schema.md §3 '{key}' 통제 어휘 줄을 찾지 못함")
        head = re.split(r"[—(]", m.group(1), maxsplit=1)[0]  # 산문·괄호 앞 구간만
        vals = set(re.findall(r"`([^`]+)`", head))
        if not vals:
            die(f"wiki-schema.md §3 '{key}' 어휘 값을 파싱하지 못함")
        out[key] = vals
    return out


def main():
    skill_text = read(SKILL_MD)
    schema_text = read(SCHEMA_MD)
    lint = load_lint()

    budget_sources = {
        "lint.py": lint_budget(lint),
        "SKILL.md 예산표": parse_skill_budget(skill_text),
        "schema §2 타입별 줄": parse_schema_type_budget(schema_text),
        "schema §4 표": parse_schema_table_budget(schema_text),
    }
    mismatches = []
    all_keys = sorted(set().union(*[set(v) for v in budget_sources.values()]))
    checked = 0
    for key in all_keys:
        vals = {src: rows[key] for src, rows in budget_sources.items() if key in rows}
        if len(vals) < 2:
            continue  # 한 소스에만 있으면 대조 불가(구조상 §2에 없는 log/index 등) — 대상 아님
        checked += 1
        if len(set(vals.values())) > 1:
            detail = " / ".join(f"{src}={v}" for src, v in vals.items())
            mismatches.append(f"예산 '{key}' 불일치: {detail}")

    schema_vocab = parse_schema_vocab(schema_text)
    for key, (_rx, attr) in VOCAB_LINES.items():
        lint_vals = set(getattr(lint, attr))
        sch_vals = schema_vocab[key]
        checked += 1
        if lint_vals != sch_vals:
            only_lint = sorted(lint_vals - sch_vals)
            only_sch = sorted(sch_vals - lint_vals)
            mismatches.append(
                f"통제 어휘 '{key}' 불일치: lint에만 {only_lint} / schema에만 {only_sch}")

    placement_issues, placement_checked = check_procedure_placement(skill_text)
    checked += placement_checked
    mismatches.extend(placement_issues)

    toc_issues, toc_checked = check_schema_toc(schema_text)
    checked += toc_checked
    mismatches.extend(toc_issues)

    f1_issues, f1_checked = check_f1_schema7(read(OPS_MD), schema_text)
    checked += f1_checked
    mismatches.extend(f1_issues)

    pointer_issues, pointer_checked = check_prose_pointers(skill_text, schema_text)
    checked += pointer_checked
    mismatches.extend(pointer_issues)

    tmpl_issues, tmpl_checked = check_templates_types(schema_text)
    checked += tmpl_checked
    mismatches.extend(tmpl_issues)

    enum_issues, enum_checked = check_type_enumerations(schema_text, lint)
    checked += enum_checked
    mismatches.extend(enum_issues)

    print("== llm-wiki 상수 정합 셀프체크 (SKILL ↔ schema ↔ lint) ==")
    if mismatches:
        for m in mismatches:
            print(f"[MISMATCH] {m}")
        print(f"\n결과: 불일치 {len(mismatches)}건 / 대조 {checked}항목 — "
              f"H-2 규약(references/procedures-ops.md 하단 '(참고)' 블록)대로 관련 파일을 함께 갱신하세요.")
        sys.exit(1)
    print(f"결과: 대조 {checked}항목 전부 일치 (예산 {len(all_keys)}키 + 통제 어휘 5종 + "
          f"절차 배치 {placement_checked}항목 + schema 목차 {toc_checked}§ + "
          f"F-1↔§7 {f1_checked}항목 + 산문 포인터 {pointer_checked}건 + templates 타입 "
          f"{tmpl_checked}종 + 타입 열거 {enum_checked}자리 — 항목당 소스 2~4곳 대조)")
    sys.exit(0)


if __name__ == "__main__":
    main()
