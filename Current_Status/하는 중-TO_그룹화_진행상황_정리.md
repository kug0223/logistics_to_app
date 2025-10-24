# TO 그룹화 기능 구현 진행상황

## 📅 작업 일자
2025-10-24

---

## ✅ 완료된 작업 (Phase 1)

### 1. 데이터 모델 수정 ✅
**파일:** `lib/models/to_model.dart`

**추가된 필드:**
```dart
final String? groupId;        // 그룹 ID
final String? groupName;      // 그룹 이름
final DateTime? startDate;    // 그룹 시작일
final DateTime? endDate;      // 그룹 종료일
final bool isGroupMaster;     // 대표 TO 여부 (기본값 false)
```

**추가된 Getter:**
```dart
bool get isGroupTO            // 그룹 TO인지 확인
String? get groupPeriodString // "10/24~10/30" 형식
int? get groupDaysCount       // 그룹 일수
String get formattedDate      // "10/24 (금)" 형식
String get weekday            // "금"
String get deadlineStatus     // "D-2시간"
bool get isDeadlineSoon       // 24시간 이내 여부
bool get isGrouped            // 그룹화 여부
bool get isFull               // 정원 마감 여부
int get availableSlots        // 남은 자리
String get timeRange          // "09:00~18:00"
String get formattedDeadline  // "10/23 18:00"
```

**결과:** 
- ✅ 그룹 정보 저장 가능
- ✅ 편의 메서드로 UI 표시 간편화

---

### 2. Firestore Service 메서드 추가 ✅
**파일:** `lib/services/firestore_service.dart`

**추가된 메서드:**

#### 그룹 생성
```dart
String generateGroupId()
// → 'group_1698123456789' 형식 ID 생성

Future<bool> createTOGroup({
  required String businessId,
  required String businessName,
  required String groupName,
  required String title,
  required DateTime startDate,
  required DateTime endDate,
  required List<Map<String, dynamic>> workDetails,
  required DateTime applicationDeadline,
  String? description,
  required String creatorUID,
})
// → 시작일~종료일 사이 모든 날짜 TO 자동 생성
// → 첫 번째 TO만 isGroupMaster: true
```

#### 그룹 조회
```dart
Future<List<TOModel>> getTOsByGroup(String groupId)
// → 같은 그룹의 모든 TO 조회 (날짜 오름차순)

Future<List<TOModel>> getGroupMasterTOs()
// → isGroupMaster == true OR groupId == null인 TO만
// → 목록 화면에 표시할 TO들

Future<List<ApplicationModel>> getApplicationsByGroup(String groupId)
// → 그룹 전체 지원자 조회
```

#### 그룹 삭제
```dart
Future<bool> deleteGroupTOs(String groupId)
// → 그룹 전체 TO + WorkDetails + 지원서 일괄 삭제

Future<bool> deleteSingleTOFromGroup(String toId, String? groupId)
// → 특정 날짜 TO만 삭제
// → 대표 TO 삭제 시 다음 TO가 대표로
```

**결과:**
- ✅ 날짜 범위 TO 일괄 생성 가능
- ✅ 그룹별 조회/삭제 가능

---

### 3. TO 생성 화면 수정 ✅
**파일:** `lib/screens/admin/admin_create_to_screen.dart`

**추가된 기능:**

#### UI 변경
```
┌─────────────────────────────────┐
│ 📅 근무 날짜                     │
│ ┌───────────┬───────────┐       │
│ │ 단일 날짜 │ 날짜 범위 │ ← 토글 │
│ └───────────┴───────────┘       │
└─────────────────────────────────┘
```

**단일 날짜 모드:**
```
📅 2025-10-24 선택
→ [TO 생성] 버튼
→ 1개 TO 생성
```

**날짜 범위 모드:**
```
시작일: 2025-10-24
종료일: 2025-10-30
💡 총 7일간의 TO가 생성됩니다
→ [TO 그룹 생성] 버튼
→ 7개 TO 생성 (같은 groupId)
```

#### 코드 구조
```dart
// 상태 변수 추가
String _dateMode = 'single';  // 'single' 또는 'range'
DateTime? _startDate;
DateTime? _endDate;

// 생성 로직 분기
if (_dateMode == 'single') {
  await _createSingleTO();    // 기존 방식
} else {
  await _createTOGroup();     // 신규 - FirestoreService 호출
}
```

**결과:**
- ✅ 단일/범위 선택 UI
- ✅ 날짜 범위 선택 시 일수 표시
- ✅ 버튼 텍스트 동적 변경
- ✅ 검증 로직 (종료일 >= 시작일)

---

### 4. TO 목록 화면 수정 ✅
**파일:** `lib/screens/admin/admin_to_list_screen.dart`

**변경 사항:**

#### 조회 메서드 변경
```dart
// 변경 전
final allTOs = await _firestoreService.getAllTOs();

// 변경 후
final allTOs = await _firestoreService.getGroupMasterTOs();
```

#### 날짜 표시 수정
```dart
// 그룹 TO면 범위, 아니면 단일 날짜
to.isGroupTO && to.groupPeriodString != null
    ? '${to.groupPeriodString} (${to.groupDaysCount}일)'
    : dateFormat.format(to.date)
```

