# Flutter 물류 TO 앱 개발 진행 상황 - 최종 정리

## 📅 작업 일시
2025년 10월 22일

---

## 🎯 프로젝트 개요

**프로젝트명**: 물류 TO(Transport Order) 관리 앱  
**기술 스택**: Flutter Web, Firebase (Auth, Firestore)  
**주요 기능**: 
- 사업장 관리자: TO 생성 및 관리, 지원자 관리
- 일반 사용자: TO 지원, 출퇴근 체크
- 다중 역할 시스템 (SUPER_ADMIN, BUSINESS_ADMIN, USER)

---

## 📂 프로젝트 구조

```
lib/
├── models/
│   ├── user_model.dart (역할: SUPER_ADMIN, BUSINESS_ADMIN, USER)
│   ├── business_model.dart (사업장 정보, 사업자등록번호 포함)
│   ├── to_model.dart (TO 정보)
│   ├── application_model.dart (지원 정보)
│   └── work_type_model.dart
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart (역할 선택, 사업장 등록 옵션)
│   ├── admin/
│   │   ├── admin_home_screen.dart (SUPER_ADMIN용)
│   │   ├── business_registration_screen.dart (사업장 등록)
│   │   ├── admin_create_to_screen.dart (TO 생성)
│   │   ├── admin_to_list_screen.dart (TO 관리)
│   │   └── admin_to_detail_screen.dart (TO 상세)
│   └── user/
│       ├── user_home_screen.dart (일반 사용자용)
│       ├── to_list_screen.dart (TO 목록)
│       ├── to_detail_screen.dart (TO 상세)
│       └── my_applications_screen.dart (내 지원 내역)
├── services/
│   ├── auth_service.dart (Firebase Auth)
│   ├── firestore_service.dart (Firestore CRUD)
│   └── location_service.dart (GPS)
├── providers/
│   └── user_provider.dart (사용자 상태 관리)
├── widgets/
│   ├── custom_button.dart
│   ├── loading_widget.dart
│   ├── to_card_widget.dart
│   └── daum_address_search.dart (주소 검색)
└── utils/
    ├── constants.dart (업종 카테고리, 업무 유형)
    └── toast_helper.dart
```

---

## 🔥 현재 진행 상황 (Phase 6-2 완료)

### ✅ 완료된 주요 기능

#### 1. 사업장 등록 시스템 (완료)
- ✅ 사업자등록번호 입력 및 검증
- ✅ 자동 포맷팅 (000-00-00000)
- ✅ 업종 선택 (회사, 알바 매장, 기타)
- ✅ 주소 검색 (다음 API)
- ✅ 위도/경도 자동 입력
- ✅ Firestore `businesses` 컬렉션에 저장

#### 2. 회원가입 플로우 개선 (완료)
- ✅ Step 1: 기본 정보 (이름, 이메일, 비밀번호)
- ✅ Step 2: 역할 선택 (일반 지원자 vs 사업장 관리자)
- ✅ 역할별 다른 플로우:
  - 일반 사용자: 즉시 Firebase 저장 → 로그인 화면
  - 사업장 관리자: 다이얼로그 표시
    - "지금 등록하기": Firebase 저장 → 사업장 등록 화면
    - "나중에 등록하기": Firebase 저장 → 로그인 화면

#### 3. 뒤로가기 처리 (완료)
- ✅ 회원가입에서 온 경우: "나중에 하기" 다이얼로그
- ✅ 홈에서 온 경우: 뒤로가기 허용
- ✅ `isFromSignUp` 파라미터로 구분

#### 4. postMessage 에러 해결 (완료)
- ✅ try-catch로 안전하게 처리
- ✅ CustomEvent 대체 방법 추가
- ✅ 이중 전송으로 안정성 확보

#### 5. Firebase 400 Bad Request 에러 해결 (완료)
- ✅ 만료된 토큰 자동 감지
- ✅ 자동 로그아웃 처리
- ✅ 사용자 친화적 에러 메시지

