# 물류센터 인력관리 앱 - 현재 개발 상태

## 📅 최종 업데이트
2025년 10월 21일

## ✅ 완료된 기능 (Phase 1)

### 1. 기본 구조
- ✅ Firebase 초기화 (Auth, Firestore)
- ✅ Provider 상태 관리
- ✅ 로그인/회원가입 시스템
- ✅ 관리자/일반 사용자 분리

### 2. TO 시스템
- ✅ 센터 목록 화면 (송파/강남/서초)
- ✅ TO 목록 화면 (날짜 필터 기능)
- ✅ TO 상세 화면
- ✅ TO 카드 위젯 (지원 상태별 색상 표시)

### 3. 지원 시스템
- ✅ 지원하기 기능 (무조건 PENDING 상태)
- ✅ 중복 지원 체크
- ✅ 지원 상태 실시간 표시
- ✅ TO 목록에서 내 지원 상태 표시
  - 🟢 지원 가능 (초록색)
  - 🟠 지원 완료 (대기) (주황색)
  - 🔵 확정됨 (파란색)
  - 🔴 마감 (빨간색)

---

## 🚧 다음 개발 예정 (Phase 2)

### 내 지원 내역 화면
- [ ] 내가 지원한 TO 목록 조회
- [ ] 상태별 필터/정렬
- [ ] TO 정보와 함께 표시
- [ ] 대기 중인 TO 취소 기능

---

## 🔥 Firestore 데이터 구조

### Collections

#### 1. `users/`
```
{
  uid: string (문서 ID)
  name: string
  email: string
  isAdmin: boolean
  createdAt: Timestamp
  lastLoginAt: Timestamp
}
```

#### 2. `tos/`
```
{
  centerId: "CENTER_A" | "CENTER_B" | "CENTER_C"
  centerName: string
  date: Timestamp
  startTime: string (예: "09:00")
  endTime: string (예: "18:00")
  requiredCount: number
  currentCount: number
  workType: string (피킹/패킹/배송/분류/하역/검수)
  description: string (optional)
  creatorUID: string
  createdAt: Timestamp
}
```

#### 3. `applications/`
```
{
  toId: string (TO 문서 ID)
  uid: string (지원자 UID)
  status: "PENDING" | "CONFIRMED" | "REJECTED" | "CANCELED"
  appliedAt: Timestamp
  confirmedAt: Timestamp | null
  confirmedBy: string | null
}
```

---

## 📊 Firestore 인덱스 (필수!)

### 인덱스 1: TO 조회용
- Collection: `tos`
- Fields:
  - `centerId` (ascending)
  - `date` (ascending)
  - `startTime` (ascending)

### 인덱스 2: 지원 내역 조회용
- Collection: `applications`
- Fields:
  - `uid` (ascending)
  - `appliedAt` (descending)

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

**⚠️ 프로덕션 배포 전 상세 규칙으로 변경 필요!**

---

## 🎯 주요 비즈니스 로직

### 지원하기 로직
1. 사용자가 "지원하기" 클릭
2. 중복 지원 체크 (같은 TO에 이미 지원했는지)
3. **무조건 PENDING 상태로 저장** (자동 확정 없음)
4. 관리자가 수동으로 확정/거절

### 시간 겹침 자동 취소 (예정)
- 사용자가 A TO 확정 (09:00-18:00)
- 같은 시간대 겹치는 다른 TO 지원 자동 취소
- 예: B TO (14:00-22:00) → 자동 취소

---

## 🐛 알려진 이슈
없음 (현재 정상 작동)

---

## 💡 개발 팁

### Provider 사용
```dart
// UserProvider에서 사용자 정보 가져오기
final userProvider = Provider.of<UserProvider>(context, listen: false);
final uid = userProvider.currentUser?.uid;  // ⚠️ currentUser 사용 (user 아님!)
```

### Firestore 쿼리
```dart
// 인덱스 필요한 복합 쿼리
_firestore.collection('tos')
  .where('centerId', isEqualTo: centerId)
  .orderBy('date')
  .orderBy('startTime');
```

### TO 카드에 지원 상태 전달
```dart
TOCardWidget(
  to: to,
  applicationStatus: 'PENDING', // 또는 'CONFIRMED', null 등
)
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

1. ✅ Phase 1 완료 상태 확인
2. ✅ Firestore 인덱스 2개 생성되어 있는지
3. ✅ 테스트 데이터 6개 TO 있는지
4. ✅ 로그인 → TO 지원 → 목록에서 주황색 배지 확인

---

## 🎯 최종 목표

1. **Phase 1**: TO 상세 + 지원하기 ✅ **완료!**
2. **Phase 2**: 내 지원 내역 화면 (다음)
3. **Phase 3**: 관리자 지원자 관리 + 시간 겹침 자동 취소
4. **Phase 4**: FCM 푸시 알림
