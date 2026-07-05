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
# ⚠️ 한계 (정규식 접근의 본질적 미탐 — 의도된 트레이드오프):
#   명령치환·변수 간접 참조는 잡지 못한다 — 예: rm -rf $(echo /), X=/; rm -rf $X.
#   문자열 평가를 하지 않는 정규식으로는 불가하며, 1차 방어선은 Claude Code 권한 시스템이다.
#   (hook-cases.json에 '[알려진 미탐]' 케이스로 문서화 — 이 동작이 바뀌면 회귀로 검출됨.)
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

# ---- 위험 대상($dangerTarget) — 루프 밖에서 1회 정의(사전검사 2종·in-loop 컴파운드 검사 공유) ----
# 위험 대상(따옴표 선택): / /* // | POSIX 시스템 디렉터리(/usr /etc /bin … /opt /srv /run, 하위·글롭 포함) |
#   ~ $HOME $env: | * | . ./ .* ./* | Windows 시스템 디렉터리(C:\Windows·Program Files·ProgramData — 네이티브 및
#   MSYS /c/… · WSL /mnt/c/… 마운트) | 드라이브 루트 C:\(글롭 포함).
# MSYS /c/… · WSL /mnt/c/… 마운트는 (?i)로 /C/·/D/ 등 대소문자 무관 매치. 시스템 디렉터리는 dir명 뒤가
#   /·따옴표·공백·끝이어야 매치돼 동음 접두(/etcetera·C:\WindowsApps·/c/Users)는 통과.
# M5: 사용자 프로필 루트(C:\Users·C:\Users\<name>)만 위험대상 — 하위 임의 폴더(C:\Users\x\proj\dist 등 2단계+)는
#   제외해 일상 정리 작업 오탐을 막는다(([\\/]+[^\\/\s]+)? 뒤 경계 요구).
#   트레일링 구분자 표기(C:\Users\ · /home/jongc/)도 동일 대상이므로 [\\/]?로 함께 차단한다(H1 — 없으면
#   끝 슬래시 하나로 뒤 경계가 깨져 통과했다). 2단계+ 하위(/home/jongc/proj)는 여전히 미매치.
# /home: /home·/home/<user>만 위험대상 — /home/<user>/<하위>(프로젝트 폴더)는 제외(C:\Users와 동일 원리).
#   /root와 달리 /home은 POSIX 그룹의 (/\S*)?(하위 전부 포함)에 넣으면 정상 하위 삭제까지 차단되므로 별도 알터네이션.
$dangerTarget = '(^|\s)(["'']?)(/(usr|etc|bin|sbin|lib64|lib|var|boot|root|sys|proc|dev|opt|srv|run)(/\S*)?|/home([\\/]+[^\\/\s]+)?[\\/]?|/(mnt/)?[a-z]/(Windows|Program Files( \(x86\))?|ProgramData)([\\/]\S*)?|/[*/]?|~\S*|\$HOME\S*|\$env:\S*|\*|\.\*|\./\*|\./|\.|[A-Za-z]:[\\/]+(Windows|Program Files( \(x86\))?|ProgramData)([\\/]\S*)?|[A-Za-z]:[\\/]+Users([\\/]+[^\\/\s]+)?[\\/]?|[A-Za-z]:[\\/]+\*?)(["'']?)(\s|$)'

# 삭제 명령 별칭 세트 — 사전검사(find·열거 파이프)와 in-loop 컴파운드 검사가 **동일 집합을 공유**한다.
#   한 곳만 좁으면(예: 사전검사가 ri/rmdir/rd 누락) 그 별칭으로 파이프 삭제 우회가 다시 열린다(T3 B1).
$delCmdAlt = 'rm|Remove-Item|ri|rmdir|rd|del|erase'

