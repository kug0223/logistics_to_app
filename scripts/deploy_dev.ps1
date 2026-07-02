# DEV Firebase 배포 (alfit-89567)
# 사용법: .\scripts\deploy_dev.ps1 [all|functions|firestore|storage]

param(
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "[DEV] Firebase 배포 대상: alfit-89567" -ForegroundColor Cyan

Push-Location $ProjectRoot
try {
    switch ($Target) {
        "functions"  { firebase deploy --only functions --project dev }
        "firestore"  { firebase deploy --only firestore --project dev }
        "storage"    { firebase deploy --only storage --project dev }
        default      { firebase deploy --project dev }
    }
    Write-Host "[DEV] 배포 완료 ✅" -ForegroundColor Green
} finally {
    Pop-Location
}
