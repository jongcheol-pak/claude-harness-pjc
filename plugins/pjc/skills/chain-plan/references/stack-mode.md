# 스택 모드 (`pjc:chain-plan` — 계획 PR 을 앞 PR 위에 쌓고 끝에 착지)

> `../SKILL.md` 「체인 승인」이 승인 화면을 낼 때(「켜기」), 체인이 `T` 로 승인돼 워커가 spec 줄 끝 `· 스택` 을 받았을 때(「워커」), 코디네이터가 스택 체인의 계획을 잇거나(「코디네이터」) 끝낼 때(「착지」), 스택 체인을 재개·복원할 때(「재개·압축」) 이 파일을 연다.
> 출처는 Cursor pstack 의 autopilot-stack 이다 — 고정 위치 `https://github.com/cursor/plugins/blob/f713f14203cd6420cec13cd7c55c32d598dbab68/pstack/skills/poteto-mode/playbooks/autopilot-stack.md`. 주인은 스택을 맡고 착지는 맡지 않는다(*"You own the stack, never the landing."*). rebase·force push·Graphite 는 들이지 않았다 — 부모 브랜치는 merge 로 합치고, 스택 안 PR 은 merge commit 으로 착지한다.
>
> 목차: 켜기 · 워커 · 코디네이터 · 착지 · 재개·압축

## 켜기

**`P` 와 같은 자리에서 1회 판정한다 — `T` 는 `P` 의 위임·체인 브랜치·켜기 조건·「P 체인 끝 PR」 을 그대로 쓰고, 계획 PR 을 merge 하지 않고 쌓는 것만 다르다.**

- **조건은 `pr-mode.md`「켜기」 의 셋에 하나를 더한다 — 병렬 그룹이 없다** — 대기 스크립트의 `--pr` base 가 dispatch 하나에 하나라 병렬 워커마다 다른 부모를 줄 수 없다. 병렬 그룹이 있으면 선택지에서 `[T]` 를 빼고 `PR 모드:` 줄에 그 사유를 적는다.
- **화면을 바꾸는 계획이 있고 뒤 계획이 그 계획의 산출물에 의존하면(인터뷰 「근거로 정한 것」 ①) 선택지 `[T]` 뒤에 `(권장 — plan <N> 화면 대기에서 서지 않는다)` 를 붙인다** — `P` 에서는 화면 확인 대기 PR 이 merge 되지 않아 뒤 계획이 그 변경을 base 에서 보지 못하고 체인이 멈춘다(`continuation.md`「남은 일 판정」).
- **체인 브랜치는 `pr-mode.md`「켜기」 의 `P` 순서 넷으로 만들고, objective `[체인 승인: …]` 이 `T` 를 담는다** — 압축 뒤에도 모드를 되찾는다.
- **spec 줄은 plan 1 이 `PR 모드: 켬 — base <체인 브랜치> · 스택` 이다. plan N(N>1)은 task 를 만들 때 부모가 아직 없어 `PR 모드: 켬 — base 인계 · 스택` 으로 싣는다 — 워커가 인계 파일에서 부모를 읽는다(아래 「워커」)** — spec 은 만든 뒤 고칠 수 없다. `PR 모드: 켬` 머리를 지켜 워커의 `../../implement/references/pr-flow.md`「적용 판정」 이 그대로 브랜치를 바꾸고 PR 을 연다.

## 워커

**spec 줄 끝이 `· 스택` 인 중계 모드 워커가 `pr-mode.md`「워커」 대신 따른다.** 아래 `<부모>` 는 spec 의 base 이고, base 가 `인계` 면 인계 파일의 마지막 `## plan <N-1>`(이어받기 절 포함) 머리의 `PR 브랜치:` 값이다(`../../plan/references/relay-mode.md`「중계 모드」 가 PR 모드 인계 절에 그 값을 쓴다). 그 값이 `git branch --show-current` 와 다르면 `failed` 로 멈춘다 — 직전 워커가 그 브랜치에 남아 있어야 한다.