# ---- find로 위험 루트를 훑어 삭제하는 파이프/exec 형태 (Split 전, 전체 명령 사전검사) ----
# 'find / … | xargs rm', 'find ~ … -exec rm', 'find $HOME … -delete'는 Split-TopLevel가 파이프로
#   쪼개면 rm sub에 대상 토큰이 없어(삭제 대상은 find가 stdin으로 공급) 아래 컴파운드 검사를 빠져나간다.
#   → 전체 $cmd에서 직접 차단한다.
# 오탐 방지: 'find .'(상대 경로 로컬 정리)은 제외하고, 위험 루트로 시작하는 find만 차단한다
#   — 절대(/…), 홈(~…/$HOME…), $env:…, 드라이브 루트(C:\…). (chmod xargs 미탐과 달리 삭제는 비가역이라 차단.)
# 한계(의도): echo "find / | xargs rm"처럼 문자열 안에 있어도 차단될 수 있으나 — 차단돼도 무해(echo는 직접 실행).
$findDangerRoot = '(?i)\bfind\s+(/\S*|~\S*|\$HOME\S*|\$env:\S*|[A-Za-z]:[\\/]\S*)'
if ($cmd -match $findDangerRoot -and (
        ($cmd -match ('(?i)\|\s*xargs\b[^|]*\b(' + $delCmdAlt + ')\b')) -or
        ($cmd -match '(?i)-exec(dir)?\s+(rm|Remove-Item)\b') -or
        ($cmd -match '(?i)\bfind\b[^|]*\s-delete\b'))) {
    [Console]::Error.WriteLine("BLOCKED: 위험 루트(/, ~, `$HOME, 드라이브 루트)를 find로 훑어 삭제(xargs rm / -exec rm / -delete) 감지")
    [Console]::Error.WriteLine("Command: $cmd")
    [Console]::Error.WriteLine("필요하다면 사용자에게 명시적 확인을 받은 뒤 직접 실행하도록 보고하세요.")
    exit 2
}

# ---- 열거 명령으로 위험 루트를 훑어 삭제로 파이프하는 형태 (Split 전, 전체 명령 사전검사) ----
# 'Get-ChildItem C:\ -Recurse | Remove-Item -Force', 'ls / | xargs rm -rf', 'dir C:\Windows -Recurse | Remove-Item'
#   은 Split-TopLevel가 파이프로 쪼개면 삭제 sub에 대상·재귀 토큰이 없어(대상은 열거 명령이 stdin으로 공급)
#   아래 컴파운드 검사를 빠져나간다 → find 사전검사와 같은 원리로 전체 $cmd에서 직접 차단한다.
# 오탐 방지: 위험 판정은 '첫 파이프 앞(열거 소스 인자)'에만 $dangerTarget을 적용한다 — 상대경로(./build)·
#   사용자 하위 2단계+(C:\Users\me\proj\dist)는 $dangerTarget 미매치라 통과. 삭제측은 재귀·강제 플래그
#   (또는 xargs rm)를 요구해 단순 조회 파이프는 통과시킨다. printf/echo 소스는 목록에서 제외(데이터 오탐 — M3 Deferred).
$enumSource      = '(?i)(^|\s|\|)(Get-ChildItem|gci|ls|dir|find)\b'
$pipeToDelete    = '(?i)\|\s*[^|]*\b(' + $delCmdAlt + ')\b'
$pipeXargsRm     = '(?i)\|\s*xargs\b[^|]*\b(' + $delCmdAlt + ')\b'
$delRecurseForce = '(?i)(-Recurse\b|-Force\b|--recursive\b|--force\b|(^|\s)-[rfRF]+(\s|$)|\s/[sq]\b)'
$beforePipe = ($cmd -split '\|', 2)[0]   # 첫 파이프 앞 = 열거 소스 인자 영역(여기서만 위험루트 판정)
if (($beforePipe -match $enumSource) -and ($beforePipe -match $dangerTarget) -and (
        (($cmd -match $pipeToDelete) -and ($cmd -match $delRecurseForce)) -or
        ($cmd -match $pipeXargsRm))) {
    [Console]::Error.WriteLine("BLOCKED: 위험 루트를 열거 명령으로 훑어 삭제로 파이프(Get-ChildItem/ls/dir | Remove-Item/rm) 감지")
    [Console]::Error.WriteLine("Command: $cmd")
    [Console]::Error.WriteLine("필요하다면 사용자에게 명시적 확인을 받은 뒤 직접 실행하도록 보고하세요.")
    exit 2
}

