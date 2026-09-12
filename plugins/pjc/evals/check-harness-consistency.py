#!/usr/bin/env python3
r"""하니스 전역 정합 셀프체크 — 문서가 서로 어긋나는 것을 축 18개로 잰다.

사용법: python plugins/pjc/evals/check-harness-consistency.py   (인자 없음 — repo 루트를 스스로 찾는다)
       python plugins/pjc/evals/check-harness-consistency.py --fix [--dry-run]

축: ① 포인터 도달성 ② Deferred 집계 ③ 볼드 마커 짝 ④ 한 줄 문장 중복 ⑤ batch 차수 수열
    ⑥ 추출 앵커 도달성 ⑦ 문서 예산 ⑧ 줄바꿈 정합 ⑨ 종결 사유 명시 ⑩ 핵심 포인터 실재
    ⑪ 등재 마커 실재 ⑭ 폐기 식별자 실재 ⑮ 등재 근거 실측 ⑯ 분할 헬퍼 동기 ⑰ 계수·버전 정합 ⑱ 규칙 근거 보유
    ⑲ 영향 검토 3축 ⑳ 관련 파일 파서 동기
    (**⑫⑬ 은 결번이다** — v1.224.0 이 지운 옛 축 둘을 대장 대기 항목이 아직 그 번호로
     가리켜, 재사용하면 한 문자열이 두 축을 뜻하게 된다.)

**각 축이 왜 필요한가 · 무엇을 못 잡는가 · 축을 지운 이력은 `harness-consistency-rationale.md`
가 정본이다.** 여기 복제하지 않는다 — 그 문서를 안 읽고 축을 고치면 폐지 근거를 모른 채
되살리게 된다.
"""
import glob
import json
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
# 축 11이 읽는다. **레포 루트의 이 파일만 gitignore 대상이라 커밋되지 않는다** — 없는 것이
#   정상이므로 부재는 조용히 통과한다(회차 시작 전·plan 없는 세션이 그 상태다).
#   ⚠ **픽스처 사본은 다르다** — `.gitignore` 의 `!plugins/pjc/evals/fixtures/**/plan.md` 예외로
#   추적되며, 이 축의 골든 2건이 성립하는 근거가 그 커밋된 파일이다.
PLAN_MD = os.path.join(ROOT, "plan.md")

# 9,000B 경계 = auto-compact 후 스킬이 앞 5,000토큰만 재부착된다는 사양에서 온 값.
# 이 상수만은 문서가 아니라 여기 둔다 — 표의 "경계 행" 열이 이 값으로 계산된 결과이므로,
# 문서에서 읽으면 계산식과 결과를 같은 곳에서 가져와 대조가 자기순환이 된다.
HEAD_BUDGET_BYTES = 9000

# 근거는 `harness-consistency-rationale.md` 의 「축 ⑦ — AGENTS.md 목표선이 하드 게이트와 다른 축인 이유」.
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


def charlen(path):
    """문서 예산의 측정 단위 — **바이트가 아니라 문자 수**다.

    규약 문서는 한글이 섞여 B/문자가 군마다 1.25~1.99 로 갈린다(`BUDGET.md`「예산 표」
    실측). 바이트로 재면 같은 정보량이 어느 파일에 있느냐로 다른 비용이 되고, 컨텍스트를
    차지하는 것은 바이트가 아니라 내용이라 문자 수가 재려는 것에 맞다.
    디코드 실패는 예산 판정의 관심사가 아니므로 대체 문자로 넘긴다(길이만 쓴다).
    """
    with open(path, encoding="utf-8", errors="replace") as f:
        return len(f.read())

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


# 스캔에서 빼는 디렉터리 — `_md_files()` 와 축 ⑭ 가 **같은 집합을 쓴다**(복사본을 두면
#  축마다 다른 것을 보게 된다).
_SCAN_SKIP_DIRS = {".git", "node_modules", "__pycache__", "notes-archive", "fixtures"}


