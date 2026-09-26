# Google Play 데이터 안전 선언 — 최종안

작성 기준 HEAD `8945257` · 최종 수정 2026-09-26 · 개인정보 처리방침 개정 `2026-09-26`

이 문서는 **그대로 Play Console 에 입력할 수 있는 상태**를 목표로 한다.
모든 YES / NO 에 source 근거를 붙였다. 근거 없이 적은 칸은 없다.

> 이 문서는 제출물이 아니다. 실제 Play Console 입력은 별도 승인 후 수행한다.

---

## 0. 판단 규칙

**Collected** — 앱 또는 앱에 포함된 SDK 가 기기 밖으로 데이터를 내보내면 YES.
앱 코드가 직접 보내지 않아도 SDK 가 보내면 YES 다.

**Shared** — 제3자에게 전달하면 YES. 단 Play 가 명시한 예외는 Shared 가 아니다.
이 문서는 예외를 쓸 때마다 **어느 예외인지** 적는다.

- `USER-INITIATED` — 사용자가 시작한 특정 행위에 따른 전달
- `DISCLOSED-CONSENTED` — 고지하고 동의받은 전달
- `SERVICE-PROVIDER` — 우리를 대신해 처리하는 수탁자
- `LEGAL` — 법령에 따른 전달

한국 개인정보보호법의 "제3자 제공" 과 같은 말로 쓰지 않는다. 별개 기준이다.

**Required / Optional** — **모든 사용자가 수집을 선택하지 않을 수 있을 때만** Optional.
"그 기능을 안 쓰면 된다" 는 Optional 의 근거가 아니다.

---

## 1. 앱에 들어 있는 수집 주체 — 전수

| SDK / 경로 | 버전 | 기기→서버 | 수신자 | 근거 |
|---|---|---|---|---|
| `firebase_analytics` | ^11.3.6 | YES | Google | `lib/services/analytics_service.dart` · `main.dart` navigatorObservers |
| `firebase_crashlytics` | ^4.1.3 | YES | Google | `main.dart` `FlutterError.onError` / `PlatformDispatcher.onError` |
| `firebase_messaging` | ^15.1.5 | YES | Google | `fcm_service.dart` `getToken()` → `users.fcmTokens` |
| `firebase_core` / `firebase_auth` / `cloud_firestore` / `firebase_storage` / `cloud_functions` | — | YES | Google (우리 프로젝트) | 앱 전역 |
| `firebase_app_check` | ^0.3.2+2 | YES | Google | `main.dart` Play Integrity / DeviceCheck |
| `firebase_remote_config` | ^5.4.0 | YES | Google | `tax_identity_service.dart` |
| `iamport_flutter` (PortOne / KG이니시스) | ^0.10.21 | YES | PortOne → KG이니시스 | `pass_verification_service.dart` |
| `geolocator` | ^13.0.2 | YES (출퇴근 시) | 우리 서버 | `location_helper.dart` → `callableCheckIn` |
| `google_mlkit_text_recognition` | ^0.15.0 | **NO** | — | `InputImage.fromFilePath` — 기기 내 처리, 네트워크 호출 없음 |
| `flutter_blue_plus` | ^1.35.5 | **NO** | — | `beacon_helper.dart` — 근접 판정만, 서버 쓰기 없음 |
| `image_picker` / `flutter_image_compress` | — | YES (업로드 시) | 우리 Storage | `document_upload_helper.dart` |
| `webview_flutter` | ^4.4.2 | 주소검색 WebView | 카카오(다음) 주소 API | `daum_address_search_mobile.dart` |
| `connectivity_plus` / `package_info_plus` / `shared_preferences` | — | NO | — | 기기 로컬 |

### 수집 주체가 아닌 나머지 의존성 — 전수

아래는 기기 밖으로 사용자 데이터를 내보내지 않는다. 의존성 목록을 **전부**
적는다 — 빠진 이름이 생기면 계약 테스트가 실패한다.

