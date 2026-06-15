# Category H — 알림 · 서류 · 설정 관리 기능 검증 (100개 시나리오)

> 검증 범위: `notification_screen.dart`, `notification_firestore.dart`, `notification_provider.dart`,
> `document_management_screen.dart`, `settings_screen.dart`  
> 버그 수정: BUG-H-01, BUG-H-02  
> 경고 주석: H-03, H-04

---

## 섹션 1 — 알림 관리 (H-001 ~ H-040)

### H-001 알림 화면 진입
**입력**: 로그인 후 알림 아이콘 탭  
**기대**: NotificationProvider 스트림에서 알림 목록 로드, `전체` / `미읽음` 탭 표시  
**결과**: ✅

### H-002 전체 탭 — 알림 없음 empty state
**입력**: 알림이 0건인 사용자로 전체 탭 진입  
**기대**: AppEmptyState "알림이 없습니다" 표시  
**결과**: ✅

### H-003 미읽음 탭 — 미읽음 없음 empty state
**입력**: 모든 알림이 isRead=true인 상태에서 미읽음 탭 탭  
**기대**: AppEmptyState "미읽음 알림이 없습니다" 표시  
**결과**: ✅

### H-004 알림 탭 배지 — 미읽음 카운트 정확도
**입력**: 미읽음 알림 3건 있는 상태  
**기대**: 미읽음 탭 배지에 "3" 표시, urgent=true로 빨간 배지  
**결과**: ✅

### H-005 알림 탭 배지 — 미읽음 0건 시 배지 미표시
**입력**: 미읽음 0건  
**기대**: 미읽음 탭 배지 숨김 (AppTabLabel count=0)  
**결과**: ✅

### H-006 알림 카드 탭 — 읽음 처리
**입력**: 미읽음 알림 카드 탭  
**기대**: `provider.markAsRead(notificationId)` 호출, 카드가 읽음 상태로 즉시 전환  
**결과**: ✅

### H-007 알림 카드 스와이프 삭제
**입력**: 알림 카드를 좌로 스와이프  
**기대**: `provider.deleteNotification(id)` 호출, "알림이 삭제되었습니다" 토스트  
**결과**: ✅

### H-008 알림 카드 삭제 실패
**입력**: 네트워크 단절 상태에서 알림 삭제  
**기대**: "알림 삭제에 실패했습니다" 에러 토스트  
**결과**: ✅

### H-009 모두 읽음 버튼 — 미읽음 있을 때만 표시
**입력**: 미읽음 알림 1건 이상  
**기대**: 헤더 오른쪽에 "모두 읽음" TextButton 표시  
**결과**: ✅

### H-010 모두 읽음 버튼 — 미읽음 없으면 숨김
**입력**: 모든 알림 읽음 상태  
**기대**: "모두 읽음" 버튼 미표시  
**결과**: ✅

### H-011 모두 읽음 처리
**입력**: "모두 읽음" 버튼 탭  
**기대**: `markAllNotificationsAsRead()` 호출, 전체 미읽음→읽음 전환, "모든 알림을 읽음 처리했습니다" 토스트  
**결과**: ✅

### H-012 에러 상태 표시
**입력**: Firestore 스트림 에러 발생  
**기대**: "알림을 불러오지 못했습니다" AppEmptyState + "다시 시도" 버튼 표시  
**결과**: ✅

### H-013 에러 상태에서 다시 시도
**입력**: 에러 상태에서 "다시 시도" 탭  
**기대**: `provider.retry()` 호출, 스트림 재연결  
**결과**: ✅

### H-014 (BUG-H-01 수정) 에러 상태에서 pull-to-refresh
**입력**: 에러 상태에서 목록 당겨 새로고침  
**기대**: `provider.retry()` 호출 → 스트림 재연결 시도  
**수정 전**: 300ms 딜레이만 있고 `retry()` 미호출  
**수정 후**: `provider.retry()` → `Future.delayed(300ms)` 순서로 실행  
**결과**: ✅ BUG-H-01 수정 완료

