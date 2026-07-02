# PROD Firebase 배포 (alfit-prod)
# 사용법: .\scripts\deploy_prod.ps1 [all|functions|firestore|storage]
#
# 경고: 실제 서비스에 배포됩니다. 신중히 실행하세요.

param(
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# prod 프로젝트 존재 확인
$rc = Get-Content (Join-Path $ProjectRoot ".firebaserc") | ConvertFrom-Json
if ($rc.projects.prod -eq "alfit-prod" -and
    -not (firebase projects:list 2>$null | Select-String "alfit-prod")) {
    Write-Warning "alfit-prod 프로젝트가 Firebase에 없거나 접근 권한 없음"
    Write-Warning "Firebase 콘솔에서 프로젝트 생성 후 재시도"
}

Write-Host "[PROD] Firebase 배포 대상: alfit-prod" -ForegroundColor Magenta
$Confirm = Read-Host "PROD 배포를 진행하시겠습니까? (yes 입력)"
if ($Confirm -ne "yes") {
    Write-Host "배포 취소" -ForegroundColor Yellow
    exit 0
}

Push-Location $ProjectRoot
try {
    switch ($Target) {
        "functions"  { firebase deploy --only functions --project prod }
        "firestore"  { firebase deploy --only firestore --project prod }
        "storage"    { firebase deploy --only storage --project prod }
        default      { firebase deploy --project prod }
    }
    Write-Host "[PROD] 배포 완료 ✅" -ForegroundColor Green
} finally {
    Pop-Location
}
