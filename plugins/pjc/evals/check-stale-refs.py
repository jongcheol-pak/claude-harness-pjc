#!/usr/bin/env python3
"""삭제 자산 참조 검출 — 회차 1·2가 없앤 것을 살아 있는 자산이 아직 가리키는가.

무엇을 재는가: 아래 DEAD 목록의 이름을 `plugins/**`·`docs/**` 와 **레포 루트의 `*.ps1`·`*.md`** 에서
계수한다. 루트를 넣은 것은 `validate.ps1`·`install.ps1` 이 스킬·hook 이름을 배열로 담아
**이름이 죽으면 조용히 깨지는 자리**인데 종전 범위 밖이었기 때문이다(회차 22 가 지운
`bootstrap-agents-md` 가 `validate.ps1` 에, 회차 4 가 지운 같은 이름이 `install.ps1` 에
살아 있었고 검사기는 계속 exit 0 이었다).
`--ledger` 를 주면 대신 `docs/plans/deferred.md` 의 `## 대기` 구간만 본다(T9 용).

**축이 둘이다 — 트리 경로에서는 둘 다 돈다.** 위가 「죽은 이름이 살아 있는 자산에 남았는가」라면
아래 **산문 경로 축**은 반대 방향이다: `PROSE_TARGETS` 의 문서가 **백틱으로 인용한 경로가
지금도 실재하는가**. 이름 목록을 미리 적어 둘 수 없는 자리라 목록 대신 문서 본문을 모집단으로
쓴다(회차 65). 그 전까지 이 자리는 `guard-stale-docs` 층 3 이 *"어느 검사기도 재지 않는다"* 로
사람에게 넘기던 축이었다.

왜 필요한가: 회차 1이 스킬 절차를, 회차 2가 hook 을 갈아엎었는데 그 이름들이
케이스 이름·시나리오 파일명·근거 문서에 남아 있으면 그 이름으로 검색하는 다음
세션이 이미 없는 것을 현행으로 읽는다. 실행에는 영향이 없어 골든이 못 잡는다.

살아 있는 rule 이름은 DEAD 에 넣지 않는다 — `warn-external-ops`·
`require-task-checkbox`·`warn-commit-secrets`·`warn-global-find`·
`warn-dangerous-assignment` 는 `guard-bash.ps1` 이 rule 이름으로 방출한다.
표제만 보고 옛 hook 이름으로 오인하면 이 검사의 0건이 구조상 도달 불가가 된다.

exit 0 = 참조 0건 / 1 = 남아 있음 / 2 = 대상 디렉터리 없음
**산문 경로 축의 「대상 문서 부재」는 이 셋 어디에도 들지 않는다** — `[SKIP]` 1줄로 알리고
exit 에 기여하지 않는다. 「0건」(잴 것을 재서 아무것도 안 나왔다)과 「대상 없음」(잴 것 자체가
없었다)을 가르되, 이 검사기가 다른 레포·골든 픽스처에서도 돌아야 해서 앵커 실패로는 못 본다.
"""
import fnmatch
import os
import pathlib
import re
import sys
from collections import Counter

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parents[3]

DEAD = [
    # 구 스킬 2 (회차 1)
    'plan-feature', 'implement-task',
    # 구 references 3 (회차 1)
    'phase-f-detail', 'recovery.md', 'halt-conditions',
    # 구 리뷰어 6 (회차 1)
    'spec-compliance-reviewer', 'code-quality-reviewer', 'plan-completion-reviewer',
    'spec-prefilter', 'root-cause-analyzer', 'explorer',
    # 구 hook 9 (회차 2)
    'require-evidence', 'check-transcript-assumptions', 'require-plan-for-write',
    'protect-harness', 'guard-agents-content', 'bash-hook-lib',
    'orphan-process-cleanup', 'report-hook-events', 'pre-bash-dispatch',
    # 구 문서 1 (회차 1)
    'docs/prd.md',
    # 구 스킬 1 (회차 4) — 역할이 AGENTS-BOUNDARY 뼈대·pjc:plan Step 1·record-project-fact 로 나뉘었다
    'bootstrap-agents-md',
    # 구 llm-wiki 자산 2 (회차 15) — OKF 스펙 원문 사본과 신선도 축 골든 픽스처.
    #  'dashboard' 는 넣지 않는다: 살아 있는 프로젝트 이름(devdashboard-winui 등)이 오탐된다.
    'okf-spec', 'archived-fresh',
    # 구 스킬 2 (회차 22) — 스택 전용 스캐폴딩. 스택 무관분은 implement/references/code-style.md 로 옮겼고
    #  DDD 레이어 배치는 그것을 채택한 프로젝트의 AGENTS.md·위키 패턴 페이지가 받는다.
    'add-viewmodel', 'add-domain-service',
]