### H-015 알림 타입별 딥링크 — applicationConfirmed
**입력**: 지원 확정 알림 탭 (USER)  
**기대**: `MyApplicationsScreen`으로 이동  
**결과**: ✅

### H-016 알림 타입별 딥링크 — applicationRejected
**입력**: 지원 거절 알림 탭 (USER)  
**기대**: `MyApplicationsScreen`으로 이동  
**결과**: ✅

### H-017 알림 타입별 딥링크 — newApplication (ADMIN)
**입력**: 새 지원자 알림 탭 (BUSINESS_ADMIN)  
**기대**: TO + WorkDetail 로드 후 `WorkApplicantsDialog` 표시  
**결과**: ✅

### H-018 알림 딥링크 — newApplication 데이터 없음
**입력**: `notification.data`가 null인 newApplication 알림 탭  
**기대**: `IntegratedWorkforceScreen`으로 폴백  
**결과**: ✅

### H-019 알림 딥링크 — newApplication TO 없음
**입력**: toId가 가리키는 TO가 삭제된 경우  
**기대**: "공고를 찾을 수 없습니다" 토스트 + `IntegratedWorkforceScreen` 폴백  
**결과**: ✅

### H-020 알림 딥링크 — scheduleChangeRequested (USER)
**입력**: 스케줄 변경 요청 알림 탭 (USER)  
**기대**: `MyRequestsDialog` 표시  
**결과**: ✅

### H-021 알림 딥링크 — scheduleChangeRequested (ADMIN)
**입력**: 스케줄 변경 요청 알림 탭 (ADMIN)  
**기대**: `IntegratedWorkforceScreen`으로 이동  
**결과**: ✅

### H-022 알림 딥링크 — contractSignRequested
**입력**: 계약서 서명 요청 알림 탭 (USER)  
**기대**: contractId로 계약서 조회 후 `ContractSignScreen` 이동  
**결과**: ✅

### H-023 알림 딥링크 — contractSignRequested 계약서 없음
**입력**: contractId가 없거나 계약서 삭제된 경우  
**기대**: "계약서를 찾을 수 없습니다" 토스트 + `MyApplicationsScreen` 폴백  
**결과**: ✅

### H-024 알림 딥링크 — memberInvitationReceived
**입력**: 멤버 초대 알림 탭  
**기대**: 초대 조회 후 수락/거절 AlertDialog 표시  
**결과**: ✅

### H-025 멤버 초대 수락 처리
**입력**: 초대 AlertDialog에서 "수락" 탭  
**기대**: `MemberService().acceptInvitation()` 호출, `UserProvider.refreshUserData()`, "초대를 수락했습니다" 토스트  
**결과**: ✅

### H-026 멤버 초대 거절 처리
**입력**: 초대 AlertDialog에서 "거절" 탭  
**기대**: `MemberService().rejectInvitation()` 호출, "초대를 거절했습니다" 토스트  
**결과**: ✅

### H-027 멤버 초대 — 이미 처리된 초대
**입력**: `invitation.isPending == false`인 초대 알림 탭  
**기대**: "이미 처리된 초대입니다" 에러 토스트  
**결과**: ✅

### H-028 멤버 초대 — 초대 데이터 없음
**입력**: `invitationId`가 null인 memberInvitation 알림 탭  
**기대**: "초대 정보를 찾을 수 없습니다" 에러 토스트  
**결과**: ✅

### H-029 알림 딥링크 — wageConfirmed
**입력**: 급여 확정 알림 탭  
**기대**: `MyApplicationsScreen`으로 이동  
**결과**: ✅

### H-030 알림 딥링크 — contractExpiringReminder (businessId 있음)
**입력**: 계약 만료 임박 알림 탭 (ADMIN, businessId 존재)  
**기대**: `FixedWorkerManagementDialog` 표시  
**결과**: ✅

