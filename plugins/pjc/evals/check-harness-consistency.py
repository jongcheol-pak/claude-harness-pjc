#!/usr/bin/env python3
"""하니스 전역 정합 셀프체크 — 문서 로드 예산 · 리뷰어 각주 · 실행 예산 수치 · 포인터 도달성 · 마커 목록 · 개념 정본 · Deferred 집계 · 볼드 마커 짝 · 한 줄 문장 중복 · 착수 조건 동기.

사용법: python plugins/pjc/evals/check-harness-consistency.py   (인자 없음 — repo 루트를 스스로 찾는다)

무엇을: 이 repo는 마크다운이 곧 실행 규칙이라, 문서가 서로 어긋나면 그것이 곧 동작 결함이다.
아래 축들은 사람이 손으로 맞춰 온 지점들이며 실제로 어긋난 전례가 있다(축 수를 여기 적지 않는
이유는 그 숫자가 축을 늘릴 때마다 낡기 때문이다 — 실행 배너는 축 라벨에서 파생한다):

  ① 문서 로드 예산  — 스킬·리뷰어 파일의 바이트가 `docs/harness-conventions.md` 「문서 로드 예산
     기준선」 표와 일치하는가. 그 표는 조건부 절차를 references로 밀어낸 절감이 유지되는지를
     수치로 고정한다. 파일을 고친 task가 표를 갱신하지 않으면 여기서 잡힌다.
  ② 리뷰어 각주 앵커 — 리뷰어 4종이 복제 보유하는 규약 블록에 동기 신호(각주)가 전부 있는가.
     subagent는 자기 파일만 로드해 단일 소스화가 불가하므로 각주가 유일한 드리프트 신호다.
     **본문 동일성은 검사하지 않는다** — 네 파일의 같은 블록은 역할 차이로 실제로 다르다.
  ②-b 실행 예산 수치 — 리뷰어의 frontmatter `maxTurns`와 「실행 예산」 절 본문의 예산·중단선·계측
     수치가 일치하는가. 그 수치는 상한에서 파생되는데 사람이 손으로 옮겨 적으므로, 상한만 바꾸고
     본문을 빠뜨리면 ②(개수만 셈)는 통과한다. 기대값은 코드가 아니라 frontmatter에서 파생한다.
  ③ 포인터 도달성   — `<경로>` … 「<절 이름>」 형태의 크로스파일 포인터가 실제 헤딩에 닿는가.
     조건부 절차를 references로 이관하면 이 포인터가 유일한 연결이라, 끊기면 규칙이 사라진다.
  ④ 마커 목록 동기  — 정당 정지 마커의 전수 목록(정본)과 `implement-task/SKILL.md`의 대표 예시가
     어긋나지 않는가. v1.154.0 이전에 정본 6곳 ↔ 사본 8곳으로 역전돼 있었고, 그 차이가 곧
     오차단 경로였다.
  ⑫ 개념 정본      — 한 개념의 정의성 서술이 정본 1곳 밖에 흩어져 있지 않은가. 흩어지면 한쪽을 고칠 때
     나머지가 조용히 낡는다(실측: `동기 호출`이 7파일 22회, `incomplete`가 11파일 22회). 개념·앵커·스코프·
     어휘·면제는 전부 `docs/harness-conventions.md` 「개념 정본 유일성」 표에서 온다. 상세 리포트는
     `--concept-report`(정본/화이트리스트/위반/차집합/면제 잔여 5구획).
  ⑤ Deferred 집계   — 대장의 「현행 잔량」 앵커가 실제 항목 수와 일치하는가. "정리 직후 수치만
     적고 등재분을 반영하지 않는" 실수가 이 대장의 반복 패턴이다. 앵커는 4필드이며 누계 2종은
     실측 불가(삭제분은 파일에 없다)라 **불변식** `대기 + 종결 + 삭제누계 == 총등재누계`로 검사한다
     — 종전에 사람이 batch 전후로 대조하던 「무손실 대조」를 기계화한 것이다.
  ⑥ 볼드 마커 짝    — 문단 누적 `**` 개수가 홀수면 볼드 구간이 어긋난 것이다(렌더가 깨진다).
  ⑦ 한 줄 문장 중복 — 한 줄 안에 같은 문장이 2회 이상 나오면 삽입 사고다. 정본이 둘이 된다.
     ⑥⑦은 앞의 축들과 성격이 다르다 — **문서 기록값 ↔ 실측**이 아니라 **레포 md 전수의 표기
     결함**을 본다. 판정 단위·제외 정책·못 잡는 것은 각 함수의 주석과
     `docs/harness-conventions.md` 「문서 표기 축」이 정본이다.
  ⑬ 착수 조건 동기  — Deferred 소진 batch 「착수 조건」을 **의도적으로 복제 보유**하는 두 파일
     (`phase-f-detail.md` ⓪ 정본 ↔ `plan-feature/SKILL.md` Step 1 ③)이 갈리지 않았는가.
     수치 4종과 **판정일 도출 문장**을 대조한다 — 후자를 함께 보는 이유는 v1.188.0이 고친
     결함이 수치가 아니라 그 문장에 있었기 때문이다(부기 형식 미인식). 수치만 대조하면
     그 문장이 한쪽에서만 지워져도 통과한다. **못 잡는 것**: 두 파일이 같은 방향으로
     함께 틀리는 경우(정본이 곧 기준이라 서로 일치하면 통과한다).

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

CONV_MD = os.path.join(ROOT, "docs", "harness-conventions.md")
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
    """예산 표의 파일들이 표 기록값과 일치하는가. `AGENTS.md`만 상한 대비도 함께 잰다.

    표 대조(기록값 == 실측)와 상한 대조(실측 <= 상한)는 **다른 축**이다 — 전자는
    "표가 낡았나"를, 후자는 "그 파일이 SessionStart 주입 상한을 넘겼나"를 본다.
    AGENTS.md가 상한을 넘으면 전문 주입이 **목차 폴백**으로 바뀌어 모든 세션이 보는
    내용이 통째로 달라지는데, 그것을 알려주는 장치가 없었다(대장 [2026-08-19]).

    **상한 값은 코드에 박지 않고 hook에서 파싱한다** — 정본이 `session-context.ps1`의
    `$agentsMaxBytes`이므로, 그쪽을 고치면 이 검사도 함께 따라가야 갈리지 않는다.
    """
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
        if path == "AGENTS.md":
            # 상한의 정본은 hook이므로 코드에 박지 않고 거기서 읽는다. 대상이 이 한 행뿐이라
            # 헬퍼로 빼지 않고 지역 처리한다(공통화 문턱 미달 — 이 파일의 명시적·직접적 코드 원칙).
            hook = os.path.join(ROOT, "plugins", "pjc", "scripts", "session-context.ps1")
            m = re.search(r"\$agentsMaxBytes\s*=\s*(\d+)", read(hook))
            if not m:
                die("주입 상한: `session-context.ps1`에서 $agentsMaxBytes 정의를 찾지 못함")
            limit = int(m.group(1))
            if real[0] > limit:
                issues.append("주입 상한 초과 %s — 실측 %d B / 상한 %d B (초과 %d B) "
                              "— SessionStart가 전문 대신 목차 폴백을 주입한다"
                              % (path, real[0], limit, real[0] - limit))
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
    # 리뷰어 이름도 문서에서 읽는다 — 코드에 목록을 박으면 5번째 리뷰어가 생겨도
    # 조용히 4종만 검사한다(acceptance ③의 하드코딩 금지가 겨냥하는 바로 그 실패).
    # 절 첫 문단의 `(...)` 안 백틱 목록이 그 정의다.
    nm = re.search(r"리뷰어 (\d+)종\(([^)]+)\)", sec)
    if not nm:
        die("「리뷰어 4종 공통 규약」에서 리뷰어 이름 목록(첫 문단 괄호)을 추출하지 못함")
    declared = int(nm.group(1))
    files = sorted(set(re.findall(r"`([a-z][a-z-]+-reviewer)`", nm.group(2))))
    if not files:
        die("리뷰어 이름 목록에서 이름을 하나도 추출하지 못함 (표기가 바뀌었는지 확인)")
    # 선언한 "N종"과 실제 나열된 이름 수가 어긋나면 문서 자신이 모순이다 — 하드코딩을
    # 걷어내며 이 자기정합 검사까지 함께 잃지 않도록 남긴다(개수는 문서가 정한다).
    if len(files) != declared:
        die("리뷰어 이름 수 불일치 — 선언 %d종 / 나열 %d개(%s)" % (declared, len(files), files))
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
# ②-b 리뷰어 실행 예산 수치 (frontmatter ↔ 본문)
# ─────────────────────────────────────────────────────────────
def check_reviewer_budget():
    """리뷰어 정의의 frontmatter `maxTurns` ↔ 「실행 예산」 절 본문 수치를 대조한다.

    예산 고지(maxTurns − 4)와 중단선(그 2/3)은 상한에서 파생되는데 **사람이 손으로 옮겨
    적는다** — 상한만 바꾸고 본문을 빠뜨려도 각주 축(앵커 개수만 셈)은 통과하므로,
    「고지된 예산과 실제 상한이 갈리는」 드리프트를 잡을 축이 따로 필요하다.
    대상은 「실행 예산」 절을 가진 `agents/*.md` 전부다(이름을 코드에 박지 않는다 —
    5번째 리뷰어가 생기면 자동으로 검사 대상이 된다).
    """
    agents = os.path.join(ROOT, "plugins", "pjc", "agents")
    issues, checked = [], 0
    for name in sorted(os.listdir(agents)):
        if not name.endswith(".md"):
            continue
        txt = read(os.path.join(agents, name))
        if "## 실행 예산" not in txt:
            continue
        mt = re.search(r"^maxTurns: (\d+)$", txt, re.M)
        if not mt:
            issues.append("실행 예산 %s — 「실행 예산」 절은 있는데 frontmatter에 maxTurns가 없다" % name)
            continue
        limit = int(mt.group(1))
        want_budget = limit - 4
        want_stop = (want_budget * 2) // 3
        # 본문 3자리를 각각 뽑아 파생값과 대조한다. 한 자리라도 못 찾으면 절의 문면이
        # 바뀐 것이므로 통과시키지 않는다(ANCHOR FAIL이 아니라 issue — 파일별로 다를 수 있다).
        for label, rx, want in (
            ("예산 고지", r"도구 호출 예산은 (\d+)회다\*\*\(`maxTurns: (\d+)`", (want_budget, limit)),
            ("중단선", r"\*\*도구 호출 (\d+)회에 도달하면", (want_stop,)),
            ("계측 표기", r"`도구 호출 <실제>회 / 예산 (\d+)회`", (want_budget,)),
        ):
            m = re.search(rx, txt)
            if not m:
                issues.append("실행 예산 %s — %s 문면을 찾지 못함(절 표기가 바뀌었는지 확인)" % (name, label))
                continue
            got = tuple(int(g) for g in m.groups())
            if got != want:
                issues.append("실행 예산 %s %s — 본문 %s / maxTurns %d에서 파생한 기대값 %s"
                              % (name, label, got, limit, want))
            checked += 1
    if checked == 0:
        die("실행 예산: 「실행 예산」 절을 가진 리뷰어를 하나도 찾지 못함 (절 제목이 바뀌었는지 확인)")
    return issues, checked


def check_batch_trigger_sync():
    """Deferred 소진 batch 「착수 조건」을 복제 보유한 두 파일이 갈리지 않았는지 대조한다.

    `phase-f-detail.md` ⓪(정본)과 `plan-feature/SKILL.md` Step 1 ③(복제)은 착수 조건을
    **의도적으로 복제**한다 — ⓪ 자신이 *"규정을 이 파일에만 두면 판정할 사람이 그것을
    보지 않는다"*를 근거로 든다. 그런데 이 repo가 리뷰어 4종에 쓰는 **각주 + 기계 대조**
    패턴이 이 쌍에는 없었다(대장 `[2026-08-20]` 항목이 등재한 사실).

    대조 대상은 둘이다 —
      ⓐ 착수 조건 **4수치**(잔량 임계 · 신규 등재분 · 날짜 · 절대 상한): 두 파일에서 각각
         뽑아 집합으로 비교한다. 어느 쪽이 값을 바꾸고 다른 쪽을 두면 여기서 잡힌다.
      ⓑ 판정일 도출의 **공통 리터럴 한 문장**: 완전 일치(마크업·공백 포함)로 본다. 그 문장
         **밖의 근거절은 파일별로 다른 것이 정상**이라 대조하지 않는다 — 경계를 문장으로
         고정해야 근거절 차이가 섞여 들어오지 않는다.

    ⓑ를 넣은 이유는 v1.188.0이 고친 결함이 **수치가 아니라 판정 기준 문장**에 있었기
    때문이다(부기 형식 미인식). 수치만 대조하면 그 문장이 한쪽에서만 지워져도 통과한다.
    """
    # `section()`을 쓰지 않는다 — 그 헬퍼는 `#` 헤딩으로 절을 자르는데, 대조 대상인 ⓪과
    # Step 1 ③은 **리스트 불릿**이라 헤딩 경계가 없다. 파일 전체에서 정규식으로 찾는 편이
    # 정확하고(각 패턴이 파일당 1회만 출현함을 확인했다) 절 제목 변경에도 견딘다.
    canon_p = os.path.join(ROOT, "plugins", "pjc", "skills", "implement-task",
                           "references", "phase-f-detail.md")
    copy_p = os.path.join(ROOT, "plugins", "pjc", "skills", "plan-feature", "SKILL.md")
    canon, copy = read(canon_p), read(copy_p)

    # 판정 기준 문장 — 두 파일에서 같은 정규식으로 떼어 낸다.
    rule_rx = re.compile(r"그 날짜는 \*\*그 항목이 마지막으로 판정된 날\*\*이다 —.*?둘 다 없으면 등록일이다\.")
    # 착수 조건 수치 — 값 앞 주어가 파일마다 다르므로(정본 «`## 대기`가» / 복제
    # «`▶ 현행 잔량` 앵커가») 그 토큰까지 묶지 않고 값만 뽑는다. 묶으면 정당한
    # 문면 차이에 ANCHOR FAIL이 난다.
    num_rxs = (
        ("잔량 임계", r"\*\*(\d+)건을 넘고"),
        ("신규 등재분", r"신규 등재분」이 (\d+)건 이상"),
        ("날짜", r"최솟값이 (\d+)일을 넘거나"),
        ("절대 상한", r"절대 상한\(현행 (\d+)건\)"),
    )

    issues, checked = [], 0
    for label, rx in num_rxs:
        a, b = re.search(rx, canon), re.search(rx, copy)
        if not a or not b:
            # 양쪽 다 결측일 수 있다 — 한쪽만 지목하면 나머지가 함께 바뀐 것을 놓친다.
            missing = ", ".join(n for n, v in (("정본", a), ("복제", b)) if not v)
            die("착수 조건 동기 — %s 문면을 %s에서 찾지 못함(절 표기가 바뀌었는지 확인)"
                % (label, missing))
        if a.group(1) != b.group(1):
            issues.append("착수 조건 동기 %s — 정본 %s / 복제 %s (phase-f-detail ⓪ ↔ plan-feature Step 1 ③)"
                          % (label, a.group(1), b.group(1)))
        checked += 1

    ra, rb = rule_rx.search(canon), rule_rx.search(copy)
    if not ra or not rb:
        missing = ", ".join(n for n, v in (("정본", ra), ("복제", rb)) if not v)
        die("착수 조건 동기 — 판정일 도출 문장을 %s에서 찾지 못함(문면이 바뀌었는지 확인)"
            % missing)
    if ra.group(0) != rb.group(0):
        issues.append("착수 조건 동기 판정일 도출 문장 — 두 파일의 문면이 다르다"
                      "(공통 리터럴은 완전 일치여야 한다 — 근거절은 대조 대상이 아니다)")
    checked += 1
    return issues, checked


# ─────────────────────────────────────────────────────────────
# ⑫ 개념 정본 유일성 (리포트 전용 — main 편입은 T11)
# ─────────────────────────────────────────────────────────────
def _concept_table(conv):
    """「개념 정본 유일성 (축 ⑫ 기준표)」 표의 데이터 행을 파싱한다.

    절 잘라내기는 기존 `section()`을 그대로 쓴다(같은 문서의 같은 형태를 두 번
    구현하지 않는다). 반환은 6필드 dict의 리스트이며, **기대값을 코드에 박지 않는
    다는 이 파일의 원칙대로** 개념·앵커·스코프·어휘·면제가 전부 문서에서 온다.
    """
    sec = section(conv, r"^## 개념 정본 유일성", label="개념 정본 유일성 (축 ⑫ 기준표)")
    rows = []
    for line in sec.split("\n"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.strip().startswith("|") else []
        if len(cells) != 6 or cells[0] in ("개념", "---") or set(cells[0]) <= {"-", ":"}:
            continue
        def unbt(s):
            return [x.strip().strip("`") for x in s.split("`,") if x.strip()] if "`," in s else [s.strip().strip("`")]
        rows.append({
            "name": cells[0],
            "canon": cells[1].strip("`"),
            "anchor": cells[2].strip("`"),
            "scopes": [x.strip("`") for x in cells[3].split() if x.strip("`")],
            "word": cells[4].strip("`"),
            "refs": unbt(cells[5]),
        })
    if not rows:
        die("「개념 정본 유일성」 표에서 데이터 행을 추출하지 못함")
    return rows


def _anchor_block(txt, anchor_rx):
    """정본 앵커가 여는 구간의 줄 번호 집합과 앵커 매치 수를 돌려준다.

    매치 수를 함께 세는 이유는 축 ⑪의 1R MAJOR가 "앵커가 문서 전체에서 몇 건
    매치되는지 세지 않으면 첫 매치를 그냥 쓴다"였기 때문이다.

    **구간의 끝은 앵커 유형마다 다르다** — 기준표에 실재하는 세 유형을 모두 다룬다.
    이분법(헤딩/그 외)으로 두면 불릿 앵커가 번호-규칙 분기로 흘러, 같은 레벨의 다음
    불릿에서 멈추지 못하고 다음 헤딩까지 수십 줄을 통째로 정본으로 삼킨다 — 그러면
    그 구간 안의 재서술이 위반이 아니라 "정본"으로 조용히 흡수돼, 이 축이 잡아야 할
    드리프트를 놓친다(T3 quality M1 실측: `등재 게이트` 앵커가 38줄·무관 불릿 7개를 삼켰다).
    """
    lines = txt.split("\n")
    hits = [i for i, l in enumerate(lines) if re.search(anchor_rx, l)]
    if len(hits) != 1:
        return set(), len(hits)
    start = hits[0]
    head = lines[start]
    if head.startswith("#"):                       # ① 헤딩 — 다음 동급 이상 헤딩까지
        depth = len(head) - len(head.lstrip("#"))
        stop = lambda l: l.startswith("#") and (len(l) - len(l.lstrip("#"))) <= depth
    elif re.match(r"^\s*[-*] ", head):              # ② 불릿 — 같은 들여쓰기의 다음 불릿 또는 상위 헤딩까지
        indent = len(head) - len(head.lstrip())
        stop = lambda l: (l.startswith("#")
                          or (re.match(r"^\s*[-*] ", l) and (len(l) - len(l.lstrip())) <= indent))
    else:                                          # ③ 번호 규칙(`4-1. **…`) — 다음 최상위 번호 또는 헤딩까지
        stop = lambda l: bool(re.match(r"^(#{1,6} |\d+(-\d+)?\. \*\*)", l))
    end = next((i for i in range(start + 1, len(lines)) if stop(lines[i])), len(lines))
    return set(range(start, end)), 1


def _scope_lines(scopes, word):
    """스코프 디렉터리들을 걸어 `word`가 든 줄을 (rel, 0기반 줄번호, 원문)으로 낸다.

    분류 로직과 파일 순회를 한 함수에 두면 중첩이 6단계까지 내려가 읽기 부담이 커진다
    (축 ⑪의 `_scan_lines`도 파일 순회를 따로 두지만 그 분리 사유는 **스코프 한정**이다 — md/json/py마다 「규정을 서술하는 줄」의 정의가 달라서다. 여기서 그 함수를 재사용하지 않는 것은
    Design ④의 비추상화 선언대로 스코프·앵커 형태가 달라서다).
    """
    for scope in scopes:
        base = os.path.join(ROOT, scope.replace("/", os.sep))
        for b, _, names in os.walk(base):
            for nm in sorted(names):
                if not nm.endswith(".md"):
                    continue
                f = os.path.join(b, nm)
                rel = os.path.relpath(f, ROOT).replace(os.sep, "/")
                for i, line in enumerate(read(f).split("\n")):
                    if word in line:
                        yield rel, i, line


def check_concept_locality(conv, report=False):
    """개념마다 정본 1곳을 선언하고 그 밖의 언급을 넷으로 가른다.

    네 구획은 축 ⑪의 이름을 그대로 쓴다 — **정본**(앵커 구간 안) / **화이트리스트**(정본
    식별자를 동반한 포인터 = 면제) / **위반**(정본 밖 + 식별자 없음 = 정본화 검토 대상) /
    **차집합**(위 셋 어디에도 들지 않는 줄 — 이 구현은 세 분류가 전수를 덮으므로 구조적으로
    0이며, 분류 로직이 바뀌어 구멍이 생기면 여기서 드러난다) / **면제 잔여**(화이트리스트 줄인데
    개념어가 식별자 수보다 많이 나오는 자리 — 한 줄에 포인터와 독자 서술이 섞이면 후자가 면제
    뒤에 숨는다. 축 ⑪ T3 1R BLOCKER ⓑ가 잡은 형태).

    **위반은 결함 단정이 아니라 판정 대기**다 — 정당한 인용·요약도 걸린다. 처분(정본 흡수 ·
    포인터화 · 면제 등재)은 T4·T5가 한다.
    """
    issues, checked = [], 0
    out = []
    for row in _concept_table(conv):
        canon_path = os.path.join(ROOT, row["canon"].replace("/", os.sep))
        if not os.path.exists(canon_path):
            issues.append("개념 정본 %s — 정본 파일 없음 %s" % (row["name"], row["canon"]))
            continue
        canon_txt = read(canon_path)
        block, n_anchor = _anchor_block(canon_txt, row["anchor"])
        checked += 1
        if n_anchor != 1:
            issues.append("개념 정본 %s — 앵커가 %d건 매치(정확히 1건이어야 한다): %s"
                          % (row["name"], n_anchor, row["anchor"]))
            continue
        canon_rel = row["canon"]
        buckets = {"정본": [], "화이트리스트": [], "위반": [], "차집합": [], "면제 잔여": []}
        for rel, i, line in _scope_lines(row["scopes"], row["word"]):
            entry = (rel, i + 1, line.strip())
            if rel == canon_rel and i in block:
                buckets["정본"].append(entry)
                continue
            hit_ref = [r for r in row["refs"] if r in line]
            if not hit_ref:
                buckets["위반"].append(entry)
                continue
            buckets["화이트리스트"].append(entry)
            # 면제 잔여: 한 줄에 포인터와 **독자 서술**이 섞인 자리. 개념어가 식별자 수보다
            # 많이 나오면 그중 일부는 포인터가 아니다(축 ⑪ T3 1R BLOCKER ⓑ — 정당한 면제
            # 뒤에 진짜 위반이 숨던 형태).
            if line.count(row["word"]) > len(hit_ref):
                buckets["면제 잔여"].append(entry)
        out.append((row["name"], buckets))
    if checked == 0:
        die("개념 정본 유일성: 검사 대상 개념을 하나도 찾지 못함")
    if report:
        for name, b in out:
            print("\n== 개념 「%s」 ==" % name)
            for k in ("정본", "화이트리스트", "위반", "차집합", "면제 잔여"):
                print("  [%s] %d건" % (k, len(b[k])))
                for rel, ln, s in b[k]:
                    print("    %s:%d  %s" % (rel, ln, s[:110]))
    return issues, checked


# ─────────────────────────────────────────────────────────────
# ③ 포인터 도달성
# ─────────────────────────────────────────────────────────────
def _md_files():
    # `evals/fixtures/`는 **검사 대상이 아니다** — 골든 픽스처는 검사기가 잡아야 할
    #  위반을 **의도적으로** 담고 있어(깨진 포인터·누락 절 등), 여기서 세면 그 의도가
    #  곧 실패로 보고된다. lint.py가 `90_archive/`를 제외하는 것과 같은 계열이다.
    skip = {".git", "node_modules", "__pycache__", "notes-archive", "fixtures"}
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
    # `경로.md` **바로 뒤**에 「절 이름」이 오는 형태만 포인터로 본다.
    # 창을 넓게 잡으면(초기 구현 40자) 경로가 나열된 문장과 그 뒤의 무관한 「…」이 묶여
    # 오탐이 난다 — 실제로 "소비자는 `a.md`·`b.md` 둘이 더 있었다. 남은 것은 「X」 규약"이
    # 한 포인터로 잡혔다. 정당한 포인터는 경로 직후 조사·공백 몇 자 안에 「」가 온다.
    #
    # ⚠ 배제 문자를 늘리지 말 것. 한때 `·`와 `*`를 배제했더니 이 문서군에서 흔한
    # `` `경로`의 **「앵커」** `` 볼드-랩 스타일이 **매치 자체에서 빠져 무음 누락**됐다
    # (정당한 포인터 2건이 `[NOTE]`에도 안 잡히고 사라졌다 — 검사 축소가 침묵으로 나타난 사례).
    # 12자 창만으로 위 오탐은 이미 걸러진다(그 문장은 경로에서 「」까지 12자를 훨씬 넘는다).
    pat = re.compile(r"`([A-Za-z0-9_./-]+\.md)`(?:[^「\n]{0,12})「([^」\n]{2,60})」")
    heading_cache = {}
    issues, checked, skipped = [], 0, []

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

    # 부분 경로(`implement-task/SKILL.md`처럼 repo 루트 기준이 아닌 표기)를 해석하기 위한 색인.
    # 이 repo의 문서는 같은 파일을 전체 경로·부분 경로 두 방식으로 가리키며, 부분 표기를
    # 해석하지 않으면 그 참조가 통째로 검사에서 빠진다(초기 구현에서 8건이 그렇게 빠졌다).
    by_suffix = {}
    for f in _md_files():
        rel = os.path.relpath(f, ROOT).replace(os.sep, "/")
        parts = rel.split("/")
        for i in range(len(parts)):
            by_suffix.setdefault("/".join(parts[i:]), []).append(f)

    for src in _md_files():
        rel_src = os.path.relpath(src, ROOT).replace(os.sep, "/")
        # 과거 plan·로컬 노트는 그 시점의 기록이라 갱신 대상이 아니다(대장 관례).
        # 판정을 `_ARCHIVED_PLAN_RX`·`_LOCAL_ONLY`와 공유한다 — 종전에는 여기만 `docs/plans/2026-`로
        # 연도를 박아 두어 해가 바뀌면 이 축만 조용히 아카이브를 검사하기 시작했다.
        if _ARCHIVED_PLAN_RX.match(rel_src) or rel_src in _LOCAL_ONLY:
            continue
        text = open(src, encoding="utf-8").read()
        for ref_path, sec_name in pat.findall(text):
            cand = [os.path.join(ROOT, ref_path.replace("/", os.sep)),
                    os.path.join(os.path.dirname(src), ref_path.replace("/", os.sep))]
            target = next((c for c in cand if os.path.exists(c)), None)
            if target is None:
                # 부분 경로 표기(`implement-task/references/recovery.md`처럼 `plugins/pjc/skills/`
                # 접두가 빠진 형제-스킬 참조)를 접미 색인으로 해석한다. 후보가 여럿이면
                # 어느 것을 뜻하는지 확정할 수 없으므로 해석하지 않는다(추측 금지).
                hits = by_suffix.get(ref_path, [])
                if len(hits) == 1:
                    target = hits[0]
            if target is None:
                # 경로 표기가 다양해(상대·부분 경로) 해석 실패를 곧바로 결함으로 보면 오탐이 크다.
                # 다만 **조용히 넘기지는 않는다** — 파일이 실제로 삭제·이동된 경우가 가장 심한
                # 포인터 끊김인데 그것까지 침묵하면 이 축의 존재 이유가 사라진다. 건수를 노출해
                # 사람이 검토할 신호를 남긴다.
                skipped.append("%s → `%s`" % (rel_src, ref_path))
                continue
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
    if skipped:
        print("[NOTE] 포인터 %d건은 대상 파일 경로를 해석하지 못해 검사에서 제외됨 — %s"
              % (len(skipped), " / ".join(skipped[:5]) + (" …" if len(skipped) > 5 else "")))
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
    # 줄 끝(`$`)까지 앵커링한다 — 접두 매치로 두면 필드가 빠지거나 늘어도 조용히 통과해
    # 대장↔대조기 lockstep이 성립하지 않는다(4필드 도입 시 실측으로 드러났다).
    m = re.search(
        r"현행 잔량\(기계 대조 대상\)\*\*: 대기 (\d+) / 종결 (\d+)"
        r" / 정리 삭제 누계 (\d+) / 총 등재 누계 (\d+)\s*$",
        ledger, re.M)
    if not m:
        die("대장에서 「현행 잔량」 전용 앵커를 찾지 못함(4필드 형식이 아닐 수 있다)")
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
    a_wait, a_done, purged, enrolled = (int(g) for g in m.groups())
    issues = []
    if (wait, done) != (a_wait, a_done):
        issues.append("Deferred 집계 — 앵커 대기 %d/종결 %d / 실측 대기 %d/종결 %d"
                      % (a_wait, a_done, wait, done))
    # 누계 2종은 실측 대조가 불가능하므로(삭제된 항목은 파일에 없다) 불변식으로만 구속한다.
    # 어긋나면 누계를 서로 맞춰 green을 만들지 말고 원인 연산을 고칠 것 — 대장 「카운트 기준」.
    if a_wait + a_done + purged != enrolled:
        issues.append("Deferred 불변식 — 대기 %d + 종결 %d + 삭제누계 %d = %d ≠ 총등재누계 %d"
                      % (a_wait, a_done, purged, a_wait + a_done + purged, enrolled))
    return issues, wait + done


# ─────────────────────────────────────────────────────────────
# ⑧ 볼드 마커 짝 · ⑨ 한 줄 안 문장 중복 (문서 표기 결함)
#
# 두 축이 공유하는 것: 스캔 제외 정책과 「펜스·코드 스팬을 걷어낸 문단」 분리.
# 왜 필요한가 — 어느 검증 명령도 이 둘을 잡지 못했다. 볼드가 어긋나면 렌더가 깨지고,
#  같은 문장이 한 줄 안에 반복 삽입되면 **정본이 둘이 된다**(v1.180.0 F-7 M1이 실제로
#  잡은 형태 — 사람 눈은 두 번 통과했다. 줄 수로 세면 같은 줄 안의 반복이 보이지 않는다).
# ─────────────────────────────────────────────────────────────
# 제외 정책 — ⓐ 픽스처는 **의도적으로 깨뜨린** 파일이라 검사 대상이 되면 축이 상시 실패한다
#  ⓑ `docs/plans/YYYY-MM-DD-*.md`는 과거 회차의 이력 자산이고 그 시점의 사실이라 고치지 않는다
#  (`deferred.md`는 살아 있는 자산이라 **제외하지 않는다** — 가장 활발히 편집되는 문서다)
#  ⓒ `plan.md`·`notes.md`는 gitignore 로컬 전용이라 회차마다 통째로 교체된다.
_ARCHIVED_PLAN_RX = re.compile(r"^docs/plans/\d{4}-\d{2}-\d{2}-")
_LOCAL_ONLY = {"plan.md", "notes.md"}
_INLINE_CODE_RX = re.compile(r"`[^`\n]*`")


def _scan_scope():
    """문서 표기 축의 대상을 `(경로, 레포 상대경로)`로 낸다 (위 제외 정책 적용)."""
    for path in _md_files():
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if "/fixtures/" in rel or _ARCHIVED_PLAN_RX.match(rel) or rel in _LOCAL_ONLY:
            continue
        yield path, rel


def _blocks(text):
    """펜스를 걷어내고 빈 줄로 끊은 **문단** 리스트. 각 원소는 `[(줄번호, 판정용 줄, 원문)]`.

    판정용 줄은 **인라인 코드 스팬을 지운 것**이다 — 두 축 모두 코드 스팬 안의 문자를
    세면 안 된다(볼드 축은 `` `**` `` 같은 리터럴 설명을 위반으로 잡고, 중복 축은 경로의
    `.`을 문장 끝으로 오인한다. 둘 다 실측된 오탐이다).
    문단 단위로 끊는 이유는 볼드 축에 있다 — 여러 줄에 걸친 정당한 볼드가 줄 단위 판정에서는
    전부 오탐이 된다(실측: 줄 15건 → 문단 8건, 걸러진 10건이 전부 정당한 여러 줄 볼드).
    펜스 판정은 `skills/llm-wiki/scripts/lint.py`의 상태 머신과 같은 방식이다."""
    out, cur, fence = [], [], False
    for i, ln in enumerate(text.split("\n"), 1):
        if ln.lstrip().startswith("```"):
            fence = not fence
            if cur:
                out.append(cur)
                cur = []
            continue
        if fence:
            continue
        if not ln.strip():
            if cur:
                out.append(cur)
                cur = []
            continue
        cur.append((i, _INLINE_CODE_RX.sub("", ln), ln))
    if cur:
        out.append(cur)
    return out


def check_bold_pairing():
    """⑧ 문단 누적 `**` 개수가 홀수면 볼드 구간이 어긋난 것이다 (렌더가 깨진다)."""
    issues, checked = [], 0
    for path, rel in _scan_scope():
        for block in _blocks(read(path)):
            checked += 1
            if sum(judged.count("**") for _, judged, _ in block) % 2:
                # 라인 번호로 지목하지 않는다 — 편집 한 번에 낡는다(이 repo가 세 번 겪었다).
                head = block[0][2].strip()[:60]
                issues.append("볼드 마커 홀수 — %s 문단 시작 %r" % (rel, head))
    return issues, checked


# 문장 분리 — **종결부 뒤에서 자른다**. `[^.!?]{20,}?…` 형태로 뽑으면 최소 길이 요구가
#  앞 문장을 삼켜 *"A. A."* 같은 실제 삽입 사고에서 두 조각이 서로 달라져 **미검출**된다
#  (v1.180.0 F-7 M1이 잡은 바로 그 형태를 초안이 놓쳤다 — 재현으로 확인).
_SENT_SPLIT_RX = re.compile(r"(?<=[.!?])")
# 최소 길이 — 짧은 토막을 세면 표·열거의 정상 반복이 전부 걸린다. 값의 근거는 실측이다:
#  임계 0이면 레포 전수에서 **124건**이 걸리는데 임계 10 이상이면 **0건**이다(2026-08-19 실측).
#  즉 오탐은 전부 아주 짧은 조각(표 셀·번호 항목)이고, 실제 삽입 사고는 문장 길이다.
#  10~25 어디를 잡아도 현행 검출은 같아 여유를 두고 20으로 뒀다.
_SENT_MIN_LEN = 20


def _sentences(line):
    """한 줄을 문장 단위로 자른다(종결부 기준). 최소 길이 미만 조각은 버린다."""
    return [s for s in (p.strip() for p in _SENT_SPLIT_RX.split(line))
            if len(s) >= _SENT_MIN_LEN and s[-1] in ".!?"]


def check_line_dup():
    """⑨ 한 줄 안에 같은 문장이 2회 이상 나오면 삽입 사고다.

    **문서 내 3회 이상** 축은 채택하지 않았다 — 실측에서 오탐 10건이 나왔고 그중 8건이
    리뷰어 4종의 **의도된 공통 규약 블록**이었다. 그것을 예외로 빼면 축이 잡아야 할
    「같은 문장이 여러 곳에 있음」과 형태가 같아져 예외가 곧 축의 무력화가 된다.

    **무엇을 못 잡는가 (검출 범위의 대가)**: ⓐ **다른 줄에 걸친 반복** — 줄 단위 판정이라
    한 문장이 여러 줄로 접혀 반복되면 안 잡힌다 ⓑ **문장이 아닌 반복**(제목·표 셀·짧은 구)
    — `_SENT_MIN_LEN`과 종결부 요구 밖이다 ⓒ **문면이 조금 다른 반복** — 완전 일치만 센다.
    ⓐ~ⓒ를 잡으려면 유사도 판정이 필요한데 그 대가가 오탐이고, 이 축이 겨냥한 실제 사고는
    **한 줄 안 완전 복제**였다(v1.180.0 F-7 M1).
    """
    issues, checked = [], 0
    for path, rel in _scan_scope():
        for block in _blocks(read(path)):
            for no, judged, _raw in block:
                checked += 1
                seen = {}
                for s in _sentences(judged):
                    seen[s] = seen.get(s, 0) + 1
                for s, n in seen.items():
                    if n >= 2:
                        issues.append("한 줄 안 문장 %d회 반복 — %s:%d %r" % (n, rel, no, s[:50]))
    return issues, checked


def main():

    # Windows 기본 콘솔은 cp949라 출력의 `—`(em dash)·한글 기호가 UnicodeEncodeError를 낸다.
    # 검증 매핑에 등록된 명령은 `python <이 파일>`이라 환경변수가 붙지 않으므로, 스스로 UTF-8로
    # 재설정하지 않으면 **매 실행이 크래시해 검사 자체가 성립하지 않는다**(개발 중 `PYTHONUTF8=1`을
    # 붙여 돌리면 이 결함이 보이지 않는다 — 실제로 그렇게 놓쳤다).
    # 자매 스크립트 `skills/llm-wiki/evals/check_consistency.py`가 쓰는 것과 같은 패턴이다.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass  # 재설정 불가 환경(파이프 등)에서는 그대로 진행

    # 축 ⑫는 v1.179.0 T11에서 `main()`에 편입됐다(그전까지는 리포트 전용 — 소진이 끝나기 전에
    # 편입하면 그 사이 모든 task의 검증이 FAIL하기 때문. 축 ⑪의 전례를 그대로 따랐다).
    # `--concept-report`는 승격 후에도 상세 목록을 보기 위해 남긴다.
    if "--concept-report" in sys.argv:
        conv = read(CONV_MD)
        issues, n = check_concept_locality(conv, report=True)
        print("\n== 개념 %d개 검사 ==" % n)
        for m in issues:
            print("[MISMATCH] %s" % m)
        sys.exit(1 if issues else 0)

    conv = read(CONV_MD)
    ledger = read(LEDGER_MD)
    impl = read(IMPL_MD)

    # 라벨 목록을 한 곳에 두고 **배너와 결과 문구가 둘 다 여기서 파생**되게 한다 —
    #  종전에는 배너가 별도 리터럴이라 축을 늘려도 그대로 남았다(이 회차가 실제로 겪었다).
    axes = [
        ("예산 기준선", check_doc_budget(conv)),
        ("리뷰어 각주", check_reviewer_footnote(conv)),
        ("실행 예산 수치", check_reviewer_budget()),
        ("포인터 도달성", check_pointer_reachability()),
        ("마커 동기", check_marker_sync(conv, impl)),
        ("개념 정본", check_concept_locality(conv)),
        ("Deferred 집계", check_deferred_stats(ledger)),
        ("볼드 마커 짝", check_bold_pairing()),
        ("한 줄 문장 중복", check_line_dup()),
        # 맨 뒤에 둔다 — `harness-conventions.md` 「문서 표기 축」이 볼드/중복 축을
        # **서수**("여덟째·아홉째")로 가리키므로, 중간에 끼우면 그 서술이 어긋난다.
        ("착수 조건 동기", check_batch_trigger_sync()),
    ]
    all_issues, parts = [], []
    for label, (issues, n) in axes:
        all_issues.extend(issues)
        parts.append("%s %d항목" % (label, n))

    print("== 하니스 정합 셀프체크 (%s) ==" % " · ".join(label for label, _ in axes))
    if all_issues:
        for m in all_issues:
            print("[MISMATCH] %s" % m)
        print("\n결과: 불일치 %d건 — 해당 파일을 고친 task가 기준선·앵커를 함께 갱신해야 합니다"
              "(`docs/harness-conventions.md` 「문서 로드 예산 기준선」 서문 참조)." % len(all_issues))
        sys.exit(1)
    print("결과: 대조 전부 일치 (%s)" % " + ".join(parts))
    sys.exit(0)


if __name__ == "__main__":
    main()
