#!/usr/bin/env python3
"""SKILL.md ↔ wiki-schema.md ↔ lint.py 공유 상수 정합 셀프체크.

사용법: python check_consistency.py   (인자 없음 — 번들 내 상대 위치로 세 파일을 찾는다)

무엇을: llm-wiki의 공유 상수(파일 예산·통제 어휘)는 네 곳에 존재한다 —
  ① lint.py 상수(BUDGET·GUIDE_BUDGET·SPECIAL_BUDGET·INDEX_*·*_VOCAB)
  ② SKILL.md '## 파일 예산' 표
  ③ wiki-schema.md 타입별 '- **예산**: ~N줄' 줄 (§2.x)
  ④ wiki-schema.md §4 예산 표 (schema 내 이중 표현 — ③과 ④가 서로 어긋나는 것도 잡는다)
SKILL.md H-2는 이들의 수동 동기화를 요구하는데, 사람이 한 곳을 고치고 나머지를 놓치면
드리프트가 조용히 생긴다. 이 스크립트가 그 드리프트를 기계로 잡는다.

추가로 ⑤ 절차 배치 정합을 검사한다 — SKILL.md는 지연 로드 분할(본체 + references/procedures-*.md)
구조라, 본체 '## 절차 목차' 라우팅 표가 가리키는 파일이 실존하고 각 절차 헤딩(### A. ~ ### L.)이
표의 위치에 정확히 1곳만 존재해야 한다(파일 개명·헤딩 소실·중복 시 라우팅이 허공을 가리킴).

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
LINT_PY = os.path.join(SKILL_DIR, "scripts", "lint.py")

# schema §2.x 헤딩 → 예산 키 (### 2.N 뒤 첫 토큰이 타입명)
SCHEMA_TYPE_HEADING_RX = re.compile(r"^### 2\.\d+\s+([a-z-]+)", re.M)

# SKILL 본체 라우팅 표 행: | A. 프로젝트 추가 | `references/procedures-content.md` | 또는 | ... | (이 문서) |
ROUTING_ROW_RX = re.compile(r"^\|\s*([A-L])\.\s[^|]*\|\s*(.+?)\s*\|", re.M)
# 절차 헤딩(### 레벨 고정 — #### A-1. 하위 헤딩과 구분)
PROC_HEADING_RX = re.compile(r"^### ([A-L])\. ", re.M)


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
    """SKILL.md '## 절차 목차' 라우팅 표에서 {절차 문자: 상대경로 또는 None(본체)}을 추출한다."""
    m = re.search(r"^## 절차 목차\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        die("SKILL.md '## 절차 목차' 섹션을 찾지 못함")
    rows = {}
    for rm in ROUTING_ROW_RX.finditer(m.group(1)):
        letter, loc = rm.group(1), rm.group(2).strip().strip("`")
        rows[letter] = None if "이 문서" in loc else loc
    if sorted(rows) != list("ABCDEFGHIJKL"):
        die(f"라우팅 표에서 절차 A~L 12행을 찾지 못함 (발견: {sorted(rows)})")
    return rows


def check_procedure_placement(skill_text):
    """⑤ 절차 배치 정합 — 라우팅 표 경로 실존 + 절차 헤딩이 표의 위치에 정확히 1곳.

    반환: (불일치 목록, 대조 항목 수). 스캔 대상은 본체 + 표가 참조하는 파일로 한정한다
    (wiki-schema.md 등 규칙 문서는 절차 본문이 아니므로 제외 — §2.N 헤딩과의 오탐도 없다)."""
    issues = []
    checked = 0
    routing = parse_routing_table(skill_text)
    files = {"SKILL.md": skill_text}
    for letter in sorted(routing):
        rel = routing[letter]
        if rel is None:
            continue
        checked += 1
        path = os.path.join(SKILL_DIR, *rel.split("/"))
        if not os.path.isfile(path):
            issues.append(f"절차 {letter} 라우팅 위치 '{rel}' 파일 없음")
        elif rel not in files:
            files[rel] = read(path)
    found = {}
    for fname, text in files.items():
        for hm in PROC_HEADING_RX.finditer(text):
            found.setdefault(hm.group(1), []).append(fname)
    for letter in "ABCDEFGHIJKL":
        checked += 1
        locs = found.get(letter, [])
        expected = routing[letter] or "SKILL.md"
        if len(locs) != 1:
            issues.append(f"절차 {letter} 헤딩(### {letter}. )이 {len(locs)}곳 {locs} — 정확히 1곳이어야 함")
        elif locs[0] != expected:
            issues.append(f"절차 {letter} 헤딩 위치 '{locs[0]}' ≠ 라우팅 표 '{expected}'")
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

    print("== llm-wiki 상수 정합 셀프체크 (SKILL ↔ schema ↔ lint) ==")
    if mismatches:
        for m in mismatches:
            print(f"[MISMATCH] {m}")
        print(f"\n결과: 불일치 {len(mismatches)}건 / 대조 {checked}항목 — "
              f"SKILL.md H-2 규약대로 관련 파일을 함께 갱신하세요.")
        sys.exit(1)
    print(f"결과: 대조 {checked}항목 전부 일치 (예산 {len(all_keys)}키 + 통제 어휘 5종 + "
          f"절차 배치 {placement_checked}항목 — 항목당 소스 2~4곳 대조)")
    sys.exit(0)


if __name__ == "__main__":
    main()