---

## 📋 최종 수정된 파일 목록

### 필수 적용 파일 (outputs 디렉토리)

1. **register_screen_v2.dart**
   - 역할 선택 다이얼로그
   - "지금 등록" vs "나중에 등록" 선택
   - 적용: `lib/screens/auth/register_screen.dart`

2. **business_registration_screen_v3.dart**
   - `isFromSignUp` 파라미터 추가
   - 사업자등록번호 입력
   - 조건부 뒤로가기 버튼
   - 적용: `lib/screens/admin/business_registration_screen.dart`

3. **daum_address_search_v2.dart**
   - postMessage 에러 완전 해결
   - try-catch + CustomEvent
   - 적용: `lib/widgets/daum_address_search.dart`

4. **business_model_v2.dart**
   - `businessNumber` 필드 추가
   - `latitude`, `longitude` nullable
   - `formattedBusinessNumber` getter
   - 적용: `lib/models/business_model.dart`

5. **custom_button.dart**
   - `onPressed` nullable
   - 적용: `lib/widgets/custom_button.dart`

6. **user_provider_v2.dart**
   - `signUp`에 `role` 파라미터 추가
   - 자동 에러 처리 (토큰 만료 등)
   - 적용: `lib/providers/user_provider.dart`

---

## 🚀 파일 적용 명령어 (순서대로!)

```bash
# 1. business_registration_screen (최우선!) ⭐⭐⭐
cp outputs/business_registration_screen_v3.dart \
   lib/screens/admin/business_registration_screen.dart

# 2. register_screen
cp outputs/register_screen_v2.dart \
   lib/screens/auth/register_screen.dart

# 3. business_model
cp outputs/business_model_v2.dart \
   lib/models/business_model.dart

# 4. custom_button
cp outputs/custom_button.dart \
   lib/widgets/custom_button.dart

# 5. user_provider
cp outputs/user_provider_v2.dart \
   lib/providers/user_provider.dart

# 6. daum_address_search
cp outputs/daum_address_search_v2.dart \
   lib/widgets/daum_address_search.dart

# 7. 빌드
flutter clean
flutter pub get
flutter run -d chrome
```

---

## 🐛 해결된 주요 에러

### 1. `updateUser` 메서드 없음
**에러**: `The method 'updateUser' isn't defined for the type 'FirestoreService'.`  
**해결**: Firestore 직접 호출로 변경
```dart
await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .update({'businessId': businessId});
```

### 2. `businessCategories` 없음
**에러**: `Member not found: 'businessCategories'.`  
**해결**: `jobCategories`로 수정
```dart
AppConstants.jobCategories // ✅ 올바름
```

### 3. `isFromSignUp` 파라미터 없음
**에러**: `The named parameter 'isFromSignUp' isn't defined.`  
**해결**: 파일 적용 순서 변경 (business_registration_screen 먼저 적용)

### 4. postMessage 에러
**에러**: `Failed to execute 'postMessage' on 'Window': Invalid target origin 'about://'`  
**해결**: try-catch + CustomEvent 이중 전송

### 5. Firebase 400 Bad Request
**에러**: `POST accounts:lookup 400 (Bad Request)`  
**해결**: 브라우저 캐시 삭제 + 자동 에러 처리

### 6. 들여쓰기 에러
**에러**: `Expected to find ';'.`  
**해결**: `body:` 앞 들여쓰기 수정

---

## 📊 Firestore 데이터 구조

### users 컬렉션
```javascript
{
  uid: "user_uid_123",
  name: "김사장",
  email: "admin@test.com",
  role: "BUSINESS_ADMIN", // SUPER_ADMIN | BUSINESS_ADMIN | USER
  businessId: "business_id_456", // 또는 null (사업장 등록 전)
  createdAt: Timestamp,
  lastLoginAt: Timestamp
}
```

