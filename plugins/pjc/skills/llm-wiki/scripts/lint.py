#!/usr/bin/env python3
"""llm-wiki Lint 보조 스크립트.

사용법: python lint.py "<vault_path>" [--fix] [--build-index [--dry-run]]
검사: 깨진/경로 없는 wikilink(루트 큐 파일 pending.md·skill-feedback.md는 제외 — §7-1) / 예산 준수(§7-2 발동·guide_kind 부재/오타 —
      platform-bootstrap·ui-ux guide는 코드 펜스 내부 문자 제외 판정, recipe는 펜스 포함)
      / platform·origin·confidence·category 통제어휘 위반·누락
      / updated 필드 누락(§7-9 — 신선도 추적 전제) / feature '## 구현 방법' 섹션 부재(§7-18 확장)
      / 고아 페이지(간이) / 신선도(60·90일)·미래 날짜 / 기능별 인덱스·허브 동기화 / 네이밍 규칙 / 타입 미지정
      / tech_stack 휘발성 버전 / index·sub-index 분할 신호(INFO) / deprecated 표기 정합·집계 / feature 구현 근거 각주
      / feature 각주 경로 레포 실존(§7-20 — 허브 '레포 정보 > 경로'의 레포 접근 가능 시)
      / feature '## 관련 파일' 섹션 게이트 + 경로 실존(§7-21 — §7-20과 동일 레포 루트 캐시)
      / 시크릿 의심 패턴(§7-22 — password/API key/token/Bearer/DB 연결문자열/개인키/URI 자격증명)
      / 큐 잔량 집계(INFO — 절차 K 큐, **두 파일을 각각 별도 줄로**, §7-25)
        · pending.md: [K-DRIFT]/[DECISION]/[PROJECT-FACT]/[K-MISS]/[SYMPTOM] 태그별
        · skill-feedback.md: [SKILL-IMPROVE] (플러그인 개선 후보 — SKILL K 5-1)
        + 형식 위반(WARN — 태그는 있으나 날짜 선두가 아니라 집계에서 누락되는 줄, §7-25)
      / decision-log 정합(§7-24 — '## 아카이브' 포인터 ↔ 실파일 양방향 + 항목 결정 어휘)
      / log 아카이브 인덱스 정합
      / 미해결 질문 인덱스 동기(§7-23 — open 미등록 유실 위험·resolved 잔존 stale)
      / index.md 부재·읽기 실패(ERR — 인덱스 기반 검사 불능 신호. 두 사유는 처방이 정반대라
        각각 다른 ERR: 부재는 골격 생성, 읽기 실패는 인코딩 복구)
      / 위키 뒤처짐(INFO — 허브 synced_commit 이후 레포에 쌓인 커밋 수, §7-26. fail-open)
      / (미검증)·미해결 question 집계(INFO)
      / 본문 릴리즈 마커(§7-28 — vX.Y.Z 3필드 semver, §5 changelog 미러링 금지. decision-log·question 제외)
      / 장식 이모지(§7-29 — 20_/30_/40_ 본문 산문의 Emoji_Presentation 이모지. 코드펜스·lint-* 리포트·decision-log 제외)
      / 이동·분리 도달 경로 정합(§7-30 — ⓐ 허브 '## 아카이브' 포인터 ↔ changes.md 양방향
        ⓑ conventions.md '## 하위 문서' 목록 ↔ 하위 파일 양방향)
      / 작업 규약 미마이그레이션(§7-31 — 허브에 '## 작업 규약·주의사항' 잔존 시 INFO, conventions.md 이전 대상).
출력: 사람이 읽는 보고(오류/경고/정보). 기본 실행은 파일을 수정하지 않는다(읽기 전용) —
      `--fix`는 §7 참조 무결성 안전 3종(§7-23·§7-24·§7-19 stale 행)만 적용(승인 후 실행, 자동 백업 — schema §7 서두 정본).
범위: vault 파일 읽기 + 레포 접근 2종 — §7-20·§7-21의 파일 '실존' 확인과 §7-26의 git 이력 조회
      (커밋 '수'만 셈). 어느 쪽도 코드 내용은 해석하지 않는다
      (서술↔코드 사실 정합은 §7-10 에이전트 표본이 담당).
규칙 진실원천은 references/wiki-schema.md. 예산/통제어휘가 바뀌면 이 상수도 함께 갱신할 것
(H-2 규약(references/procedures-ops.md): 예산표(references/wiki-ops-rules.md)·wiki-schema §3~§4·이 파일 3중 동기화).
"""
import os, re, sys, glob, shutil, datetime, subprocess, collections

# Windows 콘솔(cp949)에서도 한글이 깨지지 않도록 UTF-8 출력 강제
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# 임박 판정의 선행 게이트 — 자체 신호를 내지 않는 내부 임계다(v1.177.0에서 근접 INFO 폐지).
#  이 상수를 지우면 안 되는 이유: 임박은 `이 비율 이상 AND (비율 조건 OR 잔여 조건)`이라,
#  선행 게이트가 빠지면 예산이 작은 타입(source-stub 1800)에서 72%짜리가 잔여 조건만으로 임박이 된다.
BUDGET_NEAR_RATIO = 0.8

# 예산 임박 임계 — 초과 전에 나는 유일한 신호다. 선행 게이트가 참인 파일 중 아래 둘 중 하나면 WARN.
#  왜 두 축인가: 비율만 쓰면 여유 414자인 decision-log(93%)를 놓치고, 절대값만 쓰면 예산이 작은
#  타입(source-stub 1800)에서 72%짜리가 임박이 된다. 선행 게이트 + OR 결합이 실측 분포를 정확히 가른다.
#  왜 단일 단계인가: 80% INFO를 함께 내던 때는 여유 28자와 1,624자가 같은 줄로 나와 정작 급한 것이
#  INFO 더미에 묻혔다(실측 INFO 99건 중 10건). 묻히는 층을 없애고 WARN 하나만 남긴다.
BUDGET_CRITICAL_RATIO = 0.95
BUDGET_CRITICAL_SLACK = 500

# 백업 자동 정리 임계(§8) — `-presplit` 사본을 며칠까지 보존하는가.
#  §8의 "30일 지난 폴더는 삭제한다"를 그대로 쓴다. 접미사 없는 `{YYYY-MM-DD}/`는 이 값과 무관하게
#  「오늘 것만 남긴다」로 더 빨리 회수된다(위키 decisions [2026-08-13] 채택 — 아래 cleanup_backups).
BACKUP_KEEP_DAYS = 30

# 「분리 불가 판정」(frontmatter budget_split) — 나눌 하위 주제가 없는 페이지(단일 주제 recipe·concept)는
#  §4의 이동·분리 처방이 성립하지 않는다. 판정을 기록하면 임박 WARN을 「분리 불가 판정 유지」 INFO로 강등한다.
#  판정 시점 문자 수(budget_split_chars) 대비 이 마진을 넘게 자라면 억제가 풀려 재판정을 강제한다 —
#  영구 면제로 두면 "한 번 판정하면 초과까지 무신호"가 되어 판정이 곧 사각이 된다.
BUDGET_REJUDGE_MARGIN = 0.10
BUDGET_SPLIT_VOCAB = {"none"}

BUDGET = {  # type -> 최대 문자 수 (wiki-schema.md §4와 일치 유지 — v1.138.0 줄 수→문자 수 전환)
    #  줄 수는 밀도를 못 담아(한 줄에 500자를 써도 통과) 예산이 무의미했다 → 문자 수로 전환.
    #  단 index.md는 '행 수(등록 항목 개수)'가 본질적 단위라 문자로 못 바꾼다(INDEX_* 별도 경로 유지),
    #  log.md도 이미 문자 수(SPECIAL_BUDGET). 즉 산문 타입만 이 딕셔너리로 문자 수 판정한다.
    "source-stub": 1800, "project": 13000, "feature": 22000,
    "entity": 6000, "concept": 5000, "question": 3500,
    "decision-log": 6000,  # 결정 이력 (wiki-schema §2.8 — §7-2 발동 시 90_archive 원경로 이동)
    #  작업 규약 (§2.9 — §7-2 발동 시 ① 무효 항목 제거 → ② ①로도 해소 안 되면 하위 분리 → 재분할. 아카이브 롤오버는 안 한다:
    #  절차 K가 매 작업 전에 읽으므로 아카이브로 옮기면 조회 경로 밖이 되어 이동이 곧 유실이다)
    "convention": 12000,
}
GUIDE_BUDGET = {"platform-bootstrap": 9000, "ui-ux": 6000, "recipe": 8500}
PLATFORM_VOCAB = {"windows-desktop", "web", "mobile", "cli", "cross"}
ORIGIN_VOCAB = {"agent-synthesized", "human-validated"}
CONFIDENCE_VOCAB = {"high", "medium", "low"}
# vault 루트 소비 대기 큐 (wiki-schema §6·§7-1·§9 — 지식 페이지가 아니라 검사 대상에서 제외되는 축).
#  둘로 나뉜 이유는 소비 주체가 다르기 때문이다 — pending.md는 위키 세션이 반영 후 제거,
#  skill-feedback.md는 플러그인 개선 후보라 위키에 반영하지 않고 사용자 보고만 한다(SKILL K 5-1).
ROOT_QUEUE_FILES = {"pending.md", "skill-feedback.md"}
# 큐 항목의 정상 접두 — `[YYYY-MM-DD] ` 하나뿐이다(§7-25 형식 규약). 형식 위반 판정이
#  이 정규식과 어긋나는 접두를 위반으로 센다: 날짜 누락(`- [TAG]`)·형식 불일치(`[2026-7-2]`)·
#  대괄호 없음(`- 2026-07-02 [TAG]`) 셋 다 여기서 걸린다.
QUEUE_DATE_PREFIX_RX = re.compile(r"^\[\d{4}-\d{2}-\d{2}\]\s*$")
# decision-log 항목 결정 어휘 (wiki-schema §2.8·§3 — 어긋나면 타임라인 합성·번복 추적 누락)
DECISION_VOCAB = {"채택", "보류", "기각", "번복"}
# 본문 릴리즈 마커 (§7-28 — §5 "changelog 미러링 금지"의 기계 신호). v접두 3필드 semver만 —
#  2필드(v1.2)·v 없는 버전(2.9.2)은 제품 라인·라이브러리 버전일 수 있어 비검출(오탐 회피가 1급 요건).
#  경계를 \b로 하지 않는 이유: 한글도 \w라 "v1.2.3에서"(실vault 최빈 형태)의 꼬리 경계가 실패한다 —
#  영숫자·언더스코어·점만 명시 배제해 한글 인접은 매치하고 식별자 일부(curve1.2.3)·4필드는 배제.
RELEASE_MARKER_RX = re.compile(r"(?<![0-9A-Za-z_.])v\d+\.\d+\.\d+(?![0-9.])")

# 장식 이모지 (§7-29 — 위키 본문 평문 원칙). Unicode Emoji_Presentation=Yes 코드포인트 + VS16(U+FE0F).
#  이 속성은 "기본이 컬러 이모지 표현인 문자"만 포함해, 화살표(→ U+2192)·흑백 기호(⚠ U+26A0·★ U+2605·
#  ✔ U+2714)는 자동 배제된다(모두 text-default) — 산문에서 기능적으로 쓰이는 기호를 오탐하지 않기 위함.
#  ✅(U+2705)는 Emoji_Presentation=Yes라 검출, ✔(U+2714)는 No라 비검출(경계 예). VS16은 text-default
#  기호를 이모지로 강제 표현하는 신호라(예: ✔️=U+2714+FE0F) 존재만으로 장식 의도로 본다.
#  SMP(U+1F300–1FAFF 등)는 전부 이모지라 범위로, BMP는 Emoji_Presentation 코드포인트만 명시 열거한다.
EMOJI_RX = re.compile(
    "["
    "\U0001F300-\U0001FAFF"   # 그림문자·이모티콘·교통·기호(🎯🚀😀🔴🟡 등)
    "\U0001F1E6-\U0001F1FF"   # 지역 표시자(국기)
    "\U0001F000-\U0001F0FF"   # 마작·도미노·카드(🀄🃏)
    "⌚⌛⏩-⏬⏰⏳◽◾☔☕"
    "♈-♓♿⚓⚡⚪⚫⚽⚾⛄⛅"
    "⛎⛔⛪⛲⛳⛵⛺⛽✅✊✋"
    "✨❌❎❓-❕❗➕-➗➰➿"
    "⬛⬜⭐⭕"
    "️"                  # VS16(이모지 표현 강제) — text-default 기호를 이모지화한 신호
    "]")

# decisions '## 아카이브' 포인터 패턴 — §7-24 판정(main)과 --fix(apply_fixes)가 같은 대상을 보도록
#  단일 출처로 둔다(한쪽만 고치면 lint 판정과 fix 대상이 조용히 어긋나는 드리프트 방지 — T2 리뷰 m1).
DEC_PTR_RX = re.compile(r"(90_archive/[^\s`()]+decisions\.md)")
# 허브 '## 아카이브' 포인터 패턴 (§7-30ⓐ — 최근 주요 변경 롤오버 대상). DEC_PTR_RX와 같은 형태를
#  대상 파일만 바꿔 쓴다. 통합 함수를 만들지 않는 이유: 대상 섹션·현행 경로 도출 규칙·--fix 대상
#  여부가 달라(§7-30은 --fix 비대상) 분기 파라미터만 늘고 --fix 안전 경계가 흐려진다.
CHG_PTR_RX = re.compile(r"(90_archive/[^\s`()]+changes\.md)")
# origin/confidence 필수 타입 화이트리스트 (wiki-schema.md §3 — source-stub/question/인프라 타입 제외)
ORIGIN_REQUIRED_TYPES = {"feature", "project", "entity", "concept", "guide"}
# category 통제 어휘 (wiki-schema §3 — 오타(Personal 등)는 sub-index 분할 라우팅·경로 규약을 어긋나게 함)
CATEGORY_VOCAB = {"personal", "work"}
# updated 필수 타입 (§7-9 — 필드가 없으면 신선도(§7-3)·미래날짜 검사가 조용히 건너뛰어져 추적 사각.
#  source-stub은 불변 스텁이라 ingested를 쓰므로 제외)
UPDATED_REQUIRED_TYPES = ORIGIN_REQUIRED_TYPES | {"question", "decision-log", "convention"}
# log.md는 문자 수 예산(줄 수 아님 — 한 항목이 길면 줄 수가 실제 분량을 못 담음, wiki-schema §4·§8)
SPECIAL_BUDGET = {"log.md": 6000}
# 타입별 **더 낮은 목표치** — 처방을 어디까지 수행하고 멈추는가(§7-2 종료 조건의 마지막 문장:
#  "타입이 더 낮은 목표치를 따로 정하면 그쪽이 우선한다"). log.md만 §8이 3000자를 명시한다.
#  나머지 타입은 목표치가 따로 없어 §7-2 종료 조건(발동이 풀릴 때까지)이 그대로 적용된다.
BUDGET_ROLLOVER_TARGET = {"log.md": 3000}
# project 허브 `## 최근 주요 변경` 유지 개수(§2.2·§8 — 3~5개 유지, 6번째가 생기면 롤오버).
#  **문자 예산과 무관한 별개 트리거**다(§7-2 「별개 트리거」ⓑ) — budget_state를 타지 않는다.
HUB_CHANGES_KEEP = 5
# 신선도·고아·타입 검사에서 제외하는 인프라 타입 (위키 본문 페이지가 아님)
INFRA_TYPES = {"index", "log", "dashboard", "schema"}
# 신선도: 90일 아카이브 후보에서 제외하는 타입 (wiki-schema.md §8 예외 2)
ARCHIVE_EXEMPT_TYPES = {"feature", "guide"}
# 신선도: 시간 기반 처리 **전체**(60일 confidence 하락 + 90일 아카이브 후보)에서 면제하는 타입
#  (§7-3 · §8 「아카이브」 예외 목록). ARCHIVE_EXEMPT_TYPES와 갈리는 지점: 그 집합은 90일 분기에서만
#  걸러 60일 분기로 떨어지는데, 아래 셋은 confidence 필드 자체가 없어 '60일+ confidence 하락 후보'
#  라벨이 성립하지 않는다 — 그래서 90일만이 아니라 전체를 면제한다.
#  (§ 번호가 아니라 절 제목으로 인용하는 이유: 예외 항목이 늘면 번호가 밀려 주석만 낡는다.)
#    decision-log: 결정 이력은 미편집이 정상 (§2.8)
#    question:     resolved question은 동결된 이력 기록이라 편집이 정상적으로 멈추고(lint-* 리포트 포함),
#                  open question은 §7-12 집계가 이미 추적한다 (§2.7 — priority를 쓰고 confidence가 없다)
#    convention:   작업 규약은 오래돼도 유효하므로 미편집이 정상 (§2.9)
FRESHNESS_EXEMPT_TYPES = {"decision-log", "question", "convention"}
# §7-28 본문 릴리즈 마커 검사에서 제외하는 타입 — 재작성 대상이 아닌 동결 기록이라 WARN이
#  수리 불가능한 소음이 된다(decision-log는 항목 불변 이력, question은 발견 원문 인용 보존).
#  convention은 미편입 — 규약은 갱신이 정상이라 동결 기록이 아니다(§5 changelog 미러링 금지가 그대로 적용).
RELEASE_MARKER_EXEMPT_TYPES = {"decision-log", "question"}
# §7-29 장식 이모지 검사에서 제외하는 타입 — decision-log는 §2.8 「항목 불변」이라 항목에 이모지가
#  섞여 들어오면 **고칠 수 없는 WARN**이 영구히 남는다(규약이 수정을 금지한 파일에 수리를 요구하는 모순).
#  RELEASE_MARKER_EXEMPT_TYPES와 값을 공유하지 않고 따로 두는 이유는 제외 근거가 다르기 때문이다 —
#  그쪽은 "동결 기록이라 재작성 대상이 아님"이고 여기는 "규약상 수정이 금지됨"이라, 한쪽 제외를
#  바꿀 때 다른 쪽이 조용히 따라 바뀌면 안 된다(ARCHIVE_EXEMPT_TYPES를 별도로 둔 것과 같은 이유).
#  question을 넣지 않은 이유: 항목 불변 규정이 없어 본문 편집이 가능하고, 인용 원문의 이모지는
#  대개 코드펜스 안이라 strip_code가 이미 걷어낸다.
EMOJI_EXEMPT_TYPES = {"decision-log"}
# index.md 분할 신호 임계 (wiki-schema.md §4 — index.md 초과는 B/F 세션이 2단계 파일 분할을 자동 수행,
#   sub-index(순번 파일) 초과는 순번 파일(index-{cat}-{n}.md)로 자동 분할)
INDEX_BODY_LINES = 400   # index.md 전체 줄 수(frontmatter 포함)
INDEX_FEAT_ROWS = 200    # '## 기능별 인덱스' 표의 feature/recipe 행 수

# 인덱스 등록 검사 대상(§7-30 ⓒ) — feature는 종전대로 §7-6이 따로 보므로 여기서 제외한다.
#  이 세 타입은 등록처가 서로 다른데(guide→index-guides / entity→기술 스택 지식 / concept→범용 패턴)
#  **어느 곳에도 안 실리면 조회 경로 밖**이 된다는 점은 같다. convention·question은 대상이 아니다 —
#  전자는 §7-30 ⓑ가 허브 목록으로, 후자는 §7-23이 미해결 질문 표로 각각 도달성을 이미 본다.
INDEXED_TYPES = {"guide", "entity", "concept"}

