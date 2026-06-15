# Category K — 슈퍼어드민(SuperAdmin) 관리 기능 테스트 시나리오

> 대상 파일:
> - `lib/screens/super_admin/super_admin_home_screen.dart`
> - `lib/screens/super_admin/all_users_screen.dart`
> - `lib/screens/super_admin/all_businesses_screen.dart`
> - `lib/screens/super_admin/system_settings_screen.dart`
> - `lib/screens/super_admin/trust_rules_settings_screen.dart` (Category I 참조)
> - `lib/screens/super_admin/badge_settings_screen.dart`
> - `lib/screens/super_admin/minimum_wage_settings_screen.dart`
> - `lib/screens/super_admin/insurance_rate_settings_screen.dart`
> - `lib/screens/super_admin/review_tags_settings_screen.dart`
>
> 버그 수정: 없음
> 경고: ⚠️ K-01 (사업장 소유자 병렬 조회 300건), ⚠️ K-02 (사용자 500건 limit 고정)

---

## 수정된 버그

없음 — 슈퍼어드민 화면들은 현재 상태에서 심각한 로직 버그 없음.

---

## 경고 (버그 수준 아님)

### ⚠️ K-01 — `AllBusinessesScreen` 소유자 조회 N+1 병렬화 제한
- 사업장 최대 300건 × 소유자 조회 `Future.wait` — 300개 동시 요청
- Firestore는 일반적으로 수백 개 병렬 요청 처리 가능하나 네트워크 혼잡 시 지연 가능
- 현재 규모(수십 개 사업장)에서는 수용 가능

### ⚠️ K-02 — `AllUsersScreen` limit 500 고정, 페이지네이션 없음
- 사용자가 500명 초과 시 일부 미표시 — OOM 방지 의도적 제한
- 향후 페이지네이션 또는 서버 사이드 검색 도입 고려

---

## 테스트 시나리오 (K-001 ~ K-100)

### [SuperAdmin 홈 — AdminHomeScreen]

**K-001** SUPER_ADMIN 역할 로그인 → AdminHomeScreen 표시

**K-002** 헤더 — '최고' 역할 배지 + 사용자 이름 + 이메일 표시

**K-003** 가로 모드 → vertical 패딩 축소 + 인사말 섹션 숨김

**K-004** 세로 모드 → 인사말 섹션 표시 ('안녕하세요, {name}님')

**K-005** currentUser.name null → '관리자님' 표시

**K-006** 로그아웃 버튼 → 확인 다이얼로그 표시 후 signOut 및 ThemeProvider.reset()

**K-007** 로그아웃 취소 → 홈 화면 유지

**K-008** GridView 6개 메뉴 카드 표시 (모든 사업장, 공고 모니터링, 사용자 관리, 통계, 시스템 설정, 설정)

**K-009** '모든 사업장' 카드 탭 → AllBusinessesScreen 이동

**K-010** '공고 모니터링' 카드 탭 → '준비 중' 토스트

**K-011** '사용자 관리' 카드 탭 → '준비 중' 토스트

**K-012** '통계' 카드 탭 → '준비 중' 토스트

**K-013** '시스템 설정' 카드 탭 → SystemSettingsScreen 이동

**K-014** '설정' 카드 탭 → SettingsScreen 이동

---

### [AllUsersScreen — 전체 사용자 관리]

**K-015** 화면 진입 → users 컬렉션 최신순 최대 500건 조회 (limit 500)

**K-016** 로딩 중 → LoadingWidget 표시

**K-017** 조회 성공 → 타이틀 '전체 사용자 관리 (N명)' 업데이트

**K-018** 조회 실패 → '사용자 목록 불러오기 실패' 에러 토스트

**K-019** 검색 — 이름 소문자 포함 필터
- 조건: "김" 검색 → '김철수', '이김우' 포함

**K-020** 검색 — 이메일 포함 필터

**K-021** 검색 — username 포함 필터

