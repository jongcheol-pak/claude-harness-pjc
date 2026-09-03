#!/usr/bin/env python3
"""잘린 주석 검출 — 근거 이관 스크립트가 표제를 단어 중간에서 자른 자리를 찾는다.

무엇을 재는가: scripts/*.ps1 의 근거 인용 주석(# <표제> - 근거는 rules/<파일>.md 의
「§N <표제>」 형식)에서 두 축을 본다.

  축 A (절단)   표제가 길이 상한 근처(>= MIN_CUT_LEN)이면서 종결부 없이 끝난다.
  축 B (짝)     주석의 「§N …」 인용이 대응 rationale 의 `## §N …` 헤딩과 글자 그대로 같다.

왜 필요한가: v1.225.0 의 근거 이관이 표제를 60자에서 기계적으로 잘라
`$harnessHo`(→ `$harnessHookName`)·`우회한`(→ `우회한다`)처럼 문장으로 성립하지 않는
주석 34곳을 남겼다. 실행에는 영향이 없지만 잘린 식별자는 grep 대상이 못 되고,
남은 문면이 후속 작업을 오도한다.

축 B 가 함께 있는 이유: 주석과 rationale 헤딩은 같은 문자열을 공유하므로 한쪽만
고치면 짝이 깨진다. 축 A 만 두면 그 파손이 조용히 통과한다.

exit 0 = 잘림 0건이고 짝도 전건 일치 / 1 = 위반 있음 / 2 = 대상 디렉터리 없음
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'plugins' / 'pjc' / 'scripts'
RULES = SCRIPTS / 'rules'

CITE_RX = re.compile(r'# (.*?) — 근거는 `rules/([a-z\-]+\.md)`의 「(§\d+ .*?)」')

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


def collect():
    rows = []
    for f in sorted(SCRIPTS.glob('*.ps1')):
        for n, line in enumerate(f.read_text(encoding='utf-8-sig').splitlines(), 1):
            m = CITE_RX.search(line)
            if m:
                rows.append((f.name, n, m.group(1), m.group(2), m.group(3)))
    return rows


def main():
    if not SCRIPTS.is_dir():
        print(f'[ANCHOR FAIL] 대상 디렉터리 없음: {SCRIPTS}')
        return 2

    rows = collect()
    cut = [r for r in rows
           if len(r[2]) >= MIN_CUT_LEN
           and not SEPARATOR_RX.match(r[2])
           and not TERM_RX.search(r[2])]

    mismatch = []
    for name, n, head, rf, sec in rows:
        p = RULES / rf
        if not p.exists():
            mismatch.append((name, n, sec, f'rationale 없음: rules/{rf}'))
            continue
        if ('## ' + sec) not in p.read_text(encoding='utf-8'):
            mismatch.append((name, n, sec, f'rules/{rf}에 대응 헤딩 없음'))

    print('== 잘린 주석 검사 (절단 · 주석↔rationale 헤딩 짝) ==')
    print(f'근거 인용 주석 {len(rows)}건 · 대상 스크립트 {len(list(SCRIPTS.glob("*.ps1")))}개')

    if cut:
        print(f'\n[FAIL] 절단 {len(cut)}건 — 표제가 {MIN_CUT_LEN}자 이상인데 종결부 없이 끝난다')
        for name, n, head, _rf, _sec in cut:
            print(f'  {name}:{n}  «{head}»')
    if mismatch:
        print(f'\n[FAIL] 짝 불일치 {len(mismatch)}건')
        for name, n, sec, why in mismatch:
            print(f'  {name}:{n}  「{sec}」 — {why}')

    if cut or mismatch:
        return 1
    print('\n결과: 절단 0건 · 짝 전건 일치')
    return 0


if __name__ == '__main__':
    sys.exit(main())
