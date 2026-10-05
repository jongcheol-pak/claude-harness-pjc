"""pjc:chain-plan 코디네이터의 워커 대기 — Bash `run_in_background` 로 띄우고 끝날 때만 코디네이터를 깨운다.

왜 따로 두는가: 코디네이터가 `check --wait` 를 9분마다 직접 돌리면 그때마다 큰 컨텍스트를 다시 읽는다
(2026-10-04 실측 — 체인 1회 폴링에 53~68턴 · 21~32M 토큰). 이 스크립트가 그 반복과 멈춤 판정을 맡고,
코디네이터는 출력 첫 줄의 지시만 따른다.

출력 — 첫 줄 `RESULT: <갈래> — <다음 행동>`, 이어 원문:
- message    `check` 가 배치를 돌려줬다(원문 JSON). ack 는 하지 않는다 — 코디네이터가 처리한 뒤 한다.
- stall      같은 화면이 체크포인트마다 `--stall` 장 이어졌다 — 첫 화면이 1장이다(화면 끝 40줄).
- error      CLI 실행 실패 · JSON 아님 · `ok: false`(원문).
- superseded 같은 dispatch 의 새 대기가 잠금을 가져갔다. 받은 배치는 싣지 않는다 —
             Karina `check` 는 ack 전까지 같은 배치를 다시 주므로 새 대기가 받는다.
- progress   워커가 task 를 끝냈다(`--repo` 를 줬을 때만) — 표시할 줄 `<label>: T<N>/T<M> 완료 — <무엇을> · T<다음> 시작`.
             message 와 같은 주기에 오면 그 줄을 message 원문 앞에 싣는다 — worker_done 뒤에는 대기를 다시
             띄우지 않아, 따로 내면 마지막 task 줄이 사라진다.
- freed      (`--place` 만) 지켜보던 다른 세션 워커가 자리를 놓았다(그 dispatch 행 원문).

자리 대기(`--place <dispatch>`): `worker-start` 가 `duplicate_worker` 로 다른 세션 워커를 이름 댔을 때 띄운다.
주기(`--poll-ms`, 기본 1분)마다 `check --wait` 로 쉬고 `worker-list --json`(전 Run)에서 그 dispatch 행을 본다.
행이 없거나 Karina `holds_place_at` 기준으로 놓았으면 freed 다. 시한·멈춤 판정은 없다 — 사람이 탭을 놓아야
풀리는 상태도 있어서다. 이 모드의 message·freed 지시문은 --place 재기동을 말하고 error 는 두 모드가 같다.

멈춤 판정: `check` 가 시한 만료(count 0)로 돌아올 때마다 `worker-read`(커서 없음 — 커서는 출처에 묶여
다른 출처로 넘기면 `source_changed` 다)로 화면을 읽고, 앞 체크포인트와 `lines` 가 같으면 연속 수(일치한 비교
횟수 — 같은 화면 장 수보다 하나 적다)를 올린다.
일하는 워커는 스피너 경과 시간이 바뀌어 같을 수 없어, 출력 없이 오래 도는 빌드도 멈춤으로 세지 않는다.
화면 비교까지 남은 대기를 시계가 아니라 차감으로 센다 — `check` 시한은 min(--poll-ms, 남은 대기)이고
남은 대기가 0 이 된 주기에만 화면을 읽는다(비교 간격을 9분으로 지킨다).

진행 감지: 주기마다 `git -C <repo> log <본 sha>..HEAD` 에서 제목이 `<유형>: T<N> — <무엇을>`
(implement 「커밋」 형식)인 커밋을 고른다. 분모는 `<repo>/plan.md` 의 `### T<N>.` 번호 최댓값(implement 의
`T<N>/T<M>` 과 같은 정의)이고 다음 시작은 N 보다 큰 최소 번호다 — N 이 최댓값보다 크면 분모·다음 시작 없이 낸다.
본 sha 와 표시한 번호는 dispatch 별 상태 파일에 두어 재기동해도 같은 커밋·같은 task 의 후속 커밋(「수정: T2」)을
다시 표시하지 않는다. 진행 감지는 잠금 확인보다 먼저 돌고, 잠금을 잃은 대기는 상태를 쓰지 않는다.
git 실패는 대기를 끊지 않고, 본 sha 가 무효하면 HEAD 로 다시 채운다. 상태 파일이 없으면(시작 때 HEAD 를
못 잡음) 주기마다 다시 잡고, 있는데 읽지 못하면 덮어쓰지 않는다. 상태 파일은 임시 파일을 바꿔 넣어 쓰고,
저장 실패는 대기를 끊지 않는다.

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


def _action(kind, dispatch, streak=0, on_place=False):
    if kind == 'message' and on_place:
        return ('배치를 chain-plan 「워커 루프」 규칙대로 처리하고 ack 한 뒤 같은 --place 대기를 다시 띄운다 '
                '(자리 대기 중이라 --dispatch 대기를 띄우지 않는다)')
    if kind == 'freed':
        return ('자리가 비었다 — 거절됐던 worker-start 를 같은 인자로 다시 보낸다 '
                '(references/cli-errors.md 「오류 응답」 duplicate_worker)')
    if kind == 'message':
        return ('앞에 진행 줄이 있으면 먼저 그대로 한 줄씩 표시하고, 배치를 chain-plan 「워커 루프」 규칙대로 '
                '처리하고 ack 한 뒤 대기를 다시 띄운다 (이 배치의 deliveryId 를 이미 ack 했으면 처리하지 않고 대기만 다시 띄운다 · '
                'worker_done 이면 다시 띄우지 않고 다음 계획의 worker-start 뒤에 띄운다)')
    if kind == 'stall':
        return ('같은 화면이 체크포인트마다 %d장 이어졌다 — worker-retain --dispatch %s 후 보고하고 멈춘다'
                % (streak, dispatch))
    if kind == 'error':
        return ('references/cli-errors.md 「오류 응답」 을 따른다 — 그 처방의 「같은 명령을 다시 실행」은 '
                '이 대기를 다시 띄우는 것이다(샌드박스 해제가 필요하면 같은 플래그로)')
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


def wait_loop(call, lock, dispatch, timeout_ms, stall, poll_ms=None, progress=None):
    """대기 반복. call(args)->str 은 `<CLI> orchestration <args>` 의 stdout, lock.owned() 는 잠금 소유,
    progress 는 진행 감지(Progress — 없으면 끈다)다 — 바깥에서 넣어 골든이 Karina·git 없이 갈래를 잰다.
    poll_ms 가 없으면 timeout_ms 와 같아 주기마다 화면을 읽는다. 시한은 두지 않는다 — 백그라운드 실행은
    45분을 넘겨도 살아 완료 알림을 낸다(2026-10-06 실측)."""
    streak, last_hash = 0, None
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
        # 진행 감지(git 하위 프로세스)를 잠금 확인보다 먼저 한다 — 확인 뒤에 돌리면 그 사이 잠금을 잃은
        # 대기가 배치를 싣고 나간다. poll 은 저장하지 않으므로 앞에 둬도 상태를 쓰지 않는다.
        lines_done = progress.poll() if progress is not None else []
        if not lock.owned():
            return _result('superseded', dispatch)
        data, err = _parse(raw)
        if err is not None:
            return _result('error', dispatch, [err])
        if progress is not None:
            progress.commit()
        if data.get('count', 0) > 0:
            return _result('message', dispatch, lines_done + [raw[:RAW_LIMIT * 4]])
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
        # streak 은 일치한 비교 횟수라 같은 화면 장 수는 그보다 하나 많다 — 첫 화면이 1장이다.
        if streak + 1 >= stall:
            return _result('stall', dispatch, lines[-STALL_TAIL:], streak=streak + 1)


# Karina `Worker::holds_place_at` 이 「자리를 쥐고 있다」로 보는 state — 그 밖이거나 놓았으면(released) 빈자리다.
HOLDING_STATES = ('starting', 'ready', 'start_unknown', 'stopping', 'stop_unknown')


def holds_place(row):
    return row.get('state') in HOLDING_STATES and row.get('terminalState') != 'released'


def place_loop(call, lock, place, poll_ms):
    """자리 대기. 다른 세션 워커(dispatch `place`)가 같은 폴더를 쥐고 있는 동안 백그라운드에서 돌고,
    놓으면 freed 로 끝나 코디네이터가 worker-start 를 다시 보낸다. 쉬는 수단은 `check --wait` 다 —
    sleep 을 새로 두지 않아도 되고, 그 사이 이 코디네이터에게 온 배치도 잃지 않는다."""
    while True:
        try:
            raw = call(['check', '--json', '--wait', '--timeout-ms', str(poll_ms)])
        except OSError as e:
            return _result('error', place, ['CLI 실행 실패: %s' % e])
        if not lock.owned():
            return _result('superseded', place)
        data, err = _parse(raw)
        if err is not None:
            return _result('error', place, [err])
        if data.get('count', 0) > 0:
            return _result('message', place, [raw[:RAW_LIMIT * 4]], on_place=True)

        try:
            raw = call(['worker-list', '--json'])
        except OSError as e:
            return _result('error', place, ['CLI 실행 실패: %s' % e])
        if not lock.owned():
            return _result('superseded', place)
        data, err = _parse(raw)
        if err is not None:
            return _result('error', place, [err])
        rows = [r for r in data.get('workers') or [] if r.get('dispatchId') == place]
        if not any(holds_place(r) for r in rows):
            return _result('freed', place, [json.dumps(rows, ensure_ascii=False)[:RAW_LIMIT]])


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
        """새 진행 줄을 돌려주고 갱신할 상태를 pending 에 둔다 — 저장은 commit() 이 한다(잠금 확인 뒤).
        plan.md 는 매치가 있는 주기에 한 번만 읽는다."""
        self.pending = None
        st = self.store.load()
        if st is None:
            # 시작 때 HEAD 를 못 잡았다(커밋 없는 레포·일시 실패) — 다시 잡지 않으면 이 대기가 끝날 때까지 꺼진다.
            ok, head = self.git(['rev-parse', 'HEAD'])
            if ok and head:
                self.pending = {'sha': head, 'shown': []}
            return []
        if not st.get('sha'):
            return []
        shown = list(st.get('shown') or [])
        ok, out = self.git(['log', '--reverse', '--format=%H%x1f%s', '%s..HEAD' % st['sha']])
        if not ok:
            ok, head = self.git(['rev-parse', 'HEAD'])
            if ok and head:
                self.pending = {'sha': head, 'shown': shown}
            return []
        done, last, nums = [], st['sha'], None
        for row in out.splitlines():
            sha, _, subject = row.partition('\x1f')
            if not sha:
                continue
            last = sha
            m = TASK_COMMIT.match(subject.strip())
            if not m or int(m.group(2)) in shown:
                continue
            shown.append(int(m.group(2)))
            if nums is None:
                nums = sorted({int(x) for x in PLAN_TASK.findall(self.read_plan() or '')})
            done.append(self._line(int(m.group(2)), m.group(3).strip(), nums))
        self.pending = {'sha': last, 'shown': shown}
        return done

    def commit(self):
        if self.pending is not None:
            self.store.save(self.pending)
            self.pending = None

    def _line(self, n, what, nums):
        head = '%s: ' % self.label if self.label else ''
        # 분모를 넘는 번호(plan.md 가 바뀐 뒤의 커밋)는 분모 없이 낸다 — T7/T5 처럼 분자가 분모를 넘지 않게.
        if not nums or n > nums[-1]:
            return '%sT%d 완료 — %s' % (head, n, what)
        nxt = [k for k in nums if k > n]
        tail = ' · T%d 시작' % nxt[0] if nxt else ''
        return '%sT%d/T%d 완료 — %s%s' % (head, n, nums[-1], what, tail)


class FileStore:
    """dispatch 별 상태 파일(JSON). 대기가 task 마다 재기동돼 지울 시점이 없고 크기가 작아 지우지 않는다."""

    def __init__(self, dispatch):
        self.path = os.path.join(tempfile.gettempdir(), 'pjc-chain-wait-%s.seen' % dispatch)

    def load(self):
        """부재면 None, 읽지 못하면 {} — 읽지 못함을 부재로 보면 start() 가 남은 상태를 HEAD 로 덮어쓴다."""
        try:
            with open(self.path, encoding='utf-8') as f:
                data = json.load(f)
        except FileNotFoundError:
            return None
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}

    def save(self, st):
        # 임시 파일에 쓰고 바꿔 넣는다 — 제자리 쓰기는 다른 대기의 load() 에 반쯤 쓴 JSON 을 보인다.
        # 저장 실패는 삼킨다: 진행 표시는 부가 기능인데 크래시로 RESULT 줄을 잃으면 체인이 선다.
        folder, name = os.path.split(self.path)
        tmp = None
        try:
            fd, tmp = tempfile.mkstemp(prefix=name + '.', dir=folder or None)
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                json.dump(st, f)
            os.replace(tmp, self.path)
        except OSError:
            if tmp is not None:
                try:
                    os.remove(tmp)
                except OSError:
                    pass


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
    ap.add_argument('--dispatch', default=None)
    ap.add_argument('--place', default=None)
    ap.add_argument('--timeout-ms', type=int, default=540000)
    ap.add_argument('--stall', type=int, default=3)
    ap.add_argument('--repo', default=None)
    ap.add_argument('--label', default='')
    ap.add_argument('--poll-ms', type=int, default=None)
    a = ap.parse_args(argv)
    if (a.dispatch is None) == (a.place is None):
        ap.error('--dispatch 와 --place 중 하나만 준다')
    if a.place is not None:
        lock = FileLock('place-%s' % a.place)
        out = place_loop(make_call(a.cli), lock, a.place, a.poll_ms or 60000)
        lock.release()
        print('\n'.join(out), flush=True)
        return 0
    progress = None
    poll_ms = a.poll_ms
    if a.repo:
        progress = Progress(make_git(a.repo), make_read_plan(a.repo), FileStore(a.dispatch), a.label)
        poll_ms = poll_ms or 60000
    lock = FileLock(a.dispatch)
    out = wait_loop(make_call(a.cli), lock, dispatch=a.dispatch, timeout_ms=a.timeout_ms, stall=a.stall,
                    poll_ms=poll_ms, progress=progress)
    lock.release()
    print('\n'.join(out), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
