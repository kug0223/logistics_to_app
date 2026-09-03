# AlFit 프로젝트 Claude 작업 지침

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

### [DESIGN-A-M5] callableApplyNoShowPenalty 2단계 구조 — 클라이언트 자발적 호출
당일 취소 후 노쇼 패널티는 클라이언트가 `callableCancelConfirmedApplication` → `callableApplyNoShowPenalty` 순으로 별도 호출하는 2단계 구조.
클라이언트가 2번째 호출을 건너뛰면 TrustScore 패널티 없이 취소 가능하나, CF 내부에서 workDate 서버 재검증(48시간 이내)이 있어 시간 우회 불가.
불리한 것은 근로자 TrustScore이므로 사용자가 자신에게 패널티 미부과하는 것이 경미한 이슈.
관리자 물리 노쇼(`callableBatchSetNoShow`)는 별도 경로로 status=NO_SHOW + finalWage=0만 처리 — TrustScore 연동은 의도적 미구현.

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

**CURRENT IMPLEMENTATION:**
- 내국인: `nativeIdentityFingerprints/{ciHash}_{role}` sentinel (Firestore transaction, atomic)
- 외국인: `foreignIdFingerprints/{HMAC-SHA256}_{role}` sentinel (동일 패턴, 대칭)
- sentinel key는 CF Admin SDK로만 생성/삭제 — 클라이언트 직접 조작 불가

---

### 2. 내국인/외국인 가입 (Registration)

**CONFIRMED:**
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
- `callableGetBankbookSignedUrl`: SUPER_ADMIN + businessId 권한 확인 후 1시간 Signed URL 반환
- [Phase 6 삭제됨] `callableSuperAdminVerifyBankAccount`, `callableSuperAdminMarkBankMismatch`, `callableGetPendingBankVerification`, `callableMigrateBankVerificationStatus`

**FUTURE OPTION:**
- 금융기관 예금주 조회 API 도입 시: 정상 본인명의 계좌 자동 confirmed, 예외건만 manual review
- `users.name`을 `accountHolder`에 복사하거나 문자열 비교로 "본인계좌" 처리하지 않음 — 금융기관 실명 검증이 아님

---

### 5. Application 지원 Prerequisite

**CONFIRMED (Phase 6 업데이트):**
- bankName + accountNumber + (bankbookImagePath 또는 bankbookImageUrl) 미등록 → 지원 불가
- 단기(슬롯) 공고: `isIdVerified == true` 추가 필요
- 내국인: `passVerifiedAt` 존재 필요
- 외국인: `accountStatus == 'active'` 필요
- 블랙리스트/제재 중 계정: 지원 불가
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
- complexId(`{toId}_{slotId}_{workType}_{uid}`)로 동일 공고·동일 슬롯 중복 지원 차단

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
- 탈퇴 후 30일간 동일 CI(내국인) / 동일 외국인등록번호(외국인)로 재가입 불가
- 블랙리스트 계정은 재가입 영구 차단
- 탈퇴 시 양쪽 sentinel 모두 삭제 + `deleted_accounts` 기록

**CURRENT IMPLEMENTATION:**
- `callableDeleteAccountPreData`: sentinel 삭제 + `deleted_accounts.canReregisterAt = 탈퇴일 + 30일`
- 내국인 재가입: `callableVerifyPassAuth`에서 `deleted_accounts.ciHash` 조회
- 외국인 재가입: `callableFinalizeForeignIdentity`에서 `deleted_accounts.foreignIdentityFingerprint` 조회

---

### 9. 외국인 Document-First 가입 (V3 — 2026-08-21 확정)

**CONFIRMED:**
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
