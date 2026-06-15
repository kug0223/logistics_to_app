# AlFit 안티패턴 탐지 스크립트 (Layer 2 QA)
# 실행: scripts\check_antipatterns.ps1

param([string]$Dir = "")

if ($Dir -eq "") {
    $Dir = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"
}

$issues = 0

function Find-Pattern {
    param([string]$Label, [string]$Pattern, [string]$Desc)
    $dartFiles = Get-ChildItem -Path $Dir -Filter "*.dart" -Recurse -ErrorAction SilentlyContinue
    $found = @()
    foreach ($f in $dartFiles) {
        $lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $Pattern) {
                $rel = $f.FullName.Replace($Dir + "\", "lib\")
                $found += "${rel}:$($i+1)  $($lines[$i].Trim())"
            }
        }
    }
    if ($found.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARNING] [$Label] $Desc" -ForegroundColor Yellow
        foreach ($line in $found) { Write-Host "   $line" -ForegroundColor Red }
        $script:issues += $found.Count
    } else {
        Write-Host "[OK] [$Label] $Desc" -ForegroundColor Green
    }
}

Write-Host "=== AlFit 안티패턴 탐지 ===" -ForegroundColor Cyan
Write-Host "검사 대상: $Dir"
Write-Host ""

# NET-01: netWage 보험료 미차감 폴백 버그
Find-Pattern "NET-01" `
    "netWage\s*>\s*0\s*\?\s*\w+\.netWage\s*:\s*\w+\.totalAmount[^-]" `
    "netWage 보험료 미차감 폴백 버그 (totalAmount 그대로 사용)"

# TMP-01: 임시 파일 정리 누락 가능성
Find-Pattern "TMP-01" `
    "getTemporaryDirectory" `
    "임시 디렉토리 사용 -- delete() 호출 여부 수동 확인"

# LOG-01: print() 직접 사용
Find-Pattern "LOG-01" `
    "(?<![a-zA-Z_\$])print\s*\(" `
    "print() 직접 사용 -- debugPrint() 권장"

# QUERY-01: whereIn 사용 (30개 제한 확인)
Find-Pattern "QUERY-01" `
    "\.whereIn\s*\(" `
    "whereIn 사용 -- 인수 30개 이하 여부 및 주석 확인"

Write-Host ""
Write-Host "==========================="
if ($issues -eq 0) {
    Write-Host "[OK] 안티패턴 없음" -ForegroundColor Green
} else {
    Write-Host "[WARNING] 총 $issues 건 발견 -- 수동 확인 필요" -ForegroundColor Yellow
}
Write-Host ""
