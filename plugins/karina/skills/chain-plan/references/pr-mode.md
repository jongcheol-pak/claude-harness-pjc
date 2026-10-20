# PR 모드 (`karina:chain-plan` — 계획마다 PR 을 merge 까지)

> `../SKILL.md` 「체인 승인」이 승인 화면의 `PR 모드:` 줄을 채울 때(「켜기」), 체인이 `P` 로 승인돼 워커가 spec 의 `PR 모드: 켬` 줄을 받았을 때(「워커」), 코디네이터가 PR 모드 체인의 계획을 잇거나 병렬 그룹을 다룰 때(「직렬」·「병렬」) 이 파일을 연다. `Y` 로 승인한 체인은 계획 사이를 로컬 병합으로 잇고, 체인이 끝나면 「Y 체인 끝 PR」 하나만 쓴다(`report.md`「인계 파일 정리」 뒤). `P` 체인이 끝나면 「P 체인 끝 PR」 이 체인 브랜치를 기본 브랜치로 올린다.
> 출처는 Cursor pstack 의 autopilot-full 이다 — 고정 위치 `https://github.com/cursor/plugins/blob/f713f14203cd6420cec13cd7c55c32d598dbab68/pstack/skills/poteto-mode/playbooks/autopilot-full.md`. 계획마다 한 주인이 빌드에서 merge 까지 PR 을 맡는다(*"One owner carries each PR from build to merge"*). 스택 PR 은 `stack-mode.md` 에서만 쓰고 Graphite·rebase 는 들이지 않았다 — 앞선 base 는 merge 로 합친다(rebase 는 history rewrite 라 karina 에서 별도 승인이다).
>
> 목차: 켜기(출발 브랜치 · 체인 브랜치 만들기) · 워커(마무리 순서 · 화면 줄 task 직렬 예외 · base 합치기 · 멈춘 자리 표) · 직렬 · 병렬 · Y 체인 끝 PR · P 체인 끝 PR

## 켜기

**코디네이터가 체인 승인 화면을 내기 전에 1회 판정한다.**

- **PR 모드는 셋이 모두 참일 때만 고를 수 있다 — `git -C "<대상 레포 경로>" remote get-url origin` 이 `github.com` 을 담고 · `gh auth status` 가 exit 0 이고 · 출발 브랜치가 깨끗하다** — 앞의 둘은 워커의 `../../implement/references/pr-flow.md`「적용 판정」 과 같은 조건이다. 셋째는 아래 셋이 모두 참인 것이고, `P` 는 지금 브랜치를 버리고 기본 브랜치에서 새 체인 브랜치를 가르므로 지금 브랜치에만 있는 것이 체인에서 빠지지 않게 막는다(사용자 답 「PR 모드 불가로 표시」).
  - 기본 브랜치를 정한다 — `pr-flow.md`「브랜치」 머리의 `git symbolic-ref --short refs/remotes/origin/HEAD` → `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` 순서다.
  - `git -C "<대상 레포 경로>" status --porcelain --untracked-files=no` 가 비어 있다 — `parallel.md`「병합」 ⓐ 와 같이 stash·폐기하지 않는다. untracked 는 보지 않는다 — 새 브랜치로 넘어가도 커밋되지 않고, 워커 커밋은 경로 한정이다.
  - `git -C "<대상 레포 경로>" fetch -q origin` 뒤 지금 브랜치에 기본 브랜치에 없는 커밋이 0 이다 — 지금 브랜치가 `karina/*` 이고 `gh pr view <브랜치> --json state,headRefOid` 가 MERGED 면 `git rev-list --count <headRefOid>..HEAD`, 그 밖이면 `git rev-list --count origin/<기본>..HEAD` 다. squash merge 된 옛 `karina/*` 는 커밋이 기본 브랜치 조상이 아니어서 둘째 식이 늘 0 이 아니다(`pr-flow.md`「merge 된 브랜치에서 시작할 때」 의 headRefOid 선례). push 안 된 커밋도, push 됐지만 merge 안 된 기능 브랜치의 커밋도 여기서 걸린다. 재개가 옛 체인 브랜치를 다시 쓰고 지금 브랜치가 그 브랜치면 이 줄은 재지 않는다(`resume.md`「재개」).
