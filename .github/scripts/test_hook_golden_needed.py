"""hook_golden_needed.py 의 판정 갈래를 잰다. 갈래 번호는 plan T2 의 ①~⑬ 이다.

실행: python .github/scripts/test_hook_golden_needed.py
출력: 케이스마다 PASS <갈래> 또는 FAIL <갈래> <기대·실제>, 끝에 N cases. 실패가 있으면 exit 1.
"""
import os
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hook_golden_needed as h

results = []


def check(branch, expected, actual, label):
    ok = expected == actual
    results.append(ok)
    if ok:
        print(f'PASS {branch} {label}')
    else:
        print(f'FAIL {branch} {label} 기대={expected} 실제={actual}')


def paths(branch, files, expected, label):
    check(branch, expected, h.needs_hook_golden(files)[0], label)


def fake_git(diff_out=None, parents_out='p1 p2', fail=False):
    def run(args):
        if fail:
            raise subprocess.CalledProcessError(128, args)
        if 'diff' in args:
            return diff_out
        return parents_out
    return run


paths(1, ['plugins/pjc/.claude-plugin/plugin.json', 'README.md'], False, '버전 PR')
paths(2, ['plugins/pjc/skills/implement/references/pr-flow.md'], True, 'skills md')
paths(3, ['plugins/pjc/scripts/guard-bash.ps1'], True, 'hook 스크립트')
paths(4, ['plugins/pjc/hooks/hooks.json'], True, 'hooks.json')
paths(5, ['docs/golden-runner.md'], True, 'golden-runner.md')
paths(5, ['docs/harness-conventions.md'], True, 'harness-conventions.md')
paths(6, ['.github/workflows/checks.yml'], True, '워크플로')
paths(6, ['.github/scripts/hook_golden_needed.py'], True, '판정 스크립트')
paths(7, ['docs/plans/deferred.md', 'AGENTS.md', 'intent/2026-10-19-x.md'], False, '대장·AGENTS·intent')
paths(8, [], True, '빈 목록')

check(9, True, h.decide('push', fake_git(diff_out=''))[0], 'push 이벤트')
check(10, True, h.decide('pull_request', fake_git(fail=True))[0], 'git 실패')

paths(11, ['plugins\\pjc\\scripts\\guard-bash.ps1'], True, 'Windows 구분자')
paths(11, ['./plugins/pjc/hooks/hooks.json'], True, '앞 ./')
paths(11, ['.\\README.md'], False, '앞 .\\ 입력 밖')

check(12, True, h.decide('pull_request', fake_git(diff_out='plugins/pjc/scripts/x.ps1\0docs/x.ps1\0'))[0],
      '입력 밖으로 옮김(삭제+추가)')
check(12, False, h.decide('pull_request', fake_git(diff_out='README.md\0plugins/pjc/.claude-plugin/plugin.json\0'))[0],
      'NUL 구분 입력 밖')

paths(13, ['"plugins/pjc/skills/\\355\\225\\234.md"'], True, '따옴표로 감싼 경로')
paths(13, ['README.md\nhook_golden=false'], True, '줄바꿈이 든 경로')
check(13, False, '\n' in h.needs_hook_golden(['plugins/pjc/hooks/a\nhook_golden=false'])[1], '사유에 줄바꿈 없음')

print(f'{len(results)} cases')
sys.exit(0 if all(results) else 1)
