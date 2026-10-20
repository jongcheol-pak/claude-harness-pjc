"""karina:chain-plan 코디네이터의 워커 대기 — Bash `run_in_background` 로 띄우고 끝날 때만 코디네이터를 깨운다.

출력 — 첫 줄 `RESULT: <갈래> — <다음 행동>`, 이어 본문:
- message    `check` 가 배치를 돌려줬다(빈 값의 키를 빼고 subject·body 밖의 긴 값을 자른 JSON 한 줄).
             ack 는 하지 않는다 — 코디네이터가 처리한 뒤 한다.
- stall      같은 화면이 체크포인트마다 `--stall` 장 이어졌고 그 사이 HEAD 가 움직이지 않았다 — 첫 화면이 1장이다(화면 끝 40줄).
- error      CLI 실행 실패 · JSON 아님 · `ok: false`(원문).
- superseded 같은 dispatch 의 새 대기가 잠금을 가져갔다. 받은 배치는 싣지 않는다 —
             Karina `check` 는 ack 전까지 같은 배치를 다시 주므로 새 대기가 받는다.
- freed      (`--place` 만) 지켜보던 다른 세션 워커가 자리를 놓았다(그 dispatch 행 — message 와 같은 축약).
- orphaned   대기를 띄운 셸·세션이 사라졌다(두 모드 공통 · 본문 없음).
- deadline   (`--answer-by` 만) 시한까지 배치가 없었다(본문 없음).

진행 줄(`--repo` 를 줬을 때만): 워커가 끝낸 task 마다 `<label>: T<N>/T<M> 완료 — <무엇을> · T<다음> 시작` 한 줄,
`--pr <base>` 면 PR 단계마다 한 줄(문면은 `pr_stage.py` 모듈 docstring). 따로 깨우지 않고
message·stall·error 원문 앞에 싣는다.

모드: `--dispatch` 하나(단일) · 여럿(병렬 — `--repo`·`--label` 도 같은 수·같은 순서) · `--place <dispatch>`(자리 대기).
`--answer-by <epoch 초>` 는 단일에만 — 사용자에게 넘긴 질문의 미답 시한 대기다(화면을 읽지 않는다 · 45분 안).

판정 근거(멈춤·진행 감지·PR 단계·고아 감시·외부 호출 시한·stdout 인코딩)는
`../references/wait-worker-rationale.md` 가 정본이다.
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pr_stage

STALL_TAIL = 40
RAW_LIMIT = 4000
RESULT_CAP = RAW_LIMIT * 4   # message 배치를 다시 쓴 뒤의 안전 상한
COMPACT_STR_LIMIT = 200      # subject·body 밖의 문자열 값은 여기까지만 싣는다
COMPACT_KEEP = ('subject', 'body')
WAIT_FILE_PREFIX = 'karina-chain-wait-'
WATCH_SHELLS = ('bash', 'sh', 'cmd', 'pwsh', 'powershell')  # 감시 사슬에서 지나쳐 계속 올라가는 셸
CLI_TIMEOUT_SEC = 60         # worker-read·worker-list 처럼 기다리지 않는 CLI 호출의 시한
CLI_WAIT_MARGIN_SEC = 60     # check --wait 는 자기 --timeout-ms 에 이만큼 더한 뒤에야 응답 불능으로 본다
GIT_TIMEOUT_SEC = 30         # lint.py·relocate-agents.py 의 git 시한과 같다
SWEEP_AGE_SEC = 7 * 24 * 3600
PR_PENDING_MAX = 6           # CI pending 인 같은 화면을 움직임으로 세는 연속 비교 상한(약 54분)
ANSWER_MAX_SEC = 2700        # --answer-by 상한 — 백그라운드 대기 생존 실측 45분


def screen_hash(lines):
    return hashlib.sha1('\n'.join(lines).encode('utf-8')).hexdigest()[:16]


def _action(kind, dispatch, streak=0, on_place=False, parallel=False, answer_by=None):
    if kind == 'message' and answer_by is not None:
        return ('배치를 chain-plan 「워커 루프」 규칙대로 처리하고 ack 한 뒤, 사용자에게 넘긴 질문이 아직 열려 있으면 '
                '같은 --answer-by %d 로 다시 띄운다 (답을 reply 했으면 --answer-by 없이)' % answer_by)
    if kind == 'deadline':
        return ('사용자에게 넘긴 질문에 시한까지 답이 없다 — references/user-relay.md 「미답 기본값」 대로 '
                '기본값으로 reply 하고 알린 뒤 --answer-by 없이 대기를 다시 띄운다')
    if kind == 'message' and on_place:
        return ('배치를 chain-plan 「워커 루프」 규칙대로 처리하고 ack 한 뒤 같은 --place 대기를 다시 띄운다 '
                '(자리 대기 중이라 --dispatch 대기를 띄우지 않는다)')
    if kind == 'freed':
        return ('자리가 비었다 — 거절됐던 worker-start 를 같은 인자로 다시 보낸다 '
                '(references/cli-errors.md 「오류 응답」 duplicate_worker)')
    if kind == 'message':
        return ('앞에 진행 줄이 있으면 먼저 그대로 한 줄씩 표시하고, 배치를 chain-plan 「워커 루프」 규칙대로 '
                '처리하고 ack 한 뒤 대기를 다시 띄운다 (이 배치의 deliveryId 를 이미 ack 했으면 처리하지 않고 대기만 다시 띄운다 · '
                'worker_done·사후 완료 status 면 다시 띄우지 않고 다음 계획의 worker-start 뒤에 띄운다 · '
                '남은 병렬 워커가 있으면 그 dispatch 들로 곧바로 다시 띄운다 — references/parallel.md)')
    if kind == 'stall' and parallel:
        return ('앞에 진행 줄이 있으면 먼저 그대로 한 줄씩 표시하고(화면은 구분 줄 뒤다), '
                '같은 화면이 체크포인트마다 %d장 이어졌고 HEAD 가 움직이지 않았다 — worker-retain --dispatch %s 후 '
                '병렬 대기라 references/parallel.md 「멈춤」 을 따른다' % (streak, dispatch))
    if kind == 'stall':
        return ('앞에 진행 줄이 있으면 먼저 그대로 한 줄씩 표시하고(화면은 구분 줄 뒤다), '
                '같은 화면이 체크포인트마다 %d장 이어졌고 HEAD 가 움직이지 않았다 — worker-retain --dispatch %s 후 보고하고 멈춘다 '
                '(보고의 멈춘 사유에 직접 재개 알림 안내를 싣는다 — references/report.md · references/manual-resume.md)'
                % (streak, dispatch))
    if kind == 'error':
        return '앞에 진행 줄이 있으면 먼저 그대로 한 줄씩 표시하고, references/cli-errors.md 「오류 응답」 을 따른다'
    if kind == 'orphaned':
        return ('대기를 띄운 셸·세션이 사라졌다 — 이 줄을 읽고 있다면 같은 대기를 다시 띄운다 '
                '(직전 대기도 orphaned 였으면 다시 띄우지 않고 보고하고 멈춘다)')
    return '같은 dispatch 의 새 대기가 이어받았다 — 아무것도 하지 않는다'


def _result(kind, dispatch, body=(), **kw):
    return ['RESULT: %s — %s' % (kind, _action(kind, dispatch, **kw))] + list(body)


def _compact_value(v, key=None):
    if isinstance(v, dict):
        return {k: _compact_value(x, k) for k, x in v.items() if x not in (None, '', [], {})}
    if isinstance(v, list):
        return [_compact_value(x) for x in v]
    if isinstance(v, str) and key not in COMPACT_KEEP and len(v) > COMPACT_STR_LIMIT:
        return v[:COMPACT_STR_LIMIT] + '…(%d자 생략)' % (len(v) - COMPACT_STR_LIMIT)
    return v


def _compact(obj):
    """코디네이터가 읽는 배치·행 — 값이 있는 키는 이름째 남기고(worker_done 결과 키 이름을 확인하지 못했다),
    빈 값의 키는 빼고, subject·body 밖의 긴 문자열만 자른다. 공백 없는 JSON 한 줄이다."""
    return json.dumps(_compact_value(obj), ensure_ascii=False, separators=(',', ':'))


def _parse(raw):
    """CLI 출력을 JSON 으로 읽는다. 실패나 ok:false 면 (None, 오류 원문) 을 돌려준다."""
    try:
        data = json.loads(raw)
    except ValueError:
        return None, raw[:RAW_LIMIT]
    if not isinstance(data, dict) or data.get('ok') is not True:
        return None, raw[:RAW_LIMIT]
    return data, None


def wait_loop(call, lock, dispatch, timeout_ms, stall, poll_ms=None, progress=None, alive=None,
              answer_by=None, now=time.time):
    """대기 반복. call(args)->str 은 `<CLI> orchestration <args>` 의 stdout, lock.owned() 는 잠금 소유,
    progress 는 진행 감지(Progress — 없으면 끈다), now 는 시계다 — 바깥에서 넣어 골든이 Karina·git 없이 갈래를 잰다.
    poll_ms 가 없으면 timeout_ms 와 같아 주기마다 화면을 읽는다. answer_by(epoch 초)가 있으면 화면을 읽지 않고
    그 시각에 deadline 으로 끝나며, 없으면 시한이 없다(근거는 rationale 「미답 시한」·「병렬 대기」).
    dispatch 는 하나(str) 또는 병렬 워커 여럿(list)이고, progress 도 하나 또는 같은 순서의 list 다."""
    ids = [dispatch] if isinstance(dispatch, str) else list(dispatch)
    progs = [] if progress is None else (list(progress) if isinstance(progress, list) else [progress])
    parallel = len(ids) > 1
    head = ids[0] if not parallel else ' '.join(ids)
    streak = {d: 0 for d in ids}
    last_hash = {d: None for d in ids}
    # 직전 화면 비교 때 본 그 워커 레포의 HEAD — progs[i] 가 ids[i] 의 레포다(같은 수·같은 순서).
    head_at_read = {d: None for d in ids}
    pending_run = {d: 0 for d in ids}
    poll = poll_ms or timeout_ms
    remaining = timeout_ms
    for p in progs:
        p.start()

    def poll_all():
        return [line for p in progs for line in p.poll()]

    def commit_all():
        for p in progs:
            p.commit()

    def emit(kind, body, lines_done, who=head, **kw):
        commit_all()
        return _result(kind, who, lines_done + list(body), **kw)

    while True:
        wait = min(poll, remaining)
        if answer_by is not None:
            wait = max(1, min(wait, int((answer_by - now()) * 1000)))
        try:
            raw = call(['check', '--json', '--wait', '--timeout-ms', str(wait)])
        except OSError as e:
            return _result('error', head, ['CLI 실행 실패: %s' % e])
        if alive is not None and not alive():
            return _result('orphaned', head)
        lines_done = poll_all()
        if not lock.owned():
            return _result('superseded', head)
        data, err = _parse(raw)
        if err is not None:
            return emit('error', [err], lines_done)
        if data.get('count', 0) > 0:
            return emit('message', [_compact(data)[:RESULT_CAP]], lines_done, answer_by=answer_by)
        if not lines_done and progs:
            commit_all()
        if answer_by is not None:
            if now() >= answer_by:
                return emit('deadline', [], lines_done)
            continue
        remaining -= wait
        if remaining > 0:
            continue
        remaining = timeout_ms

        for i, d in enumerate(ids):
            try:
                raw = call(['worker-read', '--json', '--dispatch', d])
            except OSError as e:
                return _result('error', head, ['CLI 실행 실패: %s' % e])
            if not lock.owned():
                return _result('superseded', head)
            data, err = _parse(raw)
            if err is not None:
                return emit('error', [err], lines_done)
            lines = [str(l) for l in data.get('lines') or []]
            h = screen_hash(lines)
            cur_head = progs[i].last_head if i < len(progs) else None
            moved = None not in (cur_head, head_at_read[d]) and cur_head != head_at_read[d]
            head_at_read[d] = cur_head
            busy = i < len(progs) and progs[i].pr_busy
            pending_run[d] = pending_run[d] + 1 if busy and h == last_hash[d] else 0
            moved = moved or (busy and pending_run[d] <= PR_PENDING_MAX)
            streak[d] = streak[d] + 1 if h == last_hash[d] and not moved else 0
            last_hash[d] = h
            if streak[d] + 1 >= stall:
                sep = ['— 화면 끝 %d줄 —' % STALL_TAIL] if lines_done else []
                return emit('stall', sep + lines[-STALL_TAIL:], lines_done, who=d,
                            streak=streak[d] + 1, parallel=parallel)


# Karina `Worker::holds_place_at` 이 「자리를 쥐고 있다」로 보는 state — 그 밖이거나 놓았으면(released) 빈자리다.
HOLDING_STATES = ('starting', 'ready', 'start_unknown', 'stopping', 'stop_unknown')


def holds_place(row):
    return row.get('state') in HOLDING_STATES and row.get('terminalState') != 'released'


def place_loop(call, lock, place, poll_ms, alive=None):
    """자리 대기. 다른 세션 워커(dispatch `place`)가 같은 폴더를 쥐고 있는 동안 백그라운드에서 돌고,
    놓으면 freed 로 끝나 코디네이터가 worker-start 를 다시 보낸다. 쉬는 수단은 `check --wait` 다 —
    sleep 을 새로 두지 않아도 되고, 그 사이 이 코디네이터에게 온 배치도 잃지 않는다."""
    while True:
        try:
            raw = call(['check', '--json', '--wait', '--timeout-ms', str(poll_ms)])
        except OSError as e:
            return _result('error', place, ['CLI 실행 실패: %s' % e])
        if alive is not None and not alive():
            return _result('orphaned', place)
        if not lock.owned():
            return _result('superseded', place)
        data, err = _parse(raw)
        if err is not None:
            return _result('error', place, [err])
        if data.get('count', 0) > 0:
            return _result('message', place, [_compact(data)[:RESULT_CAP]], on_place=True)

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
            return _result('freed', place, [_compact(rows)[:RAW_LIMIT]])


class FileLock:
    """dispatch 마다 시스템 임시 폴더에 둔 파일 하나. 새 대기가 자기 표식을 덮어쓰면 앞 대기는 물러난다."""

    def __init__(self, dispatch):
        self.path = os.path.join(tempfile.gettempdir(), 'karina-chain-wait-%s.lock' % dispatch)
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


class AllLocks:
    """병렬 대기의 잠금 — dispatch 마다 FileLock 하나씩이고 전부 쥐었을 때만 소유다. 새 대기의 dispatch 집합이
    하나라도 겹치면(끝난 워커를 뺀 나머지로 다시 띄운 대기) 앞 대기가 물러나 같은 배치를 두 대기가 받지 않는다."""

    def __init__(self, locks):
        self.locks = list(locks)

    def owned(self):
        return all(l.owned() for l in self.locks)

    def release(self):
        for l in self.locks:
            l.release()


def pick_watch_targets(chain):
    """조상 사슬(가까운 순 `[(pid, 이름), …]`)에서 감시할 프로세스를 고른다 — 앞쪽 python 은 건너뛰고,
    셸은 담고 계속, 첫 비셸(claude.exe 등)을 담고 멈춘다. 앞쪽 python 은 WindowsApps 스텁이라 이 대기와 함께
    살아 감시해도 소용이 없다(2026-10-14 실측 — `python(실) → python(스텁) → bash×3 → claude.exe`)."""
    i = 0
    while i < len(chain) and chain[i][1].lower().startswith(('python', 'py.', 'pyw.')):
        i += 1
    picked = []
    for pid, name in chain[i:]:
        picked.append((pid, name))
        if name.lower().rsplit('.', 1)[0] not in WATCH_SHELLS:
            break
    return picked


def _win_chain():
    """Toolhelp32 스냅숏으로 자기 조상 사슬을 얻는다(자기 제외 · 가까운 순). 실패는 OSError."""
    import ctypes
    from ctypes import wintypes

    class Entry(ctypes.Structure):
        _fields_ = [('dwSize', wintypes.DWORD), ('cntUsage', wintypes.DWORD), ('th32ProcessID', wintypes.DWORD),
                    ('th32DefaultHeapID', ctypes.c_size_t), ('th32ModuleID', wintypes.DWORD),
                    ('cntThreads', wintypes.DWORD), ('th32ParentProcessID', wintypes.DWORD),
                    ('pcPriClassBase', ctypes.c_long), ('dwFlags', wintypes.DWORD),
                    ('szExeFile', ctypes.c_wchar * 260)]

    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    k32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
    if not snap or snap == wintypes.HANDLE(-1).value:
        raise OSError('CreateToolhelp32Snapshot 실패')
    table = {}
    try:
        e = Entry()
        e.dwSize = ctypes.sizeof(Entry)
        ok = k32.Process32FirstW(snap, ctypes.byref(e))
        while ok:
            table[e.th32ProcessID] = (e.th32ParentProcessID, e.szExeFile)
            ok = k32.Process32NextW(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)
    chain, pid, seen = [], os.getpid(), set()
    while pid in table and pid not in seen and len(chain) < 16:
        seen.add(pid)
        ppid = table[pid][0]
        if ppid not in table:
            break
        chain.append((ppid, table[ppid][1]))
        pid = ppid
    return chain


def _win_open(pid):
    # SYNCHRONIZE 핸들은 그 프로세스 객체에 묶여 PID 가 재사용돼도 죽은 프로세스를 가리킨다.
    import ctypes
    from ctypes import wintypes
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    k32.OpenProcess.restype = wintypes.HANDLE
    return k32.OpenProcess(0x00100000, False, pid) or None


def _win_running(handle):
    import ctypes
    return ctypes.WinDLL('kernel32').WaitForSingleObject(handle, 0) == 0x102  # WAIT_TIMEOUT — 아직 살아 있다


def make_alive(windows=None, list_chain=None, open_handle=None, is_running=None):
    """대기를 띄운 셸·세션이 살아 있는가를 돌려주는 alive() — 감시를 세울 수 없으면 None(현행처럼 계속 기다린다).
    ⚠ 생존 확인에 `os.kill(pid, 0)` 을 쓰지 않는다 — Windows 에서는 TerminateProcess 라 감시 대상을 죽인다.
    POSIX 는 직계 부모가 바뀌었는가만 본다 — 실험적 지원이라 조상 사슬은 재지 않는다."""
    if windows is None:
        windows = os.name == 'nt'
    if not windows:
        ppid = os.getppid()
        return lambda: os.getppid() == ppid
    list_chain = list_chain or _win_chain
    open_handle = open_handle or _win_open
    is_running = is_running or _win_running
    try:
        targets = pick_watch_targets(list_chain())
        handles = [h for h in (open_handle(pid) for pid, _ in targets) if h]
    except (OSError, AttributeError, ValueError):
        return None
    if not handles:
        return None
    # 일부만 열렸으면(권한 차이 등) 연 것만 본다 — 그것만으로도 세션 소멸은 잡힌다.
    return lambda: all(is_running(h) for h in handles)


def _cli_timeout(args):
    if '--timeout-ms' in args:
        return int(args[args.index('--timeout-ms') + 1]) / 1000 + CLI_WAIT_MARGIN_SEC
    return CLI_TIMEOUT_SEC


def make_call(cli):
    def call(args):
        try:
            p = subprocess.run([cli, 'orchestration'] + args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, timeout=_cli_timeout(args))
        except subprocess.TimeoutExpired as e:
            raise OSError('응답 없음 — %s 초 시한 초과' % e.timeout) from None
        return p.stdout.decode('utf-8', errors='replace')
    return call


TASK_COMMIT = re.compile(r'^(기능|수정|리팩토링|문서|설정): T(\d+) — (.+)$')
PLAN_TASK = re.compile(r'^### T(\d+)\. ', re.M)


class Progress:
    """task 완료 커밋을 표시 줄로 바꾼다. git(args)->(성공, 출력) · read_plan()->str|None · store(load/save) 는 주입한다."""

    def __init__(self, git, read_plan, store, label, pr=None):
        self.git, self.read_plan, self.store, self.label = git, read_plan, store, label
        self.pr = pr
        self.pending = None
        self.last_head = None

    def start(self):
        if self.store.load() is None:
            ok, head = self.git(['rev-parse', 'HEAD'])
            if ok and head:
                self.store.save({'sha': head, 'shown': []})
                self.last_head = head

    @property
    def pr_busy(self):
        return self.pr is not None and self.pr.busy

    def poll(self):
        """새 진행 줄(task 완료 · PR 단계)을 돌려주고 갱신할 상태를 pending 에 둔다 — 저장은 commit() 이 한다(잠금 확인 뒤).
        plan.md 는 매치가 있는 주기에 한 번만 읽는다."""
        self.pending = None
        st = self.store.load()
        done = self._poll_tasks(st)
        if self.pr is not None:
            # 기준 sha 가 없는 상태(부재·읽지 못함)에는 PR 상태만 저장하지 않는다 — 저장하면 task 진행 감지가 꺼진다.
            base = self.pending if self.pending is not None else (st or {})
            lines, pr_st = self.pr.poll(base.get('pr'))
            if base.get('sha') and pr_st != (base.get('pr') or {}):
                self.pending = dict(base, pr=pr_st)
            done += lines
        return done

    def _poll_tasks(self, st):
        if st is None:
            # 시작 때 HEAD 를 못 잡았다(커밋 없는 레포·일시 실패) — 다시 잡지 않으면 이 대기가 끝날 때까지 꺼진다.
            ok, head = self.git(['rev-parse', 'HEAD'])
            if ok and head:
                self.pending = {'sha': head, 'shown': []}
                self.last_head = head
            return []
        if not st.get('sha'):
            return []
        shown = list(st.get('shown') or [])
        ok, out = self.git(['log', '--reverse', '--format=%H%x1f%s', '%s..HEAD' % st['sha']])
        if not ok:
            ok, head = self.git(['rev-parse', 'HEAD'])
            if ok and head:
                self.pending = dict(st, sha=head, shown=shown)
                self.last_head = head
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
        self.pending = dict(st, sha=last, shown=shown)
        self.last_head = last
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
    """dispatch 별 상태 파일(JSON). 대기가 재기동될 때마다 이어 쓰여 그 dispatch 의 마지막 대기를 스크립트가
    알 수 없으므로 끝에 지우지 않고, 7일 지나면 다음 대기의 시작 정리(sweep_stale)가 지운다."""

    def __init__(self, dispatch):
        self.path = os.path.join(tempfile.gettempdir(), 'karina-chain-wait-%s.seen' % dispatch)

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


def sweep_stale(folder, now):
    """`folder` 의 `karina-chain-wait-*`(잠금·상태·쓰다 남은 임시 파일) 중 수정 시각이 SWEEP_AGE_SEC 지난 것을 지운다.
    대기 수명은 45분 실측이라 그만큼 지난 파일은 죽은 대기의 것이다 — 지우지 않으면 dispatch 마다 하나씩 쌓인다.
    정리는 부가 기능이라 실패는 삼킨다."""
    try:
        names = os.listdir(folder)
    except OSError:
        return
    for name in names:
        if not name.startswith(WAIT_FILE_PREFIX):
            continue
        path = os.path.join(folder, name)
        try:
            if now - os.path.getmtime(path) > SWEEP_AGE_SEC:
                os.remove(path)
        except OSError:
            pass


def make_git(repo):
    def git(args):
        try:
            p = subprocess.run(['git', '-C', repo] + args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, timeout=GIT_TIMEOUT_SEC)
        except (OSError, subprocess.TimeoutExpired):
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
    # --dispatch·--repo·--label 은 병렬 워커마다 한 번씩 같은 순서로 준다(한 번이면 종전 단일 대기).
    ap.add_argument('--dispatch', action='append', default=None)
    ap.add_argument('--place', default=None)
    ap.add_argument('--timeout-ms', type=int, default=540000)
    ap.add_argument('--stall', type=int, default=3)
    ap.add_argument('--repo', action='append', default=None)
    ap.add_argument('--label', action='append', default=None)
    ap.add_argument('--poll-ms', type=int, default=None)
    ap.add_argument('--pr', default=None)
    ap.add_argument('--answer-by', type=int, default=None)
    a = ap.parse_args(argv)
    if (a.dispatch is None) == (a.place is None):
        ap.error('--dispatch 와 --place 중 하나만 준다')
    if a.pr is not None and not a.repo:
        ap.error('--pr 는 --repo 와 함께 준다')
    if a.answer_by is not None and (a.place is not None or len(a.dispatch) > 1):
        ap.error('--answer-by 는 --dispatch 하나와만 준다')
    if a.answer_by is not None and a.answer_by - time.time() > ANSWER_MAX_SEC:
        ap.error('--answer-by 는 지금부터 %d초 안이어야 한다' % ANSWER_MAX_SEC)
    for name, vals in (('--repo', a.repo), ('--label', a.label)):
        if vals is not None and a.dispatch is not None and len(vals) != len(a.dispatch):
            ap.error('%s 는 --dispatch 와 같은 수만큼 같은 순서로 준다' % name)
    alive = make_alive()
    if a.place is not None:
        lock = FileLock('place-%s' % a.place)
        out = place_loop(make_call(a.cli), lock, a.place, a.poll_ms or 60000, alive=alive)
        lock.release()
        print('\n'.join(out), flush=True)
        return 0
    sweep_stale(tempfile.gettempdir(), time.time())
    ids = a.dispatch
    labels = a.label or [''] * len(ids)
    progress = None
    poll_ms = a.poll_ms
    if a.repo:
        progress = [Progress(make_git(r), make_read_plan(r), FileStore(d), lb,
                             pr=pr_stage.PrStage(make_git(r), pr_stage.make_gh(r), a.pr, lb) if a.pr else None)
                    for d, r, lb in zip(ids, a.repo, labels)]
        poll_ms = poll_ms or 60000
    lock = FileLock(ids[0]) if len(ids) == 1 else AllLocks([FileLock(d) for d in ids])
    out = wait_loop(make_call(a.cli), lock, dispatch=ids if len(ids) > 1 else ids[0], timeout_ms=a.timeout_ms,
                    stall=a.stall, poll_ms=poll_ms, progress=progress, alive=alive, answer_by=a.answer_by)
    lock.release()
    print('\n'.join(out), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
