# pjc 하니스 설계 원칙 (Opus 5 세대)

> **이 파일은 스킬이 아니라 설계 원칙 문서다** (frontmatter가 없어 플러그인 로더가 스킬로 등록하지 않는다).
> `AUTHORING.md`가 **스킬 문서를 어떤 형식으로 쓰는가**를 다룬다면, 이 문서는 **무엇을 규칙으로 만들고 무엇을 만들지 않는가**를 다룬다. 둘이 충돌하면 이 문서가 우선한다 — Opus 5에서 유효한 것이 이전 세대와 다르기 때문이다.

## 1. 규약 문면 형식

**모든 규칙은 다음 한 줄 형식으로 쓴다.**

```
- **<규칙>** — <근거>
```

- **규칙은 무엇을 하는지를 동사로 쓴다** — `금지`·`제한`만 적으면 읽는 쪽이 무엇을 대신 해야 하는지 모르고, 그 빈자리를 자기 판단으로 채우다 규칙이 무력해진다.
- **근거는 한 문장으로 쓴다** — 왜 그런지를 아는 모델이 경계 사례에서 더 정확하게 판단한다.
- **근거가 두 문장을 넘으면 그 규칙은 `references/`로 내린다** — 본문에 근거 서사가 쌓이면 규칙 자체가 산문에 묻혀 어느 문장이 구속력인지 고를 수 없게 된다.

### WRONG / RIGHT

```
WRONG: **추측 금지.**
       → 무엇이 추측인지, 대신 무엇을 해야 하는지가 없다.

WRONG: **추측 금지.** 모르는 것은 "확인 필요"로 표시한다. "아마도"·"보통은" 같은 가정은
       쓰지 않는다. 모든 주장은 Read 또는 grep으로 확인한 결과여야 한다. 사용처는 전수
       조사한다. 읽기 비례 원칙 — hit 과다(30건 초과)면 … (900자 계속)
       → 한 규칙이 900자가 되면 규칙이 아니라 산문이다. 이것이 실제 `plan-feature`
         절대 규칙 2였고, 그 아래에서 계획은 여전히 추측으로 작성됐다.

RIGHT: **사실 주장은 `주장 | 실행한 명령 | 출력 요지` 표에 적는다** — 명령 열이 빈 행은
       주장으로 쓸 수 없어, 추측이 산출물 형식 단계에서 걸린다.
       → 규칙 한 줄 + 근거 한 줄. 그리고 준수 여부가 기계로 보인다.
```

### 규칙을 쓰기 전에 묻는 것

**같은 취지의 규칙이 이미 있는데 지켜지지 않는다면, 새 규칙을 적지 말고 그 규칙을 산출물 형식으로 바꾼다** — 지시를 한 줄 더하는 것은 이미 실패한 수단을 한 번 더 쓰는 일이다. 2026-09-03 실측에서 사용자 요청 8건 중 5건이 이미 규약에 존재했고 전부 미준수였다.

## 2. 자기참조 금지

**규칙에서 다른 문서의 항목 번호를 지목하지 않는다. 파일명까지만 쓴다.**

- **번호는 편집으로 밀린다** — 항목 하나를 넣거나 빼면 그것을 가리키던 모든 참조가 조용히 어긋나고, 검사기는 번호가 여전히 존재하므로 깨진 것을 알아채지 못한다.
- **폐기 대상의 실제 문면**: `plan-reviewer 항목 2·3·4·7·9·12-a·14·16·18`을 한 문장이 동시에 지목했다. 이 구조에서는 한 항목을 고칠 때마다 다른 문서 아홉 자리를 함께 확인해야 하고, 그 확인이 빠지면 다음 수정이 새 문제를 만든다.

```
WRONG: (정본은 `phase-f-detail.md` F-6.5 게이트 ⓑ-2의 ⑴이며, 그 예외는 ⓓ의 두 ⚠가 정본)
RIGHT: (판정 기준은 `wiki-sync.md`에 있다)
```

**한 사실은 한 곳에만 적는다.** 같은 규정을 두 파일에 복제하면 한쪽만 고쳐져 갈린다. 다른 곳에서 필요하면 복제하지 말고 파일명으로 가리킨다.

## 3. Opus 5 전제 — 만들지 않는 것

출처: `platform.claude.com/docs/ko/build-with-claude/prompt-engineering/prompting-claude-opus-5`

### 3-1. 검증 단계를 추가하지 않는다

가이드 원문:

