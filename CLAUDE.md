# AlFit 프로젝트 Claude 작업 지침

## 역할 분담 · 공용 기록 (2026-11-04)

- Claude = 구현·테스트·시뮬레이터 검증. Codex(gpt-6.1-sol) = 독립 감사 + 공용 기준 문서 관리.
- 공용 기록 폴더: `C:\Users\kug02\codex-audit\records` — Continuity Index / Integrity Ledger / UX Master 는 **Codex만 직접 갱신**. Claude는 읽고, 구현·실행 증거는 별도 보고서(`reports/<PhaseID>_implementation_<차수>.md` 또는 기존 보고 폴더)로 남긴다.
- 보고서에는 worktree·HEAD·미커밋 변경, 문제·writer/state/readers, 테스트 결과, DEV·시뮬레이터 증거 경로, 미실행·잔여를 적는다. 이전 차수를 덮어쓰지 않고, 전체 PRODUCT VERIFIED를 임의 선언하지 않는다.
- 감사 요청: `C:\Users\kug02\codex-audit\ask-codex.ps1` (읽기 전용, `-Records`면 records 폴더만 쓰기). 아래 정책·HOLD는 그대로 유지된다.
- 2026-11-05 대화 연결: 위 래퍼는 고정 대화 `01a1a598-83fa-7a22-9a37-c0ff9b4b9aa4` (`ALfit · Claude 협업·독립 감사`)에 공식 메시지 큐로 요청 원문과 실제 CLI 결과를 자동 누적한다. 감사 실행은 기존 읽기 전용/`-Records` 격리를 유지하고, 대화에는 출처를 표시한 전달 기록을 남긴다. UI 수신 시 같은 감사를 다시 실행하거나 공통 정본 writer를 추가하지 않는다. 직접 임시 실행·새 세션·`--last`로 이 전달 경로를 대체하지 않는다. 래퍼 호출끼리는 순서대로 실행하며, 기존 로그와 공용 기록을 보존한다.
- 이미지 여러 장은 `-Images "C:/path/a.png,D:/path/b.png"` 형식도 지원한다. 래퍼가 배열/쉼표 목록을 정규화해 감사 CLI와 대화 큐에 같은 개수로 전달한다.
- 래퍼 종료 코드 `91`은 감사 CLI 성공 후 대화 전달에 문제가 있었다는 뜻이다. 같은 감사를 다시 실행하지 말고 해당 요청 ID의 `.last.txt`·`.log`와 `.request.queue-receipt.json`·`.result.queue-receipt.json`을 확인한다. 큐 상태가 `unknown`이면 중복 여부 확인 없이 재전송하지 않는다.

## 절대 금지 사항

### Android 패키지 관련 파일 — 절대 수정 금지
다음 파일들은 어떤 이유로도 수정하지 않는다:
- `android/app/build.gradle.kts`
- `android/app/google-services.json`
- `android/app/src/main/kotlin/com/alfit/app/MainActivity.kt`

패키지명 `ALfit`도 변경하지 않는다. (Android 설정과 연동됨)

---

## 응답 언어

항상 **한국어**로 응답한다.

---

## 하단 홈버튼 / 네비게이션바 영역 처리 (SafeArea)

### 필수 규칙: 새 바텀시트/화면을 만들 때 반드시 적용

#### 바텀시트 — `DialogHelper.showSheet()` 전용 (절대 금지: 직접 showModalBottomSheet 호출)

모든 바텀시트는 반드시 `DialogHelper.showSheet()`를 사용한다.
`showModalBottomSheet`를 직접 호출하면 shape·useSafeArea 누락으로 디자인이 틀어진다.

```dart
// ✅ 올바른 패턴 — 유일하게 허용되는 방식
final result = await DialogHelper.showSheet<String>(
  context,
  isScrollControlled: true,  // 키보드가 밀어올릴 때 필요 시 추가
  builder: (ctx) => MySheet(),
);

// ❌ 절대 금지 — showModalBottomSheet 직접 호출
showModalBottomSheet(
  context: context,
  builder: (ctx) => MySheet(),
);
```

`DialogHelper.showSheet()`는 내부적으로 다음을 보장한다:
- `useSafeArea: true` (하단 홈버튼 자동 처리)
- `shape: RoundedRectangleBorder(radius: 20)` (앱 통일 디자인)

DraggableScrollableSheet처럼 `backgroundColor: transparent`가 필수인 특수 케이스에만 직접 호출을 허용한다.

#### 커스텀 하단 바 (Scaffold bottomNavigationBar / 고정 버튼)
`SafeArea(top: false)`로 감싼다.

```dart
// ✅ 올바른 패턴
Scaffold(
  bottomNavigationBar: SafeArea(
    top: false,   // 상단 safe area 제외, 하단만 처리
    child: Container(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(...),
    ),
  ),
)
```

#### 화면 전체 (`Scaffold body`)
대부분의 Scaffold는 `resizeToAvoidBottomInset: true`(기본값)로 키보드를 처리한다. 추가 SafeArea는 필요 시에만.

### 이중 처리 주의
`useSafeArea: true`와 내부 `SafeArea` 위젯을 동시에 쓰면 Flutter이 자동으로 중복 패딩을 막아주므로 시각적 문제는 없지만, 코드 명확성을 위해 `useSafeArea: true` 하나로 통일을 권장한다.