# DEAD **총량**의 기준선(= 목록 길이). 늘거나 줄면 불일치다 — 이 목록이 곧 검사 대상이라
#  항목이 조용히 빠지면 그 이름의 잔존이 **검출되지 않는 채 통과**한다(축이 좁아진 것과
#  전건 통과가 구분되지 않는다). 정당한 증감이면 **이 값을 함께 갱신한다** — 그 diff 가
#  목록 변경의 기록이다(`check-harness-consistency.py` 의 허용목록 기준선과 같은 형태).
DEAD_BASELINE = 26

RX = re.compile('|'.join(re.escape(d) for d in DEAD))

SKIP_DIRS = {'.git', '__pycache__', 'notes-archive', '.agents-presplit', 'node_modules'}

# 예외 — 각 줄에 사유가 붙는다. 사유 없는 예외를 만들지 않는다.
EXCEPTIONS = [
    (re.compile(r'^docs/plans/'),
     '대장 3파일은 이력이다 — 등재 당시의 대상을 그 이름으로 적는 것이 기록의 정확성이다'),
    (re.compile(r'^(plan|notes)\.md$'),
     '루트의 진행 메모·이력 — 이 스캐너는 pathlib 순회라 gitignore 를 보지 않는다(둘 다 gitignore 지만 디스크에 실재한다). '
     '지나간 회차가 그때의 대상을 이름으로 적은 것이라 갱신 대상이 아니다'),
    (re.compile(r'^plugins/pjc/evals/check-stale-refs\.py$'),
     '이 검사기 자신 — DEAD 목록이 곧 검사 대상 문자열이다'),
    (re.compile(r'^plugins/pjc/skills/llm-wiki/evals/fixtures/'),
     'lint 골든 픽스처 — 옛 스킬 이름이 테스트 입력의 일부라 바꾸면 기대값이 깨진다'),
    # 이 검사기의 골든은 **케이스 파일에 옛 이름을 적는다** — 변이 문자열이 곧 검사 대상
    #   문자열이라, 픽스처 디렉터리만 빼면 `cases.json` 이 남아 실행이 자기 골든을 잡는다.
    (re.compile(r'^plugins/pjc/evals/(fixtures/|cases\.json$)'),
     '이 검사기의 골든 — 옛 이름을 심는 것이 케이스의 입력이라 바꾸면 기대값이 깨진다'),
]
# 줄 단위 예외 — 이력 인용. **버전 태그와 제거·개명 동사가 같은 줄에 있어야** 한다.
# 버전 태그만 보면 "v1.220.0의 recovery.md 규정을 따른다" 같은 살아 있는 참조까지 통과한다.
HISTORY_RX = re.compile(r'v1\.\d{1,3}\.\d+')
HISTORY_VERB_RX = re.compile(r'제거|삭제|폐기|지웠|지운|없앴|소멸|합쳤|통폐합|개명|→\s*`?guard-|매핑은')
HISTORY_WHY = ('회차 1·2의 제거·개명 이력 — 지우면 다음 세션이 옛 이름으로 검색했을 때 '
               '무엇으로 바뀌었는지 알 길이 없다')


