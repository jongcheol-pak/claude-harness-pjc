# PRD: Opus 5 세대 대응 — 하니스·위키 스킬 정합 및 프롬프트 품질 계측

> 상태: **초안 (사용자 승인 대기)** · 작성 2026-07-29

## 목적

pjc 하니스는 Opus 4.x 세대를 전제로 "더 꼼꼼히 시키는" 방향으로 설계됐다. Claude Code가 `opus` 별칭을 **Claude Opus 5**로 해소(v2.1.219+)하면서 그 전제 일부가 어긋났다 — Opus 5는 검증을 알아서 하고(지시하면 과검증), subagent를 더 적극적으로 위임하며, 출력이 길어지고, "보수적으로만 보고" 지시가 리뷰 recall을 떨어뜨린다. 동시에 Claude Code의 스킬 수명주기 사양(auto-compact 후 **스킬당 앞 5,000토큰만 재부착**)이 확인되면서, 34,000토큰급 SKILL.md의 뒷부분(Phase 절차·Halt 조건)이 긴 자율 루프에서 통째로 유실되는 구조적 결함이 드러났다.

이 작업은 ① 압축 후 규칙을 되찾게 하고 **(선두 구간 재구성은 2026-07-29 분리 — 이번 범위는 FR-4의 재읽기 유도에 의한 *복구*까지이며, "구조적 생존"은 후속 plan의 몫이다)** ② Opus 5의 행동 변화에 맞춰 지시를 **더하는 게 아니라 정리**하며 ③ 그 변경의 효과를 **감이 아니라 수치로** 재는 계측 수단을 도입한다.

사용자는 이 하니스로 매일 코드 작업을 하는 개발자 본인이며, 개선의 수혜는 "긴 자율 루프 후반의 품질 저하"와 "리뷰가 놓치는 결함"의 감소로 나타난다.

## 기능 요구사항 (Functional Requirements)

| ID | 요구사항 | 우선순위 | 검증 방법 |
|----|---------|---------|----------|
| FR-1 | 스킬 **트리거 정확도**(should-trigger / should-not-trigger)를 Windows에서 측정할 수 있다 | Must | 러너 실행 → 케이스별 판정 + 발동률 집계가 stdout에 출력. 격리 `CLAUDE_CONFIG_DIR`로 실설치 스킬 간섭 0을 실증(동일 케이스 격리/비격리 결과 대조) |
| FR-2 | 스킬 **산출물 품질**을 고정 루브릭으로 채점할 수 있다 | Must | 고정 입력 세트(`docs/plans/`의 과거 plan 아카이브)를 judge에 넣어 항목별 1-10 점수 + 근거 파일:라인을 반환. 동일 입력 2회 실행 시 점수 편차가 보고됨 |
| FR-3 | 스킬 변경 **전후 비교(A/B)** 로 회귀를 검출할 수 있다 | Should | 같은 케이스 세트를 두 버전에 돌려 항목별 증감표 출력 |
| FR-4 | auto-compact 직후 세션에 **진행 중 plan이 있으면**, 재읽어야 할 스킬 문서·reference 경로를 기계가 지정해 주입한다 | Must | hook 골든 케이스(`source=compact` + 미완료 task 있는 plan) 추가 → 출력에 재읽기 대상 경로가 포함됨을 ExpectContains로 고정 |
| ~~FR-5~~ | ~~`implement-task`·`plan-feature`·`llm-wiki` SKILL.md의 **앞 5,000토큰 안**에 절대 규칙·Halt 조건·"현재 어느 단계인가" 판정법이 들어간다~~ | **REMOVED (2026-07: 이번 범위에서 분리 — 별도 plan으로 재수립)** | — |
| FR-6 | **중복 자기 재확인 지시**를 정리한다 — 재시도 카운터·상한·V-8 체크박스는 불변 | Must | 대상 문구 목록의 전후 대조표 + 카운터·상한 리터럴(`3회`·`5회`·`10회`·`2회`)의 diff 0줄 실증 |
| FR-7 | **subagent 위임 상한**이 `implement-task`·`plan-feature`에 명시된다 | Must | 두 파일에 상한 문장 존재 + 기존 「위임 금지 가드」 문단 무변경(diff 대조) |
| FR-8 | **산출 문서 길이 지침**이 plan 템플릿·최종 보고 템플릿에 존재한다 | Should | 두 템플릿에 길이 지침 문장 존재 |
| FR-9 | 리뷰어 4종이 **근거는 있으나 확신이 낮은 지적**을 `MINOR + (판정 유보)`로 배출한다. "근거 지목 불가 → 미보고"는 유지 | Must | 4개 agent 파일의 억제 표 행 전후 대조 + `plugins/pjc/skills/` diff 0줄(통제 어휘 오염 방지) |
| FR-10 | 동기 호출 규약에 **백그라운드 subagent의 도구 축소(LSP 소실)** 근거가 명시된다 | Must | `recovery.md` 「Subagent 호출 규약」에 해당 근거 문장 존재 |
| FR-11 | reviewer 응답이 **거절(refusal)** 일 때의 처리 분기가 존재한다 | Must | `recovery.md` 「Reviewer 호출 실패 대응」에 C 분기 신설 + `implement-task` V-5 헤더에서 도달 가능 |
| FR-12 | `implement-task`가 **세션 effort를 인지**해 low/medium이면 자율 루프 부적합을 1줄 경고한다 | Should | 스킬 본문에 치환 변수 기반 분기 존재 + 실제 치환 동작을 세션에서 실증 |
| FR-13 | `implement-task` frontmatter에 자율 루프에서 **질문 도구를 제거하는 필드를 도입**한다 | Should | frontmatter에 `disallowed-tools: AskUserQuestion`이 존재하고, 스킬 본문에 **"이 필드는 미검증 — 기존 문서 규칙이 여전히 1차 방어선"** 이 명시되며, 실동작 스모크 테스트가 `## Deferred / Follow-up`에 등재된다 (2026-07-29 2차 정정: frontmatter 변경은 워킹트리에만 생기고 실행되는 것은 설치본이라 실동작 검증에 push→update가 필요한데 push는 위임 불가 — 자율 루프 안에서 수행할 수 없음이 확인됨. 미지원이어도 필드는 무시될 뿐이라 무회귀) |
| FR-14 | `AUTHORING.md`의 **description 한도·frontmatter 필드 목록**이 현행 Claude Code 사양과 일치한다 | Must | 공식 문서 기준값과 문서 기재값 항목별 대조표 |
| FR-15 | `README.md`·`AGENTS.md`에 **Opus 5 리뷰어 요구 버전**(Claude Code v2.1.219+)이 명시된다 | Should | 두 파일에 버전 명시 문장 존재 |