---

## 모바일 UI 공간 설계 원칙

좁은 화면(360dp 미만)에서 Row 레이아웃이 넘칠 수 있다:
- 2개 이상의 위젯을 Row에 넣을 때는 `Flexible` 또는 `Expanded` 사용
- 텍스트 + 아이콘 조합이 길어질 경우 `Wrap`으로 줄바꿈 허용
- 고정 너비(`width: 200`) 대신 비율 기반(`flex`) 사용

---

## 디자인 시스템 규칙

신규 UI는 반드시 공통 컴포넌트를 사용하고, 인라인 구현 금지:
- 색상: `AppColors.*` 사용 (하드코딩 금지)
- 텍스트 스타일: `ResponsiveHelper.bodyStyle()` 등 사용
- 카드: `CommonWidgets.compactCardDecoration()` 사용
- 아이콘: `WorkTypeIcon.buildWithBackground()` 사용

---

## 임금 구조 설계 원칙

- 주휴수당 자동계산 없음 — 관리자가 수동 입력하거나 0으로 처리
- 시급/일급 TO 레벨에서 고정 (변경 불가)
- `effectiveNetWage` getter를 사용 — `netWage`를 직접 참조하지 않는다

```dart
// ✅ 올바른 참조
final net = wageDetail.effectiveNetWage;

// ❌ 금지 — 미확정 시 0 반환
final net = wageDetail.netWage;
```

---

## 비동기 안전성

async gap 이후 `context` 또는 `setState` 사용 시 반드시 `mounted` 체크:

```dart
// ✅ 올바른 패턴
await someAsyncOperation();
if (!mounted) return;
setState(() { ... });

// ❌ 금지
await someAsyncOperation();
setState(() { ... });  // mounted 체크 없음
```

---

## Firestore 삭제 순서

Storage와 Firestore를 함께 삭제할 때 반드시 **Firestore 먼저**:

```dart
// ✅ 올바른 순서 (Firestore 실패 시 Storage는 건드리지 않음)
// 1. Storage URL 미리 수집
// 2. Firestore 삭제 (실패 시 전체 취소)
// 3. Storage 정리

// ❌ 금지
await storageRef.delete();  // Storage 먼저 삭제하면 Firestore 실패 시 broken URL 남음
await firestoreDoc.delete();
```

---

## 임시 파일 처리

`getTemporaryDirectory()`로 생성한 파일은 공유(`Share.shareXFiles`) 후 반드시 삭제:

```dart
final file = File('${dir.path}/export.xlsx');
await file.writeAsBytes(bytes);
await Share.shareXFiles([XFile(file.path)]);
await file.delete();  // 필수
```

파일을 반환하는 함수(`savePdfLocally` 등)는 호출자가 삭제 책임을 가진다.

---

## 테스트 실행

```bash
flutter test          # 전체 테스트
flutter analyze       # 정적 분석 (No issues found 확인)
```

---

## 안티패턴 탐지 스크립트

```powershell
.\scripts\check_antipatterns.ps1
```

NET-01(보험료 미차감 폴백), TMP-01(임시파일 누수), LOG-01(print 직접사용), QUERY-01(whereIn 30개 제한) 탐지.

---

## Firestore 크래시 방어 — 이미 완료된 패턴 (재탐색 금지)

### tryFromMap / tryFromFirestore 패턴 — 전체 적용 완료

다음 모델에 `tryFromMap`/`tryFromFirestore` 정적 메서드가 추가되어 있다:
`TOModel`, `SlotModel`, `ApplicationModel`, `ScheduleChangeRequestModel`,
`UserModel`, `BusinessWorkTypeModel`, `MemberInvitationModel`,
`WorkDetailData`, `TrustSettingsModel` (TrustRule 포함),
`WageDetailModel`, `LegalTerms`, `PayrollSummaryModel` (PayrollWorkerSummary 포함),
`AttendanceModel` (wageDetail 필드), `EmploymentContractModel` (slots/articles 필드),
`ContractTemplateModel` (articles 필드)

Firestore 리스트 쿼리 결과를 파싱하는 모든 서비스는 `tryFromMap + whereType<T>()` 패턴으로 전환 완료:
`to_firestore.dart`, `attendance_firestore.dart`, `application_firestore.dart`,
`business_firestore.dart`, `member_service.dart`, `firestore_service.dart` (전체)

### 잘못 탐지되기 쉬운 패턴 — HIGH 아님

