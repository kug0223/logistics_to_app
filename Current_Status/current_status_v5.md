# 물류센터 인력관리 앱 - 현재 개발 상태 (v5)

## 📅 최종 업데이트
2025년 10월 22일 (Flutter 대화7 완료)

---

## ✅ 완료된 기능

### Phase 1: TO 시스템 기본 구조 ✅

#### 1. 기본 구조
- ✅ Firebase 초기화 (Auth, Firestore, Web 포함)
- ✅ Provider 상태 관리 (`UserProvider`)
- ✅ 로그인/회원가입 시스템
- ✅ 관리자/일반 사용자 분리

#### 2. TO 시스템
- ✅ **센터 목록 화면** (`CenterListScreen`)
  - 송파/강남/서초 물류센터 카드
  - 그라디언트 디자인 + 아이콘
- ✅ **TO 목록 화면** (`TOListScreen`)
  - **3단계 필터**: 날짜/업무 유형/시간
  - **날짜 필터**: 오늘/3일/7일/전체/날짜 선택
  - **업무 유형 필터**: 전체/피킹/패킹/배송/분류/하역/검수
  - **시간 필터**: 시작/종료 시간 (30분 단위)
  - 날짜 범위 표시 (예: 2025.10.21 - 2025.10.24)
  - 과거 날짜 자동 제외
  - 내 지원 상태 실시간 반영
  - 병렬 쿼리로 성능 개선
- ✅ **TO 상세 화면** (`TODetailScreen`)
  - 센터 정보, 날짜, 시간, 업무 유형, 인원 현황
  - 내 지원 상태 실시간 체크
  - 지원하기 버튼 (상태별 비활성화)
  - WillPopScope로 뒤로가기 시 지원 상태 전달
- ✅ **TO 카드 위젯** (`TOCardWidget`)
  - 지원 상태별 색상 배지 표시
  - 날짜/시간/업무/인원 정보 표시

#### 3. 지원 시스템
- ✅ **지원하기 기능** (`FirestoreService.applyToTO`)
  - 중복 지원 체크
  - **무조건 PENDING 상태로 저장** (관리자 승인 대기)
  - 지원 완료 후 TO 목록으로 복귀 시 상태 반영
- ✅ **지원 상태 실시간 표시**
  - 🟢 **지원 가능** (초록색) - 아직 지원 안 함
  - 🟠 **지원 완료 (대기)** (주황색) - PENDING 상태
  - 🔵 **확정됨** (파란색) - CONFIRMED 상태
  - 🔴 **마감** (빨간색) - 인원이 다 참
- ✅ **TO 목록에서 내 지원 상태 표시**
  - `TOCardWidget`에 `applicationStatus` 전달
  - ValueKey로 ListView 아이템 추적
  - 지원 후 자동 UI 업데이트

---

### Phase 2: 내 지원 내역 화면 ✅

#### 1. 내 지원 내역 화면 (`MyApplicationsScreen`)
- ✅ **내가 지원한 TO 목록 조회**
  - `FirestoreService.getMyApplications(uid)` 구현
  - Firestore 쿼리: `applications` 컬렉션에서 `uid` 필터링
  - `appliedAt` 기준 내림차순 정렬
- ✅ **지원 내역 + TO 정보 조인**
  - 각 application의 `toId`로 TO 문서 조회
  - `_ApplicationWithTO` 클래스로 데이터 결합
- ✅ **상태별 필터링**
  - 전체 / 대기 중 / 확정 / 거절 / 취소
  - FilterChip으로 UI 구현
  - 파란색 선택 스타일
- ✅ **대기 중인 TO 취소 기능**
  - `FirestoreService.cancelApplication` 구현
  - PENDING 상태만 취소 가능
  - CONFIRMED 상태는 취소 불가 (관리자 문의 안내)
  - 확인 다이얼로그 + 로딩 상태
- ✅ **빈 상태 처리**
  - 필터별 빈 상태 메시지
  - 아이콘 + 안내 문구
