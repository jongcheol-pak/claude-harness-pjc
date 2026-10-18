# 병렬 실행 (`pjc:chain-plan` — 의존 없는 계획을 별도 worktree 에서)

> `../SKILL.md` 「체인 승인」이 병렬 그룹을 정할 때, 「Run·Task」·「워커 루프」가 병렬 그룹의 계획을 다룰 때 이 파일을 연다. `interrupt.md`·`continuation.md`·`manual-resume.md`·`compaction.md`·`resume.md` 도 병렬 계획이면 여기를 가리킨다. 그룹이 없는 체인은 이 파일을 쓰지 않는다 — 「워커 루프」의 직렬 그대로다.

## 병렬 그룹

- **인터뷰 실측 뒤, 체인 승인 전에 정한다 — 체인 순서에서 이웃한 계획을 앞에서부터 묶되 그룹 안 모든 쌍이 넷을 다 만족할 때만 한 그룹이다** — 이웃끼리만 묶어야 그룹 앞뒤의 직렬 순서가 사용자가 준 순서와 어긋나지 않는다.
  - ① 서로 의존하지 않는다 — 인터뷰의 「근거로 정한 것」 ① 이 상대 계획의 산출물을 가리키지 않는다
  - ② 실측의 바뀌는 파일이 겹치지 않는다 — `../scripts/chain-merge.gitattributes` 가 다루는 경로와 대상 레포 Deferred 대장(`AGENTS.md` `## Plan Location`)은 판정에서 뺀다. 바뀌는 영역이 「워커 실측 후 확정」인 계획은 겹침을 모르므로 묶지 않는다
  - ③ 검증이 새 체크아웃에서 돈다 — Karina 는 `git worktree add` 만 하고 무시 대상 파일을 옮기지 않는다. 대상 레포 `git status --ignored --short` 에 검증 명령이 읽는 경로(`.env`·로컬 설정·빌드 캐시)가 있으면 그 레포에서는 묶지 않는다
  - ④ 그룹 크기는 동시 상한 이하다 — 기본 2. 사용자가 체인 승인 `E` 로 바꾼다
- **체인 승인의 `병렬:` 줄은 `그룹 A = plan 2·3 · 그룹 B = plan 5·6 — 동시 상한 2 · 체인 브랜치 <이름> (근거: 의존 없음·바뀌는 파일 겹침 없음)` 이고, 없으면 `없음 — <이유 한 구>` 다** — 체인 브랜치는 `Y` 면 체인 시작 때 대상 레포의 `git branch --show-current`, `P` 면 위에서 만든 `pjc/chain-<Run id 의 run_ 뒤 앞 8자>` 이고(`pr-mode.md`「켜기」) 병합이 들어갈 곳이다. Run 전이라 이름이 없는 승인 화면에서는 `<현재 브랜치>(P 면 새 pjc/chain-…)` 로 적는다.
- **`Y` 는 이 그룹의 worktree 로컬 병합(양방향)도 위임한다** — 글로벌 `~/.claude/CLAUDE.md` 「스킬·계획 우선」의 체인 worktree 예외가 이 위임을 별도 승인에서 뺀다. push·PR 은 승인 대상이 아니라 위임할 것이 없고(스킬 실행 안 — PR 모드의 워커 merge 도 같다), rebase 는 덮지 않는다.

## Run·Task

- **그룹 안 task 끼리는 `--deps` 를 걸지 않고 전부 그룹 바로 앞 task 들에 걸며, 그룹 바로 뒤 task 는 그룹의 모든 task 에 건다.**
- **뒤 계획을 띄우는 시점은 `--deps` 가 아니라 그 그룹의 병합 완료가 정한다** — task 는 체인 승인 직후 한꺼번에 만들어 나중에 생기는 이어받기·병합 준비 task 가 deps 에 없고, `completed` 는 병합 전에 온다.
- **병렬 계획의 spec 은 `spec-format.md`「spec 서식」 의 `병렬:` 줄을 채운다.**

## 띄우기