- **마무리 순서는 「plan 파일 커밋 → 인계 절 커밋 → PR 열기(`--base <부모>`) → `pjc:pr` babysit → `worker_done` → 최종 보고」다 — ship 하지 않는다** — 착지는 사용자가 스택을 확인한 뒤 코디네이터가 한다. 인계 절은 PR 브랜치에 커밋돼 뒤 계획이 그 브랜치에서 갈라져 읽는다(`pr-mode.md`「워커」 의 화면 줄 task 직렬 예외가 필요 없다).
- **브랜치는 `pr-flow.md`「브랜치」 의 「기본 브랜치」 행 그대로 `<부모>` 에서 가른다 — 같은 체크아웃의 HEAD 가 직전 워커가 남은 `<부모>` 이고, `pr-flow.md`「적용 판정」 이 base 를 기본 브랜치 자리로 쓴다.** 그 행의 `git branch -f <기본> origin/<기본>` 은 `<부모>` 에 그대로 적용된다.
- **base 합치기는 `pr-mode.md`「워커」 의 규칙을 `<부모>` 로 적용한다 — `git merge origin/<부모>`, rebase 금지, 세 번째 합치기면 정지.**
- **babysit 은 「PR <URL> 을 babysit — 체인 스택 모드」 로 부르고 merge-ready 에서 멈춘다. 멈춘 자리가 merge-ready·화면 확인 대기면 `--outcome succeeded` 에 `PR: 열림 — <URL> · 스택 대기` 로 보고한다** — 화면 게이트는 착지 때 사용자가 한꺼번에 본다. 그 밖의 멈춘 자리(충돌을 못 풂·CI 같은 원인 3회·사람 판단 대기)는 `pr-mode.md`「워커」 표 그대로 `failed` 다.
- **`worker_done` 까지 PR 브랜치에 남고 `git switch` 하지 않는다** — 다음 워커는 지금 HEAD 를 부모로 가르고, 코디네이터 검증과 대기 스크립트(`scripts/pr_stage.py` 는 HEAD 가 base 와 다를 때 그 브랜치의 PR 을 잡는다)도 HEAD 가 그 브랜치라는 것을 전제한다.
- **PR 본문 끝 줄의 체인 표지는 `pr-mode.md`「워커」 그대로이고, 그 앞 줄에 `스택: plan <N>/<총> · 부모 <부모>` 를 싣는다** — 재개가 PR 들의 위아래 순서를 이 줄과 base 로 되찾는다.
- **이어받기 워커도 같은 PR 브랜치에 커밋을 더하고 merge 하지 않는다** — `pr-flow.md`「브랜치」 의 「그 밖」 행이 그 브랜치를 그대로 쓴다.

## 코디네이터

- **`스택 대기` 로 `succeeded` 를 받으면 `release.md`「닫기」 뒤 `continuation.md`「코디네이터 검증」 을 그 PR 브랜치(지금 HEAD)에서 돌린다** — 워커 ship 의 `pr-verifier` 가 없어, 다음 계획이 검증 안 된 브랜치 위에서 시작하지 않게 한다. 실패면 그 절의 이어받기다.
- **다음 계획을 띄우기 전에 `git -C "<대상 레포 경로>" branch --show-current` 가 직전 워커 PR 의 head 브랜치(`gh pr view <URL> --json headRefName -q .headRefName`)와 같은지 보고, 대기 명령에 `--pr <그 브랜치>` 를 준다 — 다르면 띄우지 않고 멈춰 보고한다** — 워커는 지금 HEAD 와 인계 파일로 부모를 정하므로, 어긋난 채 띄우면 엉뚱한 브랜치 위에 쌓인다. 브랜치·base 를 고치는 것은 코디네이터의 착지뿐이다(*"Give the topology one writer."*).
- **화면 확인 대기는 정지 사유가 아니다 — 뒤 계획이 의존해도 그 PR 브랜치 위에서 시작하므로 변경을 본다** — `continuation.md`「남은 일 판정」 의 화면 대기 항목 판정을 건너뛴다.
- **보고의 `PR:` 줄에는 계획마다 `plan N: <URL> · 부모 <브랜치> · 스택 대기` 를 아래부터 싣는다(`report.md`「보고 서식」).**