- ✅ **RefreshIndicator** (당겨서 새로고침)

#### 2. UI 구성
- ✅ 상태별 FilterChip
- ✅ 지원 내역 카드
  - 상태별 색상 배지 (주황/초록/빨강/회색)
  - TO 정보 (센터명, 날짜, 시간, 업무, 인원)
  - 지원 일시 표시 (HH:mm 포맷)
  - 확정 일시 표시 (확정/거절 시)
  - 취소 버튼 (PENDING 상태만)

---

### Phase 3: 관리자 기능 ✅

#### 1. 관리자 홈 화면 (`AdminHomeScreen`)
- ✅ **TO 목록 조회 + 지원자 통계**
  - 모든 TO 조회
  - 각 TO별 확정/대기 인원 통계
  - **병렬 쿼리로 성능 최적화** (Future.wait 사용)
- ✅ **3단계 필터 시스템**
  - **날짜 필터**: 오늘/전체/날짜 선택
  - **센터 필터**: 전체/송파/강남/서초
  - **업무 유형 필터**: 전체/피킹/패킹/배송/분류/하역/검수 (Wrap으로 자동 줄바꿈)
- ✅ **TO 카드 표시**
  - 센터명 + 마감 여부 배지
  - 날짜, 시간, 업무 유형
  - 컴팩트 통계 표시 (확정/대기/필요 인원)
  - 보라색 테마

#### 2. 관리자 TO 상세 화면 (`AdminTODetailScreen`)
- ✅ **지원자 목록 조회**
  - `FirestoreService.getApplicantsWithUserInfo` 구현
  - 지원자 정보 + 사용자 정보 조인
  - 메모리에서 `appliedAt` 기준 정렬
- ✅ **상태별 지원자 분류**
  - ⏳ 대기 중 (PENDING)
  - ✅ 확정 (CONFIRMED)
  - ❌ 거절 (REJECTED)
  - 🚫 취소 (CANCELED)
- ✅ **지원자 카드**
  - 이름, 이메일, 지원 일시, 처리 일시
  - 상태별 색상 배지
  - 승인/거절 버튼 (PENDING 상태만)
- ✅ **지원자 승인/거절 기능**
  - `confirmApplicant`, `rejectApplicant` 구현
  - 확인 다이얼로그 + 로딩
  - 상태 변경 + 타임스탬프 기록

#### 3. 관리자 TO 생성 화면 (`AdminCreateTOScreen`)
- ✅ **FloatingActionButton으로 진입**
- ✅ **입력 폼**
  - 센터 선택 (드롭다운)
  - 날짜 선택 (DatePicker)
  - 시작/종료 시간 선택 (TimePicker)
  - 업무 유형 선택 (드롭다운)
  - 필요 인원 입력 (숫자)
  - 설명 입력 (선택사항)
- ✅ **유효성 검증**
  - 모든 필수 항목 입력 확인
  - 시작 시간 < 종료 시간 체크
  - 필요 인원 > 0 체크
- ✅ **TO 생성 로직**
  - `FirestoreService.createTO` 구현
  - Firestore에 TO 문서 생성
  - 생성 완료 후 관리자 홈으로 복귀

---

### Phase 4: 센터 관리 시스템 ✅ **NEW!**

#### 1. 센터 목록 화면 (`CenterListScreen`)
- ✅ **관리자 전용 FloatingActionButton 추가**
  - 관리자만 센터 추가 버튼 표시
  - 일반 사용자에게는 숨김
- ✅ **센터 카드 수정**
  - Edit 버튼 추가 (관리자만 표시)
  - 편집 화면으로 이동

#### 2. 센터 등록 화면 (`CenterFormScreen`)
- ✅ **센터 추가 모드**
  - 새 센터 등록
  - 센터명, 주소, 좌표 입력
  - Daum 우편번호 API 연동 (WebView 사용)
- ✅ **센터 수정 모드**
  - 기존 센터 정보 수정
  - 센터 삭제 기능
