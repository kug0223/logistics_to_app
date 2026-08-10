# DEV 빌드 스크립트 (Firebase: alfit-89567)
# 사용법: .\scripts\build_dev.ps1 [apk|appbundle|run]

param(
    [string]$Target = "apk"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "[DEV] Firebase 프로젝트: alfit-89567" -ForegroundColor Cyan

# 1. Android google-services.json 교체
$DevGoogleServices = Join-Path $ProjectRoot "config\dev\google-services.json"
$AndroidTarget     = Join-Path $ProjectRoot "android\app\google-services.json"

if (-not (Test-Path $DevGoogleServices)) {
    Write-Error "config\dev\google-services.json 없음"
    exit 1
}
Copy-Item $DevGoogleServices $AndroidTarget -Force
Write-Host "[DEV] google-services.json 교체 완료" -ForegroundColor Green

# 2. dart-define 읽기
$DefinesPath = Join-Path $ProjectRoot "config\dev\dart_defines.json"
if (-not (Test-Path $DefinesPath)) {
    Write-Error "config\dev\dart_defines.json 없음"
    exit 1
}
$Defines = Get-Content $DefinesPath | ConvertFrom-Json
$DartDefineArgs = ($Defines.PSObject.Properties | ForEach-Object {
    "--dart-define=$($_.Name)=$($_.Value)"
}) -join " "

# 3. 빌드
$FlutterArgs = switch ($Target) {
    "run"        { "run $DartDefineArgs" }
    "appbundle"  { "build appbundle --release $DartDefineArgs" }
    default      { "build apk --debug $DartDefineArgs" }
}

Write-Host "[DEV] flutter $FlutterArgs" -ForegroundColor Yellow
Push-Location $ProjectRoot
try {
    Invoke-Expression "flutter $FlutterArgs"
} finally {
    Pop-Location
}
