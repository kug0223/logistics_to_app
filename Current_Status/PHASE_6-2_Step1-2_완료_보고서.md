# Phase 6-2: 사업장 관리 시스템 구현 (Step 1~2 완료) ✅

## 📅 작업 일시
2025년 10월 22일

---

## ✅ 완료된 작업

### Step 1: FirestoreService 확장

#### 추가된 메서드 (총 14개)

##### 📝 CRUD 기본 메서드
1. `createBusiness()` - 사업장 생성
2. `updateBusiness()` - 사업장 수정
3. `deleteBusiness()` - 사업장 삭제 (TO 있으면 삭제 불가)
4. `getBusinessById()` - 사업장 ID로 조회

##### 🔍 조회 메서드
5. `getAllBusinesses()` - 전체 사업장 조회 (슈퍼관리자용)
6. `getApprovedBusinesses()` - 승인된 사업장만 조회
7. `getPendingBusinesses()` - 승인 대기 사업장 조회 (슈퍼관리자용)
8. `getMyBusiness()` - 내 사업장 조회 (사업장 관리자용)
9. `getBusinessesByCategory()` - 업종별 사업장 조회

##### ✅ 승인 관리 메서드
10. `approveBusiness()` - 사업장 승인 (슈퍼관리자 전용)
11. `rejectBusiness()` - 사업장 거절 및 삭제 (슈퍼관리자 전용)

##### 📊 통계 메서드
12. `getTOCountByBusiness()` - 사업장별 TO 개수 조회

##### 🔄 실시간 스트림
13. `approvedBusinessesStream()` - 승인된 사업장 실시간 스트림

---

### Step 2: 사업장 등록 화면 (가치업 스타일)

#### 화면 구조
```
BusinessRegistrationScreen (Stepper 기반)
├─ Step 1: 업종 선택
│   ├─ 회사
│   │   ├─ 일반 회사
│   │   └─ 제조, 생산, 건설
│   ├─ 알바 매장
│   │   ├─ 알바-카페
│   │   ├─ 알바-외식업
│   │   ├─ 알바-판매-서비스
│   │   └─ 알바-매장관리
│   └─ 기타
│       ├─ 교육, 의료, 기관
│       └─ 기타
└─ Step 2: 사업장 정보 입력
    ├─ 사업장명 (필수)
    ├─ 주소 (필수) + Daum 주소 검색
    ├─ 위도/경도 (자동 입력)
    ├─ 연락처 (선택)
    └─ 설명 (선택)
```

#### 주요 기능
- ✅ Stepper UI로 단계별 입력
- ✅ ExpansionTile로 업종 카테고리 표시
- ✅ Radio 버튼으로 세부 업종 선택
- ✅ Daum 주소 검색 API 연동
- ✅ 좌표 자동 입력 (Kakao Geocoding)
- ✅ 폼 유효성 검증
- ✅ 승인 대기 상태로 등록 (isApproved: false)

---

## 📂 파일 위치

### 1. 사업장 메서드 추가 코드
**파일**: `/mnt/user-data/outputs/사업장_메서드_추가_코드.dart`

**사용 방법**:
```bash
# 이 파일의 내용을 복사해서
# lib/services/firestore_service.dart 파일의
# 맨 아래 (마지막 메서드 다음)에 붙여넣기
```

**추가 위치**:
```dart
class FirestoreService {
  // ... 기존 메서드들 ...
  
  // ==================== 센터 관련 ====================
  Future<CenterModel?> getCenterById(String centerId) async { ... }
  Future<List<CenterModel>> getActiveCenters() async { ... }
  
  // ✅ 여기에 붙여넣기!
  // ==================== 사업장 관련 (NEW - Phase 6-2) ====================
  Future<String?> createBusiness(BusinessModel business) async { ... }
  // ... (복사한 나머지 메서드들)
  
} // class 끝
```

**⚠️ 중요**: `business_model.dart` import 필요!
```dart
// firestore_service.dart 상단에 추가
import '../models/business_model.dart';
```

---

### 2. 사업장 등록 화면
**파일**: `/mnt/user-data/outputs/business_registration_screen.dart`

**사용 방법**:
```bash
위치: lib/screens/admin/business_registration_screen.dart

작업:
1. lib/screens/admin/ 폴더에 새 파일 생성
2. business_registration_screen.dart 이름으로 저장
3. outputs 파일 내용 복사/붙여넣기
```

---

## 🔥 Firestore 데이터 구조

### businesses 컬렉션
```javascript
{
  id: string (문서 ID),
  name: "스타벅스 강남점",
  category: "알바 매장",
  subCategory: "알바-카페 (카페, 음료, 베이커리)",
  address: "서울시 강남구 테헤란로 123",
  latitude: 37.5146,
  longitude: 127.1059,
  ownerId: "사업장_관리자_UID",
  phone: "010-1234-5678" | null,
  description: "강남역 근처 스타벅스입니다" | null,
  isApproved: false,  // 슈퍼관리자 승인 대기
  createdAt: Timestamp,
  updatedAt: Timestamp | null
}
```