| 의존성 | 왜 수집 주체가 아닌가 |
|---|---|
| `flutter` · `flutter_localizations` · `cupertino_icons` | 프레임워크·아이콘 |
| `provider` | 앱 내부 상태 |
| `flutter_local_notifications` | 수신한 알림을 기기에서 표시만 |
| `loading_animation_widget` · `flutter_svg` · `shimmer` · `fl_chart` · `table_calendar` | 화면 표시 |
| `cached_network_image` | 우리 Storage 이미지 캐시 |
| `permission_handler` | OS 권한 상태 조회·요청 |
| `intl` | 서식 |
| `http` | 우리 서버·Firebase 호출용 클라이언트. `lib/` 에 `http://` 0건 |
| `path_provider` | 임시 디렉터리 경로 |
| `shared_preferences` | 온보딩 여부 등 기기 로컬 값 |
| `url_launcher` | 전화·지도 앱 실행 |
| `encrypt` · `pointycastle` · `crypto` | 계좌번호 암호화·해시 |
| `pdf` · `printing` · `excel` | 기기에서 문서 생성 |
| `share_plus` | 사용자가 직접 고른 앱으로 내보내기 (`USER-INITIATED`) |
| `signature` | 서명 입력 위젯 — 저장은 우리 Storage |
| `flutter_native_splash` | 시작 화면 |

`file_picker` 는 의존성에 없다 — 임의 파일 접근 경로가 없다.

### Android 권한 ↔ 실제 수집

| 권한 | 선언 | 실제 수집 | 근거 |
|---|---|---|---|
| `ACCESS_FINE_LOCATION` | YES | **YES** | `LocationAccuracy.high` + `checkInLat/checkInLng` 저장 |
| `ACCESS_COARSE_LOCATION` | YES | 위 요청에 수반 | 동일 경로 |
| `ACCESS_BACKGROUND_LOCATION` | **미선언** | **NO** | manifest 에 없음 · `getPositionStream()` 호출부 0건 |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` (maxSdk 30) | YES | NO | 구버전 호환용 — 스캔 결과 미전송 |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` | YES | NO | 비콘 근접 판정 결과만 사용, 스캔 결과 미전송 |
| `POST_NOTIFICATIONS` | YES | — | 표시용 |
| `INTERNET` / `ACCESS_NETWORK_STATE` | YES | — | 통신 |

> 권한 선언만 보고 수집을 추정하지 않았다. 각 행은 호출부로 확인했다.

---

## 2. 최종 선언 매트릭스

### Location

| PLAY DATA TYPE | Approximate location | Precise location |
|---|---|---|
| **COLLECTED** | YES | **YES** |
| **SHARED** | NO | NO |
| **SHARING EXCEPTION** | `SERVICE-PROVIDER` (Google Analytics) | `DISCLOSED-CONSENTED` + `USER-INITIATED` |
| **EPHEMERAL** | NO | **NO** — 저장됨 |
| **REQUIRED / OPTIONAL** | Required | **Required** |
| **PURPOSES** | Analytics | App functionality · Fraud prevention, security, and compliance |
| **SOURCE EVIDENCE** | `firebase_analytics` 의존 + 수집 비활성화 플래그 없음(아래 §3) — Google 이 IP 기반으로 대략적 위치를 산출 | `location_helper.dart:89` `LocationAccuracy.high` → `index.ts:32491` GPS 필수 게이트 → `index.ts:32582` `checkInLat/checkInLng` 저장 |
| **SDK / RECIPIENT** | Google | 우리 서버(Firestore), 근무한 사업장의 관리자 |
| **PRIVACY POLICY SECTION** | 서비스 접속·이용 로그 | 출퇴근 기록 |
| **INLINE DISCLOSURE** | — | `PrivacyDisclosure.location` (권한 팝업 직전) |
| **CONFIDENCE** | SDK-BASIS (앱 코드 아님) | SOURCE-CONFIRMED |