- ✅ **Daum 주소 검색**
  - `DaumAddressSearch` 위젯 구현
  - WebView로 Daum Postcode API 호출
  - JavaScript 통신으로 주소 데이터 수신
  - 선택한 주소 자동 입력
- ✅ **유효성 검증**
  - 센터명 필수 입력
  - 주소 필수 입력
  - 위도/경도 필수 입력 (소수점 형식 체크)

#### 3. 센터 관리 서비스 (`FirestoreService`)
- ✅ **센터 CRUD 메서드**
  - `createCenter()` - 센터 생성
  - `updateCenter()` - 센터 수정
  - `deleteCenter()` - 센터 삭제
  - `getCenters()` - 센터 목록 조회
- ✅ **센터 데이터 실시간 동기화**
  - StreamBuilder로 센터 목록 실시간 갱신
  - 센터 추가/수정/삭제 시 즉시 반영

#### 4. 센터 모델 (`CenterModel`)
- ✅ **데이터 구조**
  ```dart
  - id: String (문서 ID)
  - name: String (센터명)
  - address: String (주소)
  - latitude: double (위도)
  - longitude: double (경도)
  - createdAt: Timestamp (생성일)
  - updatedAt: Timestamp (수정일)
  ```
- ✅ **JSON 직렬화**
  - `toMap()`, `fromMap()` 구현
  - Firestore 연동

---

## 🔥 Firestore 데이터 구조

### Collections

#### 1. `users/`
```javascript
{
  uid: string,              // 문서 ID
  name: string,
  email: string,
  isAdmin: boolean,
  createdAt: Timestamp,
  lastLoginAt: Timestamp
}
```

