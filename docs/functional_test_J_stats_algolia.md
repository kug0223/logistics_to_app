# Category J — 통계 대시보드 · 공고 탐색(Algolia) 기능 테스트 시나리오

> 대상 파일:
> - `lib/screens/business_admin/admin_stats_screen.dart`
> - `lib/services/admin_stats_service.dart`
> - `lib/services/algolia_service.dart`
> - `lib/screens/business_admin/admin_month_detail_screen.dart` (참조)
>
> 버그 수정: 없음 (기존 코드 양호)
> 경고: ⚠️ J-01 (대용량 근태 메모리 적재), ⚠️ J-02 (Algolia hits 50개 상한)

---

## 수정된 버그

없음 — `admin_stats_service.dart`, `admin_stats_screen.dart`, `algolia_service.dart` 모두 현재 상태에서 심각한 로직 버그 없음.

---

## 경고 (버그 수준 아님)

### ⚠️ J-01 — `_queryAttendance()` limit 없는 전체 집계 쿼리
- `_queryAttendance()`는 연간 통계 목적이므로 limit 적용 시 통계 왜곡 발생
- 현재는 사업장당 연간 근태를 전부 메모리에 적재 → 30초 타임아웃 + 에러 처리는 있음
- 사업장이 성장해 연간 수만 건 이상이 되면 Cloud Function 집계로 이동 필요
- 현재 규모에서는 수용 가능

### ⚠️ J-02 — Algolia `hitsPerPage=50` 상한
- `searchTOIds()`의 기본 hitsPerPage=50 — TO가 50개 초과 검색되면 일부 누락
- 현재 앱 규모(사업장별 TO 수십 개)에서는 수용 가능
- 향후 인덱스 규모 증가 시 hitsPerPage 상향 또는 페이지네이션 고려

---

## 테스트 시나리오 (J-001 ~ J-100)

### [AdminStatsService — 사업장 목록 조회]

**J-001** `getBusinessOptions([])` → 빈 리스트 반환 (Firestore 호출 없음)

**J-002** `getBusinessOptions(['id1', 'id2'])` → 2개 문서 병렬 조회, BusinessOption 리스트 반환

**J-003** 일부 사업장 문서 없음 (doc.exists=false) → 해당 사업장 목록에서 제외

**J-004** 개별 사업장 조회 실패 (오류) → 해당 항목 null, 나머지는 정상 반환

**J-005** 사업장 name 필드 없음 → businessId를 name으로 대신 표시

**J-006** 15초 타임아웃 → 타임아웃 발생 시 해당 사업장 null 처리

---

### [AdminStatsService — 연간 통계 getAnnualStats]

**J-007** 정상 호출 → 선택 연도 + 전년도 근태, 리뷰 병렬 조회 (Future.wait 4개)

**J-008** filterBusinessId=null → businessIds 전체 집계

**J-009** filterBusinessId 지정 → 해당 사업장 데이터만 집계

**J-010** businessIds 빈 리스트 → _emptyAnnual 반환 (Firestore 호출 없음)

**J-011** 30초 타임아웃 → _emptyAnnual 반환, 에러 로그 출력

**J-012** 연간 인건비 계산 — finalWage 합산
- 조건: 3건 근태, finalWage=[100000, 200000, 150000]
- 결과: totalWage=450000

**J-013** 전년 대비 인건비 증감율 — wageDeltaPct
- 조건: prevYearTotalWage=400000, totalWage=500000
- 결과: wageDeltaPct=25.0%

**J-014** prevYearTotalWage=0 → wageDeltaPct=0 (0 나누기 방어)

**J-015** 총 근무건수 = thisYearAtt.length

**J-016** 총 근무인원 = userId 중복 제거 후 집합 크기

**J-017** 출근율 계산 — present/total × 100
- 조건: 정시 출근 8건, 지각 1건, 기타 1건 → 10건 중 8건
- 결과: attendanceRate=80.0%

**J-018** 근태 데이터 없을 때 출근율 → 0 (0 나누기 방어)

**J-019** 재고용률 = wouldRehire==true 수 / wouldRehire 존재하는 리뷰 수 × 100

**J-020** 리뷰 없을 때 재고용률, 평점 → 0

**J-021** 평균 평점 = 리뷰 rating 합 / 리뷰 수

**J-022** 노쇼율 = noShowCount / 전체 건수 × 100

**J-023** 근태 없을 때 노쇼율 → 0 (0 나누기 방어)