### H-031 알림 딥링크 — contractExpiringReminder (businessId 없음)
**입력**: 계약 만료 임박 알림 탭 (ADMIN, businessId null)  
**기대**: `IntegratedWorkforceScreen` 폴백  
**결과**: ✅

### H-032 알림 딥링크 — idCardAccessRequested (USER)
**입력**: 신분증 열람 요청 알림 탭 (USER)  
**기대**: `MyRequestsDialog` 표시  
**결과**: ✅

### H-033 알림 딥링크 — reviewReceived (USER)
**입력**: 리뷰 수신 알림 탭 (USER)  
**기대**: `MyScheduleScreen`으로 이동  
**결과**: ✅

### H-034 알림 딥링크 — reviewReceived (ADMIN)
**입력**: 리뷰 수신 알림 탭 (BUSINESS_ADMIN)  
**기대**: 아무 동작 없음 (관리자는 `if (isUser)`로 분기 없음)  
**비고**: ⚠️ BUSINESS_ADMIN이 USER_TO_BUSINESS 리뷰를 받으면 알림은 오지만 탭해도 이동 없음 — 미래에 `AdminReviewListScreen` 딥링크 추가 고려  
**결과**: 설계상 허용, 주석 처리

### H-035 알림 실시간 갱신
**입력**: 타 기기/CF에서 새 알림 생성  
**기대**: Firestore 스트림이 즉시 UI 반영 (setState 불필요)  
**결과**: ✅

### H-036 알림 스트림 limit — ⚠️ 30개 초과 누락
**입력**: 알림 31건 이상 존재  
**기대**: 스트림에는 최신 30건만 표시, 31번째 이후 알림 미표시  
**비고**: ⚠️ H-03: limit(30) 고정 설계 — 미읽음 카운트 과소 표시 가능. Provider 구조 대규모 수정 필요하여 현행 유지, 주석 추가 완료  
**결과**: ⚠️ limit 설계 제약 (코드 주석 완료)

### H-037 오래된 알림 자동 삭제
**입력**: 로그인 시 `setUser()` 호출  
**기대**: 30일 이상 된 알림 최대 500건 배치 삭제 (백그라운드)  
**결과**: ✅

### H-038 (BUG-H-02 수정) deleteOldNotifications limit 없이 전체 조회
**입력**: 오래된 알림 수천 건 존재  
**수정 전**: limit 없이 `.get()` → 대량 메모리 사용 가능  
**수정 후**: `.limit(500)` 추가 → 1회 호출당 최대 500건 처리  
**결과**: ✅ BUG-H-02 수정 완료

### H-039 markAllNotificationsAsRead — 500건 초과 배치 분할
**입력**: 미읽음 알림 600건 존재  
**기대**: `chunkSize=500`으로 2번 배치 처리 (500 + 100)  
**결과**: ✅

### H-040 로그아웃 시 알림 스트림 정리
**입력**: 로그아웃  
**기대**: `NotificationProvider.clearUser()` → 스트림 구독 취소, `_notifications = []`, `notifyListeners()`  
**결과**: ✅

---

## 섹션 2 — 서류 관리 (H-041 ~ H-070)

### H-041 서류 관리 화면 진입 (USER)
**입력**: USER로 설정 > '내 서류 관리' 탭  
**기대**: 신분증 섹션 + 통장 정보 섹션 표시  
**결과**: ✅

### H-042 서류 관리 화면 진입 (BUSINESS_ADMIN)
**입력**: BUSINESS_ADMIN으로 설정 > '내 서류 관리' 탭  
**기대**: 사업자등록증 섹션 + 사업자 정보 입력 섹션 표시  
**결과**: ✅

### H-043 사업자 정보 저장 — 정상
**입력**: 사업자번호 10자리, 상호명, 대표자명 입력 후 저장  
**기대**: `updateUserDocument()` 호출, `refreshCurrentUser()`, "사업자 정보가 저장되었습니다" 토스트  
**결과**: ✅

