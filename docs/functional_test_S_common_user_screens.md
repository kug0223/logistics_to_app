# Category S — 공통·유저·기타 화면 검증 (100개 시나리오)

> 대상 파일:
> - `lib/screens/common/job_posting_screen.dart`
> - `lib/screens/common/profile_edit_screen.dart`
> - `lib/screens/common/help_screen.dart`
> - `lib/screens/common/tour_screen.dart`
> - `lib/screens/common/onboarding_screen.dart`
> - `lib/screens/user/my_reviews_screen.dart`
> - `lib/screens/user/dialogs/apply_dialog.dart`
> - `lib/screens/user/dialogs/my_requests_dialog.dart`
> - `lib/screens/user/dialogs/work_detail_dialog.dart`
> - `lib/screens/super_admin/legal_terms_management_screen.dart`
> - `lib/screens/business_admin/workforce_management/workforce_calendar_view.dart`
>
> 버그 수정: 없음
> 경고: ⚠️ S-01 (apply_dialog 중복 지원 체크 쿼리 경합), ⚠️ S-02 (my_requests_dialog 3-쿼리 통합 정렬 시점)

---

## 수정된 버그

없음 — 분석 결과 mounted 체크, async 안전 처리, 에러 폴백 모두 정상 확인됨.

---

## 경고

### ⚠️ S-01 — `apply_dialog.dart` 중복 지원 체크와 생성 사이 경합
- 중복 체크 쿼리 후 applyToTOWithWorkType 호출 사이 짧은 gap 존재
- 극히 드문 동시 탭 상황에서 이중 지원 가능성 있음 (서버 규칙으로 최종 방어)
- 수용

### ⚠️ S-02 — `my_requests_dialog.dart` 3개 쿼리 통합 정렬
- Future.wait로 3개 쿼리 동시 실행 후 requestedAt 기준 재정렬
- 각 쿼리 반환 시점이 다를 경우 순서가 일시적으로 뒤섞일 수 있음 (통합 후 정렬되므로 수용)

---

## 테스트 시나리오

### [JobPostingScreen — 공고 상세]

**S-001** toId로 진입 → Firestore에서 TO 로드 + workDetails + business 병렬 조회

**S-002** TO 직접 전달(adminPreview) → 추가 Firestore 조회 없이 전달된 데이터 즉시 표시

**S-003** adminPreview 모드 → 지원하기 버튼 비표시, '미리보기' 배지 표시

**S-004** 사용자 모드 — 이메일 미인증 → 지원 불가 사유 표시

**S-005** 사용자 모드 — 신분증 미제출 → 지원 불가 사유 표시

**S-006** 사용자 모드 — 통장정보 미등록 → 지원 불가 사유 표시

**S-007** 사용자 모드 — 제한(RESTRICTED) 상태 → 지원 불가 사유 표시

**S-008** 모든 자격 충족 → '지원하기' 버튼 활성화

**S-009** 마감일 경과 공고 → 지원 불가 + "마감된 공고" 메시지

**S-010** applicationDeadline 30분 이내 → 지원 불가 + 마감임박 안내

**S-011** isClosed=true TO → 지원 불가 표시

**S-012** 단기 공고 — slotDate 있음 → 해당 날짜 슬롯만 필터링

**S-013** flex TO — 전체 슬롯 표시 + 슬롯별 확정/대기 인원

**S-014** 슬롯 visibleFrom 미경과 → 해당 슬롯 비표시

**S-015** 이미 지원한 TO → 재지원 불가 또는 재지원 허용 (AppStatus.inactiveStates 체크)

**S-016** 업무유형 이미지 → 썸네일 표시 + 탭 시 확대 표시

**S-017** Firestore 로드 실패 → _buildErrorState() 표시

---

### [ProfileEditScreen — 프로필 수정]

**S-018** 화면 진입 → 현재 사용자 정보 자동 로드 (이름/이메일/전화번호/주소)

**S-019** 이름 수정 → _hasChanges=true, 저장 버튼 활성화

**S-020** 프로필 사진 탭 → 갤러리/카메라 선택 바텀시트

**S-021** 갤러리 선택 → 이미지 피커 → 미리보기 업데이트

**S-022** 사진 업로드 → Storage 저장 → Firestore URL 갱신 → UserProvider.refreshCurrentUser()

**S-023** 이메일 변경 입력 → '인증코드 전송' 버튼 활성화

**S-024** 인증코드 전송 → _isEmailSending=true → Cloud Function 호출 → 발송 완료 표시

**S-025** 인증코드 입력 → '확인' 버튼 탭 → Cloud Function 검증

**S-026** 올바른 코드 입력 → _isEmailVerified=true, 체크 배지 표시