#### 2. `centers/` ✅ **NEW!**
```javascript
{
  // 자동 생성 ID (문서 ID)
  name: string,             // "송파 물류센터"
  address: string,          // "서울시 송파구 ..."
  latitude: double,         // 37.5146
  longitude: double,        // 127.1059
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

#### 3. `tos/`
```javascript
{
  // 자동 생성 ID (문서 ID)
  centerId: string,         // centers 컬렉션의 문서 ID
  centerName: string,       // "송파 물류센터"
  date: Timestamp,
  startTime: string,        // "09:00"
  endTime: string,          // "18:00"
  requiredCount: number,    // 필요 인원
  currentCount: number,     // 현재 지원 인원 (동적 계산, 사용 안 함)
  workType: string,         // "피킹", "패킹", "배송", "분류", "하역", "검수"
  description: string,      // 선택사항
  creatorUID: string,
  createdAt: Timestamp
}
```

#### 4. `applications/`
```javascript
{
  // 자동 생성 ID (문서 ID)
  toId: string,             // 지원한 TO 문서 ID
  uid: string,              // 지원자 UID
  status: "PENDING" | "CONFIRMED" | "REJECTED" | "CANCELED",
  appliedAt: Timestamp,
  confirmedAt: Timestamp | null,
  confirmedBy: string | null  // 관리자 UID 또는 "SYSTEM"
}
```

---

## 📊 Firestore 인덱스

### ⚠️ 필요한 인덱스 (Firebase Console에서 생성)

#### 인덱스 1: TO 조회용
- **Collection**: `tos`
- **Fields**:
  - `centerId` (Ascending)
  - `date` (Ascending)
  - `startTime` (Ascending)

#### 인덱스 2: 지원 내역 조회용
- **Collection**: `applications`
- **Fields**:
  - `uid` (Ascending)
  - `appliedAt` (Descending)

**✅ 관리자 지원자 목록은 인덱스 불필요** (메모리에서 정렬)

---

## 🔐 Firestore 보안 규칙

**현재 상태:** 개발용 (모든 인증된 사용자 읽기/쓰기 가능)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

**⚠️ 프로덕션 배포 전 반드시 상세 규칙으로 변경 필요!**

```javascript
// 프로덕션용 예시 (추후 적용)
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 사용자는 자신의 문서만 읽기/쓰기
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // 센터는 모든 인증된 사용자가 읽기 가능, 관리자만 쓰기
    match /centers/{centerId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
    }
    
    // TO는 모든 인증된 사용자가 읽기 가능, 관리자만 쓰기
    match /tos/{toId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
    }
    
    // 지원 내역은 본인 것만 읽기 가능, 본인과 관리자만 쓰기
    match /applications/{applicationId} {
      allow read: if request.auth != null && 
                     (resource.data.uid == request.auth.uid || 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true);
      allow create: if request.auth != null && request.resource.data.uid == request.auth.uid;
      allow update, delete: if request.auth != null && 
                               (resource.data.uid == request.auth.uid || 
                                get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true);
    }
  }
}
```

---

## 🎯 주요 비즈니스 로직

### 1. 센터 등록 로직 ✅ **NEW!**
```
1. 관리자가 센터 목록에서 + 버튼 클릭
2. 센터 등록 화면으로 이동
3. 센터명 입력
4. "주소 검색" 버튼 클릭 → Daum 주소 검색 WebView 표시
5. 주소 선택 → 자동으로 주소 입력
6. 위도/경도 수동 입력 (추후 자동 변환 기능 추가 예정)
7. "등록하기" 버튼 클릭
8. Firestore centers 컬렉션에 문서 생성
9. 센터 목록으로 복귀 (실시간 갱신)
```

### 2. 센터 수정 로직 ✅ **NEW!**
```
1. 관리자가 센터 카드에서 "Edit" 버튼 클릭
2. 센터 수정 화면으로 이동 (기존 정보 자동 입력)
3. 센터명, 주소, 좌표 수정
4. "수정하기" 버튼 클릭
5. Firestore centers 컬렉션 문서 업데이트
6. 센터 목록으로 복귀 (실시간 갱신)
```

### 3. 센터 삭제 로직 ✅ **NEW!**
```
1. 센터 수정 화면에서 "센터 삭제" 버튼 클릭
2. 확인 다이얼로그 표시
3. 확인 시 Firestore centers 컬렉션 문서 삭제
4. ⚠️ 주의: 관련된 TO 데이터는 남아있음 (고아 데이터 발생 가능)
5. 센터 목록으로 복귀 (실시간 갱신)
```

### 4. 지원하기 로직
```
1. 사용자가 "지원하기" 버튼 클릭
2. 중복 지원 체크
3. 무조건 PENDING 상태로 저장
4. 관리자가 수동으로 승인/거절
5. TO 상세 화면에서 뒤로가기 시 목록 자동 새로고침
```

### 5. 지원 취소 로직
```
1. 사용자가 "지원 취소" 버튼 클릭
2. CONFIRMED 상태면 취소 불가 (에러 메시지)
3. PENDING 상태만 CANCELED로 변경
4. 목록 자동 새로고침
```

### 6. 관리자 승인/거절 로직
```
1. 관리자가 승인/거절 버튼 클릭
2. PENDING 상태만 처리 가능
3. CONFIRMED 또는 REJECTED로 변경
4. 지원자 목록 자동 새로고침
```

### 7. TO 생성 로직
```
1. 관리자가 FloatingActionButton 클릭
2. TO 생성 화면으로 이동
3. 센터 선택 (Firestore에서 실시간 센터 목록 조회)
4. 모든 필수 항목 입력
5. 유효성 검증 (시간, 인원 등)
6. Firestore에 TO 문서 생성 (centerId 저장)
7. 관리자 홈으로 복귀 + 목록 새로고침
```

---

## 💡 개발 팁

### 1. WebView 사용 (Daum 주소 API)
```dart
// webview_flutter 패키지 설치 필요
WebViewController _controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..addJavaScriptChannel(
    'AddressChannel',
    onMessageReceived: (JavaScriptMessage message) {
      // 주소 데이터 수신
      final data = jsonDecode(message.message);
      setState(() {
        _addressController.text = data['address'];
      });
    },
  )
  ..loadRequest(Uri.parse('https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js'));