### H-044 사업자 정보 저장 — 사업자번호 미달
**입력**: 사업자번호 9자리 입력 후 저장  
**기대**: "사업자번호 10자리를 입력해주세요" 경고 토스트, 저장 안 됨  
**결과**: ✅

### H-045 사업자 정보 저장 — 상호명 공백
**입력**: 상호명 공백 입력 후 저장  
**기대**: "상호명을 입력해주세요" 경고 토스트  
**결과**: ✅

### H-046 사업자 정보 저장 — 대표자명 공백
**입력**: 대표자명 공백 입력 후 저장  
**기대**: "대표자명을 입력해주세요" 경고 토스트  
**결과**: ✅

### H-047 '내 이름' 버튼
**입력**: 대표자명 입력란 옆 "내 이름" 버튼 탭  
**기대**: 사용자 이름을 대표자명 필드에 자동 입력  
**결과**: ✅

### H-048 사업자등록증 업로드 — 사업자 정보 미저장 시 차단
**입력**: 사업자 정보 저장 전 "사업자등록증 업로드" 탭  
**기대**: "사업자 정보를 먼저 저장해주세요" 경고 토스트  
**결과**: ✅

### H-049 사업자등록증 업로드 정상
**입력**: 사업자 정보 저장 후 이미지 선택 및 업로드  
**기대**: Storage 업로드 → Firestore URL 저장 → 기존 이미지 삭제(best-effort) → "사업자등록증이 등록되었습니다" 토스트  
**결과**: ✅

### H-050 사업자등록증 재업로드
**입력**: 등록된 사업자등록증이 있을 때 "재업로드" 탭  
**기대**: 새 이미지 업로드 성공 후 기존 Storage 이미지 삭제(best-effort)  
**결과**: ✅

### H-051 사업자등록증 Storage 업로드 실패
**입력**: Storage 연결 불가 상태에서 업로드  
**기대**: "이미지 업로드에 실패했습니다" 에러 토스트, 기존 데이터 유지  
**결과**: ✅

### H-052 사업자등록증 삭제 확인
**입력**: "삭제" 버튼 탭 → 확인 다이얼로그  
**기대**: `DialogHelper.showDangerConfirm` 표시  
**결과**: ✅

### H-053 사업자등록증 삭제 취소
**입력**: 삭제 확인 다이얼로그에서 취소  
**기대**: 삭제 미실행, 기존 이미지 유지  
**결과**: ✅

### H-054 사업자등록증 삭제 정상
**입력**: 삭제 확인  
**기대**: Firestore `businessLicenseImageUrl: null` 업데이트 → Storage 이미지 삭제 → "사업자등록증이 삭제되었습니다" 토스트  
**결과**: ✅

### H-055 신분증 업로드 — 정상
**입력**: USER로 신분증 이미지 선택  
**기대**: Storage 업로드 → Firestore `idCardImageUrl`, `isIdVerified: true`, `idCardVerifiedAt` 저장 → "신분증이 등록되었습니다" 토스트  
**결과**: ✅

### H-056 신분증 업로드 — 주민번호 검증 연동
**입력**: 저장된 residentNumber 8자리가 있는 경우  
**기대**: `pickAndVerifyIdCard`에 `expectedResidentNumber` 전달하여 OCR 검증 수행  
**결과**: ✅

### H-057 신분증 업로드 — 주민번호 미등록 시 검증 스킵
**입력**: `user.residentNumber == null`  
**기대**: `expectedResidentNumber: null`로 OCR 호출, 이름만 검증  
**결과**: ✅

### H-058 신분증 삭제 정상
**입력**: 신분증 삭제 확인  
**기대**: Firestore `idCardImageUrl: null`, `isIdVerified: false`, `idCardVerifiedAt: null` 저장, Storage 삭제  
**결과**: ✅

