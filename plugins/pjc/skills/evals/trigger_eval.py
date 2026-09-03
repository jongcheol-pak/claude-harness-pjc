#!/usr/bin/env python3
"""스킬 트리거 정확도 eval 러너.

사용법:
  python trigger_eval.py                      # 격리 모드로 전 케이스 1회
  python trigger_eval.py --isolation both     # 격리·비격리 각 1회 + 대조 요약
  python trigger_eval.py --filter impl-       # id 접두 필터
  python trigger_eval.py --out-dir <경로>     # 결과 JSON 저장 위치

각 케이스를 `claude -p <query> --output-format stream-json`으로 실행하고 **Skill 도구 호출을
관측**해 스킬 발동 여부를 판정한다. 정적 문자열 매칭이 아니라 실제 모델 판단을 관측하는
이유는, 트리거가 모델이 스킬 목록을 보고 내리는 결정이라 정적으로 재현되지 않기 때문이다.

이 러너가 반드시 지키는 세 가지 (전부 과거에 실측된 실패를 막기 위한 것):
  1. **pjc 로드 단언** — stream-json의 `init` 이벤트에 실린 plugins/skills/agents 배열로
     pjc 로드를 확인하고, 실패하면 즉시 exit 2로 죽는다. 플러그인이 안 실렸는데 실행만
     성공해 전 케이스가 '미발동'으로 집계되는 은닉 실패를 구조적으로 막는 축이다.
  2. **PYTHONUTF8=1 자체 설정** — 미설정 시 한글·이모지 출력에서 cp949 UnicodeEncodeError로
     러너가 죽는다(Windows).
  3. **watchdog kill + 프로세스 트리 정리** — 응답이 오지 않는 케이스가 러너를 무한 대기시키지
     않게 한다. timeout은 성공/실패 어느 쪽으로도 집계하지 않는다.

워크스페이스(plan.md 유무)는 픽스처로 체크인하지 않고 **실행 시점에 임시 폴더에 생성**한다 —
repo .gitignore가 `plan.md`를 무시해 체크인 자체가 불가능하다.

표준 라이브러리만 사용한다(pip install 불필요 — AGENTS.md 정합).

exit code: 전 케이스 판정 완료 0 / 하나라도 FAIL 1 / 환경·로드 실패 2.
"""
import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

# Windows 콘솔(cp949)에서 한글·이모지 출력이 죽지 않도록 강제 (llm-wiki lint.py와 동일 관례)
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

EVALS_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGIN_DIR = os.path.dirname(os.path.dirname(EVALS_DIR))  # .../plugins/pjc
CASES_JSON = os.path.join(EVALS_DIR, "trigger-cases.json")

# 케이스당 상한. 판정에 필요한 만큼만 넓히고 그 이상은 비용이다.
# 3이던 값을 8로 올린 이유: 모델이 스킬을 부르기 전에 프로젝트를 훑는 케이스가 있는데
# (2026-08-06 재현 실측 — 탐색 도구 3~5회 관측, 그마저 3턴에서 잘린 하한이다), 3턴에서는
# 그 탐색만으로 상한에 닿아 **스킬 호출 기회 자체가 없었다**. 발동하는 케이스는 stop_skill이
# 즉시 끊으므로(run_claude) 상한을 올려도 비용이 늘지 않는다 — 늘어나는 것은 미발동 케이스뿐.
MAX_TURNS = 8
# 2026-07-29 기준선 40세션의 최장 케이스가 108.7초였다 — 그보다 넉넉히 잡아 정상 케이스가
# timeout으로 버려지지 않게 하되, 응답이 끊긴 세션이 러너를 무한정 붙잡지도 않게 한다.
CASE_TIMEOUT_SEC = 180
# 미발동 케이스에 싣는 진단의 상한. 원인을 읽기엔 충분하고 결과 JSON을 부풀리지 않는 선.
MAX_DIAG_TOOLS = 20
MAX_DIAG_TEXT = 300


