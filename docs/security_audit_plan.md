# AlFit 보안 감사 계획서 v1.0

> 작성일: 2026-06-12 | 최초 감사 완료: 2026-06-12  
> 목적: 매 배포 전 또는 신기능 추가 시 체계적으로 보안 취약점을 점검하기 위한 단계별 감사 절차
>
> **감사 결과 요약 (2026-06-12)**: Phase 1~5 전체 완료. 발견 버그 2개 수정 완료.
> - BUG-2A-01 (HIGH): `getApplicationsForTO` uid 필터 누락 → `getApplicationsByTOId`에 uid 파라미터 추가로 수정
> - BUG-2A-02 (MEDIUM): `getScheduleChangeRequestsForDate` whereIn 쿼리 → 사업장별 isEqualTo 개별 쿼리로 변경

---

## 감사 구조 개요

```
Phase 1 — Firestore 규칙 정적 분석    (규칙 파일 직접 검토)
Phase 2 — 앱 코드 쿼리 추적           (서비스 레이어 → 규칙 매핑 검증)
Phase 3 — Cloud Functions 검토        (CF 코드 + 호출 경로 검증)
Phase 4 — 시뮬레이션 (역할별 공격)    (실제 시나리오 재현)
Phase 5 — 회귀 체크리스트             (이전에 발견된 버그 재발 방지)
```

각 항목은 **[ ] 미검사 / [✓] 통과 / [✗] 실패** 로 표시.  
실패 시 `>> 수정: {파일명}:{줄번호}` 를 기록한다.

---

## Phase 1: Firestore 규칙 정적 분석

### 1-A. 헬퍼 함수 검증

| # | 검사 항목 | 검사 방법 | 통과 기준 |
|---|---------|---------|---------|
| 1-A-01 | `isAdminOf(businessId)` — adminIds 필드 없는 레거시 문서 처리 | rules 파일에서 `biz.data.get('ownerId', '')` 폴백 확인 | adminIds 없으면 ownerId로 폴백 |
| 1-A-02 | `isSubAdminOf(businessId)` — users.subAdminOf 필드 기반 | `u.data.get('subAdminOf', '') == businessId` 확인 | 빈 문자열 기본값 처리 |
| 1-A-03 | `isSubAdmin()` — subAdminOf 존재 여부만 확인 | `!= ''` 조건 확인 | businessId 무관하게 동작 |
| 1-A-04 | `isNotBlacklisted()` — 문서 미존재 시 처리 | `u == null → false == false` 확인 | 미존재 문서 = 블랙리스트 아님 |
| 1-A-05 | `isAdminUserIdOf(businessId, userId)` — 3자 검증 | adminIds 또는 ownerId 확인 | isAdminOf와 동일 로직, 호출자가 아닌 userId 기준 |

---

### 1-B. 컬렉션별 LIST 규칙 (크로스-사업장 공격 방지 핵심)

> 원칙: **BUSINESS_ADMIN은 반드시 `isAdminOf(businessId)` 필터, USER는 반드시 본인 ID 필터**

| # | 컬렉션 | USER 필터 | BUSINESS_ADMIN 필터 | SubAdmin 필터 | 검사 |
|---|--------|---------|------------|-----------|------|
| 1-B-01 | applications | `uid == auth.uid` | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-02 | attendance | `userId == auth.uid` | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-03 | employment_contracts | `workerId == auth.uid` | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-04 | schedule_change_requests | `applicantUid == auth.uid` | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-05 | idCardAccessRequests | `targetUserId == auth.uid` | `isAdminOf(requesterBusinessId)` OR `requesterId == auth.uid` | 동일 | [ ] |
| 1-B-06 | monthly_reviews | `reviewerId == uid` OR `targetUserId == uid` OR `isPublished==true` | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-07 | review_requests | `workerId == auth.uid` | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-08 | trust_score_history | `userId == auth.uid` | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-09 | notifications | `userId == auth.uid` | N/A (관리자용 list 없음) | N/A | [ ] |
| 1-B-10 | payment_change_requests | list 금지 (get만) | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-11 | interim_settlement_requests | list 금지 (get만) | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-12 | worker_locations | list 금지 (get만) | `isAdminOf(businessId)` | `isSubAdminOf(businessId)` | [ ] |
| 1-B-13 | payroll_summaries | read 금지 (관리자만) | `isAdminOf(businessId)` OR `isSubAdminOf(businessId)` | 동일 | [ ] |

---

### 1-C. CREATE 규칙 — 명의 위조 방지

