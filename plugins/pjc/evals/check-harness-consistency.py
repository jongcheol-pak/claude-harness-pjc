#!/usr/bin/env python3
r"""하니스 전역 정합 셀프체크 — 포인터 도달성 · Deferred 집계 · 볼드 마커 짝 · 한 줄 문장 중복 · batch 차수 수열 · 추출 앵커 도달성 · 문서 예산 · 줄바꿈 정합.

사용법: python plugins/pjc/evals/check-harness-consistency.py   (인자 없음 — repo 루트를 스스로 찾는다)

무엇을: 이 repo는 마크다운이 곧 실행 규칙이라, 문서가 서로 어긋나면 그것이 곧 동작 결함이다.
아래 축들은 사람이 손으로 맞춰 온 지점들이며 실제로 어긋난 전례가 있다.

  ① 포인터 도달성   — `<경로>` … 「<절 이름>」 형태의 크로스파일 포인터가 실제 헤딩에 닿는가.
     조건부 절차를 references로 이관하면 이 포인터가 유일한 연결이라, 끊기면 규칙이 사라진다.
     대장 2종(`deferred.md`·`deferred-closed.md`)은 관측 시점의 기록이라 면제한다.
  ② Deferred 집계   — 대장의 「현행 잔량」 앵커가 실제 항목 수와 일치하는가. "정리 직후 수치만
     적고 등재분을 반영하지 않는" 실수가 이 대장의 반복 패턴이다. 앵커는 4필드이며 누계 2종은
     실측 불가(삭제분은 파일에 없다)라 **불변식** `대기 + 종결 + 삭제누계 == 총등재누계`로 검사한다.
  ③ 볼드 마커 짝    — 문단 누적 `**` 개수가 홀수면 볼드 구간이 어긋난 것이다(렌더가 깨진다).
  ④ 한 줄 문장 중복 — 한 줄 안에 같은 문장이 2회 이상 나오면 삽입 사고다. 정본이 둘이 된다.
     ③④는 앞의 축들과 성격이 다르다 — **문서 기록값 ↔ 실측**이 아니라 **레포 md 전수의 표기
     결함**을 본다. 판정 단위·제외 정책·못 잡는 것은 각 함수의 주석이 정본이다.
  ⑤ batch 차수 수열 — 소진 batch 회고의 차수가 빠짐없이 이어지는가. 건너뛴 차수는 그 회차의
     기록이 유실됐다는 뜻이다.
  ⑥ 추출 앵커 도달성 — `session-context.ps1`이 압축 직후 잘라 오는 절의 헤딩이 대상 문서에
     실재하고 크기 상한 안인가. 헤딩이 바뀌면 hook은 조용히 폴백해 주입이 사라지고, 그 상실은
     압축된 세션에서만 드러나 아무도 모른 채 지나간다.
  ⑦ 문서 예산      — `DESIGN.md` 4절 표의 상한을 실측 파일 크기와 대조한다. v1.226.0 착수 시점에
     스킬 5종 중 4종이 12,000 B 상한을 최대 2.02배 초과한 채였는데, 크기를 재는 축이 하나도
     없어 조용히 통과했다. 예산이 문서에만 있고 기계는 보지 않는 상태였다.
  ⑧ 줄바꿈 정합    — 워킹트리 tracked 파일이 CRLF 규약을 지키는가(혼재 · bare CR · 전면 LF).
     `core.autocrlf=true` 아래에서 워킹트리가 LF 로 바뀌면 blob 이 정규화돼 **`git diff` 가 비고**,
     그래서 리뷰로도 사람 눈으로도 잡히지 않는다 — v1.176.0 부터 다섯 번 재발했고 매번 `git add`
     경고나 우연한 관측으로만 드러났다.

**축을 지운 이력 (v1.224.0)**: 구 `plan-feature`·`implement-task`와 그 references, 리뷰어 6종이
제거되면서 그것을 대상으로 하던 아홉 축(문서 로드 예산 · 리뷰어 각주 · 실행 예산 수치 ·
마커 목록 · 개념 정본 · 착수 조건 동기 · 잔류 절 동기 · 복제 리터럴 동기 · 파생 수치 동기)이
잴 대상을 잃었다. 그 축들은 **같은 사실이 여러 문서에 복제된 구조**를 감시하던 것이고,
새 구조는 `skills/DESIGN.md` 2절로 복제 자체를 금지해 감시할 대상이 없다.
"""
import glob
import os
import re
import subprocess
import sys

# repo 루트 = 이 파일의 3단계 상위 (plugins/pjc/evals/ → repo)
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

CONV_MD = os.path.join(ROOT, "docs", "harness-conventions.md")
LEDGER_MD = os.path.join(ROOT, "docs", "plans", "deferred.md")
# 대장은 v1.198.0에서 셋으로 갈렸다 — 대기(위)·종결·batch 회고.
#   조회 대상은 `## 대기`뿐인데도 종결 140건과 회차 서사가 함께 컨텍스트에 실렸다.
#   ⚠ 두 파일을 여기서 함께 읽지 않으면 계수 축과 차수 축이 **0항목으로 조용히 통과**한다.
LEDGER_CLOSED_MD = os.path.join(ROOT, "docs", "plans", "deferred-closed.md")
LEDGER_HISTORY_MD = os.path.join(ROOT, "docs", "plans", "deferred-history.md")
AGENTS_MD = os.path.join(ROOT, "AGENTS.md")

