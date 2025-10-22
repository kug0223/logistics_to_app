# Phase 6-2 Step 3: 회원가입 화면 개편 완료 보고서 ✅

## 📅 작업 일시
2025년 10월 22일

---

## ✅ 완료된 작업

### 1. 회원가입 화면 개편 (register_screen.dart)

#### 새로운 구조
```
Stepper 기반 2단계 회원가입

Step 1: 기본 정보 입력
├─ 이름
├─ 이메일
├─ 비밀번호
└─ 비밀번호 확인

Step 2: 역할 선택 ⭐ NEW!
├─ 일반 지원자 (USER)
│   ├─ 아이콘: 👤
│   ├─ 설명: TO에 지원하고 싶어요
│   └─ 기능: TO 지원, 지원 내역, 출퇴근 체크
└─ 사업장 관리자 (BUSINESS_ADMIN)
    ├─ 아이콘: 🏢
    ├─ 설명: TO를 등록하고 싶어요
    └─ 기능: TO 생성/관리, 지원자 승인, 사업장 관리
```

#### 주요 기능
1. **Stepper UI**
   - 단계별 진행 표시
   - 이전/다음 버튼
   - 각 단계 유효성 검증

2. **역할 선택 카드**
   - 선택 가능한 2개의 카드 UI
   - 선택 시 하이라이트 및 체크 아이콘
   - 각 역할의 기능 목록 표시
   - 색상 구분 (USER: 파란색, BUSINESS_ADMIN: 초록색)

3. **회원가입 분기 처리**
   ```dart
   if (role == USER) {
       회원가입 완료 → 로그인 화면으로
   } else if (role == BUSINESS_ADMIN) {
       회원가입 완료 → 사업장 등록 화면으로
   }
   ```

---

### 2. UserProvider 수정 (user_provider.dart)

#### 변경 사항
```dart
// 기존
Future<bool> signUp({
  required String email,
  required String password,
  required String name,
})

// 변경 후 ✅
Future<bool> signUp({
  required String email,
  required String password,
  required String name,
  UserRole role = UserRole.USER, // ✅ 역할 선택 가능
})
```

#### 역할 전달
```dart
_currentUser = await _authService.signUp(
  email: email,
  password: password,
  name: name,
  role: role, // ✅ role 전달
);
```

---

## 📂 생성된 파일

### 1. register_screen.dart
**위치**: `/mnt/user-data/outputs/register_screen.dart`

**사용 방법**:
```bash
1. 기존 파일 백업:
   lib/screens/auth/register_screen.dart → register_screen.dart.backup

2. 새 파일 복사:
   outputs/register_screen.dart → lib/screens/auth/register_screen.dart
```

**주요 구성**:
- `_currentStep`: Stepper 현재 단계 (0 또는 1)
- `_selectedRole`: 선택된 역할 (USER 또는 BUSINESS_ADMIN)
- `_validateStep1()`: 기본 정보 유효성 검증
- `_validateStep2()`: 역할 선택 유효성 검증
- `_handleRegister()`: 회원가입 처리 및 분기
- `_buildRoleCard()`: 역할 선택 카드 위젯

---

### 2. user_provider.dart
**위치**: `/mnt/user-data/outputs/user_provider.dart`

**사용 방법**:
```bash
1. 기존 파일 백업:
   lib/providers/user_provider.dart → user_provider.dart.backup

2. 새 파일 복사:
   outputs/user_provider.dart → lib/providers/user_provider.dart
```

**변경 내용**:
- `signUp()` 메서드에 `role` 파라미터 추가
- 기본값은 `UserRole.USER`
- AuthService로 role 전달

---

## 🎨 UI/UX 특징

### 역할 선택 카드
```
┌─────────────────────────────────────┐
│ 🙋 일반 지원자                       │
│ TO에 지원하고 싶어요                 │
│                                ✓    │
├─────────────────────────────────────┤
│ ✓ TO 지원하기                       │
│ ✓ 내 지원 내역 확인                 │
│ ✓ 출퇴근 체크                       │
└─────────────────────────────────────┘
```

### 선택 시 시각적 피드백
- **선택 전**: 회색 테두리, 흰색 배경
- **선택 후**: 
  - 컬러 테두리 (파란색 또는 초록색)
  - 컬러 배경 (10% 투명도)
  - 체크 아이콘 표시
  - 그림자 효과

---

## 🔄 회원가입 플로우

### Case 1: 일반 지원자
```
1. Step 1: 기본 정보 입력
2. Step 2: "일반 지원자" 선택
3. "가입하기" 버튼 클릭
4. ✅ 회원가입 성공
5. → 로그인 화면으로 이동
6. 로그인 후 → UserHomeScreen
```

### Case 2: 사업장 관리자
```
1. Step 1: 기본 정보 입력
2. Step 2: "사업장 관리자" 선택
3. "가입하기" 버튼 클릭
4. ✅ 회원가입 성공
5. → BusinessRegistrationScreen으로 이동
6. 사업장 정보 입력
7. 사업장 등록 완료 → BusinessAdminHomeScreen
```

---

## 🧪 테스트 시나리오

### 테스트 1: 일반 지원자 회원가입
```
1. 회원가입 버튼 클릭
2. 기본 정보 입력 (이름, 이메일, 비밀번호)
3. "다음" 버튼 클릭
4. "일반 지원자" 카드 선택
5. "가입하기" 버튼 클릭
6. 확인: 로그인 화면으로 돌아감
7. 로그인
8. 확인: UserHomeScreen 표시
9. Firestore 확인: role = "USER"
```

