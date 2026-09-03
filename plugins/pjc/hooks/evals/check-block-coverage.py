#!/usr/bin/env python3
"""차단 경로 커버리지 검사 — 모든 차단 경로에 양성·델타 음성 케이스가 있는가.

무엇을 재는가: hook 스크립트의 `exit 2` 지점마다 그 직전에 나오는 차단 사유 문구를 뽑고,
골든 자산(선언형 케이스 + 시나리오 스크립트)이 그 문구를 실제로 대조하는지 본다.

왜 필요한가: 차단 hook 을 재작성할 때 어느 경로가 골든 밖으로 빠졌는지는 전건 통과로는
보이지 않는다 — 그 경로를 재는 케이스가 애초에 없으면 코드를 지워도 green 이다.

판정:
  양성      = 그 차단 문구를 ExpectContains 로 재는 케이스가 1건 이상
  델타 음성 = 같은 hook 에 exit 0(통과) 기대 케이스가 1건 이상
              — 차단이 정상 입력까지 삼키지 않음을 그 hook 안에서 보인다

exit 0 = 전건 충족, exit 1 = 미충족 있음.
"""
import json
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parents[3].parent
SCRIPTS = ROOT / 'plugins' / 'pjc' / 'scripts'
EVALS = ROOT / 'plugins' / 'pjc' / 'hooks' / 'evals'

# 차단 사유 문구를 여는 마커 — 이 뒤 문면이 케이스가 대조할 수 있는 고유 문자열이다
REASON_RX = re.compile(
    r'"(?:\[HARNESS\] )?(?:BLOCKED|\[차단\])[:\s]\s*([^"$]{6,60})'   # 직접 출력형
    r'|Deny\s+"([^"]{6,120})"'                                          # block-destructive 의 Deny 헬퍼
    r'|\.Add\("(?:\[HARNESS\] )?BLOCKED[:\s]\s*([^"$]{6,60})"'         # $lines.Add 형
    r'|"\[HARNESS\] BLOCKED[:\s]\s*([^"]{6,120})"')                      # 배열 리터럴 형(보간 포함)


def read(p):
    return p.read_text(encoding='utf-8-sig', errors='replace')


def block_paths():
    """hook 별 차단 사유 문구 목록."""
    out = {}
    for f in sorted(SCRIPTS.glob('*.ps1')):
        text = read(f)
        if 'exit 2' not in text and '-Block $true' not in text:
            continue   # dot-source 헬퍼는 exit 대신 Block=$true 로 차단을 알린다
        reasons = []
        for m in REASON_RX.finditer(text):
            s = next((g for g in m.groups() if g), '').strip().rstrip('.,·—-').strip()
            # 보간 변수를 기준으로 조각내고 **가장 긴 고정 구간**을 쓴다 — 앞부분이 짧아도
            #   뒤에 고정 문면이 있으면 그것으로 대조할 수 있다(guard-bash 의 "T$taskNum 완료 커밋인데…").
            frags = [x.strip() for x in re.split(r'\$\(|\$[A-Za-z_][A-Za-z0-9_]*', s)]
            s = max(frags, key=len) if frags else ''
            if len(s) >= 6 and s not in reasons:
                reasons.append(s)
        # 차단 호출 수 — `Deny` 헬퍼를 쓰는 파일은 그 함수 정의 안의 `exit 2` 를 빼야 이중 계수가
        #   되지 않는다(호출부는 `Deny "..."` 쪽이다).
        calls = len(re.findall(r'(?m)^\s*exit 2\s*$', text)) + len(re.findall(r'(?m)^\s*Deny\s+"', text))
        if re.search(r'(?m)^function Deny\b', text):
            calls -= 1
        if reasons:
            out[f.stem] = reasons
            if calls > len(reasons):
                out.setdefault('_partial', []).append('%s (차단 호출 %d · 사유 추출 %d)' % (f.stem, calls, len(reasons)))
        else:
            # exit 2 를 내는데 사유를 못 뽑았다 — 조용히 빠지는 것이 이 검사기가 막으려던 실패다
            out.setdefault('_unparsed', []).append(f.stem)
    return out


