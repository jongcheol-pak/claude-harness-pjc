"""계획 체인 PR 모드의 PR 단계 감시 — `wait-worker.py --pr <base>` 가 dispatch 마다 하나씩 쓴다.

poll(st) 는 상태(`{'branch', 'number', 'shown'}` 또는 None)를 받아 (새 진행 줄, 새 상태)를 돌려주고,
그 PR 이 OPEN 이며 체크가 pending 이면 busy 를 참으로 둔다. 판정 근거는
`../references/wait-worker-rationale.md` 「PR 단계」 가 정본이다.

진행 줄(단계마다 한 줄): `<label>: PR #<n> 열림 — <url>` · `… CI green` ·
`… 화면 확인 대기`(본문에 `## 화면` 줄이 있는 OPEN·CI green PR) · `… merged`.
"""
import json
import re
import subprocess

GH_TIMEOUT_SEC = 30
DONE_BUCKETS = ('pass', 'skipping')
SCREEN_MARKER = re.compile(r'^## 화면\s*$', re.MULTILINE)
STAGE_TEXT = {'green': 'CI green', 'screen': '화면 확인 대기', 'merged': 'merged'}


def _rows(ok, out):
    if not ok:
        return None
    try:
        data = json.loads(out)
    except ValueError:
        return None
    return data if isinstance(data, list) else None


class PrStage:
    """git(args)->(성공, 출력) · gh(args)->(성공, 출력) 를 주입한다 — 골든이 git·gh 없이 단계를 잰다."""

    def __init__(self, git, gh, base, label):
        self.git, self.gh, self.base, self.label = git, gh, base, label
        self.branch = None
        self.busy = False

    def poll(self, st):
        self.busy = False
        st = dict(st or {})
        ok, cur = self.git(['branch', '--show-current'])
        if ok and cur and cur != self.base:
            self.branch = cur
        branch = self.branch or st.get('branch')
        if not branch:
            return [], st
        if branch != st.get('branch'):
            st = {'branch': branch, 'shown': []}
        rows = _rows(*self.gh(['pr', 'list', '--head', branch, '--state', 'all', '--limit', '1',
                               '--json', 'number,state,url,body']))
        if not rows or not isinstance(rows[0], dict):
            return [], st
        pr = rows[0]
        if pr.get('number') != st.get('number'):
            st = {'branch': branch, 'number': pr.get('number'), 'shown': []}
        reached = self._reached(pr)
        shown = list(st.get('shown') or [])
        lines = []
        for stage in reached:
            if stage not in shown:
                shown.append(stage)
                lines.append(self._line(pr, stage))
        st['shown'] = shown
        return lines, st

    def _reached(self, pr):
        if pr.get('state') == 'MERGED':
            return ('open', 'green', 'merged')
        if pr.get('state') != 'OPEN':
            return ('open',)
        buckets = [r.get('bucket') for r in _rows(*self.gh(['pr', 'checks', str(pr.get('number')),
                                                              '--json', 'bucket'])) or [] if isinstance(r, dict)]
        self.busy = 'pending' in buckets
        if not (buckets and all(b in DONE_BUCKETS for b in buckets)):
            return ('open',)
        if SCREEN_MARKER.search(pr.get('body') or ''):
            return ('open', 'green', 'screen')
        return ('open', 'green')

    def _line(self, pr, stage):
        head = '%s: ' % self.label if self.label else ''
        if stage == 'open':
            return '%sPR #%s 열림 — %s' % (head, pr.get('number'), pr.get('url'))
        return '%sPR #%s %s' % (head, pr.get('number'), STAGE_TEXT[stage])


def make_gh(repo):
    def gh(args):
        # `gh pr checks` 는 pending 이면 exit 8 이라 종료 코드가 아니라 출력으로 가른다 — 출력이 JSON 목록이면 성공으로 넘긴다.
        try:
            p = subprocess.run(['gh'] + args, cwd=repo, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, timeout=GH_TIMEOUT_SEC)
        except (OSError, subprocess.TimeoutExpired):
            return False, ''
        out = p.stdout.decode('utf-8', errors='replace').strip()
        return p.returncode == 0 or out.startswith('['), out
    return gh
