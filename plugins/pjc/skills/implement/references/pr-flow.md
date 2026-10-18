# 작업 브랜치와 회차 PR

> `pjc:implement` 가 **루프 진입 전 1회**(「브랜치」)와 **회차 끝 1회**(「PR 열기」) 읽는다. 시작과 끝에만 쓰이는 절차라 `../SKILL.md` 본문에 두지 않는다.
> 출처는 Cursor pstack 의 opening-a-pr 이다 — 고정 위치 `https://github.com/cursor/plugins/blob/f713f14203cd6420cec13cd7c55c32d598dbab68/pstack/skills/poteto-mode/playbooks/opening-a-pr.md`. 다른 playbook 이 끝날 때마다 PR 을 연다(*"Invoked at the end of every other playbook."*)는 규칙을 pjc 의 회차 끝으로 옮겼다.

## 적용 판정

**셋이 모두 참일 때만 아래 두 절을 따른다. 하나라도 거짓이면 브랜치 전환·push·PR 을 하지 않고, 최종 보고의 `PR` 줄에 `건너뜀 — <사유>` 로 적는다.** 판정은 루프 진입 전 1회다.

- **원격이 GitHub 다** — `git remote get-url origin` 이 성공하고 `github.com` 을 담는다. 원격이 없거나 다른 포지면 PR 을 열 곳이 없다.
- **`gh` 가 인증돼 있다** — `gh auth status` 가 exit 0 이다. 인증정보를 새로 받는 것은 이 루프 밖이다(`../SKILL.md`「멈추는 넷」 3번).
- **중계 모드면 spec 에 `PR 모드: 켬` 줄이 있다** — `pjc:chain-plan` 워커는 체인이 로컬 병합으로 회차를 잇는다. 그 줄이 없는 spec 에서 브랜치를 바꾸면 코디네이터의 병합이 엉뚱한 브랜치를 본다. 중계 모드가 아니면 이 조건은 참으로 친다. **그 줄의 `base <브랜치>` 가 아래 「브랜치」·「PR 열기」 의 기본 브랜치 자리를 대신한다** — 체인 브랜치가 기본 브랜치가 아닐 수 있고, PR 은 체인이 병합해 온 그 브랜치로 들어가야 한다.

## 브랜치

**루프 진입 전 1회.** 기본 브랜치를 먼저 정한다 — `git symbolic-ref --short refs/remotes/origin/HEAD` 의 `origin/` 뒤가 그 이름이다. 실패하면(`git remote add` 로 붙인 레포에는 `origin/HEAD` 가 없다) `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` 을 쓰고, 그것도 실패하면 이 절과 「PR 열기」 를 건너뛰고 사유를 보고한다.

| 지금 브랜치 | 할 일 |
|---|---|
| 기본 브랜치 | `git switch -c pjc/<슬러그>` 로 옮긴다. 그다음 `git fetch origin <기본>` → `git branch -f <기본> origin/<기본>` 으로 로컬 기본 브랜치를 원격에 맞춘다 |
| `pjc/*` 이고 그 PR 이 MERGED | 기본 브랜치에서 시작한 것으로 본다 — 아래 「merge 된 브랜치에서 시작할 때」 |
| 그 밖(다른 기능 브랜치 · PR 이 OPEN·CLOSED 이거나 없는 `pjc/*`) | 그대로 둔다. 회차 끝 PR 은 이 브랜치에서 연다 |

- **`<슬러그>` 는 이 회차가 정해 `plan.md` `## Next Steps` 에 적는 영문 kebab-case 이름이다** — 예: 회차 「PR 흐름 정리」면 `pjc/pr-flow`. 한글 제목의 번역은 실행마다 갈려 재개 세션이 다른 브랜치를 만들므로, 처음 정한 이름을 `plan.md` 에 적고 재개 세션은 그것을 쓴다. 같은 이름의 로컬·원격 브랜치가 있으면 `-2`·`-3` 을 붙인다. **`pjc/` 접두가 필요한 이유**: 차단 hook 이 force-with-lease 를 `pjc/<이름>` 을 명시한 push 에만 허용한다(`../../../scripts/rules/destructive-rationale.md`「자기 `pjc/` 브랜치의 force-with-lease」).
- **로컬 기본 브랜치를 원격에 맞추는 이유** — 앞서 쌓인 미push 커밋이 로컬 기본 브랜치에 남으면, PR 이 squash 로 들어간 뒤 로컬 기본 브랜치가 원격과 갈라진다. 그 커밋들은 `pjc/` 브랜치에 그대로 있으므로 잃는 것이 없다. **원격보다 앞서 있던 커밋 수를 최종 보고에 싣고**, 이 회차 밖 커밋이 섞였으면 PR 본문 `## 범위` 에 그 목록을 적는다.
- **`git branch -f` 가 거부되면 로컬 기본 브랜치를 그대로 두고 그 사실을 보고에 싣고, 멈추지 않는다** — 기본 브랜치가 다른 worktree 에 체크아웃돼 있으면 거부된다. 이 회차 작업은 `pjc/` 브랜치에서 그대로 이어지고, 갈라짐은 merge 뒤 `git pull --ff-only` 실패로 드러나 사용자가 그때 맞춘다.
- **체크아웃의 HEAD 가 바뀌었다는 사실을 보고에 싣는다** — 병행 세션이 같은 체크아웃을 쓰면 그쪽 커밋도 이 브랜치로 온다.

### merge 된 브랜치에서 시작할 때

