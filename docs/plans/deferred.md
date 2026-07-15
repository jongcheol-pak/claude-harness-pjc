# Deferred 대장

> 미처리 Deferred의 단일 추적 대장 (형식 정본: implement-task `references/phase-f-detail.md` F-6.5).
> 항목은 `- [등록일] {요지 1줄} (출처)`, 종결 시 삭제가 아니라 `## 종결`로 이동한다.
> plan-feature Step 1이 계획 때 `## 대기`를 조회하고, implement-task F-6.5가 완료 때 신규분을 append한다.

## 대기

- [2026-07-15] **Phase F에 전체-diff(BASE..HEAD) 품질 패스 추가** — task별 diff 리뷰(V-6)는 task 간 누적 중복·패턴 불일치·여러 task에 걸쳐 비대해진 파일을 원리적으로 못 본다. 전 task 완료 후 전체 diff에 1회 품질 리뷰를 수행하는 F-단계 신설 검토. v1.122.0 3레버(Design 필드·V-6 기본화·SUGGEST)의 효과 관찰 후. (출처: v1.122.0 plan Deferred)
- [2026-07-15] **simplify(정리) 패스** — 리뷰 통과 후 diff를 더 단순하게 정리하는 단계. 자율 루프 churn(수정→재리뷰 반복) 위험이 있어 범위·트리거 별도 설계 필요. (출처: v1.122.0 plan Deferred)
- [2026-07-15] **품질 루브릭 eval(Opus judge 채점)** — 고정 task 세트를 돌려 아키텍처 품질을 1-10 루브릭으로 채점, 파이프라인 변경 효과를 수치로 측정(eval 기준선은 Opus 실작업). (출처: v1.122.0 plan Deferred)
- [2026-07-14] **문자열 형태의 상위 탈출(`..`)·`/.*` 미탐** — `Remove-Item -Recurse -Force "$env:APPDATA\..\..\.."`(드라이브 루트로 상승)·`rm -rf "/.*"`이 현행에서 통과한다(실측 PASS). v1.121.0의 `Join-Path` 정규화가 만든 구멍이 **아니다** — 조인 조건 ②③이 이런 자식을 걸러 `Join-Path` 경로에서는 차단 유지되며, 남은 것은 원래부터 뚫려 있던 문자열 형태다. `$dangerTarget`에 `\.\.`·`/\.?\*` 성분을 추가하는 강화는 정상 상대 경로(`../build` 정리) 오탐과 트레이드오프가 있어 별도 검토 필요. (출처: v1.121.0 plan Deferred / plan-reviewer 2회차 M1)
- [2026-07-14] **`$env:` 별칭 시스템 루트의 깊이 cap 미탐** — `$env:SystemRoot`·`$env:SystemDrive`·`$env:ProgramFiles`·`$env:windir`처럼 **환경변수가 시스템 경로를 가리키는 경우**, 그 하위 삭제(`"$env:SystemDrive\Windows"`·`(Join-Path $env:SystemDrive "Windows")`)가 통과한다. `$dangerTarget`이 `$env:NAME`을 리터럴 토큰으로만 보고 **값이 무엇인지 모르기 때문**(깊이 cap의 구조적 한계 — v1.98.0 승인 설계). **v1.121.0이 만든 구멍이 아니다**: 등가 문자열 형태가 수정 전에도 이미 통과했고(실측), Join-Path 형태가 그와 대칭이 된 것뿐이라 실질 공격면 증가는 0이다. 다만 37케이스 매트릭스·골든 어디에도 이 축이 없어 의식적 판단 없이 통과했다. 위 `..` 미탐 항목과 **같은 성격**(정규식이 값이 아니라 표기만 본다)이라 함께 검토. (출처: v1.121.0 F-7 m1 — 리뷰어 독립 프로브)
- [2026-07-14] **`Join-Path` 3인자·중첩 괄호·역순 명명 인자의 오탐 잔존** — `(Join-Path $env:TEMP "claude" "x")`(PS6+ AdditionalChildPath)·`(Join-Path $env:TEMP (Get-Date -F yyyy))`·`(Join-Path -ChildPath "x" -Path $env:TEMP)`는 정규화 정규식에 매치되지 않아 무변경 → 현행 차단이 유지된다(정상 작업이 막히는 오탐이지만 **오차단 방향이라 안전**). 골든에 `[알려진 오탐 — 3인자 미커버]` 라벨로 현행 동작만 고정해 뒀다. 실제 오차단이 관측되면 커버 확대. (출처: v1.121.0 Out of Scope / D5)
- [2026-07-13] **DB 연결 문자열 패턴이 흔한 실제 형태를 미탐** — `secret-patterns.ps1`의 `(Server|Data Source)=[^;]+;\s*(User|Uid|Password|Pwd)=`는 `Server=` **바로 뒤에** 자격증명 키가 와야 매치한다. 실제로 흔한 `Server=x;Database=y;User Id=sa;Password=z;`(중간 키 + `User Id=` 공백 표기)는 **불매치**(저신뢰 `password 값` 경고만). 이 라벨이 고신뢰 **차단** 등급이라 실효성이 걸린 문제. `[^;]*(;[^;]+)*` 류로 중간 키 허용 + `User\s*Id` 표기 수용 검토 — 오탐 회귀(정상 설정이 연결 문자열로 오인)를 골든으로 함께 확인할 것. (출처: v1.119.0 T2 골든 FAIL 조사 / F-7 M1)
- [2026-07-13] **도메인형 비밀번호 미탐** — `Test-CredentialPairToken`의 파일명 배제(마지막 `.` 뒤 2~5 영문자)가 pw 토큰에도 적용돼 `Secret1.io`·`Pw123.dev` 류를 놓친다. **의도적 트레이드오프**(pw에서 배제를 빼면 `계정: admin / config2.yml` 류 파일명 쌍이 오탐되고, 이 라벨은 커밋 차단 기준이라 오탐 1건이 자율 루프를 세운다). 엔트로피·사전 대조 등 더 정밀한 판별 근거가 생기면 재검토. (출처: v1.119.0 T1 quality M1)
- [2026-07-13] **자격증명 쌍의 나머지 미탐 형태** — 마크다운 **표 형태**(`| admin | pw |`)는 라벨 0건(경고조차 없음), **줄 분리형**(`- 아이디: admin` / 다음 줄 `- 비밀번호: pw`)은 `password 값` 경고만. 표·줄분리는 문서에서 흔한 표기라 차단 등급 확장 시 오탐 위험이 크므로, 경고 계층(post-write)에서 먼저 데이터를 모은 뒤 결정할 것. (출처: v1.119.0 F-7 M1 실측)
- [2026-07-13] **비인용 자격증명 쌍(경고 라벨)의 숫자 접미 열거형 오탐** — `Account 상태: active / suspended_30d`·`Login 실패 코드: AUTH_401 / AUTH_403` 같은 **상태·에러코드 열거**가 pw 토큰 요건(6자 + 숫자)을 만족해 `자격증명 쌍(비인용)` 경고를 받는다. 차단이 아니라 경고라 루프는 안 서지만, 이 라벨은 **편집 시점 hook이 모든 파일 쓰기마다 발동**하므로 늑대소년화 대상이다(D9가 경계한 바로 그 실패 모드). pw 토큰 요건을 "숫자만으로는 부족, 특수문자 필요" 쪽으로 좁히거나 `<영문>_<숫자>` 접미 패턴을 배제할지 검토 — 단 실제 비밀번호 중 숫자만 든 것도 흔하므로 미탐 트레이드오프를 함께 볼 것. 부수: `account: \`svc-runner\` / \`deploy-2024\`` 같은 서비스 계정·배포 태그 표기가 **고신뢰(차단)** 판정을 받을 여지도 확인 필요. (출처: v1.119.0 F-7 2회차 m1)
- [2026-07-13] **한 호출 안에서 파일 생성 + 즉시 커밋은 여전히 통과** — `cat > R.md <<EOF … EOF; git add -A && git commit`은 hook 시점에 **파일이 아직 없어** exit 0이다(PreToolUse의 구조적 한계). 다만 **heredoc 본문이 command 문자열에 그대로 있으므로**, 명령 텍스트 자체를 `Get-SecretMatches`에 통과시키면 저비용으로 닫힌다. 오탐(명령에 시크릿 '언급'만 있는 경우) 위험을 골든으로 확인한 뒤 도입 검토. (출처: v1.119.0 F-7 2회차 m2)
- [2026-07-13] **커밋 게이트 스캔 상한** — `Invoke-WarnCommitSecrets`의 선행 `git add` 스캔이 파일 50개·1MB 상한을 둔다(hook 지연 방지). 상한 밖 파일은 미스캔이라 이론상 미탐 가능. 커밋 직전 신규 파일이 50개를 넘는 경우는 드물고 그때도 `--cached`/`diff HEAD` 경로는 작동하나, 상한 도달 시 경고를 남길지 검토. (출처: v1.119.0 T9)
- [2026-07-13] README 버전 이력의 **서술 정책 확정**(시점 스냅샷 vs 현행 반영) — v1.117.0에서 과거 v1.100.0 블록의 문장을 현재 동작으로 소급 수정하고 "(v1.117.0에서 …)" 각주를 달았는데, 이 repo의 다른 이력 블록은 append-only 관례다. 그 블록이 "Subagents(검토 담당)" 섹션 안에 있어 독자가 현재 기능 설명으로 읽는 위치라 이번엔 stale 방치보다 정확성을 택했으나, 정책 자체가 미확정 (출처: v1.117.0 T1 quality 리뷰 m1)
- [2026-07-10] 골든 러너 `-Filter "a,b"` 단일 문자열 바인딩 시 콤마 split 안 됨(배열 전달만 동작) — 기존 동작, 다음 러너 정비 때 (출처: v1.112.0 T1 quality 리뷰 m2)
- [2026-07-13] `pjc-systematic-debugging` 단독 세션이 **plan.md가 없는 레포**에서 조사 로그를 plan.md로 **신규 Write**하면 plan 작성 게이트에 차단된다(통과 흔적 목록에 debug 스킬 없음 — D3). 실해는 작다(SKILL.md:281이 `debug-<날짜>.md` 대안을 이미 제시, 차단 메시지도 그리로 유도). SKILL.md:281에 "plan.md가 없으면 `debug-<날짜>.md`" 1구 명문화 또는 흔적 허용 여부 재검토 (출처: v1.118.0 F-7 m2)
- [2026-07-13] 비표준 체크박스 문자(`- [-]` 취소·`- [~]`) 표기만 쓰는 외부 레포는 `$planTaskRx`(` `/`x`/`X`/`/`만 인정)에 무매치라 `docs/plans/`가 있어도 plan 판정 OFF → 코드 Write 전면 차단(종전엔 통과). 진단 문구로 회복 가능하나 문자 클래스 확장 검토 (출처: v1.118.0 F-7 m3)
- [2026-07-13] `$isInPlansDir` 정규식이 선행 구분자 필수(`[\\/]docs[\\/]plans[\\/]`)라, 상대경로 `docs/plans/x.md` Write가 오면 게이트 미발동인데 `Test-PlansDirHasPlan`은 그 파일을 plan으로 인정 → 게이트/판정 비대칭. Claude Code Write는 절대경로 계약이라 현 재현성 낮음(기존 AGENTS 게이트도 동일 가정) — 차기 hook 정비 때 `(^|[\\/])` 분기 추가 검토 (출처: v1.118.0 F-7 m4)
- [2026-07-08] block-destructive: `cat <<EOF > file`(데이터 싱크 스트립) 후 같은 Bash 호출에서 즉시 실행 시 위험 본문 미스캔 — "파일 작성+동일 호출 실행" 조합 감지 개선 (출처: harness-quality-part1)
- [2026-07-08] suggest-agents-record 명령 오인 오탐 2류 — ① 커밋 -m 값 속 명령 문자열 ② grep 패턴 문자열 속 "dotnet build" — hook 이벤트 로그 데이터 축적 후 근거 기반 수정 (출처: harness-quality-part1·v1.101.0)
- [2026-07-08] .state 디듑 마커(post-write-warn·require-plan-warn·suggest-agents-record) 누적 정리 정책(TTL/청소) 부재 (출처: harness-quality-part1)
- [2026-07-08] (저신뢰 audit) block-destructive 열거 `.` 제외의 이름필터 판정에서 `-Include *.tmp,*` 콤마 배열 catch-all 원소 통과 여지 — 차기 hook 정비 때 감사 케이스로 검토 (출처: harness-quality-part1 F-7)
- [2026-07-09] suggest(제안) 이벤트의 로깅 확장 — v1.105.0 T2는 차단+경고만(사용자 확정 범위) (출처: harness-wiki-part1)
- [2026-07-09] lint.py --fix 대상 확대(§7-19 누락 행 추가 등) — 키워드 요약을 기계 생성할 근거가 생기면 재검토 (출처: harness-wiki-part2)
- [2026-07-09] lint.py `section()` 헬퍼 Match 반환형 확장으로 `section_span()`과 단일화 — 호출부 리팩터링 동반, 다음 lint.py 정비 때 (출처: harness-wiki-part2 T2 리뷰 m2)
- [2026-07-09] 나머지 7개 프로젝트 메모리의 위키 순차 이전(AI-Agents·neighborhood-walk-rpg·Obsidian-Vault-WIKI·bitleader-dev-HomePage·Web-HomePage·ProjectDashboard·DevDashboard-WinUI) — 각 프로젝트 위키 절차 B 세션에서 (출처: v1.102.0)
- [2026-07-09] SessionStart hook의 위키 허브 컨텍스트 자동 주입 — v1.102.0 미채택(지침 방식 선택), 지침 방식 실효성이 낮다고 관찰되면 재검토 (출처: v1.102.0)
- [2026-07-09] 위키 허브 `## 작업 규약·주의사항`이 수십 건으로 커지면 전용 페이지(worknotes류) 승격 검토 (출처: v1.103.0)
- [2026-07-10] warn-external-ops가 `gh release create --notes "…git merge…"` 노트 값 속 텍스트를 오탐 — 커밋 `-m`/`--message` 값은 스트립하나 `--notes` 값은 미스트립이라 노트 본문의 push/merge/tag 텍스트가 규칙에 걸림(비차단), `--notes`(및 유사 값 옵션) 스트립 또는 `git ` 접두 요구로 개선, 다음 hook 오탐 정비 라운드에서 (출처: v1.113.1 릴리즈 발행 시 실관찰)