- **PR 모드 체인이면 띄우기 전에 `pr-mode.md`「병렬」 의 그룹 전 확인을 먼저 한다** — 로컬 체인 브랜치가 원격보다 앞서 있으면 그 그룹은 직렬로 돈다.
- **그룹의 계획을 한 번에 띄운다 — 대상 레포 폴더가 아니라 새 worktree 다:**

  ```
  <CLI> orchestration worker-start --json --task <task id> --agent claude --worktree new-child --repo "<대상 레포 경로>" --base-branch <체인 브랜치> --name chain-<Run id 의 run_ 뒤 8자>-p<N> 2>/dev/null
  ```

  - **응답 갈래는 「워커 루프」와 같다 — `ok: false` 는 `cli-errors.md`「오류 응답」, `ok: true` 인 이상 응답은 `cli-errors.md`「시작 이상 응답」.** 이름이 같은 폴더가 이미 있다는 거절이면 그 worktree 를 `--worktree "<그 경로>"` 로 다시 쓴다.
  - **`--name` 에 Run 과 계획 번호를 넣는다** — 기본 이름은 무작위라, 넣지 않으면 재개(`resume.md`)가 브랜치를 계획에 잇지 못한다. Run id 는 `run_` 로 시작해 앞 8자로 자르면 체인끼리 갈리지 않으므로 `run_` 뒤에서 8자를 뗀다. 이름을 고를 때는 `-p<N>` 을 끝에 고정해 맞춘다 — `-p1` 이 `-p10` 에도 걸리지 않게.
  - **응답 `worker.workingDir` 이 그 계획의 worktree 경로이고 브랜치는 `git -C "<workingDir>" branch --show-current` 다** — 응답에 브랜치 필드가 없다.
- **첫 워커의 `workingDir` 이 대상 레포 루트 아래면 그룹의 나머지를 띄우지 않는다 — 뜬 워커는 끝까지 돌려 「병합」으로 넣고 나머지는 그 뒤 직렬로 돌린다** — Karina 설정 `workspace_dir` 이 레포 안이면 hook 이 worktree 루트에서 멈추지 않고 주 레포의 낡은 `plan.md` 로 게이트를 통과한다. 그 설정은 CLI 로 읽지 못해 띄운 뒤에야 안다.
- **대기는 워커마다 `--dispatch`·`--repo`·`--label` 을 같은 순서로 이어 한 번 띄운다:**

  ```
  python "<skill>/scripts/wait-worker.py" --cli <CLI> --dispatch <id1> --repo "<workingDir1>" --label "Plan <N1>/<총>" --dispatch <id2> --repo "<workingDir2>" --label "Plan <N2>/<총>"
  ```

  - **배치의 메시지가 어느 워커 것인지는 메시지의 `from`(handle)과 `payload` 의 dispatch-id 로 가른다.**
  - **한 워커가 `worker_done` 이면 남은 워커의 dispatch 로 대기를 먼저 다시 띄운 뒤 그 워커를 「병합」한다** — 병합·검증에 몇 분이 드는 동안 남은 워커의 질문이 쌓인다.

## 병합

`worker_done`(succeeded)을 받은 순서대로 하나씩 한다. 병합 중에 다른 워커가 끝나면 앞 병합이 끝난 뒤에 한다. **PR 모드 체인이면 이 절·「충돌·검증 실패」·「버전」 대신 `pr-mode.md`「병렬」 을 따른다** — 워커가 PR 을 원격에서 merge 하므로 여기서 로컬로 다시 병합하면 체인 브랜치가 원격과 갈라진다.