```

### 2. 센터 목록 실시간 갱신
```dart
// StreamBuilder 사용
StreamBuilder<QuerySnapshot>(
  stream: _firestore.collection('centers').snapshots(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return LoadingWidget();
    
    final centers = snapshot.data!.docs
      .map((doc) => CenterModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
      .toList();
    
    return ListView.builder(...);
  },
)
```

### 3. Colors 사용 (중요!)
```dart
// ❌ 에러 발생
Colors.purple[700]
Colors.red[300]

// ✅ 올바른 사용
Colors.purple.shade700
Colors.red.shade300

// ✅ Color 타입일 때 (shade 없음)
color  // 그냥 사용
color.withOpacity(0.5)  // 투명도만 조절
```

### 4. ApplicationModel.fromFirestore
```dart
// application_model.dart에 추가 필요
factory ApplicationModel.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  return ApplicationModel.fromMap(data, doc.id);
}
```

### 5. Constants 사용
```dart
// AppConstants에 추가된 항목들
AppConstants.centers        // 센터 목록 (deprecated - Firestore에서 동적 로드)
AppConstants.workTypes      // 업무 유형 목록
AppConstants.primaryColor   // 기본 색상
```

### 6. 시간 필터 로직
```dart
// 시작 시간만: TO 시작 시간 ≥ 설정 시간
if (_startTime != null && _endTime == null) {
  return toStartTime.compareTo(_startTime!) >= 0;
}

// 종료 시간만: TO 종료 시간 ≤ 설정 시간
if (_startTime == null && _endTime != null) {
  return toEndTime.compareTo(_endTime!) <= 0;
}

// 둘 다: 범위 내
if (_startTime != null && _endTime != null) {
  return toStartTime.compareTo(_startTime!) >= 0 && 
         toEndTime.compareTo(_endTime!) <= 0;
}
```

---

## 📱 테스트 계정

### 관리자
- 이메일: `admin@test.com`
- 비밀번호: `admin123!@#`

### 일반 사용자
- 이메일: `user@test.com`
- 비밀번호: `user123!@#`

---

## 🚀 실행 방법

```bash
# Web 서버 모드 (추천)
flutter run -d web-server

# Chrome 직접 실행
flutter run -d chrome

# Edge 실행
flutter run -d edge

# Android 에뮬레이터
flutter run

# iOS 시뮬레이터 (Mac에서만)
flutter run -d ios
```

---

## 📦 주요 패키지 버전

```yaml
dependencies:
  firebase_core: ^3.8.1
  firebase_auth: ^5.3.3
  cloud_firestore: ^5.5.0
  firebase_messaging: ^15.1.5
  provider: ^6.1.2
  fluttertoast: ^8.2.8
  loading_animation_widget: ^1.2.1
  geolocator: ^13.0.2
  permission_handler: ^11.3.1
  intl: ^0.19.0
  http: ^1.2.2
  webview_flutter: ^4.9.0  # ✅ NEW! (Daum 주소 검색용)
```

---

## 📞 다음 개발 시 확인할 것

1. ✅ Phase 1, 2, 3, 4 완료 상태 확인
2. ✅ Firestore 인덱스 2개 생성 확인
3. ✅ 테스트 계정으로 로그인
4. ✅ 센터 목록 → 관리자로 센터 추가/수정/삭제 테스트 **NEW!**
5. ✅ Daum 주소 검색 API 동작 확인 **NEW!**
6. ✅ TO 지원 → 내 지원 내역 확인 → 취소 테스트
7. ✅ 관리자 로그인 → 필터 테스트 (날짜/센터/업무 유형)
8. ✅ 관리자 → TO 생성 → 센터 선택 드롭다운에 실시간 센터 목록 표시 확인 **NEW!**
9. ✅ 관리자 → 지원자 목록 → 승인/거절 테스트

---

## 🎯 프로젝트 현황

