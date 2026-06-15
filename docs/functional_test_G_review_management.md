# Category G: 리뷰 관리 기능 시나리오 (100개)

> 대상 파일
> - `lib/services/monthly_review_service.dart`
> - `lib/services/firestore/review_firestore.dart` (레거시)
> - `lib/models/core/monthly_review_model.dart`
> - `lib/models/core/review_request_model.dart`
> - `lib/screens/business_admin/admin_review_list_screen.dart`

---

## G-001 ~ G-020: 리뷰 작성 (createReviewForUser)

### G-001 정상 — 관리자 → 지원자 리뷰 작성 성공
- **기댓값**: `reviewKey = businessId_targetUserId_year_month` 로 문서 생성
- **부수효과**: review_requests.adminStatus = submitted + `(reviewId, null)` 반환

### G-002 정상 — 리뷰 기한 내 작성 (`_isWithinReviewWindow = true`)
- **환경**: 해당 월 마지막 날 + 14일 이내
- **기댓값**: 정상 작성

### G-003 정상 — 리뷰 기한 초과 차단
- **환경**: 해당 월 마지막 날 + 15일 이후
- **기댓값**: `(null, '리뷰 작성 기한(근무 완료 후 14일)이 지났습니다.')` 반환

### G-004 정상 — 트랜잭션으로 중복 제출 방지
- **환경**: 동일 reviewKey로 두 번 호출
- **기댓값**: 두 번째 호출 → `existing.exists = true` → `FirebaseException(already-exists)` → `(null, '이번 달 리뷰는 이미 작성되었습니다.')` 반환

### G-005 정상 — requestId 없이 작성 가능 (review_requests 없이 단독 작성)
- **기댓값**: requestId가 null이면 review_requests 업데이트 없이 리뷰만 생성

### G-006 **BUG-G-01** — review_requests 업데이트가 트랜잭션 밖
- **현상**: 트랜잭션 성공 후 `review_requests` set() 실패 시
  - `monthly_reviews` 생성됨
  - `review_requests.adminStatus = submitted` 미갱신 → CF 공개 트리거 미발동
  - 관리자 리뷰가 영구 미공개 상태로 고착
- **원인**: review_requests set이 트랜잭션 외부에서 별도 호출됨
- **수정**: review_requests 업데이트를 트랜잭션 내부로 이동 → **수정 완료**

### G-007 정상 — wouldRehire=false 로 작성
- **기댓값**: `wouldRehire: false` 저장, 재고용 비희망 배지 표시

### G-008 정상 — positiveTags + improvementTags 모두 있는 경우
- **기댓값**: 두 목록 모두 저장, 카드에서 색상 구분 렌더링

### G-009 정상 — comment 없이 작성
- **기댓값**: `comment: null` → 카드에서 코멘트 영역 숨김

### G-010 정상 — reviewerName이 `MonthlyReviewModel`에 저장
- **기댓값**: ADMIN_TO_USER reviewerId도 함께 저장 (`toMap()` 조건부 포함)

### G-011 엣지 — Firestore 오류 발생
- **기댓값**: catch → `(null, '리뷰 작성에 실패했습니다.')` 반환

### G-012 엣지 — `_isWithinReviewWindow` 경계값: 해당 월 마지막 날 + 정확히 14일
- **기댓값**: `deadline = monthEnd + 14일`, `DateTime.now().isBefore(deadline)` — 경계일 당일은 허용

### G-013 엣지 — `_isWithinReviewWindow` 클라이언트 시간 기준 ⚠️
- **현황**: 기기 시간 조작 시 기한 우회 가능 — 클라이언트 UX 제어용으로 의도된 설계
- **서버 강제**: CF에서 serverTimestamp 기준으로 deadline 재검증 권장 (G-013)
- **의사결정**: 주석 처리

### G-014 정상 — `reviewKey` 포맷 확인 (ADMIN_TO_USER)
- **기댓값**: `businessId_targetUserId_year_month` 형식

### G-015 정상 — `reviewYear/Month` 누락 시 `ArgumentError` throw (fromFirestore)
- **기댓값**: `ArgumentError('Document ${id} missing required field: reviewYear')`

### G-016 정상 — `reviewType` 알 수 없는 값 → `ADMIN_TO_USER` 폴백
- **기댓값**: `orElse: () => ReviewType.ADMIN_TO_USER`

### G-017 정상 — `toMap()` publishAt은 항상 null (CF 설정용)
- **기댓값**: `'publishAt': null` — 클라이언트가 직접 설정하지 않음