# --- 산문 경로 축 (회차 65) ---------------------------------------------------
# 대상은 **하나뿐**이다. 전체 `*.md` 로 넓히면 후보 706 중 미실존 191 이 나오는데(회차 65 실측)
#   그 191 은 결함이 아니라 다른 성격의 경로다 — 스킬 문서의 상대 참조(`../WIKI.md`), 위키
#   vault 경로(`20_projects/…`), lint 픽스처의 예시 소스(`src/Demo/Thing.cs`). 각각을 가르려면
#   문서 종류별 기준이 필요하고, 그것은 이 축이 아니라 별개 축이다.
# **늘릴 때는 그 문서 하나의 오탐율을 먼저 재고 10% 미만일 때만 넣는다.**
PROSE_TARGETS = ('docs/harness-conventions.md',)

# 백틱 인라인 코드 스팬. 여는·닫는 백틱이 같은 줄에 있는 것만 본다(코드 펜스는 여러 줄이라
#   이 정규식에 걸리지 않는다 — 펜스 안의 경로는 예시일 때가 많아 대상 밖인 편이 맞다).
PROSE_TOKEN_RX = re.compile(r'`([^`\n]+)`')

# 경로 후보의 문자셋. **좁히는 것이 이 축의 전부다** — 백틱 안에는 경로만이 아니라 명령 조각·
#   정규식·환경변수·설명용 리터럴이 섞여 있고, 구분자 포함만으로 거르면 미실존이 58 로 튄다
#   (회차 65 실측). 공백을 빼면 명령 조각(`python …/x.py`)과 산문 리터럴이, 백슬래시를 빼면
#   정규식(`\r\n`)이, `<>` 를 빼면 자리표시(`skills/<name>/`)가 함께 떨어져 58 → 1 이 된다.
#   남은 1 은 gitignore 된 실재 디렉터리였고 그것은 아래 인덱스가 푼다.
PROSE_PATH_CHARS = re.compile(r'^[A-Za-z0-9_.\-*/]+$')

# 인덱스에서 제외할 디렉터리. **`SKIP_DIRS` 를 재사용하지 않는다** — 그쪽은 「죽은 이름을 찾을
#   대상」이라 `notes-archive`·`.agents-presplit` 을 빼는데, 실존 판정에서는 디스크에 있으면
#   실존이다. `docs/.agents-presplit/` 은 gitignore 지만 실재하고 이 문서가 그것을 가리킨다.
PROSE_INDEX_SKIP = {'.git', '__pycache__', 'node_modules'}


def excused(rel):
    for rx, why in EXCEPTIONS:
        if rx.match(rel):
            return why
    return None


def scan_ledger():
    p = ROOT / 'docs' / 'plans' / 'deferred.md'
    text = p.read_text(encoding='utf-8')
    body = text[text.index('\n## 대기'):]
    items, cur = [], None
    for line in body.split('\n'):
        if re.match(r'^- \[\d{4}-\d{2}-\d{2}', line):
            if cur:
                items.append(cur)
            cur = line
        elif cur is not None and not line.startswith(('- ', '#', '>', '**▶')):
            cur += '\n' + line
    if cur:
        items.append(cur)
    def classify(item):
        """항목을 hit · self(검사기 자신 언급) · history(이력 표기) · None 으로 가른다.

        **면제는 항목 단위다** — 대장은 항목 1건 = 1줄이라, 줄 어디든 면제 조건이 있으면
        그 항목이 통째로 빠진다. 그래서 **한 번 면제된 항목에 나중에 다른 죽은 이름이
        섞여도 잡히지 않는다**. 그 대가를 아래 통지가 드러낸다(회차 26).
        """
        dead = [l for l in item.splitlines() if RX.search(l)]
        if not dead:
            return None
        # 이 검사기 자신을 논하는 줄은 면제한다 — DEAD 목록을 다루는 대장 항목은
        #   그 이름을 적을 수밖에 없다. 트리 경로의 「검사기 자신」 예외와 같은 성격이다.
        rest = [l for l in dead if 'check-stale-refs' not in l]
        if not rest:
            return 'self'
        # 트리 경로와 같은 규칙 — 버전 태그 + 제거·개명 동사가 같은 줄에 있으면 이력이다
        if any(not (HISTORY_RX.search(l) and HISTORY_VERB_RX.search(l)) for l in rest):
            return 'hit'
        return 'history'

    marked = [(x, classify(x)) for x in items]
    hit = [x for x, k in marked if k == 'hit']
    exempt = [(x, k) for x, k in marked if k in ('self', 'history')]
    print(f'== 대장 `## 대기` 삭제 자산 참조 ==\n대기 {len(items)}건 · 참조 {len(hit)}건')
    for x in hit:
        print(f'  {x.split(chr(10))[0][:110]}')
    if exempt:
        n_hist = sum(1 for _, k in exempt if k == 'history')
        n_self = len(exempt) - n_hist
        print(f'[NOTICE] 죽은 이름을 담았으나 면제된 항목 {len(exempt)}건 '
              f'(이력 표기 {n_hist} · 검사기 자신 {n_self}) — **면제는 항목 단위**라 '
              f'한 번 표기된 항목에 나중에 다른 죽은 이름이 섞여도 잡히지 않는다. '
              f'그래서 세어 보인다(막지는 않는다).')
        for x, k in exempt:
            print(f'  [{k}] {x.split(chr(10))[0][:100]}')
    return 1 if hit else 0