### ✅ 완료된 Phase
- **Phase 1**: TO 시스템 기본 구조 (3단계 필터) ✅
- **Phase 2**: 내 지원 내역 화면 ✅
- **Phase 3**: 관리자 지원자 관리 ✅
- **Phase 4**: 센터 관리 시스템 (CRUD + Daum 주소 검색) ✅ **NEW!**

### 🚧 다음 개발 예정 (Phase 5)

#### 옵션 1: 주소 → 좌표 자동 변환 ⭐ **우선순위 높음**
- [ ] Kakao Map API 연동
- [ ] 주소 입력 시 자동으로 위도/경도 가져오기
- [ ] `geocode` API 사용
- [ ] 센터 등록 시 위도/경도 자동 입력

#### 옵션 2: 시간 겹침 자동 취소
- [ ] TO 확정 시 시간대 겹침 체크 로직
- [ ] 겹치는 PENDING 지원 자동 취소
- [ ] 사용자에게 취소 알림 (Toast 또는 푸시)

#### 옵션 3: FCM 푸시 알림
- [ ] Firebase Cloud Messaging 설정
- [ ] 지원 확정/거절 시 푸시 알림
- [ ] 알림 권한 요청
- [ ] 알림 수신 처리

#### 옵션 4: GPS 출퇴근 체크
- [ ] LocationService 활용
- [ ] 출근 체크 화면
- [ ] 퇴근 체크 화면
- [ ] 센터 좌표 기반 범위 체크
- [ ] 출퇴근 기록 저장

#### 옵션 5: 통계 대시보드
- [ ] 관리자 통계 화면
- [ ] 센터별 TO 현황
- [ ] 지원자 참여율
- [ ] 차트/그래프 표시

#### 옵션 6: 센터 삭제 시 관련 TO 정리
- [ ] 센터 삭제 시 관련 TO 자동 삭제 또는 경고
- [ ] CASCADE DELETE 또는 RESTRICT 로직
- [ ] 고아 데이터 방지

---

## 📊 개선 사항 (백로그)

### UI/UX 개선
- [ ] 다크 모드 지원
- [ ] 애니메이션 추가
- [ ] 스켈레톤 로딩
- [ ] 에러 바운더리
- [ ] 센터 목록에 지도 미리보기 추가

### 기능 개선
- [ ] 오프라인 모드
- [ ] 이미지 업로드 (센터 사진, 프로필 사진)
- [ ] 근무 이력 조회
- [ ] 급여 계산
- [ ] 센터 검색 기능
- [ ] 센터 즐겨찾기 기능

### 성능 개선
- [ ] 페이지네이션
- [ ] 이미지 캐싱
- [ ] Lazy Loading
- [ ] 센터 목록 캐싱

### 보안 강화
- [ ] Firestore Security Rules 적용
- [ ] API 키 환경변수 분리
- [ ] Rate Limiting
- [ ] 센터 수정/삭제 권한 검증 강화

---

## 📦 파일 구조 요약

```
lib/
├── models/
│   ├── user_model.dart
│   ├── center_model.dart              # ✅ NEW!
│   ├── to_model.dart
│   ├── application_model.dart
│   └── work_type_model.dart
├── services/
│   ├── auth_service.dart
│   ├── firestore_service.dart         # ✅ 센터 CRUD 메서드 추가
│   └── location_service.dart
├── providers/
│   └── user_provider.dart
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   ├── user/
│   │   ├── user_home_screen.dart
│   │   ├── center_list_screen.dart    # ✅ FAB + Edit 버튼 추가
│   │   ├── to_list_screen.dart
│   │   ├── to_detail_screen.dart
│   │   └── my_applications_screen.dart
│   └── admin/
│       ├── admin_home_screen.dart
│       ├── admin_to_detail_screen.dart
│       ├── admin_create_to_screen.dart
│       ├── center_form_screen.dart    # ✅ NEW! (센터 등록/수정)
│       └── center_management_screen.dart  # (미사용, 삭제 예정)
├── widgets/
│   ├── custom_button.dart
│   ├── loading_widget.dart
│   ├── to_card_widget.dart
│   └── daum_address_search.dart       # ✅ NEW! (Daum 주소 검색)
├── utils/
│   ├── constants.dart
│   └── toast_helper.dart
├── firebase_options.dart
└── main.dart
```