```dart
// ✅ 안전 — whereType<Map>()은 Dart에서 LinkedHashMap 등 모든 Map 구현체 포함
rawList.whereType<Map>().map((s) { ... }).whereType<ContractSlot>().toList()

// ✅ 안전 — 외부 try-catch가 있으면 단일 fromMap 호출도 크래시 방지됨
try {
  final model = SomeModel.fromMap(data, id);  // 실패 시 catch로 이동
} catch (e) { debugPrint(...); }

// ✅ 안전 — Future.wait() 실패 시 outer catch가 처리, 불완전 데이터 미반영
try {
  final results = await Future.wait([queryA, queryB]);
  setState(() { ... });
} catch (e) { ToastHelper.showError(...); }  // 전체 롤백

// ✅ 안전 — 서비스 파일(StatelessService)은 mounted 개념 없음, 체크 불필요
class SomeService { Future<void> doSomething() async { ... } }

// ✅ 안전 — await 이전의 setState는 동기 컨텍스트에서 실행되므로 mounted 체크 불필요
// mounted 체크가 필요한 것은 await 이후의 setState/ToastHelper/Navigator
setState(() => _isLoading = true);  // 이 줄은 OK — mounted 보장됨
try {
  final result = await someAsyncCall();
  if (!mounted) return;            // await 이후에 체크 필수
  setState(() { _data = result; _isLoading = false; });
} catch (e) {
  if (mounted) ToastHelper.showError(...);  // await 이후 체크
} finally {
  if (mounted) setState(() => _isLoading = false);  // await 이후 체크
}
```

---

## 설계 결정 완료 항목 — 재탐색 금지

### [DESIGN-F-M1] callableCalculateAndConfirmWage 시간 교차검증 없음
actualStart/actualEnd ↔ checkIn/checkOut 교차검증 의도적 미구현. 관리자 재량 허용 설계.
이유: 반올림·야간교대·기기 오류 등으로 체크인 시간과 크게 다른 값을 입력할 정당한 이유 존재.
HH:MM 포맷 검증만 유지.

### [DESIGN-A-M3] callableBatchAdjustAttendanceTime 90일 제한
소급 수정 기간 90일 제한 적용. 90일 이전 기록은 workDate/checkIn 기준으로 skip.

### [DESIGN-A-M4] 퇴사 D+3 자동 승인 + D+1/D+2 알림
D+3 자동 승인 유지 (민법상 1개월 기준보다 관대). 관리자에게 D+1(2일 경고), D+2(긴급) FCM 알림.

### [DESIGN-A-M5] 확정 취소 노쇼 벌점 — 서버 권위 · 취소와 같은 거래 (2026-11-26 판정291 F291-C07 문서 교정)
- **CURRENT**: 당일(벌점 대상) 확정 취소의 노쇼 벌점은 `callableCancelConfirmedApplication` **안에서** 서버가 결정하고, 취소 전이와 원장/카운터를 **같은 거래**로 적용한다(`index.ts` 취소 핸들러 · `applyPenaltyInTx` · 같은 날 이미 부과면 중복 0 · 마커 소유·보류·멱등 조건 포함). 클라이언트가 보내는 `applyNoShowPenalty` 는 호환성용이며 서버 결정에 쓰지 않는다.
- 앱(lib)에는 `callableApplyNoShowPenalty` 호출부가 없다 — 옛 '클라이언트 자발적 2단계 · 2번째 호출 생략 시 벌점 없이 취소 가능' 설명은 **역사 설계**이며 현재 동작이 아니다. 후속 callable 을 새로 붙이지 않는다.
- 대기(PENDING) 취소와 확정 취소를 혼동하지 않는다(대기 취소 서버 단일화는 별도 L55 판정).
- 관리자 물리 노쇼(`callableBatchSetNoShow`)는 별도 경로로 status=NO_SHOW + finalWage=0 처리 — 신뢰도 연동은 트리거·원장 경로를 따른다(이 항목에서 바꾸지 않음).

### [DESIGN-TO-T1] TO 레벨 minTrustScore 지원 차단 — 미구현 (의도적)
TO에 신뢰도 최솟값 필드를 추가해 미달 근로자의 지원을 시스템에서 차단하는 기능은 구현하지 않는다.
이유: 신뢰도 점수는 관리자가 지원서 검토 시 참고하는 정보이며, 채용 여부는 관리자 재량이다.
시스템이 자동 차단하면 오히려 유연성이 떨어진다.

### [DESIGN-SLOT-S4] updateSlotFull — 기존 지원서 시간 소급 변경 미구현 (의도적)
슬롯 시간 변경 시 이미 PENDING/CONFIRMED 상태인 지원서의 startTime/endTime을 소급 업데이트하지 않는다.
이유: CONFIRMED는 해당 시간으로 계약이 성립된 상태이므로 소급 변경은 계약 내용 변경에 해당하고,
PENDING도 근로자가 그 시간을 보고 자발적으로 지원한 것이므로 몰래 바꾸면 부당하다.
슬롯 시간을 새 값으로 운영하려면 기존 지원서를 취소 후 재지원 받는 것이 올바른 절차다.

### [DESIGN-STORAGE-EMPLOYER] contracts/signature_employer.png 소속 검증 없음
Storage rules에서 동적 경로 체이닝 불가(employment_contracts→businessId→businesses).
보완: contractId = Firebase auto-id(무작위), update: if false 덮어쓰기 차단. 실질 위험 낮음.

### [DESIGN-SLOT-PENDING] 슬롯 대기인원(PENDING) — 정원(requiredCount)과 무관 (재탐색 금지)
대기인원(PENDING 상태 지원자)은 정원과 무관하게 제한 없이 지원 가능하다.
예: 정원 5명인 슬롯에 10명이 동시에 PENDING 지원 → 정상 동작, 이슈 아님.
callableApplyToTO는 `confirmedCount >= requiredCount` 조건에서만 throw — CONFIRMED 추가를 차단할 뿐이다.
"waitlist 기능 없음" / "대기 미구현"은 **잘못된 탐지**이다.
PENDING 자체가 대기 상태이며, 관리자가 PENDING 인원 중에서 선발·확정하는 것이 설계 의도다.