**S-027** 만료된 코드 → '인증코드가 만료되었습니다' 토스트 + 재발송 유도

**S-028** 횟수 초과 → '인증 시도 횟수 초과' 토스트 + 차단

**S-029** 이메일 변경 저장 → 인증 필수 체크 후 Firestore 업데이트

**S-030** 전화번호 필드 탭 → '고객센터를 통해 변경해주세요' 안내 (수정 차단)

**S-031** 주소 검색 버튼 탭 → Daum 주소검색 웹뷰 오픈

**S-032** 주소 선택 → 주소 필드 자동 채워짐 + 상세주소 입력 활성화

**S-033** 비밀번호 변경 메뉴 탭 → 현재/신규/확인 입력 다이얼로그

**S-034** 신규 비밀번호 강도 표시 → 영문/숫자/특수문자 충족 여부 시각화

**S-035** 비밀번호 불일치 → '비밀번호가 일치하지 않습니다' 에러

**S-036** 저장 실패 (Storage 성공 후 Firestore 실패) → orphan 파일 정리 시도

---

### [HelpScreen — 도움말]

**S-037** 관리자 역할로 진입 → 관리자용 FAQ 목록 표시 (TO/계약서/급여 관련)

**S-038** 일반 사용자 역할 → 사용자용 FAQ 목록 표시 (공고/출퇴근/급여 관련)

**S-039** FAQ 아이템 탭 → 아코디언 확장 (내용 표시)

**S-040** 확장된 아이템 재탭 → 축소

**S-041** 섹션 헤더 색상 → 카테고리별 구분 색상 표시

**S-042** 정적 화면 → 스크롤만 가능, 네트워크 요청 없음

---

### [TourScreen — 인앱 투어]

**S-043** 관리자 역할 투어 → 관리자 기능 중심 페이지 표시

**S-044** 사용자 역할 투어 → 사용자 기능 중심 페이지 표시

**S-045** 다음 버튼 탭 → 다음 페이지 전환 + 스케일 애니메이션

**S-046** 스와이프 제스처 → 페이지 전환

**S-047** 마지막 페이지 → '다음' → '완료'로 버튼 텍스트 변경

**S-048** '완료' 탭 → Navigator.pop() 호출

**S-049** '건너뛰기' 탭 → 즉시 Navigator.pop() 호출

**S-050** 페이지 인디케이터 → 현재 페이지 활성 표시

---

### [OnboardingScreen — 온보딩]

**S-051** 관리자 역할 → 5개 페이지 표시

**S-052** 사용자 역할 → 4개 페이지 표시

**S-053** 다음 버튼 → 다음 페이지 전환 + elasticOut 스케일 애니메이션

**S-054** AnimatedSwitcher → 페이지 전환 시 콘텐츠 부드럽게 전환

**S-055** 마지막 페이지 → '완료' 버튼으로 전환

**S-056** '완료' 탭 → onComplete 콜백 호출 (화면 전환 부모 담당)

**S-057** '건너뛰기' 탭 → 즉시 onComplete 콜백 호출

**S-058** 그래디언트 배경 → 페이지별 색상 변경

---

### [MyReviewsScreen — 내 평가 목록]

**S-059** 화면 진입 → 첫 페이지 리뷰 조회 + 평균 별점 계산 + 요약 헤더 표시

**S-060** 별점 0점 → 요약 헤더 '아직 평가 없음' 상태 또는 0.0 표시

**S-061** 별점 있음 → 숫자 + 별 아이콘 시각화 표시

**S-062** 리뷰 카드 → 사업장명/근무기간/별점/근무일수/지각-조퇴 통계 표시

**S-063** 지각/조퇴 0 → 통계 항목 숨김 또는 0 표시

**S-064** '더 보기' 버튼 탭 → _loadMore() 호출 + 목록 이어붙이기

**S-065** 마지막 페이지 도달 (_hasMore=false) → '더 보기' 버튼 미표시

**S-066** RefreshIndicator pull → _loadReviews() 재실행, cursor 리셋

**S-067** 빈 목록 → AppEmptyState 표시

**S-068** 로드 실패 → 에러 메시지 + '다시 시도' 버튼

**S-069** '다시 시도' 탭 → _loadReviews() 재실행

**S-070** _loadMore 실패 → 에러 토스트 없이 silent (로딩 상태만 해제)

---

### [ApplyDialog — 지원 확인 다이얼로그]

**S-071** 다이얼로그 열기 → 업무 정보 (이름/시간/임금/인원) 표시

**S-072** '취소' 버튼 → 다이얼로그 닫기 (지원 없음)

**S-073** '지원하기' 버튼 → 중복 지원 Firestore 쿼리 실행