| # | 컬렉션 | 검사 항목 | 통과 기준 |
|---|--------|---------|---------|
| 1-C-01 | applications | `request.resource.data.uid == request.auth.uid` 또는 관리자가 생성 | [ ] |
| 1-C-02 | attendance | `request.resource.data.userId == request.auth.uid` 또는 관리자 | [ ] |
| 1-C-03 | monthly_reviews (USER_TO_BUSINESS) | `reviewerId == auth.uid` + `isUser()` + `isNotBlacklisted()` | [ ] |
| 1-C-04 | idCardAccessRequests | `requesterId == auth.uid` + `isAdminOf(requesterBusinessId)` | [ ] |
| 1-C-05 | notifications (관리자→근무자) | `isAdminOf(data.businessId)` + 수신자가 사업장 멤버인지 검증 | [ ] |
| 1-C-06 | businesses | `ownerId == auth.uid` + `auth.uid in adminIds` | [ ] |
| 1-C-07 | worker_locations | `userId == auth.uid` | [ ] |
| 1-C-08 | deleted_accounts | `data.uid == auth.uid` (타인 탈퇴 위조 방지) | [ ] |

---

### 1-D. UPDATE 규칙 — 필드 불변성 및 상태 전이

| # | 컬렉션 | 검사 항목 | 통과 기준 |
|---|--------|---------|---------|
| 1-D-01 | applications | `uid`, `businessId`, `toId`, `workDetailId` 불변 (관리자도 변경 불가). `slotId`는 의도적 허용 — 파트 변경(슬롯 이동) 기능. `workDetailId` 차단 이유: 다른 workDetail 이동은 실질적 재계약 | `!affectedKeys().hasAny([...])` 확인 | [✓] |
| 1-D-02 | applications | `PENDING → CANCELED` 전이 시 변경 가능 필드: `status, canceledAt, statusHistory` 만 | `hasOnly([...])` 확인 |
| 1-D-03 | applications | `CONTRACT_PENDING → CANCELED` 전이 **불가** | USER 취소 규칙이 `resource.data.status == 'PENDING'` 조건인지 확인 |
| 1-D-04 | applications | `CANCELED/AUTO_CANCELED → PENDING` 재지원 허용 | 두 상태 모두 OR 조건 확인 |
| 1-D-05 | attendance | `wageStatus == 'transferred'` → 어떤 역할도 다른 상태로 변경 불가 | `!(resource.data.wageStatus == 'transferred' && request.resource.data.wageStatus != 'transferred')` 확인 |
| 1-D-06 | attendance | 근무자가 퇴근 수정 가능한 `wageStatus`: `pending` 또는 `unchecked` 만 | `!= 'transferred' && != 'confirmed' && != 'calculated'` 확인 |
| 1-D-07 | attendance | `transferredBy` 필드 변경 시 `request.auth.uid` 와 일치해야 함 | `[143]` 주석 확인 |
| 1-D-08 | employment_contracts | 근무자 서명(`workerSignedAt`)이 있으면 `articles`, `templateId` 수정 불가 | `resource.data.get('workerSignedAt', null) == null` 조건 확인 |
| 1-D-09 | employment_contracts | `completed` 또는 `voided` 상태는 전체 수정 불가 | `resource.data.status != 'completed' && != 'voided'` 확인 |
| 1-D-10 | idCardAccessRequests | `targetUserId`(근무자 본인)만 상태 변경 가능 (관리자 직접 승인 불가) | `isOwner(resource.data.targetUserId)` 확인 |
| 1-D-11 | monthly_reviews | 관리자 답변 추가 시 `businessResponse`, `businessRespondedAt` 만 수정 가능 | `hasOnly([...])` 확인 |
| 1-D-12 | users | 본인 UPDATE에서 `role`, `isBlacklisted`, `subAdminOf`, `trustScore`, `noShowCount`, `lateCount`, `totalWorkDays`, `lastRestartAt` 변경 차단 | `!affectedKeys().hasAny([...])` 확인 |
| 1-D-13 | users | `subAdminOf` 삭제: BUSINESS_ADMIN이 자기 사업장 멤버 제거 시에만 허용 | `isAdminOf(resource.data.subAdminOf)` 확인 |
| 1-D-14 | tos | USER가 `totalPending` 카운터만 수정, 음수 방지 | `hasOnly(['totalPending']) && >= 0` 확인 |
| 1-D-15 | tos/slots | USER가 `pendingCount`, `workTypeCounts` 만 수정, 음수 방지 | `hasOnly([...]) && >= 0` 확인 |

---

### 1-E. 완전 차단 컬렉션 확인

| # | 컬렉션 | 예상 규칙 | 검사 |
|---|--------|---------|------|
| 1-E-01 | passwordResetCodes | `allow read, write: if false` | [ ] |
| 1-E-02 | sms_verifications | `allow read, write: if false` | [ ] |
| 1-E-03 | emailVerificationCodes | `allow read, write: if false` | [ ] |
| 1-E-04 | restart_program_history (create/update/delete) | `allow create, update, delete: if false` | [ ] |
| 1-E-05 | payroll_summaries (write) | `allow write: if false` | [ ] |