# 시크릿 의심 패턴 (wiki-schema §7-22 — 키워드+구분자+실값 형태만 매칭하는 보수 정규식.
#  post-write-checks.ps1의 민감정보 검사를 위키용으로 이식하되, IP 주소는 산문 오탐 위험으로 제외).
#  password/api key 계열은 값을 캡처해 아래 secret_value_is_codey()로 "코드 꼴" 값을 걸러낸다.
SECRET_PATTERNS = [
    ("password", re.compile(r"(?i)\b(password|passwd|pwd)\s*[:=]\s*['\"]?([^\s'\";,]{8,})")),
    # api key/token: 라벨 앞 경계를 \b 대신 (?<![A-Za-z0-9])로 — \b는 선행 '_'(단어문자)에서 깨져
    #   'aws_secret_access_key = ...'의 access_key/secret을 놓쳤다(T5 (d)). '_'는 [A-Za-z0-9]가 아니므로 매치.
    ("api key/token", re.compile(r"(?i)(?<![A-Za-z0-9])(api[_-]?key|apikey|secret|access[_-]?key|auth[_-]?token)\s*[:=]\s*['\"]?([A-Za-z0-9_\-./+]{12,})")),
    # 한글 라벨 크리덴셜(T5 (b)) — 위키 본문은 한글이 원칙이라 한글 라벨이 자연스럽다. 값은 ASCII 토큰꼴(8자+)만
    #   캡처해 한글 산문 값(예: '비밀번호: 사용자설정')은 매치하지 않는다. 값은 아래 codey 필터도 거친다.
    ("한글 라벨", re.compile(r"(비밀번호|비번|암호|토큰|시크릿|접근키|인증키|비밀키)\s*[:=]\s*['\"]?([A-Za-z0-9_\-./+]{8,})")),
    # 라벨 없는 생 토큰(T5 (c)) — 알려진 접두사(sk_live_·ghp_·AKIA·AIza·xox·JWT eyJ)는 라벨 없이 산문에 있어도
    #   실값이다. 접두사 뒤 충분한 본문 길이를 요구해 접두사 언급(예: 'ghp_ 형식')만으로는 오탐하지 않는다.
    ("토큰 접두사", re.compile(r"(?<![A-Za-z0-9])((sk_(live|test)_|ghp_|gho_|AKIA|AIza)[A-Za-z0-9_\-]{16,}|xox[bap]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{6,})")),
    ("bearer 토큰", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._\-]{20,}")),
    ("DB 연결문자열", re.compile(r"(?i)(server|data source|host)\s*=\s*[^;\n]+;.*(password|pwd)\s*=\s*[^;\n]{4,}")),
    ("개인키 블록", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("URI 자격증명", re.compile(r"(?i)\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^@\s]{4,}@")),
]
# 값 post-filter를 적용하는 라벨 (변수 대입·함수 호출 등 "코드 꼴" 값 제외 대상)
SECRET_VALUE_FILTER_LABELS = {"password", "api key/token", "한글 라벨"}
# 플레이스홀더/예시 값 오탐 제외 — 해당 줄에 이 표식이 있으면 시크릿이 아니라 규약 안내로 본다.
#  'example'은 단어 그대로일 때만(example.com 같은 도메인은 제외 표식 아님 — 위음성 방지).
SECRET_PLACEHOLDER_RX = re.compile(
    r"(YOUR_|<[^>]+>|\{[^}]+\}|\$env:|\$\{|%[A-Za-z_]+%|예\s*[:)]|환경변수|placeholder|example(?![.\w])|localhost|127\.0\.0\.1|\*\*\*|xxxx)",
    re.I)
# 알려진 시크릿 접두사 — 이 꼴이면 코드 꼴 판정과 무관하게 항상 실값 취급 (JWT eyJ 포함)
SECRET_KEY_PREFIX_RX = re.compile(r"^(sk_(live|test)_|ghp_|gho_|xox[bap]-|AKIA|AIza|eyJ)")
# 숫자·특수문자 없는 순수 식별자/프로퍼티 체인 꼴 (예: somePassword, input.password;)
SECRET_IDENTIFIER_LIKE_RX = re.compile(r"^[A-Za-z_][A-Za-z_.;,\[\]]*$")


def secret_value_is_codey(val):
    """§7-22 값 post-filter: 캡처된 값이 코드 스니펫의 변수·함수 호출 꼴(실값 아님)인지 판정.
    보수 정책 — 위양성(코드 오탐) 억제를 위음성보다 우선한다(plan T7 Edge Case).
    함수 호출(괄호 포함)·숫자 없는 순수 식별자/체이닝은 코드 꼴로 보고 제외하되,
    알려진 시크릿 접두사(sk_live_ 등)는 항상 실값으로 취급한다."""
    v = val.strip().strip("'\"")
    if SECRET_KEY_PREFIX_RX.match(v):
        return False
    if "(" in v or ")" in v:
        return True   # 함수 호출 꼴 — 코드(엔트로피 판정보다 먼저 걸러 정상 코드 오탐 방지)
    # 숫자·기호(-·/ 등)를 포함하는 값은 SECRET_IDENTIFIER_LIKE_RX(영문·_·.·;·,·[]만 허용)에 매치되지 않아
    #   여기서 '실값'(비-codey)으로 떨어진다 — 예: Xk29fj3kd82jf, wJalr...K7... (엔트로피 별도 분기 불필요).
    if SECRET_IDENTIFIER_LIKE_RX.match(v):
        # 식별자 꼴(영문·_·.…)이면 코드 참조로 보고 codey 처리. 단 **대소문자 변화·구분자가 전혀 없는
        #   단일 소문자 블록 20자+**는 변수·상수명보다 패스프레이즈(correcthorsebatterystaple 등)에 가까워
        #   실값으로 본다(T5 (a)). camelCase(대소 혼합)·dotted·snake·대문자 상수는 이 조건에서 빠져 codey 유지
        #   — 긴 식별자(getUserConfigurationFromEnvironment 등) 위양성을 막는다.
        if re.fullmatch(r"[a-z]{20,}", v):
            return False
        return True
    return False


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    fm = {}
    if m:
        for line in m.group(1).splitlines():
            mm = re.match(r"\s*([A-Za-z_]+)\s*:\s*(.*)", line)
            if mm:
                fm[mm.group(1)] = mm.group(2).strip().strip('"')
    return fm


def parse_date(s):
    try:
        return datetime.date.fromisoformat(s)
    except Exception:
        return None


def strip_code(text):
    """wikilink 오탐 방지용: 코드펜스(```...```)·인라인코드(`...`)를 같은 길이 공백으로 치환한 사본 반환.
    코드 스니펫 안 정규식(예: `![](...)`·`[[..]]`)이 wikilink로 오인되는 것을 막는다.
    줄바꿈은 보존해 다른 줄 단위 검사(예산 등)와 줄 수가 어긋나지 않게 한다(이 사본은 wikilink 추출 전용)."""
    blank = lambda m: re.sub(r"[^\n]", " ", m.group(0))  # 줄바꿈만 남기고 공백화
    text = re.sub(r"```.*?```", blank, text, flags=re.S)   # 펜스 블록
    # 미닫힘 펜스 → 끝까지 코드 간주(보수적). `.`(re.S로 줄바꿈 포함)로 EOF까지 공백화한다 —
    #   기존 `[^\n]*`는 줄바꿈을 못 넘어 파일 중간의 '여러 줄' 미닫힘 펜스를 공백화하지 못했다(T6).
    text = re.sub(r"```.*\Z", blank, text, flags=re.S)
    text = re.sub(r"`[^`\n]*`", blank, text)                # 인라인 코드
    return text


def fenced_interior_chars(text):
    """guide 예산 판정용: 백틱 코드 펜스(```)의 '내부' 문자 수를 센다(여닫는 구분자 줄은 판정에서 제외).
    platform-bootstrap·ui-ux 가이드는 분할 불가능한 페이로드(샘플 템플릿·예제)가 펜스에 실리므로
    예산(산문 비대 억제)에서 펜스 내부를 제외한다 — recipe는 스니펫이 본체(예산이 펜스 포함 보정값)라
    비적용(wiki-schema §2.6·§4·§7-2).
    여닫이가 안 맞으면(미종결 펜스) 0을 반환해 전체 문자 수로 판정한다(비대 은폐 방지 — 보수 폴백).
    문자 수 계산은 각 내부 줄의 길이 + 줄바꿈 1자로 하되(전체 len(text)와 같은 기준), 여닫는 구분자 줄은
    제외해 전체 문자 수에서 빼면 산문분만 남는다(v1.138.0 줄 수→문자 수 전환).
    한계: 4-backtick 중첩 펜스는 단순 토글이라 오계상 가능, ~~~ 물결 펜스는 비지원(vault 관례는 백틱뿐)."""
    interior = 0
    in_fence = False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            interior += len(line)
    return 0 if in_fence else interior


def section(text, heading):
    """본문에서 '## {heading}' 섹션(헤딩 줄부터 다음 '## ' 헤딩 또는 문서 끝까지)을 반환, 없으면 None.
    기능별 인덱스(§7-6·14)·레포 정보(§7-20)·아카이브 인덱스(§7-19)·미해결 질문(§7-23) 공용 —
    섹션 경계 규칙(다음 ## 또는 \\Z)이 검사마다 어긋나지 않게 한 곳에서 유지한다."""
    m = re.search(r"^##\s*" + re.escape(heading) + r"\b.*?(?=^##\s|\Z)",
                  text, re.M | re.S)
    return m.group(0) if m else None


def without_section(text, heading):
    """'## {heading}' 섹션(헤딩~다음 '## ' 또는 \\Z)을 제거한 사본. section()의 역(逆).
    증상별 인덱스(§6)는 행 형상이 기능별 인덱스와 겹치지만(첫 컬럼 평문 + feat/recipe 링크,
    is_feat_recipe_row가 True) 의미가 달라(첫 컬럼이 '증상' 관찰 표현) 한/영 병기(§7-16)·등록
    (§7-6) 검사 대상이 아니다 — 스캔 텍스트에서 이 섹션을 뺀다. §7-14 행수는 section('기능별
    인덱스')로 이미 스코프돼 영향 없고, 행 wikilink의 깨진 링크는 §7-1이 전 페이지에서 잡는다."""
    return re.sub(r"^##\s*" + re.escape(heading) + r"\b.*?(?=^##\s|\Z)", "",
                  text, flags=re.M | re.S)


def wikilink_targets(text):
    """코드펜스/인라인코드를 제외(strip_code)한 텍스트에서 wikilink 대상([[대상|표시]]의 대상)을
    정규화(이스케이프 백슬래시 제거·#앵커 제거·트림)해 순서대로 반환. 빈 대상은 제외.
    깨진 링크(§7-1)·기능별 인덱스 동기(§7-6)·미해결 질문 동기(§7-23) 공용 —
    정규화 규칙이 검사마다 어긋나 서로 모순된 판정을 내는 것을 막는다."""
    out = []
    for m in re.findall(r"\[\[([^\]|]+)", strip_code(text)):
        t = m.replace("\\", "").split("#")[0].strip()
        if t:
            out.append(t)
    return out


def question_is_resolved(fm):
    """question 닫힘 판정(§7-12·§7-23 공용): `status: resolved` 또는 `resolved:` 필드(날짜)
    어느 쪽이든 닫힌 것으로 본다(SKILL B-2 3-1 이중 표기 허용 — §7-17 deprecated 판정과 동일 원칙)."""
    return fm.get("status") == "resolved" or bool(fm.get("resolved"))


def is_lint_report(rel_path):
    """lint-YYYYMMDD 리포트 페이지 판정: type: question을 쓰지만 '질문'이 아니라 lint 결과 보존물 —
    §7-12 미해결 집계와 §7-23 인덱스 등록 요구에서 같은 기준으로 제외한다(집계↔등록 모순 방지)."""
    return os.path.basename(rel_path).startswith("lint-")


def budget_split_suppressed(fm, chars):
    """「분리 불가 판정」이 유효해 임박 WARN을 억제해야 하는지 판정한다(§7-2·§4).
    유효 조건은 둘이다 — ① budget_split이 통제 어휘 안(none) ② 현재 문자 수가 판정 시점
    (budget_split_chars) 대비 BUDGET_REJUDGE_MARGIN 이내. 판정 시점보다 그만큼 자랐으면 판정의
    전제(더 나눌 것이 없다)가 흔들린 것이므로 억제를 풀어 재판정을 강제한다.
    budget_split_chars가 없거나 정수가 아니면 억제하지 않는다 — 판정 시점을 알 수 없으면 재판정
    시점도 정할 수 없어 영구 면제가 되기 때문이다(신호를 살리는 쪽으로 폴백).
    억제는 임박에만 적용되고 초과 WARN은 그대로 난다. 억제된 임박은 침묵하지 않고
    「분리 불가 판정 유지」 INFO로 강등된다 — 상태가 계속 보여야 재판정 시점을 놓치지 않는다."""
    if str(fm.get("budget_split", "")).strip() not in BUDGET_SPLIT_VOCAB:
        return False
    try:
        judged = int(str(fm.get("budget_split_chars", "")).strip())
    except (TypeError, ValueError):
        return False
    return judged > 0 and chars <= judged * (1 + BUDGET_REJUDGE_MARGIN)


BudgetState = collections.namedtuple(
    "BudgetState",
    "typ budget chars eff_chars fence_note over near critical suppressed target stage")


def budget_state(rel_path, fm, text):
    """§7-2 예산 조건을 **한 곳에서** 계산해 BudgetState로 돌려준다. 대상이 아니면 None.

    이 함수가 유일 구현인 이유: 2026-08-17 결정(예산 트리거 §7-2 단일 정의화)이 **산문에서**
    이룬 것을 코드에서도 유지한다. 종전에는 같은 판정이 메인 루프의 SPECIAL_BUDGET 분기와
    일반 분기에 각각 인라인돼 있었고, 여기에 `--auto-split`이 자기 판정을 또 두면 세 벌이 된다.
    조건이 복제되면 한 자리만 고쳐지는 드리프트가 생기는데, 그 드리프트는 개별 지점을 고치는
    방식으로 6라운드를 돌아도 수렴하지 않았다(v1.177 실측).

    필드 의미:
      over/near/critical -- §7-2 발동 판정의 세 축. near는 선행 게이트(자체 신호 없음),
        critical이 실제 발동이다(억제 전 값 -- suppressed와 함께 읽는다).
      suppressed -- 「분리 불가 판정」(budget_split)이 유효해 신호가 강등되는 상태.
        **`--auto-split`은 이 페이지를 건드리지 않는다** -- 규정이 「더 나눌 것이 없다」고
        판정한 것을 코드가 강제로 쪼개면 그 판정 자체가 무의미해진다.
      target -- 처방을 어디까지 수행하고 멈추는가. 타입별 더 낮은 목표치가 있으면 그 값,
        없으면 None(그 경우 종료 기준은 「발동이 풀릴 때까지」이지 「예산 이내」가 아니다).
      stage -- 다단 처방의 진입 단계. convention은 ①(무효 항목 제거)이 「무엇이 무효인가」를
        묻는 판단이라 자동 경로가 수행할 수 없어 **2부터 시작**한다(하위 분리). ①을 건너뛰어도
        손실이 없다 -- 제거 대신 분리하면 내용이 남을 뿐이다. 나머지 타입은 단계가 하나다."""
    chars = len(text)
    if rel_path in SPECIAL_BUDGET:
        budget, typ, eff_chars, fence_note = SPECIAL_BUDGET[rel_path], "log", chars, ""
    else:
        typ = fm.get("type", "")
        eff_chars, fence_note = chars, ""
        if typ == "guide":
            gk = fm.get("guide_kind", "")
            budget = GUIDE_BUDGET.get(gk, 9000)
            # platform-bootstrap·ui-ux는 펜스 내부를 뺀 유효 문자 수로 잰다(§2.6 예산 판정 방식).
            if gk in ("platform-bootstrap", "ui-ux"):
                fenced = fenced_interior_chars(text)
                if fenced:
                    eff_chars = chars - fenced
                    fence_note = f", 코드 펜스 {fenced}자 제외"
        elif typ in BUDGET:
            budget = BUDGET[typ]
        else:
            return None
    if not budget:
        return None
    near = eff_chars >= budget * BUDGET_NEAR_RATIO
    critical = near and (eff_chars >= budget * BUDGET_CRITICAL_RATIO
                         or budget - eff_chars < BUDGET_CRITICAL_SLACK)
    return BudgetState(
        typ=typ, budget=budget, chars=chars, eff_chars=eff_chars, fence_note=fence_note,
        over=eff_chars > budget, near=near, critical=critical,
        suppressed=budget_split_suppressed(fm, eff_chars),
        target=BUDGET_ROLLOVER_TARGET.get(rel_path),
        stage=2 if typ == "convention" else 1)


def budget_resolved(state):
    """처방을 더 수행할 필요가 없는 상태인가(§7-2 종료 조건).

    **「예산 이내」가 종료 기준이 아니다** -- 한 항목·한 절만 옮겨 문턱 바로 아래로 내려오면
    다음 추가로 곧 재발화하므로, 발동이 풀릴 때까지 오래된 것부터 반복한다. 타입이 더 낮은
    목표치를 따로 정했으면(log.md 3000자) 그쪽이 우선한다."""
    if state.target is not None:
        return state.eff_chars <= state.target
    return not (state.over or state.critical)


def feat_row_name(line):
    """기능별 인덱스 유형 행이면 **첫 컬럼의 표시 이름**을, 아니면 None을 돌려준다
    (§7-14 행수·§7-16 병기 공용 — 이중 구현 방지. 판정과 이름 추출을 한 함수에 두는 이유는
    §7-16이 따로 `split("|")[1]`을 쓰면 아래 옛 형상의 `\\|` 이스케이프에서 이름이 잘리기 때문).
    형상+대상 기반이라 상세 컬럼 alias 표기(`\\|feature]]` 권장 관례, schema §3)에 의존하지 않는다:
    ① `|`로 시작 ② 첫 컬럼이 비어 있지 않은 **평문**(통합 표 — 현행) **또는 `40_guides/` wikilink**
    (옛 `## 가이드 / 레시피` 섹션 형상 — 단 `40_guides/recipes/`는 이중 요구 방지로 제외, 아래 참조).
    프로젝트/기술 표처럼 첫 컬럼이 `20_projects/`·`30_knowledge/` 링크인 행은 종전대로 제외된다.
    `\\|` 이스케이프로 split이 경로만 잡는 오탐은 아래 재추출로 차단.
    ③ 행 내 wikilink 대상(정규화: 이스케이프 `\\`·`#`앵커 제거 — wikilink_targets와 동일 규칙)의
    basename이 `feat-` 시작(단축 링크 포함)이거나 대상에 `40_guides/` 포함.

    ③의 대상을 `40_guides/recipes/`가 아니라 `40_guides/` 전체로 두는 이유: 가이드·레시피가
    통합 표 하나로 합쳐지면서(`_rows_guides`) platform-bootstrap·ui-ux 행도 첫 컬럼이 평문이 됐다.
    좁은 조건을 두면 그 행들은 **형상은 맞는데 대상 조건에서 탈락**해 §7-16 병기 검사를 통째로
    비껴간다 -- 종전에 그 사각을 메우던 「가이드 섹션 전용 병기 검사」는 통합 표로 대체돼
    폐지하고 이 검사에 흡수했다.

    ②가 wikilink 첫 컬럼을 함께 받는 이유: **생성 마커가 없는 vault는 `## 가이드 / 레시피` 섹션을
    그대로 유지**하고(wiki-schema §4의 마커 없는 vault 분기) 그 행은 첫 컬럼이 wikilink다. 평문만
    받으면 그 vault의 guide 행은 폐지된 전용 검사에도 이 검사에도 걸리지 않아 **병기 무신호 구간**이
    생긴다 -- 폐지가 만든 공백이라 하위호환 형상을 여기서 함께 받는다."""
    s = line.lstrip()
    if not s.startswith("|"):
        return None
    parts = s.split("|")
    if len(parts) < 2:
        return None
    first = parts[1].strip()
    if "[[" in first:
        # 옛 형상: 첫 컬럼이 통째로 wikilink라 `\|` 이스케이프에서 split이 잘린다 -- 원문에서 재추출.
        m = re.match(r"\|\s*\[\[([^\]]+)\]\]", s)
        if not m:
            return None
        inner = m.group(1)
        target, _, alias = inner.partition("\\|")
        if not alias:
            target, _, alias = inner.partition("|")
        target = target.replace("\\", "").split("#")[0].strip()
        if "40_guides/" not in target:
            return None
        if "40_guides/recipes/" in target:
            # 폐지된 §7-27이 recipe를 명시 제외했던 이유를 승계한다(규정 정본: wiki-schema §3
            #  「하위호환 형상」 ①) -- 마커 없는 vault에서 recipe는 `## 기능별 인덱스`(첫 컬럼 평문)와
            #  `## 가이드 / 레시피`(첫 컬럼 wikilink) **두 곳**에 실리므로, 여기서 받으면 같은
            #  페이지에 병기 WARN이 두 번 난다(이중 요구). 평문 쪽 행이 이미 대상이라 커버는 유지된다.
            return None
        # ⚠ 하위호환 수용은 **full path 형상 한정**이다(wiki-schema §3 「하위호환 형상」 ②) --
        #  단축 wikilink(`[[help-style|...]]`)는 대상이 `40_guides/`를 담지 않아 여기서도 조건 ③에서도
        #  탈락한다. 폐지된 §7-27은 섹션 스코프라 경로를 보지 않고 잡았으므로 그만큼 커버가 좁다.
        #  닫으려면 링크 대상을 페이지 집합에 해소해야 하는데(이 함수는 행 문자열만 받는다) 실 vault
        #  가이드 행은 전부 full path라 실사용 근거 없이 구조를 바꾸지 않는다.
        #  실측(재현 가능): vault에서 `git show 53d036e^:index.md`의 `## 가이드 / 레시피` 섹션 링크 행
        #  **111행 중 첫 컬럼 full path 111 / 단축 0**.
        name = alias.strip() or target.split("/")[-1]
    else:
        if not first:
            return None
        name = first
    for m in re.findall(r"\[\[([^\]|]+)", s):
        t = m.replace("\\", "").split("#")[0].strip()
        if t.split("/")[-1].startswith("feat-") or "40_guides/" in t:
            return name
    return None


def is_feat_recipe_row(line):
    """기능별 인덱스 유형 행 여부(판정 본체는 feat_row_name — 이중 구현 방지)."""
    return feat_row_name(line) is not None


def feature_index_rows(text):
    """index.md '## 기능별 인덱스' 섹션의 feature/recipe 표 행 수(분할 신호 측정용, §7-14).
    행 판정은 is_feat_recipe_row 공용 — alias 무관(비표준 alias 행도 정확히 센다)."""
    sec = section(text, "기능별 인덱스")
    if not sec:
        return 0
    return sum(1 for line in sec.splitlines() if is_feat_recipe_row(line))


def git_commits_behind(repo_root, sha):
    """repo_root의 HEAD가 sha 이후로 몇 커밋 쌓였는지 반환(§7-26). 계산 불가면 None.

    fail-open이 이 함수의 계약이다 — git 미설치·비 git 레포·sha 소실(rebase·force push)·
    타임아웃·예외를 전부 None으로 흡수한다. lint은 읽기 전용 진단 도구라, 환경 차이로
    실패해 vault 점검 전체를 막으면 안 된다(§7-20의 "레포 접근 가능 시"와 동일 원칙).
    코드 내용은 읽지 않고 커밋 '수'만 센다(§7 결과 처리의 레포 접근 범위)."""
    try:
        proc = subprocess.run(
            ["git", "-C", repo_root, "rev-list", "--count", f"{sha}..HEAD"],
            capture_output=True, text=True, timeout=10,
            stdin=subprocess.DEVNULL,  # 자격증명·에디터 프롬프트로 매달리지 않게 입력을 닫는다
        )
    except (OSError, subprocess.SubprocessError):
        return None  # git 미설치·실행 실패·타임아웃
    if proc.returncode != 0:
        return None  # sha가 이력에 없음(rebase·force push) 등
    out = proc.stdout.strip()
    return int(out) if out.isdigit() else None


def repo_root_for_hub(hub_text):
    """project 허브 '## 레포 정보' 섹션의 '- **경로**: `...`' 백틱 값을 레포 루트로 반환(§7-20용).
    섹션/경로 줄이 없거나 그 디렉터리가 실재하지 않으면(다른 PC 등) None — 레포 접근 불가로 간주."""
    sec = section(hub_text, "레포 정보")
    if not sec:
        return None
    m = re.search(r"\*\*경로\*\*\s*:\s*`([^`\n]+)`", sec)
    if not m:
        return None
    root = os.path.expanduser(m.group(1).strip())
    return root if os.path.isdir(root) else None


def cleanup_backups(vault, today):
    """§8 백업 정리 — `--fix`가 새 백업을 만들기 **전에** 1회 호출된다. 두 규칙을 함께 집행한다:
      ① **접미사 없는 `{YYYY-MM-DD}/` 중 오늘이 아닌 것 제거** — git vault는 사전 백업이 면제인데
         `--fix` 자동 백업만 쌓이는 것을 막는다. 제거 시점을 「세션 종료」가 아니라 「다음 --fix 시작」으로
         두는 이유: 미커밋 상태로 세션이 끝나면 git 복구(checkout은 미커밋을 못 되돌린다)와 백업이
         동시에 없어져 복구 수단이 0이 된다. 한 세션분을 남기면 복구 창이 유지되고 누적은 1개로 상한된다.
      ② **`{YYYY-MM-DD}-presplit/` 중 BACKUP_KEEP_DAYS 경과분 제거** — 원본이 vault에 그대로 있는
         수정 백업 성격이라 30일 정리 대상이다(§8 — `-deleted`·`-pre-restore` 같은 보존 특례가 없다).
    **`-deleted`(삭제 백업 = 유일 사본)와 `-pre-restore`(복구 재백업)는 어느 규칙에도 걸리지 않는다** —
    지우면 복구가 영구 불가해진다. 날짜로 읽히지 않는 이름(사람이 만든 임의 폴더)도 건드리지 않는다.
    반환: `(제거 목록, 실패 목록)` — 둘 다 호출부가 `--fix` 헤더 **아래**에서 [CLEANUP]·[CLEANUP-FAIL]로
    보고한다(여기서 바로 print하면 그 줄만 헤더 밖으로 나가 [FIXED]/[FIX-FAIL]과 형식이 어긋난다)."""
    root = os.path.join(vault, "90_archive", "backup")
    if not os.path.isdir(root):
        return [], []
    removed, failed = [], []
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name)
        if not os.path.isdir(path):
            continue
        m = re.match(r"^(\d{4}-\d{2}-\d{2})(-.+)?$", name)
        if not m:
            continue
        day = parse_date(m.group(1))
        if day is None:   # 2026-13-45 같은 형식만 맞는 이름 — 판정 불가라 건드리지 않는다
            continue
        suffix = m.group(2) or ""
        if suffix == "":
            if day == today:
                continue
            reason = "이전 날짜 — 누적 금지"
        elif suffix == "-presplit":
            if (today - day).days <= BACKUP_KEEP_DAYS:
                continue
            reason = f"{BACKUP_KEEP_DAYS}일 경과"
        else:
            continue   # -deleted·-pre-restore 등 보존 특례
        try:
            shutil.rmtree(path)
            removed.append(f"{name} ({reason})")
        except OSError as e:
            # 항목별 실패 격리 — apply_fixes의 [FIX-FAIL]과 같은 규약(그 폴더만 건너뛰고 계속).
            failed.append(f"{name} 제거 실패({type(e).__name__}) — 건너뜀")
    return removed, failed


