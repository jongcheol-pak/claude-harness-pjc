# -*- coding: utf-8 -*-
"""픽스처 — 「관련 파일 파서 동기」 축이 대조하는 Python 쪽 최소 구현이다."""
import re


def check_related_files(stripped_lines, raw_lines):
    """§7-21 — `## 관련 파일` 섹션의 `- ` 항목에서 구분자를 담은 백틱 토큰을 모은다."""
    out, in_rel = [], False
    for i, sl in enumerate(stripped_lines):
        s = sl.strip()
        if re.match(r"^##\s*관련 파일\b", s):
            in_rel = True
            continue
        if in_rel and s.startswith("## "):
            in_rel = False
        if in_rel and s.startswith("-"):
            out += [t for t in re.findall(r"`([^`\n]+)`", raw_lines[i])
                    if "/" in t or "\\" in t]
    return out