**K-022** 검색 결과 없음 → AppEmptyState 표시 ('해당하는 사용자가 없습니다')

**K-023** 검색창 X 버튼 → 검색어 초기화 + 전체 목록 복원

**K-024** 역할 필터 — '전체' → 전체 사용자

**K-025** 역할 필터 — '지원자' → USER 역할만

**K-026** 역할 필터 — '관리자' → BUSINESS_ADMIN 역할만

**K-027** 역할 필터 — '슈퍼관리자' → SUPER_ADMIN 역할만

**K-028** 역할 필터 + 검색 복합 → 역할 필터 먼저, 이름/이메일 검색 추가 적용

**K-029** 사용자 카드 — SUPER_ADMIN: 빨간 역할 배지 '슈퍼관리자'

**K-030** 사용자 카드 — BUSINESS_ADMIN: 보라색 역할 배지 '사업장관리자'

**K-031** 사용자 카드 — USER: 초록색 역할 배지 '지원자'

**K-032** 블랙리스트 사용자 → 카드에 빨간 '블랙리스트' 표시

**K-033** 신뢰도/근무일 표시 — '신뢰도: {storedTrustScore ?? 100}점  근무: {totalWorkDays}일'

**K-034** phone null 사용자 → 전화번호 행 미표시

**K-035** RefreshIndicator pull → _loadAllUsers 재호출

---

### [AllBusinessesScreen — 전체 사업장 관리]

**K-036** 화면 진입 → businesses 컬렉션 최신순 최대 300건 조회

**K-037** 각 사업장 소유자 정보 병렬 조회 (Future.wait)

**K-038** 로딩 중 → LoadingWidget 표시

**K-039** 사업장 없음 → AppEmptyState 표시 ('등록된 사업장이 없습니다')

**K-040** 조회 실패 → '사업장 목록을 불러오는데 실패했습니다' 에러 토스트

**K-041** 사업장 카드 — 승인됨(isApproved=true) → 초록색 '승인됨' 배지

**K-042** 사업장 카드 — 미승인(isApproved=false) → 주황색 '대기중' 배지

**K-043** 소유자 정보 — 이름 + 이메일 표시 (이메일 있을 때)

**K-044** 소유자 조회 실패 → '알 수 없음', 이메일 빈 문자열 표시

**K-045** 사업자등록번호 표시 — `business.formattedBusinessNumber`

**K-046** 업종 표시 — '${business.category} / ${business.subCategory}'

**K-047** 주소 표시 — `business.address`

**K-048** 연락처 있음 → 연락처 행 표시

**K-049** 연락처 null → 연락처 행 미표시

**K-050** 설명 있음 → 설명 박스 표시

**K-051** 설명 없음(null/빈 문자열) → 설명 박스 미표시

**K-052** 등록일 표시 — `formatDateISO(business.createdAt)`

**K-053** RefreshIndicator pull → _loadAllBusinesses 재호출

---

### [SystemSettingsScreen — 시스템 설정]

**K-054** 화면 표시 — '리뷰 & 신뢰도' 섹션 + '기타 설정' 섹션

**K-055** '신뢰도 규칙' 탭 → TrustRulesSettingsScreen 이동

**K-056** '리뷰 태그' 탭 → ReviewTagsSettingsScreen 이동

**K-057** '배지 관리' 탭 → BadgeSettingsScreen 이동

**K-058** '최저시급 설정' 탭 → MinimumWageSettingsScreen 이동

**K-059** '보험료율 설정' 탭 → InsuranceRateSettingsScreen 이동

**K-060** '알림 설정' 탭 (isDisabled=true) → 탭 비활성, '준비 중' 토스트

**K-061** 비활성 항목 — 아이콘/텍스트 회색 표시

**K-062** 활성 항목 — chevron_right 아이콘 표시

---

### [BadgeSettingsScreen — 배지 관리]

**K-063** 화면 진입 → 배지 목록 조회

