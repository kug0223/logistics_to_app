# Category M — 인증·온보딩·공통 화면 테스트 시나리오

> 대상 파일:
> - `lib/screens/common/splash_screen.dart`
> - `lib/screens/auth/login_screen.dart`
> - `lib/screens/auth/register_screen.dart`
> - `lib/screens/common/settings_screen.dart`
>
> 버그 수정: 없음
> 경고: ⚠️ M-01 (비밀번호 찾기 인증코드 5분 만료 클라이언트 미표시), ⚠️ M-02 (주민번호 체크섬 미검증)

---

## 수정된 버그

없음 — 인증·온보딩·설정 화면 현재 상태에서 심각한 로직 버그 없음.

---

## 경고 (버그 수준 아님)

### ⚠️ M-01 — 비밀번호 찾기 인증코드 5분 만료 클라이언트 미표시
- 인증코드 발송 후 '5분 유효' 토스트만 표시, 화면 내 카운트다운 타이머 없음
- 사용자가 5분 경과 후 코드를 입력하면 서버 오류 토스트만 표시
- UX 개선으로 카운트다운 타이머 추가 고려 (현재 기능 정상)

### ⚠️ M-02 — 주민번호 뒷자리 체크섬 미검증
- 코드 주석: "뒷자리 첫 자리(성별코드)만 입력받으므로 체크섬 검증 불가 — 서버 측 검증으로 대체 예정"
- 현재 클라이언트에서는 성별코드 범위만 검증
- 서버(Cloud Function) 측 검증 구현 시 해결 예정

---

## 테스트 시나리오 (M-001 ~ M-100)

---

### [SplashScreen — 스플래시]

**M-001** 앱 실행 → 600ms 페이드+스케일 애니메이션 정상 재생

**M-002** 2000ms 후 AppVersionService.check() 호출

**M-003** VersionCheckResult.ok → AuthWrapper로 FadeTransition 전환 (400ms)

**M-004** VersionCheckResult.forceUpdate → '업데이트 필요' 다이얼로그 (PopScope canPop=false, barrierDismissible=false)

**M-005** forceUpdate 다이얼로그 → 뒤로가기 차단 (앱 진입 영구 차단)

**M-006** forceUpdate + update_url_android 있음 → '스토어로 이동' 버튼 활성화 + launchUrl 호출

**M-007** forceUpdate + update_url 빈 문자열 → '스토어로 이동' 버튼 비활성화 (null 처리)

**M-008** VersionCheckResult.recommendUpdate → '업데이트 안내' 다이얼로그 (barrierDismissible 기본값)

**M-009** recommendUpdate 다이얼로그 — '나중에' 탭 → 다이얼로그 닫기 + AuthWrapper 이동

**M-010** recommendUpdate 다이얼로그 — '업데이트' 탭 → 스토어 URL 열기

**M-011** iOS 플랫폼 → update_url_ios RemoteConfig 값 사용

**M-012** Android 플랫폼 → update_url_android RemoteConfig 값 사용

**M-013** 화면 dispose 후 Timer 완료 → mounted 체크로 Navigator 호출 차단

---

### [LoginScreen — 로그인]

**M-014** 화면 진입 → 아이디/비밀번호 텍스트 필드 표시, 로그인 버튼

**M-015** 아이디 필드 빈 채로 로그인 → validator '아이디를 입력해주세요' 표시

**M-016** 비밀번호 빈 채로 로그인 → validator '비밀번호를 입력해주세요' 표시

**M-017** 비밀번호 7자 이하 → validator '비밀번호는 8자 이상이어야 합니다' 표시

**M-018** 아이디 필드 엔터 → 비밀번호 필드로 포커스 이동 (TextInputAction.next)

**M-019** 비밀번호 필드 엔터 → `_handleLogin()` 호출 (TextInputAction.done)

**M-020** 로그인 성공 → AnalyticsService.logLogin(role) 호출

**M-021** 로그인 실패 → userProvider.error 메시지 토스트 (null/빈 → '아이디 또는 비밀번호가 올바르지 않습니다.')

**M-022** 로그인 중 (_isLoading=true) → LoadingOverlay '로그인 중...' 표시 + 버튼 비활성화

**M-023** 비밀번호 표시/숨김 토글 → _obscurePassword 전환

**M-024** 로그인 중 재탭 → userProvider.isLoading 체크로 중복 실행 차단

**M-025** '회원가입' 링크 탭 → RegisterScreen 이동

---

### [LoginScreen — 아이디 찾기]

**M-026** '아이디 찾기' 탭 → BottomSheet 표시 (이름 + 전화번호 입력 폼)

**M-027** 이름 빈 채로 찾기 → '이름을 입력해주세요' 토스트 + 이름 필드 포커스

**M-028** 전화번호 빈 채로 찾기 → '전화번호를 입력해주세요' 토스트 + 전화번호 필드 포커스

**M-029** 찾기 성공 → foundUsername 마스킹 표시 (앞 4자리 노출, 나머지 `*`)

**M-030** foundUsername 4자 이하 → 마스킹 없이 전체 표시

**M-031** 일치하는 계정 없음 → '일치하는 계정을 찾을 수 없어요' + '다시 찾기' 버튼

**M-032** '다시 찾기' 탭 → foundUsername 초기화 + 입력 폼 복원

**M-033** 찾기 중 (isSearching=true) → 버튼 비활성화 + CircularProgressIndicator

**M-034** 찾기 완료 → '확인' 탭 시 BottomSheet 닫기

**M-035** 이름 엔터 → 전화번호 필드로 포커스 이동

---

### [LoginScreen — 비밀번호 찾기]

**M-036** '비밀번호 찾기' 탭 → BottomSheet Step 0 표시 (아이디 + 이메일 입력)

**M-037** Step 0 — 아이디 빈 채로 발송 → '아이디를 입력해주세요' 토스트

**M-038** Step 0 — '@' 없는 이메일 → '올바른 이메일을 입력해주세요' 토스트

**M-039** Step 0 — 발송 성공 → '인증번호가 이메일로 발송되었습니다 (5분 유효)' 토스트 + Step 1 전환

**M-040** Step 0 — FirebaseFunctionsException → e.message 에러 토스트

**M-041** Step 0 — 일반 예외 → '오류가 발생했습니다. 다시 시도해주세요' 에러 토스트

**M-042** Step 0 — 발송 중 (isSending=true) → 버튼 비활성화 + CircularProgressIndicator

**M-043** Step 1 — 인증번호 6자 미만 → '6자리 인증번호를 입력해주세요' 토스트

**M-044** Step 1 — 비밀번호 정책 미충족 (8자 미만/영문 미포함/숫자 미포함/특수문자 미포함) → 경고 토스트

**M-045** Step 1 — 비밀번호 불일치 → '비밀번호가 일치하지 않습니다' 토스트

**M-046** Step 1 — 변경 성공 → Step 2 (완료 화면) 전환

**M-047** Step 1 — FirebaseFunctionsException → e.message 에러 토스트

**M-048** Step 2 — '로그인하러 가기' 탭 → BottomSheet 닫기

**M-049** 새 비밀번호 표시/숨김 토글 (obscureNew), 확인 표시/숨김 토글 (obscureConfirm)

---

### [RegisterScreen — 회원가입 (3단계)]

**M-050** 화면 진입 → 400ms 후 이름 필드 자동 포커스 + 약관 Firestore 로드

**M-051** 약관 로드 실패 → LegalTerms.defaultTerms() 폴백 적용

**M-052** Step 0 — 역할 선택 없이 다음 → '이용 방법을 선택해주세요' 토스트

**M-053** Step 0 — USER 선택 → Step 1 전환

**M-054** Step 0 — BUSINESS_ADMIN 선택 → Step 1 전환

**M-055** Step 1 — 아이디 중복 확인: ValueNotifier 디바운스 (타이핑마다 전체 rebuild 방지)

**M-056** Step 1 — 아이디 중복 → 중복 표시, 미중복 → 사용 가능 표시

**M-057** Step 1 — 신분증 유형 'resident' (주민번호) → 주민번호 앞6자리 + 뒷자리 첫 1자리 입력

**M-058** Step 1 — 신분증 유형 'foreign' (외국인등록번호) → 코드 범위 5~8 검증

**M-059** Step 1 — 신분증 유형 'passport' (여권) → 여권번호 패턴 `[A-Z]{1,2}[0-9]{6,8}` + 생년월일 피커

**M-060** Step 1 — 주민번호 파싱 → 생년월일 + 성별 자동 추출, 만 18세 미만 → '만 18세 이상만 가입 가능합니다'

**M-061** Step 1 — 여권 만 18세 미만 → '만 18세 이상만 가입 가능합니다'

**M-062** Step 1 — 전화번호 SMS 인증 미완료 → '휴대폰 번호 인증을 완료해주세요' 토스트

**M-063** Step 1 — 전화번호 변경 후 재인증 필요 → _lastSentPhone 추적으로 재인증 강제

**M-064** Step 1 — 이메일 분리 입력 (로컬 + 도메인 선택/직접입력)

**M-065** Step 1 — 필수 약관 미동의 → '필수 약관에 모두 동의해주세요' 토스트

**M-066** Step 1 — 약관 열람 없이 동의 체크 → 열람 완료 항목(_viewedTermIds)만 체크 허용

**M-067** Step 1 — 비밀번호 정책 (8자 이상 + 영문 + 숫자 + 특수문자) 미충족 → validator 오류

**M-068** Step 1 — 비밀번호 확인 불일치 → validator 오류

**M-069** Step 1 — 더블탭 Step 건너뜀 방지 (_isStepTransitioning 가드)

**M-070** Step 2 (USER) — 신분증/통장사본 이미지 업로드 (선택, StorageService)

**M-071** Step 2 (BUSINESS_ADMIN) — 사업자등록번호 빈 채로 → '사업자등록번호를 입력해주세요' 토스트

**M-072** Step 2 (BUSINESS_ADMIN) — 10자리 미만 → '사업자등록번호 10자리를 확인해주세요' 토스트

**M-073** Step 2 (BUSINESS_ADMIN) — 체크섬 검증 실패 → '유효하지 않은 사업자등록번호입니다' 토스트

**M-074** Step 2 (BUSINESS_ADMIN) — 사업자등록증 미업로드 → 경고 다이얼로그 (나중에 등록 허용)

**M-075** Step 2 (BUSINESS_ADMIN) — 사업자등록증 업로드 완료 → 사업장 등록 여부 선택 다이얼로그

**M-076** 가입 완료 → AnalyticsService 이벤트 기록

**M-077** 뒤로가기(이전 Step) → _currentStep-- + 스크롤 맨 위로

**M-078** Step 0에서 뒤로가기 → Navigator.pop (LoginScreen으로 복귀)

**M-079** 화면 dispose → 모든 Controller + FocusNode + Timer 정리 (메모리 누수 없음)

---

### [SettingsScreen — 설정]

**M-080** 화면 진입 → 알림 상태 로드 (시스템 권한 + Firestore fcmToken 확인)

**M-081** 시스템 권한 미허용 → _isPushEnabled=false

**M-082** 시스템 권한 허용 + fcmToken 없음 → _isPushEnabled=false

**M-083** 시스템 권한 허용 + fcmToken 있음 → _isPushEnabled=true

**M-084** 푸시 알림 켜기 → 시스템 권한 요청, 권한 거부 시 앱 설정으로 이동 안내

**M-085** 푸시 알림 켜기 성공 → FCMService.initialize() 호출 + '푸시 알림이 활성화되었습니다' 토스트

**M-086** 푸시 알림 끄기 → FCMService.clearToken() 호출 + '푸시 알림이 비활성화되었습니다' 토스트

**M-087** 개별 알림 카테고리 토글 → Firestore notifPrefs 업데이트 + 실패 시 롤백

**M-088** Firestore 알림 설정 저장 실패 → setState 롤백 + '설정 저장에 실패했습니다' 에러 토스트

**M-089** 앱 버전 표시 — PackageInfo.fromPlatform() 기반 version 표시

**M-090** USER 역할 → '내 서류 관리' + '내 평가 확인' + 서명 패드 섹션 표시

**M-091** BUSINESS_ADMIN 역할 → 사업장 설정 섹션 표시 (계약서 템플릿, 구성원 관리 등)

**M-092** SUPER_ADMIN 역할 → 슈퍼어드민 전용 메뉴 표시

**M-093** 이메일 인증 카드 — 미인증 → '이메일 인증하기' 버튼 표시

**M-094** 이메일 인증 완료 → 인증 완료 표시

**M-095** BUSINESS_ADMIN 사업장 인감 — businessId 있음 → sealBase64 이미지 로드

**M-096** BUSINESS_ADMIN sealBase64 null → 인감 없음 상태 표시

**M-097** BUSINESS_ADMIN adminIds로 사업장 조회 폴백 — businessId null일 때 businesses 컬렉션에서 adminIds arrayContains 조회

**M-098** 프로필 수정 탭 → ProfileEditScreen 이동

**M-099** 로그아웃 → 확인 다이얼로그 후 signOut + ThemeProvider.reset()

**M-100** notifPrefs Firestore 저장 값 → UserModel.defaultNotifPrefs와 merge 후 적용

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ M-01 | 비밀번호 찾기 인증코드 5분 만료 클라이언트 미표시 | 수용 (토스트 안내 있음) |
| ⚠️ M-02 | 주민번호 체크섬 미검증 — 서버 측 검증으로 대체 예정 | 수용 (코드에 TODO 명시됨) |