### H-059 통장 정보 저장 — 정상
**입력**: 은행 선택 + 계좌번호 입력 후 저장  
**기대**: Firestore `bankName`, `accountNumber`, `accountHolder` 저장, "통장 정보가 저장되었습니다" 토스트  
**결과**: ✅

### H-060 통장 정보 저장 — 은행 미선택
**입력**: 은행 미선택 + 계좌번호만 입력 후 저장  
**기대**: "은행과 계좌번호를 입력해주세요" 경고 토스트  
**결과**: ✅

### H-061 통장 정보 저장 — 계좌번호 공백
**입력**: 은행 선택 + 계좌번호 빈 값  
**기대**: "은행과 계좌번호를 입력해주세요" 경고 토스트  
**결과**: ✅

### H-062 통장 정보 삭제
**입력**: 통장 정보 삭제 확인  
**기대**: `bankbookImageUrl` Storage 삭제(존재 시) → Firestore `bankName/accountNumber/accountHolder/bankbookImageUrl: null` → UI 초기화  
**결과**: ✅

### H-063 서류 화면 — 변경 후 뒤로가기
**입력**: 신분증/통장 정보 변경 후 뒤로가기 버튼  
**기대**: `NavigationHelper.pop(context, changed: true)` 호출, 이전 화면에 변경 여부 전달  
**결과**: ✅

### H-064 서류 화면 — 변경 없이 뒤로가기
**입력**: 아무 변경 없이 뒤로가기  
**기대**: `changed: false`로 pop  
**결과**: ✅

### H-065 서류 화면 — 로딩 중 UI
**입력**: 업로드/저장 진행 중  
**기대**: `CircularProgressIndicator` 표시, 버튼 비활성화  
**결과**: ✅

### H-066 서류 화면 — 사용자 null
**입력**: `currentUser == null` 상태로 화면 접근  
**기대**: "사용자 정보를 불러올 수 없습니다" 텍스트 표시 (GradientScaffold 내)  
**결과**: ✅

### H-067 서류 화면 — pull-to-refresh
**입력**: 서류 목록 당겨 새로고침  
**기대**: `_loadUserDocuments()` 재실행, 최신 사용자 데이터 반영  
**결과**: ✅

### H-068 사업자번호 포맷터 — 입력 시 자동 하이픈
**입력**: 사업자번호 123456789 입력  
**기대**: `BusinessNumberFormatter`가 "123-45-67890" 형식으로 자동 변환  
**결과**: ✅

### H-069 사업자등록증 재업로드 — hasBusinessInfo 체크
**입력**: 사업자 정보 미저장 상태에서 "재업로드" 탭  
**기대**: "사업자 정보를 먼저 저장해주세요" 경고 (H-048과 동일)  
**결과**: ✅

### H-070 서류 화면 새로고침 — userProvider 갱신 반영
**입력**: 저장 성공 후 `refreshCurrentUser()` 완료  
**기대**: `context.select<UserProvider, UserModel?>` 리빌드로 UI 자동 갱신  
**결과**: ✅

---

## 섹션 3 — 설정 관리 (H-071 ~ H-100)

### H-071 설정 화면 진입 — USER
**입력**: USER로 설정 탭 진입  
**기대**: 내 정보 섹션(프로필 수정, 내 서류 관리, 내 평가 확인), 알림, 앱 정보, 도움말 메뉴 표시  
**결과**: ✅

### H-072 설정 화면 진입 — BUSINESS_ADMIN
**입력**: BUSINESS_ADMIN으로 설정 진입  
**기대**: 사업장 설정 섹션(내 서류 관리, 사업장 정보, 업무 유형, 근로계약서, 멤버 관리, 리뷰 관리) 추가 표시  
**결과**: ✅

### H-073 설정 화면 진입 — SUPER_ADMIN
**입력**: SUPER_ADMIN으로 설정 진입  
**기대**: 관리자 메뉴(전체 사용자, 전체 사업장, 약관 관리, Application 마이그레이션) 표시  
**결과**: ✅

