---
type: index
okf_version: "0.1"
updated: 2026-08-21
---

# LLM WIKI

<!-- 생성 마커가 없는 vault는 wiki-schema §4의 마커 없는 vault 분기대로 `## 가이드 / 레시피`
     섹션을 그대로 유지하고, 그 행은 첫 컬럼이 wikilink다. 통합 표 전용 판정(첫 컬럼 평문)만
     남기면 이 형상은 폐지된 가이드 섹션 전용 검사에도 §7-16에도 걸리지 않아 병기 무신호가 된다.
     feat_row_name 조건 ②가 `40_guides/` wikilink 첫 컬럼을 함께 받는 것을 이 fixture가 고정한다.
     아래 `## 참조` 표의 첫 컬럼 wikilink 행은 대상이 `40_guides/`가 아니라 **제외**돼야 한다 --
     프로젝트/기술 표를 병기 검사로 끌어들이지 않는다는 반대 축(조건 ②의 40_guides 한정). -->
## 가이드 / 레시피
| 가이드 | 설명 |
|---|---|
| [[40_guides/ui-ux/legacy-help\|옛 섹션 도움말 가이드]] | 첫 컬럼 wikilink · 한글 전용 alias |

## 참조
| 대상 | 설명 |
|---|---|
| [[log.md\|변경 로그]] | 첫 컬럼 wikilink이나 `40_guides/`가 아니라 병기 검사 제외 |