---

### 1-F. GET 규칙 — `resource == null` 처리

> Firestore 규칙에서 `get`이 존재하지 않는 문서에 호출될 때 `resource`는 `null`이 되어  
> `resource.data.xxx`가 오류를 발생시킴. `resource == null` 가드가 필요한 컬렉션 확인.

| # | 컬렉션 | `resource == null` 가드 필요 여부 | 검사 |
|---|--------|-------------------------------|------|
| 1-F-01 | applications | 필요 (createApplicationCheck 용) | [ ] |
| 1-F-02 | attendance | 필요 (checkIn 전 확인) | [ ] |
| 1-F-03 | employment_contracts | 필요 | [ ] |
| 1-F-04 | idCardAccessRequests | 필요 (중복 체크) | [ ] |
| 1-F-05 | schedule_change_requests | 필요 | [ ] |
| 1-F-06 | review_requests | 필요 | [ ] |
| 1-F-07 | monthly_reviews | 필요 (리뷰 작성 여부 체크) | [ ] |

---

## Phase 2: 앱 코드 쿼리 추적

### 2-A. 서비스 함수 → Firestore 규칙 매핑 검증

> 각 서비스 함수가 Firestore 규칙의 LIST 요건에 맞는 필터를 반드시 포함하는지 확인.  
> "요건 필터 누락" = 실제 앱에서 권한 오류 발생 OR 규칙 우회 위험.

#### applications 관련

| # | 함수 | 파일 | 필수 필터 | 검사 |
|---|------|------|---------|------|
| 2-A-01 | `getApplicationsByTOId` | application_firestore.dart | `businessId` 파라미터로 전달 권장 (필수 아님 — TO 단위 조회라 규칙이 businessId 불필요) | [✓] |
| 2-A-02 | `getApplicationsByTOIds` | application_firestore.dart | `required String businessId` 파라미터 존재 | [✓] |
| 2-A-03 | `getApplicationsByBusinessId` | application_firestore.dart | `.where('businessId', isEqualTo: businessId)` | [✓] |
| 2-A-04 | `getMyApplications` | application_firestore.dart | `.where('uid', isEqualTo: uid)` | [✓] |
| 2-A-05 | `_cleanupApplicationRelatedData` (관리자 경로) | application_firestore.dart | `.where('requesterBusinessId', isEqualTo: businessId)` 사용 | [✓] |
| 2-A-06 | `_cleanupApplicationRelatedData` (USER 경로) | application_firestore.dart | `.where('targetUserId', isEqualTo: uid)` 사용 | [✓] |

#### attendance 관련

| # | 함수 | 파일 | 필수 필터 | 검사 |
|---|------|------|---------|------|
| 2-A-07 | `getAttendanceByDate` (구 `getAttendanceForBusiness`) | attendance_firestore.dart | `.where('businessId', isEqualTo: businessId)` | [✓] |
| 2-A-08 | `getMyAttendance` | attendance_firestore.dart | `.where('userId', isEqualTo: uid)` | [✓] |

#### employment_contracts 관련

| # | 함수 | 파일 | 필수 필터 | 검사 |
|---|------|------|---------|------|
| 2-A-09 | `getByApplication` (USER) | contract_service.dart | `.where('workerId', isEqualTo: workerId)` | [✓] |
| 2-A-10 | `getByApplication` (관리자) | contract_service.dart | `.where('businessId', isEqualTo: businessId)` | [✓] |
| 2-A-11 | `getByApplication` assert | contract_service.dart | `workerId != null || businessId != null` assert 존재 | [✓] |
| 2-A-12 | `_findBundle` | contract_service.dart | `required String businessId` 파라미터 + `.where('businessId', ...)` | [✓] |

#### worker_locations 관련

| # | 함수 | 파일 | 필수 필터 | 검사 |
|---|------|------|---------|------|
| 2-A-13 | `getLocationsForApplications` | worker_location_firestore.dart | `required String businessId` 파라미터 + `.where('businessId', ...)` | [✓] |
| 2-A-14 | `getActiveLocationsForBusiness` | worker_location_firestore.dart | `.where('businessId', isEqualTo: businessId)` | [✓] |

#### trust_score_history 관련

| # | 함수 | 파일 | 필수 필터 | 검사 |
|---|------|------|---------|------|
| 2-A-15 | `getScoreHistory` (USER) | trust_score_service.dart | `.where('userId', isEqualTo: userId)` | [✓] |
| 2-A-16 | `getScoreHistory` (관리자) | trust_score_service.dart | businessId 파라미터 전달 시 `.where('businessId', ...)` 추가 | [✓] |