def scan_tree():
    targets = []
    # 레포 루트의 스크립트·문서 — 하위 재귀는 하지 않는다(그 트리는 아래 루프가 돈다).
    #   루트를 재귀하면 .git·node_modules 배제를 새로 관리해야 하는데 얻는 것이 없다.
    for pat in ('*.ps1', '*.md'):
        targets.extend(p for p in ROOT.glob(pat) if p.is_file())
    # `.github` 만 **선택**이다 — CI 없는 레포가 정상이라 부재를 앵커 실패로 보면
    #   이 검사기가 그 레포에서 통째로 exit 2 가 된다(골든 픽스처도 그 상태였다).
    #   `plugins`·`docs` 는 없으면 잴 것이 없다는 뜻이라 종전대로 앵커 실패다.
    for base in ('plugins', 'docs', '.github'):
        d = ROOT / base
        if not d.is_dir():
            if base == '.github':
                continue
            print(f'[ANCHOR FAIL] 대상 없음: {d}')
            return 2
        for p in d.rglob('*'):
            if not p.is_file() or p.suffix in ('.pyc', '.png', '.jpg'):
                continue
            if SKIP_DIRS & set(p.relative_to(ROOT).parts):
                continue
            targets.append(p)

    hits, excused_n = Counter(), Counter()
    for p in targets:
        rel = p.relative_to(ROOT).as_posix()
        why = excused(rel)
        try:
            text = p.read_text(encoding='utf-8-sig', errors='replace')
        except OSError:
            continue
        for line in text.split('\n'):
            n = len(RX.findall(line))
            if not n:
                continue
            if why:
                excused_n[why] += n
            elif HISTORY_RX.search(line) and HISTORY_VERB_RX.search(line):
                excused_n[HISTORY_WHY] += n
            else:
                hits[rel] += n

    print(f'== 삭제 자산 참조 검사 ==\n대상 {len(targets)}파일 · 이름 {len(DEAD)}개')
    if excused_n:
        print('\n[예외]')
        for why, n in excused_n.most_common():
            print(f'  {n:>4}건 — {why}')
    if hits:
        print(f'\n[FAIL] 살아 있는 자산에 {sum(hits.values())}건 / {len(hits)}파일')
        for rel, n in hits.most_common():
            print(f'  {n:>4}  {rel}')
        return 1
    print('\n결과: 살아 있는 자산의 삭제 자산 참조 0건')
    return 0


def build_path_index():
    """레포의 모든 파일·디렉터리를 레포 상대 posix 경로로 모은다.

    디렉터리도 넣는 것은 문서가 `docs/plans/` 처럼 디렉터리를 가리키기 때문이다.
    """
    paths = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in PROSE_INDEX_SKIP]
        rel = pathlib.Path(dirpath).relative_to(ROOT).as_posix()
        base = '' if rel == '.' else rel + '/'
        paths.extend(base + n for n in dirnames)
        paths.extend(base + n for n in filenames)
    return paths


