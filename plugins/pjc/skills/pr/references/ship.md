# ship — 독립 검증 PASS 뒤 merge

> `../SKILL.md` 가 ship 요청일 때 읽는다. 출처는 Cursor pstack 의 shipping 이다 — 고정 위치 `https://github.com/cursor/plugins/blob/f713f14203cd6420cec13cd7c55c32d598dbab68/pstack/skills/poteto-mode/playbooks/shipping.md`. 스택 PR·클라우드 검증 에이전트·auto-merge·merge queue 는 들이지 않았다 — 대상은 PR 하나이고 검증자는 `pr-verifier` 서브에이전트다.

**코드를 쓰지 않은 검증자의 판정만 센다** — 작성자는 자기가 만들려던 것을 확인한다. CI 녹색과 봇 리뷰 승인은 판정이 아니다(*"Green CI and an approving bot review are not verdicts"*).

## 절차

1. **PR 을 읽는다** — `gh pr view <n> --json number,state,headRefName,headRefOid,baseRefName,baseRefOid,mergeable,mergeStateStatus,reviewDecision,title,body`. `state` 가 `OPEN` 이 아니면 멈추고 보고한다.
2. **사람의 판단이 걸려 있으면 merge 하지 않는다** — `reviewDecision` 이 `CHANGES_REQUESTED` 이거나 미해결 리뷰 스레드가 있으면(조회는 `babysit.md` 「2. 리뷰 스레드」 의 `reviewThreads` 쿼리) 「사람 판단 대기」 로 보고하고 멈춘다. 스레드를 다루는 것은 babysit(`babysit.md`)이다.
3. **PR head 를 받아 worktree 를 만든다** — `git fetch origin pull/<n>/head` 뒤 `git rev-parse FETCH_HEAD` 가 1번의 `headRefOid` 와 같은지 본다. 다르면 그 사이 push 가 들어온 것이니 1번부터 다시 한다. 같으면 `git worktree add --detach <스크래치 경로>/pr-<n> <headRefOid>`. 사용자의 체크아웃은 건드리지 않는다.
4. **`pr-verifier` 를 부른다** — 입력은 PR 번호 · head full SHA · base 브랜치와 `baseRefOid` · worktree 경로 · 그 레포 `AGENTS.md` 경로다. **PR 에 이미 달린 판정 코멘트는 merge 근거로 쓰지 않고 ship 할 때마다 새로 돌린다** — 코멘트는 로그인한 누구나 달 수 있어 작성자를 믿을 수 없다.
5. **판정을 PR 에 기록한다** — 본문 파일을 Write 로 쓰고 `gh pr comment <n> --body-file <파일>`. 올리는 것은 판정 줄 · head SHA · base SHA · 돌린 명령 이름과 exit 코드뿐이다. 출력 원문은 로컬 보고에만 싣는다 — 공개 코멘트에 경로·시크릿이 나가지 않게 한다.
6. **worktree 를 지운다** — `git worktree remove <경로>`.
7. **merge 조건을 다시 본다** — 판정이 `PASS` 또는 `PASS+NOTES` 이고, `gh pr checks <n>` 이 전부 통과하고, `gh pr view <n> --json mergeable,baseRefOid` 가 `MERGEABLE` 이고 `baseRefOid` 가 4번 때와 같다. base 가 움직였으면 검증한 조합과 merge 결과가 다르므로 3번부터 다시 한다. 판정이 `FAIL` 이면 merge 하지 않고 실패 사유를 보고한다.
8. **merge 한다 — 검증한 head 에 묶는다** — 제목·본문을 파일로 넘겨 squash 커밋 메시지를 레포 설정에 맡기지 않는다:
   `gh pr merge <n> --squash --match-head-commit <검증한 head full SHA> --subject "<PR 제목>" --body-file <PR 본문 파일>`
   head 가 바뀌어 거부되면 merge 하지 않고 보고한다. `--auto` 는 쓰지 않는다.
9. **다시 읽어 확인한다** — `gh pr view <n> --json state,mergedAt,baseRefName,mergeCommit`. `state` 가 `MERGED` 이고 `baseRefName` 이 1번의 `baseRefName` 과 같아야 merge 다. 명령이 성공을 말해도 큐에 들어가기만 했거나 auto-merge 가 걸린 것은 merge 가 아니다.
10. **로컬을 맞춘다** — 작업 트리가 깨끗하면(`git status --porcelain` 빈 출력) `git switch <1번의 baseRefName>` → `git pull --ff-only`. 깨끗하지 않거나 `switch`·`pull --ff-only` 가 실패하면 하지 않고 그 사실을 보고한다.

## 버전 전용 PR 잇기

**대상 레포 `AGENTS.md` 의 Release 줄이 「버전 전용 PR」 을 지목하고, 방금 merge 한 PR 이 그 레포가 정한 배포 대상을 바꿨으면 버전 PR 을 이어서 연다.** 이 하니스 레포는 `plugins/` 가 배포 대상이고 버전 정본은 `plugins/pjc/.claude-plugin/plugin.json` 이다(`docs/harness-conventions.md` 「Release」). **체인 PR 모드의 병렬 워커는 이 절을 건너뛴다 — `../../chain-plan/references/pr-mode.md`「병렬」**(그룹원끼리 같은 다음 버전을 다툰다).

1. 10번에서 1번의 `baseRefName` 으로 돌아온 뒤 `git switch -c pjc/release-v<다음 버전>`. 다음 버전은 그 레포 규약이 정한다 — 정하지 않았으면 minor 를 1 올린다.
2. 그 레포 규약이 지목한 버전 자리만 고친다(이 레포는 `plugin.json` 의 `version` 과 `README.md` 상단 `**버전**:` 줄). 다른 변경을 섞지 않는다 — squash 해도 기본 브랜치에 「버전만 올린 커밋」 하나가 남아야 그 위에 발행한 릴리즈 태그가 다음 판정(`git log v<버전>..HEAD -- plugins/`)의 기준점이 된다.
3. 커밋 `설정: v<버전> — <요약>` → `git push -u origin pjc/release-v<버전>` → PR 생성(`../../implement/references/pr-flow.md`「PR 열기」 와 같은 방식) → 이 절차 1~10번으로 검증·merge.
4. **릴리즈는 발행하지 않는다** — 태그·릴리즈는 외부·비가역이라 스킬 안에서도 별도 승인이다. 보고에 「승인 필요 — `gh release create v<버전> --target <버전 PR merge 커밋 full SHA>`」 를 싣는다. merge 커밋 SHA 는 9번 출력의 `mergeCommit.oid` 다.

- 버전 자리를 고치는 편집이 plan 게이트에 막히면 버전 PR 을 건너뛰고 그 사실을 보고한다.

## 보고

PR URL · 판정과 판정자(`pr-verifier`) · 판정이 덮은 head·base SHA · 돌린 검증 명령과 결과 요지 · merge 여부와 확인한 방법(9번 출력) · 로컬 정리 결과 · 버전 PR(열었으면 URL 과 merge 결과) · 승인 필요 항목(릴리즈).
