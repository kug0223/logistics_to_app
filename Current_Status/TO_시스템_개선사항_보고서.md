# 🚀 TO 관리 시스템 개선사항 종합 보고서

**작성일:** 2025년 10월 24일  
**프로젝트:** Flutter + Firebase TO 관리 앱  
**목적:** WorkDetails 하위 컬렉션 전환 후 추가 개선사항 구현

---

## 📋 목차

1. [현재 시스템 상태](#현재-시스템-상태)
2. [개선사항 1: 업무별 근무시간](#개선사항-1-업무별-근무시간)
3. [개선사항 2: TO 그룹 관리](#개선사항-2-to-그룹-관리)
4. [개선사항 3: TO 공고 등록 횟수 제한](#개선사항-3-to-공고-등록-횟수-제한)
5. [개선사항 4: 차량등록 기능](#개선사항-4-차량등록-기능)
6. [구현 순서](#구현-순서)
7. [데이터 구조 변경 요약](#데이터-구조-변경-요약)

---

## 현재 시스템 상태

### ✅ 완료된 작업
- TOModel에서 WorkDetails 하위 컬렉션으로 분리
- 업무유형별 인원 관리 (currentCount, requiredCount)
- 지원 시 업무유형 선택 기능
- 업무유형 변경 이력 관리
- 전체 인원 집계 (totalRequired, totalConfirmed)

### 📁 현재 데이터 구조

```
tos/{toId}
  ├─ businessId
  ├─ businessName
  ├─ title
  ├─ date
  ├─ startTime        // ⚠️ 제거 예정
  ├─ endTime          // ⚠️ 제거 예정
  ├─ applicationDeadline
  ├─ totalRequired
  ├─ totalConfirmed
  ├─ description
  ├─ creatorUID
  ├─ createdAt
  └─ workDetails/{workDetailId}
       ├─ workType
       ├─ wage
       ├─ requiredCount
       ├─ currentCount
       ├─ order
       └─ createdAt
```

---

## 개선사항 1: 업무별 근무시간

### 🎯 목적
각 업무유형마다 근무시간이 다를 수 있음 (예: 피킹 09:00-18:00, 패킹 14:00-23:00)

### 📝 변경사항

#### 1. TOModel 수정
```dart
// ❌ 제거
final String startTime;
final String endTime;
```

#### 2. WorkDetailModel 수정
```dart
// ✅ 추가
final String startTime;  // 예: "09:00"
final String endTime;    // 예: "18:00"

// 편의 메서드 추가
String get timeRange => '$startTime ~ $endTime';
```

#### 3. Firestore 구조
```
workDetails/{workDetailId}
  ├─ workType: "피킹"
  ├─ wage: 50000
  ├─ requiredCount: 5
  ├─ currentCount: 3
  ├─ startTime: "09:00"    // ✅ 추가
  ├─ endTime: "18:00"      // ✅ 추가
  ├─ order: 0
  └─ createdAt: Timestamp
```

### 🔧 수정 파일 목록

1. **lib/models/work_detail_model.dart**
   - `startTime`, `endTime` 필드 추가
   - `timeRange` getter 추가
   - `fromMap`, `toMap` 수정

2. **lib/screens/admin/admin_create_to_screen.dart**
   - TO 레벨 시간 입력 UI 제거
   - 업무 추가 다이얼로그에 시간 입력 추가
   ```dart
   class WorkDetailInput {
     final String? workType;
     final int? wage;
     final int? requiredCount;
     final String? startTime;  // ✅ 추가
     final String? endTime;    // ✅ 추가
   }
   ```

3. **lib/services/firestore_service.dart**
   - `createWorkDetails` 메서드 수정
   ```dart
   batch.set(docRef, {
     'workType': data['workType'],
     'wage': data['wage'],
     'requiredCount': data['requiredCount'],
     'currentCount': 0,
     'startTime': data['startTime'],     // ✅ 추가
     'endTime': data['endTime'],         // ✅ 추가
     'order': i,
     'createdAt': FieldValue.serverTimestamp(),
   });
   ```

4. **lib/widgets/to_card_widget.dart**
   - 시간 표시 제거 또는 "업무별 시간 상이" 표시

5. **lib/screens/user/to_detail_screen.dart**
   - WorkDetail 카드에 시간 표시 추가

### 🎨 UI 예시

#### 업무 추가 다이얼로그
```
┌─────────────────────────────────────┐
│ 업무 추가                            │
├─────────────────────────────────────┤
│                                      │
│ 업무 유형 *                          │
│ [피킹 ▼]                             │
│                                      │
│ 근무 시간 *                          │
│ [09:00 ▼]  ~  [18:00 ▼]            │
│                                      │
│ 금액 (원) *                          │
│ [50000_____________]                 │
│                                      │
│ 필요 인원 (명) *                     │
│ [5_____]                             │
│                                      │
│           [취소]  [추가]             │
└─────────────────────────────────────┘
```

---

## 개선사항 2: TO 그룹 관리

### 🎯 목적
같은 내용의 TO를 여러 개 등록했을 때 지원자 명단을 합쳐서 관리

### 💡 사용 시나리오
```
예시 1: 분리
- "물류센터 파트타임 (10/25)" - 독립적인 TO
- "물류센터 파트타임 (10/26)" - 독립적인 TO
→ 각각 따로 지원자 관리

예시 2: 연결
- "물류센터 파트타임 (10/25 오전)" - 그룹A
- "물류센터 파트타임 (10/25 오후)" - 그룹A
→ 지원자 명단 합쳐서 출력
```

### 📝 변경사항

#### 1. TOModel 수정
```dart
final String? groupId;  // ✅ 추가: 같은 그룹의 TO들을 묶음
final String? groupName; // ✅ 추가: 그룹 표시명 (선택사항)
```

#### 2. Firestore 구조
```
tos/{toId}
  ├─ groupId: "group_abc123"      // ✅ 추가 (null 가능)
  ├─ groupName: "물류센터_1025"   // ✅ 추가 (null 가능)
  ├─ businessId
  ├─ title
  └─ ...
```

### 🔧 수정 파일 목록

1. **lib/models/to_model.dart**
   - `groupId`, `groupName` 필드 추가

2. **lib/screens/admin/admin_create_to_screen.dart**
   - "기존 공고와 연결" 체크박스 추가
   - 기존 TO 선택 드롭다운 추가
   ```dart
   bool _linkToExisting = false;
   String? _selectedGroupId;
   List<TOModel> _myRecentTOs = [];
   ```

3. **lib/services/firestore_service.dart**
   - 그룹 ID 생성 메서드
   ```dart
   String generateGroupId() {
     return 'group_${DateTime.now().millisecondsSinceEpoch}';
   }
   ```
   - 사용자의 최근 TO 조회 메서드
   ```dart
   Future<List<TOModel>> getRecentTOsByUser(String uid, {int days = 30})
   ```

4. **lib/screens/admin/admin_to_detail_screen.dart**
   - 그룹 정보 표시
   - "같은 그룹의 다른 TO" 목록 표시

5. **지원자 명단 출력 (신규 기능)**
   - 그룹별로 지원자 합산
   ```dart
   Future<List<ApplicationModel>> getApplicationsByGroup(String groupId)
   ```

### 🎨 UI 예시

#### TO 생성 화면
```
┌─────────────────────────────────────┐
│ 📝 TO 제목                           │
│ [물류센터 파트타임알바_________]     │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🔗 기존 공고와 연결                  │
│                                      │
│ ☐ 기존 공고와 같은 TO입니다          │
│   (선택 시 지원자 명단이 합쳐집니다) │
│                                      │
│ [기존 공고 선택 ▼]                   │
│ ┌─────────────────────────────┐     │
│ │ 물류센터 파트타임 (10/25)    │     │
│ │ 쿠팡 물류센터 (10/26)        │     │
│ └─────────────────────────────┘     │
└─────────────────────────────────────┘
```

#### TO 상세 화면 (그룹 연결된 경우)
```
┌─────────────────────────────────────┐
│ 🔗 연결된 공고                       │
│                                      │
│ 이 TO는 다음 공고들과 연결되어       │
│ 지원자 명단이 합쳐집니다:            │
│                                      │
│ • 물류센터 파트타임 (10/25 오전)     │
│ • 물류센터 파트타임 (10/25 오후) ✓   │
│ • 물류센터 파트타임 (10/26)          │
│                                      │
│ 총 지원자: 15명 / 총 필요: 20명      │
└─────────────────────────────────────┘
```

---

## 개선사항 3: TO 공고 등록 횟수 제한

### 🎯 목적
중복 공고 방지 및 플랫폼 품질 관리 (당근마켓처럼 최대 2개 제한)

### 📝 변경사항

#### 1. BusinessModel 수정
```dart
final int maxTOCount;  // ✅ 추가: 최대 TO 공고 수 (기본값: 5)
```

#### 2. Firestore 구조
```
businesses/{businessId}
  ├─ maxTOCount: 2    // ✅ 추가
  ├─ businessNumber
  ├─ name
  └─ ...
```

### 🔧 수정 파일 목록

1. **lib/models/business_model.dart**
   - `maxTOCount` 필드 추가 (기본값: 5)

2. **lib/screens/admin/business_registration_screen.dart**
   - 사업장 등록 시 maxTOCount는 기본값으로 설정 (수정 불가)

3. **lib/screens/super_admin/business_management_screen.dart** (신규 또는 수정)
   - 최고관리자만 maxTOCount 수정 가능
   ```dart
   TextFormField(
     initialValue: business.maxTOCount.toString(),
     decoration: InputDecoration(
       labelText: '최대 TO 공고 수',
       helperText: '이 사업장이 동시에 등록할 수 있는 TO 수',
     ),
     keyboardType: TextInputType.number,
   )
   ```

4. **lib/screens/admin/admin_create_to_screen.dart**
   - TO 생성 전 개수 체크
   ```dart
   @override
   void initState() {
     super.initState();
     _checkTOLimit();
   }
   
   Future<void> _checkTOLimit() async {
     final activeTOCount = await _firestoreService.getActiveTOCount(businessId);
     if (activeTOCount >= business.maxTOCount) {
       _showLimitReachedDialog();
     }
   }
   ```

5. **lib/services/firestore_service.dart**
   - 활성 TO 개수 조회
   ```dart
   Future<int> getActiveTOCount(String businessId) async {
     final snapshot = await _firestore
         .collection('tos')
         .where('businessId', isEqualTo: businessId)
         .where('date', isGreaterThanOrEqualTo: DateTime.now())
         .get();
     return snapshot.docs.length;
   }
   ```
   - TO 생성 전 검증
   ```dart
   Future<bool> canCreateTO(String businessId) async {
     final business = await getBusiness(businessId);
     final activeCount = await getActiveTOCount(businessId);
     return activeCount < business.maxTOCount;
   }
   ```

### 🎨 UI 예시

#### 제한 도달 시 알림
```
┌─────────────────────────────────────┐
│ ⚠️ TO 공고 제한                      │
├─────────────────────────────────────┤
│                                      │
│ 현재 2개의 TO 공고가 등록되어        │
│ 있습니다.                            │
│                                      │
│ 이 사업장은 최대 2개까지만           │
│ TO 공고를 등록할 수 있습니다.        │
│                                      │
│ 기존 공고를 삭제하거나 마감된 후     │
│ 새로운 공고를 등록해주세요.          │
│                                      │
│          [기존 공고 보기]  [확인]    │
└─────────────────────────────────────┘
```

#### TO 생성 화면 상단
```
┌─────────────────────────────────────┐
│ ℹ️ 등록 가능 횟수: 1 / 2             │
└─────────────────────────────────────┘
```

---

## 개선사항 4: 차량등록 기능

### 🎯 목적
주차장 이용 시 차량번호 사전 등록 필수인 사업장 대응

### 📝 변경사항

#### 1. BusinessModel 수정
```dart
final bool requiresVehicleRegistration;  // ✅ 추가: 차량등록 필수 여부
```

#### 2. UserModel 수정
```dart
final List<VehicleInfo>? vehicles;  // ✅ 추가: 사용자의 차량 목록

class VehicleInfo {
  final String plateNumber;      // 차량번호 (예: "12가3456")
  final String? vehicleType;      // 차종 (선택사항)
  final DateTime registeredAt;    // 등록일
  final DateTime? lastUsedAt;     // 마지막 사용일
  
  VehicleInfo({
    required this.plateNumber,
    this.vehicleType,
    required this.registeredAt,
    this.lastUsedAt,
  });
  
  factory VehicleInfo.fromMap(Map<String, dynamic> map) {
    return VehicleInfo(
      plateNumber: map['plateNumber'] ?? '',
      vehicleType: map['vehicleType'],
      registeredAt: (map['registeredAt'] as Timestamp).toDate(),
      lastUsedAt: map['lastUsedAt'] != null 
          ? (map['lastUsedAt'] as Timestamp).toDate() 
          : null,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'plateNumber': plateNumber,
      'vehicleType': vehicleType,
      'registeredAt': Timestamp.fromDate(registeredAt),
      'lastUsedAt': lastUsedAt != null 
          ? Timestamp.fromDate(lastUsedAt!) 
          : null,
    };
  }
}
```

#### 3. ApplicationModel 수정
```dart
final String? vehiclePlateNumber;  // ✅ 추가: 이 지원에 사용한 차량번호
```

#### 4. Firestore 구조
```
businesses/{businessId}
  └─ requiresVehicleRegistration: true  // ✅ 추가

users/{uid}
  └─ vehicles: [                         // ✅ 추가
       {
         plateNumber: "12가3456",
         vehicleType: "소나타",
         registeredAt: Timestamp,
         lastUsedAt: Timestamp
       }
     ]

applications/{applicationId}
  └─ vehiclePlateNumber: "12가3456"     // ✅ 추가
```

### 🔧 수정 파일 목록

1. **lib/models/business_model.dart**
   - `requiresVehicleRegistration` 필드 추가

2. **lib/models/user_model.dart**
   - `vehicles` 필드 추가
   - `VehicleInfo` 클래스 생성

3. **lib/models/application_model.dart**
   - `vehiclePlateNumber` 필드 추가

4. **lib/screens/admin/business_registration_screen.dart**
   - 차량등록 필수 체크박스 추가
   ```dart
   SwitchListTile(
     title: Text('차량등록 필수'),
     subtitle: Text('지원자가 차량번호를 등록해야 합니다'),
     value: _requiresVehicleRegistration,
     onChanged: (value) {
       setState(() => _requiresVehicleRegistration = value);
     },
   )
   ```

5. **lib/screens/user/to_detail_screen.dart**
   - 지원 시 차량 체크 로직 추가
   ```dart
   Future<void> _handleApply(WorkDetailModel selectedWork) async {
     // 1. 사업장 정보 조회
     final business = await _firestoreService.getBusiness(widget.to.businessId);
     
     String? vehiclePlateNumber;
     
     // 2. 차량등록 필요 여부 확인
     if (business.requiresVehicleRegistration) {
       final userProvider = Provider.of<UserProvider>(context, listen: false);
       final userVehicles = userProvider.currentUser?.vehicles ?? [];
       
       if (userVehicles.isEmpty) {
         // 차량 정보 입력 다이얼로그
         final vehicleInfo = await _showVehicleInputDialog();
         if (vehicleInfo == null) return; // 취소
         
         vehiclePlateNumber = vehicleInfo.plateNumber;
         
         // 사용자가 저장 선택 시
         await _firestoreService.addUserVehicle(uid, vehicleInfo);
       } else {
         // 기존 차량 선택 다이얼로그
         final selectedVehicle = await _showVehicleSelectionDialog(userVehicles);
         if (selectedVehicle == null) return; // 취소
         
         vehiclePlateNumber = selectedVehicle.plateNumber;
         
         // 마지막 사용일 업데이트
         await _firestoreService.updateVehicleLastUsed(uid, vehiclePlateNumber);
       }
     }
     
     // 3. 지원 진행
     final success = await _firestoreService.applyToTOWithWorkType(
       toId: widget.to.id,
       uid: uid,
       selectedWorkType: selectedWork.workType,
       wage: selectedWork.wage,
       vehiclePlateNumber: vehiclePlateNumber,  // ✅ 추가
     );
   }
   ```

6. **lib/services/firestore_service.dart**
   - 차량 관련 메서드 추가
   ```dart
   // 차량 추가
   Future<bool> addUserVehicle(String uid, VehicleInfo vehicle) async {
     try {
       await _firestore.collection('users').doc(uid).update({
         'vehicles': FieldValue.arrayUnion([vehicle.toMap()]),
       });
       return true;
     } catch (e) {
       print('❌ 차량 추가 실패: $e');
       return false;
     }
   }
   
   // 차량 마지막 사용일 업데이트
   Future<void> updateVehicleLastUsed(String uid, String plateNumber) async {
     final userDoc = await _firestore.collection('users').doc(uid).get();
     final vehicles = List<Map<String, dynamic>>.from(userDoc.data()?['vehicles'] ?? []);
     
     for (var i = 0; i < vehicles.length; i++) {
       if (vehicles[i]['plateNumber'] == plateNumber) {
         vehicles[i]['lastUsedAt'] = Timestamp.now();
         break;
       }
     }
     
     await _firestore.collection('users').doc(uid).update({'vehicles': vehicles});
   }
   
   // applyToTOWithWorkType 수정
   Future<bool> applyToTOWithWorkType({
     required String toId,
     required String uid,
     required String selectedWorkType,
     required int wage,
     String? vehiclePlateNumber,  // ✅ 추가
   }) async {
     // ...
     await _firestore.collection('applications').add({
       'toId': toId,
       'uid': uid,
       'selectedWorkType': selectedWorkType,
       'wage': wage,
       'vehiclePlateNumber': vehiclePlateNumber,  // ✅ 추가
       'status': 'PENDING',
       'appliedAt': FieldValue.serverTimestamp(),
     });
     // ...
   }
   ```

7. **lib/screens/user/my_vehicles_screen.dart** (신규)
   - 내 차량 관리 화면
   - 차량 추가/삭제
   - 자주 사용하는 차량 표시

8. **lib/screens/admin/admin_to_detail_screen.dart**
   - 지원자 카드에 차량번호 표시
   ```dart
   if (application.vehiclePlateNumber != null)
     Row(
       children: [
         Icon(Icons.directions_car, size: 16, color: Colors.blue[700]),
         SizedBox(width: 4),
         Text(
           application.vehiclePlateNumber!,
           style: TextStyle(fontSize: 13, color: Colors.grey[700]),
         ),
       ],
     )
   ```

### 🎨 UI 예시

#### 케이스 1: 차량 정보 있음
```
┌─────────────────────────────────────┐
│ ⚠️ 이 사업장은 차량등록이 필수입니다  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🚗 차량 선택                          │
│                                      │
│ ● 12가 3456 (소나타) ✅ 최근 사용    │
│ ○ 34나 7890 (아반떼)                │
│ ○ 새 차량 등록                       │
└─────────────────────────────────────┘

[다음]
```

#### 케이스 2: 차량 정보 없음
```
┌─────────────────────────────────────┐
│ ⚠️ 이 사업장은 차량등록이 필수입니다  │
│                                      │
│ 출입을 위해 차량번호를 등록해주세요   │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🚗 차량번호 *                         │
│                                      │
│ [12가3456__________________]         │
│                                      │
│ 예: 12가3456, 123가4567             │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🚙 차종 (선택사항)                    │
│                                      │
│ [소나타____________________]         │
└─────────────────────────────────────┘

☐ 이 차량을 내 계정에 저장

[지원하기]
```

#### 관리자 화면 - 지원자 카드
```
┌─────────────────────────────────────┐
│ 홍길동                               │
│ 피킹 | 50,000원                      │
│                                      │
│ 🚗 12가 3456                         │
│ ⏰ 2025.10.24 14:30 지원             │
│                                      │
│ [상태: 대기중 ▼]     [업무유형 변경] │
└─────────────────────────────────────┘
```

### ✅ 차량번호 유효성 검사
```dart
String? _validatePlateNumber(String? value) {
  if (value == null || value.isEmpty) {
    return '차량번호를 입력해주세요';
  }
  
  // 공백 제거
  final cleaned = value.replaceAll(' ', '');
  
  // 한국 차량번호 패턴
  // 2~3자리 숫자 + 한글 1자 + 4자리 숫자
  final pattern = RegExp(r'^\d{2,3}[가-힣]\d{4}$');
  
  if (!pattern.hasMatch(cleaned)) {
    return '올바른 차량번호 형식이 아닙니다\n예: 12가3456, 123가4567';
  }
  
  return null;
}
```

---

## 구현 순서

### 🗓️ 권장 순서

#### **Phase 1: 업무별 근무시간** (우선순위: 최고)
데이터 구조의 핵심 변경이므로 가장 먼저 진행

1. WorkDetailModel 수정
2. AdminCreateTOScreen 수정 (업무 추가 시 시간 입력)
3. FirestoreService.createWorkDetails 수정
4. TOModel에서 startTime/endTime 제거
5. 기존 TO 데이터 마이그레이션 (옵션)

**예상 소요 시간:** 2-3시간

---

#### **Phase 2: TO 그룹 관리** (우선순위: 중)
사용자 편의성 개선

1. TOModel에 groupId, groupName 추가
2. AdminCreateTOScreen에 "기존 공고와 연결" 기능 추가
3. FirestoreService에 그룹 관련 메서드 추가
4. 지원자 명단 통합 조회 기능 구현

**예상 소요 시간:** 3-4시간

---

#### **Phase 3: 차량등록 기능** (우선순위: 중)
실용적 기능 추가

1. BusinessModel, UserModel, ApplicationModel 수정
2. 차량 입력/선택 다이얼로그 구현
3. FirestoreService에 차량 관련 메서드 추가
4. 지원 프로세스에 차량 체크 로직 통합
5. 관리자 화면에 차량번호 표시

**예상 소요 시간:** 4-5시간

---

#### **Phase 4: TO 등록 횟수 제한** (우선순위: 낮)
플랫폼 관리 기능

1. BusinessModel에 maxTOCount 추가
2. 최고관리자 화면에서 수정 기능 구현
3. TO 생성 전 검증 로직 추가
4. UI 알림 구현

**예상 소요 시간:** 2시간

---

### 📊 전체 예상 시간
**총 11-14시간** (테스트 포함 시 15-18시간)

---

## 데이터 구조 변경 요약

### 📁 Firestore 최종 구조

```
users/{uid}
  ├─ name
  ├─ email
  ├─ role
  ├─ businessId
  └─ vehicles: [                    // ✅ 추가
       {
         plateNumber: "12가3456",
         vehicleType: "소나타",
         registeredAt: Timestamp,
         lastUsedAt: Timestamp
       }
     ]

businesses/{businessId}
  ├─ businessNumber
  ├─ name
  ├─ category
  ├─ address
  ├─ ownerId
  ├─ maxTOCount: 5                  // ✅ 추가
  ├─ requiresVehicleRegistration    // ✅ 추가
  └─ ...

tos/{toId}
  ├─ businessId
  ├─ businessName
  ├─ title
  ├─ date
  ├─ groupId                        // ✅ 추가
  ├─ groupName                      // ✅ 추가
  ├─ applicationDeadline
  ├─ totalRequired
  ├─ totalConfirmed
  ├─ description
  ├─ creatorUID
  ├─ createdAt
  └─ workDetails/{workDetailId}
       ├─ workType
       ├─ wage
       ├─ requiredCount
       ├─ currentCount
       ├─ startTime                 // ✅ 추가
       ├─ endTime                   // ✅ 추가
       ├─ order
       └─ createdAt

applications/{applicationId}
  ├─ toId
  ├─ uid
  ├─ selectedWorkType
  ├─ wage
  ├─ vehiclePlateNumber            // ✅ 추가
  ├─ status
  ├─ appliedAt
  └─ ...
```

---

## 🔔 주의사항

### 1. 기존 데이터 마이그레이션
- 기존 TO의 startTime/endTime을 WorkDetails로 이동 필요
- 스크립트 작성 또는 수동 마이그레이션

### 2. 하위 호환성
- 구버전 앱 사용자 고려
- 점진적 배포 계획 필요

### 3. 테스트 체크리스트
- [ ] 업무별 시간 입력/조회
- [ ] TO 그룹 연결/해제
- [ ] 그룹별 지원자 통합 조회
- [ ] TO 등록 횟수 제한
- [ ] 차량번호 입력/저장
- [ ] 차량번호 유효성 검사
- [ ] 기존 차량 선택
- [ ] 관리자 화면에 차량번호 표시

---

## 📞 다음 단계

1. **Phase 1 시작**: WorkDetailModel 수정부터 착수
2. **테스트 데이터 준비**: 각 Phase별 테스트 시나리오 작성
3. **단계별 배포**: 각 Phase 완료 후 테스트 및 배포
4. **사용자 피드백 수집**: 실사용 후 개선사항 파악

---

## 📝 변경 이력

- **2025.10.24**: 초기 보고서 작성
- WorkDetails 하위 컬렉션 전환 완료 후 추가 개선사항 정리

---

**작성자:** AI Assistant  
**검토자:** 개발팀  
**승인자:** -  

---

## 🔗 관련 문서

- [WorkDetails 하위 컬렉션 전환 가이드](이전 대화 참조)
- [Firebase 보안 규칙](별도 문서)
- [API 명세서](별도 문서)

---

**끝.**
