# Flutter 물류센터 인력관리 앱 - 프로젝트 구조

## 📁 프로젝트 전체 구조

```
logistics_to_app/
├── lib/
│   ├── main.dart                    # 앱 진입점, Firebase 초기화, Provider 설정
│   ├── firebase_options.dart        # Firebase 설정 (Android, iOS, Web)
│   │
│   ├── models/                      # 데이터 모델
│   │   ├── user_model.dart          # 사용자 모델 (uid, name, email, isAdmin 등)
│   │   ├── to_model.dart            # TO(근무오더) 모델 (센터, 날짜, 시간, 인원 등)
│   │   └── application_model.dart   # 지원서 모델 (상태, 지원일시 등)
│   │
│   ├── services/                    # 비즈니스 로직 & Firebase 통신
│   │   ├── auth_service.dart        # Firebase 인증 (로그인, 회원가입, 로그아웃)
│   │   ├── firestore_service.dart   # Firestore CRUD (TO 조회/생성, 지원/취소)
│   │   └── location_service.dart    # GPS 위치 서비스 (권한, 현재위치, 거리계산)
│   │
│   ├── providers/                   # 상태 관리 (Provider 패턴)
│   │   └── user_provider.dart       # 사용자 상태 관리 (로그인 상태, 사용자 정보)
│   │
│   ├── screens/                     # UI 화면
│   │   ├── auth/
│   │   │   ├── login_screen.dart    # 로그인 화면 (이메일/비밀번호 입력)
│   │   │   └── register_screen.dart # 회원가입 화면 (이름/이메일/비밀번호)
│   │   ├── user/
│   │   │   ├── user_home_screen.dart    # 사용자 홈 (메뉴 카드: TO지원, 내역 등)
│   │   │   └── center_list_screen.dart  # 센터 목록 (송파/강남/서초)
│   │   └── admin/
│   │       └── admin_home_screen.dart   # 관리자 홈 (TO 관리 기능)
│   │
│   ├── widgets/                     # 재사용 가능한 위젯
│   │   ├── custom_button.dart       # 커스텀 버튼 (로딩, 아웃라인 지원)
│   │   └── loading_widget.dart      # 로딩 위젯 (애니메이션, 오버레이)
│   │
│   └── utils/                       # 유틸리티
│       ├── constants.dart           # 상수 (센터 목록, 색상, 상태 코드, API URL)
│       └── toast_helper.dart        # 토스트 메시지 (성공/에러/정보)
│
├── android/                         # Android 네이티브 설정
├── ios/                             # iOS 네이티브 설정
├── web/                             # Web 플랫폼 설정
├── pubspec.yaml                     # 패키지 의존성 관리
└── firebase.json                    # Firebase Hosting 설정
```

## 🔑 핵심 기능 구현 현황

### ✅ 완료된 기능
- **Firebase 초기화**: Android, iOS, Web 플랫폼 설정 완료
- **회원가입/로그인**: Firebase Authentication 연동
- **사용자 정보 저장**: Firestore에 사용자 데이터 저장
- **상태 관리**: Provider 패턴으로 전역 상태 관리
- **로그인/회원가입 UI**: Material Design 기반 폼 검증
- **사용자 홈 화면**: 환영 메시지, 메뉴 카드 레이아웃
- **센터 목록 화면**: 3개 물류센터 카드 표시

### ⏳ 다음 구현 예정
1. **TO 목록 화면**: Firestore에서 TO 데이터 실시간 조회
2. **TO 상세 & 지원**: 지원 버튼, 인원 현황 표시
3. **내 지원 내역**: 사용자별 지원 목록 조회
4. **관리자 TO 생성**: 날짜/시간/인원 입력 폼
5. **관리자 지원자 관리**: 승인/반려 기능
6. **GPS 출퇴근 체크**: 위치 기반 출퇴근 인증
7. **FCM 푸시 알림**: TO 확정/취소 알림

### 🚧 추가 개선 사항
- 에러 핸들링 강화
- 오프라인 모드 지원
- 이미지 업로드 (프로필 사진)
- 통계 대시보드 (관리자)
- 다국어 지원

## 📦 주요 패키지

```yaml
dependencies:
  # Firebase 핵심
  firebase_core: ^3.8.1           # Firebase 초기화
  firebase_auth: ^5.3.3           # 인증
  cloud_firestore: ^5.5.0         # NoSQL 데이터베이스
  firebase_messaging: ^15.1.5     # 푸시 알림
  
  # 상태 관리
  provider: ^6.1.2                # Provider 패턴
  
  # UI/UX
  cupertino_icons: ^1.0.8         # iOS 스타일 아이콘
  fluttertoast: ^8.2.8            # 토스트 메시지
  loading_animation_widget: ^1.2.1 # 로딩 애니메이션
  
  # 위치/GPS
  geolocator: ^13.0.2             # GPS 위치 정보
  permission_handler: ^11.3.1     # 권한 요청
  
  # 유틸리티
  intl: ^0.19.0                   # 날짜/시간 포맷팅
  http: ^1.2.2                    # HTTP 요청
```

## 🔥 Firebase 구조

### Firestore Collections

#### 1. `users/` - 사용자 정보
```
{
  uid: string (문서 ID와 동일)
  name: string
  email: string
  isAdmin: boolean (기본값: false)
  createdAt: Timestamp
  lastLoginAt: Timestamp
}
```

#### 2. `tos/` - TO(근무 오더)
```
{
  centerId: string (CENTER_A, CENTER_B, CENTER_C)
  centerName: string (송파 물류센터, 강남 물류센터, 서초 물류센터)
  date: Timestamp (근무 날짜)
  startTime: string (예: "09:00")
  endTime: string (예: "18:00")
  requiredCount: number (필요 인원)
  currentCount: number (현재 지원 인원)
  workType: string (업무 유형: 피킹, 패킹, 배송 등)
  description: string (선택사항)
  creatorUID: string (생성한 관리자 UID)
  createdAt: Timestamp
}
```

