#!/usr/bin/env python3
"""SKILL.md ↔ wiki-schema.md ↔ lint.py 공유 상수 정합 셀프체크.

사용법: python check_consistency.py   (인자 없음 — 번들 내 상대 위치로 세 파일을 찾는다)
       python check_consistency.py --trigger-report
         축 ⑪(예산 트리거 조건 어휘 유일성)의 위반·화이트리스트·차집합 목록만 출력한다.
         정합 대조는 돌지 않고 exit 0으로 끝난다(위반 여부는 인자 없는 기본 실행이 축으로 본다 —
         여기는 차집합·면제 잔여까지 펼쳐 보는 상세 리포트다).

무엇을: llm-wiki의 공유 상수(파일 예산·통제 어휘)는 네 곳에 존재한다 —
  ① lint.py 상수(BUDGET·GUIDE_BUDGET·SPECIAL_BUDGET·INDEX_*·*_VOCAB)
  ② references/wiki-ops-rules.md '## 파일 예산' 표 (v1.180.0 T8이 SKILL.md에서 분리)
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

⑪ 예산 트리거 조건 어휘 유일성 — 예산 처방의 발동·종료·재발동·승급 조건은 wiki-schema §7-2
(와 임계 정본인 SKILL '## 예산 단계 신호' 표)에서만 서술하고, 나머지 자리는 조건을 다시 쓰지 않고
`§7-2 발동 시` 포인터만 둔다 — **예외는 §7-2가 명시한 `lint.py` 임계 상수 근거 주석 하나**로,
그 자리는 조건의 형태를 말하지 않으면 '이 상수를 지우면 안 되는 이유'가 성립하지 않는다. 그 자리들이 저마다 조건을 다시 쓰던 것이 v1.177 회차에서 6라운드
연속 드리프트를 낸 원인이다(헤딩은 「임박」인데 본문은 「초과」 같은 반쪽 상태). 조건이 한 곳에만
있으면 그 상태를 만들 수 없다. 상세 리포트(차집합·면제 잔여)는 `--trigger-report`로 본다.

판정:
  - 전 항목 일치 → 요약 출력 + exit 0
  - 불일치 → 항목별 소스 값 나열 + exit 1
  - 파싱 앵커 실패(섹션·표·어휘 줄을 못 찾음) → exit 2 (조용한 통과 금지 —
    앵커가 사라졌다는 것 자체가 문서 구조 변경 신호이므로 소리 내어 실패한다)

lint.py 상수는 재파싱하지 않고 importlib로 모듈을 로드해 직접 읽는다(정의가 곧 정본).
표준 라이브러리만 사용(AGENTS.md 정합).
"""
import glob
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
# 쓰기 세션 전용 규칙(파일 예산·예산 단계 신호·네이밍·J 부트스트랩)이 SKILL.md에서 분리된 자리(v1.180.0 T8).
#  코드 세션(절차 K)이 로드하지 않도록 뺀 것이라 예산 표·예산 단계 파싱도 이 파일을 본다.
OPS_RULES_MD = os.path.join(SKILL_DIR, "references", "wiki-ops-rules.md")
TEMPLATES_MD = os.path.join(SKILL_DIR, "references", "templates.md")
LINT_PY = os.path.join(SKILL_DIR, "scripts", "lint.py")
CONTENT_MD = os.path.join(SKILL_DIR, "references", "procedures-content.md")
LINT_CASES_JSON = os.path.join(EVALS_DIR, "lint-cases.json")

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