> 프롬프트에 명시적인 검증 지시("단순하지 않은 모든 작업에 최종 검증 단계를 포함하라", "서브에이전트를 사용해 검증하라")가 있다면 제거하세요. 이런 지시는 Claude Opus 5에서 과도한 검증을 유발하며, 제거하면 품질 손실 없이 낭비되는 토큰이 줄어듭니다. **별도의 검증 단계를 추가하는 레거시 하네스 스캐폴딩에도 동일하게 적용됩니다.**

- **검증은 기계가 판정하는 것만 단계로 만든다** — 빌드·테스트·정적 검사는 출력이 참/거짓으로 갈리지만, "자기 정직성 체크"·"caller 재검증" 같은 자기 재확인은 모델이 이미 하는 일이라 단계로 만들면 비용만 는다.
- **폐기한 것**: Phase V 9단계(V-1~V-9) · Phase F 8단계 · Phase G. 새 구조의 검증은 넷 이하다.

### 3-2. 서브에이전트로 자기 작업을 검증하지 않는다

가이드가 제시한 문구를 원문 그대로 쓴다:

> Delegate to a subagent only for large tasks that are genuinely independent and parallelizable, such as a wide multi-file investigation. Do not delegate work you can finish yourself in a handful of tool calls, and do not use subagents to verify or double-check your own work. If one subagent can complete the task, use one rather than several, and keep spawn counts low.

- **리뷰어는 2종·호출 2곳을 넘지 않는다** — 계획 완성 후 1회, 전 task 완료 후 1회. task마다 리뷰어를 부르면 왕복과 요약 손실이 작업량에 비례해 늘어난다.
- **리뷰 프롬프트에 심각도 억제 문구를 넣지 않는다** — 가이드에 따르면 "심각도가 높은 문제만 보고하라"·"보수적으로 판단하라"를 넣으면 모델이 문자 그대로 따라 **더 적게** 보고한다. 전부 보고하게 하고 걸러내는 쪽을 호출자가 맡는다.

### 3-3. 작업 범위

가이드가 제시한 문구를 원문 그대로 쓴다:

> Deliver what was asked, at the scope intended. Make routine judgment calls yourself, and check in only when different readings of the request would lead to materially different work. If the request seems mistaken or a better approach exists, say so in a sentence and continue with the task as asked rather than quietly narrowing, widening, or transforming it. Finish the whole task, and stop short of actions that are clearly beyond what was asked.

### 3-4. 진행 보고

가이드가 제시한 문구를 원문 그대로 쓴다:

> Before your first tool call, say in one sentence what you're about to do. While working, give a brief update only when you find something important or change direction. When you finish, lead with the outcome: your first sentence should answer "what happened" or "what did you find," with supporting detail after it for readers who want it.

- **자율 루프에서는 중간 업데이트도 내지 않는다** — 사용자가 개입할 지점이 없는 구간의 서술은 결정에 쓰이지 않으면서 컨텍스트를 소모해 후반 task의 품질을 떨어뜨린다.

## 4. 문서 예산

| 대상 | 상한 | 근거 |
|---|---|---|
| `SKILL.md` | **12,000 B** | 스킬 본문은 발동할 때마다 전량 로드된다. 이 선을 넘으면 규칙이 파묻히기 시작하고, 넘긴 뒤에는 줄이는 편집 자체가 새 결함을 만든다(실측: 104,733 B와 109,769 B에서 그렇게 됐다) |
| 단일 `references/*.md` | **15,000 B** | 한 번에 Read해 쓸 수 있는 크기. 넘으면 주제를 쪼갠다 |
| 에이전트 정의 `agents/*.md` | **6,000 B** | 리뷰어는 호출 프롬프트와 함께 로드되므로 짧을수록 지시가 선명하다 |
| 가이드 문서 (`DESIGN.md`·`AUTHORING.md`) | **12,000 B** | 자동 로드되지 않고 스킬을 고칠 때만 사람·모델이 열어 보므로 런타임 예산을 쓰지 않는다. 상한을 두는 이유는 읽는 부담뿐이다 |

**초과가 보이면 문장을 줄이지 말고 항목을 뺀다** — 같은 내용을 압축해 담는 개정은 매번 조금씩 나아지지만 끝나지 않는다. 뺄 항목이 없다고 판단되면 그 판단 자체를 의심한다.

## 5. 적용 범위

`skills/plan/` · `skills/implement/` · `agents/`. 나머지 스킬 6종은 아직 이 원칙으로 재작성되지 않았고, 적용 여부는 그 스킬을 고칠 때 판정한다 — 부분 적용은 한 스킬에 두 형식을 섞어 정본을 흐린다.