- **체인 브랜치는 `Y` 면 체인 시작 때 대상 레포의 `git branch --show-current` 이고, `P` 면 위에서 만든 `karina/chain-<Run id 의 run_ 뒤 앞 8자>` 다** — `P` 의 PR 들이 이미 merge 된 옛 브랜치로 들어가지 않게 한다(2026-10-19 체인 승인 화면의 체인 브랜치가 merge 된 `karina/release-v1.392.0` 이었다).
- **승인 화면의 줄은 `PR 모드: 꺼짐(끝에 PR 하나) — [P] 로 켠다(<기본>에서 새 체인 브랜치)` 이고, 셋 중 하나라도 거짓이면 `PR 모드: 불가 — <거짓인 조건과 수치>` 이며 선택지 줄에서 `[P]` 를 뺀다** — 꺼짐이어도 체인이 끝까지 성공하면 코디네이터가 「Y 체인 끝 PR」 로 PR 하나를 연다. 끝 PR 이 없는 대상(아래 「Y 체인 끝 PR」 의 조건이 거짓)이면 괄호를 `(끝 PR 없음 — <거짓인 조건>)` 으로 바꾼다.
- **`Y`·`P` 둘 다 버전 커밋을 막는 경우가 하나 있다 — 대상 레포가 끝 PR 대상이고 그 `AGENTS.md` Release 가 「버전 전용 PR」 을 지목하면 spec 재진술 `제약조건` 끝에 「버전 올리기 task 를 만들지 않는다(체인 끝 PR — merge 를 맡는 `karina:pr` ship 이 버전 전용 PR 을 잇는다)」 를 더한다(`spec-format.md`「spec 서식」)** — 버전 커밋이 끝 PR 에 squash 되면 기능 변경과 섞이고, ship 의 「버전 전용 PR 잇기」(`../../pr/references/ship.md`)가 버전을 한 번 더 올린다. `P` 의 계획 PR 도 기본 브랜치가 아닌 체인 브랜치로 merge 되므로 같다. Release 가 다른 형식인 레포는 지금처럼 체인 안에서 버전 커밋을 만들고 그 커밋이 끝 PR 에 실린다.
- **`P` 는 `Y` 와 같은 위임에 PR 모드를 더한 답이다** — objective 의 `[체인 승인: <답 원문>]` 이 `P` 를 담아 압축 뒤에도 모드를 되찾는다(`compaction.md`「압축 뒤 복원」).
- **`P` 면 run-create 뒤 task-create 전에 체인 브랜치를 만든다 — 이름은 Run id 로 정해져 run-create 앞에 둘 수 없다** — 순서는 넷이다. 재개가 옛 체인 브랜치를 다시 쓰면 넷 대신 `resume.md`「재개」 의 전환이다.
  1. 위 미커밋 줄을 다시 잰다 — 승인 화면 뒤에 생긴 tracked 변경은 `switch -c` 가 새 브랜치로 끌고 가 다음 커밋에 섞인다.
  2. `git -C "<대상 레포 경로>" fetch origin <기본>`
  3. `git -C "<대상 레포 경로>" switch -c karina/chain-<Run id 의 run_ 뒤 앞 8자> origin/<기본>`
  4. `git -C "<대상 레포 경로>" push -u origin karina/chain-<Run id 의 run_ 뒤 앞 8자>` — refspec 을 생략하지 않는다(`pr-flow.md`「PR 열기」 1). push 는 스킬 안이라 승인 대상이 아니다.
  - **하나라도 실패하면 task 를 만들지 않고 오류 원문을 보고하고 멈춘다 — `Y` 로 바꿔 잇지 않는다** — 사용자가 고른 `P` 를 바꾸면 사용자 답 뒤집기다(`../SKILL.md`「답하는 기준」 ②). 3 뒤에 실패했으면 `git switch <시작 브랜치>` 로 돌아가고 만든 로컬 브랜치 이름을 보고에 싣는다(지우지 않는다).
  - **이 체크아웃의 HEAD 가 체인 브랜치로 바뀐 사실을 보고에 싣는다** — 직렬 워커는 이 체크아웃에서 돌고, 병행 세션이 같은 폴더를 쓰면 그쪽도 이 브랜치를 본다.
