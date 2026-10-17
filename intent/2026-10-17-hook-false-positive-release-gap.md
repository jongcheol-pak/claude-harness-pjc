# Intent: 외부 작업 경고·차단 hook 의 데이터 문자열 오탐 수정 · 릴리즈 누락 판정을 버전 hook 에

Author: 사용자. Status: approved.

## Problem
원문 요청: 「대장에 올리지 말고 수정해줘」 — 직전 보고의 두 항목, ① guard-bash 외부 작업 경고가 따옴표로 싼 검색 문자열(`git grep -l 'gh pr merge'`)·본문 속 명령 이름에 발화하는 오탐(계획 체인 전체 ×17) ② 릴리즈 누락 판정을 버전 경고 hook(warn-version-drift)이 맡게 하는 것(plan 2 후보 라운드에서 보류였으나 대장에 오르지 않고 유실).
Q: block-destructive 가 파일에 쓰는 heredoc 본문 속 force push 문구를 막는 오탐도 같이 고칠까요? / 선택지: 포함 (권장) · 제외 · 재진술 수정 / A: 포함 (권장)

## Proposed outcome
① 외부 작업 경고는 실행되지 않는 따옴표 문자열(검색 패턴·인자 값) 속 명령 이름에 뜨지 않는다. 셸·인터프리터가 실행하는 따옴표와 `$(…)`·백틱이 든 따옴표는 계속 검사한다. ② SessionStart 버전 hook 이 마지막 릴리즈 이후 origin/main 에 plugins/ 커밋이 있으면 알린다. ③ block-destructive 가 앞에 다른 명령이 이어진 데이터-싱크 heredoc(`… && cat > "$N" <<'EOF'`) 본문을 실행 명령으로 읽지 않는다.

## Affected users and systems
pjc 를 쓰는 모든 세션(①③ — guard-bash·block-destructive)과 pjc 하니스 레포 세션(② — warn-version-drift). 골든 회귀(hook-cases.json·scenarios)와 rationale 문서, harness-conventions 의 「판정 시점」 서술.

## Constraints
경고는 exit 0 비차단 유지. block-destructive 는 오탐 수정만(골든 실증 — 수정 전 차단 음성 대조 + 실행자 heredoc 차단 유지). 같은 싱크 판정을 가진 guard-bash 사본은 heredoc 소비자 판정으로 맞추며, 그쪽의 미탐 보완(`bash <<EOF | tee log` 본문)은 델타 음성 짝을 붙인다. 실행자로 가는 heredoc·`bash -c` 따옴표는 계속 검사(미탐 금지). ② 는 SessionStart 1회, 원격 조회는 캐시. `.ps1` 은 UTF-8 BOM·CRLF.

## Open questions
없음.
