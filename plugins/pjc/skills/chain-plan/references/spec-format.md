# spec 서식 (`pjc:chain-plan`)

> `../SKILL.md` 「Run·Task」가 task 를 만들기 직전에 이 파일을 연다 — 계획마다 spec 을 채울 때만 읽는다.

## spec 서식

```
[chain-plan 중계] plan <N>/<총>
CLI: <해석한 실행 파일 이름 또는 따옴표 친 전체경로>
인계: docs/plans/chain-<run-create 가 돌려준 Run id>.md
실측 기준: <회차 실측·measure.md 의 실측 기준 | 없음>
DB 변경: <금지 | 승인 목록: DB·테이블·연산·조건 — 목록 밖은 금지(SELECT 는 허용)>
근거로 정한 것: <① · ③ — 각 (근거: …)>
체인 대조: <이 Run 앞 계획마다 plan M — 성공의 모습 | 없음>

원문:
<사용자의 계획 목록 중 이 계획의 줄>
<문답 원문 | Q/A: 없음>

재진술:
- 결과:        …
- 사용자:      …
- 지금 하는 이유: …
- 성공의 모습:  …
- 제약조건:    …
- 범위 밖:     …

실측 요지:
<실측(회차 실측 또는 measure.md 결과)의 task 초안·바뀌는 파일 — 항목마다 (근거: …) | 없음>
다른 회차: plan <M> — <task 초안 한 줄> …

진행:
1. pjc:plan 을 Skill 도구로 부르되 args 첫 줄에 [chain-plan 중계] 를 두고 위 실측 기준·원문·재진술·실측 요지를 그대로 싣는다. 승인되면 pjc:implement 를 Skill 도구로 불러 마지막 task 까지 간다.
2. 질문·승인은 이 배정문 끝의 ask 명령에서 karina-cli 를 CLI 줄의 값(따옴표 포함)으로 바꾸고 --timeout-ms 540000 과 2>/dev/null 을 더해 Bash 도구 timeout 600000 으로 보낸다(만료되면 ask --resume <questionId>). 돌아오는 답은 코디네이터가 사용자의 답을 글자 그대로 옮긴 것이거나 체인 승인 위임 답(Y (체인 승인 위임 — …))이거나 코디네이터 판정 답(… (코디네이터 판정 — …))이라, 셋 다 사용자 응답·승인으로 본다. 워커 화면에는 묻지 않는다(AskUserQuestion 금지).
3. 보고는 이 배정문 끝의 worker_done 명령에서 karina-cli 를 CLI 줄의 값(따옴표 포함)으로 바꾸고 아래 --body 를 더한 것이다. 최종 보고 텍스트를 내기 전, 같은 turn 에서 보낸다. 멈추면 --outcome failed 에 --body 로 사유·남은 task·환경 마찰을 싣는다.
   --body "$(cat <<'BODY'
   결과: <1줄>
   사용자용 요약: <무엇이 바뀌었나 — 사용자 관점 2~3줄>
   확인 방법: <사용자가 결과를 확인하는 방법>
   남은 일: <없으면 「없음」>
   승인 필요 항목: <없으면 「없음」>
   HUMAN-VERIFY·미검증: <없으면 「없음」>
   환경 마찰: <겪은 것마다 「<무엇> ×<횟수>」 — hook 차단·AGENTS.md 에 없어 찾거나 물은 명령·원인별 실패(1회도) · 겪을 때 Progress Log 에 적어 모은다(올린 곳이 있으면 그 위치) · 없으면 「없음」>
   BODY
   )"
4. 문제가 생기면 pjc:pjc-systematic-debugging 절차로 근본 원인을 고친다 — 테스트 skip·예외 삼키기·하드코딩·검증 완화 같은 우회는 쓰지 않는다.
```

- **표식은 spec 첫 줄에 둔다** — 워커의 `pjc:plan` 이 그 자리(배정문 `할 일:` 바로 아래)와 Skill args 첫 줄로 중계 모드를 판정한다(`../../plan/references/relay-mode.md`「중계 모드」).
- **질문·보고 명령은 spec 에 새로 적지 않고 배정문 끝의 것을 가리킨다** — 핸들·task id·dispatch id 가 거기 이미 채워져 있고, 옮겨 적으면 값이 어긋날 자리가 하나 는다.
- **`--body` 의 heredoc 구분자는 `BODY` 다** — spec 자체가 `EOF` heredoc 으로 넘어가, 그 안에 `EOF` 줄이 있으면 spec 이 거기서 끊긴다.