**결과:**
- ✅ 그룹 TO는 1개만 표시 (대표)
- ✅ 단일 TO는 그대로 표시
- ✅ 그룹 TO는 "10/25~10/27 (3일)" 형식

**화면 예시:**
```
┌─────────────────────────────────┐
│ 테스트1                          │
│ 테스트 단일 TO                   │
│ 📅 2025-10-25 (토) ⏰ 09:00~18:00│
│ 👥 확정: 0/2  ⏳ 대기: 0        │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ 테스트1                          │
│ 테스트 그룹TO                    │
│ 📅 10/25~10/27 (3일) ⏰ 09:00~18:00│
│ 👥 확정: 0/1  ⏳ 대기: 0        │
└─────────────────────────────────┘
```

---

### 5. Import 및 에러 수정 ✅

**추가된 Import:**
```dart
// admin_create_to_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
```

**수정된 코드:**
```dart
// WorkDetailInput 클래스에 필드 추가
final String? workTypeIcon;
final String? workTypeColor;

// Firestore 접근 방식 변경
_firestoreService._firestore  →  FirebaseFirestore.instance

// const 제거 (동적 텍스트)
const Text(_dateMode ...)  →  Text(_dateMode ...)
```

---

## 🔄 테스트 완료 항목

### ✅ 단일 날짜 TO 생성
- [x] TO 생성 화면 진입
- [x] [단일 날짜] 선택
- [x] 날짜 1개 선택
- [x] 업무 추가 후 생성
- [x] 목록에 1개 TO 표시 확인

### ✅ 날짜 범위 TO 생성
- [x] [날짜 범위] 선택
- [x] 시작일/종료일 선택
- [x] "총 X일간의 TO가 생성됩니다" 표시
- [x] 생성 성공 (3개 TO 생성)
- [x] 목록에 그룹 카드 1개만 표시
- [x] 날짜 범위 형식 "10/25~10/27 (3일)" 표시

### ✅ Firestore 데이터 확인
- [x] groupId 동일
- [x] isGroupMaster 첫 번째만 true
- [x] startDate, endDate 정상 저장
- [x] date 각각 다른 날짜

---

## 📋 남은 작업 (Phase 2)

### 🔴 우선순위 1: TO 카드에 업무 유형 정보 표시

**현재 문제:**
```
TO 카드에 업무 유형(피킹, 배송 등)이 표시되지 않음
```

**목표 UI:**
```
┌─────────────────────────────────┐
│ 테스트1                          │
│ 테스트 그룹TO                    │
│                                 │
│ 📦 피킹  09:00~18:00            │  ← 추가 필요
│    15,000원/일                  │  ← 추가 필요
│                                 │
│ 📅 10/25~10/27 (3일)            │
│ 👥 확정: 0/3  ⏳ 대기: 0        │
└─────────────────────────────────┘
```

**작업 내용:**

#### 1. WorkDetail 정보 로드
**파일:** `admin_to_list_screen.dart`

**수정 위치:** `_loadTOsWithStats()` 메서드

```dart
// 각 TO별 통계를 병렬로 조회
final tosWithStats = await Future.wait(
  allTOs.map((to) async {
    final applications = await _firestoreService.getApplicationsByTOId(to.id);
    
    // ✅ NEW: WorkDetails 조회 추가
    final workDetails = await _firestoreService.getWorkDetails(to.id);
    
    final confirmedCount = applications
        .where((app) => app.status == 'CONFIRMED')
        .length;
    
    final pendingCount = applications
        .where((app) => app.status == 'PENDING')
        .length;
    
    return _TOWithStats(
      to: to,
      workDetails: workDetails,  // ✅ 추가
      confirmedCount: confirmedCount,
      pendingCount: pendingCount,
    );
  }).toList(),
);
```

#### 2. _TOWithStats 클래스 수정
**위치:** 파일 하단

```dart
class _TOWithStats {
  final TOModel to;
  final List<WorkDetailModel> workDetails;  // ✅ 추가
  final int confirmedCount;
  final int pendingCount;

  _TOWithStats({
    required this.to,
    required this.workDetails,  // ✅ 추가
    required this.confirmedCount,
    required this.pendingCount,
  });
}
```

#### 3. _buildTOCard() UI 수정
**위치:** `_buildTOCard()` 메서드 내부

**추가할 위치:**
```dart
// ✅ 제목
Text(
  to.title,
  style: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.grey[800],
  ),
),
const SizedBox(height: 8),

// ✅ NEW: 업무 상세 정보 표시
if (item.workDetails.isNotEmpty) ...[
  ...item.workDetails.map((work) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          // 아이콘
          if (work.workTypeIcon != null)
            Text(
              work.workTypeIcon!,
              style: const TextStyle(fontSize: 16),
            )
          else
            Icon(Icons.work, size: 16, color: Colors.grey[600]),
          
          const SizedBox(width: 8),
          
          // 업무명 + 시간
          Expanded(
            child: Text(
              '${work.workType}  ${work.startTime}~${work.endTime}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          // 급여
          Text(
            '${NumberFormat('#,###').format(work.wage)}원',
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }).toList(),
  const SizedBox(height: 8),
],

// 날짜 + 시간 (기존 코드)
Row(
```

