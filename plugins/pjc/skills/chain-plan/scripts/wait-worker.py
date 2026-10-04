"""pjc:chain-plan 코디네이터의 워커 대기 — Bash `run_in_background` 로 띄우고 끝날 때만 코디네이터를 깨운다.

왜 따로 두는가: 코디네이터가 `check --wait` 를 9분마다 직접 돌리면 그때마다 큰 컨텍스트를 다시 읽는다
(2026-10-04 실측 — 체인 1회 폴링에 53~68턴 · 21~32M 토큰). 이 스크립트가 그 반복과 멈춤 판정을 맡고,
코디네이터는 출력 첫 줄의 지시만 따른다.

출력 — 첫 줄 `RESULT: <갈래> — <다음 행동>`, 이어 원문:
- message    `check` 가 배치를 돌려줬다(원문 JSON). ack 는 하지 않는다 — 코디네이터가 처리한 뒤 한다.
- stall      같은 화면이 체크포인트마다 이어져 `--stall` 회 연속이 됐다(화면 끝 40줄).
- error      CLI 실행 실패 · JSON 아님 · `ok: false`(원문).
- renew      `--max-ms` 를 넘겼다 — 연속 수와 마지막 화면 해시를 넘겨 다시 띄운다.
- superseded 같은 dispatch 의 새 대기가 잠금을 가져갔다. 받은 배치는 싣지 않는다 —
             Karina `check` 는 ack 전까지 같은 배치를 다시 주므로 새 대기가 받는다.

멈춤 판정: `check` 가 시한 만료(count 0)로 돌아올 때마다 `worker-read`(커서 없음 — 커서는 출처에 묶여
다른 출처로 넘기면 `source_changed` 다)로 화면을 읽고, 앞 체크포인트와 `lines` 가 같으면 연속 수를 올린다.
일하는 워커는 스피너 경과 시간이 바뀌어 같을 수 없어, 출력 없이 오래 도는 빌드도 멈춤으로 세지 않는다.

stdout 을 utf-8 로 바꾸는 것은 필수다 — 백그라운드 stdout 은 cp949 라 첫 줄의 「—」에서 죽는다(실측).
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

STALL_TAIL = 40
RAW_LIMIT = 4000


def screen_hash(lines):
    return hashlib.sha1('\n'.join(lines).encode('utf-8')).hexdigest()[:16]


def _action(kind, dispatch, streak=0, last_hash=None):
    if kind == 'message':
        return ('배치를 chain-plan 「워커 루프」 규칙대로 처리하고 ack 한 뒤 대기를 다시 띄운다 '
                '(이 배치의 deliveryId 를 이미 ack 했으면 처리하지 않고 대기만 다시 띄운다 · '
                'worker_done 이면 다시 띄우지 않고 다음 계획의 worker-start 뒤에 띄운다)')
    if kind == 'stall':
        return ('같은 화면이 체크포인트 %d회 연속이다 — worker-retain --dispatch %s 후 보고하고 멈춘다'
                % (streak, dispatch))
    if kind == 'error':
        return ('references/cli-errors.md 「오류 응답」 을 따른다 — 그 처방의 「같은 명령을 다시 실행」은 '
                '이 대기를 다시 띄우는 것이다(샌드박스 해제가 필요하면 같은 플래그로)')
    if kind == 'renew':
        return ('--max-ms 에 닿았다 — 같은 명령에 --stall-carry %d --prev-hash %s 를 더해 대기를 다시 띄운다'
                % (streak, last_hash or '-'))
    return '같은 dispatch 의 새 대기가 이어받았다 — 아무것도 하지 않는다'


def _result(kind, dispatch, body=(), **kw):
    return ['RESULT: %s — %s' % (kind, _action(kind, dispatch, **kw))] + list(body)


def _parse(raw):
    """CLI 출력을 JSON 으로 읽는다. 실패나 ok:false 면 (None, 오류 원문) 을 돌려준다."""
    try:
        data = json.loads(raw)
    except ValueError:
        return None, raw[:RAW_LIMIT]
    if not isinstance(data, dict) or data.get('ok') is not True:
        return None, raw[:RAW_LIMIT]
    return data, None


def wait_loop(call, lock, now, dispatch, timeout_ms, stall, max_ms, stall_carry, prev_hash):
    """대기 반복. call(args)->str 은 `<CLI> orchestration <args>` 의 stdout, lock.owned() 는 잠금 소유,
    now() 는 ms 단위 시계다 — 셋 다 바깥에서 넣어 골든이 Karina 없이 갈래를 잰다."""
    start = now()
    streak, last_hash = stall_carry, prev_hash
    while True:
        try:
            raw = call(['check', '--json', '--wait', '--timeout-ms', str(timeout_ms)])
        except OSError as e:
            return _result('error', dispatch, ['CLI 실행 실패: %s' % e])
        if not lock.owned():
            return _result('superseded', dispatch)
        data, err = _parse(raw)
        if err is not None:
            return _result('error', dispatch, [err])
        if data.get('count', 0) > 0:
            return _result('message', dispatch, [raw[:RAW_LIMIT * 4]])

        try:
            raw = call(['worker-read', '--json', '--dispatch', dispatch])
        except OSError as e:
            return _result('error', dispatch, ['CLI 실행 실패: %s' % e])
        if not lock.owned():
            return _result('superseded', dispatch)
        data, err = _parse(raw)
        if err is not None:
            return _result('error', dispatch, [err])
        lines = [str(l) for l in data.get('lines') or []]
        h = screen_hash(lines)
        streak = streak + 1 if h == last_hash else 0
        last_hash = h
        if streak >= stall:
            return _result('stall', dispatch, lines[-STALL_TAIL:], streak=streak)
        if now() - start >= max_ms:
            return _result('renew', dispatch, streak=streak, last_hash=last_hash)


class FileLock:
    """dispatch 마다 시스템 임시 폴더에 둔 파일 하나. 새 대기가 자기 표식을 덮어쓰면 앞 대기는 물러난다."""

    def __init__(self, dispatch):
        self.path = os.path.join(tempfile.gettempdir(), 'pjc-chain-wait-%s.lock' % dispatch)
        self.token = '%d-%d' % (os.getpid(), time.time_ns())
        with open(self.path, 'w', encoding='utf-8') as f:
            f.write(self.token)

    def owned(self):
        try:
            with open(self.path, encoding='utf-8') as f:
                return f.read() == self.token
        except OSError:
            return False

    def release(self):
        # 아직 자기 것일 때만 지운다 — 이어받은 새 대기의 잠금을 지우면 그 대기가 물러난다.
        if self.owned():
            try:
                os.remove(self.path)
            except OSError:
                pass


def make_call(cli):
    def call(args):
        # keepalive 줄이 stderr 로 15초마다 오므로 버린다. 출력에 서로게이트가 섞여 엄격 디코딩이 깨진다(실측).
        p = subprocess.run([cli, 'orchestration'] + args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return p.stdout.decode('utf-8', errors='replace')
    return call


def main(argv=None):
    sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description='chain-plan 워커 대기')
    ap.add_argument('--cli', required=True)
    ap.add_argument('--dispatch', required=True)
    ap.add_argument('--timeout-ms', type=int, default=540000)
    ap.add_argument('--stall', type=int, default=3)
    ap.add_argument('--max-ms', type=int, default=1500000)
    ap.add_argument('--stall-carry', type=int, default=0)
    ap.add_argument('--prev-hash', default=None)
    a = ap.parse_args(argv)
    lock = FileLock(a.dispatch)
    out = wait_loop(make_call(a.cli), lock, lambda: time.monotonic() * 1000,
                    dispatch=a.dispatch, timeout_ms=a.timeout_ms, stall=a.stall, max_ms=a.max_ms,
                    stall_carry=a.stall_carry, prev_hash=None if a.prev_hash in (None, '-') else a.prev_hash)
    lock.release()
    print('\n'.join(out), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