**Precise location 이 Required 인 이유** — `attendanceType` 이 `gps` / `beacon` / `both`
인 사업장에서는 좌표 없이 출근이 서버에서 거부된다(`index.ts:32491`). 비콘 전용
사업장도 마찬가지다 — bare beacon 원격 체크인을 막기 위해 좌표를 함께 요구한다.
`manual` 사업장에서는 근로자 self check-in 자체가 없어 위치를 쓰지 않지만, 그것은
**사업장 설정**이지 사용자의 선택이 아니다. 따라서 Optional 이 아니다.

**Precise location 이 Shared=NO 인 근거** — 수신자는 근로자가 **스스로 출근을 누른**
그 사업장이고(`USER-INITIATED`), 저장·열람 사실을 권한 팝업 직전 고지와 처리방침이
함께 적는다(`DISCLOSED-CONSENTED`). 좌표를 화면에 그리지는 않지만
`callableGetAdminAttendances` 응답에는 들어 있다 — 그래서 "관리자가 근무 기록으로
확인할 수 있다" 고 고지에 명시했다.

### Personal info

| PLAY DATA TYPE | COLLECTED | SHARED | EXCEPTION | REQ/OPT | PURPOSES | SOURCE EVIDENCE |
|---|---|---|---|---|---|---|
| Name | YES | NO | `USER-INITIATED` (지원 시 사업장에 표시) | Required | App functionality · Account management · Fraud prevention | `verifyPassAuth` `cert.name` (index.ts:9086) · 외국인 `legalName` |
| Phone number | YES | NO | `USER-INITIATED` | Required | App functionality · Account management · Fraud prevention | `cert.phone` (index.ts:9089) · `users.authPhone/contactPhone` · `worker_detail_dialog.dart:1977` 전화걸기 |
| Email address | **NO** | — | — | — | — | 실제 이메일을 받지 않는다. `auth_service.dart:43` `'$username@ALfit-system.com'` 합성 식별자 |
| User IDs | YES | NO | `SERVICE-PROVIDER` (Analytics) | Required | App functionality · Account management · Analytics | Firebase uid · `analytics_service.dart:27` `setUserId(uid)` |
| Address | YES | NO | — | **Optional** | App functionality | `user_model.dart:45` · `profile_edit_screen.dart:265` — 프로필 수정에서만 입력, 가입·지원 필수 아님 |
| Other info | YES | NO | `DISCLOSED-CONSENTED` | Required | App functionality · Fraud prevention · **법정 신고** | 생년월일·성별(`verifyPassAuth`), `ciHash`, 세무 식별번호(아래 §5) |

Race/ethnicity · Political or religious beliefs · Sexual orientation — **NO.**
해당 입력 필드가 없다.

### Financial info

| PLAY DATA TYPE | COLLECTED | SHARED | EXCEPTION | REQ/OPT | PURPOSES | SOURCE EVIDENCE |
|---|---|---|---|---|---|---|
| User payment info | YES | NO | `DISCLOSED-CONSENTED` | Required | App functionality | `users.bankName/accountNumber/accountHolder` — `accountNumber` 는 `EncryptionHelper` 로 암호화 저장(`user_model.dart:627`). 지원 전제조건(USER PRODUCT POLICY §5) |
| Other financial info | YES | NO | `DISCLOSED-CONSENTED` | Required | App functionality | 임금·급여 결과 `finalWage` · `wageDetail` · `payroll_summaries` |
| Purchase history | NO | — | — | — | — | 앱에 결제 기능 없음. `iamport_flutter` 는 본인인증 전용(`pass_verification_service.dart`) |
| Credit score | NO | — | — | — | — | 해당 없음 |

