"""chain-plan 대기 스크립트(scripts/wait-worker.py) 골든.

Karina·모델을 부르지 않는다 — CLI 호출·잠금·시계를 가짜로 주입해 갈래마다 첫 줄과 호출 인자를 잰다.
마지막 케이스 하나만 실제 프로세스로 띄워, 백그라운드 stdout 이 cp949 일 때도 RESULT 줄이 살아 나오는지 본다.
"""
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'scripts', 'wait-worker.py')

spec = importlib.util.spec_from_file_location('wait_worker', SCRIPT)
ww = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ww)


def msg_batch(n=1):
    return json.dumps({'ok': True, 'count': n, 'deliveryId': 'dlv_1',
                       'messages': [{'id': 'msg_1', 'type': 'question', 'subject': 'Q: 질문'}]})


EMPTY = json.dumps({'ok': True, 'count': 0, 'messages': [], 'deliveryId': None})


def screen(*lines):
    return json.dumps({'ok': True, 'source': 'terminal', 'count': len(lines), 'lines': list(lines),
                       'cursor': 'terminal:1'})


class FakeCli:
    """명령 종류(check·worker-read)마다 응답 열을 차례로 돌려주고, 받은 인자를 적어 둔다."""

    def __init__(self, checks, reads=()):
        self.checks = list(checks)
        self.reads = list(reads)
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        queue = self.checks if args[0] == 'check' else self.reads
        item = queue.pop(0)
        if isinstance(item, BaseException):
            raise item
        return item


class FakeLock:
    def __init__(self, owned_until=None):
        self.n = 0
        self.owned_until = owned_until  # 이 횟수만큼 owned() 가 참이고 그 뒤는 거짓

    def owned(self):
        self.n += 1
        return self.owned_until is None or self.n <= self.owned_until


class FakeClock:
    def __init__(self, step_ms):
        self.t = 0
        self.step = step_ms

    def __call__(self):
        self.t += self.step
        return self.t


def run(cli, lock=None, clock=None, **kw):
    opts = dict(dispatch='disp_1', timeout_ms=540000, stall=3, max_ms=10 ** 12, stall_carry=0, prev_hash=None)
    opts.update(kw)
    return ww.wait_loop(cli, lock or FakeLock(), clock or FakeClock(1), **opts)


def first(out):
    return out[0]


CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def message_first_check():
    cli = FakeCli([msg_batch()])
    out = run(cli)
    assert first(out).startswith('RESULT: message — '), out
    assert any('dlv_1' in l for l in out), '원문 배치가 실려야 한다'


@case
def message_after_timeouts():
    cli = FakeCli([EMPTY, EMPTY, msg_batch()], [screen('a', '1s'), screen('a', '2s')])
    out = run(cli)
    assert first(out).startswith('RESULT: message — '), out
    assert len([c for c in cli.calls if c[0] == 'worker-read']) == 2


@case
def changing_screen_never_stalls():
    reads = [screen('spin %d' % i) for i in range(6)]
    cli = FakeCli([EMPTY] * 6 + [msg_batch()], reads)
    out = run(cli)
    assert first(out).startswith('RESULT: message — '), out


@case
def same_screen_three_times_stalls():
    cli = FakeCli([EMPTY] * 4, [screen('idle')] * 4)
    out = run(cli, dispatch='disp_9')
    assert first(out).startswith('RESULT: stall — '), out
    assert 'disp_9' in first(out), 'retain 할 dispatch 를 지시에 담아야 한다'
    assert len([c for c in cli.calls if c[0] == 'worker-read']) == 4
    assert out[-1] == 'idle', '화면 끝 줄이 실려야 한다'


@case
def streak_resets_on_change():
    reads = [screen('x'), screen('x'), screen('x'), screen('y'), screen('y'), screen('y')]
    cli = FakeCli([EMPTY] * 6 + [msg_batch()], reads)
    out = run(cli)
    assert first(out).startswith('RESULT: message — '), out


@case
def check_not_ok_is_error():
    cli = FakeCli([json.dumps({'ok': False, 'code': 'protocol_error', 'error': 'x'})])
    out = run(cli)
    assert first(out).startswith('RESULT: error — '), out
    assert any('protocol_error' in l for l in out)


@case
def read_not_ok_is_error():
    cli = FakeCli([EMPTY], [json.dumps({'ok': False, 'code': 'inactive_dispatch'})])
    out = run(cli)
    assert first(out).startswith('RESULT: error — '), out
    assert any('inactive_dispatch' in l for l in out)