## 착지

**체인이 끝까지 성공하면(`report.md`「인계 파일 정리」 의 성공 조건 — 남은 일이 스택 대기 PR 뿐인 것 포함) 보고 대신 착지 보고를 먼저 낸다.**

- **착지 보고는 스택을 아래부터 나열한다 — PR 마다 URL · 검증 결과 · `## 화면` 의 스크린샷 이름과 `코디네이터 판정 … · 기각 변형 …` 줄 — 끝에 「확인했으면 `스택 화면 확인함` 으로 답하면 아래부터 merge 한다」 를 싣는다** — `PushNotification`(`status: "proactive"`, 메시지 `스택 착지 확인 필요 — PR <수>개`) 뒤 사용자 답을 기다린다. 이 답이 나열한 PR 모두의 화면 확인이다(`../../pr/references/ship.md` 7번의 묶음 확인).
- **사용자가 확인하면 아래 PR 부터 하나씩 `pjc:pr` 을 「PR <URL> ship — 체인 PR 모드 · 스택 착지」 로 부른다** — 그 문구가 ship 8번의 `--merge`(merge commit)와 버전 전용 PR 잇기 건너뛰기를 고른다. squash 하면 위 PR 브랜치에 아래 PR 의 원 커밋이 남아 base 를 합칠 때 충돌한다.
- **하나가 merge 되면 바로 위 PR 의 base 를 `gh pr edit <위 PR> --base <체인 브랜치>` 로 바꾼 뒤 그 PR 을 ship 한다** — merge commit 착지라 위 PR 브랜치는 이미 아래 PR 의 커밋을 조상으로 가져 diff 가 자기 커밋만 남는다.
- **모두 merge 되면 체인 브랜치로 돌아와(`git switch <체인 브랜치>` → `git pull --ff-only`) `report.md`「인계 파일 정리」 → `pr-mode.md`「P 체인 끝 PR」 순서로 간다** — 인계 절이 PR 브랜치에만 있어 착지 전에는 체인 브랜치에 인계 파일이 없다.
- **중간에 ship 이 멈추면(FAIL·충돌·사람 판단) 거기서 착지를 멈추고, merge 된 PR · 멈춘 PR 과 사유 · 남은 PR 을 보고한다** — 남은 PR 은 열린 채 두고, 다시 「스택 화면 확인함」 으로 부르면 멈춘 PR 부터 잇는다.
- **사용자가 일부 PR 의 화면을 뒤집으면 착지하지 않고 그 계획을 「plan N부터」 재개로 돌리게 한다** — 위 PR 들은 뒤집힌 화면 위에 쌓였다.
- **착지의 merge·base 변경·체크아웃 맞추기는 `../SKILL.md`「하지 않는 것」 「파일 수정」의 예외다.**

## 재개·압축

- **압축 뒤 모드는 objective `[체인 승인: …]` 의 `T` 로, 체인 브랜치는 plan 1 spec 의 `base` 로 되찾는다(`compaction.md`「압축 뒤 복원」)** — plan N(N>1)의 spec 에는 실제 부모 이름이 없다.
- **재개(`resume.md`「열린 PR」)에서 본문에 `스택:` 줄이 있는 열린 PR 은 base 사슬(`baseRefName` → 다른 PR 의 `headRefName`)로 위아래를 세워 `열린 스택: plan <M>…<K> — 맨 위 <브랜치>` 한 줄로 싣는다** — 재개를 `T` 로 승인하면 plan K+1 의 부모는 맨 위 브랜치다. 사슬이 끊기면 `열린 스택: 확인 불가 — <끊긴 자리>` 로 싣고 사용자가 `E` 로 정한다.