### H-074 설정 헤더 프로필
**입력**: 설정 화면 헤더  
**기대**: 사용자 이름, `@username`, 역할 배지(아이콘+텍스트) 표시  
**결과**: ✅

### H-075 설정 헤더 — USER 신뢰도/통계 표시
**입력**: USER로 설정 헤더 확인  
**기대**: trustGradeEmoji, 신뢰도 점수, 지원 횟수, 근무 일수 compact 표시  
**결과**: ✅

### H-076 알림 토글 — 푸시 ON
**입력**: 푸시 알림 토글 활성화 (시스템 권한 이미 허용)  
**기대**: `FCMService().initialize(userId)` 호출, "푸시 알림이 활성화되었습니다" 토스트  
**결과**: ✅

### H-077 알림 토글 — 권한 거부된 경우 ON 시도
**입력**: 시스템 알림 권한 거부 상태에서 토글 ON  
**기대**: 권한 요청 → 거부 → "기기 설정에서 알림 권한을 허용해주세요" 경고 + openAppSettings 호출  
**결과**: ✅

### H-078 알림 토글 — 푸시 OFF
**입력**: 푸시 알림 토글 비활성화  
**기대**: `FCMService().clearToken()` 호출, "푸시 알림이 비활성화되었습니다" 토스트  
**결과**: ✅

### H-079 알림 토글 — 비활성화 시 개별 알림 설정 카드 숨김
**입력**: `_isPushEnabled == false`  
**기대**: `_buildNotifPrefsCard` 미표시  
**결과**: ✅

### H-080 개별 알림 설정 — 카테고리 토글
**입력**: "지원 알림" 토글 OFF  
**기대**: `_toggleNotifPref('applications', false)` → Firestore `notifPrefs` 업데이트  
**결과**: ✅

### H-081 개별 알림 설정 — Firestore 실패 시 롤백
**입력**: 카테고리 토글 후 Firestore 업데이트 실패  
**기대**: 로컬 상태 롤백 (`!value`), "설정 저장에 실패했습니다" 에러 토스트  
**결과**: ✅

### H-082 시스템 알림 설정 버튼
**입력**: "시스템 알림 설정" 탭  
**기대**: `openAppSettings()` 호출, 기기 시스템 설정으로 이동  
**결과**: ✅

### H-083 앱 버전 표시
**입력**: 설정 화면 앱 정보 섹션  
**기대**: `PackageInfo.fromPlatform()` 결과 버전 표시, 로드 전 "..." 표시  
**결과**: ✅

### H-084 프로필 수정 이동
**입력**: "프로필 수정" 탭  
**기대**: `ProfileEditScreen`으로 이동  
**결과**: ✅

### H-085 내 서류 관리 이동 (USER)
**입력**: USER > "내 서류 관리" 탭  
**기대**: `DocumentManagementScreen`으로 이동  
**결과**: ✅

### H-086 내 평가 확인 이동 (USER)
**입력**: USER > "내 평가 확인" 탭  
**기대**: `MyReviewsScreen`으로 이동  
**결과**: ✅

### H-087 사업장 정보 이동 (BUSINESS_ADMIN)
**입력**: BUSINESS_ADMIN > "사업장 정보" 탭  
**기대**: `BusinessListScreen`으로 이동  
**결과**: ✅

### H-088 업무 유형 관리 이동
**입력**: "업무 유형 관리" 탭  
**기대**: `WorkTypeManagementScreen`으로 이동  
**결과**: ✅

### H-089 근로계약서 관리 이동 — businessId 있음
**입력**: BUSINESS_ADMIN (businessId 존재) > "근로계약서 관리" 탭  
**기대**: `ContractTemplateListScreen(businessId: businessId)` 이동  
**결과**: ✅