**통장 사본의 이중 선언 여부** — 통장 사본 **이미지**는 `Photos` 로 한 번만 선언한다.
`User payment info` 로 중복 선언하지 않는다. 계좌의 금융 값(은행명·계좌번호·예금주)은
이미지와 별개로 텍스트 필드에 저장되며 그쪽이 `User payment info` 다. 즉
**금융 값 = User payment info, 제출 이미지 = Photos** 로 나눈다 — 같은 값을 두 번
세지 않는다. `Files and docs` 는 쓰지 않는다: 앱에 파일 선택기가 없고
(`file_picker` 미의존) 모든 제출물이 `image_picker` 를 통한 사진이다.

### Photos and videos

| PLAY DATA TYPE | COLLECTED | SHARED | EXCEPTION | REQ/OPT | PURPOSES | SOURCE EVIDENCE |
|---|---|---|---|---|---|---|
| Photos | YES | NO | `DISCLOSED-CONSENTED` | Required | App functionality · Fraud prevention | 신분증·외국인등록증(`users/{uid}/idCard_*.jpg`), 통장 사본, 사업자등록증, 프로필 사진 |
| Videos | NO | — | — | — | — | 영상 입력 경로 없음 |

프로필 사진만 놓고 보면 Optional 이지만, 신분증·통장 사본은 지원 전제조건이므로
**타입 전체로는 Required** 다. Play 는 데이터 타입 단위로 답한다.

### App activity

| PLAY DATA TYPE | COLLECTED | SHARED | EXCEPTION | REQ/OPT | PURPOSES | SOURCE EVIDENCE |
|---|---|---|---|---|---|---|
| App interactions | YES | NO | `SERVICE-PROVIDER` | Required | Analytics | `main.dart:193` `AnalyticsService.observer` 화면 전환 + `logEvent` 8종 |
| In-app search history | YES | NO | `SERVICE-PROVIDER` | Required | Analytics | `analytics_service.dart:163` `logSearch(city, toType)` — 자유 입력이 아닌 필터 값 |
| Other user-generated content | YES | NO | `USER-INITIATED` | Required | App functionality | 근무 평가(`monthly_reviews`), 근로계약 서명 이미지, 공고 본문 |
| Installed apps | NO | — | — | — | — | 설치 앱 조회 경로 없음 |
| Other actions | NO | — | — | — | — | 위 네 종 외 행동 수집 없음 |
| Web browsing history | NO | — | — | — | — | 주소검색 WebView 는 방문 기록을 수집하지 않는다 |

### App info and performance

| PLAY DATA TYPE | COLLECTED | SHARED | EXCEPTION | REQ/OPT | PURPOSES | SOURCE EVIDENCE |
|---|---|---|---|---|---|---|
| Crash logs | YES | NO | `SERVICE-PROVIDER` | **Required** | App functionality(안정성) · Analytics | `main.dart:108-111` — 전역 핸들러, opt-out 없음 |
| Diagnostics | YES | NO | `SERVICE-PROVIDER` | **Required** | App functionality · Analytics | Crashlytics 진단 + Analytics 자동 수집 |
| Other app performance data | NO | — | — | — | — | Performance Monitoring 미사용(`firebase_performance` 미의존) |

### Device or other IDs

| PLAY DATA TYPE | COLLECTED | SHARED | EXCEPTION | REQ/OPT | PURPOSES | SOURCE EVIDENCE |
|---|---|---|---|---|---|---|
| Device or other IDs | YES | NO | `SERVICE-PROVIDER` | Required | App functionality(알림) · Analytics · Fraud prevention | `fcm_service.dart:282-307` `fcmToken`/`fcmTokens` 저장 · Analytics app instance ID · App Check 기기 무결성 토큰 |

### 선언하지 않는 카테고리

Health and fitness · Messages · Audio files · Calendar · Contacts · Files and docs
— 전부 **NO.** 해당 권한도 SDK 도 없다.

---

## 3. Firebase Analytics — 현재 소스 확인

