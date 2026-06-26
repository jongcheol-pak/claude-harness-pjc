# notes

## 최근 변경

- 2026-06-26: 위키·하네스 흐름 2차 audit 결함 수정 (1.59.0 → 1.60.0). 3개 병렬 시각 에이전트(① 위키 내부 정합 ② 하네스 흐름 정합 ③ 연동·메타·네이밍) + 직접 정독으로 발견한 **MAJOR 2 / MINOR 7** 수정. 메타·옛이름(`systematic-debugging` 잔존 0)·버전·위키↔하네스 연동은 전부 정합 확인(무수정).
  - **W1 (MAJOR) question resolved 삭제↔보존 모순**: `wiki-schema.md` §2.7·§4는 "흡수 후 삭제", `SKILL.md` B-2 3-1·`lint.py`(`status!=resolved` 집계)·schema §7-12는 "보존" 전제 → schema 내부 자기모순. 진실원천 "보존"(3:2, 최신 커밋 16c7588 의도)으로 §2.7·§4를 `status: resolved` 표시·보존으로 정정.
  - **W2 (MINOR) Lint 검사항목 4·8 뒤바뀜**: `SKILL.md` F-1(4=고아/8=모순) ↔ `wiki-schema.md` §7(4=모순/8=고아). SKILL을 schema(규칙 진실원천) 순서로 교환. 번호 역참조 0건이라 안전.
  - **W3 (MINOR) deprecated 필드 미반영**: B-1a가 도입한 `deprecated:`/`status: deprecated`를 schema §2.3·`templates.md`에 옵션 필드로 명세 추가. 폐기 feature 허브 처리를 "`## 폐기된 기능` 구역으로 이동(링크 유지)"으로 명확화 — 허브에서 링크 완전 제거 시 lint 허브 동기화가 "누락"으로 오발하던 빈틈 차단.
  - **H1 (MAJOR) Type B V-6 자기모순**: `implement-task` V-5 "Type B PASS → V-6 진행 (Sonnet 호출 안 함)"인데 V-6=code-quality(Sonnet)이고 Fast-Path 표·plan-feature·spec-prefilter는 Type B가 V-6 생략 → "V-7(축소)·V-8 진행, V-6 생략"으로 정정 + ESCALATE된 Type B도 V-6 생략 단서 추가.
  - **H2 (MINOR)** Phase G 진입조건 흐름 다이어그램(L150 "docs/prd.md 있을 때만")을 본문(`**PRD**:`줄·docs/prds/ 포함)과 일치시킴.
  - **H3 (MINOR)** `plan-reviewer` PRD 탐지에 `docs/prd.md`·`docs/prds/` fallback 추가(implement-task·plan-completion과 대칭 — `**PRD**:`줄 누락 시 게이트 빠짐 방지).
  - **H4 (MINOR)** `plan-reviewer` Type-aware 표: C/D 적용항목이 동일(D행 무의미)→"Type C/D 포함"으로 통합 + Type B에 항목9(자율준비도)·조건부 10(빈/null·경계값) 추가(plan-feature 통과 체크리스트와 정합).
  - **H5 (MINOR)** `plan-reviewer` 항목10 Edge 카테고리 8개→`edge-cases.md` 정본 10개(외부 의존 부재·멱등성 추가).
  - **H6 (MINOR)** Phase G G-1(메인 직접)과 F-7 `plan-completion-reviewer`(PRD cross-check)의 PRD 전수대조 중복 → G-1에 "F-7 결과 재사용, 메인은 갭처리(G-2~G-4) 집중" 역할경계 한 줄 명시.
  - **변경 파일(6)**: `wiki-schema.md`, `templates.md`, `llm-wiki/SKILL.md`, `implement-task/SKILL.md`, `plan-reviewer.md` (+ `plugin.json`·`README.md` 버전).
  - **검증**: grep으로 "흡수 후 삭제"·검사항목 번호 역참조·"V-6 진행" 잔존 점검 → 깨진 참조 0. schema §2.7/§4/§7-12 보존 일관, F-1↔§7 번호 일치, Type B V-5↔Fast-Path 일치 재확인. vault 미설정이라 lint.py 실행 불가(lint.py 자체 무수정). 빌드 대상 없는 문서 수정.