---

## Trust Boundary Charter — 새 기능 설계 전 필수 체크

새 기능을 추가하기 전, 아래 기준으로 "CF(서버)냐 클라이언트냐"를 먼저 결정한다.

### CF(서버)에서 반드시 처리해야 하는 것

다음 중 하나라도 해당하면 CF 필수:

1. **카운터 증감** — totalConfirmed, totalPending ±1 초과, TO 등록 개수 제한 강제
2. **법적 상태 전이** — AUTO_CANCELED, AUTO_APPROVED, 계약 만료, 퇴직 자동 승인
3. **세션/인증 조작** — revokeRefreshTokens, custom claim 부여, 토큰 발급
4. **타인 데이터에 영향** — 블랙리스트, 강제 상태 변경, 타 사용자 필드 쓰기
5. **감사 로그 필수 작업** — 블랙리스트 등록/해제, 신원 확인 결과, 계약 효력 상태
6. **민감 필드 저장** — sealBase64(인감/서명), ci(CI 번호), passVerifiedAt, sealedAt
7. **법적 타임스탬프** — termsConsentAt, 계약일자 등 법적 효력이 있는 시각
8. **Rate limiting / 쿼터 강제** — CF에서 Firestore 읽기로 검증 후 허용·거부

### 클라이언트에서 해도 되는 것

- **읽기 전용 쿼리** (Firestore rules로 보호된 경우)
- **UI/UX 상태 관리** — 로딩 상태, 탭 선택, 필터 값
- **입력 유효성 검사** — 서버 재검증 전 UX용 로컬 체크 (서버 재검증 필수)
- **Optimistic update** — 서버 응답 전 화면 선반영 (실패 시 롤백 필수)
- **totalPending ±1** — rules에서 ±1 제한 강제, 음수 방지 검증 있음

### 결정 규칙

```
새 기능 추가 전:
  → "이 작업이 다른 사용자 데이터에 영향을 주는가?" → YES → CF
  → "이 필드가 법적·감사 기록에 해당하는가?" → YES → CF
  → "클라이언트가 이 값을 위조하면 실질적 피해가 발생하는가?" → YES → CF
  → 위 모두 NO → 클라이언트 OK (rules로 2차 방어 추가)
```

---

## USER PRODUCT POLICY REGISTRY

> **목적:** 코드 구현·함수명·필드명만 보고 Product Policy를 잘못 추론하는 오탐 방지.
> 각 정책은 CONFIRMED / CURRENT IMPLEMENTATION / FUTURE OPTION 으로 구분한다.

---

### 1. Identity Uniqueness (계정 유일성)

**CONFIRMED:**
- REAL PERSON × ROLE = 계정 최대 1개
- 동일인이 USER 1개 + BUSINESS_ADMIN 1개를 동시에 보유하는 것은 허용
- phone/authPhone/contactPhone은 uniqueness key가 아님

**CURRENT — 새 세대 (카카오 가입 · 2026-11-25 구현1 · 판정282 반영):**
- `identities/{ciKey}`(versioned domain-separated HMAC · Secret `CI_HMAC_KEY_V1`) × canonical role 슬롯
- `authLinks` 양방향(provider·app·subject·role ↔ uid) · 같은 카카오의 두 역할 = 같은 identity · 별도 UID · 자동 병합·교체 0
- writer = CF 전용
- KG CI 는 **요구 계약**이며 실 KG 결과로 검증된 것은 아님 (**미검증** · 실 MID 표본 전)

**CURRENT — 옛 QA 세대 (보존만 · 새 흐름 미조회 · 신규 생성 경로 서버 닫힘):**
- 내국인: `nativeIdentityFingerprints/{ciHash}_{role}` sentinel (Firestore transaction, atomic)
- 외국인: `foreignIdFingerprints/{HMAC-SHA256}_{role}` sentinel (동일 패턴, 대칭)
- sentinel key는 CF Admin SDK로만 생성/삭제 — 클라이언트 직접 조작 불가
- 옛 QA 와 새 가입이 같은 사람일 수 있음 — 세대 간 중복 0 을 주장하지 않는다

**FUTURE:** 이메일 가입은 같은 identity·authLinks·가입 세션 계약을 재사용 (방식 미정)

---

### 2. 가입 (Registration)

**CONFIRMED (2026-11-25 대표 · 새 세대):**
- 내·외국인 선택 없는 하나의 흐름 — 카카오 → 이용 목적 → 시행본 필수 동의 → KG이니시스 본인확인(공통 · 계약 = 간편인증) → 회원 완료 → 역할별 첫 화면·시작 준비
- 국적은 가입 시 `unknown`(미분류) · 가입 후 서류(신분증/외국인등록증)로 **서류 분류** (법적 국적·진위·취업자격 검증 아님)
- 30일(정확 경계) · 영구 블랙
- KG 불가 외국인 예외 경로는 만들지 않음 (재결정 대상)