def _md_files():
    # `evals/fixtures/`는 **검사 대상이 아니다** — 골든 픽스처는 검사기가 잡아야 할
    #  위반을 **의도적으로** 담고 있어(깨진 포인터·누락 절 등), 여기서 세면 그 의도가
    #  곧 실패로 보고된다. lint.py가 `90_archive/`를 제외하는 것과 같은 계열이다.
    skip = _SCAN_SKIP_DIRS
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
    # 근거는 `harness-consistency-rationale.md` 의 「축 ① — 왜 「절 이름 동반」만 포인터로 세는가」.
    # ⚠ **배제 문자를 늘리거나 절 이름 상한을 내리지 말 것** — 둘 다 무음 누락을 낸 전례가 있다.
    #   사유는 같은 문서의 「축 ① — 정규식을 좁히면 침묵한다」.
    pat = re.compile(r"`([A-Za-z0-9_./-]+\.md)`(?:[^「\n]{0,12})「([^」\n]{2,120})」")
    # 근거는 `harness-consistency-rationale.md` 의 「축 ① — 「절 이름 없는 참조」를 판정이 아니라 범위로 내는 이유」.
    pat_any = re.compile(r"`([A-Za-z0-9_./-]+\.md)`")
    # 자기 파일 내부 참조 — 대상이 **그 파일 자신**이라 경로가 선행하지 않는다. 위 `pat` 에도
    #   `pat_any` 에도 안 걸려 **계수조차 되지 않던 사각지대**였다(회차 66). 절을 지우는 회차가
    #   축 ① 로 재확인하면 끊긴 참조가 있어도 「0건」으로 통과했다.
    # 근거는 `harness-consistency-rationale.md` 의 「축 ① — 자기 파일 내부 참조를 같은 축에 넣는 이유」.
    pat_self = re.compile(r"(?:아래|위|같은 문서)(?:의)?\s*「([^」\n]{2,120})」")
    heading_cache = {}
    issues, checked, skipped, exempt = [], 0, [], []
    unnamed, named = 0, 0

    def anchors_of(path):
        """도달 대상 = 헤딩 ∪ 굵은 텍스트 ∪ 불릿 항목 ∪ 표 셀.

        이 repo는 절 앵커로 헤딩만 쓰지 않는다 — `**카운트 기준 …**`,
        `**▶ 현행 잔량(기계 대조 대상)**`, `**판정 3축**` 처럼
        굵은 텍스트를 앵커로 삼는 관례가 실재한다. 헤딩만 보면 그 참조가 전부 오탐이 된다.

        불릿·표 셀을 넣는 이유는 자기 파일 참조(`아래 「…」`)가 그 둘을 자주 가리키기
        때문이다 — 실측 3건이 그 형태였다(`README.md` 의 불릿 「위험한 명령 차단」,
        `golden-runner.md` 의 표 열 「명령」, `harness-conventions.md` 의 표 행
        「모든 `*.md` 변경」). 넓히지 않으면 **정당한 참조가 끊김으로 잡히고**, 그것을
        화이트리스트로 막으면 또 하나의 「낡을 목록」이 생긴다.

        헤딩의 `§N ---- ` 접두를 벗긴 형태도 함께 등록한다 — 그 접두는 v1.225.0 이
        근거 주석을 rationale 로 내리며 **기계가 붙인 것**이라 참조 쪽이 알 이유가 없다.
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
                    h = mm.group(1).strip()
                    hs.add(h)
                    bare = _HEADING_PREFIX_RX.sub("", h).strip()
                    if bare:
                        hs.add(bare)
                    continue
                s = line.strip()
                bm = re.match(r"^[-*] +(.+?)\s*$", s)
                if bm:
                    # 괄호 꼬리는 부기이지 이름의 일부가 아니다 — `- 위험한 명령 차단 (끌 수 없음)`
                    #   을 「위험한 명령 차단」으로도 가리킨다.
                    hs.add(re.sub(r"\s*\(.*$", "", bm.group(1)).strip())
                elif s.startswith("|"):
                    for cell in s.strip("|").split("|"):
                        c = cell.strip().strip("*").strip("`").strip()
                        if 2 <= len(c) <= 80:
                            hs.add(c)
            hs.update(b.strip() for b in re.findall(r"\*\*([^*\n]{2,80})\*\*", txt))
            hs.discard("")
            heading_cache[path] = hs
        return heading_cache[path]

    # 근거는 `harness-consistency-rationale.md` 의 「축 ① — 검사 비대상 선언이 왜 별도 목록인가」.
    POINTER_EXEMPT = {
        ("docs/plans/deferred.md", "feat-safety-hooks-advisory.md"),
        ("docs/plans/deferred.md", "maid/feat-app-shell.md"),
        ("docs/plans/deferred-closed.md", "SKILL.md"),
    }

    # 대장 2종 파일 단위 면제 — 근거는 `harness-consistency-rationale.md`의 「§5 축 ① — 대장 2종을 파일 단위로 통째 면제하는 이유」
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
        # 대장 2종은 위에서 이미 파일 단위 면제라 계수에서도 뺀다 — 그 둘은 관측 시점의
        #   기록이라 산문 언급이 많고(실측 302건), 넣으면 이 수가 부풀어 신호가 죽는다.
        if rel_src not in POINTER_EXEMPT_SRC:
            _named = len(pat.findall(text))
            unnamed += len(pat_any.findall(text)) - _named
            named += _named
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
                #   이름만으로 가리키는 표기가 흔한데 ②③ 이 둘 다 실패한다(사유는 rationale).
                #   출처에서 위로 거슬러 `skills/<name>/` 경계를 찾아 그 폴더에서만 찾으면
                #   후보가 하나로 확정된다(추측이 아니라 소속으로 정해진다).
                #   한계는 `harness-consistency-rationale.md` 의 「축 ① — 같은 스킬 폴더 해석의 한계」.
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
            # 대장 2종 인용 제외 — 근거는 `harness-consistency-rationale.md`의 「§1 축 ① — 대장 2종 인용을 축 수치에서 빼는 이유」
            if rel_src not in POINTER_EXEMPT_SRC:
                checked += 1
            # 전체 일치 또는 앵커가 그 이름으로 시작(부제·괄호 꼬리 허용).
            # 양쪽을 strip 하는 이유: 기계 생성 포인터는 절단 위치에 따라 후행 공백이 남는데
            #   그것으로 갈리면 실질 도달 가능한 참조가 끊김으로 잡힌다.
            _sn = sec_name.strip()
            if not any(h.strip() == _sn or h.strip().startswith(_sn) for h in hs):
                if rel_src not in POINTER_EXEMPT_SRC:
                    issues.append("포인터 끊김: %s → `%s` 「%s」 (대상에 그 헤딩 없음)"
                                  % (rel_src, ref_path, sec_name))

        # ---- 자기 파일 내부 참조(`아래/위/같은 문서 「절」`) ----
        # 대상은 **이 파일 자신**이라 경로 해석이 없다. 면제·아카이브 규칙은 위와 같은 것을
        #   쓴다(대장 2종은 산문 언급이 많아 파일 단위 면제).
        # ⚠ **양방향 부분 일치(`_sn in h`)를 쓰지 않는다** — 참조 문장 자신이 80자 이내
        #   굵은 텍스트면 그것이 앵커로 잡혀 **자기 자신에 도달했다고 판정된다**. 실측:
        #   `golden-runner.md` 의 `⚠ 아래 「명령」 열은 … 아래 「실행·대기 절차 (정본)」이
        #   정본이다.` 가 그 형태라, 낡은 절 이름(실제 헤딩은 `실행 절차 (정본)`)이 조용히
        #   통과했다. 근거는 `harness-consistency-rationale.md` 의
        #   「축 ① — 양방향 부분 일치를 기각한 이유」.
        if rel_src not in POINTER_EXEMPT_SRC and not _POINTER_SKIP_RX.match(rel_src):
            self_hs = anchors_of(src)
            if self_hs is not None:
                for sec_name in pat_self.findall(text):
                    checked += 1
                    _sn = sec_name.strip()
                    if not any(h.strip() == _sn or h.strip().startswith(_sn)
                               for h in self_hs):
                        issues.append("포인터 끊김: %s → 자기 파일 「%s」 (그 파일에 그 앵커 없음)"
                                      % (rel_src, sec_name))
    if checked == 0:
        die("포인터 도달성: 검사 대상 포인터를 하나도 찾지 못함 (패턴이 낡았는지 확인)")
    if unnamed:
        # 분모를 `checked` 로 쓰지 않는다 — 회차 24 T2 가 세 수의 제외 규칙을 통일했지만
        #   `checked` 는 그 위에 **헤딩 해석·앵커 확인을 통과한 부분집합**이라 여전히 분모가
        #   아니다. `named` 와 `unnamed` 는 같은 소스 집합에서 세므로 그 둘만 나란히 낸다.
        print("[NOTE] 절 이름 없는 `*.md` 참조 %d건은 **이 축의 대상 밖**이다(같은 소스 집합의 "
              "절 이름 동반 참조 %d건). 경로만 적은 참조는 파일 전체를 가리킨 것일 수도, 절을 "
              "적었어야 하는데 빠진 것일 수도 있어 기계가 가르지 못한다 — 이 수는 판정이 아니라 감시 범위다."
              % (unnamed, named))
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


# 대장 항목 1건의 문자 상한. 정본 문면은 `docs/plans/deferred.md` 머리말과
#  `plugins/pjc/skills/BUDGET.md` 이고, 이 상수는 그것을 재는 쪽이다.
#  **바이트가 아니라 문자로 재는 이유는 문서 예산 축과 같다** — 한글 1자가 3바이트라
#  바이트로 재면 같은 정보량이 언어에 따라 다른 비용으로 계산된다(`BUDGET.md` 「예산 표」
#  단위 문단). 785 B 로 초과를 내던 항목이 실측 391자로 상한 안이었다.
LEDGER_ITEM_MAX = 600


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
    # 항목 상한 600자는 대장 머리말이 선언하지만 **재는 축이 없어 2배까지 자랐다**
    #  (2026-09-11 실측 1,175·1,160). **통지 등급인 이유**: 게이트로 두면 기존 초과분이
    #  전부 red 라 그 회차가 통째로 멈춘다 — 재는 것이 먼저이고 조이는 것은 그 다음이다.
    over = [(l[:36], len(l)) for l in lines[w:]
            if re.match(r"^- \[\d{4}-\d{2}-\d{2}", l)
            and len(l) > LEDGER_ITEM_MAX]
    notices = []
    if over:
        notices.append("대장 항목 상한 초과 %d건(상한 %d자) — 통지 등급이라 exit 0 을 "
                       "유지합니다. 다음 편집에서 줄이세요: %s"
                       % (len(over), LEDGER_ITEM_MAX,
                          " · ".join("%s… %d자" % (h, c) for h, c in over[:3])))
    return issues, wait + done, notices


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
# ─────────────────────────────────────────────────────────────
# 제외 정책 — ⓐ 픽스처는 **의도적으로 깨뜨린** 파일이라 검사 대상이 되면 축이 상시 실패한다
#  ⓑ `docs/plans/YYYY-MM-DD-*.md`는 과거 회차의 이력 자산이고 그 시점의 사실이라 고치지 않는다
#  (`deferred.md`는 살아 있는 자산이라 **제외하지 않는다** — 가장 활발히 편집되는 문서다)
#  ⓑ-2 `docs/.agents-presplit/`도 같은 이유로 제외한다 — 이관 전 문서 사본이라 **고칠 수 없고**,
#  (그 근거는 `harness-consistency-rationale.md` 의 「축 ③④ — 아카이브 제외의 근거」)
#  ⓒ `plan.md`·`notes.md`는 gitignore 로컬 전용이라 회차마다 통째로 교체된다.
_ARCHIVED_RX = re.compile(r"^docs/(plans/\d{4}-\d{2}-\d{2}-|\.agents-presplit/)")
# `intent/` 는 **승인 시점의 요구 기록**이라 대상 문서의 절 이름이 나중에 바뀌어도 고치지
#   않는다(`AGENTS.md` 「Plan Location」 — *"요구는 `intent/`"*). 그래서 **자기 파일 참조
#   판정에서만** 뺀다 — 두 겹으로 좁힌 것이다. ⓐ `_ARCHIVED_RX` 에 합치면 줄바꿈·예산처럼
#   intent 에도 적용돼야 할 축까지 함께 꺼지고, ⓑ 축 ① 루프 선두에서 `continue` 하면
#   **경로 동반 참조(`pat`) 22건의 커버리지가 같이 꺼진다**(회차 66 완료 리뷰 MINOR — 그
#   22건은 BASE 까지 이 축이 재고 있던 것이다). 끄려던 것은 자기 참조 오탐 2건뿐이다.
# 회차 66 실측: 이 회차의 intent 가 ⓐ 정규식 형태를 설명하는 인용(`아래/위/같은 문서 「절
#   이름」`)과 ⓑ 아직 없는 절(`wiki-schema.md`「사실 오기 정정」 — 같은 회차가 만든다)로
#   끊김 2건을 냈는데, 둘 다 고칠 대상이 아니다.
_POINTER_SKIP_RX = re.compile(r"^intent/")
_LOCAL_ONLY = {"plan.md", "notes.md"}
# `## §2 ---- 릴리즈 누락 감지` 처럼 rationale 문서의 헤딩에 기계가 붙인 접두. 참조 쪽은
#   절 이름만 적으므로(`위 「릴리즈 누락 감지」`) 이것을 벗긴 형태도 앵커로 등록해야
#   정당한 참조가 끊김으로 잡히지 않는다. 축 ① `anchors_of` 가 쓴다.
_HEADING_PREFIX_RX = re.compile(r"^§\d+\s*-*\s*")
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
# 한 줄 중복 최소 길이 — 근거는 `harness-consistency-rationale.md`의 「§2 축 ④ — 한 줄 중복 최소 길이 20 의 근거」
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
# 예산 표의 정본. `DESIGN.md` 에서 분리됐다 — 그 파일은 폐기 식별자 축이 계속 쓴다.
BUDGET_MD = os.path.join(ROOT, "plugins", "pjc", "skills", "BUDGET.md")

# 예산 축이 보는 대상 — `BUDGET.md` 「예산 표」의 「대상」 열 리터럴 → 실제 파일 glob.
#   표를 정본으로 읽어 값을 여기 박지 않는다. 대상 매핑만 여기 두는 이유는 표가 사람이 읽는
#   이름("단일 `references/*.md`")을 쓰고 그것이 glob 과 1:1이 아니기 때문이다.
BUDGET_TARGETS = [
    ("`SKILL.md`", ["plugins/pjc/skills/*/SKILL.md"]),
    ("단일 `references/*.md`", ["plugins/pjc/skills/*/references/*.md"]),
    ("에이전트 정의 `agents/*.md`", ["plugins/pjc/agents/*.md"]),
    ("가이드 문서 (`DESIGN.md`·`AUTHORING.md`·`BUDGET.md`)",
     ["plugins/pjc/skills/DESIGN.md", "plugins/pjc/skills/AUTHORING.md",
      "plugins/pjc/skills/BUDGET.md"]),
    ("hook 스크립트 `scripts/*.ps1`", ["plugins/pjc/scripts/*.ps1"]),
    ("근거 문서 `scripts/rules/*.md`", ["plugins/pjc/scripts/rules/*.md"]),
    # 검사기 자신도 잰다 — 근거는 `BUDGET.md` 「예산 표」의 이 행이 정본이다.
    ("검사기 `evals/*.py`", ["plugins/pjc/evals/*.py", "plugins/pjc/hooks/evals/*.py",
                             "plugins/pjc/skills/evals/*.py",
                             "plugins/pjc/skills/*/evals/*.py"]),
    # 검사기에서 내린 근거 산문의 수령처. **글롭을 위 `*.py` 행과 대칭으로 둔다** —
    #   갈라 두면 새로 생긴 md 가 어느 쪽에도 안 걸려 재는 축 밖에 남는다(그 자리가
    #   실제로 있었다: `harness-consistency-rationale.md` 가 이 행이 생기기 전까지
    #   예산 표 어느 행에도 없었다). `fixtures/` 는 한 단계 더 아래라 `*` 에 안 걸린다.
    ("근거 문서 `evals/*.md`", ["plugins/pjc/evals/*.md", "plugins/pjc/hooks/evals/*.md",
                                "plugins/pjc/skills/evals/*.md",
                                "plugins/pjc/skills/*/evals/*.md"]),
]

# `llm-wiki` 트리 면제 — 선언과 근거는 `BUDGET.md` 「예산 표」가 정본이다(면제이지 통과가 아니다).
BUDGET_EXEMPT_PREFIX = ("plugins/pjc/skills/llm-wiki/",)
# 초과를 면제로 숨기지 않는다 — `rules/*.md` 는 **통지 등급**이라 초과해도 exit 0 이므로,
#   면제 없이 그대로 두면 「얼마나 넘었는가」가 매 실행에 보이면서 회차를 막지는 않는다.
BUDGET_EXEMPT = set()

# 게이트 등급의 임박 통지 임계. 추출 앵커 축의 80% 보다 높게 잡았다 — 실측에서 SKILL.md 6개가
#   전부 87% 이상이라 80% 로 두면 **매 실행에 6건이 상시로 떠 신호가 소음이 된다**
#   (대장 [2026-08-03] 「늘 '해당 없음'으로 채워지면 형식만 남는다」 와 같은 축).
BUDGET_NEAR_RATIO = 0.9


# ── 축 ⑱ 「규칙 근거 보유」 ────────────────────────────────────────────────
# **사정거리는 `DESIGN.md` 「6. 적용 범위」가 정본이다** — 여기서 다시 정하면 갈린다.
# 배제 넷·형식 정규식의 근거는 `harness-consistency-rationale.md` 의
#   「축 ⑱ — 규칙 근거 보유」. **배제이지 통과가 아니다.**
RULE_SCOPE_GLOBS = [
    "plugins/pjc/skills/plan/**/*.md",
    "plugins/pjc/skills/implement/**/*.md",
    "plugins/pjc/agents/*.md",
]
RULE_EXCLUDE_FIXTURE_SEG = "/evals/fixtures/"
RULE_EXCLUDE_LABEL_RX = re.compile(r"^- \*\*\d+\*\*[:：]")
RULE_EXCLUDE_PLACEHOLDER_RX = re.compile(r"<[^>]{2,40}>")
RULE_FORM_RX = re.compile(r"^- \*\*.+?\*\*[^\S\n]*—[^\S\n]")
# 자리표시자를 **담기만 한** 줄은 템플릿이 아니다 — 규칙이 꺾쇠를 예시로 인용할 수 있다
#   (`설정: intent — <제목>` 제목으로 커밋한다). 줄 전체에 `search` 를 걸면 그런 규칙이
#   영구히 배제돼 축이 침묵한다(회차 59 완료 리뷰 실측 1건). 볼드를 닫은 뒤 남는 것이
#   **자리표시자와 구두점뿐일 때만** 템플릿으로 본다.
TEMPLATE_RESIDUE_MAX = 10


def is_template_line(line):
    """볼드 뒤 본문이 사실상 자리표시자뿐인가 — 그때만 템플릿으로 배제한다."""
    if not RULE_EXCLUDE_PLACEHOLDER_RX.search(line):
        return False
    m = re.match(r"^- \*\*.+?\*\*", line)
    rest = line[m.end():] if m else line
    rest = RULE_EXCLUDE_PLACEHOLDER_RX.sub("", rest)
    return len(re.sub(r"[\s\W_]+", "", rest, flags=re.UNICODE)) < TEMPLATE_RESIDUE_MAX


def check_rule_rationale():
    """규칙 근거 보유 — §6 범위의 규칙이 §1 형식(`- **<규칙>** — <근거>`)을 갖췄는가.

    **통지 등급이고 0 건이어도 카운트를 낸다.** 두 선택의 근거는
    `harness-consistency-rationale.md` 의 「축 ⑱ — 규칙 근거 보유」.
    """
    issues, notices, n, missing = [], [], 0, []
    for pat in RULE_SCOPE_GLOBS:
        for path in sorted(glob.glob(os.path.join(ROOT, pat), recursive=True)):
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            if RULE_EXCLUDE_FIXTURE_SEG in "/" + rel:
                continue
            in_fence = False
            for i, line in enumerate(read(path).splitlines(), 1):
                if line.lstrip().startswith("```"):
                    in_fence = not in_fence
                    continue
                if in_fence or not line.startswith("- **"):
                    continue
                if RULE_EXCLUDE_LABEL_RX.match(line) or is_template_line(line):
                    continue
                n += 1
                if not RULE_FORM_RX.match(line):
                    missing.append("%s:%d" % (rel, i))
    notices.append(
        "규칙 근거 보유 — §1 형식을 갖추지 못한 규칙 **%d건**%s **통지 등급이라 막지 않는다.**"
        % (len(missing), (" — " + " / ".join(missing[:12]) +
                          (" 외 %d" % (len(missing) - 12) if len(missing) > 12 else "") + ".")
           if missing else " (전건 충족)."))
    return issues, n, notices


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
    """⑦ 문서 예산 — 예산 표 **둘**의 상한·기록값을 실측 파일 크기와 대조한다.

    왜 필요한가는 `harness-consistency-rationale.md` 의 「축 ⑦ — 문서 예산이 왜 필요한가」.

    표를 파싱해 값을 읽는다 — 상한을 코드에 박으면 정본이 둘이 되고 한쪽만 고쳐진다.
    """
    text = read(BUDGET_MD)
    body = section(text, r"^## 예산 표", label="BUDGET.md 「예산 표」")
    limits = {}
    # 등급까지 읽는다 — 게이트는 issues(exit 1), 통지는 notices(exit 0)로 간다.
    for m in re.finditer(r"^\| (.+?) \| \*\*([\d,]+)자\*\* \| \*\*(게이트|통지)\*\* \|", body, re.M):
        limits[m.group(1).strip()] = (int(m.group(2).replace(",", "")), m.group(3))
    if not limits:
        die("[ANCHOR FAIL] BUDGET.md 「예산 표」에서 상한을 하나도 읽지 못했다 — 표 형식이 바뀌었다")

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
                size = charlen(path)
                if size > cap:
                    msg = ("문서 예산 초과: %s %d자 > 상한 %d자 (「%s」)" % (rel, size, cap, label))
                    if grade == "게이트":
                        issues.append(msg)
                    else:
                        notices.append(msg + " — 통지 등급이라 exit 0 을 유지합니다(고칠 때만 읽는 문서).")
                elif grade == "게이트" and size >= cap * BUDGET_NEAR_RATIO:
                    # 임박 통지 — 게이트는 넘는 순간 회차를 막으므로, 넘기 **전에** 보여야 한다.
                    #   여유 8 B 로 꽉 찬 SKILL.md 가 실재했고(회차 13 실측), 그 상태에서는 규칙을
                    #   한 구 고치려 해도 감량이 선행돼 본작업이 멈춘다.
                    near.append((cap - size, rel, size, cap))
    # 조건부 참조 표 — 이 표만 **기록값 열**을 갖는다. 예산 표와 나눈 이유·기록값을 함께 재는
    #   이유는 `harness-conventions.md` 「조건부 참조 문서 크기 임계」가 정본이다.
    conv_body = section(read(CONV_MD), r"^## 조건부 참조 문서 크기 임계",
                        label="harness-conventions.md 「조건부 참조 문서 크기 임계」")
    conv_rows = re.findall(r"^\| `([^`]+)` \| ([\d,]+) \| ([\d,]+) \|", conv_body, re.M)
    if not conv_rows:
        die("[ANCHOR FAIL] 「조건부 참조 문서 크기 임계」 표에서 행을 하나도 읽지 못했다 — 표 형식이 바뀌었다")
    for rel, rec_s, cap_s in conv_rows:
        rec, conv_cap = int(rec_s.replace(",", "")), int(cap_s.replace(",", ""))
        n += 1
        try:
            size = charlen(os.path.join(ROOT, *rel.split("/")))
        except OSError:
            issues.append("조건부 참조 표: %s 가 없다 — 표에서 빼거나 경로를 고치세요" % rel)
            continue
        if size != rec:
            issues.append("조건부 참조 표 기록값 불일치: %s 기록 %d자 / 실측 %d자 (%+d) — "
                          "그 파일을 고친 task 가 같은 task 안에서 표를 갱신해야 합니다"
                          % (rel, rec, size, size - rec))
        if size > conv_cap:
            issues.append("조건부 참조 표 상한 초과: %s %d자 > 상한 %d자" % (rel, size, conv_cap))

    # 임박은 건수 요약 1줄 + 여유가 가장 적은 셋만 낸다 — 전건 나열은 상시 6줄이라 읽히지 않는다.
    if near:
        near.sort()
        head = " · ".join("%s %d/%d자(여유 %d)" % (r.split("/")[-2] + "/" + r.split("/")[-1], sz, cp, sl)
                            for sl, r, sz, cp in near[:3])
        notices.append("문서 예산 임박 %d건(게이트 등급, 상한의 %d%% 이상) — 여유 최소 셋: %s"
                       % (len(near), round(BUDGET_NEAR_RATIO * 100), head))
    return issues, n, notices


# ⑧ 줄바꿈 정합이 쓰는 유일한 git 열거다 — 기존 축의 `_md_files()` 는 md 전용 `os.walk` 라
#   `.json`·`.ps1`·`.gitignore` 를 보지 못하고 「레포 안 파일인가」도 판정하지 못한다.
_LE_SKIP_RX = re.compile(r"(^|/)fixtures/")


def _line_ending_targets():
    """`git ls-files` 로 검사 대상 경로를 낸다. git 이 없거나 실패하면 `die()` 로 합류한다.

    `--others --exclude-standard` 를 함께 준다 — **`git add` 전의 새 파일을 보기 위해서다**.
    Write 도구가 만든 신규 파일은 LF 로 저장되는데(위키 conventions-verification
    `[2026-08-23]`), tracked 만 열거하면 그 파일이 커밋된 **다음 실행**에서야 잡히고
    회차 마지막 task 라면 다음 회차로 밀린다 — 그 항목이 *"파일을 만든 회차가 스스로
    확인해야 한다"* 를 요구하던 이유다. `--exclude-standard` 가 gitignore 대상을
    걸러 내므로 `plan.md`·`notes.md` 제외는 그대로 유지된다.

    미포착 traceback 으로 죽으면 **다른 일곱 축까지 함께 죽는다** — 이 검사기에
    처음 들어오는 외부 프로세스 의존이라 실패 경로를 명시한다.
    """
    try:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z",
                              "--cached", "--others", "--exclude-standard"],
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

    왜 필요한가는 `harness-consistency-rationale.md` 의 「축 ⑧ — 줄바꿈 정합이 왜 필요한가」.

    세 형태를 본다. **대장의 최초 처방은 「혼재」 하나였는데 여기서 넓혔다** — 그
    처방은 전면 LF 파일을 예외 목록으로 빼는 부담을 피하려던 것이나, 기록된 사고
    다섯 중 다수가 `sed -i`·텍스트 모드 I/O 의 **전면 변환**이라 혼재만 재면 실제로
    일어난 형태를 하나도 못 잡는다. 실측에서 fixture 를 민 예외가 2건뿐이라(그 2건은
    이 회차가 CRLF 로 복원했다) 회피의 근거가 사라졌다.

      ⓐ 혼재     — CRLF 와 LF 가 한 파일에 섞였다. 편집이 삽입한 새 줄의 흔적이다.
      ⓑ bare CR  — LF 를 동반하지 않는 단독 CR. 이스케이프가 한 번 더 풀려 제어문자가
                   박히는 형태로, 원인은 다르나 검출 수단이 같아 여기서 함께 잰다.
      ⓒ 전면 LF  — 파일 전체가 LF. 위 전면 변환이 남기는 형태다.

    **못 잡는 것**: BOM(별도 축이 없다) · gitignore 된 파일(`plan.md`·`notes.md` —
    `--exclude-standard` 가 걸러 낸다) · index 쪽 줄바꿈(항상 LF 로 정규화돼 검사 의미가 없다).

    제외는 둘이다 — **바이너리**(NUL 바이트 포함. `.gitattributes` 가 없어 git 의 텍스트
    판정을 빌릴 수 없고, `assets/logo.png` 가 bare CR 1,253개로 상시 위반이 된다)와
    **fixture**(다른 축과 같은 정책 — 의도적으로 깨뜨린 파일이다).
    """
    issues, n = [], 0
    for rel in _line_ending_targets():
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


