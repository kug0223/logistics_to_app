# 물류센터 인력관리 앱 - 현재 개발 상태 (v2)

## 📅 최종 업데이트
2025년 10월 21일 (Flutter 대화3 완료)

---

## ✅ 완료된 기능

### Phase 1: TO 시스템 기본 구조 ✅

#### 1. 기본 구조
- ✅ Firebase 초기화 (Auth, Firestore)
- ✅ Provider 상태 관리 (`UserProvider`)
- ✅ 로그인/회원가입 시스템
- ✅ 관리자/일반 사용자 분리

#### 2. TO 시스템
- ✅ **센터 목록 화면** (`CenterListScreen`)
  - 송파/강남/서초 물류센터 카드
- ✅ **TO 목록 화면** (`TOListScreen`)
  - 날짜 필터 기능 (오늘/전체)
  - 센터별 TO 조회
  - Firestore 복합 쿼리 (`centerId` + `date` + `startTime`)
  - 내 지원 상태 표시 (ListView에 Key 추가로 실시간 반영)
- ✅ **TO 상세 화면** (`TODetailScreen`)
  - 센터 정보, 날짜, 시간, 업무 유형, 인원 현황
  - 내 지원 상태 실시간 체크
  - 지원하기 버튼
- ✅ **TO 카드 위젯** (`TOCardWidget`)
  - 지원 상태별 색상 배지 표시

#### 3. 지원 시스템
- ✅ **지원하기 기능** (`FirestoreService.applyToTO`)
  - 중복 지원 체크
  - **무조건 PENDING 상태로 저장** (자동 확정 없음)
  - 지원 완료 후 TO 목록으로 복귀 시 상태 반영
- ✅ **지원 상태 실시간 표시**
  - 🟢 **지원 가능** (초록색) - 아직 지원 안 함
  - 🟠 **지원 완료 (대기)** (주황색) - PENDING 상태
  - 🔵 **확정됨** (파란색) - CONFIRMED 상태
  - 🔴 **마감** (빨간색) - 인원이 다 참
- ✅ **TO 목록에서 내 지원 상태 표시**
  - `TOCardWidget`에 `applicationStatus` 전달
  - 지원 상태에 따라 배지 색상 변경

---

### Phase 2: 내 지원 내역 화면 ✅ **완료!**

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
- ✅ **대기 중인 TO 취소 기능**
  - `FirestoreService.cancelApplication` 구현
  - PENDING 상태만 취소 가능
  - CONFIRMED 상태는 취소 불가 (관리자 문의 안내)
  - 확인 다이얼로그 + 로딩 상태
- ✅ **빈 상태 처리**
  - 필터별 빈 상태 메시지
  - 아이콘 + 안내 문구

#### 2. UI 구성
- ✅ 상태별 FilterChip (파란색 선택 스타일)
- ✅ 지원 내역 카드
  - 상태별 색상 배지 (주황/초록/빨강/회색)
  - TO 정보 (센터명, 날짜, 시간, 업무, 인원)
  - 지원 일시 표시
  - 확정 일시 표시 (확정/거절 시)
  - 취소 버튼 (PENDING 상태만)
- ✅ RefreshIndicator (당겨서 새로고침)

---

### Phase 3: 관리자 기능 ✅ **완료!**

#### 1. 관리자 홈 화면 (`AdminHomeScreen`)
- ✅ **TO 목록 조회 + 지원자 통계**
  - 모든 TO 조회
  - 각 TO별 확정/대기 인원 통계
- ✅ **필터 시스템**
  - 날짜 필터 (오늘/전체)
  - 센터 필터 (전체/송파/강남/서초)
  - 상태 필터 (전체/미마감/마감)
- ✅ **TO 카드 표시**
  - 센터명 + 마감 여부 배지
  - 날짜, 시간, 업무 유형
  - 확정/대기/필요 인원 통계 (컴팩트 표시)