**미검증:** KG V1 실제 응답 필드 · 외국인 인증 가능 범위 · KG 창 카카오 인증서의 CI 수신(별도 서류 필요 · 미수신 시 `KG_CI_MISSING` 거부 유지) — X1 실기기 표본 대기

**CURRENT (서버 계약):**
- `verifyPassAuth` 목적 = `signup` · `account_deletion` (세션·세대·requestId·역할·기한 결합 · imp_uid 같은 세션 멱등/다른 세션 거부 · 실 CI 없으면 실패)
- 옛 `register`/`reauth`/`resetPasswordWithPass` 및 옛 신규 가입 writer 는 닫힘
- QA 아이디 로그인 유지는 **로그인만** — 옛 가입·PASS 재인증/재설정은 닫히고, 구 QA 비밀번호 OTP 복구·관리자 초기화만 구 QA 전용으로 남음

**옛 QA 세대 (역사 계약 · 신규 가입 경로 닫힘):**
- 내국인: PASS 본인인증 (KG이니시스/PortOne V1) 필수 → CI 기반 uniqueness
- 외국인: 외국인등록번호 직접 입력 → HMAC fingerprint 기반 uniqueness
- 탈퇴 후 30일 재가입 불가 (`deleted_accounts` 컬렉션 기준)
- 블랙리스트 계정은 영구 재가입 차단

**CURRENT IMPLEMENTATION:**
- 내국인 CI는 `users/{uid}.ciHash` + `nativeIdentityFingerprints` sentinel
- 외국인 fingerprint는 `users/{uid}.foreignIdentityFingerprint` + `foreignIdFingerprints` sentinel
- 탈퇴 시 `callableDeleteAccountPreData`가 두 sentinel 모두 삭제 + `deleted_accounts` 기록

---

### 3. 신분증 업로드 / ID-CONSENT

**CONFIRMED:**
- `isIdVerified` = "USER가 자신의 Storage 경로에 신분증을 정상 업로드했다"는 상태
- SUPER_ADMIN의 신분증 진위 심사 결과가 **아니다**
- 단기(슬롯 있는) 공고 지원 시 `isIdVerified = true` 필수 (서버 gate)
- 장기(슬롯 없는) 공고에는 이 gate 미적용
- 신분증 열람 authority는 신분증 승인 여부가 아닌 ID-CONSENT Grant 기반
- Grant 기준: Application + idCardConsentGiven + 확정 상태 + 사업장 관계 + 관리자 permission + expiresAt

**CURRENT IMPLEMENTATION:**
- `callableMarkIdCardVerified`: USER 본인 호출, 경로 검증 후 `isIdVerified = true`
- `callableGetIdCardSignedUrl`: idCardAccessRequests Grant 확인 후 1시간 만료 Signed URL 반환

---

### 4. 급여계좌 등록 / Verification

**CONFIRMED:**
- USER가 자신의 급여계좌를 직접 등록/변경한다
- `bankName`/`accountNumber`/`accountHolder` — 클라이언트 Firestore direct write 금지, CF 전용
- `accountHolder`는 서버가 `users/{uid}.name`에서 읽어 저장 (클라이언트 전달 불가)
- 계좌 변경 시 기존 bankbookImage/bankbookUploadedAt 전면 초기화 (불변 원칙)
- `Attendance.wageAccount` snapshot은 계좌 변경 후에도 소급 변경하지 않음
- [Phase 6 완료] `bankVerificationStatus`(review_required/verified/mismatch) 시스템 폐기 — V3에서 불필요

**CURRENT IMPLEMENTATION:**
- 금융기관 계좌 실명조회 API 없음
- `callableMarkBankbookVerified`: 통장사본 업로드 → `bankbookImageUrl`/`bankbookImagePath`/`bankbookUploadedAt` 기록만 (status 전환 없음)
- `callableGetBankbookSignedUrl`: 1시간 Signed URL 반환.
  권한은 **SUPER_ADMIN 이 아니다** — `BUSINESS_ADMIN` 또는 **실제 SubAdmin**
  (`role == 'USER'` + 비어 있지 않은 `subAdminBusinessIds`/`subAdminOf`)이고,
  호출자가 보낸 `businessId` 를 `businesses`(ownerId/adminIds)와 SubAdmin 배정으로
  인가한 뒤, `members` 문서의 **`canManageWage`** 로 열람을 한 번 더 막는다.
  `users.businessId` 는 legacy hint 일 뿐 authorization truth 가 아니고,
  `managedBusinessIds` 는 클라이언트가 쓰는 값이라 인가 근거에서 제거됐다.
  [R7-P4.4E.6A DOC CORRECTION] 이전 기술("SUPER_ADMIN + businessId")은 실제 구현과
  달랐다. 코드가 canonical 이며, 문서를 코드에 맞췄다.
- [Phase 6 삭제됨] `callableSuperAdminVerifyBankAccount`, `callableSuperAdminMarkBankMismatch`, `callableGetPendingBankVerification`, `callableMigrateBankVerificationStatus`

**FUTURE OPTION:**
- 금융기관 예금주 조회 API 도입 시: 정상 본인명의 계좌 자동 confirmed, 예외건만 manual review
- `users.name`을 `accountHolder`에 복사하거나 문자열 비교로 "본인계좌" 처리하지 않음 — 금융기관 실명 검증이 아님

