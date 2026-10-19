"""CI 에서 Hook 골든 회귀를 돌릴지 변경 파일 경로로 판정한다.

실행: python .github/scripts/hook_golden_needed.py --event <github.event_name>
출력: hook_golden=true|false · reason=<사유> · parents=<merge 커밋 부모> 세 줄(GITHUB_OUTPUT 형식).
판정하지 못하면 true 다 — 건너뛰어 놓치는 쪽보다 돌려서 늦는 쪽을 고른다.
"""
import argparse
import subprocess
import sys

INPUT_PREFIXES = (
    'plugins/pjc/scripts/',
    'plugins/pjc/hooks/',
    'plugins/pjc/skills/',
    '.github/',
)
INPUT_FILES = (
    'docs/golden-runner.md',
    'docs/harness-conventions.md',
)


def normalize(path):
    path = path.replace('\\', '/')
    while path.startswith('./'):
        path = path[2:]
    return path


def needs_hook_golden(paths):
    if not paths:
        return True, 'no changed files detected'
    for raw in paths:
        if raw.startswith('"') or '\n' in raw or '\r' in raw:
            return True, 'quoted or multi-line path'
        path = normalize(raw)
        if path in INPUT_FILES or path.startswith(INPUT_PREFIXES):
            return True, f'input path changed: {path}'
    return False, f'{len(paths)} changed files, none under hook golden inputs'


def run_git(args):
    return subprocess.run(['git', *args], capture_output=True, text=True, encoding='utf-8', check=True).stdout


def decide(event, run_git=run_git):
    if event != 'pull_request':
        return True, f'event {event} runs everything', ''
    try:
        diff = run_git(['-c', 'core.quotepath=off', 'diff', '--name-only', '--no-renames', '-z', 'HEAD^1', 'HEAD'])
        parents = run_git(['log', '-1', '--format=%P']).strip()
    except (subprocess.CalledProcessError, OSError) as e:
        return True, f'git failed: {e}', ''
    needed, reason = needs_hook_golden([p for p in diff.split('\0') if p])
    return needed, reason, parents


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--event', required=True)
    needed, reason, parents = decide(parser.parse_args().event)
    print(f'hook_golden={"true" if needed else "false"}')
    print(f'reason={reason}')
    print(f'parents={parents}')


if __name__ == '__main__':
    main()
