# 📊 물류 TO 관리 시스템 개발 중간 보고서

**작성일**: 2025년 10월 24일  
**개발 기간**: 2025.10.24  
**작성자**: Flutter/Firebase 개발팀  
**문서 버전**: v2.0

---

## 📌 프로젝트 개요

### 프로젝트명
물류 TO(Task Order) 관리 시스템

### 목적
물류센터 및 사업장의 단기 근무자(알바) 관리를 위한 모바일 애플리케이션 개발

### 주요 기능
- 사업장별 TO(근무 오더) 생성 및 관리
- 업무 유형별 세부 근무 조건 설정
- 지원자 지원 및 관리자 승인 시스템
- TO 그룹 관리를 통한 연속 근무 관리
- 하이브리드 지원자 관리 (개별 TO + 그룹 통합)

---

## ✅ 완료된 개발 내용

### **Phase 1: 업무별 근무시간 분리** ✅ 완료

#### 1.1 개발 목표
기존 TO 단위 근무시간을 **업무(WorkDetail) 단위**로 변경하여 하나의 TO에서 여러 업무가 각각 다른 근무시간을 가질 수 있도록 개선

#### 1.2 주요 변경사항

##### **1.2.1 WorkDetailInput 클래스 수정**
```dart
class WorkDetailInput {
  final String? workType;      // 업무 유형
  final int? wage;             // 급여
  final int? requiredCount;    // 필요 인원
  final String? startTime;     // ✅ NEW: 시작 시간
  final String? endTime;       // ✅ NEW: 종료 시간
}
```

**변경 이유**: 각 업무마다 다른 근무시간 설정 가능
**예시**: 
- 피킹: 09:00~13:00 (4시간)
- 포장: 13:00~18:00 (5시간)
- 검수: 09:00~18:00 (8시간)

##### **1.2.2 TO 생성 화면 개선**
- **파일**: `admin_create_to_screen.dart`
- **주요 수정**:
  - TO 레벨 시간 입력 제거 (`startTime`, `endTime` 삭제)
  - 업무 추가 다이얼로그에 시간 입력 추가
  - 시간 선택 드롭다운 (30분 단위, 00:00~23:30)
  - 업무 카드에 근무시간 표시

**UI 개선**:
```
[업무 카드 표시 예시]
┌─────────────────────────────────┐
│ 📦 피킹                          │
│ 🕐 09:00 ~ 13:00                │
│ 💰 50,000원  👥 5명             │
└─────────────────────────────────┘
```

##### **1.2.3 데이터 구조 변경**
**Firestore 구조**:
```
tos/{toId}/workDetails/{detailId}
  - workType: "피킹"
  - wage: 50000
  - requiredCount: 5
  - startTime: "09:00"    ✅ NEW
  - endTime: "13:00"      ✅ NEW
  - confirmedCount: 0
```

#### 1.3 영향받은 파일
- ✅ `lib/screens/admin/admin_create_to_screen.dart` (전체 수정)
- ✅ `lib/services/firestore_service.dart` (createTOWithDetails 메서드 수정)

#### 1.4 테스트 결과
- [x] TO 생성 시 업무별 시간 입력 가능
- [x] 시간 정보 Firestore 정상 저장
- [x] 업무 카드에 시간 정보 표시

---

### **Phase 2: TO 그룹 관리** ✅ 완료

#### 2.1 개발 목표
같은 사업장에서 **연속으로 발생하는 동일 업무**를 그룹으로 묶어 관리하고, 지원자를 통합 관리

#### 2.2 주요 기능

##### **2.2.1 그룹 개념 도입**
```
예시: 물류센터 정기 업무
├─ TO #1: 2025-10-25 (금) - 그룹: "물류센터_정기"
├─ TO #2: 2025-10-26 (토) - 그룹: "물류센터_정기"  
└─ TO #3: 2025-10-27 (일) - 그룹: "물류센터_정기"

→ 지원자들이 그룹 단위로 관리됨
→ 한 명이 여러 날짜에 지원 가능
```

