"""chain-plan 대기 스크립트(scripts/wait-worker.py) 골든.

Karina·모델을 부르지 않는다 — CLI 호출·잠금·시계·git·plan 읽기·상태 저장을 가짜로 주입해 갈래마다 첫 줄과
호출 인자를 잰다(상태 파일의 원자 쓰기·읽지 못함 케이스만 임시 폴더의 실제 파일을 쓴다).
마지막 두 케이스만 실제 프로세스로 띄운다 — 중간 부모(cmd)를 죽이면 대기가 orphaned 로 스스로 끝나는지(Windows),
백그라운드 stdout 이 cp949 일 때도 RESULT 줄이 살아 나오는지 본다.
"""
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

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

    def release(self):
        pass


def run(cli, lock=None, **kw):
    opts = dict(dispatch='disp_1', timeout_ms=540000, stall=3)
    opts.update(kw)
    return ww.wait_loop(cli, lock or FakeLock(), **opts)


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
    assert any('dlv_1' in l for l in out), '배치가 실려야 한다'
    assert '사후 완료' in first(out), '사후 완료 status 도 대기를 다시 띄우지 않는 예외임을 지시에 담아야 한다'


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
def same_screen_three_screens_stalls():
    cli = FakeCli([EMPTY] * 3, [screen('idle')] * 3)
    out = run(cli, dispatch='disp_9')
    assert first(out).startswith('RESULT: stall — '), out
    assert 'disp_9' in first(out), 'retain 할 dispatch 를 지시에 담아야 한다'
    assert '직접 재개' in first(out), '멈춤 보고에 직접 재개 알림 안내를 싣게 지시해야 한다'
    assert len([c for c in cli.calls if c[0] == 'worker-read']) == 3, '첫 화면을 1장으로 센다'
    assert out[-1] == 'idle', '화면 끝 줄이 실려야 한다'


@case
def two_same_screens_do_not_stall():
    cli = FakeCli([EMPTY, EMPTY, msg_batch()], [screen('idle')] * 2)
    out = run(cli)
    assert first(out).startswith('RESULT: message — '), out


@case
def streak_resets_on_change():
    reads = [screen('x'), screen('x'), screen('y'), screen('y'), screen('z'), screen('z')]
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
        ww.place_loop(FakeCli([EMPTY], [workers()]), FakeLock(), 'disp_o', 60000),
        run(FakeCli([EMPTY, msg_batch()]), alive=lambda: False),
        run(FakeCli([EMPTY]), answer_by=5, now=lambda: 10),
    ]
    kinds = [first(o).split(' — ')[0] for o in outs]
    assert kinds == ['RESULT: message', 'RESULT: stall', 'RESULT: error', 'RESULT: superseded',
                     'RESULT: freed', 'RESULT: orphaned', 'RESULT: deadline'], kinds
    assert all(len(first(o).split(' — ', 1)[1]) > 10 for o in outs), '다음 행동 문구가 있어야 한다'


@case
def long_wait_no_renew():
    # 시한 없이 돈다 — 빈 check 와 바뀌는 화면이 이어져도 메시지가 올 때까지 RESULT 를 내지 않는다.
    reads = [screen('spin %d' % i) for i in range(10)]
    cli = FakeCli([EMPTY] * 10 + [msg_batch()], reads)
    out = run(cli)
    assert first(out).startswith('RESULT: message — '), out
    assert len([c for c in cli.calls if c[0] == 'worker-read']) == 10


@case
def removed_args_rejected():
    saved = (ww.make_call, ww.FileLock)
    ww.make_call = lambda c: FakeCli([msg_batch()])
    ww.FileLock = lambda dispatch: FakeLock()
    real_stdout, real_stderr = sys.stdout, sys.stderr
    try:
        for extra in (['--max-ms', '1'], ['--stall-carry', '1'], ['--prev-hash', 'abc']):
            sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
            sys.stderr = io.StringIO()
            try:
                ww.main(['--cli', 'x', '--dispatch', 'disp_r'] + extra)
            except SystemExit as e:
                assert e.code == 2, (extra, e.code)
            else:
                raise AssertionError('%s 를 받아들였다' % extra[0])
    finally:
        ww.make_call, ww.FileLock = saved
        sys.stdout, sys.stderr = real_stdout, real_stderr


@case
def message_action_mentions_acked_delivery():
    out = run(FakeCli([msg_batch()]))
    assert 'ack' in first(out) and 'deliveryId' in first(out), out
    assert 'worker_done' in first(out), 'worker_done 이면 다시 띄우지 않는다는 지시'


# ── 미답 시한(--answer-by — 사용자에게 넘긴 질문) ───────────────────────────────

class ClockCli(FakeCli):
    """check 마다 받은 --timeout-ms 만큼 가짜 시계를 앞으로 민다 — 실제로 기다리지 않고 시한 도달을 잰다."""

    def __init__(self, checks, reads=(), start=0.0):
        super().__init__(checks, reads)
        self.t = start

    def now(self):
        return self.t

    def __call__(self, args):
        if args[0] == 'check':
            self.t += int(args[args.index('--timeout-ms') + 1]) / 1000
        return super().__call__(args)


@case
def answer_by_reached_gives_deadline():
    cli = ClockCli([EMPTY] * 4)
    out = run(cli, answer_by=1800, now=cli.now)
    assert first(out).startswith('RESULT: deadline — '), out
    assert '미답 기본값' in first(out), out


@case
def answer_by_skips_worker_read():
    # 화면 읽기가 하나라도 일어나면 reads 가 비어 IndexError 다 — 넘긴 질문을 기다리는 워커는 화면이 그대로다.
    cli = ClockCli([EMPTY] * 4)
    out = run(cli, answer_by=240, now=cli.now, timeout_ms=60000)
    assert first(out).startswith('RESULT: deadline — '), out
    assert not [c for c in cli.calls if c[0] == 'worker-read'], cli.calls


@case
def answer_by_caps_check_wait():
    cli = ClockCli([EMPTY] * 4)
    run(cli, answer_by=1800, now=cli.now)
    waits = [c[c.index('--timeout-ms') + 1] for c in cli.calls if c[0] == 'check']
    assert waits == ['540000', '540000', '540000', '180000'], waits


@case
def answer_by_message_repeats_value():
    cli = ClockCli([EMPTY, msg_batch()])
    out = run(cli, answer_by=1792341369, now=cli.now)
    assert first(out).startswith('RESULT: message — '), out
    assert '--answer-by 1792341369' in first(out), out


@case
def answer_by_superseded_before_deadline():
    cli = ClockCli([EMPTY])
    out = run(cli, lock=FakeLock(owned_until=0), answer_by=1800, now=cli.now)
    assert first(out).startswith('RESULT: superseded — '), out