# 9,000B 경계 = auto-compact 후 스킬이 앞 5,000토큰만 재부착된다는 사양에서 온 값.
# 이 상수만은 문서가 아니라 여기 둔다 — 표의 "경계 행" 열이 이 값으로 계산된 결과이므로,
# 문서에서 읽으면 계산식과 결과를 같은 곳에서 가져와 대조가 자기순환이 된다.
HEAD_BUDGET_BYTES = 9000

# AGENTS.md 목표선 — 상한(16,384B, `session-context.ps1`이 정본)과 **다른 축**이다.
#   상한은 "주입이 목차 폴백으로 깨졌나"를 보는 하드 게이트이고, 이 값은 "다시 차오르고 있나"를
#   넘기기 전에 알리는 경고선이다. 실측 증가율이 하루 약 +170B라(2026-08 2주간 이관 3회)
#   상한만 보면 넘긴 뒤에야 알게 되는데, 그때는 이미 그 세션들이 명령도 금지선도 못 본 상태다.
#   값의 근거: 상한 대비 여유 6,384B ≈ 그 증가율로 약 37일. 상한처럼 hook에서 읽지 않는 이유는
#   정본이 없기 때문이다 — 이 경고선은 이 검사기 고유의 판정이라 여기가 정본이다.
AGENTS_TARGET_BYTES = 10000
# 하드 게이트 — 정본은 `session-context.ps1` 의 `$agentsMaxBytes` 다. 여기 두는 것은 통지 문구에
#   함께 적기 위한 사본이고, 판정에는 쓰지 않는다(판정은 위 목표선만 본다).
AGENTS_HARD_LIMIT_BYTES = 16384


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
    # 절 이름 상한이 60자였을 때 **기계 생성 포인터 16건이 매치 자체에서 빠졌다** — 근거를
    #   `rules/*-rationale.md`로 내리며 붙은 `§N ` 접두 때문에 62~64자에 몰렸기 때문이다.
    #   상한을 120자로 올리고 비교 전 양쪽을 strip 한다(후행 공백 차이로 갈리지 않게).
    pat = re.compile(r"`([A-Za-z0-9_./-]+\.md)`(?:[^「\n]{0,12})「([^」\n]{2,120})」")
    heading_cache = {}
    issues, checked, skipped, exempt = [], 0, [], []

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

    # 해석하지 않기로 **선언한** 포인터. 「못 찾았다」와 「볼 수 없다」를 같은 줄에 섞으면
    #   그 줄이 무의미해지므로 갈라 둔다(전자는 사람이 봐야 할 잠재 결함, 후자는 정상).
    #   ⓐ 레포 밖 대상(위키 vault 페이지) — 이 검사기는 vault를 스캔하지 않는다.
    #   ⓑ 산문 속 언급 — 포인터가 아니라 문장 안에서 파일을 거론한 것이라 대상이 특정되지 않는다.
    #   **경로 문자열이 아니라 (출처, 참조) 쌍으로 적는다** — 같은 이름이 다른 자리에서 진짜
    #   포인터로 쓰이면 그것은 계속 검사돼야 하기 때문이다.
    POINTER_EXEMPT = {
        ("docs/plans/deferred.md", "feat-safety-hooks-advisory.md"),
        ("docs/plans/deferred.md", "maid/feat-app-shell.md"),
        ("docs/plans/deferred-closed.md", "SKILL.md"),
    }

    # 대장 2종은 **관측 시점의 기록**이라 이미 사라진 문서를 가리키는 것이 정상이다
    #   (과거 plan·노트를 `_ARCHIVED_RX`로 제외하는 것과 같은 이유). 항목의 참조가 깨진 것은
    #   그 항목이 재판정 대상이라는 신호이고, 그 신호는 대장 자신이 담는다 — 이 축이 매번
    #   FAIL하는 방식으로 알릴 것이 아니다. 그래서 파일 단위로 통째 면제한다.
    POINTER_EXEMPT_SRC = {"docs/plans/deferred-closed.md", "docs/plans/deferred.md"}

    # 부분 경로(`implement/SKILL.md`처럼 repo 루트 기준이 아닌 표기)를 해석하기 위한 색인.
    # 이 repo의 문서는 같은 파일을 전체 경로·부분 경로 두 방식으로 가리키며, 부분 표기를
    # 해석하지 않으면 그 참조가 통째로 검사에서 빠진다(초기 구현에서 8건이 그렇게 빠졌다).
    by_suffix = {}
    for f in _md_files():
        rel = os.path.relpath(f, ROOT).replace(os.sep, "/")
        parts = rel.split("/")
        for i in range(len(parts)):
            by_suffix.setdefault("/".join(parts[i:]), []).append(f)

    # hook 스크립트도 포인터 소스다 — v1.225.0에서 근거 주석을 `rules/*-rationale.md`로 내리며
    #   `.ps1`이 그 문서의 절을 가리키게 됐는데, 이 축이 마크다운만 보아 **끊긴 포인터 46건이
    #   exit 0으로 통과했다**(완료 리뷰가 잡았다). 소스에 스크립트를 더해 같은 결함을 막는다.
    _ptr_sources = list(_md_files()) + sorted(glob.glob(os.path.join(ROOT, "plugins/pjc/scripts/*.ps1")))

    for src in _ptr_sources:
        rel_src = os.path.relpath(src, ROOT).replace(os.sep, "/")
        # 과거 plan·로컬 노트·문서 아카이브는 그 시점의 기록이라 갱신 대상이 아니다(대장 관례).
        # 판정을 `_ARCHIVED_RX`·`_LOCAL_ONLY`와 공유한다 — 종전에는 여기만 `docs/plans/2026-`로
        # 연도를 박아 두어 해가 바뀌면 이 축만 조용히 아카이브를 검사하기 시작했다.
        if _ARCHIVED_RX.match(rel_src) or rel_src in _LOCAL_ONLY:
            continue
        text = open(src, encoding="utf-8-sig", errors="replace").read()
        for ref_path, sec_name in pat.findall(text):
            cand = [os.path.join(ROOT, ref_path.replace("/", os.sep)),
                    os.path.join(os.path.dirname(src), ref_path.replace("/", os.sep))]
            target = next((c for c in cand if os.path.exists(c)), None)
            if target is None:
                # 부분 경로 표기(`implement/SKILL.md`처럼 `plugins/pjc/skills/`
                # 접두가 빠진 형제-스킬 참조)를 접미 색인으로 해석한다. 후보가 여럿이면
                # 어느 것을 뜻하는지 확정할 수 없으므로 해석하지 않는다(추측 금지).
                hits = by_suffix.get(ref_path, [])
                if len(hits) == 1:
                    target = hits[0]
            if target is None and "/" not in ref_path:
                # **같은 스킬 폴더 기준 해석.** `references/` 안의 문서가 자기 스킬의 `SKILL.md`를
                #   이름만으로 가리키는 표기가 흔한데, `dirname(src)`는 `references/`라 위 ②가
                #   실패하고 동명 파일이 스킬마다 있어 접미 색인(③)도 후보 다수로 포기한다.
                #   출처에서 위로 거슬러 `skills/<name>/` 경계를 찾아 그 폴더에서만 찾으면
                #   후보가 하나로 확정된다(추측이 아니라 소속으로 정해진다).
                #   **한계 — 이 해석은 「자기 스킬」로만 귀속시킨다.** 다른 스킬의 파일을 이름만으로
                #   가리키는 표기가 생기면 **틀린 파일에 조용히 매칭**될 수 있다(못 찾아 issues로
                #   뜨는 것보다 나쁘다). 현재 레포의 실사용 2건은 둘 다 자기 스킬 자기참조라
                #   무해하지만, 그런 표기가 생기면 `by_suffix`처럼 후보 다수 시 포기하도록 좁혀야 한다.
                skill_dir = os.path.dirname(src)
                while True:
                    up = os.path.dirname(skill_dir)
                    if not up or up == skill_dir:
                        break
                    if os.path.basename(up) == "skills":
                        skill_cand = os.path.join(skill_dir, ref_path)
                        if os.path.exists(skill_cand):
                            target = skill_cand
                        break
                    skill_dir = up
            if target is None:
                # 경로 표기가 다양해(상대·부분 경로) 해석 실패를 곧바로 결함으로 보면 오탐이 크다.
                # 다만 **조용히 넘기지는 않는다** — 파일이 실제로 삭제·이동된 경우가 가장 심한
                # 포인터 끊김인데 그것까지 침묵하면 이 축의 존재 이유가 사라진다. 건수를 노출해
                # 사람이 검토할 신호를 남긴다.
                if rel_src in POINTER_EXEMPT_SRC or (rel_src, ref_path) in POINTER_EXEMPT:
                    exempt.append("%s → `%s`" % (rel_src, ref_path))
                else:
                    skipped.append("%s → `%s`" % (rel_src, ref_path))
                continue
            hs = anchors_of(target)
            if hs is None:
                continue
            checked += 1
            # 전체 일치 또는 앵커가 그 이름으로 시작(부제·괄호 꼬리 허용).
            # 양쪽을 strip 하는 이유: 기계 생성 포인터는 절단 위치에 따라 후행 공백이 남는데
            #   그것으로 갈리면 실질 도달 가능한 참조가 끊김으로 잡힌다.
            _sn = sec_name.strip()
            if not any(h.strip() == _sn or h.strip().startswith(_sn) for h in hs):
                if rel_src not in POINTER_EXEMPT_SRC:
                    issues.append("포인터 끊김: %s → `%s` 「%s」 (대상에 그 헤딩 없음)"
                                  % (rel_src, ref_path, sec_name))
    if checked == 0:
        die("포인터 도달성: 검사 대상 포인터를 하나도 찾지 못함 (패턴이 낡았는지 확인)")
    if exempt:
        print("[NOTE] 포인터 %d건은 **검사 비대상으로 선언**됨(레포 밖 대상·산문 언급) — %s"
              % (len(exempt), " / ".join(exempt)))
    if skipped:
        # 선언되지 않은 해석 실패는 「미검사인 채 통과」다 — 파일이 실제로 삭제·이동된 경우가
        #   그 형태로 숨으므로, 건수만 흘리지 않고 **불일치로 올려** 사람이 판정하게 한다.
        #   정당한 것으로 판명되면 POINTER_EXEMPT에 (출처, 참조) 쌍으로 등재해 닫는다.
        issues.append("포인터 해석 실패 %d건 (선언되지 않음 — 삭제·이동됐거나 표기가 낡았을 수 있다. "
                      "정당하면 POINTER_EXEMPT에 등재할 것): %s"
                      % (len(skipped), " / ".join(skipped[:5]) + (" …" if len(skipped) > 5 else "")))
    return issues, checked


