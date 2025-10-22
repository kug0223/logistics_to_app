# Phase 6-1: 권한 시스템 개편 완료 보고서 ✅

## 📅 작업 일시
2025년 10월 22일

---

## ✅ 완료된 작업

### 1. UserModel 개편 (`user_model.dart`)

#### 주요 변경사항
- ❌ `bool isAdmin` 제거
- ✅ `UserRole role` 추가 (enum 기반 권한 시스템)
- ✅ `String? businessId` 추가 (사업장 관리자용)

#### UserRole Enum
```dart
enum UserRole {
  SUPER_ADMIN,    // 슈퍼관리자 (플랫폼 운영자)
  BUSINESS_ADMIN, // 사업장 관리자 (사장님)
  USER            // 일반 사용자 (지원자)
}
```

#### 편의 메서드 추가
```dart
bool get isSuperAdmin      // 슈퍼관리자인지 확인
bool get isBusinessAdmin   // 사업장 관리자인지 확인
bool get isUser            // 일반 사용자인지 확인
bool get isAdmin           // 관리자 권한이 있는지 (슈퍼 또는 사업장)
```

#### 기존 데이터 호환성
- 기존 `isAdmin: true` 데이터는 자동으로 `SUPER_ADMIN`으로 변환
- 기존 `isAdmin: false` 데이터는 자동으로 `USER`로 변환

---

### 2. BusinessModel 신규 생성 (`business_model.dart`)

#### 사업장 데이터 구조
```dart
class BusinessModel {
  String id;              // 사업장 ID
  String name;            // 사업장명
  String category;        // 업종 카테고리 (회사/알바 매장/기타)
  String subCategory;     // 세부 업종
  String address;         // 주소
  double latitude;        // 위도
  double longitude;       // 경도
  String ownerId;         // 사업장 관리자 UID
  String? phone;          // 연락처 (선택)
  String? description;    // 설명 (선택)
  bool isApproved;        // 슈퍼관리자 승인 여부
  DateTime createdAt;
  DateTime? updatedAt;
}
```

#### 주요 메서드
- `fromMap()` - Firestore 데이터 → 모델 변환
- `toMap()` - 모델 → Firestore 데이터 변환
- `copyWith()` - 불변 객체 업데이트
- `approvalStatusText` - 승인 상태 텍스트

---

### 3. Constants 확장 (`constants.dart`)

#### 업종 카테고리 추가 (가치업 스타일)
```dart
static const Map<String, List<String>> jobCategories = {
  '회사': [
    '일반 회사',
    '제조, 생산, 건설',
  ],
  '알바 매장': [
    '알바-카페 (카페, 음료, 베이커리)',
    '알바-외식업 (음식, 외식업)',
    '알바-판매-서비스 (편의점, 유통, 호텔 등)',
    '알바-매장관리 (PC방, 스터디카페 등)',
  ],
  '기타': [
    '교육, 의료, 기관',
    '기타',
  ],
};
```

#### 새 컬렉션 상수 추가
```dart
static const String collectionBusinesses = 'businesses';
```

---

### 4. AuthService 개편 (`auth_service.dart`)

#### 회원가입 메서드 수정
```dart
Future<UserModel?> signUp({
  required String email,
  required String password,
  required String name,
  UserRole role = UserRole.USER,  // ✅ role 파라미터 추가
  String? businessId,             // ✅ businessId 파라미터 추가
})
```

#### 신규 메서드 추가
```dart
// 사업장 관리자 회원가입
Future<UserModel?> signUpBusinessAdmin({
  required String email,
  required String password,
  required String name,
  required String businessId,
})

// 사용자 권한 업데이트 (슈퍼관리자 전용)
Future<void> updateUserRole({
  required String uid,
  required UserRole role,
  String? businessId,
})
```

---

## 🔥 Firestore 데이터 구조 변경

### 기존 users 컬렉션
```javascript
{
  uid: string,
  name: string,
  email: string,
  isAdmin: boolean,  // ❌ 삭제됨
  createdAt: Timestamp,
  lastLoginAt: Timestamp
}
```

### 신규 users 컬렉션
```javascript
{
  uid: string,
  name: string,
  email: string,
  role: "SUPER_ADMIN" | "BUSINESS_ADMIN" | "USER",  // ✅ 추가
  businessId: string | null,  // ✅ 추가
  createdAt: Timestamp,
  lastLoginAt: Timestamp
}
```

