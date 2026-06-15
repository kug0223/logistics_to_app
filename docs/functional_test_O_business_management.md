# Category O — 사업장 관리 기능 검증 (100개 시나리오)

> 대상 파일:
> - `lib/screens/business_admin/business_admin_home_screen.dart`
> - `lib/screens/business_admin/business_list_screen.dart`
> - `lib/screens/business_admin/business_detail_screen.dart`
> - `lib/screens/business_admin/Business_form_screen.dart`
>
> 버그 수정: **BUG-O-01** (네비게이션 중복 탭)
> 경고: ⚠️ O-01 (사업장 삭제 원자성), ⚠️ O-02 (이미지 업로드 실패 후 진행)

---

## 수정된 버그

### BUG-O-01 — `business_admin_home_screen.dart` 메뉴 카드 중복 탭 방지 **[수정 완료]**
- **위치**: `_BusinessAdminHomeScreenState`
- **원인**: 메뉴 카드 onTap에 중복 실행 방지 없어 연속 탭 시 동일 화면 2회 push 가능
- **수정**: `_isNavigating` 플래그 + `_safeNavigate()` 헬퍼 추가, `_requireApprovedBusiness()` → `Future<void>` 전환

---

## 경고

### ⚠️ O-01 — `business_list_screen.dart` 사업장 삭제 원자성 미보장
- 이미지 삭제 → workType 서브컬렉션 삭제 → 메인 문서 삭제 순서로 진행
- 중간 단계 실패 시 부분 삭제 가능 (고아 이미지 생성)
- Cloud Function 후처리로 보완되어 수용

### ⚠️ O-02 — `Business_form_screen.dart` 이미지 업로드 실패 시 진행
- 대표 이미지 업로드 실패 시 경고 토스트 후 이미지 없이 사업장 등록 계속 진행
- 의도된 설계 (등록 자체를 막지 않음) — 수용

---

## 테스트 시나리오

### [BusinessAdminHomeScreen — 관리자 홈]

**O-001** 승인된 사업장 있는 관리자 로그인 → 홈 화면 정상 표시, 모든 메뉴 카드 활성화

**O-002** 승인 대기 중인 사업장만 보유한 관리자 → 메뉴 탭 시 "승인된 사업장이 있어야 이용할 수 있습니다" 토스트

**O-003** `_loadApprovedBusinessStatus()` 조회 중 (null 상태) → 메뉴 탭 시 "사업장 정보를 불러오는 중" 토스트

**O-004** 조회 에러 발생 → `_hasApprovedBusiness = false` 설정, 모든 메뉴 차단

**O-005** SubAdmin 로그인 → 부여된 권한(canManageTo 등)에 따라 메뉴 일부만 표시

**O-006** SubAdmin canManageTo=false → '공고 관리' 카드 미표시

**O-007** SubAdmin canManageWage=false → '급여 관리' 카드 미표시

**O-008** SubAdmin canManageContract=false → '계약서 관리' 카드 미표시

**O-009** '공고 등록' 카드 연속 빠른 탭 → 화면 1회만 push (BUG-O-01 수정 확인)

**O-010** '공고 관리' 카드 탭 → IntegratedWorkforceScreen 이동

**O-011** '급여 관리' 카드 — 오늘 지급 건수 0 → 일반 카드 렌더링

**O-012** '급여 관리' 카드 — 오늘 지급 건수 > 0 → 카드 우상단 빨간 배지 (숫자) 표시

**O-013** '급여 관리' 카드 — 오늘 지급 건수 99 초과 → "99+" 배지 표시

**O-014** '계약서 관리' 카드 — effectiveBusinessId 있음 → AdminContractManagementScreen(businessId) 이동

**O-015** '계약서 관리' 카드 — effectiveBusinessId null → getMyBusiness() 재조회 → 첫 사업장 ID로 이동

**O-016** '통계' 카드 탭 → AdminStatsScreen 이동

**O-017** '설정' 카드 탭 → SettingsScreen 이동

**O-018** 알림 벨 탭 → NotificationScreen 이동

**O-019** 로그아웃 버튼 → 확인 다이얼로그 표시, 취소 시 홈 유지

**O-020** 로그아웃 확인 → ThemeProvider.reset() + signOut() 호출

**O-021** SubAdmin 모드 전환 버튼 탭 → userProvider.toggleAdminMode() 호출

**O-022** '공고 등록' — 일반 관리자 + 이메일 미인증 → checkTOPrerequisites 차단 다이얼로그

**O-023** '공고 등록' — 일반 관리자 + 사업자등록증 미등록 → 체크 차단 다이얼로그

