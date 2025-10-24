# TO 그룹화 및 날짜 범위 기능 설계서

## 📋 목차
1. [프로젝트 개요](#프로젝트-개요)
2. [현재 문제점](#현재-문제점)
3. [해결 방안](#해결-방안)
4. [화면 설계](#화면-설계)
5. [데이터베이스 구조](#데이터베이스-구조)
6. [수정/삭제 정책](#수정삭제-정책)
7. [구현 순서](#구현-순서)

---

## 프로젝트 개요

### 현재 상황
- TO(작업 공고) 등록 시 **단일 날짜**만 선택 가능
- 여러 날짜에 같은 조건의 TO를 올리려면 반복 작성 필요

### 개선 목표
- 관리자가 **날짜 범위**로 TO 일괄 등록
- 지원자가 **원하는 날짜만 선택**하여 지원
- 관리자가 **날짜별로 개별 확정/거절** 가능
- TO 목록에서 **그룹으로 보기** + **날짜별 상세 관리**

---

## 현재 문제점

### 관리자 불편
```
10/24~10/30 (7일간) 피킹 모집 필요
→ 현재: TO 7개 각각 생성해야 함 ❌
→ 개선: 한 번에 날짜 범위 선택 ✅
```

### 지원자 불편
```
나는 10/24, 10/26, 10/28만 가능해
→ 현재: 각 날짜 TO 찾아서 개별 지원 ❌
→ 개선: 원하는 날짜 체크박스 선택 ✅
```

### 관리자 확정 불편
```
A 지원자가 24,26,28 지원
→ 24,26만 확정하고 28은 거절하고 싶음
→ 현재: 각 TO별로 따로 관리 ❌
→ 개선: 한 화면에서 날짜별 확정 ✅
```

---

## 해결 방안

### 핵심 아이디어: 템플릿 일괄 생성 + 그룹화

```
관리자가 TO 생성:
┌─────────────────────────────┐
│ 제목: 피킹 모집             │
│ 기간: 10/24 ~ 10/30 (7일)   │
│ 업무: 📦 피킹              │
│ 시간: 09:00 ~ 18:00        │
│ 금액: 15,000원             │
│ 인원: 5명/일               │
└─────────────────────────────┘
        ↓
자동으로 7개 TO 생성
- 10/24 피킹 TO (groupId: "group_xxx")
- 10/25 피킹 TO (groupId: "group_xxx")
- 10/26 피킹 TO (groupId: "group_xxx")
- 10/27 피킹 TO (groupId: "group_xxx")
- 10/28 피킹 TO (groupId: "group_xxx")
- 10/29 피킹 TO (groupId: "group_xxx")
- 10/30 피킹 TO (groupId: "group_xxx")

모두 같은 groupId로 연결!
```

### 장점
- ✅ 기존 DB 구조 거의 그대로 사용 (단순 필드 추가만)
- ✅ 날짜별 독립 관리 (복잡도 낮음)
- ✅ 그룹으로 묶어서 보기 (편의성 높음)
- ✅ 구현 난이도 적당

---

## 화면 설계

### 1단계: TO 목록 - 그룹 대표 카드

```
┌─────────────────────────────────┐
│ 📦 피킹 모집               [D-2시간]│
│ 10/24(금) ~ 10/28(화) · 5일간    │
│                                 │
│ 📦 피킹  09:00~18:00            │
│    15,000원/일                  │
│                                 │
│ 총 모집: 25명 (5일 × 5명)        │
│ 확정: 12명 | 대기: 8명           │
│                                 │
│ [📅 날짜별 상세보기 →]      [⋮]  │
└─────────────────────────────────┘
```

**표시 정보:**
- 그룹 대표 정보 (제목, 기간, 업무)
- 전체 통계 (총 모집, 확정, 대기)
- 마감까지 남은 시간
- 메뉴 버튼 (수정/삭제)

---

### 2단계: 날짜별 요약 화면

```
┌─────────────────────────────────┐
│ ← 📦 피킹 모집 (5일간)           │
│   10/24(금) ~ 10/28(화)     [⋮]  │
├─────────────────────────────────┤
│                                 │
│ 📅 10/24 (금)              [⋮]  │
│    모집 5명 | 확정 3명 | 대기 2명 │
│    [→ 지원자 관리]               │
│                                 │
├─────────────────────────────────┤
│                                 │
│ 📅 10/25 (토)              [⋮]  │
│    모집 5명 | 확정 2명 | 대기 1명 │
│    [→ 지원자 관리]               │
│                                 │
├─────────────────────────────────┤
│                                 │
│ 📅 10/26 (일)              [⋮]  │
│    모집 5명 | 확정 4명 | 대기 3명 │
│    [→ 지원자 관리]               │
│                                 │
├─────────────────────────────────┤
│                                 │
│ 📅 10/27 (월)              [⋮]  │
│    모집 5명 | 확정 1명 | 대기 0명 │
│    [→ 지원자 관리]               │
│                                 │
├─────────────────────────────────┤
│                                 │
│ 📅 10/28 (화)              [⋮]  │
│    모집 5명 | 확정 2명 | 대기 2명 │
│    [→ 지원자 관리]               │
│                                 │
└─────────────────────────────────┘
```

**기능:**
- 각 날짜별 통계 한눈에 확인
- 날짜 클릭 → 해당일 지원자 상세 관리
- 각 날짜별 메뉴 (수정/삭제)
- 상단 그룹 메뉴 (전체 수정/삭제)

---

### 3단계: 특정 날짜 지원자 관리

```
┌─────────────────────────────────┐
│ ← 10/24 (금) 지원자 관리         │
│   피킹 · 09:00~18:00 · 15,000원 │
│   모집 5명 | 확정 3명 | 대기 2명  │
├─────────────────────────────────┤
│ [확정 3명] [대기 2명] [전체 5명] │
├─────────────────────────────────┤
│                                 │
│ ✅ 홍길동                        │
│    확정됨 · 010-1234-5678       │
│    [거절하기]                    │
│                                 │
├─────────────────────────────────┤
│                                 │
│ ✅ 김철수                        │
│    확정됨 · 010-2345-6789       │
│    [거절하기]                    │
│                                 │
├─────────────────────────────────┤
│                                 │
│ ✅ 이영희                        │
│    확정됨 · 010-3456-7890       │
│    [거절하기]                    │
│                                 │
├─────────────────────────────────┤
│                                 │
│ ⏳ 박민수                        │
│    대기중 · 010-4567-8901       │
│    [확정] [거절]                 │
│                                 │
├─────────────────────────────────┤
│                                 │
│ ⏳ 최지훈                        │
│    대기중 · 010-5678-9012       │
│    [확정] [거절]                 │
│                                 │
└─────────────────────────────────┘
```

**기능:**
- 현재 화면: 기존 지원자 관리 화면 그대로 활용
- 날짜별 독립적으로 확정/거절 처리

---

## 데이터베이스 구조

### TOModel 필드 추가

```dart
class TOModel {
  final String id;
  final String businessId;
  final String businessName;
  
  // ✅ NEW: 그룹 관련 필드
  final String? groupId;        // 그룹 ID (예: "group_1698123456789")
  final String? groupName;      // 그룹 이름 (예: "피킹 모집")
  final DateTime? startDate;    // 그룹 시작일
  final DateTime? endDate;      // 그룹 종료일
  final bool isGroupMaster;     // 대표 TO 여부 (목록 표시용)
  
  // 기존 필드들
  final String title;
  final DateTime date;          // 개별 날짜
  final String startTime;
  final String endTime;
  final DateTime applicationDeadline;
  final int totalRequired;
  final int totalConfirmed;
  final String? description;
  final String creatorUID;
  final DateTime createdAt;
}
```

### Firestore 구조

```
tos (collection)
├─ to_id_1
│  ├─ groupId: "group_xxx"
│  ├─ groupName: "피킹 모집"
│  ├─ startDate: 2025-10-24
│  ├─ endDate: 2025-10-30
│  ├─ isGroupMaster: true     ← 대표 TO
│  ├─ date: 2025-10-24
│  └─ ... (기타 필드)
│
├─ to_id_2
│  ├─ groupId: "group_xxx"     ← 같은 그룹
│  ├─ groupName: "피킹 모집"
│  ├─ startDate: 2025-10-24
│  ├─ endDate: 2025-10-30
│  ├─ isGroupMaster: false     ← 일반 TO
│  ├─ date: 2025-10-25
│  └─ ... (기타 필드)
│
└─ to_id_3
   ├─ groupId: "group_xxx"     ← 같은 그룹
   └─ date: 2025-10-26
```

### ApplicationModel (변경 없음)

```dart
// 기존 구조 그대로 사용
// 각 날짜 TO에 개별적으로 지원서 생성
class ApplicationModel {
  final String id;
  final String toId;            // 특정 날짜 TO ID
  final String uid;
  final String selectedWorkType;
  final int wage;
  final String status;          // PENDING, CONFIRMED, REJECTED
  final DateTime appliedAt;
  // ...
}
```

**예시:**
```
지원자 A가 10/24, 10/26 지원
→ to_id_1 (10/24)에 application 1개
→ to_id_3 (10/26)에 application 1개
```

---

## 수정/삭제 정책

### 삭제 옵션

#### 1. 그룹 전체 삭제

```
┌─────────────────────────────────┐
│ ⚠️ 그룹 전체 삭제                │
│                                 │
│ 삭제될 내용:                     │
│ - 모든 날짜 TO (5개)            │
│ - 모든 지원서 (25개)            │
│ - 확정된 지원자 (12명)          │
│                                 │
│ 정말 삭제하시겠습니까?           │
│                                 │
│ [취소]  [삭제하기]               │
└─────────────────────────────────┘
```

**동작:**
- groupId가 같은 모든 TO 삭제
- 해당 TO의 모든 지원서 삭제
- 확정자 있으면 강력 경고

#### 2. 특정 날짜만 삭제

```
┌─────────────────────────────────┐
│ ⚠️ 10/26 (일) TO 삭제            │
│                                 │
│ 삭제될 내용:                     │
│ - 10/26 TO                      │
│ - 지원자 (7명)                  │
│ - 확정된 지원자 (4명)           │
│                                 │
│ 다른 날짜(10/24, 25, 27, 28)는  │
│ 유지됩니다.                      │
│                                 │
│ [취소]  [삭제하기]               │
└─────────────────────────────────┘
```

**동작:**
- 해당 날짜 TO만 삭제
- 그룹은 유지
- isGroupMaster가 true인 TO를 삭제하면 다음 TO가 대표가 됨

---

### 수정 정책

#### ✅ 항상 수정 가능
- **제목/설명**
- **마감 시간 연장**
- **모집 인원 증가**

#### ⚠️ 조건부 수정 가능

##### 1. 모집 인원 감소

```dart
// 체크 로직
if (새로운_인원 >= 확정_인원) {
  ✅ 바로 변경 가능
} else {
  ⚠️ 확정 취소 필요
}
```

**UI 플로우:**
```
┌─────────────────────────────────┐
│ 모집 인원 변경                   │
│                                 │
│ 현재: 5명 (확정 3명, 대기 2명)   │
│ 변경: 2명 ◀─ 입력               │
│                                 │
│ ⚠️ 확정 인원(3명)보다 적습니다   │
│                                 │
│ 최소 1명의 확정을 취소해야       │
│ 변경할 수 있습니다.              │
│                                 │
│ [확정 취소하고 변경하기]         │
│ [취소]                          │
└─────────────────────────────────┘
        ↓ 클릭
┌─────────────────────────────────┐
│ 확정 취소 선택                   │
│ (최소 1명 취소 필요)             │
├─────────────────────────────────┤
│ ☑️ 홍길동 (확정됨)              │
│    10-1234-5678                 │
│                                 │
│ ☐ 김철수 (확정됨)               │
│    10-2345-6789                 │
│                                 │
│ ☑️ 이영희 (확정됨)              │
│    10-3456-7890                 │
├─────────────────────────────────┤
│ 선택: 2명 취소                   │
│ → 모집 인원 2명으로 변경         │
│                                 │
│ [확정 취소 후 인원 변경]         │
└─────────────────────────────────┘
```

##### 2. 업무/금액/시간 변경

```dart
// 체크 로직
if (확정_인원 == 0) {
  ✅ 변경 가능
} else {
  ❌ 변경 불가
  💡 "확정자 전원 취소 후 가능"
}
```

**UI 예시:**
```
┌─────────────────────────────────┐
│ TO 수정                          │
├─────────────────────────────────┤
│ 제목: [피킹 모집________________]│
│ ✅ 언제든 수정 가능              │
│                                 │
│ 업무 유형: 📦 피킹               │
│ ⚠️ 확정자 3명 있음 - 변경 불가   │
│ [확정자 전원 취소하기]           │
│                                 │
│ 시간: 09:00 ~ 18:00             │
│ ⚠️ 확정자 있음 - 변경 불가       │
│                                 │
│ 금액: 15,000원                  │
│ ⚠️ 확정자 있음 - 변경 불가       │
│                                 │
│ 모집 인원: 5명 ▼                │
│ ✅ 증가 가능 (최대 99명)         │
│ ⚠️ 감소: 확정 3명 이상만 가능    │
│    [확정 취소하기]               │
│                                 │
│ 마감 시간: 10/23 18:00          │
│ ✅ 연장 가능                     │
│                                 │
│ [저장]  [취소]                   │
└─────────────────────────────────┘
```

#### ❌ 수정 불가능
- **날짜 변경** (삭제 후 재생성 필요)

---

### 수정/삭제 메뉴 구조

#### 그룹 카드 메뉴
```
┌─────────────────────────────────┐
│ 📦 피킹 모집           [⋮]       │
│ 10/24(금) ~ 10/28(화)            │
└─────────────────────────────────┘
        ↓ 클릭
┌─────────────────────┐
│ 📝 그룹 전체 수정    │
│ 📅 날짜 추가        │
│ ──────────────────  │
│ 🗑️ 그룹 전체 삭제   │
└─────────────────────┘
```

#### 날짜별 카드 메뉴
```
┌─────────────────────────────────┐
│ 📅 10/24 (금)           [⋮]     │
│    확정 3명 | 대기 2명            │
└─────────────────────────────────┘
        ↓ 클릭
┌─────────────────────┐
│ 📝 이 날짜만 수정    │
│ 🗑️ 이 날짜만 삭제   │
└─────────────────────┘
```

---

## 구현 순서

### Phase 1: 핵심 기능 (필수)

#### 1. TO 생성 화면 수정
```
파일: lib/screens/admin/admin_create_to_screen.dart

추가 사항:
- 날짜 범위 선택 UI
  - 시작일 선택
  - 종료일 선택
  - 단일 날짜 / 범위 선택 토글
  
- groupId 생성 로직
  String generateGroupId() {
    return 'group_${DateTime.now().millisecondsSinceEpoch}';
  }
  
- 날짜별 TO 자동 생성
  - 시작일~종료일 사이의 모든 날짜 생성
  - 첫 번째 TO는 isGroupMaster: true
  - 나머지는 isGroupMaster: false
```

#### 2. Firestore Service 수정
```
파일: lib/services/firestore_service.dart

추가 메서드:
- createTOGroup()           // 그룹 TO 일괄 생성
- getTOsByGroup()           // 같은 그룹 TO 조회
- getGroupTOsMaster()       // 대표 TO만 조회 (목록용)
- deleteGroupTOs()          // 그룹 전체 삭제
- deleteSingleTO()          // 특정 날짜만 삭제
```

#### 3. TO 목록 화면 수정
```
파일: lib/screens/admin/admin_to_list_screen.dart

변경 사항:
- isGroupMaster == true인 TO만 표시
- 그룹 통계 계산 (전체 확정/대기)
- 그룹 카드 클릭 → 날짜별 화면 이동
```

#### 4. 날짜별 요약 화면 생성
```
새 파일: lib/screens/admin/admin_group_to_detail_screen.dart

기능:
- 같은 그룹 TO 리스트 표시
- 각 날짜별 통계 표시
- 날짜 클릭 → 지원자 관리 화면
```

#### 5. 기존 지원자 관리 화면 연결
```
파일: lib/screens/admin/admin_to_detail_screen.dart

변경 사항:
- 기존 로직 그대로 사용
- 특정 날짜 TO의 지원자만 관리
```

---

### Phase 2: 수정/삭제 기능

#### 6. 그룹 삭제
```
기능:
- 그룹 전체 삭제
- 특정 날짜만 삭제
- 확정자 있을 때 경고

삭제 체크:
if (confirmedCount > 0) {
  showWarning("확정된 지원자 ${confirmedCount}명이 있습니다!");
}
```

#### 7. 인원 수정 (확정 취소 기능)
```
기능:
- 모집 인원 증가 (항상 가능)
- 모집 인원 감소
  → 확정 >= 새 인원이면 OK
  → 아니면 확정 취소 화면 표시
  
확정 취소 화면:
- 확정자 리스트
- 체크박스 선택
- 선택한 인원만큼 취소 후 인원 변경
```

#### 8. 업무/금액/시간 수정 제한
```
체크 로직:
if (confirmedCount > 0) {
  // 변경 불가
  showWarning("확정자가 있어 변경할 수 없습니다");
  showButton("확정자 전원 취소하기");
}
```

---

### Phase 3: 추가 기능 (선택)

#### 9. 날짜 추가 기능
```
기능:
- 기존 그룹에 새 날짜 TO 추가
- 같은 groupId로 연결
```

#### 10. 지원자 입장 UI
```
파일: lib/screens/user/all_to_list_screen.dart

변경 사항:
- 그룹 TO는 하나의 카드로 표시
- 카드 클릭 → 날짜 선택 화면
- 원하는 날짜 체크박스 선택하여 지원
```

---

## 핵심 로직 코드

### 1. 그룹 ID 생성
```dart
String generateGroupId() {
  return 'group_${DateTime.now().millisecondsSinceEpoch}';
}
```

### 2. 날짜별 TO 생성
```dart
Future<void> createTOGroup({
  required String businessId,
  required String businessName,
  required String groupName,
  required DateTime startDate,
  required DateTime endDate,
  required List<WorkDetailInput> workDetails,
  required String title,
  required DateTime applicationDeadline,
  required String creatorUID,
}) async {
  final groupId = generateGroupId();
  
  // 시작일~종료일 사이의 모든 날짜 계산
  List<DateTime> dates = [];
  DateTime currentDate = startDate;
  
  while (currentDate.isBefore(endDate.add(Duration(days: 1)))) {
    dates.add(currentDate);
    currentDate = currentDate.add(Duration(days: 1));
  }
  
  // 각 날짜별 TO 생성
  for (int i = 0; i < dates.length; i++) {
    final toData = {
      'businessId': businessId,
      'businessName': businessName,
      'groupId': groupId,
      'groupName': groupName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isGroupMaster': i == 0, // 첫 번째만 대표
      'date': Timestamp.fromDate(dates[i]),
      'title': title,
      'applicationDeadline': Timestamp.fromDate(applicationDeadline),
      'totalRequired': workDetails.fold(0, (sum, w) => sum + w.requiredCount!),
      'totalConfirmed': 0,
      'creatorUID': creatorUID,
      'createdAt': FieldValue.serverTimestamp(),
    };
    
    // TO 생성
    final toDoc = await _firestore.collection('tos').add(toData);
    
    // WorkDetails 생성
    for (int j = 0; j < workDetails.length; j++) {
      await _firestore
          .collection('tos')
          .doc(toDoc.id)
          .collection('workDetails')
          .add({
        'workType': workDetails[j].workType,
        'wage': workDetails[j].wage,
        'requiredCount': workDetails[j].requiredCount,
        'currentCount': 0,
        'startTime': workDetails[j].startTime,
        'endTime': workDetails[j].endTime,
        'order': j,
      });
    }
  }
}
```

### 3. 그룹 TO 조회
```dart
Future<List<TOModel>> getTOsByGroup(String groupId) async {
  final snapshot = await _firestore
      .collection('tos')
      .where('groupId', isEqualTo: groupId)
      .orderBy('date', descending: false)
      .get();

  return snapshot.docs
      .map((doc) => TOModel.fromMap(doc.data(), doc.id))
      .toList();
}
```

### 4. 대표 TO만 조회 (목록용)
```dart
Future<List<TOModel>> getGroupMasterTOs() async {
  final snapshot = await _firestore
      .collection('tos')
      .where('isGroupMaster', isEqualTo: true)
      .orderBy('date', descending: false)
      .get();

  return snapshot.docs
      .map((doc) => TOModel.fromMap(doc.data(), doc.id))
      .toList();
}
```

### 5. 인원 감소 체크
```dart
Future<bool> validateRequiredCountDecrease({
  required int currentRequired,
  required int newRequired,
  required int confirmedCount,
  required BuildContext context,
}) async {
  if (newRequired >= confirmedCount) {
    return true; // 바로 변경 가능
  }
  
  // 확정 취소 필요
  final needToCancel = confirmedCount - newRequired;
  
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('확정 취소 필요'),
      content: Text(
        '모집 인원을 $newRequired명으로 줄이려면\n'
        '확정된 지원자 ${needToCancel}명을 취소해야 합니다.\n\n'
        '확정 취소 화면으로 이동하시겠습니까?'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('취소'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('확정 취소하기'),
        ),
      ],
    ),
  );
  
  if (confirmed == true) {
    // 확정자 선택 화면으로 이동
    await showCancelConfirmedDialog(context, needToCancel);
  }
  
  return false;
}
```

---

## 체크리스트

### Phase 1: 핵심 기능
- [ ] TOModel에 그룹 필드 추가 (groupId, groupName, startDate, endDate, isGroupMaster)
- [ ] TO 생성 화면에 날짜 범위 선택 UI 추가
- [ ] createTOGroup() 메서드 구현
- [ ] getTOsByGroup() 메서드 구현
- [ ] TO 목록에서 대표 카드만 표시
- [ ] 날짜별 요약 화면 생성
- [ ] 기존 지원자 관리 화면 연결

### Phase 2: 수정/삭제
- [ ] 그룹 전체 삭제 기능
- [ ] 특정 날짜만 삭제 기능
- [ ] 삭제 시 확정자 경고
- [ ] 인원 증가 기능
- [ ] 인원 감소 + 확정 취소 기능
- [ ] 업무/금액/시간 수정 제한
- [ ] 확정자 전원 취소 기능

### Phase 3: 추가 기능
- [ ] 날짜 추가 기능
- [ ] 지원자 입장 날짜 선택 UI
- [ ] 그룹 통계 대시보드

---

## 주의사항

### 1. 기존 TO와의 호환성
```dart
// groupId가 null이면 단일 TO (기존 방식)
if (to.groupId == null) {
  // 단일 TO 처리
} else {
  // 그룹 TO 처리
}
```

### 2. isGroupMaster 관리
```
- 그룹의 첫 번째 TO만 true
- 대표 TO 삭제 시 다음 TO가 대표가 됨
- 목록에서는 대표 TO만 표시
```

### 3. 날짜 순서 보장
```dart
// 항상 날짜 오름차순 정렬
.orderBy('date', descending: false)
```

### 4. 트랜잭션 처리
```dart
// 그룹 삭제 시 배치 처리
final batch = _firestore.batch();
for (var to in groupTOs) {
  batch.delete(_firestore.collection('tos').doc(to.id));
}
await batch.commit();
```

---

## 예상 질문 & 답변

### Q1. 기존 단일 TO는 어떻게 되나요?
**A:** 기존 TO는 groupId가 null이므로 그대로 작동합니다. 호환성 유지됩니다.

### Q2. 날짜 추가는 어떻게 하나요?
**A:** 같은 groupId를 가진 새 TO를 생성하면 됩니다. isGroupMaster는 false로 설정.

### Q3. 대표 TO를 삭제하면?
**A:** 같은 그룹의 다음 TO가 자동으로 isGroupMaster: true로 변경됩니다.

### Q4. 지원자는 여러 날짜에 한 번에 지원할 수 있나요?
**A:** Phase 3에서 구현 예정. 각 날짜 TO에 개별 지원서가 생성됩니다.

### Q5. 그룹 전체 수정은 가능한가요?
**A:** 확정자가 없으면 가능. 제목/설명은 항상 가능, 업무/금액/시간은 확정자 있으면 불가.

---

## 참고 자료

### 관련 파일
```
lib/
├── models/
│   └── to_model.dart                    (수정 필요)
├── services/
│   └── firestore_service.dart           (수정 필요)
├── screens/
│   ├── admin/
│   │   ├── admin_create_to_screen.dart  (수정 필요)
│   │   ├── admin_to_list_screen.dart    (수정 필요)
│   │   ├── admin_to_detail_screen.dart  (기존 활용)
│   │   └── admin_group_to_detail_screen.dart (신규 생성)
│   └── user/
│       └── all_to_list_screen.dart      (Phase 3)
```

### 테스트 시나리오
1. 단일 날짜 TO 생성 (기존 방식)
2. 날짜 범위 TO 생성 (5일)
3. 그룹 목록 확인
4. 날짜별 화면 확인
5. 특정 날짜 지원자 관리
6. 인원 수정 (증가/감소)
7. 그룹 전체 삭제
8. 특정 날짜 삭제

---

## 버전 이력

| 버전 | 날짜 | 내용 |
|------|------|------|
| 1.0 | 2025-10-24 | 초안 작성 - 그룹 TO 기능 설계 |

---

**작성자:** AI Assistant  
**검토자:** 개발팀  
**최종 수정일:** 2025-10-24