- **`P` 면 모든 계획 spec 에 `PR 모드: 켬 — base <체인 브랜치>` 를, 아니면 `PR 모드: 꺼짐` 을 싣는다(`spec-format.md`「spec 서식」)** — 워커의 `pr-flow.md` 는 `PR 모드: 켬` 으로 시작하는 줄이 있을 때만 브랜치를 바꾸고 PR 을 연다.
- **대기 명령 끝에 `--pr <체인 브랜치>` 를 더한다** — 대기 스크립트가 PR 단계(열림·CI green·화면 확인 대기·merged)를 진행 줄에 싣고, CI 가 pending 인 동안 같은 화면을 멈춤으로 세지 않는다(근거 정본은 `wait-worker-rationale.md`「PR 단계」). 워커는 CI 를 기다리는 동안 turn 을 끝내 화면과 HEAD 가 함께 멈춘다.

## 워커

**spec 에 `PR 모드: 켬 — base <브랜치>` 줄이 있는 중계 모드 워커가 따른다 — 줄 끝이 `· 스택` 이면 이 절 대신 `stack-mode.md`「워커」 다.** 아래 `<base>` 는 그 줄의 브랜치다.

- **마무리 순서는 「plan 파일 커밋 → 인계 절 커밋 → PR 열기 → `karina:pr` babysit·ship → `worker_done` → 최종 보고」다** — 인계 절이 PR 에 실려야 squash merge 뒤 base 에 남는다. 인계 절을 쓰지 않는 계획(`../../plan/references/relay-mode.md`「중계 모드」 의 마지막 계획)이면 그 칸만 건너뛴다.
  - **화면 줄 task 직렬 예외 — plan 에 `**화면**` 줄 task 가 든 직렬 워커는 인계 절을 PR 앞에 커밋하지 않는다** — 그 PR 은 ship 화면 게이트에서 멈춰 merge 되지 않으므로, PR 에 실린 인계 절은 다음 워커의 base 에 없고 뒤 절과 merge 충돌을 낸다(babysit 은 충돌을 고치지 않는다). 순서는 셋이다.
    - 「브랜치」 에서 `git fetch origin <base>` 뒤 `git switch -c karina/<슬러그> origin/<base>` 로 가른다. 로컬 base 의 미push 커밋(앞 화면 워커의 인계 커밋)을 옮기지 않고 `git branch -f` 도 하지 않는다.
    - ship 이 화면 게이트에서 멈추면 아래 표대로 `git switch <base>` 하고, 인계 절을 base 의 로컬 커밋(push 안 함)으로 남긴다. 다음 비화면 워커의 `pr-flow.md`「브랜치」 가 쌓인 미push 커밋을 자기 PR 로 옮긴다. 마지막 계획이면 `report.md`「인계 파일 정리」 의 정리 커밋처럼 로컬에 남는다.
    - 작업 트리가 깨끗하지 않아 switch 를 못 하면 PR 을 열어 둔 채 `--outcome failed` 로 정지하고 `PR:` 필드에 `열림 — <URL> · 화면 확인 대기 · 인계 절 미커밋` 을 싣는다.
    - 병렬 워커는 이 예외 없이 지금 순서다(PR 에 인계 절) — 처리는 「병렬」.
  - **인계 절 머리에 `PR 브랜치: <브랜치>` 를 더한다** — babysit·ship 의 수정 커밋은 인계 절 커밋 뒤라 절의 커밋 범위에 들지 않는다. 뒤 계획은 그 브랜치의 PR 로 나머지를 찾는다.
