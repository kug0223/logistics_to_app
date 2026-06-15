# Category L — 워커(지원자) 화면 테스트 시나리오

> 대상 파일:
> - `lib/screens/user/user_home_screen.dart`
> - `lib/screens/user/my_schedule_screen.dart`
> - `lib/screens/user/attendance_check_screen.dart`
> - `lib/screens/user/all_to_list_screen.dart`
> - `lib/screens/user/my_applications_screen.dart`
> - `lib/screens/user/user_contracts_screen.dart`
>
> 버그 수정: 없음 (전 화면 현재 상태에서 심각한 로직 버그 없음)
> 경고: ⚠️ L-01 (계약서 전체 조회), ⚠️ L-02 (즐겨찾기 batch limit 미분할)

---

## 수정된 버그

없음 — 워커 화면 전체 코드 검토 결과 심각한 버그 없음.

---

## 경고 (버그 수준 아님)

### ⚠️ L-01 — `MyApplicationsScreen._loadContracts()` 전체 조회
- `getByWorker(uid)` 호출로 해당 워커의 계약서 전체 조회 후 로컬 매핑
- 계약서 수십 건 이하에서는 문제없으나, 수백 건 이상이면 불필요한 데이터 전송 발생
- 현재 규모(지원자 1인당 계약서 수십 건 이하)에서는 수용 가능
- 향후 applicationId 기준 개별 조회 또는 페이지네이션 고려

### ⚠️ L-02 — `AllTOListScreen` 즐겨찾기 batch fetch 청크 미분할
- 즐겨찾기 toId 목록 전체를 `Future.wait`로 병렬 개별 조회
- Firestore whereIn 30개 제한은 없으나 수십 개 병렬 요청 발생 가능
- 즐겨찾기가 수십 개 이하인 현재 규모에서는 수용 가능

---

## 테스트 시나리오 (L-001 ~ L-100)

---

### [UserHomeScreen — 워커 홈]

**L-001** USER 역할 로그인 → UserHomeScreen 표시 (GradientScaffold)

**L-002** 온보딩 배너 — 이메일 미인증 → '이메일 인증 필요' 배너 표시

**L-003** 온보딩 배너 — 신분증 미등록 → '신분증 등록 필요' 배너 표시

**L-004** 온보딩 배너 — 통장사본 미등록 → '통장사본 등록 필요' 배너 표시

**L-005** 온보딩 배너 — 통장정보 미등록 → '계좌 정보 등록 필요' 배너 표시

**L-006** 온보딩 배너 — 모든 인증 완료 → 온보딩 배너 미표시

**L-007** TrustBadge — trustGradeEmoji + trustScore 정상 표시

**L-008** trustScore null → 기본값 100점 표시

**L-009** SubAdmin 배너 — USER + 관리자 권한 보유 시 '관리자 모드 전환' 버튼 표시

**L-010** SubAdmin 배너 — 관리자 권한 없음 → SubAdmin 배너 미표시

**L-011** 관리자 모드 전환 버튼 탭 → BusinessAdminHomeScreen으로 이동

**L-012** TourHelper — 첫 방문 시 투어 오버레이 표시

**L-013** TourHelper — 투어 완료 후 재진입 시 투어 미표시 (SharedPreferences 저장)

**L-014** RefreshIndicator pull → 사용자 데이터 갱신

**L-015** 오프라인 상태 → 캐시된 사용자 데이터 표시, 에러 처리

---

### [MyScheduleScreen — 내 일정]

**L-016** 화면 진입 → 현재 월 캘린더 + 월 통계 표시

**L-017** `_dateIndex` — 날짜 탭 시 O(1) 조회로 해당 날 지원서 목록 반환

**L-018** 캘린더 페이지 이동(이전/다음 월) → `_loadMonthlyAttendances(focusedDay)` 재호출

**L-019** 이전 월 이동 → 해당 월 근태 데이터 Firestore에서 조회

**L-020** `_attendanceMap` key — `'${applicationId}_${year}-${month}-${day}'` 형식으로 조회

**L-021** `_recomputeStats()` — confirmedCount, pendingCount, totalIncome, actualDays, confirmedIncome 계산

**L-022** 통계 — confirmedCount: CONFIRMED 상태 지원서 수

**L-023** 통계 — pendingCount: PENDING 상태 지원서 수

**L-024** 통계 — totalIncome: 모든 확정 지원서 예상 임금 합산

**L-025** 통계 — actualDays: 실제 근무 완료된 일수 (근태 기록 존재)

**L-026** 통계 — confirmedIncome: 근태 완료된 실제 지급 임금 합산

**L-027** 날짜 탭 → 하단 시트 or 목록에 해당 날 지원서 표시

**L-028** 근태 있는 날 → 캘린더 날짜 마커 표시

**L-029** 임금명세서 생성 버튼 → `PayslipPdfBuilder.buildAggregated()` 호출 후 `Printing.sharePdf()`