@case
def non_json_is_error():
    cli = FakeCli(['not json at all'])
    out = run(cli)
    assert first(out).startswith('RESULT: error — '), out
    assert any('not json' in l for l in out)


@case
def cli_launch_failure_is_error():
    cli = FakeCli([FileNotFoundError('karina-cli.exe')])
    out = run(cli)
    assert first(out).startswith('RESULT: error — '), out
    assert any('karina-cli.exe' in l for l in out)


@case
def superseded_even_with_message():
    cli = FakeCli([msg_batch()])
    out = run(cli, lock=FakeLock(owned_until=0))
    assert first(out).startswith('RESULT: superseded — '), out
    assert not any('dlv_1' in l for l in out), '물러난 대기는 배치를 싣지 않는다(ack 전이라 재배달된다)'


@case
def command_arguments():
    cli = FakeCli([EMPTY, msg_batch()], [screen('a')])
    run(cli, dispatch='disp_7', timeout_ms=1234)
    chk, rd = cli.calls[0], cli.calls[1]
    assert chk[:1] == ['check'] and '--wait' in chk and '--json' in chk, chk
    assert chk[chk.index('--timeout-ms') + 1] == '1234', chk
    assert rd[:1] == ['worker-read'] and rd[rd.index('--dispatch') + 1] == 'disp_7', rd
    assert '--cursor' not in rd and '--json' in rd, rd


@case
def every_branch_has_action_line():
    outs = [
        run(FakeCli([msg_batch()])),
        run(FakeCli([EMPTY] * 4, [screen('i')] * 4)),
        run(FakeCli(['x'])),
        run(FakeCli([msg_batch()]), lock=FakeLock(owned_until=0)),
        run(FakeCli([EMPTY], [screen('i')]), clock=FakeClock(10 ** 6), max_ms=1),
    ]
    kinds = [first(o).split(' — ')[0] for o in outs]
    assert kinds == ['RESULT: message', 'RESULT: stall', 'RESULT: error', 'RESULT: superseded', 'RESULT: renew'], kinds
    assert all(len(first(o).split(' — ', 1)[1]) > 10 for o in outs), '다음 행동 문구가 있어야 한다'


@case
def renew_after_max_ms():
    cli = FakeCli([EMPTY, EMPTY], [screen('p'), screen('p')])
    out = run(cli, clock=FakeClock(400000), max_ms=700000)
    assert first(out).startswith('RESULT: renew — '), out
    assert '--stall-carry 1' in first(out) and '--prev-hash ' in first(out), out


@case
def stall_carry_continues_streak():
    h = ww.screen_hash(['idle'])
    cli = FakeCli([EMPTY], [screen('idle')])
    out = run(cli, stall_carry=2, prev_hash=h)
    assert first(out).startswith('RESULT: stall — '), out


@case
def message_action_mentions_acked_delivery():
    out = run(FakeCli([msg_batch()]))
    assert 'ack' in first(out) and 'deliveryId' in first(out), out
    assert 'worker_done' in first(out), 'worker_done 이면 다시 띄우지 않는다는 지시'



# ── 진행 감지(task 완료마다 한 줄) ─────────────────────────────────────────

PLAN5 = '# plan\r\n\r\n### T1. 첫\r\n### T2. 둘\r\n### T3. 셋\r\n### T4. 넷\r\n### T5. 다섯\r\n'


class FakeGit:
    """`git -C <repo> <args>` 응답. log 는 호출마다 차례로 소비하고, None 이면 실패를 낸다."""

    def __init__(self, head='h0', logs=(), head_ok=True):
        self.head = head
        self.logs = list(logs)
        self.head_ok = head_ok
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        if args[0] == 'rev-parse':
            return (self.head_ok, self.head)
        item = self.logs.pop(0) if self.logs else []
        if item is None:
            return (False, 'fatal: bad revision')
        return (True, '\n'.join('%s\x1f%s' % c for c in item))


class FakeStore:
    def __init__(self, state=None):
        self.state = state
        self.saves = 0

    def load(self):
        return None if self.state is None else json.loads(json.dumps(self.state))

    def save(self, st):
        self.saves += 1
        self.state = st


def prog(git, store=None, plan=PLAN5, label='Plan 2'):
    return ww.Progress(git, lambda: plan, store if store is not None else FakeStore({'sha': 'h0', 'shown': []}), label)


def runp(cli, progress, lock=None, **kw):
    opts = dict(timeout_ms=540000, poll_ms=60000)
    opts.update(kw)
    return run(cli, lock=lock, progress=progress, **opts)


