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
- progress   워커가 task 를 끝냈다(`--repo` 를 줬을 때만) — 표시할 줄 `<label>: T<N>/T<M> 완료 — <무엇을> · T<다음> 시작`.
             message 와 같은 주기에 오면 그 줄을 message 원문 앞에 싣는다 — worker_done 뒤에는 대기를 다시
             띄우지 않아, 따로 내면 마지막 task 줄이 사라진다.

멈춤 판정: `check` 가 시한 만료(count 0)로 돌아올 때마다 `worker-read`(커서 없음 — 커서는 출처에 묶여
다른 출처로 넘기면 `source_changed` 다)로 화면을 읽고, 앞 체크포인트와 `lines` 가 같으면 연속 수를 올린다.
일하는 워커는 스피너 경과 시간이 바뀌어 같을 수 없어, 출력 없이 오래 도는 빌드도 멈춤으로 세지 않는다.
화면 비교까지 남은 대기를 시계가 아니라 차감으로 센다 — `check` 시한은 min(--poll-ms, 남은 대기)이고
남은 대기가 0 이 된 주기에만 화면을 읽는다. renew 판정도 화면 비교 뒤에만 한다(비교 간격을 9분으로 지킨다).

진행 감지: 주기마다 `git -C <repo> log <본 sha>..HEAD` 에서 제목이 `<유형>: T<N> — <무엇을>`
(implement 「커밋」 형식)인 커밋을 고른다. 분모는 `<repo>/plan.md` 의 `### T<N>.` 번호 최댓값(implement 의
`T<N>/T<M>` 과 같은 정의)이고 다음 시작은 N 보다 큰 최소 번호다. 본 sha 와 표시한 번호는 dispatch 별
상태 파일에 두어 재기동해도 같은 커밋·같은 task 의 후속 커밋(「수정: T2」)을 다시 표시하지 않는다.
잠금을 잃은 대기는 상태를 쓰지 않는다. git 실패는 대기를 끊지 않고, 본 sha 가 무효하면 HEAD 로 다시 채운다.