**O-024** '공고 등록' — SubAdmin → 전제조건 체크 없이 바로 AdminCreateTOScreen 이동

**O-025** 첫 진입 시 투어 가이드 미완료 → pushTourScreen() 실행 후 TourHelper.markCompleted()

**O-026** 재진입 시 투어 완료 상태 → 투어 가이드 미표시

**O-027** 가로 모드 → 인사말 섹션 숨김, vertical padding 축소, 메뉴 그리드 유지

**O-028** 역할 배지 → isSubAdmin=true: '하위 관리자', false: '관리자' 표시

**O-029** Debug 모드 — 더미 데이터 생성 버튼 표시, Release에서 미표시

---

### [BusinessListScreen — 사업장 목록]

**O-030** 관리자 로그인 → getMyBusiness(uid)로 본인 사업장 목록 로드

**O-031** SubAdmin → effectiveBusinessId 기반 단일 사업장만 표시

**O-032** 사업장 목록 로드 실패 → 에러 토스트 + _isLoading=false

**O-033** 사업장 없음 → 마지막 리스트 아이템으로 '+ 새 사업장 추가' 카드 표시

**O-034** '+ 새 사업장 추가' 탭 — 사업자등록증 미등록 → 등록 안내 다이얼로그 → DocumentManagementScreen

**O-035** '+ 새 사업장 추가' 탭 — 사업자등록증 등록 완료 → BusinessFormScreen(isNew) 이동

**O-036** BusinessFormScreen 복귀 시 result=true → _loadBusinesses() 재호출

**O-037** 사업장 카드 탭 → BusinessDetailScreen 이동

**O-038** BusinessDetailScreen 복귀 시 _hasChanges=true → _loadBusinesses() 재호출

**O-039** 더보기 메뉴 — '수정' → BusinessFormScreen(business) 이동

**O-040** 더보기 메뉴 — 'TO 등록' — 승인됨 + 이메일 인증 + 사업자등록증 → AdminCreateTOScreen 이동

**O-041** 더보기 메뉴 — 'TO 등록' — 승인 대기 사업장 → checkTOPrerequisites 차단

**O-042** 더보기 메뉴 — '삭제' — 확인 다이얼로그 → 취소 시 목록 유지

**O-043** 더보기 메뉴 — '삭제' — 확인 → 이미지 삭제 → workType 삭제 → 사업장 삭제 순 진행

**O-044** 이미지 개별 삭제 실패 시 → 로그만 출력 후 나머지 삭제 계속 진행 (⚠️ O-01)

**O-045** SubAdmin → 더보기 메뉴에 '삭제' 옵션 없음

**O-046** 승인됨 사업장 → 초록 배지 '승인됨', 대기 중 → 주황 배지 '대기중'

**O-047** 사업장 카드 썸네일 없음 → 기본 아이콘 플레이스홀더 표시

**O-048** RefreshIndicator pull → _loadBusinesses() 재호출

---

### [BusinessDetailScreen — 사업장 상세]

**O-049** 상세 화면 진입 → widget.business로 즉시 UI 렌더링 (Firestore 재조회 없음)

**O-050** 이미지 없음 → 회색 플레이스홀더 + 아이콘 표시

**O-051** 이미지 1개 → 슬라이더 인디케이터 없음, 단일 이미지 표시

**O-052** 이미지 복수 → PageView 스와이프 가능 + 하단 인디케이터 업데이트

**O-053** 주차 정보 표시 — hasParking=true: '가능', false: '불가' + 회색 아이콘

**O-054** 식사 정보 — ['조식','중식'] → '조식, 중식' 콤마 구분 표시

**O-055** 주소 복사 버튼 탭 → Clipboard.setData() + 토스트 표시

**O-056** 지도 탭 — 위도/경도 있음 → KakaoMapWidget 마커 표시

**O-057** 지도 탭 — 위도/경도 null → 지도 섹션 미표시

**O-058** 전화 아이콘 탭 → url_launcher로 전화 다이얼 실행

**O-059** 수정 버튼 탭 → BusinessFormScreen(business) 이동

**O-060** BusinessFormScreen 복귀 result=true → _reloadBusiness() (Source.server 강제 조회)

**O-061** 평점 있음 → 별점 시각화 표시, 평점 없음 → 별점 섹션 미표시

**O-062** 지하철 정보 — walkingMinutes 있음: "역삼역 도보 5분", 없음: 역명만 표시

---

### [BusinessFormScreen — 사업장 등록/수정]

**O-063** 신규 등록 모드 → Step 1: 업종 선택 필수, 미선택 시 다음 버튼 비활성화