@case
def answer_by_args_rejected():
    saved = (ww.make_call, ww.FileLock)
    ww.make_call = lambda c: FakeCli([msg_batch()])
    ww.FileLock = lambda dispatch: FakeLock()
    real_stdout, real_stderr = sys.stdout, sys.stderr
    soon, far = str(int(time.time()) + 600), str(int(time.time()) + 3600)
    try:
        for extra in (['--dispatch', 'disp_a', '--answer-by', far],
                      ['--dispatch', 'disp_a', '--dispatch', 'disp_b', '--answer-by', soon],
                      ['--place', 'disp_o', '--answer-by', soon]):
            sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
            sys.stderr = io.StringIO()
            try:
                ww.main(['--cli', 'x'] + extra)
            except SystemExit as e:
                assert e.code == 2, (extra, e.code)
            else:
                raise AssertionError('%s 를 받아들였다' % extra)
        sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
        try:
            code = ww.main(['--cli', 'x', '--dispatch', 'disp_a', '--answer-by', soon])
        except SystemExit as e:
            raise AssertionError('45분 안의 --answer-by 를 거절했다 (exit %s)' % e.code)
        assert code == 0, code
    finally:
        ww.make_call, ww.FileLock = saved
        sys.stdout, sys.stderr = real_stdout, real_stderr



# ── 진행 감지(task 완료마다 한 줄) ─────────────────────────────────────────

PLAN5 = '# plan\r\n\r\n### T1. 첫\r\n### T2. 둘\r\n### T3. 셋\r\n### T4. 넷\r\n### T5. 다섯\r\n'


class FakeGit:
    """`git -C <repo> <args>` 응답. log 는 두 모드다 — `logs=` 는 호출마다 차례로 소비하고(None 이면 실패),
    `history=` 는 실제 git 처럼 기준 범위(`<sha>..HEAD`)로 답한다: log 를 k번째 부를 때 history[:k] 의 커밋이
    쌓여 있고, 기준이 `head`(시작 HEAD)면 그 전부를, 쌓인 커밋 중 하나면 그 뒤를, 어느 쪽도 아니면 실패를 낸다.
    저장하지 않은 주기에 같은 커밋이 다시 나오는 것을 흉내 내려면 history 모드를 쓴다."""

    def __init__(self, head='h0', logs=(), head_ok=True, heads=(), history=None):
        self.head = head
        self.logs = list(logs)
        self.head_ok = head_ok
        self.heads = list(heads)  # rev-parse 응답 (성공, HEAD) 를 차례로 — 다 쓰면 head_ok·head 고정값
        self.history = None if history is None else [list(h) for h in history]
        self.log_count = 0
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        if args[0] == 'rev-parse':
            if self.heads:
                return self.heads.pop(0)
            return (self.head_ok, self.head)
        if self.history is not None:
            return self._range(args[-1].split('..')[0])
        item = self.logs.pop(0) if self.logs else []
        if item is None:
            return (False, 'fatal: bad revision')
        return (True, '\n'.join('%s\x1f%s' % c for c in item))

    def _range(self, base):
        self.log_count += 1
        visible = [c for step in self.history[:self.log_count] for c in step]
        shas = [c[0] for c in visible]
        if base == self.head:
            after = visible
        elif base in shas:
            after = visible[shas.index(base) + 1:]
        else:
            return (False, 'fatal: bad revision')
        return (True, '\n'.join('%s\x1f%s' % c for c in after))


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
    out = runp(FakeCli([msg_batch()]), prog(git))
    assert first(out).startswith('RESULT: message — '), out
    assert out[1] == 'Plan 2: T1/T5 완료 — 사각형을 칠한다 · T2 시작', out


@case
def progress_last_task_has_no_start():
    git = FakeGit(logs=[[('h5', '문서: T5 — README')]])
    out = runp(FakeCli([msg_batch()]), prog(git))
    assert out[1] == 'Plan 2: T5/T5 완료 — README', out


@case
def progress_two_commits_two_lines():
    git = FakeGit(logs=[[('h1', '기능: T1 — 하나'), ('h2', '수정: T2 — 둘')]])
    out = runp(FakeCli([msg_batch()]), prog(git))
    assert out[1:3] == ['Plan 2: T1/T5 완료 — 하나 · T2 시작', 'Plan 2: T2/T5 완료 — 둘 · T3 시작'], out


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
    out = runp(FakeCli([msg_batch()]), prog(git, plan=None))
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
    saved = (ww.make_call, ww.make_git, ww.FileLock, sys.stdout)
    ww.make_call = lambda c: FakeCli([msg_batch()])
    ww.make_git = lambda repo: git_made.append(repo)
    ww.FileLock = lambda dispatch: FakeLock()
    # main() 이 stdout 을 reconfigure 하므로 StringIO 가 아니라 바이트 위의 텍스트 스트림으로 받는다.
    sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
    try:
        ww.main(['--cli', 'x', '--dispatch', 'disp_norepo'])
        sys.stdout.flush()
        printed = sys.stdout.buffer.getvalue().decode('utf-8')
    finally:
        ww.make_call, ww.make_git, ww.FileLock, sys.stdout = saved
    assert git_made == [], 'main() 은 --repo 가 없으면 git 을 만들지 않는다'
    assert printed.startswith('RESULT: message — '), printed[:200]


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
def invalid_seen_reseeds_head():
    store = FakeStore({'sha': 'gone', 'shown': []})
    git = FakeGit(head='h7', history=[[], [('h8', '기능: T2 — 다음')]])
    out = runp(FakeCli([EMPTY, EMPTY, msg_batch()]), prog(git, store))
    assert first(out).startswith('RESULT: message — '), out
    assert out[1] == 'Plan 2: T2/T5 완료 — 다음 · T3 시작', out
    log_calls = [c for c in git.calls if c[0] == 'log']
    assert log_calls[1][-1] == 'h7..HEAD', git.calls


@case
def same_task_followup_not_repeated():
    git = FakeGit(logs=[[('h1', '기능: T2 — 둘'), ('h2', '수정: T2 — 둘 보강'), ('h3', '기능: T3 — 셋')]])
    out = runp(FakeCli([msg_batch()]), prog(git))
    assert out[1:3] == ['Plan 2: T2/T5 완료 — 둘 · T3 시작', 'Plan 2: T3/T5 완료 — 셋 · T4 시작'], out
    assert sum('완료 —' in l for l in out) == 2, out


@case
def gapped_numbers_use_max_and_next():
    plan = '### T0. 영\n### T2. 둘\n### T5. 다섯\n'
    git = FakeGit(logs=[[('h1', '기능: T2 — 둘')]])
    out = runp(FakeCli([msg_batch()]), prog(git, plan=plan))
    assert out[1] == 'Plan 2: T2/T5 완료 — 둘 · T5 시작', out