우선순위: Must(없으면 미완성) / Should(중요하나 1차 후 가능) / Could(여유 시)

## 비기능 요구사항 (Non-Functional)

| ID | 요구사항 | 검증 방법 |
|----|---------|----------|
| NFR-1 | 인코딩·언어 규약 준수 — `.ps1`은 UTF-8 BOM, 그 외 BOM 없음, 문서·주석은 한글 | `post-write-checks` hook 무경고 + 전 ps1 parse OK |
| NFR-2 | 기존 hook 골든 케이스 **전량 무회귀** | `run-hook-evals.ps1` 무인자 전체 실행 exit 0 |
| NFR-3 | llm-wiki 상수·배치 정합 유지 | `check_consistency.py` exit 0 |
| NFR-4 | `confidence` 통제 어휘 **오염 0** — 리뷰어 판정 어휘 변경의 diff는 `plugins/pjc/agents/`에 한정 | 리뷰어 task의 `git diff --stat`에 `skills/llm-wiki/` 0줄 |
| NFR-5 | 신규 eval 자산이 **기존 검증 명령을 느리게 하지 않는다** — Phase F-2 전체 검증에 자동 편입되지 않고 명시 호출로만 실행 | AGENTS.md 검증 매핑 표에 별도 행으로 등재되고 기본 경로에 미포함 |
| NFR-6 | eval 러너는 **Python**으로 구현하고 표준 라이브러리만 쓴다(신규 패키지 의존 0) | 러너 실행 시 `pip install` 없이 동작. `PYTHONUTF8=1`·격리 `CLAUDE_CONFIG_DIR` 전제는 러너가 스스로 설정하거나 문서화 |

## Out of Scope (명시적 제외)

- **`PreCompact` hook 신설** — 2026-07-10에 "주입 목적엔 `SessionStart(source=compact)`가 공식 정답"으로 기각된 결정을 유지한다. FR-4는 기존 compact 분기의 **강화**이지 신규 hook이 아니다.
- **`Artifact`·MCP 도구의 hook 커버리지** — Deferred 대장 [2026-07-25] 항목 유지. 실제로 그 워크플로가 생길 때 착수.
- **리뷰어 모델·effort 티어 상향** — Deferred 대장 [2026-07-15]·[2026-07-25] 항목 유지. 이번은 판정 **어휘**만 바꾸고 티어는 건드리지 않는다.
- **공식 `skill-creator` 플러그인 자체 도입** — `run_eval.py`가 Windows에서 은닉 실패(전 쿼리 `trigger_rate 0.0`)함이 실측돼 있다. 자체 드라이버로 대체한다.
- **스킬 frontmatter `model:` 강제** — 사용자의 세션 모델 선택을 덮어쓰므로 도입하지 않는다.
- **`wiki-schema.md` 본문 감량·SKILL 분할 재편** — Deferred 대장 [2026-07-24] 항목. 별도 설계가 선행돼야 한다.
- **리뷰어 판정 스케일의 전면 복원**(0-100 confidence) — 2026-07-08 "근거 지목 기준" 결정을 전면 번복하지 않는다. FR-9는 부분 완화다.
- **SKILL.md 선두 구간 재구성 (구 FR-5)** — 2026-07-29 분리. 사유: 선두 9,000B는 제로섬이고(실측: `implement-task` 75행 / `plan-feature` 84행 / `llm-wiki` 79행에서 경계), 여기에 17항목 규칙을 재구성하는 문제는 **plan-reviewer 4회차까지 BLOCKER를 해소하지 못했다**. 나머지 요구는 2회차 이후 지적이 0건이라, 이 한 요구가 전체를 막지 않도록 분리한다. **압축 대응 자체는 FR-4(hook 주입)가 계속 담당한다.** 후속 plan이 쓸 자산(바이트 실측·항목 수·포인터 귀속·게이트 4축 설계·리뷰어 지적 9건)은 분리 시점 `plan.md`의 Investigation Log와 `docs/plans/deferred.md`에 보존한다.

## 성공 기준

- **active** Must 요구사항 **100% 충족**(REMOVED 처리된 FR-5는 대조 제외), Should **80% 이상**
- `run-hook-evals.ps1` 무인자 전체 실행 exit 0 (무회귀)
- `check_consistency.py` exit 0
- FR-1·FR-2의 러너가 **실제로 1회 이상 실행되어 수치를 산출**했고, 그 수치가 plan에 기록됨 (구현만 하고 미실행은 미충족)