def build_workspace(kind, dest):
    """케이스가 실행될 최소 프로젝트를 dest에 만든다.

    kind='with_plan'이면 미완료 task가 있는 plan.md를 둔다 — pjc:implement는 '승인된 plan이
    이미 있을 때만' 발동하므로, plan 유무가 곧 트리거 조건의 일부다.

    kind='no_agents_md'면 AGENTS.md를 만들지 않는다 — 그 파일의 **부재**가 발동 조건의 일부인
    케이스를 재기 위한 워크스페이스다(`record-project-fact`는 기존 파일 갱신 전담이라 부재
    상태에서 미발동이 정답이다). AGENTS.md가 있는 워크스페이스로 재면 그 판정이 성립하지 않는다.

    kind='ddd_project'·'xaml_project'는 **그 스킬의 발동 조건이 프로젝트 성격**이라 따로 만든다.
    `add-domain-service`는 description이 "projects without a Domain/Application layer split
    (single-project apps, scripts...)"를 명시적 제외로 두고, `add-viewmodel`은 "non-XAML stacks"를
    제외한다 — 기본 워크스페이스(Python 단일 스크립트)로 재면 **미발동이 정상**이라 그 수치는
    스킬 트리거 품질이 아니라 픽스처 불일치를 잰 것이 된다(no_agents_md와 같은 이유).

    kind='multi_file'·'stale_agents_md'도 같은 이유로 생겼다 — **질의가 전제하는 상태가 기본
    워크스페이스에 없어서** 미발동하던 케이스들이다(2026-08-06 실측). 전자는 "여러 파일에 걸쳐"를
    전제하는데 기본 워크스페이스는 `src/sample.py` 하나뿐이었고, 후자는 "안 쓰는 테스트 명령을
    빼 달라"인데 AGENTS.md가 `Test: 없음`이라 지울 대상이 아예 없었다.
    """
    os.makedirs(dest, exist_ok=True)
    if kind == "ddd_project":
        for sub in ("src/Domain/Orders", "src/Application/Orders", "src/Infrastructure"):
            os.makedirs(os.path.join(dest, *sub.split("/")), exist_ok=True)
        with open(os.path.join(dest, "src", "Domain", "Orders", "Order.cs"),
                  "w", encoding="utf-8", newline="\n") as fh:
            fh.write("namespace Shop.Domain.Orders;\n\n"
                     "public sealed class Order\n{\n"
                     "    public Guid Id { get; init; }\n"
                     "    public decimal Amount { get; private set; }\n}\n")
        with open(os.path.join(dest, "AGENTS.md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(
                "# AGENTS.md\n\n"
                "## Stack\n- .NET 8 / C# 12. **DDD 레이어 분리**(Domain · Application · Infrastructure).\n"
                "- 비즈니스 로직은 Domain 레이어에 둔다. DI는 Microsoft.Extensions.DependencyInjection.\n\n"
                "## Build & Test\n- Build: `dotnet build`\n- Test: `dotnet test`\n\n"
                "## Plan Location\n- 단일 plan: `plan.md`\n"
            )
        return
    if kind == "xaml_project":
        for sub in ("Views", "ViewModels"):
            os.makedirs(os.path.join(dest, sub), exist_ok=True)
        with open(os.path.join(dest, "ViewModels", "MainViewModel.cs"),
                  "w", encoding="utf-8", newline="\n") as fh:
            fh.write("using CommunityToolkit.Mvvm.ComponentModel;\n\n"
                     "namespace App.ViewModels;\n\n"
                     "public partial class MainViewModel : ObservableObject\n{\n"
                     "    [ObservableProperty]\n    private string title = \"Home\";\n}\n")
        with open(os.path.join(dest, "App.csproj"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write('<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n'
                     "    <UseWinUI>true</UseWinUI>\n  </PropertyGroup>\n</Project>\n")
        with open(os.path.join(dest, "AGENTS.md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(
                "# AGENTS.md\n\n"
                "## Stack\n- **WinUI 3** (Windows App SDK) / C#. MVVM은 **CommunityToolkit.Mvvm**.\n"
                "- View는 `Views/`, ViewModel은 `ViewModels/`에 둔다.\n\n"
                "## Build & Test\n- Build: `dotnet build`\n- Test: 없음\n\n"
                "## Plan Location\n- 단일 plan: `plan.md`\n"
            )
        return
    if kind == "multi_file":
        # 에러 처리를 **서로 다르게** 흩어 둔다 — "여러 파일에 걸쳐 바꿔야 한다"는 질의가
        # 성립하려면 흩어진 상태가 실재해야 한다(한 파일에 모여 있으면 그 요청이 모순이 된다).
        os.makedirs(os.path.join(dest, "src"), exist_ok=True)
        modules = {
            "loader.py": ("import json\n\n\n"
                          "def load(path):\n    try:\n"
                          "        with open(path, encoding='utf-8') as fh:\n"
                          "            return json.load(fh)\n"
                          "    except Exception:\n        return None\n"),
            "summary.py": ("def summarize(rows):\n    total = 0\n"
                           "    for row in rows:\n        try:\n"
                           "            total += row['amount']\n"
                           "        except KeyError as e:\n            print('누락 필드', e)\n"
                           "    return total\n"),
            "report.py": ("def render(total):\n    if total is None:\n"
                          "        raise ValueError('집계 결과가 없습니다')\n"
                          "    return f'합계: {total}'\n"),
        }
        for name, body in modules.items():
            with open(os.path.join(dest, "src", name), "w", encoding="utf-8", newline="\n") as fh:
                fh.write(body)
        with open(os.path.join(dest, "AGENTS.md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(
                "# AGENTS.md\n\n"
                "## Stack\n- Python 3. `src/` 아래 모듈 3개(loader · summary · report).\n\n"
                "## Build & Test\n- Build: `python -m compileall src`\n- Test: 없음\n\n"
                "## Plan Location\n- 단일 plan: `plan.md`\n"
            )
        with open(os.path.join(dest, "README.md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("# Sales Report\n\nJSON을 읽어 합계를 내고 문자열로 렌더하는 예제.\n")
        return

    if kind != "no_agents_md":
        # stale_agents_md만 Test 줄이 다르다 — "이제 안 쓰는 테스트 명령을 빼 달라"는 질의는
        # 지울 대상이 실재해야 성립한다(`tests/`가 없는 옛 명령을 심어 stale임이 드러나게 한다).
        # 다른 kind의 생성 내용은 바뀌지 않는다.
        test_line = ("- Test: `python -m pytest tests/` (tests/ 디렉터리 없음 — 옛 명령)\n"
                     if kind == "stale_agents_md" else "- Test: 없음\n")
        with open(os.path.join(dest, "AGENTS.md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(
                "# AGENTS.md\n\n"
                "## Stack\n- Python 3 단일 스크립트.\n\n"
                "## Build & Test\n- Build: `python -m py_compile src/sample.py`\n"
                + test_line +
                "\n## Plan Location\n- 단일 plan: `plan.md`\n"
            )
    os.makedirs(os.path.join(dest, "src"), exist_ok=True)
    with open(os.path.join(dest, "src", "sample.py"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(
            "import logging\n\n"
            'logging.basicConfig(level="INFO")\n\n\n'
            "def summarize(rows):\n"
            "    total = 0\n"
            "    for row in rows:\n"
            "        total += row.get('amount', 0)\n"
            "    logging.info('합계 %s', total)\n"
            "    return total\n"
        )
    with open(os.path.join(dest, "README.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Smaple Project\n\n합계를 계산하는 예제 스크립트.\n")

    if kind == "with_plan":
        with open(os.path.join(dest, "plan.md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(
                "# Plan: 합계 계산 정확도 개선\n\n"
                "## Goal\n\nsummarize()가 통화 단위와 소수점을 올바르게 처리하게 한다.\n\n"
                "## Tasks\n\n"
                "- [ ] T1. summarize()에 통화 단위 인자 추가\n"
                "  - **Type**: B\n"
                "  - **Acceptance**: 인자 미지정 시 기존 동작 유지\n"
                "  - **Files**: `src/sample.py`\n"
                "  - **Depends on**: -\n\n"
                "- [ ] T2. 소수점 반올림 규칙 적용\n"
                "  - **Type**: B\n"
                "  - **Acceptance**: 소수 둘째 자리에서 반올림\n"
                "  - **Files**: `src/sample.py`\n"
                "  - **Depends on**: T1\n\n"
                "## Progress Log\n\n- (없음)\n"
            )


def prepare_isolated_config():
    """빈 CLAUDE_CONFIG_DIR을 만들고 인증 파일만 복사해 반환한다.

    실설치 pjc 스킬이 eval용 사본 대신 트리거를 흡수하면 측정이 교란되므로, 설정을 통째로
    비우고 인증만 가져온다. .credentials.json이 없는 환경(keychain·API 키 사용)에서는 조용히
    넘어가고, 실제 인증 실패는 첫 케이스의 init 부재로 드러난다.
    """
    cfg = tempfile.mkdtemp(prefix="pjc-eval-cfg-")
    src = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")
    if os.path.isfile(src):
        shutil.copy2(src, os.path.join(cfg, ".credentials.json"))
    return cfg


def kill_tree(proc):
    """자식까지 함께 종료한다. proc.kill()만으로는 claude가 띄운 하위 프로세스가 남는다.

    POSIX는 프로세스 그룹째 죽인다 — 그러려면 Popen이 `start_new_session=True`로 자식을 별도
    세션에 띄워야 하며(run_claude가 그렇게 한다), 그래야 killpg가 러너 자신을 말려들게 하지
    않는다. 그룹 킬이 실패하면 최소한 부모라도 정리한다.
    """
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                           capture_output=True, timeout=20)
        else:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (OSError, subprocess.SubprocessError):
        try:
            proc.kill()
        except OSError:
            pass


def parse_events(lines):
    """stream-json 줄들에서 (init, 발동 스킬 목록, result, 도구 시퀀스, 최종 텍스트)를 뽑는다.

    첫 줄이 init이라고 가정하면 안 된다 — pjc hook이 있으면 hook_started가 먼저 온다.
    플러그인 스킬은 네임스페이스 이름(`pjc:implement`)으로 등재되므로 그대로 수집한다.

    도구 시퀀스와 최종 텍스트는 **미발동 케이스의 원인 규명용**이다. 이것이 없으면 결과 JSON에
    "발동 안 함"만 남아 ⓐ 질의가 선행 대화를 전제해 모델이 되물은 것 ⓑ 픽스처와 전제가 어긋난 것
    ⓒ 탐색만 하다 턴이 소진된 것 ⓓ 진짜로 description이 안 맞은 것이 구분되지 않는다(2026-08-06에
    실제로 그 오진이 Deferred 대장에 등재됐다). 같은 순회에서 함께 모으므로 추가 파싱 비용이 없다.

    `tool_calls`는 호출 **시도**의 기록이다 — 결과(성공/거부)는 보지 않으므로 permission-mode가
    manual일 때 거부된 호출도 들어간다. 분류에 쓸 때 "실제로 그 작업을 했다"로 읽지 말 것.
    """
    init_ev = None
    result_ev = None
    triggered = []
    tool_calls = []
    final_text = ""
    for line in lines:
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "system" and ev.get("subtype") == "init":
            init_ev = ev
        elif ev.get("type") == "result":
            result_ev = ev
        elif ev.get("type") == "assistant":
            for block in (ev.get("message") or {}).get("content") or []:
                if block.get("type") == "tool_use":
                    tool_calls.append(block.get("name") or "?")
                    if block.get("name") == "Skill":
                        name = (block.get("input") or {}).get("skill")
                        if name and name not in triggered:
                            triggered.append(name)
                elif block.get("type") == "text" and (block.get("text") or "").strip():
                    final_text = block["text"].strip()  # 마지막 것만 남는다
    return init_ev, triggered, result_ev, tool_calls, final_text


def is_skill_call(line, skill):
    """이 stream-json 줄이 `skill`에 대한 Skill 도구 호출인가 (조기 종료 판정용)."""
    if skill not in line:
        return False
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        return False
    if ev.get("type") != "assistant":
        return False
    for block in (ev.get("message") or {}).get("content") or []:
        if block.get("type") == "tool_use" and block.get("name") == "Skill":
            if (block.get("input") or {}).get("skill") == skill:
                return True
    return False


def run_claude(query, workspace, config_dir, model, stop_skill=None):
    """claude를 한 번 실행하고 (stdout 줄 목록, stderr, timed_out)을 반환한다.

    stop_skill이 주어지면 그 스킬의 발동을 관측하는 즉시 종료한다 — 트리거 판정에 필요한
    정보를 이미 얻었으므로 남은 턴은 시간과 토큰만 쓴다.
    """
    # 옵션을 먼저 쌓고 질의를 **맨 뒤에 `-p -- <query>`로** 붙인다. `-`로 시작하는 질의(불릿
    # 목록 등 실사용 발화)를 CLI가 옵션으로 파싱해 죽는 것을 막기 위함이다 — 그 형태의 케이스가
    # 재시도 2회 모두 0.6초 만에 error로 끝나는 것이 실측됐다. `--` 뒤는 전부 positional이라
    # **그 뒤에는 어떤 옵션도 올 수 없다**(2026-08-06 실증: `-p -- <q> --output-format json`은
    # 질의만 전달되고 옵션이 무시됐다).
    cmd = [
        "claude",
        "--output-format", "stream-json", "--verbose",
        "--max-turns", str(MAX_TURNS),
        "--permission-mode", "manual",
        "--plugin-dir", PLUGIN_DIR,
    ]
    if model:
        cmd += ["--model", model]
    cmd += ["-p", "--", query]

    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    if config_dir:
        env["CLAUDE_CONFIG_DIR"] = config_dir
    else:
        env.pop("CLAUDE_CONFIG_DIR", None)

    proc = subprocess.Popen(
        cmd, cwd=workspace, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
        start_new_session=(os.name != "nt"),  # kill_tree의 POSIX 그룹 킬 전제
    )
    state = {"timed_out": False}

    def on_timeout():
        state["timed_out"] = True
        kill_tree(proc)

    timer = threading.Timer(CASE_TIMEOUT_SEC, on_timeout)
    timer.start()
    lines = []
    try:
        for line in proc.stdout:  # blocking readline — watchdog kill이 EOF로 풀어준다
            lines.append(line)
            if stop_skill and is_skill_call(line, stop_skill):
                kill_tree(proc)
                break
    finally:
        timer.cancel()
        try:
            stderr = proc.communicate(timeout=30)[1] or ""
        except subprocess.TimeoutExpired:
            kill_tree(proc)
            stderr = ""
    return lines, stderr, state["timed_out"]


def is_fatal(result_ev):
    """실행 자체가 실패했는가.

    턴 소진(`error_max_turns`)은 실패가 아니다 — 스킬이 발동해 작업을 진행하다 상한에 닿은
    정상 경로이며, 트리거 판정에 필요한 정보는 이미 스트림에 다 나와 있다.
    """
    res = result_ev or {}
    return bool(res.get("is_error")) and res.get("subtype") != "error_max_turns"


def run_case(case, config_dir, model, workspaces):
    """한 케이스를 실행·판정해 결과 dict를 반환한다. 오류는 1회 재시도한다."""
    ws = workspaces[case["workspace"]]
    started = time.time()
    attempts = 0
    init_ev = triggered = result_ev = None
    tool_calls, final_text = [], ""
    stderr = ""
    timed_out = False

    # 목표 스킬이 발동해야 하는 케이스는 그 발동을 보는 즉시 끊는다(오발동 케이스는 끝까지 봐야
    # '발동 없음'을 확인할 수 있으므로 조기 종료 대상이 아니다).
    stop_skill = case["skill"] if case["expect"] == "trigger" else None

    # 네트워크·API 오류(rate limit·5xx)는 케이스당 1회만 재시도한다. 재시도를 늘리면 실패가
    # 비용으로만 쌓이고, 늘리지 않으면 일시 장애가 기준선을 오염시킨다.
    while attempts < 2:
        attempts += 1
        lines, stderr, timed_out = run_claude(case["query"], ws, config_dir, model, stop_skill)
        init_ev, triggered, result_ev, tool_calls, final_text = parse_events(lines)
        if timed_out:
            break
        if init_ev is not None and not is_fatal(result_ev):
            break

    duration = round(time.time() - started, 1)
    base = {
        "id": case["id"], "skill": case["skill"], "expect": case["expect"],
        "workspace": case["workspace"], "query": case["query"],
        "attempts": attempts, "duration_sec": duration,
        "triggered": triggered or [],
    }

    if timed_out:
        # 성공으로도 실패로도 집계하지 않는다 — 판정을 못 한 것이지 결과가 아니다.
        base["status"] = "timeout"
        return base, init_ev
    if init_ev is None:
        base["status"] = "error"
        base["detail"] = (stderr.strip().splitlines() or ["(stderr 없음)"])[-1][:300]
        return base, init_ev
    if is_fatal(result_ev):
        base["status"] = "error"
        base["detail"] = str(result_ev.get("result") or result_ev.get("subtype") or "")[:300]
        return base, init_ev

    hit = case["skill"] in base["triggered"]
    base["fired"] = hit
    stop_reason = (result_ev or {}).get("subtype")

    if not hit:
        # 진단은 미발동 케이스에만 싣는다 — 발동 케이스는 stop_skill이 즉시 끊어 남길 정보가
        # 없고, 전 케이스에 실으면 결과 JSON만 커진다. 절단은 표시한다(조용한 절단 금지).
        base["stop_reason"] = stop_reason
        base["tool_calls"] = tool_calls[:MAX_DIAG_TOOLS]
        if len(tool_calls) > MAX_DIAG_TOOLS:
            base["tool_calls"].append(f"…(+{len(tool_calls) - MAX_DIAG_TOOLS} more)")
        base["final_text"] = (final_text[:MAX_DIAG_TEXT] + "…(절단)"
                              if len(final_text) > MAX_DIAG_TEXT else final_text)

    if not hit and case["expect"] == "trigger" and stop_reason == "error_max_turns":
        # 스킬을 안 쓰기로 판단한 것이 아니라 **호출 기회에 닿지 못한** 것이라 판정 불가다
        # (timeout과 같은 성격 — 판정을 못 한 것이지 결과가 아니다). 발동률 분모에서 뺀다.
        # expect=no-trigger에는 적용하지 않는다 — 그쪽은 "발동 없음"을 확인하려 설계상 끝까지
        # 돌리므로 턴 소진이 정상 경로이고, 여기 포함시키면 오발동률 분모가 통째로 무너진다.
        base["status"] = "inconclusive"
    else:
        base["status"] = "pass" if hit == (case["expect"] == "trigger") else "fail"
    return base, init_ev


def assert_plugin_loaded(init_ev, isolation):
    """init 이벤트로 pjc 로드를 단언한다. 실패는 즉시 종료 — 이것이 은닉 실패를 막는 축이다."""
    plugins = init_ev.get("plugins") or []
    skills = init_ev.get("skills") or []
    agents = init_ev.get("agents") or []
    names = [p if isinstance(p, str) else (p.get("name") or "") for p in plugins]
    if "pjc" not in names:
        print(f"[중단] pjc 플러그인이 로드되지 않았습니다 (mode={isolation}).")
        print(f"       plugins={names}")
        print(f"       --plugin-dir 경로를 확인하세요: {PLUGIN_DIR}")
        print("       (상위 디렉터리를 주면 엉뚱한 플러그인이 로드되고 실행만 성공합니다)")
        sys.exit(2)
    pjc_skills = [s for s in skills if isinstance(s, str) and s.startswith("pjc:")]
    print(f"  로드 확인: plugins={names} · pjc 스킬 {len(pjc_skills)}종 · agents {len(agents)}종")
    return {"plugins": names, "pjc_skill_count": len(pjc_skills), "agent_count": len(agents)}


def summarize(cases):
    """should-trigger 발동률과 should-not-trigger 오발동률을 집계한다.

    분모는 **판정된 케이스만**이다(`pass`/`fail`). timeout·error·inconclusive를 섞으면
    환경 장애나 관측 실패가 트리거 품질 저하로 둔갑한다.
    """
    pos = [c for c in cases if c["expect"] == "trigger"]
    neg = [c for c in cases if c["expect"] == "no-trigger"]
    pos_judged = [c for c in pos if c["status"] in ("pass", "fail")]
    neg_judged = [c for c in neg if c["status"] in ("pass", "fail")]
    fired_pos = [c for c in pos_judged if c.get("fired")]
    fired_neg = [c for c in neg_judged if c.get("fired")]
    return {
        "total": len(cases),
        "passed": sum(1 for c in cases if c["status"] == "pass"),
        "failed": sum(1 for c in cases if c["status"] == "fail"),
        "timeout": sum(1 for c in cases if c["status"] == "timeout"),
        "error": sum(1 for c in cases if c["status"] == "error"),
        "inconclusive": sum(1 for c in cases if c["status"] == "inconclusive"),
        "judged_positive": len(pos_judged),
        "judged_negative": len(neg_judged),
        "trigger_rate": round(len(fired_pos) / len(pos_judged), 3) if pos_judged else None,
        "false_trigger_rate": round(len(fired_neg) / len(neg_judged), 3) if neg_judged else None,
    }


def run_suite(cases, isolation, model, out_dir, run_id):
    """한 격리 모드로 전 케이스를 돌리고 결과 JSON을 저장한 뒤 요약을 반환한다."""
    config_dir = prepare_isolated_config() if isolation == "isolated" else None
    tmp_root = tempfile.mkdtemp(prefix="pjc-eval-ws-")
    # 케이스가 실제로 쓰는 종류만 만든다 — 케이스 파일에 새 workspace가 추가돼도
    # 이 목록을 함께 고칠 필요가 없다(하드코딩 목록은 곧 조용한 KeyError다).
    workspaces = {}
    for kind in sorted({c["workspace"] for c in cases}):
        path = os.path.join(tmp_root, kind)
        build_workspace(kind, path)
        workspaces[kind] = path

    print(f"\n== 트리거 eval ({isolation}) — {len(cases)}건 ==")
    results = []
    load_info = None
    try:
        for idx, case in enumerate(cases, 1):
            result, init_ev = run_case(case, config_dir, model, workspaces)
            if load_info is None and init_ev is not None:
                load_info = assert_plugin_loaded(init_ev, isolation)
            mark = {"pass": "PASS", "fail": "FAIL", "timeout": "TIME",
                    "error": "ERR ", "inconclusive": "INCO"}[result["status"]]
            fired = ", ".join(result["triggered"]) or "(발동 없음)"
            print(f"[{mark}] {idx:2d}/{len(cases)} {result['id']:12s} {result['duration_sec']:6.1f}s  → {fired}")
            if result.get("detail"):
                print(f"       {result['detail']}")
            results.append(result)
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)
        if config_dir:
            shutil.rmtree(config_dir, ignore_errors=True)

    summary = summarize(results)
    payload = {
        "run_id": run_id,
        "kind": "trigger",
        "isolation": isolation,
        "model": model or "(세션 기본)",
        "plugin_dir": PLUGIN_DIR,
        "load_check": load_info,
        "retry_policy": "케이스당 오류 시 1회 재시도 후 error 표기",
        "summary": summary,
        "cases": results,
    }
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"trigger-{isolation}-{run_id}.json")
    try:
        with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
    except OSError as e:
        print(f"[중단] 결과 JSON 저장 실패: {e}")
        sys.exit(1)

    print(f"\n  판정 {summary['passed']}/{summary['total']} PASS "
          f"(fail {summary['failed']} · timeout {summary['timeout']} · error {summary['error']}"
          f" · 판정불가 {summary['inconclusive']})")
    print(f"  발동률(should-trigger): {summary['trigger_rate']} "
          f"({summary['judged_positive']}건 판정)")
    print(f"  오발동률(should-not-trigger): {summary['false_trigger_rate']} "
          f"({summary['judged_negative']}건 판정)")
    print(f"  저장: {out_path}")
    return payload


def print_isolation_diff(iso, native):
    """격리·비격리 결과의 차이를 표로 남긴다 — '실설치 스킬 간섭 0'의 실증 자료다."""
    print("\n== 격리/비격리 대조 ==")
    print(f"{'case':14s} {'격리':>8s} {'비격리':>8s}  차이")
    by_id = {c["id"]: c for c in native["cases"]}
    diffs = 0
    for c in iso["cases"]:
        n = by_id.get(c["id"])
        if n is None:
            continue
        a = "발동" if c.get("fired") else c["status"]
        b = "발동" if n.get("fired") else n["status"]
        same = "" if a == b else "  ← 다름"
        if same:
            diffs += 1
        print(f"{c['id']:14s} {a:>8s} {b:>8s}{same}")
    print(f"\n  판정이 갈린 케이스: {diffs}건")
    print(f"  발동률   격리 {iso['summary']['trigger_rate']} / 비격리 {native['summary']['trigger_rate']}")
    print(f"  오발동률 격리 {iso['summary']['false_trigger_rate']} / 비격리 {native['summary']['false_trigger_rate']}")


def main():
    ap = argparse.ArgumentParser(description="pjc 스킬 트리거 정확도 eval")
    ap.add_argument("--isolation", choices=["isolated", "native", "both"], default="isolated",
                    help="isolated=빈 CLAUDE_CONFIG_DIR(기본) / native=실설치 환경 / both=둘 다 + 대조")
    ap.add_argument("--model", default="opus", help="측정 모델 (기본 opus — 기준선 재현성)")
    ap.add_argument("--filter", default="", help="케이스 id 접두 필터")
    ap.add_argument("--out-dir", default=os.path.join(tempfile.gettempdir(), "pjc-evals"),
                    help="결과 JSON 저장 위치 (기본: 시스템 임시 폴더 — 프로젝트를 더럽히지 않는다)")
    args = ap.parse_args()

    if shutil.which("claude") is None:
        print("[중단] claude CLI를 찾을 수 없습니다. PATH를 확인하세요.")
        sys.exit(2)
    try:
        with open(CASES_JSON, encoding="utf-8") as fh:
            cases = json.load(fh)["cases"]
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print(f"[중단] trigger-cases.json 로드 실패: {e}")
        sys.exit(2)
    if args.filter:
        cases = [c for c in cases if c["id"].startswith(args.filter)]
    if not cases:
        print("[중단] 실행할 케이스가 없습니다.")
        sys.exit(2)

    run_id = time.strftime("%Y%m%d-%H%M%S")
    modes = ["isolated", "native"] if args.isolation == "both" else [args.isolation]
    runs = {}
    for mode in modes:
        runs[mode] = run_suite(cases, mode, args.model, args.out_dir, run_id)
    if len(modes) == 2:
        print_isolation_diff(runs["isolated"], runs["native"])

    failed = sum(r["summary"]["failed"] for r in runs.values())
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