# --- 인덱스 생성 (--build-index) ------------------------------------------
# index.md는 손으로 유지하기에는 원천이 너무 흩어져 있다(수백 페이지의 frontmatter). 생성 마커
# 사이만 파생으로 채우고 밖은 손대지 않는다 -- 증상별 인덱스·참조처럼 판단이 들어가는 섹션은
# 사람이 쓰는 자리로 남긴다(wiki-schema §6 「생성 마커」).
AUTO_INDEX_BEGIN = "<!-- AUTO-INDEX:BEGIN -->"
AUTO_INDEX_END = "<!-- AUTO-INDEX:END -->"


def _fm_list(fm, key):
    """frontmatter의 `[a, b]` 또는 `a, b` 형식 값을 리스트로. 없으면 빈 리스트."""
    raw = fm.get(key, "").strip()
    if not raw:
        return []
    raw = raw.strip("[]")
    return [x.strip().strip('"').strip("'") for x in raw.split(",") if x.strip()]


def scan_index_pages(vault):
    """인덱스 생성용 최소 스캔 -- 검사는 돌리지 않고 frontmatter와 본문만 모은다.
    `90_archive/`·루트 큐 파일·인덱스 자신은 생성 대상이 아니라 제외한다."""
    pages = {}
    for p in glob.glob(os.path.join(glob.escape(vault), "**", "*.md"), recursive=True):
        r = os.path.relpath(p, vault).replace("\\", "/")
        if r.startswith("90_archive/") or r in ROOT_QUEUE_FILES or r.startswith("index"):
            continue
        try:
            with open(p, "rb") as fh:
                text = fh.read().decode("utf-8-sig")
        except (UnicodeDecodeError, OSError):
            continue   # 읽기 실패는 lint 본 검사가 ERR로 보고한다 -- 생성은 그 파일만 건너뛴다
        # 정규화를 frontmatter 파싱 **전에** 한다 -- frontmatter()의 `^---` 매치가 CRLF 파일에서
        #  실패해 전 섹션이 빈 인덱스로 생성되는 것을 막는다(본 검사 루프와 같은 순서).
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        pages[r] = (frontmatter(text), text)
    return pages


def display_label(fm, text, fallback_field):
    """표시 라벨 -> (라벨, 미역이관 여부). `index_label`이 1차 원천이고, 없으면 타입별 폴백
    원천(feature_name·entity_name 등) 또는 H1을 쓴다. 폴백값은 인덱스 표기 규약(한/영 병기
    §7-16)을 만족하지 못할 수 있으므로 「미역이관」으로 표시해 구분한다 --
    파일명에서 라벨을 유도하지는 않는다(추측 금지)."""
    lbl = fm.get("index_label", "").strip()
    if lbl:
        return lbl, False
    fb = fm.get(fallback_field, "").strip() if fallback_field else ""
    if not fb:
        m = re.search(r"^#\s+(.+)$", text, re.M)
        fb = m.group(1).strip() if m else ""
    return (fb or "(라벨 미정)"), True


def _rows_projects(pages, category):
    rows, pend = [], []
    for r in sorted(pages):
        fm, text = pages[r]
        if fm.get("type") != "project" or fm.get("category") != category:
            continue
        lbl, todo = display_label(fm, text, "project")
        if todo:
            pend.append(r)
        stack = ", ".join(_fm_list(fm, "tech_stack"))
        rows.append("| [[%s\\|%s]] | %s | %s | %s |"
                    % (r[:-3], lbl, fm.get("platform", "-"), stack or "-", fm.get("status", "-")))
    return rows, pend


def _rows_features(pages, category):
    """category(personal|work)에 속한 project feature 행.

    종전에는 `category=None`으로 recipe 행도 냈으나, 가이드·레시피가 통합 표로 옮겨가면서
    (`_rows_guides`) 그 호출부가 사라져 feature 전용이 됐다."""
    rows, pend = [], []
    for r in sorted(pages):
        fm, text = pages[r]
        if fm.get("type") != "feature" or fm.get("category") != category:
            continue
        lbl, todo = display_label(fm, text, "feature_name")
        if todo:
            pend.append(r)
        rows.append("| %s | %s | %s | [[%s\\|feature]] |"
                    % (lbl, fm.get("platform", "-"), fm.get("project", "-"), r[:-3]))
    return rows, pend

def _rows_guides(pages):
    """guide 전 종류(recipe·platform-bootstrap·ui-ux)를 담는 **통합 표** 행.

    종전에는 recipe가 두 곳에 실렸다 -- 본체 `## 기능별 인덱스`(첫 컬럼 평문 라벨)와
    `## 가이드 / 레시피`(첫 컬럼 wikilink). 실 vault에서 그 중복이 106행이었고, 두 표의 형상이
    달라 병기 검사도 첫 컬럼 평문용과 wikilink용으로 갈려 있었다(후자는 이 통합으로 폐지). 통합 표는 **첫 컬럼을 평문
    라벨로 두고 마지막을 wikilink로** 잡아 한 표에 합친다 -- 행이 사라지지 않으면서(합집합
    흡수) §7-16 하나가 전 행의 병기를 본다 -- 단 그것이 성립하려면 `is_feat_recipe_row`의
    대상 조건이 `40_guides/` 전체를 포괄해야 한다(그 함수 docstring 참조). 두 변경은 한 벌이며,
    조건을 넓히지 않은 채 표만 합치면 platform-bootstrap·ui-ux 행이 어느 검사에도 안 걸린다.

    컬럼: `| 이름(평문 한/영) | 종류(guide_kind) | 플랫폼 | 상세(wikilink) |`
      종전 기능별 인덱스의 `프로젝트` 컬럼은 recipe에서 항상 `(레시피)` 고정값이라 정보가 없었다 --
      그 자리를 `guide_kind`가 대신해 종류 구분이 살아난다."""
    rows, pend = [], []
    for r in sorted(pages):
        fm, text = pages[r]
        if fm.get("type") != "guide":
            continue
        lbl, todo = display_label(fm, text, None)
        if todo:
            pend.append(r)
        rows.append("| %s | %s | %s | [[%s\\|%s]] |"
                    % (lbl, fm.get("guide_kind", "-"), fm.get("platform", "-"),
                       r[:-3], fm.get("guide_kind", "guide")))
    return rows, pend


def _rows_knowledge(pages, typ, field, list_key):
    rows, pend = [], []
    for r in sorted(pages):
        fm, text = pages[r]
        if fm.get("type") != typ:
            continue
        lbl, todo = display_label(fm, text, field)
        if todo:
            pend.append(r)
        rows.append("| [[%s\\|%s]] | %s |"
                    % (r[:-3], lbl, ", ".join(_fm_list(fm, list_key)) or "-"))
    return rows, pend


def _rows_questions(pages):
    rows, pend = [], []
    for r in sorted(pages):
        fm, text = pages[r]
        if fm.get("type") != "question" or question_is_resolved(fm):
            continue
        lbl, todo = display_label(fm, text, None)
        if todo:
            pend.append(r)
        rows.append("| [[%s\\|%s]] | %s | %s |"
                    % (r[:-3], lbl, fm.get("status", "open"),
                       ", ".join(_fm_list(fm, "related")) or "-"))
    return rows, pend


def _table(header, sep, rows, empty_note):
    out = [header, sep]
    out.extend(rows if rows else ["<!-- %s -->" % empty_note])
    return out


def _chunk_rows(rows, limit):
    """행 목록을 limit 단위로 자른 리스트의 리스트. 행이 limit 이하면 통째로 한 덩어리다.

    **나누어떨어져도 빈 덩어리를 만들지 않는다** — 400행 / 200 임계면 파일 3개가 아니라
    2개다(빈 sub-index는 조회에 쓸모가 없고 §7-15 목록만 늘린다).
    덩어리 수에 상한이 없다 -- category 안에서 순번이 무제한으로 늘 뿐 계층은 깊어지지
    않으므로(§4 3단계), 지식이 몇 배가 되어도 조회 홉 1이 유지된다."""
    if len(rows) <= limit:
        return [rows]
    return [rows[i:i + limit] for i in range(0, len(rows), limit)]


def _stale_sub_indexes(vault, keep_names):
    """이번 생성 대상이 아닌 기존 `index-*.md` 경로 목록(생성물 정리 대상).

    삭제 조건을 **3중으로 좁힌다**: ① 파일명이 `index-*.md` ② frontmatter `type: index`
    ③ 이번 생성 대상(keep_names) 밖. 사용자가 만든 다른 파일을 지우지 않기 위함이며,
    읽을 수 없는 파일은 판정 불가이므로 **건드리지 않는다**(세 조건 중 ②를 확인할 수 없다)."""
    out = []
    for p in sorted(glob.glob(os.path.join(glob.escape(vault), "index-*.md"))):
        stem = os.path.basename(p)[:-3]
        if stem in keep_names:
            continue
        text, _bom, _nl = _read_page(p)
        if text is None:
            continue          # 읽기 실패 -- 타입을 확인할 수 없으면 삭제 대상으로 보지 않는다
        if frontmatter(text).get("type") == "index":
            out.append(p)
    return out


def _sub_index_text(name, rows):
    """sub-index 파일 본문. 생성물이므로 머리말에 그 사실을 적는다 --
    수기로 고쳐도 다음 `--build-index`가 덮어쓴다는 것을 파일 자신이 알려야 한다.

    헤딩은 세 파일 모두 `## 기능별 인덱스`로 통일한다 -- §7-14의 행수 측정
    (`feature_index_rows`)과 §7-16의 병기 검사가 그 헤딩을 기준으로 스코프를 잡으므로,
    guides만 다른 헤딩을 쓰면 그 파일의 행이 두 검사에서 통째로 빠진다."""
    if name == "index-guides":
        title = "가이드 / 레시피 인덱스"
        lead = ("[[index|위키 인덱스]]에서 분할된 가이드·레시피 인덱스"
                " (recipe·platform-bootstrap·ui-ux 전 종류를 한 표에 담는다)")
    else:
        title = ("개인" if name.endswith("personal") else "업무") + " 프로젝트 기능별 인덱스"
        lead = "[[index|위키 인덱스]]에서 분할된 기능별 인덱스 (wiki-schema §4 2단계)"
    return ("---\ntype: index\ntags: [index, navigation, %s]\n---\n\n"
            "# %s\n\n> %s. **이 파일은 `--build-index`가 생성한다 --"
            " 수기 편집은 다음 생성에서 사라진다.**\n\n"
            "## 기능별 인덱스\n\n%s\n") % (name, title, lead, "\n".join(rows))


def build_index(vault, dry_run):
    """`index.md`의 생성 마커 사이를 frontmatter에서 파생한 6섹션으로 채우고, category별
    sub-index를 함께 생성한다. 마커 밖은 한 글자도 바꾸지 않는다.
    반환: 종료 코드(0 정상 / 1 마커 없음·읽기·쓰기 실패)."""
    pages = scan_index_pages(vault)
    pending = []          # 라벨 미역이관 페이지 (index_label 부재)
    body, sub_files = [], {}

    for cat, title in (("personal", "개인 프로젝트"), ("work", "업무 프로젝트")):
        rows, pend = _rows_projects(pages, cat)
        pending += pend
        body.append("## " + title)
        body.append("")
        body += _table("| 프로젝트 | 플랫폼 | 기술 스택 | 상태 |",
                       "|----------|--------|-----------|------|", rows,
                       "아직 없음 -- %s project 페이지 0개" % cat)
        body.append("")

    # 기능별 인덱스: 본체에는 sub-index 목록만 두고 실제 행은 전부 sub-index로 낸다.
    #  project feature는 category별(§4 2단계)로, guide 전 종류는 index-guides로 간다 --
    #  본체가 얇아야 절차 K가 매 코드 세션에서 이 파일을 여는 비용이 낮다(실측 39,747자였다).
    sub_links = []

    def _emit_sub(base, label_fmt, rows, header, sep, empty_note):
        """행을 임계 단위로 잘라 sub-index 파일 1~N개를 낸다(§4 3단계 순번 분할).

        **라우팅은 `sorted(pages)` 정렬의 슬라이스**라 같은 vault면 같은 청크가 나온다
        (생성기는 매 실행 전체를 다시 만들므로 「append-only 증분」이라는 수기 절차 전제가
        여기서는 성립하지 않는다). 한 덩어리면 종전대로 무순번 이름을 쓴다 -- 임계에 닿지
        않은 vault의 파일명을 바꾸지 않기 위함이다(무회귀)."""
        chunks = _chunk_rows(rows, INDEX_FEAT_ROWS)
        for i, chunk in enumerate(chunks, start=1):
            name = base if len(chunks) == 1 else "%s-%d" % (base, i)
            suffix = "" if len(chunks) == 1 else " (%d/%d)" % (i, len(chunks))
            sub_links.append("[[%s|%s]]" % (name, label_fmt + suffix))
            sub_files[name] = _table(header, sep, chunk, empty_note)

    for cat, title in (("personal", "개인"), ("work", "업무")):
        rows, pend = _rows_features(pages, cat)
        pending += pend
        if not rows:
            continue
        _emit_sub("index-%s" % cat, "%s 프로젝트 기능별 인덱스" % title, rows,
                  "| 기능 | 플랫폼 | 프로젝트 | 상세 |",
                  "|------|--------|----------|------|", "없음")
    # 가이드·레시피 통합 표 -- 종전의 본체 recipe 행 + `## 가이드 / 레시피` 섹션을 한 표로 합친 것.
    #  두 섹션이 같은 recipe를 각각 실어 실 vault에서 106행이 중복이었다(_rows_guides docstring).
    guide_rows, pend = _rows_guides(pages)
    pending += pend
    if guide_rows:
        # 가이드도 같은 임계·같은 순번 규칙을 쓴다 — category가 없을 뿐 행 수가 많아지면
        #  조회 비용은 똑같이 오른다(§7-14가 sub-index 전체를 대상으로 재는 것과 정합).
        _emit_sub("index-guides", "가이드 / 레시피 인덱스", guide_rows,
                  "| 이름 | 종류 | 플랫폼 | 상세 |", "|------|------|--------|------|",
                  "가이드 없음")
    body.append("## 기능별 인덱스")
    body.append("")
    if sub_links:
        body.append("> **분할 인덱스**: 기능별 인덱스 행은 전부 sub-index에 있다 -- "
                    + " · ".join(sub_links) + ". 한/영 어느 쪽으로 grep해도 해당 sub-index "
                    "한 줄에서 잡히므로, 본체를 통째로 읽지 말고 관련 sub-index만 연다.")
    else:
        body += _table("| 기능 | 플랫폼 | 프로젝트 | 상세 |",
                       "|------|--------|----------|------|", [], "등재된 기능·가이드 없음")
    body.append("")

    rows, pend = _rows_knowledge(pages, "entity", "entity_name", "used_by")
    pending += pend
    body.append("## 기술 스택 지식 (tech/)")
    body.append("")
    body += _table("| 기술 | 사용 프로젝트 |", "|------|--------------|", rows, "entity 없음")
    body.append("")

    rows, pend = _rows_knowledge(pages, "concept", "concept_name", "related_projects")
    pending += pend
    body.append("## 범용 패턴 (patterns/)")
    body.append("")
    body += _table("| 패턴 | 관련 프로젝트 |", "|------|--------------|", rows, "concept 없음")
    body.append("")

    rows, pend = _rows_questions(pages)
    pending += pend
    body.append("## 미해결 질문")
    body.append("")
    body += _table("| 질문 | 상태 | 관련 |", "|------|------|------|", rows, "미해결 질문 없음")

    generated = "\n".join(body)

    idx_path = os.path.join(vault, "index.md")
    try:
        with open(idx_path, "rb") as fh:
            cur = fh.read().decode("utf-8-sig")
    except (UnicodeDecodeError, OSError) as e:
        print("index.md 읽기 실패(%s) -- 생성을 중단합니다." % type(e).__name__)
        return 1
    cur_n = cur.replace("\r\n", "\n").replace("\r", "\n")
    if AUTO_INDEX_BEGIN not in cur_n or AUTO_INDEX_END not in cur_n:
        print("생성 마커 없음 -- index.md를 덮어쓰지 않았습니다.")
        print("  도입하려면 생성 대상 구역(프로젝트 테이블~미해결 질문)을 다음 두 줄로 감싸세요:")
        print("    %s" % AUTO_INDEX_BEGIN)
        print("    %s" % AUTO_INDEX_END)
        print("  마커 밖(증상별 인덱스·참조·머리말)은 생성이 건드리지 않습니다.")
        return 1

    head, _sep, rest = cur_n.partition(AUTO_INDEX_BEGIN)
    if AUTO_INDEX_END not in rest:
        # END가 BEGIN보다 앞에 있는 malformed 파일 -- "마커 없음"과 같은 경로로 닫는다
        #  (여기서 split을 그냥 하면 ValueError로 죽어, 안내 없이 트레이스백만 남는다).
        print("마커 순서 이상(END가 BEGIN보다 앞) -- index.md를 덮어쓰지 않았습니다.")
        return 1
    _, tail = rest.split(AUTO_INDEX_END, 1)
    new = head + AUTO_INDEX_BEGIN + "\n" + generated + "\n" + AUTO_INDEX_END + tail

    if pending:
        print("라벨 미역이관 %d건 -- `index_label` 부재로 폴백값을 썼습니다(한/영 병기 미보증):"
              % len(pending))
        for r in pending[:10]:
            print("  - %s" % r)
        if len(pending) > 10:
            print("  ... 외 %d건" % (len(pending) - 10))

    if dry_run:
        print("== --build-index --dry-run (파일 미변경) ==")
        print(new)
        for name, lines in sorted(sub_files.items()):
            print("---- %s.md ----" % name)
            print("\n".join(lines))
        return 0

    # 여러 파일을 순차로 덮어쓰면 중간 실패가 **깨진 상태**를 남긴다 -- index.md는 이미
    #  [[index-personal]]을 가리키는데 그 파일은 없는 식이다. 전부 `.tmp-build-index`로 쓴 뒤
    #  한꺼번에 os.replace로 치환한다. (치환 자체는 파일 단위 원자성이라 다중 파일 전체를
    #  보장하지는 않지만, 실패가 몰리는 지점인 '쓰기'를 치환 앞으로 모아 창을 최소화한다.)
    staged = []
    try:
        for path, content in [(idx_path, new)] + [
                (os.path.join(vault, name + ".md"), _sub_index_text(name, lines))
                for name, lines in sorted(sub_files.items())]:
            tmp = path + ".tmp-build-index"
            with open(tmp, "wb") as fh:
                fh.write(content.encode("utf-8"))
            staged.append((tmp, path))
        for tmp, path in staged:
            os.replace(tmp, path)
    except OSError as e:
        for tmp, _path in staged:
            try:
                os.remove(tmp)
            except OSError:
                pass   # 임시 파일 정리 실패는 원본에 영향이 없다 -- 원 실패를 가리지 않는다
        print("인덱스 쓰기 실패(%s) -- 원본을 그대로 두었습니다." % type(e).__name__)
        return 1

    # stale sub-index 제거는 **치환 전건 성공 이후에만** 한다. 앞에 두면 쓰기가 실패했을 때
    #  "지워졌는데 index.md는 옛 상태"가 남고, 삭제는 tmp 정리로 되돌릴 수 없다.
    #  개별 삭제 실패는 격리한다 -- 치환은 이미 끝났으므로 되돌릴 대상이 아니다.
    removed = []
    for p in _stale_sub_indexes(vault, set(sub_files)):
        try:
            os.remove(p)
            removed.append(os.path.basename(p))
        except OSError as e:
            print("  [정리 실패] %s (%s)" % (os.path.basename(p), type(e).__name__))
    print("index.md 생성 구역 갱신 · sub-index %d개 생성" % len(sub_files)
          + (" · stale %d개 제거(%s)" % (len(removed), "·".join(removed)) if removed else ""))
    return 0


