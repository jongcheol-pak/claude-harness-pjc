#!/usr/bin/env python3
"""잘린 주석 검출 — 근거 이관 스크립트가 표제를 단어 중간에서 자른 자리를 찾는다.

무엇을 재는가: scripts/*.ps1 과 evals/*.py 의 근거 인용 주석(# <표제> — 근거는
`<파일>.md` §<id> 형식, id 는 §12·§2-1·§3a 꼴)에서 세 축을 본다. rationale 경로는 `rules/`
접두가 있으면 `scripts/rules/`, 없으면 **인용한 파일과 같은 폴더**로 푼다.

  축 A (절단)    표제가 길이 상한 근처(>= MIN_CUT_LEN)이면서 종결부 없이 끝난다.
  축 B (짝)      주석의 §<id> 가 대응 rationale 에 `## §<id>` 헤딩으로 정확히 하나 있다.
  축 C (옛 형식) 헤딩 제목까지 복제하던 옛 꼴(`.md` 뒤에 「의 낫표+§」)이 남아 있지 않다.

왜 필요한가: v1.225.0 의 근거 이관이 표제를 60자에서 기계적으로 잘라
`$harnessHo`(→ `$harnessHookName`)·`우회한`(→ `우회한다`)처럼 문장으로 성립하지 않는
주석 34곳을 남겼다. 실행에는 영향이 없지만 잘린 식별자는 grep 대상이 못 되고,
남은 문면이 후속 작업을 오도한다.

축 B 가 함께 있는 이유: 주석이 가리키는 절이 사라지거나 번호가 바뀌면 근거가 끊긴다.
축 A 만 두면 그 파손이 조용히 통과한다. 번호만 대조하는 이유: 제목까지 복제하면 헤딩을
고칠 때마다 주석이 함께 바뀌어야 했다(감사 3회차 — 사용자 답).
축 C 가 있는 이유: 옛 꼴은 축 A·B 의 정규식에 걸리지 않아, 없으면 조용히 빠진다.

exit 0 = 잘림 0건 · 짝 전건 일치 · 옛 형식 0건 / 1 = 위반 있음 / 2 = `scripts/` 없음
(`evals/` 는 없어도 통과한다 — 검사기 없는 레포가 정상이다).
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'plugins' / 'karina' / 'scripts'
RULES = SCRIPTS / 'rules'
EVALS = ROOT / 'plugins' / 'karina' / 'evals'

# id 는 줄 끝이다 — `§2-1`·`§3a` 꼴이 실재한다.
#   `rules/` 접두는 선택이다 — 없으면 인용한 파일과 같은 폴더에서 찾는다(검사기 → `evals/*-rationale.md`).
CITE_RX = re.compile(r'# (.*?) — 근거는 `(rules/)?([a-z0-9\-]+\.md)` (§\d+(?:-\d+|[a-z])?)\s*$')
# 옛 꼴 — 줄 끝 앵커 없이 찾는다. 낫표와 § 를 이어 쓰지 않는 것은 이 파일 자신도 대상이라 자기 줄에 걸리지 않게 하려는 것이다.
OLD_RX = re.compile(r'근거는 `[^`]*\.md` *의 「' + '§')

# 절단 판정: 이 길이 이상인데 종결부 없이 끝나면 캡에 눌린 것으로 본다.
# 60이 관측된 캡이고, 그보다 짧게 끝난 표제는 원래 그 길이였다.
MIN_CUT_LEN = 50

# 종결부 — 한국어 종결어미·문장부호·닫는 기호. 여기서 끝나면 문장이 완결됐다고 본다.
# NOUN_TAIL 은 표제가 "…를 검사"·"…를 경고"처럼 동작명사로 끝나는 형태다. 닫힌 목록으로
# 두는 이유: `고`·`사` 를 일반 허용하면 "…하고"·"…에서" 같은 연결어미가 함께 통과한다.
# `라` 도 같은 이유로 뺐다 — "…배타적이라" 처럼 이유절이 잘린 것을 종결로 오인했다(완료 리뷰 MAJOR 3).
NOUN_TAIL = '검사|경고|수행|주입|정리|판정|처리|확인|회수|차단|비교|집계|생성|해소|보존'
TERM_RX = re.compile(r'(?:' + NOUN_TAIL + r'|다|음|것|함|요|오|안|밖|위|아래|앞|뒤|중|시|때|말|점|줄|건|개|초|배'
                     r'|[.!?)\]}»」』`\'"*:;,]|—)$')

# `====…====` 구분선은 표제가 아니라 시각 구분자다 — 종결부가 없는 것이 정상.
SEPARATOR_RX = re.compile(r'^[=\-#*]+$')


def targets():
    """인용 주석을 담을 수 있는 파일 — hook 스크립트와 검사기 둘이다."""
    out = list(sorted(SCRIPTS.glob('*.ps1')))
    if EVALS.is_dir():
        out += sorted(EVALS.glob('*.py'))
    return out


def collect():
    rows, old = [], []
    for f in targets():
        for n, line in enumerate(f.read_text(encoding='utf-8-sig').splitlines(), 1):
            if OLD_RX.search(line):
                old.append((f.name, n))
            m = CITE_RX.search(line)
            if m:
                # 접두가 있으면 `scripts/rules/`, 없으면 인용한 파일과 같은 폴더다.
                base = RULES if m.group(2) else f.parent
                rows.append((f.name, n, m.group(1), base / m.group(3), m.group(4)))
    return rows, old


def main():
    if not SCRIPTS.is_dir():
        print(f'[ANCHOR FAIL] 대상 디렉터리 없음: {SCRIPTS}')
        return 2

    rows, old = collect()
    cut = [r for r in rows
           if len(r[2]) >= MIN_CUT_LEN
           and not SEPARATOR_RX.match(r[2])
           and not TERM_RX.search(r[2])]

    mismatch = []
    for name, n, head, p, sec in rows:
        if not p.exists():
            mismatch.append((name, n, sec, f'rationale 없음: {p.name}'))
            continue
        # `## §<id>` 다음에 공백·줄 끝 — `§1` 이 `§11`·`§1-1` 헤딩에 붙지 않게 한다
        head_rx = re.compile(r'^## ' + re.escape(sec) + r'(\s|$)')
        found = sum(1 for ln in p.read_text(encoding='utf-8').splitlines() if head_rx.match(ln))
        if found != 1:
            why = f'{sec} 헤딩 없음' if not found else f'{sec} 헤딩이 {found}개'
            mismatch.append((name, n, sec, f'{p.name}에 {why}'))

    print('== 잘린 주석 검사 (절단 · 주석↔rationale 번호 짝 · 옛 형식) ==')
    tg = targets()
    n_ps1 = sum(1 for f in tg if f.suffix == '.ps1')
    print(f'근거 인용 주석 {len(rows)}건 · 대상 스크립트 {n_ps1}개 · 대상 검사기 {len(tg) - n_ps1}개')

    if cut:
        print(f'\n[FAIL] 절단 {len(cut)}건 — 표제가 {MIN_CUT_LEN}자 이상인데 종결부 없이 끝난다')
        for name, n, head, _p, _sec in cut:
            print(f'  {name}:{n}  «{head}»')
    if mismatch:
        print(f'\n[FAIL] 짝 불일치 {len(mismatch)}건')
        for name, n, sec, why in mismatch:
            print(f'  {name}:{n}  {sec} — {why}')
    if old:
        print(f'\n[FAIL] 옛 형식 {len(old)}건 — 헤딩 제목을 복제하던 꼴이다. `— 근거는 `<파일>.md` §<id>` 로 바꾼다')
        for name, n in old:
            print(f'  {name}:{n}')

    if cut or mismatch or old:
        return 1
    print('\n결과: 절단 0건 · 짝 전건 일치 · 옛 형식 0건')
    return 0


if __name__ == '__main__':
    sys.exit(main())