**J-024** 업무별 인건비 — workType 기준 groupBy 후 상위 5개
- 조건: workType A=500000, B=300000, C=100000, D=200000, E=400000, F=50000 (6개)
- 결과: wageByWorkType에 A, E, B, D, C 상위 5개만 포함 (F 제외)

**J-025** workType이 빈 문자열인 근태 → 업무별 인건비에서 제외

**J-026** 월별 추이 12개월 고정 생성 (1~12월, 데이터 없는 달은 0)

**J-027** 예외 알림 — `_latestActiveMonth()` — 가장 최근 데이터 있는 달 반환
- 조건: 1~5월 데이터, 6월 이후 0 → exceptionMonth=5

**J-028** 전체 근태 없음 → exceptionMonth=0, exceptions=[]

**J-029** 예외 알림 — 지각 2회 이상이거나 결근 1회 이상인 직원 포함
- 조건: 직원 A 지각 1회 (기준 미달), 직원 B 지각 2회 (포함), 직원 C 결근 1회 (포함)
- 결과: exceptions에 B, C 포함, A 제외

**J-030** 예외 우선순위 — `lateCount + absentCount×2` 내림차순 정렬

**J-031** 예외 직원 이름 조회 — _fetchUserNames로 userId→name 매핑

**J-032** `_fetchUserNames` — 30개 청크 분할 (whereIn 30개 제한 대응)

**J-033** 사용자 이름 없음 → '알 수 없음' 표시

---

### [AdminStatsService — 월 상세 getMonthDetail]

**J-034** 정상 호출 → 해당 월 근태 + 리뷰 병렬 조회

**J-035** businessIds 빈 리스트 → _emptyDetail 반환

**J-036** 직원별 집계 — present, late, absent 카운트 + 임금 합산

**J-037** absent 카운트 — statusPresent, statusLate 외 모두 absent로 계산
- 포함 상태: absent, noShow, earlyLeave, 기타

**J-038** 직원 목록 — totalDays 내림차순 정렬

**J-039** 직원별 근태 기록 — workDate 오름차순 정렬

**J-040** 리뷰 긍정 태그 빈도 집계 — posTagFreq

**J-041** 리뷰 개선 태그 빈도 집계 — impTagFreq

**J-042** 재고용 희망/비희망 카운트

**J-043** `_fetchUserInfo` — name, gender, phone 매핑, 30개 청크 분할

**J-044** MonthDetailData.attendanceRate — (presentCount / total) × 100

**J-045** totalAttendanceCount = presentCount + lateCount + absentCount

---

### [AdminStatsScreen — UI]

**J-046** 화면 진입 → `_init()` 호출: 사업장 목록 + 연간 통계 로드 (현재 연도)

**J-047** 사업장 1개 → 헤더에 사업장 선택 드롭다운 미표시

**J-048** 사업장 2개 이상 → 헤더에 사업장 선택 버튼 표시

**J-049** 데이터 로딩 중 → LoadingWidget 표시 ('통계 불러오는 중...')

**J-050** 연간 통계 없음 (_data=null) → AppEmptyState 표시 ('데이터가 없습니다')

**J-051** 데이터 있음 → KPI 섹션 + 예외 알림 + 업무별 인건비 + 월별 차트 순서

**J-052** 데이터 있지만 totalWorkCount=0 → '데이터가 없습니다' 안내 + KPI 섹션 모두 표시

---

### [AdminStatsScreen — 연도 선택]

**J-053** 현재 연도(2026) 표시 → 오른쪽 화살표 비활성화 (미래 연도 이동 불가)

**J-054** 현재 연도 미만 → 오른쪽 화살표 활성화

**J-055** 왼쪽 화살표 → _selectedYear-- + _loadStats() 호출

**J-056** 오른쪽 화살표 (활성) → _selectedYear++ + _loadStats() 호출

**J-057** `_isFetching=true` 상태에서 _loadStats 재호출 → 중복 실행 차단

---

### [AdminStatsScreen — 사업장 선택 BottomSheet]

**J-058** 사업장 선택 버튼 탭 → BottomSheet 표시 (전체 + 개별 사업장 목록)

**J-059** '전체 사업장' 탭 → _filterBusinessId=null + BottomSheet 닫기 + _loadStats()

**J-060** 개별 사업장 탭 → _filterBusinessId=해당 id + BottomSheet 닫기 + _loadStats()

**J-061** 선택된 사업장 radio 아이콘 checked 표시

**J-062** 현재 선택이 전체인 경우 헤더 텍스트 → '전체 사업장'

**J-063** 개별 선택된 경우 헤더 텍스트 → 해당 사업장 이름 (firstWhere 없으면 businesses.first)

