# 물류센터 인력관리 앱 - 현재 개발 상태 (v4)

## 📅 최종 업데이트
2025년 10월 21일 (Flutter 대화5 완료)

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
  - **메모리에서 `appliedAt` 기준 정렬** (orderBy 제거로 인덱스 불필요)
- ✅ **상태별 지원자 분류**
  - ⏳ 대기 중 (PENDING)
  - ✅ 확정 (CONFIRMED)
  - ❌ 거절 (REJECTED)
  - 🚫 취소 (CANCELED)
- ✅ **지원자 카드**
  - 이름, 이메일, 지원 일시, 처리 일시
  - 상태별 색상 배지
  - 승인/거절 버튼 (PENDING 상태만)
- ✅ **지원자 승인 기능**
  - `FirestoreService.confirmApplicant` 구현
  - 확인 다이얼로그 + 로딩
  - CONFIRMED 상태로 변경 + `confirmedAt`, `confirmedBy` 저장
- ✅ **지원자 거절 기능**
  - `FirestoreService.rejectApplicant` 구현
  - 확인 다이얼로그 + 로딩
  - REJECTED 상태로 변경

---

### Phase 4: 관리자 TO 생성 기능 ✅ **NEW!**

#### 1. TO 생성 화면 (`AdminCreateTOScreen`)
- ✅ **입력 항목**
  - 센터 선택 (드롭다운)
  - 날짜 선택 (DatePicker, 오늘 이후만)
  - 시작/종료 시간 (30분 단위 드롭다운)
  - 업무 유형 (드롭다운 + 아이콘)
  - 필요 인원 (숫자 입력)
  - 설명 (텍스트, 선택사항)
- ✅ **유효성 검증**
  - 모든 필수 항목 체크
  - 종료 시간 > 시작 시간
  - 필요 인원 > 0
  - 과거 날짜 선택 불가
- ✅ **UI 디자인**
  - 보라색 테마 (관리자 색상)
  - 깔끔한 카드 디자인
  - 필수 항목 별표(*) 표시
  - 안내 카드
  - 로딩 상태 표시
- ✅ **Firestore 연동**
  - `FirestoreService.createTO` 메서드
  - 서버 타임스탬프 사용
  - 에러 핸들링

#### 2. 관리자 홈 연동
- ✅ **FloatingActionButton** (우측 하단 "TO 생성")
- ✅ TO 생성 후 목록 자동 새로고침
- ✅ 성공 토스트 메시지

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

#### 2. `tos/`
```javascript
{
  // 자동 생성 ID (문서 ID)
  centerId: "CENTER_A" | "CENTER_B" | "CENTER_C",
  centerName: string,       // "송파 물류센터", "강남 물류센터", "서초 물류센터"
  date: Timestamp,
  startTime: string,        // "09:00"
  endTime: string,          // "18:00"
  requiredCount: number,    // 필요 인원
  currentCount: number,     // 현재 지원 인원 (사용 안 함, 동적 계산)
  workType: string,         // "피킹", "패킹", "배송", "분류", "하역", "검수"
  description: string,      // 선택사항
  creatorUID: string,
  createdAt: Timestamp
}
```

#### 3. `applications/`
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

---

## 🎯 주요 비즈니스 로직

### 1. 지원하기 로직
```
1. 사용자가 "지원하기" 버튼 클릭
2. 중복 지원 체크
3. 무조건 PENDING 상태로 저장
4. 관리자가 수동으로 승인/거절
5. TO 상세 화면에서 뒤로가기 시 목록 자동 새로고침
```

### 2. 지원 취소 로직
```
1. 사용자가 "지원 취소" 버튼 클릭
2. CONFIRMED 상태면 취소 불가 (에러 메시지)
3. PENDING 상태만 CANCELED로 변경
4. 목록 자동 새로고침
```

### 3. 관리자 승인/거절 로직
```
1. 관리자가 승인/거절 버튼 클릭
2. PENDING 상태만 처리 가능
3. CONFIRMED 또는 REJECTED로 변경
4. 지원자 목록 자동 새로고침
```

### 4. TO 생성 로직
```
1. 관리자가 FloatingActionButton 클릭
2. TO 생성 화면으로 이동
3. 모든 필수 항목 입력
4. 유효성 검증 (시간, 인원 등)
5. Firestore에 TO 문서 생성
6. 관리자 홈으로 복귀 + 목록 새로고침
```

---

## 💡 개발 팁

### 1. Colors 사용 (중요!)
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

### 2. ApplicationModel.fromFirestore
```dart
// application_model.dart에 추가 필요
factory ApplicationModel.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  return ApplicationModel.fromMap(data, doc.id);
}
```

### 3. Constants 사용
```dart
// AppConstants에 추가된 항목들
AppConstants.centers        // 센터 목록
AppConstants.workTypes      // 업무 유형 목록
AppConstants.primaryColor   // 기본 색상
```