## 종결

- [2026-07-10 → 2026-07-13] AGENTS 게이트 임시폴더 예외 분기 골든 케이스 추가 — 반영(v1.118.0 T1 — TE1(plan 게이트)·TE2(AGENTS 게이트) 2건 신설. 픽스처를 `$iso`(GetTempPath 하위) + **흔적 없는 transcript 주입**으로 구성해, 미주입 시 fail-open으로 exit 0이 나는 거짓 green을 방지)
- [2026-07-08 → 2026-07-12] 위키 feat-safety-hooks 보호 집합 서술("hook 스크립트 8종") 현행화 — 확인 종결(2026-07-12 하네스 ingest 세션에서 grep 확인: "8종" 서술이 이미 없음 — 이전 ingest(v1.108~113 반영)가 "검사 10종 + 디스패처"로 현행화 완료)
- [2026-07-09 → 2026-07-12] llm-wiki fixture `archive-exempt/.../oldproj.md` UTF-8 BOM 정리 — 기각(v1.116.0 D6: 그 BOM은 lint-cases archive-exempt 케이스의 expect_absent "BOM"이 검증하는 **의도된 테스트 입력**(90_archive BOM 무경고 실증)이라 제거하면 검증이 공허해짐 — 컨벤션 위반이 아니라 테스트 대상 데이터)