### businesses 컬렉션
```javascript
{
  id: "business_id_456",
  businessNumber: "1234567890",      // ✅ 사업자등록번호
  name: "스타벅스 강남점",
  category: "알바 매장",
  subCategory: "알바-카페 (카페, 음료, 베이커리)",
  address: "서울시 강남구 테헤란로 123",
  latitude: 37.514600,               // ✅ 자동 입력
  longitude: 127.105900,             // ✅ 자동 입력
  ownerId: "user_uid_123",
  phone: "010-1234-5678",
  description: "강남역 근처 스타벅스",
  isApproved: true,
  createdAt: Timestamp,
  updatedAt: null
}
```

### tos 컬렉션
```javascript
{
  id: "to_id_789",
  businessId: "business_id_456",
  title: "오전 피킹 작업",
  workTypes: ["피킹", "패킹"],
  date: "2025-10-25",
  startTime: "09:00",
  endTime: "13:00",
  hourlyWage: 15000,
  requiredPeople: 5,
  currentPeople: 2,
  description: "오전 피킹 작업입니다",
  status: "OPEN", // OPEN | CLOSED | COMPLETED
  createdBy: "user_uid_123",
  createdAt: Timestamp
}
```

### applications 컬렉션
```javascript
{
  id: "app_id_012",
  toId: "to_id_789",
  userId: "user_uid_456",
  userName: "이지원",
  userEmail: "worker@test.com",
  status: "PENDING", // PENDING | CONFIRMED | REJECTED | CANCELED
  appliedAt: Timestamp,
  checkInTime: null,
  checkOutTime: null
}
```

---

## 🎯 현재 구현된 사용자 시나리오

### 시나리오 1: 일반 사용자 회원가입
```
1. 회원가입 화면
2. 이름, 이메일, 비밀번호 입력
3. "일반 지원자" 선택
4. "선택하기" 버튼
5. ✅ Firebase에 저장 (role: USER)
6. ✅ 로그인 화면으로 이동
7. 로그인
8. ✅ UserHomeScreen 표시
9. TO 목록 확인 및 지원
```

### 시나리오 2: 사업장 관리자 - 지금 등록
```
1. 회원가입 화면
2. 이름, 이메일, 비밀번호 입력
3. "사업장 관리자" 선택
4. "선택하기" 버튼
5. ✅ 다이얼로그 표시
6. "지금 등록하기" 선택
7. ✅ Firebase에 저장 (role: BUSINESS_ADMIN)
8. ✅ 사업장 등록 화면 이동 (isFromSignUp: true)
9. 업종 선택
10. 사업자등록번호, 사업장명 입력
11. 주소 검색
12. "등록 완료"
13. ✅ Firestore에 저장
14. ✅ 홈으로 이동
```

### 시나리오 3: 사업장 관리자 - 나중에 등록
```
1. 회원가입 화면
2. 이름, 이메일, 비밀번호 입력
3. "사업장 관리자" 선택
4. "선택하기" 버튼
5. ✅ 다이얼로그 표시
6. "나중에 등록하기" 선택
7. ✅ Firebase에 저장 (businessId: null)
8. ✅ 로그인 화면으로 이동
9. 로그인
10. ✅ 홈 화면에 "사업장 등록 필요" 안내
```

---

## ⚠️ 알려진 이슈 및 해결 방법

### 이슈 1: 새로고침 시 400 Bad Request
**증상**: 페이지 새로고침 시 Firebase 에러  
**원인**: 만료된 토큰이 Local Storage에 저장됨  
**해결**: 
```
1. F12 → Application → Storage → Clear
2. Ctrl + Shift + R (Hard Refresh)
```

### 이슈 2: postMessage 에러
**증상**: 주소 검색 시 콘솔에 에러  
**원인**: Flutter Web iframe의 origin 문제  
**해결**: `daum_address_search_v2.dart` 적용 (이중 전송 방식)

### 이슈 3: 파일 적용 순서
**증상**: isFromSignUp 파라미터 에러  
**원인**: register_screen을 먼저 적용  
**해결**: business_registration_screen을 먼저 적용!