# 차단 패턴 (POSIX + Windows 둘 다 대응)
# 주의: rm/Remove-Item/rmdir 계열의 '재귀 삭제'는 옵션 순서·따옴표·글롭 변형이 많아
#   단일 정규식으로는 우회가 쉽다(예: rm -fr /, rm -rf /*, Remove-Item C:\ -Recurse -Force).
#   → 이 패턴 배열이 아니라 아래 '컴파운드 검사'에서 플래그·대상을 분해해 판정한다.
$patterns = @(
    'git\s+((-c|-C)\s+\S+\s+)*push\s+.*(--force|--force-with-lease)',   # git push --force (git -c/-C 선행 옵션으로 우회 방지)
    'git\s+((-c|-C)\s+\S+\s+)*push\s+-f(\s|$)',                         # git push -f (git -c/-C 선행 옵션으로 우회 방지)
    'git\s+((-c|-C)\s+\S+\s+)*push\s+\S+\s+\+\S',                       # git push <remote> +refspec (M4 — plus-refspec 강제 푸시. 예: git push origin +main, +HEAD:master. 히스토리 덮어씀)
    'git\s+filter-branch',                              # 히스토리 재작성
    'git\s+filter-repo',
    'git\s+reflog\s+expire',
    'git\s+clean\s+(-[a-z]*f[a-z]*d|-[a-z]*d[a-z]*f|.*-f\b.*-d\b|.*-d\b.*-f\b)',  # git clean -fd/-df/-f -d (untracked 영구 삭제)
    'gh\s+repo\s+delete',                               # GitHub 원격 저장소 영구 삭제 (외부·비가역)
    # (sudo 전면 차단은 제거 — sudo 자체는 파괴적이지 않고 위험은 뒤따르는 명령에 있으며
    #  그건 rm 컴파운드·다른 패턴이 잡는다. 예: 'sudo rm -rf /'는 rm 컴파운드가 차단,
    #  'sudo -l'·'sudo apt install'은 정상 통과. 전면 차단은 정당한 sudo까지 막던 오탐.)
    'DROP\s+TABLE',                                     # SQL — 테이블 삭제
    'DROP\s+DATABASE',                                  # DB 전체 삭제
    'DROP\s+SCHEMA',                                    # 스키마 삭제
    'TRUNCATE\s+TABLE',                                 # 테이블 전체 비우기
    'TRUNCATE\s+(?!TABLE\b)(?!-)',                      # TRUNCATE <table> (TABLE 키워드 생략형). (?!-)로 coreutils
                                                        #   'truncate -s 0 file'(대시 옵션 선행) 오탐 배제 — SQL은 식별자가 뒤따름.
                                                        #   한계: 파일명 선행형 'truncate file -s 0'은 잔여 미배제(드문 형태).
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
    # (Remove-Item/rmdir 재귀 삭제는 아래 '컴파운드 검사'에서 인자 순서 무관하게 처리)
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

# &&, ||, ;, |, 개행 으로 분리 — 단, 따옴표 안의 구분자는 분리하지 않는다(quote-aware).
# (단순 -split '[;|&]'는 grep "DELETE FROM x;" 처럼 따옴표 안의 ;에서 명령을 쪼개
#  따옴표가 깨지고, 그러면 데이터 인자 제거가 작동하지 못해 오탐이 난다.)
# 개행도 최상위 구분자다(H1) — Bash 도구는 여러 줄 명령이 흔한데, 개행을 분리하지 않으면
#  둘째 줄의 파괴 명령이 ^앵커 패턴(chmod 등)을 벗어나고 컴파운드 윈도우 계산도 빈 문자열이
#  되어(선행 \n 매치) 'ls\nrm -rf /'가 통째로 미탐이었다. 따옴표 안 개행(멀티라인 커밋 메시지
#  등 데이터)은 그대로 보존된다.
function Split-TopLevel([string]$s) {
    $parts = New-Object System.Collections.Generic.List[string]
    $cur = ''
    $q = $null   # 현재 열린 따옴표 문자(' 또는 ") 또는 $null
    # 인덱스 순회 — 백슬래시 이스케이프를 보려면 다음 문자를 함께 소비해야 하므로.
    $chars = $s.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]
        if ($q -eq "'") {
            # 작은따옴표 안: bash는 여기서 이스케이프가 없다 — 다음 ' 까지 전부 리터럴.
            $cur += $ch
            if ($ch -eq "'") { $q = $null }
        } elseif ($q -eq '"') {
            # 큰따옴표 안: 백슬래시가 다음 문자를 이스케이프 → \" 가 인용을 닫지 않게 둘 다 리터럴 보존.
            if ($ch -eq '\' -and $i + 1 -lt $chars.Length) {
                $cur += $ch; $cur += $chars[$i + 1]; $i++
            } else {
                $cur += $ch
                if ($ch -eq '"') { $q = $null }
            }
        } else {
            # 인용 밖: 백슬래시가 다음 문자를 이스케이프한다(H1 후속 D1). \"·\'·\; 등이 인용 열기·구분자로
            #   오인되지 않게 둘 다 리터럴로 소비 — 이게 없으면 'echo \" ; rm -rf /'에서 \"가 따옴표를
            #   열어 ;가 분리되지 않고 한 sub로 뭉쳐(→ echo 데이터 제거가 rm까지 삭제) 미탐이었다.
            #   문자열 끝 단독 \ (다음 문자 없음)는 그대로 append. bash 시맨틱과 일치.
            if ($ch -eq '\' -and $i + 1 -lt $chars.Length) {
                $cur += $ch; $cur += $chars[$i + 1]; $i++
            } elseif ($ch -eq '"' -or $ch -eq "'") {
                $q = $ch; $cur += $ch
            } elseif ($ch -eq ';' -or $ch -eq '|' -or $ch -eq '&' -or $ch -eq "`n" -or $ch -eq "`r") {
                $parts.Add($cur); $cur = ''
            } else {
                $cur += $ch
            }
        }
    }
    $parts.Add($cur)
    return $parts
}
# 줄-이음(PowerShell 백틱+개행, bash 백슬래시+개행)은 셸이 한 명령으로 잇는다 — 개행 분리 '전에'
#  전역 1회 공백으로 합쳐, 이어진 명령(rm -rf \<개행>/)이 두 sub로 갈라져 미탐되는 것을 막는다.
# 줄-이음은 백슬래시/백틱 '직후' 개행만 해당한다(D2). 중간에 공백이 있는 '\ <개행>'는 bash에서
#  줄-이음이 아니라 '이스케이프된 공백 + 명령 종결 개행'이므로 결합하지 않는다 — 결합하면 다음 줄
#  명령(chmod 등)이 앞 명령과 한 논리 줄로 붙어 ^앵커 패턴을 벗어나 미탐된다. 그래서 \s* 없이 \r?\n.
$cmdJoined = $cmd -replace '`\r?\n', ' '
$cmdJoined = $cmdJoined -replace '\\\r?\n', ' '
$subs = Split-TopLevel $cmdJoined