- 2026-06-26: 플러그인 전체 audit 결함 일괄 수정 (1.58.1 → 1.59.0). 7개 병렬 audit 에이전트 + 직접 검증으로 발견한 BLOCKER 3 / MAJOR 8 / MINOR 다수를 모두 수정. **근본 원인**: `systematic-debugging → pjc-systematic-debugging` 이름 변경이 스킬/매니페스트에는 반영됐으나 install/validate/marketplace/템플릿에 누락 + 템플릿 패키징 누락 + 문서 stale.
  - **B1 validate.ps1 (정상 설치에서 항상 FAIL)**: skills 배열 `systematic-debugging`→`pjc-systematic-debugging` + `llm-wiki` 추가(7→8개), hooks 배열에서 삭제된 `backup-on-compact.ps1` 제거(5개), 주석/카운트 갱신. 템플릿 검사 경로를 번들 내(`$pluginRoot\skills\bootstrap-agents-md\templates`)로, 기대 템플릿에 winui3.md·wpf.md 추가. (왜: 두 stale 항목이 존재 검사 FAIL → 건강한 설치도 ❌ 보고.)
  - **B2 bootstrap 템플릿 패키징**: repo 루트 `AGENTS.md.templates/`(번들 소스 `./plugins/pjc` 밖이라 설치 시 미포함)를 `plugins/pjc/skills/bootstrap-agents-md/templates/`로 `git mv`. SKILL.md 206행 문구·install.ps1:262·validate.ps1:184 경로 갱신. (SKILL 93/107행은 이미 `templates/<stack>.md`였어 이동만으로 정합.)
  - **B3 implement-task 컨텍스트 한계 모순**: `halt-conditions.md`가 컨텍스트 한계를 "즉시 정지+새 세션" Halt로 안내 → SKILL.md 규칙4(멈추지 않고 압축 통과)와 정면 충돌. halt-conditions를 규칙4와 일치하도록 재작성(중단 아님, plan.md 기록 후 auto-compact 통과).
  - **M1 stale 사용자 명령/이름**: install.ps1:290·multi-stack-example.md:152 `pjc:systematic-debugging`→`pjc:pjc-systematic-debugging`, marketplace.json·pjc-systematic-debugging evals.json description 이름 갱신.
  - **M2 llm-wiki `reference/`(단수) 경로 깨짐**: SKILL.md(17·233·291·303·330·362)·templates.md:4·lint.py docstring을 실제 디렉터리 `references/`로 정정.
  - **M3 require-evidence.ps1 배열 버그**: `git log --pretty=%B`가 다중 줄에서 배열로 캡처되어 `-notmatch`가 줄 단위 필터가 됨 → 증거 있어도 오탐. `-join "`n"`으로 단일 문자열화.
  - **M4 advisory hook 모델 전달**: impact-warn·check-utf8-and-lines(PostToolUse)가 stderr+exit 0이라 모델에 안 닿음 → stdout JSON `hookSpecificOutput.additionalContext` 추가(비차단). require-evidence(Stop)는 비차단 전달 메커니즘이 없어 advisory 유지(M3·인코딩만 수정). **설치된 Claude Code로 실측 권장.**
  - **M5 install.ps1 거짓 성공**: PS5.1에서 `& claude ...` 네이티브 비0 종료가 try/catch에 안 잡혀 실패해도 `[OK]`+exit 0. marketplace add·plugin install·enable 3블록에 `if ($LASTEXITCODE -ne 0) { throw }` 추가 + catch의 already 판정을 출력+메시지 기준으로. (실패 시 정상적으로 exit 1.)
  - **M6 add-viewmodel 컴파일 오류**: XAML이 `mc:Ignorable` 쓰며 `xmlns:mc`/`xmlns:d` 미선언 → 선언 추가. WinUI 전용 코드에 WPF 차이(`x:Bind`/`ProgressRing`/namespace) 주석 추가. UserControl B 변형 DataContext 모순 정정.
  - **M7 llm-wiki vault 진실원천 모순**: frontmatter가 번들 config.json이라 했으나 §0-1은 `~/.claude/llm-wiki-config.json` → frontmatter 정정.
  - **M8 한글 출력 인코딩(cp949 mojibake)**: 6개 hook 스크립트(block-destructive·require-plan-for-write·check-utf8-and-lines·impact-warn·require-evidence·harness-toggle)에 `[Console]::OutputEncoding = UTF8(BOM 없음)` 추가.
  - **MINOR**: block-destructive 정규식(`rm -rf ./*`·`rm -rf .` 차단 추가, `UPDATE...SET` WHERE-없음 가드를 `\bWHERE\b`로 "nowhere" 오탐 방지), check-utf8 IP 시크릿 패턴의 버전문자열 오탐 제외, require-plan `.env.example`/`.env.sample` 파일명 예외, lint.py 인덱스 링크 `#앵커` 제거, add-domain-service eval id3 결정표 정합(false), bootstrap 마커(requirements*.txt·AndroidManifest.xml)·카운트(7→8), harness-toggle 상태 예시 impact-warn 추가, implement-task 규칙 7-1 중복→7-2(+decision-points 참조), antipatterns V-1~V-6→V-1~V-8, phase-f-detail `## Follow-ups`→`## Deferred / Follow-up`·F-6.5 주석, plan-feature 규칙 7중복→8·참조에 prd-template, plan-completion-reviewer V-7/V-5 라벨 명확화, wiki-schema questions 닫기 라우팅·H-2 상수(SPECIAL_BUDGET/ORIGIN_REQUIRED_TYPES) 보강.
  - **검증**: PS1 8개 구문 정상·BOM 보존, JSON 6개 유효, block-destructive 정규식 8/8 케이스 PASS(합성 테스트), lint.py 합성 vault에서 sub-index 등록 feature·앵커 링크 feature 모두 "인덱스 누락" 오탐 없음 확인.
  - **의도적 미변경(리스크/모호)**: 에이전트 frontmatter 비표준 필드(effort/maxTurns/disallowedTools — 무시되지만 제거 시 동작 변경 위험, read-only 안전은 tools 화이트리스트로 성립), plan-reviewer 본문의 예시 `grep`(Grep 도구로 매핑되는 illustrative).