- **ⓐ 주 레포가 깨끗할 때만 한다 — `git -C "<대상 레포 경로>" status --porcelain --untracked-files=no` 가 비어 있고 현재 브랜치가 체인 브랜치여야 한다. 아니면 병합하지 않고 보고하고 멈춘다(stash·폐기하지 않는다)** — 미커밋 변경이 있으면 git 이 병합을 거부하거나 `--abort` 가 그 변경을 되살리지 못할 수 있고, 섞인 트리의 검증은 판정이 오염된다. 워커에 넘겨도 주 레포는 고칠 수 없다.
- **ⓑ 속성이 걸리는지 본다 — `git -C "<대상 레포 경로>" -c core.attributesFile="<skill>/scripts/chain-merge.gitattributes" check-attr merge -- docs/plans/chain-<Run id>.md docs/plans/history.md plan.md notes.md`** — `core.attributesFile` 은 우선순위가 가장 낮아 레포의 `.gitattributes` 가 같은 경로를 정하면 그쪽이 이긴다. `union`·`chaintheirs` 가 아닌 경로는 일반 병합으로 두고 진행한다(충돌하면 「충돌·검증 실패」).
- **ⓒ 커밋하지 않고 병합한다:**

  ```
  git -C "<대상 레포 경로>" -c core.attributesFile="<skill>/scripts/chain-merge.gitattributes" -c merge.chaintheirs.driver='cp -f %B %A' merge --no-ff --no-commit <워커 브랜치>
  ```

  - **속성 파일을 셸 리다이렉트로 새로 쓰지 않는다** — `guard-bash` 가 `plan.md` 문자열을 담은 셸 쓰기를 막아, 고정 파일을 쓴다.
  - **`warn-external-ops` 의 「git merge」 경고는 체인 승인 위임과 글로벌 예외가 덮는다 — 이 병합에서 멈추지 않는다.**
  - **충돌(exit ≠ 0)이면 `git merge --abort` 뒤 아래 「충돌·검증 실패」로 간다. untracked 파일이 덮인다는 거절은 ⓐ 와 같이 보고하고 멈춘다.**
- **ⓓ 그 계획 spec 의 「근거로 정한 것」 ③ 검증을 주 레포에서 돌린다 — 실패하면 `git merge --abort` 뒤 「충돌·검증 실패」** — 계획마다 자기 worktree 에서 통과했어도 합친 결과는 아무도 재지 않았다. `reset --hard` 를 쓰지 않으려고 커밋 전에 잰다.
- **ⓔ 경로 없는 `git commit` 으로 끝낸다 — 제목 `설정: 병합 — plan <N>/<총> <한 줄>`, 메시지는 heredoc `-m`, 끝에 `2>&1`** — 병합 중에는 git 이 경로 한정 커밋을 거부한다(`AGENTS.md` 「병행 세션의 커밋」의 예외). **시크릿 경고가 하나라도 뜨면 커밋하지 않고 `git merge --abort` 한 뒤 사용자에게 넘긴다**(`../SKILL.md` 「답하는 기준」 사용자 몫 ①) — 워커 단계의 판정을 승계하지 않는다.
- **병합 커밋은 `../SKILL.md` 「하지 않는 것」 「파일 수정」의 예외다** — 코디네이터가 만드는 것은 병합 커밋 하나이고, 파일 내용은 워커가 만들었다.

## 충돌·검증 실패

- **같은 탭에 「병합 준비」 task 를 다시 배정한다 — 워커가 그 계획의 맥락을 쥐고 있다:**

  ```
  <CLI> orchestration task-create --json --task-title "plan <N>/<총> 병합 준비 <k> — <한 줄>" --spec "$(cat <<'EOF'
  [chain-plan 병합 준비] plan <N>/<총>
  CLI: <spec 의 CLI 줄 값>
  할 일: 이 worktree 의 브랜치에 체인 브랜치 <이름> 을 git merge 로 합친다(rebase 금지 — history rewrite 는 별도 승인이다). 충돌은 아래 재진술을 기준으로 양쪽 의도를 살려 풀고, 검증을 돌려 통과하면 커밋한 뒤 보고한다.
  사유: <충돌 파일 목록 | 검증 실패 출력 요지>
  검증: <spec ③ 명령>
  재진술: <plan N spec 의 재진술 6항목 그대로>
  보고: 배정문 끝의 worker_done 명령에서 karina-cli 를 CLI 줄의 값으로 바꾸고 --body "결과: <커밋 sha> · 검증: <명령과 결과>" 를 더한다. 풀 수 없으면 --outcome failed 에 사유를 싣는다.
  EOF
  )"
  <CLI> orchestration worker-start --json --task <새 task id> --terminal <그 워커 handle> 2>/dev/null
  ```

  - **`--terminal` 재배정은 같은 Run 안이고 그 탭의 앞 배정이 정산됐을 때만 된다** — `worker_done` 뒤라 정산돼 있다. 응답 갈래는 「띄우기」와 같다.
  - **새 dispatch 를 대기에 더해 다시 띄우고, succeeded 면 「병합」 ⓐ 부터 다시 한다.**
