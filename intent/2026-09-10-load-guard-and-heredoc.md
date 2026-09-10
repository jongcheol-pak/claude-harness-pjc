# Intent: 규칙 로드 실패의 침묵 제거 · heredoc 오차단 해소
Author: 사용자. Status: approved.

## Problem

회차 52 가 대장에 올린 2건이 남아 있고, 그중 하나는 조사해 보니 **등재 문면보다 심각했다.**

① **`harness-hooks.json` 을 지우면 `guard-harness` 의 자기보호 이름 축이 경고 한 줄 없이 꺼진다.** 실측: 규칙 json 이 있으면 설치본 hook 스크립트 쓰기가 `BLOCKED`, 지우면 `rc=0` 무출력이다(경로 축 `hooks.json`·`rules/*.json` 은 유지). 그 파일의 `catch` 안에 `stderr` + `'(?!)'` 폴백이 **적혀 있는데 실행되지 않는다** — 뿌리는 등재 문면이 적은 「`-ErrorAction Stop` 부재」가 아니라 **파일 전역 `$ErrorActionPreference = 'SilentlyContinue'`** 다. `block-destructive.ps1:10` 만 `'Stop'` 이라 그 파일의 가시화는 실제로 동작하고, 나머지 넷은 `'SilentlyContinue'` 라 `catch` 가 죽어 있다. 그리고 **그 규칙 파일 삭제는 어느 hook 도 막지 않는다**(`rm`·`Remove-Item` 둘 다 `rc=0`).

② **`Split-TopLevel` 이 heredoc 을 몰라 정상 명령을 오차단한다.** `cat <<'EOF' > notes.md` / 본문 `hello; cp notes.md plan.md` / `EOF` 가 `exit 2` 로 막힌다 — 본문의 `;` 가 최상위 구분자로 잘려 조각의 첫 실효 토큰이 `cp` 가 되고, 대상은 `notes.md` 인데 `plan.md` 쓰기로 판정된다.

지금 하는 이유는 ①이 **안전장치를 끄는 경로**이고 ②가 **정상 작업을 막는 경로**여서다 — 둘 다 방향은 반대지만 관측된 실해가 있다.

## Scope (승인 시점 확정)

**이번 회차는 ①만 닫는다.** ②(heredoc)는 예산 때문에 뺐다 — 이식 최소형 647 B 에 `guard-bash.ps1` 여유가 344 B 라 303 B 초과이고, 초안 대비책(`Invoke-RequireTaskCheckbox` 정규식 외부화)은 실측 결과 **순증 +555 B** 로 반대 방향이었다. 축 확장도 구조적으로 막혔다 — heredoc 스트립은 함수가 아니라 최상위 인라인 코드다. 대장에 남으며 `post-write-checks.ps1` 예산 회차와 묶는다(사용자 판정 · 계획 리뷰 1R BLOCKER 2건).

## Proposed outcome

규칙 파일을 못 읽으면 **그 사실이 화면에 보이고**, `guard-harness` 는 이름 목록 없이도 설치본 hook 스크립트 개조를 막는다. 설치본의 규칙 파일·hook 스크립트 삭제가 차단된다. heredoc 본문의 구분자가 분할을 깨지 않아 `cat <<'EOF' > notes.md` 형태가 통과한다.

## Affected users and systems

이 레포에서 작업하는 모든 세션. 걸리는 것은 `plugins/pjc/scripts/guard-harness.ps1` · `guard-write.ps1` · `post-write-checks.ps1` · `guard-bash.ps1` · `rules/destructive.json` · 그 근거 문서들 · hook 골든 시나리오 · 「분할 헬퍼 동기」 축 · Deferred 대장이다.

## Constraints

**`block-destructive.ps1` 은 이번에도 스크립트를 고치지 않는다** — 삭제 차단은 `rules/destructive.json` 의 `patterns` 배열에 행을 더해 넣는다(그 파일이 판정 데이터의 정본이고 스크립트는 로더다). heredoc 스트립은 **복제 이식**이며 회차 52 가 세운 「분할 헬퍼 동기」 축의 대상에 함께 넣는다. `guard-bash.ps1` 은 여유가 **344 B** 뿐이라 이식 코드(406 B)가 그대로는 안 들어간다.

## Open questions

없음.