**L-030** 해당 월 확정 지원서 없음 → 임금명세서 생성 버튼 비활성화 또는 안내 메시지

**L-031** 지원서 없는 날 탭 → '지원 내역이 없습니다' 빈 상태 표시

**L-032** 로딩 중 → LoadingWidget 표시

**L-033** RefreshIndicator pull → `_dateIndex` + `_attendanceMap` 재빌드

**L-034** 오프라인 → Firestore 근태 조회 실패 시 에러 토스트, 기존 데이터 유지

**L-035** 장기 근무 지원서 → 캘린더 날짜 범위에 마커 표시 (startDate ~ endDate)

---

### [AttendanceCheckScreen — 근태 체크]

**L-036** 화면 진입 → 기기 시간 변조 감지 `DeviceIntegrityService().isDeviceTimeValid()` 호출

**L-037** 기기 시각이 서버 시각과 5분 이상 차이 → '기기 시간이 올바르지 않습니다' 에러, 출근 불가

**L-038** 기기 시각 정상 → 출근 UI 표시

**L-039** 위치 방식 'gps' → GPS 좌표 획득 후 사업장 반경 내 확인

**L-040** 위치 방식 'beacon' → 비콘 스캔 후 등록된 비콘과 매칭

**L-041** 위치 방식 'both' → GPS + 비콘 중 하나라도 인식 시 출근 허용

**L-042** 위치 방식 'manual' → 위치 확인 없이 즉시 출근 처리

**L-043** 반경 내 위치 확인 → 출근 버튼 활성화

**L-044** 반경 외 → '근무지 밖에 있습니다' 안내, 출근 버튼 비활성화

**L-045** 위치 추적 타이머 — `Timer.periodic(Duration(minutes: 2))` 2분마다 위치 갱신

**L-046** 앱 백그라운드 진입 → `WidgetsBindingObserver` 감지, 위치 추적 일시 중지

**L-047** 앱 포그라운드 복귀 → 위치 추적 재개

**L-048** 근무지 이탈 감지 — `radius+50m` 버퍼 초과 시 이탈로 판단

**L-049** 근무지 이탈 쿨다운 — 이탈 감지 후 15분 내 중복 알림 차단

**L-050** 야간 근무 처리 — 어제 시작 근무, 오늘 퇴근 완료 기록 있음 → 오늘 화면에서 미표시 [C-001]

**L-051** 야간 근무 처리 — 어제 시작 근무, 오늘 퇴근 미완료 → 오늘 화면에서 계속 표시

**L-052** 장기 근무 workDate — `DateTime.now()` 기준으로 기록 (work.workDate는 계약 시작일 고정값)

**L-053** 출근 처리 성공 → 근태 기록 Firestore 저장 + '출근 완료' 토스트

**L-054** 퇴근 처리 성공 → 근태 기록 업데이트 + '퇴근 완료' 토스트

**L-055** 이미 출근 처리됨 → 퇴근 버튼만 표시 (출근 버튼 비표시)

**L-056** GPS 권한 거부 → '위치 권한이 필요합니다' 안내

**L-057** GPS 비활성화(기기 위치 꺼짐) → 위치 서비스 활성화 요청 다이얼로그

**L-058** 비콘 블루투스 꺼짐 → 블루투스 활성화 요청 안내

**L-059** 화면 dispose → Timer 취소 + WidgetsBindingObserver 해제 (메모리 누수 없음)

**L-060** 출근 처리 실패 (Firestore 오류) → '출근 처리에 실패했습니다' 에러 토스트, 상태 복원

---

### [AllTOListScreen — 전체 TO 목록]

**L-061** 화면 진입 → Firestore 커서 페이지네이션 첫 페이지 로드

**L-062** 스크롤 300px 전 → `_loadMoreTOs()` 트리거 (커서 페이지네이션)

**L-063** `_hasMoreData=false` → 스크롤 도달 시 추가 로드 없음

**L-064** 키워드 입력 (500ms 디바운스) → Algolia 검색 경로로 전환

**L-065** Algolia 미설정 시 키워드 검색 → 빈 결과 + 경고 토스트

**L-066** Algolia 검색 결과 → objectID 목록 기반 Firestore 배치 조회

**L-067** 즐겨찾기 탭 → 즐겨찾기 toId 목록 개별 병렬 조회 (`Future.wait`)

**L-068** 즐겨찾기 없음 → '즐겨찾기한 공고가 없습니다' 빈 상태

**L-069** `_workDetailsCache` — 동일 toId 반복 조회 시 캐시에서 반환 (서버 중복 호출 없음)

**L-070** `_slotsCache` — 동일 toId 슬롯 조회 시 캐시에서 반환

**L-071** `_applyExpiredFilter()` — 만료 필터 + 날짜 범위 필터 단일 O(n) 순회 적용

**L-072** 만료 필터 ON → 만료된 TO 미표시

**L-073** 날짜 범위 필터 → 근무 날짜 범위 내 TO만 표시

**L-074** 도시/지역/유형 필터 → Algolia facet 필터로 반영