##### **2.2.2 TOModel 확장**
```dart
class TOModel {
  // 기존 필드...
  final String? groupId;    // ✅ NEW: 그룹 ID
  final String? groupName;  // ✅ NEW: 그룹 표시명
  
  // 편의 메서드
  bool get isGrouped => groupId != null;
}
```

##### **2.2.3 FirestoreService 그룹 메서드 추가**
```dart
// 1. 그룹 ID 생성
String generateGroupId()

// 2. 사용자의 최근 TO 조회 (30일)
Future<List<TOModel>> getRecentTOsByUser(String uid, {int days = 30})

// 3. 같은 그룹의 TO들 조회
Future<List<TOModel>> getTOsByGroup(String groupId)

// 4. 그룹 전체 지원자 조회
Future<List<ApplicationModel>> getApplicationsByGroup(String groupId)
```

##### **2.2.4 TO 생성 시 그룹 연결 - 드롭다운 UI 개선**
**UI 개선 - selectedItemBuilder 추가**:
```dart
DropdownButtonFormField<String>(
  // ✅ 선택 후에는 제목만 표시 (레이아웃 깨짐 방지)
  selectedItemBuilder: (BuildContext context) {
    return _myRecentTOs.map((to) {
      return Text(
        to.title,
        overflow: TextOverflow.ellipsis,
      );
    }).toList();
  },
  // 드롭다운 펼쳤을 때는 제목 + 날짜 표시
  items: _myRecentTOs.map((to) {
    return DropdownMenuItem<String>(
      value: to.groupId ?? to.id,
      child: Column(...), // 제목 + 날짜
    );
  }).toList(),
)
```

**선택 전 (드롭다운 펼침)**:
```
┌─────────────────────────────────┐
│ 물류센터 파트타임알바           │
│ 2025-10-25 (금)                 │
├─────────────────────────────────┤
│ 물류센터 정기 업무              │
│ 2025-10-26 (토)                 │
└─────────────────────────────────┘
```

**선택 후 (드롭다운 닫힘)**:
```
┌─────────────────────────────────┐
│ 물류센터 파트타임알바        ▼  │ ← 제목만!
└─────────────────────────────────┘
```

**로직**:
1. 체크박스 선택 시 → 최근 30일 TO 목록 로드
2. 기존 TO 선택 시 → 같은 groupId 사용
3. 선택 안 함 시 → 새 그룹 생성

##### **2.2.5 TO 상세 화면 그룹 정보 표시**
**AdminTODetailScreen 개선**:
```
┌─────────────────────────────────────┐
│ 그룹: 물류센터_정기                  │ ✅ NEW
│                                      │
│ 📦 A물류센터                         │
│ 물류센터 파트타임알바                │
│ 2025-10-25 (금) | 09:00 ~ 18:00    │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🔗 연결된 TO (2개)                   │ ✅ NEW
│ 그룹 전체 지원자: 15명               │
├─────────────────────────────────────┤
│ 10/26  물류센터 파트타임알바  [모집중]│
│ (토)   09:00~18:00 | 3/5명           │
├─────────────────────────────────────┤
│ 10/27  물류센터 파트타임알바  [모집중]│
│ (일)   09:00~18:00 | 2/5명           │
└─────────────────────────────────────┘
```

#### 2.3 영향받은 파일
- ✅ `lib/models/to_model.dart` (groupId, groupName 추가)
- ✅ `lib/services/firestore_service.dart` (그룹 메서드 4개 추가)
- ✅ `lib/screens/admin/admin_create_to_screen.dart` (그룹 연결 UI + 드롭다운 개선)
- ✅ `lib/screens/admin/admin_to_detail_screen.dart` (그룹 정보 표시)

#### 2.4 데이터베이스 구조
```
tos/{toId}
  - businessId: "business_123"
  - businessName: "A물류센터"
  - title: "물류센터 파트타임알바"
  - groupId: "group_1698123456789"    ✅ NEW
  - groupName: "물류센터_정기"         ✅ NEW
  - date: Timestamp
  - totalRequired: 15
  - totalConfirmed: 8
  - ...
```