### G-018 정상 — `publishStatusText` — isPublished=false, publishAt=null
- **기댓값**: '공개 대기'

### G-019 정상 — `publishStatusText` — isPublished=false, publishAt=미래
- **기댓값**: 'N일 후 공개' 또는 '곧 공개'

### G-020 ⚠️ `getReviewsByBusiness` / `getPublishedReviewsForBusiness` limit(100)
- **현황**: 리뷰 100건 초과 사업장에서 오래된 리뷰 UI에서 누락
- **현실적 위험**: 초기 서비스 단계에서 낮음 — 페이지네이션 추후 대응 필요
- **의사결정**: 주석 처리

---

## G-021 ~ G-040: 사업장 리뷰 작성 (createReviewForBusiness)

### G-021 정상 — 지원자 → 사업장 리뷰 작성 성공
- **기댓값**: `reviewKey = businessId_workerId_year_month_biz` 로 문서 생성

### G-022 **BUG-G-02** — `createReviewForBusiness()` 트랜잭션 없이 batch.set() 사용
- **현상**: 동일 reviewKey로 두 번 동시 호출 시 두 번째 요청이 첫 번째를 덮어씀
- **원인**: `batch.set()` — 트랜잭션 없이 중복 체크 없음
- **기대**: `createReviewForUser()`와 동일하게 트랜잭션 + `existing.exists` 체크
- **영향**: 익명 사업장 리뷰 이중 제출 가능 (reviewerId 미저장이라 중복 감지 어려움)
- **수정**: 트랜잭션 방식으로 전환 → **수정 완료**

### G-023 정상 — USER_TO_BUSINESS 리뷰에 reviewerId 저장 안 됨
- **기댓값**: `toMap()`에서 `if (reviewType == ReviewType.ADMIN_TO_USER && reviewerId != null)` 조건 → BUSINESS 리뷰는 reviewerId 없음

### G-024 정상 — `reviewerName = '익명'` 고정
- **기댓값**: 사업장이 받은 리뷰 카드에 '익명'으로 표시

### G-025 정상 — review_requests.workerStatus = submitted 업데이트
- **기댓값**: requestId 있으면 `workerStatus: submitted, workerReviewId: reviewKey` 갱신

### G-026 정상 — wouldWorkAgain → `wouldRehire` 필드로 저장
- **기댓값**: USER_TO_BUSINESS의 재근무 의사가 `wouldRehire`에 저장됨

### G-027 정상 — 기한 초과 차단 — USER_TO_BUSINESS도 동일 기준
- **기댓값**: `_isWithinReviewWindow` → 동일 14일 기준 적용

### G-028 정상 — 기존 리뷰 중복 작성 시 에러 반환 ⚠️
- **현황**: BUG-G-02 수정 후, 이미 작성한 리뷰의 동일 key로 재작성 시 → `already-exists` 처리
- **기댓값**: 수정 후 `(null, '이번 달 리뷰는 이미 작성되었습니다.')` 반환

### G-029 정상 — `generateKeyForBusiness` 포맷 확인
- **기댓값**: `businessId_workerId_year_month_biz` — `_biz` 접미사로 ADMIN_TO_USER 키 충돌 방지

### G-030 정상 — Firestore 오류 처리
- **기댓값**: catch → `(null, '리뷰 작성에 실패했습니다.')` 반환

---

## G-031 ~ G-045: 리뷰 요청 (ReviewRequest)

### G-031 정상 — `getPendingRequestsForBusiness()` — adminStatus=pending + isPublished=false
- **기댓값**: 미작성 + 미공개 요청만 반환

### G-032 정상 — `getPendingRequestsForWorker()` — workerStatus=pending + isPublished=false
- **기댓값**: 지원자가 작성해야 할 요청 목록

### G-033 정상 — `getAllNonPublishedRequestsForBusiness()` — adminStatus 무관
- **기댓값**: 관리자 작성 완료 후 상대방 대기 중인 것도 포함

### G-034 정상 — `ReviewRequestModel.deadline` 누락 시 `ArgumentError` throw
- **기댓값**: `ArgumentError('ReviewRequestModel: deadline is missing')`

### G-035 정상 — `bothSubmitted` 확인
- **기댓값**: `adminStatus == submitted && workerStatus == submitted` → CF 즉시 공개 트리거

### G-036 정상 — `isDeadlinePassed` 확인
- **기댓값**: `DateTime.now().isAfter(deadline)` — 기한 경과 시 true

### G-037 정상 — `_requestDeadlines` 맵 구성 (allNonPublished 기반)
- **기댓값**: `{requestId: deadline}` — 미작성 탭 카드 툴팁에 자동공개일 표시