@case
def seeds_head_when_no_state():
    store = FakeStore(None)
    git = FakeGit(head='h9', logs=[[]])
    runp(FakeCli([EMPTY, msg_batch()]), prog(git, store))
    assert store.state and store.state['sha'] == 'h9', store.state


@case
def head_retried_after_start_failure():
    store = FakeStore(None)
    git = FakeGit(head='h9', heads=[(False, ''), (True, 'h9')], history=[[('h10', '기능: T1 — 하나')]])
    out = runp(FakeCli([EMPTY, EMPTY, msg_batch()]), prog(git, store))
    assert first(out).startswith('RESULT: message — '), out
    assert out[1] == 'Plan 2: T1/T5 완료 — 하나 · T2 시작', out
    assert [c[-1] for c in git.calls if c[0] == 'log'] == ['h9..HEAD', 'h9..HEAD'], git.calls


@case
def number_over_total_drops_total():
    git = FakeGit(logs=[[('h7', '기능: T7 — 일곱')]])
    out = runp(FakeCli([msg_batch()]), prog(git))
    assert out[1] == 'Plan 2: T7 완료 — 일곱', out


@case
def progress_held_until_message():
    # 진행 커밋만 있는 주기는 대기를 끝내지 않는다 — 그 줄은 다음 message 원문 앞에 실린다.
    git = FakeGit(history=[[('h1', '기능: T1 — 하나')]])
    out = runp(FakeCli([EMPTY, msg_batch()]), prog(git))
    assert first(out).startswith('RESULT: message — '), out
    assert out[1] == 'Plan 2: T1/T5 완료 — 하나 · T2 시작' and 'dlv_1' in out[2], out