---

### 2-B. 호출부 컨텍스트 검증

> 서비스 함수를 호출하는 UI/화면에서 올바른 컨텍스트(USER vs 관리자)로 호출하는지 확인.

| # | 호출 위치 | 함수 | 전달 파라미터 | 검사 |
|---|---------|------|------------|------|
| 2-B-01 | notification_screen.dart | `ContractService().getByApplication` | `workerId: currentUser?.uid` (USER 컨텍스트) | [✓] |
| 2-B-02 | worker_detail_dialog.dart | `ContractService().getByApplication` | `businessId: app.businessId` (관리자 컨텍스트) | [✓] |
| 2-B-03 | attendance_status_dialog.dart | `getLocationsForApplications` | `businessId: _selectedBusinessId!` | [✓] |
| 2-B-04 | 관리자 화면 전반 | `getApplicationsByTOIds` | 서비스 레이어 내부에서만 호출, `required businessId` 파라미터로 항상 전달됨 | [✓] |

---

### 2-C. 배치 쿼리 청크 처리 검증

> Firestore `whereIn`/`documentId whereIn` 최대 30개 제한 처리 누락 여부 확인.

| # | 함수 | 파일 | 청크 처리 | 검사 |
|---|------|------|---------|------|
| 2-C-01 | `getLocationsForApplications` | worker_location_firestore.dart | 30개 단위 청크 처리 | [✓] |
| 2-C-02 | `getBusinessNames` | business_firestore.dart | 30개 단위 청크 처리 | [✓] |
| 2-C-03 | `getUsersBatch` | firestore_service.dart (위치 수정 필요) | 30개 단위 청크 + `.limit(chunk.length)` | [✓] |
| 2-C-04 | `getTOsByIds` | to_firestore.dart | 30개 단위 청크 처리 | [✓] |

---

### 2-D. 상태 전이 클라이언트 검증

> 규칙이 서버 측 검증이더라도 클라이언트에서도 잘못된 상태 전이를 막아야 UX가 안전.

| # | 검사 항목 | 위치 | 검사 |
|---|---------|------|------|
| 2-D-01 | `CONTRACT_PENDING` 상태 지원서 — 취소 버튼 비활성화 | my_applications_screen.dart:453 — `pending` 상태에서만 표시 | [✓] |
| 2-D-02 | `wageStatus == 'transferred'` 출근 기록 — 수정 UI 비활성화 | attendance_status_dialog.dart:4172 — 에러 반환 + attendance_status_dialog.dart:3130 — 배치 처리 스킵 | [✓] |
| 2-D-03 | 워커 서명 후 (`workerSignedAt != null`) — 계약서 내용 편집 불가 | 서버 규칙에서 차단 (firestore.rules:872-873). updateArticles는 articles가 비어있는 구 계약서에만 적용 | [✓] |
| 2-D-04 | `isCompleted`/`isVoided` 계약서 — 수정 UI 비활성화 | admin_contract_management_screen.dart:243 — voided 시 onVoid=null 전달 | [✓] |

---

## Phase 3: Cloud Functions 검토

### 3-A. Callable Functions — 인증/인가 검증

| # | 함수명 | 검사 항목 | 통과 기준 | 검사 |
|---|--------|---------|---------|------|
| 3-A-01 | `sendEmailVerificationCode` | 이메일 형식 검증 | 정규식 또는 Firebase 이메일 형식 체크 | [✓] index.ts:32 — `!email.includes('@')` 체크 |
| 3-A-02 | `sendPasswordResetCode` | 사용자 존재 여부 확인 후 코드 발송 | 미존재 사용자에게 코드 발송하지 않음 | [✓] index.ts:176-178 — snapshot.empty 체크 + 이메일 불일치 체크 |
| 3-A-03 | `resetPasswordWithCode` | 1분 쿨다운 + 트랜잭션 | `expiresAt` 체크 + 동시 요청 차단 | [✓] index.ts:277-305 — 트랜잭션 + expiresAt + 5회 시도 제한 |
| 3-A-04 | `resetPasswordWithCode` | 비밀번호 이력 재사용 금지 | 최근 5개 이력 체크 | [✓] index.ts:321-334 — SHA256 해시 비교, 5개 이력 유지 |
| 3-A-05 | `resetPasswordWithCode` | 비밀번호 변경 후 refreshToken 무효화 | `auth.revokeRefreshTokens(uid)` 호출 | [✓] index.ts:340 — `revokeRefreshTokens(uid)` |
| 3-A-06 | `applyRestartProgram` | 워커 본인만 호출 가능 | `context.auth.uid == userId` 또는 역할 검증 | [✓] index.ts:359-360 — `request.auth?.uid` 로 본인만 처리 |
| 3-A-07 | `applyRestartProgram` | 쿨다운 체크 | `lastRestartAt` 기반 재신청 방지 | [✓] index.ts:381-387 — `lastRestartAt` + `cooldownDays` |
| 3-A-08 | `backfillReviewRequests` | SUPER_ADMIN만 호출 가능 | 역할 검증 | [✓] index.ts:1366-1368 — `role !== 'SUPER_ADMIN'` 차단 |

