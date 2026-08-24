# -*- coding: utf-8 -*-
"""AGENTS.md 주입 상한 이관 — 절을 원문 그대로 옮기고 그 자리에 포인터를 남긴다.

**판정의 정본은 이 docstring이다.** `record-project-fact/SKILL.md` Step 5는 이 스크립트를
부르고 결과를 보고하는 절차만 담는다 — 판정 서술이 두 곳에 있으면 한쪽만 고쳐지는 드리프트가
생기고, 그 드리프트는 「어느 쪽이 맞는가」를 매번 되짚게 만든다.

판정 순서(위키 `lint.py`의 산문 하위 분리와 **같은 순서**다 — 도메인이 달라 코드는 공용화하지
않지만 순서를 맞춰 두면 한쪽을 읽은 사람이 다른 쪽을 읽을 때 되짚을 것이 없다):

  ⓐ 발동 — 파일 바이트가 상한의 `near_ratio` 이상이거나 여유가 `near_slack` 미만이면 이관한다.
     **상한·비율·잔여를 여기 박지 않는다** — `session-context.ps1`에서 셋 다 읽는다. 상한만
     읽고 나머지를 박으면 hook이 임계를 바꿔도 판정이 따라가지 않는다.
  ⓑ 잔류 — `## 위키` · `## Build & Test` · `## DO NOT` · `## Plan Location`은 절 단위로
     통째 남긴다. **줄 단위로 가르지 않는다**: 명령만 남기고 「언제 어떤 조건에서 쓰는지」를
     설명하는 산문을 떼면 남은 명령이 그대로 오용된다.
     **`## Stack`이 아니라 `## 위키`인 이유**: 프로젝트 정보는 위키가 정본이 되어 `## Stack`
     자체가 사라졌고(`plugins/pjc/skills/AGENTS-BOUNDARY.md` 「AGENTS.md 내용 경계」), `## 위키`는
     그 정본으로 가는 유일한 포인터라 옮기면 도달 경로가 끊긴다.
  ⓒ 대상 — 잔류 밖의 `## ` 절을 바이트 크기순으로 세어 큰 것부터. 크기는 헤딩 줄부터 다음
     `## ` 직전까지의 **파일 바이트**(CRLF 포함 — ⓐ 판정과 같은 기준).
  ⓓ 이관처 — 결정론 2분기다. ① 본문에 백틱·링크로 등장하는 `.md` 경로 중 **최다 등장**(동수면
     먼저 나온 것) ② 후보가 없으면 `docs/agents-detail.md` 신설. 「규약 문서처럼 보이는 것을
     고른다」 같은 판단 여지를 두지 않는다 — 회차마다 다른 곳으로 흩어지면 그것이 곧 유실이다.
  ⓔ 포인터 — 옮긴 자리에 **절 제목을 유지한 채** `**정본은 …의 「…」이다** — …` 1줄을 남긴다.
     제목까지 지우면 목차 폴백에서도 그 주제가 사라져 「어디로 갔는지 물을 실마리」조차 없다.
  ⓕ 사본 — 착수 직전 `docs/.agents-presplit/{YYYY-MM-DD}/`에 복사한다(git 저장소여도 만든다 —
     이관은 미커밋 작업 도중에도 돌 수 있어 `git checkout` 원복이 그 작업까지 지운다).
  ⓖ 검증 — ① 상한 이내 ② 잔류 절 7종 존재 ③ 포인터 도달성(파일 실재 + **같은 절 이름 존재**)
     ④ 원문 줄 수 보존. 하나라도 실패하면 ⓕ 사본으로 원복하고 보고한다.
  ⓘ 이관 불가 — 잔류 절만으로 이미 상한을 넘거나 옮길 절이 하나도 없으면 **아무것도 옮기지
     않고** 그 사실을 보고한다. 마커로 남기지 않는다(잔류 크기는 이후 기록으로 바뀐다).
     새 경계에서 잔류 7종은 AGENTS.md 절의 사실상 전부라 이것은 예외가 아니라 **정상 귀결**이다 —
     그래서 막다른 메시지로 끝내지 않고 **소급 정리 경로**를 함께 지목한다(SKILL.md 「소급 정리」).

사용: python relocate-agents.py <레포 루트> [--dry-run]
종료 코드: 0 정상(이관했거나 발동하지 않음) / 1 실패(검증 실패로 원복했거나 입력 오류).
"""
import datetime
import io
import os
import re
import shutil
import sys

# Windows 콘솔(cp949)에서도 한글·줄표가 깨지지 않도록 UTF-8 출력 강제.
#  형제 스크립트(`llm-wiki/evals/run_lint_evals.py`·`evals/check-harness-consistency.py`)와
#  같은 관례다 — 이것이 없으면 문서가 안내한 그대로 실행할 때 UnicodeEncodeError로 죽는다.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# 이관 대상이 0인 것은 새 경계에서 예외가 아니라 정상 귀결이다(잔류 7종이 AGENTS.md 절의 거의 전부).
# 그래서 막다른 메시지로 끝내지 않고 실제 해소 경로를 지목한다 — 절을 옮기는 대신 절 **안**을 줄인다.
_MIGRATE_HINT = (
    "[이관 불가] %s" + chr(10)
    + "    절 단위로는 해소할 수 없다 — `record-project-fact` SKILL.md 「소급 정리」로 간다"
    + "(잔류 절 안의 근거 서술을 레포 상세 문서·위키로 보내고 명령·값만 남긴다).")