# 축 9가 인정하는 종결 사유. 「대상 소멸」은 독립 범주가 아니라 `기각(대상 소멸 — …)` 형태의
#   하위 사유라 넣지 않는다(넣어도 기각과 중복 매치일 뿐이다). `확인 종결`·`실측 종결`은
#   실사용 4건이 있어 인정한다 — 사유를 안 적은 것이 아니라 다른 말로 적은 것이다.
CLOSE_REASON_RX = re.compile(r"기각|반영|병합|해소|확인 종결|실측 종결|사유 미상")
# 인정하되 세는 표현 — 근거는 `harness-consistency-rationale.md`의 「§3 축 ⑨ — 인정 어휘와 백틱 인용 제외의 근거」
VAGUE_REASON_RX = re.compile(r"(?<!`)사유 미상(?!`)")
# 근거는 `harness-consistency-rationale.md` 의 「축 ⑨ — 종결 사유 표기와 `사유 미상`의 취급」.
CLOSE_REASON_TAG = "**종결 사유**:"
CLOSED_ITEM_RX = re.compile(r"^- \[\d{4}-\d{2}-\d{2} → \d{4}-\d{2}-\d{2}\]")


def check_close_reasons():
    """종결 사유 명시 — `deferred-closed.md`의 각 항목이 왜 닫혔는지 적었는가.

    **재는 것은 「사유가 있는가」이지 「기각인가」가 아니다.** 대장 규약은 한때
    *「기각만 여기로」*였으나 실측은 다르다 — 반영·병합·해소가 이미 그 파일에 산다.
    규약을 문자 그대로 강제하면 이력 본문 61건을 파일에서 들어내야 하므로, 회차 24가
    **실태를 규약으로** 삼고 이 축은 사유 명시만 잰다.

    왜 필요한가는 `harness-consistency-rationale.md` 의 「축 ⑨ — 종결 사유 명시가 왜 필요한가」.
    """
    issues, notices, n, vague = [], [], 0, 0
    for line in read(LEDGER_CLOSED_MD).splitlines():
        if not CLOSED_ITEM_RX.match(line):
            continue
        n += 1
        tag = line.find(CLOSE_REASON_TAG)
        if VAGUE_REASON_RX.search(line if tag < 0 else line[tag:]):
            vague += 1
        if not CLOSE_REASON_RX.search(line):
            head = re.search(r"\*\*(.+?)\*\*", line)
            issues.append("종결 사유 없음: %s" % (head.group(1)[:70] if head else line[:70]))
    if vague:
        notices.append(
            "종결 사유 `사유 미상` %d건 — **막지 않고 센다**. 인정 표현에서 빼면 정말 모를 때 적을 자리가"
            " 없어져 red 를 피하려 억지 사유를 적게 되고, 그것은 지금보다 나쁘다. 회차 25 가 23건을"
            " 전수 재판정해 0 으로 내렸고, 그때 **본문을 읽으면 안 갈리는 것은 하나도 없었다**." % vague)
    return issues, n, notices