### H-090 근로계약서 관리 이동 — businessId 없음
**입력**: BUSINESS_ADMIN (businessId null, _resolvedBusinessId null) > "근로계약서 관리" 탭  
**기대**: "사업장 정보를 먼저 등록해주세요" 경고 토스트  
**결과**: ✅

### H-091 멤버 관리 이동 — 사업장 있음
**입력**: BUSINESS_ADMIN (non-SubAdmin) > "멤버 관리" 탭  
**기대**: `getMyBusiness(uid)` 조회 → `MemberManagementScreen(businessId, businessName)` 이동  
**결과**: ✅

### H-092 멤버 관리 이동 — 사업장 없음
**입력**: BUSINESS_ADMIN (사업장 미등록) > "멤버 관리" 탭  
**기대**: "사업장을 먼저 등록해주세요" 경고 토스트  
**결과**: ✅

### H-093 멤버 관리 — SubAdmin에게 숨김
**입력**: SubAdmin (USER + subAdminOf)으로 설정 확인  
**기대**: "멤버 관리" 메뉴 미표시 (`!(user?.isSubAdmin ?? false)` 조건)  
**비고**: SubAdmin은 `UserRole.USER`이므로 BUSINESS_ADMIN 섹션 자체가 미표시  
**결과**: ✅

### H-094 리뷰 관리 이동 — businessId 있음
**입력**: BUSINESS_ADMIN > "리뷰 관리" 탭  
**기대**: `AdminReviewListScreen(businessId: businessId)` 이동  
**결과**: ✅

### H-095 사업장 인감 — 로드 및 표시
**입력**: BUSINESS_ADMIN으로 설정 화면 초기화  
**기대**: `businesses` 컬렉션에서 `sealBase64` 로드, 인감 카드 표시  
**결과**: ✅

### H-096 사업장 인감 — adminIds 미등록 시 조회 폴백
**입력**: `user.businessId == null`인 BUSINESS_ADMIN  
**기대**: `adminIds.arrayContains(uid)` 쿼리로 businessId 탐색 후 인감 로드  
**결과**: ✅

### H-097 도움말 이동
**입력**: "도움말 (Q&A)" 탭  
**기대**: `HelpScreen`으로 이동  
**결과**: ✅

### H-098 가이드 다시 보기
**입력**: "가이드 다시 보기" 탭  
**기대**: `TourHelper.resetAll()` → `pushTourScreen(context, role: role)` 실행  
**결과**: ✅

### H-099 로그아웃
**입력**: 로그아웃 버튼 탭 → 확인  
**기대**: `AuthService().signOut()` 호출, 로그인 화면으로 이동  
**결과**: ✅

### H-100 회원탈퇴
**입력**: 회원탈퇴 버튼 탭 → 확인  
**기대**: 탈퇴 처리 (이전 분석: BUG-ADMIN-72 수정 완료), CONFIRMED 지원서 orphan 방지  
**결과**: ✅

---

## 버그 수정 요약

| ID | 위치 | 심각도 | 내용 | 상태 |
|---|---|---|---|---|
| BUG-H-01 | `notification_screen.dart:122` | LOW | RefreshIndicator.onRefresh가 에러 상태에서 `provider.retry()` 미호출 | ✅ 수정 |
| BUG-H-02 | `notification_firestore.dart:133` | LOW | `deleteOldNotifications()` limit 없이 전체 조회 → `.limit(500)` 추가 | ✅ 수정 |

## ⚠️ 경고 (수정 불필요)

| ID | 위치 | 내용 |
|---|---|---|
| ⚠️ H-03 | `notification_firestore.dart:164` | `watchUserNotifications` limit(30) 고정 — 미읽음 카운트 과소 표시 가능, Provider 구조 전면 수정 없이 개선 불가 |
| ⚠️ H-04 | `notification_firestore.dart:101` | `markAllNotificationsAsRead()` limit 없이 전체 조회 — 기능상 의도적 (모두 처리 필요), 비정상 대용량 시 느릴 수 있음 |