### 테스트 2: 사업장 관리자 회원가입
```
1. 회원가입 버튼 클릭
2. 기본 정보 입력
3. "다음" 버튼 클릭
4. "사업장 관리자" 카드 선택
5. "가입하기" 버튼 클릭
6. 확인: BusinessRegistrationScreen 표시
7. 사업장 정보 입력 (업종, 이름, 주소 등)
8. 사업장 등록 완료
9. 확인: BusinessAdminHomeScreen 표시
10. Firestore 확인:
    - users 컬렉션: role = "BUSINESS_ADMIN", businessId = "xxx"
    - businesses 컬렉션: ownerId = 사용자 UID
```

### 테스트 3: 유효성 검증
```
1. Step 1에서 정보 미입력 시 → 에러 메시지 표시
2. 비밀번호 불일치 시 → 에러 메시지 표시
3. Step 2에서 역할 미선택 시 → SnackBar 경고
4. 중복 이메일 가입 시 → Firebase 에러 처리
```

---

## 📊 Firestore 데이터 구조

### users 컬렉션
```javascript
// 일반 지원자
{
  uid: "user_uid_123",
  name: "홍길동",
  email: "user@test.com",
  role: "USER",        // ✅
  businessId: null,
  createdAt: Timestamp,
  lastLoginAt: Timestamp
}

// 사업장 관리자
{
  uid: "admin_uid_456",
  name: "김사장",
  email: "admin@test.com",
  role: "BUSINESS_ADMIN",  // ✅
  businessId: "business_id_789",  // ✅
  createdAt: Timestamp,
  lastLoginAt: Timestamp
}
```

---

## 🎯 다음 단계 (Phase 6-2 Step 4)

### Step 4-1: 일반 사용자 홈 화면 수정
**파일**: `lib/screens/user/user_home_screen.dart`

**작업 내용**:
- ❌ "사업장 등록" 메뉴 제거
- ✅ 일반 사용자 전용 메뉴만 표시
  - TO 지원하기
  - 내 지원 내역
  - 출퇴근 체크
  - 내 정보
  - 설정

---

### Step 4-2: 사업장 관리자 홈 화면 생성 ⭐ 최우선!
**파일**: `lib/screens/admin/business_admin_home_screen.dart` (새로 생성)

**구조**:
```
AppBar
├─ 제목: "사업장 관리"
└─ Actions: 로그아웃 버튼

Body
├─ 사업장 정보 카드
│   ├─ 사업장명
│   ├─ 주소
│   └─ 수정 버튼
├─ 메뉴 그리드
│   ├─ TO 생성하기
│   ├─ 내 TO 관리
│   ├─ 지원자 관리
│   ├─ 통계
│   └─ 설정
```

---

### Step 4-3: main.dart 라우팅 수정
```dart
// main.dart
switch (user.role) {
  case UserRole.SUPER_ADMIN:
    return const SuperAdminHomeScreen();  // ✅ 나중에 만들기
  
  case UserRole.BUSINESS_ADMIN:
    return const BusinessAdminHomeScreen();  // ✅ Step 4-2에서 만들기
  
  case UserRole.USER:
    return const UserHomeScreen();  // ✅ Step 4-1에서 수정
  
  default:
    return const LoginScreen();
}
```

---

### Step 4-4: TO 생성 화면 수정
**파일**: `lib/screens/admin/admin_create_to_screen.dart`

**변경 사항**:
- ❌ 센터 선택 드롭다운 제거
- ✅ 자동으로 내 사업장 ID 사용
- ✅ 사업장명 자동 표시 (수정 불가)

---

## 💡 중요 참고 사항

### 1. BusinessRegistrationScreen import
```dart
import '../admin/business_registration_screen.dart';
```
- 회원가입 화면에서 사업장 등록 화면으로 이동하기 위해 필요
- 경로가 정확한지 확인 필요

### 2. 역할 분기 처리
```dart
if (_selectedRole == UserRole.BUSINESS_ADMIN) {
  // 사업장 등록 화면으로
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) => const BusinessRegistrationScreen(),
    ),
  );
} else {
  // 로그인 화면으로
  Navigator.pop(context);
}
```

### 3. 로딩 상태 관리
- `userProvider.isLoading`을 통한 로딩 표시
- 회원가입 중 중복 클릭 방지

---

## 🎉 Phase 6-2 Step 3 완료!

### 완료된 기능
- ✅ Stepper 기반 회원가입 UI
- ✅ 역할 선택 카드 UI
- ✅ 역할별 분기 처리
- ✅ UserProvider role 지원

### 다음 작업
- 🚧 Step 4-1: user_home_screen.dart 수정
- 🚧 Step 4-2: business_admin_home_screen.dart 생성 ⭐
- 🚧 Step 4-3: main.dart 라우팅 수정
- 🚧 Step 4-4: admin_create_to_screen.dart 수정

---

**📝 작성일**: 2025년 10월 22일  
**💾 파일명**: `PHASE_6-2_Step3_완료_보고서.md`  
**🔗 연관 문서**:
- `Phase_6_진행상황_및_다음단계.md`
- `PHASE_6-1_완료_보고서.md`
- `PHASE_6-2_Step1-2_완료_보고서.md`

**화이팅! 🚀**
