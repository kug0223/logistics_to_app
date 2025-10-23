# 📋 다음 개발 과제 - TO 시스템 개선

## 📅 작성일
2025년 10월 23일

---

## 🎯 현재 상태

### ✅ 완료된 기능
- 사업장 기반 TO 시스템
- 중간관리자 TO 생성 (여러 사업장 선택 가능)
- 지원자 전체 TO 조회
- TO 상세 화면 이동

### 🚧 추가 필요 기능 (3개)
1. TO 마감 시간 추가
2. 업무 유형 커스터마이징
3. 업무 설명 사진 첨부

---

## 1️⃣ TO 마감 시간 추가

### 📌 요구사항
- 근무 날짜와 **별개로** 지원 마감 일시 필요
- 마감 시간이 지나면 자동으로 지원 불가 처리
- 관리자는 마감 후에도 TO 수정 가능

### 🔧 구현 방안

#### A. TO 모델 수정
```dart
class TOModel {
  // 기존 필드
  final DateTime date; // 근무 날짜
  final String startTime; // 근무 시작 시간
  final String endTime; // 근무 종료 시간
  
  // ✅ 추가 필드
  final DateTime applicationDeadline; // 지원 마감 일시
  
  // ✅ 추가 Getter
  bool get isDeadlinePassed {
    return DateTime.now().isAfter(applicationDeadline);
  }
}
```

#### B. Firestore 구조
```javascript
tos/{toId}
{
  businessId: "...",
  businessName: "...",
  date: Timestamp,           // 근무 날짜
  startTime: "09:00",
  endTime: "18:00",
  applicationDeadline: Timestamp, // ✅ 추가 (지원 마감 일시)
  // ...
}
```

#### C. TO 생성 화면 추가
```dart
// admin_create_to_screen.dart
1. 마감 날짜 선택 DatePicker
2. 마감 시간 선택 TimePicker
3. 유효성 검증: 마감일시 < 근무일시
```

#### D. TO 목록/상세 화면 표시
```dart
// 마감 여부 뱃지 표시
if (to.isDeadlinePassed) {
  Container(
    child: Text('마감', style: TextStyle(color: Colors.red)),
  );
}

// 지원 버튼 비활성화
ElevatedButton(
  onPressed: to.isDeadlinePassed ? null : () => _apply(),
  child: Text(to.isDeadlinePassed ? '마감됨' : '지원하기'),
);
```

### 📊 우선순위
- **난이도**: ⭐⭐ (쉬움)
- **중요도**: ⭐⭐⭐⭐⭐ (매우 높음)
- **예상 시간**: 2~3시간

### 📝 수정 파일 목록
1. `lib/models/to_model.dart` - applicationDeadline 필드 추가
2. `lib/services/firestore_service.dart` - createTO 메서드 파라미터 추가
3. `lib/screens/admin/admin_create_to_screen.dart` - 마감일시 입력 UI
4. `lib/screens/user/to_detail_screen.dart` - 마감 여부 확인 로직
5. `lib/widgets/to_card_widget.dart` - 마감 뱃지 표시

---

## 2️⃣ 업무 유형 커스터마이징

### 📌 요구사항
- 현재: 고정된 업무 유형 (피킹, 패킹, 배송, 분류, 하역, 검수)
- 변경: **사업장별로** 업무 유형 커스터마이징 가능
- ⚠️ 기본값 제공 없음 (사업장 관리자가 직접 추가)

### 🔧 구현 방안

#### A. BusinessModel 수정
```dart
class BusinessModel {
  // 기존 필드
  final String id;
  final String name;
  final String address;
  // ...
  
  // ✅ 추가 필드
  final List<String> workTypes; // 사업장별 업무 유형 리스트
}
```

#### B. Firestore 구조
```javascript
businesses/{businessId}
{
  name: "홍길동 물류",
  address: "...",
  workTypes: ["피킹", "패킹", "상품진열", "재고정리"], // ✅ 추가
  // ...
}
```

#### C. 사업장 수정 화면에 업무 유형 관리 추가
```dart
// 화면 구조
사업장 정보 수정
├─ 사업장명
├─ 주소
├─ ✅ 업무 유형 관리 (NEW!)
│   ├─ [피킹] [X]
│   ├─ [패킹] [X]
│   ├─ [상품진열] [X]
│   └─ [+ 업무 유형 추가] 버튼
└─ 저장 버튼
```