KEEP_SECTIONS = ("위키", "Build & Test", "Conventions", "데이터 접근",
                 "산출물·파일 관리", "DO NOT", "Plan Location")
DEFAULT_DEST = "docs/agents-detail.md"
BACKUP_DIR = os.path.join("docs", ".agents-presplit")
# hook에서 읽을 세 값의 변수 이름. 이름이 바뀌면 여기서 **명확히 실패**한다(조용한 기본값 금지).
LIMIT_VARS = ("agentsMaxBytes", "agentsNearRatio", "agentsNearSlack")


def load_limit(hook_path):
    """`session-context.ps1`에서 상한·비율·잔여 세 값을 읽는다.

    하나라도 못 찾으면 예외를 던진다 — 기본값으로 조용히 진행하면 hook이 임계를 바꾼 뒤에도
    이 스크립트만 옛 기준으로 판정하고, 그 어긋남은 아무 신호도 내지 않는다."""
    text = io.open(hook_path, encoding="utf-8-sig").read()
    out = {}
    for var in LIMIT_VARS:
        m = re.search(r"\$%s\s*=\s*([0-9.]+)" % re.escape(var), text)
        if not m:
            raise SystemExit("[ERROR] %s에서 $%s를 찾지 못했다 — hook 변수명이 바뀌었는지 확인" %
                             (hook_path, var))
        out[var] = float(m.group(1))
    return int(out["agentsMaxBytes"]), out["agentsNearRatio"], int(out["agentsNearSlack"])


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def md_sections(raw):
    """`## ` 절을 [(제목, 시작 바이트, 끝 바이트)]로 돌려준다(파일 바이트 기준)."""
    marks = [(m.start(), m.group(1).decode("utf-8").strip())
             for m in re.finditer(rb"(?m)^##[ \t]+(.+)$", raw)]
    out = []
    for i, (pos, title) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(raw)
        out.append((title, pos, end))
    return out


def pick_targets(raw):
    """이관 후보를 **큰 것부터** 돌려준다(잔류 절 제외)."""
    cand = [s for s in md_sections(raw) if s[0] not in KEEP_SECTIONS]
    return sorted(cand, key=lambda s: s[2] - s[1], reverse=True)


def pick_destination(raw):
    """이관처를 결정론으로 고른다(ⓓ). 반환: (경로, 신설 여부)."""
    text = raw.decode("utf-8", "replace")
    hits = re.findall(r"`([^`\n]+\.md)`|\]\(([^)\n]+\.md)\)", text)
    order, count = [], {}
    for a, b in hits:
        p = (a or b).strip()
        if p.lower().endswith("agents.md") or p.startswith(("http://", "https://")):
            continue        # 자기 자신·외부 링크는 이관처가 아니다
        if p not in count:
            order.append(p)
        count[p] = count.get(p, 0) + 1
    if not count:
        return DEFAULT_DEST, True
    # 동수면 **먼저 등장한** 경로가 이기도록 `-index`를 키에 함께 둔다(ⓓ의 「동수면 먼저」).
    best = max(order, key=lambda p: (count[p], -order.index(p)))
    return best, False