---

### 5. Application 지원 Prerequisite

**CONFIRMED/CURRENT (2026-11-25 판정282 반영):**
- 모든 세대 공통: `accountStatus == active` · 신분증 열람 동의 · 신분증 경로/URL 존재(장기 포함) · `bankName + accountNumber + accountHolder` 3필드 + 통장사본(bankbookImagePath 또는 URL) · 블랙/제재 중 불가 · 기존 법적 재동의 · 세무(수집 ON 일 때만 · 현재 OFF)
- 단기(슬롯) 공고: `isIdVerified == true` 추가 필요
- 근무 확정·초대 수락 등 신원 판정이 적용되는 단계에서는 현재 문서/객체 근거에 대한 자동 MATCHED 또는 해당 사업장의 현재 문서 버전 수동 REVIEWED_OK 라는 기존 OR 를 보존한다. 지원 제출의 서류 준비 조건과 동일한 단계로 쓰지 않는다.
- 본인확인: 옛 QA 세대 = 내국인 `passVerifiedAt` / 외국인 `accountStatus == 'active'` 계약 그대로 · 새 세대 = 가입 시 공통 KG 근거
- 새 세대 `nationalityStatus == unknown` 은 지원·TO 초대 수락·재배치 수락에서 `NATIONALITY_UNCONFIRMED`(서류 등록으로 해소) — 미분류를 내국인으로 접지 않는 방어선이며 새 국적 업무 gate 아님
- [Phase 6 삭제됨] `bankVerificationStatus === 'mismatch'` gate — V3에서 해당 상태 값 미발급이므로 gate 제거
- [Phase 6 삭제됨] `bankVerificationStatus`(review_required/verified/mismatch) 기반 게이팅 전면 제거

**isIdVerified 역할:**
- `isIdVerified = true` = PASS 본인인증 완료 사용자가 신분증 업로드 완료.
  → SUPER_ADMIN 사전 심사 결과가 아님. callableMarkIdCardVerified가 업로드 후 설정.
- `callableAdminVerifyIdCard` 같은 사전 관리자 승인 구조 생성 금지.

**OCR 역할:**
- 금융기관 실명조회 / 공적 신분증 진위 인증이 아님.
- 입력 정보와 제출 이미지의 1차 일치 확인 보조 수단.
- "신뢰도 N%", "검증 완료", "계좌 인증 완료" 표현 사용 금지.

**CURRENT IMPLEMENTATION:**
- `callableApplyToTO`에서 위 조건들을 순서대로 서버 검증
- 클라이언트 `apply_prerequisites_screen.dart`는 UX 사전 안내용 (서버 재검증 필수)
- `UserModel.hasWageDocumentsReady` — canonical 지원 준비 완료 getter
- `UserModel.hasApplicationDocumentsReady` — 신분증 + 급여정보 통합 getter
- UI는 Document Readiness만 표현: "계좌 등록 완료", "통장사본 등록 완료" (bankVerificationStatus 표시 없음)

---

### 6. Application 중복지원 / 확정 충돌

**CONFIRMED:**
- 동일 시간대 여러 공고에 Application 제출(PENDING) 허용 — Application = 관심 표현
- 하나가 CONFIRMED되는 시점에 겹치는 다른 Application을 자동취소
- 동일 시간대 복수 CONFIRMED는 허용하지 않음
- Apply 단계에서 "동일 시간대 지원이 존재한다"는 이유만으로 차단하는 정책이 아님

**CURRENT IMPLEMENTATION:**
- Application 확정 시 `autoConflictCancelOverlapping` 로직으로 겹치는 PENDING 자동취소
- 동일 공고·동일 슬롯 중복 지원은 복합 docId로 차단한다. [R7-4 정정] 3번째 segment는
  workType 고정이 아니다 — 클라이언트가 보낸 `workDetailId`, 없으면 `selectedWorkType`이
  discriminator이고, 새 문서는 서버가 역산한 `resolvedWdId`를 쓴다
  (`{toId}_{slotId}_{resolvedWdId}_{uid}`). 기존 문서의 id는 바꾸지 않는다.
  **docId를 파싱하는 소비자는 없다(CF 주석 전수 확인) — 형식 migration 금지.**

---

### 7. Attendance Bank Snapshot

**CONFIRMED:**
- Attendance 급여 확정(`wageStatus = 'confirmed'`) 시 계좌 snapshot 기록
- 이후 USER가 계좌를 변경해도 기존 Attendance snapshot은 소급 변경하지 않음
- [Phase 6 삭제됨] `wageAccountVerificationStatus` — V3에서 폐기. 이체 판단은 4필드 완전성으로만.
- V3 이체 invariant: `wageAccountBankName + wageAccountNumberEncrypted + wageAccountHolder + wageAccountSnapshotAt` 4필드 모두 존재 → 이체 가능

**CURRENT IMPLEMENTATION:**
- `callableConfirmFinalWage`: 급여 확정 시 4필드 snapshot + `wageAccountSnapshotVersion = 1` 기록
- `callableMarkTransferredBatch`: V3(snapshotVersion==1)는 4필드 완전성만 검증. Legacy는 bankGate 없이 통과.
- [Phase 6 삭제됨] `callableSuperAdminVerifyBankAccount` 기반 `wageAccountVerificationStatus` 승격 로직
- [TODO-ACCOUNT-FINGERPRINT] 재암호화 시 동일 계좌 암호문 불일치 문제 → HMAC fingerprint 전환 예정