def check_deferred_stats(ledger, closed):
    """대기(`deferred.md`)와 종결(`deferred-closed.md`) 두 파일을 합산해 앵커와 대조한다.

    **앵커는 대기 파일에만 있다** — 계수의 정본을 한 곳에 두어야 두 파일이 갈리지 않는다.
    ⚠ 종결 파일을 읽지 않으면 `done`이 0이 되어 불변식이 통째로 어긋난다(조용한 통과가
    아니라 즉시 FAIL이므로 위험 방향은 안전하나, 인자를 빠뜨린 호출이 없어야 한다).
    """
    # 줄 끝(`$`)까지 앵커링한다 — 접두 매치로 두면 필드가 빠지거나 늘어도 조용히 통과해
    # 대장↔대조기 lockstep이 성립하지 않는다(4필드 도입 시 실측으로 드러났다).
    m = re.search(
        r"현행 잔량\(기계 대조 대상\)\*\*: 대기 (\d+) / 종결 (\d+)"
        r" / 정리 삭제 누계 (\d+) / 총 등재 누계 (\d+)\s*$",
        ledger, re.M)
    if not m:
        die("대장에서 「현행 잔량」 전용 앵커를 찾지 못함(4필드 형식이 아닐 수 있다)")
    lines = ledger.split("\n")
    closed_lines = closed.split("\n")
    try:
        w = next(i for i, l in enumerate(lines) if l.strip() == "## 대기")
    except StopIteration:
        die("`deferred.md`에서 `## 대기` 구간 헤딩을 찾지 못함")
    try:
        d = next(i for i, l in enumerate(closed_lines) if l.strip() == "## 종결")
    except StopIteration:
        die("`deferred-closed.md`에서 `## 종결` 구간 헤딩을 찾지 못함")
    # 대기는 날짜 '접두'만 본다 — `[등록일, **vN에서 부분 해소**]` 부기 형식이 실재해
    # `\]`로 닫으면 조용히 누락된다. 종결은 `[등록일 → 종결일]` 범위 형식.
    wait = sum(1 for l in lines[w:] if re.match(r"^- \[\d{4}-\d{2}-\d{2}", l))
    done = sum(1 for l in closed_lines[d:] if re.match(r"^- \[\d{4}-\d{2}-\d{2} → \d{4}-\d{2}-\d{2}\]", l))
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


