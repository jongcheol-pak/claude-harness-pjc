#!/usr/bin/env python3
"""llm-wiki lint.py 골든 회귀 러너.

사용법: python run_lint_evals.py   (llm-wiki/evals 폴더 기준, 인자 없음)

lint-cases.json의 각 case를 evals/fixtures/<fixture> vault에 대해 lint.py로 실행하고
결과를 대조한다:
  - expect_clean=true  → lint 출력에 '[ERR] 오류 0건'·'[WARN] 경고 0건'이 모두 있어야 PASS
                         (정상 vault를 경고하지 않는지 = 오탐 회귀 방지). INFO는 허용.
  - expect_keywords    → 나열된 키워드가 lint 출력에 모두 있으면 PASS (부분 매칭 —
                         lint 문구 미세 변경에 견고).
  - expect_absent      → (보조) 나열된 키워드가 lint 출력에 하나라도 있으면 FAIL —
                         "실재 경로는 경고하지 않는다" 같은 무경고 기대를 검증한다.
  - after_expect_keywords → (fix_mode 보조) --fix 후 재lint 출력에 전부 있어야 PASS —
                         "--fix가 건드리지 않아야 하는 위반의 잔존"(보수 동작)을 검증한다.
  - placeholder=true   → fixture를 임시 폴더로 복사한 뒤 .md 안의 __FIXTURE_ROOT__를
                         복사본 절대경로로 치환해 lint를 실행한다. §7-20처럼 '실재하는
                         절대경로'가 필요한 fixture를 기계 독립적으로 만든다 (opt-in —
                         기존 fixture는 그대로 원본 경로로 실행).

lint.py 자체는 수정하지 않고 subprocess로 호출만 한다(실사용 경로와 동일). 표준 라이브러리만
사용하며(테스트 프레임워크 없음 — AGENTS.md 정합), lint.py를 부른 것과 같은 인터프리터
(sys.executable)로 실행하므로 'python 부재'로 실패하지 않는다.

exit code: 전 case PASS면 0, 하나라도 FAIL이면 1.
"""
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# Windows 콘솔(cp949)에서도 한글·em-dash가 깨지지 않도록 UTF-8 출력 강제 (lint.py와 동일)
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

EVALS_DIR = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(EVALS_DIR)
LINT_PY = os.path.join(SKILL_DIR, "scripts", "lint.py")
FIXTURES_DIR = os.path.join(EVALS_DIR, "fixtures")
CASES_JSON = os.path.join(EVALS_DIR, "lint-cases.json")


def run_lint(vault_path, extra_args=None):
    """lint.py를 subprocess로 실행하고 (stdout, returncode, stderr)를 반환한다.
    returncode를 함께 넘겨, lint.py 자체 크래시와 '위반 검출 결과'를 호출부가 구분하게 한다.
    extra_args: --fix 등 추가 인자(fix_mode 케이스용)."""
    proc = subprocess.run(
        [sys.executable, LINT_PY, vault_path] + (extra_args or []),
        capture_output=True, text=True, encoding="utf-8",
    )
    return proc.stdout, proc.returncode, proc.stderr


def prepare_placeholder_vault(fixture_dir):
    """fixture를 임시 폴더로 복사하고 .md 안의 __FIXTURE_ROOT__를 복사본 절대경로(슬래시
    정규화)로 치환한다. 반환: (정리용 임시 루트, lint에 넘길 vault 경로).
    §7-20 실존 검사는 허브 '레포 정보 > 경로'가 실재 디렉터리여야 동작하는데, 체크인된
    fixture에 절대경로를 박으면 다른 PC에서 깨지므로 실행 시점에 만들어 넣는다."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    root_token = dest.replace("\\", "/")
    for dirpath, _dirs, files in os.walk(dest):
        for name in files:
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            if "__FIXTURE_ROOT__" in text:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(text.replace("__FIXTURE_ROOT__", root_token))
    return tmp, dest


def prepare_backup_cleanup_vault(fixture_dir):
    """fixture를 임시 복사하고 90_archive/backup/ 아래에 날짜 폴더 8종을 만든다(§8 정리 골든).
    **날짜를 fixture에 체크인할 수 없어서** 여기서 만든다 — 오늘·어제·31일 전 판정은 실행 시점
    기준 상대값이라, 고정 날짜를 커밋하면 시간이 지나며 기대 결과가 조용히 뒤집힌다.
    반환: (정리용 임시 루트, vault 경로, {케이스 토큰: 실제 폴더명} 매핑)."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-backup-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    today = datetime.date.today()
    d1 = (today - datetime.timedelta(days=1)).isoformat()
    d31 = (today - datetime.timedelta(days=31)).isoformat()
    names = {
        "TODAY": today.isoformat(),          # 남는다 — 한 세션분 복구 창
        "D1": d1,                            # 제거 — 접미사 없는 이전 날짜(누적 금지)
        "D31": d31,                          # 제거 — 같은 규칙(30일보다 먼저 걸린다)
        "D1-deleted": d1 + "-deleted",       # 남는다 — 유일 사본
        "D1-pre-restore": d1 + "-pre-restore",  # 남는다 — 복구 재백업
        "D1-presplit": d1 + "-presplit",     # 남는다 — 30일 이내
        "D31-presplit": d31 + "-presplit",   # 제거 — 30일 경과
        "NOTADATE": "manual-note",           # 남는다 — 날짜로 읽히지 않는 임의 폴더
    }
    root = os.path.join(dest, "90_archive", "backup")
    for folder in names.values():
        os.makedirs(os.path.join(root, folder), exist_ok=True)
        with open(os.path.join(root, folder, "sample.md"), "w", encoding="utf-8", newline="") as fh:
            fh.write("백업 사본 더미\n")
    return tmp, dest, names