#### 2. 관리자 TO 상세 화면 (`AdminTODetailScreen`)
- ✅ **지원자 목록 조회**
  - `FirestoreService.getApplicantsWithUserInfo` 구현
  - 지원자 정보 + 사용자 정보 조인
  - 메모리에서 `appliedAt` 기준 정렬 (orderBy 제거로 인덱스 불필요)
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
  confirmedBy: string | null  // 관리자 UID
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
2. 중복 지원 체크 (같은 TO에 PENDING 또는 CONFIRMED 상태로 이미 지원했는지)
3. 무조건 PENDING 상태로 applications 컬렉션에 저장
4. 관리자가 수동으로 승인/거절
```

### 2. 지원 취소 로직
```
1. 사용자가 "지원 취소" 버튼 클릭
2. 본인 확인 (uid 체크)
3. CONFIRMED 상태면 취소 불가 (에러 메시지)
4. PENDING 상태만 CANCELED로 변경
```

### 3. 관리자 승인/거절 로직
```
1. 관리자가 승인/거절 버튼 클릭
2. 상태 확인 (이미 처리되었는지, 취소되었는지)
3. PENDING 상태만 처리 가능
4. CONFIRMED 또는 REJECTED로 변경 + confirmedAt, confirmedBy 저장
```

### 4. 시간 겹침 자동 취소 (예정)
```
- 사용자가 A TO 확정 (09:00-18:00)
- 같은 시간대 겹치는 다른 TO 지원 자동 취소
- 예: B TO (14:00-22:00) → 자동 취소
```

---

## 🐛 주요 버그 수정 내역

### Phase 1
- ✅ `UserProvider.currentUser` 사용 (`user` → `currentUser`)
- ✅ 지원 후 TO 목록 복귀 시 상태 반영 (`Navigator.pop(context, true)`)
- ✅ TO 카드 배지 빌드 로직 개선 (`applicationStatus` 우선 체크)
- ✅ ListView에 `ValueKey` 추가로 실시간 UI 반영

### Phase 2
- ✅ 빈 상태 메시지 필터별로 분기 처리
- ✅ 취소 버튼 조건부 렌더링 (PENDING만)
- ✅ CONFIRMED 취소 시도 시 명확한 에러 메시지

### Phase 3
- ✅ 관리자 지원자 목록에서 `orderBy` 제거 (메모리 정렬로 변경)
- ✅ Firestore 인덱스 요구사항 감소

---

## 💡 개발 팁

### 1. Provider 사용
```dart
final userProvider = Provider.of<UserProvider>(context, listen: false);
final uid = userProvider.currentUser?.uid;  // ⚠️ currentUser 사용!
```

### 2. Firestore 쿼리
```dart
// 복합 인덱스 필요
_firestore.collection('tos')
  .where('centerId', isEqualTo: centerId)
  .orderBy('date')
  .orderBy('startTime');

// 인덱스 불필요 (메모리 정렬)
final docs = snapshot.docs.toList()
  ..sort((a, b) {
    final aTime = (a.data()['appliedAt'] as Timestamp);
    final bTime = (b.data()['appliedAt'] as Timestamp);
    return aTime.compareTo(bTime);
  });
```

### 3. TO 카드에 지원 상태 전달
```dart
TOCardWidget(
  key: ValueKey('${to.id}-$applicationStatus'), // Key 추가!
  to: to,
  applicationStatus: applicationStatus, // 'PENDING', 'CONFIRMED', null
)
```

### 4. 지원 내역 + TO 정보 조인
```dart
class _ApplicationWithTO {
  final ApplicationModel application;
  final TOModel to;
}

// 사용 예시
final app = item.application;
final to = item.to;
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
```

---

## 📞 다음 개발 시 확인할 것

1. ✅ Phase 1, 2, 3 완료 상태 확인
2. ✅ Firestore 인덱스 2개 생성 확인
3. ✅ 테스트 계정으로 로그인
4. ✅ TO 지원 → 내 지원 내역 확인 → 취소 테스트
5. ✅ 관리자 로그인 → 지원자 목록 → 승인/거절 테스트

---

## 🎯 최종 목표 (로드맵)

1. **Phase 1**: TO 상세 + 지원하기 ✅ **완료!**
2. **Phase 2**: 내 지원 내역 화면 ✅ **완료!**
3. **Phase 3**: 관리자 지원자 관리 ✅ **완료!**
4. **Phase 4**: 시간 겹침 자동 취소 (다음)
5. **Phase 5**: FCM 푸시 알림
6. **Phase 6**: GPS 출퇴근 체크

---

## 🚧 다음 개발 예정 (Phase 4)

### 시간 겹침 자동 취소
- [ ] TO 확정 시 시간대 겹침 체크 로직
- [ ] 겹치는 PENDING 지원 자동 취소
- [ ] 사용자에게 취소 알림 (Toast 또는 푸시)

### 개선 사항
- [ ] 에러 핸들링 강화
- [ ] 오프라인 모드 지원
- [ ] 이미지 업로드 (프로필 사진)
- [ ] 통계 대시보드 (관리자)
- [ ] 다국어 지원

---

## 📦 파일 구조 요약

```
lib/
├── models/
│   ├── user_model.dart
│   ├── to_model.dart
│   └── application_model.dart
├── services/
│   ├── auth_service.dart
│   ├── firestore_service.dart        # ✅ 모든 CRUD 로직
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
│   │   ├── to_list_screen.dart       # ✅ Phase 1
│   │   ├── to_detail_screen.dart     # ✅ Phase 1
│   │   └── my_applications_screen.dart  # ✅ Phase 2
│   └── admin/
│       ├── admin_home_screen.dart    # ✅ Phase 3
│       └── admin_to_detail_screen.dart  # ✅ Phase 3
├── widgets/
│   ├── custom_button.dart
│   ├── loading_widget.dart
│   └── to_card_widget.dart           # ✅ Phase 1
└── utils/
    ├── constants.dart
    └── toast_helper.dart
```

---

## 🎉 Phase 1, 2, 3 완료 축하합니다!

현재까지 구현된 기능:
- ✅ 사용자 TO 지원 시스템
- ✅ 내 지원 내역 조회 및 취소
- ✅ 관리자 지원자 관리 (승인/거절)

다음 단계로 **시간 겹침 자동 취소** 또는 **FCM 푸시 알림**을 구현하면 됩니다!