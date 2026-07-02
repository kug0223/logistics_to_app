# PROD 빌드 스크립트 (Firebase: alfit-prod)
# 사용법: .\scripts\build_prod.ps1 [apk|appbundle]
#
# 사전 준비 (최초 1회):
#   1. Firebase 콘솔 → alfit-prod 프로젝트 생성
#   2. Android 앱(com.alfit.app) 등록 → google-services.json → config\prod\google-services.json
#   3. iOS 앱(com.alfit.app) 등록 → GoogleService-Info.plist → ios\Runner\GoogleService-Info.plist
#   4. flutterfire configure --project=alfit-prod --out=lib/firebase_options_prod.dart
#   5. lib/firebase_options.dart의 prod import 주석 해제
#   6. config\prod\dart_defines.json 실제 키 입력

param(
    [string]$Target = "appbundle"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# 준비 체크
$ProdGoogleServices  = Join-Path $ProjectRoot "config\prod\google-services.json"
$ProdOptionsFile     = Join-Path $ProjectRoot "lib\firebase_options_prod.dart"
$DefinesPath         = Join-Path $ProjectRoot "config\prod\dart_defines.json"

if (-not (Test-Path $ProdGoogleServices)) {
    Write-Error "config\prod\google-services.json 없음 — Firebase 콘솔에서 Android 앱 등록 후 다운로드"
    exit 1
}
if (-not (Test-Path $ProdOptionsFile)) {
    Write-Error "lib\firebase_options_prod.dart 없음 — flutterfire configure --project=alfit-prod --out=lib/firebase_options_prod.dart 실행 필요"
    exit 1
}

$Defines = Get-Content $DefinesPath | ConvertFrom-Json
$TodoValues = $Defines.PSObject.Properties | Where-Object { $_.Value -like "여기에*" }
if ($TodoValues) {
    Write-Error "config\prod\dart_defines.json 미완성 — 실제 키 입력 필요: $($TodoValues.Name -join ', ')"
    exit 1
}

Write-Host "[PROD] Firebase 프로젝트: alfit-prod" -ForegroundColor Magenta

# 1. google-services.json 교체
$AndroidTarget = Join-Path $ProjectRoot "android\app\google-services.json"
Copy-Item $ProdGoogleServices $AndroidTarget -Force
Write-Host "[PROD] google-services.json 교체 완료" -ForegroundColor Green

# 2. dart-define 빌드
$DartDefineArgs = ($Defines.PSObject.Properties | ForEach-Object {
    "--dart-define=$($_.Name)=$($_.Value)"
}) -join " "

$FlutterArgs = switch ($Target) {
    "apk"       { "build apk --release $DartDefineArgs" }
    default     { "build appbundle --release $DartDefineArgs" }
}

Write-Host "[PROD] flutter $FlutterArgs" -ForegroundColor Yellow
Push-Location $ProjectRoot
try {
    Invoke-Expression "flutter $FlutterArgs"
    Write-Host "[PROD] 빌드 완료 ✅" -ForegroundColor Green
} finally {
    # 빌드 후 dev google-services.json으로 복원
    $DevGoogleServices = Join-Path $ProjectRoot "config\dev\google-services.json"
    if (Test-Path $DevGoogleServices) {
        Copy-Item $DevGoogleServices $AndroidTarget -Force
        Write-Host "[PROD] google-services.json → dev 복원 완료" -ForegroundColor Cyan
    }
    Pop-Location
}