---

## 🎉 Phase 4 완료 축하합니다!

### 현재까지 구현된 기능
- ✅ 사용자 TO 지원 시스템 (3단계 필터)
- ✅ 내 지원 내역 조회 및 취소
- ✅ 관리자 지원자 관리 (승인/거절)
- ✅ 관리자 TO 생성 기능
- ✅ 센터 관리 시스템 (CRUD + Daum 주소 검색) **NEW!**

### 다음 단계 추천
1. **주소 → 좌표 자동 변환** (Kakao Map API) ⭐ **우선순위 높음**
2. **시간 겹침 자동 취소** (UX 개선)
3. **FCM 푸시 알림** (사용자 참여도 향상)
4. **GPS 출퇴근 체크** (근태 관리)
5. **통계 대시보드** (관리자 의사결정 지원)

---

## 📝 변경 이력

### v5 (2025-10-22) - Phase 4 완료 (센터 관리 시스템)
- ✅ 센터 CRUD 시스템 구현
- ✅ Daum 우편번호 API 연동 (WebView)
- ✅ `CenterModel` 추가
- ✅ `CenterFormScreen` 추가 (센터 등록/수정)
- ✅ `DaumAddressSearch` 위젯 추가
- ✅ FirestoreService에 센터 관리 메서드 추가
- ✅ 센터 목록 실시간 동기화 (StreamBuilder)
- ✅ 관리자 전용 센터 관리 권한
- ✅ TO 생성 시 센터 선택 드롭다운 동적 로드

### v4 (2025-10-21) - Phase 3 완료
- ✅ 관리자 TO 생성 화면 추가
- ✅ FloatingActionButton으로 TO 생성 진입
- ✅ FirestoreService.createTO 메서드 구현
- ✅ ApplicationModel.fromFirestore 메서드 추가
- ✅ AppConstants에 centers, workTypes 추가
- ✅ Colors.shade 방식으로 색상 사용 통일
- ✅ 사용자 TO 목록 3단계 필터 완성 (날짜/업무/시간)

### v3 (2025-10-21)
- ✅ 관리자 홈 화면에 업무 유형 필터 추가
- ✅ 사용자 TO 목록에 시간 필터 추가 (30분 단위)

### v2 (2025-10-21)
- ✅ Phase 1, 2 완료
- ✅ 병렬 쿼리 최적화

### v1 (2025-10-21)
- ✅ Phase 1 완료
- ✅ 기본 TO 시스템 구축

---

## 🐛 주요 해결된 이슈

### Phase 4 개발 중 발생한 이슈
1. ✅ WebView에서 JavaScript 통신 설정
   - `addJavaScriptChannel` 사용
   - `JavaScriptMode.unrestricted` 설정
2. ✅ 센터 목록 실시간 갱신
   - StreamBuilder로 변경
   - 센터 추가/수정/삭제 시 자동 새로고침
3. ✅ TO 생성 시 센터 선택 드롭다운 동적 로드
   - Firestore에서 실시간 센터 목록 조회
   - 센터 추가 시 즉시 드롭다운에 반영
4. ✅ Daum 주소 API CORS 문제
   - WebView 사용으로 해결
   - iframe 대신 전체 페이지 로드
5. ✅ 센터 삭제 시 관련 TO 데이터 처리
   - 현재: 경고 메시지만 표시
   - 추후: CASCADE DELETE 또는 RESTRICT 로직 추가 필요