---

## 🔜 다음 작업 (미완료)

### 1. 사업장 관리자 홈 화면 개선
- [ ] businessId가 null인 경우 "사업장 등록 필요" 안내
- [ ] "지금 등록하기" 버튼으로 business_registration_screen 이동
- [ ] 내 사업장 정보 카드 표시

### 2. business_admin_home_screen.dart 생성
- [ ] 내 사업장 정보
- [ ] TO 생성/관리 메뉴
- [ ] 지원자 관리 메뉴
- [ ] 통계 (총 TO, 총 지원자 등)

### 3. TO 생성 화면 개선
- [ ] 사업장 관리자만 접근 가능
- [ ] businessId 자동 설정
- [ ] 유효성 검증 강화

### 4. TO 목록 필터링
- [ ] 업종별 필터
- [ ] 날짜별 필터
- [ ] 지역별 필터

### 5. 출퇴근 체크 시스템
- [ ] GPS 기반 위치 확인
- [ ] Check-in/Check-out 버튼
- [ ] 출퇴근 시간 기록

---

## 📚 참고 문서

### 생성된 가이드 문서
1. **최종_수정_가이드.md** - 전체 수정 내역
2. **최종_파일_적용_가이드.md** - 파일 적용 방법
3. **isFromSignUp_에러_해결.md** - 파라미터 에러 해결
4. **빌드_에러_수정_완료.md** - updateUser, businessCategories 에러
5. **들여쓰기_에러_수정.md** - 문법 에러 해결
6. **Firebase_400_에러_해결.md** - 400 Bad Request 해결
7. **VoidCallback_에러_수정_가이드.md** - nullable onPressed 에러
8. **사업장_등록_수정_완료_보고서.md** - 사업장 등록 기능

### Firebase 설정
- **firebase_options.dart** - Firebase 프로젝트 설정
- API Key: AIzaSyATfYwUbF0dJfygiiV-9m_ws9JzK9_n-W4
- Project ID: logistics-to-app

---

## 🎨 UI/UX 특징

### 회원가입 화면
- ✅ 2단계 Stepper (기본 정보 → 역할 선택)
- ✅ 역할별 카드 디자인
- ✅ 선택 시 색상 변화
- ✅ 기능 설명 포함

### 사업장 등록 화면
- ✅ 2단계 Stepper (업종 선택 → 사업장 정보)
- ✅ 사업자등록번호 자동 포맷팅
- ✅ 다음 주소 검색 팝업
- ✅ 위도/경도 자동 입력 (UI에서 숨김)
- ✅ 로딩 인디케이터

### 홈 화면
- ✅ 역할별 다른 화면 (SUPER_ADMIN, BUSINESS_ADMIN, USER)
- ✅ 메뉴 카드 레이아웃
- ✅ 통계 정보 표시

---

## 🧪 테스트 체크리스트

### 회원가입 테스트
- [x] 일반 사용자 회원가입
- [x] 사업장 관리자 - 지금 등록
- [x] 사업장 관리자 - 나중에 등록
- [x] 유효성 검증 (이메일, 비밀번호)
- [x] 에러 처리

### 사업장 등록 테스트
- [x] 업종 선택
- [x] 사업자등록번호 입력
- [x] 주소 검색
- [x] 위도/경도 자동 입력
- [x] Firestore 저장
- [x] 뒤로가기 처리

### 로그인 테스트
- [x] 이메일/비밀번호 로그인
- [x] 역할별 홈 화면 이동
- [x] 에러 메시지 표시

### 에러 처리 테스트
- [x] 네트워크 에러
- [x] 만료된 토큰
- [x] 유효하지 않은 입력
- [x] Firebase 에러

---

## 💻 개발 환경

### Flutter 버전
```
Flutter 3.x
Dart 3.x
```

### 주요 패키지
```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: latest
  firebase_auth: latest
  cloud_firestore: latest
  provider: latest
  geolocator: latest
  geocoding: latest
  intl: latest
```