#### D. TO 생성 시 해당 사업장의 업무 유형 사용
```dart
// admin_create_to_screen.dart
// 선택된 사업장의 workTypes 사용
DropdownButton<String>(
  items: _selectedBusiness!.workTypes.map((type) {
    return DropdownMenuItem(value: type, child: Text(type));
  }).toList(),
);

// 업무 유형이 없으면 경고
if (_selectedBusiness!.workTypes.isEmpty) {
  Text('사업장 설정에서 업무 유형을 먼저 등록하세요');
}
```

### 📊 우선순위
- **난이도**: ⭐⭐⭐ (보통)
- **중요도**: ⭐⭐⭐⭐ (높음)
- **예상 시간**: 3~4시간

### 📝 수정 파일 목록
1. `lib/models/business_model.dart` - workTypes 필드 추가
2. `lib/screens/admin/business_registration_screen.dart` - 업무 유형 입력 UI (선택사항)
3. `lib/screens/admin/business_edit_screen.dart` - 업무 유형 관리 UI (신규 생성 필요)
4. `lib/screens/admin/admin_create_to_screen.dart` - 업무 유형 드롭다운 수정
5. `lib/services/firestore_service.dart` - 업무 유형 CRUD 메서드

### 💡 UI 예시
```
┌────────────────────────────┐
│ 업무 유형 관리              │
├────────────────────────────┤
│ 피킹                [삭제]  │
│ 패킹                [삭제]  │
│ 상품진열            [삭제]  │
│                            │
│ [+ 업무 유형 추가]         │
└────────────────────────────┘

다이얼로그:
┌────────────────────────────┐
│ 업무 유형 추가              │
├────────────────────────────┤
│ [입력 필드]                │
│                            │
│ [취소]  [추가]             │
└────────────────────────────┘
```

---

## 3️⃣ 업무 설명 사진 첨부

### 📌 요구사항
- 현재: 텍스트 설명만 가능
- 변경: 텍스트 + **사진 첨부** 가능
- 제한: 크기/용량/개수 제한 필요

### 🔧 구현 방안

#### A. TO 모델 수정
```dart
class TOModel {
  // 기존 필드
  final String? description; // 텍스트 설명
  
  // ✅ 추가 필드
  final List<String> imageUrls; // 이미지 URL 리스트
}
```

#### B. Firebase Storage 구조
```
storage/
└── to_images/
    └── {toId}/
        ├── image_1.jpg (자동 리사이징: 1200px)
        ├── image_2.jpg
        └── image_3.jpg
```

#### C. Firestore 구조
```javascript
tos/{toId}
{
  description: "오전 피킹 작업입니다",
  imageUrls: [  // ✅ 추가
    "https://storage.googleapis.com/.../image_1.jpg",
    "https://storage.googleapis.com/.../image_2.jpg"
  ],
  // ...
}
```

#### D. 제한 사항
```dart
const int MAX_IMAGE_COUNT = 3;           // 최대 3장
const int MAX_IMAGE_SIZE = 5 * 1024 * 1024; // 5MB/개
const int MAX_IMAGE_WIDTH = 1200;        // 가로 1200px로 리사이징
List<String> ALLOWED_FORMATS = ['jpg', 'jpeg', 'png'];
```

#### E. 필요한 패키지
```yaml
dependencies:
  image_picker: ^1.0.4       # 갤러리/카메라 선택
  firebase_storage: ^11.5.6  # Firebase Storage 업로드
  image: ^4.1.3              # 이미지 압축/리사이징
```

#### F. TO 생성 화면 수정
```dart
// admin_create_to_screen.dart
1. [사진 추가] 버튼
2. 선택된 이미지 미리보기 (썸네일)
3. 각 이미지에 [X] 삭제 버튼
4. 업로드 진행률 표시
```

#### G. TO 상세 화면 수정
```dart
// to_detail_screen.dart
1. 이미지 갤러리 표시 (가로 스크롤)
2. 이미지 클릭 시 전체 화면 뷰어
3. 줌 인/아웃 가능
```

### 📊 우선순위
- **난이도**: ⭐⭐⭐⭐ (어려움)
- **중요도**: ⭐⭐⭐ (보통)
- **예상 시간**: 5~6시간