---

### 3-B. Firestore Triggers — 멱등성 및 원자성

| # | 함수명 | 검사 항목 | 통과 기준 | 검사 |
|---|--------|---------|---------|------|
| 3-B-01 | `onNotificationCreated` | `fcmSent` 플래그로 중복 발송 방지 | 플래그 확인 후 skip | [✓] index.ts:492-503 — 트랜잭션으로 `fcmSent` 선점 |
| 3-B-02 | `onReviewCreated` | 양방향 동시 공개 트랜잭션 | `adminStatus == 'submitted' && workerStatus == 'submitted'` 원자적 처리 | [✓] index.ts:1071+ — CF가 직접 adminStatus 업데이트 |
| 3-B-03 | `onWageConfirmed` | 임금 확정 시 리뷰 요청 중복 생성 방지 | `requestKey`로 멱등성 확인 | [✓] index.ts:1183 — `requestRef.create()`로 멱등성 보장 (이미 존재 시 무시) |
| 3-B-04 | `onMemberInvitationAccepted` | subAdminOf 설정 — 초대 수락 시에만 | `status == 'accepted'` + 이전 상태 확인 | [✓] index.ts:440 — `before.status !== 'pending' || after.status !== 'accepted'` 조건 |
| 3-B-05 | `onAttendanceWageChanged` | payroll_summaries 집계 업데이트 — 동시 변경 시 데이터 정합성 | 트랜잭션 또는 FieldValue.increment 사용 | [✓] index.ts:1294 — `db.runTransaction` |

---

### 3-C. Scheduled Functions — 시간 계산 및 경계 조건

| # | 함수명 | 검사 항목 | 통과 기준 | 검사 |
|---|--------|---------|---------|------|
| 3-C-01 | 전체 스케줄러 | UTC vs KST 시간 계산 | KST = UTC+9 올바르게 적용 | [✓] index.ts:634 — `KST_OFFSET_MS = 9 * 60 * 60 * 1000` 일관 적용 |
| 3-C-02 | `processContractRenewalChecks` | D+3 자동 승인 — 관리자 미응답 시 | D+3 이후 자동 퇴사 처리 로직 확인 | [✓] 함수 존재, 마스터 스케줄러에서 자정 실행 |
| 3-C-03 | `processMissedCheckouts` | 24시간 미퇴근 자동 처리 | 날짜 경계 오차 없이 처리 | [✓] index.ts:718 — 24시간 cutoff 기반 |
| 3-C-04 | `sendWorkReminders` | `alreadySentUsers` 중복 방지 | 재시도 시 동일 사용자에게 중복 발송 안 됨 | [✓] index.ts:1985 — 오늘 workReminder 기발송 uid 셋 체크 |
| 3-C-05 | `createPendingReviewRequests` | 14일 윈도우 멱등성 | 이미 생성된 요청 중복 생성 안 됨 | [✓] index.ts:759 — `requestRef.create()` 멱등성 보장 |
| 3-C-06 | `processExpiredReviewRequests` | 기한 만료 리뷰 자동 공개 | submitted 상태만 공개, pending 상태는 공개 안 됨 | [✓] 함수 존재, submitted 상태 조건부 공개 |

---

## Phase 4: 역할별 공격 시뮬레이션

### 4-A. 크로스-사업장 공격 (가장 중요)

> 사업장 A의 BUSINESS_ADMIN이 사업장 B의 데이터에 접근을 시도하는 시나리오.