### 신규 businesses 컬렉션
```javascript
{
  id: string,
  name: string,
  category: string,
  subCategory: string,
  address: string,
  latitude: double,
  longitude: double,
  ownerId: string,
  phone: string | null,
  description: string | null,
  isApproved: boolean,
  createdAt: Timestamp,
  updatedAt: Timestamp | null
}
```

---

## 📂 파일 위치

모든 수정된 파일은 `/mnt/user-data/outputs/`에 저장되어 있습니다:

1. ✅ `user_model.dart` - 권한 시스템 개편
2. ✅ `business_model.dart` - 사업장 모델 신규 생성
3. ✅ `constants.dart` - 업종 카테고리 추가
4. ✅ `auth_service.dart` - 회원가입/권한 관리 개편

---

## 🔄 마이그레이션 가이드

### 기존 코드에서 수정이 필요한 부분

#### 1. UserModel 사용 코드
```dart
// ❌ 기존 코드
if (user.isAdmin) {
  // 관리자 로직
}

// ✅ 새 코드
if (user.isAdmin) {  // 편의 메서드 사용 (추천)
  // 관리자 로직
}

// 또는

if (user.role == UserRole.SUPER_ADMIN) {
  // 슈퍼관리자 로직
} else if (user.role == UserRole.BUSINESS_ADMIN) {
  // 사업장 관리자 로직
}
```

#### 2. 회원가입 코드
```dart
// ❌ 기존 코드
await authService.signUp(
  email: email,
  password: password,
  name: name,
);

// ✅ 새 코드 (일반 사용자)
await authService.signUp(
  email: email,
  password: password,
  name: name,
  // role과 businessId는 기본값 사용
);

// ✅ 새 코드 (사업장 관리자)
await authService.signUpBusinessAdmin(
  email: email,
  password: password,
  name: name,
  businessId: businessId,
);
```

---

## 🚨 주의사항

### 1. 기존 데이터 호환성
- ✅ 기존 `isAdmin` 필드는 자동으로 `role`로 변환됨
- ✅ 기존 사용자는 다음 로그인 시 권한이 자동 마이그레이션됨
- ⚠️ Firestore에 저장된 기존 문서는 수동으로 업데이트하지 않아도 됨

### 2. 테스트 계정 권한
기존 테스트 계정은 다음과 같이 자동 변환됩니다:
- `admin@test.com` → `SUPER_ADMIN`
- `user@test.com` → `USER`

### 3. 코드 수정 필요 파일 목록
다음 화면들은 `user.isAdmin` 사용 → `user.isAdmin` 또는 `user.isSuperAdmin` 등으로 수정 필요:
- `main.dart` - 라우팅 로직
- `user_home_screen.dart` - 하단 네비게이션
- `center_list_screen.dart` - FAB 표시 조건
- `admin_home_screen.dart` - 슈퍼관리자 전용 기능
- 기타 관리자 권한 체크하는 모든 화면

---

## 🎯 다음 단계 (Phase 6-2)

### 사업장 관리 시스템 구현
1. ✅ BusinessModel 생성 완료
2. 🚧 사업장 등록 화면 (`BusinessRegistrationScreen`)
3. 🚧 업종 선택 카드 UI (가치업 스타일)
4. 🚧 사업장 목록 화면 (슈퍼관리자용)
5. 🚧 사업장 승인/거절 기능

---

## ✅ Phase 6-1 완료 체크리스트

- ✅ UserRole enum 정의
- ✅ UserModel 개편 (role, businessId 추가)
- ✅ BusinessModel 신규 생성
- ✅ Constants에 업종 카테고리 추가
- ✅ AuthService 개편 (role 기반 회원가입)
- ✅ 기존 데이터 호환성 확보
- ✅ 편의 메서드 추가 (isSuperAdmin, isBusinessAdmin 등)
- ✅ 문서화 완료

---

## 💡 개발자 노트

### 잘된 점
- ✅ 기존 `isAdmin` 방식의 한계 극복
- ✅ 3단계 권한 시스템으로 확장 가능
- ✅ 기존 데이터와의 호환성 유지
- ✅ 편의 메서드로 코드 가독성 향상

### 개선 필요 사항
- ⚠️ 기존 화면 코드 수정 필요 (user.isAdmin 사용 부분)
- ⚠️ 라우팅 로직 개편 필요 (3단계 권한 분기)
- ⚠️ Firestore Security Rules 업데이트 필요

---

**🎉 Phase 6-1 작업이 성공적으로 완료되었습니다!**

**다음 단계**: Phase 6-2 (사업장 관리 시스템 구현)로 진행하시겠습니까?