def relocate(root, dry_run=False):
    """이관을 수행한다. 반환: (종료 코드, 보고 줄 목록)."""
    log = []
    agents = os.path.join(root, "AGENTS.md")
    if not os.path.exists(agents):
        return 1, ["[ERROR] AGENTS.md가 없다: " + agents]
    hook = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "..", "..", "scripts", "session-context.ps1")
    limit, ratio, slack = load_limit(os.path.normpath(hook))

    raw = read_bytes(agents)
    size = len(raw)
    if not (size >= limit * ratio or limit - size < slack):
        return 0, ["이관 대상 아님 — %dB / 상한 %dB (여유 %dB)" % (size, limit, limit - size)]

    targets = pick_targets(raw)
    keep_bytes = sum(e - s for t, s, e in md_sections(raw) if t in KEEP_SECTIONS)
    if not targets:
        return 0, [_MIGRATE_HINT % ("옮길 절이 없다 — 잔류 대상(%s)만 남아 있다"
                                    % ", ".join(KEEP_SECTIONS))]
    if keep_bytes >= limit:
        return 0, [_MIGRATE_HINT % ("잔류 절만으로 %dB라 상한 %dB를 넘는다 — 옮겨도 해소되지 않는다"
                                    % (keep_bytes, limit))]

    dest_rel, dest_new = pick_destination(raw)
    dest = os.path.join(root, dest_rel.replace("/", os.sep))

    # ⓕ 사본 — 이관처가 이미 있으면 그것도 함께 뜬다(원복이 한쪽만 되돌리면 반쪽이 남는다).
    stamp = datetime.date.today().isoformat()
    bdir = os.path.join(root, BACKUP_DIR, stamp)
    backups = []
    if not dry_run:
        os.makedirs(bdir, exist_ok=True)
        for p in (agents, dest):
            if os.path.exists(p):
                b = os.path.join(bdir, os.path.basename(p))
                shutil.copy2(p, b)
                backups.append((p, b))

    moved, cur = [], raw
    for title, _s, _e in targets:
        if len(cur) < limit * ratio and limit - len(cur) >= slack:
            break
        # 매 회차 현재 본문에서 경계를 다시 잡는다 — 앞 절을 옮기면 뒤 절의 오프셋이 밀린다.
        span = [s for s in md_sections(cur) if s[0] == title]
        if not span:
            continue
        _t, s0, s1 = span[0]
        block = cur[s0:s1]
        head_end = cur.index(b"\n", s0) + 1
        body = cur[head_end:s1]
        if not body.strip():
            continue
        ptr = ("\n**정본은 `%s`의 「%s」이다** — 이 절의 규정은 그 문서가 담는다.\n\n"
               % (dest_rel, title)).encode("utf-8")
        cur = cur[:head_end] + ptr + cur[s1:]
        moved.append((title, block, len(block)))

    if not moved:
        return 0, [_MIGRATE_HINT % "발동했으나 옮길 수 있는 절이 없다"]

    dest_raw = read_bytes(dest) if os.path.exists(dest) else b""
    if not dest_raw.strip():
        dest_raw = b"# AGENTS \xeb\xb3\xb4\xec\xa1\xb0 \xeb\xac\xb8\xec\x84\x9c\n\n"  # "# AGENTS 보조 문서"
    for title, block, _n in moved:
        dest_raw = dest_raw.rstrip(b"\n") + b"\n\n" + block.rstrip(b"\n") + b"\n"

    if not dry_run:
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(dest_raw)
        with open(agents, "wb") as fh:
            fh.write(cur)

    ok, problems = verify(cur, dest_raw, dest_rel, limit, raw)
    if not ok:
        if not dry_run:
            for orig, b in backups:
                shutil.copy2(b, orig)
            # 이 회차에 **신설한** 이관처는 사본이 없으므로 되돌릴 대상이 아니라 지울
            #  대상이다. 판정은 「그 파일이 백업 목록에 있는가」로 한다 — `not backups`는
            #  AGENTS.md 백업이 늘 들어가 항상 거짓이라 아무것도 지우지 못했다.
            if dest_new and not any(p == dest for p, _b in backups):
                if os.path.exists(dest):
                    os.remove(dest)
        return 1, ["[검증 실패] " + p for p in problems] + ["사본으로 원복했다: " + bdir]

    log.append("이관 전: %dB / 상한 %dB" % (size, limit))
    for title, _b, n in moved:
        log.append("옮긴 절: 「%s」 %dB → `%s`%s" % (title, n, dest_rel, " (신설)" if dest_new else ""))
    log.append("이관 후: %dB (여유 %dB)" % (len(cur), limit - len(cur)))
    log.append("되돌리려면: %s" % bdir)
    return 0, log


def verify(agents_raw, dest_raw, dest_rel, limit, orig_raw):
    """ⓖ 검증 4종. 반환: (통과 여부, 문제 목록)."""
    problems = []
    if len(agents_raw) > limit:
        problems.append("AGENTS.md가 여전히 상한을 넘는다(%dB > %dB)" % (len(agents_raw), limit))
    titles = {t for t, _s, _e in md_sections(agents_raw)}
    for k in KEEP_SECTIONS:
        if k in {t for t, _s, _e in md_sections(orig_raw)} and k not in titles:
            problems.append("잔류 절이 사라졌다: ## " + k)
    dest_titles = {t for t, _s, _e in md_sections(dest_raw)}
    text = agents_raw.decode("utf-8", "replace")
    for m in re.finditer(r"\*\*정본은 `([^`]+)`의 「([^」]+)」이다\*\*", text):
        if m.group(1) != dest_rel:
            continue        # 다른 문서를 가리키는 기존 포인터는 이 회차의 산출물이 아니다
        if m.group(2) not in dest_titles:
            problems.append("포인터가 가리키는 절이 이관처에 없다: 「%s」" % m.group(2))
    # ④ 원문 줄 수 보존 — 옮긴 것과 남은 것을 합치면 원문보다 줄이 줄지 않아야 한다.
    if agents_raw.count(b"\n") + dest_raw.count(b"\n") < orig_raw.count(b"\n"):
        problems.append("줄 수가 줄었다 — 원문 일부가 유실됐을 수 있다")
    return not problems, problems


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__.strip().splitlines()[-2])
        return 2
    code, log = relocate(args[0], "--dry-run" in sys.argv)
    print("== AGENTS.md 주입 상한 이관%s ==" % (" --dry-run" if "--dry-run" in sys.argv else ""))
    for line in log:
        print("  " + line)
    return code


if __name__ == "__main__":
    sys.exit(main())