### 📝 수정 파일 목록
1. `pubspec.yaml` - 패키지 추가
2. `lib/models/to_model.dart` - imageUrls 필드 추가
3. `lib/services/storage_service.dart` - 이미지 업로드 서비스 신규 생성
4. `lib/screens/admin/admin_create_to_screen.dart` - 이미지 선택/업로드 UI
5. `lib/screens/user/to_detail_screen.dart` - 이미지 갤러리 표시
6. `lib/widgets/image_viewer.dart` - 전체 화면 이미지 뷰어 (신규)

### 💡 UI 예시
```
TO 생성 화면:
┌────────────────────────────┐
│ 📝 설명                     │
│ [텍스트 입력 영역]          │
│                            │
│ 📷 사진 (0/3)               │
│ ┌──┐ ┌──┐ ┌──┐            │
│ │+ │ │  │ │  │            │
│ └──┘ └──┘ └──┘            │
└────────────────────────────┘

사진 선택 후:
┌────────────────────────────┐
│ 📷 사진 (2/3)               │
│ ┌──┐ ┌──┐ ┌──┐            │
│ │🖼️│ │🖼️│ │+ │            │
│ │X │ │X │ │  │            │
│ └──┘ └──┘ └──┘            │
└────────────────────────────┘

TO 상세 화면:
┌────────────────────────────┐
│ 업무 설명                   │
│ 오전 피킹 작업입니다        │
│                            │
│ 📷 첨부 사진                │
│ ┌────┐┌────┐┌────┐        │
│ │🖼️  ││🖼️  ││🖼️  │        │
│ │    ││    ││    │        │
│ └────┘└────┘└────┘        │
│ ← 스크롤 →                 │
└────────────────────────────┘
```

### 🔒 보안 고려사항
```dart
// Storage Security Rules
service firebase.storage {
  match /b/{bucket}/o {
    match /to_images/{toId}/{imageId} {
      // 인증된 사용자만 읽기
      allow read: if request.auth != null;
      
      // TO 생성자만 쓰기/삭제
      allow write, delete: if request.auth != null 
        && request.auth.uid == getCreatorUID(toId);
    }
  }
}
```

---

## 📊 전체 우선순위 및 일정

### 🥇 Phase 1: TO 마감 시간 (Day 1)
- **시작**: 바로 시작 가능
- **소요 시간**: 2~3시간
- **핵심 기능**: 필수

### 🥈 Phase 2: 업무 유형 관리 (Day 2)
- **시작**: Phase 1 완료 후
- **소요 시간**: 3~4시간
- **핵심 기능**: 매우 중요

### 🥉 Phase 3: 사진 첨부 (Day 3)
- **시작**: Phase 2 완료 후
- **소요 시간**: 5~6시간
- **핵심 기능**: 선택사항 (있으면 좋음)

---

## 🎯 다음 채팅에서 시작할 것

### 즉시 시작
```
"Phase 1 시작! TO 마감 시간 추가해줘"
```

### 특정 Phase
```
"Phase 2부터 해줘" (업무 유형)
"Phase 3부터 해줘" (사진 첨부)
```

### 전체 코드 생성
```
"3개 Phase 코드 전부 만들어줘"
```

---

## 📝 참고사항

### TO 마감 시간 예시
```
근무일: 2025년 10월 25일 09:00~18:00
마감일시: 2025년 10월 24일 18:00 ✅

→ 10월 24일 18:00 이후엔 지원 불가
→ 관리자는 언제든 수정 가능
```

### 업무 유형 예시
```
사업장 A (물류센터):
- 피킹
- 패킹
- 배송

사업장 B (카페):
- 주방 보조
- 홀 서빙
- 바리스타

사업장 C (편의점):
- 계산대
- 상품 진열
- 재고 관리
```

### 사진 첨부 제한 이유
```
파일 크기: 5MB 이하
→ 모바일 데이터 절약
→ 로딩 속도 향상

이미지 개수: 3개 이하
→ 핵심 정보만 전달
→ 스토리지 비용 절감

자동 리사이징: 1200px
→ 고화질 유지하면서 용량 감소
→ 다양한 기기에서 최적 표시
```

---

## 🚀 준비 완료!

다음 채팅에서 원하는 Phase를 말씀해주세요!