def golden_text():
    """골든 자산 전문 — 케이스가 어떤 문자열을 대조하는지 여기서 찾는다."""
    parts = []
    for f in list(EVALS.glob('*.ps1')) + list((EVALS / 'scenarios').glob('*.ps1')):
        parts.append(read(f))
    cases = json.loads(read(EVALS / 'hook-cases.json'))['cases']
    for c in cases:
        parts.append(str(c.get('expect_contains', '')))
    return '\n'.join(parts), cases


# dot-source 헬퍼 -> 그를 호출하는 진입점. 헬퍼는 골든이 직접 부르지 않고 진입점을 통해 돌므로
#   통과(델타 음성) 케이스도 진입점 이름으로 기록된다.
HELPER_ENTRY = {'guard-commit-secrets': 'guard-bash', 'write-gate-trivial': 'guard-write',
                'secret-patterns': 'guard-bash', 'session-end-cleanup-lib': 'session-end-cleanup',
                'session-wiki-signals': 'session-context', 'session-ledger-signal': 'session-context'}


def negative_by_hook(cases):
    """hook 별 통과(exit 0) 기대 케이스 수 — 선언형 + 시나리오."""
    counts = {}
    for c in cases:
        if int(c.get('expect_exit', 0)) == 0:
            counts[c['hook'].replace('.ps1', '')] = counts.get(c['hook'].replace('.ps1', ''), 0) + 1
    for f in (EVALS / 'scenarios').glob('*.ps1'):
        text = read(f)
        for m in re.finditer(r"Invoke-Hook '([\w-]+)\.ps1'", text):
            pass
        for m in re.finditer(r"-ExpectExit 0", text):
            pass
        # 시나리오는 hook 이름과 기대값이 서로 다른 줄에 있어 정밀 집계가 어렵다 —
        # 파일 안에 그 hook 호출과 -ExpectExit 0 이 함께 있으면 통과 케이스가 있다고 본다.
        for hook in set(re.findall(r"Invoke-Hook '([\w-]+)\.ps1'", text)):
            if '-ExpectExit 0' in text or '-ExpectSilent $true' in text:
                counts[hook] = counts.get(hook, 0) + 1
    return counts


def main():
    paths = block_paths()
    unparsed = paths.pop('_unparsed', [])
    partial = paths.pop('_partial', [])
    gtext, cases = golden_text()
    negatives = negative_by_hook(cases)

    missing_pos, missing_neg = [], []
    total = 0
    for hook, reasons in sorted(paths.items()):
        for r in reasons:
            total += 1
            if r not in gtext:
                missing_pos.append((hook, r))
        entry = HELPER_ENTRY.get(hook, hook)
        if negatives.get(hook, 0) + negatives.get(entry, 0) == 0:
            missing_neg.append(hook)

    print('== 차단 경로 커버리지 ==')
    print('차단 hook %d개 · 차단 경로 %d건' % (len(paths), total))
    for hook, reasons in sorted(paths.items()):
        entry = HELPER_ENTRY.get(hook, hook)
        n = negatives.get(hook, 0) + (negatives.get(entry, 0) if entry != hook else 0)
        via = ('' if entry == hook else ' (진입점 %s 경유)' % entry)
        print('  %-22s 경로 %d · 통과 케이스 %d%s' % (hook, len(reasons), n, via))

    if missing_pos:
        print('\n[MISSING] 양성 케이스가 없는 차단 경로:')
        for hook, r in missing_pos:
            print('  %s — "%s"' % (hook, r))
    if missing_neg:
        print('\n[MISSING] 델타 음성(통과 기대) 케이스가 없는 hook:')
        for hook in missing_neg:
            print('  %s' % hook)

    if unparsed:
        print('\n[WARN] exit 2 를 내는데 차단 사유를 뽑지 못한 파일 — 커버리지 판정 밖이다:')
        for u in unparsed:
            print('  %s' % u)

    if partial:
        print('\n[WARN] 차단 호출 수보다 뽑은 사유가 적다 — 그 차이만큼 판정 밖이다:')
        for q in partial:
            print('  %s' % q)

    bad = len(missing_pos) + len(missing_neg) + len(unparsed) + len(partial)
    print('\n결과: %s' % ('전건 충족' if bad == 0 else '미충족 %d건' % bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