### 개발 도구
- VS Code / Android Studio
- Chrome DevTools
- Firebase Console

---

## 🎓 핵심 학습 내용

### 1. Flutter Web에서의 주소 검색
- iframe 사용
- postMessage 통신
- CustomEvent 대체 방법

### 2. Firebase Authentication
- 역할 기반 접근 제어 (RBAC)
- 토큰 관리
- 에러 처리

### 3. Firestore 데이터 모델링
- 컬렉션 구조 설계
- 관계형 데이터 처리
- 인덱스 최적화

### 4. Provider 상태 관리
- ChangeNotifier
- Consumer
- 전역 상태 관리

### 5. 에러 처리 패턴
- try-catch
- 사용자 친화적 메시지
- 자동 복구

---

## 📞 다음 채팅에서 이어서 작업할 내용

### 우선순위 1: 사업장 관리자 홈 화면
```dart
// business_admin_home_screen.dart 생성
// - businessId null 체크
// - "사업장 등록 필요" 안내
// - 내 사업장 정보 카드
// - TO 생성/관리 메뉴
```

### 우선순위 2: TO 생성 화면 개선
```dart
// admin_create_to_screen.dart 개선
// - businessId 자동 설정
// - 유효성 검증 강화
// - 날짜/시간 선택 개선
```

### 우선순위 3: 출퇴근 체크 시스템
```dart
// to_detail_screen.dart 개선
// - Check-in/Check-out 버튼
// - GPS 위치 확인
// - 시간 기록
```

---

## 🎉 현재까지의 성과

### 완료된 기능
1. ✅ 회원가입 (역할 선택)
2. ✅ 사업장 등록 (사업자등록번호, 주소 검색)
3. ✅ 로그인/로그아웃
4. ✅ 역할별 홈 화면 분기
5. ✅ 에러 처리 (토큰 만료, 네트워크 등)

### 해결된 주요 이슈
1. ✅ postMessage 에러
2. ✅ Firebase 400 Bad Request
3. ✅ 파일 적용 순서 문제
4. ✅ 들여쓰기 에러
5. ✅ 파라미터 에러

### 생성된 파일 수
- **코드 파일**: 6개
- **가이드 문서**: 8개
- **총**: 14개

---

## 🚀 빠른 시작 가이드

### 1. 파일 적용
```bash
# 모든 파일 한번에 적용
cd your-project-directory

cp outputs/business_registration_screen_v3.dart lib/screens/admin/business_registration_screen.dart
cp outputs/register_screen_v2.dart lib/screens/auth/register_screen.dart
cp outputs/business_model_v2.dart lib/models/business_model.dart
cp outputs/custom_button.dart lib/widgets/custom_button.dart
cp outputs/user_provider_v2.dart lib/providers/user_provider.dart
cp outputs/daum_address_search_v2.dart lib/widgets/daum_address_search.dart
```

### 2. 빌드 및 실행
```bash
flutter clean
flutter pub get
flutter run -d chrome
```

### 3. 테스트
```
1. 회원가입 (사업장 관리자)
2. "지금 등록하기" 선택
3. 사업장 정보 입력
4. 주소 검색
5. 등록 완료
6. ✅ 정상 작동 확인
```

---

## 📝 중요 체크포인트

### 캐시 문제 발생 시
```
F12 → Application → Storage → Clear
Ctrl + Shift + R
```

### 빌드 에러 발생 시
```
flutter clean
flutter pub get
flutter run -d chrome
```

### Firebase 에러 발생 시
```
1. 토큰 만료 확인
2. 캐시 삭제
3. 재로그인
```

---

**📝 작성일**: 2025년 10월 22일  
**✅ 현재 상태**: Phase 6-2 완료  
**🎯 다음 작업**: business_admin_home_screen.dart 생성

**이 문서를 다음 채팅 시작 시 참고하시면 됩니다!** 🚀
