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
            for gm in re.finditer(r"([a-z-]+)\s*~(\d+)줄", val):
                rows["guide:" + gm.group(1)] = int(gm.group(2))
            if not any(k.startswith("guide:") for k in rows):
                die("schema §2.6 guide 예산 줄 파싱 실패")
        else:
            nm = re.search(r"~(\d+)줄", val)
            if not nm:
                die(f"schema §2 '{typ}' 예산 줄에서 '~N줄'을 찾지 못함")
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
    §7은 다음 '## N.' 전까지 — 다른 절의 번호 목록·표와 충돌하지 않게). 반환: (불일치 목록, 대조 수)."""
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

    print("== llm-wiki 상수 정합 셀프체크 (SKILL ↔ schema ↔ lint) ==")
    if mismatches:
        for m in mismatches:
            print(f"[MISMATCH] {m}")
        print(f"\n결과: 불일치 {len(mismatches)}건 / 대조 {checked}항목 — "
              f"H-2 규약(references/procedures-ops.md 하단 '(참고)' 블록)대로 관련 파일을 함께 갱신하세요.")
        sys.exit(1)
    print(f"결과: 대조 {checked}항목 전부 일치 (예산 {len(all_keys)}키 + 통제 어휘 5종 + "
          f"절차 배치 {placement_checked}항목 + schema 목차 {toc_checked}§ + "
          f"F-1↔§7 {f1_checked}항목 — 항목당 소스 2~4곳 대조)")
    sys.exit(0)


if __name__ == "__main__":
    main()