def prepare_bad_encoding_vault(fixture_dir):
    """fixture를 임시 폴더로 복사하고 CP949(비 UTF-8) .md 파일 1개를 주입한다(M-2 격리 검증).
    비 UTF-8 파일을 레포에 체크인하면 git·에디터가 손상시킬 수 있어 실행 시점에 만든다.
    반환: (정리용 임시 루트, lint에 넘길 vault 경로)."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-badenc-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    bad = os.path.join(dest, "20_projects", "personal", "demo", "feat-badenc.md")
    with open(bad, "wb") as fh:
        fh.write("---\ntype: feature\n---\n한글 CP949 본문".encode("cp949"))
    return tmp, dest


def prepare_bad_index_vault(fixture_dir):
    """fixture를 임시 폴더로 복사하고 **index.md 자체**를 CP949로 덮어쓴다.
    일반 페이지를 깨뜨리는 bad_encoding과 달리 index.md는 메인 루프 밖에서 한 번 더 읽히던
    경로라, 예외 처리가 없던 시절엔 이 파일 하나로 lint 전체가 traceback으로 죽었다.
    반환: (정리용 임시 루트, lint에 넘길 vault 경로)."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-badidx-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    bad = os.path.join(dest, "index.md")
    with open(bad, "wb") as fh:
        fh.write("# 인덱스\n\n한글 CP949 본문".encode("cp949"))
    return tmp, dest


def prepare_git_repo_vault(fixture_dir, synced_mode):
    """fixture를 임시 폴더로 복사하고, 그 옆에 **커밋 3개짜리 임시 git 레포**를 만들어
    허브의 `__REPO_ROOT__`·`__SYNCED_SHA__`를 실제 값으로 치환한다(§7-26 골든).

    §7-26의 뒤처짐 계산은 실제 git 이력이 있어야만 실증된다 — 스텁으로 대체하면
    `git rev-list` 실경로가 어디서도 검증되지 않으므로 진짜 레포를 만든다.
    synced_mode: "first"=첫 커밋 sha(→ 2커밋 뒤처짐) / "missing"=이력에 없는 가짜 sha.
    커밋은 전역 git config에 의존하지 않게 `-c user.*`를 케이스 로컬로 준다.
    git이 없거나 실패하면 (None, None) — 호출부가 케이스를 SKIP한다.
    반환: (정리용 임시 루트, vault 경로). 기대 뒤처짐 수는 케이스의 expect_keywords가
    문자열로 못박으므로(예: "2커밋 미반영") 따로 반환하지 않는다."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-git-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    repo = os.path.join(tmp, "repo")
    os.makedirs(repo)
    git = ["git", "-c", "user.name=lint-eval", "-c", "user.email=lint-eval@example.invalid"]
    try:
        subprocess.run(["git", "init", "-q", repo], check=True, capture_output=True, timeout=20)
        shas = []
        for i in range(3):
            with open(os.path.join(repo, f"f{i}.txt"), "w", encoding="utf-8") as fh:
                fh.write(f"commit {i}\n")
            subprocess.run(git + ["-C", repo, "add", "-A"], check=True, capture_output=True, timeout=20)
            subprocess.run(git + ["-C", repo, "commit", "-q", "-m", f"c{i}"],
                           check=True, capture_output=True, timeout=20)
            out = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"],
                                 check=True, capture_output=True, text=True, timeout=20)
            shas.append(out.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        shutil.rmtree(tmp, ignore_errors=True)
        return None, None  # git 미설치·실행 실패 → 케이스 SKIP
    # "first" = 첫 커밋 기준 → 이후 2커밋이 미반영. "missing" = 이력에 없는 sha(rebase 소실 재현).
    synced = shas[0] if synced_mode == "first" else "0" * 40
    for dirpath, _dirs, files in os.walk(dest):
        for name in files:
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            new = text.replace("__REPO_ROOT__", repo.replace("\\", "/")) \
                      .replace("__SYNCED_SHA__", synced)
            if new != text:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(new)
    return tmp, dest


def prepare_aux_split_vault(fixture_dir, concept_count, open_questions):
    """fixture를 임시 복사하고 **본체를 임계 위로 밀어 올릴 만큼** concept을 생성한 뒤,
    open question을 심는다(§4 1단계 본체 구역 분리 골든).

    concept을 쓰는 이유: feature는 sub-index로 빠져 본체를 키우지 않지만 `## 범용 패턴`은
    본체 구역이라 행이 그대로 쌓인다. open question은 §7-23 오탐 회귀(구역이 옮겨간 뒤
    본체만 보면 전부 '미등록'으로 잡히던 것)를 재현하는 데 필요하다 — 질문이 0건이면
    그 검사가 아무것도 세지 않아 회귀가 침묵한다.
    반환: (정리용 임시 루트, vault 경로)."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-aux-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    pat = os.path.join(dest, "30_knowledge", "patterns")
    os.makedirs(pat, exist_ok=True)
    for i in range(1, concept_count + 1):
        with open(os.path.join(pat, "bulk-concept-%03d.md" % i), "w",
                  encoding="utf-8", newline="") as fh:
            fh.write("---\ntype: concept\n"
                     'concept_name: "대량 개념 %03d"\n'
                     'index_label: "대량 개념 %03d (bulk concept %03d)"\n'
                     "platform: cross\norigin: agent-synthesized\nconfidence: medium\n"
                     "updated: 2026-07-02\nrelated_projects: [Demo]\ntags: [concept]\n---\n\n"
                     "# 대량 개념 %03d\n\n## 정의\n골든용 최소 concept.\n" % (i, i, i, i))
    qd = os.path.join(dest, "30_knowledge", "questions")
    os.makedirs(qd, exist_ok=True)
    for i in range(1, open_questions + 1):
        with open(os.path.join(qd, "q-20260822-bulk%02d.md" % i), "w",
                  encoding="utf-8", newline="") as fh:
            fh.write("---\ntype: question\nstatus: open\npriority: medium\n"
                     "updated: 2026-08-22\nrelated: [Demo]\ntags: [question]\n---\n\n"
                     "# 미해결 질문 %02d\n\n## 질문\n골든용.\n" % i)
    return tmp, dest