---

### 8. 탈퇴 / 30일 재가입

**CONFIRMED:**
- 30일 재가입 불가 (정확 경계 · 기준 = 탈퇴 freeze 시각 · 기존 cooldown 과 max) · 영구 블랙 우선

**CURRENT — 새 세대 (2026-11-25 판정282 C282-01 반영):**
- PreData(freeze) = identity 슬롯을 `deleting` 으로 보존 · **Final 이 제한 기록과 슬롯 해제를 같은 거래로** 처리
- 비밀번호 없는 계정 탈퇴 = uid·용도 결합 KG 재확인 증명(10분) · cert 용도·요청·만료는 거래 시점 재판정
- 탈퇴 진행 중(tombstone) 계정의 새 비허용 callable 진입은 공통 서버 판정으로 거부한다(허용16 유지). Firestore 클라이언트 업무 쓰기도 `callerNotDeleting()`으로 거부하며, 본인 로그인 시각·FCM 갱신 예외1과 기존 읽기 규칙은 유지한다. 앱은 PreData 성공 뒤 실패하면 삭제 재개 화면으로 전환한다. 공통 진입 판정은 freeze 전에 이미 입장한 요청의 후속 commit까지 차단한다는 보장이 아니다.
- 카카오 링크는 Auth 삭제 뒤 삭제 UID 소유분만 정리 (생존 역할 링크 보존)
- rules 에뮬레이터 의미평가 313셀 통과(DG282-01 · rules SHA 4246c2b3 · `records/work/auth-kakao-1/rules_emu_1.md`) → 11-26 원장 동기화 필드 차단 4줄 추가본(SHA 1f7929b8) 324셀 통과(`records/work/server-merge-1/rules_emu_2/logs/p2`) — 에뮬레이터 ≠ 운영. 실제 연동은 **미검증**

**CURRENT — 옛 QA 세대 (기존 sentinel 삭제·`deleted_accounts.canReregisterAt` 경로 그대로):**
- 탈퇴 후 30일간 동일 CI(내국인) / 동일 외국인등록번호(외국인)로 재가입 불가
- 탈퇴 시 양쪽 sentinel 모두 삭제 + `deleted_accounts` 기록
- `callableDeleteAccountPreData`: sentinel 삭제 + `deleted_accounts.canReregisterAt = 탈퇴일 + 30일`
- 내국인 재가입: `callableVerifyPassAuth`에서 `deleted_accounts.ciHash` 조회
- 외국인 재가입: `callableFinalizeForeignIdentity`에서 `deleted_accounts.foreignIdentityFingerprint` 조회

---

### 9. 외국인 가입 (Document-First → 2026-11-25 공통 흐름으로 대체)

**CONFIRMED (2026-11-25):**
- 외국인 별도 가입 마법사는 신규 가입에서 닫힘 · 외국인도 공통 흐름(정책 2)
- 외국인등록증은 **가입 후 서류 등록** (`callableRegisterForeignIdDocument` · 가입 sentinel 과 분리 · 옛 HMAC sentinel 미사용)

**CURRENT:**
- 서버 회원 완료(identity 슬롯 · 제한 통과 · 시행본 필수 동의 사건 · 유효 KG · users 생성) 시 `accountStatus: active`(homeRegion 없음) · **가입 완료 → 짧은 앱 소개 → Home 직행**(대표 11-25 · 지역 미설정 USER 도 Home 진입 · 일자리는 전체 지역 · 홈 「시작 준비」 카드가 지역 → 신분증/외국인등록증 → 급여 계좌 순으로 안내 · 지원 시점 서버 gate 불변)
- 등록증은 active 조건이 아니라 지원 gate 에서 요구
- 아래 보존 항목(OCR 역할 · 원문 미저장 · 이름 독립 · 승인 단계 금지 · 클라 active 쓰기 금지 · resume 중 signUp/`users.set` 금지 · 수집 OFF·법무 HOLD)은 그대로 유효
- 이력: 아래 'active 완료 조건 4가지' · 'registration_pending 복구 CASE A–E' 는 **옛 QA 세대 역사 계약** — 현재 복구 경로의 pending→active 승격은 닫힘 (구 pending 자동 active 0)

**옛 V3 (2026-08-21) 계약:**
- 외국인 가입 = "외국인등록증 이미지 업로드 → OCR → 사용자 확인 → 서버 검증" 순서
- OCR = 입력 보조수단 ONLY. "진위확인/취업자격인증" 절대 표현 금지
- OCR 실패 → 수동 입력으로 대체 (가입 차단 없음)
- `legalName` / `koreanName` / `accountHolder` 는 완전 독립된 개념 (혼용 금지)
- `displayName` getter: `koreanName ?? legalName ?? name`
- `officialName` getter: `(isForeign && legalName != null) ? legalName : name`