# 축 10이 검사하는 포인터. **손으로 관리한다** — 「유일한 방어선」·「정본」 같은 말을 grep 하는
#   기준은 폭에 따라 1~69건으로 갈려 재현되지 않는다(회차 24 계획 리뷰). 여기 적힌 것은
#   문면이 스스로 그 문서 없이는 규칙이 사라진다고 선언한 자리다.
CRITICAL_POINTERS = [
    ("plugins/pjc/skills/implement/SKILL.md",
     "plugins/pjc/skills/implement/references/loop-stop-patterns.md",
     "자율 루프 정지 판정의 유일한 방어선 — 그 판정을 하던 hook 이 v1.225.0 에 제거돼 이 문면이 대신한다"),
]

# 핵심 포인터 **총량**의 기준선(= 목록 길이). 이 목록은 손으로 관리하는데 **줄어드는 것이
#  더 위험하다** — 항목이 빠지면 그 포인터가 지워져도 축이 조용히 통과한다(축의 전제가
#  「정규식이 못 세는 자리를 손으로 올린다」이므로, 손 목록이 곧 유일한 그물이다).
#  정당한 증감이면 **이 값을 함께 갱신한다** — 그 diff 가 목록 변경의 기록이다.
CRITICAL_POINTERS_BASELINE = 1


# 축 11이 대장 실재로 인정하는 파일. 종결된 항목은 `deferred-closed.md` 로 옮겨지므로
#   둘 다 봐야 한다 — 대기에서만 찾으면 이미 처리된 항목이 위반으로 잡힌다.
LEDGER_MARKER_RX = re.compile(r"^-\s*`?\[등재[^\]]*\]`?\s*(.*)$")

# 서식 게이트 3종. `## Deferred / Follow-up` 절만 잘라 보는 이유는 아래 docstring 에 있다.
#   구간 정규식은 `session-context.ps1` 의 계수 블록과 같은 형태로 둔다 — 두 소비자가
#   다른 구간을 보면 한쪽만 통과하는 서식이 생긴다.
DEFERRED_SECTION_RX = re.compile(r"(?ms)^## Deferred / Follow-up\s*?$(.*?)(?=^## |\Z)")
MARKER_ANY_RX = re.compile(r"\[(?:등재|미등재|미판정|다음 회차)")
MARKER_HEAD_RX = re.compile(r"^-\s*`?\[(?:등재|미등재|미판정|다음 회차)")


def _nospace(s):
    # 제목 대조 전용 정규화 — **추출이 끝난 뒤에만** 쓴다. 추출 전에 공백을 지우면
    #   볼드 경계(`**…**`)가 붙어 버려 제목의 시작·끝을 가를 수 없다.
    return re.sub(r"\s+", "", s)


def check_ledger_marker_sync():
    """등재 마커 실재 — `plan.md` 의 `[등재…]` 항목이 대장에 실제로 있는가.
    함께 **마커를 읽을 수 있는 서식인가**도 본다.

    왜 필요한가는 `harness-consistency-rationale.md` 의 「축 ⑪ — 등재 마커 실재가 왜 필요한가」.

    **제목만 대조하는 이유**: 본문은 대장으로 옮기며 다듬어지는 것이 정상이라 전문 일치를
    요구하면 오탐이 된다. 두 실측 누락은 둘 다 볼드 제목이 그대로 옮겨진 형태였다.

    **제목 비교에 공백을 지우는 이유**: 같은 다듬기가 제목에 닿기 때문이다. 대장은 조사를
    띄어 쓰고(`task 가`) `plan.md` 는 붙여 쓰는데(`task가`), 완전 일치를 요구하면 옮긴
    항목이 안 옮긴 것으로 잡힌다(2026-09-09 실측: 등재 4건 중 2건). 공백만 무시하므로
    문면이 실제로 바뀐 것은 여전히 걸린다.

    **서식 게이트가 같은 축에 있는 이유**: 「마커를 읽을 수 있는가」는 「마커가 주장하는
    것이 실재하는가」의 **전제**다. 볼드로 시작하는 항목(`- **`[등재]` …**`)은 위 정규식에
    걸리지 않아 이 축이 **0항목으로 침묵**하고, 같은 이유로 `session-context` hook 은 판정을
    마친 항목을 미판정으로 센다(2026-09-09 실측: 축 0항목 · hook 「미판정 9건」).

    **절만 잘라 보는 이유**: 서식 검사는 `## Deferred / Follow-up` 안에서만 돈다. `plan.md`
    의 작업 단계 체크박스 줄(`- [ ] **T2-1** … `[등재]` …`)이 마커 리터럴을 예시로 인용하므로
    전문을 훑으면 그 줄들이 전부 위반이 된다. 마커 대조 쪽은 종전대로 전문 순회다.

    fail-open: `plan.md` 가 없으면 `([], 0)`. gitignore 대상이라 없는 것이 정상이다.
    """
    try:
        plan = open(PLAN_MD, encoding="utf-8").read()
    except OSError:
        return [], 0
    ledgers = read(LEDGER_MD) + read(LEDGER_CLOSED_MD)
    ledgers_flat = _nospace(ledgers)
    issues, n = [], 0

    # ① 서식 게이트 — 절 안에서만. 마커를 담았는데 줄 머리가 규정 서식이 아닌 항목.
    sec = DEFERRED_SECTION_RX.search(plan)
    if sec:
        for line in sec.group(1).splitlines():
            if not line.startswith("- "):
                continue
            if MARKER_ANY_RX.search(line) and not MARKER_HEAD_RX.match(line):
                n += 1
                issues.append(
                    "Deferred 항목 서식 위반: %s — 마커는 `- ` 바로 뒤에 와야 한다"
                    " (`- `[등재]` **제목** — 본문`). 볼드가 마커를 감싸면 이 축과"
                    " `session-context` hook 이 그 항목을 읽지 못한다"
                    " (형식 정본은 `plan/references/deferred-rules.md`)" % line.strip()[:70])

    # ② 마커 대조 — 종전대로 전문 순회(D4). 비교할 때만 공백을 지운다.
    for line in plan.splitlines():
        m = LEDGER_MARKER_RX.match(line.strip())
        if not m:
            continue
        title = re.search(r"\*\*(.+?)\*\*", m.group(1))
        if not title:
            continue   # 제목이 없으면 대조할 키가 없다 — 세지 않는다
        n += 1
        if _nospace(title.group(1)) not in ledgers_flat:
            issues.append(
                "등재 마커가 주장하는 항목이 대장에 없음: %s — `[등재]` 는 「올렸다」는 뜻이다"
                " (`docs/plans/deferred.md` 에 넣거나 마커를 `[미등재:<사유>]` 로 바꿔라)"
                % title.group(1)[:70])
    return issues, n


def check_critical_pointers():
    """핵심 포인터 실재 — 「절 이름」이 없어도 이 참조들은 검사한다.

    포인터 도달성 축의 정규식은 경로 뒤에 「절 이름」이 붙은 형태만 세므로 경로만 적은
    참조가 판정 밖이다(회차 24 마감 실측 758건 — 문서를 고칠 때마다 움직이는 **관측값**이라
    acceptance 로 쓰지 않는다. 현재값은 실행 출력의 `[NOTE]` 줄이 낸다). 대부분은 파일 전체를 가리킨 정당한 표기라 전부 올리면
    오탐이 대량 발생하지만, **그 안에 「유일한 방어선」급이 섞여 있다** — 지워져도 축
    수치가 안 움직인다(회차 22 계획 리뷰 BLOCKER의 근거).
    """
    issues, n = [], 0
    if len(CRITICAL_POINTERS) != CRITICAL_POINTERS_BASELINE:
        issues.append("핵심 포인터 총량이 기준선과 다르다: %d != %d "
                      "(CRITICAL_POINTERS_BASELINE — 정당한 증감이면 그 상수를 함께 갱신한다)"
                      % (len(CRITICAL_POINTERS), CRITICAL_POINTERS_BASELINE))
    for src_rel, ref_rel, why in CRITICAL_POINTERS:
        n += 1
        src_p = os.path.join(ROOT, *src_rel.split("/"))
        ref_p = os.path.join(ROOT, *ref_rel.split("/"))
        if not os.path.exists(src_p):
            # 출처가 아예 없는 레포는 이 축의 관심사가 아니다 — 검사할 포인터가 없는 것이지
            #   포인터가 깨진 것이 아니다(골든 픽스처 `minimal-repo` 가 그런 형상이다).
            n -= 1
            continue
        if not os.path.exists(ref_p):
            issues.append("핵심 포인터의 대상이 없다: %s → %s (%s)" % (src_rel, ref_rel, why))
            continue
        if os.path.basename(ref_rel) not in read(src_p):
            issues.append("핵심 포인터가 출처에서 사라졌다: %s → %s (%s)" % (src_rel, ref_rel, why))
    return issues, n


