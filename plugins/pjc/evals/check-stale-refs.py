#!/usr/bin/env python3
"""삭제 자산 참조 검출 — 회차 1·2가 없앤 것을 살아 있는 자산이 아직 가리키는가.

무엇을 재는가: 아래 DEAD 24개 이름을 `plugins/**`·`docs/*.md` 에서 계수한다.
`--ledger` 를 주면 대신 `docs/plans/deferred.md` 의 `## 대기` 구간만 본다(T9 용).

왜 필요한가: 회차 1이 스킬 절차를, 회차 2가 hook 을 갈아엎었는데 그 이름들이
케이스 이름·시나리오 파일명·근거 문서에 남아 있으면 그 이름으로 검색하는 다음
세션이 이미 없는 것을 현행으로 읽는다. 실행에는 영향이 없어 골든이 못 잡는다.

살아 있는 rule 이름은 DEAD 에 넣지 않는다 — `warn-external-ops`·
`require-task-checkbox`·`warn-commit-secrets`·`warn-global-find`·
`warn-dangerous-assignment` 는 `guard-bash.ps1` 이 rule 이름으로 방출한다.
표제만 보고 옛 hook 이름으로 오인하면 이 검사의 0건이 구조상 도달 불가가 된다.

exit 0 = 참조 0건 / 1 = 남아 있음 / 2 = 대상 디렉터리 없음
"""
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
]
RX = re.compile('|'.join(re.escape(d) for d in DEAD))

SKIP_DIRS = {'.git', '__pycache__', 'notes-archive', '.agents-presplit', 'node_modules'}

# 예외 — 각 줄에 사유가 붙는다. 사유 없는 예외를 만들지 않는다.
EXCEPTIONS = [
    (re.compile(r'^docs/plans/'),
     '대장 3파일은 이력이다 — 등재 당시의 대상을 그 이름으로 적는 것이 기록의 정확성이다'),
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
    def live(item):
        # 트리 경로와 같은 규칙 — 버전 태그 + 제거·개명 동사가 같은 줄에 있으면 이력이다
        # 이 검사기 자신을 논하는 줄도 면제한다 — DEAD 목록을 다루는 대장 항목은
        #   그 이름을 적을 수밖에 없다. 트리 경로의 「검사기 자신」 예외와 같은 성격이다.
        return [l for l in item.splitlines()
                if RX.search(l)
                and 'check-stale-refs' not in l
                and not (HISTORY_RX.search(l) and HISTORY_VERB_RX.search(l))]

    hit = [x for x in items if live(x)]
    print(f'== 대장 `## 대기` 삭제 자산 참조 ==\n대기 {len(items)}건 · 참조 {len(hit)}건')
    for x in hit:
        print(f'  {x.split(chr(10))[0][:110]}')
    return 1 if hit else 0


def scan_tree():
    targets = []
    for base in ('plugins', 'docs'):
        d = ROOT / base
        if not d.is_dir():
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


if __name__ == '__main__':
    sys.exit(scan_ledger() if '--ledger' in sys.argv else scan_tree())