def parse_ops_rules_budget(text):
    """예산 표는 references/wiki-ops-rules.md에 있다(v1.180.0 T8 분리). text는 그 파일 내용이다."""
    m = re.search(r"^## 파일 예산\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        die("wiki-ops-rules.md '## 파일 예산' 섹션을 찾지 못함")
    return parse_budget_table(m.group(1), "wiki-ops-rules.md 예산표")


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
        "wiki-ops-rules.md": read(OPS_RULES_MD),
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
    # §7-29: '**제외 타입**:' 뒤 ~ 첫 ' — ' 앞. A5의 '**제외**: '와는 문면이 달라 서로 물지 않는다.
    #  구간을 첫 ' — '에서 끊는 것이 필수다 — 그 뒤에 'question은 제외하지 않는다'는 근거가 오는데,
    #  구간에 들어오면 found에 question이 섞여 엄격 비교가 영원히 불일치가 된다(A4·A6 주석과 같은 함정).
    "A7-emoji": (r"\*\*제외 타입\*\*: (.+?) — ", lambda lint: lint.EMOJI_EXEMPT_TYPES),
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

# ⑩-ⓑ 삭제 이력 — 「타입을 지웠는데 산문에 이름이 남는」 사각을 잡는 유일한 경로.
#  아래 check_type_enumerations docstring이 적듯 축 ⑩의 토큰 추출은 어휘를 **실재 타입으로
#  한정**해 오탐을 막으므로, 삭제된 이름은 애초에 추출되지 않아 조용히 통과한다. 어휘를 넓히면
#  산문 단어 오탐이 들어와 그 1급 요건을 깨므로, 넓히는 대신 **삭제한 이름만 따로 아는 목록**을 준다.
# ⚠ **비어 있는 것이 현재의 정상 상태다** — 2026-08-19 실측(`lint.py` 73커밋 추적)에서 현행
#  8타입 대비 과거에만 있던 타입이 0건이었다. 이 축이 겨냥한 결함은 아직 한 번도 실현된 적이
#  없고, 여기 있는 것은 **다음 삭제 때 작동할 자리**다. 빈 dict 자체가 「삭제 이력 0건」의 기록이다.
# ⚠ **사람이 갱신해야 동작한다** — 타입을 삭제하면 `{이름: 사유·삭제 회차}`를 여기 추가한다.
#  같은 규약을 wiki-schema.md §2 서두에도 적어 두 곳에서 보이게 했다(한쪽만 보고 지나치지 않게).
# 이름이 **다른 의미의 일반어로 재사용**되면(예: 타입명이 아닌 문맥의 같은 단어) 오탐이 나므로,
#  그때는 사유란에 문맥 한정을 적거나 그 이름을 목록에서 뺀다.
RETIRED_TYPES = {}


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

    ⚠ ⓐⓑ의 검출 방향은 **누락 한쪽뿐이다** — 토큰 어휘를 실재 타입으로 한정하므로(오탐 차단이
    1급 요건) 타입을 **삭제한 뒤 산문에 남은 유령 이름**은 애초에 추출되지 않아 조용히 통과한다
    (개명은 새 이름이 없어서, 오타는 기대 토큰이 없어서 잡히지만 순수 잔존은 안 잡힌다).
    아래 issue 문면의 '문서에만 [...]' 분기가 ⓑ에서 비는 이유가 이것이며, 넓히려면 어휘를
    열어야 하는데 그러면 산문 단어 오탐이 들어온다 — 의식적 트레이드오프다(F-7 m2).
    **그 반대 방향은 B5가 목록 등재분에 한해서만 본다**(`RETIRED_TYPES`) — 자동 확장이 아니라
    사람이 적은 이름만 보므로 위 어휘 한정을 깨지 않는다. 즉 미등재 삭제 이름은 여전히 통과한다.
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

    # ⓑ B5 — 삭제된 타입의 유령 이름(RETIRED_TYPES). 위 docstring이 「검출 방향은 누락 한쪽뿐」
    #  이라 적은 그 반대 방향이다. 목록에 있는 이름만 보므로 오탐 경로가 새로 열리지 않는다 —
    #  어휘 확대 없이 닫는 것이 이 설계의 요지다. 경계 클래스는 extract_type_tokens와 같게 맞춘다
    #  (하이픈 복합 타입명이 잘리거나 '20_projects'의 project가 물리는 것을 함께 막는다).
    checked += 1
    for name, reason in sorted(RETIRED_TYPES.items()):
        ghosts = [label for label, text in (("wiki-schema.md", schema_text), ("templates.md", tmpl_text))
                  if re.search(r"(?<![a-z-])" + re.escape(name) + r"(?![a-z-])", text)]
        if ghosts:
            issues.append(f"타입 열거 'B5-retired' 유령 이름: 삭제된 타입 '{name}'이 "
                          f"{'·'.join(ghosts)}에 남아 있다 ({reason})")

    return issues, checked


# 예산 단계 신호 표(SKILL.md '## 예산 단계 신호') 행 라벨 → (lint 상수명, 해석 방식).
#  이 표를 `## 파일 예산` 절 밖의 형제 `##`로 둔 이유는 parse_ops_rules_budget이 그 절을 다음 `##`까지
#  통째로 잡고 parse_budget_table이 구간 내 모든 `|`행을 훑기 때문이다 — 절 안에 두면 이 표의
#  헤더행이 예산 데이터로 잡혀 die()가 난다(그래서 별도 앵커가 필요했다).
BUDGET_STAGE_ROWS = {
    "근접": ("BUDGET_NEAR_RATIO", "percent"),
    "임박(비율)": ("BUDGET_CRITICAL_RATIO", "percent"),
    "임박(잔여)": ("BUDGET_CRITICAL_SLACK", "chars"),
    "재판정 마진": ("BUDGET_REJUDGE_MARGIN", "percent"),
    "판정 어휘": ("BUDGET_SPLIT_VOCAB", "vocab"),
}


def check_budget_stages(ops_rules_text, lint):
    """예산 단계 임계·판정 어휘 정합 — SKILL.md '## 예산 단계 신호' 표 ↔ lint.py 상수.

    기존 예산 축(값 4소스 대조)이 다루지 않는 자리다: 임계 상수(BUDGET_NEAR_RATIO 계열)와
    budget_split 통제 어휘는 어느 대조에도 들어 있지 않아, 한쪽만 고쳐도 조용히 통과했다.
    문서 측 앵커를 표 하나로 좁힌 이유는 산문에 흩어진 수치를 파싱하면 문면이 조금만 바뀌어도
    앵커가 깨져 exit 2(파싱 실패)가 나기 때문이다."""
    m = re.search(r"^## 예산 단계 신호\n(.*?)(?=^## |\Z)", ops_rules_text, re.M | re.S)
    if not m:
        die("wiki-ops-rules.md '## 예산 단계 신호' 섹션을 찾지 못함")
    found = {}
    for line in m.group(1).splitlines():
        cm = re.match(r"^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|", line)
        if not cm:
            continue
        label, val = cm.group(1), cm.group(2)
        if label not in BUDGET_STAGE_ROWS:
            continue  # 헤더·구분선·미등록 행
        found[label] = val
    missing = sorted(set(BUDGET_STAGE_ROWS) - set(found))
    if missing:
        die(f"wiki-ops-rules.md 예산 단계 표에서 행을 찾지 못함: {missing}")

    issues, checked = [], 0
    for label, (const, kind) in BUDGET_STAGE_ROWS.items():
        raw = found[label]
        lint_val = getattr(lint, const)
        checked += 1
        if kind == "vocab":
            doc_vals = set(re.findall(r"`([^`]+)`", raw))
            if doc_vals != set(lint_val):
                issues.append(f"예산 단계 '{label}' 어휘 불일치: SKILL={sorted(doc_vals)} / "
                              f"lint.{const}={sorted(lint_val)}")
            continue
        nm = re.match(r"(\d+(?:\.\d+)?)", raw)
        if not nm:
            die(f"wiki-ops-rules.md 예산 단계 '{label}' 행에서 선두 숫자를 찾지 못함: {raw[:40]}")
        doc_num = float(nm.group(1))
        # percent 행은 문서가 %로 적고 lint은 비율로 갖는다(80% ↔ 0.8) — 단위를 맞춰 비교한다.
        doc_val = doc_num / 100 if kind == "percent" else doc_num
        if abs(doc_val - float(lint_val)) > 1e-9:
            issues.append(f"예산 단계 '{label}' 불일치: SKILL={raw.strip()} / "
                          f"lint.{const}={lint_val}")
    return issues, checked


# ⑪ 예산 트리거 조건 어휘 유일성 — 예산 처방의 발동·종료·재발동·승급 조건은
#  wiki-schema §7-2(와 임계 정본인 SKILL '## 예산 단계 신호' 표)에서만 서술하고,
#  다른 자리는 조건을 적지 않고 `§7-2 발동 시` 포인터만 둔다(예외는 §7-2가 명시한
#  `lint.py` 임계 상수 근거 주석 하나 — 아래 화이트리스트에 사유와 함께 등재돼 있다). 그 자리들이 저마다 조건을
#  다시 쓰던 것이 v1.177 회차에서 6라운드 연속 드리프트를 낸 원인이다(헤딩은 「임박」인데
#  본문은 「초과」 같은 반쪽 상태). 조건이 한 곳에만 있으면 그 상태를 만들 수 없다.
#
# 조건어는 **어미를 열거하지 않고 축어만** 쓴다. 어미 열거형은 두 번 뚫렸다 —
#  `초과 시|초과하면|초과면` 계열은 `초과가 확실하면`(procedures-content I-2b)을 놓쳤고,
#  그것을 고치며 `넘기?[면는]`로 남긴 갈래는 `넘길 것 같으면`(schema §2.2 온보딩)을 놓쳤다.
#  반증(예산과 무관한 「초과」·「넘」)은 정규식을 좁히는 대신 아래 화이트리스트로만 거른다 —
#  면제는 늘어나는 것이 보이지만 정규식의 사각은 보이지 않기 때문이다.
TRIGGER_COND_RX = re.compile(r"임박|예산\s*이내|초과|넘")

# 조사용 광의 패턴 — 위 조건어보다 넓게 잡아 **차집합**(광의에는 걸리는데 축 ⑪ 스캔에는
#  안 들어오는 줄)을 만든다. 그 차집합이 비어 있지 않은 것은 정상이고, 처분되지 않은 줄이
#  남는 것이 실패다. 정규식이 좁아 놓친 것과 정말 무관한 것을 구분하는 유일한 장치다.
TRIGGER_BROAD_RX = re.compile(r"임박|초과|넘|예산|한도|여유")

# 스캔 스코프 — 규정을 **서술**하는 자리만 본다. `lint.py`의 출력 f-string(`예산 임박: …`)과
#  `lint-cases.json`의 expect 문자열은 규정 서술이 아니라 **신호 그 자체**라, 금지하면
#  정본 출력을 없애라는 뜻이 된다.
#
# 목록을 손으로 적지 않고 `references/*.md`를 글롭으로 훑는 이유: 손 열거는 **신규 reference
#  파일이 조용히 스캔 밖에 남는다**(축 ⑪의 전제가 "대상 열거를 기계가 한다"인데 파일 단위에서만
#  사람 손이었다). 명시 제외 목록을 미리 두지 않는 것도 같은 이유다 — 제외 자리가 곧 그 사각을
#  재생산한다. 빼야 할 파일이 실제로 생기면 그때 사유와 함께 추가한다.
TRIGGER_SCAN_EXCLUDE = set()  # 파일명(basename) 집합. 현재 비어 있다 — 위 주석 참조.


def _trigger_scan_scope():
    """축 ⑪의 스캔 대상을 `(경로, kind)` 정렬 리스트로 산출한다.

    kind는 확장자에서 도출한다(`.md`→md / `.py`→py / `.json`→json) — 손으로 붙이면
    파일이 늘 때마다 그 자리도 손대야 한다."""
    paths = [SKILL_MD, LINT_PY, LINT_CASES_JSON]
    paths += sorted(glob.glob(os.path.join(SKILL_DIR, "references", "*.md")))
    out = []
    for p in paths:
        if os.path.basename(p) in TRIGGER_SCAN_EXCLUDE:
            continue
        ext = os.path.splitext(p)[1]
        kind = {".md": "md", ".py": "py", ".json": "json"}.get(ext)
        if kind is None:
            die(f"축 ⑪ 스캔 스코프에 처리할 수 없는 확장자: {p}")
        out.append((p, kind))
    return out

# 정본 앵커 — 구간이다(줄이 아니다). §7-2는 착수 시점에 한 줄이지만 소불릿으로 나뉘면
#  여러 줄이 되므로, 줄로 잡으면 정본을 정리하는 순간 그 정리가 위반으로 잡힌다.
TRIGGER_ANCHORS = {
    SCHEMA_MD: (r"^2\. \*\*예산 준수\*\*", r"^3\. \*\*"),
    OPS_RULES_MD: (r"^## 예산 단계 신호", r"^## "),
}

# 예산 축 ①의 부분 소스 허용 — 「구조상 네 소스 전부에는 존재할 수 없는 키」만 넣는다.
#  목적은 아래 `TRIGGER_ALLOWLIST`와 같다(면제 항목마다 사유를 남긴다 — 자료 구조는 다르다:
#  이쪽은 `{키: 사유}` dict, 저쪽은 `(파일, 앵커, 사유[, 기대 수])` 튜플 리스트다).
#
# ⚠ 이 목록이 **비어 있지 않은 것이 정상**이다 — 아래 셋은 §2가 「타입별 페이지」를 서술하는
#  절이라 페이지 타입이 아닌 키(index의 줄/행 상한, log.md)를 담을 자리가 구조상 없다.
#  종전 게이트가 `len(vals) < 2`(0·1소스)만 잡아 **2·3소스에만 등재된 키는 값만 맞으면
#  통과**했고, 그것이 원 결함이 지목한 fail-open이다(새 타입을 두 곳에만 적어도 exit 0).
#  이제 「네 소스 전수 등재」를 요구하고 예외는 여기에만 둔다.
BUDGET_PARTIAL_SOURCE_OK = {
    "index:body-lines": "§2에 없음 — index는 문자 예산이 아니라 본문 줄 수가 임계라 타입별 예산 줄에 자리가 없다(§7-14 축)",
    "index:feat-rows": "§2에 없음 — 위와 같은 이유(기능별 인덱스 행 수 임계)",
    "log.md": "§2에 없음 — log는 페이지 타입이 아니라 단일 파일이라 타입별 예산 서술 대상이 아니다",
}

# 면제 열거 — 「파일, 줄 내용 앵커, 사유[, 기대 매치 수]」. 줄 번호가 아니라 **줄 내용**으로
#  잡는 이유는 후속 task의 편집으로 번호가 밀리기 때문이다. 앵커는 대상 파일의 스캔 대상
#  줄에서 **기대 매치 수만큼**(4번째 원소 생략 시 1건) 매치해야 하고, 어긋나면 issue로 낸다 —
#  적으면 문면이 바뀌어 면제가 허공을 가리키는 것이고, 많으면 면제가 의도하지 않은 줄까지
#  덮는 것이다. 기대 수를 2 이상으로 적는 자리는 **같은 문면이 여러 벌 복제된 곳**뿐이며,
#  그 벌 수를 열거에 적어 두면 벌 수가 달라지는 것 자체가 신호가 된다.
TRIGGER_ALLOWLIST = [
    # ── index 줄/행 축(§7-14) — 문자 예산이 아니라 본문 400줄·기능별 인덱스 200행이 트리거다
    (SCHEMA_MD, "| index.md | 제한 없음", "§7-14 index 트리거 — 줄/행 기준이라 문자 예산 무관"),
    (SCHEMA_MD, '**트리거는 "그 시점 임계 초과"**', "§7-14 index 분할 트리거의 시점 규정"),
    (SCHEMA_MD, "> lint §7-14 INFO(본문 400줄", "§4 분할 수행 절차 서두의 §7-14 신호 인용"),
    (SCHEMA_MD, "- **범위는 2단계 category 분할과 3단계", "index 분할 자동화 근거(2·3단계 라우팅 결정론) — §7-14 축"),
    (SCHEMA_MD, "- **수행 시점은 그 세션의 주 작업 완료 후**다", "index 분할 수행 시점 — 「임계를 넘는다」는 §7-14 축"),
    (SCHEMA_MD, "- **3단계(순번)**: 초과한 sub-index가 무순번", "index 3단계 순번 분할 — §7-14 축"),
    (SCHEMA_MD, "3. **내용 이동(잘라내기)**", "index 분할의 초과분 이동 — §7-14 축"),
    (SCHEMA_MD, "14. **index.md·sub-index 분할 신호**", "§7-14 검사 항목 본문 — index 트리거 정본"),
    (SCHEMA_MD, "**예산 판정 방식 (펜스 제외 — platform-bootstrap·ui-ux 한정)**",
     "§2.6 펜스 제외 판정 — 「초과 WARN 문구」는 §7-2 신호의 이름 인용이지 조건 서술이 아니다"),
    (SCHEMA_MD, "- **도달 경로(4번 등록)의 기계 검증은 타입에 따라",
     "「lint 통과만 보고 넘기면」 — 예산 무관"),
    (SCHEMA_MD, "2b. **델타 신뢰도 점검**", "허브 `updated` 30일 초과 = 신선도 축(§7-3)"),
    (OPS_RULES_MD, "| index.md | 제한 없음", "§7-14 index 트리거 — 줄/행 기준"),
    (OPS_MD, "`[기계]` index·sub-index 분할 신호", "F-1 인덱스의 §7-14 라벨"),
    (LINT_PY, "# index.md 분할 신호 임계", "INDEX_BODY_LINES 상수 주석 — index 축"),
    (LINT_PY, "#   sub-index(순번 파일) 초과는", "위 상수 주석의 이어지는 줄 — index 축"),
    (LINT_PY, "# sub-index(순번 파일)가 초과하면", "§7-14 3단계 자동 분할 구현 주석"),
    (LINT_PY, "# 본체 조립 + 임계 초과 시 덜어내기", "§4 1단계 본체 구역 분리 — 줄 수 축(§7-14)"),
    (LINT_PY, "「본문(frontmatter 포함 전체)」이라 생성 구역만 세면",
     "§7-14 측정 단위(파일 전체 줄 수) 근거 — 문자 예산 무관"),

    # ── `--auto-split` 처방 구현(§4·§8) — 조건을 **정의**하지 않고 §7-2 조건을 구현·인용한다.
    #  budget_state/budget_resolved가 §7-2 네 조건의 유일 구현이므로 그 docstring은 조건의
    #  형태를 말하지 않으면 근거가 성립하지 않는다(임계 상수 근거 주석과 같은 예외 축).
    (LINT_PY, "없으면 None(그 경우 종료 기준은", "budget_state target 필드 설명 — §7-2 종료 조건 구현"),
    (LINT_PY, "**「예산 이내」가 종료 기준이 아니다**", "budget_resolved docstring — §7-2 종료 조건 정본 인용"),

    # ── §2.2 항목 개수 축 — `## 최근 주요 변경`은 6번째 항목이 트리거이고 문자 예산과 무관하다
    #    (§7 결과 처리가 "⚠ project 허브만 트리거가 다르다"로 명시 배제한 대상이다).
    #    `§7-2 발동 시`로 치환하면 정본이 되려는 §7-2가 자기 배제 규정과 충돌한다.
    (SCHEMA_MD, "**초과분은 압축하지 않고 롤오버한다**", "§2.2 6번째 항목 트리거 — 문자 예산 무관"),
    (SCHEMA_MD, "| project (허브) | 13000자 |", "§4 표 project 행 — 3열 롤오버 구가 §2.2 항목 개수 축"),
    (SCHEMA_MD, "**project 허브 `## 최근 주요 변경`**: 3~5개를 유지하고", "§8 롤오버 — §2.2 항목 개수 축"),
    (TEMPLATES_MD, "<!-- 3~5개 유지. 초과분은 압축하지 않고", "허브 템플릿 주석 — §2.2 항목 개수 축"),
    (TEMPLATES_MD, "# budget_split_chars: 0         #   lint 예산 판정과 같은 기준의 문자 수(=임박 메시지의 {현재} 값,",
     "`budget_split_chars` 필드 설명 — 「임박 메시지」는 §7-2 신호의 이름 인용이지 조건 서술이 아니다", 2),  # 템플릿 2곳 공통 문면

    # ── 예산과 무관한 「초과」·「넘」 — 축어 정규식이 넓어 걸리지만 트리거 서술이 아니다
    (SCHEMA_MD, "소비 대상은 두 태그뿐이다", "절차 M 보류 8종의 상황 범주 열거 — 예산은 그중 한 항목명"),
    (SCHEMA_MD, "7. **기록**: `log.md`에", "log 기록 형식의 `(사유: 임계 초과)` 예시 문자열"),
    (CONTENT_MD, "그 파일은 프로젝트 단위 규약", "「스택을 넘는 일반 패턴」 — 귀속 판정이지 예산 아님"),
    (CONTENT_MD, "5. **델타 신뢰도 점검**", "허브 `updated` 30일 초과 = 신선도 축"),
    (CONTENT_MD, "> **축소 조건 (소규모 갱신)**", "변경 파일 5개 초과 = 개수 조건, 예산 무관"),
    (SKILL_MD, '**"범용 패턴"(`30_knowledge/patterns/`)을 먼저 보고**', "절차 K 조회 순서 — 「경계를 넘는 지식」"),
    (SKILL_MD, "**무매칭 = 사실대로 보고(합성 금지)**", "「기록 없이 넘기면」 — 큐 기록 규약"),
    (SKILL_MD, "- **잔량·체류 경고**: append 시 둘 중", "skill-feedback 큐 잔량·체류 임계"),
    (SKILL_MD, "- **입도 기준(필수 — 노이즈 방지)**", "[DECISION] 큐 입도 — 「범위를 넘는」"),
    (SKILL_MD, "- **잔량 경고**: append 시 `pending.md`", "pending 큐 잔량 임계"),
    (LINT_PY, "#   기존 `[^\\n]*`는 줄바꿈을 못 넘어", "펜스 정규식 구현 주석 — 예산 무관"),
    (LINT_PY, "#  **수용된 한계**: 접두가 15자를 넘는 위반", "큐 형식 접두 길이 — 예산 무관"),

    # ── `lint.py` 구현 주석 — 임계 상수의 근거와 억제 로직 설명. 신호를 만드는 코드 옆의
    #    주석이라 §7-2·SKILL 예산 단계 표의 코드측 대응이며, 규정을 다시 서술하는 자리가 아니다.
    (LINT_PY, "# 임박 판정의 선행 게이트", "BUDGET_NEAR_RATIO 상수 근거 — §7-2가 명시 예외로 둔 자리"),
    (LINT_PY, "#  이 상수를 지우면 안 되는 이유", "위 상수 근거의 이어지는 줄"),
    (LINT_PY, "#  선행 게이트가 빠지면 예산이 작은 타입", "위 상수 근거의 이어지는 줄"),
    (LINT_PY, "# 예산 임박 임계 — 초과 전에 나는 유일한 신호다", "BUDGET_CRITICAL_* 상수 근거 — §7-2가 명시 예외로 둔 자리"),
    (LINT_PY, "#  타입(source-stub 1800)에서 72%짜리가 임박이 된다", "위 상수 근거의 이어지는 줄"),
    (LINT_PY, "#  §4의 이동·분리 처방이 성립하지 않는다", "BUDGET_REJUDGE_MARGIN 상수 근거"),
    (LINT_PY, "#  판정 시점 문자 수(budget_split_chars) 대비", "위 상수 근거의 이어지는 줄"),
    (LINT_PY, '#  영구 면제로 두면 "한 번 판정하면', "위 상수 근거의 이어지는 줄"),
    (LINT_PY, '"""「분리 불가 판정」이 유효해', "budget_split 억제 판정 함수 docstring"),
    (LINT_PY, "억제는 임박에만 적용되고", "위 docstring의 이어지는 줄"),
    (LINT_PY, "# 이 경로에는 임박 계층이 없어", "SPECIAL_BUDGET 임박 분기 구현 주석"),
    (LINT_PY, '#  무신호가 되고, "임박 도달 시', "위 분기 주석의 이어지는 줄"),
    (LINT_PY, "#   영구 '예산 초과' WARN을 만드는 것을 막는다", "억제 로직 구현 주석"),
    (LINT_PY, "# 수리 경로가 정해진 타입은 초과 시점에도", "초과 WARN 힌트 병기 구현 주석"),
    (LINT_PY, "#  안내하고 초과 WARN에서 침묵하면", "위 주석의 이어지는 줄"),
    (LINT_PY, "# L-5: 초과 전에 나는 유일한 신호다", "임박 WARN 분기 구현 주석"),
    (LINT_PY, "# L-4: 위 임박 분기가 budget_split", "억제 강등 INFO 분기 구현 주석"),
    (LINT_PY, "#   동일하고 억제 여부만 다르다", "위 분기 주석의 이어지는 줄"),
    (LINT_PY, "#   침묵시키지 않는 이유: 억제를 영구 면제로", "위 분기 주석의 이어지는 줄"),

    # ── eval 실증 서술 — 케이스가 무엇을 실증하는지의 기록이지 규정 서술이 아니다
    #    (`:398`은 폐지된 근접 INFO를 인용한 stale이라 T6의 치환 대상 — 여기 넣지 않는다).
    (LINT_CASES_JSON, '"rationale": "§7-2 파일 예산 초과 (WARN)"', "초과 WARN 케이스 실증 서술"),
    (LINT_CASES_JSON, '"rationale": "§7-2 펜스 제외 판정', "펜스 제외 판정 케이스 실증 서술"),
    (LINT_CASES_JSON, '"rationale": "§7-14 순번 sub-index', "index 축 케이스 실증 서술"),
    (LINT_CASES_JSON, '"rationale": "§7-2 임박 단계(WARN)', "임박 OR 두 항 케이스 실증 서술"),
    (LINT_CASES_JSON, '"rationale": "「분리 불가 판정」(budget_split)', "억제·재판정 케이스 실증 서술"),
    (LINT_CASES_JSON, '"rationale": "§7-2 convention 예산(12000자) 초과 WARN + 처방 힌트',
     "convention 초과 WARN·힌트 병기 케이스 실증 서술 — 「초과 WARN」은 §7-2가 내는 신호의 이름이고 이 케이스가 실증하는 대상이다"),

    # ── budget_split 부속 — 「분리 불가 판정」 필드 정의(§3). 처방 불가 판정의 기록 규약이지
    #    발동 조건 서술이 아니다.
    (SCHEMA_MD, "- **`budget_split` 3필드 (선택", "§3 budget_split 필드 정의"),
]

# 차집합 사유 — 광의 패턴에는 걸리지만 예산 트리거가 아닌 줄. 위 화이트리스트와 자료구조를
#  나누는 이유는 이쪽이 **스캔 밖**의 줄이라 「앵커 1건 매치」 검증의 대상이 아니기 때문이다.
#  섞으면 두 검사의 의미가 충돌한다.
#  앵커가 `None`이면 **그 파일의 스코프 정의가 의도적으로 뺀 부류 전체**를 덮는다 — 같은
#  사유를 줄마다 25번 적는 것이 오히려 노이즈이기 때문이다. 대신 리포트가 **덮은 줄 수를
#  출력**해 면제가 조용히 자라는 것을 볼 수 있게 한다(D6가 지키려는 것은 "면제 열거"라는
#  형식이 아니라 "면제가 보인다"는 성질이다). md 파일은 전 줄이 스캔 대상이라 차집합이
#  구조적으로 0이고, 부류 사유를 쓰는 것은 스코프를 좁힌 두 파일뿐이다.
TRIGGER_DIFFSET_NOTES = [
    (LINT_PY, None,
     "스코프 정의상 제외 — 코드·출력 f-string. 규정 서술이 아니라 신호 그 자체이며, "
     "여기를 금지하면 정본 출력(`예산 임박: …`)을 없애라는 뜻이 된다(D5)"),
    (LINT_CASES_JSON, None,
     "스코프 정의상 제외 — expect 문자열·`_note`. lint 출력의 기대값이라 "
     "`run_lint_evals.py`가 정본으로 검증한다(여기서 다시 고정하면 이중 관리)"),
]


def _scan_lines(path, kind):
    """파일에서 '규정을 서술하는 줄'만 뽑아 `(스캔 줄, 원본 줄 전량)`으로 반환한다 (스코프 한정 — D5).

    원본 줄을 함께 돌려주는 이유: 호출부의 차집합 계산이 **스캔 대상 밖 줄**을 필요로 해
    같은 파일을 한 번 더 읽고 있었다. 여기서 한 번만 읽어 넘긴다."""
    lines = read(path).split("\n")
    if kind == "md":
        return [(i + 1, ln) for i, ln in enumerate(lines)], lines
    if kind == "json":
        return [(i + 1, ln) for i, ln in enumerate(lines) if '"rationale"' in ln], lines
    if kind == "py":
        out = []
        in_doc = False
        for i, ln in enumerate(lines):
            s = ln.strip()
            is_scannable = s.startswith("#") or in_doc or s.startswith('"""')
            # 여는/닫는 `"""`가 한 줄에 하나만 있을 때만 상태를 뒤집는다
            # (`"""한 줄 docstring"""`은 두 개라 상태 불변).
            if s.count('"""') == 1:
                in_doc = not in_doc
            # 코드 뒤 **인라인** 주석도 규정을 서술한다 — `BUDGET` 딕셔너리의 타입별 주석이
            # 그 예다. 선두 `#`만 보면 그 자리가 통째로 스캔 밖으로 빠진다(차집합 검사가
            # `lint.py:72`를 미처분으로 드러내 발견한 사각).
            if not is_scannable and _py_inline_comment(ln) is not None:
                is_scannable = True
            if is_scannable:
                out.append((i + 1, ln))
        return out, lines
    die(f"⑪ 알 수 없는 스캔 스코프 종류: {kind}")


def _py_inline_comment(line):
    """코드 뒤 인라인 주석 본문을 반환. 주석이 없으면 None.

    문자열 리터럴 안의 `#`을 주석으로 오인하지 않도록 따옴표 상태를 따라간다
    (`warn(f"... #tag ...")` 같은 줄이 통째로 주석 취급되는 것을 막는다)."""
    quote = None
    escaped = False
    for idx, ch in enumerate(line):
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            continue
        if ch == "#":
            return line[idx:]
    return None


def _anchor_span(path, lines):
    """정본 앵커 구간의 줄 번호 집합과 issue 목록. 앵커가 없는 파일은 (빈 집합, []).

    시작 정규식은 **문서 전체에서 1건**이어야 한다 — 여러 건이면 첫 매치를 말없이 골라
    엉뚱한 구간을 정본으로 삼는다(화이트리스트 앵커에 건 것과 같은 검증을 여기에도 둔다.
    한쪽에만 두면 "자리마다 매치가 1건인가를 실측한다"는 원칙이 반쪽이 된다)."""
    if path not in TRIGGER_ANCHORS:
        return set(), []
    start_rx, end_rx = TRIGGER_ANCHORS[path]
    starts = [no for no, ln in lines if re.match(start_rx, ln)]
    if not starts:
        die(f"⑪ 정본 앵커 시작을 찾지 못함: {os.path.basename(path)} /{start_rx}/")
    issues = []
    if len(starts) > 1:
        issues.append(f"{os.path.basename(path)}: 정본 앵커 시작이 {len(starts)}건 매치 "
                      f"(1건이어야 함) — /{start_rx}/ @ {starts}")
    start = starts[0]
    for no, ln in lines:
        if no > start and re.match(end_rx, ln):
            return set(range(start, no)), issues
    return set(range(start, lines[-1][0] + 1)), issues


def check_trigger_locality():
    """⑪ 예산 트리거 조건 어휘 유일성. 반환: (위반, 화이트리스트 검증, 차집합, 면제 잔여).

    다른 축은 `(issues, checked)` 2-튜플을 반환하는데 이 축만 4-튜플인 이유: 리포트가
    위반뿐 아니라 **화이트리스트 앵커별 매치 수**와 **차집합 처분 상태**를 함께 내야
    하고(그 둘이 각각 「면제가 엉뚱한 줄을 덮지 않는가」·「정규식이 좁아 놓친 것이
    없는가」를 지키는 장치다), 2-튜플로는 그 정보가 담기지 않는다. main() 축으로 편입할
    `main()`은 앞의 두 값만 `(issues, checked)`로 접어 기존 집계 루프에 맞추고,
    뒤의 둘은 `--trigger-report`에서만 펼친다.

    위반 = 정본 앵커 밖 + 화이트리스트 밖인데 조건어가 있는 스캔 대상 줄.
    이 목록이 곧 「포인터로 바꿔야 할 자리」의 전수다 — 사람이 grep으로 세면 형태가
    다른 자리를 놓치지만(6라운드 실증), 기계가 세면 놓치지 않는다."""
    violations = []
    allow_report = []
    diffset = []
    residual = []

    for path, kind in _trigger_scan_scope():
        name = os.path.basename(path)
        scan, raw_lines = _scan_lines(path, kind)
        scan_by_no = dict(scan)
        scan_nos = set(scan_by_no)
        anchor_nos, anchor_issues = _anchor_span(path, scan)
        violations.extend(anchor_issues)

        # 화이트리스트 앵커를 줄 번호로 해소 (0건·2건 이상은 그 자체가 issue)
        allowed_nos = set()
        for entry in TRIGGER_ALLOWLIST:
            a_path, needle, reason = entry[0], entry[1], entry[2]
            # 4번째 원소는 **기대 매치 수**(생략 시 1). 같은 문면이 한 파일에 여러 벌
            # 복제된 자리가 실재해서(템플릿 두 곳의 동일 필드 주석) 필요하다 — 그때
            # "몇 벌인가"를 열거에 적어 두면 벌 수가 달라지는 것 자체가 신호가 된다.
            expected = entry[3] if len(entry) > 3 else 1
            if a_path != path:
                continue
            hits = [no for no, ln in scan if needle in ln]
            allow_report.append((name, needle, len(hits), reason))
            if len(hits) != expected:
                violations.append(
                    f"{name}: 화이트리스트 앵커가 {len(hits)}건 매치 ({expected}건이어야 함) — {needle!r}")
            allowed_nos.update(hits)
            # 면제 잔여 — 앵커가 설명하는 조건어를 지운 **나머지**에 조건어가 또 있으면 보고한다.
            #  화이트리스트는 줄 단위라, 한 줄에 정당한 면제(예: index 축)와 진짜 트리거 서술이
            #  함께 있으면 **후자가 통째로 숨는다.** 실제로 `wiki-schema.md:384`가 그렇게 숨었다 —
            #  index 자동화 근거를 말하는 줄 안에 §7 결과 처리 예외 ②의 구 문구가 복제돼 있었고,
            #  같은 문구를 `:536`에서는 치환했는데 여기만 면제로 넘어갔다.
            #  하드 위반으로 내지 않는 이유: 앵커가 조건어를 포함하지 않는 정당한 항목이 많아
            #  (앵커는 「그 줄을 특정하는 조각」이지 「면제할 조건어」가 아니다) 전건이 잔여로 잡힌다.
            #  판정은 사람이 하되 **보이게** 만드는 것이 목적이다(차집합 절과 같은 취급).
            for no in hits:
                rest = scan_by_no[no].replace(needle, "")
                for m in TRIGGER_COND_RX.finditer(rest):
                    ctx = rest[max(0, m.start() - 30):m.start() + 40].strip()
                    residual.append((name, no, m.group(0), ctx, reason))

        for no, ln in scan:
            if no in anchor_nos or no in allowed_nos:
                continue
            if TRIGGER_COND_RX.search(ln):
                violations.append(f"{name}:{no}: {ln.strip()[:120]}")

        # 차집합 — 광의에는 걸리는데 스캔 대상이 아닌 줄
        notes = [(nd, r) for p, nd, r in TRIGGER_DIFFSET_NOTES if p == path]
        for i, ln in enumerate(raw_lines):
            no = i + 1
            if no in scan_nos or not TRIGGER_BROAD_RX.search(ln):
                continue
            reason = next((r for nd, r in notes if nd is None or nd in ln), None)
            diffset.append((name, no, ln.strip()[:100], reason))

    return violations, allow_report, diffset, residual


def report_trigger_locality():
    """`--trigger-report` 진입점. 목록만 출력하고 실패시키지 않는다 (exit 0).

    축은 `main()`에 편입돼 있고(v1.178.0 T7) 위반이 남으면 기본 실행이 exit 1이다.
    이 리포트 모드를 함께 남긴 이유: **차집합·면제 잔여는 사람이 판정할 목록**이라
    `main()` 집계에 접히지 않는다. 편입을 소진이 끝난 뒤로 미룬 것도 같은 축의 판단이었다 —
    위반이 남은 도중에 넣었으면 매 task 검증이 FAIL해 자율 루프가 그라인딩했을 것이다."""
    violations, allow_report, diffset, residual = check_trigger_locality()

    print("== ⑪ 예산 트리거 조건 어휘 유일성 (리포트 모드 — 실패시키지 않음) ==")
    print(f"\n[위반] {len(violations)}건 — 정본 앵커·화이트리스트 밖의 조건어")
    for v in violations:
        print(f"  {v}")

    print(f"\n[화이트리스트] {len(allow_report)}건 — 앵커별 매치 수(엔트리 기대치와 대조 — 기본 1)")
    expected_by = {(os.path.basename(e[0]), e[1]): (e[3] if len(e) > 3 else 1)
                   for e in TRIGGER_ALLOWLIST}
    for name, needle, hits, reason in allow_report:
        flag = "OK " if hits == expected_by.get((name, needle), 1) else "!! "
        print(f"  {flag}{name} ({hits}건) {needle[:50]!r} — {reason}")

    unresolved = [d for d in diffset if d[3] is None]
    print(f"\n[차집합] {len(diffset)}건 (사유 등재 {len(diffset) - len(unresolved)} / "
          f"미처분 {len(unresolved)}) — 광의 패턴에는 걸리나 스캔 대상이 아닌 줄")
    covered = {}
    for name, _no, _text, reason in diffset:
        if reason is not None:
            covered[name] = covered.get(name, 0) + 1
    for name, cnt in sorted(covered.items()):
        print(f"  OK {name}: {cnt}줄이 부류 사유로 덮임")
    print("  ⚠ 미처분 줄은 둘 중 하나로 처분한다: 트리거가 아니면 TRIGGER_DIFFSET_NOTES에")
    print("    사유를 등재하고, 트리거이면 사유를 붙이지 말고 TRIGGER_COND_RX를 넓히거나")
    print("    해당 task의 치환 대상에 편입한다.")
    for name, no, text, reason in unresolved:
        print(f"  ?? {name}:{no}: {text}")

    print(f"\n[면제 잔여] {len(residual)}건 — 화이트리스트 줄에서 **앵커를 지운 나머지**에 남은 조건어")
    print("  ⚠ 줄 단위 면제라 한 줄에 정당한 면제와 진짜 트리거 서술이 섞이면 후자가 숨는다.")
    print("    각 줄이 그 사유로 정말 덮이는지 확인하고, 아니면 치환 대상으로 꺼낸다.")
    for name, no, word, ctx, reason in residual:
        print(f"  ~~ {name}:{no} [{word}] {ctx[:70]} — 사유: {reason[:40]}")

    total_exempt = len(TRIGGER_ALLOWLIST) + len(TRIGGER_DIFFSET_NOTES)
    print(f"\n[면제 총계] 화이트리스트 {len(TRIGGER_ALLOWLIST)} + 차집합 사유 "
          f"{len(TRIGGER_DIFFSET_NOTES)} = {total_exempt} (상한 130 — 넘으면 면제가 규칙을 삼킨 것)")
    sys.exit(0)


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
    if "--trigger-report" in sys.argv[1:]:
        report_trigger_locality()  # exit 0으로 끝난다
    skill_text = read(SKILL_MD)
    ops_rules_text = read(OPS_RULES_MD)
    schema_text = read(SCHEMA_MD)
    lint = load_lint()

    budget_sources = {
        "lint.py": lint_budget(lint),
        "wiki-ops-rules.md 예산표": parse_ops_rules_budget(ops_rules_text),
        "schema §2 타입별 줄": parse_schema_type_budget(schema_text),
        "schema §4 표": parse_schema_table_budget(schema_text),
    }
    mismatches = []
    # 축별 `(라벨, 값, 단위)`. 출력 문구를 여기서 조립하므로 축을 추가할 때
    #  손댈 자리가 이 리스트 하나다(종전에는 f-string 끝의 열거를 함께 고쳐야 했다).
    axes = []
    all_keys = sorted(set().union(*[set(v) for v in budget_sources.values()]))
    checked = 0
    for key in all_keys:
        vals = {src: rows[key] for src, rows in budget_sources.items() if key in rows}
        if len(vals) < len(budget_sources):
            # 종전 게이트는 `len(vals) < 2`(0·1소스)라, **새 타입이 두 소스에만 등재되고
            #  나머지 두 곳에서 빠져도 값만 맞으면 조용히 exit 0**이었다(v1.164.0이 plan
            #  acceptance로 우회했던 그 구멍 — 우회는 그 plan에만 있고 검사기에는 남지 않았다).
            #  이제 **네 소스 전수 등재**를 요구하고, 건너뛰는 것은 위 허용 목록에 있는 키뿐이다.
            reason = BUDGET_PARTIAL_SOURCE_OK.get(key)
            if reason is None:
                missing = ", ".join(sorted(set(budget_sources) - set(vals)))
                mismatches.append(
                    f"예산 '{key}'가 일부 소스에만 있다 — 빠진 곳: {missing}. "
                    f"네 소스 전부에 등재하거나, 구조상 그곳에 둘 수 없는 키면 "
                    f"BUDGET_PARTIAL_SOURCE_OK에 사유와 함께 넣어라")
                continue
            # 허용된 키도 **있는 소스끼리는** 값이 맞아야 한다 — 면제는 「자리가 없다」는
            #  사실에 대한 것이지 값 드리프트까지 봐주는 것이 아니다.
        checked += 1
        if len(set(vals.values())) > 1:
            detail = " / ".join(f"{src}={v}" for src, v in vals.items())
            mismatches.append(f"예산 '{key}' 불일치: {detail}")

    axes.append(("예산", len(all_keys), "키"))

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

    axes.append(("통제 어휘", len(VOCAB_LINES), "종"))

    placement_issues, placement_checked = check_procedure_placement(skill_text)
    checked += placement_checked
    mismatches.extend(placement_issues)
    axes.append(("절차 배치", placement_checked, "항목"))

    toc_issues, toc_checked = check_schema_toc(schema_text)
    checked += toc_checked
    mismatches.extend(toc_issues)
    axes.append(("schema 목차", toc_checked, "§"))

    f1_issues, f1_checked = check_f1_schema7(read(OPS_MD), schema_text)
    checked += f1_checked
    mismatches.extend(f1_issues)
    axes.append(("F-1↔§7", f1_checked, "항목"))

    pointer_issues, pointer_checked = check_prose_pointers(skill_text, schema_text)
    checked += pointer_checked
    mismatches.extend(pointer_issues)
    axes.append(("산문 포인터", pointer_checked, "건"))

    tmpl_issues, tmpl_checked = check_templates_types(schema_text)
    checked += tmpl_checked
    mismatches.extend(tmpl_issues)
    axes.append(("templates 타입", tmpl_checked, "종"))

    enum_issues, enum_checked = check_type_enumerations(schema_text, lint)
    checked += enum_checked
    mismatches.extend(enum_issues)
    axes.append(("타입 열거", enum_checked, "항목"))

    stage_issues, stage_checked = check_budget_stages(ops_rules_text, lint)
    checked += stage_checked
    mismatches.extend(stage_issues)
    axes.append(("예산 단계", stage_checked, "항목"))

    # ⑪ 트리거 유일성 — 4-튜플의 앞 두 값만 접어 쓴다. 차집합·면제 잔여는 사람이
    #  판정할 리포트라 `--trigger-report`에만 나오고, 여기서는 **위반 유무**만 본다.
    trigger_issues, trigger_allow, _diffset, _residual = check_trigger_locality()
    trigger_checked = len(trigger_allow) + len(TRIGGER_ANCHORS)
    checked += trigger_checked
    mismatches.extend(trigger_issues)
    axes.append(("트리거 유일성", trigger_checked, "항목"))

    print("== llm-wiki 상수 정합 셀프체크 (SKILL ↔ schema ↔ lint) ==")
    if mismatches:
        for m in mismatches:
            print(f"[MISMATCH] {m}")
        print(f"\n결과: 불일치 {len(mismatches)}건 / 대조 {checked}항목 — "
              f"H-2 규약(references/procedures-ops.md 하단 '(참고)' 블록)대로 관련 파일을 함께 갱신하세요.")
        sys.exit(1)
    breakdown = " + ".join(f"{label} {n}{unit}" for label, n, unit in axes)
    print(f"결과: 대조 {checked}항목 전부 일치 ({breakdown} — 항목당 소스 2~4곳 대조)")
    sys.exit(0)


if __name__ == "__main__":
    main()