- **같은 계획의 병합 준비가 3회째도 충돌·실패면 그 계획은 「멈춤」이다.**

## 버전

- **대상 레포 `AGENTS.md` 에 버전 규약(버전 정본·버전 커밋)이 있을 때만 한다 — 병렬 워커는 spec `병렬:` 줄 때문에 버전 task 를 만들지 않는다.**
- **`Y` 승인에서 대상 레포가 체인 끝 PR 대상이고 그 Release 가 「버전 전용 PR」 을 지목하면 아래 재배정을 하지 않는다(`pr-mode.md`「켜기」)** — 그룹 버전 커밋이 체인 끝 PR 에 squash 되면, merge 를 맡는 `pjc:pr` ship 의 「버전 전용 PR 잇기」 가 버전을 한 번 더 올린다.
- **그룹의 마지막 워커 — 다른 그룹원이 전부 병합되거나 멈춤으로 빠진 뒤 병합을 기다리는 워커 — 에게는 충돌이 없어도 「병합 준비」 task 를 재배정하고 `할 일:` 끝에 「합친 뒤 대상 레포 `AGENTS.md` 의 버전 규약대로 그룹(plan <목록>)의 버전을 한 번 올리는 별도 커밋을 더한다」를 덧붙인다** — 코디네이터가 직접 고치면 `guard-write` 의 plan 존재 게이트가 주 레포 루트의 `plan.md` 유무에 따라 막는다. 병합된 그룹원이 없으면 올리지 않는다.

## 닫기

- **병합 커밋(PR 모드면 주 레포 fast-forward)이 끝난 뒤 `release.md`「닫기」 로 닫고, 그 탭의 마지막 dispatch(재배정했으면 재배정 dispatch)로 닫는다** — 앞 dispatch 의 release 도 같은 탭을 닫는다.
- **worktree 폴더와 브랜치는 지우지 않는다 — 경로·브랜치는 보고에 싣는다** — Karina 에 지우는 CLI 가 없고, 폴더 안 `plan.md` 는 gitignore 인 레포에서 복구 경로가 없다. 재개(`resume.md`)도 그 `plan.md` 로 완료를 판정한다.

## 중단·이어받기·사후 완료

- **사용자 중단(`interrupt.md`「사용자 중단」)이면 돌고 있는 병렬 워커 전부를 retain 하고, 진행 중인 병합이 있으면 먼저 `git merge --abort` 한다.**
- **이어받기(`continuation.md`「이어받기」)가 온 병렬 계획은 병합하지 않고 이어받기를 먼저 한다** — 앞 워커는 이어받기를 띄우기 직전에 닫고, 이어받기 워커는 `--worktree new-child` 대신 `--worktree "<그 계획의 workingDir>"` 로 같은 worktree 에 띄워 대기에 넣는다. 병합은 이어받기가 끝나 `남은 일` 이 「없음」이 된 뒤 한 번이다.
- **사후 완료(`manual-resume.md`「사후 완료」)가 병렬 계획이면 다음 계획으로 가지 않고 「병합」으로 간다.**

## 멈춤

- **그룹의 한 워커가 failed·stall(retain 뒤)이거나 병합 준비 3회 실패면 새 계획은 띄우지 않고, 그룹의 나머지는 끝까지 기다려 병합한 뒤 체인을 멈추고 보고한다** — 끝난 일을 버리지 않는다.
- **멈춘 계획의 worktree·브랜치는 남긴다** — 「plan N부터」 재개(`resume.md`)가 이어 받는다.

## 보고

- **`report.md`「보고 서식」 의 `병렬 병합:` 줄에 그룹마다 plan · 병합 커밋 sha(PR 모드면 PR URL·merge 커밋 — 또는 미병합 사유) · worktree 경로 · 브랜치를 싣는다.**
