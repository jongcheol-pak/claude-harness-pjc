# Intent: chain-plan 워커 탭을 입력창 문구와 무관하게 닫고, 못 닫으면 옆 탭으로 잇기
Author: 사용자(jongcheol-pak). Status: approved.

## Problem
원문: 「chain-plan에서 띄운 워커 탭에 입력창에 문구가 입력되어 있으면 작업이 끝나도 종료를 하지 않고 멈추고 사용자가 종료 할때까지 대기 하는데 작업이 끝나면 입력창에 문구가 있어도 종료를 하도록 함. 종료를 못 하는 경우 멈추지 말고 옆에 워커 탭을 띄워서 계속 작업 하도록 수정」. 입력창에 문구가 남은 워커 탭은 Karina 가 사람이 손댄 탭으로 보아 `worker-release` 가 닫지 않고, 그 워커가 같은 폴더 자리를 계속 쥐어 체인이 다음 계획 앞에서 사람이 탭을 닫을 때까지 선다.

## Proposed outcome
작업을 마친(succeeded) 워커 탭은 입력창 문구가 있어도 코디네이터가 닫고 다음 계획으로 간다. 닫지 못하면 멈추지 않고 그 탭을 둔 채 같은 폴더에 다음 워커 탭을 새로 띄워 이어 가며, 남은 탭은 체인 보고에 실린다.

## Affected users and systems
Karina 탭에서 `pjc:chain-plan` 체인을 돌리는 사용자. 걸리는 것은 `pjc:chain-plan` 의 워커 루프·워커 닫기·`duplicate_worker` 처방·보고 서식 문서다.

## Constraints
이번 체인(Run)이 띄운 앞 워커에만 적용하고 다른 Run·다른 세션 워커는 지금처럼 기다린다(Q/A). failed·멈춤(stall)·사용자 중단 경로는 지금처럼 탭을 남기고 멈춘다(Q/A). Karina 앱 코드는 고치지 않는다.

## Open questions
없음