foreach ($sub in $subs) {
    $sub = $sub.Trim()
    if ([string]::IsNullOrWhiteSpace($sub)) { continue }

    # ---- 오탐 완화: '데이터'(실행되지 않는) 인자를 스캔 대상에서 제거 ----
    # git 커밋 메시지·echo/printf 출력·grep 검색 패턴·sed/awk 스크립트는 텍스트일 뿐 실행되지 않으므로,
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
    if ($scan -match '(?i)(^|\s)(grep|egrep|fgrep|rg|ag|ack|sed|awk)(\s|$)') {
        # grep 계열 검색 패턴 + sed/awk 스크립트(따옴표) 제거 — 텍스트 처리기라 따옴표 인자는
        # 패턴/치환 스크립트일 뿐 SQL·명령을 실행하지 않는다(L1: sed -i 's/DROP TABLE//' 오탐 방지)
        $scan = ($scan -replace '"[^"]*"', ' ') -replace "'[^']*'", ' '
    }

    # ---- 컴파운드 검사: 재귀 삭제 (옵션 순서·따옴표·글롭 변형 무관) ----
    # rm/Remove-Item/rmdir/rd/del 계열이 '재귀' 플래그를 갖고(강제 플래그 유무 무관 — H2:
    #   위험루트 재귀 삭제는 -f 없이도 비가역이라 rm -r /home/user·rm -r * 가 통과하면 안 됨),
    # 대상이 위험 루트(/, /*, //, ~, $HOME, *, ., ./, 드라이브 루트 C:\, $env:) 또는
    #   시스템 디렉터리(POSIX /usr·/etc…, Windows C:\Windows·Program Files·ProgramData 및 /c/·/mnt/c/ 마운트)이면 차단.
    # 단일 정규식이 못 잡던 변형을 포착: rm -fr /, rm -r /, rm --recursive /,
    #   rm -rf /*, rm -rf "/", rm -rf //, Remove-Item C:\ -Recurse(인자 순서) 등.
    #
    # [오탐 방지 — D2] 위험 판정을 '삭제 명령이 있는 그 줄(인자 윈도우)'에 연계한다. 명령 앞의
    #   -replace 연산·변수 정의나 '다른 문장 줄'의 경로 구분자(/·C:/)가 재귀 플래그와 잘못
    #   결합되는 오탐을 막는다. 단, 줄-이음(PowerShell 백틱+개행 · bash 백슬래시+개행)은 셸이 한 명령으로
    #   잇는 것이라 먼저 공백으로 정규화해 한 논리 줄로 합친다 — 대상이 다음 물리 줄에 와도 차단되게 해
    #   미탐을 막는다(예: bash에서 rm -rf 뒤 백슬래시+개행+/ 는 실제 rm -rf / 로 실행됨).
    $norm = $scan -replace '`\r?\n', ' '       # PowerShell 백틱 줄-이음(백틱 직후 개행만 — D2)
    $norm = $norm -replace '\\\r?\n', ' '      # bash 백슬래시 줄-이음(백슬래시 직후 개행만 — D2)
    # $dangerTarget(위험 대상 정규식)은 위(파일 상단, 사전검사 공유)에서 1회 정의했다 — 루프 불변.
    # 대소문자 무시(?i) — PowerShell cmdlet·alias는 케이스 무관하게 실행되므로(REMOVE-ITEM·RM·Del 등)
    #   토큰 매칭도 무시해야 한다. 이게 없으면 대문자 변형이 컴파운드 삭제 검사를 통째로 우회한다(H1).
    # 앞 경계에 ["'] 포함 — 인터프리터 문자열 안 삭제(bash -c "rm -rf /"·eval "rm -rf /")는 따옴표가
    #   보존돼 rm 앞이 " 가 되므로, (^|\s)만으론 미탐이었다. 뒤 경계 (\s|$)는 불변 — 확장하면
    #   'rm'(SQL 문자열 등 정상) 매치 표면만 넓히고 실익은 "rm" -rf /(명령어 완전 따옴표) 1건뿐이라,
    #   그 케이스는 $(echo /)처럼 '알려진 미탐'으로 남긴다(안전 hook 오탐 최소화 우선).
    #   트레이드오프: 앞경계 ["'] 확장으로, echo/printf/grep/git과 '달리' 인자가 데이터로 스트립되지
    #   않는 명령의 따옴표 인자에 rm+위험대상 문자열이 들어가도 차단될 수 있다(예: notify-send 'rm -rf /').
    #   (echo/printf/grep/git은 190~196행에서 인자를 스트립하므로 echo "rm -rf /"는 오차단 안 됨.)
    #   이는 과소 차단보다 과잉 차단을 택하는 안전 hook 설계 방향과 일치 — 오차단 시 사용자가 직접 실행하면 됨.
    $delMatches = [regex]::Matches($norm, '(?i)(^|\s|["''])(' + $delCmdAlt + ')(\s|$)')
    foreach ($dm in $delMatches) {
        # 삭제 명령 토큰부터 다음 줄바꿈 전까지가 그 명령의 인자 윈도우.
        # 선행 공백·개행을 먼저 제거한다(H1 방어) — 매치가 (^|\s)로 시작해 선행 \n을 포함하면
        # 아래 줄바꿈 컷이 윈도우를 빈 문자열로 만들어(따옴표 안 개행이 sub에 남는 경우) 미탐이 된다.
        $win = $norm.Substring($dm.Index).TrimStart()
        $nlIdx = $win.IndexOfAny([char[]]@("`n", "`r"))
        if ($nlIdx -ge 0) { $win = $win.Substring(0, $nlIdx) }

        # 재귀 플래그: 짧은 묶음(-r/-rf/-fr/-Rf) | -Recurse | PS 약어(-re/-rec…, -replace 연산자는 lookahead로 제외) | --recursive | cmd /s
        $hasRecurse = ($win -match '(^|\s)-[rfRF]*r[rfRF]*(\s|$)') -or
                      ($win -match '(^|\s)-Recurse\b') -or
                      ($win -match '(^|\s)-(?!replace\b)[rR]e[a-z]*(\s|$)') -or    # -replace(문자열 연산자)만 제외, -re/-rec/-recurse 유지
                      ($win -match '--recursive\b') -or
                      ($win -match '\s/s\b')
        # 강제 플래그는 요구하지 않는다(H2) — 위험루트 재귀 삭제는 -f 없이도 대부분 즉시 실행·비가역이다
        #   (rm -r은 쓰기보호 파일에만 묻고, Remove-Item은 숨김/읽기전용 외엔 그냥 지운다).
        if ($hasRecurse -and ($win -match $dangerTarget)) {
            [Console]::Error.WriteLine("BLOCKED: 재귀 삭제 + 위험 루트 대상 감지")
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