### G-038 정상 — deadline 3일 이내 임박 → 빨간 테두리 + 경보 아이콘
- **기댓값**: `req.deadline.difference(DateTime.now()).inDays <= 3`

### G-039 정상 — 미작성 탭 배지 urgent 표시
- **기댓값**: pending 중 deadline 3일 이내 항목 있으면 `urgent=true`

### G-040 정상 — `_buildPendingRequestList()` — activePending/expiredPending 구분
- **기댓값**: 활성 요청 위, 기한만료 요청 아래에 반투명(opacity=0.5) 표시

---

## G-041 ~ G-055: 리뷰 조회

### G-041 정상 — `getPublishedReviewsForUser()` — isPublished=true 필터
- **기댓값**: 공개된 리뷰만 반환

### G-042 정상 — `getAllReviewsForUser()` — isPublished 무관
- **기댓값**: 미공개 리뷰 포함 (관리자 전용)

### G-043 정상 — `getReviewsByBusiness()` — ADMIN_TO_USER 타입만
- **기댓값**: 사업장이 작성한 근무자 리뷰만 반환

### G-044 정상 — `getPublishedReviewsForBusiness()` — USER_TO_BUSINESS + isPublished=true
- **기댓값**: 사업장이 받은 공개 리뷰만 반환

### G-045 ⚠️ `getReviewableWorkers()` longTermFuture limit(500)
- **현황**: 한 사업장에서 월 500명 초과 장기 근무자 시 일부 누락
- **현실적 위험**: 초기 서비스에서 가능성 낮음
- **의사결정**: 주석 처리

### G-046 정상 — `getReviewableWorkers()` — 장기/단기 중복 문서 제거
- **기댓값**: `longTermDocIds.contains(doc.id)` → 같은 문서가 양쪽 쿼리에 나타나도 1회만 집계

### G-047 정상 — `getReviewableWorkers()` — 이미 리뷰한 근무자 제외
- **기댓값**: `reviewedUserIds.contains(uid)` → 스킵

### G-048 정상 — `getReviewableWorkers()` — 장기 근무자 실제 근무 일수 계산
- **기댓값**: `_countWorkingDaysInMonth()` — 계약 시작/종료 + 요일 기반 일수 계산

### G-049 정상 — `_countWorkingDaysInMonth()` — 계약 기간과 해당 월 교집합만
- **기댓값**: `effectiveStart = max(contractStart, monthStart)`, `effectiveEnd = min(contractEnd, monthEnd)`

### G-050 정상 — `getReviewById()` — reviewKey == doc ID 조회
- **기댓값**: 문서 존재하면 `MonthlyReviewModel` 반환

### G-051 정상 — `hasAdminReviewThisMonth()` — 중복 확인
- **기댓값**: `monthly_reviews/{key}` 존재 여부 확인

### G-052 정상 — `hasWorkerReviewThisMonth()` — 중복 확인 (사업장 리뷰)
- **기댓값**: `key = businessId_reviewerId_year_month_biz` 존재 여부

### G-053 정상 — `getReviewRequest()` — requestKey로 단건 조회
- **기댓값**: 존재 시 `ReviewRequestModel`, 없으면 null

### G-054 정상 — `getUserReviews()` (레거시) limit=10 기본값
- **기댓값**: 최근 10건만 반환 (레거시 `review_firestore.dart`)

### G-055 ⚠️ 레거시 `createReview()` (review_firestore.dart) — `_updateUserReviewStats()`가 신규 리뷰 즉시 미반영
- **현황**: 리뷰 생성 직후 `isPublished=false` → 통계 쿼리 (`isPublished=true` 필터)에 포함 안 됨
- **현황**: CF가 publish 후 통계 재계산 필요 — 의도된 설계
- **의사결정**: 주석 처리

---

## G-056 ~ G-070: 통계 업데이트

### G-056 정상 — `updateUserReviewStats()` — isPublished=true 기준
- **기댓값**: 공개 리뷰만 averageRating, reviewCount, rehireRate 계산

### G-057 정상 — `updateUserReviewStats()` — 리뷰 없음 → 조기 반환
- **기댓값**: `snap.docs.isEmpty` → return (update 호출 없음)

### G-058 정상 — `updateUserReviewStats()` — rating=0인 리뷰는 평균에서 제외
- **기댓값**: `if (r > 0)` → ratedCount 증가 안 함

### G-059 정상 — `updateBusinessReviewStats()` — USER_TO_BUSINESS + isPublished=true
- **기댓값**: `businesses/{id}.rating`, `reviewCount` 갱신