#### 4. Import 추가
**파일 상단:**
```dart
import '../../models/work_detail_model.dart';
```

---

### 🟡 우선순위 2: 날짜별 상세 화면 (그룹 TO 클릭 시)

**목표:**
```
그룹 TO 클릭 → 날짜별 요약 화면
├─ 📅 10/25 (금) - 확정 3명, 대기 2명 [→]
├─ 📅 10/26 (토) - 확정 2명, 대기 1명 [→]
└─ 📅 10/27 (일) - 확정 1명, 대기 0명 [→]
   각 날짜 클릭 → 지원자 관리 화면
```

**작업 파일:**
- 새 파일 생성: `lib/screens/admin/admin_group_to_detail_screen.dart`
- 수정: `admin_to_list_screen.dart` (클릭 시 분기)

**화면 구조:**
```dart
// 그룹 TO 클릭 시 분기
onTap: () async {
  if (to.isGroupTO) {
    // 그룹 TO → 날짜별 화면
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminGroupTODetailScreen(
          groupId: to.groupId!,
          groupName: to.groupName!,
        ),
      ),
    );
  } else {
    // 단일 TO → 기존 지원자 관리
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminTODetailScreen(to: to),
      ),
    );
  }
}
```

---

### 🟡 우선순위 3: 수정/삭제 기능

#### 그룹 메뉴
```
┌─────────────────────┐
│ 📝 그룹 전체 수정    │
│ 📅 날짜 추가        │
│ ──────────────────  │
│ 🗑️ 그룹 전체 삭제   │
└─────────────────────┘
```

#### 삭제 확인 다이얼로그
```
┌─────────────────────────────────┐
│ ⚠️ 그룹 전체 삭제                │
│                                 │
│ 삭제될 내용:                     │
│ - 모든 날짜 TO (3개)            │
│ - 모든 지원서 (15개)            │
│ - 확정된 지원자 (8명)           │
│                                 │
│ 정말 삭제하시겠습니까?           │
│                                 │
│ [취소]  [삭제하기]               │
└─────────────────────────────────┘
```

---

### 🟢 우선순위 4: 지원자 입장 UI

**현재 상태:**
- 지원자가 TO 목록에서 그룹 TO를 보면 3개가 모두 보임

**목표:**
```
그룹 TO 클릭 → 날짜 선택 화면
├─ ☑️ 10/25 (금) - 남은 자리 2/5
├─ ☐ 10/26 (토) - 남은 자리 3/5
└─ ☑️ 10/27 (일) - 남은 자리 5/5
   [지원하기] → 선택한 날짜만 지원
```

**작업 파일:**
- `lib/screens/user/all_to_list_screen.dart` 수정
- 새 파일: `lib/screens/user/group_to_date_selection_screen.dart`

---

## 📊 전체 진행률

```
Phase 1: 핵심 기능 (관리자)     ████████████ 100%
├─ TO 모델 수정                ✅ 완료
├─ FirestoreService            ✅ 완료
├─ TO 생성 화면                ✅ 완료
└─ TO 목록 화면                ✅ 완료

Phase 2: 추가 기능
├─ 업무 유형 표시              ⬜ 대기 (우선)
├─ 날짜별 상세 화면            ⬜ 대기
├─ 수정/삭제                   ⬜ 대기
└─ 지원자 입장 UI              ⬜ 대기

전체 진행률: ████░░░░░░░░ 40%
```

---

## 🎯 다음 작업

**즉시 진행:**
1. TO 카드에 업무 유형 정보 표시
   - WorkDetails 로드
   - UI 수정
   - 테스트

**이후 순서:**
2. 날짜별 상세 화면 생성
3. 그룹 삭제 기능
4. 지원자 입장 날짜 선택

---

## 📝 참고사항

### Firestore 구조
```
tos (collection)
├─ to_id_1 (대표 TO)
│  ├─ groupId: "group_xxx"
│  ├─ isGroupMaster: true
│  ├─ startDate: 2025-10-25
│  ├─ endDate: 2025-10-27
│  ├─ date: 2025-10-25
│  └─ workDetails (subcollection)
│     ├─ work_1
│     └─ work_2
│
├─ to_id_2
│  ├─ groupId: "group_xxx"
│  ├─ isGroupMaster: false
│  └─ date: 2025-10-26
│
└─ to_id_3
   ├─ groupId: "group_xxx"
   ├─ isGroupMaster: false
   └─ date: 2025-10-27
```

### 핵심 로직
- **목록 표시:** isGroupMaster == true OR groupId == null
- **그룹 확인:** groupId != null
- **날짜 범위:** startDate ~ endDate
- **일수 계산:** endDate - startDate + 1

---

**작성일:** 2025-10-24  
**작성자:** AI Assistant  
**다음 업데이트:** 업무 유형 표시 완료 후