**O-064** 수정 모드 → 기존 데이터 자동 로드 (업종, 사업장명 등)

**O-065** Step 1 — 업종 ExpansionTile 펼침 → RadioListTile 선택 → 선택 상태 시각 반영

**O-066** Step 2 — 사업장명 빈 값 → FormValidator 오류 메시지 표시

**O-067** Step 2 — 사업자번호 자동 포맷팅 → '1234567890' 입력 → '123-45-67890'

**O-068** Step 2 — 주소 검색 성공 → latitude/longitude/city/district 자동 설정

**O-069** Step 2 — 주소 검색 실패 → 수동 주소 입력 다이얼로그 표시

**O-070** Step 2 — 수동 주소 입력 — 주소+위도+경도 → 저장 후 반영 확인

**O-071** Step 2 — 급여 지급일 선택 → 매월 N일 표시

**O-072** Step 3 — 추가 이미지 최대 5장 초과 시도 → 추가 버튼 비활성화

**O-073** Step 3 — 기존 URL 이미지 삭제 → 삭제 목록에 추가, 저장 시 Storage 삭제

**O-074** Step 3 — GPS 출퇴근 선택 → 반경 Slider(30-500m) 표시

**O-075** Step 3 — 비콘 출퇴근 선택 → UUID 필수 입력 검증 활성화

**O-076** Step 3 — GPS 좌표 미설정 + GPS 출퇴근 → 저장 전 경고 다이얼로그, 그래도 진행 가능

**O-077** 저장 — 이미지 업로드 실패 → 경고 토스트 후 이미지 없이 사업장 등록 (⚠️ O-02)

**O-078** 저장 — 신규 등록 — WriteBatch: businesses 문서 + users.managedBusinessIds 동시 기록

**O-079** 저장 — isFromSignUp=true → 저장 후 LoginScreen으로 pushAndRemoveUntil

**O-080** 저장 — isFromSignUp=false → 저장 후 뒤로가기 (changed=true)

**O-081** PopScope — isFromSignUp=true + 작성 중 뒤로가기 → 취소 확인 다이얼로그

**O-082** 사업자등록증 미등록 상태에서 저장 시도 → DocumentManagementScreen 이동 후 복귀

**O-083** 수정 모드 — 사용자 사전 입력 정보(businessNumber, businessName, ceoName) 자동 완성

---

### [통합 시나리오]

**O-084** 관리자 로그인 → 홈 → 사업장 목록 → 신규 사업장 등록 → 홈 복귀 확인

**O-085** 사업장 등록 → 승인 대기 → 승인 후 홈 메뉴 활성화 확인

**O-086** 사업장 수정 → BusinessDetailScreen 재조회 후 수정값 반영 확인

**O-087** 사업장 삭제 → 목록에서 즉시 제거 확인

**O-088** SubAdmin → 본인 사업장 외 접근 불가 확인

**O-089** 네트워크 오프라인 → 홈 화면 조회 실패 → _hasApprovedBusiness=false → 메뉴 차단

**O-090** 홈 화면 → 공고 등록 → 공고 등록 완료 → '공고가 등록되었습니다' 토스트

**O-091** 홈 화면 → 계약서 관리 → AdminContractManagementScreen → 복귀 시 _isNavigating 해제

**O-092** 홈 화면 → 급여 관리 → PayrollOverviewScreen → 복귀 시 오늘 지급 배지 reload

**O-093** Business_form_screen — Step 이동 중 취소 → 이전 단계 데이터 유지 확인

**O-094** 이미지 5장 + 기존 URL 1장 = 6장 → 마지막 추가 버튼 비활성화 확인

**O-095** 업종 선택 후 Step 2 이동 → 업종 다시 바꾸기 위해 Step 1 복귀 불가 확인

**O-096** 사업장 삭제 중 뒤로가기 → mounted 체크로 setState 오류 방지 확인

**O-097** 관리자 로그아웃 후 재로그인 → _hasApprovedBusiness 초기화 재조회 확인

**O-098** 가로 모드 → 사업장 목록 그리드 레이아웃 유지 확인

**O-099** 사업장 상세 → 지도 전체화면 → FullMapDialog → 닫기 복귀

**O-100** 사업장 삭제 후 TO 등록 시도 → 승인 사업장 없음 → 차단 토스트 확인

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | BUG-O-01: 메뉴 카드 중복 탭 (_safeNavigate) | 수정 완료 |
| ⚠️ O-01 | 사업장 삭제 원자성 미보장 (고아 이미지) | 수용 |
| ⚠️ O-02 | 이미지 업로드 실패 후 등록 계속 진행 | 수용 |