class SplitSession:
    """`--auto-split` 한 번의 실행 컨텍스트 — 사본·기록·보고를 모은다(§4 분할 수행 절차).

    `--fix`(apply_fixes)와 합치지 않는 이유: 그쪽은 「참조 무결성 3종」으로 대상이 한정되고
    실행에 사용자 승인이 필요한데(§7 서두), 분할·롤오버는 승인 불요다(§7 결과 처리 예외 ①②③).
    규약이 정반대라 한 함수에 섞으면 승인 경계가 흐려진다."""

    def __init__(self, vault, dry_run):
        self.vault = vault
        self.dry_run = dry_run
        self.backup_dir = os.path.join(
            vault, "90_archive", "backup",
            datetime.date.today().isoformat() + "-presplit")
        self.backed_up = set()
        self.claimed = set()   # 이번 실행에서 어느 처방이 이미 맡은 파일 — claim() 참조
        self.current_claims = set()   # **지금 도는 처방이** 맡은 것 — 격리·계약 강제의 단위
        self.actions = []      # (종류, 대상, 신설 파일 목록) — §4 7번 log 기록·사후 보고 공용
        self.notes = []        # 건너뛴 사유 등 보고용 1줄들
        self.failed = False

    def backup(self, *paths):
        """착수 직전 사본(§4 절차 1번·§8 `-presplit`). 실패하면 처방을 시작하지 않는다 —
        사본 없는 분할은 원복 수단이 없다. 같은 세션 2회째는 재복사하지 않는다(§8: 그 세션
        최초 상태 1부만 보존 — 재복사하면 이미 분할한 중간 상태가 원본 자리를 덮는다)."""
        # 계약 강제: 백업하려는 파일은 이 처방이 맡은 것이어야 한다. 처방이 claim을 잊고
        #  바로 쓰기로 들어가면 겹침 방지·원복 범위 보장이 조용히 무너지므로, 여기서 대신
        #  claim해 보고 **다른 처방이 이미 맡았으면 예외**로 즉시 드러낸다(격리 루프가 잡아
        #  `[SPLIT-FAIL]`로 보고한다). docstring 규율만으로는 위반이 침묵한다.
        unclaimed = [p for p in paths if p not in self.current_claims]
        if unclaimed and not self.claim(*unclaimed):
            raise RuntimeError(
                "claim 없이 백업 시도 — 다른 처방이 맡은 파일: "
                + ", ".join(sorted(os.path.relpath(p, self.vault) for p in unclaimed)))
        if self.dry_run:
            return True
        for p in paths:
            if not os.path.exists(p) or p in self.backed_up:
                continue
            rel = os.path.relpath(p, self.vault)
            dest = os.path.join(self.backup_dir, rel)
            try:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                if not os.path.exists(dest):   # §8 미덮어쓰기 — 그날 최초 상태를 지키다
                    shutil.copy2(p, dest)
                self.backed_up.add(p)
            except OSError as e:
                self.notes.append(f"사본 실패({type(e).__name__}) — 처방 미수행: {rel}")
                self.failed = True
                return False
        return True

    def claim(self, *paths):
        """이번 실행에서 이 파일들을 **이 처방이 맡는다**고 선언한다. 이미 다른 처방이 맡은
        파일이 하나라도 있으면 False — 그 처방은 이번 실행에서 그 대상을 건너뛴다.

        **한 실행에서 한 파일은 한 처방만 손댄다**는 규칙이 필요한 이유: 사본은 §8상
        「그 세션 최초 상태 1부」뿐이라 **중간 상태로 되돌릴 방법이 없다.** 두 처방이 같은
        파일을 순차로 고치면(등록 순서 주석이 예고하는 project 허브가 그렇다) 뒤 처방이
        실패할 때 되돌릴 수 있는 것은 「첫 처방 이전」뿐이고, 그러면 이미 보고된 앞 처방의
        결과가 조용히 사라진다. 겹침을 애초에 막으면 원복 범위가 언제나 명확하다.

        건너뛴 대상은 **다음 실행이 처리한다** — 처방은 멱등이고 `--auto-split`은 반복
        실행이 전제이므로(수렴하면 「수행 대상 없음」), 한 실행에서 다 끝내려다 원복 불가
        상태를 만드는 것보다 낫다."""
        want = set(paths)
        if want & self.claimed:
            return False
        self.claimed |= want
        self.current_claims |= want
        return True

    def restore(self, only=None):
        """`-presplit` 사본으로 되돌린다(§4 절차 5번 원복).

        **`only`로 범위를 좁힌다 — 기본값(None)은 세션 전체다.** 처방 단위 격리에서는
        **그 처방이 맡은 파일만**(`claim`) 전달한다. `claim`이 겹침을 막으므로 그 집합은
        다른 처방의 결과를 담지 않는다 — 과잉 복원(앞 처방 결과까지 되돌림)도, 미복원
        (이미 백업돼 차집합에서 빠진 공유 파일)도 생기지 않는다.

        **사본이 있는 파일만** 되돌린다 — 신설된 하위 파일은 사본이 없으므로 그대로 남는데,
        그것은 다음 실행이 같은 이름으로 덮어쓰거나 사람이 지울 수 있는 상태다(원본이
        온전하면 유실이 아니다). 반환: 되돌린 파일 수."""
        n = 0
        for p in sorted(self.backed_up if only is None else (only & self.backed_up)):
            src = os.path.join(self.backup_dir, os.path.relpath(p, self.vault))
            if not os.path.exists(src):
                continue
            try:
                shutil.copy2(src, p)
                n += 1
            except OSError:
                self.notes.append(f"원복 실패: {os.path.relpath(p, self.vault)}")
        return n

    def record(self, kind, target, created):
        self.actions.append((kind, target, list(created)))

    def log_line(self, kind, target, created):
        """§4 절차 7번 기록 1줄. 형식은 그 절이 정본이다."""
        made = "·".join(created) if created else "(신설 없음)"
        return (f"- [{datetime.date.today().isoformat()}] [SCHEMA] {kind} — "
                f"{target}: {made}. (사유: 임계 초과)")