def prose_path_rx(token):
    """경로 토큰을 인덱스에 맞출 정규식으로 바꾼다 — **접미 매치이고 글롭을 받는다**.

    이 문서는 앞 포인터가 준 앵커를 생략한 상대 표기를 상용한다(`plan/SKILL.md` 는
    `plugins/pjc/skills/plan/SKILL.md` 를 가리킨다). 완전 경로만 보면 그 표기가 전부
    오탐이라 축이 성립하지 않는다. 대가는 **동명이인**이다 — 가리키던 파일이 사라져도
    같은 접미의 다른 파일이 있으면 통과한다. 이 축이 잡으려는 것은 「대상이 통째로
    사라진 자리」라 그 대가를 받는다.
    """
    pat = fnmatch.translate(token.rstrip('/'))
    # `fnmatch.translate` 의 꼬리 앵커는 판본에 따라 `\Z`(~3.11)·`\z`(3.12~)로 갈린다.
    #   한쪽만 벗기면 남은 앵커가 접미 매치를 통째로 죽여 **모든 토큰이 미실존**이 된다.
    for tail in ('\\z', '\\Z'):
        if pat.endswith(tail):
            pat = pat[:-len(tail)]
            break
    return re.compile(r'(?:^|/)' + pat + r'(?:/|$)')


def prose_candidates(text):
    """백틱 토큰에서 경로 후보만 남긴다. 정렬·중복 제거해 출력이 실행마다 같게 한다."""
    out = []
    for t in sorted(set(PROSE_TOKEN_RX.findall(text))):
        if '/' not in t or not PROSE_PATH_CHARS.match(t):
            continue
        if t.startswith(('/', '~')):
            continue   # 홈·절대 경로는 레포 밖이라 실존을 물을 상대가 없다
        out.append(t)
    return out


def scan_prose_paths():
    """`PROSE_TARGETS` 산문의 백틱 경로가 레포에 실재하는가."""
    index = build_path_index()
    print(f'\n== 산문 경로 실존 ==\n대상 {len(PROSE_TARGETS)}문서 · 인덱스 {len(index)}건')
    total, miss = 0, []
    for rel in PROSE_TARGETS:
        p = ROOT / rel
        if not p.is_file():
            # 앵커 실패로 보지 않는다 — 다른 레포·골든 픽스처에서도 이 검사기가 돌아야 한다.
            print(f'  [SKIP] 산문 대상 없음: {rel}')
            continue
        cand = prose_candidates(p.read_text(encoding='utf-8-sig', errors='replace'))
        total += len(cand)
        gone = [t for t in cand if not any(prose_path_rx(t).search(f) for f in index)]
        print(f'  {rel} — 후보 {len(cand)}건 · 미실존 {len(gone)}건')
        miss += [(rel, t) for t in gone]
    if miss:
        print(f'\n[FAIL] 산문이 가리키는 경로가 없습니다 — {len(miss)}건')
        for rel, t in miss:
            print(f'  {rel} -> `{t}` (이동·삭제·오기 가능 — 서술을 갱신하세요)')
        return 1
    print(f'결과: 후보 {total}건 전부 실재')
    return 0


def check_baseline():
    """DEAD 총량 대조 — 두 스캔 경로가 공통으로 먼저 탄다."""
    if len(DEAD) != DEAD_BASELINE:
        print(f'[FAIL] DEAD 총량이 기준선과 다르다: {len(DEAD)} != {DEAD_BASELINE}'
              ' (DEAD_BASELINE — 정당한 증감이면 그 상수를 함께 갱신한다)')
        return 1
    return 0


def run_tree():
    """트리 경로 — 축 둘을 **둘 다 돌리고** 나쁜 쪽을 낸다.

    앞 축이 2(앵커 실패)면 거기서 멈춘다 — 대상 디렉터리가 없는 레포에서는 산문 축도
    판정 불가라, 돌려서 나오는 「0건」이 통과로 읽히면 안 된다.
    """
    rc = scan_tree()
    if rc == 2:
        return 2
    return max(rc, scan_prose_paths())


if __name__ == '__main__':
    _rc = check_baseline()
    sys.exit(_rc if _rc else (scan_ledger() if '--ledger' in sys.argv else run_tree()))
