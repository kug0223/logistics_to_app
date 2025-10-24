# 📊 물류 TO 관리 시스템 개발 중간 보고서

**작성일**: 2025년 10월 24일  
**개발 기간**: 2025.10.24  
**작성자**: Flutter/Firebase 개발팀

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

##### **2.2.4 TO 생성 시 그룹 연결**
**UI 개선**:
```
┌─────────────────────────────────────┐
│ 🔗 기존 공고와 연결 (선택사항)       │
├─────────────────────────────────────┤
│ ☑ 기존 공고와 같은 TO입니다         │
│   지원자 명단이 합쳐집니다           │
│                                      │
│ 연결할 공고 선택                     │
│ ┌─────────────────────────────┐    │
│ │ 물류센터 파트타임알바        │    │
│ │ 2025-10-25 (금)              │    │
│ └─────────────────────────────┘    │
└─────────────────────────────────────┘
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
- ✅ `lib/screens/admin/admin_create_to_screen.dart` (그룹 연결 UI)
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

---

## 📊 개발 현황

### 완료된 기능
| 기능 | 상태 | 완료일 |
|------|------|--------|
| Phase 1: 업무별 근무시간 | ✅ 완료 | 2025-10-24 |
| Phase 2: TO 그룹 관리 | ✅ 완료 | 2025-10-24 |
| 에러 수정 및 버그 픽스 | ✅ 완료 | 2025-10-24 |

### 진행 예정 기능
| 기능 | 우선순위 | 예상 일정 |
|------|----------|-----------|
| Phase 3: 지원자 화면 개선 | 높음 | 미정 |
| Phase 4: 통계 대시보드 | 중간 | 미정 |
| Phase 5: 알림 기능 | 중간 | 미정 |

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

### 3. 사용자 경험 개선
- ✅ 직관적인 UI/UX
- ✅ 단계별 입력 가이드
- ✅ 실시간 데이터 반영

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
│   └── application_model.dart
├── services/            # 비즈니스 로직
│   ├── firestore_service.dart
│   └── auth_service.dart
├── screens/            # 화면
│   ├── admin/
│   └── user/
├── widgets/            # 재사용 위젯
└── utils/              # 유틸리티
```

### 개발 원칙
- ✅ Single Responsibility Principle
- ✅ DRY (Don't Repeat Yourself)
- ✅ 명확한 네이밍 컨벤션
- ✅ 에러 핸들링
- ✅ 로깅 및 디버깅

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

### 우선 순위 2: 고도화
1. **통계 및 분석**
   - 사업장별 TO 현황
   - 지원자 참여율
   - 업무 유형별 통계

2. **관리자 기능 강화**
   - 일괄 TO 생성
   - 지원자 블랙리스트 관리
   - 급여 정산 기능

---

## 📝 특이사항 및 이슈

### 해결된 이슈
1. ✅ TOModel import 누락 → 해결
2. ✅ null 체크 미흡 → orElse 추가로 해결
3. ✅ TO 관리 메뉴 미연결 → AdminTOListScreen 연결

### 진행 중인 이슈
- 없음

### 알려진 제약사항
- 그룹은 같은 사업장 내에서만 생성 가능
- 최근 30일 이내 TO만 그룹 연결 가능
- 업무는 최대 3개까지 추가 가능

---

## 💡 개선 제안

### 단기 개선사항
1. TO 복사 기능 (같은 조건으로 다른 날짜 TO 생성)
2. 업무 템플릿 저장 기능
3. Excel 내보내기 기능

### 장기 개선사항
1. 머신러닝 기반 지원자 추천
2. 자동 스케줄링 기능
3. 급여 자동 계산 및 정산

---

## 📞 문의

**개발팀**: Flutter/Firebase 개발팀  
**작성일**: 2025년 10월 24일  
**문서 버전**: v1.0

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

---

**보고서 끝**
