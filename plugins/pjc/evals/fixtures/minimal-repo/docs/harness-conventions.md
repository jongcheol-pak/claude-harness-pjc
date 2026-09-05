# 하니스 규약 (픽스처)

## 검증 매핑 (task 검증 선택)

| 변경 파일 패턴 | 필수 검증 |
|---|---|
| `plugins/pjc/evals/**` | `python plugins/pjc/evals/check-harness-consistency.py` |

## 조건부 참조 문서 크기 임계

> **기계 대조 대상이다.** 「문서 예산」 축이 이 표를 파싱해 **기록값 == 실측**과 **실측 <= 상한** 둘 다 대조한다.

| 파일 | 파일 바이트 | 상한 |
|---|---|---|
| `docs/golden-runner.md` | 139 | 4,000 |

> **이 표에 있는 파일을 편집한 task가 같은 task 안에서 이 표를 갱신한다.**