| 확인 항목 | 결과 | 근거 |
|---|---|---|
| 초기화 | YES | `analytics_service.dart:11` `FirebaseAnalytics.instance` |
| 기본 수집 활성 | **YES** | `setAnalyticsCollectionEnabled` 호출 0건, manifest 에 `firebase_analytics_collection_deactivated` 없음 |
| `setUserId` | **YES — uid 전송** | `analytics_service.dart:27` |
| 사용자 속성 | `user_role` | `analytics_service.dart:28` |
| 화면 추적 | YES | `main.dart:193` navigatorObservers |
| 이벤트 | 로그인·가입·공고조회/등록·지원/취소/확정·출퇴근·급여확정·검색·오류 | `analytics_service.dart` 전체 |
| **opt-out 존재** | **없음** | 설정 화면에 수집 토글 없음 |
| 디버그 제외 | `if (kDebugMode) return` — 릴리스에서는 전부 전송 | 각 메서드 첫 줄 |

→ **COLLECTED = YES / OPTIONAL = NO (Required).** 이전 판단과 같다.

**주의할 값 하나** — `logTOView` / `logApply` 가 `businessName` 을 파라미터로 보낸다.
이것은 사업장 상호이지 개인정보가 아니다. 개인 식별자는 `setUserId(uid)` 뿐이다.

## 4. Firebase Crashlytics — 현재 소스 확인

| 확인 항목 | 결과 | 근거 |
|---|---|---|
| 활성화 | YES (웹 제외) | `main.dart:107` `if (!kIsWeb)` |
| Flutter 치명 오류 | YES | `recordFlutterFatalError` |
| 플랫폼 오류 | YES | `PlatformDispatcher.instance.onError` |
| non-fatal 수동 기록 | YES | `document_management_screen.dart:965` |
| `setUserIdentifier` | **호출 없음** | grep 0건 — uid 를 Crashlytics 에 붙이지 않는다 |
| `setCrashlyticsCollectionEnabled` | **호출 없음** | 즉 기본값(활성) |
| **opt-out 존재** | **없음** | — |
| 릴리스/디버그 차이 | 코드상 분기 없음 | `kDebugMode` 가드 없음 |

→ **Crash logs / Diagnostics = Required.** "기능상 중요하지 않다" 는 이유로
Optional 로 쓰지 않았다.

## 5. 세무 식별정보 (주민등록번호 / 외국인등록번호)

Play taxonomy 에 "주민등록번호" 항목은 없다. **없다고 신고하지 않는다.**
가장 가까운 타입인 **Personal info → Other info** 로 신고하고 근거를 남긴다.

| 추적 항목 | 사실 | 근거 |
|---|---|---|
| 기기에서 원문 입력 | YES — 13자리 | `_TaxIdentitySheet` (`document_management_screen.dart`) |
| 서버 전송 | YES | `callableRegisterTaxIdentity` / `callableUpdateTaxIdentity` |
| 저장 형태 | **암호화** + 지문 | `srvEncryptTaxIdentifier` (index.ts:1817), `identifierFingerprint` |
| 원문 재열람(본인) | **불가** | `callableGetTaxIdentityStatus` 응답에 번호 없음 |
| 관리자 열람 가능 값 | 전체 번호 | `callableGetTaxIdentityNumber` (index.ts:29737) |
| 열람 조건 | 권한 + **현재 세무 처리 사유** + 화면이 보고 있는 버전 일치 | `srvAssertTaxIdentityAuthority` · `srvHasCurrentTaxIdentityPurpose` · `expectedIdDocumentVersion`/`expectedTaxIdentityFingerprint` |
| 감사 | **fail-closed** | `srvLogTaxIdentityAudit(..., {failClosed: true})` — 기록 실패 시 번호를 내보내지 않음 |
| 수집 스위치 | Remote Config `tax_identity_collection_enabled` (기본 false) + 서버 동일 스위치 | `tax_identity_service.dart:34` |
| 삭제 | 탈퇴 시 `taxIdentities/{uid}` 삭제 | 계정 삭제 런북 §5-B 1 |
| 수신자 | 함께 일하는 사업장의 관리자 | 위 게이트 |