#### 3. `applications/` - 지원서
```
{
  recordId: string (문서 ID와 동일)
  toId: string (지원한 TO의 ID)
  uid: string (지원자 UID)
  status: string (PENDING, CONFIRMED, REJECTED, CANCELED)
  appliedAt: Timestamp (지원 시각)
  confirmedAt: Timestamp | null (확정 시각)
  confirmedBy: string | null (확정한 사람: SYSTEM 또는 관리자 UID)
}
```

### Firebase Authentication
- **인증 방식**: 이메일/비밀번호
- **세션 지속성**: LOCAL (브라우저/앱 재시작 후에도 로그인 유지)

### Firebase Cloud Functions (기존 웹앱 백엔드)
- `getUserByUID`: UID로 사용자 정보 조회
- `updateLastLogin`: 마지막 로그인 시간 업데이트
- `registerUser`: 회원가입 시 Firestore에 사용자 저장
- `getTOsByDateAndCenter`: 날짜/센터별 TO 조회
- `applyToTO`: TO 지원 처리 (자동 확정 또는 대기)
- `cancelApplication`: 지원 취소
- `confirmApplicant`: 관리자의 지원자 승인
- `rejectApplicant`: 관리자의 지원자 반려

## 🎨 UI/UX 디자인 패턴

### 디자인 시스템
- **테마**: Material Design 3
- **주 색상**: Blue (#2563EB)
- **배경색**: Grey 50 (#FAFAFA)
- **폰트**: 시스템 기본 폰트

### 컴포넌트
- **CustomButton**: 로딩 상태, 아웃라인 스타일 지원
- **LoadingWidget**: 애니메이션 스피너 + 메시지
- **LoadingOverlay**: 전체 화면 로딩 오버레이

### 네비게이션
- **로그인 전**: LoginScreen ↔ RegisterScreen
- **로그인 후**:
  - 일반 사용자: UserHomeScreen → CenterListScreen → (TO List)
  - 관리자: AdminHomeScreen → (TO Management)

### 상태 표시
- 로딩: CircularProgressIndicator + 애니메이션
- 성공: 초록색 Toast
- 에러: 빨간색 Toast
- 정보: 파란색 Toast

## 📱 지원 플랫폼

### ✅ Android
- **minSdkVersion**: 21 (Android 5.0)
- **targetSdkVersion**: 34 (Android 14)
- **권한**: 위치, 알림

### ✅ iOS
- **최소 버전**: iOS 12.0
- **권한**: 위치, 알림

### ✅ Web
- **브라우저**: Chrome, Safari, Edge
- **PWA 지원 가능**

## 🔐 보안 고려사항

### 현재 구현
- Firebase Authentication으로 사용자 인증
- UID 기반 데이터 접근 제어

### 추가 필요
- **Firestore Security Rules** 강화
  ```javascript
  // 예시: 사용자는 본인 데이터만 읽기/쓰기
  match /users/{userId} {
    allow read, write: if request.auth.uid == userId;
  }
  
  // 예시: TO는 모두 읽기 가능, 관리자만 쓰기
  match /tos/{toId} {
    allow read: if request.auth != null;
    allow write: if get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
  }
  ```

- **API 키 보호**: firebase_options.dart는 Git에 커밋하지 않기 (또는 환경변수 사용)
- **입력 검증**: 클라이언트 + 서버 양쪽 검증
- **Rate Limiting**: 과도한 API 호출 방지

## 🚀 배포 전략

### 개발 환경
- Web: `flutter run -d web-server`
- Android: `flutter run` (에뮬레이터 또는 실제 기기)
- iOS: `flutter run` (시뮬레이터 또는 실제 기기, Mac 필요)

### 프로덕션 빌드
```bash
# Android APK
flutter build apk --release

# iOS (Mac에서만)
flutter build ios --release

# Web
flutter build web --release
```

### Firebase Hosting (Web 배포)
```bash
firebase deploy --only hosting
```

## 🧪 테스트 계획

### 단위 테스트
- 모델 클래스 (toMap, fromMap)
- 서비스 클래스 로직

### 통합 테스트
- Firebase 연동 테스트
- 로그인/회원가입 플로우

### UI 테스트
- 화면 전환
- 폼 검증
- 버튼 동작

## 📊 성능 최적화

### 목표
- 1만명 이상 동시 사용자 지원

### 전략
1. **Firestore 쿼리 최적화**
   - 복합 인덱스 생성
   - 페이지네이션 구현
   - 불필요한 데이터 조회 최소화

2. **캐싱**
   - Provider로 메모리 캐싱
   - 자주 조회하는 데이터 캐시

3. **이미지 최적화**
   - 압축 및 리사이징
   - CDN 활용

4. **네트워크**
   - HTTP/2 사용
   - 배치 요청

## 🔄 버전 관리

- **현재 버전**: 1.0.0+1
- **Semantic Versioning**: MAJOR.MINOR.PATCH+BUILD

## 📝 다음 개발 우선순위

1. ⭐ **TO 목록 화면** (가장 중요!)
2. ⭐ **TO 지원 기능**
3. ⭐ **내 지원 내역**
4. 관리자 TO 생성
5. GPS 출퇴근
6. 푸시 알림

## 🤝 협업 정보

- **개발 도구**: VSCode, Android Studio
- **버전 관리**: Git
- **이슈 트래킹**: (필요시 GitHub Issues)
- **문서화**: 이 파일 + 코드 주석
