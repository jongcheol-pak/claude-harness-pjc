# 픽스처용 최소 hook — 추출 앵커 축이 이 파일을 파싱한다.
$sectionMaxBytes = 4000
$skillsDir = Join-Path $PSScriptRoot '..' 'skills'
$s = Get-SkillSection -Path (Join-Path $skillsDir 'sample/SKILL.md') -StartHeading '## 주입 대상 절' -StopHeading '## 그다음 절'
Write-Output $s
