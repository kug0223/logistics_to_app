import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../models/core/user_model.dart';
import '../models/core/to_model.dart';
import '../models/core/application_model.dart';
import '../models/ui/admin_to_list_ui_models.dart'; 
import '../models/core/business_model.dart';
import '../models/core/work_type_model.dart';
import '../models/core/work_detail_model.dart';
import '../utils/toast_helper.dart';
import '../models/core/business_work_type_model.dart';
import '../models/core/attendance_model.dart';
import '../models/core/schedule_change_request_model.dart';
import '../models/core/review_model.dart';
import '../models/core/id_card_access_request_model.dart';
import '../models/core/notification_model.dart';

// ═══════════════════════════════════════════════════════════
// Part 파일 선언
// ═══════════════════════════════════════════════════════════
part 'firestore/user_firestore.dart';
part 'firestore/to_firestore.dart';
part 'firestore/to_group_firestore.dart';
part 'firestore/application_firestore.dart';
part 'firestore/work_detail_firestore.dart';
part 'firestore/business_firestore.dart';
part 'firestore/attendance_firestore.dart';
part 'firestore/notification_firestore.dart';

/// 배치 처리 결과
class BatchResult {
  final int success;
  final int failed;
  
  BatchResult({required this.success, required this.failed});
  
  int get total => success + failed;
  bool get hasFailures => failed > 0;
}
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // ═══════════════════════════════════════════════════════════
  // Internal getters (part 파일에서 접근용)
  // ═══════════════════════════════════════════════════════════
  FirebaseFirestore get db => _firestore;
  Map<String, List<ApplicationModel>> get applicationCache => _applicationCache;
  Map<String, List<WorkDetailModel>> get workDetailCache => _workDetailCache;
  Map<String, Map<String, String>> get timeRangeCache => _timeRangeCache;
  Map<String, UserModel> get userCache => _userCache;
  Map<String, DateTime> get userCacheTimestamps => _userCacheTimestamps;
  Duration get userCacheValidDuration => _userCacheValidDuration;
  Map<String, DateTime> get cacheTimestamps => _cacheTimestamps;
  Duration get cacheValidDuration => _cacheValidDuration;
  Duration get listCacheValidDuration => _listCacheValidDuration;
  
  // TO 목록 캐시 getter/setter
  List<TOModel>? get activeTOsCacheData => _activeTOsCache;
  set activeTOsCacheData(List<TOModel>? value) => _activeTOsCache = value;
  List<TOModel>? get closedTOsCacheData => _closedTOsCache;
  set closedTOsCacheData(List<TOModel>? value) => _closedTOsCache = value;
  DateTime? get activeTOsCacheTime => _activeTOsCacheTime;
  set activeTOsCacheTime(DateTime? value) => _activeTOsCacheTime = value;
  DateTime? get closedTOsCacheTime => _closedTOsCacheTime;
  set closedTOsCacheTime(DateTime? value) => _closedTOsCacheTime = value;

  // ✅ 캐시 추가
  final Map<String, List<ApplicationModel>> _applicationCache = {};
  final Map<String, List<WorkDetailModel>> _workDetailCache = {};
  final Map<String, Map<String, String>> _timeRangeCache = {};
  // 🔥 NEW: 사용자 정보 캐시 추가!
  final Map<String, UserModel> _userCache = {};
  final Map<String, DateTime> _userCacheTimestamps = {};
  final Duration _userCacheValidDuration = const Duration(hours: 1);
  // ⭐ TO 목록 캐시
  List<TOModel>? _activeTOsCache;
  List<TOModel>? _closedTOsCache;
  DateTime? _activeTOsCacheTime;
  DateTime? _closedTOsCacheTime;
  
  // 캐시 유효 시간
  final Duration _cacheValidDuration = const Duration(minutes: 5);  // 상세 데이터용
  final Duration _listCacheValidDuration = const Duration(seconds: 30);  // ✅ 목록용 (짧게)
  final Map<String, DateTime> _cacheTimestamps = {};

  // ═══════════════════════════════════════════════════════════
  // 지원서 관리 (Application Management)
  // ═══════════════════════════════════════════════════════════

  /// TO별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByTOId(String toId) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 2. businessId, toTitle, workDate로 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 여러 TO의 지원자를 한 번에 조회 (병렬 최적화!)
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOIds(List<String> toIds) async {
    try {
      if (toIds.isEmpty) return {};
      
      print('🔍 배치 지원자 조회 시작: ${toIds.length}개 TO (병렬 처리)');
      
      // ✅ 병렬로 각 TO의 지원서 조회
      final futures = toIds.map((toId) async {
        // TO 정보 조회
        final toDoc = await _firestore.collection('tos').doc(toId).get();
        if (!toDoc.exists) {
          return MapEntry(toId, <ApplicationModel>[]);
        }

        final toData = toDoc.data()!;
        final businessId = toData['businessId'];
        final toTitle = toData['title'];
        final workDate = toData['date'] as Timestamp;

        // 지원서 조회
        final snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: toTitle)
            .where('workDate', isEqualTo: workDate)
            .get();

        final apps = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();
        
        return MapEntry(toId, apps);
      }).toList();
      
      // ✅ 병렬 실행 완료 대기
      final results = await Future.wait(futures);
      final result = Map.fromEntries(results);
      
      print('✅ 배치 지원자 조회 완료 (병렬): ${toIds.length}개 TO, ${result.values.fold(0, (sum, list) => sum + list.length)}명');
      return result;
    } catch (e) {
      print('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }
  /// 사업장별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByBusinessId(String businessId) async {
    try {
      print('📋 사업장별 지원서 조회 시작: $businessId');
      
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ 사업장별 지원서 조회 완료: ${applications.length}개');
      return applications;
    } catch (e) {
      print('❌ 사업장별 지원서 조회 실패: $e');
      return [];
    }
  }
  /// 여러 TO의 지원자를 한 번에 조회 (TO 정보 전달 - 중복 조회 제거)
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOs(List<TOModel> tos) async {
    try {
      if (tos.isEmpty) return {};
      
      print('🔍 배치 지원자 조회 시작: ${tos.length}개 TO (TO 정보 재사용)');
      
      final futures = tos.map((to) async {
        // ✅ TO 정보는 이미 있음 - 재조회 안 함!
        final snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: to.businessId)
            .where('toTitle', isEqualTo: to.title)
            .where('workDate', isEqualTo: Timestamp.fromDate(to.date))
            .get();

        final apps = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();
        
        return MapEntry(to.id, apps);
      }).toList();
      
      final results = await Future.wait(futures);
      final result = Map.fromEntries(results);
      
      print('✅ 배치 지원자 조회 완료: ${tos.length}개 TO, ${result.values.fold(0, (sum, list) => sum + list.length)}명');
      return result;
    } catch (e) {
      print('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }

  /// 여러 TO의 WorkDetails를 한 번에 조회 (병렬)
  Future<Map<String, List<WorkDetailModel>>> getWorkDetailsBatch(
    List<String> toIds, 
    {bool forceRefresh = false}  // 🔥 추가!
  ) async {
    try {
      if (toIds.isEmpty) return {};
      
      // 병렬로 모든 WorkDetails 조회
      final futures = toIds.map((toId) async {
        final workDetails = await getWorkDetails(toId, forceRefresh: forceRefresh);
        return MapEntry(toId, workDetails);
      }).toList();
      
      final results = await Future.wait(futures);
      
      final map = Map.fromEntries(results);
      return map;
    } catch (e) {
      print('❌ 배치 WorkDetails 조회 실패: $e');
      return {};
    }
  }
  /// 특정 TO의 특정 업무 유형에 대한 지원서 조회
  Future<List<ApplicationModel>> getApplicationsByWorkDetail(
    String toId,
    String workType,
  ) async {
    try {
      // ✅ TO 정보 먼저 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // ✅ businessId, toTitle, workDate, workType으로 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .where('selectedWorkType', isEqualTo: workType)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 업무별 지원서 조회 실패: $e');
      return [];
    }
  }
  // ═══════════════════════════════════════════════════════════
  // Phase 2: 충돌 방지 시스템
  // ═══════════════════════════════════════════════════════════
  
  /// 시간이 겹치는지 체크
  bool _hasTimeOverlap(String s1, String e1, String s2, String e2) {
    final start1 = _timeToMinutes(s1);
    final end1 = _timeToMinutes(e1);
    final start2 = _timeToMinutes(s2);
    final end2 = _timeToMinutes(e2);
    
    // 겹치지 않는 경우: end1 <= start2 || end2 <= start1
    // 겹치는 경우: 위의 반대
    return !(end1 <= start2 || end2 <= start1);
  }
  
  /// 시간을 분 단위로 변환 (예: "09:30" → 570)
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
  
  
  
  /// 충돌하는 지원서 찾기 (장기 공고 날짜 확장 포함)
  Future<List<ApplicationModel>> findConflictingApplications({
    required String uid,
    required DateTime workDate,
    required String startTime,
    required String endTime,
    required String excludeId,
    String status = 'PENDING',
  }) async {
    try {
      // 1. 해당 상태의 모든 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: status)
          .get();
      
      // 2. 날짜와 시간대 겹침 필터링
      final conflicts = <ApplicationModel>[];
      
      for (var doc in snapshot.docs) {
        if (doc.id == excludeId) continue;
        
        final app = ApplicationModel.fromFirestore(doc);
        
        // 해당 날짜에 근무하는지 확인
        if (!_isWorkingOnDate(app, workDate)) continue;
        
        // 시간대 겹침 확인
        if (_hasTimeOverlap(startTime, endTime, app.startTime, app.endTime)) {
          conflicts.add(app);
        }
      }
      
      print('✅ 충돌하는 지원서 ${conflicts.length}개 발견');
      return conflicts;
    } catch (e) {
      print('❌ 충돌 지원서 조회 실패: $e');
      return [];
    }
  }
  
  /// 확정된 근무 일정 조회 (장기 공고 날짜 확장 포함)
  Future<List<ApplicationModel>> getConfirmedSchedules({
    required String uid,
    required DateTime workDate,
  }) async {
    try {
      // 1. 모든 확정된 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();
      
      final allConfirmed = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      // 2. 해당 날짜와 겹치는 근무만 필터링
      final relevantSchedules = <ApplicationModel>[];
      
      for (var app in allConfirmed) {
        if (_isWorkingOnDate(app, workDate)) {
          relevantSchedules.add(app);
        }
      }
      
      print('✅ ${workDate.month}/${workDate.day}에 확정된 근무: ${relevantSchedules.length}개');
      return relevantSchedules;
    } catch (e) {
      print('❌ 확정 일정 조회 실패: $e');
      return [];
    }
  }
  // ============================================================
  // 🧹 지원서 연관 데이터 정리 (공통)
  // ============================================================

  /// 지원서 취소/거절 시 연관 데이터 정리
  /// - 신분증 요청 무효화
  /// - 출근 데이터 삭제
  /// - 스케줄 변경 요청 취소
  Future<void> _cleanupApplicationRelatedData({
    required String applicationId,
    required String uid,
    WriteBatch? batch,
  }) async {
    print('🧹 [Cleanup] 연관 데이터 정리 시작: $applicationId');
    
    final useBatch = batch != null;
    final localBatch = batch ?? _firestore.batch();
    
    try {
      // 1. 신분증 요청 무효화 (pending → canceled)
      final idCardRequests = await _firestore
          .collection('idCardAccessRequests')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'pending')
          .get();
      
      for (var doc in idCardRequests.docs) {
        localBatch.update(doc.reference, {
          'status': 'canceled',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'APPLICATION_CANCELED',
        });
      }
      print('   📋 신분증 요청 ${idCardRequests.docs.length}건 무효화');
      
      // 2. 출근 데이터는 유지 (근무 이력 보존)
      // 확정 취소되어도 이미 출근한 기록은 남겨둠
      
      // 3. 스케줄 변경 요청 취소 (PENDING → CANCELED)
      final scheduleRequests = await _firestore
          .collection('scheduleChangeRequests')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'PENDING')
          .get();
      
      for (var doc in scheduleRequests.docs) {
        localBatch.update(doc.reference, {
          'status': 'CANCELED',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'APPLICATION_CANCELED',
        });
      }
      print('   📋 스케줄 요청 ${scheduleRequests.docs.length}건 취소');
      
      // batch가 외부에서 제공되지 않은 경우에만 commit
      if (!useBatch) {
        await localBatch.commit();
      }
      
      print('✅ [Cleanup] 연관 데이터 정리 완료');
    } catch (e) {
      print('❌ [Cleanup] 연관 데이터 정리 실패: $e');
      // 실패해도 메인 로직은 계속 진행
    }
  }
  
  /// 특정 날짜에 근무하는지 확인 (장기 공고 고려)
  bool _isWorkingOnDate(ApplicationModel app, DateTime targetDate) {
    // ✅ 장기 판단: workDays가 있으면 장기 (근무 요일 지정됨)
    // workEndDate만 있는 경우는 그룹 단기일 수 있으므로 단기로 취급
    final isLongTerm = app.workDays != null && app.workDays!.isNotEmpty;
    
    // 단기: workDate만 체크
    if (!isLongTerm) {
      return _isSameDate(app.workDate, targetDate);
    }
    
    // 장기: 시작일~종료일 범위 + 근무 요일 체크
    if (app.workEndDate == null) return false;
    
    // ✅ 시작일 계산: 확정일이 공고 시작일보다 이후면 확정일 기준
    DateTime effectiveStartDate = app.workDate;
    if (app.confirmedAt != null) {
      final confirmedDate = DateTime(
        app.confirmedAt!.year,
        app.confirmedAt!.month,
        app.confirmedAt!.day,
      );
      if (confirmedDate.isAfter(app.workDate)) {
        effectiveStartDate = confirmedDate;
      }
    }
    
    // 날짜 범위 체크 (확정일 기준 시작)
    final isInRange = !targetDate.isBefore(effectiveStartDate) && 
                      !targetDate.isAfter(app.workEndDate!);
    
    if (!isInRange) return false;
    
    // 근무 요일 체크
    if (app.workDays == null || app.workDays!.isEmpty) {
      return true; // 모든 날 근무
    }
    
    final targetDayKorean = _getKoreanDayOfWeek(targetDate);
    return app.workDays!.contains(targetDayKorean);
  }
  
  /// 두 날짜가 같은지 비교 (시간 제외)
  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
  
  /// 요일을 한글로 변환
  String _getKoreanDayOfWeek(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }
  /// 지원서 상태 업데이트 (승인/거절) - Phase 2: 자동 취소 추가
  Future<void> updateApplicationStatus({
    required String applicationId,
    required String status,
    String? confirmedBy,
    String? rejectedBy,
    String? message,  // ⭐ Phase 2: 메시지 추가
  }) async {
    try {
      // ⭐ Phase 2: 확정 시 충돌 처리
      if (status == 'CONFIRMED') {
        await _confirmWithConflictCheck(
          applicationId: applicationId,
          confirmedBy: confirmedBy,
          message: message,
        );
        return;
      }
      
      // 기존 로직 (거절 등)
      final updates = <String, dynamic>{
        'status': status,
      };

      if (status == 'REJECTED') {
        updates['rejectedAt'] = FieldValue.serverTimestamp();
        if (rejectedBy != null) {
          updates['rejectedBy'] = rejectedBy;
        }
        if (message != null) {
          updates['rejectMessage'] = message;  // ⭐ Phase 2
        }
      }

      await _firestore
          .collection('applications')
          .doc(applicationId)
          .update(updates);

      print('✅ 지원서 상태 업데이트: $status');
      
      // ✅ REJECTED: Increment 방식으로 처리
      if (status == 'REJECTED') {
        final appDoc = await _firestore
            .collection('applications')
            .doc(applicationId)
            .get();
        
        if (appDoc.exists) {
          final appData = appDoc.data()!;
          final workDetailId = appData['workDetailId'] as String?;
          
          final toSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: appData['businessId'])
              .where('title', isEqualTo: appData['toTitle'])
              .where('date', isEqualTo: appData['workDate'])
              .limit(1)
              .get();
          
          if (toSnapshot.docs.isNotEmpty) {
            final toDoc = toSnapshot.docs.first;
            final toId = toDoc.id;
            final toData = toDoc.data();
            final groupId = toData['groupId'] as String?;
            
            final batch = _firestore.batch();
            
            // TO 통계 Increment
            batch.update(toDoc.reference, {
              'totalPending': FieldValue.increment(-1),
            });
            
            // WorkDetail 통계 Increment
            if (workDetailId != null && workDetailId.isNotEmpty) {
              batch.update(
                _firestore
                    .collection('tos')
                    .doc(toId)
                    .collection('workDetails')
                    .doc(workDetailId),
                {
                  'pendingCount': FieldValue.increment(-1),
                },
              );
            }
            
            // 그룹 마스터 통계 Increment
            if (groupId != null) {
              final masterSnapshot = await _firestore
                  .collection('tos')
                  .where('groupId', isEqualTo: groupId)
                  .where('isGroupMaster', isEqualTo: true)
                  .limit(1)
                  .get();
              
              if (masterSnapshot.docs.isNotEmpty) {
                batch.update(masterSnapshot.docs.first.reference, {
                  'groupTotalPending': FieldValue.increment(-1),
                });
              }
            }
            
            await batch.commit();
            clearCache(toId: toId);
            print('📊 TO 통계 Increment 완료: $toId');
          }
        }
      }
    } catch (e) {
      print('❌ 지원서 상태 업데이트 실패: $e');
      rethrow;
    }
  }
  
  /// 확정 처리 (Increment 방식 - 재계산 없음!)
  Future<void> _confirmWithConflictCheck({
    required String applicationId,
    String? confirmedBy,
    String? message,
  }) async {
    try {
      // 1. 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      
      if (!appDoc.exists) {
        throw Exception('지원서를 찾을 수 없습니다');
      }
      
      final appData = appDoc.data()!;
      final currentStatus = appData['status'];
      
      // 이미 확정/취소된 경우
      if (currentStatus == 'CONFIRMED') return;
      if (currentStatus == 'CANCELED') {
        throw Exception('취소된 지원서는 확정할 수 없습니다');
      }
      
      final app = ApplicationModel.fromMap(appData, appDoc.id);
      final workDetailId = appData['workDetailId'] as String?;
      
      // 2. TO 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: app.businessId)
          .where('title', isEqualTo: app.toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(app.workDate))
          .limit(1)
          .get();
      
      if (toSnapshot.docs.isEmpty) {
        throw Exception('TO를 찾을 수 없습니다');
      }
      
      final toDoc = toSnapshot.docs.first;
      final toId = toDoc.id;
      final toData = toDoc.data();
      final groupId = toData['groupId'] as String?;
      
      // 3. 충돌하는 대기중 지원서 찾기
      // ✅ 장기공고인 경우 모든 근무일에 대해 충돌 체크
      final isConfirmingLongTerm = app.workDays != null && app.workDays!.isNotEmpty;
      
      List<ApplicationModel> conflictingApps;
      
      if (isConfirmingLongTerm && app.workEndDate != null) {
        // 장기공고: 모든 근무일에 대해 충돌 체크
        conflictingApps = await _findConflictingForLongTerm(
          uid: app.uid,
          startDate: app.workDate,
          endDate: app.workEndDate!,
          workDays: app.workDays!,
          startTime: app.startTime,
          endTime: app.endTime,
          excludeId: applicationId,
        );
      } else {
        // 단기공고: 해당 날짜만 체크
        conflictingApps = await findConflictingApplications(
          uid: app.uid,
          workDate: app.workDate,
          startTime: app.startTime,
          endTime: app.endTime,
          excludeId: applicationId,
          status: 'PENDING',
        );
      }
      
      print('✅ 충돌하는 지원서 ${conflictingApps.length}개 발견');
      
      // 4. Batch 처리 (모든 업데이트를 한 번에!)
      final batch = _firestore.batch();
      final now = FieldValue.serverTimestamp();
      
      // 4-1. 지원서 확정
      final confirmUpdates = <String, dynamic>{
        'status': 'CONFIRMED',
        'confirmedAt': now,
      };
      if (confirmedBy != null) confirmUpdates['confirmedBy'] = confirmedBy;
      if (message != null) confirmUpdates['confirmMessage'] = message;
      
      batch.update(appDoc.reference, confirmUpdates);
      
      // 4-2. TO 통계 Increment (PENDING → CONFIRMED)
      batch.update(toDoc.reference, {
        'totalConfirmed': FieldValue.increment(1),
        'totalPending': FieldValue.increment(-1),
      });
      
      // 4-3. WorkDetail 통계 Increment
      if (workDetailId != null && workDetailId.isNotEmpty) {
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'currentCount': FieldValue.increment(1),
            'pendingCount': FieldValue.increment(-1),
          },
        );
      }
      
      // 4-4. 그룹 마스터 통계 Increment
      if (groupId != null) {
        final masterSnapshot = await _firestore
            .collection('tos')
            .where('groupId', isEqualTo: groupId)
            .where('isGroupMaster', isEqualTo: true)
            .limit(1)
            .get();
        
        if (masterSnapshot.docs.isNotEmpty) {
          batch.update(masterSnapshot.docs.first.reference, {
            'groupTotalConfirmed': FieldValue.increment(1),
            'groupTotalPending': FieldValue.increment(-1),
          });
        }
      }
      
      // 4-5. 충돌 지원 자동 취소 + TO 통계 감소
      for (var conflictApp in conflictingApps) {
        batch.update(
          _firestore.collection('applications').doc(conflictApp.id),
          {
            'status': 'AUTO_CANCELED',
            'canceledAt': now,
            'cancelReason': 'SCHEDULE_CONFLICT',
            'conflictingAppId': applicationId,
            'conflictingBusiness': app.businessName,
            'conflictingTime': '${app.startTime}~${app.endTime}',
          },
        );
      }
      
      // 5. 한 번에 커밋!
      await batch.commit();
      
      // 5-1. ✅ AUTO_CANCELED 된 지원서들의 TO 통계 업데이트 (별도 batch)
      if (conflictingApps.isNotEmpty) {
        final statsBatch = _firestore.batch();
        
        for (var conflictApp in conflictingApps) {
          // 충돌 지원서의 TO 찾기
          final conflictTOSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: conflictApp.businessId)
              .where('title', isEqualTo: conflictApp.toTitle)
              .where('date', isEqualTo: Timestamp.fromDate(conflictApp.workDate))
              .limit(1)
              .get();
          
          if (conflictTOSnapshot.docs.isNotEmpty) {
            final conflictTODoc = conflictTOSnapshot.docs.first;
            final conflictTOData = conflictTODoc.data();
            final conflictGroupId = conflictTOData['groupId'] as String?;
            
            // TO pendingCount 감소
            statsBatch.update(conflictTODoc.reference, {
              'totalPending': FieldValue.increment(-1),
            });
            
            // WorkDetail pendingCount 감소
            final conflictWorkDetailId = conflictApp.workDetailId;
            if (conflictWorkDetailId != null && conflictWorkDetailId.isNotEmpty) {
              statsBatch.update(
                _firestore
                    .collection('tos')
                    .doc(conflictTODoc.id)
                    .collection('workDetails')
                    .doc(conflictWorkDetailId),
                {
                  'pendingCount': FieldValue.increment(-1),
                },
              );
            }
            
            // 그룹 마스터 통계 감소
            if (conflictGroupId != null) {
              final conflictMasterSnapshot = await _firestore
                  .collection('tos')
                  .where('groupId', isEqualTo: conflictGroupId)
                  .where('isGroupMaster', isEqualTo: true)
                  .limit(1)
                  .get();
              
              if (conflictMasterSnapshot.docs.isNotEmpty) {
                statsBatch.update(conflictMasterSnapshot.docs.first.reference, {
                  'groupTotalPending': FieldValue.increment(-1),
                });
              }
            }
            
            // 캐시 클리어
            clearCache(toId: conflictTODoc.id);
          }
        }
        
        await statsBatch.commit();
        print('✅ AUTO_CANCELED ${conflictingApps.length}건의 TO 통계 업데이트 완료');
      }
      
      // 6. 캐시만 클리어 (재계산 없음!)
      clearCache(toId: toId);
      
      print('✅ 확정 완료 + ${conflictingApps.length}개 자동 취소 (Increment 방식)');
      
    } catch (e) {
      print('❌ 확정 처리 실패: $e');
      rethrow;
    }
  }
  /// 장기공고 확정 시 모든 근무일에 대해 충돌하는 지원서 찾기
  Future<List<ApplicationModel>> _findConflictingForLongTerm({
    required String uid,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> workDays,
    required String startTime,
    required String endTime,
    required String excludeId,
  }) async {
    try {
      print('📅 [LongTerm] 장기공고 충돌 체크 시작');
      print('   기간: ${startDate.month}/${startDate.day} ~ ${endDate.month}/${endDate.day}');
      print('   요일: $workDays');
      
      // 1. 해당 사용자의 모든 PENDING 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'PENDING')
          .get();
      
      final conflicts = <ApplicationModel>{};  // Set으로 중복 방지
      
      // 2. 장기공고의 모든 근무일 생성
      final workingDates = <DateTime>[];
      var currentDate = startDate;
      
      while (!currentDate.isAfter(endDate)) {
        final dayOfWeek = _getKoreanDayOfWeek(currentDate);
        if (workDays.contains(dayOfWeek)) {
          workingDates.add(currentDate);
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }
      
      print('   근무일 수: ${workingDates.length}일');
      
      // 3. 각 근무일에 대해 충돌 체크
      for (var doc in snapshot.docs) {
        if (doc.id == excludeId) continue;
        
        final app = ApplicationModel.fromFirestore(doc);
        
        // 각 근무일과 비교
        for (var workDate in workingDates) {
          // 해당 날짜에 근무하는 지원서인지 확인
          if (!_isWorkingOnDate(app, workDate)) continue;
          
          // 시간대 겹침 확인
          if (_hasTimeOverlap(startTime, endTime, app.startTime, app.endTime)) {
            conflicts.add(app);
            break;  // 이미 충돌 확인됐으면 다음 지원서로
          }
        }
      }
      
      print('✅ [LongTerm] 충돌 지원서 ${conflicts.length}개 발견');
      return conflicts.toList();
    } catch (e) {
      print('❌ [LongTerm] 충돌 조회 실패: $e');
      return [];
    }
  }
  /// TO의 모든 지원서 조회 (businessId, title, date 기준)
  /// [isLongTerm] - 장기 TO인 경우 날짜 필터 제외
  Future<List<ApplicationModel>> getApplicationsByTO(
    String businessId,
    String title,
    DateTime date, {
    bool isLongTerm = false,
  }) async {
    try {
      QuerySnapshot snapshot;
      
      if (isLongTerm) {
        // ✅ 장기 TO: businessId + toTitle로만 조회 (날짜 필터 제외)
        snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: title)
            .get();
        
        print('✅ 장기 TO 지원서 조회: ${snapshot.docs.length}개 (businessId=$businessId, title=$title)');
      } else {
        // ✅ 단기 TO: 날짜 범위로 조회
        final dateStart = DateTime(date.year, date.month, date.day);
        final dateEnd = dateStart.add(const Duration(days: 1));
        
        snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: title)
            .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
            .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
            .get();
        
        print('✅ 단기 TO 지원서 조회: ${snapshot.docs.length}개 (businessId=$businessId, title=$title, date=$dateStart~$dateEnd)');
      }

      final apps = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();

      return apps;
    } catch (e) {
      print('❌ TO 지원서 조회 실패: $e');
      return [];
    }
  }
  

  /// 내 지원 내역 조회
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('내 지원 내역 조회 실패: $e');
      return [];
    }
  }

  /// TO별 지원자 목록 + 사용자 정보 조회 (관리자용)
  Future<List<Map<String, dynamic>>> getApplicantsWithUserInfo(String toId) async {
    try {
      // ✅ TO 정보 먼저 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      print('🔍 지원자 조회: businessId=$businessId, toTitle=$toTitle');

      // ✅ businessId, toTitle, workDate로 조회
      QuerySnapshot appSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      print('✅ 조회된 지원서: ${appSnapshot.docs.length}개');

      // 메모리에서 정렬
      final sortedDocs = appSnapshot.docs.toList()
        ..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['appliedAt'] as Timestamp?;
          final bTime = bData['appliedAt'] as Timestamp?;
          
          if (aTime == null || bTime == null) return 0;
          return aTime.compareTo(bTime);
        });

      List<Map<String, dynamic>> result = [];

      for (var appDoc in sortedDocs) {
        final appData = appDoc.data() as Map<String, dynamic>;
        final uid = appData['uid'];

        final userDoc = await _firestore.collection('users').doc(uid).get();
        
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          
          result.add({
            'applicationId': appDoc.id,
            'application': ApplicationModel.fromMap(appData, appDoc.id),
            'userName': userData['name'] ?? '(알 수 없음)',
            'userEmail': userData['email'] ?? '',
            'userPhone': userData['phone'] ?? '',
          });
        }
      }

      print('✅ 사용자 정보 포함 지원자: ${result.length}명');
      return result;
    } catch (e) {
      print('❌ 지원자 조회 실패: $e');
      return [];
    }
  }

  /// 지원하기 (업무유형 선택)
  Future<bool> applyToTOWithWorkType({
    required String businessId,
    required String businessName,
    required String toTitle,
    required DateTime workDate,
    required String uid,
    required String selectedWorkType,
    required String workDetailId,  // ✅ 추가
    required int wage,
    required String startTime,
    required String endTime,
    // ⭐ Phase 1: 장기 공고 정보 추가
    DateTime? workEndDate,
    List<String>? workDays,
    String type = 'short',
    // ✅ 장기공고 희망 시작일
    DateTime? desiredStartDate,
  }) async {
    try {
      // ✅ 서버 레벨 서류 체크
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (!userDoc.exists) {
        ToastHelper.showError('사용자 정보를 찾을 수 없습니다.');
        return false;
      }
      
      final userData = userDoc.data()!;
      
      // 필수 서류 체크
      if (userData['idCardImageUrl'] == null) {
        ToastHelper.showError('신분증 등록이 필요합니다.');
        return false;
      }
      
      if (userData['bankName'] == null || userData['accountNumber'] == null) {
        ToastHelper.showError('통장 정보 등록이 필요합니다.');
        return false;
      }
      
      if (userData['bankbookImageUrl'] == null) {
        ToastHelper.showError('통장사본 등록이 필요합니다.');
        return false;
      }
      // 1. 중복 지원 확인 - ✅ workDetailId 기준으로 체크 (시간대 다르면 다른 업무)
      // 먼저 workDetailId 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(workDate))
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final toId = toSnapshot.docs.first.id;

      // 1. 기존 지원서 확인 (상태 무관)
      final existingApp = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: Timestamp.fromDate(workDate))
          .where('uid', isEqualTo: uid)
          .where('selectedWorkType', isEqualTo: selectedWorkType)
          .where('startTime', isEqualTo: startTime)
          .where('endTime', isEqualTo: endTime)
          .limit(1)
          .get();
      
      // 기존 지원서가 있는 경우
      if (existingApp.docs.isNotEmpty) {
        final existingDoc = existingApp.docs.first;
        final existingStatus = existingDoc.data()['status'];
        
        // 이미 활성 상태면 차단
        if (existingStatus == 'PENDING' || existingStatus == 'CONFIRMED') {
          print('🔍 활성 지원서 발견: 이미 지원한 업무');
          ToastHelper.showWarning('이미 지원한 업무입니다.');
          return false;
        }
        
        // 취소/거절 상태면 → 재지원 (status만 업데이트)
        print('✅ 기존 지원서 재활성화: ${existingDoc.id}');
        
        final batch = _firestore.batch();
        
        // 지원서 상태 업데이트
        batch.update(existingDoc.reference, {
          'status': 'PENDING',
          'appliedAt': FieldValue.serverTimestamp(),
          'canceledAt': null,
          'cancelReason': null,
          // ✅ 장기공고 희망 시작일도 업데이트
          if (desiredStartDate != null) 
            'desiredStartDate': Timestamp.fromDate(desiredStartDate),
        });
        
        // TO 통계 업데이트
        batch.update(_firestore.collection('tos').doc(toId), {
          'totalPending': FieldValue.increment(1),
        });
        
        // WorkDetail pendingCount 증가
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'pendingCount': FieldValue.increment(1),
          },
        );
        
        await batch.commit();
        clearCache(toId: toId);
        
        print('✅ 재지원 완료 (기존 문서 업데이트)');
        return true;
      }
      // ⭐ Phase 2-C: 확정된 근무와 충돌 체크
      final confirmedSchedules = await getConfirmedSchedules(
        uid: uid,
        workDate: workDate,
      );
      
      for (var schedule in confirmedSchedules) {
        if (_hasTimeOverlap(
          startTime,
          endTime,
          schedule.startTime,
          schedule.endTime,
        )) {
          // ⚠️ 충돌 발견!
          ToastHelper.showError(
            '이미 ${schedule.startTime}~${schedule.endTime}에\n'
            '${schedule.businessName}에서 확정된 근무가 있습니다.\n\n'
            '해당 시간대에는 추가 지원이 불가능합니다.'
          );
          return false;
        }
      }

      // 4. Batch로 한번에 처리
      final batch = _firestore.batch();

      // 4-1. 지원서 생성
      final appRef = _firestore.collection('applications').doc();
      batch.set(appRef, {
        'uid': uid,
        'businessId': businessId,
        'businessName': businessName,
        'toTitle': toTitle,
        'selectedWorkType': selectedWorkType,
        'workDetailId': workDetailId,
        'wage': wage,
        'workDate': Timestamp.fromDate(workDate),
        'startTime': startTime,
        'endTime': endTime,
        'status': 'PENDING',
        'appliedAt': FieldValue.serverTimestamp(),
        // ⭐ Phase 1: 장기 공고 정보 추가
        'type': type,
        'workEndDate': workEndDate != null 
            ? Timestamp.fromDate(workEndDate) 
            : null,
        'workDays': workDays,
        // ✅ 장기공고 희망 시작일
        'desiredStartDate': desiredStartDate != null 
            ? Timestamp.fromDate(desiredStartDate) 
            : null,
      });

      // 4-2. TO 통계 업데이트
      batch.update(_firestore.collection('tos').doc(toId), {
        'totalApplications': FieldValue.increment(1),
        'totalPending': FieldValue.increment(1),
      });

      // 4-3. WorkDetail pendingCount 증가
      batch.update(
        _firestore
            .collection('tos')
            .doc(toId)
            .collection('workDetails')
            .doc(workDetailId),
        {
          'pendingCount': FieldValue.increment(1),
        },
      );

      // 4-4. 그룹 마스터 통계 Increment (그룹 TO인 경우)
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      final groupId = toDoc.data()?['groupId'] as String?;
      
      if (groupId != null) {
        final masterSnapshot = await _firestore
            .collection('tos')
            .where('groupId', isEqualTo: groupId)
            .where('isGroupMaster', isEqualTo: true)
            .limit(1)
            .get();
        
        if (masterSnapshot.docs.isNotEmpty) {
          batch.update(masterSnapshot.docs.first.reference, {
            'groupTotalPending': FieldValue.increment(1),
          });
        }
      }

      await batch.commit();
      print('✅ Batch commit 완료 (Increment 방식)');
      
      // ✅ 캐시만 클리어 (재계산 없음!)
      clearCache(toId: toId);

      print('✅ 지원 완료: businessId=$businessId, toTitle=$toTitle, WorkType=$selectedWorkType');
      return true;
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 지원자 승인 (관리자용)
  Future<bool> confirmApplicant(String applicationId, String adminUID) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('이미 확정된 지원자입니다.');
        return false;
      }

      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('취소된 지원자는 확정할 수 없습니다.');
        return false;
      }

      await _firestore.collection('applications').doc(applicationId).update({
        'status': 'CONFIRMED',
        'confirmedAt': FieldValue.serverTimestamp(),
        'confirmedBy': adminUID,
      });

      ToastHelper.showSuccess('지원자가 확정되었습니다.');
      return true;
    } catch (e) {
      print('지원자 승인 실패: $e');
      ToastHelper.showError('승인 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 지원자 확정 (WorkDetail count + TO 통계 업데이트 포함)
  Future<bool> confirmApplicantWithWorkDetail({
    required String applicationId,
    required String adminUID,
  }) async {
    try {
      // 1. 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data()!;
      
      // 이미 확정된 경우
      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('이미 확정된 지원자입니다.');
        return false;
      }

      // 취소된 경우
      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('취소된 지원자는 확정할 수 없습니다.');
        return false;
      }

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;
      final selectedWorkType = appData['selectedWorkType'];
      final uid = appData['uid'];

      // 2. TO 문서 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final toId = toSnapshot.docs.first.id;

      // 3. WorkDetail ID 찾기
      final workDetailId = await findWorkDetailIdByType(toId, selectedWorkType);
      if (workDetailId == null) {
        ToastHelper.showError('업무유형 정보를 찾을 수 없습니다.');
        return false;
      }

      // 4. 정원 체크
      final workDetailDoc = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();
      
      if (!workDetailDoc.exists) {
        ToastHelper.showError('업무 정보를 찾을 수 없습니다.');
        return false;
      }
      
      final workDetailData = workDetailDoc.data()!;
      final currentCount = workDetailData['currentCount'] ?? 0;
      final requiredCount = workDetailData['requiredCount'] ?? 0;
      
      // 정원 초과 체크
      if (currentCount >= requiredCount) {
        ToastHelper.showError('이미 정원이 충족되었습니다. ($currentCount/$requiredCount명)');
        return false;
      }

      // 5. Batch 업데이트
      final batch = _firestore.batch();
      final now = Timestamp.now();

      // 5-1. 지원서 확정
      batch.update(_firestore.collection('applications').doc(applicationId), {
        'status': 'CONFIRMED',
        'confirmedAt': now,
        'confirmedBy': adminUID,
      });

      // 5-2. confirmed_applications 서브컬렉션에 추가
      final confirmedRef = _firestore
          .collection('tos')
          .doc(toId)
          .collection('confirmed_applications')
          .doc(applicationId);
      
      batch.set(confirmedRef, {
        'uid': uid,
        'workDetailId': workDetailId,
        'confirmedAt': now,
        'confirmedBy': adminUID,
      });

      await batch.commit();

      // ✅ 통계 재계산 (통합 함수 사용)
      print('📊 지원자 확정 후 통계 재계산...');
      await recalculateTOStats(toId);
      clearCache(toId: toId);
      
      // ✅ 그룹 마스터 통계 동기화
      await syncGroupMasterStats(toId);

      print('✅ 지원자 확정 완료');
      ToastHelper.showSuccess('지원자가 확정되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원자 확정 실패: $e');
      ToastHelper.showError('확정 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 지원자 거절 (관리자용)
  Future<bool> rejectApplicant(
    String applicationId, 
    String adminUID, {
    String? rejectMessage,
  }) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('이미 취소된 지원자입니다.');
        return false;
      }

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;

      // 지원서 거절 처리
      final updateData = <String, dynamic>{
        'status': 'REJECTED',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': adminUID,
      };
      
      if (rejectMessage != null && rejectMessage.isNotEmpty) {
        updateData['rejectMessage'] = rejectMessage;
      }
      
      // ✅ TO 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        await _firestore.collection('applications').doc(applicationId).update(updateData);
        print('✅ 지원자 거절 완료 (TO 없음)');
        return true;
      }

      final toDoc = toSnapshot.docs.first;
      final toId = toDoc.id;
      final toData = toDoc.data();
      final groupId = toData['groupId'] as String?;
      final workDetailId = appData['workDetailId'] as String?;

      // ✅ Batch로 한 번에 처리
      final batch = _firestore.batch();

      // 1. 지원서 거절
      batch.update(_firestore.collection('applications').doc(applicationId), updateData);

      // 2. TO 통계 Increment (PENDING인 경우만)
      if (appData['status'] == 'PENDING') {
        batch.update(toDoc.reference, {
          'totalPending': FieldValue.increment(-1),
        });

        // 3. WorkDetail 통계 Increment
        if (workDetailId != null && workDetailId.isNotEmpty) {
          batch.update(
            _firestore
                .collection('tos')
                .doc(toId)
                .collection('workDetails')
                .doc(workDetailId),
            {
              'pendingCount': FieldValue.increment(-1),
            },
          );
        }

        // 4. 그룹 마스터 통계 Increment
        if (groupId != null) {
          final masterSnapshot = await _firestore
              .collection('tos')
              .where('groupId', isEqualTo: groupId)
              .where('isGroupMaster', isEqualTo: true)
              .limit(1)
              .get();

          if (masterSnapshot.docs.isNotEmpty) {
            batch.update(masterSnapshot.docs.first.reference, {
              'groupTotalPending': FieldValue.increment(-1),
            });
          }
        }
      }

      await batch.commit();
      clearCache(toId: toId);

      print('✅ 지원자 거절 완료');
      ToastHelper.showSuccess('지원자가 거절되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원자 거절 실패: $e');
      ToastHelper.showError('거절 중 오류가 발생했습니다.');
      return false;
    }
  }

  

  /// 지원 취소 (사용자용)
  Future<bool> cancelApplication(String applicationId, String uid) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['uid'] != uid) {
        ToastHelper.showError('본인의 지원서만 취소할 수 있습니다.');
        return false;
      }

      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('확정된 TO는 취소할 수 없습니다.\n관리자에게 문의해주세요.');
        return false;
      }

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;

      // ✅ TO 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        await _firestore.collection('applications').doc(applicationId).update({
          'status': 'CANCELED',
        });
        ToastHelper.showSuccess('지원이 취소되었습니다.');
        return true;
      }

      final toDoc = toSnapshot.docs.first;
      final toId = toDoc.id;
      final toData = toDoc.data();
      final groupId = toData['groupId'] as String?;
      final workDetailId = appData['workDetailId'] as String?;

      // ✅ Batch로 한 번에 처리
      final batch = _firestore.batch();

      // 1. 지원서 취소
      batch.update(_firestore.collection('applications').doc(applicationId), {
        'status': 'CANCELED',
        'canceledAt': FieldValue.serverTimestamp(),
      });

      // 2. TO 통계 Increment
      batch.update(toDoc.reference, {
        'totalPending': FieldValue.increment(-1),
      });

      // 3. WorkDetail 통계 Increment
      if (workDetailId != null && workDetailId.isNotEmpty) {
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'pendingCount': FieldValue.increment(-1),
          },
        );
      }

      // 4. 그룹 마스터 통계 Increment
      if (groupId != null) {
        final masterSnapshot = await _firestore
            .collection('tos')
            .where('groupId', isEqualTo: groupId)
            .where('isGroupMaster', isEqualTo: true)
            .limit(1)
            .get();

        if (masterSnapshot.docs.isNotEmpty) {
          batch.update(masterSnapshot.docs.first.reference, {
            'groupTotalPending': FieldValue.increment(-1),
          });
        }
      }

      await batch.commit();
      clearCache(toId: toId);
      
      // ✅ 연관 데이터 정리 (신분증 요청 등)
      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
      );

      ToastHelper.showSuccess('지원이 취소되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원 취소 실패: $e');
      ToastHelper.showError('지원 취소에 실패했습니다.');
      return false;
    }
  }

  /// 지원자 업무유형 변경 (관리자용)
  Future<bool> changeApplicationWorkType({
    required String applicationId,
    required String newWorkType,
    required int newWage,
    required String adminUID,
  }) async {
    try {
      // 1. 기존 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data()!;
      final currentWorkType = appData['selectedWorkType'];
      final currentWage = appData['wage'];

      // 2. 업무유형 변경
      await _firestore.collection('applications').doc(applicationId).update({
        'selectedWorkType': newWorkType,
        'wage': newWage,
        'originalWorkType': appData['originalWorkType'] ?? currentWorkType,
        'originalWage': appData['originalWage'] ?? currentWage,
        'changedAt': FieldValue.serverTimestamp(),
        'changedBy': adminUID,
      });

      print('✅ 업무유형 변경 완료: $currentWorkType → $newWorkType');
      ToastHelper.showSuccess('업무유형이 변경되었습니다.');
      return true;
    } catch (e) {
      print('❌ 업무유형 변경 실패: $e');
      ToastHelper.showError('업무유형 변경에 실패했습니다.');
      return false;
    }
  }


  // ═══════════════════════════════════════════════════════════
  // 사업장 관리 (Business Management)
  // ═══════════════════════════════════════════════════════════
  
  /// 사업장 ID로 조회
  Future<BusinessModel?> getBusinessById(String businessId) async {
    try {
      final doc = await _firestore.collection('businesses').doc(businessId).get();
      
      if (!doc.exists) {
        print('⚠️ 사업장을 찾을 수 없습니다: $businessId');
        return null;
      }
      
      return BusinessModel.fromFirestore(doc);
    } catch (e) {
      print('❌ 사업장 조회 실패: $e');
      return null;
    }
  }

  /// 내 사업장 목록 조회
  Future<List<BusinessModel>> getMyBusiness(String ownerId) async {
    try {
      print('🔍 [FirestoreService] 내 사업장 조회 시작...');
      print('   ownerId: $ownerId');

      final snapshot = await _firestore
      .collection('businesses')
      .where('ownerId', isEqualTo: ownerId)
      .orderBy('createdAt', descending: true)
      .get(const GetOptions(source: Source.server));

      final businesses = snapshot.docs
          .map((doc) => BusinessModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ [FirestoreService] 조회 완료: ${businesses.length}개');
      return businesses;
    } catch (e) {
      print('❌ [FirestoreService] 내 사업장 조회 실패: $e');
      return [];
    }
  }

  /// 사업장 생성
  Future<String?> createBusiness(BusinessModel business) async {
    try {
      DocumentReference docRef = await _firestore
          .collection('businesses')
          .add(business.toMap());
      return docRef.id;
    } catch (e) {
      print('사업장 생성 실패: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 업무 유형 관리 (Work Type Management)
  // ═══════════════════════════════════════════════════════════

  /// 모든 업무 유형 조회
  Future<List<WorkTypeModel>> getWorkTypes({bool activeOnly = false}) async {
    try {
      Query query = _firestore.collection('work_types');
      
      if (activeOnly) {
        query = query.where('isActive', isEqualTo: true);
      }
      
      query = query.orderBy('displayOrder', descending: false);
      
      QuerySnapshot snapshot = await query.get();
      
      return snapshot.docs
          .map((doc) => WorkTypeModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 업무 유형 목록 조회 실패: $e');
      return [];
    }
  }

  /// 특정 업무 유형 조회
  Future<WorkTypeModel?> getWorkType(String workTypeId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('work_types')
          .doc(workTypeId)
          .get();
      
      if (doc.exists) {
        return WorkTypeModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('❌ 업무 유형 조회 실패: $e');
      return null;
    }
  }

  /// 업무 유형 생성
  Future<String?> createWorkType(WorkTypeModel workType) async {
    try {
      final docRef = await _firestore.collection('work_types').add(workType.toMap());
      
      ToastHelper.showSuccess('업무 유형이 등록되었습니다.');
      return docRef.id;
    } catch (e) {
      print('❌ 업무 유형 생성 실패: $e');
      ToastHelper.showError('업무 등록에 실패했습니다.');
      return null;
    }
  }

  /// 업무 유형 수정
  Future<bool> updateWorkType(String workTypeId, WorkTypeModel workType) async {
    try {
      await _firestore.collection('work_types').doc(workTypeId).update(
        workType.copyWith(updatedAt: DateTime.now()).toMap(),
      );
      
      ToastHelper.showSuccess('업무 정보가 수정되었습니다.');
      return true;
    } catch (e) {
      print('❌ 업무 유형 수정 실패: $e');
      ToastHelper.showError('업무 수정에 실패했습니다.');
      return false;
    }
  }

  /// 업무 유형 삭제 (소프트 삭제)
  Future<bool> deleteWorkType(String workTypeId) async {
    try {
      await _firestore.collection('work_types').doc(workTypeId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      ToastHelper.showSuccess('업무 유형이 비활성화되었습니다.');
      return true;
    } catch (e) {
      print('❌ 업무 유형 삭제 실패: $e');
      ToastHelper.showError('업무 삭제에 실패했습니다.');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 사업장별 업무 유형 관리 (Business Work Type Management)
  // ═══════════════════════════════════════════════════════════

  /// 특정 사업장의 업무 유형 목록 조회
  Future<List<BusinessWorkTypeModel>> getBusinessWorkTypes(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .where('isActive', isEqualTo: true)
          .orderBy('displayOrder')
          .get();

      final workTypes = snapshot.docs
          .map((doc) => BusinessWorkTypeModel.fromMap(doc.data(), doc.id))
          .toList();

      print('🔍 Firestore 조회: ${workTypes.length}개');
      return workTypes;
    } catch (e) {
      print('❌ getBusinessWorkTypes 오류: $e');
      return [];
    }
  }

  /// 업무 유형 추가
  Future<String?> addBusinessWorkType({
    required String businessId,
    required String name,
    required String icon,
    String? color,
    String? backgroundColor,
    String wageType = 'hourly',
    int? displayOrder,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 추가...');

      // displayOrder 자동 설정 (기존 개수 + 1)
      final existingTypes = await getBusinessWorkTypes(businessId);
      final order = displayOrder ?? existingTypes.length;

      final workType = BusinessWorkTypeModel(
        id: '',
        businessId: businessId,
        name: name,
        icon: icon,
        color: color,
        backgroundColor: backgroundColor, 
        displayOrder: order,
        isActive: true,
        createdAt: DateTime.now(),
      );

      final docRef = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .add(workType.toMap());

      print('✅ [FirestoreService] 업무 유형 추가 완료: ${docRef.id}');
      ToastHelper.showSuccess('업무 유형이 추가되었습니다');
      return docRef.id;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 추가 실패: $e');
      ToastHelper.showError('업무 유형 추가에 실패했습니다');
      return null;
    }
  }

  /// 업무 유형 수정
  Future<bool> updateBusinessWorkType({
    required String businessId,
    required String workTypeId,
    String? name,
    String? icon,
    String? color,
    String? backgroundColor,
    String? wageType,
    int? displayOrder,
    bool showToast = true,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 수정...');

      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (icon != null) updates['icon'] = icon;
      if (color != null) updates['color'] = color;
      if (backgroundColor != null) updates['backgroundColor'] = backgroundColor;
      if (displayOrder != null) updates['displayOrder'] = displayOrder;
      if (wageType != null) updates['wageType'] = wageType;

      if (updates.isEmpty) {
        print('⚠️ 수정할 내용이 없습니다');
        return false;
      }

      await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .update(updates);

      print('✅ [FirestoreService] 업무 유형 수정 완료');
      
      if (showToast) {
        ToastHelper.showSuccess('업무 유형이 수정되었습니다');
      }
      
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 수정 실패: $e');
      
      if (showToast) {
        ToastHelper.showError('업무 유형 수정에 실패했습니다');
      }
      
      return false;
    }
  }

  /// 업무 유형 삭제 (소프트 삭제 + Storage 이미지 삭제)
  Future<bool> deleteBusinessWorkType({
    required String businessId,
    required String workTypeId,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 삭제...');

      // ✅ 1. 업무유형 문서 조회 (이미지 URL 확인)
      final doc = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        final storage = FirebaseStorage.instance;
        
        // ✅ 2. 썸네일 이미지 삭제
        if (data['thumbnailUrl'] != null) {
          try {
            await storage.refFromURL(data['thumbnailUrl']).delete();
            print('✅ 썸네일 삭제: ${data['thumbnailUrl']}');
          } catch (e) {
            print('⚠️ 썸네일 삭제 실패: $e');
          }
        }
        
        // ✅ 3. 추가 이미지들 삭제
        if (data['images'] != null) {
          for (var url in List<String>.from(data['images'])) {
            try {
              await storage.refFromURL(url).delete();
              print('✅ 이미지 삭제: $url');
            } catch (e) {
              print('⚠️ 이미지 삭제 실패: $e');
            }
          }
        }
      }

      // ✅ 4. Firestore 소프트 삭제
      await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .update({'isActive': false});

      print('✅ [FirestoreService] 업무 유형 삭제 완료');
      ToastHelper.showSuccess('업무 유형이 삭제되었습니다');
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 삭제 실패: $e');
      ToastHelper.showError('업무 유형 삭제에 실패했습니다');
      return false;
    }
  }

  /// 업무 유형 순서 변경 (여러 개 일괄 업데이트)
  Future<bool> reorderBusinessWorkTypes({
    required String businessId,
    required List<String> workTypeIds,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 순서 변경...');

      final batch = _firestore.batch();

      for (int i = 0; i < workTypeIds.length; i++) {
        final docRef = _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('workTypes')
            .doc(workTypeIds[i]);

        batch.update(docRef, {'displayOrder': i});
      }

      await batch.commit();

      print('✅ [FirestoreService] 순서 변경 완료');
      ToastHelper.showSuccess('순서가 변경되었습니다');
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 순서 변경 실패: $e');
      ToastHelper.showError('순서 변경에 실패했습니다');
      return false;
    }
  }



  // ═══════════════════════════════════════════════════════════
  // 🔥 Phase A: 퇴사 관리 시스템
  // ═══════════════════════════════════════════════════════════

  /// 퇴사 요청 (지원자용)
  Future<bool> requestResignation({
    required String applicationId,
    required DateTime resignDate,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignRequestedAt': Timestamp.fromDate(DateTime.now()),
        'resignRequestDate': Timestamp.fromDate(resignDate),
        'resignStatus': 'PENDING',
      });

      print('✅ 퇴사 요청 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 요청 실패: $e');
      return false;
    }
  }

  /// 퇴사 요청 취소 (지원자용)
  Future<bool> cancelResignRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignRequestedAt': FieldValue.delete(),
        'resignRequestDate': FieldValue.delete(),
        'resignStatus': FieldValue.delete(),
      });

      print('✅ 퇴사 요청 취소 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 요청 취소 실패: $e');
      return false;
    }
  }

  /// 퇴사 승인 (관리자용)
  Future<bool> approveResignation({
    required String applicationId,
    required String adminUID,
  }) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;
      final resignDate = (appData['resignRequestDate'] as Timestamp).toDate();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'APPROVED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': adminUID,
        'actualResignDate': Timestamp.fromDate(resignDate),
        'workEndDate': Timestamp.fromDate(resignDate), // 실제 종료일 업데이트
      });

      print('✅ 퇴사 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 승인 실패: $e');
      return false;
    }
  }

  /// 퇴사 거절 (관리자용)
  Future<bool> rejectResignation({
    required String applicationId,
    required String adminUID,
    required String rejectReason,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'REJECTED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': adminUID,
        'resignRejectReason': rejectReason,
      });

      print('✅ 퇴사 거절 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 거절 실패: $e');
      return false;
    }
  }
  // ============================================================
  // 🔥 계약해지 관리 (관리자 → 근무자)
  // ============================================================

  /// 계약해지 요청 (관리자용)
  Future<bool> requestTermination({
    required String applicationId,
    required String reason,
    required String requestedByUid,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationRequestedAt': Timestamp.fromDate(DateTime.now()),
        'terminationReason': reason,
        'terminationRequestedByUid': requestedByUid,
        'terminationStatus': 'PENDING',
      });

      print('✅ 계약해지 요청 완료: $applicationId');
      
      // TODO: 근무자에게 알림 발송
      // await _sendTerminationNotification(applicationId);
      
      return true;
    } catch (e) {
      print('❌ 계약해지 요청 실패: $e');
      return false;
    }
  }

  /// 계약해지 요청 취소 (관리자용)
  Future<bool> cancelTerminationRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationRequestedAt': FieldValue.delete(),
        'terminationReason': FieldValue.delete(),
        'terminationRequestedByUid': FieldValue.delete(),
        'terminationStatus': FieldValue.delete(),
        'terminationRespondedAt': FieldValue.delete(),
        'terminationRejectReason': FieldValue.delete(),
      });

      print('✅ 계약해지 요청 취소 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 요청 취소 실패: $e');
      return false;
    }
  }

  /// 계약해지 승인 (근무자용)
  Future<bool> approveTermination(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'APPROVED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'resignStatus': 'APPROVED',  // 퇴사 상태도 함께 업데이트
        'actualResignDate': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ 계약해지 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 승인 실패: $e');
      return false;
    }
  }

  /// 계약해지 거절 (근무자용)
  Future<bool> rejectTermination({
    required String applicationId,
    String? rejectReason,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'REJECTED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'terminationRejectReason': rejectReason,
      });

      print('✅ 계약해지 거절 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 거절 실패: $e');
      return false;
    }
  }

  /// 계약해지 자동 승인 처리 (3일 경과 시)
  Future<bool> autoApproveTermination(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'AUTO_APPROVED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'resignStatus': 'AUTO_APPROVED',
        'actualResignDate': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ 계약해지 자동 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 자동 승인 실패: $e');
      return false;
    }
  }

  /// 계약해지 대기 중인 지원서 조회 (3일 경과 체크용)
  Future<List<ApplicationModel>> getPendingTerminations() async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('terminationStatus', isEqualTo: 'PENDING')
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 계약해지 대기 목록 조회 실패: $e');
      return [];
    }
  }

  /// 퇴사 자동 승인 처리 (Cloud Function에서 호출)
  Future<bool> autoApproveResignation(String applicationId) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) return false;

      final appData = appDoc.data() as Map<String, dynamic>;
      
      // 이미 처리된 경우 스킵
      if (appData['resignStatus'] != 'PENDING') return false;

      final resignDate = (appData['resignRequestDate'] as Timestamp).toDate();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'AUTO_APPROVED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': 'SYSTEM',
        'actualResignDate': Timestamp.fromDate(resignDate),
        'workEndDate': Timestamp.fromDate(resignDate),
      });

      print('✅ 퇴사 자동 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 자동 승인 실패: $e');
      return false;
    }
  }
  /// 퇴사 요청 목록 조회 (관리자용)
  Future<List<ApplicationModel>> getResignRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('resignStatus', isEqualTo: 'PENDING')
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) => app.isLongTermApplication) // 장기 근무만
          .toList();

      print('✅ 퇴사 요청 ${applications.length}건 조회');
      return applications;
    } catch (e) {
      print('❌ 퇴사 요청 조회 실패: $e');
      return [];
    }
  }
  /// 장기 근무 지원자 조회 (사업장별)
  Future<List<ApplicationModel>> getLongTermApplicationsByBusiness(
    String businessId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) => app.isLongTermApplication)
          .toList();

      print('✅ 장기 근무 지원자 조회: ${applications.length}명');
      return applications;
    } catch (e) {
      print('❌ 장기 근무 지원자 조회 실패: $e');
      return [];
    }
  }
  /// 활성 TO 조회 (사업장별) - 캐싱 적용
  Future<List<TOModel>> getActiveTOsByBusinessId(String businessId) async {
    try {
      // 캐시 확인
      if (_activeTOsCache != null && _activeTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(_activeTOsCacheTime!);
        if (cacheAge < _cacheValidDuration) {
          print('✅ 활성 TO 캐시 사용');
          return _activeTOsCache!
              .where((to) => to.businessId == businessId)
              .toList();
        }
      }

      final snapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 캐시 저장
      _activeTOsCache = toList;
      _activeTOsCacheTime = DateTime.now();

      print('✅ 활성 TO 조회: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ 활성 TO 조회 실패: $e');
      return [];
    }
  }

  /// 마감된 TO 조회 (사업장별) - 이미 있음, 사업장 필터 추가
  Future<List<TOModel>> getClosedTOsByBusinessId(String businessId) async {
    try {
      // 캐시 확인
      if (_closedTOsCache != null && _closedTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(_closedTOsCacheTime!);
        if (cacheAge < _cacheValidDuration) {
          print('✅ 마감 TO 캐시 사용');
          return _closedTOsCache!
              .where((to) => to.businessId == businessId)
              .toList();
        }
      }

      final snapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('isManualClosed', isEqualTo: true)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 캐시 저장
      _closedTOsCache = toList;
      _closedTOsCacheTime = DateTime.now();

      print('✅ 마감 TO 조회: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ 마감 TO 조회 실패: $e');
      return [];
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 🕐 출근 관리 (Attendance Management)
  // ═══════════════════════════════════════════════════════════

  /// 출근 체크
  Future<String?> checkIn({
    required String applicationId,
    required String userId,
    required String businessId,
    required String businessName,
    required DateTime workDate,
    required String workType,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      print('🕐 [checkIn] 출근 체크 시작...');
      print('   applicationId: $applicationId');
      print('   workDate: $workDate');
      
      // 1. 오늘 이미 출근했는지 확인
      final todayStart = DateTime(workDate.year, workDate.month, workDate.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      final existing = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      
      if (existing.docs.isNotEmpty) {
        final existingData = existing.docs.first.data();
        if (existingData['checkIn'] != null) {
          print('⚠️ 이미 출근 완료');
          throw Exception('오늘 이미 출근하셨습니다.');
        }
      }
      
      // 2. 출근 시간
      final now = DateTime.now();
      final checkInTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      // 3. 출근 기록 생성
      final attendanceData = {
        'applicationId': applicationId,
        'userId': userId,
        'businessId': businessId,
        'businessName': businessName,
        'workDate': Timestamp.fromDate(workDate),
        'workType': workType,
        'checkIn': checkInTime,
        'checkInLat': latitude,
        'checkInLng': longitude,
        'checkInMethod': method,
        'checkInTime': FieldValue.serverTimestamp(),
        'status': 'present', // 기본값
        'isModified': false,
        'modifyRequested': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      final docRef = await _firestore.collection('attendance').add(attendanceData);
      
      print('✅ 출근 체크 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 출근 체크 실패: $e');
      rethrow;
    }
  }

  /// 퇴근 체크
  Future<bool> checkOut({
    required String attendanceId,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      print('🕐 [checkOut] 퇴근 체크 시작...');
      print('   attendanceId: $attendanceId');
      
      // 1. 출근 기록 조회
      final doc = await _firestore
          .collection('attendance')
          .doc(attendanceId)
          .get();
      
      if (!doc.exists) {
        throw Exception('출근 기록을 찾을 수 없습니다.');
      }
      
      final data = doc.data()!;
      if (data['checkOut'] != null) {
        throw Exception('이미 퇴근하셨습니다.');
      }
      
      // 2. 퇴근 시간
      final now = DateTime.now();
      final checkOutTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      // 3. 근무 시간 계산
      final checkInTime = data['checkIn'] as String;
      final workHours = _calculateWorkHours(checkInTime, checkOutTime);
      
      // 4. 퇴근 기록 저장
      await _firestore.collection('attendance').doc(attendanceId).update({
        'checkOut': checkOutTime,
        'checkOutLat': latitude,
        'checkOutLng': longitude,
        'checkOutMethod': method,
        'checkOutTime': FieldValue.serverTimestamp(),
        'workHours': workHours,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ 퇴근 체크 완료');
      return true;
    } catch (e) {
      print('❌ 퇴근 체크 실패: $e');
      rethrow;
    }
  }

  /// 근무 시간 계산 (시:분:초 → 시간)
  double _calculateWorkHours(String checkIn, String checkOut) {
    try {
      final inParts = checkIn.split(':');
      final outParts = checkOut.split(':');
      
      final inMinutes = int.parse(inParts[0]) * 60 + int.parse(inParts[1]);
      final outMinutes = int.parse(outParts[0]) * 60 + int.parse(outParts[1]);
      
      final diffMinutes = outMinutes - inMinutes;
      return diffMinutes / 60.0;
    } catch (e) {
      print('❌ 근무 시간 계산 실패: $e');
      return 0.0;
    }
  }

  /// 오늘 내 출근 기록 조회
  Future<AttendanceModel?> getTodayAttendance({
    required String userId,
    required String applicationId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('applicationId', isEqualTo: applicationId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return null;
      }
      
      return AttendanceModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('❌ 오늘 출근 기록 조회 실패: $e');
      return null;
    }
  }

  /// 사업장별 오늘 출근 현황 조회 (관리자용)
  Future<List<AttendanceModel>> getTodayAttendanceByBusiness({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      print('🔍 [getTodayAttendanceByBusiness] 조회 시작...');
      print('   businessId: $businessId');
      print('   todayStart: $todayStart');
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .orderBy('workDate', descending: false)
          .orderBy('checkInTime', descending: false)
          .get();
      
      final attendances = snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
          .toList();
      
      print('✅ 오늘 출근 현황: ${attendances.length}명');
      return attendances;
    } catch (e) {
      print('❌ 출근 현황 조회 실패: $e');
      return [];
    }
  }

  /// 오늘 확정된 근무자 목록 조회 (출근 대상자)
  Future<List<ApplicationModel>> getTodayConfirmedWorkers({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      print('🔍 [getTodayConfirmedWorkers] 조회 시작...');
      
      // 1. 오늘 확정된 단기 근무
      final shortTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('workDate', isEqualTo: Timestamp.fromDate(todayStart))
          .get();
      
      final shortTerm = shortTermSnapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      print('   단기 근무자: ${shortTerm.length}명');
      
      // 2. 오늘 근무하는 장기 근무자
      final longTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('type', isEqualTo: 'long_term')
          .get();
      
      final longTerm = longTermSnapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) {
            // 오늘이 근무일인지 확인
            if (app.workEndDate == null) return false;
            
            final isInRange = !todayStart.isBefore(app.workDate) && 
                             !todayStart.isAfter(app.workEndDate!);
            
            if (!isInRange) return false;
            
            // 근무 요일 확인
            if (app.workDays == null || app.workDays!.isEmpty) {
              return true; // 매일 근무
            }
            
            final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
            final todayWeekday = weekdays[today.weekday - 1];
            
            return app.workDays!.contains(todayWeekday);
          })
          .toList();
      
      print('   장기 근무자: ${longTerm.length}명');
      
      final allWorkers = [...shortTerm, ...longTerm];
      print('✅ 총 출근 대상: ${allWorkers.length}명');
      
      return allWorkers;
    } catch (e) {
      print('❌ 출근 대상자 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜 출근 기록 조회
  Future<List<AttendanceModel>> getAttendanceByDate({
    required String businessId,
    required DateTime date,
  }) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final dateEnd = dateStart.add(const Duration(days: 1));
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
          .get();
      
      return snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 출근 기록 조회 실패: $e');
      return [];
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 스케줄 변경 요청 관리 (Schedule Change Request Management)
  // ═══════════════════════════════════════════════════════════

  /// 스케줄 변경 요청 생성
  Future<String?> createScheduleChangeRequest(ScheduleChangeRequestModel request) async {
    try {
      final docRef = await _firestore.collection('schedule_change_requests').add(request.toMap());
      print('✅ 스케줄 변경 요청 생성 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 스케줄 변경 요청 생성 실패: $e');
      return null;
    }
  }

  /// 사업장의 대기중인 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getPendingScheduleChangeRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 대기중인 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 사업장의 모든 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getAllScheduleChangeRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 지원자의 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getMyScheduleChangeRequests(String applicantUid) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('applicantUid', isEqualTo: applicantUid)
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 내 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 스케줄 변경 요청 승인
  Future<bool> approveScheduleChangeRequest({
    required String requestId,
    required String approverUid,
  }) async {
    try {
      // 1. 요청 정보 조회
      final requestDoc = await _firestore
          .collection('schedule_change_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        print('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 2. 요청 상태 업데이트
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'APPROVED',
        'respondedByUid': approverUid,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      // 3. ApplicationModel의 leaveDates 또는 extraWorkDates 업데이트
      final appSnapshot = await _firestore
          .collection('applications')
          .doc(request.applicationId)
          .get();

      if (appSnapshot.exists) {
        final appData = appSnapshot.data()!;
        
        if (request.isLeaveRequest || request.isNoWorkRequest) {
          // 휴무/미출근 → leaveDates에 추가
          List<DateTime> leaveDates = [];
          if (appData['leaveDates'] != null) {
            leaveDates = (appData['leaveDates'] as List)
                .map((e) => (e as Timestamp).toDate())
                .toList();
          }
          
          if (!leaveDates.any((d) => 
              d.year == request.targetDate.year &&
              d.month == request.targetDate.month &&
              d.day == request.targetDate.day)) {
            leaveDates.add(request.targetDate);
          }

          await _firestore.collection('applications').doc(request.applicationId).update({
            'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
          });
        } else if (request.isExtraWorkRequest) {
          // 추가 근무 → extraWorkDates에 추가
          List<DateTime> extraWorkDates = [];
          if (appData['extraWorkDates'] != null) {
            extraWorkDates = (appData['extraWorkDates'] as List)
                .map((e) => (e as Timestamp).toDate())
                .toList();
          }
          
          if (!extraWorkDates.any((d) => 
              d.year == request.targetDate.year &&
              d.month == request.targetDate.month &&
              d.day == request.targetDate.day)) {
            extraWorkDates.add(request.targetDate);
          }

          await _firestore.collection('applications').doc(request.applicationId).update({
            'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
          });
        }
      }

      print('✅ 스케줄 변경 요청 승인 완료: $requestId');
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 승인 실패: $e');
      return false;
    }
  }

  /// 스케줄 변경 요청 거절
  Future<bool> rejectScheduleChangeRequest({
    required String requestId,
    required String rejectorUid,
    String? rejectReason,
  }) async {
    try {
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'REJECTED',
        'respondedByUid': rejectorUid,
        'respondedAt': FieldValue.serverTimestamp(),
        'rejectReason': rejectReason,
      });

      print('✅ 스케줄 변경 요청 거절 완료: $requestId');
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 거절 실패: $e');
      return false;
    }
  }

  /// 스케줄 변경 요청 취소
  Future<bool> cancelScheduleChangeRequest({
    required String requestId,
    required String canceledByUid,
  }) async {
    try {
      // 1. 요청 정보 조회
      final requestDoc = await _firestore
          .collection('schedule_change_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        print('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 2. 승인된 요청이면 ApplicationModel에서도 제거
      if (request.isApproved) {
        final appSnapshot = await _firestore
            .collection('applications')
            .doc(request.applicationId)
            .get();

        if (appSnapshot.exists) {
          final appData = appSnapshot.data()!;
          
          if (request.isLeaveRequest || request.isNoWorkRequest) {
            // leaveDates에서 제거
            List<DateTime> leaveDates = [];
            if (appData['leaveDates'] != null) {
              leaveDates = (appData['leaveDates'] as List)
                  .map((e) => (e as Timestamp).toDate())
                  .toList();
            }
            
            leaveDates.removeWhere((d) => 
                d.year == request.targetDate.year &&
                d.month == request.targetDate.month &&
                d.day == request.targetDate.day);

            await _firestore.collection('applications').doc(request.applicationId).update({
              'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request.isExtraWorkRequest) {
            // extraWorkDates에서 제거
            List<DateTime> extraWorkDates = [];
            if (appData['extraWorkDates'] != null) {
              extraWorkDates = (appData['extraWorkDates'] as List)
                  .map((e) => (e as Timestamp).toDate())
                  .toList();
            }
            
            extraWorkDates.removeWhere((d) => 
                d.year == request.targetDate.year &&
                d.month == request.targetDate.month &&
                d.day == request.targetDate.day);

            await _firestore.collection('applications').doc(request.applicationId).update({
              'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          }
        }
      }

      // 3. 요청 상태 업데이트
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'CANCELED',
        'respondedByUid': canceledByUid,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      print('✅ 스케줄 변경 요청 취소 완료: $requestId');
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 취소 실패: $e');
      return false;
    }
  }

  /// 대기중인 요청 개수 조회
  Future<int> getPendingScheduleChangeRequestCount(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'PENDING')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('❌ 대기중인 요청 개수 조회 실패: $e');
      return 0;
    }
  }
  /// 지원서 업데이트
  Future<bool> updateApplication(String applicationId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update(data);
      print('✅ 지원서 업데이트 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 지원서 업데이트 실패: $e');
      return false;
    }
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // 📝 FirestoreService 추가 메서드 (리뷰, 신분증 열람, 알림)
  // 이 내용을 lib/services/firestore_service.dart에 추가하세요
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // 리뷰 관리 (Review Management)
  // ═══════════════════════════════════════════════════════════

  /// 리뷰 작성
  Future<String?> createReview({
    required String applicationId,
    required String reviewerId,
    required String reviewerName,
    required String targetUserId,
    required String businessId,
    required String businessName,
    required String workType,
    required DateTime workDate,
    required int rating,
    String? comment,
    bool wouldRehire = true,
  }) async {
    try {
      print('📝 [createReview] 리뷰 작성 시작');
      
      // 1. 리뷰 생성
      final docRef = await _firestore.collection('reviews').add({
        'applicationId': applicationId,
        'reviewerId': reviewerId,
        'reviewerName': reviewerName,
        'targetUserId': targetUserId,
        'businessId': businessId,
        'businessName': businessName,
        'workType': workType,
        'workDate': Timestamp.fromDate(workDate),
        'rating': rating,
        'comment': comment,
        'wouldRehire': wouldRehire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 2. 사용자 통계 업데이트 (평균 평점, 리뷰 수)
      await _updateUserReviewStats(targetUserId);
      
      // 3. 지원서에 리뷰 작성 표시
      await _firestore.collection('applications').doc(applicationId).update({
        'hasReview': true,
        'reviewId': docRef.id,
      });
      
      // 4. 알림 생성
      await createNotification(
        NotificationModel.createReviewReceived(
          userId: targetUserId,
          businessName: businessName,
          rating: rating,
          reviewId: docRef.id,
        ),
      );
      
      print('✅ [createReview] 리뷰 작성 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ [createReview] 실패: $e');
      return null;
    }
  }

  /// 사용자 리뷰 통계 업데이트
  Future<void> _updateUserReviewStats(String userId) async {
    try {
      final reviews = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .get();
      
      if (reviews.docs.isEmpty) return;
      
      double totalRating = 0;
      for (var doc in reviews.docs) {
        totalRating += (doc.data()['rating'] ?? 0) as int;
      }
      
      final avgRating = totalRating / reviews.docs.length;
      
      await _firestore.collection('users').doc(userId).update({
        'averageRating': avgRating,
        'reviewCount': reviews.docs.length,
      });
      
      print('✅ 사용자 리뷰 통계 업데이트: avg=$avgRating, count=${reviews.docs.length}');
    } catch (e) {
      print('⚠️ 사용자 리뷰 통계 업데이트 실패: $e');
    }
  }

  /// 사용자가 받은 리뷰 목록 조회
  Future<List<ReviewModel>> getUserReviews(String userId, {int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 사용자 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 특정 지원서의 리뷰 조회
  Future<ReviewModel?> getReviewByApplicationId(String applicationId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) return null;
      return ReviewModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('❌ 리뷰 조회 실패: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 우리 사업장 근무 이력 (Business Work History)
  // ═══════════════════════════════════════════════════════════

  /// 특정 사용자의 우리 사업장 근무 이력 조회
  Future<Map<String, dynamic>> getBusinessWorkHistory({
    required String userId,
    required String businessId,
  }) async {
    try {
      print('🔍 [getBusinessWorkHistory] 조회: userId=$userId, businessId=$businessId');
      
      // 1. 확정된 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: userId)
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .orderBy('workDate', descending: true)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return {
          'workCount': 0,
          'lastWorkDate': null,
          'lastWorkType': null,
          'averageRating': null,
          'reviews': <ReviewModel>[],
        };
      }
      
      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      // 2. 이 사업장에서 받은 리뷰 조회
      final reviewSnapshot = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .where('businessId', isEqualTo: businessId)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      final reviews = reviewSnapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
      
      // 3. 이 사업장에서의 평균 평점 계산
      double? avgRating;
      if (reviews.isNotEmpty) {
        double total = 0;
        for (var review in reviews) {
          total += review.rating;
        }
        avgRating = total / reviews.length;
      }
      
      // 4. 가장 최근 근무 정보
      final lastApp = applications.first;
      
      print('✅ [getBusinessWorkHistory] 조회 완료: ${applications.length}회 근무');
      
      return {
        'workCount': applications.length,
        'lastWorkDate': lastApp.workDate,
        'lastWorkType': lastApp.selectedWorkType,
        'averageRating': avgRating,
        'reviews': reviews,
        'applications': applications,
      };
    } catch (e) {
      print('❌ [getBusinessWorkHistory] 실패: $e');
      return {
        'workCount': 0,
        'lastWorkDate': null,
        'lastWorkType': null,
        'averageRating': null,
        'reviews': <ReviewModel>[],
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 신분증 열람 요청 (ID Card Access Request)
  // ═══════════════════════════════════════════════════════════

  /// 신분증 열람 요청 생성
  Future<String?> createIdCardAccessRequest({
    required String requesterId,
    required String requesterName,
    required String requesterBusinessId,
    required String requesterBusinessName,
    required String targetUserId,
    required String targetUserName,
    required IdCardAccessReason reason,
    String? customReason,
    String? applicationId,
  }) async {
    try {
      print('📄 [createIdCardAccessRequest] 요청 생성');
      
      // 1. 이미 대기 중인 요청이 있는지 확인
      final existingPending = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      
      if (existingPending.docs.isNotEmpty) {
        print('⚠️ 이미 대기 중인 요청이 있습니다');
        ToastHelper.showWarning('이미 요청 중입니다. 응답을 기다려주세요.');
        return null;
      }
      
      // 2. 유효한 승인이 있는지 확인
      final existingApproved = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'approved')
          .get();
      
      for (var doc in existingApproved.docs) {
        final expiresAt = (doc.data()['expiresAt'] as Timestamp?)?.toDate();
        if (expiresAt != null && DateTime.now().isBefore(expiresAt)) {
          print('⚠️ 이미 유효한 열람 권한이 있습니다');
          ToastHelper.showInfo('이미 열람 권한이 있습니다.');
          return doc.id;
        }
      }
      
      // 3. 요청 생성
      final docRef = await _firestore.collection('idCardAccessRequests').add({
        'requesterId': requesterId,
        'requesterName': requesterName,
        'requesterBusinessId': requesterBusinessId,
        'requesterBusinessName': requesterBusinessName,
        'targetUserId': targetUserId,
        'targetUserName': targetUserName,
        'reason': _reasonToString(reason),
        'customReason': customReason,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'applicationId': applicationId,
      });
      
      // 4. 알림 생성 (지원자에게)
      final reasonText = reason == IdCardAccessReason.other 
          ? (customReason ?? '기타') 
          : _getReasonText(reason);
      
      await createNotification(
        NotificationModel.createIdCardAccessRequest(
          userId: targetUserId,
          businessName: requesterBusinessName,
          reason: reasonText,
          requestId: docRef.id,
        ),
      );
      
      print('✅ [createIdCardAccessRequest] 요청 생성 완료: ${docRef.id}');
      ToastHelper.showSuccess('신분증 열람 요청을 보냈습니다');
      return docRef.id;
    } catch (e) {
      print('❌ [createIdCardAccessRequest] 실패: $e');
      ToastHelper.showError('요청 실패');
      return null;
    }
  }

  /// 신분증 열람 요청 승인
  Future<bool> approveIdCardAccessRequest(String requestId) async {
    try {
      print('✅ [approveIdCardAccessRequest] 승인: $requestId');
      
      final docRef = _firestore.collection('idCardAccessRequests').doc(requestId);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        print('❌ 요청을 찾을 수 없습니다');
        return false;
      }
      
      final data = doc.data()!;
      final expiresAt = DateTime.now().add(const Duration(days: 7));
      
      // 1. 요청 상태 업데이트
      await docRef.update({
        'status': 'approved',
        'respondedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
      
      // 2. 알림 생성 (관리자에게)
      await createNotification(
        NotificationModel.createIdCardAccessApproved(
          userId: data['requesterId'],
          targetUserName: data['targetUserName'],
          requestId: requestId,
        ),
      );
      
      print('✅ [approveIdCardAccessRequest] 승인 완료');
      return true;
    } catch (e) {
      print('❌ [approveIdCardAccessRequest] 실패: $e');
      return false;
    }
  }

  /// 신분증 열람 요청 거절
  Future<bool> rejectIdCardAccessRequest(String requestId, {String? reason}) async {
    try {
      print('❌ [rejectIdCardAccessRequest] 거절: $requestId');
      
      final docRef = _firestore.collection('idCardAccessRequests').doc(requestId);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        print('❌ 요청을 찾을 수 없습니다');
        return false;
      }
      
      final data = doc.data()!;
      
      // 1. 요청 상태 업데이트
      await docRef.update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason,
      });
      
      // 2. 알림 생성 (관리자에게)
      await createNotification(
        NotificationModel.createIdCardAccessRejected(
          userId: data['requesterId'],
          targetUserName: data['targetUserName'],
          requestId: requestId,
          rejectionReason: reason,
        ),
      );
      
      print('✅ [rejectIdCardAccessRequest] 거절 완료');
      return true;
    } catch (e) {
      print('❌ [rejectIdCardAccessRequest] 실패: $e');
      return false;
    }
  }



  /// 신분증 열람 권한 확인 (pending, approved 모두 조회)
  Future<IdCardAccessRequestModel?> checkIdCardAccess({
    required String requesterId,
    required String targetUserId,
  }) async {
    try {
      // ✅ pending 또는 approved 상태 조회 (최신순)
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', whereIn: ['pending', 'approved'])
          .orderBy('requestedAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      
      if (snapshot.docs.isEmpty) return null;
      
      final request = IdCardAccessRequestModel.fromFirestore(snapshot.docs.first);
      
      // 승인된 경우 만료 확인
      if (request.status == IdCardAccessStatus.approved && request.isExpired) {
        // 만료 상태로 업데이트
        await _firestore
            .collection('idCardAccessRequests')
            .doc(request.id)
            .update({'status': 'expired'});
        return null;
      }
      
      return request;
    } catch (e) {
      print('❌ 열람 권한 확인 실패: $e');
      return null;
    }
  }
  /// 사용자에게 온 신분증 열람 요청 조회 (지원자/근무자용)
  Future<List<IdCardAccessRequestModel>> getPendingIdCardRequestsForUser(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('targetUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => IdCardAccessRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 신분증 요청 조회 실패: $e');
      return [];
    }
  }

  /// 사용자에게 온 계약해지 요청 조회 (근무자용)
  Future<List<ApplicationModel>> getMyTerminationRequests(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('terminationStatus', isEqualTo: 'PENDING')
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 계약해지 요청 조회 실패: $e');
      return [];
    }
  }

  /// 대기 중인 신분증 열람 요청 조회 (지원자용)
  Future<List<IdCardAccessRequestModel>> getPendingIdCardRequests(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('targetUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .get();
      
      return snapshot.docs
          .map((doc) => IdCardAccessRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 대기 요청 조회 실패: $e');
      return [];
    }
  }

  /// 내가 보낸 신분증 열람 요청 조회 (관리자용)
  Future<List<IdCardAccessRequestModel>> getMyIdCardRequests(String requesterId) async {
    try {
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .orderBy('requestedAt', descending: true)
          .limit(50)
          .get();
      
      return snapshot.docs
          .map((doc) => IdCardAccessRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 내 요청 조회 실패: $e');
      return [];
    }
  }

  // Helper methods for IdCardAccessReason
  String _reasonToString(IdCardAccessReason reason) {
    switch (reason) {
      case IdCardAccessReason.incomeTax: return 'incomeTax';
      case IdCardAccessReason.laborContract: return 'laborContract';
      case IdCardAccessReason.insurance: return 'insurance';
      case IdCardAccessReason.identityVerify: return 'identityVerify';
      case IdCardAccessReason.other: return 'other';
    }
  }

  String _getReasonText(IdCardAccessReason reason) {
    switch (reason) {
      case IdCardAccessReason.incomeTax: return '소득세 신고';
      case IdCardAccessReason.laborContract: return '근로계약서 작성';
      case IdCardAccessReason.insurance: return '4대보험 신고';
      case IdCardAccessReason.identityVerify: return '본인 확인';
      case IdCardAccessReason.other: return '기타';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 알림 관리 (Notification Management)
  // ═══════════════════════════════════════════════════════════

  /// 알림 생성
  Future<String?> createNotification(NotificationModel notification) async {
    try {
      final docRef = await _firestore.collection('notifications').add(
        notification.toMap(),
      );
      print('✅ 알림 생성: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 알림 생성 실패: $e');
      return null;
    }
  }

  /// 사용자 알림 목록 조회
  Future<List<NotificationModel>> getUserNotifications(
    String userId, {
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    try {
      Query query = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      
      if (unreadOnly) {
        query = query.where('isRead', isEqualTo: false);
      }
      
      final snapshot = await query.get();
      
      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 알림 조회 실패: $e');
      return [];
    }
  }

  /// 읽지 않은 알림 개수
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      print('❌ 읽지 않은 알림 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 알림 읽음 처리
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('❌ 알림 읽음 처리 실패: $e');
      return false;
    }
  }

  /// 모든 알림 읽음 처리
  Future<bool> markAllNotificationsAsRead(String userId) async {
    try {
      final batch = _firestore.batch();
      
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      print('✅ ${snapshot.docs.length}개 알림 읽음 처리');
      return true;
    } catch (e) {
      print('❌ 전체 읽음 처리 실패: $e');
      return false;
    }
  }

  /// 오래된 알림 삭제 (30일 이상)
  Future<int> deleteOldNotifications(String userId) async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();
      
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('✅ ${snapshot.docs.length}개 오래된 알림 삭제');
      return snapshot.docs.length;
    } catch (e) {
      print('❌ 오래된 알림 삭제 실패: $e');
      return 0;
    }
  }

  /// 알림 스트림 (실시간)
  Stream<List<NotificationModel>> watchUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromFirestore(doc))
            .toList());
  }

  /// 읽지 않은 알림 개수 스트림 (실시간)
  Stream<int> watchUnreadNotificationCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
  // ═══════════════════════════════════════════════════════════════════════════
// 📌 FirestoreService에 추가할 메서드들
// 
// 이 파일의 내용을 lib/services/firestore_service.dart에 추가하세요.
// ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // 지원 다이얼로그용 메서드
  // ═══════════════════════════════════════════════════════════

  /// 특정 TO에 대한 사용자의 지원 목록 조회
  /// 
  /// [toId] - TO 문서 ID
  /// [uid] - 사용자 UID
  /// 
  /// 반환: 해당 사용자가 이 TO에 지원한 모든 지원서
  Future<List<ApplicationModel>> getApplicationsForTO({
    required String toId,
    required String uid,
  }) async {
    try {
      // TO 정보 먼저 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) return [];

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ TO 지원 목록 조회 실패: $e');
      return [];
    }
  }

  /// TO에 지원하기 (간편 버전)
  /// 
  /// apply_work_dialog에서 사용
  Future<bool> applyForTO({
    required String toId,
    required String workDetailId,
    required String workType,
    required String uid,
    DateTime? desiredStartDate,  // ✅ 장기공고 희망 시작일
  }) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        ToastHelper.showError('TO를 찾을 수 없습니다');
        return false;
      }

      final toData = toDoc.data()!;
      final to = TOModel.fromMap(toData, toId);

      // 2. WorkDetail 정보 조회
      final workDetailDoc = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();

      if (!workDetailDoc.exists) {
        ToastHelper.showError('업무 정보를 찾을 수 없습니다');
        return false;
      }

      final workDetail = WorkDetailModel.fromMap(workDetailDoc.data()!, workDetailId);

      // 3. 기존 applyToTOWithWorkType 호출
      return await applyToTOWithWorkType(
        uid: uid,
        businessId: to.businessId,
        businessName: to.businessName,
        toTitle: to.title,
        workDate: to.date,
        selectedWorkType: workType,
        workDetailId: workDetailId,  // ✅ 추가
        wage: workDetail.wage,
        startTime: workDetail.startTime,
        endTime: workDetail.endTime,
        workEndDate: to.endDate,
        workDays: to.workDays,
        type: to.isLongTerm ? 'long_term' : 'short',
        desiredStartDate: desiredStartDate,  // ✅ 희망 시작일 전달
      );
    } catch (e) {
      print('❌ TO 지원 실패: $e');
      ToastHelper.showError('지원에 실패했습니다');
      return false;
    }
  }

  /// 확정된 지원 취소 (노쇼 패널티 포함)
  /// 
  /// [applicationId] - 지원서 ID
  /// [applyNoShowPenalty] - true면 노쇼 카운트 증가
  Future<bool> cancelConfirmedApplication(
    String applicationId, {
    bool applyNoShowPenalty = false,
  }) async {
    try {
      // 1. 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다');
        return false;
      }

      final appData = appDoc.data()!;
      final uid = appData['uid'] as String;

      // 2. 상태 확인
      if (appData['status'] != 'CONFIRMED') {
        ToastHelper.showError('확정된 지원만 취소할 수 있습니다');
        return false;
      }

      // 3. Batch로 처리
      final batch = _firestore.batch();

      // 3-1. 지원서 상태 변경
      batch.update(
        _firestore.collection('applications').doc(applicationId),
        {
          'status': 'CANCELED',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': applyNoShowPenalty ? 'SAME_DAY_CANCEL' : 'USER_CANCELED',
        },
      );

      // 3-2. 노쇼 패널티 적용
      if (applyNoShowPenalty) {
        batch.update(
          _firestore.collection('users').doc(uid),
          {
            'noShowCount': FieldValue.increment(1),
          },
        );

        // 노쇼 3회 체크 → 3일 이용 제한
        final userDoc = await _firestore.collection('users').doc(uid).get();
        final currentNoShow = (userDoc.data()?['noShowCount'] ?? 0) as int;
        
        if (currentNoShow >= 2) { // 이번 취소 포함해서 3회
          final restrictedUntil = DateTime.now().add(const Duration(days: 3));
          batch.update(
            _firestore.collection('users').doc(uid),
            {
              'restrictedUntil': Timestamp.fromDate(restrictedUntil),
              'noShowCount': 0, // 리셋
            },
          );
        }
      }

      // 4. TO 찾기 및 통계 Increment
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;
      final workDetailId = appData['workDetailId'] as String?;

      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isNotEmpty) {
        final toDoc = toSnapshot.docs.first;
        final toId = toDoc.id;
        final toData = toDoc.data();
        final groupId = toData['groupId'] as String?;

        // TO 통계 Increment (CONFIRMED → CANCELED)
        batch.update(toDoc.reference, {
          'totalConfirmed': FieldValue.increment(-1),
        });

        // WorkDetail 통계 Increment
        if (workDetailId != null && workDetailId.isNotEmpty) {
          batch.update(
            _firestore
                .collection('tos')
                .doc(toId)
                .collection('workDetails')
                .doc(workDetailId),
            {
              'currentCount': FieldValue.increment(-1),
            },
          );
        }

        // 그룹 마스터 통계 Increment
        if (groupId != null) {
          final masterSnapshot = await _firestore
              .collection('tos')
              .where('groupId', isEqualTo: groupId)
              .where('isGroupMaster', isEqualTo: true)
              .limit(1)
              .get();

          if (masterSnapshot.docs.isNotEmpty) {
            batch.update(masterSnapshot.docs.first.reference, {
              'groupTotalConfirmed': FieldValue.increment(-1),
            });
          }
        }

        await batch.commit();
        clearCache(toId: toId);
      } else {
        await batch.commit();
      }
      
      // ✅ 연관 데이터 정리 (신분증 요청, 출근 기록, 스케줄 요청)
      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
      );

      print('✅ 확정 취소 완료 (패널티: $applyNoShowPenalty)');
      return true;
    } catch (e) {
      print('❌ 확정 취소 실패: $e');
      ToastHelper.showError('확정 취소에 실패했습니다');
      return false;
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 일괄 처리 메서드 (Batch Operations)
  // ═══════════════════════════════════════════════════════════

  /// 지원서 일괄 확정 (Increment 방식)
  Future<BatchResult> batchConfirmApplications({
    required List<String> applicationIds,
    required String adminUID,
  }) async {
    if (applicationIds.isEmpty) {
      return BatchResult(success: 0, failed: 0);
    }
    
    try {
      print('📦 [Batch] 일괄 확정 시작: ${applicationIds.length}건');
      
      // 1. 모든 지원서 조회 (병렬)
      final appFutures = applicationIds.map((id) => 
        _firestore.collection('applications').doc(id).get()
      );
      final appDocs = await Future.wait(appFutures);
      
      // 2. TO 정보 한 번만 조회
      String? toId;
      String? groupId;
      DocumentReference? toRef;
      DocumentReference? masterRef;
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) continue;
        final appData = appDoc.data()!;
        
        if (toId == null) {
          final toSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: appData['businessId'])
              .where('title', isEqualTo: appData['toTitle'])
              .where('date', isEqualTo: appData['workDate'])
              .limit(1)
              .get();
          
          if (toSnapshot.docs.isNotEmpty) {
            toRef = toSnapshot.docs.first.reference;
            toId = toSnapshot.docs.first.id;
            groupId = toSnapshot.docs.first.data()['groupId'] as String?;
            
            // 마스터 TO 찾기
            if (groupId != null) {
              final masterSnapshot = await _firestore
                  .collection('tos')
                  .where('groupId', isEqualTo: groupId)
                  .where('isGroupMaster', isEqualTo: true)
                  .limit(1)
                  .get();
              
              if (masterSnapshot.docs.isNotEmpty) {
                masterRef = masterSnapshot.docs.first.reference;
              }
            }
          }
        }
        break;
      }
      
      // 3. Batch 처리
      final batch = _firestore.batch();
      final now = Timestamp.now();
      int successCount = 0;
      int failedCount = 0;
      
      // WorkDetail별 카운트 집계
      Map<String, int> workDetailCounts = {};
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) {
          failedCount++;
          continue;
        }
        
        final appData = appDoc.data()!;
        
        if (appData['status'] == 'CONFIRMED' || appData['status'] == 'CANCELED') {
          failedCount++;
          continue;
        }
        
        // 지원서 확정
        batch.update(appDoc.reference, {
          'status': 'CONFIRMED',
          'confirmedAt': now,
          'confirmedBy': adminUID,
        });
        
        // WorkDetail 카운트 집계
        final workDetailId = appData['workDetailId'] as String?;
        if (workDetailId != null && workDetailId.isNotEmpty) {
          workDetailCounts[workDetailId] = (workDetailCounts[workDetailId] ?? 0) + 1;
        }
        
        successCount++;
      }
      
      // TO 통계 한 번에 업데이트
      if (toRef != null && successCount > 0) {
        batch.update(toRef, {
          'totalConfirmed': FieldValue.increment(successCount),
          'totalPending': FieldValue.increment(-successCount),
        });
      }
      
      // WorkDetail 통계 한 번에 업데이트
      for (var entry in workDetailCounts.entries) {
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(entry.key),
          {
            'currentCount': FieldValue.increment(entry.value),
            'pendingCount': FieldValue.increment(-entry.value),
          },
        );
      }
      
      // 그룹 마스터 통계 한 번에 업데이트
      if (masterRef != null && successCount > 0) {
        batch.update(masterRef, {
          'groupTotalConfirmed': FieldValue.increment(successCount),
          'groupTotalPending': FieldValue.increment(-successCount),
        });
      }
      
      await batch.commit();
      
      if (toId != null) clearCache(toId: toId);
      
      print('✅ [Batch] 확정 완료: $successCount건 성공, $failedCount건 실패');
      return BatchResult(success: successCount, failed: failedCount);
    } catch (e) {
      print('❌ [Batch] 일괄 확정 실패: $e');
      rethrow;
    }
  }

  /// 지원서 일괄 거절 (Increment 방식)
  Future<BatchResult> batchRejectApplications({
    required List<String> applicationIds,
    required String adminUID,
    String? message,
  }) async {
    if (applicationIds.isEmpty) {
      return BatchResult(success: 0, failed: 0);
    }
    
    try {
      print('📦 [Batch] 일괄 거절 시작: ${applicationIds.length}건');
      
      final appFutures = applicationIds.map((id) => 
        _firestore.collection('applications').doc(id).get()
      );
      final appDocs = await Future.wait(appFutures);
      
      String? toId;
      String? groupId;
      DocumentReference? toRef;
      DocumentReference? masterRef;
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) continue;
        final appData = appDoc.data()!;
        
        if (toId == null) {
          final toSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: appData['businessId'])
              .where('title', isEqualTo: appData['toTitle'])
              .where('date', isEqualTo: appData['workDate'])
              .limit(1)
              .get();
          
          if (toSnapshot.docs.isNotEmpty) {
            toRef = toSnapshot.docs.first.reference;
            toId = toSnapshot.docs.first.id;
            groupId = toSnapshot.docs.first.data()['groupId'] as String?;
            
            if (groupId != null) {
              final masterSnapshot = await _firestore
                  .collection('tos')
                  .where('groupId', isEqualTo: groupId)
                  .where('isGroupMaster', isEqualTo: true)
                  .limit(1)
                  .get();
              
              if (masterSnapshot.docs.isNotEmpty) {
                masterRef = masterSnapshot.docs.first.reference;
              }
            }
          }
        }
        break;
      }
      
      final batch = _firestore.batch();
      final now = Timestamp.now();
      int successCount = 0;
      int failedCount = 0;
      
      Map<String, int> workDetailCounts = {};
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) {
          failedCount++;
          continue;
        }
        
        final appData = appDoc.data()!;
        
        if (appData['status'] == 'CANCELED') {
          failedCount++;
          continue;
        }
        
        final updates = <String, dynamic>{
          'status': 'REJECTED',
          'rejectedAt': now,
          'rejectedBy': adminUID,
        };
        if (message != null) updates['rejectMessage'] = message;
        
        batch.update(appDoc.reference, updates);
        
        // PENDING인 경우만 카운트
        if (appData['status'] == 'PENDING') {
          final workDetailId = appData['workDetailId'] as String?;
          if (workDetailId != null && workDetailId.isNotEmpty) {
            workDetailCounts[workDetailId] = (workDetailCounts[workDetailId] ?? 0) + 1;
          }
        }
        
        successCount++;
      }
      
      // PENDING 거절 수만큼 통계 감소
      final pendingRejectCount = workDetailCounts.values.fold(0, (sum, v) => sum + v);
      
      if (toRef != null && pendingRejectCount > 0) {
        batch.update(toRef, {
          'totalPending': FieldValue.increment(-pendingRejectCount),
        });
      }
      
      for (var entry in workDetailCounts.entries) {
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(entry.key),
          {
            'pendingCount': FieldValue.increment(-entry.value),
          },
        );
      }
      
      if (masterRef != null && pendingRejectCount > 0) {
        batch.update(masterRef, {
          'groupTotalPending': FieldValue.increment(-pendingRejectCount),
        });
      }
      
      await batch.commit();
      
      if (toId != null) clearCache(toId: toId);
      
      print('✅ [Batch] 거절 완료: $successCount건');
      return BatchResult(success: successCount, failed: failedCount);
    } catch (e) {
      print('❌ [Batch] 일괄 거절 실패: $e');
      rethrow;
    }
  }
  /// 해당 application에 출퇴근 기록이 있는지 확인
  Future<bool> hasAttendanceRecord(String applicationId) async {
    try {
      final snapshot = await _firestore
          .collection('attendance')
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('❌ 출퇴근 기록 확인 실패: $e');
      return false;
    }
  }
  
}