@case
def progress_line_with_next():
    git = FakeGit(logs=[[('h1', '기능: T1 — 사각형을 칠한다')]])
    out = runp(FakeCli([EMPTY]), prog(git))
    assert first(out).startswith('RESULT: progress — '), out
    assert out[1] == 'Plan 2: T1/T5 완료 — 사각형을 칠한다 · T2 시작', out


@case
def progress_last_task_has_no_start():
    git = FakeGit(logs=[[('h5', '문서: T5 — README')]])
    out = runp(FakeCli([EMPTY]), prog(git))
    assert out[1] == 'Plan 2: T5/T5 완료 — README', out


@case
def progress_two_commits_two_lines():
    git = FakeGit(logs=[[('h1', '기능: T1 — 하나'), ('h2', '수정: T2 — 둘')]])
    out = runp(FakeCli([EMPTY]), prog(git))
    assert out[1:] == ['Plan 2: T1/T5 완료 — 하나 · T2 시작', 'Plan 2: T2/T5 완료 — 둘 · T3 시작'], out


@case
def non_task_commit_updates_seen_only():
    store = FakeStore({'sha': 'h0', 'shown': []})
    git = FakeGit(logs=[[('h1', '설정: intent — 무엇')], []])
    out = runp(FakeCli([EMPTY, msg_batch()]), prog(git, store))
    assert first(out).startswith('RESULT: message — '), out
    assert store.state['sha'] == 'h1', store.state
    assert not any('완료 —' in l for l in out), out


@case
def seen_state_prevents_repeat():
    store = FakeStore({'sha': 'h1', 'shown': [1]})
    git = FakeGit(logs=[[]])
    runp(FakeCli([EMPTY, msg_batch()]), prog(git, store))
    log_calls = [c for c in git.calls if c[0] == 'log']
    assert log_calls and log_calls[0][-1] == 'h1..HEAD', git.calls


@case
def no_plan_omits_total():
    git = FakeGit(logs=[[('h3', '기능: T3 — 셋째')]])
    out = runp(FakeCli([EMPTY]), prog(git, plan=None))
    assert out[1] == 'Plan 2: T3 완료 — 셋째', out


@case
def git_failure_keeps_waiting():
    git = FakeGit(logs=[None], head_ok=False)
    out = runp(FakeCli([EMPTY, msg_batch()]), prog(git))
    assert first(out).startswith('RESULT: message — '), out


@case
def screen_read_only_after_timeout():
    cli = FakeCli([EMPTY] * 9 + [msg_batch()], [screen('a')])
    out = runp(cli, prog(FakeGit()))
    waits = [c[c.index('--timeout-ms') + 1] for c in cli.calls if c[0] == 'check']
    reads = [i for i, c in enumerate(cli.calls) if c[0] == 'worker-read']
    assert waits[:9] == ['60000'] * 9, waits
    assert reads == [9], ('9번째 check(누적 540000) 뒤에만 화면을 읽는다', cli.calls)
    assert first(out).startswith('RESULT: message — '), out


@case
def remaining_caps_wait():
    cli = FakeCli([EMPTY, EMPTY, msg_batch()], [screen('a')])
    runp(cli, prog(FakeGit()), timeout_ms=100000, poll_ms=60000)
    waits = [c[c.index('--timeout-ms') + 1] for c in cli.calls if c[0] == 'check']
    assert waits[:2] == ['60000', '40000'], waits


@case
def no_repo_no_git():
    cli = FakeCli([EMPTY, msg_batch()], [screen('a')])
    run(cli, timeout_ms=540000)
    assert [c[c.index('--timeout-ms') + 1] for c in cli.calls if c[0] == 'check'] == ['540000', '540000']
    git_made = []
    saved = (ww.make_call, ww.make_git)
    ww.make_call = lambda c: FakeCli([msg_batch()])
    ww.make_git = lambda repo: git_made.append(repo)
    try:
        ww.main(['--cli', 'x', '--dispatch', 'disp_norepo'])
    finally:
        ww.make_call, ww.make_git = saved
    assert git_made == [], 'main() 은 --repo 가 없으면 git 을 만들지 않는다'


@case
def message_carries_progress_first():
    git = FakeGit(logs=[[('h5', '기능: T5 — 마지막')]])
    out = runp(FakeCli([msg_batch()]), prog(git))
    assert first(out).startswith('RESULT: message — '), out
    assert '진행 줄' in first(out), '진행 줄을 먼저 표시하라는 지시'
    assert out[1] == 'Plan 2: T5/T5 완료 — 마지막' and 'dlv_1' in out[2], out