---

## 🚀 사용 예시

### 사업장 등록 플로우
```
1. 사용자가 "사업장 등록" 버튼 클릭
2. BusinessRegistrationScreen 열림
3. Step 1: 업종 선택
   - "알바 매장" → "알바-카페" 선택
4. Step 2: 사업장 정보 입력
   - 사업장명: "스타벅스 강남점"
   - 주소 검색: "서울시 강남구 테헤란로 123"
   - 좌표 자동 입력
   - 연락처, 설명 입력 (선택)
5. "등록하기" 버튼 클릭
6. Firestore에 저장 (isApproved: false)
7. 성공 다이얼로그 표시
   "슈퍼관리자의 승인 후 이용 가능합니다"
```

---

## 📋 적용 가이드

### 1단계: firestore_service.dart 수정

```bash
1. lib/services/firestore_service.dart 파일 열기
2. 상단에 import 추가:
   import '../models/business_model.dart';
3. 파일 맨 아래 (마지막 메서드 다음)에
   '사업장_메서드_추가_코드.dart' 내용 복사/붙여넣기
4. 저장
```

---

### 2단계: 사업장 등록 화면 추가

```bash
1. lib/screens/admin/ 폴더에 새 파일 생성
2. business_registration_screen.dart 이름으로 저장
3. outputs/business_registration_screen.dart 내용 복사/붙여넣기
4. 저장
```

---

### 3단계: 사업장 등록 진입점 추가

사업장 등록 화면으로 가는 버튼을 어디에 추가할까요?

#### 옵션 1: 관리자 홈에 FloatingActionButton 추가
```dart
// admin_home_screen.dart
floatingActionButton: FloatingActionButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BusinessRegistrationScreen(),
      ),
    );
  },
  child: const Icon(Icons.add_business),
),
```

#### 옵션 2: 일반 사용자 홈에 "사업장 등록" 버튼 추가
```dart
// user_home_screen.dart
ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BusinessRegistrationScreen(),
      ),
    );
  },
  child: const Text('사업장 등록'),
),
```

---

## 🧪 테스트 시나리오

### 테스트 1: 사업장 등록 (일반 사용자)
```
1. user@test.com 로그인
2. "사업장 등록" 버튼 클릭
3. 업종 선택: "알바 매장" → "알바-카페"
4. 다음 클릭
5. 사업장명: "테스트 카페"
6. 주소 검색: 아무 주소 입력
7. 연락처: 010-1234-5678
8. "등록하기" 클릭
9. 성공 다이얼로그 확인
10. Firebase Console에서 businesses 컬렉션 확인
    - isApproved: false 확인
```

### 테스트 2: 업종별 사업장 조회
```dart
// 코드로 테스트
final businesses = await _firestoreService.getBusinessesByCategory('알바 매장');
print('알바 매장: ${businesses.length}개');
```

---

## 🎯 다음 단계 (Step 3)

### 슈퍼관리자 화면 구현
1. 사업장 승인 대기 목록 화면
2. 사업장 승인/거절 기능
3. 사업장 관리자 계정 생성

---

## ⚠️ 주의사항

### 1. import 누락 방지
```dart
// firestore_service.dart에 꼭 추가!
import '../models/business_model.dart';
```

### 2. 좌표 자동 입력 확인
- Daum 주소 검색 시 Kakao Geocoding API 사용
- 좌표가 제대로 입력되는지 확인
- 좌표 없으면 등록 불가

### 3. 승인 시스템
- 사업장 등록 시 `isApproved: false`
- 슈퍼관리자가 승인해야 사용 가능
- 승인 전에는 TO 생성 불가

---

## 💡 개발자 노트

### 잘된 점
- ✅ 가치업 스타일 UI 구현 (ExpansionTile + Radio)
- ✅ Stepper로 단계별 입력 UX 개선
- ✅ Daum 주소 + Kakao Geocoding 자동 연동
- ✅ 14개 사업장 관리 메서드 완성

### 개선 필요 사항
- ⚠️ 사업장 등록 진입점 추가 필요
- ⚠️ 슈퍼관리자 승인 화면 구현 필요
- ⚠️ 사업장 관리자 계정 생성 기능 필요

---

## ✅ 완료 체크리스트

- [  ] firestore_service.dart에 사업장 메서드 추가
- [  ] business_registration_screen.dart 파일 생성
- [  ] 사업장 등록 진입점 추가 (관리자 또는 일반 사용자)
- [  ] 앱 재시작 (flutter run)
- [  ] 사업장 등록 테스트
- [  ] Firebase Console에서 데이터 확인

---

**🎉 Phase 6-2 Step 1~2 완료!**

**다음**: Step 3 (슈퍼관리자 승인 화면)로 진행하시겠습니까?