**S-074** 유효한 기존 지원 있음 → '이미 지원한 공고입니다' 토스트 + 차단

**S-075** 취소된 지원 있음 (AppStatus.inactiveStates) → 재지원 허용, applyToTOWithWorkType 호출

**S-076** 첫 지원 → applyToTOWithWorkType 호출 + 업무상세 정보 저장 (wageType/아이콘/색상)

**S-077** 장기 공고 → workEndDate + workDays + type 포함 지원서 생성

**S-078** 지원 성공 → '지원이 완료되었습니다' 토스트 + onSuccess() 콜백 호출 + 다이얼로그 닫기

**S-079** 지원 실패 → '지원에 실패했습니다' 에러 토스트 + 다이얼로그 유지

**S-080** uid null → 사전 차단 (uid 체크 후 early return)

---

### [MyRequestsDialog — 내 알림/요청 다이얼로그]

**S-081** 다이얼로그 열기 → 스케줄 변경/신분증 요청/계약해지 3개 쿼리 병렬 로드

**S-082** 통합 목록 → requestedAt 기준 최신순 정렬

**S-083** 스케줄 변경 요청 (PENDING + isAdminRequest) → 수락/거절 버튼 표시

**S-084** 스케줄 변경 수락 → approveScheduleChangeRequest 호출 → 목록 갱신

**S-085** 스케줄 변경 거절 → 사유 입력 다이얼로그 표시 → rejectScheduleChangeRequest 호출

**S-086** 신분증 열람 요청 → 요청자명 + 사유 표시 + 허용/거절 버튼

**S-087** 계약해지 요청 → D-day 3일 자동 승인 안내 배지 표시

**S-088** 계약해지 거절 → 사유 입력 (필수) → 처리 후 목록에서 제거

**S-089** 알림 카운트 배지 → 미처리 건수 표시

**S-090** 빈 목록 → "처리할 요청이 없습니다" 표시

**S-091** 로드 실패 → 에러 처리 + _isLoading=false

**S-092** 처리 완료 후 → _loadAllNotifications() + onChanged() 콜백 호출

---

### [WorkDetailDialog — 업무 상세 다이얼로그]

**S-093** 다이얼로그 열기 → 업무 아이콘 + 업무명 + 근무시간 + 임금 표시

**S-094** 임금 포맷 → FormatHelper.formatWage 호출 (한글 단위 축약)

**S-095** 상세 설명 있음 → 본문에 설명 표시

**S-096** 상세 설명 없음 → 설명 영역 미표시

**S-097** '닫기' 버튼 → 다이얼로그 닫기

---

### [LegalTermsManagementScreen — 약관 관리]

**S-098** 화면 진입 → LegalTermsService.getTerms() 조회 + 목록 표시

**S-099** 약관 항목 카드 → 제목/필수여부/버전/수정일 표시

**S-100** 활성 토글 → toggleActive() 호출 → 아이콘 변경 + _loadTerms() 재실행

---

### [WorkforceCalendarView — 인력 캘린더]

> 참고: 이 화면은 IntegratedWorkforceScreen 내부에 탭으로 포함됨 (Category K의 K 문서와 연계)

**S-101** 캘린더 날짜 탭 → _selectedDay 변경 + 해당 날짜 TO/슬롯 그룹 필터링

**S-102** 단기 TO 날짜 → 해당 날짜 슬롯만 표시

**S-103** 장기 TO — workDays 배열 포함 요일 → 확정 근무자 목록 표시

**S-104** 장기 TO — 비근무 요일 → 목록에서 제외

**S-105** 이벤트 마커 — 단기 일정 있음 → 마커 표시

**S-106** 이벤트 마커 — 장기 근무자 있음 → 마커 표시

**S-107** 이벤트 마커 — 과거 날짜 → 별도 색상 마커

**S-108** '당일명단' 버튼 탭 → ConfirmedListDialog 표시 (해당 날짜)

**S-109** '고정관리' 버튼 탭 → _getAdminBusinesses() → FixedWorkerManagementDialog 표시

**S-110** 사업장 없음 → '등록된 사업장이 없습니다' 경고 토스트

**S-111** '마감관리' 버튼 탭 → CloseManagementDialog(해당 날짜 월) 표시

**S-112** 다이얼로그에서 onChanged 콜백 → _reload() 호출 → 캘린더 + 그룹 갱신

**S-113** 월 스와이프 → _focusedDay 변경 + 이벤트 마커 재계산

**S-114** SubAdmin → effectiveBusinessId 기반 사업장만 조회

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ S-01 | apply_dialog 중복 체크 경합 | 수용 |
| ⚠️ S-02 | my_requests_dialog 3-쿼리 정렬 시점 | 수용 |