def check_batch_number_sequence(hist):
    """batch 회고(`deferred-history.md`)의 blockquote 차수가 연속·유일한지 대조한다.

    **읽는 파일이 v1.198.0에서 `deferred.md` → `deferred-history.md`로 바뀌었다.**
    회고를 분리하면서 이 인자를 함께 옮기지 않으면 `nums`가 비고 아래 `if not nums`가
    **exit 0으로 통과**시켜 축이 무증상으로 사라진다 — 실패가 아니라 0항목 통과라
    러너의 종료 코드로는 잡히지 않는다. 그래서 axes 출력의 `N항목`을 함께 본다.

    차수는 규약 ⓪의 순증분 보정이 「직전 batch의 정리 직후 값」을 인용할 때
    **어느 블록을 직전으로 잡는지의 유일한 단서**라, 중복되면 계산이 갈린다.
    실측: v1.195.0이 이미 있는 `10차 batch (v1.194.0 T9)` 위에 같은 이름의 블록을
    얹었는데 이 대조기가 exit 0으로 통과시켰고, 잡아낸 것은 F-7 리뷰어였다.

    ⚠ **줄 시작 `> **N차 …` 블록 헤더에서만 센다.** 본문에는 다른 회차를 가리키는
    인용(`**9차 batch(v1.193.0…`·`**2차 batch`)이 실재해, 비앵커 정규식으로 뽑으면
    현행 대장이 곧바로 중복·비연속 오탐을 낸다.

    ⚠ **「1부터」가 아니라 「존재하는 최솟값부터」 연속을 본다** — 대장은 6차부터
    담고 있다(그 이전 기록은 남아 있지 않다).

    `N차 판정`(구간 batch 미실행)도 같은 수열을 쓰므로 함께 센다.
    """
    nums = [int(m.group(1)) for m in
            re.finditer(r"^> \*\*(\d+)차 (?:batch|판정)", hist, re.M)]
    if not nums:
        return [], 0          # batch 기록이 없는 대장(다른 프로젝트)도 통과시킨다
    issues = []
    dup = sorted({n for n in nums if nums.count(n) > 1})
    if dup:
        issues.append("batch 차수 중복 — %s (블록 %d개)"
                      % (", ".join("%d차" % n for n in dup), len(nums)))
    uniq = sorted(set(nums))
    gaps = [n for n in range(uniq[0], uniq[-1] + 1) if n not in uniq]
    if gaps:
        issues.append("batch 차수 비연속 — %s 누락 (%d차~%d차 구간)"
                      % (", ".join("%d차" % n for n in gaps), uniq[0], uniq[-1]))
    return issues, len(nums)