**L-075** 검색어 초기화 → Firestore 커서 경로로 복귀

**L-076** 로딩 중 → LoadingWidget 표시

**L-077** 추가 로딩 중 → 리스트 하단 LoadingWidget 표시

**L-078** TO 카드 탭 → JobPostingScreen 이동

**L-079** RefreshIndicator pull → 캐시 초기화 + 첫 페이지 재로드

**L-080** 오프라인 → Firestore 조회 실패 시 에러 토스트, 빈 상태 표시

---

### [MyApplicationsScreen — 내 지원 내역]

**L-081** 화면 진입 → `autoExpirePendingApplications(uid)` 만료 처리 후 페이지 로드

**L-082** 커서 페이지네이션 — pageSize=20, 스크롤 200px 전 `_loadMore()` 트리거

**L-083** `_attachTOInfo()` — TO 삭제된 지원서 → '삭제된 공고' 간소화 카드 표시

**L-084** `_attachTOInfo()` — TO 존재 → 정상 카드 표시

**L-085** 필터 '전체' → 모든 상태 표시

**L-086** 필터 '대기중' → AppStatus.pending만 표시

**L-087** 필터 '확정' → AppStatus.confirmedStatuses 포함 상태 표시

**L-088** 필터 '거절' → AppStatus.rejected만 표시

**L-089** 필터 '취소' → AppStatus.inactiveStates(rejected 제외) 표시

**L-090** 필터 선택 후 빈 결과 + `_hasMore=true` → 자동 `_loadMore()` 추가 호출

**L-091** PENDING 상태 카드 → '지원 취소' 버튼 표시 + 탭 시 확인 다이얼로그

**L-092** 취소 성공 → '지원이 취소되었습니다.' 토스트 + `_loadApplications()` 재호출

**L-093** 자동 취소(autoCanceled) + conflictingBusiness 있음 → 충돌 정보 박스 표시

**L-094** 확정 지원서 + 계약서 pendingWorker → '근로계약서 서명하기' 버튼 표시

**L-095** 확정 지원서 + 계약서 completed → '근로계약서 서명 완료' + '전체 보기' 링크

**L-096** 확정 지원서 + 계약서 pendingEmployer → '사업주 서명 대기 중' 박스 표시

**L-097** 확정 지원서 + 계약서 voided → '계약서가 무효 처리되었습니다' 박스 표시

**L-098** '근로계약서 서명하기' 탭 → ContractSignScreen → 서명 완료 후 `_loadApplications()` 갱신

**L-099** `_loadContracts()` — pending/rejected/canceled만인 페이지 → Firestore 계약서 조회 생략 (최적화)

**L-100** RefreshIndicator pull → `_loadApplications()` 재호출 (만료 처리 포함)

---

### [UserContractsScreen — 내 계약서]

**L-101** 화면 진입 → '전체' 탭 기준 계약서 로드 (커서 페이지네이션)

**L-102** TabController 5탭 — 전체/서명 필요/사업주 대기/완료/무효

**L-103** 탭 전환 → `_refresh()` 호출 (`indexIsChanging` 가드로 중복 방지)

**L-104** 커서 페이지네이션 — 스크롤 200px 전 `_loadMore()` 트리거

**L-105** `_hasMore=false` → 스크롤 도달 시 추가 로드 없음

**L-106** 계약서 없음 → AppEmptyState 표시 (탭별 서브타이틀 다름)

**L-107** pendingWorker 탭 빈 상태 → '서명이 필요한 계약서가 없습니다'

**L-108** completed 탭 빈 상태 → '완료된 계약서가 없습니다'

**L-109** 기타 탭 빈 상태 → '확정된 공고에서 계약서를 받으세요.'

**L-110** pendingWorker 계약서 카드 → info 색상 테두리(1.5) + '서명이 필요합니다' 배너

**L-111** completed 계약서 카드 → '${date} 서명 완료' 표시 (workerSignedAt 기준)

**L-112** voided 계약서 카드 → 회색 '무효' 배지

**L-113** 계약서 카드 탭 → ContractSignScreen (role: 'worker') 이동 + 복귀 시 `_refresh()`

**L-114** 장기 근무 계약 → `isLongTerm=true` 시 createdAt 날짜 표시

**L-115** 단기 계약 슬롯 있음 → slots.first.workDate ~ slots.last.workDate 범위 표시

**L-116** 급여 표시 — '${wage}원 / ${wageType}' (hourly→시급, daily→일급, monthly→월급)

**L-117** RefreshIndicator pull → `_refresh()` 호출

**L-118** 오프라인 → 계약서 로드 실패 시 빈 상태 + 에러 로그 출력 (토스트 없음)

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ L-01 | MyApplicationsScreen._loadContracts() 전체 조회 | 수용 (현재 규모 적합) |
| ⚠️ L-02 | AllTOListScreen 즐겨찾기 병렬 조회 청크 미분할 | 수용 (즐겨찾기 수십 개 이하) |