- **PR 본문 끝 줄에 `체인: <인계 파일 이름의 Run id> · plan <N>/<총>` 을 싣는다** — 이 체인이 멈추면 재개가 이 표지로 열린 PR 을 찾는다(`resume.md`「열린 PR」). 마지막 계획은 인계 절을 쓰지 않아 인계 파일로는 그 브랜치를 못 찾는다.
- **PR 을 열기 전과 충돌·낡은 base 멈춤에서는 base 를 합친다 — `git fetch origin <base>` 뒤 `git merge-base --is-ancestor origin/<base> HEAD` 가 거짓이면 `git merge origin/<base>` 다(rebase 금지). merge-ready 에서 ship 을 부르기 직전에는 같은 조건에 `../../pr/references/ship.md` 7번의 영향 판정(기준 `git merge-base HEAD origin/<base>` — 파일 겹침 · base 쪽 검증 선택 문서·CI·의존 매니페스트 · drift sweep)을 더해 참일 때만 합치고 babysit 부터 다시 하며, 거짓이면 합치지 않고 두 목록을 보고에 싣고 ship 으로 간다** — PR 을 열기 전의 합치기는 squash 된 앞 PR 을 들여 PR diff 가 새 커밋만 담게 하고(`continuation.md`「코디네이터 검증」 전제), 충돌·낡은 base 는 그 멈춤 자체가 영향의 증거다. ship 직전에 모든 base 이동마다 합치면 검증이 끝나지 않는다(*"rebasing for every trunk move never ends"*) — merge 는 검증한 조합이 착지할 base 위에 있어야 하되(*"tested on the trunk it lands on"*), PR 이 닿지 않는 base 변경은 그 조합을 바꾸지 않는다.
  - **충돌은 재진술을 기준으로 양쪽 의도를 살려 풀고, spec 「근거로 정한 것」 ③ 검증을 돌려 통과하면 커밋·push 한 뒤 babysit 부터 다시 한다** — `parallel.md`「충돌·검증 실패」 의 병합 준비와 같은 기준이다. 풀 수 없으면 아래 정지다.
  - **한 PR 에서 세 번째 합치기가 필요하면 합치지 않고 정지한다** — base 가 계속 움직이면 검증이 끝나지 않는다(*"If trunk would force a third rebase past merge prep, hold and report"*).
- **PR 을 연 뒤 `karina:pr` 을 Skill 도구로 「PR <URL> 을 babysit 뒤 ship — 체인 PR 모드」 로 부른다** — 요청이 babysit 과 merge 를 함께 말해 `../../pr/SKILL.md`「모드 고르기」 대로 merge-ready 뒤 ship 으로 잇는다. 이 요청이 `pr-flow.md`「PR 을 연 뒤」 의 「babysit 을 시작하지 않는다」 의 예외다.
  - **ship 은 「버전 전용 PR 잇기」 를 건너뛴다 — 요청의 「체인 PR 모드」 가 표지다(`../../pr/references/ship.md`)** — 계획 PR 은 체인 브랜치로 merge 되고, 버전은 「P 체인 끝 PR」 을 merge 하는 ship 이 한 번 올린다.
- **babysit·ship 이 멈춘 자리마다 아래로 간다:**

  | 멈춘 자리 | 워커가 할 일 |
  |---|---|
  | merge-ready | ship 으로 간다 |
  | 충돌 · 낡은 base(`../../pr/references/babysit.md`「1. 충돌」·「3. CI」) | 위 base 합치기 뒤 babysit 부터 다시 |
  | ship 「base 합치기 필요」(`../../pr/references/ship.md` 7번 영향 판정 참) | 위 base 합치기 뒤 babysit 부터 다시 |
  | `pr-verifier` FAIL | 지적한 결함을 고쳐 커밋·push 한 뒤 babysit 부터 다시 — 지적은 하나의 수정으로 모은다(*"Send every proven finding … to the owner in one fix-forward"*) |
  | head 가 바뀌어 merge 거부(`--match-head-commit`) | ship 1번부터 다시 |
  | 화면 확인 대기(`../../pr/references/ship.md` 7번 화면 게이트) | PR 을 열어 둔 채 작업 트리가 깨끗하면 `git switch <base>`(병렬 워커는 건너뛴다) 뒤 `--outcome succeeded` 로 보고한다 — `PR:` 필드는 `열림 — <URL> · 화면 확인 대기`, `남은 일` 에 `PR <URL> 화면 확인 대기 — 사용자가 스크린샷을 보고 「화면 확인함」 으로 karina:pr ship 을 요청`. 질문이 아니라 보고다 — 사용자 몫으로 넘기지 않는다 |
  | 사람 판단 대기(`CHANGES_REQUESTED`·`REVIEW_REQUIRED`·보고만 한 스레드) · 브랜치 보호 등 그 밖의 merge 거부 | 곧바로 정지 — 사람이 정할 자리이고 체인은 그것을 대신 정하지 못한다 |
  | CI 실패가 같은 원인으로 3회 · `pr-verifier` FAIL 3회 · 세 번째 합치기 | 정지 — `../../implement/SKILL.md`「멈추는 넷」 의 동일 원인 3회와 같은 수다 |