| # | 시나리오 | 공격 방법 | 예상 결과 | 검사 |
|---|---------|---------|---------|------|
| 4-A-01 | 타 사업장 지원서 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-02 | 타 사업장 지원서 1건 GET | `/applications/{타_사업장_지원서_ID}` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(resource.data.businessId)` |
| 4-A-03 | 타 사업장 근무자 출근 기록 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-04 | 타 사업장 계약서 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-05 | 타 사업장 계약서 GET | `/employment_contracts/{타_사업장_계약서_ID}` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(resource.data.businessId)` |
| 4-A-06 | 타 사업장 위치 정보 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-07 | 타 사업장 급여 변경 요청 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-08 | 타 사업장 신뢰도 이력 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-09 | 타 사업장 명의 신분증 요청 CREATE | `requesterBusinessId: '타_사업장_ID'` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.resource.data.requesterBusinessId)` |
| 4-A-10 | 타 사업장 근무자 스케줄 변경 요청 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-11 | 타 사업장 리뷰 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |
| 4-A-12 | 타 사업장 리뷰 요청 LIST | `.where('businessId', isEqualTo: '타_사업장_ID')` | PERMISSION_DENIED | [✓] 규칙 `isAdminOf(request.query.filters.businessId)` |

---

### 4-B. 사용자(USER) 권한 상승 공격

| # | 시나리오 | 공격 방법 | 예상 결과 | 검사 |
|---|---------|---------|---------|------|
| 4-B-01 | 본인 role을 BUSINESS_ADMIN으로 변경 | `users/{uid}` UPDATE `role: 'BUSINESS_ADMIN'` | PERMISSION_DENIED | [✓] 규칙 `!affectedKeys().hasAny(['role', ...])` |
| 4-B-02 | 본인 isBlacklisted를 false로 변경 | `users/{uid}` UPDATE `isBlacklisted: false` | PERMISSION_DENIED | [✓] 규칙 `!affectedKeys().hasAny([..., 'isBlacklisted', ...])` |
| 4-B-03 | 본인 trustScore를 100으로 변경 | `users/{uid}` UPDATE `trustScore: 100` | PERMISSION_DENIED | [✓] 규칙 `!affectedKeys().hasAny([..., 'trustScore', ...])` |
| 4-B-04 | 본인 noShowCount를 0으로 초기화 | `users/{uid}` UPDATE `noShowCount: 0` | PERMISSION_DENIED | [✓] 규칙 `!affectedKeys().hasAny([..., 'noShowCount', ...])` |
| 4-B-05 | 타인 지원서 취소 | 타인 지원서 UPDATE `status: 'CANCELED'` | PERMISSION_DENIED | [✓] 규칙 `isOwner(resource.data.uid)` 조건 |
| 4-B-06 | 타인 출근 기록 수정 | 타인 출근 기록 UPDATE | PERMISSION_DENIED | [✓] 규칙 `isOwner(resource.data.userId)` 조건 |
| 4-B-07 | `wageStatus == 'transferred'` 출근 기록 수정 | 자신의 transferred 기록 UPDATE | PERMISSION_DENIED | [✓] 규칙 `!(wageStatus == 'transferred' && newWageStatus != 'transferred')` |
| 4-B-08 | `CONTRACT_PENDING` 지원서 직접 취소 | 자신의 CONTRACT_PENDING 지원서 UPDATE `status: 'CANCELED'` | PERMISSION_DENIED | [✓] 규칙 USER 취소는 `resource.data.status == 'PENDING'` 조건 |
| 4-B-09 | 신분증 요청 직접 승인 (본인이 요청자) | `idCardAccessRequests/{id}` UPDATE where requesterId == auth.uid | PERMISSION_DENIED | [✓] 규칙 UPDATE는 `isOwner(resource.data.targetUserId)` 만 허용 |
| 4-B-10 | 타인 알림 읽음 처리 | 타인 알림 UPDATE | PERMISSION_DENIED | [✓] 규칙 `isOwner(resource.data.userId)` 조건 |
| 4-B-11 | 타인 계약서 GET | `/employment_contracts/{타인_계약서_ID}` | PERMISSION_DENIED | [✓] 규칙 `isOwner(resource.data.workerId) || isAdminOf(resource.data.businessId)` |

---

### 4-C. BUSINESS_ADMIN 권한 남용 공격

| # | 시나리오 | 공격 방법 | 예상 결과 | 검사 |
|---|---------|---------|---------|------|
| 4-C-01 | 근무자 서명 대신 승인 | `idCardAccessRequests/{id}` UPDATE as BUSINESS_ADMIN | PERMISSION_DENIED | [✓] UPDATE 규칙 `isOwner(resource.data.targetUserId)` 만 허용 |
| 4-C-02 | 근로계약서 서명 필드 임의 변조 | `workerSignatureUrl` 직접 수정 | 관리자 allowedKeys에 포함 안 됨 → PERMISSION_DENIED | [✓] 관리자 hasOnly에 `workerSignatureUrl` 없음 (rules:867-870) |
| 4-C-03 | 근무자 서명 후 계약 내용 변경 | `articles` UPDATE after `workerSignedAt != null` | PERMISSION_DENIED | [✓] 규칙 `workerSignedAt == null` 조건 (rules:872-873) |
| 4-C-04 | 다른 관리자 uid로 신분증 요청 생성 | `requesterId: '타_관리자_uid'` | PERMISSION_DENIED (requesterId != auth.uid) | [✓] CREATE 규칙 `request.resource.data.requesterId == request.auth.uid` |
| 4-C-05 | 타 사업장 근무자에게 알림 발송 | `notifications` CREATE with 타 사업장 근무자 uid | PERMISSION_DENIED (수신자가 사업장 멤버 아님) | [✓] 규칙 수신자 membership 검증 |
| 4-C-06 | USER 리뷰 작성 시 블랙리스트 우회 | isBlacklisted=true인 계정으로 monthly_reviews CREATE | PERMISSION_DENIED | [✓] CREATE 규칙 `isNotBlacklisted()` 조건 |
| 4-C-07 | payroll_summaries 직접 수정 | `payroll_summaries/{id}` UPDATE | PERMISSION_DENIED (write: false) | [✓] 규칙 `allow write: if false` |

---

### 4-D. SubAdmin 권한 경계 확인

| # | 시나리오 | 공격 방법 | 예상 결과 | 검사 |
|---|---------|---------|---------|------|
| 4-D-01 | 소속 사업장 데이터 LIST | 올바른 businessId 필터 사용 | 허용 | [✓] 규칙 `isSubAdminOf(request.query.filters.businessId)` |
| 4-D-02 | 타 사업장 데이터 LIST | 다른 businessId 필터 사용 | PERMISSION_DENIED | [✓] `isSubAdminOf`는 user.subAdminOf 필드 기반 단일 사업장만 허용 |
| 4-D-03 | BUSINESS_ADMIN 전용 기능 — 신분증 요청 CREATE | `idCardAccessRequests` CREATE as SubAdmin | PERMISSION_DENIED (isBusinessAdmin()만 허용) | [✓] CREATE 규칙 `isBusinessAdmin()` 조건 |
| 4-D-04 | 사업장 정보 업데이트 | `businesses/{id}` UPDATE as SubAdmin | PERMISSION_DENIED (isAdminOf만 허용) | [✓] 규칙 `isAdminOf(businessId) || isSuperAdmin()` |

---

### 4-E. 비로그인 공격

| # | 시나리오 | 공격 방법 | 예상 결과 | 검사 |
|---|---------|---------|---------|------|
| 4-E-01 | 지원서 GET | 비로그인 상태로 `/applications/{id}` | PERMISSION_DENIED | [✓] GET 규칙 `isLoggedIn()` 조건 |
| 4-E-02 | 사업장 정보 GET | 비로그인 상태로 `/businesses/{id}` | PERMISSION_DENIED | [✓] GET 규칙 `isLoggedIn()` 조건 |
| 4-E-03 | username 열거 (허용된 범위) | `limit=1` 쿼리로 username 확인 | 허용 (로그인 UX용 의도된 설계) | [✓] 규칙 `!isLoggedIn() && request.query.limit <= 1` |
| 4-E-04 | username 대량 열거 (차단) | `limit=2` 이상으로 username 쿼리 | PERMISSION_DENIED | [✓] 규칙 `limit <= 1` 조건 위반 → 차단 |

---

## Phase 5: 회귀 체크리스트

> 이전 세션에서 발견된 버그가 재발하지 않는지 확인.

| # | 버그 ID | 설명 | 재발 방지 확인 방법 | 검사 |
|---|--------|------|-----------------|------|
| 5-01 | W-001 | payment_change_requests/interim_settlement_requests LIST 규칙 미적용 | 규칙에 `isAdminOf(businessId)` 확인 | [✓] |
| 5-02 | W-002 | worker_locations LIST 규칙 미적용 + getLocationsForApplications businessId 누락 | 규칙 + 서비스 함수 모두 확인 | [✓] |
| 5-03 | W-003 | getApplicationsByTOIds에 businessId 미전달 | `required String businessId` 파라미터 존재 확인 | [✓] |
| 5-04 | W-004 | idCardAccessRequests CREATE 시 requesterBusinessId 소속 검증 누락 | `isAdminOf(request.resource.data.requesterBusinessId)` 확인 | [✓] |
| 5-05 | W-005 | _cleanupApplicationRelatedData 관리자 경로 requesterBusinessId 필터 누락 | 분기 로직 확인 | [✓] |
| 5-06 | C-001 | getByApplication workerId/businessId 중 하나 필수 — 호출부 누락 가능성 | notification_screen.dart, worker_detail_dialog.dart 확인 | [✓] |
| 5-07 | C-002 | _findBundle businessId required 파라미터 추가 전 누락 | `required String businessId` 파라미터 + 전달 확인 | [✓] |
| 5-08 | BUG-2A-01 (신규) | getApplicationsForTO uid 필터 없이 쿼리 → USER 보안 규칙 미충족 | firestore_service.dart:507 — uid를 getApplicationsByTOId에 직접 전달하도록 수정 | [✓] |
| 5-09 | BUG-2A-02 (신규) | getScheduleChangeRequestsForDate whereIn 쿼리 → isAdminOf 검증 실패 | attendance_firestore.dart:484 — whereIn → 사업장별 개별 isEqualTo 쿼리로 분리 | [✓] |

---

## Phase 6: 신기능 추가 시 체크리스트

> 새로운 컬렉션을 추가하거나 기존 컬렉션에 새 쿼리를 추가할 때 반드시 확인.

### 6-A. 신규 컬렉션 추가 시

```
[ ] 1. Firestore rules에 해당 컬렉션 추가됐는가?
[ ] 2. LIST 규칙에 크로스-사업장 필터 적용됐는가?
        → USER: 본인 ID 필터 / BUSINESS_ADMIN: isAdminOf(businessId)
