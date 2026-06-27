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

# 한글 차단 사유가 cp949 콘솔에서 깨지지 않도록 stderr 출력을 UTF-8로 (Claude Code는 hook 출력을 UTF-8로 디코딩)
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

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
# 주의: rm/Remove-Item/rmdir 계열의 '재귀 강제 삭제'는 옵션 순서·따옴표·글롭 변형이 많아
#   단일 정규식으로는 우회가 쉽다(예: rm -fr /, rm -rf /*, Remove-Item C:\ -Recurse -Force).
#   → 이 패턴 배열이 아니라 아래 '컴파운드 검사'에서 플래그·대상을 분해해 판정한다.
$patterns = @(
    'git\s+push\s+.*(--force|--force-with-lease)',      # git push --force
    'git\s+push\s+-f(\s|$)',                            # git push -f
    'git\s+filter-branch',                              # 히스토리 재작성
    'git\s+filter-repo',
    'git\s+reflog\s+expire',
    'git\s+clean\s+(-[a-z]*f[a-z]*d|-[a-z]*d[a-z]*f|.*-f\b.*-d\b|.*-d\b.*-f\b)',  # git clean -fd/-df/-f -d (untracked 영구 삭제)
    # (sudo 전면 차단은 제거 — sudo 자체는 파괴적이지 않고 위험은 뒤따르는 명령에 있으며
    #  그건 rm 컴파운드·다른 패턴이 잡는다. 예: 'sudo rm -rf /'는 rm 컴파운드가 차단,
    #  'sudo -l'·'sudo apt install'은 정상 통과. 전면 차단은 정당한 sudo까지 막던 오탐.)
    'DROP\s+TABLE',                                     # SQL — 테이블 삭제
    'DROP\s+DATABASE',                                  # DB 전체 삭제
    'DROP\s+SCHEMA',                                    # 스키마 삭제
    'TRUNCATE\s+TABLE',                                 # 테이블 전체 비우기
    'TRUNCATE\s+(?!TABLE)',                             # TRUNCATE <table> (TABLE 키워드 생략형)
    'DELETE\s+FROM\s+[^\s;]+\s*;',                      # DELETE FROM x; — WHERE 없는 전체 행 삭제
    'DELETE\s+FROM\s+[^\s;]+\s*$',                      # DELETE FROM x (문장 끝, WHERE 없음)
    'DELETE\s+FROM\s+\w+\s+WHERE\s+1\s*=\s*1',          # WHERE 1=1 = 사실상 전체 삭제
    'UPDATE\s+\w+\s+SET\b(?![^;]*\bWHERE\b)',           # UPDATE x SET ... (WHERE 절 없음 — 전체 행 변조). \bWHERE\b로 값 속 "nowhere" 등 오탐 방지
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
    # (Remove-Item/rmdir 재귀 강제 삭제는 아래 '컴파운드 검사'에서 인자 순서 무관하게 처리)
    'Format-Volume',                                    # 볼륨 포맷
    'Clear-RecycleBin\s+.*-Force',                      # 휴지통 강제 비우기
    # ---- 권한·보안 변경 (규칙 10) ----
    # 각 sub의 '선두 명령'일 때만 차단(^ 앵커). $scan은 trim된 sub라(위 foreach $sub.Trim())
    # 'git grep chmod'·'rg chmod'는 선두가 git/rg여서 안 걸린다(정당한 검색 오탐 방지).
    # 조회형(icacls 경로만·attrib 인자 없음)은 변경 인자가 없어 통과한다.
    # 한계(의도된 트레이드오프): 'xargs chmod'·'find -exec chmod'·'env X=Y chmod'처럼 권한 명령이
    # sub 선두가 아닌 우회는 미탐 — 검색 오탐 방지를 우선한 것. plan 승인·리뷰가 2차 방어선.
    '^\s*(sudo\s+)?chmod\s',                            # POSIX 권한 변경
    '^\s*(sudo\s+)?chown\s',                            # POSIX 소유자 변경
    '^\s*(sudo\s+)?takeown\b',                          # Windows 소유권 탈취
    '^\s*Set-Acl\b',                                    # PowerShell ACL 변경
    '^\s*icacls\b.*(/grant|/deny|/remove|/setowner|/reset|/restore|/setintegritylevel|/inheritance:[red])',  # Windows ACL 변경(조회형·/save 제외)
    '^\s*attrib\s+.*[+-][rhsa]',                        # 파일 속성 변경(조회형 제외)
    '^\s*(Add|Set)-MpPreference\b.*Exclusion',          # Defender 예외 추가/변경(보안 약화)
    '^\s*netsh\s+advfirewall\s+.*\b(set|add|delete|reset|import)\b'  # 방화벽 설정 변경(show/dump/export 조회는 통과)
)