#### 2.5 테스트 결과
- [x] TO 생성 시 기존 TO와 연결 가능
- [x] 그룹 ID 자동 생성
- [x] 같은 그룹의 TO 목록 조회
- [x] 그룹 통합 지원자 수 표시
- [x] TO 상세 화면에 연결된 TO 표시
- [x] 드롭다운 선택 후 레이아웃 깨짐 방지

---

### **Phase 2.5: 하이브리드 지원자 표시** ✅ 완료

#### 2.5.1 개발 목표
TO 상세 화면에서 **"이 TO 지원자"**와 **"그룹 전체 지원자"**를 탭으로 전환하여 볼 수 있도록 개선

#### 2.5.2 주요 기능

##### **탭 UI 추가**
```
┌─────────────────────────────────────┐
│ [이 TO (3명)] [그룹 전체 (8명)]     │ ← 탭
└─────────────────────────────────────┘
```

**이 TO 탭**:
- 현재 TO에 지원한 사람만 표시
- 기존 기능 유지

**그룹 전체 탭**:
- 같은 그룹의 모든 TO에 지원한 사람 표시
- 각 지원자가 어느 TO(날짜)에 지원했는지 표시
- 지원 시간 기준 정렬

##### **그룹 지원자 카드 구조**
```
┌─────────────────────────────────────┐
│ 홍길동                 [대기중]      │
├─────────────────────────────────────┤
│ 📅 지원한 TO                         │
│ 물류센터 파트타임알바                │
│ 10/25 (금)                           │
├─────────────────────────────────────┤
│ 📦 선택 업무                         │
│ 피킹 - 50,000원                      │
├─────────────────────────────────────┤
│ 📧 hong@email.com                    │
│ 🕐 2025-10-24 14:30 지원             │
├─────────────────────────────────────┤
│ [거절] [승인]                        │
└─────────────────────────────────────┘
```

##### **데이터 로딩 최적화**
```dart
Future<void> _loadData() async {
  // 기본 데이터 (지원자 + WorkDetails)
  final results = await Future.wait([
    _firestoreService.getApplicantsWithUserInfo(widget.to.id),
    _firestoreService.getWorkDetails(widget.to.id),
  ]);

  // 그룹 정보가 있으면 추가 로드
  if (widget.to.groupId != null) {
    final groupApplications = await _firestoreService
        .getApplicationsByGroup(widget.to.groupId!);
    
    // 각 지원자의 상세 정보 로드
    for (var app in groupApplications) {
      final userDoc = await _firestoreService.getUser(app.uid);
      final toDoc = await _firestoreService.getTO(app.toId);
      // ...
    }
  }
}
```

#### 2.5.3 영향받은 파일
- ✅ `lib/screens/admin/admin_to_detail_screen.dart` (전면 개편)
  - 상태 변수 추가 (_groupApplicants, _selectedTabIndex)
  - _loadData() 메서드 확장
  - _buildApplicantsSection() 추가 (탭 UI)
  - _buildThisTOApplicantsList() 분리
  - _buildGroupApplicantsList() 추가
  - _buildGroupApplicantCard() 추가

#### 2.5.4 테스트 결과
- [x] 탭 전환 정상 작동
- [x] 이 TO 지원자 표시
- [x] 그룹 전체 지원자 표시
- [x] 지원한 TO 정보 표시
- [x] 승인/거절 기능 정상 작동

---

### **Phase 2.6: UserModel phone 필드 추가** ✅ 완료

#### 2.6.1 개발 목표
지원자의 **전화번호 정보**를 저장하고 관리자가 확인할 수 있도록 UserModel 확장

#### 2.6.2 주요 변경사항

##### **UserModel 클래스 수정**
```dart
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? phone;  // ✅ NEW: 전화번호
  final UserRole role;
  final String? businessId;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  
  // fromMap, toMap, copyWith 모두 phone 필드 추가
}
```

