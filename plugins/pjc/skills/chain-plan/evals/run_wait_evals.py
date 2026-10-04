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
