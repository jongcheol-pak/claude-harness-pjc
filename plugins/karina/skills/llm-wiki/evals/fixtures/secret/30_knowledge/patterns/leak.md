---
type: concept
concept_name: "누출예시"
origin: agent-synthesized
confidence: low
updated: 2026-07-02
related_projects: [X, Y]
tags: [concept, leak]
---
# 누출 예시 (시크릿 스캔 대상 — 더미 값)

아래는 실제 값이 아닌 명백한 더미이며, 시크릿 의심 스캔(§7-22)이
password 실값 패턴을 잡는지 검증하기 위한 위반 픽스처다.

password: FakeDummyPass99

T5 강화 검증용 더미(모두 명백한 가짜 — 강화된 스캔이 잡는지 확인):
- 순수 영문 값(엔트로피): password: correcthorsebatterystaple
- 한글 라벨: 비밀번호: Xk29fj3kd82jf
- 라벨 없이 산문에 노출 ghp_wJalrXUtnFEMIabcdefghij0123456789 여기 끝
- 밑줄 인접 라벨(경계 수정): aws_secret_access_key = wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY
