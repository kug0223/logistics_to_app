# Phase 6 개발 진행 상황 정리 및 다음 단계 계획

## 📅 작업 일시
2025년 10월 22일

---

## ✅ 완료된 작업 요약

### Phase 6-1: 권한 시스템 개편 ✅ 완료!

#### 완료된 파일들
1. ✅ `user_model.dart` - UserRole enum 추가 (SUPER_ADMIN, BUSINESS_ADMIN, USER)
2. ✅ `business_model.dart` - 사업장 모델 신규 생성
3. ✅ `constants.dart` - 업종 카테고리 추가 (회사/알바 매장/기타)
4. ✅ `auth_service.dart` - role 기반 회원가입 개편
5. ✅ `main.dart` - 3단계 권한 라우팅
6. ✅ `user_provider.dart` - 권한 체크 메서드 추가
7. ✅ `daum_address_search.dart` - Web 에러 수정 (dart:ui_web)

#### 테스트 결과
```
✅ admin@test.com → SUPER_ADMIN 자동 변환 확인
✅ user@test.com → USER 자동 변환 확인
✅ 기존 데이터 호환성 정상 작동
```

---

### Phase 6-2: 사업장 관리 시스템 (Step 1~2) ✅ 완료!

#### Step 1: FirestoreService 확장
**추가된 메서드 (14개)**
```dart
// CRUD
- createBusiness()
- updateBusiness()
- deleteBusiness()
- getBusinessById()

// 조회
- getAllBusinesses()
- getApprovedBusinesses()
- getPendingBusinesses()
- getMyBusiness()
- getBusinessesByCategory()

// 승인 관리
- approveBusiness()
- rejectBusiness()

// 통계
- getTOCountByBusiness()

// 실시간
- approvedBusinessesStream()
```

**적용 완료:**
- ✅ `firestore_service.dart`에 사업장 메서드 추가
- ✅ `business_model.dart` import 추가

---

#### Step 2: 사업장 등록 화면
**파일:** `business_registration_screen.dart`

**구조:**
```
Step 1: 업종 선택 (가치업 스타일)
├─ 회사
│   ├─ 일반 회사
│   └─ 제조, 생산, 건설
├─ 알바 매장
│   ├─ 알바-카페
│   ├─ 알바-외식업
│   ├─ 알바-판매-서비스
│   └─ 알바-매장관리
└─ 기타
    ├─ 교육, 의료, 기관
    └─ 기타

Step 2: 사업장 정보 입력
├─ 사업장명 (필수)
├─ 주소 (필수) + Daum 주소 검색
├─ 위도/경도 (자동 입력)
├─ 연락처 (선택)
└─ 설명 (선택)
```

**적용 완료:**
- ✅ `lib/screens/admin/business_registration_screen.dart` 생성
- ✅ Stepper UI 구현
- ✅ ExpansionTile + Radio 업종 선택
- ✅ Daum 주소 검색 연동
- ✅ 좌표 자동 입력 (Kakao Geocoding)

---

## 🎯 중요한 결정 사항

### 최종 결정: 회원가입 시 역할 선택

#### 기존 구조 (변경 전)
```
회원가입 → USER로 가입 → 사업장 등록 신청 → 슈퍼관리자 승인 대기
```

#### 새로운 구조 (변경 후) ⭐
```
회원가입 시 선택:

1. 일반 지원자 (USER)
   └─ TO에 지원하는 사람
   └─ 사업장 등록 메뉴 없음
   └─ 지원자 홈 화면

2. 사업장 관리자 (BUSINESS_ADMIN)
   └─ TO를 만드는 사람
   └─ 가입 시 사업장 등록 필수
   └─ 관리자 홈 화면
   └─ 슈퍼관리자 승인 불필요

3. 슈퍼관리자 (SUPER_ADMIN)
   └─ 플랫폼 운영자
   └─ 코드로만 생성 가능
```

#### 장점
- ✅ **명확한 역할 분리**: 지원자는 지원만, 관리자는 TO 생성만
- ✅ **간단한 온보딩**: 승인 과정 없이 바로 사용 가능
- ✅ **UX 개선**: 각 역할에 맞는 화면만 표시
- ✅ **역할 혼란 제거**: 한 계정은 한 역할만

---

## 🚀 다음 단계 (Phase 6-2 계속)

### Step 3: 회원가입 화면 개편 ⭐ 최우선!

#### 수정할 파일
**파일:** `lib/screens/auth/register_screen.dart`

#### 새로운 회원가입 플로우
```
Step 1: 기본 정보 입력
├─ 이름
├─ 이메일
└─ 비밀번호

Step 2: 역할 선택 (NEW!) ⭐
┌──────────────────────────────┐
│    어떻게 이용하시나요?       │
├──────────────────────────────┤
│ 🙋 일반 지원자                │
│ TO에 지원하고 싶어요          │
│ [선택하기]                    │
├──────────────────────────────┤
│ 👔 사업장 관리자              │
│ TO를 등록하고 싶어요          │
│ [선택하기]                    │
└──────────────────────────────┘

Step 3-A: 일반 지원자 선택
└─ role: USER 로 회원가입 완료
└─ 일반 사용자 홈으로 이동

Step 3-B: 사업장 관리자 선택
└─ role: BUSINESS_ADMIN 으로 회원가입
└─ 사업장 등록 화면으로 즉시 이동 (필수)
└─ 사업장 정보 입력 완료
└─ 관리자 홈으로 이동
```

---

### Step 4: 홈 화면 분리

#### 4-1. 일반 사용자 홈 (`user_home_screen.dart`)
```dart
메뉴:
- TO 지원하기
- 내 지원 내역
- 출퇴근 체크
- 내 정보
- 설정

❌ 제거: 사업장 등록 메뉴
```

#### 4-2. 사업장 관리자 홈 (`business_admin_home_screen.dart`) - 새로 만들기! ⭐
```dart
메뉴:
- TO 생성하기
- 내 TO 관리
- 지원자 관리
- 내 사업장 정보
- 통계
- 설정
```

#### 4-3. 슈퍼관리자 홈 (`super_admin_home_screen.dart`) - 새로 만들기!
```dart
메뉴:
- 전체 사업장 관리
- 전체 TO 모니터링
- 사용자 관리
- 통계 대시보드
- 설정
```

---

### Step 5: main.dart 라우팅 수정

```dart
// main.dart
switch (user.role) {
  case UserRole.SUPER_ADMIN:
    return const SuperAdminHomeScreen();  // ✅ 새로 만들기
  
  case UserRole.BUSINESS_ADMIN:
    return const BusinessAdminHomeScreen();  // ✅ 새로 만들기
  
  case UserRole.USER:
    return const UserHomeScreen();  // ✅ 수정 (사업장 등록 메뉴 제거)
  
  default:
    return const LoginScreen();
}
```

---

## 📋 구체적인 작업 계획

### 우선순위 1: 회원가입 화면 개편 (Step 3)

**작업 내용:**
1. `register_screen.dart` 수정
   - Stepper 또는 PageView로 단계별 UI
   - Step 2: 역할 선택 화면 추가
2. `auth_service.dart` 수정
   - signUp 메서드에 role 전달
3. 사업장 관리자 선택 시
   - 회원가입 완료 후 바로 `BusinessRegistrationScreen`으로 이동
   - 사업장 등록 완료 후 관리자 홈으로

**예상 시간:** 2-3시간

---

### 우선순위 2: 사업장 관리자 홈 화면 (Step 4-2)

**파일:** `business_admin_home_screen.dart` (새로 생성)

**구조:**
```dart
AppBar
├─ 제목: "사업장 관리"
└─ Actions: 로그아웃 버튼

Body
├─ 사업장 정보 카드
│   ├─ 사업장명
│   ├─ 주소
│   └─ 수정 버튼
├─ 메뉴 그리드
│   ├─ TO 생성하기 (FloatingActionButton)
│   ├─ 내 TO 관리
│   ├─ 지원자 관리
│   ├─ 통계
│   └─ 설정
```

**예상 시간:** 2-3시간

---

### 우선순위 3: TO 생성 화면 수정

**파일:** `admin_create_to_screen.dart` 수정

**변경 사항:**
- ❌ 센터 선택 드롭다운 제거
- ✅ 자동으로 내 사업장 정보 사용
- ✅ businessId 자동 입력

**예상 시간:** 1시간

---

### 우선순위 4: 슈퍼관리자 홈 화면 (나중에)

**파일:** `super_admin_home_screen.dart` (새로 생성)

**기능:**
- 전체 사업장 목록
- 전체 TO 모니터링
- 사용자 관리
- 통계 대시보드

**예상 시간:** 3-4시간

---

## 📂 파일 구조 (변경 후)

```
lib/
├── models/
│   ├── user_model.dart              ✅ 완료
│   ├── business_model.dart          ✅ 완료
│   ├── to_model.dart
│   └── application_model.dart
├── services/
│   ├── auth_service.dart            ✅ 완료
│   ├── firestore_service.dart       ✅ 완료 (사업장 메서드 추가)
│   └── location_service.dart
├── providers/
│   └── user_provider.dart           ✅ 완료
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart     🚧 수정 필요 (Step 3)
│   ├── user/
│   │   ├── user_home_screen.dart    🚧 수정 필요 (사업장 등록 메뉴 제거)
│   │   ├── center_list_screen.dart
│   │   ├── to_list_screen.dart
│   │   ├── to_detail_screen.dart
│   │   └── my_applications_screen.dart
│   └── admin/
│       ├── business_admin_home_screen.dart     ⭐ 새로 만들기 (Step 4-2)
│       ├── super_admin_home_screen.dart        ⭐ 새로 만들기 (나중에)
│       ├── business_registration_screen.dart   ✅ 완료
│       ├── admin_create_to_screen.dart         🚧 수정 필요 (센터→사업장)
│       ├── admin_to_detail_screen.dart
│       └── admin_home_screen.dart              (deprecated - 삭제 예정)
├── widgets/
│   ├── custom_button.dart
│   ├── loading_widget.dart
│   ├── to_card_widget.dart
│   └── daum_address_search.dart     ✅ 완료
├── utils/
│   ├── constants.dart               ✅ 완료
│   └── toast_helper.dart
├── firebase_options.dart
└── main.dart                        🚧 수정 필요 (라우팅 분기)
```

---

## 🎯 다음 대화에서 할 일

### 1단계: 회원가입 화면 개편 ⭐ 최우선!
```
register_screen.dart 수정
├─ Step 1: 기본 정보
├─ Step 2: 역할 선택 (NEW!)
└─ Step 3: 완료 또는 사업장 등록으로 이동
```

### 2단계: 사업장 관리자 홈 화면
```
business_admin_home_screen.dart 새로 생성
├─ 사업장 정보 카드
├─ TO 생성/관리 메뉴
└─ 지원자 관리 메뉴
```

### 3단계: 라우팅 및 기타 화면 수정
```
- main.dart 라우팅 분기
- user_home_screen.dart 사업장 등록 메뉴 제거
- admin_create_to_screen.dart 센터→사업장 변경
```

---

## 💾 저장된 파일 목록

### Phase 6-1 관련
- `user_model.dart`
- `business_model.dart`
- `constants.dart`
- `auth_service.dart`
- `main.dart`
- `user_provider.dart`
- `daum_address_search.dart`

### Phase 6-2 관련
- `사업장_메서드_추가_코드.dart` (firestore_service.dart에 추가용)
- `business_registration_screen.dart`
- `user_home_screen_with_business.dart` (이제 필요 없음 - 사업장 등록 메뉴 제거 예정)

### 문서
- `PHASE_6-1_완료_보고서.md`
- `PHASE_6-2_Step1-2_완료_보고서.md`
- `단계별_수정_가이드.md`
- `사업장_등록_버튼_추가_가이드.md` (이제 필요 없음)

---

## 🔑 핵심 결정 사항 요약

### ✅ 확정된 사항
1. **회원가입 시 역할 선택 필수**
   - 일반 지원자 (USER)
   - 사업장 관리자 (BUSINESS_ADMIN)

2. **사업장 관리자 가입 시 사업장 등록 필수**
   - 회원가입 → 사업장 등록 → 관리자 홈

3. **역할 중복 불가**
   - 한 계정은 한 역할만
   - 명확한 분리

4. **슈퍼관리자 승인 불필요**
   - 사업장 등록 시 바로 승인 (isApproved: true)
   - 추후 신고 시스템으로 관리

5. **홈 화면 완전 분리**
   - 일반 사용자 홈
   - 사업장 관리자 홈
   - 슈퍼관리자 홈

---

## 💬 다음 대화 시작할 때

**이렇게 말씀해주세요:**

> "Phase 6-2 이어서 진행하자! 회원가입 화면 개편부터 시작하면 돼"

또는

> "register_screen.dart 수정해서 역할 선택 기능 추가하자"

---

## 🎉 현재까지 잘하고 있어요!

- ✅ Phase 6-1 완벽하게 완료!
- ✅ Phase 6-2 Step 1~2 완료!
- ✅ 명확한 방향성 확립!
- ✅ 다음 단계 계획 수립 완료!

**화이팅! 🚀**

---

**📝 작성일:** 2025년 10월 22일  
**💾 파일명:** `Phase_6_진행상황_및_다음단계.md`  
**🔗 연관 문서:**
- `PHASE_6-1_완료_보고서.md`
- `PHASE_6-2_Step1-2_완료_보고서.md`
- `current_status_v5.md`