**Required 판정** — 수집 스위치가 꺼져 있으면 화면 자체가 뜨지 않는다. 그러나 그것은
운영 스위치이지 사용자의 선택이 아니다. 켜진 상태에서 근로자가 번호를 거부하면
소득신고 처리가 불가능하다. 따라서 **Required.**

**Shared = NO** — 수신자는 근로자가 실제로 근무 중인 사업장이고, 목적(소득신고·
원천징수)·조건·감사 사실을 입력 직전에 고지한다(`PrivacyDisclosure.taxIdentity`).
`DISCLOSED-CONSENTED` 예외에 해당한다.

## 6. 신분증 / 통장 사본 — Shared 판정

| 항목 | 수신자 | TRIGGER | USER-INITIATED | 예상 가능 | 명시 고지 | SERVICE PROVIDER | PLAY 예외 |
|---|---|---|---|---|---|---|---|
| 이름 · 연락처 · 일반 지원 정보 | 지원한 사업장 | 근로자가 지원 | YES | YES | 처리방침 | NO | `USER-INITIATED` |
| 계좌 정보(은행·계좌번호·예금주) | 근무한 사업장 | 급여 지급 | 간접 | YES | 처리방침 | NO | `DISCLOSED-CONSENTED` |
| 통장 사본 원본 | 근무한 사업장 | **지급 대상 근무가 있을 때만** — `srvAssertCurrentPayrollPurpose` | 간접 | YES | 처리방침 + 업로드 화면 | NO | `DISCLOSED-CONSENTED` |
| 신분증 원본 | 근무한 사업장 | **세무 확인을 누른 순간만** — `callableGetTaxIdentityIdCardUrl`, 1시간 만료 URL | 간접 | YES | `PrivacyDisclosure.idDocument` | NO | `DISCLOSED-CONSENTED` |
| 세무 식별번호 | 근무한 사업장 | 위 §5 게이트 | 간접 | YES | `PrivacyDisclosure.taxIdentity` | NO | `DISCLOSED-CONSENTED` |
| 정밀 위치 | 근무한 사업장 | 근로자가 출근 버튼을 누름 | **YES** | YES | `PrivacyDisclosure.location` | NO | `USER-INITIATED` + `DISCLOSED-CONSENTED` |
| 본인인증 정보(이름·연락처·생년월일·통신사) | PortOne → KG이니시스 | 가입 시 본인인증 | YES | YES | 처리방침 | **YES** | `SERVICE-PROVIDER` + `LEGAL` |
| 진단·이용 통계 | Google | 자동 | NO | — | 처리방침 | **YES** | `SERVICE-PROVIDER` |

> 관리자가 근로자 정보를 본다는 사실만으로 Shared=YES 로 적지 않았다. 각 행을
> 수신자·트리거·고지·예외로 따로 판단했다.

**이 판정이 뒤집히는 조건** — 어떤 항목의 inline/정책 고지에서 **수신자 또는 목적**이
빠지면 `DISCLOSED-CONSENTED` 예외가 성립하지 않는다. 그때는 그 행만
Shared = YES 로 바꾸고 수신자 유형을 함께 신고한다. 지금은 여섯 항목 모두
고지가 존재한다(§7 표 참조).

## 7. 화면 내 고지 (inline disclosure)

| SURFACE | 위치 | 고지 시점 | 구현 |
|---|---|---|---|
| 정밀 위치 | 출퇴근 체크 화면 | **OS 권한 팝업 직전** (`willPromptForPermission()` 이 true 일 때 1회) | `attendance_check_screen._verifyByGPS` |
| 신분증 업로드 | 서류 관리 > 신분증 카드 | 업로드 버튼 **위** | `document_management_screen._buildIdCardSection` |
| 세무 식별정보 | 세무정보 등록 시트 | 입력 칸 **위** | `document_management_screen._TaxIdentitySheet` |