### Phase 3 개발 중 발생한 이슈
1. ✅ `Colors.purple[700]` → `Colors.purple.shade700` 변경
2. ✅ `AppConstants.centers` 정의 안 됨 → constants.dart 확장
3. ✅ `ApplicationModel.fromFirestore` 없음 → factory 메서드 추가
4. ✅ `getApplicationsByTOId` 없음 → firestore_service.dart에 추가
5. ✅ Hot Reload 안 먹힘 → 완전 재시작 필요

---

## 🚀 Phase 5 개발 방향 논의

### 1. 주소 → 좌표 자동 변환 (⭐ 추천)
**목적**: 센터 등록 시 수동으로 위도/경도 입력하는 불편함 해소

**구현 방안**:
- Kakao Map REST API 사용
- Daum 주소 검색 후 자동으로 좌표 변환
- API 키는 환경변수로 분리

**장점**:
- 사용자 편의성 대폭 향상
- 좌표 입력 오류 방지
- GPS 출퇴근 체크 기능의 기반 마련

**예상 작업 시간**: 2-3시간

---

### 2. 시간 겹침 자동 취소
**목적**: 사용자가 이미 확정된 TO와 시간이 겹치는 다른 TO에 지원할 수 없도록 함

**구현 방안**:
- TO 확정 시 해당 사용자의 다른 PENDING 지원 조회
- 시간대 겹침 체크 로직 구현
- 겹치는 지원 자동 CANCELED 처리
- Toast 알림

**장점**:
- 이중 근무 방지
- 스케줄 관리 자동화

**예상 작업 시간**: 3-4시간

---

### 3. FCM 푸시 알림
**목적**: 지원 확정/거절 시 사용자에게 실시간 알림

**구현 방안**:
- Firebase Cloud Messaging 설정
- 알림 권한 요청
- 관리자가 승인/거절 시 FCM 메시지 전송
- 앱 내 알림 처리

**장점**:
- 사용자 참여도 향상
- 실시간 정보 전달

**예상 작업 시간**: 4-5시간

---

### 4. GPS 출퇴근 체크
**목적**: 센터 반경 내에서만 출퇴근 체크 가능

**구현 방안**:
- LocationService 활용
- 출근/퇴근 체크 화면
- 센터 좌표 기반 거리 계산
- 출퇴근 기록 Firestore 저장

**장점**:
- 근태 관리 자동화
- 부정 출퇴근 방지

**예상 작업 시간**: 5-6시간

---

### 5. 통계 대시보드
**목적**: 관리자가 센터별 TO 현황과 지원자 참여율을 한눈에 파악

**구현 방안**:
- 센터별 TO 개수, 확정률 통계
- 지원자별 참여율 통계
- 차트 라이브러리 사용 (fl_chart)
- 날짜별 필터링

**장점**:
- 데이터 기반 의사결정
- 센터별 인력 배치 최적화

**예상 작업 시간**: 6-8시간

---

## 💬 개발자 메모

### 잘된 점
- ✅ 센터 관리 시스템 구현으로 동적 센터 추가 가능
- ✅ Daum 주소 API 연동으로 사용자 편의성 향상
- ✅ StreamBuilder로 실시간 데이터 동기화 구현
- ✅ 관리자/일반 사용자 권한 분리 명확

### 개선 필요 사항
- ⚠️ 센터 삭제 시 관련 TO 데이터 정리 로직 필요
- ⚠️ 주소 입력 후 자동 좌표 변환 기능 추가 필요
- ⚠️ Firestore Security Rules 적용 필요
- ⚠️ 에러 핸들링 강화 필요
- ⚠️ 오프라인 모드 지원 필요

### 다음 개발 우선순위
1. **주소 → 좌표 자동 변환** (Kakao Map API) ⭐
2. **시간 겹침 자동 취소**
3. **FCM 푸시 알림**

---

**🚀 프로젝트는 안정적으로 작동하고 있으며, Phase 5로 진행할 준비가 되었습니다!**

**💡 다음 단계로 "주소 → 좌표 자동 변환" 기능을 구현하면 사용자 편의성이 크게 향상될 것입니다!**