class SwitchLock:
    """lose() 뒤로 owned() 가 거짓 — 진행 감지(git log) 도중 새 대기가 잠금을 가져간 순간을 흉내 낸다."""

    def __init__(self):
        self.lost = False

    def owned(self):
        return not self.lost

    def lose(self):
        self.lost = True


def losing_git(lock, logs):
    git = FakeGit(logs=logs)

    def call(args):
        if args[0] == 'log':
            lock.lose()
        return git(args)
    return call


@case
def lock_lost_during_poll_does_not_save():
    lock = SwitchLock()
    store = FakeStore({'sha': 'h0', 'shown': []})
    out = runp(FakeCli([EMPTY]), prog(losing_git(lock, [[('h1', '기능: T1 — 하나')]]), store), lock=lock)
    assert first(out).startswith('RESULT: superseded — '), out
    assert store.saves == 0 and store.state['sha'] == 'h0', store.state


@case
def lock_lost_during_poll_drops_batch():
    lock = SwitchLock()
    store = FakeStore({'sha': 'h0', 'shown': []})
    out = runp(FakeCli([msg_batch()]), prog(losing_git(lock, [[('h1', '기능: T1 — 하나')]]), store), lock=lock)
    assert first(out).startswith('RESULT: superseded — '), out
    assert not any('dlv_1' in l for l in out), '물러난 대기는 배치를 싣지 않는다(새 대기가 재배달받는다)'
    assert store.saves == 0, store.state


@case
def renew_only_after_screen():
    cli = FakeCli([EMPTY] * 9 + [msg_batch()], [screen('a')])
    out = runp(cli, prog(FakeGit()), clock=FakeClock(10 ** 6), max_ms=1)
    assert first(out).startswith('RESULT: renew — '), out
    assert len([c for c in cli.calls if c[0] == 'check']) == 9, '화면 비교(9번째 check 뒤) 전에는 renew 하지 않는다'


@case
def invalid_seen_reseeds_head():
    store = FakeStore({'sha': 'gone', 'shown': []})
    git = FakeGit(head='h7', logs=[None, [('h8', '기능: T2 — 다음')]])
    out = runp(FakeCli([EMPTY, EMPTY]), prog(git, store))
    assert first(out).startswith('RESULT: progress — '), out
    log_calls = [c for c in git.calls if c[0] == 'log']
    assert log_calls[1][-1] == 'h7..HEAD', git.calls


@case
def same_task_followup_not_repeated():
    git = FakeGit(logs=[[('h1', '기능: T2 — 둘'), ('h2', '수정: T2 — 둘 보강'), ('h3', '기능: T3 — 셋')]])
    out = runp(FakeCli([EMPTY]), prog(git))
    assert out[1:] == ['Plan 2: T2/T5 완료 — 둘 · T3 시작', 'Plan 2: T3/T5 완료 — 셋 · T4 시작'], out


@case
def gapped_numbers_use_max_and_next():
    plan = '### T0. 영\n### T2. 둘\n### T5. 다섯\n'
    git = FakeGit(logs=[[('h1', '기능: T2 — 둘')]])
    out = runp(FakeCli([EMPTY]), prog(git, plan=plan))
    assert out[1] == 'Plan 2: T2/T5 완료 — 둘 · T5 시작', out


@case
def seeds_head_when_no_state():
    store = FakeStore(None)
    git = FakeGit(head='h9', logs=[[]])
    runp(FakeCli([EMPTY, msg_batch()]), prog(git, store))
    assert store.state and store.state['sha'] == 'h9', store.state


@case
def non_ascii_survives_cp949_stdout():
    env = dict(os.environ, PYTHONIOENCODING='cp949')
    p = subprocess.run([sys.executable, SCRIPT, '--cli', sys.executable, '--dispatch', 'disp_x',
                        '--timeout-ms', '10'], capture_output=True, env=env, timeout=60)
    text = p.stdout.decode('utf-8', errors='strict')
    assert p.returncode == 0, (p.returncode, p.stderr[-400:])
    assert text.startswith('RESULT: error — '), text[:200]


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    failed = 0
    for fn in CASES:
        try:
            fn()
            print('PASS', fn.__name__)
        except Exception as e:  # 케이스 하나의 실패가 나머지 판정을 막지 않게 한다
            failed += 1
            print('FAIL', fn.__name__, '-', type(e).__name__, str(e)[:300])
    print('%d/%d PASS' % (len(CASES) - failed, len(CASES)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