**active 완료 조건 (4가지 모두 충족 시 CF가 자동 전환):**
1. `foreignIdentityFingerprint` 존재
2. `idCardImagePath` 존재 (`isIdVerified = true`)
3. `termsConsentAt` 존재
4. SUPER_ADMIN 수동 승인 불필요 — `callableRecordTermsConsent`가 조건 확인 후 자동 전환

**registration_pending 복구 (CASE A~E):**
- `RegistrationRecoveryScreen` → Firestore 직접 읽기로 CASE 판단 (user_provider pending guard 우회)
- CASE A/E: fingerprint ✓ + idCard ✓ → `callableRecordTermsConsent` 재호출 → active
- CASE B: fingerprint ✓, idCard ✗ → `ForeignRegisterScreen(isResume: true)` documentScan부터
- CASE C: fingerprint ✗, idCard ✓ → `ForeignRegisterScreen(isResume: true, existingIdCardPath: ...)` — Storage 재사용 시도 (성공 시 ocrConfirm 바로 이동, 재업로드 없음)
- CASE D: fingerprint ✗, idCard ✗ → `ForeignRegisterScreen(isResume: true)` documentScan부터

**절대 금지:**
- ❌ SUPER_ADMIN 승인 단계를 어떤 이름으로도 재추가
- ❌ `rawForeignId` 13자리 원문 Firestore 영구 저장
- ❌ 클라이언트가 `accountStatus`를 active로 직접 쓰기
- ❌ resume 진입 시 `userProvider.signUp()` 호출 (새 계정 생성 금지)
- ❌ resume 진입 시 `users/{uid}.set()` 또는 전체 문서 초기화
- ❌ "취업자격 인증 완료", "정부 인증 완료" 문구 사용

**CURRENT IMPLEMENTATION:**
- `lib/screens/auth/foreign_register_screen.dart` — V3 마법사 (6단계, isResume/existingIdCardPath 지원)
- `lib/screens/auth/registration_recovery_screen.dart` — CASE A~E 복구 화면
- `lib/services/foreign_id_ocr_service.dart` — OCR 서비스 (google_mlkit_text_recognition)
- `lib/services/auth_service.dart` — `finalizeForeignIdentity()` (legalName/visaType/stayExpiryDate 포함)
- CF: `callableFinalizeForeignIdentity` — HMAC fingerprint atomic 중복 체크 + idempotent
- CF: `callableMarkIdCardVerified` — Storage 경로 소유권 검증 + isIdVerified 설정
- CF: `callableRecordTermsConsent` — 4가지 조건 확인 → active 자동 전환
- CF: `callableAdminApproveForeignWorker` — V3에서 `unimplemented` throw로 비활성화 (dead code 제거 완료)

## 전체 디자인 통일 · 사용자 선택 (2026-11-04)

- 요청 정본: C:\Users\kug02\codex-audit\records\ALfit_Design_Unification_Request_2026-11-04.md
- 선택 이미지: C:\Users\kug02\codex-audit\records\ALfit_Design_Concept_01.png — Claude도 두 파일을 실제 열고 확인한다.
- 계획/기준: 같은 records의 ALfit_Design_Unification_Plan_2026-11-04.md / ALfit_Design_Standards_2026-11-04.md. 단일 적용표는 ALfit_Design_Surface_Register.csv다.
- 첫 실행: records\requests\DU_implementation_1.md → DU_revalidation_1.md. 현재 .82의 증거·변경·원복 상태를 보존한 안정 지점에서 원본 확인 ACK 후 진행하며, 파일 게시만으로 상대 세션 실행을 가정하지 않는다.
- 전체 목록 → 공통 기준 → 실제 대표 화면 → 밀도 패턴/전체 확장 → 실제 화면 재검증. 세 시안 화면에 한정하지 않고 가입부터 근무·급여·정산까지 적용한다.
- 기존 전면 디자인 후속 제한은 사용자 승인 디자인 범위에서 대체한다. 실제 탭·정책·데이터/권한·검증 이력·HOLD·Android 금지 파일은 보존한다. Claude가 구현/기기 조작, 지정 Codex가 독립 감사/기준 기록을 담당한다. 공통 기준 문서의 별도 writer를 만들지 않는다.
- **두 축 체계 (2026-11-06 사용자 지시 「매번 지적하지 않게 체계적으로」)**: 글자·대비·잘림·터치만 고치고 시각 완성도를 "적합"이라 쓰지 않는다. 매 DU 구현 보고는 다음을 갖춘다.
  - `## … 시안 대조` 절: 시안·before·after 합성 PNG를 직접 열람하고 V1~V11 표를 채운다. V1~V11은 위계·헤더·섹션 구조·표면 깊이·행 패턴·강조/색·아이콘·여백·빈 상태·버튼 위계·교차 일관성이다.
  - `## … 견고성` 절.
  - 합성은 `records/work/du-tools/du_vq_compare.py`로 만든다.
  - 감사 요청 전 `du_report_check.py <보고서>`를 통과해야 한다. 미통과면 요청하지 않는다. 합성 PNG는 `-Images`로 함께 보낸다.
  - 요청서가 견고성 한 셀만 지정해도 V표는 채우고, 범위 밖은 `후보`로 올린다(판정은 Codex).
  - 근거: `records/reports/DU_two_axis_protocol_2026-11-06.md`, 방향 검토 §7.2.