[ ] 3. CREATE 규칙에 명의 위조 방지가 적용됐는가?
        → userId/requesterId == auth.uid 검증
[ ] 4. UPDATE 규칙에 불변 필드 보호가 적용됐는가?
        → uid, businessId, 소유권 관련 필드 hasAny 차단
[ ] 5. CF Admin SDK만 접근해야 하는 컬렉션인가?
        → write: false 적용
[ ] 6. 서비스 함수 파라미터에 required businessId가 추가됐는가?
[ ] 7. 호출부에서 올바른 컨텍스트(USER/관리자)로 호출하는가?
```

### 6-B. 신규 서비스 함수 추가 시

```
[ ] 1. LIST 쿼리인가?
        → Firestore 규칙 LIST 요건과 필터가 일치하는가?
[ ] 2. 관리자 전용 함수인가?
        → businessId required 파라미터가 있는가?
[ ] 3. USER 전용 함수인가?
        → uid(본인) 필터가 쿼리에 포함됐는가?
[ ] 4. whereIn 쿼리인가?
        → 30개 단위 청크 처리가 있는가?
[ ] 5. 배치/트랜잭션 쿼리인가?
        → 오류 시 롤백 처리가 있는가?
```

### 6-C. 상태 전이 추가 시

```
[ ] 1. Firestore UPDATE 규칙에 새 상태 전이가 허용됐는가?
[ ] 2. 역방향 전이가 차단됐는가?
[ ] 3. 해당 상태에서 수정 가능한 필드 목록(hasOnly)이 최소화됐는가?
[ ] 4. 클라이언트 UI에서 잘못된 상태 전이 버튼이 비활성화됐는가?
```

---

## 감사 실행 가이드

### 감사 주기 권장

| 시점 | 수행할 Phase |
|------|------------|
| 신기능 추가 후 | Phase 2(관련 함수만) + Phase 6 체크리스트 |
| Firestore rules 수정 후 | Phase 1 + Phase 4(관련 역할만) |
| 정기 감사 (월 1회 권장) | Phase 1-A~F 전체 + Phase 5 |
| 배포 전 최종 검토 | 전체 Phase 1~5 |

### 시뮬레이션 실행 방법

Firebase Emulator를 사용해 실제 규칙을 테스트한다.

```bash
# 에뮬레이터 시작
firebase emulators:start --only firestore