- [2026-07-10 → 2026-07-10] warn-external-ops가 `git merge-base`(읽기 전용 조회)를 "git merge"로 오탐 — 반영(v1.113.1 T1 — bash-hook-lib.ps1:39 `merge\b`→`merge(?![-\w])`, merge-base·merge-tree·merge-file·merge-index plumbing 오탐 제거·실제 merge 경고와 --abort/continue/quit 제외 보존, 골든 merge-base·merge-tree 무경고 2건 추가)
- [2026-07-10 → 2026-07-10] 위키 feat-safety-hooks·feat-plan-feature에 v1.111.0 bootstrap 게이트·직접 작성 금지 반영 — 반영(2026-07-10 위키 ingest 세션 — feat-plan-feature Step 1 bootstrap 강화 + feat-safety-hooks require-plan 게이트 동작·지도 서술)
- [2026-07-10 → 2026-07-10] Type B 분류 정의가 구조 기준(단일 파일·메서드·호출자 없음)뿐이라 신규 비자명 로직이 B로 새어 검토(V-5 prefilter만·V-3/V-6 생략) 얕아짐 — 반영(v1.113.0 T1 — plan-feature:257에 경계 명문화(비자명 로직·알고리즘·제어흐름·상태변경 신규 심볼은 Type C 이상, 자명 접근자·상수·순수 위임은 B 유지) + plan-reviewer:39 오분류 검출 예시 병기, 방어선 2층)
- [2026-07-10 → 2026-07-10] SessionStart matcher `compact` 추가 + 요약 직후 재확인 컨텍스트 주입 — 반영(v1.112.0 T1 — session-context.ps1 신설, matcher 4종 + compact 리마인더, 골든 SC2)
- [2026-07-10 → 2026-07-10] post-write-checks notes.md 30,000자 초과 아카이브 경고 — 반영(v1.112.0 T2 — 섹션 2b, Test-WarnOnce 디듑, 골든 NA1~NA3)
- [2026-07-10 → 2026-07-10] SessionStart에 plan.md 존재·미완료 task 수·notes.md 최신 항목 날짜 주입(로컬 경량판) — 반영(v1.112.0 T1 — session-context.ps1에 compact 항목과 통합 구현, 골든 SC1·SC1b·SC3~SC5)
- [2026-07-10 → 2026-07-10] implement-task Phase D clean/dirty 판정×재리뷰 커밋 프로토콜 모순 + review-fix 커밋 메시지 미규정 — 반영(v1.110.0 T1 — Phase D ①을 HEAD 커밋 제목 판정으로 교체·review-fix checkpoint 규정·재개 트리 5분기+폴백·새 완료 커밋 --allow-empty)
- [2026-07-10 → 2026-07-10] plan-feature 분할×PRD 전수 커버×12-a 규정 교착 — 반영(v1.110.0 T2·T3 — part별 Coverage 스코프(`⏭️ 다음 part`/`✅ 이전 part 기구현` 행)+합집합=전수 게이트+두 part 동시 작성 명문화, 12-a 분할 인지+실질 MAJOR 게이트, 마지막 part Phase G/F-7 전수(전체 트리 기준))
- [2026-07-09 → 2026-07-10] 하네스 최근 버전분(v1.102.0~) 위키 ingest — 반영(2026-07-10 위키 세션 2회: v1.102~1.108 feature 5페이지 상세 ingest + v1.109.0 델타·run_eval 함정·A~L 표기 드리프트 정정, lint 델타 0)
- [2026-07-08 → 2026-07-10] plan-feature description 1,018자 하드 한도(1,024) 근접 — 반영(v1.109.0 T5 — 981자로 무손실 압축(연결부만), 여유 43자. pjc-systematic-debugging 1,019→921자도 동일 처리. 전후 트리거 eval 동률 실증)
- [2026-07-09 → 2026-07-09] hook 이벤트 로그 자동 요약(3개월 축적 후) — 반영(v1.107.0 T2 `report-hook-events.ps1` 수동 리포트로 대체 — 자동 실행은 사용자 확정으로 채택 안 함)
- [2026-07-08 → 2026-07-08] llm-wiki 본체에서 절차 K 초경량 분리 — 기각(정식 검토 결과 분리하지 않음: 최빈 경로가 본체를 어차피 로드해 토큰 중립+Read 1회 지연만 추가. 재논의는 로드 경로가 바뀔 때만 — deferred-followups-closure)
- [2026-07-08 → 2026-07-08] explorer subagent 모델 상향(haiku→상위) — 기각(현행 유지: effort medium 반영 직후 관찰 기간 0·실패 실사례 없음. 재검토 조건: locating 실패·부정확 실사례 관찰 시 — deferred-followups-closure)

<!-- 초기 시드 sweep 근거 (2026-07-09, v1.107.0 T4): notes.md 현행 전 항목의 "미처리 Deferred" 목록 +
     docs/plans/*.md 6파일의 "## Deferred / Follow-up" 섹션 + notes-archive/2026-07.md 대조.
     중복은 최초 출처로 병합(suggest-agents-record 오탐 2류는 동일 수정 라운드라 1항목).
     "재설치(install.ps1)"는 반복 등장하나 작업 항목이 아니라 사용자 지시로 보류 중인 운영 행위라 제외.
     분할 plan 상호 포인터(다음 plan 안내)는 실행 완료된 안내문이라 제외. -->