# ─────────────────────────────────────────────────────────────
# ③ 볼드 마커 짝 · ④ 한 줄 안 문장 중복 (문서 표기 결함)
#   ⚠ v1.224.0 이전 번호(⑧⑨)가 남아 있던 자리다 — 축 아홉이 사라지며 docstring 은 ③④ 으로
#   당겨졌는데 이 주석은 옛 번호였다. 회차 14 가 ⑧ 을 신설 축에 쓰면서 한 파일 안에서 ⑧ 이
#   두 축을 가리키게 돼 함께 고쳤다.
#
# 두 축이 공유하는 것: 스캔 제외 정책과 「펜스·코드 스팬을 걷어낸 문단」 분리.
# 왜 필요한가 — 어느 검증 명령도 이 둘을 잡지 못했다. 볼드가 어긋나면 렌더가 깨지고,
#  같은 문장이 한 줄 안에 반복 삽입되면 **정본이 둘이 된다**(v1.180.0 F-7 M1이 실제로
#  잡은 형태 — 사람 눈은 두 번 통과했다. 줄 수로 세면 같은 줄 안의 반복이 보이지 않는다).
# ─────────────────────────────────────────────────────────────
# 제외 정책 — ⓐ 픽스처는 **의도적으로 깨뜨린** 파일이라 검사 대상이 되면 축이 상시 실패한다
#  ⓑ `docs/plans/YYYY-MM-DD-*.md`는 과거 회차의 이력 자산이고 그 시점의 사실이라 고치지 않는다
#  (`deferred.md`는 살아 있는 자산이라 **제외하지 않는다** — 가장 활발히 편집되는 문서다)
#  ⓑ-2 `docs/.agents-presplit/`도 같은 이유로 제외한다 — 이관 전 문서 사본이라 **고칠 수 없고**,
#  그 안의 포인터·표기를 검사하면 남은 유일한 처방이 「아카이브를 고치는 것」이 되어 그 시점의
#  기록이 아니게 된다(v1.223.0 — 종전에는 이 관례가 plan에만 코드화돼 문서 아카이브가 빠져 있었다).
#  ⓒ `plan.md`·`notes.md`는 gitignore 로컬 전용이라 회차마다 통째로 교체된다.
_ARCHIVED_RX = re.compile(r"^docs/(plans/\d{4}-\d{2}-\d{2}-|\.agents-presplit/)")
_LOCAL_ONLY = {"plan.md", "notes.md"}
_INLINE_CODE_RX = re.compile(r"`[^`\n]*`")