### G-060 정상 — `rehireRate` 계산 — wouldRehire=true 비율
- **기댓값**: `rehireYesCount / snap.size` (0~1 범위)

### G-061 정상 — 통계 업데이트 실패해도 상위 로직에 영향 없음
- **기댓값**: catch → `debugPrint` → 반환

### G-062 정상 — `getReviewTags()` — settings/review_tags 조회
- **기댓값**: 없으면 defaults 생성 후 저장 + 반환

### G-063 정상 — `getTrustSettings()` — settings/trust_rules 조회
- **기댓값**: 없으면 defaults 생성 후 저장 + 반환

### G-064 정상 — `getReviewTags()` Firestore 오류
- **기댓값**: catch → `ReviewTagsModel.defaults()` 반환

### G-065 정상 — `getTrustSettings()` Firestore 오류
- **기댓값**: catch → `TrustSettingsModel.defaults()` 반환

---

## G-066 ~ G-080: 관리자 화면 (AdminReviewListScreen)

### G-066 정상 — `_loadReviews()` 4개 쿼리 병렬 실행
- **기댓값**: `Future.wait([written, received, pending, allNonPublished])` 병렬 처리

### G-067 정상 — `businessId` 결정 우선순위
- **기댓값**: `widget.businessId ?? user.businessId ?? managedBusinessIds.firstOrNull`

### G-068 정상 — businessId = null → 로딩 종료 후 빈 화면
- **기댓값**: `setState(() => _isLoading = false)` 후 리뷰 없는 상태 렌더링

### G-069 정상 — workerName 누락 시 users 컬렉션 보완 조회
- **기댓값**: `missingNameIds` → `Future.wait` 병렬 조회 → `_resolvedWorkerNames` 캐시

### G-070 정상 — 연도 필터 자동 이동 (데이터 없는 연도 → 최신 연도로)
- **기댓값**: `!years.contains(_selectedYear)` → `_selectedYear = years.first`

### G-071 정상 — 월 칩 — 데이터 있는 달만 표시 + 건수
- **기댓값**: `_availableMonths` 맵 기준 칩 생성, `label count` 형태

### G-072 ⚠️ `addBusinessResponse()` — 기존 답변 덮어쓰기 가능 (G-072)
- **현황**: 답변 존재 여부 체크 없음 → 재호출 시 기존 답변 override
- **현황**: UI에서 "답변하기" 버튼은 `businessResponse == null`일 때만 표시 → 실제 발생 가능성 낮음
- **의사결정**: 주석 처리

### G-073 정상 — 답변 등록 성공 후 `_loadReviews()` 재호출
- **기댓값**: `ok = true` → 새로고침

### G-074 정상 — 답변 다이얼로그 텍스트 비어있으면 등록 안 됨
- **기댓값**: `if (text.isEmpty) return`

### G-075 정상 — `_buildReviewList` 검색 필터 (작성 탭: targetUserName, 받음 탭: reviewerName)
- **기댓값**: `isWritten ? targetUserName : reviewerName`으로 검색

### G-076 정상 — 연도 네비게이션 — 가장 과거 연도에서 left 버튼 비활성화
- **기댓값**: `yearIdx < years.length - 1` → `_YearNavButton(enabled: false)`

### G-077 정상 — 연도 변경 시 월 필터 초기화
- **기댓값**: `_selectedYear = years[i]` → `_selectedMonth = 0`

### G-078 정상 — 탭 카운트 배지 — 필터 적용된 건수 표시
- **기댓값**: `_writtenReviews.length`, `_receivedReviews.length`, `_pendingRequests.length`

### G-079 정상 — 리뷰 상세 바텀시트 — DraggableScrollableSheet
- **기댓값**: `initialChildSize: 0.6`, `maxChildSize: 0.9`

### G-080 정상 — 받은 리뷰(USER_TO_BUSINESS)는 `isPublished=true`만 표시
- **기댓값**: `getPublishedReviewsForBusiness` 사용 → 미공개 근무자 리뷰는 관리자도 못 봄

---

## G-081 ~ G-095: _openReviewFromRequest (리뷰 작성 진입)

### G-081 정상 — 근무자 정보 + 출근 기록 병렬 조회
- **기댓값**: `Future.wait([userDoc, attendanceQuery])` 병렬

### G-082 정상 — 근무자 성별/나이 조회 성공
- **기댓값**: `UserModel.fromMap()` → `workerGender`, `workerAge` 추출