# ─────────────────────────────────────────────────────────────
# ⑲ 영향 검토 3축 기재 — 대상 회차의 계획이 충돌·도달성·병목을 실제로 실었는가
#   규약 정본은 `docs/harness-conventions.md` 「개정·개선 전 영향 검토 (3축)」이고
#   기재 의무는 `plan/references/plan-template.md` 의 Investigation Log 절이 규정한다.
#   왜 이 형태인가는 `harness-consistency-rationale.md` 의 「축 ⑲ — 영향 검토 3축 기재」.
# ─────────────────────────────────────────────────────────────
# 게이트 — 이 접두 중 하나라도 계획의 Files 에 있으면 3축 대상이다. 정본 문면이 대상을
#   *"hook·스킬 로직 또는 규약 문서"* 로 쓰는데, 이 레포에서 그 셋이 사는 자리가 아래다.
#   검사기(`evals/`)를 넣은 것은 그것이 판정 로직이어서다 — 축을 늘리고 줄이는 변경이
#   충돌·병목을 가장 자주 만든다.
IMPACT_GATE_PREFIXES = (
    "plugins/pjc/scripts/", "plugins/pjc/skills/", "plugins/pjc/agents/",
    "plugins/pjc/evals/", "plugins/pjc/hooks/",
    "docs/harness-conventions.md", "AGENTS.md",
)
# **라벨만 본다 — 내용은 보지 않는다.** 정본이 *"재지 않은 축은 「없음」이 아니라 「미측정」으로
#   적는다"* 라 「미측정」도 정당한 기재이고, 내용을 재면 그것을 red 로 만든다.
IMPACT_AXIS_LABELS = ("충돌", "도달성", "병목")
IMPACT_FILES_RX = re.compile(r"^\s*-\s*\*\*Files\*\*\s*:(.*)$")
IMPACT_SECTION_RX = re.compile(r"(?ms)^## Investigation Log\s*?$(.*?)(?=^## |\Z)")


def _impact_labels_present(section):
    """Investigation Log 안에서 **표 행 형태로** 등장한 축 라벨을 낸다.

    줄 머리가 `|` 인 것만 세는 이유: 산문이 「충돌이 없었다」처럼 라벨 단어를 지나가듯
    쓰는 일이 흔한데, 그것까지 기재로 세면 아래 부분 기재 판정이 오탐을 낸다. 3축은
    정본에서도 표로 제시되므로 행 형태를 요구하는 것이 기재의 실제 모습과 같다.
    """
    rows = [ln for ln in section.splitlines() if ln.lstrip().startswith("|")]
    return {lab for lab in IMPACT_AXIS_LABELS if any(lab in ln for ln in rows)}


def check_impact_axes():
    """영향 검토 3축 기재 — 대상 회차의 `plan.md` 가 세 축을 전부 실었는가.

    요구 조건은 **둘의 OR** 이다. ⓐ 게이트 — Files 에 `IMPACT_GATE_PREFIXES` 가 걸린다
    ⓑ 부분 기재 — 셋 중 하나라도 실려 있다. ⓑ 를 둔 이유는 **부분 기재가 미기재보다
    나쁘기 때문**이다: 한 축만 실으면 나머지 둘이 「없음」으로 읽히는데 정본은 그 자리에
    「미측정」을 요구한다. 게이트가 못 잡는 회차라도 셋 중 하나를 쓴 이상 나머지를 묻는다.

    fail-open: `plan.md` 가 없으면 `([], 0)`. gitignore 대상이라 없는 것이 정상이고,
    골든 픽스처의 추적본(`.gitignore` 의 `!…/fixtures/**/plan.md` 예외)이 대신 잰다.
    """
    try:
        plan = open(PLAN_MD, encoding="utf-8").read()
    except OSError:
        return [], 0

    gated = []
    for line in plan.splitlines():
        m = IMPACT_FILES_RX.match(line)
        if m:
            gated += [p for p in IMPACT_GATE_PREFIXES if p in m.group(1)]
    sec = IMPACT_SECTION_RX.search(plan)
    present = _impact_labels_present(sec.group(1)) if sec else set()

    if not gated and not present:
        return [], 0
    issues = []
    for lab in IMPACT_AXIS_LABELS:
        if lab in present:
            continue
        why = ("Files 가 %s 를 담아 대상이다" % gated[0]) if gated else \
              ("다른 축(%s)이 이미 실려 있다" % " · ".join(sorted(present)))
        issues.append(
            "영향 검토 3축 미기재: `%s` 행이 Investigation Log 에 없다 — %s."
            " 재지 않았으면 「없음」이 아니라 **「미측정」**으로 적는다"
            " (`docs/harness-conventions.md` 「개정·개선 전 영향 검토 (3축)」)" % (lab, why))
    return issues, len(IMPACT_AXIS_LABELS)


# ─────────────────────────────────────────────────────────────
# ⑳ 관련 파일 파서 동기 — 같은 규약(`wiki-schema` §7-21)을 읽는 두 구현이 갈리지 않았는가
#   왜 이 형태인가는 `harness-consistency-rationale.md` 의 「축 ⑳ — 관련 파일 파서 동기」.
# ─────────────────────────────────────────────────────────────
# 대조 요소 넷. **문자열 동일성이 아니라 「그 판정이 있는가」를 잰다** — 두 구현이 다른
#   언어라 문면이 같을 수 없다. 요소마다 언어별 패턴을 쌍으로 두고 **한쪽에만 있으면**
#   MISMATCH 다. 회차 67 착수 시점에 ⓑⓒ 가 실제로 한쪽에만 있었다(드리프트 2건).
PARSER_SYNC_FILES = ("plugins/pjc/scripts/session-wiki-signals.ps1",
                     "plugins/pjc/skills/llm-wiki/scripts/lint.py")
PARSER_SYNC_ELEMENTS = [
    ("섹션 앵커 정규식", r"\^##\\s\*관련 파일", r"\^##\\s\*관련 파일"),
    ("`- ` 항목 한정", r"-notlike '-\*'", r'startswith\("-"\)'),
    ("코드펜스 제외", r"\$inFence", r"stripped_lines"),
    ("구분자 필터", r"-notmatch '\[/", r'"/" in t or'),
]


def check_parser_sync():
    """관련 파일 파서 동기 — ps1·py 두 구현에 같은 판정 요소가 다 있는가.

    **fail-closed 로 읽는다** — 파일을 못 읽으면 「요소 없음」이라 MISMATCH 가 난다.
    두 파일 다 이 레포의 자산이라 부재가 정상인 경우가 없다(골든 픽스처에도 없으면
    그 픽스처가 이 축의 대상이 아니라는 뜻이므로 아래 fail-open 이 따로 있다).

    **픽스처 fail-open**: 두 파일이 **둘 다** 없으면 `([], 0)` 이다 — 축소 픽스처에는
    그 트리가 통째로 없고, 그때 red 를 내면 무관한 케이스가 전부 깨진다.
    """
    bodies = {}
    for rel in PARSER_SYNC_FILES:
        p = os.path.join(ROOT, rel)
        bodies[rel] = read(p) if os.path.isfile(p) else None
    if all(v is None for v in bodies.values()):
        return [], 0

    ps1, py = PARSER_SYNC_FILES
    issues, n = [], 0
    for label, ps_rx, py_rx in PARSER_SYNC_ELEMENTS:
        n += 1
        have = {ps1: bodies[ps1] is not None and re.search(ps_rx, bodies[ps1]) is not None,
                py: bodies[py] is not None and re.search(py_rx, bodies[py]) is not None}
        if have[ps1] == have[py]:
            continue
        missing = ps1 if not have[ps1] else py
        issues.append(
            "관련 파일 파서 동기: `%s` 판정이 `%s` 에만 없다 — 같은 규약"
            "(`wiki-schema` §7-21)을 읽는 두 구현이라 한쪽만 고치면 lint 와 세션 신호가"
            " 다른 것을 본다" % (label, missing))
    return issues, n


# ─────────────────────────────────────────────────────────────
# ⑭ 폐기 식별자 실재 — 폐기된 단계명이 살아 있는 자산에서 **현행 규정**을 가리키는가
#   목록의 정본은 `DESIGN.md` 3-1 의 고정 형식 1줄이다 — 선언과 검사가 한 자리에 묶인다.
#   ⑫⑬ 결번의 근거는 이 파일 머리 docstring 에 있다(여기 복제하지 않는다).
#
# ─────────────────────────────────────────────────────────────
_DEPRECATED_ANCHOR = "**폐기 식별자(기계 대조)**:"

# 스캔 대상 확장자 — 이 repo 는 마크다운이 곧 실행 규칙이지만 폐기 단계명은 hook 시나리오
#  (`.ps1`)·골든 케이스(`.json`)·검사기(`.py`) 주석에도 실재한다(회차 38 이 hooks/evals/ 5건).
_DEPRECATED_EXTS = (".md", ".ps1", ".py", ".json")

# 근거는 `harness-consistency-rationale.md` 의 「축 ⑫ — 폐기 식별자 스캔이 대장 3파일을 제외하는 이유」.
_DEPRECATED_SKIP_RELS_EXTRA = {"plugins/pjc/evals/cases.json"}
_DEPRECATED_SKIP_RELS = {
    "docs/plans/deferred.md",
    "docs/plans/deferred-closed.md",
    "docs/plans/deferred-history.md",
}

# 허용목록 — `(레포 상대경로, 그 줄을 특정하는 조각)`. **줄 번호를 쓰지 않는다**(밀린다).
#  전부 폐기 사실·유래·과거 사례의 **인용**이라 현행 규정을 가리키지 않는다.
DEPRECATED_QUOTE_ALLOWLIST = [
    ("plugins/pjc/skills/DESIGN.md", "**폐기한 것**:"),
    ("plugins/pjc/skills/DESIGN.md", _DEPRECATED_ANCHOR),
    ("plugins/pjc/skills/plan/SKILL.md", "회차 38 실측:"),
    ("docs/golden-runner.md", "갈음한 사례들이 전부"),
    ("docs/harness-conventions.md", "구 근거였던 「F-4 스캔」은 대상이 소멸했다"),
    ("plugins/pjc/hooks/evals/scenarios/post-write-checks.ps1", "전재 폴백으로 경고 유지"),
    ("plugins/pjc/skills/llm-wiki/evals/lint-cases.json", "M1이 잡은 미커버 축이다"),
]

