# DEV Firebase 배포 (alfit-89567)
# 사용법: .\scripts\deploy_dev.ps1 [all|functions|firestore|storage]

param(
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "[DEV] Firebase 배포 대상: alfit-89567" -ForegroundColor Cyan

# [CORE-.16 2026-10-28] 전용 소스 함수 — 일반 작업트리에서 배포 금지.
#   onAttendanceWageStatusChanged(DEV 00097-ruz)는 노쇼 원장 체계(A)가 있는 전용 TS 에서 빌드됐다.
#   작업트리 functions/src/index.ts 에는 그 체계가 없어(srvNsLedgerForWrite 0회) 여기서 배포하면 원장·재시도 보완이 후퇴한다.
#   전용 소스: AlFit-release-candidates/core-invite-wd-20261026/retry16/build (인계: REPORT-CORE-SHORT-TERM-LEDGER-MAX-RESTORE-AND-CLOSEOUT.16.md)
#   'functions'·'all' 은 모든 함수를 다시 올리므로 이 함수도 포함된다 → 막는다. 작업트리 소스 패리티가 맞춰질 때까지(SOURCE PARITY OPEN) 유지.
$DedicatedSourceFunctions = @("onAttendanceWageStatusChanged")
if ($Target -eq "functions" -or $Target -notin @("firestore", "storage")) {
    Write-Host "[DEV] 중단: 작업트리 전체 함수 배포는 전용 소스 함수($($DedicatedSourceFunctions -join ', '))를 덮어씁니다." -ForegroundColor Red
    Write-Host "      함수는 '--only functions:<이름>' 단위로, 전용 소스 함수는 그 전용 소스에서만 배포하세요." -ForegroundColor Red
    exit 1
}

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