@case
def progress_held_on_stall():
    # 멈춤 결과에도 실린다 — 진행 줄이 먼저, 그다음 구분 줄과 화면 끝 줄이다.
    git = FakeGit(history=[[('h1', '기능: T1 — 하나')]])
    cli = FakeCli([EMPTY] * 3, [screen('idle')] * 3)
    out = runp(cli, prog(git), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: stall — '), out
    assert '진행 줄' in first(out), '멈춤 지시도 진행 줄을 먼저 표시하라고 해야 한다'
    assert out[1] == 'Plan 2: T1/T5 완료 — 하나 · T2 시작', out
    assert out[-1] == 'idle', '화면 끝 줄이 실려야 한다'


@case
def stall_reset_by_commit_each_checkpoint():
    # worker-read 화면이 고정돼도 체크포인트마다 커밋이 생기면 일하는 워커다 — 멈춤으로 세지 않는다.
    git = FakeGit(history=[[('h%d' % n, '기능: T%d — %d번' % (n, n))] for n in range(1, 5)])
    cli = FakeCli([EMPTY] * 4 + [msg_batch()], [screen('frozen')] * 4)
    out = runp(cli, prog(git), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: message — '), out


@case
def stall_after_single_commit_then_frozen():
    # 커밋 한 번은 그 비교만 되돌린다 — 진행 줄이 내보내기 전까지 남아 있어도 이후의 진짜 멈춤은 잡는다.
    git = FakeGit(history=[[], [('h1', '기능: T1 — 하나')]])
    cli = FakeCli([EMPTY] * 4, [screen('frozen')] * 4)
    out = runp(cli, prog(git), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: stall — '), out
    assert len([c for c in cli.calls if c[0] == 'worker-read']) == 4, '커밋이 난 비교에서 연속 수가 0 이어야 한다'


@case
def stall_when_git_always_fails():
    # HEAD 를 한 번도 못 보면 진행 신호가 없다 — 실패를 「달라짐」으로 세지 않아 3장째에 멈춘다.
    git = FakeGit(logs=[None] * 3, head_ok=False)
    cli = FakeCli([EMPTY] * 3, [screen('idle')] * 3)
    out = runp(cli, prog(git), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: stall — '), out
    assert len([c for c in cli.calls if c[0] == 'worker-read']) == 3, out


@case
def progress_not_saved_until_output():
    # 진행만 있던 주기는 상태를 저장하지 않는다 — 그 대기가 물러나도 새 대기가 같은 줄을 낸다.
    store = FakeStore({'sha': 'h0', 'shown': []})
    git = FakeGit(history=[[('h1', '기능: T1 — 하나')]])
    out = runp(FakeCli([EMPTY, EMPTY]), prog(git, store), lock=FakeLock(owned_until=1))
    assert first(out).startswith('RESULT: superseded — '), out
    assert store.saves == 0 and store.state == {'sha': 'h0', 'shown': []}, store.state
    out = runp(FakeCli([msg_batch()]), prog(git, store))
    assert out[1] == 'Plan 2: T1/T5 완료 — 하나 · T2 시작', out
    assert store.state == {'sha': 'h1', 'shown': [1]}, store.state


@case
def held_lines_shown_once_each():
    # 진행만 있는 주기가 둘 이어진 뒤 message 가 오면 각 줄은 정확히 한 번씩 실린다(메모리 누적 구현을 잡는다).
    git = FakeGit(history=[[('h1', '기능: T1 — 하나')], [('h2', '기능: T2 — 둘')]])
    out = runp(FakeCli([EMPTY, EMPTY, msg_batch()]), prog(git))
    assert first(out).startswith('RESULT: message — '), out
    assert out[1:3] == ['Plan 2: T1/T5 완료 — 하나 · T2 시작', 'Plan 2: T2/T5 완료 — 둘 · T3 시작'], out
    assert sum('완료 —' in l for l in out) == 2, out


@case
def sweep_removes_week_old_wait_files():
    # 7일 지난 karina-chain-wait-* 만 지운다 — 7일 이내 파일과 다른 접두 파일은 남긴다.
    d = tempfile.mkdtemp(prefix='karina-wait-eval-')
    now = 1_000_000_000.0
    files = {'karina-chain-wait-a.seen': 8, 'karina-chain-wait-b.lock': 8, 'karina-chain-wait-c.seen': 1, 'other.txt': 8}
    try:
        for name, days in files.items():
            p = os.path.join(d, name)
            with open(p, 'w', encoding='utf-8') as f:
                f.write('{}')
            os.utime(p, (now - days * 86400, now - days * 86400))
        ww.sweep_stale(d, now)
        assert sorted(os.listdir(d)) == ['karina-chain-wait-c.seen', 'other.txt'], os.listdir(d)
    finally:
        shutil.rmtree(d)


@case
def plan_read_once_per_poll():
    reads = []

    def read_plan():
        reads.append(1)
        return PLAN5
    git = FakeGit(logs=[[('h1', '기능: T1 — 하나'), ('h2', '기능: T2 — 둘')]])
    out = runp(FakeCli([msg_batch()]), ww.Progress(git, read_plan, FakeStore({'sha': 'h0', 'shown': []}), 'Plan 2'))
    assert len(out) == 4 and len(reads) == 1, (out, reads)


# ── 자리 대기(--place — 다른 세션 워커가 같은 폴더를 쥐었을 때) ──────────────────

def place_row(state, terminal, dispatch='disp_o'):
    return {'dispatchId': dispatch, 'runId': 'run_o', 'state': state, 'terminalState': terminal,
            'workingDir': 'D:\\work\\alpha', 'agentId': 'claude'}


def workers(*rows):
    return json.dumps({'ok': True, 'count': len(rows), 'workers': list(rows)})


def place(cli, lock=None):
    return ww.place_loop(cli, lock or FakeLock(), 'disp_o', 60000)


@case
def place_freed_when_row_missing():
    # 다른 dispatch 가 쥔 자리는 이 대기와 무관하다 — 지켜보는 dispatch 의 행이 없으면 빈자리다.
    out = place(FakeCli([EMPTY], [workers(place_row('ready', 'active', dispatch='disp_other'))]))
    assert first(out).startswith('RESULT: freed — '), out
    assert 'worker-start' in first(out), out


@case
def place_freed_when_stopped():
    out = place(FakeCli([EMPTY], [workers(place_row('stopped', 'active'))]))
    assert first(out).startswith('RESULT: freed — ') and 'worker-start' in first(out), out


@case
def place_freed_when_released():
    out = place(FakeCli([EMPTY], [workers(place_row('ready', 'released'))]))
    assert first(out).startswith('RESULT: freed — ') and 'worker-start' in first(out), out


@case
def place_waits_then_freed():
    cli = FakeCli([EMPTY, EMPTY], [workers(place_row('ready', 'active')), workers(place_row('stopped', 'released'))])
    out = place(cli)
    assert first(out).startswith('RESULT: freed — ') and 'worker-start' in first(out), out
    assert len([c for c in cli.calls if c[0] == 'worker-list']) == 2, cli.calls


@case
def place_holding_states_keep_waiting():
    # Karina holds_place_at 의 「쥐고 있음」 조합 — 한 번 보고 놓지 않았으면 다음 주기의 메시지에서야 끝난다.
    combos = [(s, 'active') for s in ('starting', 'ready', 'start_unknown', 'stopping', 'stop_unknown')]
    combos += [('ready', t) for t in ('reclaimable', 'retained', 'release_pending', 'release_unknown')]
    for state, terminal in combos:
        out = place(FakeCli([EMPTY, msg_batch()], [workers(place_row(state, terminal))]))
        assert first(out).startswith('RESULT: message — '), (state, terminal, out)


@case
def place_list_not_ok_is_error():
    out = place(FakeCli([EMPTY], [json.dumps({'ok': False, 'code': 'protocol_error', 'error': 'x'})]))
    assert first(out).startswith('RESULT: error — ') and '오류 응답' in first(out), out
    assert any('protocol_error' in l for l in out)


@case
def place_superseded_when_lock_lost():
    out = place(FakeCli([EMPTY], [workers()]), lock=FakeLock(owned_until=0))
    assert first(out).startswith('RESULT: superseded — '), out


@case
def place_message_passthrough():
    out = place(FakeCli([msg_batch()]))
    assert first(out).startswith('RESULT: message — ') and '--place' in first(out), out
    assert any('dlv_1' in l for l in out), '배치가 실려야 한다'


@case
def place_command_arguments():
    cli = FakeCli([EMPTY], [workers()])
    locks = []
    saved = (ww.make_call, ww.FileLock, sys.stdout)
    ww.make_call = lambda c: cli
    ww.FileLock = lambda key: locks.append(key) or FakeLock()
    sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
    try:
        try:
            ww.main(['--cli', 'x', '--place', 'disp_o'])
        except SystemExit as e:
            # SystemExit 는 Exception 이 아니라 러너의 except 를 지나 러너째 죽인다 — 실패로 바꿔 낸다.
            raise AssertionError('--place 를 거절했다 (exit %s)' % e.code)
        sys.stdout.flush()
        printed = sys.stdout.buffer.getvalue().decode('utf-8')
    finally:
        ww.make_call, ww.FileLock, sys.stdout = saved
    chk, lst = cli.calls[0], cli.calls[1]
    assert chk[:1] == ['check'] and chk[chk.index('--timeout-ms') + 1] == '60000', chk
    assert lst == ['worker-list', '--json'], lst
    assert locks == ['place-disp_o'], locks
    assert printed.startswith('RESULT: freed — '), printed[:200]


@case
def place_and_dispatch_rejected():
    real_stdout, real_stderr = sys.stdout, sys.stderr
    try:
        for args in (['--dispatch', 'disp_1', '--place', 'disp_o'], []):
            sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
            sys.stderr = io.StringIO()
            try:
                ww.main(['--cli', 'x'] + args)
            except SystemExit as e:
                assert e.code == 2, (args, e.code)
            else:
                raise AssertionError('%s 를 받아들였다' % args)
    finally:
        sys.stdout, sys.stderr = real_stdout, real_stderr


# 상태 파일 케이스만 임시 폴더의 실제 파일을 쓴다 — 원자 쓰기·읽지 못함은 파일 시스템이 재는 동작이다.

SEEN = 'karina-chain-wait-disp_t.seen'


def temp_store(content=None):
    d = tempfile.mkdtemp(prefix='karina-wait-eval-')
    st = ww.FileStore('disp_t')
    st.path = os.path.join(d, SEEN)
    if content is not None:
        with open(st.path, 'w', encoding='utf-8') as f:
            f.write(content)
    return d, st


@case
def save_survives_missing_folder():
    d, st = temp_store()
    st.path = os.path.join(d, 'no-such-folder', SEEN)
    try:
        st.save({'sha': 'h1', 'shown': []})
    finally:
        shutil.rmtree(d)


@case
def save_failure_keeps_old_file():
    d, st = temp_store('{"sha": "h0", "shown": [1]}')
    real = ww.json.dump

    def broken(obj, f, *a, **kw):
        f.write('{"sha":')
        raise OSError(28, 'No space left on device')
    ww.json.dump = broken
    try:
        st.save({'sha': 'h1', 'shown': [1, 2]})
        with open(st.path, encoding='utf-8') as f:
            assert json.load(f) == {'sha': 'h0', 'shown': [1]}, '쓰다 실패해도 앞 상태가 남는다'
        assert os.listdir(d) == [SEEN], os.listdir(d)
    finally:
        ww.json.dump = real
        shutil.rmtree(d)


@case
def save_roundtrip_leaves_no_temp():
    d, st = temp_store()
    try:
        st.save({'sha': 'h1', 'shown': [2]})
        assert st.load() == {'sha': 'h1', 'shown': [2]}, st.load()
        assert os.listdir(d) == [SEEN], os.listdir(d)
    finally:
        shutil.rmtree(d)


@case
def unreadable_state_not_reseeded():
    d, st = temp_store('{"sha":')
    try:
        assert st.load() == {}, '읽지 못함은 부재(None)와 갈린다'
        p = ww.Progress(FakeGit(head='h9'), lambda: PLAN5, st, '')
        p.start()
        assert p.poll() == [] and p.pending is None, p.pending
        with open(st.path, encoding='utf-8') as f:
            assert f.read() == '{"sha":', '읽지 못한 상태를 HEAD 로 덮어쓰지 않는다'
    finally:
        shutil.rmtree(d)


@case
def message_batch_compacted():
    # RESULT 는 배치를 다시 쓴다 — 빈 값의 키만 빼고 나머지 키는 남기며, subject·body 밖의 긴 문자열만 자른다.
    batch = json.dumps({'ok': True, 'count': 1, 'deliveryId': 'dlv_1', 'cursor': None,
                        'messages': [{'id': 'msg_1', 'type': 'worker_done', 'subject': 'S' * 300,
                                      'body': 'B' * 1000, 'extra': 'x' * 1000, 'gone': None,
                                      'empty': [], 'blank': ''}]})
    out = run(FakeCli([batch]))
    assert first(out).startswith('RESULT: message — '), out
    assert len(out) == 2 and ': ' not in out[1] and ', ' not in out[1], '공백 없는 JSON 한 줄이어야 한다'
    data = json.loads(out[1])
    m = data['messages'][0]
    assert m['body'] == 'B' * 1000 and m['subject'] == 'S' * 300, 'subject·body 는 자르지 않는다'
    assert m['extra'] == 'x' * 200 + '…(800자 생략)', m['extra'][-30:]
    assert not {'gone', 'empty', 'blank'} & set(m) and 'cursor' not in data, '빈 값의 키는 뺀다'
    assert {'id', 'type', 'subject', 'body', 'extra'} <= set(m), '값이 있는 키는 이름째 남는다'
    assert data['deliveryId'] == 'dlv_1', 'ack 에 쓸 deliveryId 를 잃으면 안 된다'


@case
def freed_rows_compacted():
    row = dict(place_row('stopped', 'active'), workingDir='D:\\' + 'w' * 300, note=None)
    out = place(FakeCli([EMPTY], [workers(row)]))
    assert first(out).startswith('RESULT: freed — '), out
    rows = json.loads(out[1])
    assert rows[0]['workingDir'] == 'D:\\' + 'w' * 197 + '…(103자 생략)', rows[0]['workingDir'][-30:]
    assert 'note' not in rows[0] and rows[0]['dispatchId'] == 'disp_o', rows[0]


# ---- 감시 사슬 · 외부 호출 시한 ----
# Git Bash 의 python 은 WindowsApps 스텁을 거쳐 `python(실) → python(스텁) → bash×3 → claude.exe` 로 뜬다(2026-10-14 실측).
#   스텁은 자식과 함께 살아 직계 부모 감시는 원리상 발화하지 않는다 — 아래 사슬 모양이 그 실측을 옮긴 것이다.

@case
def watch_skips_leading_python_stubs():
    chain = [(1, 'python.exe'), (2, 'python.exe'), (3, 'bash.exe'), (4, 'claude.exe'), (5, 'pwsh.exe')]
    assert [p for p, _ in ww.pick_watch_targets(chain)] == [3, 4]


@case
def watch_takes_shells_until_first_non_shell():
    chain = [(1, 'python.exe'), (2, 'bash.exe'), (3, 'BASH.EXE'), (4, 'cmd.exe'), (5, 'claude.exe'), (6, 'karina-daemon.exe')]
    assert [p for p, _ in ww.pick_watch_targets(chain)] == [2, 3, 4, 5]


@case
def watch_single_non_shell_parent():
    assert [p for p, _ in ww.pick_watch_targets([(9, 'claude.exe'), (8, 'pwsh.exe')])] == [9]
    assert ww.pick_watch_targets([]) == []


@case
def orphaned_ends_wait_loop():
    # 감시 대상이 사라지면 배치가 남아 있어도 기다리지 않는다 — 감시가 없으면 이 FakeCli 는 message 로 끝난다.
    out = run(FakeCli([EMPTY, msg_batch()]), alive=lambda: False)
    assert first(out).startswith('RESULT: orphaned — '), out
    assert '다시 띄운다' in first(out) and '직전 대기도 orphaned' in first(out), out


@case
def orphaned_ends_place_loop():
    cli = FakeCli([EMPTY, msg_batch()], [workers(place_row('ready', 'active'))])
    out = ww.place_loop(cli, FakeLock(), 'disp_o', 60000, alive=lambda: False)
    assert first(out).startswith('RESULT: orphaned — '), out


@case
def alive_fail_open_and_partial_handles():
    def broken_chain():
        raise OSError('snapshot')
    assert ww.make_alive(windows=True, list_chain=broken_chain) is None, '사슬 조회 실패면 감시를 끈다'
    chain = lambda: [(2, 'bash.exe'), (3, 'claude.exe')]
    assert ww.make_alive(windows=True, list_chain=chain, open_handle=lambda pid: None) is None, '하나도 못 열면 끈다'
    running = {'h3': True}
    alive = ww.make_alive(windows=True, list_chain=chain,
                          open_handle=lambda pid: 'h3' if pid == 3 else None, is_running=lambda h: running[h])
    assert alive() is True
    running['h3'] = False
    assert alive() is False, '연 핸들만으로 판정한다'


class RecordingRun:
    """subprocess.run 대역 — 받은 인자를 적고 TimeoutExpired 를 던진다. 무조건 던지기만 하면 timeout= 을 빼도
    케이스가 통과하므로 인자를 함께 단언한다."""

    def __init__(self):
        self.calls = []

    def __call__(self, cmd, **kw):
        self.calls.append((cmd, kw))
        raise subprocess.TimeoutExpired(cmd, kw.get('timeout'))


def with_run(fake, fn):
    saved = ww.subprocess.run
    ww.subprocess.run = fake
    try:
        return fn()
    finally:
        ww.subprocess.run = saved


@case
def cli_timeout_becomes_oserror():
    fake = RecordingRun()
    call = ww.make_call('karina-cli')
    for args in (['check', '--json', '--wait', '--timeout-ms', '1234'], ['worker-read', '--json', '--dispatch', 'd'],
                 ['worker-list', '--json']):
        try:
            with_run(fake, lambda: call(args))
        except OSError:
            pass
        else:
            raise AssertionError('시한 초과가 OSError 로 바뀌지 않았다: %s' % args[0])
    timeouts = [kw.get('timeout') for _, kw in fake.calls]
    assert timeouts == [1234 / 1000 + 60, 60, 60], timeouts
    assert all(kw.get('stdin') is subprocess.DEVNULL for _, kw in fake.calls), fake.calls


@case
def git_timeout_is_git_failure():
    fake = RecordingRun()
    got = with_run(fake, lambda: ww.make_git('D:/repo')(['rev-parse', 'HEAD']))
    assert got == (False, ''), got
    _, kw = fake.calls[0]
    assert kw.get('timeout') == 30 and kw.get('stdin') is subprocess.DEVNULL, kw


# ── 병렬 대기(--dispatch 여러 개) ──────────────────────────────────────────

@case
def multi_dispatch_repo_count_mismatch_rejected():
    saved = (ww.make_call, ww.FileLock)
    ww.make_call = lambda c: FakeCli([msg_batch()])
    ww.FileLock = lambda dispatch: FakeLock()
    real_stdout, real_stderr = sys.stdout, sys.stderr
    try:
        sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
        sys.stderr = io.StringIO()
        try:
            ww.main(['--cli', 'x', '--dispatch', 'disp_a', '--dispatch', 'disp_b', '--repo', 'r1'])
        except SystemExit as e:
            assert e.code == 2, e.code
        else:
            raise AssertionError('dispatch 2개에 --repo 1개를 받아들였다')
    finally:
        ww.make_call, ww.FileLock = saved
        sys.stdout, sys.stderr = real_stdout, real_stderr


@case
def multi_overlapping_set_supersedes():
    # 앞 대기가 {a, b} 를 쥐었는데 새 대기가 {b, c} 를 띄우면 b 가 넘어가 앞 대기는 물러난다.
    tag = 'multi-%d' % os.getpid()
    old = ww.AllLocks([ww.FileLock(tag + '-a'), ww.FileLock(tag + '-b')])
    assert old.owned(), '띄운 직후에는 전부 쥐고 있다'
    new = ww.AllLocks([ww.FileLock(tag + '-b'), ww.FileLock(tag + '-c')])
    try:
        assert not old.owned(), '하나라도 넘어가면 앞 대기는 소유가 아니다'
        assert new.owned()
        out = run(FakeCli([msg_batch()]), lock=old, dispatch=['disp_a', 'disp_b'])
        assert first(out).startswith('RESULT: superseded — '), out
    finally:
        new.release()
        old.release()
        for k in ('-a', '-b', '-c'):
            try:
                os.remove(os.path.join(tempfile.gettempdir(), 'karina-chain-wait-%s%s.lock' % (tag, k)))
            except OSError:
                pass


@case
def multi_worker_read_per_dispatch():
    cli = FakeCli([EMPTY, msg_batch()], [screen('a'), screen('b')])
    run(cli, dispatch=['disp_a', 'disp_b'])
    reads = [c[c.index('--dispatch') + 1] for c in cli.calls if c[0] == 'worker-read']
    assert reads == ['disp_a', 'disp_b'], reads


@case
def multi_stall_names_stalled_dispatch():
    # disp_a 는 화면이 바뀌고 disp_b 는 같은 화면 3장 — 멈춘 것은 disp_b 하나다.
    reads = []
    for i in range(3):
        reads += [screen('spin %d' % i), screen('same')]
    out = run(FakeCli([EMPTY] * 3, reads), dispatch=['disp_a', 'disp_b'])
    assert first(out).startswith('RESULT: stall — '), out
    assert 'worker-retain --dispatch disp_b' in first(out), out
    assert 'disp_a' not in first(out), out


@case
def multi_commit_resets_only_its_dispatch():
    # 둘 다 화면이 고정이고 disp_a 레포만 커밋한다 — 커밋은 자기 dispatch 만 되돌려 멈춘 것은 disp_b 다.
    ga = FakeGit(history=[[('a%d' % n, '기능: T%d — %d번' % (n, n))] for n in range(1, 4)])
    gb = FakeGit(history=[])
    cli = FakeCli([EMPTY] * 3, [screen('fa'), screen('fb')] * 3)
    out = runp(cli, [prog(ga, label='Plan 2'), prog(gb, label='Plan 3')], dispatch=['disp_a', 'disp_b'],
               timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: stall — '), out
    assert 'worker-retain --dispatch disp_b' in first(out), out
    assert 'disp_a' not in first(out), out


@case
def multi_progress_lines_from_two_repos():
    p2 = prog(FakeGit(logs=[[('h1', '기능: T1 — 사각형')]]), label='Plan 2')
    p3 = prog(FakeGit(logs=[[('k1', '기능: T2 — 원')]]), label='Plan 3')
    try:
        out = runp(FakeCli([msg_batch()]), [p2, p3], dispatch=['disp_a', 'disp_b'])
    except AttributeError as e:
        raise AssertionError('진행 감지 여러 개를 받지 못했다: %s' % e)
    assert out[1:3] == ['Plan 2: T1/T5 완료 — 사각형 · T2 시작', 'Plan 3: T2/T5 완료 — 원 · T3 시작'], out


@case
def message_action_mentions_remaining_parallel():
    out = run(FakeCli([msg_batch()]))
    assert 'parallel.md' in first(out) and '남은' in first(out), out



# ── PR 단계(`--pr <base>`) — 계획 체인 PR 모드 ──

def pr_list(state, number=7, url='https://github.com/o/r/pull/7', body=''):
    return (True, json.dumps([{'number': number, 'state': state, 'url': url, 'body': body}]))


SCREEN_BODY = '## 왜\n화면을 바꾼다\n\n## 화면\n- main.png — %TEMP%\\karina-verify\\main.png\n'


def pr_checks(*buckets):
    return (True, json.dumps([{'bucket': b} for b in buckets]))


class FakeGh:
    """`gh <args>` 응답 — `pr list` 와 `pr checks` 마다 응답 열을 차례로 돌려주고, 다 쓰면 마지막 값을 되풀이한다."""

    def __init__(self, lists=(), checks=()):
        self.lists = list(lists)
        self.checks = list(checks)
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        queue = self.lists if args[:2] == ['pr', 'list'] else self.checks
        if not queue:
            return (False, '')
        return queue.pop(0) if len(queue) > 1 else queue[0]


def branch_git(*branches):
    """`git branch --show-current` 만 답하는 대역 — 차례로 내고 다 쓰면 마지막 값을 되풀이한다."""
    seq = list(branches)

    def git(args):
        assert args[:2] == ['branch', '--show-current'], args
        return (True, seq.pop(0) if len(seq) > 1 else seq[0])
    return git


def pr_prog(gh, branches=('karina/x',), store=None, base='main'):
    stage = ww.pr_stage.PrStage(branch_git(*branches), gh, base, 'Plan 3')
    return ww.Progress(FakeGit(history=[]), lambda: PLAN5,
                       store if store is not None else FakeStore({'sha': 'h0', 'shown': []}), 'Plan 3', pr=stage)


def pr_lines(out):
    return [l for l in out if l.startswith('Plan 3: PR')]


@case
def pr_pending_checks_do_not_stall():
    # ⓐ CI 대기 중인 워커는 turn 을 끝내 화면·HEAD 가 함께 멈춘다 — pending 이면 같은 화면을 멈춤으로 세지 않는다.
    gh = FakeGh(lists=[pr_list('OPEN')], checks=[pr_checks('pass', 'pending')])
    cli = FakeCli([EMPTY] * 5 + [msg_batch()], [screen('idle')] * 5)
    out = runp(cli, pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: message — '), out


@case
def pr_checks_done_still_stalls():
    # ⓑ 체크가 다 끝났는데 화면·HEAD 가 그대로면 멈춤이다.
    gh = FakeGh(lists=[pr_list('OPEN')], checks=[pr_checks('pass', 'skipping')])
    cli = FakeCli([EMPTY] * 3, [screen('idle')] * 3)
    out = runp(cli, pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: stall — '), out


@case
def pr_stage_lines_in_order_once():
    # ⓒ 열림 → CI green → merged 를 한 번씩 차례로 낸다.
    gh = FakeGh(lists=[pr_list('OPEN'), pr_list('OPEN'), pr_list('MERGED')],
                checks=[pr_checks('pending'), pr_checks('pass')])
    reads = [screen('spin %d' % i) for i in range(3)]
    cli = FakeCli([EMPTY] * 3 + [msg_batch()], reads)
    out = runp(cli, pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert pr_lines(out) == ['Plan 3: PR #7 열림 — https://github.com/o/r/pull/7', 'Plan 3: PR #7 CI green',
                             'Plan 3: PR #7 merged'], out


@case
def pr_first_seen_merged_emits_all():
    # ⓒ merged 를 처음 본 주기에 앞 단계까지 함께 낸다 — 1분 주기 안에 열림부터 merge 까지 끝날 수 있다.
    gh = FakeGh(lists=[pr_list('MERGED')])
    out = runp(FakeCli([msg_batch()]), pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert pr_lines(out) == ['Plan 3: PR #7 열림 — https://github.com/o/r/pull/7', 'Plan 3: PR #7 CI green',
                             'Plan 3: PR #7 merged'], out


@case
def pr_screen_stage_after_green_with_marker():
    # ⓙ 본문에 `## 화면` 이 있는 OPEN PR 이 CI green 이면 화면 확인 대기 줄을 green 뒤에 낸다.
    gh = FakeGh(lists=[pr_list('OPEN', body=SCREEN_BODY)], checks=[pr_checks('pass')])
    out = runp(FakeCli([msg_batch()]), pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert pr_lines(out) == ['Plan 3: PR #7 열림 — https://github.com/o/r/pull/7', 'Plan 3: PR #7 CI green',
                             'Plan 3: PR #7 화면 확인 대기'], out


@case
def pr_screen_marker_crlf_body():
    # ⓙ 본문 줄 끝이 CRLF 여도 같은 표지로 읽는다.
    gh = FakeGh(lists=[pr_list('OPEN', body=SCREEN_BODY.replace('\n', '\r\n'))], checks=[pr_checks('pass')])
    out = runp(FakeCli([msg_batch()]), pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert 'Plan 3: PR #7 화면 확인 대기' in pr_lines(out), out


@case
def pr_screen_list_requests_body():
    # ⓙ 표지를 보려면 `gh pr list` 가 본문을 함께 받아야 한다.
    gh = FakeGh(lists=[pr_list('OPEN')], checks=[pr_checks('pass')])
    runp(FakeCli([msg_batch()]), pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    fields = [c[c.index('--json') + 1] for c in gh.calls if c[:2] == ['pr', 'list']]
    assert fields and all('body' in f.split(',') for f in fields), gh.calls


@case
def pr_screen_absent_without_marker():
    # ⓙ 음성 짝 — 표지 없는 green PR 은 화면 확인 대기 줄을 내지 않는다(`## 화면 시나리오` 같은 다른 머리도 표지가 아니다).
    gh = FakeGh(lists=[pr_list('OPEN', body='## 검증\n화면 시나리오: a · 스크린샷 a.png\n## 화면 시나리오\n')],
                checks=[pr_checks('pass')])
    out = runp(FakeCli([msg_batch()]), pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert pr_lines(out) == ['Plan 3: PR #7 열림 — https://github.com/o/r/pull/7', 'Plan 3: PR #7 CI green'], out


@case
def pr_screen_skipped_when_merged():
    # ⓙ 음성 짝 — merged 를 본 주기에는 화면 확인 대기를 내지 않는다(사용자가 이미 확인했다).
    gh = FakeGh(lists=[pr_list('MERGED', body=SCREEN_BODY)])
    out = runp(FakeCli([msg_batch()]), pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert pr_lines(out) == ['Plan 3: PR #7 열림 — https://github.com/o/r/pull/7', 'Plan 3: PR #7 CI green',
                             'Plan 3: PR #7 merged'], out


@case
def pr_branch_remembered_after_return_to_base():
    # ⓓ ship 이 merge 한 뒤 워커는 base 로 돌아온다 — 기억한 브랜치로 merged 를 낸다.
    gh = FakeGh(lists=[pr_list('OPEN'), pr_list('MERGED')], checks=[pr_checks('pending')])
    reads = [screen('spin %d' % i) for i in range(2)]
    cli = FakeCli([EMPTY] * 2 + [msg_batch()], reads)
    out = runp(cli, pr_prog(gh, branches=('karina/x', 'main')), timeout_ms=60000, poll_ms=60000)
    assert 'Plan 3: PR #7 merged' in out, out
    heads = [c[c.index('--head') + 1] for c in gh.calls if '--head' in c]
    assert heads and all(h == 'karina/x' for h in heads), gh.calls


@case
def pr_gh_failure_is_no_info():
    # ⓔ gh 실패·JSON 아님 → 단계 줄 없음, 멈춤 판정은 PR 모드가 아닐 때와 같다.
    gh = FakeGh(lists=[(False, ''), (True, 'not json')])
    cli = FakeCli([EMPTY] * 3, [screen('idle')] * 3)
    out = runp(cli, pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: stall — '), out
    assert not [l for l in out if 'PR #' in l], out


@case
def pr_flag_absent_never_calls_gh():
    # ⓕ `--pr` 없이 띄운 대기는 gh 를 만들지 않는다(ⓐ 의 음성 짝 — 구현 전에도 통과해야 한다).
    stage_mod = getattr(ww, 'pr_stage', None)
    made = []
    saved = (ww.make_call, ww.FileLock, ww.FileStore)
    ww.make_call = lambda c: FakeCli([msg_batch()])
    ww.FileLock = lambda dispatch: FakeLock()
    ww.FileStore = lambda dispatch: FakeStore({'sha': 'h0', 'shown': []})
    if stage_mod is not None:
        saved_gh = stage_mod.make_gh
        stage_mod.make_gh = lambda repo: made.append(repo) or (lambda args: (False, ''))
    real_stdout = sys.stdout
    sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
    try:
        ww.main(['--cli', 'x', '--dispatch', 'disp_np', '--repo', tempfile.gettempdir(), '--timeout-ms', '10'])
    finally:
        sys.stdout = real_stdout
        ww.make_call, ww.FileLock, ww.FileStore = saved
        if stage_mod is not None:
            stage_mod.make_gh = saved_gh
    assert made == [], made


@case
def pr_shown_stage_not_repeated_after_restart():
    # ⓖ 재기동한 대기는 상태 파일에 적힌 낸 단계를 다시 내지 않는다.
    store = FakeStore({'sha': 'h0', 'shown': [], 'pr': {'branch': 'karina/x', 'number': 7, 'shown': ['open']}})
    gh = FakeGh(lists=[pr_list('OPEN')], checks=[pr_checks('pass')])
    out = runp(FakeCli([msg_batch()]), pr_prog(gh, store=store), timeout_ms=60000, poll_ms=60000)
    assert pr_lines(out) == ['Plan 3: PR #7 CI green'], out


@case
def pr_flag_requires_repo():
    # ⓗ `--pr` 는 레포를 봐야 하므로 `--repo` 없이 받지 않는다.
    saved = (ww.make_call, ww.FileLock)
    ww.make_call = lambda c: FakeCli([msg_batch()])
    ww.FileLock = lambda dispatch: FakeLock()
    real_stdout, real_stderr = sys.stdout, sys.stderr
    sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
    sys.stderr = io.StringIO()
    try:
        ww.main(['--cli', 'x', '--dispatch', 'disp_p', '--pr', 'main'])
    except SystemExit as e:
        assert e.code == 2, e.code
        last = sys.stderr.getvalue().strip().splitlines()[-1]
        assert '--pr' in last and '--repo' in last, last
    else:
        raise AssertionError('--repo 없는 --pr 를 받아들였다')
    finally:
        ww.make_call, ww.FileLock = saved
        sys.stdout, sys.stderr = real_stdout, real_stderr


@case
def pr_gh_call_arguments():
    # ⓘ gh 는 레포 폴더에서 · stdin 없이 · stderr 를 잇지 않고 · 시한을 두고 돈다. 시한 초과는 실패로 받는다.
    fake = RecordingRun()
    gh = ww.pr_stage.make_gh('D:/repo')
    saved = ww.pr_stage.subprocess.run
    ww.pr_stage.subprocess.run = fake
    try:
        result = gh(['pr', 'list'])
    finally:
        ww.pr_stage.subprocess.run = saved
    assert result == (False, ''), result
    cmd, kw = fake.calls[0]
    assert cmd[:3] == ['gh', 'pr', 'list'], cmd
    assert kw.get('cwd') == 'D:/repo' and kw.get('timeout') and kw.get('stdin') == subprocess.DEVNULL, kw
    assert kw.get('stderr') == subprocess.DEVNULL, kw


@case
def pr_pending_too_long_stalls():
    # ⓙ pending 인 채 같은 화면이 6비교를 넘으면 다시 멈춤으로 센다 — 1장 + 6비교 + 멈춤까지 2비교 = 9장.
    gh = FakeGh(lists=[pr_list('OPEN')], checks=[pr_checks('pending')])
    cli = FakeCli([EMPTY] * 12, [screen('idle')] * 12)
    out = runp(cli, pr_prog(gh), timeout_ms=60000, poll_ms=60000)
    assert first(out).startswith('RESULT: stall — '), out
    assert len([c for c in cli.calls if c[0] == 'worker-read']) == 9, out


@case
def orphaned_when_middle_parent_killed():
    # 실제 프로세스: cmd 아래 띄운 대기에서 cmd 만 죽인다(트리 킬이 아닌 고아 상황). 가짜 CLI 는 1초 쉬고 빈 배치를
    #   돌려줘 감시가 없으면 대기가 끝나지 않는다. 끝나면 cmd 가 넘겨준 stdout 파이프가 닫혀 read 가 돌아온다.
    if os.name != 'nt':
        return
    d = tempfile.mkdtemp(prefix='karina-orphan-')
    dispatch = 'disp_orph_%d' % os.getpid()
    lock_path = os.path.join(tempfile.gettempdir(), 'karina-chain-wait-%s.lock' % dispatch)
    cli = os.path.join(d, 'fake.cmd')
    with open(cli, 'w', encoding='ascii') as f:
        f.write('@ping -n 2 localhost >nul\r\n@echo {"ok":true,"count":0,"messages":[]}\r\n')
    inner = subprocess.list2cmdline([sys.executable, SCRIPT, '--cli', cli, '--dispatch', dispatch,
                                     '--timeout-ms', '600000', '--poll-ms', '1000'])
    # cmd /c 는 따옴표가 셋 이상이면 첫·끝 따옴표를 벗겨 공백 경로가 깨진다 — /s 와 바깥 따옴표로 통째로 넘긴다.
    try:
        os.remove(lock_path)
    except OSError:
        pass
    proc = subprocess.Popen('cmd /s /c "%s"' % inner, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    got = {}
    try:
        # 잠금 파일은 감시를 세운 make_alive() 뒤에 생긴다(wait-worker.py main) — 그 전에 죽이면 고아를 못 잡는다.
        deadline = time.time() + 30
        while not os.path.exists(lock_path) and time.time() < deadline:
            time.sleep(0.2)
        assert os.path.exists(lock_path), '30초 안에 대기가 잠금을 만들지 않았다'
        proc.kill()
        reader = threading.Thread(target=lambda: got.update(out=proc.stdout.read()), daemon=True)
        reader.start()
        reader.join(15)
        assert not reader.is_alive(), 'cmd 를 죽인 뒤 15초 안에 대기가 끝나지 않았다'
        text = got['out'].decode('utf-8', errors='replace')
        assert text.startswith('RESULT: orphaned — '), text[:200]
    finally:
        # 실패 경로의 남은 대기를 거둔다 — 잠금 토큰 앞자리가 그 PID 다.
        try:
            with open(lock_path, encoding='utf-8') as f:
                os.kill(int(f.read().split('-')[0]), 9)
        except (OSError, ValueError):
            pass
        for p in (lock_path,):
            try:
                os.remove(p)
            except OSError:
                pass
        shutil.rmtree(d, ignore_errors=True)


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