# 면제 **총량**의 기준선(= 목록 길이). 정당한 증감이면 이 값을 함께 올린다 — 숫자를 맞추려 면제를 지우지 않는다.
# 면제 총량 기준선 — 근거는 `harness-consistency-rationale.md`의 「§4 축 ⑭ — 면제 총량 기준선을 숫자로 맞추지 않는 이유」
DEPRECATED_ALLOWLIST_BASELINE = 7

# `DESIGN.md` 3-1 정본 줄의 **백틱 토큰 수**(범위 표기를 접기 전 원문 개수).
DEPRECATED_TOKENS_BASELINE = 7


def _deprecated_targets():
    """스캔 대상을 `(경로, 레포 상대경로)`로 낸다 — `_scan_scope()`의 제외 술어 + 대장 3파일."""
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in _SCAN_SKIP_DIRS]
        for n in names:
            if not n.endswith(_DEPRECATED_EXTS):
                continue
            path = os.path.join(base, n)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            if (_ARCHIVED_RX.match(rel) or rel in _LOCAL_ONLY or rel in _DEPRECATED_SKIP_RELS
                    or rel in _DEPRECATED_SKIP_RELS_EXTRA):
                continue
            yield path, rel


def _deprecated_pattern():
    """`DESIGN.md` 3-1 고정 형식 1줄에서 식별자 정규식을 만든다.

    접두가 같고 끝자리만 다른 두 토큰이 이웃하면 **범위 표기**로 보고 한 패턴으로 접는다 —
    낱개를 코드에 나열하면 그 목록이 곧 두 번째 정본이 된다.

    **원문 토큰 수를 함께 돌려준다** — 호출부가 기준선과 대조한다. 접은 패턴 수가 아니라
    토큰 수인 이유는 정본 줄과 1:1 이라 범위 접기 규칙이 바뀌어도 흔들리지 않기 때문이다.
    """
    line = next((l for l in read(DESIGN_MD).splitlines() if _DEPRECATED_ANCHOR in l), None)
    if line is None:
        die("DESIGN.md 3-1 에서 `%s` 줄을 찾지 못함 (폐기 식별자 목록의 정본)" % _DEPRECATED_ANCHOR)
    toks = re.findall(r"`([^`]+)`", line.split(_DEPRECATED_ANCHOR, 1)[1])
    if not toks:
        die("DESIGN.md 3-1 폐기 식별자 줄에서 백틱 토큰을 하나도 파싱하지 못함")
    num_rx = re.compile(r"^(.*?)([0-9]+)$")
    pats, i = [], 0
    while i < len(toks):
        lo = num_rx.match(toks[i])
        hi = num_rx.match(toks[i + 1]) if i + 1 < len(toks) else None
        if lo and hi and lo.group(1) == hi.group(1):
            pats.append("%s[%s-%s]" % (re.escape(lo.group(1)), lo.group(2), hi.group(2)))
            i += 2
            continue
        pats.append(re.escape(toks[i]))
        i += 1
    return re.compile(r"(?<![0-9A-Za-z_-])(%s)(?![0-9A-Za-z_-])" % "|".join(pats)), len(toks)


def check_deprecated_identifiers():
    """폐기 단계명이 살아 있는 자산에 남았는지 본다.

    허용목록이 인용을 덮고, 그 **목록 길이**를 기준선 상수와 · **적중 수**를 스캔에 실재한
    항목 수와 대조한다. 적중하지 않는 항목은 그 파일이 스캔 대상일 때만 따로 낸다.
    """
    rx, tok_n = _deprecated_pattern()
    # DESIGN.md 3-1 정본 줄의 **토큰 수** 대조. 줄이 통째로 사라지거나 토큰이 0이 되는 것은
    #  `_deprecated_pattern()` 의 die() 가 이미 막는다(exit 2). 여기서 막는 것은 **일부만
    #  조용히 빠지는 것**이다 — 정본 줄에서 단계명 하나가 지워지면 그 이름의 잔존이 검출되지
    #  않는 채 전건 통과가 된다. 정당한 증감이면 이 상수를 함께 갱신한다.
    if tok_n != DEPRECATED_TOKENS_BASELINE:
        return (["DESIGN.md 3-1 폐기 식별자 토큰 수가 기준선과 다르다: %d != %d "
                 "(DEPRECATED_TOKENS_BASELINE — 정당한 증감이면 그 상수를 함께 갱신한다)"
                 % (tok_n, DEPRECATED_TOKENS_BASELINE)], 0)
    allow = {}
    for rel, frag in DEPRECATED_QUOTE_ALLOWLIST:
        allow.setdefault(rel, []).append(frag)
    issues, n, hits, seen, present = [], 0, 0, set(), set()
    for path, rel in _deprecated_targets():
        present.add(rel)
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        frags = allow.get(rel, [])
        for i, line in enumerate(text.splitlines(), 1):
            m = rx.search(line)
            if not m:
                continue
            n += 1
            covered = next((f for f in frags if f in line), None)
            if covered is not None:
                hits += 1
                seen.add((rel, covered))
                continue
            issues.append("폐기 식별자 `%s` 가 살아 있는 자산에 있다: %s:%d — 현행 규정을 가리키면 "
                          "현행 이름으로 고치고, 인용이면 DEPRECATED_QUOTE_ALLOWLIST 에 올려라"
                          % (m.group(1), rel, i))
    for rel, frag in DEPRECATED_QUOTE_ALLOWLIST:
        if rel in present and (rel, frag) not in seen:
            issues.append("허용목록 항목이 적중하지 않는다: %s — `%s` (문면이 사라졌으면 목록에서 빼라)"
                          % (rel, frag))
    if len(DEPRECATED_QUOTE_ALLOWLIST) != DEPRECATED_ALLOWLIST_BASELINE:
        issues.append("면제 총량이 기준선과 다르다: %d != %d (DEPRECATED_ALLOWLIST_BASELINE — "
                      "정당한 증감이면 상수를 함께 올려라)"
                      % (len(DEPRECATED_QUOTE_ALLOWLIST), DEPRECATED_ALLOWLIST_BASELINE))
    # 총량은 같은 파일 두 리터럴의 대조라 **레포를 재지 않는다** — 스캔에 실재한 파일로
    #  한정해 적중 수와 기대 수를 함께 세면 상수가 다시 레포를 잰다. 기존 조각이 같은
    #  파일의 **새 줄에도 걸리기 시작하는** 변화가 이 대조에만 잡힌다.
    expect_hit = sum(1 for rel, _ in DEPRECATED_QUOTE_ALLOWLIST if rel in present)
    if hits != expect_hit:
        issues.append("면제 적중 수가 목록과 다르다: %d != %d (같은 조각이 새 줄에도 걸렸거나 "
                      "한 줄이 두 조각에 덮인다 — 조각을 그 줄만 특정하게 좁혀라)" % (hits, expect_hit))
    return issues, n


# ─────────────────────────────────────────────────────────────
# ⑮ 등재 근거 실측 — 대장 `## 대기` 의 각 항목이 **실해 근거 필드**를 갖는가
#   등재 하한선의 정본은 `plan/references/deferred-rules.md`이고,
#   그 하한선은 「실해가 관측된 것만 올린다」이다. 필드 형식은 `(실해: YYYY-MM-DD <관측>)`.
#
# ─────────────────────────────────────────────────────────────
LEDGER_EVIDENCE_RX = re.compile(r"\(실해: \d{4}-\d{2}-\d{2} ")


def check_ledger_evidence(ledger):
    """등재 근거 실측 — `## 대기` 항목이 `(실해: YYYY-MM-DD <관측>)` 필드를 갖는가.

    날짜까지 본다 — 필드 이름만 있고 날짜가 없으면 형식을 흉내 낸 것이지 관측 기록이 아니다.
    판정 대상은 `## 대기` 구간의 날짜 접두 항목뿐이고, 머리말의 형식 예시는 그 구간 밖이라
    걸리지 않는다(축 ② 가 같은 구간 기준으로 세는 것과 맞춘다).
    """
    lines = ledger.split("\n")
    try:
        w = next(i for i, l in enumerate(lines) if l.strip() == "## 대기")
    except StopIteration:
        die("`deferred.md`에서 `## 대기` 구간 헤딩을 찾지 못함")
    # **항목 블록 단위로 본다 — 물리줄이 아니다.** 대장에는 코드스팬 안에 실제 CR·LF 를 담아
    #  그 함정을 보여주는 항목이 있어(줄바꿈 관련 3건) 한 항목이 여러 물리줄에 걸친다.
    #  첫 줄만 보면 필드를 「항목 끝」에 두라는 머리말 형식과 양립할 수 없다(회차 40 완료 리뷰).
    tail = lines[w:]
    starts = [i for i, l in enumerate(tail) if re.match(r"^- \[\d{4}-\d{2}-\d{2}", l)]
    issues, n = [], len(starts)
    for k, a in enumerate(starts):
        b = starts[k + 1] if k + 1 < len(starts) else len(tail)
        block = "\n".join(tail[a:b])
        if LEDGER_EVIDENCE_RX.search(block):
            continue
        title = re.search(r"\*\*(.+?)\*\*", tail[a])
        issues.append(
            "등재 근거 필드가 없다: %s — 등재 하한선은 「실해가 관측된 것만」이다"
            " (`(실해: YYYY-MM-DD <관측>)` 를 붙이거나 항목을 내려라)"
            % (title.group(1)[:70] if title else tail[a].strip()[:70]))
    return issues, n


# 축 ⑯이 대조하는 두 사본. 순서가 곧 「어느 쪽이 원본인가」이며, 앞이 원본이다.
#   ⚠ 이 목록을 늘리려면 복제를 늘린다는 뜻이다 — `skills/DESIGN.md` 2절의 예외 문단을 먼저 읽는다.
SPLIT_HELPER_FILES = ("block-destructive.ps1", "guard-bash.ps1")
SPLIT_HELPER_NAME = "Split-TopLevel"


def _strip_ps_comment_lines(text):
    """줄 전체가 주석인 줄을 지운다. **본문을 오려 내기 전에** 부른다.

    산문 주석에는 짝이 안 맞는 따옴표가 흔하다(원본의 *"다음 ' 까지 전부 리터럴"*). 그것을
    문자열 시작으로 읽으면 뒤따르는 중괄호를 세지 못해 **조용히 잘린 본문**을 비교하게 된다
    — 실제로 원본이 296자에서 끊겼다.
    """
    return "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("#"))


def _ps_function_body(text, name):
    """`function <name>` 부터 그 중괄호가 닫힐 때까지를 돌려준다. 못 찾으면 None.

    문자열 안의 중괄호는 세지 않는다 — 지금 대상 함수에는 없지만, 없다는 전제를 코드가
    말하지 않으면 다음에 생겼을 때 조용히 잘린 본문을 비교하게 된다.
    """
    text = _strip_ps_comment_lines(text)
    i = text.find("function %s" % name)
    if i < 0:
        return None
    depth, started, quote = 0, False, None
    for j in range(i, len(text)):
        c = text[j]
        if quote:
            if c == quote:
                quote = None
            continue
        if c in "'\"":
            quote = c
        elif c == "{":
            depth += 1
            started = True
        elif c == "}":
            depth -= 1
            if started and depth == 0:
                return text[i:j + 1]
    return None