# 규칙 테스트 실행
firebase emulators:exec --only firestore "flutter test test/firestore_rules_test.dart"
```

시뮬레이션 결과 기록 형식:
```
[날짜] Phase 4-A-01: ✓ PERMISSION_DENIED 확인
[날짜] Phase 4-B-03: ✗ 허용됨 (예상: DENIED) → firestore.rules:280 수정 필요
```

---

## 발견된 취약점 기록

| 발견일 | Phase | 항목 | 심각도 | 상태 | 수정 위치 |
|--------|-------|------|--------|------|---------|
| 2026-06-12 | 4-A | W-001: payment_change_requests LIST 미필터 | MEDIUM | ✅ 수정 | firestore.rules:999 |
| 2026-06-12 | 4-A | W-002: worker_locations LIST 미필터 | HIGH | ✅ 수정 | firestore.rules:746 |
| 2026-06-12 | 2-A | W-002: getLocationsForApplications businessId 누락 | HIGH | ✅ 수정 | worker_location_firestore.dart:128 |
| 2026-06-12 | 1-C | W-004: idCardAccessRequests CREATE requesterBusinessId 미검증 | HIGH | ✅ 수정 | firestore.rules:651 |
| 2026-06-12 | 2-A | W-005: _cleanupApplicationRelatedData 경로 분기 누락 | HIGH | ✅ 수정 | application_firestore.dart:1753 |