##### **회원가입 화면 수정**
- **파일**: `lib/screens/auth/register_screen.dart`
- **추가 사항**:
  - `_phoneController` 추가
  - 전화번호 입력 필드 추가 (이메일 다음)
  - 입력 형식 제한 (숫자와 '-'만, 최대 13자)
  - 유효성 검증 추가

```dart
// 전화번호 입력 필드
TextFormField(
  controller: _phoneController,
  keyboardType: TextInputType.phone,
  decoration: InputDecoration(
    labelText: '전화번호',
    hintText: '010-0000-0000',
    prefixIcon: const Icon(Icons.phone_outlined),
    // ...
  ),
  inputFormatters: [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
    LengthLimitingTextInputFormatter(13),
  ],
  validator: (value) {
    if (value == null || value.isEmpty) {
      return '전화번호를 입력해주세요';
    }
    if (value.length < 10) {
      return '올바른 전화번호를 입력해주세요';
    }
    return null;
  },
),
```

##### **Provider 및 Service 수정**
- **user_provider.dart**: `signUp()` 메서드에 `phone` 파라미터 추가
- **auth_service.dart**: `signUp()` 메서드에 `phone` 파라미터 추가

```dart
// UserProvider
Future<bool> signUp({
  required String email,
  required String password,
  required String name,
  String? phone,  // ✅ 추가
  required UserRole role,
}) async {
  // ...
}

// AuthService
Future<UserModel?> signUp({
  required String email,
  required String password,
  required String name,
  String? phone,  // ✅ 추가
  UserRole role = UserRole.USER,
  String? businessId,
}) async {
  // ...
}
```

##### **지원자 카드에 전화번호 표시**
```dart
// admin_to_detail_screen.dart
Row(
  children: [
    Icon(Icons.phone_outlined, size: 14, color: Colors.grey[600]),
    const SizedBox(width: 6),
    Text(
      userPhone.isNotEmpty ? userPhone : '전화번호 없음',
      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
    ),
  ],
),
```

#### 2.6.3 영향받은 파일
- ✅ `lib/models/user_model.dart` (phone 필드 추가)
- ✅ `lib/screens/auth/register_screen.dart` (전화번호 입력 UI)
- ✅ `lib/providers/user_provider.dart` (signUp 메서드 수정)
- ✅ `lib/services/auth_service.dart` (signUp 메서드 수정)
- ✅ `lib/screens/admin/admin_to_detail_screen.dart` (전화번호 표시)

#### 2.6.4 데이터베이스 구조
```
users/{uid}
  - name: "홍길동"
  - email: "hong@email.com"
  - phone: "010-1234-5678"  ✅ NEW
  - role: "USER"
  - createdAt: Timestamp
  - lastLoginAt: Timestamp
```

#### 2.6.5 테스트 결과
- [x] 회원가입 시 전화번호 입력
- [x] 전화번호 형식 검증
- [x] Firestore에 전화번호 저장
- [x] 지원자 카드에 전화번호 표시
- [x] 기존 사용자 호환성 (phone: null)

---

## 🔧 버그 수정

### 1. admin_create_to_screen.dart 에러 수정
**문제**:
- TOModel import 누락
- null 체크 미흡으로 인한 런타임 에러

**해결**:
```dart
// 1. import 추가
import '../../models/to_model.dart';

// 2. null 체크 개선
try {
  final selectedTO = _myRecentTOs.firstWhere(
    (to) => (to.groupId == _selectedGroupId) || (to.id == _selectedGroupId),
    orElse: () => _myRecentTOs.first,
  );
  groupName = selectedTO.groupName ?? selectedTO.title;
} catch (e) {
  groupName = _titleController.text.trim();
}
```

### 2. Business Admin TO 관리 메뉴 연결
**문제**: TO 관리 버튼이 TODO 상태로 미연결