def _normalize_ps_body(body):
    """주석 줄을 지우고 공백을 정규화한다 — 재는 것은 판정 로직이지 문면이 아니다.

    한쪽(`guard-bash.ps1`)은 근거 주석을 `rules/bash-guard-rationale.md` 로 내렸고 그것은
    설계대로다. 주석까지 비교하면 이 축이 그 이관을 드리프트로 잡아 **문서를 정리할 때마다
    red** 가 나고, 그러면 축을 끄게 된다. 줄 전체가 주석인 것만 지운다 — 대상 함수에 줄 끝
    주석이 없고, `#` 를 문자열 안에서 잘라 내면 없던 차이를 만든다.
    """
    kept = [l.strip() for l in body.splitlines() if not l.lstrip().startswith("#")]
    return re.sub(r"\s+", " ", " ".join(k for k in kept if k)).strip()


def check_split_helper_sync():
    """축 ⑯ 분할 헬퍼 동기 — 두 hook 의 `Split-TopLevel` 본문이 같은가.

    `block-destructive.ps1` 은 `AGENTS.md` 「DO NOT」의 마지막 방어선이라 외부 파일 의존을
    만들지 않는다(공유 모듈은 dot-source 실패 시 차단이 통째로 사라지고 그 경로를 재는 것이
    없다). 그래서 이 함수는 공유가 아니라 복제이고, **복제를 허용한 대가로 여기서 감시한다** —
    「복제 리터럴 동기」 축이 v1.224.0 에 폐지된 근거가 *"`DESIGN.md` 2절로 복제 자체를 금지해
    감시할 대상이 없다"* 였으므로, 복제를 만드는 순간 그 전제가 깨진다.

    **부재는 통과가 아니다** — 한쪽에서 함수를 지우면 드리프트가 아니라 감시 대상 소멸이고,
    그것이 조용히 지나가면 남은 쪽이 혼자 바뀌어도 아무도 모른다.
    """
    scripts = os.path.join(ROOT, "plugins", "pjc", "scripts")
    issues, bodies = [], {}
    for name in SPLIT_HELPER_FILES:
        path = os.path.join(scripts, name)
        if not os.path.exists(path):
            issues.append("분할 헬퍼 동기: 파일 없음 — plugins/pjc/scripts/%s" % name)
            continue
        body = _ps_function_body(open(path, encoding="utf-8-sig").read(), SPLIT_HELPER_NAME)
        if body is None:
            issues.append("분할 헬퍼 동기: %s 에 `function %s` 이 없다 — 복제 한쪽이 사라지면 "
                          "남은 쪽의 드리프트를 재는 것이 없어진다" % (name, SPLIT_HELPER_NAME))
            continue
        bodies[name] = _normalize_ps_body(body)

    if len(bodies) == len(SPLIT_HELPER_FILES):
        src, dst = SPLIT_HELPER_FILES
        if bodies[src] != bodies[dst]:
            a, b = bodies[src], bodies[dst]
            at = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
            issues.append("분할 헬퍼 동기: `%s` 본문이 갈렸다 — %s ↔ %s. 첫 차이 %d자째: "
                          "원본 %r / 사본 %r (주석·공백은 비교에서 제외된다)"
                          % (SPLIT_HELPER_NAME, src, dst, at + 1, a[at:at + 40], b[at:at + 40]))
    return issues, len(bodies)


# 축 ⑰이 파싱하는 세 문면. **사정거리는 문서 전체이고 아래 절 이름은 앵커로만 쓴다** —
#  절 밖 계수는 `(기계 미대조)` 표시로 닫는다(회차 56 리뷰: 절 안으로 자른 탓에 실제로
#  낡아 있던 자리가 통째로 빠졌다).
COUNT_SECTION_HEADING = "## 검증 명령 상세"
# ⓐ `케이스 정본은 \`<경로>\`` — 그 줄이 어느 매니페스트를 말하는지
_RX_MANIFEST = re.compile(r"케이스 정본은 `([^`]+\.json)`")
# ⓑ `**기준선 N케이스**` — 같은 줄의 기재값
_RX_BASELINE = re.compile(r"\*\*기준선 (\d+)케이스\*\*")
# ⓒ `` `<파일>`은 N건 `` — hook-cases 만 쓰는 별도 형태(그 줄의 「기준선」은 러너 총계라
#  파일 건수가 아니다). 그래서 ⓑ 로 재면 870 ↔ 269 로 어긋난 판정이 나온다.
_RX_FILE_COUNT = re.compile(r"`([\w.-]+\.json)`은 (\d+)건")
# ⓓ 문서 안의 **모든** `N케이스` 표기. ⓐ 가 못 잡는 자리를 찾아내 표시를 강제하는 데 쓴다.
_RX_CASE_COUNT = re.compile(r"\d+케이스")
# 그 표시 문구. 이 자리는 사람이 러너 출력을 눈으로 대조하는 수밖에 없다는 선언이다.
_UNMEASURED_MARK = "(기계 미대조)"
# 러너 총계(hook 골든)는 내장 시나리오가 섞여 **파일을 세면 원리상 어긋난다** — 그 축은
#  `run-hook-evals.ps1` 자신이 자기 총계를 상수와 대조한다(회차 55 T4). 여기서는 세지 않는다.
COUNT_SKIP_BASELINE = {"hook-cases.json"}


PLUGIN_JSON = os.path.join(ROOT, "plugins", "pjc", ".claude-plugin", "plugin.json")
README_MD = os.path.join(ROOT, "README.md")
# ⓒ 형태로 적힌 파일명을 레포 경로로 되돌리기 위한 목록. 문서가 파일명만 적으므로
#  여기 없는 이름은 이 축의 대상이 아니다(다른 문맥의 json 언급을 세지 않는다).
_MANIFEST_PATHS = (
    "plugins/pjc/hooks/evals/hook-cases.json",
    "plugins/pjc/skills/llm-wiki/evals/lint-cases.json",
    "plugins/pjc/skills/record-project-fact/evals/relocation-cases.json",
    "plugins/pjc/evals/cases.json",
    "plugins/pjc/skills/evals/trigger-cases.json",
)


def _load_json(path):
    """JSON 을 읽어 낸다. 부재·파손이면 `None` — 판정 불가와 불일치를 가른다."""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _read_json_field(path, key):
    doc = _load_json(path)
    return doc.get(key) if isinstance(doc, dict) else None


def _json_case_count(rel):
    """매니페스트의 케이스 수. 못 읽으면 `None`.

    최상위가 리스트인 것과 `{"_note": …, "cases": [...]}` 형태가 섞여 있어 둘 다 받는다.
    """
    doc = _load_json(os.path.join(ROOT, rel))
    if isinstance(doc, dict):
        doc = doc.get("cases")
    return len(doc) if isinstance(doc, list) else None


# frontmatter 필드 길이 상한 — 출처는 Anthropic 공식 Agent Skills best-practices 다.
#  **단위가 바이트가 아니라 문자**라 한글 스킬에서 바이트로 재면 3배로 어긋난다.
#  넘으면 스킬이 로드되지 않으므로 통지가 아니라 게이트다.
SKILL_FM_MAX = {"name": 64, "description": 1024}
# 같은 출처의 **하드 제약 2종** — 근거는 `harness-consistency-rationale.md` 의
#  「축 ⑰ — frontmatter 하드 제약 2종」.
SKILL_FM_RESERVED = ("anthropic", "claude")
_RX_FM_XML = re.compile(r"<[A-Za-z/!]")
_RX_FRONTMATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---", re.S)