def _atomic_write(path, content, bom=False, newline="\n"):
    """임시 파일에 쓴 뒤 os.replace로 치환한다 — 쓰기 도중 실패가 원본을 깨뜨리지 않게.
    build_index가 확립한 관례를 파일 하나짜리 쓰기에도 그대로 쓴다(같은 파일 안에서
    한쪽만 직접 덮어쓰면 그 파일이 손상 위험을 혼자 진다).

    **원본의 BOM·줄바꿈을 보존한다** — `apply_fixes`의 `write`/`nl_of`가 지키는 규약과 같다.
    보존하지 않으면 CRLF·BOM 파일이 수정될 때마다 조용히 LF·BOM 없음으로 평탄화돼,
    변경한 줄과 무관한 전체 diff가 만들어진다. 반환: 성공 여부."""
    if newline != "\n":
        content = content.replace("\n", newline)
    data = content.encode("utf-8")
    if bom:
        data = b"\xef\xbb\xbf" + data
    tmp = path + ".tmp-write"
    try:
        with open(tmp, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
        return True
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass   # 임시 파일 정리 실패는 원본에 영향이 없다 -- 원 실패를 가리지 않는다
        return False


def _read_page(path):
    """페이지를 읽어 (정규화 텍스트, BOM 여부, 줄바꿈)을 돌려준다. 실패면 (None, False, "\\n").
    쓰기 쪽(_atomic_write)이 원본 형상을 보존하려면 읽기 쪽이 그 형상을 함께 알려줘야 한다."""
    try:
        with open(path, "rb") as fh:
            b = fh.read()
    except OSError:
        return None, False, "\n"
    bom = b.startswith(b"\xef\xbb\xbf")
    try:
        raw = b.decode("utf-8-sig")
    except UnicodeDecodeError:
        return None, False, "\n"
    return raw.replace("\r\n", "\n").replace("\r", "\n"), bom, ("\r\n" if "\r\n" in raw else "\n")


def _append_log_entries(vault, lines):
    """§4 7번 기록을 log.md `## 최근 변경`에 append한다. 파일·섹션이 없으면 만들지 않고
    건너뛴다 — 없는 vault에 구조를 지어내지 않는다(그 경우 보고에만 남는다).
    반환: 기록한 줄 수."""
    path = os.path.join(vault, "log.md")
    if not lines or not os.path.exists(path):
        return 0
    text, bom, nl = _read_page(path)
    if text is None:
        return 0
    sec = section(text, "최근 변경")
    if not sec:
        return 0
    new_sec = sec.rstrip("\n") + "\n" + "\n".join(lines) + "\n\n"
    if not _atomic_write(path, text.replace(sec, new_sec, 1), bom, nl):
        return 0
    return len(lines)


# 처방 목록 — 각 처방이 자기 함수를 정의하고 여기 등록한다(auto_split의 순차 호출 대상).
#  등록 순서가 곧 수행 순서이며 「롤오버 먼저, 산문 분리 나중」이다: 롤오버가 먼저 줄여 두면
#  산문 분리가 손댈 페이지가 줄어든다(project 허브가 그렇다). 플러그인·전략 클래스로
#  추상화하지 않는다 -- 이 목록이 곧 처방 목록이고, 새 처방은 여기 한 줄이 는다.
#  비어 있으면 `--auto-split`은 "수행 대상 없음"으로 끝난다.
PRESCRIPTIONS = []


def _run_prescriptions(ses):
    """처방 목록을 **격리해서** 순차 실행한다(본 실행·재점검 공용).

    두 호출 지점이 같은 안전 계약을 쓰게 하려고 함수로 묶었다 -- 한쪽에만 try/except를
    두면 재점검 경로에서 처방 하나가 죽을 때 그때까지의 수행분이 보고 없이 사라진다.

    격리는 「계속 진행」이 아니라 **「되돌리고 계속」**이다: 중간에 죽은 처방은 파일을 절반만
    고쳤을 수 있어, **그 처방이 맡은 파일만**(claim) 원복한 뒤 다음 처방으로 간다. 원복 범위를
    claim으로 잡는 이유는 `backup()`이 멱등이라 「새로 백업한 것」으로 재면 **앞 처방이 이미
    백업해 둔 공유 파일이 차집합에서 빠져 반쯤 고쳐진 채 남기** 때문이다(claim이 애초에
    그 공유를 막으므로 두 오류 방향이 함께 닫힌다 -- claim()·restore(only=) 참조)."""
    for prescribe in PRESCRIPTIONS:
        before_actions = len(ses.actions)
        ses.current_claims = set()      # 처방 단위 리셋 — 격리·계약 강제가 이 집합을 단위로 본다
        try:
            prescribe(ses)
        except Exception as e:      # 처방 구현의 어떤 실패든 나머지를 막지 않게(광의 포획 의도)
            restored = ses.restore(only=set(ses.current_claims))
            del ses.actions[before_actions:]
            ses.notes.append(
                f"[SPLIT-FAIL] {getattr(prescribe, '__name__', prescribe)}: "
                f"{type(e).__name__} — 사본에서 {restored}개 파일 원복 후 다음 처방 계속")
            ses.failed = True


def auto_split(vault, dry_run):
    """임계에 닿은 파일을 규정된 처방대로 **코드가** 나누거나 옮긴다(§4·§8).

    **수행 주체가 세션에서 코드로 바뀐 근거**: 종전 §7-2는 *"무엇을 옮길지는 판단"*이라며
    스크립트 수행을 배제했는데, 그 전제는 **옮길 단위를 임의로 잡을 때만** 참이다. 경계를
    스키마가 이미 정한 `## ` 섹션과 항목 단위로 고정하면 「무엇을 옮길지」가 크기·시간
    순서로 결정돼 판단이 사라진다. 롤오버 3종은 §2.8·§8이 이미 그렇게 규정하고 있었다.

    실행 순서(각 처방은 자기 절에서 정의된다):
      ① index 계열 -- `build_index`가 담당(생성 마커 vault). 여기서는 마지막에 연쇄 호출한다.
      ② 롤오버 -- log.md · decision-log · project 허브 `## 최근 주요 변경`
      ③ 산문 하위 분리 -- 필수 섹션 헤딩은 남기고 본문만 옮긴 뒤 포인터 1줄
      ④ 등록 -- ①의 연쇄로 신설 하위가 인덱스에 오른다(등록이 빠지면 분할이 곧 유실이다)

    반환: 종료 코드(0 정상 / 1 처방 실패)."""
    ses = SplitSession(vault, dry_run)
    if not dry_run:
        cleaned, cleanup_failed = cleanup_backups(vault, datetime.date.today())
        if cleaned:
            print(f"백업 정리: {cleaned}건 제거 (§8 30일)")
        for f in cleanup_failed:
            print(f"  [정리 실패] {f}")

    _run_prescriptions(ses)

    if not ses.actions:
        print("== --auto-split: 수행 대상 없음 ==")
        for n in ses.notes:
            print(f"  {n}")
        return 1 if ses.failed else 0

    if dry_run:
        print("== --auto-split --dry-run (파일 미변경) ==")
        for kind, target, created in ses.actions:
            print(f"  {kind} — {target}: {'·'.join(created) if created else '(신설 없음)'}")
        for n in ses.notes:
            print(f"  {n}")
        return 0

    # §4 7번 기록. **이 기록이 log.md를 다시 임계로 밀 수 있으므로** 기록 후 롤오버 트리거를
    #  1회 재점검한다(§8 "log 기록 추가 직후 트리거 점검"). 그 재점검이 유발한 롤오버는
    #  기록을 다시 남기지 않는다 -- 기록→롤오버→기록의 연쇄를 끊는 것이 이 「1회」의 의미다.
    written = _append_log_entries(vault, [ses.log_line(*a) for a in ses.actions])
    if written:
        # 재점검은 처방 **목록 전체**를 다시 돌린다 -- 특정 처방을 이름으로 부르지 않는 이유는
        #  그 이름이 이 골격에 없는 심볼에 대한 계약이 되어(정의 위치가 후속 task) 목록과
        #  이름 참조 두 곳이 갈리기 때문이다. 이미 해소된 처방은 발동 조건이 거짓이라 no-op다.
        #  본 실행과 **같은 격리 계약**을 쓴다(_run_prescriptions 공용).
        recheck = SplitSession(vault, dry_run)
        _run_prescriptions(recheck)
        if recheck.actions:
            ses.notes.append(
                f"log 기록 후 재점검에서 {len(recheck.actions)}건 추가 수행(§4 7번 기록 미생성 — 연쇄 차단)")

    # 신설 하위를 인덱스에 등재한다 -- 이 연쇄가 없으면 분할 직후 §7-6·§7-30ⓒ가 미등록을
    #  경고하고 조회 경로가 끊긴다. 생성 마커가 없는 vault에서는 build_index가 아무것도 쓰지
    #  않고 1을 돌려주므로 **실패로 보지 않고** 등록이 수기 몫임을 알린다(§4 절차 4번).
    if build_index(vault, False) != 0:
        ses.notes.append("생성 마커 없음 — 인덱스 등록은 수기 몫(§4 절차 4번)")

    print(f"== --auto-split: {len(ses.actions)}건 수행 ==")
    for kind, target, created in ses.actions:
        print(f"  {kind} — {target}: {'·'.join(created) if created else '(신설 없음)'}")
    for n in ses.notes:
        print(f"  {n}")
    print(f"  사본: {ses.backup_dir}")
    return 1 if ses.failed else 0


def apply_fixes(vault):
    """--fix 모드: 판단이 필요 없는 '참조 무결성 동기' 3종만 자동 수정한다 (§7 —fix 규약) —
      ① §7-23 미해결 질문 인덱스 동기(양방향: open 미등록 행 추가 + resolved 잔존 행 제거 —
         섹션이 표면 표 행, 아니면 불릿으로 추가: insert_into_section)
      ② §7-24 decisions '## 아카이브' 포인터 동기(양방향: 깨진 포인터 행 제거 + 실재 아카이브 포인터 행 추가
         — 제거는 '## 아카이브' 섹션 안 행만, 결정 항목 본문 인용은 불변 §2.8)
      ③ §7-19 log 아카이브 인덱스 stale 행 '제거만' (누락 행 추가는 그 달 키워드 요약이 필요해 판단 개입 — 수동)
    그 외 검사(인덱스 행 생성·한/영 병기·updated 등)는 내용 판단이 필요해 --fix 대상이 아니다.
    안전장치: 수정 전 원본을 90_archive/backup/{오늘}/ 원경로에 백업(목적지 존재 시 미덮어쓰기 — §8,
      복구는 절차 L 그대로 적용). 인코딩(BOM)·줄바꿈은 원본 상태를 보존한다. 항목별 실패는 격리
      (그 파일만 [FIX-FAIL] 보고 후 계속). 위반 0이면 파일 무변경·백업 미생성.
    **백업 정리는 새 백업을 만들기 전에 1회 수행한다**(cleanup_backups — §8 누적 금지·30일 정리).
      순서가 중요하다: 나중에 하면 방금 만든 오늘 백업을 지울 판정을 다시 하게 된다.
    플래그 없는 기본 실행은 이 함수를 타지 않는다 — read-only 계약 불변(정리도 여기서만 일어난다)."""
    today = datetime.date.today()
    cleaned, cleanup_failed = cleanup_backups(vault, today)
    rel = lambda p: os.path.relpath(p, vault).replace("\\", "/")
    md = [f for f in glob.glob(os.path.join(glob.escape(vault), "**", "*.md"), recursive=True)]
    raws, pages = {}, {}   # rel -> (bom, 원본 텍스트) / rel -> (fm, type, 정규화 텍스트)
    for p in md:
        try:
            with open(p, "rb") as fh:
                b = fh.read()
            raw = b.decode("utf-8-sig")
        except (UnicodeDecodeError, OSError):
            continue   # 읽기 실패 파일은 fix 제외 — 본 lint가 ERR로 보고한다
        norm = raw.replace("\r\n", "\n").replace("\r", "\n")
        fm = frontmatter(norm)
        raws[rel(p)] = (b.startswith(b"\xef\xbb\xbf"), raw)
        pages[rel(p)] = (fm, fm.get("type", ""), norm)

    fixed, failed = [], []
    skipped_fix = []   # 생성기가 담당해 이번 --fix에서 제외한 항목 (D11)
    backed = set()

    def backup(r):
        if r in backed:
            return
        src = os.path.join(vault, r.replace("/", os.sep))
        dst = os.path.join(vault, "90_archive", "backup", today.isoformat(), r.replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(dst):   # 목적지 존재 시 미덮어쓰기(§8) — 같은 날 첫 백업이 원본
            shutil.copy2(src, dst)
        backed.add(r)

    def write(r, new_raw):
        bom, _ = raws[r]
        data = new_raw.encode("utf-8")
        if bom:   # 원본 BOM 보존 — BOM 정리는 fix 범위 아님(별도 WARN이 안내)
            data = b"\xef\xbb\xbf" + data
        with open(os.path.join(vault, r.replace("/", os.sep)), "wb") as fh:
            fh.write(data)
        raws[r] = (bom, new_raw)

    def nl_of(raw):
        return "\r\n" if "\r\n" in raw else "\n"

    def remove_lines(raw_seg, pred):
        kept = [ln for ln in raw_seg.splitlines(keepends=True) if not pred(ln)]
        return "".join(kept), len(raw_seg.splitlines()) - len(kept)

    def section_span(raw, heading):
        return re.search(r"(?m)^##\s*" + re.escape(heading) + r"\b.*?(?=^##\s|\Z)", raw, re.S)

    def insert_into_section(raw, heading, new_line, cell=None):
        """섹션 끝(후행 공백줄 앞)에 행 삽입. 섹션이 없으면 문서 끝에 신설(기계적 — 골격 규약 준수).
        cell이 주어지고 섹션에 표(`|` 시작 행)가 있으면 불릿 대신 **표 행**으로 삽입한다 —
        부트스트랩 골격(SKILL J 2 "표는 헤더만")의 표 섹션에 불릿을 섞지 않는다(§7 --fix 규약).
        컬럼 수는 섹션 첫 `|` 행(헤더) 기준, 첫 셀에 cell·나머지는 빈 셀. 표가 없으면
        new_line(불릿) 그대로 — 기존 불릿형 vault 하위호환(§7-24 포인터 추가도 불릿 경로).
        반환: (새 텍스트, 섹션 신설 여부)."""
        nl = nl_of(raw)
        m = section_span(raw, heading)
        if not m:
            base = raw if raw.endswith("\n") else raw + nl
            return base + nl + "## " + heading + nl + new_line + nl, True
        seg = m.group(0)
        body = seg.rstrip("\r\n")
        trail = seg[len(body):]
        insert = new_line
        if cell is not None:
            header = next((ln for ln in seg.splitlines() if ln.lstrip().startswith("|")), None)
            if header:
                ncols = max(1, len(header.strip().strip("|").split("|")))
                insert = "| " + cell + " |" + " |" * (ncols - 1)
        new_seg = body + nl + insert + (trail if trail else nl)
        return raw[:m.start()] + new_seg + raw[m.end():], False

    # ── ① §7-23 미해결 질문 인덱스 동기 ──────────────────────────────
    # 생성 마커가 있는 vault에서는 이 항목을 건너뛴다 -- `## 미해결 질문`이 `--build-index`의
    #  생성 구역이 되어 writer가 둘이 되기 때문이다(같은 섹션에 두 주체가 쓰면 어느 쪽이 근거인지
    #  사라진다). 생성기가 같은 정합을 매 실행 보장하므로 자동수정이 할 일이 없다.
    #  **못 잡게 되는 것**: 마커 있는 vault에서 생성기를 돌리지 않은 채 open question이 늘면
    #  index.md가 그만큼 뒤처진다 -- 그 상태는 다음 `--build-index` 한 번으로 닫히고, 검사(§7-23)
    #  자체는 그대로 남아 보고한다(수정만 생성기가 맡는다).
    #  **마커 없는 vault는 무회귀** -- 종전대로 안전 3종이 모두 동작한다(D11).
    if AUTO_INDEX_BEGIN in pages.get("index.md", (None, None, ""))[2]:
        skipped_fix.append("§7-23 미해결 질문 동기 — 생성 구역이라 --build-index가 담당 (D11)")
    elif "index.md" in pages:
        try:
            inorm = pages["index.md"][2]
            q_sec = section(strip_code(inorm), "미해결 질문") or ""
            q_listed = {t[:-3] if t.endswith(".md") else t for t in wikilink_targets(q_sec)}
            to_add, stale_keys = [], set()
            for qr, (qfm, qtyp, qnorm) in sorted(pages.items()):
                if qtyp != "question" or qr.startswith("90_archive/"):
                    continue
                resolved = question_is_resolved(qfm)
                listed = qr[:-3] in q_listed or os.path.basename(qr)[:-3] in q_listed
                if not resolved and not is_lint_report(qr) and not listed:
                    h1 = re.search(r"(?m)^#\s+(.+)$", qnorm)
                    to_add.append((qr[:-3], h1.group(1).strip() if h1 else os.path.basename(qr)[:-3]))
                if resolved and listed:
                    stale_keys.add(qr[:-3])
                    stale_keys.add(os.path.basename(qr)[:-3])
            if to_add or stale_keys:
                backup("index.md")
                bom, raw = raws["index.md"]
                if stale_keys:
                    m = section_span(raw, "미해결 질문")
                    if m:   # 섹션 '안'의 행만 제거 — 다른 섹션의 정당한 링크 보존
                        def is_stale_row(ln):
                            return any((t[:-3] if t.endswith(".md") else t) in stale_keys
                                       for t in wikilink_targets(ln))
                        new_seg, n = remove_lines(m.group(0), is_stale_row)
                        if n:
                            raw = raw[:m.start()] + new_seg + raw[m.end():]
                            fixed.append(f"index.md: 해결된 질문 행 {n}개 제거 (§7-23)")
                for path_noext, title in to_add:
                    # 제목의 `|`는 표 셀·wikilink 표시명을 깨뜨리므로 치환(표시용 텍스트라 무손실 아님을 감수)
                    safe_title = title.replace("|", "/")
                    raw, created = insert_into_section(
                        raw, "미해결 질문", f"- [[{path_noext}|{safe_title}]]",
                        cell=f"[[{path_noext}\\|{safe_title}]]")  # 표 셀 안 wikilink는 \| 이스케이프(§3)
                    fixed.append(f"index.md: 미해결 질문 등록 — {path_noext} (§7-23)"
                                 + (" [섹션 신설]" if created else ""))
                write("index.md", raw)
        except OSError as e:
            failed.append(f"index.md 수정 실패({type(e).__name__}) — 건너뜀")

    # ── ② §7-24 decisions '## 아카이브' 포인터 동기 (패턴 단일 출처: DEC_PTR_RX) ──
    dec_rx = DEC_PTR_RX
    for r in sorted(pages):
        fm, typ, norm = pages[r]
        if typ != "decision-log" or r.startswith("90_archive/"):
            continue
        try:
            acted = False
            broken = sorted({t for t in dec_rx.findall(norm) if t not in pages})
            if broken:
                bom, raw = raws[r]
                # 제거는 '## 아카이브' 섹션 안 행만 — 결정 항목 본문이 깨진 아카이브 경로를 인용해도
                #   지우지 않는다(§2.8 항목 불변·수정 삭제 금지). 섹션 밖 깨진 포인터는 제거 0건으로
                #   남고 본 lint의 §7-24 WARN이 계속 가리킨다(검출 광역·수정 보수 — §7-19 '제거만' 동형).
                m = section_span(raw, "아카이브")
                if m:
                    new_seg, n = remove_lines(m.group(0), lambda ln: any(b in ln for b in broken))
                    if n:
                        backup(r)
                        raws[r] = (bom, raw[:m.start()] + new_seg + raw[m.end():])
                        acted = True
                        fixed.append(f"{r}: 깨진 decisions 아카이브 포인터 {n}행 제거 (§7-24 — '## 아카이브' 섹션 내)")
            arch = "90_archive/" + r
            if arch in pages and arch not in raws[r][1]:
                backup(r)
                bom, raw = raws[r]
                new_raw, created = insert_into_section(raw, "아카이브", f"- {arch}")
                raws[r] = (bom, new_raw)
                acted = True
                fixed.append(f"{r}: 아카이브 포인터 추가 — {arch} (§7-24)"
                             + (" [섹션 신설]" if created else ""))
            if acted:
                write(r, raws[r][1])
        except OSError as e:
            failed.append(f"{r} 수정 실패({type(e).__name__}) — 건너뜀")

    # ── ③ §7-19 log 아카이브 인덱스 stale 행 제거 (제거만 — 추가는 수동) ──
    if "log.md" in pages:
        try:
            norm = pages["log.md"][2]
            sec_txt = section(norm, "아카이브 인덱스")
            indexed = set(re.findall(r"(\d{4}-\d{2})\.md", sec_txt)) if sec_txt else set()
            archived = {m.group(1) for k in pages
                        if (m := re.fullmatch(r"90_archive/log/(\d{4}-\d{2})\.md", k))}
            stale = sorted(indexed - archived)
            if stale:
                backup("log.md")
                bom, raw = raws["log.md"]
                m = section_span(raw, "아카이브 인덱스")
                if m:
                    new_seg, n = remove_lines(m.group(0), lambda ln: any((ym + ".md") in ln for ym in stale))
                    if n:
                        write("log.md", raw[:m.start()] + new_seg + raw[m.end():])
                        fixed.append(f"log.md: stale 아카이브 인덱스 행 {n}개 제거 (§7-19 — 누락 행 추가는 수동)")
        except OSError as e:
            failed.append(f"log.md 수정 실패({type(e).__name__}) — 건너뜀")

    print("== --fix 적용 (안전 3종: §7-23 / §7-24 / §7-19 stale 제거) ==")
    for c in cleaned:
        print("[CLEANUP] 백업 제거: " + c)
    for c in cleanup_failed:
        print("[CLEANUP-FAIL] " + c)
    for s in skipped_fix:
        # 건너뛴 것을 조용히 두면 "3종을 다 돌렸다"로 읽힌다 -- 무엇이 왜 빠졌는지 남긴다.
        print("[SKIP] " + s)
    if fixed:
        for f in fixed:
            print("[FIXED] " + f)
        print(f"백업: 90_archive/backup/{today.isoformat()}/ (원본 보존 — 복구는 절차 L)")
    else:
        print("수정 대상 없음 (파일 무변경·백업 미생성)")
    for f in failed:
        print("[FIX-FAIL] " + f)
    print()


def main():
    if len(sys.argv) < 2:
        print("사용법: python lint.py \"<vault_path>\" "
              "[--fix] [--build-index [--dry-run]] [--auto-split [--dry-run]]")
        sys.exit(1)
    vault = sys.argv[1].rstrip("/\\")
    # --fix는 opt-in — 지정 시 안전 3종을 먼저 수정하고, 이어지는 본 lint가 수정 후 상태를 보고한다.
    #  (기본 실행은 완전 read-only 불변)
    # --build-index는 검사와 독립이다 -- 생성만 하고 끝낸다(검사가 섞이면 결과가 진단에 묻힌다).
    if "--build-index" in sys.argv[2:]:
        sys.exit(build_index(vault, "--dry-run" in sys.argv[2:]))
    # --auto-split도 검사와 독립이다(같은 이유). --fix와 **함께 쓸 수 없다** — 그쪽은 사용자
    #  승인 후 실행하는 참조 무결성 수리이고 이쪽은 승인 불요 분할이라, 한 번에 섞으면
    #  어느 변경이 어느 규약으로 이뤄졌는지 사후에 가릴 수 없다(§7 서두·결과 처리 예외).
    if "--auto-split" in sys.argv[2:]:
        if "--fix" in sys.argv[2:]:
            print("--auto-split과 --fix는 함께 쓸 수 없습니다 "
                  "(승인 규약이 다름 — 따로 실행하세요, wiki-schema §7).")
            sys.exit(1)
        sys.exit(auto_split(vault, "--dry-run" in sys.argv[2:]))
    if "--fix" in sys.argv[2:]:
        apply_fixes(vault)
    # L-3: vault 경로에 glob 메타문자([ ] * ? 등)가 있어도 리터럴로 취급 — glob.escape로 감싸지 않으면
    #   'D:\wiki[2026]' 같은 경로에서 md 목록이 0개가 되어 대부분 검사가 공허 통과한다.
    md = [f for f in glob.glob(os.path.join(glob.escape(vault), "**", "*.md"), recursive=True)]
    rel = lambda p: os.path.relpath(p, vault).replace("\\", "/")
    existing = {rel(p)[:-3] for p in md}  # 확장자 제거한 상대경로 집합
    existing_cf = {e.casefold() for e in existing}  # L-1: 대소문자 무시 비교용(Windows/Obsidian 정합)
    today = datetime.date.today()

    errors, warns, infos = [], [], []

    # WARN 프로젝트별 집계(§7 결과 처리): 메시지 문자열을 되파싱하지 않고, append 시점에
    #  경고 '대상 페이지'(vault 상대경로)로 집계한다 — 문구 수정·공백 포함 경로에 안전.
    #  20_projects는 category/프로젝트 키(허브 .md도 동일 키), 그 외는 최상위 디렉터리 키,
    #  루트 파일·페이지 무관 경고(sub-index 미등록·한/영 병기 등)는 집계 제외 —
    #  요약은 우선순위 파악용이라 총합과 다를 수 있다.
    warn_groups = {}

    def warn(msg, page=None):
        """WARN 추가 + 대상 페이지 기준 프로젝트별 집계(page 없으면 집계 제외)."""
        warns.append(msg)
        if not page or "/" not in page:
            return
        parts = page.split("/")
        if parts[0] == "20_projects" and len(parts) >= 3:
            key = "/".join(parts[1:3])   # feature: personal/{프로젝트}
            if key.endswith(".md"):      # 허브(20_projects/{cat}/{프로젝트}.md)도 동일 키
                key = key[:-3]
        else:
            key = parts[0]               # 40_guides 등: 최상위 디렉터리
        warn_groups[key] = warn_groups.get(key, 0) + 1

    unverified_hits, unverified_files = 0, 0  # (미검증) 집계 (wiki-schema §7-12)
    open_questions = 0                        # 미해결 question 집계 (〃)
    dep_count = 0                             # deprecated 페이지 집계 (wiki-schema §7-17)
    feat_files, index_feat_links = set(), set()
    indexed_files = {}     # typ -> {무확장 경로} — guide·entity·concept 인덱스 등록 검사(§7-30 ⓒ)
    stale60 = []           # (경과일, 경로) — 60일+ 미편집 집계용(§7-3)
    link_targets = set()   # 위키 전체에서 링크된 대상 (고아 검사용)
    pages = {}             # rel -> (frontmatter, type, 본문 텍스트)
    unreadable = set()     # 읽기 실패한 rel 경로 — 부재와 구분해 진단하기 위해 실패 지점에서 기록한다
                           #  (파일 실존을 나중에 os.path.exists로 되묻지 않는 이유: OSError(권한·잠금)는
                           #   실존해도 실패하므로 같은 사유가 두 번 다르게 판정된다)

    for p in md:
        r = rel(p)
        # M-2: 비 UTF-8 파일 1개가 전체 lint를 죽이지 않도록 파일별로 격리한다 — 실패 파일만 ERR로
        #   보고하고 나머지 검사는 계속(예: 외부 편집기가 CP949로 저장한 페이지 하나).
        # BOM: utf-8-sig로 읽어 BOM이 있어도 frontmatter 파싱이 실패하지 않게 하고, BOM 존재는 별도 WARN.
        try:
            with open(p, "rb") as fh:
                raw_bytes = fh.read()
            text = raw_bytes.decode("utf-8-sig")
        except (UnicodeDecodeError, OSError) as e:
            errors.append(f"파일 읽기 실패({type(e).__name__}): {r} — UTF-8(BOM 없음)로 저장하세요.")
            unreadable.add(r)
            continue
        # binary 읽기는 text-mode의 universal-newline 변환을 하지 않으므로 CRLF→LF로 정규화한다 —
        #   frontmatter '^---\n' 매치·줄 수 계산이 CRLF 파일에서 깨지지 않게(text-mode 열기와 동등).
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        if raw_bytes.startswith(b"\xef\xbb\xbf") and not r.startswith("90_archive/"):
            warn(f"UTF-8 BOM 발견: {r} — BOM 없이 저장 권장(인코딩 규약)", r)
        fm = frontmatter(text)
        typ = fm.get("type", "")
        pages[r] = (fm, typ, text)
        is_root = "/" not in r
        in_archive = r.startswith("90_archive/")

        # deprecated 판정 (status: deprecated 또는 deprecated 필드 — schema §2.3 둘 다 허용)
        is_dep = (fm.get("status") == "deprecated") or bool(fm.get("deprecated"))
        if is_dep and not in_archive:
            dep_count += 1  # F1-ⓐ 현행 vault deprecated 집계(이력 가시성, §7-17)
            # F1-ⓑ 폐기 안내 정합: deprecated인데 "코드에서 제거" 안내가 없으면 경고
            if "코드에서 제거" not in text:
                warn(f"deprecated 표기 안내 누락: {r} ('⚠ 코드에서 제거됨' 안내 권장, schema §2.3)", r)
        # F2 구현 근거 각주 게이트(§7-18): '## 구현 방법'은 필수 섹션(§2.3)이므로 ⓐ 섹션 자체가 없으면
        #  WARN(섹션을 통째로 빼서 각주 게이트를 우회하는 구멍 차단), ⓑ 섹션이 있는데 [^src-...] 각주가
        #  0개면 얕은 feature 의심 WARN. 각주 '존재'는 여기서, 각주 경로의 레포 실존은 §7-20 블록이
        #  기계 검사; 서술↔코드 사실 정합은 §7-10(에이전트 표본)이 담당.
        #  섹션 판정은 줄 시작 헤딩 정규식으로 — 산문이 '## 구현 방법'을 인용만 해도 존재로
        #  오인하지 않게 한다(단순 포함 검사의 오탐).
        if typ == "feature" and not is_dep and not in_archive:
            if not re.search(r"(?m)^##\s*구현 방법\b", text):
                warn(f"구현 방법 섹션 누락: {r} ('## 구현 방법'은 필수 섹션 — 얇게라도 유지, schema §2.3·§7-18)", r)
            elif "[^src-" not in text:
                warn(f"구현 근거 각주 누락: {r} (## 구현 방법 있으나 [^src-...] 0개 — 얕은 feature 의심, schema §2.3)", r)

        # wikilink: 깨진 링크(경로형) + 경로 없는 링크(명시적 경로 필수 위반)
        # 코드펜스/인라인코드 안 텍스트는 제외 — 추출·정규화는 wikilink_targets(§7-6·23과 공용)
        for t in wikilink_targets(text):
            # M-3: '.md' 확장자 제거 + L-1: casefold 정규화 — 깨진링크 검사와 고아 검사(696행)가 모두
            #   이 정규화값(link_targets)을 쓴다. 실존 파일을 가리키는 [[…/feat-x.md|…]]나 케이스만 다른
            #   링크를 '깨진 링크'·'고아 페이지'로 3중 오판하지 않게 한다(§3 무확장 규약·Windows/Obsidian
            #   대소문자 무관과 정합). link_targets에 raw를 넣으면 고아 검사가 정규화값과 어긋나 오탐 재발.
            t_norm = (t[:-3] if t.endswith(".md") else t).casefold()
            link_targets.add(t_norm)
            # 90_archive/ 하위(삭제 -deleted 백업 포함)는 깨진 링크·경로없음 검사에서 제외 —
            #   §8 "아카이브는 lint 자동 제외" 서술과 동작 일치. 삭제된 프로젝트의 -deleted 백업은
            #   원경로가 사라져 그 안의 링크가 '깨진 링크' ERR로 뜨는데, 이는 복구 수단(백업)을 스스로
            #   지우도록 유도하는 오탐이다(예산·인덱스·고아 검사가 이미 아카이브를 제외하는 것과 정합).
            #   link_targets.add는 위에서 무조건 수행 — 고아 검사가 아카이브발 링크도 '링크됨'으로
            #   인정해야 무회귀(가드를 add 위로 올리면 아카이브만 링크한 페이지가 고아로 오탐).
            # 루트 큐 파일(pending.md·skill-feedback.md, 소비 대기 큐)도 제외 — 큐 항목은 지식
            #   페이지가 아니라 링크 규약(§3) 대상이 아니다(§6·§7-1). 큐에 적힌 wikilink 대상이
            #   이후 삭제·이름변경돼도 lint를 exit 1로 죽이지 않는다(시크릿 스캔·§7-25 잔량
            #   집계·link_targets 수집은 유지).
            if not in_archive and r not in ROOT_QUEUE_FILES:
                if "/" in t:
                    if t_norm not in existing_cf:
                        errors.append(f"깨진 링크: {r} -> [[{t}]]")
                elif t_norm not in existing_cf:  # 루트 파일(index 등)로도 해석되지 않으면 위반
                    warn(f"경로 없는 wikilink(명시적 경로 필수): {r} -> [[{t}]]", r)

        # 예산 — log.md는 문자 수(len), 그 외 타입은 줄 수.
        #  90_archive/ 하위는 제외 — "아카이브는 lint 자동 제외" 서술과 동작 일치(§8),
        #  특히 append 성장하는 decisions 롤오버 파일에 영구 WARN이 걸리는 것 방지(§2.8).
        if r in SPECIAL_BUDGET:
            st = budget_state(r, fm, text)
            chars = st.chars
            if st.over:
                warn(f"예산 초과: {r} {chars}/{st.budget}자 "
                     f"— 오래된 항목을 90_archive/log/로 롤오버 필요 (wiki-schema §8)", r)
            elif st.critical:
                # 이 경로에는 임박 계층이 없어 근접 INFO만 있었다 — 그것을 지우면 log.md는 초과 전
                #  무신호가 되고, "임박 도달 시 소비 지점이 처방을 수행한다"는 규정이 이 타입에만
                #  도달하지 못한다. 일반 예산 분기와 같은 임계·같은 OR 결합을 쓴다(새 임계 없음 —
                #  판정은 budget_state 공용).
                warn(f"예산 임박: {r} {chars}/{st.budget}자 "
                     f"({chars / st.budget * 100:.0f}%, 여유 {st.budget - chars}자) "
                     f"— 다음 기록 전에 §8 롤오버 수행 (wiki-schema §8)", r)
        elif not in_archive:
            # 판정은 budget_state 공용 — 조건을 여기 다시 쓰지 않는다(그 함수 docstring 참조).
            #  guide_kind 통제어휘 WARN은 예산 판정이 아니라 「값 위반 가시화」라 여기 남는다.
            if typ == "guide":
                gk = fm.get("guide_kind", "")
                # L-3: guide_kind 오타(예: 'recipes')면 기본 9000자가 조용히 적용돼 recipe 8500자 예산을
                #   우회한다 → 통제어휘 밖이면 WARN(오타 가시화). 부재도 동일하게 침묵 우회가 되므로
                #   WARN(§7-2) — origin/confidence "누락 WARN·값 위반 ERR" 패턴과 동형(부재는 값이
                #   없어 ERR 대상이 아니고, exit 1로 기존 vault를 즉시 차단하지 않는다).
                if not gk:
                    warn(f"guide_kind 누락: {r} (허용: {', '.join(GUIDE_BUDGET)}) — 기본 9000자 적용됨(recipe 8500자 예산 우회 주의, schema §2.6)", r)
                elif gk not in GUIDE_BUDGET:
                    warn(f"guide_kind 통제어휘 위반: {r} guide_kind='{gk}' (허용: {', '.join(GUIDE_BUDGET)}) — 기본 9000자 적용됨", r)
            st = budget_state(r, fm, text)
            budget = st.budget if st else None
            eff_chars = st.eff_chars if st else 0
            fence_note = st.fence_note if st else ""
            # L-2: lint 리포트(questions/lint-YYYYMMDD.md)는 발견 다건이면 길어지는 게 정상이라
            #   예산 검사에서 제외한다(§7-12/23 집계·등록 제외와 동일 기준) — 자기 리포트가 다음 lint에서
            #   영구 '예산 초과' WARN을 만드는 것을 막는다.
            if budget and st.over and not is_lint_report(r):
                # 수리 경로가 정해진 타입은 초과 시점에도 그 처방을 병기한다 — 임박 WARN에서만
                #  안내하고 초과 WARN에서 침묵하면, 정작 고쳐야 할 시점에 방법을 못 받는다.
                hint = {
                    "decision-log": " — 오래된 항목을 90_archive 원경로로 롤오버 + '## 아카이브' 포인터 갱신 (wiki-schema §2.8)",
                    "project": " — '최근 주요 변경' 초과분을 90_archive/…/changes.md로 롤오버 + '## 아카이브' 포인터 갱신, 작업 규약은 conventions.md로 분리 (wiki-schema §2.2·§2.9)",
                    "convention": " — 무효 항목 제거 → 주제별 하위 파일(conventions-{주제}.md) 분리 + '## 하위 문서' 목록 갱신 (wiki-schema §2.9)",
                }.get(typ, "")
                warn(f"예산 초과: {r} {eff_chars}/{budget}자 (type={typ}{fence_note}){hint}", r)
            elif budget and st.critical and not is_lint_report(r) and not st.suppressed:
                # L-5: 초과 전에 나는 유일한 신호다. 80% INFO를 함께 내던 때는 여유 28자와 1,624자가
                #   같은 줄로 나와 정작 급한 것이 INFO 더미에 묻혔고(실측: INFO 99건 중 10건이 그것이었고
                #   그 상태로 방치돼 feature 하나가 여유 28자까지 왔다), 그래서 묻히는 층을 없앴다.
                #   이 WARN을 소비하는 것은 lint 세션(F-2)·ingest(A-4·B-3)다. **자동 수리는 하지 않는다**
                #   — 무엇을 옮길지는 판단이라 §4 index 자동 분할의 결정론 근거가 성립하지 않는다.
                #   여기서 하는 일은 신호를 내는 것까지이고, 처방을 수행하는 것은 세션이다(`--fix` 아님).
                #   그 수행의 승인 여부는 절차 문서(F-2·A-4·B-3)가 정하며 이 스크립트가 규정하지 않는다.
                #   억제(budget_split)가 걸리면 이 분기를 건너뛰어 아래 「분리 불가 판정 유지」 INFO로
                #   강등된다 — 나눌 하위가 없는 페이지에 실행 불가능한 처방을 반복 요구하지 않기 위함이다.
                crit_hint = {"project": " — '최근 주요 변경' 롤오버(§2.2·§8) 또는 작업 규약 conventions.md 분리(§2.9)",
                             "decision-log": " — 오래된 항목을 90_archive 원경로로 롤오버 (§2.8)",
                             "convention": " — 무효 항목 제거 → 주제별 하위 파일 분리 (§2.9)"}.get(typ, "")
                warn(f"예산 임박: {r} {eff_chars}/{budget}자 "
                     f"({eff_chars / budget * 100:.0f}%, 여유 {budget - eff_chars}자, type={typ})"
                     f"{crit_hint} — 다음 편집 전에 §4 처방 수행 (나눌 하위가 없으면 budget_split 판정)", r)
            elif budget and st.critical and not is_lint_report(r):
                # L-4: 위 임박 분기가 budget_split 억제로 건너뛴 파일이 여기로 내려온다(조건식은 임박과
                #   동일하고 억제 여부만 다르다 — 선행 게이트만으로 잡으면 82%짜리가 「임박」으로 오표기된다).
                #   침묵시키지 않는 이유: 억제를 영구 면제로 두면 "한 번 판정하면 초과까지 무신호"가 되어
                #   판정 자체가 사각이 된다. 상태는 보이되 수리 의무는 없으므로 WARN이 아니라 INFO다.
                infos.append(f"예산 임박(분리 불가 판정 유지): {r} {eff_chars}/{budget}자 "
                             f"({eff_chars / budget * 100:.0f}%, type={typ}) "
                             f"— 재판정 마진 초과 시 자동 재발화")

        # platform 통제어휘 (90_archive/ 제외 — 동결 백업은 wiki-schema §2.8·§8 자동 제외 원칙)
        plat = fm.get("platform")
        if plat and plat not in PLATFORM_VOCAB and not in_archive:
            errors.append(f"platform 통제어휘 위반: {r} -> '{plat}'")

        # category 통제어휘 (§7-7): 값이 있는데 어휘 밖이면 ERR. 부재는 검사하지 않는다 —
        #  경로 규약(20_projects/{personal|work}/)과 이중 검출을 피하고 값 오타만 잡는다.
        #  (90_archive/ 제외 — 통제어휘 축소 시 동결 백업이 영구 ERR로 exit 1을 유발하지 않게)
        cat = fm.get("category")
        if cat and cat not in CATEGORY_VOCAB and not in_archive:
            errors.append(f"category 통제어휘 위반: {r} -> '{cat}' (personal|work — schema §3)")

        # tech_stack 휘발성 버전 검사 (wiki-schema §2.1·§2.2·§7-11):
        #  ⓐ 소스 스텁 "기술 스택" 본문 줄, ⓑ project 허브 tech_stack frontmatter 값에서
        #  major.minor 이상 버전(\d+\.\d+) 발견 시 경고. ".NET 10"·"WinUI 3" 등 major-only는 미매칭(허용).
        if r.startswith("10_sources/"):
            for line in text.splitlines():
                if "기술 스택" in line and re.search(r"\d+\.\d+", line):
                    warn(f"소스 스텁 휘발성 버전 기재: {r} (기술 스택은 이름만, 버전 제외)", r)
                    break
        if typ == "project" and not in_archive:
            ts = fm.get("tech_stack", "")
            if re.search(r"\d+\.\d+", ts):
                warn(f"허브 tech_stack 휘발성 버전 기재: {r} (이름만, 버전 진실원천은 코드)", r)

        # origin/confidence: 화이트리스트 타입만 검사 (type 매칭만으로 수행, 신선도 로직과 무관)
        if typ in ORIGIN_REQUIRED_TYPES and not in_archive:
            for key, vocab in (("origin", ORIGIN_VOCAB), ("confidence", CONFIDENCE_VOCAB)):
                val = fm.get(key)
                if not val:
                    warn(f"{key} 누락: {r} (type={typ})", r)
                elif val not in vocab:
                    errors.append(f"{key} 통제어휘 위반: {r} -> '{val}'")

        # 미래/이상 날짜 + 신선도 (updated 필드 보유 페이지만)
        raw_upd = fm.get("updated", "")
        upd = parse_date(raw_upd) if raw_upd else None
        if raw_upd and upd is None:
            warn(f"updated 형식 이상: {r} -> '{raw_upd}'", r)
        # updated 누락 (§7-9): 필드가 아예 없으면 신선도(§7-3)·미래날짜 검사가 조용히 건너뛰어진다 —
        #  origin/confidence 누락은 WARN인데 updated만 침묵하던 사각을 메운다.
        if typ in UPDATED_REQUIRED_TYPES and not in_archive and not raw_upd:
            warn(f"updated 누락: {r} (type={typ}) — 신선도 추적 불가 (schema §7-9)", r)
        if upd:
            if upd > today and not in_archive:
                # 미래 날짜 ERR도 90_archive/ 제외 — 동결 백업이 exit 1을 유발하지 않게 (§2.8·§8 자동 제외)
                errors.append(f"미래 날짜: {r} updated={upd}")
            # 타입 기반 전체 면제 3종(decision-log·question·convention)의 근거는 FRESHNESS_EXEMPT_TYPES 정의부.
            # status: paused·archived도 전체 면제 — 의도적으로 중단/보관한 frozen 상태라 미편집이 정상 (§8 예외 1)
            # lint 리포트(lint-YYYYMMDD, type: question)도 제외 — 갱신 안 되는 보존 스냅샷이라 90일 후 매 실행
            #   자기 자신을 '아카이브 후보'로 오탐한다(§7-8 고아 제외와 동일 계열, bcc6558 정합).
            #   (타입으로는 question이라 위 집합에도 걸리지만, 파일명 기반 판정이라 별도 절로 남긴다.)
            elif (typ not in INFRA_TYPES and typ not in FRESHNESS_EXEMPT_TYPES
                  and not in_archive
                  and fm.get("status") not in ("paused", "archived") and not is_dep
                  and not is_lint_report(r)):
                days = (today - upd).days
                if days >= 90 and typ not in ARCHIVE_EXEMPT_TYPES:
                    infos.append(f"90일+ 미편집(아카이브 후보): {r} ({days}일)")
                elif days >= 60:
                    stale60.append((days, r))

        # 네이밍 규칙
        base = os.path.basename(r)
        if r.startswith("10_sources/") and not re.fullmatch(r"src-[a-z0-9-]+\.md", base):
            warn(f"네이밍 위반(src-*): {r}", r)
        if typ == "feature" and not re.fullmatch(r"feat-[a-z0-9-]+\.md", base):
            warn(f"네이밍 위반(feat-*): {r}", r)
        if r.startswith("30_knowledge/questions/") and not re.fullmatch(
                r"(q-\d{8}-[a-z0-9-]+|lint-\d{8})\.md", base):
            warn(f"네이밍 위반(q-YYYYMMDD-* / lint-YYYYMMDD): {r}", r)

        # 타입 미지정 (루트 인프라 파일·아카이브 제외)
        if not typ and not is_root and not in_archive:
            warn(f"타입 미지정 파일: {r}", r)

        # 시크릿 의심 스캔 (§7-22) — 전 페이지 본문(frontmatter 제외, 아카이브 포함 — 시크릿은
        #  어디 있든 위험). 코드펜스도 스캔 대상(시크릿이 스니펫 안에 남는 경우가 많음).
        #  키워드+구분자+실값 형태만 매칭하고, 플레이스홀더 표식 줄은 제외해 오탐을 억제한다.
        sec_body = re.sub(r"^---\n.*?\n---", "", text, count=1, flags=re.S)
        fm_lines = text.count("\n") - sec_body.count("\n")  # 본문 시작 줄 오프셋(줄 번호 보고용)
        for li, line in enumerate(sec_body.splitlines(), start=fm_lines + 1):
            for label, rx in SECRET_PATTERNS:
                m2 = rx.search(line)
                if not m2:
                    continue
                # L-6: placeholder 표식을 '줄 전체'가 아니라 '매치된 시크릿 부분'에만 적용한다 —
                #   'password: realSecret  # localhost용'처럼 실값과 예시 표식이 같은 줄에 있어도 실값을
                #   놓치지 않는다(기존엔 줄에 localhost가 있으면 줄 전체를 스킵해 위음성이었음).
                if SECRET_PLACEHOLDER_RX.search(m2.group(0)):
                    continue
                # password/api key 계열은 값이 코드 꼴(변수·함수 호출)이면 제외 (§7-22 보수 정책)
                if label in SECRET_VALUE_FILTER_LABELS and secret_value_is_codey(m2.group(2)):
                    continue
                warn(f"시크릿 의심({label}): {r} L{li} — 실제 값이면 즉시 제거하고 "
                     f"환경변수 이름만 기재 (schema §7-22)", r)
                break  # 같은 줄 다중 라벨 중복 경고 방지

        # (미검증)·미해결 question 집계 (§7-12) — 20_/30_/40_ 본문만(frontmatter 제외),
        # 10_sources(불변 스텁, 검증 루프 대상 아님)·90_archive·루트 인프라는 범위 밖.
        # resolved 판정·lint-* 제외는 §7-23과 공용 헬퍼로 동일 기준(집계↔등록 요구 모순 방지).
        # lint-* 리포트는 (미검증) 표기 집계(ⓐ)에서도 제외 — 리포트가 발견 내역을 원문 인용으로
        # 보존하므로 표기가 본문에 남아 자기참조 오집계가 된다(§7-12).
        if r.startswith(("20_", "30_", "40_")):
            body = re.sub(r"^---\n.*?\n---", "", text, count=1, flags=re.S)
            hits = 0 if is_lint_report(r) else body.count("(미검증)")
            if hits:
                unverified_hits += hits
                unverified_files += 1
            if typ == "question" and not question_is_resolved(fm) and not is_lint_report(r):
                open_questions += 1

            # 릴리즈 마커 (§7-28) — 본문의 vX.Y.Z는 changelog 미러링 신호(§5 금지 형태 — 이력은
            #   레포 git·notes·릴리즈가 정본, 위키 서술은 현재형·이유 중심 §2.3).
            #   제외 타입(RELEASE_MARKER_EXEMPT_TYPES 정의부에 근거)에는 걸지 않는다.
            #   90_archive/·루트 인프라·pending.md는 위 prefix 가드가 이미 배제한다.
            if typ not in RELEASE_MARKER_EXEMPT_TYPES:
                rm_hits = len(RELEASE_MARKER_RX.findall(body))
                if rm_hits:
                    warn(f"릴리즈 마커 {rm_hits}건(§5 changelog 미러링 금지): {r} — "
                         f"버전 서사는 레포 이력에 위임하고 본문은 현재형·이유 중심으로 (schema §7-28)", r)

        # 장식 이모지 스캔 (§7-29) — 20_/30_/40_ 콘텐츠 페이지 산문에 Emoji_Presentation 이모지가 섞이면 WARN.
        #  위키 본문은 평문이 원칙(장식 이모지는 정보가 아니라 소음). 코드펜스·인라인코드는 strip_code로 제외
        #  (코드 스니펫의 이모지는 정당할 수 있음), lint-* 리포트는 자체 심각도 이모지(🔴🟡🔵)를 담으므로
        #  제외(§7-12·§7-28의 lint-* 제외와 동일 계열). 화살표(→)·흑백 기호(⚠★✔)는 EMOJI_RX 정의상 비검출.
        #  타입 제외(EMOJI_EXEMPT_TYPES 정의부에 근거): decision-log는 §2.8 항목 불변이라 수리 불가.
        if r.startswith(("20_", "30_", "40_")) and not is_lint_report(r) and typ not in EMOJI_EXEMPT_TYPES:
            emo_body = strip_code(re.sub(r"^---\n.*?\n---", "", text, count=1, flags=re.S))
            emo_fm_lines = text.count("\n") - emo_body.count("\n")  # 본문 시작 줄 오프셋(줄 번호 보고용, §7-22 방식)
            for eli, eline in enumerate(emo_body.splitlines(), start=emo_fm_lines + 1):
                m3 = EMOJI_RX.search(eline)
                if m3:  # 줄당 첫 매치만 — 한 줄 다중 이모지 중복 경고 방지
                    warn(f"장식 이모지 의심('{m3.group(0)}'): {r} L{eli} — "
                         f"위키 본문은 평문 유지 (schema §7-29)", r)

        # 90_archive/ 하위(백업 사본 포함)는 인덱스 동기 대상이 아님 — §8 "백업 파일이 WARN을 만들지 않는다"
        #  등록처는 타입마다 다르다: feature는 category sub-index, guide는 index-guides 통합 표,
        #  entity는 `## 기술 스택 지식`, concept은 `## 범용 패턴`. 어디에 실리든 인덱스 전체 텍스트
        #  (index.md + sub-index 합산)에서 링크되면 등록으로 본다 — "올바른 등록처인가"까지는 보지
        #  않는다(그건 생성기가 결정론으로 배치한다). 여기서 막는 것은 **어느 인덱스에도 없어 조회
        #  경로 밖에 남는 것**이며, §7-8 고아 검사는 위키 어디서든 링크되면 통과하므로 "인덱스에는
        #  없지만 다른 페이지가 링크한" 상태를 놓친다.
        if not r.startswith("90_archive/"):
            if typ == "feature":
                feat_files.add(r[:-3])
            elif typ in INDEXED_TYPES:
                indexed_files.setdefault(typ, set()).add(r[:-3])

    # index.md: 분할 신호(줄수/행수) + sub-index 목록 정합 + 기능별 인덱스 ↔ feature 동기화
    sub_files = sorted(glob.glob(os.path.join(glob.escape(vault), "index-*.md")))  # L-3: vault만 escape('index-*'의 *는 패턴 유지)
    # M-2 격리 복원: 메인 루프가 읽어 둔 본문을 재사용한다(두 번 읽지 않는다) — 종전에는 여기서
    #   index.md를 예외 처리 없이 다시 열어, CP949로 저장된 index.md 하나가 lint 전체를 traceback으로
    #   죽였다(파일별 격리가 정작 가장 중요한 파일에서만 무력화돼 있었다). pages 멤버십은 부재와
    #   읽기 실패를 구분하지 못하므로, else에서 unreadable로 사유를 갈라 각각 다른 ERR을 낸다
    #   (종전에는 읽기 실패도 "index.md 없음 … 골격 생성 필요"로 오진해 처방이 정반대였다).
    #   BOM은 utf-8-sig로 이미 흡수됐고 개행도 메인 루프가 LF로 정규화했다(534-544행).
    if "index.md" in pages:
        itext = pages["index.md"][2]

        # 미해결 질문 인덱스 동기 (wiki-schema §7-23): open question ↔ index.md '## 미해결 질문'
        #  (비분할 섹션 — 본체 기준 §4, 아래 sub-index 합산 '전'에 검사해야 하므로 이 위치).
        #  섹션 탐색도 strip_code 사본에서 수행해 코드펜스 안 예시 헤딩 오매칭을 막는다.
        #  lint-* 리포트는 질문이 아니라 등록 요구에서 제외(is_lint_report — §7-12 집계와 동일 기준).
        #  질문 '유실'(등록 누락으로 잊힘)과 'stale'(해결됐는데 미해결 목록 잔존)을 기계로 잡는다.
        #  resolved 페이지의 '삭제' 자체는 스냅샷 검사로 탐지 불가 — 삭제 금지는 절차 규칙
        #  (§2.7·SKILL 사전 준수)이 담당한다.
        q_section = section(strip_code(itext), "미해결 질문") or ""
        # 등록 판정: 규약(§3)은 무확장자 경로 링크가 원칙이나, `.md` 포함·파일명만 링크도 등록으로
        #  인정한다 — 그 형식 위반은 §7-1 링크 검사가 별도 보고하므로 여기서 겹치면 '미등록' 오탐.
        q_listed = {t[:-3] if t.endswith(".md") else t for t in wikilink_targets(q_section)}
        for qr, (qfm, qtyp, _) in sorted(pages.items()):
            if qtyp != "question" or qr.startswith("90_archive/"):
                continue
            resolved = question_is_resolved(qfm)
            listed = qr[:-3] in q_listed or os.path.basename(qr)[:-3] in q_listed
            if not resolved and not is_lint_report(qr) and not listed:
                warn(f"미해결 질문 index 미등록: {qr} "
                     f"(유실 위험 — index.md '## 미해결 질문'에 등록, schema §7-23)", qr)
            if resolved and listed:
                warn(f"해결된 질문이 index 미해결 목록에 잔존: {qr} "
                     f"(index에서 제거 — 페이지는 보존, B-2 3-1, schema §7-23)", qr)

        # 분할 신호 (wiki-schema §4) — sub 합치기 전 index.md 본체로 측정
        idx_lines = itext.count("\n") + 1
        #  행수는 증상별 인덱스를 뺀 본문으로 잰다 -- 그 섹션 행은 첫 컬럼이 평문이고 해법
        #  컬럼이 `40_guides/`를 가리켜 is_feat_recipe_row에 걸리는데, 기능 등재가 아니라
        #  증상->해법 매핑이라 분할 판정의 분모가 아니다(§7-6·§7-16이 쓰는 제외와 같은 이유).
        feat_rows = feature_index_rows(without_section(itext, "증상별 인덱스"))
        if idx_lines > INDEX_BODY_LINES or feat_rows > INDEX_FEAT_ROWS:
            infos.append(f"index.md 분할 대상: 본문 {idx_lines}줄(임계 {INDEX_BODY_LINES}), "
                         f"기능별 인덱스 {feat_rows}행(임계 {INDEX_FEAT_ROWS}) — B/F 세션이 "
                         f"주 작업 완료 후 자동 분할(승인 불요, wiki-schema §4 2단계)")

        # sub-index 분할 신호 (§7-14): 각 index-*.md 자체 크기도 측정.
        # sub-index(순번 파일)가 초과하면 순번 파일(index-{cat}-{n}.md)로 자동 분할한다
        # (wiki-schema §4 3단계 — personal/work 종착 분류를 유지한 채 등록 순서로 순번 청크 증분).
        # 본문 줄수는 헤딩과 무관하게, 행수는 sub-index가 보유한 '## 기능별 인덱스' 헤딩 기준으로 측정.
        for sp in sub_files:
            try:
                with open(sp, encoding="utf-8-sig") as sfh:  # M-2/BOM 정합
                    stext = sfh.read()
            except (UnicodeDecodeError, OSError):  # M-2: 비 UTF-8 sub-index 하나로 전체가 죽지 않게
                continue
            s_lines = stext.count("\n") + 1
            s_rows = feature_index_rows(stext)
            if s_lines > INDEX_BODY_LINES or s_rows > INDEX_FEAT_ROWS:
                infos.append(
                    f"{os.path.basename(sp)} 순번 파일 자동 분할 대상: 본문 {s_lines}줄(임계 {INDEX_BODY_LINES}), "
                    f"기능별 인덱스 {s_rows}행(임계 {INDEX_FEAT_ROWS}) — B/F 세션이 순번 파일"
                    f"(index-{{cat}}-{{n}}.md)로 자동 분할(승인 불요, wiki-schema §4 3단계)")

        # sub-index 목록 정합: 실재하는 index-*.md가 index.md에 언급(등록)됐는지.
        #  A(실재 파일) − B(index.md 언급) = 미등록 → WARN. 역방향(언급은 있으나 파일 없음)은
        #  wikilink면 위 깨진/경로없음 검사가 이미 잡으므로 신규 WARN을 내지 않는다(중복·모순 차단).
        # 순번 sub-index(index-work-1 등)의 '-\d+' suffix까지 stem으로 포착한다(비캡처 그룹 —
        #  findall이 전체 매치를 반환해 '-1'이 잘려 index-work로만 잡히던 §7-15 오탐 제거).
        #  무순번 index-personal도 그대로 매치돼 회귀 없음(wiki-schema §4 3단계).
        mentioned = set(re.findall(r"index-[a-z]+(?:-\d+)?", itext))
        for sp in sub_files:
            stem = os.path.basename(sp)[:-3]  # 예: 'index-personal'
            if stem not in mentioned:
                warn(f"sub-index 미등록: {stem}.md가 index.md 목록에 없음(절차 K·검색 누락 위험)")

        # 인덱스가 sub-index로 분할된 경우 그 내용도 합쳐서 동기화 검사 (분할 시 누락 오탐 방지)
        for sub in sub_files:
            try:
                with open(sub, encoding="utf-8-sig") as sfh:  # M-2/BOM 정합
                    itext += "\n" + sfh.read()
            except (UnicodeDecodeError, OSError):  # M-2: 비 UTF-8 sub-index 하나로 전체가 죽지 않게
                pass
        # 증상별 인덱스(§6)는 행 형상이 기능별 인덱스와 겹치나 의미가 달라 등록(§7-6)·한/영(§7-16)
        #  검사에서 제외한다(증상 행이 feature를 '등록됨'으로 마스킹하거나, 증상 관찰 표현에 한/영을
        #  요구하는 오탐 방지). 깨진 링크는 §7-1이 전 페이지에서 잡으므로 이 제외로 놓치지 않는다.
        itext_feat = without_section(itext, "증상별 인덱스")
        # 코드펜스/인라인코드 제외 후 feature 링크 추출 — wikilink_targets(메인 루프 파싱과 공용)
        for t in wikilink_targets(itext_feat):
            if "/feat-" in t:
                # M-3: '.md' 확장자를 벗겨 feat_files(무확장)와 동일 형태로 맞춘다 —
                #   '[[…/feat-x.md]]' 링크를 '인덱스 누락'으로 오판하지 않게(깨진링크·고아와 함께 3중 오탐 제거).
                index_feat_links.add(t[:-3] if t.endswith(".md") else t)
        for f in sorted(feat_files - index_feat_links):
            warn(f"기능별 인덱스 누락: {f} (feature인데 index 미등록)", f)

        # 인덱스 등록 (§7-30 ⓒ): guide·entity·concept이 어느 인덱스에도 안 실렸는가.
        #  §7-6이 feature에 하는 일을 나머지 타입으로 넓힌 것이다 — 종전에는 이 셋에 대응 검사가
        #  없어, 분할·신설한 페이지가 등록에서 빠져도 기계가 침묵했다(§7-8 고아 검사는 위키 어디서든
        #  링크되면 통과하므로 "인덱스 밖" 상태를 잡지 못한다). 증상별 인덱스 제외본(itext_feat)을
        #  쓰는 이유는 §7-6과 같다 — 증상 행의 해법 링크가 그 페이지를 "등록됨"으로 마스킹한다.
        idx_links = {t[:-3] if t.endswith(".md") else t for t in wikilink_targets(itext_feat)}
        for typ_name in sorted(indexed_files):
            for f in sorted(indexed_files[typ_name] - idx_links):
                warn(f"인덱스 등록 누락: {f} ({typ_name}인데 index·sub-index 어디에도 미등록 "
                     f"— 조회 경로 밖, wiki-schema §7-30)", f)

        # 한/영 양방향 병기: 기능별 인덱스 유형 행(is_feat_recipe_row — 형상+대상 기반, alias 무관)의
        #  첫 컬럼(기능명)에 한글·영문 중 한쪽만 있으면 WARN. 한글 등록이든 영문 등록이든 양방향
        #  검색이 되게(wiki-schema §3·§7-16). 스캔은 sub-index까지 합친 itext 전체 — `## ` 소분할
        #  뒤의 행도 누락하지 않는다(§4 보증). 이름 추출은 feat_row_name이 형상별로 처리한다 --
        #  통합 표는 첫 컬럼 평문, 옛 `## 가이드 / 레시피` 섹션은 첫 컬럼 wikilink의 alias.
        han, lat = re.compile(r"[가-힣]"), re.compile(r"[A-Za-z]")
        for line in itext_feat.splitlines():   # 증상별 인덱스 섹션 제외본(위 §7-6) — 증상 관찰 표현 오탐 차단
            name = feat_row_name(line)
            if name is None:
                continue
            has_h, has_l = bool(han.search(name)), bool(lat.search(name))
            if has_h != has_l:
                warn(f"한/영 병기 누락: '{name}' ({'한글만' if has_h else '영문만'} — 양방향 검색 위해 한글·영문 모두 병기)")

        # 「가이드/레시피 섹션 가이드 행 병기」 검사는 **폐지**됐다 -- 위 병기 검사에 흡수.
        #  그 검사가 있던 이유는 `## 가이드 / 레시피` 섹션 행의 첫 컬럼이 wikilink라
        #  종전 판정(첫 컬럼 평문)이 형상 자체로 놓친다는 것이었는데, 그 섹션이 통합 표
        #  (index-guides.md, 첫 컬럼 평문)로 대체되고 대상 조건이 `40_guides/` 전체로 넓어졌으며,
        #  **옛 섹션 형상도 feat_row_name 조건 ②가 함께 받으므로** 위 검사 하나가 신·구 양쪽
        #  전 행을 본다 — 마커 없는 vault가 옛 섹션을 유지해도 무신호 구간이 생기지 않는다.
        #  폐지 이력은 wiki-schema §7 목록에 남긴다.

    elif "index.md" in unreadable:
        # 파일은 실재하는데 못 읽은 경우 — 처방이 부재와 정반대라(골격 생성 ✗ / 인코딩 복구 ✓)
        #  같은 ERR을 쓰면 실재하는 인덱스를 덮어쓰도록 지시하게 된다.
        errors.append("index.md 읽기 실패: 인덱스 기반 검사(§7-6·14·15·16·23)를 건너뜀 — "
                      "파일은 실재하므로 골격 생성이 아니라 인코딩 복구가 필요 "
                      "(위 '파일 읽기 실패' 참조)")
    else:
        # 인덱스 기반 검사(§7-6·14·15·16·23) 전체가 불능인 구조 결함 — 침묵 대신 ERR 1건으로 신호
        #  (특히 §7-23은 index.md가 없으면 '질문 유실' 최악 시나리오를 못 잡는다).
        errors.append("index.md 없음: vault 루트에 index.md가 없어 인덱스 기반 검사"
                      "(§7-6·14·15·16·23)를 건너뜀 — 카탈로그 골격 생성 필요 (schema §4)")

    # log 아카이브 인덱스 정합 (wiki-schema §7-19): log.md '## 아카이브 인덱스'에 등록된
    #  {YYYY-MM}.md ↔ 실재 90_archive/log/{YYYY-MM}.md 양방향 대조. sub-index 정합(위)과 유사하나
    #  양방향 — 아카이브 인덱스 항목은 wikilink가 아니라, 역방향(파일 있으나 미등록)이 깨진링크
    #  검사로 안 잡히므로 양쪽 다 WARN(검색 누락·깨진 참조 방지).
    if "log.md" in pages:
        log_text = pages["log.md"][2]
        sec = section(log_text, "아카이브 인덱스")
        indexed = set(re.findall(r"(\d{4}-\d{2})\.md", sec)) if sec else set()
        archived = set()
        for p in md:
            am = re.fullmatch(r"90_archive/log/(\d{4}-\d{2})\.md", rel(p))
            if am:
                archived.add(am.group(1))
        for ym in sorted(archived - indexed):
            warn(f"log 아카이브 미등록: 90_archive/log/{ym}.md가 log.md '## 아카이브 인덱스'에 없음(검색 누락 위험)",
                 f"90_archive/log/{ym}.md")
        for ym in sorted(indexed - archived):
            warn(f"log 아카이브 인덱스 깨짐: log.md가 {ym}.md를 가리키나 90_archive/log/{ym}.md 없음",
                 f"90_archive/log/{ym}.md")

    # pending.md 미처리 잔량 집계 (절차 K 큐 — SKILL K-5/K 5-1/K 5-2/K 5-3/K 5-4/K 5-5/B-1 0): 잔량이 있으면 INFO로 알려
    #  다음 소비 세션이 소비하게 한다 (0건·파일 없음이면 생략). 소비 주체는 ingest/lint 세션이고,
    #  [DECISION]·[PROJECT-FACT] 둘은 implement-task F-6.5의 큐 자동 소비(절차 M 자동 경로)도 소비 주체다
    #  — 자동 소비는 그 세션 대상 프로젝트분만 닿으므로 이 INFO가 0이 되지 않는 것은 정상. 태그별 분리 —
    #  [K-DRIFT]는 위키 세션이 반영 후 제거,
    #  [DECISION]은 해당 프로젝트 decisions.md에 추가 후 제거(자가 소비),
    #  [PROJECT-FACT]는 해당 프로젝트 conventions.md(§2.9)에 반영 후 제거(자가 소비),
    #  [K-MISS]는 레포 근거 대조 후 feature/recipe 반영 또는 기각 보고 후 제거(수요 신호 — 자동 생성 아님),
    #  [SYMPTOM]은 증상별 인덱스(§6)에 등재 게이트 검증 후 반영 또는 보류(해법 페이지 부재)·기각(미검증 원인) 후 제거.
    #  (보고됨 ...) 표식 줄도 잔량이므로 집계에 포함.
    if "pending.md" in pages:
        pend_text = pages["pending.md"][2]
        # 태그 목록은 아래 잔량 집계와 형식 위반 검사가 공유한다 — 한쪽만 태그를 추가하면
        #  새 태그가 집계되지 않거나 위반 검출에서 빠져 조용히 사각지대가 생긴다(단일 출처).
        pend_tags = (("K-DRIFT", "K-DRIFT {n}건"),
                     ("DECISION", "DECISION {n}건(결정 이력 — ingest는 대상 프로젝트 즉시·타 프로젝트 동의 소비, lint는 F-2 승인 시 소비, implement-task F-6.5는 대상 프로젝트분 자동 소비)"),
                     ("PROJECT-FACT", "PROJECT-FACT {n}건(프로젝트 작업 사실 — conventions.md 반영 대상(§2.9), 소비 주체·게이트는 DECISION 동형)"),
                     ("K-MISS", "K-MISS {n}건(참조 미스 = 수요 신호 — ingest에서 feature/recipe 반영·기각 판정)"),
                     ("SYMPTOM", "SYMPTOM {n}건(증상→검증된 원인→해법 — 증상별 인덱스 §6 반영, 게이트 미충족 시 보류)"))
        parts = []
        for tag, label in pend_tags:
            n = sum(1 for line in pend_text.splitlines()
                    if re.match(r"^\s*-\s*\[\d{4}-\d{2}-\d{2}\]\s*\[" + tag + r"\]", line))
            if n:
                parts.append(label.format(n=n))
        if parts:
            infos.append("pending.md 미처리 잔량 — " + " / ".join(parts)
                         + " — ingest(절차 B-1 0) 또는 lint(F-0 보고 후 F-2 승인 시)에서 소비")

        # 형식 위반 검출 (§7-25): 위 집계는 날짜 선두를 요구하므로, 태그는 있으나 그 형식이
        #  아닌 줄은 **어느 태그에도 안 잡히고 버려진다** — 큐가 쌓여 있어도 잔량 0으로 보고돼
        #  "0건"과 "형식이 틀려 못 셈"이 구분되지 않는다(실측: 17줄이 0건으로 집계된 사례).
        #  집계 숫자의 신뢰성 문제라 INFO가 아니라 WARN이다.
        # **선두 태그만 본다 (본문 언급 오탐 차단)**: 종전엔 줄 어디에든 태그가 있으면(search)
        #  위반 후보로 삼았는데, 그러면 **선두 태그가 이 파일 소관이 아닌 줄**이 본문에 소관 태그를
        #  언급했을 때 오탐한다 — 실제로 큐 분리 직후 `- [날짜] [SKILL-IMPROVE] … `[PROJECT-FACT]` 큐에…`
        #  1줄이 pending.md에서 형식 위반으로 잡혔다(선두는 집합 밖, 본문은 집합 안). 아래처럼
        #  **불릿 직후의 태그**를 잡고 그 앞의 날짜 유무로 판정하면 본문 언급은 애초에 매치되지 않는다.
        #  **접두를 15자로 제한하는 것이 본문 언급과 선두 위치를 가르는 축이다.** 정상 접두
        #  `[YYYY-MM-DD] `가 13자이고 위반 형태(날짜 누락·형식 불일치·대괄호 없음)도 그보다 짧은데,
        #  본문에 태그를 언급하는 줄은 접두가 수십 자라 이 제한에 걸려 애초에 매치되지 않는다.
        #  **접두를 날짜 형식으로 좁히면 안 된다** — `[2026-7-2]`·대괄호 없는 날짜처럼 **집계
        #  정규식에도 안 잡히는 줄**(이 WARN이 존재하는 이유의 정중앙)이 미검출로 새어 나간다.
        #  **수용된 한계**: 접두가 15자를 넘는 위반(`- [2026-07-02 재확] [TAG]`·`- (보류) 2026-07-02 [TAG]`)은
        #  미검출로 남는다. 본문 언급과 접두 길이가 같은 축이라 **이 방식으로는 원리상 분리되지 않는다** —
        #  대안("불릿 직후 첫 대괄호 토큰")은 그 형태를 회복하는 대신 `- 2026-07-02 [TAG]`(대괄호 없는 날짜)를
        #  잃어 우월하지 않다(F-7 2R 실측). 둘 다 덮으려면 두 축의 OR가 필요하다.
        pend_lead_rx = re.compile(r"^\s*-\s*(.{0,15}?)\[("
                                  + "|".join(t for t, _ in pend_tags) + r")\]")
        #  공백 폭을 `\s*`로 둔 이유는 종전과 같다 — `-[TAG]`처럼 대시 뒤 공백이 없는 줄도
        #  위반으로 잡아야 이 검사가 없애려던 사각지대가 남지 않는다.
        malformed = sum(1 for line in pend_text.splitlines()
                        if (m := pend_lead_rx.match(line)) and not QUEUE_DATE_PREFIX_RX.match(m.group(1)))
        if malformed:
            warn(f"pending.md 형식 위반 {malformed}건 — 태그는 있으나 '- [YYYY-MM-DD] [TAG]' 선두 형식이 "
                 f"아니라 위 잔량 집계에서 누락됨(K 5 큐 형식 규약, 정규화 필요)", "pending.md")

    # skill-feedback.md 미처리 잔량 집계 (§7-25 — [SKILL-IMPROVE] 전용 큐, SKILL K 5-1)
    #  위 pending.md 블록과 같은 형식·같은 두 검사(잔량 INFO + 형식 위반 WARN)를 쓰되 **파일을
    #  나눠 각각 처리**한다 — 태그를 한 튜플에 합치면 어느 파일이 밀렸는지가 INFO 한 줄에 뭉개지고,
    #  두 큐는 소비 주체가 다르다(pending은 위키 세션이 반영 후 제거, 이쪽은 사용자에게 보고만 하고
    #  제거는 지시가 있을 때만 — B-1 0). **INFO를 별도 줄로 내는 것은 골든 무회귀 요건이기도 하다**:
    #  기존 케이스가 "pending.md 미처리 잔량" 문자열을 고정하고 있어 한 줄로 합치면 깨진다.
    if "skill-feedback.md" in pages:
        fb_text = pages["skill-feedback.md"][2]
        # 태그 목록은 아래 잔량 집계와 형식 위반 검사가 공유한다(pending 블록과 동일 구조 —
        #  한쪽만 태그를 추가하면 조용한 사각지대가 생긴다).
        fb_tags = (("SKILL-IMPROVE", "SKILL-IMPROVE {n}건(플러그인 개선 후보 — 사용자 보고 대상, 제거는 사용자 지시 시)"),)
        parts = []
        for tag, label in fb_tags:
            n = sum(1 for line in fb_text.splitlines()
                    if re.match(r"^\s*-\s*\[\d{4}-\d{2}-\d{2}\]\s*\[" + tag + r"\]", line))
            if n:
                parts.append(label.format(n=n))
        if parts:
            infos.append("skill-feedback.md 미처리 잔량 — " + " / ".join(parts)
                         + " — 하네스 레포 세션(plan-feature Step 1)이 할 일 후보로 조회, "
                           "lint는 F-0 보고 후 F-2 승인 시 소비")

        # 선두 태그만 본다 — pending 블록과 동일 구조(접두 15자 제한·날짜 형식 판정, 위 주석이 근거).
        fb_lead_rx = re.compile(r"^\s*-\s*(.{0,15}?)\[("
                                + "|".join(t for t, _ in fb_tags) + r")\]")
        fb_malformed = sum(1 for line in fb_text.splitlines()
                           if (m := fb_lead_rx.match(line)) and not QUEUE_DATE_PREFIX_RX.match(m.group(1)))
        if fb_malformed:
            warn(f"skill-feedback.md 형식 위반 {fb_malformed}건 — 태그는 있으나 '- [YYYY-MM-DD] [TAG]' 선두 형식이 "
                 f"아니라 위 잔량 집계에서 누락됨(K 5-1 큐 형식 규약, 정규화 필요)", "skill-feedback.md")

    # decision-log 정합 (§7-24): ⓐ '## 아카이브' 포인터 ↔ 실파일 양방향 ⓑ 항목 결정 어휘.
    #  포인터는 wikilink가 아닌 평문 경로라 §7-1 깨진 링크 검사에 안 잡힘 — 누락·오기 시
    #  조회(K 2·G 2b)가 현행 파일만 읽고 "기록 없음"으로 침묵 오답하므로 기계 검사한다.
    dec_ptr_rx = DEC_PTR_RX   # 패턴 단일 출처(모듈 상수) — apply_fixes와 동일 대상 보장
    dec_item_rx = re.compile(r"^-\s*\[\d{4}-\d{2}-\d{2}\]")
    dec_vocab_rx = re.compile(r"\*\*(" + "|".join(DECISION_VOCAB) + r")\*\*")
    for r, (fm, typ, text) in pages.items():
        if typ != "decision-log" or r.startswith("90_archive/"):
            continue
        # ⓐ-정방향: 포인터가 가리키는 아카이브 파일 실재
        for m in dec_ptr_rx.finditer(text):
            if m.group(1) not in pages:
                warn(f"decisions 아카이브 포인터 깨짐: {r} -> {m.group(1)} 없음 (wiki-schema §2.8)", r)
        # ⓑ 항목 결정 어휘 (하위 불릿은 들여쓰기라 ^- 매치에서 자연 제외)
        bad = sum(1 for ln in text.splitlines()
                  if dec_item_rx.match(ln) and not dec_vocab_rx.search(ln))
        if bad:
            warn(f"decision-log 어휘 위반: {r} {bad}건 (고정 어휘 채택|보류|기각|번복 — wiki-schema §2.8)", r)
    # ⓐ-역방향: 롤오버 아카이브가 실재하는데 대응 현행 파일에 포인터 미등재 (검색 유실).
    #  대응 현행 파일 자체가 없으면 절차 C 보존-삭제 이력이므로 건너뜀(§7-24).
    for r in pages:
        if not (r.startswith("90_archive/") and r.endswith("decisions.md")):
            continue
        cur = r[len("90_archive/"):]
        if cur in pages and r not in pages[cur][2]:
            warn(f"decisions 아카이브 포인터 누락: {cur}의 '## 아카이브'에 {r} 미등재 "
                 f"— 오래된 결정이 검색에서 유실 (wiki-schema §2.8)", cur)

    # 이동·분리한 내용의 도달 경로 정합 (§7-30): ⓐ 허브 '## 아카이브' 포인터 ↔ changes.md 양방향
    #  ⓑ conventions.md '## 하위 문서' 목록 ↔ 하위 파일 양방향. 둘 다 "옮긴 자리를 읽는 경로"를 검사한다 —
    #  §2.2 롤오버·§2.9 하위 분리는 압축을 없앤 대가로 도달 경로에 의존하므로, 그 경로가 깨지면
    #  이동이 곧 유실이 된다(§7-24 decisions 포인터·§7-15 sub-index 목록·§7-19 log 인덱스와 동일 계열).
    #  --fix 대상은 아니다 — §7 서두가 --fix를 참조 무결성 3종으로 한정한다.
    for r, (fm, typ, text) in pages.items():
        if typ != "project" or r.startswith("90_archive/"):
            continue
        # ⓐ-정방향: 허브 포인터가 가리키는 changes 아카이브 실재
        for m in CHG_PTR_RX.finditer(text):
            if m.group(1) not in pages:
                warn(f"변경 이력 아카이브 포인터 깨짐: {r} -> {m.group(1)} 없음 (wiki-schema §2.2·§8)", r)
        # §7-31: 허브에 '## 작업 규약·주의사항' 잔존 = conventions.md 미마이그레이션 신호.
        #  INFO 고정 — 사용자가 점진 마이그레이션을 택했고(각 프로젝트 ingest 때 적용) WARN이면
        #  미마이그레이션 허브 전부가 매 lint마다 경고를 낸다. exit code 불변.
        if section(text, "작업 규약·주의사항"):
            infos.append(f"작업 규약 미마이그레이션: {r}의 '## 작업 규약·주의사항'을 "
                         f"conventions.md로 이전 대상 (wiki-schema §2.9 — 다음 ingest에서 처리)")
    # ⓐ-역방향: changes 아카이브가 실재하는데 대응 현행 허브에 포인터 미등재 (검색 유실).
    #  경로 도출이 §7-24와 다르다 — decisions는 아카이브·현행이 같은 파일명이라 접두만 떼면 되지만,
    #  changes는 '90_archive/20_projects/{cat}/{proj}/changes.md' → 현행 허브 '20_projects/{cat}/{proj}.md'로
    #  폴더가 파일이 된다. 대응 허브가 없으면 절차 C 보존-삭제 이력이므로 건너뛴다(§7-24 동형 —
    #  없으면 삭제된 프로젝트의 아카이브가 영구 WARN이 된다).
    for r in pages:
        if not (r.startswith("90_archive/") and r.endswith("/changes.md")):
            continue
        hub = r[len("90_archive/"):-len("/changes.md")] + ".md"
        if hub in pages and r not in pages[hub][2]:
            warn(f"변경 이력 아카이브 포인터 누락: {hub}의 '## 아카이브'에 {r} 미등재 "
                 f"— 롤오버한 변경 이력이 검색에서 유실 (wiki-schema §2.2·§8)", hub)
    # ⓑ conventions '## 하위 문서' 목록 ↔ 하위 파일 양방향.
    #  wikilink(무확장자)·평문 경로 둘 다 인정한다 — §7-24 포인터가 평문, §7-15 목록이 파일명 언급
    #  기준인 두 선례를 모두 수용(형식 위반은 §7-1 링크 검사가 별도로 본다).
    #  본체 문자 클래스에서 `.`·`\`를 배제한다 — 배제하지 않으면 Obsidian 표의 이스케이프 파이프
    #  (`conventions-git.md\|`)에서 `.md\`가 본체로 흡수돼 코드가 다시 '.md'를 붙여 실재하지 않는
    #  경로를 만들고, 정상 등재 항목을 "목록 깨짐"으로 오탐한다. 확장자는 `(?:\.md)?`가 담당하고
    #  주제명은 네이밍 규약상 영문소문자·하이픈뿐(§3)이라 본체에 `.`이 올 일이 없다.
    sub_conv_rx = re.compile(r"(20_projects/[^\s`()|\]\\.]+/conventions-[^\s`()|\]\\.]+?)(?:\.md)?(?=[\s`()|\]\\.]|$)")
    for r, (fm, typ, text) in pages.items():
        if typ != "convention" or r.startswith("90_archive/"):
            continue
        if os.path.basename(r) != "conventions.md":
            continue          # 하위 파일(conventions-*.md) 자신은 목록 보유 대상이 아니다
        listed = {m.group(1) + ".md" for m in sub_conv_rx.finditer(section(text, "하위 문서") or "")}
        for t in sorted(listed):
            if t not in pages:
                warn(f"규약 하위 문서 목록 깨짐: {r} -> {t} 없음 (wiki-schema §2.9)", r)
        prefix = r[:-len("conventions.md")] + "conventions-"
        for other in sorted(pages):
            if other.startswith(prefix) and other.endswith(".md") and other not in listed:
                warn(f"규약 하위 문서 목록 누락: {r}의 '## 하위 문서'에 {other} 미등재 "
                     f"— 분리한 규약이 조회 경로 밖(조회 홉 1 위반, wiki-schema §2.9)", r)

    # ⓓ guide 허브 `## 하위 문서` 목록 ↔ 하위 파일 양방향.
    #  convention과 달리 guide에는 `conventions-{주제}.md` 같은 **파일명 접두 규약이 없다** —
    #  같은 폴더·같은 guide_kind만으로 하위를 특정하면 서로 무관한 독립 가이드끼리 하위로 잡힌다
    #  (실측: `40_guides/ui-ux/`에 분할 하위 2개와 무관한 가이드 1개가 함께 있다).
    #  그래서 **하위→허브 역링크**를 신호로 쓴다 — §2.6이 "하위 문서는 상단에 허브 복귀 링크"를
    #  규정하므로, 그 링크를 가진 같은 폴더 guide만 하위 후보다. 독립 가이드는 대개 그 링크가
    #  없어 후보에 들지 않는다(실 vault 399파일에서 신규 WARN 0).
    #  **판정은 링크의 위치를 가리지 않는다** — 본문 어디서든 허브를 가리키면 후보다. §2.6은
    #  "상단"을 규정하지만 상단의 경계(첫 `## ` 이전? N줄?)를 정의하지 않아, 그 선을 여기서
    #  지어내면 규정에 없는 기준으로 미탐이 생긴다. 대가는 **같은 폴더의 독립 가이드가 허브를
    #  단순 참조하면 후보로 잡히는 것**이고, 그때 나오는 WARN의 처방(목록에 올리거나 참조를
    #  떼거나)은 어느 쪽도 파괴적이지 않다 — 미탐(하위가 목록 밖에 남는 것)이 더 비싸다.
    #  허브는 `## 하위 문서` 섹션 보유로 식별한다(파일명 고정이 아니므로 섹션 존재가 유일한
    #  구조 신호다).
    #  폴더별 guide 인덱스를 미리 만든다 — 허브마다 전체 pages(실측 399개)를 훑으면
    #  O(허브 x 전체 페이지)가 되는데, 후보는 애초에 같은 폴더 guide뿐이다.
    guides_by_folder = {}
    for gr, (gfm, gtyp, gtext) in pages.items():
        if gtyp == "guide" and not gr.startswith("90_archive/"):
            guides_by_folder.setdefault(os.path.dirname(gr), []).append(gr)
    guide_hubs = {r for r, (fm, typ, text) in pages.items()
                  if typ == "guide" and not r.startswith("90_archive/")
                  and section(text, "하위 문서")}
    for hub in sorted(guide_hubs):
        listed = {t[:-3] if t.endswith(".md") else t
                  for t in wikilink_targets(section(pages[hub][2], "하위 문서") or "")}
        for t in sorted(listed):
            if t + ".md" not in pages:
                warn(f"가이드 하위 문서 목록 깨짐: {hub} -> {t} 없음 (wiki-schema §2.6)", hub)
        # 역방향: 이 허브를 복귀 링크한 같은 폴더 guide가 목록에 있는가
        folder = os.path.dirname(hub)
        hub_stem = hub[:-3]
        for other in sorted(guides_by_folder.get(folder, [])):
            if other == hub or other in guide_hubs:
                continue        # 자기 자신·다른 허브는 하위가 아니다
            back = {x[:-3] if x.endswith(".md") else x for x in wikilink_targets(pages[other][2])}
            if hub_stem in back and other[:-3] not in listed:
                warn(f"가이드 하위 문서 목록 누락: {hub}의 '## 하위 문서'에 {other} 미등재 "
                     f"— 이 허브를 가리키는 링크는 있는데 목록에 없어 조회 홉 1이 깨진다 "
                     f"(하위가 아니라 단순 참조면 그 링크를 떼거나 목록에 올린다, wiki-schema §2.6)", hub)

    # 허브 "기능 목록" ↔ feature 동기화 (feat 파일이 허브 본문에 링크돼 있는지)
    # 90_archive/ 하위 허브 사본(백업)은 검사 제외 — §8 "백업 파일이 WARN을 만들지 않는다"
    for r, (fm, typ, text) in pages.items():
        if typ != "project" or r.startswith("90_archive/"):
            continue
        hub_base = r[:-3]
        hub_text = text.replace("\\", "")
        for f in sorted(feat_files):
            # L-4: 부분문자열 매칭은 'feat-a'가 링크 'feat-a-extended'에 substring으로 포함되면 누락을
            #   못 잡는다(위음성) → 경로 뒤에 단어문자·하이픈이 없어야 진짜 등록으로 본다(.md 확장자는 허용).
            if f.startswith(hub_base + "/") and not re.search(re.escape(f) + r"(?![\w-])", hub_text):
                warn(f"허브 기능 목록 누락: {r} -> {f}", r)

    # feature 각주 경로 레포 실존 (wiki-schema §7-20) + '## 관련 파일' 섹션 게이트/경로 실존 (§7-21):
    #  §7-20 — feature의 [^src-...] 각주 정의 줄에 백틱으로 병기된 레포 상대경로가, 프로젝트 허브
    #  '## 레포 정보 > 경로'의 레포에 실재하는지 확인. §7-21 — '## 관련 파일' 섹션(기능 구성 파일
    #  지도, §2.3)이 없거나 경로 항목 0개면 WARN, 섹션 내 경로 토큰은 §7-20과 동일 로직으로 실존 확인.
    #  lint은 파일 '실존'만 보고 코드 내용은 해석하지 않는다(서술↔코드 정합은 §7-10 에이전트 표본).
    #  허브에 레포 경로가 없거나 디렉터리가 부재(다른 PC 등)면 프로젝트 단위 INFO 1건 후 건너뛴다
    #  (그 프로젝트의 ① 경로 실재 확인은 §7-10 에이전트가 폴백 수행).
    repo_cache = {}  # 허브 rel 경로 -> 레포 루트(str) 또는 None(접근 불가)
    exists_cache = {}  # (root, 상대경로) -> 실존 여부 — 여러 feature가 같은 경로를 병기할 때 중복 IO 제거
    for r, (fm, typ, text) in sorted(pages.items()):
        if typ != "feature" or r.startswith("90_archive/"):
            continue
        if (fm.get("status") == "deprecated") or bool(fm.get("deprecated")):
            continue  # deprecated는 frozen 이력 — 경로가 이미 제거된 게 정상 (§7-18과 동일 제외)
        # 각주 정의 줄 판별은 strip_code 사본으로(코드펜스 안 유사 줄 제외 — 줄 구조 보존),
        #  백틱 토큰 추출은 원문 줄에서(strip_code는 인라인코드를 공백화해 토큰이 사라지므로).
        raw_lines = text.splitlines()
        stripped_lines = strip_code(text).splitlines()
        tokens = []
        for i, sl in enumerate(stripped_lines):
            if not sl.lstrip().startswith("[^src-"):
                continue
            # 디렉터리 구분자 포함 토큰만 경로 후보 — 무구분자(`MainViewModel.LoadAsync` 등
            #  클래스·멤버명)는 오탐 방지 위해 제외 (plan D2)
            tokens += [t for t in re.findall(r"`([^`\n]+)`", raw_lines[i])
                       if "/" in t or "\\" in t]
        # §7-21: '## 관련 파일' 섹션 판별(strip_code 사본 — 코드펜스 안 유사 헤딩 제외) +
        #  섹션 내 '- ' 항목의 백틱 경로 토큰 수집(원문 줄에서).
        rel_tokens, rel_section_found = [], False
        in_rel = False
        for i, sl in enumerate(stripped_lines):
            s = sl.strip()
            if re.match(r"^##\s*관련 파일\b", s):
                rel_section_found = True
                in_rel = True
                continue
            if in_rel and s.startswith("## "):
                in_rel = False
            if in_rel and s.startswith("-"):
                rel_tokens += [t for t in re.findall(r"`([^`\n]+)`", raw_lines[i])
                               if "/" in t or "\\" in t]
        # 문구로 원인을 구분한다 — "섹션 자체 없음"과 "섹션은 있으나 백틱 경로 0개"(형식 누락:
        #  백틱 미사용·구분자 없는 토큰만 있는 경우)는 수리 방법이 달라 진단 단계를 줄인다.
        if not rel_section_found:
            warn(f"관련 파일 섹션 누락: {r} "
                 f"('## 관련 파일' 기능 구성 파일 지도 — 다음 ingest 시 채움, schema §7-21)", r)
        elif not rel_tokens:
            warn(f"관련 파일 경로 항목 0개: {r} "
                 f"(섹션은 있으나 백틱 경로 없음 — '- `경로` — 역할' 형식으로 기재, schema §7-21)", r)
        if not tokens and not rel_tokens:
            continue
        hub = r.rsplit("/", 1)[0] + ".md"  # 20_projects/{proj}/feat-x.md -> 20_projects/{proj}.md
        if hub not in repo_cache:
            hub_text = pages[hub][2] if hub in pages else ""
            repo_cache[hub] = repo_root_for_hub(hub_text) if hub_text else None
            if repo_cache[hub] is None:
                infos.append(f"레포 접근 불가(허브 레포 경로 미기재/부재): {hub} "
                             f"— 각주·관련 파일 경로 검증 건너뜀(§7-10 에이전트 폴백, schema §7-20·21)")
        root = repo_cache[hub]
        if root is None:
            continue
        # §7-20(각주)·§7-21(관련 파일)을 같은 실존 로직으로 검사하되 출처를 메시지에 구분
        for token_list, label, sec in ((tokens, "각주 경로", "§7-20"),
                                       (rel_tokens, "관련 파일 경로", "§7-21")):
            for t in token_list:
                p = t.replace("\\", "/").strip()
                if p.startswith("./"):
                    p = p[2:]
                if os.path.isabs(p) or re.match(r"^[A-Za-z]:", p):
                    continue  # 레포 '상대'경로만 검사 대상 — 절대경로 병기는 규약 밖이라 제외
                full = os.path.join(root, p)
                key = (root, p)
                if key not in exists_cache:  # 실행-내 memoization (한 실행 중 파일시스템 불변 전제)
                    # 글롭 분기는 레포 루트를 이스케이프한다(L-3의 vault escape와 동형) — 루트 경로에
                    #   [ ] 등 메타문자가 있으면 글롭 토큰이 항상 매치 0건이 되어 실재 경로를 오탐한다.
                    #   토큰 p 안의 글롭(*)은 패턴으로 유지.
                    exists_cache[key] = (bool(glob.glob(os.path.join(glob.escape(root), p)))
                                         if "*" in p else os.path.exists(full))
                if not exists_cache[key]:
                    detail = "글롭 매치 0건 — 이동·삭제·오기 가능" if "*" in p \
                        else "이동·삭제·오기 가능 — 갱신 필요"
                    warn(f"{label} 레포에 없음: {r} -> '{t}' ({detail}, schema {sec})", r)

    # 위키 뒤처짐 (wiki-schema §7-26): 허브 synced_commit(§2.2) 이후 레포에 쌓인 커밋 수를 센다.
    #  updated(§7-3 신선도)는 "언제 손댔나"라서, 날짜만 갱신되고 내용이 레포를 못 따라온 상태를
    #  그대로 통과시킨다 — 그 사각을 이 검사가 메운다("어디까지 담았나").
    #  전부 INFO다: 커밋 수 임계는 프로젝트 커밋 빈도에 따라 의미가 달라 근거 없는 상수가 되므로
    #  신선도와 같이 "후보 제시"에 머문다(exit code 불변). 접근 불가는 조용히 skip(fail-open).
    for r, (fm, typ, text) in sorted(pages.items()):
        if typ != "project" or r.startswith("90_archive/"):
            continue
        synced = str(fm.get("synced_commit", "")).strip()
        if not synced:
            infos.append(f"동기 기준점 미설정: {r} — synced_commit 없음 "
                         f"(다음 ingest에서 기록, schema §2.2·§7-26)")
            continue
        root = repo_root_for_hub(text)
        if root is None or not os.path.isdir(os.path.join(root, ".git")):
            continue  # 레포 경로 부재·git 아님 → 조용히 skip (fail-open — 다른 PC·비 git 레포)
        behind = git_commits_behind(root, synced)
        if behind is None:
            infos.append(f"동기 기준점이 레포 이력에 없음: {r} -> '{synced[:7]}' "
                         f"(rebase·force push 가능 — 다음 ingest에서 재설정, schema §7-26)")
        elif behind > 0:
            infos.append(f"위키 뒤처짐: {r} — {behind}커밋 미반영 "
                         f"(synced: {synced[:7]}, schema §7-26)")

    # 고아 페이지(간이): 어디서도 링크되지 않는 페이지 (루트 인프라·아카이브·lint 리포트 제외)
    #  lint-YYYYMMDD 리포트(questions/, type: question)는 어디서도 링크되지 않는 게 정상이라
    #  §7-12 집계·§7-23 등록과 같은 기준(is_lint_report)으로 고아 검사에서도 제외한다(매 실행 오탐 방지).
    for r, (fm, typ, _) in sorted(pages.items()):
        if "/" not in r or r.startswith("90_archive/") or typ in INFRA_TYPES or is_lint_report(r):
            continue
        if r[:-3].casefold() not in link_targets:  # link_targets는 casefold 정규화값(M-3/L-1과 정합)
            warn(f"고아 페이지(어디서도 링크되지 않음): {r}", r)

    # 60일+ 미편집 집계 (§7-3) — 개별 나열하지 않는다.
    #  실 vault에서 86건이 나와 INFO 89건 중 96%를 차지했고, 그 더미에 다른 신호가 묻혔다.
    #  이 축은 "confidence를 낮출지 판단하라"는 **경향 신호**라 개별 파일명이 액션에 직결되지
    #  않는다 — 오래된 순 상위 5건만 보이면 어디부터 볼지 정할 수 있다. 반면 90일+(아카이브
    #  후보)는 파일 단위 처리 대상이라 개별 유지한다(위 검사).
    if stale60:
        top = sorted(stale60, reverse=True)[:5]
        more = len(stale60) - len(top)
        tail = (" … 외 %d건" % more) if more > 0 else ""
        infos.append("60일+ 미편집 %d건(confidence 하락 후보) — 오래된 순: %s%s"
                     % (len(stale60), ", ".join("%s(%d일)" % (r, d) for d, r in top), tail))

    # (미검증)·미해결 question 집계 리포트 — 사용자 검증 후보 (0건이면 생략, wiki-schema §11)
    if unverified_hits:
        infos.append(f"(미검증) 표기 {unverified_hits}건 / {unverified_files}개 파일 — 사용자 검증 후보")
    if open_questions:
        infos.append(f"미해결 question {open_questions}건 — 사용자 검증 후보")
    if dep_count:
        infos.append(f"deprecated 페이지 {dep_count}건 (이력 보존 — 현재 기능 아님, schema §2.3)")

    # 보고
    # WARN이 많을 때(10건+) 프로젝트별 집계 1줄 — 대규모 정비 세션에서 우선순위 파악용.
    #  집계 자체는 warn() 헬퍼가 append 시점에 수행(warn_groups) — 여기서는 출력 여부·정렬만.
    WARN_GROUP_MIN = 10
    warn_summary = ""
    if len(warns) >= WARN_GROUP_MIN and warn_groups:
        warn_summary = ", ".join(f"{k} {v}건" for k, v in
                                 sorted(warn_groups.items(), key=lambda kv: -kv[1]))
    print(f"== llm-wiki Lint: {vault} ==")
    print(f"검사 파일: {len(md)}개")
    for label, items, mark in (("오류", errors, "[ERR]"), ("경고", warns, "[WARN]"),
                               ("정보", infos, "[INFO]")):
        print(f"\n{mark} {label} {len(items)}건")
        if mark == "[WARN]" and warn_summary:
            print(f"  (프로젝트별: {warn_summary})")
        for it in items:
            print(f"  - {it}")
    if not errors and not warns:
        print("\n[OK] 오류·경고 없음.")

    # L-5: ERR가 있으면 종료코드 1 — A-4/B-3의 "오류 0 확인"을 텍스트 해석이 아니라 종료코드로
    #   자동 판정할 수 있게 한다(hook·CI 연동 가능). WARN·INFO만이면 0(비차단 정보성).
    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