**해결**:
```dart
// business_admin_home_screen.dart
import 'admin_to_list_screen.dart';

onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const AdminTOListScreen(),
    ),
  );
},
```

### 3. admin_to_detail_screen.dart Icons 에러
**문제**: `Icons.people_off_outlined` 존재하지 않음

**해결**:
```dart
// 수정 전
Icon(Icons.people_off_outlined, size: 60, color: Colors.grey[400])

// 수정 후
Icon(Icons.people_outline, size: 60, color: Colors.grey[400])
```

### 4. register_screen.dart import 누락
**문제**: `FilteringTextInputFormatter` 정의되지 않음

**해결**:
```dart
import 'package:flutter/services.dart';  // ✅ 추가
```

### 5. user_provider.dart 문법 오류
**문제**: optional parameter 기본값에 `:` 사용

**해결**:
```dart
// 수정 전
UserRole role: UserRole.USER

// 수정 후
UserRole role = UserRole.USER  // ✅ = 사용
```

---

## 📊 개발 현황

### 완료된 기능
| 기능 | 상태 | 완료일 |
|------|------|--------|
| Phase 1: 업무별 근무시간 분리 | ✅ 완료 | 2025-10-24 |
| Phase 2: TO 그룹 관리 | ✅ 완료 | 2025-10-24 |
| Phase 2.5: 하이브리드 지원자 표시 | ✅ 완료 | 2025-10-24 |
| Phase 2.6: UserModel phone 필드 | ✅ 완료 | 2025-10-24 |
| 드롭다운 UI 개선 | ✅ 완료 | 2025-10-24 |
| 버그 수정 (5건) | ✅ 완료 | 2025-10-24 |

### 진행 예정 기능
| 기능 | 우선순위 | 예상 일정 |
|------|----------|-----------|
| Phase 3: 지원자 화면 개선 | 높음 | 미정 |
| Phase 4: 통계 대시보드 | 중간 | 미정 |
| Phase 5: 알림 기능 | 중간 | 미정 |
| Phase 6: 프로필 수정 기능 | 낮음 | 미정 |

---

## 🎯 주요 성과

### 1. 유연한 업무 관리
- ✅ 하나의 TO에서 여러 업무 유형, 각각 다른 시간 설정 가능
- ✅ 업무별 독립적인 인원 관리
- ✅ 실제 물류센터 운영 패턴 반영

### 2. 효율적인 TO 그룹 관리
- ✅ 연속 근무 TO를 그룹으로 묶어 관리
- ✅ 그룹 단위 지원자 통합 조회
- ✅ 관리자의 TO 생성 시간 단축
- ✅ 드롭다운 UI 개선으로 사용성 향상

### 3. 하이브리드 지원자 관리
- ✅ 개별 TO와 그룹 전체를 탭으로 전환하여 확인
- ✅ 상황에 맞는 지원자 관리 방식 선택 가능
- ✅ 지원자가 어느 날짜에 지원했는지 명확히 표시

### 4. 완전한 지원자 정보 관리
- ✅ 이름, 이메일, 전화번호 통합 관리
- ✅ 회원가입 시 전화번호 필수 입력
- ✅ 관리자가 지원자 연락처 즉시 확인 가능

### 5. 사용자 경험 개선
- ✅ 직관적인 UI/UX
- ✅ 단계별 입력 가이드
- ✅ 실시간 데이터 반영
- ✅ 레이아웃 깨짐 방지

---

## 📈 기술 스택

### Frontend
- **Framework**: Flutter 3.x
- **언어**: Dart
- **상태관리**: Provider 패턴
- **UI**: Material Design 3

### Backend
- **BaaS**: Firebase
- **데이터베이스**: Cloud Firestore
- **인증**: Firebase Authentication
- **스토리지**: Cloud Storage (예정)

### 개발 도구
- **IDE**: Android Studio / VS Code
- **버전관리**: Git
- **디자인**: Figma (예정)

---

## 🔍 코드 품질