def prepare_chunk_split_vault(fixture_dir, feature_count, stale_names):
    """fixture를 임시 복사하고 **feature 페이지를 feature_count개 생성**한 뒤,
    stale_names의 sub-index를 미리 심어 둔다(§4 3단계 순번 분할 골든).

    페이지를 체크인하지 않고 실행 시점에 만드는 이유: 순번 분할은 임계(200행)를 넘겨야
    발동하는데 그만큼의 md를 레포에 커밋하면 픽스처가 수백 개 파일로 불어난다. 날짜 폴더를
    실행 시점에 만드는 backup_cleanup 선례와 같은 이유다.
    반환: (정리용 임시 루트, vault 경로)."""
    tmp = tempfile.mkdtemp(prefix="lint-eval-chunk-")
    dest = os.path.join(tmp, os.path.basename(fixture_dir))
    shutil.copytree(fixture_dir, dest)
    demo = os.path.join(dest, "20_projects", "personal", "demo")
    os.makedirs(demo, exist_ok=True)
    for i in range(1, feature_count + 1):
        with open(os.path.join(demo, "feat-bulk-%03d.md" % i), "w",
                  encoding="utf-8", newline="") as fh:
            fh.write(
                "---\ntype: feature\nproject: Demo\ncategory: personal\n"
                'feature_name: "대량 %03d"\nindex_label: "대량 %03d (bulk %03d)"\n'
                "platform: windows-desktop\nstatus: active\norigin: agent-synthesized\n"
                "confidence: medium\nupdated: 2026-07-02\ntags: [feature, demo]\n---\n\n"
                "# 대량 %03d (bulk %03d)\n\n## 개요\n순번 분할 골든용 최소 feature.\n\n"
                "## 관련 파일\n- `src/Demo/Bulk%03d.cs` — 더미\n\n"
                "## 동작(사용법)\n없음.\n\n## 구현 방법\n없음.[^src-b]\n\n"
                "## UI·UX\n없음.\n\n## 관련 지식·레시피\n- 없음\n\n"
                "[^src-b]: [[10_sources/personal/src-demo|소스: Demo]] — `src/Demo/Bulk%03d.cs`\n"
                % (i, i, i, i, i, i, i))
    for name in stale_names:
        with open(os.path.join(dest, name), "w", encoding="utf-8", newline="") as fh:
            fh.write("---\ntype: index\ntags: [index]\n---\n\n# 옛 순번 파일\n\n"
                     "## 기능별 인덱스\n\n| 기능 | 플랫폼 | 프로젝트 | 상세 |\n"
                     "|------|--------|----------|------|\n")
    # 델타 음성: 이름은 index-*.md지만 type이 index가 아니다 — 삭제되면 안 된다.
    with open(os.path.join(dest, "index-notes.md"), "w", encoding="utf-8", newline="") as fh:
        fh.write("---\ntype: guide\nguide_kind: recipe\nplatform: cross\n"
                 "origin: human-validated\nconfidence: high\nupdated: 2026-07-02\n"
                 "tags: [guide]\n---\n\n# 사용자 메모\n\n## 목적\n생성물이 아니다.\n")
    return tmp, dest