def _scan_scope():
    """문서 표기 축의 대상을 `(경로, 레포 상대경로)`로 낸다 (위 제외 정책 적용)."""
    for path in _md_files():
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if "/fixtures/" in rel or _ARCHIVED_RX.match(rel) or rel in _LOCAL_ONLY:
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
    """③ 문단 누적 `**` 개수가 홀수면 볼드 구간이 어긋난 것이다 (렌더가 깨진다)."""
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
    """④ 한 줄 안에 같은 문장이 2회 이상 나오면 삽입 사고다.

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


def check_compact_anchors():
    """compact 직후 주입이 잘라 오는 절의 헤딩이 대상 문서에 실재하는지 대조한다.

    v1.212.0의 `Get-SkillSection`은 주입 텍스트를 복제하지 않고 스킬 문서 원문을 헤딩
    앵커로 잘라 온다 — 정본이 하나로 유지되는 대신, **스킬 편집 회차가 헤딩 문구를 바꾸면
    hook은 조용히 `$null`을 반환하고 폴백해 주입이 사라진다.** 그 상실은 압축된 세션에서만
    드러나므로 아무도 모른 채 지나간다. 그래서 앵커를 hook에서 **파싱해** 대조한다 —
    `$agentsMaxBytes`를 hook에서 읽는 것과 같은 이유로, 값을 여기 박으면 정본이 둘이 된다.

    헤딩이 0건이면 추출이 실패하고, 2건 이상이면 어느 쪽을 잡을지 불확정이라 둘 다 FAIL이다.

    **`section()`을 재사용하지 않는 이유**: 그 헬퍼는 못 찾으면 `die()`로 **exit 2**를 내는데
    이 축은 0건을 **exit 1 불일치**로 보고해야 하고, 첫 매치만 잘라내므로 **2건 이상을 아예
    재지 못한다**. 두 요구가 그 헬퍼와 양립하지 않아 줄 수를 직접 센다.

    **못 잡는 것 둘** (ⓒ는 v1.217.0에서 닫혔다 — 아래): ⓐ 종료 앵커의 **오타로 인한 0건**과 **의도된 EOF 절**(절이 파일
    마지막이라 종료 앵커가 없는 경우)을 구분하지 못한다 — hook이 후자를 정상으로 처리하므로
    0건을 통과로 두었고, 그래서 전자가 이 축을 그대로 지나간다. ⓑ **정규식에 매칭되지 않는
    형태로 쓰인 호출**(줄바꿈 분할·변수 경로)은 집계에서 빠진 채 통과한다 — 매칭이 **전무하면**
    아래 `die()`가 잡지만, 하나라도 맞으면 나머지의 부재는 드러나지 않는다. ⓒ였던 「크기 초과 폴백을 아무도 못 본다」는 v1.217.0에서 닫혔다 —
    아래 크기 판정이 추출 구간을 실제로 재어 `$sectionMaxBytes` 대비 초과·임박(80%)을 보고한다.
    **단위는 hook과 같게 LF 조인 UTF-8**이다(hook은 CRLF를 LF로 정규화한 뒤 재므로, 원문을
    그대로 재면 줄 수만큼 바이트가 더해져 임박 시점이 갈린다).
    """
    hook = os.path.join(ROOT, "plugins", "pjc", "scripts", "session-context.ps1")
    txt = read(hook)
    calls = re.findall(
        r"Get-SkillSection\s+-Path\s+\(Join-Path\s+\$skillsDir\s+'([^']+)'\)"
        r"\s+-StartHeading\s+'([^']+)'\s+-StopHeading\s+'([^']+)'",
        txt)
    if not calls:
        die("추출 앵커: `session-context.ps1`에서 Get-SkillSection 호출을 찾지 못함")

    # 상한은 hook에서 파싱한다 — 값을 여기 박으면 정본이 둘이 되고 한쪽만 고칠 때 갈린다
    #   (`$agentsMaxBytes`를 hook에서 읽는 것과 같은 이유).
    m_cap = re.search(r"\$sectionMaxBytes\s*=\s*(\d+)", txt)
    if not m_cap:
        die("추출 앵커: `session-context.ps1`에서 $sectionMaxBytes 를 찾지 못함")
    cap = int(m_cap.group(1))

    issues = []
    checked = 0
    for rel, start, stop in calls:
        target = os.path.join(ROOT, "plugins", "pjc", "skills", *rel.split("/"))
        if not os.path.exists(target):
            # 앵커 2개(시작·종료)를 잴 수 없게 된 것이므로 2를 더한다 —
            #   1만 더하면 정상 경로와 집계 단위가 갈려 배너의 항목 수가 어긋난다.
            issues.append("추출 앵커 — 대상 파일 없음: %s" % rel)
            checked += 2
            continue
        raw = read(target).split("\n")
        # 앵커 대조는 줄별 rstrip 한 사본으로, **크기 계산은 원본으로** 한다 —
        #   hook은 줄을 트림하지 않고 조인한 뒤 전체에 TrimEnd 1회만 적용하므로(session-context.ps1:54),
        #   같은 리스트를 재사용하면 줄 끝 공백만큼 값이 갈린다.
        lines = [l.rstrip() for l in raw]
        # 종료 앵커는 없어도 된다(절이 파일 마지막일 수 있다 — hook이 파일 끝까지로 본다).
        #   시작 앵커만 필수이며, 있다면 그것도 유일해야 추출 구간이 확정된다.
        for label, anchor, required in (("시작", start, True), ("종료", stop, False)):
            n = lines.count(anchor)
            if n != 1 and not (n == 0 and not required):
                issues.append("추출 앵커 — %s의 %s 앵커가 %d건: %s"
                              % (rel, label, n, anchor))
            checked += 1
        # 크기 판정 — 앵커가 멀쩡해도 구간이 상한을 넘으면 hook이 $null 을 반환해 주입이
        #   **조용히 사라진다**. 앵커 축만으로는 그 상태가 통과하므로 여기서 함께 잰다.
        si = lines.index(start) if start in lines else -1
        if si >= 0:
            ei = len(lines)
            for j in range(si + 1, len(lines)):
                if lines[j] == stop:
                    ei = j
                    break
            size = len(chr(10).join(raw[si:ei]).rstrip().encode("utf-8"))
            if size > cap:
                issues.append("추출 크기 — %s 「%s」 %d B > 상한 %d B (주입이 조용히 사라진다)"
                              % (rel, start, size, cap))
            elif size >= cap * 0.8:
                issues.append("추출 크기 — %s 「%s」 %d B, 상한 %d B의 80%% 도달 (절을 줄이거나 상한 재검토)"
                              % (rel, start, size, cap))
            checked += 1
    return issues, checked



DESIGN_MD = os.path.join(ROOT, "plugins", "pjc", "skills", "DESIGN.md")

# 예산 축이 보는 대상 — `DESIGN.md` 4절 표의 「대상」 열 리터럴 → 실제 파일 glob.
#   표를 정본으로 읽어 값을 여기 박지 않는다. 대상 매핑만 여기 두는 이유는 표가 사람이 읽는
#   이름("단일 `references/*.md`")을 쓰고 그것이 glob 과 1:1이 아니기 때문이다.
BUDGET_TARGETS = [
    ("`SKILL.md`", ["plugins/pjc/skills/*/SKILL.md"]),
    ("단일 `references/*.md`", ["plugins/pjc/skills/*/references/*.md"]),
    ("에이전트 정의 `agents/*.md`", ["plugins/pjc/agents/*.md"]),
    ("가이드 문서 (`DESIGN.md`·`AUTHORING.md`)",
     ["plugins/pjc/skills/DESIGN.md", "plugins/pjc/skills/AUTHORING.md"]),
    ("hook 스크립트 `scripts/*.ps1`", ["plugins/pjc/scripts/*.ps1"]),
    ("근거 문서 `scripts/rules/*.md`", ["plugins/pjc/scripts/rules/*.md"]),
]

# `llm-wiki` 트리는 예산 축의 대상이 아니다 — 회차 1~3이 Out of Scope 로 두었고(그 스킬은
#   vault 운영 절차 전체를 담아 다른 스킬과 성격이 다르다), 실측 9파일이 상한을 넘는다
#   (`wiki-schema.md` 192,698 B 등). **면제이지 통과가 아니다** — 감량은 대장의
#   「분리된 `lookup-rules.md` 의 문면 감량」 항목이 추적한다. 면제를 여기 명시해 두지
#   않으면 다음 회차가 「왜 통과하는가」를 코드에서 되짚어야 한다.
BUDGET_EXEMPT_PREFIX = ("plugins/pjc/skills/llm-wiki/",)
# 초과를 면제로 숨기지 않는다 — `rules/*.md` 는 **통지 등급**이라 초과해도 exit 0 이므로,
#   면제 없이 그대로 두면 「얼마나 넘었는가」가 매 실행에 보이면서 회차를 막지는 않는다.
#   (v1.234.0 까지는 session-context-rationale.md 를 면제로 뺐는데, 그때는 예산 축이 한 등급뿐이라
#   면제가 유일한 통과 수단이었다 — 등급이 갈린 지금은 그 우회가 불필요하다.)
BUDGET_EXEMPT = set()

# 게이트 등급의 임박 통지 임계. 추출 앵커 축의 80% 보다 높게 잡았다 — 실측에서 SKILL.md 6개가
#   전부 87% 이상이라 80% 로 두면 **매 실행에 6건이 상시로 떠 신호가 소음이 된다**
#   (대장 [2026-08-03] 「늘 '해당 없음'으로 채워지면 형식만 남는다」 와 같은 축).
BUDGET_NEAR_RATIO = 0.9


def check_agents_target():
    """AGENTS.md 목표선 통지 — `issues` 가 아니라 통지다(exit 코드에 반영하지 않는다).

    상수 주석이 이 값을 "넘기기 전에 알리는 경고선"으로 규정한다 — 하드 게이트는
    `session-context.ps1` 의 16,384 B 이고 그쪽이 넘으면 주입이 목차 폴백으로 깨진다.
    둘을 같은 등급으로 내면 경고선이 사실상 하드 게이트가 되어, 목표선을 넘은 동안
    이 검사기를 쓰는 모든 회차가 막힌다.

    통지에 현재값·목표선·하드 게이트·할 일을 함께 적는다 — 숫자만 내면 다음 세션이
    무엇을 해야 하는지 모른 채 그 줄을 지나친다.
    """
    try:
        size = os.path.getsize(AGENTS_MD)
    except OSError:
        return []
    if size <= AGENTS_TARGET_BYTES:
        return []
    return ["AGENTS.md %d B > 목표선 %d B (하드 게이트 %d B — `session-context.ps1` 이 정본). "
            "주입 상한을 넘기기 전에 절을 이관하세요 — `pjc:record-project-fact` 의 Step 5 가 그 경로입니다."
            % (size, AGENTS_TARGET_BYTES, AGENTS_HARD_LIMIT_BYTES)]


def check_doc_budget():
    """⑦ 문서 예산 — `DESIGN.md` 4절 표의 상한을 실측 파일 크기와 대조한다.

    왜 필요한가: v1.226.0 착수 시점에 스킬 5종 중 4종이 그 표의 12,000 B 를 최대 2.02배
    초과한 채였는데 **크기를 재는 축이 하나도 없어 조용히 통과**했다. 예산은 문서에만
    있고 기계는 보지 않는 상태였다.

    표를 파싱해 값을 읽는다 — 상한을 코드에 박으면 정본이 둘이 되고 한쪽만 고쳐진다.
    """
    text = read(DESIGN_MD)
    body = section(text, r"^## 4\. 문서 예산", label="DESIGN.md 「4. 문서 예산」")
    limits = {}
    # 등급까지 읽는다 — 게이트는 issues(exit 1), 통지는 notices(exit 0)로 간다.
    for m in re.finditer(r"^\| (.+?) \| \*\*([\d,]+) B\*\* \| \*\*(게이트|통지)\*\* \|", body, re.M):
        limits[m.group(1).strip()] = (int(m.group(2).replace(",", "")), m.group(3))
    if not limits:
        die("[ANCHOR FAIL] DESIGN.md 4절 표에서 상한을 하나도 읽지 못했다 — 표 형식이 바뀌었다")

    issues, notices, near, n = [], [], [], 0
    for label, globs in BUDGET_TARGETS:
        if label not in limits:
            issues.append("예산 표에 「%s」 행이 없다 — BUDGET_TARGETS 와 표가 갈렸다" % label)
            continue
        cap, grade = limits[label]
        for g in globs:
            for path in sorted(glob.glob(os.path.join(ROOT, g))):
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                if rel in BUDGET_EXEMPT or rel.startswith(BUDGET_EXEMPT_PREFIX):
                    continue
                n += 1
                size = os.path.getsize(path)
                if size > cap:
                    msg = ("문서 예산 초과: %s %d B > 상한 %d B (「%s」)" % (rel, size, cap, label))
                    if grade == "게이트":
                        issues.append(msg)
                    else:
                        notices.append(msg + " — 통지 등급이라 exit 0 을 유지합니다(고칠 때만 읽는 문서).")
                elif grade == "게이트" and size >= cap * BUDGET_NEAR_RATIO:
                    # 임박 통지 — 게이트는 넘는 순간 회차를 막으므로, 넘기 **전에** 보여야 한다.
                    #   여유 8 B 로 꽉 찬 SKILL.md 가 실재했고(회차 13 실측), 그 상태에서는 규칙을
                    #   한 구 고치려 해도 감량이 선행돼 본작업이 멈춘다.
                    near.append((cap - size, rel, size, cap))
    # 임박은 건수 요약 1줄 + 여유가 가장 적은 셋만 낸다 — 전건 나열은 상시 6줄이라 읽히지 않는다.
    if near:
        near.sort()
        head = " · ".join("%s %d/%d B(여유 %d)" % (r.split("/")[-2] + "/" + r.split("/")[-1], sz, cp, sl)
                            for sl, r, sz, cp in near[:3])
        notices.append("문서 예산 임박 %d건(게이트 등급, 상한의 %d%% 이상) — 여유 최소 셋: %s"
                       % (len(near), round(BUDGET_NEAR_RATIO * 100), head))
    return issues, n, notices


# ⑧ 줄바꿈 정합이 쓰는 유일한 git 열거다 — 기존 축의 `_md_files()` 는 md 전용 `os.walk` 라
#   `.json`·`.ps1`·`.gitignore` 를 보지 못하고 「tracked 인가」도 판정하지 못한다.
_LE_SKIP_RX = re.compile(r"(^|/)fixtures/")


def _tracked_files():
    """`git ls-files -z` 로 tracked 경로를 낸다. git 이 없거나 실패하면 `die()` 로 합류한다.

    미포착 traceback 으로 죽으면 **다른 일곱 축까지 함께 죽는다** — 이 검사기에
    처음 들어오는 외부 프로세스 의존이라 실패 경로를 명시한다.
    """
    try:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        die("[ANCHOR FAIL] git 을 실행할 수 없어 줄바꿈 축이 대상을 열거하지 못했다 — %s" % e)
    if out.returncode != 0:
        die("[ANCHOR FAIL] git ls-files 실패(rc=%d) — 줄바꿈 축이 대상을 열거하지 못했다"
            % out.returncode)
    for raw in out.stdout.split(b"\x00"):
        if raw:
            yield raw.decode("utf-8")


def check_line_endings():
    """⑧ 줄바꿈 정합 — 워킹트리 tracked 파일의 CRLF 규약 위반을 잡는다.

    왜 필요한가: `core.autocrlf=true` 아래에서 워킹트리가 LF 로 바뀌어도 **blob 이
    LF 로 정규화돼 저장되므로 `git diff` 가 비어 있다**. 그래서 사람 눈으로도 리뷰로도
    잡힐 수 없고, 실제로 v1.176.0 부터 다섯 번 재발하며 매번 `git add` 경고나 우연한
    관측으로만 드러났다(대장 `[2026-08-16]` 2회 재확인 · `[2026-08-25]`).

    세 형태를 본다. **대장의 최초 처방은 「혼재」 하나였는데 여기서 넓혔다** — 그
    처방은 전면 LF 파일을 예외 목록으로 빼는 부담을 피하려던 것이나, 기록된 사고
    다섯 중 다수가 `sed -i`·텍스트 모드 I/O 의 **전면 변환**이라 혼재만 재면 실제로
    일어난 형태를 하나도 못 잡는다. 실측에서 fixture 를 민 예외가 2건뿐이라(그 2건은
    이 회차가 CRLF 로 복원했다) 회피의 근거가 사라졌다.

      ⓐ 혼재     — CRLF 와 LF 가 한 파일에 섞였다. 편집이 삽입한 새 줄의 흔적이다.
      ⓑ bare CR  — LF 를 동반하지 않는 단독 CR. 이스케이프가 한 번 더 풀려 제어문자가
                   박히는 형태로, 원인은 다르나 검출 수단이 같아 여기서 함께 잰다.
      ⓒ 전면 LF  — 파일 전체가 LF. 위 전면 변환이 남기는 형태다.

    **못 잡는 것**: BOM(별도 축이 없다) · gitignore 된 파일(`plan.md`·`notes.md` — tracked 가
    아니라 열거되지 않는다) · index 쪽 줄바꿈(항상 LF 로 정규화돼 검사 의미가 없다).

    제외는 둘이다 — **바이너리**(NUL 바이트 포함. `.gitattributes` 가 없어 git 의 텍스트
    판정을 빌릴 수 없고, `assets/logo.png` 가 bare CR 1,253개로 상시 위반이 된다)와
    **fixture**(다른 축과 같은 정책 — 의도적으로 깨뜨린 파일이다).
    """
    issues, n = [], 0
    for rel in _tracked_files():
        if _LE_SKIP_RX.search(rel):
            continue
        try:
            with open(os.path.join(ROOT, rel), "rb") as fh:
                b = fh.read()
        except OSError:
            # 워킹트리에 없는 tracked 경로(삭제 대기 등) — 잴 대상이 아니다.
            continue
        if b"\x00" in b:
            continue
        crlf = b.count(b"\r\n")
        lf = b.count(b"\n") - crlf
        cr = b.count(b"\r") - crlf
        n += 1
        if crlf and lf:
            issues.append("줄바꿈 혼재: %s (CRLF %d · LF %d) — 편집이 삽입한 줄이 LF 로 남았다"
                          % (rel, crlf, lf))
        elif crlf == 0 and lf:
            issues.append("줄바꿈 전면 LF: %s (LF %d) — 워킹트리 규약은 CRLF 다"
                          % (rel, lf))
        if cr:
            issues.append("bare CR: %s (%d개) — LF 없는 단독 CR 이 박혔다" % (rel, cr))
    return issues, n


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

    conv = read(CONV_MD)
    ledger = read(LEDGER_MD)
    ledger_closed = read(LEDGER_CLOSED_MD)
    ledger_hist = read(LEDGER_HISTORY_MD)

    # 라벨 목록을 한 곳에 두고 **배너와 결과 문구가 둘 다 여기서 파생**되게 한다 —
    #  종전에는 배너가 별도 리터럴이라 축을 늘려도 그대로 남았다(이 회차가 실제로 겪었다).
    budget_issues, budget_n, budget_notices = check_doc_budget()
    axes = [
        ("포인터 도달성", check_pointer_reachability()),
        ("Deferred 집계", check_deferred_stats(ledger, ledger_closed)),
        ("볼드 마커 짝", check_bold_pairing()),
        ("한 줄 문장 중복", check_line_dup()),
        ("batch 차수 수열", check_batch_number_sequence(ledger_hist)),
        ("추출 앵커 도달성", check_compact_anchors()),
        ("문서 예산", (budget_issues, budget_n)),
        ("줄바꿈 정합", check_line_endings()),
    ]
    all_issues, parts = [], []
    for label, (issues, n) in axes:
        all_issues.extend(issues)
        parts.append("%s %d항목" % (label, n))

    print("== 하니스 정합 셀프체크 (%s) ==" % " · ".join(label for label, _ in axes))
    # 통지는 exit 코드에 반영하지 않는다 — 경고선이지 게이트가 아니다(위 함수 docstring).
    for m in check_agents_target() + budget_notices:
        print("[NOTICE] %s" % m)
    if all_issues:
        for m in all_issues:
            print("[MISMATCH] %s" % m)
        print("\n결과: 불일치 %d건 — 해당 파일을 고친 task가 기준선·앵커를 함께 갱신해야 합니다"
              "(`docs/harness-conventions.md` 「조건부 참조 문서 크기 임계」 참조)." % len(all_issues))
        sys.exit(1)
    print("결과: 대조 전부 일치 (%s)" % " + ".join(parts))
    sys.exit(0)


if __name__ == "__main__":
    main()
