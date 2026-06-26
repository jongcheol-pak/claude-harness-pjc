# plan.md — 광범위 audit 결함 수정

## 목표
플러그인 전체 audit에서 발견된 결함(BLOCKER 3 + MAJOR 8 + MINOR 다수)을 모두 수정한다.
근본 원인 다수는 `systematic-debugging → pjc-systematic-debugging` 이름 변경 누락, 템플릿 패키징 누락, 문서·스크립트 stale 참조.

## 범위
plugins/pjc 하위 스킬·에이전트·hook 스크립트, 루트 install.ps1/validate.ps1, AGENTS.md.templates, 매니페스트.

## 승인 필요 사항 (사용자 "모두 수정"으로 승인됨)
- [x] AGENTS.md.templates 디렉터리 이동(구조 변경) — 사용자 승인
- [x] hook 스크립트 로직/출력 변경(다중 호출부) — 사용자 승인
- [x] 버전 업(plugin.json/README) — 사용자 승인

## 작업 단계

### T1. validate.ps1 stale 리스트 (B1)
- [x] skills 배열: `systematic-debugging`→`pjc-systematic-debugging`, `llm-wiki` 추가
- [x] hooks 배열: `backup-on-compact.ps1` 제거
- [x] 주석/카운트(6개→8개, 5개 유지), 템플릿 경로를 번들로

### T2. AGENTS.md.templates 번들로 이동 (B2)
- [x] `AGENTS.md.templates/` → `plugins/pjc/skills/bootstrap-agents-md/templates/` 이동
- [x] bootstrap SKILL.md, install.ps1, validate.ps1 경로 갱신

### T3. stale systematic-debugging 참조 정리 (M1)
- [x] marketplace.json description, install.ps1:290, multi-stack-example.md, evals.json description

### T4. implement-task 모순·번호 (B3 + minor)
- [x] halt-conditions.md 컨텍스트 한계를 SKILL rule4와 일치(중단 아님)
- [x] 규칙 7-1 중복, antipatterns V-7/V-8, phase-f-detail Follow-ups·F-6.5

### T5. llm-wiki 경로·메타 (M2/M7 + minor)
- [x] `reference/`→`references/` (SKILL·templates·lint.py docstring)
- [x] frontmatter vault 진실원천, evals `skill`→`skill_name`, wiki-schema questions·H-2 상수, lint.py anchor

### T6. PowerShell hook 로직·인코딩 (M3/M4/M8 + minor)
- [x] require-evidence 배열버그, impact-warn·check-utf8 additionalContext, UTF-8 출력, block-destructive 정규식, require-plan GetExtension

### T7. 생성기·plan-feature·기타 minor (M6 + minor)
- [x] add-viewmodel WPF/xmlns/UserControl, add-domain-service eval, bootstrap 마커·카운트, harness-toggle 예시, plan-feature 번호·참조, decision-points, plan-completion 라벨

### T8. 버전 업·문서·검증
- [x] plugin.json·README 1.59.0, notes.md, validate.ps1·lint.py 실행 검증

## 검증 방법
- `python lint.py` 구문/동작, `validate.ps1` 실행(FAIL 0 목표), 변경 명세 대비 역대조
