# Intent: 코드 세션이 위키를 절 단위로 읽는다

Author: 사용자. Status: approved.

## Problem

*"작업 요청시 프로젝트 코드를 검토와 현재 스킬에서 위키를 검토 하는데 어떻게 더 속도와 토큰 절약에 좋은가?"* — 코드 세션이 위키를 읽는 자리에서 **전문 Read가 전제된 곳이 남아 있다**. 실측(2026-09-13, 이 레포의 vault 페이지): `conventions.md` 본문 18,431B 가 9개 절인데 이번 작업에 걸리는 것은 보통 1~2절(3,445B — 81% 가 불필요)이고, feature 페이지는 `## 관련 지식·레시피` 절만 필요한데 `feat-llm-wiki.md` 는 31,322B 중 그 절이 1,180B(96% 가 불필요)다. `lookup-rules.md:30` 이 **「본체는 언제나 읽는다」**로 본체 전문 Read 를 지시하고 있고, 같은 파일 31 행이 하위 전량 읽기 비용을 *"모든 코드 세션의 고정 비용이 단조 증가"*로 적어 하위 축은 닫았으나 **본체 축은 그대로 남았다**. 지금 하는 이유는 규약이 계속 누적되는 파일이라(`conventions.md` 는 아카이브 롤오버를 하지 않는다 — schema §2.9) 비용이 회차마다 단조 증가하기 때문이다.

## Proposed outcome

코드 세션(계획·디버깅)이 위키 산문 페이지를 읽을 때 ① 절 목록을 먼저 얻고 ② 이번 작업에 걸리는 절만 추출해 읽으며 ③ 절 추출이 성립하지 않는 페이지는 전문 Read 로 폴백하고 그 사실을 기록한다.

## Affected users and systems

코드 작업 세션을 여는 사용자. `plugins/pjc/skills/WIKI.md`(수단 정본)·`plugins/pjc/skills/llm-wiki/references/lookup-rules.md`(절차 K 2·K 3)·`plugins/pjc/skills/llm-wiki/references/wiki-schema.md`(§2.9 절 제목 작성 규칙).

## Constraints

**색인을 신설하지 않는다** — 절 제목이 이미 라우터이고(`## 스크립트로 파일을 고칠 때` 처럼 *언제 읽는지*를 말한다) 색인을 만들면 사본이 둘이 되어 드리프트원과 lint 축이 늘어난다. **`lookup-rules.md` 자체를 분할하지 않는다**(`deferred-closed.md:155` 의 기각을 이번에 뒤집지 않는다). **수단 문면의 정본은 한 곳**이고 다른 쪽은 포인터다 — 짧은 문면이라도 양쪽에 두면 복제 동기 축이 하나 늘어난다. 읽기 범위를 좁히는 것이 **유실이 되지 않도록** 폴백을 규약에 함께 둔다.

## Open questions

없음.
