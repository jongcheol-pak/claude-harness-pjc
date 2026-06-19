# PreToolUse hook - PowerShell 버전
# Bash 도구 호출 시 파괴적 명령 차단.
# exit 2 = block (Claude에게 차단 사유 전달).
#
# 차단 대상: 파일 시스템 파괴(rm -rf 등), git 히스토리 파괴,
#   DB 데이터 삭제(DROP/TRUNCATE/WHERE 없는 DELETE/스키마 삭제/migration reset/ORM 대량삭제).
#
# ⚠️ 한계: 이 hook은 **Bash 도구로 실행되는 명령**만 검사한다.
#   ORM 대량 삭제 코드(예: RemoveRange, deleteMany)를 소스 파일에 '작성'만 하는 경우는
#   Write/Edit 도구라 여기서 안 잡힌다. 그런 코드는 plan-feature 승인 게이트 +
#   code-quality-reviewer가 검토한다 (CLAUDE.md "DB 데이터 삭제는 승인 필수" 참조).
#
# ⚠️ 이 hook은 의도적으로 토글 불가합니다.
#   - 다른 hook(require-plan-for-write, impact-warn 등)과 달리
#     ~/.claude/.disabled/ 체크를 하지 않습니다.
#   - 파괴적 명령 차단은 사용자 안전 보장의 마지막 방어선이므로
#     harness-toggle skill로도 끌 수 없게 합니다.
#   - 환경변수 CLAUDE_HARNESS_QUICK도 무시합니다.
#   - 이 동작을 변경하지 마세요.


$ErrorActionPreference = 'Stop'

# stdin으로 JSON 입력 수신
$inputJson = [Console]::In.ReadToEnd()

# JSON 파싱
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
} catch {
    # 파싱 실패 시 통과 (차단 실패가 더 위험)
    exit 0
}

if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# 차단 패턴 (POSIX + Windows 둘 다 대응)
$patterns = @(
    'rm\s+-rf\s+/(\s|$)',                               # rm -rf /
    'rm\s+-rf\s+~',                                     # rm -rf ~
    'rm\s+-rf\s+\$HOME',                                # rm -rf $HOME
    'rm\s+-rf\s+\*(\s|$)',                              # rm -rf *
    'git\s+push\s+.*(--force|--force-with-lease)',      # git push --force
    'git\s+push\s+-f(\s|$)',                            # git push -f
    'git\s+filter-branch',                              # 히스토리 재작성
    'git\s+filter-repo',
    'git\s+reflog\s+expire',
    'git\s+clean\s+(-[a-z]*f[a-z]*d|-[a-z]*d[a-z]*f|.*-f\b.*-d\b|.*-d\b.*-f\b)',  # git clean -fd/-df/-f -d (untracked 영구 삭제)
    '(^|\s)sudo(\s|$)',                                 # sudo
    'DROP\s+TABLE',                                     # SQL — 테이블 삭제
    'DROP\s+DATABASE',                                  # DB 전체 삭제
    'DROP\s+SCHEMA',                                    # 스키마 삭제
    'TRUNCATE\s+TABLE',                                 # 테이블 전체 비우기
    'TRUNCATE\s+(?!TABLE)',                             # TRUNCATE <table> (TABLE 키워드 생략형)
    'DELETE\s+FROM\s+[^\s;]+\s*;',                      # DELETE FROM x; — WHERE 없는 전체 행 삭제
    'DELETE\s+FROM\s+[^\s;]+\s*$',                      # DELETE FROM x (문장 끝, WHERE 없음)
    'DELETE\s+FROM\s+\w+\s+WHERE\s+1\s*=\s*1',          # WHERE 1=1 = 사실상 전체 삭제
    'UPDATE\s+\w+\s+SET\s+(?:(?!WHERE).)*$',            # UPDATE x SET ... (WHERE 절 자체가 없음 — 전체 행 변조)
    'UPDATE\s+\w+\s+SET\s+.*WHERE\s+1\s*=\s*1',         # UPDATE ... WHERE 1=1 = 전체 변조
    '\.RemoveRange\(',                                  # EF Core 대량 삭제
    'ExecuteDelete(Async)?\(',                          # EF Core 7+ 대량 삭제
    '\.deleteMany\(\s*\{?\s*\}?\s*\)',                  # Prisma/Mongo 조건 없는 대량 삭제
    '\.delete_all\b',                                   # ActiveRecord/Django 전체 삭제
    'migrate\s+reset',                                  # prisma/이주 리셋 (데이터 손실)
    'db\s+reset',                                       # 일부 ORM CLI
    'database\s+drop',                                  # dotnet ef database drop
    'mkfs\.',                                           # 포맷
    'dd\s+if=.*of=/dev/',                               # dd to device
    # Windows 특화 위험 명령
    'Remove-Item.*-Recurse.*-Force\s+[A-Z]:\\',         # PowerShell 드라이브 루트 강제 삭제
    'Remove-Item.*-Recurse.*-Force\s+\$env:',           # 환경 변수 경로 강제 삭제
    'rmdir\s+/s\s+/q\s+[A-Z]:\\',                       # cmd 드라이브 루트 강제 삭제
    'Format-Volume',                                    # 볼륨 포맷
    'Clear-RecycleBin\s+.*-Force'                       # 휴지통 강제 비우기
)

# &&, ||, ;, |로 분리 (PowerShell의 ;도 포함)
$subs = $cmd -split '[;|&]'

foreach ($sub in $subs) {
    $sub = $sub.Trim()
    if ([string]::IsNullOrWhiteSpace($sub)) { continue }

    foreach ($pattern in $patterns) {
        if ($sub -match $pattern) {
            [Console]::Error.WriteLine("BLOCKED: 파괴적 명령 패턴 감지: '$pattern'")
            [Console]::Error.WriteLine("Command: $sub")
            [Console]::Error.WriteLine("필요하다면 사용자에게 명시적 확인을 받은 뒤 직접 실행하도록 보고하세요.")
            exit 2
        }
    }
}

exit 0