- **정지는 PR 을 열어 둔 채 `--outcome failed` 로 보고하고, `--body` 의 `PR:` 필드에 `열림 — <URL> · <멈춘 자리>` 를 싣는다** — 코디네이터는 failed 면 체인을 멈추고(`../SKILL.md`「워커 루프」), 사용자는 그 PR 을 보고 정한다. PR 을 닫거나 브랜치를 지우지 않는다.
- **merge 되면 `PR:` 필드는 `<URL> · merged <merge 커밋 7자리>` 다** — merge 커밋은 ship 9번의 `mergeCommit` 이다.

## 직렬

- **워커의 ship 10번이 체인 브랜치로 돌아와 `git pull --ff-only` 한 뒤 `worker_done` 을 보낸다 — 코디네이터는 succeeded 뒤 지금처럼 다음 계획을 띄운다** — 다음 워커는 같은 체크아웃에서 merge 된 커밋을 본다(`release.md`「닫기」 가 같은 폴더를 고집하는 이유와 같다).
- **워커가 화면 확인 대기로 succeeded 하면 `continuation.md`「남은 일 판정」 으로 가른다** — 그 PR 은 merge 되지 않아 다음 워커의 base 에 그 변경이 없다. 뒤 계획이 그 변경에 의존하면 멈추고, 아니면 다음 계획을 띄운다.
- **10번이 돌아오지 못했어도(작업 트리가 깨끗하지 않음·`pull --ff-only` 실패) 코디네이터는 손대지 않는다** — 다음 워커의 `pr-flow.md`「merge 된 브랜치에서 시작할 때」 가 merge 된 `karina/*` 브랜치에서 원격 base 로 갈라 받는다.

## 병렬

- **그룹을 띄우기 전에 `git -C "<대상 레포 경로>" fetch origin <체인 브랜치>` 뒤 `git -C "<대상 레포 경로>" rev-list --count origin/<체인 브랜치>..<체인 브랜치>` 가 0 이 아니면 그 그룹을 묶지 않고 직렬로 돌린다** — worktree 는 로컬 체인 브랜치에서 갈라져(`parallel.md`「띄우기」) 원격보다 앞선 커밋이 그룹원 PR 마다 함께 실린다. 직렬 워커의 `pr-flow.md`「브랜치」 는 그 커밋을 첫 PR 하나로 옮긴다. 화면 직렬 워커가 base 에 남긴 미push 인계 커밋(「워커」 의 화면 줄 task 직렬 예외) 때문에 뒤 그룹이 직렬로 도는 것도 이 정상 경로다.
- **병렬 워커는 ship 의 10번(로컬 맞추기)도 건너뛴다(「버전 전용 PR 잇기」 는 「워커」 대로 모든 워커가 건너뛴다)** — 체인 브랜치가 주 레포에 체크아웃돼 있어 worktree 에서 `git switch <체인 브랜치>` 가 거부된다. spec `병렬:` 줄이 그 워커를 가린다.
- **`worker_done`(succeeded)을 받으면 `parallel.md`「병합」 ⓐ~ⓔ 대신 주 레포를 맞춘다 — ⓐ 와 같이 주 레포가 깨끗하고 체인 브랜치일 때만 `git -C "<대상 레포 경로>" fetch origin <체인 브랜치>` → `git -C "<대상 레포 경로>" merge --ff-only origin/<체인 브랜치>` 이고, 아니거나 실패하면 보고하고 멈춘다** — 워커가 이미 base 를 합쳐 검증한 head 를 merge 했으므로 코디네이터가 다시 병합·검증할 것이 없다. 이 fast-forward 는 `../SKILL.md`「하지 않는 것」 「파일 수정」의 예외다.
- **그룹원이 화면 확인 대기로 succeeded 하면 merge 되지 않았으므로 fast-forward 할 것이 없고, 아래 그룹 버전 PR 의 「병합된 그룹원」 으로 세지 않는다** — `병렬 병합:` 칸에 `미병합 — 화면 확인 대기 · <PR URL>` 로 싣고 worktree·브랜치는 남긴다. 그 PR 에 인계 절이 실려 있어 뒤 계획이 그 절을 base 에서 읽지 못하므로, 코디네이터는 그룹 뒤 계획 앞에서 멈춘다.
- **충돌·검증 실패의 병합 준비 재배정은 없다** — 워커가 「워커」 의 base 합치기로 직접 푼다.
- **그룹 버전 PR — 대상 레포 `AGENTS.md` 에 버전 규약이 있고 그 Release 가 「버전 전용 PR」 이 아닐 때만, 그룹의 마지막 succeeded 워커를 fast-forward 한 뒤 그 탭에 「버전 PR」 task 를 `--terminal` 로 재배정한다(병합된 그룹원이 없으면 하지 않는다)** — `parallel.md`「버전」 의 마지막 워커 재배정과 같은 형태이고, PR 모드 워커는 `worker_done` 전에 ship 을 끝내므로 재배정은 그 뒤 별도 task 다. 「버전 전용 PR」 레포는 「P 체인 끝 PR」 을 merge 하는 ship 이 체인 전체의 버전을 한 번 올리므로 재배정하지 않는다. task 서식은 `parallel.md`「충돌·검증 실패」 의 병합 준비 task 와 같고 표식·`할 일:` 만 바꾼다:

  ```
  [chain-plan 버전 PR] 그룹 <g> (plan <목록>)
  할 일: 이 worktree 에서 git fetch origin <체인 브랜치> 뒤 git switch -c karina/release-v<다음 버전> origin/<체인 브랜치> 로 갈라, karina:pr 의 ship.md「버전 전용 PR 잇기」 2~3 대로 버전 PR 을 열고 merge 까지 간다(10번 로컬 맞추기는 건너뛴다). 릴리즈는 발행하지 않는다.
  ```

  - **succeeded 면 위와 같이 주 레포를 fast-forward 한다.**