### G-083 정상 — 출근 기록 `wageStatus=confirmed|transferred` 건수 → workDaysInMonth
- **기댓값**: `attSnap.docs.length` = 확정/이체된 출근 일수

### G-084 엣지 — 출근 기록 없음 → workDaysInMonth=0
- **기댓값**: 리뷰 다이얼로그에 workDaysInMonth=0 전달

### G-085 엣지 — 근무자 정보 조회 실패
- **기댓값**: catch → `debugPrint` → `workerGender=null, workerAge=null, workDaysInMonth=0` → 다이얼로그 열림

### G-086 정상 — 리뷰 다이얼로그 result=true → `_loadReviews()` 재호출
- **기댓값**: 목록 갱신

### G-087 정상 — 리뷰 다이얼로그 result=false|null → 재로드 없음
- **기댓값**: 변경 없이 유지

### G-088 정상 — `reviewer == null` 조기 반환
- **기댓값**: 로그인 정보 없으면 다이얼로그 열지 않음

### G-089 정상 — yearMonthStr 포맷 (`2024-01` 형태)
- **기댓값**: `'${req.reviewYear}-${req.reviewMonth.toString().padLeft(2, '0')}'`

### G-090 정상 — 기한 만료 요청은 "작성" 버튼 숨김
- **기댓값**: `if (!req.isDeadlinePassed)` → 버튼 표시, 만료 시 버튼 없음

---

## G-091 ~ G-100: 기타 / 엣지

### G-091 정상 — `attendanceRate` 계산 (workDaysInMonth=0 방어)
- **기댓값**: `workDaysInMonth == 0 → return 0.0` (ZeroDivisionError 방지)

### G-092 정상 — `ratingStars` — rating=0 → '☆☆☆☆☆'
- **기댓값**: `'⭐' * 0 + '☆' * 5`

### G-093 정상 — `ratingText` — rating=6 이상 → `''` (기본값)
- **기댓값**: switch default → `''`

### G-094 정상 — `ReviewPartyStatus._parseStatus` 알 수 없는 값 → pending 폴백
- **기댓값**: default → `ReviewPartyStatus.pending`

### G-095 정상 — `getReviewableWorkers()` 장기 근무자 workDays=0 → 제외
- **기댓값**: `if (daysInMonth == 0) continue`

### G-096 정상 — `_buildStatusBadgeCompact` — isPublished=true → Tooltip 없음
- **기댓값**: 공개된 리뷰는 툴팁 없이 배지만 표시

### G-097 정상 — `_deadlineSubtext` — requestId 있고 deadline 있는 경우
- **기댓값**: '상대방 미작성 시 M/D 자동공개' 텍스트

### G-098 정상 — `_deadlineSubtext` — requestId=null
- **기댓값**: '상대방 작성 후 공개'

### G-099 정상 — `_availableYears` — 데이터 없으면 현재 연도 포함
- **기댓값**: `years.isEmpty → years.add(DateTime.now().year)` → 최소 1개 연도 보장

### G-100 정상 — `_selectedYear` 연도 데이터 없는 경우 연도 칩 숨김
- **기댓값**: `if (years.length > 1)` → 단일 연도이면 연도 네비게이션 숨김

---

## 버그 수정 요약

| ID       | 위치                                      | 내용                                                         | 상태     |
|----------|------------------------------------------|--------------------------------------------------------------|--------|
| BUG-G-01 | monthly_review_service.dart:createReviewForUser | review_requests 업데이트 트랜잭션 밖 → 원자성 부재            | ✅ 수정 |
| BUG-G-02 | monthly_review_service.dart:createReviewForBusiness | 트랜잭션 없이 batch.set → 중복 제출 방지 없음           | ✅ 수정 |

## 추가검증 대상 (⚠️)

| ID    | 위치                                          | 내용                                            | 결정  |
|-------|----------------------------------------------|-------------------------------------------------|-------|
| G-013 | monthly_review_service.dart _isWithinReviewWindow | 클라이언트 시간 기준 → 기기 조작 우회 가능     | 주석  |
| G-020 | monthly_review_service.dart getReviewsByBusiness | limit(100) — 초과 시 누락                       | 주석  |
| G-045 | monthly_review_service.dart getReviewableWorkers | longTermFuture limit(500)                       | 주석  |
| G-055 | review_firestore.dart _updateUserReviewStats | 신규 리뷰 즉시 통계 미반영 (isPublished 기준)   | 주석  |
| G-072 | monthly_review_service.dart addBusinessResponse | 기존 답변 덮어쓰기 (UI 보호로 발생 가능성 낮음) | 주석  |