def check_count_and_version(conv):
    """축 ⑰ 계수·버전 정합 — 문서가 적은 수가 실제와 같은가.

    왜 필요한가·버전을 함께 재는 이유는 `harness-consistency-rationale.md` 의
    「축 ⑰ — 계수·버전 정합이 왜 필요한가」.
    """
    issues, n = [], 0
    # **매니페스트가 하나도 없으면 골든 픽스처다** — 픽스처는 레포의 일부만 담으므로 없는
    #  파일까지 세면 이 축이 픽스처에서 상시 실패한다(축 ⑭ 가 같은 이유로 스캔 실재를 본다).
    #  그래서 실재 여부를 **먼저** 가르고, 그 뒤의 절 부재만 앵커 실패로 판정한다.
    if not any(os.path.exists(os.path.join(ROOT, p)) for p in _MANIFEST_PATHS):
        return issues, n
    body = conv.split(COUNT_SECTION_HEADING, 1)
    if len(body) < 2:
        # 매니페스트는 있는데 절이 없다 = 헤딩이 바뀌어 축이 통째로 조용해진 것이다.
        #  통과로 읽히면 안 되므로 다른 앵커 실패와 같은 exit 2 를 쓴다.
        die("절을 찾지 못함: `%s` 「검증 명령 상세」 — 헤딩을 바꿨으면 "
            "COUNT_SECTION_HEADING 을 함께 고쳐라" % os.path.relpath(CONV_MD, ROOT))
    # **사정거리는 문서 전체다 — 절은 앵커로만 쓴다.** 절 안으로 자르면 그 밖의 계수가
    #  빠지고, **실측으로 낡아 있던 것이 그 밖이었다**(회차 56 리뷰: 문서 6 · 실측 10).
    section = conv

    for line in section.split("\n"):
        m = _RX_MANIFEST.search(line)
        if m:
            rel, base = m.group(1), _RX_BASELINE.search(line)
            name = os.path.basename(rel)
            if base and name not in COUNT_SKIP_BASELINE:
                n += 1
                actual = _json_case_count(rel)
                if actual is None:
                    issues.append("계수 정합: `%s` 를 읽지 못했다 — 경로가 바뀌었는지 확인하라" % rel)
                elif actual != int(base.group(1)):
                    issues.append("계수 정합: `%s` 는 %d건인데 문서는 **기준선 %s케이스**로 적었다 "
                                  "— 케이스를 늘린 task 가 이 줄을 함께 갱신해야 한다"
                                  % (rel, actual, base.group(1)))
        # 매니페스트에 기대지 않는 계수는 **「기계 미대조」로 표시하게 강제한다** — 근거는
        #  `harness-consistency-rationale.md` 의 「축 ⑰ — 미대조 표시를 강제하는 이유」.
        if _RX_CASE_COUNT.search(line) and not _RX_MANIFEST.search(line):
            n += 1
            if _UNMEASURED_MARK not in line:
                issues.append("계수 정합: 매니페스트 없이 케이스 수를 적은 줄에 `%s` 표시가 없다 "
                              "— 기계가 못 재는 수임을 명시하거나 「케이스 정본은 `<경로>`」 "
                              "형식으로 고쳐 축에 흡수시켜라: %s"
                              % (_UNMEASURED_MARK, line.strip()[:70]))
        for fm in _RX_FILE_COUNT.finditer(line):
            hit = next((p for p in _MANIFEST_PATHS if os.path.basename(p) == fm.group(1)), None)
            if not hit:
                continue
            n += 1
            actual = _json_case_count(hit)
            if actual is None:
                issues.append("계수 정합: `%s` 를 읽지 못했다" % hit)
            elif actual != int(fm.group(2)):
                issues.append("계수 정합: `%s` 는 %d건인데 문서는 %s건으로 적었다"
                              % (hit, actual, fm.group(2)))

    for path in sorted(glob.glob(os.path.join(ROOT, "plugins", "pjc", "skills",
                                               "*", "SKILL.md"))):
        fm = _RX_FRONTMATTER.match(read(path))
        # **frontmatter 가 없으면 스킵한다** — 픽스처의 `sample/SKILL.md` 가 그 형태이고
        #  정상 케이스(`harness-ok`)의 픽스처라, 에러로 처리하면 그 케이스가 깨진다.
        #  스킬이 아닌 마크다운이 그 경로에 놓일 수도 있어 관용이 안전측이다.
        if not fm:
            continue
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        for field, cap in sorted(SKILL_FM_MAX.items()):
            m = re.search(r"(?ms)^%s:\s*(.*?)(?=\r?\n[a-z-]+:|\Z)" % field, fm.group(1))
            if not m:
                continue
            n += 1
            # 여러 줄 값은 로드될 때 한 줄로 접히므로 공백을 정규화한 뒤 센다.
            val = " ".join(m.group(1).strip().strip("'\"").split())
            if len(val) > cap:
                issues.append("frontmatter 길이: `%s` 의 %s 가 %d자로 상한 %d자를 넘었다 "
                              "— 넘으면 그 스킬이 로드되지 않는다(단위는 바이트가 아니라 "
                              "문자다)" % (rel, field, len(val), cap))
            # 예약어는 `name` 에만 걸린다 — 사유는 위 상수가 가리키는 rationale 절.
            if field == "name":
                hit = next((w for w in SKILL_FM_RESERVED if w in val.lower()), None)
                if hit:
                    issues.append("frontmatter 예약어: `%s` 의 name `%s` 이 예약어 `%s` 를 "
                                  "담았다 — 공식이 금지하는 낱말이라 그 스킬이 로드되지 "
                                  "않는다" % (rel, val, hit))
            if _RX_FM_XML.search(val):
                issues.append("frontmatter XML 태그: `%s` 의 %s 가 `<` 로 시작하는 태그꼴을 "
                              "담았다 — 공식이 두 필드 모두에 금지한다" % (rel, field))

    # 버전 축도 같은 관용을 쓴다 — 픽스처에는 `plugin.json`·`README.md` 가 없다.
    if not (os.path.exists(PLUGIN_JSON) and os.path.exists(README_MD)):
        return issues, n
    n += 1
    plugin_v = _read_json_field(PLUGIN_JSON, "version")
    readme_m = re.search(r"^\*\*버전\*\*:\s*(\S+)", read(README_MD), re.M)
    if plugin_v is None or readme_m is None:
        issues.append("버전 정합: 정본 두 곳 중 한쪽을 읽지 못했다 — `plugin.json` 의 "
                      "`version` 과 `README.md` 상단 `**버전**:` 줄이 정본이다")
    elif plugin_v != readme_m.group(1):
        issues.append("버전 정합: `plugin.json` %s ↔ `README.md` %s — 버전은 한 커밋에서 "
                      "두 곳을 함께 올린다" % (plugin_v, readme_m.group(1)))
    return issues, n


# `--fix` 가 절대 건드리지 않는 파일 — `plan.md` 는 gitignore 라 복구 경로가 없다(글로벌 지침
#  「범위 확인」). 대상에 없어도 이름으로 막아 둔다. 나머지 대상은 git tracked 라 백업을 두지 않는다.
FIX_FORBIDDEN = ("plan.md", "notes.md")


def _count_fix_edits():
    """`--fix` 가 수행할 치환을 `(경로, 옛 문자열, 새 문자열, 설명)` 으로 낸다.

    **판단이 필요 없는 것만 담는다** — 대조 상대가 실재하고 결정론적인 값뿐이다.
    러너 총계(hook 골든)는 내장 시나리오가 섞여 파일을 세면 어긋나므로 여기 없다.
    """
    edits, conv = [], read(CONV_MD)
    body = conv.split(COUNT_SECTION_HEADING, 1)
    if len(body) < 2:
        return edits
    section = conv    # 사정거리는 위 축과 같다 — 문서 전체.

    for line in section.split("\n"):
        m = _RX_MANIFEST.search(line)
        if m:
            rel, base = m.group(1), _RX_BASELINE.search(line)
            if base and os.path.basename(rel) not in COUNT_SKIP_BASELINE:
                actual = _json_case_count(rel)
                if actual is not None and actual != int(base.group(1)):
                    edits.append((CONV_MD, base.group(0),
                                  "**기준선 %d케이스**" % actual,
                                  "%s 기준선 %s → %d" % (rel, base.group(1), actual)))
        for fm in _RX_FILE_COUNT.finditer(line):
            hit = next((p for p in _MANIFEST_PATHS if os.path.basename(p) == fm.group(1)), None)
            if not hit:
                continue
            actual = _json_case_count(hit)
            if actual is not None and actual != int(fm.group(2)):
                edits.append((CONV_MD, fm.group(0),
                              "`%s`은 %d건" % (fm.group(1), actual),
                              "%s 파일 건수 %s → %d" % (hit, fm.group(2), actual)))

    if os.path.exists(PLUGIN_JSON) and os.path.exists(README_MD):
        plugin_v = _read_json_field(PLUGIN_JSON, "version")
        readme_m = re.search(r"^\*\*버전\*\*:\s*(\S+)", read(README_MD), re.M)
        if plugin_v and readme_m and plugin_v != readme_m.group(1):
            edits.append((README_MD, readme_m.group(0),
                          "**버전**: %s" % plugin_v,
                          "README 버전 %s → %s" % (readme_m.group(1), plugin_v)))
    return edits


def run_fix(dry_run):
    """계수·버전을 실측값으로 치환한다. `dry_run` 이면 한 바이트도 쓰지 않는다."""
    edits = _count_fix_edits()
    if not edits:
        print("[FIX] 고칠 것 없음 — 계수·버전이 전부 실측과 같다.")
        return 0
    by_file = {}
    for path, old, new, desc in edits:
        if os.path.basename(path) in FIX_FORBIDDEN:
            die("`--fix` 대상에 %s 가 들어왔다 — 복구 경로가 없는 파일이라 손대지 않는다"
                % os.path.basename(path))
        print("[%s] %s" % ("WOULD-FIX" if dry_run else "FIXED", desc))
        by_file.setdefault(path, []).append((old, new))
    if dry_run:
        print("\n결과: %d건 — `--dry-run` 이라 쓰지 않았습니다." % len(edits))
        return 0
    for path, subs in by_file.items():
        # 줄바꿈을 보존한다 — `newline=""` 없이 쓰면 CRLF 가 LF 로 눕고 「줄바꿈 정합」 축이
        #  red 를 낸다(그 축은 `git ls-files` 로 재므로 tracked 파일에서만 드러난다).
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
        for old, new in subs:
            text = text.replace(old, new, 1)
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
    print("\n결과: %d건 갱신했습니다 — 이어서 인자 없이 1회 더 돌려 확인하세요." % len(edits))
    return 0


def main():

    # Windows 기본 콘솔은 cp949라 출력의 `—`(em dash)·한글 기호가 UnicodeEncodeError를 낸다.
    # 검증 매핑에 등록된 명령은 `python <이 파일>`이라 환경변수가 붙지 않으므로, 스스로 UTF-8로
    # 재설정하지 않으면 **매 실행이 크래시해 검사 자체가 성립하지 않는다**(개발 중 `PYTHONUTF8=1`을
    # 붙여 돌리면 이 결함이 보이지 않는다 — 실제로 그렇게 놓쳤다).
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass  # 재설정 불가 환경(파이프 등)에서는 그대로 진행

    # `--fix` 는 축 ⑰의 결정론적 자리만 고치고 즉시 끝난다 — 다른 축은 내용 판단이 필요해
    #  영구 제외다(llm-wiki `lint.py --fix` 와 같은 선긋기). 인자 없는 기본 실행은 불변이다.
    if "--fix" in sys.argv:
        sys.exit(run_fix("--dry-run" in sys.argv))

    conv = read(CONV_MD)
    ledger = read(LEDGER_MD)
    ledger_closed = read(LEDGER_CLOSED_MD)
    ledger_hist = read(LEDGER_HISTORY_MD)

    # 라벨 목록을 한 곳에 두고 **배너와 결과 문구가 둘 다 여기서 파생**되게 한다 —
    #  종전에는 배너가 별도 리터럴이라 축을 늘려도 그대로 남았다(이 회차가 실제로 겪었다).
    budget_issues, budget_n, budget_notices = check_doc_budget()
    close_issues, close_n, close_notices = check_close_reasons()
    ledger_issues, ledger_n, ledger_notices = check_deferred_stats(ledger, ledger_closed)
    rule_issues, rule_n, rule_notices = check_rule_rationale()
    axes = [
        ("포인터 도달성", check_pointer_reachability()),
        ("Deferred 집계", (ledger_issues, ledger_n)),
        ("볼드 마커 짝", check_bold_pairing()),
        ("한 줄 문장 중복", check_line_dup()),
        ("batch 차수 수열", check_batch_number_sequence(ledger_hist)),
        ("추출 앵커 도달성", check_compact_anchors()),
        ("문서 예산", (budget_issues, budget_n)),
        ("줄바꿈 정합", check_line_endings()),
        ("종결 사유 명시", (close_issues, close_n)),
        ("핵심 포인터 실재", check_critical_pointers()),
        ("등재 마커 실재", check_ledger_marker_sync()),
        ("폐기 식별자 실재", check_deprecated_identifiers()),
        ("등재 근거 실측", check_ledger_evidence(ledger)),
        ("분할 헬퍼 동기", check_split_helper_sync()),
        ("계수·버전 정합", check_count_and_version(conv)),
        ("규칙 근거 보유", (rule_issues, rule_n)),
        ("영향 검토 3축", check_impact_axes()),
        ("관련 파일 파서 동기", check_parser_sync()),
    ]
    all_issues, parts = [], []
    for label, (issues, n) in axes:
        all_issues.extend(issues)
        parts.append("%s %d항목" % (label, n))

    print("== 하니스 정합 셀프체크 (%s) ==" % " · ".join(label for label, _ in axes))
    # 통지는 exit 코드에 반영하지 않는다 — 경고선이지 게이트가 아니다(위 함수 docstring).
    for m in (check_agents_target() + budget_notices + close_notices
              + ledger_notices + rule_notices):
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