def _snapshot_md(root):
    """vault 안 모든 .md의 (상대경로 -> 바이트) 스냅샷. --build-index --dry-run이 정말로
    아무것도 쓰지 않았는지 앞뒤 비교로 증명하기 위한 것 — 출력 부재는 미변경의 증거가 아니다."""
    snap = {}
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if not name.endswith(".md"):
                continue
            p = os.path.join(dirpath, name)
            with open(p, "rb") as fh:
                snap[os.path.relpath(p, root).replace(chr(92), "/")] = fh.read()
    return snap


def check_case(case):
    """한 case를 실행·대조해 (passed, detail) 반환."""
    fixture = case["fixture"]
    vault = os.path.join(FIXTURES_DIR, fixture)
    if not os.path.isdir(vault):
        return False, f"픽스처 폴더 없음: {vault}"
    # case 스키마 방어: 기대 조건이 하나도 없으면 오타로 조용히 PASS되는 것을 막는다.
    #  단 **자체 기대 필드를 갖는 모드**(chunk_split의 expect_total_rows·expect_min_subs 등)는
    #  키워드 대조를 쓰지 않는다 — 그 모드가 스스로 구조를 세어 판정하므로 여기서 요구하면
    #  의미 없는 키워드를 형식상 넣게 된다(방어가 오히려 케이스를 왜곡한다).
    if ("expect_clean" not in case and "expect_keywords" not in case
            and not case.get("chunk_split") and not case.get("aux_split")):
        return False, "case에 expect_clean·expect_keywords 둘 다 없음(lint-cases.json 오타 의심)"

    # fix_mode 케이스: fixture를 임시 복사본에서 --fix 실행 → 재lint로 위반 해소를 대조한다.
    #  원본 fixture는 절대 수정하지 않는다(placeholder copytree 패턴 재사용). 대조 3단 —
    #  ① --fix 실행 출력에 expect_keywords([FIXED] 요약) 전부 존재
    #  ② 수정 후 재lint 출력에 after_expect_absent(원 위반 문구) 전부 부재
    #  ③ 수정 후 재lint 출력에 after_expect_keywords 전부 존재 — "--fix가 건드리지 않아야 하는
    #     위반이 그대로 남았는가"(보수 동작: §7-24 섹션 밖 비제거 등)를 실증하는 보조 필드
    # backup_cleanup 케이스: §8 백업 정리(cleanup_backups)를 폴더 집합으로 대조한다.
    #  stdout 키워드만으로는 "지워지지 않아야 할 것이 남았는가"를 증명할 수 없어(출력이 없는 것은
    #  보존의 증거가 아니다) 실제 디렉터리 목록을 본다. 무플래그 실행도 함께 돌려 read-only 계약
    #  (정리는 --fix에서만 일어난다)을 같은 케이스에서 실증한다.
    # build_index 케이스: `--build-index`(생성)를 임시 복사본에서 돌린다.
    #  ① dry-run은 파일을 한 바이트도 바꾸지 않아야 하고(계약), ② 마커 밖 텍스트가 생성 출력에
    #  그대로 살아 있어야 하며, ③ 마커가 없는 vault는 덮어쓰지 않고 안내만 내야 한다.
    #  키워드 대조만으로는 ①을 증명할 수 없어(출력이 없는 것은 미변경의 증거가 아니다) 실제
    #  파일 바이트를 앞뒤로 비교한다.
    # build_index_write 케이스: **실제 쓰기 경로**(--dry-run 없이)를 돈다. dry-run만 돌리면
    #  파일을 만드는 분기가 한 번도 실행되지 않아, sub-index 생성·마커 치환·마커 밖 보존이
    #  "출력에서만" 맞는 상태로 통과할 수 있다. 여기서는 쓰인 파일을 다시 읽어 대조한다.
    if case.get("build_index_write"):
        tmp, dest = prepare_placeholder_vault(vault)
        idx = os.path.join(dest, "index.md")
        with open(idx, "rb") as fh:
            before = fh.read().decode("utf-8")
        out, rc, err = run_lint(dest, ["--build-index"])
        with open(idx, "rb") as fh:
            after = fh.read().decode("utf-8")
        subs = sorted(n for n in os.listdir(dest)
                      if n.startswith("index-") and n.endswith(".md"))
        leftovers = [n for n in os.listdir(dest) if n.endswith(".tmp-build-index")]
        sub_text = ""
        for n in subs:
            with open(os.path.join(dest, n), "rb") as fh:
                sub_text += fh.read().decode("utf-8")
        shutil.rmtree(tmp, ignore_errors=True)
        if err.strip():
            return False, "stderr 발생: " + err.strip().splitlines()[-1]
        if rc != 0:
            return False, f"쓰기 실행이 실패함 (rc={rc}): {out.strip()[:120]}"
        if leftovers:
            return False, "임시 파일 잔존: " + ", ".join(leftovers)
        if subs != case.get("expect_sub_files", []):
            return False, f"sub-index 파일 불일치 — 기대 {case.get('expect_sub_files', [])} / 실제 {subs}"
        for kw in case.get("expect_outside_preserved", []):
            if kw not in after:
                return False, "마커 밖 텍스트가 사라짐: " + kw
        missing = [kw for kw in case.get("expect_keywords", []) if kw not in after + sub_text]
        if missing:
            return False, "쓰인 파일에 누락: " + ", ".join(missing)
        present = [kw for kw in case.get("expect_absent", []) if kw in after + sub_text]
        if present:
            return False, "쓰인 파일에 있으면 안 되는 것: " + ", ".join(present)
        # 섹션 **순서** 검증 — 키워드 존재만 보면 조립 순서가 뒤바뀌어도 통과한다.
        #  §4 「생성 대상 6섹션」이 순서를 규정하므로 그 순서 자체가 계약이다(T3 리뷰 B1:
        #  구역 지연 조립로 바꾸며 프로젝트 테이블이 기능별 인덱스 뒤로 밀린 회귀가 실재했다).
        want_order = case.get("expect_section_order", [])
        if want_order:
            got = [ln for ln in after.splitlines() if ln.startswith("## ")]
            idx, missing_h = -1, []
            for h in want_order:
                try:
                    nxt = got.index(h, idx + 1)
                except ValueError:
                    missing_h.append(h)
                    break
                idx = nxt
            if missing_h:
                return False, ("섹션 순서 불일치 — 기대 %s / 실제 %s" % (want_order, got))
        if before == after:
            return False, "index.md가 갱신되지 않음(마커 치환 미발생)"
        return True, "실제 쓰기 대조: sub-index %d개 · 마커 밖 보존 · 임시 파일 0" % len(subs)

    if case.get("build_index"):
        tmp, dest = prepare_placeholder_vault(vault)
        before = _snapshot_md(dest)
        out, rc, err = run_lint(dest, ["--build-index", "--dry-run"])
        after = _snapshot_md(dest)
        shutil.rmtree(tmp, ignore_errors=True)
        if err.strip():
            return False, "stderr 발생: " + err.strip().splitlines()[-1]
        if before != after:
            changed = sorted(set(before) ^ set(after)) or [
                k for k in before if before[k] != after.get(k)]
            return False, "--dry-run이 파일을 변경함: " + ", ".join(changed[:3])
        if rc != case.get("expect_rc", 0):
            return False, f"종료 코드 불일치 — 기대 {case.get('expect_rc', 0)} / 실제 {rc}"
        missing = [kw for kw in case.get("expect_keywords", []) if kw not in out]
        if missing:
            return False, "생성 출력 키워드 누락: " + ", ".join(missing)
        present = [kw for kw in case.get("expect_absent", []) if kw in out]
        if present:
            return False, "생성 출력에 있으면 안 되는 문구: " + ", ".join(present)
        return True, "생성 대조 + 파일 미변경 확인: " + ", ".join(case.get("expect_keywords", []))

    if case.get("backup_cleanup"):
        tmp, dest, names = prepare_backup_cleanup_vault(vault)
        root = os.path.join(dest, "90_archive", "backup")
        before = sorted(os.listdir(root))
        out0, rc0, err0 = run_lint(dest)                 # 무플래그 = read-only
        after_ro = sorted(os.listdir(root))
        out1, rc1, err1 = run_lint(dest, ["--fix"])
        kept = sorted(os.listdir(root))
        shutil.rmtree(tmp, ignore_errors=True)
        if "== llm-wiki Lint:" not in out0 or "== llm-wiki Lint:" not in out1:
            tail = (err0 or err1).strip().splitlines()[-1] if (err0 or err1).strip() else "(stderr 없음)"
            return False, f"lint.py 비정상 종료(무플래그={rc0}/fix={rc1}): {tail}"
        if after_ro != before:
            return False, "무플래그 실행이 백업 폴더를 바꿨다(read-only 계약 위반)"
        expected = sorted(names[tok] for tok in case["expect_backup_kept"])
        if kept != expected:
            return False, f"잔존 폴더 불일치 — 기대 {expected} / 실제 {kept}"
        missing = [kw for kw in case.get("expect_keywords", []) if kw not in out1]
        if missing:
            return False, "--fix 출력 미검출 키워드: " + ", ".join(missing)
        return True, f"백업 정리 확인: {len(before)}개 → {len(kept)}개 (제거 {len(before) - len(kept)})"

    # aux_split 케이스: §4 1단계 **본체 구역 분리**를 실제 쓰기로 대조한다.
    #  ① 본체가 임계 이하로 내려갔는가 ② 덜어낸 구역이 자기 헤딩을 갖고 sub-index로 갔는가
    #  ③ **§7-23이 오탐하지 않는가** — 구역이 옮겨간 뒤에도 open question이 '등록됨'으로
    #     판정되는지를 재lint로 확인한다(이 검사가 없으면 「본체만 보는 판정」 회귀가 침묵한다).
    if case.get("aux_split"):
        tmp, dest = prepare_aux_split_vault(
            vault, case.get("concept_count", 260), case.get("open_questions", 2))
        out, rc, err = run_lint(dest, ["--build-index"])
        with open(os.path.join(dest, "index.md"), encoding="utf-8-sig") as fh:
            idx = fh.read()
        body_lines = idx.count("\n") + 1
        out2, rc2, err2 = run_lint(dest)
        problems = []
        if rc != 0:
            problems.append("build-index 종료코드 %d" % rc)
        limit = case.get("expect_body_limit", 400)
        if body_lines > limit and case.get("expect_under_limit", True):
            problems.append("본체 %d줄 > 임계 %d(덜어내기 미달)" % (body_lines, limit))
        for name in case.get("expect_aux_files", []):
            path = os.path.join(dest, name)
            if not os.path.exists(path):
                problems.append("덜어낸 구역 파일 없음: " + name)
                continue
            with open(path, encoding="utf-8-sig") as fh:
                aux = fh.read()
            if "type: index" not in aux:
                problems.append("%s에 type: index 없음" % name)
            if not any(l.startswith("## ") for l in aux.splitlines()):
                problems.append("%s에 자기 헤딩 없음" % name)
        for kw in case.get("after_expect_absent", []):
            if kw in out2:
                problems.append("수행 후 재lint에 위반 잔존: " + kw)
        shutil.rmtree(tmp, ignore_errors=True)
        if problems:
            return False, " / ".join(problems)
        return True, ("본체 %d줄(임계 %d 이하) · 덜어낸 구역 %d개 · §7-23 오탐 0"
                      % (body_lines, limit, len(case.get("expect_aux_files", []))))

    # chunk_split 케이스: §4 3단계 **순번 분할**과 stale sub-index 정리를 실제 쓰기로 대조한다.
    #  키워드만으로는 "행이 보존됐는가"·"빈 청크가 안 생겼는가"를 증명할 수 없어 생성된
    #  파일을 다시 읽어 **행 총계·임계 준수·목록 등재·델타 음성**을 직접 센다.
    if case.get("chunk_split"):
        tmp, dest = prepare_chunk_split_vault(
            vault, case.get("feature_count", 210), case.get("stale_names", []))
        out, rc, err = run_lint(dest, ["--build-index"])
        subs = sorted(n for n in os.listdir(dest)
                      if n.startswith("index-") and n.endswith(".md"))
        def _rows(name):
            with open(os.path.join(dest, name), encoding="utf-8-sig") as fh:
                text = fh.read()
            sec = text.split("## 기능별 인덱스", 1)[-1]
            return sum(1 for ln in sec.splitlines()
                       if ln.startswith("|") and "---" not in ln and "| 기능 |" not in ln
                       and "| 이름 |" not in ln)
        with open(os.path.join(dest, "index.md"), encoding="utf-8-sig") as fh:
            idx = fh.read()
        gen_subs = [s for s in subs if s != "index-notes.md"]
        total = sum(_rows(s) for s in gen_subs)
        limit = case.get("expect_row_limit", 200)
        problems = []
        if rc != 0:
            problems.append("build-index 종료코드 %d" % rc)
        over = [s for s in gen_subs if _rows(s) > limit]
        if over:
            problems.append("임계 초과 sub-index: " + ", ".join(over))
        empty = [s for s in gen_subs if _rows(s) == 0]
        if empty:
            problems.append("빈 sub-index 생성: " + ", ".join(empty))
        if case.get("expect_min_subs") and len(gen_subs) < case["expect_min_subs"]:
            problems.append("sub-index %d개 < 기대 %d개(순번 경로 미발동)"
                            % (len(gen_subs), case["expect_min_subs"]))
        if case.get("expect_total_rows") and total != case["expect_total_rows"]:
            problems.append("행 총계 %d ≠ 기대 %d(분할이 행을 잃거나 늘림)"
                            % (total, case["expect_total_rows"]))
        unlisted = [s for s in gen_subs if s[:-3] not in idx]
        if unlisted:
            problems.append("index.md 목록 미등재: " + ", ".join(unlisted))
        for stale in case.get("stale_names", []):
            if os.path.exists(os.path.join(dest, stale)):
                problems.append("stale sub-index 미제거: " + stale)
        for keep in case.get("expect_kept", []):
            if not os.path.exists(os.path.join(dest, keep)):
                problems.append("생성물이 아닌 파일이 삭제됨(델타 음성 실패): " + keep)
        shutil.rmtree(tmp, ignore_errors=True)
        if problems:
            return False, " / ".join(problems)
        return True, ("순번 분할 %d개·행 %d 보존·임계 %d 준수·stale %d 제거·델타 음성 유지"
                      % (len(gen_subs), total, limit,
                         len(case.get("stale_names", []))))

    # auto_split 케이스: `--auto-split`(임계 자동 분할·롤오버)을 임시 복사본에서 돌린다.
    #  ① dry-run은 파일을 한 바이트도 바꾸지 않아야 하고(계약 — 출력 부재는 미변경의 증거가
    #     아니므로 실제 바이트를 앞뒤 비교한다) ② 실행 출력에 expect_keywords가 전부 있어야 하며
    #  ③ after_expect_absent가 있으면 **수행 후 재lint**에서 그 위반이 사라져야 한다.
    #  `--fix`와 달리 승인 불요 경로라 별도 모드로 둔다(두 규약을 한 케이스에 섞지 않는다).
    if case.get("auto_split"):
        tmp = tempfile.mkdtemp(prefix="lint-eval-split-")
        dest = os.path.join(tmp, os.path.basename(vault))
        shutil.copytree(vault, dest)
        dry_before = _snapshot_md(dest)
        out_dry, rc_dry, err_dry = run_lint(dest, ["--auto-split", "--dry-run"])
        dry_after = _snapshot_md(dest)
        if dry_before != dry_after:
            shutil.rmtree(tmp, ignore_errors=True)
            changed = sorted(k for k in set(dry_before) | set(dry_after)
                             if dry_before.get(k) != dry_after.get(k))
            return False, "--auto-split --dry-run이 파일을 변경함: " + ", ".join(changed)
        out, rc, err = run_lint(dest, ["--auto-split"])
        out2, rc2, err2 = run_lint(dest)
        if rc not in (0, 1):
            tail = err.strip().splitlines()[-1] if err.strip() else "(stderr 없음)"
            return False, f"--auto-split 비정상 종료({rc}): {tail}"
        missing = [kw for kw in case.get("expect_keywords", []) if kw not in out]
        if missing:
            return False, "--auto-split 출력 미검출 키워드: " + ", ".join(missing)
        present = [kw for kw in case.get("expect_absent", []) if kw in out]
        if present:
            return False, "--auto-split 출력에 금지 키워드: " + ", ".join(present)
        residual = [kw for kw in case.get("after_expect_absent", []) if kw in out2]
        if residual:
            return False, "수행 후 재lint에 위반 잔존: " + ", ".join(residual)
        missing2 = [kw for kw in case.get("after_expect_keywords", []) if kw not in out2]
        if missing2:
            return False, "수행 후 재lint 기대 키워드 미검출: " + ", ".join(missing2)
        # **롤오버 방향 검증** — 출력 키워드만 보면 「오래된 것부터」인지 알 수 없다.
        #  log.md는 최신이 위라, 위치로 고르는 구현은 정반대(최신부터)로 옮기면서도
        #  "롤오버 — log.md"라는 같은 줄을 낸다. 남은 월·옮겨진 월을 직접 센다.
        want_kept = case.get("expect_kept_months")
        want_arch = case.get("expect_archive_months")
        if want_kept or want_arch:
            lp = os.path.join(dest, "log.md")
            with open(lp, encoding="utf-8-sig") as fh:
                lt = fh.read()
            m = re.search(r"(?ms)^##\s*최근 변경\b.*?(?=^##\s|\Z)", lt)
            kept_months = sorted({d[:7] for d in
                                  re.findall(r"(?m)^- \[(\d{4}-\d{2}-\d{2})\]", m.group(0) if m else "")})
            arch_months = sorted(os.path.basename(f)[:-3] for f in
                                 glob.glob(os.path.join(dest, "90_archive", "log", "*.md")))
            if want_kept is not None and kept_months != want_kept:
                return False, "남은 월 불일치 — 기대 %s / 실제 %s(오래된 것부터가 아닐 수 있다)" % (want_kept, kept_months)
            if want_arch is not None and arch_months != want_arch:
                return False, "아카이브 월 불일치 — 기대 %s / 실제 %s" % (want_arch, arch_months)
            # 이동 대상이 아닌 항목이 **남아 있는가**(유실 가드). 초기 구현은 날짜 없는 항목을
            #  이동 목록에 담았다가 월 분배에서 빼면서 어느 파일에도 쓰지 않아 통째로 잃었다.
            for kw in case.get("expect_kept_contains", []):
                if kw not in lt:
                    return False, "남아야 할 항목이 사라짐(유실): " + kw
        # 수행 **결과 파일**의 내용을 직접 대조한다. stdout 키워드는 처방이 「돌았다」만 말하고
        #  「옳게 썼다」는 말하지 않는다 — 코드 경로 도달과 결과 정확성은 다른 것이라,
        #  경로만 태우는 케이스는 버그를 되돌려도 그대로 통과한다(T5 quality 2R M1).
        for rel, needles in (case.get("expect_file_contains") or {}).items():
            fp = os.path.join(dest, rel.replace("/", os.sep))
            if not os.path.exists(fp):
                return False, "결과 파일 없음: " + rel
            with open(fp, encoding="utf-8-sig") as fh:
                ft = fh.read()
            missing_n = [n for n in needles if n not in ft]
            if missing_n:
                return False, "%s에 기대 문자열 없음: %s" % (rel, ", ".join(missing_n))
        # **개수**를 대조한다. 중복 등록은 존재 여부로 잡히지 않는다 — 있기는 있기 때문이다.
        #  재분할이 이전 회차 하위를 허브 표에 다시 넣는 회귀가 정확히 그 형태였다.
        for rel, wants in (case.get("expect_file_count") or {}).items():
            fp = os.path.join(dest, rel.replace("/", os.sep))
            if not os.path.exists(fp):
                return False, "결과 파일 없음: " + rel
            with open(fp, encoding="utf-8-sig") as fh:
                ft = fh.read()
            for needle, want in wants.items():
                got = ft.count(needle)
                if got != want:
                    return False, "%s의 '%s' 개수 불일치 — 기대 %d / 실제 %d" % (rel, needle, want, got)
        shutil.rmtree(tmp, ignore_errors=True)
        return True, "--auto-split dry-run 무변경 + 수행 확인: " + ", ".join(case.get("expect_keywords", []))

    if case.get("fix_mode"):
        tmp = tempfile.mkdtemp(prefix="lint-eval-fix-")
        dest = os.path.join(tmp, os.path.basename(vault))
        shutil.copytree(vault, dest)
        out1, rc1, err1 = run_lint(dest, ["--fix"])
        out2, rc2, err2 = run_lint(dest)
        shutil.rmtree(tmp, ignore_errors=True)
        if "== llm-wiki Lint:" not in out1 or "== llm-wiki Lint:" not in out2:
            tail = (err1 or err2).strip().splitlines()[-1] if (err1 or err2).strip() else "(stderr 없음)"
            return False, f"lint.py 비정상 종료(fix={rc1}/재실행={rc2}): {tail}"
        missing = [kw for kw in case.get("expect_keywords", []) if kw not in out1]
        if missing:
            return False, "--fix 출력 미검출 키워드: " + ", ".join(missing)
        residual = [kw for kw in case.get("after_expect_absent", []) if kw in out2]
        if residual:
            return False, "수정 후 재lint에 위반 잔존: " + ", ".join(residual)
        missing2 = [kw for kw in case.get("after_expect_keywords", []) if kw not in out2]
        if missing2:
            return False, "수정 후 재lint 기대 키워드 미검출(비제거 대상이 사라짐 의심): " + ", ".join(missing2)
        return True, "--fix 적용·재lint 해소 확인: " + ", ".join(case.get("expect_keywords", []))

    tmp = None
    if case.get("git_repo"):
        # §7-26: 실제 git 이력이 있어야 뒤처짐 계산이 실증된다. git이 없는 환경에선 이 케이스만
        #  SKIP하고 전체는 통과시킨다(fail-open — 검사 자체가 fail-open이므로 골든도 같은 규약).
        tmp, vault = prepare_git_repo_vault(vault, case.get("synced_mode", "first"))
        if tmp is None:
            return True, "SKIP (git 미설치·실행 실패 — §7-26 골든은 git 필요)"
    elif case.get("placeholder"):
        tmp, vault = prepare_placeholder_vault(vault)
    elif case.get("bad_encoding"):
        tmp, vault = prepare_bad_encoding_vault(vault)
    elif case.get("bad_index"):
        tmp, vault = prepare_bad_index_vault(vault)
    out, rc, err = run_lint(vault)
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    # lint.py는 ERR가 있으면 exit 1(L-5 — A-4/B-3 자동 게이트용), 없으면 0, 사용법 오류 2다.
    #  정상 실행은 stdout에 리포트 헤더('== llm-wiki Lint:')를 내므로, 헤더가 있으면 rc와 무관하게
    #  결과를 파싱한다(exit 1이 곧 ERR 검출이라 위반 fixture는 정상이다). 헤더가 없는 종료만
    #  진짜 크래시(런타임 예외)로 보고 FAIL 처리한다.
    if "== llm-wiki Lint:" not in out:
        tail = err.strip().splitlines()[-1] if err.strip() else "(stderr 없음)"
        return False, f"lint.py 비정상 종료(exit {rc}): {tail}"

    if case.get("expect_clean"):
        # 정상 vault: ERR·WARN 0이어야 한다(INFO는 허용).
        # expect_absent는 clean 케이스에도 적용한다 — "조용히 건너뛰어야 하는" 동작(§7-26 fail-open 등)은
        #  ERR/WARN 0만으로는 실증되지 않는다(INFO로 새어나와도 clean 판정은 통과하므로).
        present = [kw for kw in case.get("expect_absent", []) if kw in out]
        if present:
            return False, "부재 기대 키워드가 출력에 존재(오탐): " + ", ".join(present)
        ok = ("[ERR] 오류 0건" in out) and ("[WARN] 경고 0건" in out)
        if ok:
            return True, "WARN/ERR 0 (정상)"
        return False, "위반 0을 기대했으나 ERR/WARN 발생"

    missing = [kw for kw in case.get("expect_keywords", []) if kw not in out]
    if missing:
        return False, "미검출 키워드: " + ", ".join(missing)
    present = [kw for kw in case.get("expect_absent", []) if kw in out]
    if present:
        return False, "부재 기대 키워드가 출력에 존재(오탐): " + ", ".join(present)
    return True, "검출: " + ", ".join(case.get("expect_keywords", []))


def main():
    if not os.path.isfile(LINT_PY):
        print(f"lint.py를 찾을 수 없음: {LINT_PY}")
        sys.exit(2)
    try:
        with open(CASES_JSON, encoding="utf-8") as fh:
            cases = json.load(fh)["cases"]
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print(f"lint-cases.json 로드 실패: {e}")
        sys.exit(2)

    print("== llm-wiki lint 골든 회귀 ==")
    passed = 0
    for case in cases:
        ok, detail = check_case(case)
        mark = "PASS" if ok else "FAIL"
        print(f"[{mark}] {case['fixture']} — {detail}")
        if ok:
            passed += 1

    total = len(cases)
    print(f"\n결과: {passed}/{total} PASS")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