- **닫기는 fast-forward 뒤이고, 버전 PR 을 재배정했으면 그 dispatch 로 닫는다** — `release.md`「닫기」 의 「그 탭의 마지막 dispatch」 규칙 그대로다.
- **보고의 `병렬 병합:` 칸에는 그룹마다 plan · PR URL · merge 커밋 · worktree 경로 · 브랜치를 싣는다(`report.md`「보고 서식」).**

## Y 체인 끝 PR

**`Y` 로 승인한 체인이 끝까지 성공했을 때(`report.md`「인계 파일 정리」 의 성공 조건과 같다) 그 정리 커밋 뒤, 보고 전에 1회 한다.** pstack 은 모든 playbook 끝에 PR 을 연다(*"Invoked at the end of every other playbook."* — `https://github.com/cursor/plugins/blob/f713f14203cd6420cec13cd7c55c32d598dbab68/pstack/skills/poteto-mode/playbooks/opening-a-pr.md`). 끝 PR 이 없으면 체인 커밋이 로컬에만 남는다(2026-10-18 PR #3 이 그 뒤 손으로 열려 제목 유형이 빠진 채 main 커밋이 됐다).

- **계획마다의 대상 레포 가운데 아래 셋이 참인 레포마다 한다** — 대상 레포 경로가 세션 시작 때 주입된 위키 vault 경로와 같지 않다(vault 는 `karina:llm-wiki` 가 직접 push 한다) · `../../implement/references/pr-flow.md`「적용 판정」 의 앞 두 조건(GitHub 원격 · `gh auth status` exit 0)이 참이다 · `git -C "<대상 레포 경로>" rev-list --count origin/<기본 브랜치>..HEAD` 가 0 이 아니다. 거짓인 레포는 보고의 `PR:` 줄에 `건너뜀 — <거짓인 조건>` 으로 싣는다.
- **`pr-flow.md`「브랜치」 의 표와 「merge 된 브랜치에서 시작할 때」 를 체인 브랜치에 그대로 적용한 뒤 「PR 열기」 1~4 를 따른다** — 같은 절차를 두 곳에 두면 한쪽만 고쳐진다. 그 절차가 `plan.md` 에 적게 한 것(슬러그·`> BASE:` 이동)은 이 세션이 `plan.md` 를 쓰지 않으므로 보고에 싣는다.
  - **슬러그는 `chain-<Run id 의 run_ 뒤 앞 8자>` 다** — 끝 PR 은 체인 끝에 1회만 열리고, 압축 뒤에도 `run-current` 로 같은 id 를 얻는다.
  - **제목은 `<유형>: <계획 제목들을 · 로 이은 한 줄>` 이다** — 유형은 `git log --format=%s origin/<기본 브랜치>..HEAD` 의 유형 접두 중 가장 많은 것이고 같으면 `기능` 이다. 길면 앞 계획부터 줄인다.
  - **본문 `## 범위` 에 plan 번호와 제목 목록을 싣는다** — 나머지 절은 「PR 열기」 의 본문 규칙 그대로다.
  - **`git log --format=%B origin/<기본 브랜치>..HEAD` 에 `화면: ` 으로 시작하는 줄(미촬영 줄 포함 — `../../implement/references/report-format.md`「화면 시나리오 실행」)이 있으면 본문에 `## 화면` 절을 싣는다** — 그 줄을 옮기고, 스크린샷 위치는 검증 스킬의 Evidence 위치를 환경변수 표기로 적는다. 이 세션은 워커의 `plan.md` 를 읽지 않아 커밋 본문이 화면 task 를 찾는 유일한 자리이고, 이 절이 있어야 사용자가 나중에 부르는 ship 의 화면 게이트가 걸린다.
- **babysit·merge 는 하지 않는다 — URL 을 보고하고 끝낸다** — merge 는 사용자가 `karina:pr` 로 요청할 때다(*"Opening a PR does not start a babysit."*).
- **어느 단계든 실패하면 오류 원문을 보고의 `PR:` 줄에 싣고 멈추지 않는다** — 체인은 이미 끝났고, 커밋은 로컬 체인 브랜치에 그대로 있다.

## P 체인 끝 PR

**`P` 로 승인한 체인이 끝까지 성공했을 때(`report.md`「인계 파일 정리」 의 성공 조건) 그 정리 커밋 뒤, 보고 전에 1회 체인 브랜치 → 기본 브랜치 PR 을 연다.** 계획 PR 들은 「켜기」 가 만든 체인 브랜치로 merge 돼, 이 PR 이 없으면 체인의 변경이 기본 브랜치로 가는 길이 없다(사용자 답 「체인 끝 main PR 하나」).

- **대상 레포가 「Y 체인 끝 PR」 의 셋째 조건(`rev-list --count origin/<기본 브랜치>..HEAD` 가 0 이 아님)을 채울 때만 한다 — 앞의 두 조건은 `P` 를 고를 때 「켜기」 가 이미 쟀다.** 0 이면 보고의 `PR:` 줄에 `체인 끝 PR: 건너뜀 — 기본 브랜치에 없는 커밋 0` 을 싣는다.
- **`../../implement/references/pr-flow.md`「PR 열기」 1~4 를 체인 브랜치에 그대로 적용한다 — 1번 push 가 정리 커밋과 쌓인 미push 인계 커밋(「워커」 의 화면 줄 task 직렬 예외)을 원격 체인 브랜치로 올린다** — 체인 브랜치는 이미 `karina/` 브랜치라 「브랜치」 표는 건너뛰고, 3번의 `--base` 는 기본 브랜치·`--head` 는 체인 브랜치다.
  - **제목·`## 범위`·`## 화면` 은 「Y 체인 끝 PR」 의 하위 불릿 셋을 따른다(슬러그 불릿은 빼고)** — 같은 체인 끝 PR 이라 규칙을 두 곳에 두지 않는다.
- **화면 확인 대기 PR 이 남아 있어도 연다 — 보고의 `화면 확인 대기:` 줄 아래에 「그 PR 들을 먼저 merge 한 뒤 체인 끝 PR 을 merge」 를 싣는다** — 이 PR 의 head 가 체인 브랜치라, 화면 대기 PR 이 나중에 체인 브랜치로 merge 되면 그 변경이 이 PR 에 함께 실린다.
- **babysit·merge 는 하지 않고 URL 을 보고하고 끝낸다 — 버전은 사용자가 이 PR 을 `karina:pr` ship 으로 merge 할 때 「버전 전용 PR 잇기」 가 한 번 올린다** — 계획 PR 의 ship 은 그 절을 건너뛰었다(「워커」).
- **실패하면 오류 원문을 `PR:` 줄의 `체인 끝 PR:` 칸에 싣고 멈추지 않는다** — 계획 PR 들은 이미 원격 체인 브랜치에 merge 돼 있어 잃는 것은 정리 커밋 하나다.