문구는 `lib/widgets/common/privacy_inline_notice.dart` 한 곳에만 있다. 각 문장의
근거를 주석으로 붙였고, 계약 테스트가 문구와 구현의 일치를 지킨다.

고지 원칙: 새 modal 을 만들지 않았고(위치는 기존 `DialogHelper.showConfirm` 재사용),
동의를 다시 받지 않으며, 처리방침 링크를 누르지 않아도 목적을 알 수 있다.

---

## 8. Play Console 전역 질문 — 최종 답변

| 질문 | 답 | 근거 |
|---|---|---|
| 앱이 사용자 데이터를 수집 또는 공유합니까? | **예 (수집함 / 공유 없음)** | §2 매트릭스 |
| 수집된 모든 데이터가 전송 중 암호화됩니까? | **예** | `lib/` 내 `http://` 0건 · `usesCleartextTraffic` / `network_security_config` 미선언 · 모든 경로가 Firebase SDK(TLS) 또는 `https://api.iamport.kr`(서버→서버) |
| 사용자가 데이터 삭제를 요청할 수 있습니까? | **예** | 앱 내 탈퇴 + 웹 요청 경로 |
| 계정 삭제 URL | **아래 §9 — PROD 배포 후 확정** | — |
| 앱 내 삭제 경로 | `설정 > 회원탈퇴` (`settings_screen` → 재인증 → `callableDeleteAccountFinal`) | 계정 삭제 런북 §0 |

> "모든 데이터 전송 암호화 = 예" 는 자동으로 적지 않았다. 평문 HTTP 경로를 전수
> 검색해 0건임을 확인하고 답했다.

## 9. 계정 삭제 URL — 확정 전 남은 일

| 환경 | URL | 상태 |
|---|---|---|
| DEV | `https://alfit-89567.web.app/account-deletion` | **배포됨 · HTTP 200 · 인증 없음 (검증 완료)** |
| PROD | `https://alfit-prod.web.app/account-deletion` | **미배포** — `.firebaserc` 의 `prod` = `alfit-prod` |

출시 빌드가 가리키는 Firebase 프로젝트는 PROD 다. 그러므로 Play Console 에 넣을
URL 은 **PROD 호스팅에 `public/` 을 배포한 뒤** 그 URL 로 확정한다. 이 Phase 는
PROD 를 건드리지 않으므로 여기서 확정하지 않는다.

이것은 새 blocker 가 아니라 이미 열려 있는 **PROD RELEASE DEPLOYMENT PENDING**
게이트의 일부다(개인정보 처리방침 PROD 동기화와 같은 게이트).

---

## 10. 법률·세무 확인과 분리되는 항목

Play taxonomy 판단(이 문서)과 COUNSEL 의존 항목은 다른 문제다. 아래는
`docs/release-privacy-gate.md` 가 관리하며, **이 매트릭스의 YES/NO 를 바꾸지 않는다.**

- 각 기록의 보존 기간 (근로기준법 외 항목)
- 출퇴근 기록의 독립 class 여부
- `account_deletion_records` 보존 기간
- 통신비밀보호법 적용 여부

보존 기간이 미확정이라는 것과, 어떤 데이터를 수집하느냐는 별개다. 후자는 확정됐다.

## 11. 이 문서가 낡는 순간

다음이 바뀌면 이 문서는 즉시 낡는다. 계약 테스트
(`test/play_data_safety_contract_test.dart`) 가 아래를 감시한다.

- `pubspec.yaml` 에 새 SDK 추가
- `AndroidManifest.xml` 에 새 권한 추가
- Analytics / Crashlytics 수집 토글 도입
- 위치 · 계좌 · 세무 식별정보 수집 경로 추가·제거
- 계정 삭제 공개 URL 변경