stdout 을 utf-8 로 바꾸는 것은 필수다 — 백그라운드 stdout 은 cp949 라 첫 줄의 「—」에서 죽는다(실측).
"""
import argparse
import hashlib
import json
import os
import re
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
        return ('앞에 진행 줄이 있으면 먼저 그대로 한 줄씩 표시하고, 배치를 chain-plan 「워커 루프」 규칙대로 '
                '처리하고 ack 한 뒤 대기를 다시 띄운다 (이 배치의 deliveryId 를 이미 ack 했으면 처리하지 않고 대기만 다시 띄운다 · '
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
    if kind == 'progress':
        return '아래 줄을 그대로 한 줄씩 표시하고 대기를 다시 띄운다'
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


def wait_loop(call, lock, now, dispatch, timeout_ms, stall, max_ms, stall_carry, prev_hash,
              poll_ms=None, progress=None):
    """대기 반복. call(args)->str 은 `<CLI> orchestration <args>` 의 stdout, lock.owned() 는 잠금 소유,
    now() 는 ms 단위 시계, progress 는 진행 감지(Progress — 없으면 끈다)다 — 바깥에서 넣어 골든이
    Karina·git 없이 갈래를 잰다. poll_ms 가 없으면 timeout_ms 와 같아 종전처럼 주기마다 화면을 읽는다."""
    start = now()
    streak, last_hash = stall_carry, prev_hash
    poll = poll_ms or timeout_ms
    remaining = timeout_ms
    if progress is not None:
        progress.start()
    while True:
        wait = min(poll, remaining)
        try:
            raw = call(['check', '--json', '--wait', '--timeout-ms', str(wait)])
        except OSError as e:
            return _result('error', dispatch, ['CLI 실행 실패: %s' % e])
        if not lock.owned():
            return _result('superseded', dispatch)
        data, err = _parse(raw)
        if err is not None:
            return _result('error', dispatch, [err])
        lines_done = progress.poll() if progress is not None else []
        if data.get('count', 0) > 0:
            if progress is not None and lock.owned():
                progress.commit()
            return _result('message', dispatch, lines_done + [raw[:RAW_LIMIT * 4]])
        if progress is not None:
            if not lock.owned():
                return _result('superseded', dispatch)
            progress.commit()
            if lines_done:
                return _result('progress', dispatch, lines_done)
        remaining -= wait
        if remaining > 0:
            continue
        remaining = timeout_ms

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


TASK_COMMIT = re.compile(r'^(기능|수정|리팩토링|문서|설정): T(\d+) — (.+)$')
PLAN_TASK = re.compile(r'^### T(\d+)\. ', re.M)


class Progress:
    """task 완료 커밋을 표시 줄로 바꾼다. git(args)->(성공, 출력) · read_plan()->str|None · store(load/save) 는 주입한다."""

    def __init__(self, git, read_plan, store, label):
        self.git, self.read_plan, self.store, self.label = git, read_plan, store, label
        self.pending = None

    def start(self):
        if self.store.load() is None:
            ok, head = self.git(['rev-parse', 'HEAD'])
            if ok and head:
                self.store.save({'sha': head, 'shown': []})

    def poll(self):
        """새 진행 줄을 돌려주고 갱신할 상태를 pending 에 둔다 — 저장은 commit() 이 한다(잠금 확인 뒤)."""
        self.pending = None
        st = self.store.load()
        if not st or not st.get('sha'):
            return []
        shown = list(st.get('shown') or [])
        ok, out = self.git(['log', '--reverse', '--format=%H%x1f%s', '%s..HEAD' % st['sha']])
        if not ok:
            ok, head = self.git(['rev-parse', 'HEAD'])
            if ok and head:
                self.pending = {'sha': head, 'shown': shown}
            return []
        done, last = [], st['sha']
        for row in out.splitlines():
            sha, _, subject = row.partition('\x1f')
            if not sha:
                continue
            last = sha
            m = TASK_COMMIT.match(subject.strip())
            if not m or int(m.group(2)) in shown:
                continue
            shown.append(int(m.group(2)))
            done.append(self._line(int(m.group(2)), m.group(3).strip()))
        self.pending = {'sha': last, 'shown': shown}
        return done

    def commit(self):
        if self.pending is not None:
            self.store.save(self.pending)
            self.pending = None

    def _line(self, n, what):
        head = '%s: ' % self.label if self.label else ''
        nums = sorted({int(x) for x in PLAN_TASK.findall(self.read_plan() or '')})
        if not nums:
            return '%sT%d 완료 — %s' % (head, n, what)
        nxt = [k for k in nums if k > n]
        tail = ' · T%d 시작' % nxt[0] if nxt else ''
        return '%sT%d/T%d 완료 — %s%s' % (head, n, nums[-1], what, tail)


class FileStore:
    """dispatch 별 상태 파일(JSON). 대기가 task 마다 재기동돼 지울 시점이 없고 크기가 작아 지우지 않는다."""

    def __init__(self, dispatch):
        self.path = os.path.join(tempfile.gettempdir(), 'pjc-chain-wait-%s.seen' % dispatch)

    def load(self):
        try:
            with open(self.path, encoding='utf-8') as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def save(self, st):
        with open(self.path, 'w', encoding='utf-8') as f:
            json.dump(st, f)


def make_git(repo):
    def git(args):
        try:
            p = subprocess.run(['git', '-C', repo] + args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError:
            return False, ''
        return p.returncode == 0, p.stdout.decode('utf-8', errors='replace').strip()
    return git


def make_read_plan(repo):
    def read_plan():
        try:
            with open(os.path.join(repo, 'plan.md'), encoding='utf-8', errors='replace') as f:
                return f.read()
        except OSError:
            return None
    return read_plan


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
    ap.add_argument('--repo', default=None)
    ap.add_argument('--label', default='')
    ap.add_argument('--poll-ms', type=int, default=None)
    a = ap.parse_args(argv)
    progress = None
    poll_ms = a.poll_ms
    if a.repo:
        progress = Progress(make_git(a.repo), make_read_plan(a.repo), FileStore(a.dispatch), a.label)
        poll_ms = poll_ms or 60000
    lock = FileLock(a.dispatch)
    out = wait_loop(make_call(a.cli), lock, lambda: time.monotonic() * 1000,
                    dispatch=a.dispatch, timeout_ms=a.timeout_ms, stall=a.stall, max_ms=a.max_ms,
                    stall_carry=a.stall_carry, prev_hash=None if a.prev_hash in (None, '-') else a.prev_hash,
                    poll_ms=poll_ms, progress=progress)
    lock.release()
    print('\n'.join(out), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