# &&, ||, ;, | 로 분리 — 단, 따옴표 안의 구분자는 분리하지 않는다(quote-aware).
# (단순 -split '[;|&]'는 grep "DELETE FROM x;" 처럼 따옴표 안의 ;에서 명령을 쪼개
#  따옴표가 깨지고, 그러면 데이터 인자 제거가 작동하지 못해 오탐이 난다.)
function Split-TopLevel([string]$s) {
    $parts = New-Object System.Collections.Generic.List[string]
    $cur = ''
    $q = $null   # 현재 열린 따옴표 문자(' 또는 ") 또는 $null
    foreach ($ch in $s.ToCharArray()) {
        if ($q) {
            $cur += $ch
            if ($ch -eq $q) { $q = $null }
        } elseif ($ch -eq '"' -or $ch -eq "'") {
            $q = $ch; $cur += $ch
        } elseif ($ch -eq ';' -or $ch -eq '|' -or $ch -eq '&') {
            $parts.Add($cur); $cur = ''
        } else {
            $cur += $ch
        }
    }
    $parts.Add($cur)
    return $parts
}
$subs = Split-TopLevel $cmd

foreach ($sub in $subs) {
    $sub = $sub.Trim()
    if ([string]::IsNullOrWhiteSpace($sub)) { continue }

    # ---- 오탐 완화: '데이터'(실행되지 않는) 인자를 스캔 대상에서 제거 ----
    # git 커밋 메시지·echo/printf 출력·grep 검색 패턴은 텍스트일 뿐 실행되지 않으므로,
    # 그 안의 'DROP TABLE'·'rm -rf /' 같은 문자열을 위험 명령으로 오인(오탐)하지 않게 제거.
    # 반대로 psql/mysql/bash -c/eval 등 '실행자'의 따옴표 내용은 실제 실행되므로 보존한다.
    # (경로 인자의 따옴표 — 예: rm -rf "/" — 는 보존: rm은 제거 대상이 아니므로 그대로 검사.)
    $scan = $sub
    if ($scan -match '(?i)(^|\s)git(\s|$)') {
        # git 메시지 인자 제거 (-m/-am/--message; 따옴표/등호/단일토큰)
        $scan = $scan -replace '(?i)(^|\s)(-[a-z]*m|--message)(=|\s+)("[^"]*"|''[^'']*''|\S+)', ' '
    }
    if ($scan -match '(?i)(^|\s)(echo|printf)(\s|$)') {
        # echo/printf 출력 내용 제거 (명령 이후 전부 — 출력은 실행 아님)
        $scan = $scan -replace '(?i)(^|\s)(echo|printf)\b.*$', ' '
    }
    if ($scan -match '(?i)(^|\s)(grep|egrep|fgrep|rg|ag|ack)(\s|$)') {
        # grep 계열 검색 패턴(따옴표) 제거 (검색은 실행 아님)
        $scan = ($scan -replace '"[^"]*"', ' ') -replace "'[^']*'", ' '
    }

    # ---- 컴파운드 검사: 재귀 강제 삭제 (옵션 순서·따옴표·글롭 변형 무관) ----
    # rm/Remove-Item/rmdir/rd/del 계열이 '재귀'+'강제' 플래그를 모두 갖고,
    # 대상이 위험 루트(/, /*, //, ~, $HOME, *, ., ./, 드라이브 루트 C:\, $env:)이면 차단.
    # 단일 정규식이 못 잡던 변형을 포착: rm -fr /, rm -r -f /, rm --recursive --force /,
    #   rm -rf /*, rm -rf "/", rm -rf //, Remove-Item C:\ -Recurse -Force(인자 순서) 등.
    if ($scan -match '(^|\s)(rm|Remove-Item|ri|rmdir|rd|del|erase)(\s|$)') {
        # 재귀 플래그: 짧은 묶음(-r/-rf/-fr/-Rf, r·f 문자만) | -Recurse | --recursive | cmd /s
        $hasRecurse = ($scan -match '(^|\s)-[rfRF]*r[rfRF]*(\s|$)') -or
                      ($scan -match '(^|\s)-Recurse\b') -or
                      ($scan -match '--recursive\b') -or
                      ($scan -match '\s/s\b')
        # 강제 플래그: 짧은 묶음(-f/-rf/-fr) | -Force | --force | cmd /q
        $hasForce   = ($scan -match '(^|\s)-[rfRF]*f[rfRF]*(\s|$)') -or
                      ($scan -match '(^|\s)-Force\b') -or
                      ($scan -match '--force\b') -or
                      ($scan -match '\s/q\b')
        # 위험 대상(따옴표 선택): / /* // | ~ $HOME $env: | * | . ./ .* ./* | 드라이브 루트 C:\(글롭 포함)
        $dangerTarget = '(^|\s)(["'']?)(/[*/]?|~\S*|\$HOME\S*|\$env:\S*|\*|\.\*|\./\*|\./|\.|[A-Za-z]:[\\/]+\*?)(["'']?)(\s|$)'
        if ($hasRecurse -and $hasForce -and ($scan -match $dangerTarget)) {
            [Console]::Error.WriteLine("BLOCKED: 재귀 강제 삭제 + 위험 루트 대상 감지")
            [Console]::Error.WriteLine("Command: $sub")
            [Console]::Error.WriteLine("필요하다면 사용자에게 명시적 확인을 받은 뒤 직접 실행하도록 보고하세요.")
            exit 2
        }
    }

    foreach ($pattern in $patterns) {
        if ($scan -match $pattern) {
            [Console]::Error.WriteLine("BLOCKED: 파괴적 명령 패턴 감지: '$pattern'")
            [Console]::Error.WriteLine("Command: $sub")
            [Console]::Error.WriteLine("필요하다면 사용자에게 명시적 확인을 받은 뒤 직접 실행하도록 보고하세요.")
            exit 2
        }
    }
}

exit 0