**K-064** 배지 활성/비활성 토글

**K-065** 배지 추가 → 이름, 설명, 조건 입력 후 저장

**K-066** 배지 수정 → 기존 데이터 로드 후 수정

**K-067** 배지 삭제 → 확인 다이얼로그 후 삭제

**K-068** 빈 이름으로 저장 시도 → 유효성 검사 오류

---

### [MinimumWageSettingsScreen — 최저시급 설정]

**K-069** 화면 진입 → 연도별 최저시급 목록 조회

**K-070** 연도 추가 → 연도 + 금액 입력 후 저장

**K-071** 중복 연도 입력 → 기존 값 덮어쓰기 또는 오류

**K-072** 금액 0 또는 음수 입력 → 유효성 검사 오류

**K-073** 삭제 → 확인 후 해당 연도 제거

---

### [InsuranceRateSettingsScreen — 보험료율 설정]

**K-074** 화면 진입 → 연도별 보험료율 목록 조회 (국민연금, 건강보험, 고용보험, 소득세 등)

**K-075** 각 요율 필드 수정 후 저장

**K-076** 요율 0% 미만 또는 100% 초과 입력 → 유효성 검사 오류

**K-077** 저장 성공 → Firestore 갱신 + 성공 토스트

---

### [ReviewTagsSettingsScreen — 리뷰 태그 설정]

**K-078** 화면 진입 → 긍정/개선 태그 목록 조회

**K-079** 태그 추가 → 입력 후 저장

**K-080** 태그 삭제 → 확인 후 제거

**K-081** 빈 태그 저장 시도 → 유효성 검사 오류

**K-082** 태그 활성/비활성 토글

---

### [공통 — 슈퍼어드민 화면]

**K-083** BUSINESS_ADMIN 역할 접근 시 → 화면 접근 불가 (라우팅 차단)

**K-084** USER 역할 접근 시 → 화면 접근 불가

**K-085** 설정 저장 중 (_isSaving=true) → 저장 버튼 비활성화

**K-086** 화면 간 이동 → 뒤로가기 정상 동작

**K-087** 오프라인 상태에서 목록 조회 → 에러 토스트, 빈 상태 처리

---

### [통합 시나리오]

**K-088** 슈퍼어드민 로그인 → 홈 진입 → 시스템 설정 → 신뢰도 규칙 수정 → 저장 성공

**K-089** 슈퍼어드민 로그인 → 모든 사업장 → 특정 사업장 확인 (승인 여부, 소유자)

**K-090** 슈퍼어드민 로그인 → 전체 사용자 → 이름 검색 → 블랙리스트 확인

**K-091** 신뢰도 규칙 수정 후 30분 내 TrustScoreService 캐시 만료 전 — 구 규칙 적용 (⚠️ I-01)

**K-092** 최저시급 변경 → 급여 계산 시 즉시 반영 확인

**K-093** 보험료율 변경 → 급여명세서 생성 시 새 요율 적용 확인

**K-094** 배지 비활성화 → 해당 배지 사용자에게 미표시

**K-095** 리뷰 태그 추가 → 리뷰 작성 시 태그 목록에 표시

**K-096** 리뷰 태그 삭제 → 기존 리뷰의 태그 데이터는 유지 (Firestore 하위 데이터 영향 없음)

**K-097** 사업장 300건 초과 시 → limit=300으로 나머지 미표시 (⚠️ K-02)

**K-098** 로그아웃 후 홈으로 이동 → 로그인 화면으로 이동

**K-099** 가로 모드에서 GridView → 2열 유지, 카드 크기 자동 조정

**K-100** 설정 저장 실패 시 UI 복원 — setState로 _isSaving=false 복원 확인

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ K-01 | AllBusinessesScreen 소유자 병렬 조회 300건 | 수용 |
| ⚠️ K-02 | AllUsersScreen limit 500 고정 | 수용 |