### 코드 구조
```
lib/
├── models/              # 데이터 모델
│   ├── to_model.dart
│   ├── work_detail_model.dart
│   ├── application_model.dart
│   └── user_model.dart  # ✅ phone 필드 추가
├── services/            # 비즈니스 로직
│   ├── firestore_service.dart
│   └── auth_service.dart
├── screens/            # 화면
│   ├── admin/
│   │   ├── admin_to_detail_screen.dart  # ✅ 하이브리드 지원자 표시
│   │   └── admin_create_to_screen.dart  # ✅ 드롭다운 개선
│   ├── auth/
│   │   └── register_screen.dart  # ✅ 전화번호 입력
│   └── user/
├── providers/
│   └── user_provider.dart  # ✅ phone 파라미터 추가
├── widgets/            # 재사용 위젯
└── utils/              # 유틸리티
```

### 개발 원칙
- ✅ Single Responsibility Principle
- ✅ DRY (Don't Repeat Yourself)
- ✅ 명확한 네이밍 컨벤션
- ✅ 에러 핸들링
- ✅ 로깅 및 디버깅
- ✅ 사용자 입력 검증

---

## 🚀 다음 단계

### 우선 순위 1: 필수 기능 완성
1. **지원자 화면 개선**
   - 그룹 TO 목록 표시
   - 한 번에 여러 날짜 지원 기능
   - 내 지원 현황 그룹별 표시

2. **알림 기능**
   - TO 생성 알림
   - 지원 승인/거절 알림
   - 근무 전날 리마인더

3. **프로필 관리**
   - 사용자 정보 수정 (전화번호 포함)
   - 비밀번호 변경
   - 계정 설정

### 우선 순위 2: 고도화
1. **통계 및 분석**
   - 사업장별 TO 현황
   - 지원자 참여율
   - 업무 유형별 통계

2. **관리자 기능 강화**
   - 일괄 TO 생성
   - 지원자 블랙리스트 관리
   - 급여 정산 기능
   - 지원자 연락처 일괄 내보내기

---

## 📝 특이사항 및 이슈

### 해결된 이슈
1. ✅ TOModel import 누락 → 해결
2. ✅ null 체크 미흡 → orElse 추가로 해결
3. ✅ TO 관리 메뉴 미연결 → AdminTOListScreen 연결
4. ✅ Icons.people_off_outlined 에러 → Icons.people_outline로 수정
5. ✅ FilteringTextInputFormatter 에러 → import 추가
6. ✅ optional parameter 문법 오류 → = 사용으로 수정
7. ✅ 드롭다운 레이아웃 깨짐 → selectedItemBuilder 추가

### 진행 중인 이슈
- 없음

### 알려진 제약사항
- 그룹은 같은 사업장 내에서만 생성 가능
- 최근 30일 이내 TO만 그룹 연결 가능
- 업무는 최대 3개까지 추가 가능
- 전화번호는 필수 입력 (기존 사용자는 null 허용)

---

## 💡 개선 제안

### 단기 개선사항
1. TO 복사 기능 (같은 조건으로 다른 날짜 TO 생성)
2. 업무 템플릿 저장 기능
3. Excel 내보내기 기능
4. 전화번호 자동 포맷팅 (010-0000-0000)
5. 그룹 지원자 필터링 (날짜별, 상태별)

### 장기 개선사항
1. 머신러닝 기반 지원자 추천
2. 자동 스케줄링 기능
3. 급여 자동 계산 및 정산
4. SMS/카카오톡 알림 연동
5. 지원자 평가 시스템

---

## 📞 문의

**개발팀**: Flutter/Firebase 개발팀  
**작성일**: 2025년 10월 24일  
**문서 버전**: v2.0  
**업데이트**: Phase 2.5, 2.6 추가

---

## 부록: 주요 코드 스니펫

### A. WorkDetailInput 클래스
```dart
class WorkDetailInput {
  final String? workType;
  final int? wage;
  final int? requiredCount;
  final String? startTime;  // Phase 1
  final String? endTime;    // Phase 1

  bool get isValid =>
      workType != null &&
      wage != null &&
      requiredCount != null &&
      startTime != null &&
      endTime != null;
}
```

### B. 그룹 ID 생성
```dart
String generateGroupId() {
  return 'group_${DateTime.now().millisecondsSinceEpoch}';
}
```

### C. TO 생성 시 그룹 처리
```dart
String? groupId;
String? groupName;

if (_linkToExisting && _selectedGroupId != null) {
  groupId = _selectedGroupId;
  final selectedTO = _myRecentTOs.firstWhere(
    (to) => (to.groupId == _selectedGroupId) || (to.id == _selectedGroupId),
    orElse: () => _myRecentTOs.first,
  );
  groupName = selectedTO.groupName ?? selectedTO.title;
} else if (_linkToExisting) {
  groupId = _firestoreService.generateGroupId();
  groupName = _titleController.text.trim();
}
```

### D. 하이브리드 지원자 로딩 (Phase 2.5)
```dart
Future<void> _loadData() async {
  // 기본 데이터
  final results = await Future.wait([
    _firestoreService.getApplicantsWithUserInfo(widget.to.id),
    _firestoreService.getWorkDetails(widget.to.id),
  ]);

  // 그룹 지원자 (있는 경우)
  if (widget.to.groupId != null) {
    final groupApplications = await _firestoreService
        .getApplicationsByGroup(widget.to.groupId!);
    
    for (var app in groupApplications) {
      final userDoc = await _firestoreService.getUser(app.uid);
      final toDoc = await _firestoreService.getTO(app.toId);
      
      if (userDoc != null && toDoc != null) {
        groupApplicants.add({
          'applicationId': app.id,
          'application': app,
          'userName': userDoc.name,
          'userEmail': userDoc.email,
          'userPhone': userDoc.phone ?? '',
          'toTitle': toDoc.title,
          'toDate': toDoc.date,
        });
      }
    }
  }
}
```

### E. UserModel with phone (Phase 2.6)
```dart
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? phone;  // ✅ Phase 2.6
  final UserRole role;
  final String? businessId;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  
  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.phone,  // ✅ Phase 2.6
    required this.role,
    this.businessId,
    this.createdAt,
    this.lastLoginAt,
  });
  
  // fromMap, toMap, copyWith에서 phone 처리
}
```

### F. 드롭다운 selectedItemBuilder (Phase 2)
```dart
DropdownButtonFormField<String>(
  value: _selectedGroupId,
  // 선택 후 표시 (제목만)
  selectedItemBuilder: (BuildContext context) {
    return _myRecentTOs.map((to) {
      return Text(
        to.title,
        overflow: TextOverflow.ellipsis,
      );
    }).toList();
  },
  // 드롭다운 펼침 (제목 + 날짜)
  items: _myRecentTOs.map((to) {
    return DropdownMenuItem<String>(
      value: to.groupId ?? to.id,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(to.title),
          Text('${to.formattedDate} (${to.weekday})'),
        ],
      ),
    );
  }).toList(),
)
```

---

## 📊 개발 통계

### 수정된 파일 수
- **Phase 1**: 2개 파일
- **Phase 2**: 4개 파일
- **Phase 2.5**: 1개 파일 (대규모 수정)
- **Phase 2.6**: 5개 파일
- **버그 수정**: 5개 파일
- **총계**: 약 10개 파일 수정

### 추가된 기능 수
- **새로운 필드**: 5개 (startTime, endTime, groupId, groupName, phone)
- **새로운 메서드**: 8개
- **새로운 위젯**: 4개
- **새로운 화면**: 0개 (기존 화면 개선)

### 코드 품질 개선
- ✅ null 안전성 강화
- ✅ 에러 핸들링 개선
- ✅ 입력 검증 추가
- ✅ UI/UX 개선
- ✅ 코드 재사용성 향상

---

**보고서 끝**

*이 보고서는 2025년 10월 24일 기준 개발 현황을 정리한 것입니다.*