---

### [AdminStatsScreen — KPI 섹션]

**J-064** Hero 카드 — 총 인건비 표시, 전년 대비 증감 배지 표시

**J-065** wageDeltaPct=0 → 증감 배지 미표시

**J-066** 보조 그리드 — 근무건수, 출근율, 노쇼율, 재고용률 4셀 표시

**J-067** 출근율=0 → '-' 표시

**J-068** 노쇼율=0 → '-' 표시

**J-069** 재고용률=0 → '-' 표시

**J-070** avgRating > 0 → '★ X.X' 서브 텍스트 표시

**J-071** _DeltaBadge delta > 0 → 초록색 상향 화살표

**J-072** _DeltaBadge delta < 0 → 빨간색 하향 화살표

---

### [AdminStatsScreen — 월별 차트]

**J-073** 모든 달 데이터 없음(maxWage=0) → '데이터 없음' 텍스트 표시

**J-074** 막대 탭 → `_openMonthDetail(month)` 호출, AdminMonthDetailScreen 이동

**J-075** 현재 월 막대 → primaryColor (강조색), 다른 달 → primaryColor 30% 투명도

**J-076** 탭된 막대 → primaryColor 85% 투명도

**J-077** 툴팁 — 'M월\n인건비\nN건' 표시 (totalWage=0이면 null 반환, 미표시)

**J-078** 연도 라벨 — 현재 월은 primaryColor 굵게, 다른 달은 회색

**J-079** 근무건수 서브 행 — 건수가 0인 달은 빈 문자열 표시

**J-080** `_touchedBarIndex` ValueNotifier dispose 확인 (setState → ValueNotifier로 차트 부분 리빌드)

---

### [AdminStatsScreen — 업무별 인건비]

**J-081** 데이터 없을 때(wageByWorkType 모두 0) → SizedBox.shrink() (미표시)

**J-082** 업무 목록 — 인건비 내림차순 정렬, LinearProgressIndicator 비율 표시

**J-083** 색상 순환 — info, success, warning, purple, error 순서 (5개 초과 시 반복)

**J-084** 업무명 긴 경우 → overflow=ellipsis로 잘림 처리

---

### [AdminStatsScreen — 예외 알림]

**J-085** exceptions 빈 리스트 → 예외 섹션 미표시

**J-086** exceptions 있음 → '${exceptionMonth}월 주의 직원' 헤더

**J-087** 최대 3명까지 표시 (`take(3)`)

**J-088** userName 빈 문자열 또는 '알 수 없음'인 경우 → 해당 항목 필터링 미표시

**J-089** 지각 있는 경우 주황색 '지각 N회' 배지

**J-090** 결근 있는 경우 빨간색 '결근 N회' 배지

---

### [AdminStatsScreen — 인건비 포맷 `_fmtWage`]

**J-091** wage=0 → '-'

**J-092** wage=50000 → '50천'

**J-093** wage=1000000 → '100만'

**J-094** wage=10000000 → '1.0천만'

**J-095** wage=100000000 → '1.0억'

**J-096** wage=150000000 → '1.5억'

---

### [AlgoliaService — 검색]

**J-097** ALGOLIA_APP_ID 또는 ALGOLIA_SEARCH_KEY 미설정 → 경고 로그 + 빈 리스트 반환

**J-098** 빈 키워드 (`keyword.trim().isEmpty`) → 빈 리스트 반환 (API 호출 없음)

**J-099** 정상 검색 — keyword='카페', hitsPerPage=50 → objectID 목록 반환

**J-100** 검색 필터 — city 있음 → facets에 'businessCity:X' 추가
- city + district 둘 다 → 'businessCity:X AND businessDistrict:Y AND isPublished:true'

**J-101** type 필터 → 'type:X AND isPublished:true' 포함

**J-102** 필터 없음 → 'isPublished:true' 하나만 포함

**J-103** HTTP 200 + hits → objectID 추출해 리스트 반환

**J-104** HTTP 4xx/5xx → 에러 로그 + 빈 리스트 반환

**J-105** 네트워크 오류 (Exception) → try/catch로 빈 리스트 반환

**J-106** `hits` 필드 없음 (null) → `?? []` 처리로 빈 리스트 반환

**J-107** `isConfigured` — APP_ID와 SEARCH_KEY 모두 비어 있지 않아야 true

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ J-01 | _queryAttendance 대용량 전체 적재 | 수용 (통계 목적 의도적) |
| ⚠️ J-02 | Algolia hitsPerPage 50 상한 | 수용 (현재 규모 적합) |