### 4. 시간 필터 로직
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
```

---

## 📞 다음 개발 시 확인할 것

1. ✅ Phase 1, 2, 3, 4 완료 상태 확인
2. ✅ Firestore 인덱스 2개 생성 확인
3. ✅ 테스트 계정으로 로그인
4. ✅ TO 지원 → 내 지원 내역 확인 → 취소 테스트
5. ✅ 관리자 로그인 → 필터 테스트 (날짜/센터/업무 유형)
6. ✅ 관리자 → TO 생성 → 목록 확인
7. ✅ 관리자 → 지원자 목록 → 승인/거절 테스트

---

## 🎯 프로젝트 현황

### ✅ 완료된 Phase
- **Phase 1**: TO 시스템 기본 구조 (3단계 필터) ✅
- **Phase 2**: 내 지원 내역 화면 ✅
- **Phase 3**: 관리자 지원자 관리 ✅
- **Phase 4**: 관리자 TO 생성 기능 ✅ **NEW!**

### 🚧 다음 개발 예정 (Phase 5)

#### 옵션 1: 시간 겹침 자동 취소
- [ ] TO 확정 시 시간대 겹침 체크 로직
- [ ] 겹치는 PENDING 지원 자동 취소
- [ ] 사용자에게 취소 알림 (Toast 또는 푸시)

#### 옵션 2: FCM 푸시 알림
- [ ] Firebase Cloud Messaging 설정
- [ ] 지원 확정/거절 시 푸시 알림
- [ ] 알림 권한 요청
- [ ] 알림 수신 처리

#### 옵션 3: GPS 출퇴근 체크
- [ ] LocationService 활용
- [ ] 출근 체크 화면
- [ ] 퇴근 체크 화면
- [ ] 센터 좌표 기반 범위 체크
- [ ] 출퇴근 기록 저장

#### 옵션 4: 통계 대시보드
- [ ] 관리자 통계 화면
- [ ] 센터별 TO 현황
- [ ] 지원자 참여율
- [ ] 차트/그래프 표시

---

## 📊 개선 사항 (백로그)

### UI/UX 개선
- [ ] 다크 모드 지원
- [ ] 애니메이션 추가
- [ ] 스켈레톤 로딩
- [ ] 에러 바운더리

### 기능 개선
- [ ] 오프라인 모드
- [ ] 이미지 업로드
- [ ] 근무 이력 조회
- [ ] 급여 계산

### 성능 개선
- [ ] 페이지네이션
- [ ] 이미지 캐싱
- [ ] Lazy Loading

### 보안 강화
- [ ] Firestore Security Rules 적용
- [ ] API 키 환경변수 분리
- [ ] Rate Limiting

---

## 📦 파일 구조 요약

```
lib/
├── models/
│   ├── user_model.dart
│   ├── to_model.dart
│   └── application_model.dart         # ✅ fromFirestore 추가됨
├── services/
│   ├── auth_service.dart
│   ├── firestore_service.dart         # ✅ createTO, getApplicationsByTOId 추가
│   └── location_service.dart
├── providers/
│   └── user_provider.dart
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   ├── user/
│   │   ├── user_home_screen.dart
│   │   ├── center_list_screen.dart
│   │   ├── to_list_screen.dart        # ✅ 3단계 필터 완성
│   │   ├── to_detail_screen.dart
│   │   └── my_applications_screen.dart
│   └── admin/
│       ├── admin_home_screen.dart     # ✅ FAB 추가, Colors 수정
│       ├── admin_to_detail_screen.dart
│       └── admin_create_to_screen.dart  # ✅ NEW!
├── widgets/
│   ├── custom_button.dart
│   ├── loading_widget.dart
│   └── to_card_widget.dart
├── utils/
│   ├── constants.dart                 # ✅ AppConstants 확장
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
- ✅ 관리자 TO 생성 기능 (NEW!)

### 다음 단계 추천
1. **시간 겹침 자동 취소** (UX 개선)
2. **FCM 푸시 알림** (사용자 참여도 향상)
3. **GPS 출퇴근 체크** (근태 관리)
4. **통계 대시보드** (관리자 의사결정 지원)

---

## 📝 변경 이력

### v4 (2025-10-21) - Phase 4 완료
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
- ✅ Phase 1, 2, 3 완료
- ✅ 병렬 쿼리 최적화

### v1 (2025-10-21)
- ✅ Phase 1 완료
- ✅ 기본 TO 시스템 구축

---

## 🐛 주요 해결된 이슈

### Phase 4 개발 중 발생한 이슈
1. ✅ `Colors.purple[700]` → `Colors.purple.shade700` 변경
2. ✅ `AppConstants.centers` 정의 안 됨 → constants.dart 확장
3. ✅ `ApplicationModel.fromFirestore` 없음 → factory 메서드 추가
4. ✅ `getApplicationsByTOId` 없음 → firestore_service.dart에 추가
5. ✅ Hot Reload 안 먹힘 → 완전 재시작 필요

---

**🚀 프로젝트는 안정적으로 작동하고 있으며, 다음 Phase로 진행할 준비가 되었습니다!**