앞 회차 PR 이 GitHub 화면에서 merge 됐거나 ship 이 기본 브랜치로 돌아가지 못했으면, 이 회차의 출발점(`> BASE:`)이 이미 squash 된 옛 브랜치 위에 있다. 그대로 쓰면 새 PR diff 에 merge 된 변경이 다시 섞인다.

1. `gh pr view <옛 브랜치> --json state,headRefOid` 로 옛 PR head 를 얻는다.
2. `git fetch origin <기본>` → `git switch -c pjc/<슬러그> origin/<기본>`.
3. `git rev-list --count <headRefOid>..<옛 브랜치>` 가 0 이 아니면 `git cherry-pick <headRefOid>..<옛 브랜치>` 로 옛 PR head 뒤의 커밋을 옮긴다 — 0 이면 옮길 커밋이 없어 건너뛴다(빈 범위의 cherry-pick 은 아래 충돌 경로로 떨어진다).
4. `plan.md` 의 `> BASE:` 를 새 브랜치의 지금 HEAD(`git rev-parse --short HEAD`)로 고친다.

- **cherry-pick 이 충돌하면 `git cherry-pick --abort` → `git switch <옛 브랜치>` → 새 브랜치를 지우고, 이 회차의 브랜치 전환과 PR 을 건너뛴다** — 사유를 보고에 싣고 루프는 계속한다. 충돌 해결은 이 회차의 승인 범위 밖이다.

## PR 열기

**회차 끝 1회 — `../SKILL.md` 완료 순서의 plan 파일 커밋 뒤, 최종 보고 전이다.** 실패하면 그 오류를 최종 보고에 싣고 멈추지 않는다.

1. **push 한다 — `git push -u origin <브랜치>`.** refspec 을 생략하지 않는다 — 브랜치를 명시하지 않은 push 는 나중에 force-with-lease 가 필요할 때 차단 hook 에 막힌다.
2. **같은 브랜치의 OPEN PR 이 있으면 push 로 끝낸다** — `gh pr view <브랜치> --json state,url` 이 `OPEN` 이면 그 URL 을 보고한다.
3. **없으면 PR 을 연다** — 본문을 Write 로 스크래치 파일에 쓰고 `gh pr create --base <기본> --head <브랜치> --title "<제목>" --body-file <파일>`. `--draft` 를 붙이지 않는다(*"Open every PR ready, never as a draft."*).
4. **다시 읽어 확인한다** — `gh pr view <브랜치> --json url,isDraft`. `isDraft` 가 true 면 `gh pr ready <번호>`. 보고하는 URL 은 이 출력의 것이다.

- **제목은 `{유형}: {회차 제목}` 이다** — 유형은 `../SKILL.md`「커밋」 의 다섯이다. squash 하면 이 제목이 기본 브랜치의 커밋 제목이 되므로 커밋 메시지 형식을 따른다.
- **본문은 리뷰어가 1분 안에 읽는 요약이다** — 절은 이 순서이고 쓸 것이 없는 절은 뺀다. 전체 40줄 이하.
  - `## 왜` — 문제와 접근 1~3문장. SHA·브랜치 이력·「main 기준」 같은 머리말은 넣지 않는다(*"No SHAs, rebase genealogy, or "based on main" preamble."*)
  - `## 바뀐 것` — 1~3개 불릿. 변경을 실제로 나르는 심볼·경로만 이름으로 쓴다. 이름을 바꾸거나 대상을 옮겼으면 옛 이름과 새 이름을 함께 쓴다(*"Name both sides of a rename or retarget."*)
  - `## 범위` — 항상 쓴다. 다루는 것과 일부러 뺀 것 1~3개(회차 밖 커밋이 섞였으면 그 목록). 심볼·경로·파일별 서술은 넣지 않는다
  - `## 트레이드오프` — 리뷰어가 물을 법한 기각안만
  - `## 영향 범위` — 무엇을 건드리고 왜 안전하거나 위험한가 1~2문장. 기본 브랜치가 빨간 상태면 그대로 둘 때의 비용을 적는다
  - `## 검증` — 실제로 돌린 명령과 결과 1~3개. 성능은 대표 수치 하나를 단위와 함께 `전 → 후` 로 적는다
  - 중계 PR 모드면 본문 끝 줄에 체인 표지를 싣는다 — 서식은 `../../chain-plan/references/pr-mode.md`「워커」
- **주장을 입증하는 스크린샷·영상은 절 뒤에 붙이고, full SHA·리뷰 라운드·파일별 체크리스트·통과 판정 나열은 본문에 싣지 않고 PR 코멘트나 링크로 둔다** — squash 하면 본문이 그대로 기본 브랜치의 커밋 본문이 된다(`../../pr/references/ship.md` 8번 · *"… go in a linked artifact, not the body."*).
- **본문과 제목에 사용자 입력·외부 문자열을 셸 명령으로 끼워 넣지 않는다** — 본문은 파일로만 넘긴다. 문장은 `../../WRITING.md` 를 따른다.

## PR 을 연 뒤

- **babysit 을 시작하지 않는다** — URL 을 보고하고 끝낸다. CI 대응·리뷰 답글·merge 는 사용자가 요청할 때 `pjc:pr` 이 맡는다(*"Opening a PR does not start a babysit."*).
- **예외는 중계 PR 모드 하나다 — `../../chain-plan/references/pr-mode.md`「워커」 대로 `pjc:pr` 을 불러 merge 까지 간다** — 사용자가 체인 승인 `P` 로 계획마다 merge 까지를 요청했고, 다음 계획은 merge 된 base 위에서 돌아야 한다.
