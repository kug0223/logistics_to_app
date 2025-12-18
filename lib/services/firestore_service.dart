import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../models/core/user_model.dart';
import '../models/core/to_model.dart';
import '../models/core/group_model.dart';
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
part 'firestore/group_firestore.dart';
part 'firestore/application_firestore.dart';
part 'firestore/work_detail_firestore.dart';
part 'firestore/business_firestore.dart';
part 'firestore/attendance_firestore.dart';
part 'firestore/notification_firestore.dart';
part 'firestore/review_firestore.dart';
part 'firestore/id_card_firestore.dart';

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
  // 캐시 변수들
  // ═══════════════════════════════════════════════════════════
  final Map<String, List<ApplicationModel>> _applicationCache = {};
  final Map<String, List<WorkDetailModel>> _workDetailCache = {};
  final Map<String, Map<String, String>> _timeRangeCache = {};
  
  // 사용자 정보 캐시
  final Map<String, UserModel> _userCache = {};
  final Map<String, DateTime> _userCacheTimestamps = {};
  final Duration _userCacheValidDuration = const Duration(hours: 1);
  
  // TO 목록 캐시
  List<TOModel>? _activeTOsCache;
  List<TOModel>? _closedTOsCache;
  DateTime? _activeTOsCacheTime;
  DateTime? _closedTOsCacheTime;
  
  // 캐시 유효 시간
  final Duration _cacheValidDuration = const Duration(minutes: 5);
  final Duration _listCacheValidDuration = const Duration(seconds: 30);
  final Map<String, DateTime> _cacheTimestamps = {};

  // ═══════════════════════════════════════════════════════════
  // 캐시 관리
  // ═══════════════════════════════════════════════════════════
  
  /// TO 목록 캐시만 무효화 (TO 변경 시 호출)
  void invalidateListCache() {
    _activeTOsCache = null;
    _closedTOsCache = null;
    _activeTOsCacheTime = null;
    _closedTOsCacheTime = null;
    print('🗑️ TO 목록 캐시 무효화');
  }
  
  /// 캐시 초기화 (TO 수정/삭제 시 호출)
  void clearCache({String? toId}) {
    if (toId != null) {
      print('🗑️ 캐시 삭제: $toId');
      _applicationCache.remove(toId);
      _workDetailCache.remove(toId);
      _timeRangeCache.remove(toId);
      
      _cacheTimestamps.remove('application_$toId');
      _cacheTimestamps.remove('workDetail_$toId');
      _cacheTimestamps.remove('timeRange_$toId');
      
      print('🗑️ 타임스탬프도 삭제 완료');
    } else {
      print('🗑️ 전체 캐시 삭제');
      _applicationCache.clear();
      _workDetailCache.clear();
      _timeRangeCache.clear();
      _cacheTimestamps.clear();

      _activeTOsCache = null;
      _closedTOsCache = null;
      _activeTOsCacheTime = null;
      _closedTOsCacheTime = null;
      
      _userCache.clear();
      _userCacheTimestamps.clear();
      
      print('🗑️ 전체 캐시 삭제 완료 (사용자 포함)');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼 메서드들
  // ═══════════════════════════════════════════════════════════
  
  /// 시간이 겹치는지 체크
  bool _hasTimeOverlap(String s1, String e1, String s2, String e2) {
    final start1 = _timeToMinutes(s1);
    final end1 = _timeToMinutes(e1);
    final start2 = _timeToMinutes(s2);
    final end2 = _timeToMinutes(e2);
    
    return !(end1 <= start2 || end2 <= start1);
  }
  
  /// 시간을 분 단위로 변환 (예: "09:30" → 570)
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
  
  /// 특정 날짜에 근무하는지 확인 (장기 공고 고려)
  bool _isWorkingOnDate(ApplicationModel app, DateTime targetDate) {
    final isLongTerm = app.workDays != null && app.workDays!.isNotEmpty;
    
    if (!isLongTerm) {
      return _isSameDate(app.workDate, targetDate);
    }
    
    // 🔥 퇴사일이 있으면 그 날짜까지만
    final endDate = app.actualResignDate ?? app.workEndDate;
    if (endDate == null) return false;
    
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
    
    final isInRange = !targetDate.isBefore(effectiveStartDate) && 
                      !targetDate.isAfter(endDate);
    
    if (!isInRange) return false;
    
    if (app.workDays == null || app.workDays!.isEmpty) {
      return true;
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
  
  /// 시간 초과 체크 헬퍼 함수
  bool _isTimeExpired(TOModel to) {
    final now = DateTime.now();
    final workDate = DateTime(to.date.year, to.date.month, to.date.day);
    final today = DateTime(now.year, now.month, now.day);
    
    if (workDate.isBefore(today)) {
      return true;
    }
    
    if (workDate == today) {
      final startTime = to.displayStartTime;
      if (startTime.isEmpty || startTime == '--:--') {
        return false;
      }
      
      try {
        final parts = startTime.split(':');
        final startHour = int.parse(parts[0]);
        final startMinute = int.parse(parts[1]);
        
        final startDateTime = DateTime(
          now.year, now.month, now.day,
          startHour, startMinute,
        );
        
        return now.isAfter(startDateTime);
      } catch (e) {
        return false;
      }
    }
    
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // TO 목록 조회 (Active / Closed)
  // ═══════════════════════════════════════════════════════════

  /// 진행중인 TO 목록 조회 (대표 TO + 단일 TO)
  Future<List<TOModel>> getActiveTOs({
    bool publishedOnly = false,
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _activeTOsCache != null && _activeTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(_activeTOsCacheTime!);
        if (cacheAge < _listCacheValidDuration) {
          print('📦 [캐시] 진행중 TO 캐시 사용 (${cacheAge.inSeconds}초 경과)');
          
          if (publishedOnly) {
            // ✅ isPendingPublish로 실시간 체크 (시간 지나면 자동 공개)
            return _activeTOsCache!.where((to) => !to.isPendingPublish).toList();
          }
          return _activeTOsCache!;
        }
      }
      
      final snapshot = await _firestore
          .collection('tos')
          .where('status', isEqualTo: 'ACTIVE')
          .orderBy('date', descending: false)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
      
      print('✅ [서버필터] ACTIVE TO: ${allTOs.length}개 조회됨');

      final masterOrSingleTOs = allTOs.where((to) {
        if (to.groupId != null) {
          return to.isGroupMaster;
        }
        return true;
      }).toList();

      List<TOModel> activeTOs = masterOrSingleTOs;

      _activeTOsCache = activeTOs;
      _activeTOsCacheTime = DateTime.now();
      
      if (publishedOnly) {
        // ✅ isPendingPublish로 실시간 체크 (시간 지나면 자동 공개)
        final publishedTOs = activeTOs.where((to) => !to.isPendingPublish).toList();
        print('✅ [최적화] 공개된 진행중 TO: ${publishedTOs.length}개 (서버 조회)');
        return publishedTOs;
      }
      
      print('✅ [최적화] 진행중 TO 조회: ${activeTOs.length}개 (서버 조회)');
      return activeTOs;
    } catch (e) {
      print('❌ 진행중 TO 조회 실패: $e');
      return [];
    }
  }

  /// 마감된 TO 목록 조회 (대표 TO + 단일 TO)
  Future<List<TOModel>> getClosedTOs({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh && _closedTOsCache != null && _closedTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(_closedTOsCacheTime!);
        if (cacheAge < _listCacheValidDuration) {
          print('📦 [캐시] 마감 TO 캐시 사용 (${cacheAge.inSeconds}초 경과)');
          return _closedTOsCache!;
        }
      }
      
      final snapshot = await _firestore
          .collection('tos')
          .where('status', whereIn: ['CLOSED', 'FULL', 'EXPIRED'])
          .orderBy('date', descending: true)
          .limit(50)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
      
      print('✅ [서버필터] 마감된 TO: ${allTOs.length}개 조회됨');

      final masterOrSingleTOs = allTOs.where((to) {
        if (to.groupId != null) {
          return to.isGroupMaster;
        }
        return true;
      }).toList();

      final recentClosedTOs = masterOrSingleTOs.take(5).toList();

      // ✅ 그룹 마스터인 경우 하위 ACTIVE TO 있으면 제외 (status 불일치 보정)
      final List<TOModel> verifiedClosedTOs = [];
      for (var to in recentClosedTOs) {
        if (to.isGroupMaster && to.groupId != null) {
          // 그룹 내 ACTIVE TO 있는지 빠르게 체크
          final activeCheck = await _firestore
              .collection('tos')
              .where('groupId', isEqualTo: to.groupId)
              .where('status', isEqualTo: 'ACTIVE')
              .limit(1)
              .get();
          
          if (activeCheck.docs.isNotEmpty) {
            // ACTIVE TO 있음 → 마스터 status 보정 후 마감 목록에서 제외
            print('⚠️ [Status 보정] ${to.title} 마스터 → ACTIVE (하위 ACTIVE TO 존재)');
            await _firestore.collection('tos').doc(to.id).update({
              'status': 'ACTIVE',
              'statusUpdatedAt': FieldValue.serverTimestamp(),
            });
            continue; // 마감 목록에서 제외
          }
        }
        verifiedClosedTOs.add(to);
      }

      _closedTOsCache = verifiedClosedTOs;
      _closedTOsCacheTime = DateTime.now();
      
      print('✅ [최적화] 마감된 TO: ${verifiedClosedTOs.length}개 (서버 조회, ${recentClosedTOs.length - verifiedClosedTOs.length}개 보정됨)');
      return verifiedClosedTOs;
    } catch (e) {
      print('❌ 마감된 TO 조회 실패: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TO 마감 관리
  // ═══════════════════════════════════════════════════════════

  /// TO 수동 마감
  Future<bool> closeTOManually(String toId, String adminUID) async {
    try {
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      final toData = toDoc.data();
      final groupId = toData?['groupId'] as String?;
      final isGroupMaster = toData?['isGroupMaster'] ?? false;
      
      await _firestore.collection('tos').doc(toId).update({
        'isManualClosed': true,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': adminUID,
        'status': 'CLOSED',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      clearCache(toId: toId);
      invalidateListCache();

      if (groupId != null && !isGroupMaster) {
        await _updateGroupMasterStatus(groupId);
      }

      print('✅ TO 수동 마감 완료: $toId');
      return true;
    } catch (e) {
      print('❌ TO 수동 마감 실패: $e');
      return false;
    }
  }

  /// TO 재오픈 (마감 취소)
  Future<bool> reopenTO(String toId, String adminUID) async {
    try {
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      final toData = toDoc.data();
      final groupId = toData?['groupId'] as String?;
      final jobType = toData?['jobType'] ?? 'short';
      final workDate = (toData?['date'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now();
      final hoursBeforeStart = toData?['hoursBeforeStart'] ?? 2;
      
      // 🔥 WorkDetails 조회 및 마감시간 재계산
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isNotEmpty) {
        final workBatch = _firestore.batch();
        
        for (var workDoc in workDetailsSnapshot.docs) {
          final workData = workDoc.data();
          
          final updates = <String, dynamic>{
            'isManualClosed': false,
            'closedAt': FieldValue.delete(),
            'closedBy': FieldValue.delete(),
          };
          
          // 🔥 단기공고만 마감시간 재계산
          if (jobType != 'long_term') {
            final startTime = workData['startTime'] as String;
            final timeParts = startTime.split(':');
            final workStartDateTime = DateTime(
              workDate.year,
              workDate.month,
              workDate.day,
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
            final newDeadline = workStartDateTime.subtract(Duration(hours: hoursBeforeStart));
            updates['applicationDeadline'] = Timestamp.fromDate(newDeadline.toUtc());  // 🔥 .toUtc() 추가
          }
          
          workBatch.update(workDoc.reference, updates);
        }
        
        await workBatch.commit();
        print('   ✅ WorkDetails 재오픈 + 마감시간 재계산: ${workDetailsSnapshot.docs.length}개');
      }
      
      // 🔥 TO 문서 업데이트 (단기공고는 마감시간도 재계산)
      final toUpdates = <String, dynamic>{
        'isManualClosed': false,
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
      };
      
      if (jobType != 'long_term' && workDetailsSnapshot.docs.isNotEmpty) {
        final firstWorkStart = workDetailsSnapshot.docs.first.data()['startTime'] as String;
        final timeParts = firstWorkStart.split(':');
        final startDateTime = DateTime(
          workDate.year,
          workDate.month,
          workDate.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        final newTODeadline = startDateTime.subtract(Duration(hours: hoursBeforeStart));
        toUpdates['applicationDeadline'] = Timestamp.fromDate(newTODeadline.toUtc());  // 🔥 .toUtc() 추가
      }
      
      await _firestore.collection('tos').doc(toId).update(toUpdates);
      
      await updateTOStatus(toId);
      
      clearCache(toId: toId);
      invalidateListCache();

      if (groupId != null) {
        await _updateGroupMasterStatus(groupId);
      }

      print('✅ TO 재오픈 완료: $toId');
      return true;
    } catch (e) {
      print('❌ TO 재오픈 실패: $e');
      return false;
    }
  }

  /// 그룹 TO 전체 마감 (WorkDetails 포함)
  Future<bool> closeGroupTOs(String groupId, String adminUID) async {
    try {
      print('🔒 [closeGroupTOs] 시작: $groupId');
      
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없음');
        return false;
      }

      final batch = _firestore.batch();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': true,
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': adminUID,
          'status': 'CLOSED',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
        
        print('   📝 TO 마감: ${doc.id}');
      }

      await batch.commit();
      print('✅ TO 마감 완료: ${snapshot.docs.length}개');

      // ✅ groups 컬렉션 문서도 마감 처리
      await _firestore.collection('groups').doc(groupId).update({
        'status': 'CLOSED',
        'isManualClosed': true,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': adminUID,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ groups 문서 마감 완료: $groupId');

      for (var doc in snapshot.docs) {
        final workDetailsSnapshot = await _firestore
            .collection('tos')
            .doc(doc.id)
            .collection('workDetails')
            .get();

        if (workDetailsSnapshot.docs.isNotEmpty) {
          final workBatch = _firestore.batch();
          
          for (var workDoc in workDetailsSnapshot.docs) {
            workBatch.update(workDoc.reference, {
              'isManualClosed': true,
              'closedAt': FieldValue.serverTimestamp(),
              'closedBy': adminUID,
            });
          }
          
          await workBatch.commit();
          print('   ✅ WorkDetails 마감: ${workDetailsSnapshot.docs.length}개');
        }
        
        clearCache(toId: doc.id);
      }

      invalidateListCache();
      print('✅ 그룹 전체 마감 완료: $groupId');
      return true;
    } catch (e) {
      print('❌ 그룹 마감 실패: $e');
      return false;
    }
  }

  /// 그룹 TO 전체 재오픈 (WorkDetails 포함)
  Future<bool> reopenGroupTOs(String groupId, String adminUID) async {
    try {
      print('🔓 [reopenGroupTOs] 시작: $groupId');
      
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없음');
        return false;
      }

      final batch = _firestore.batch();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': false,
          'reopenedAt': FieldValue.serverTimestamp(),
          'reopenedBy': adminUID,
        });
      }

      await batch.commit();
      print('✅ TO 재오픈 완료: ${snapshot.docs.length}개');

      for (var doc in snapshot.docs) {
        final toData = doc.data();
        final jobType = toData['jobType'] ?? 'short';
        final workDate = (toData['date'] as Timestamp).toDate().toLocal();
        final hoursBeforeStart = toData['hoursBeforeStart'] ?? 2;
        
        final workDetailsSnapshot = await _firestore
            .collection('tos')
            .doc(doc.id)
            .collection('workDetails')
            .get();

        if (workDetailsSnapshot.docs.isNotEmpty) {
          final workBatch = _firestore.batch();
          
          for (var workDoc in workDetailsSnapshot.docs) {
            final workData = workDoc.data();
            
            final updates = <String, dynamic>{
              'isManualClosed': false,
              'closedAt': FieldValue.delete(),
              'closedBy': FieldValue.delete(),
            };
            
            // 🔥 단기공고만 마감시간 재계산
            if (jobType != 'long_term') {
              final startTime = workData['startTime'] as String;
              final timeParts = startTime.split(':');
              final workStartDateTime = DateTime(
                workDate.year,
                workDate.month,
                workDate.day,
                int.parse(timeParts[0]),
                int.parse(timeParts[1]),
              );
              final newDeadline = workStartDateTime.subtract(Duration(hours: hoursBeforeStart));
              updates['applicationDeadline'] = Timestamp.fromDate(newDeadline.toUtc());  // 🔥 .toUtc() 추가
            }
            
            workBatch.update(workDoc.reference, updates);
          }
          
          await workBatch.commit();
          print('   ✅ WorkDetails 재오픈 + 마감시간 재계산: ${workDetailsSnapshot.docs.length}개');
        }
        
        // 🔥 TO 문서의 applicationDeadline도 재계산 (단기공고만)
        if (jobType != 'long_term') {
          final firstWorkStart = workDetailsSnapshot.docs.isNotEmpty
              ? workDetailsSnapshot.docs.first.data()['startTime'] as String
              : '09:00';
          final timeParts = firstWorkStart.split(':');
          final startDateTime = DateTime(
            workDate.year,
            workDate.month,
            workDate.day,
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
          );
          final newTODeadline = startDateTime.subtract(Duration(hours: hoursBeforeStart));
          
          await _firestore.collection('tos').doc(doc.id).update({
            'applicationDeadline': Timestamp.fromDate(newTODeadline.toUtc()),  // 🔥 .toUtc() 추가
          });
        }
        
        clearCache(toId: doc.id);
      }

      for (var doc in snapshot.docs) {
        await updateTOStatus(doc.id);
      }
      
      // ✅ groups 컬렉션 문서도 재오픈 처리
      await _firestore.collection('groups').doc(groupId).update({
        'status': 'ACTIVE',
        'isManualClosed': false,
        'closedAt': FieldValue.delete(),
        'closedBy': FieldValue.delete(),
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ groups 문서 재오픈 완료: $groupId');

      invalidateListCache();
      print('✅ 그룹 전체 재오픈 완료: $groupId');
      return true;
    } catch (e) {
      print('❌ 그룹 재오픈 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TO 상태 관리
  // ═══════════════════════════════════════════════════════════

  /// TO 상태 계산 (status 필드용)
  String _calculateTOStatus(Map<String, dynamic> data) {
    if (data['isManualClosed'] == true) {
      return 'CLOSED';
    }
    
    final totalConfirmed = data['totalConfirmed'] ?? 0;
    final totalRequired = data['totalRequired'] ?? 0;
    if (totalRequired > 0 && totalConfirmed >= totalRequired) {
      return 'FULL';
    }
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final jobType = data['jobType'] ?? 'short';
    if (jobType == 'long_term') {
      final deadline = data['applicationDeadline'];
      if (deadline != null) {
        final deadlineDate = (deadline as Timestamp).toDate();
        if (now.isAfter(deadlineDate)) {
          return 'EXPIRED';
        }
      }
      return 'ACTIVE';
    }
    
    final dateTimestamp = data['date'];
    if (dateTimestamp != null) {
      final workDate = (dateTimestamp as Timestamp).toDate().toLocal();
      final workDateOnly = DateTime(workDate.year, workDate.month, workDate.day);
      
      if (workDateOnly.isBefore(today)) {
        return 'EXPIRED';
      }
      
      if (workDateOnly.isAtSameMomentAs(today)) {
        final startTime = data['startTime'] as String?;
        if (startTime != null && startTime.contains(':')) {
          final parts = startTime.split(':');
          if (parts.length >= 2) {
            final workStart = DateTime(
              workDate.year, workDate.month, workDate.day,
              int.parse(parts[0]), int.parse(parts[1]),
            );
            if (now.isAfter(workStart)) {
              return 'EXPIRED';
            }
          }
        }
      }
    }
    
    return 'ACTIVE';
  }

  /// 단일 TO 상태 업데이트
  Future<bool> updateTOStatus(String toId) async {
    try {
      final doc = await _firestore.collection('tos').doc(toId).get();
      if (!doc.exists) return false;
      
      final data = doc.data()!;
      final newStatus = _calculateTOStatus(data);
      final currentStatus = data['status'] ?? 'ACTIVE';
      
      if (newStatus != currentStatus) {
        await _firestore.collection('tos').doc(toId).update({
          'status': newStatus,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ TO 상태 업데이트: $toId → $newStatus');
      }
      
      return true;
    } catch (e) {
      print('❌ TO 상태 업데이트 실패: $e');
      return false;
    }
  }

  /// 기존 TO 데이터 마이그레이션 (status 필드 추가)
  Future<int> migrateToStatusField() async {
    try {
      print('🔄 TO status 필드 마이그레이션 시작...');
      
      final snapshot = await _firestore.collection('tos').get();
      
      int migrated = 0;
      int skipped = 0;
      WriteBatch batch = _firestore.batch();
      int batchCount = 0;
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        if (data['status'] != null) {
          skipped++;
          continue;
        }
        
        final status = _calculateTOStatus(data);
        
        batch.update(doc.reference, {
          'status': status,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
        
        migrated++;
        batchCount++;
        
        if (batchCount >= 500) {
          await batch.commit();
          print('   진행: $migrated개 마이그레이션됨');
          batch = _firestore.batch();
          batchCount = 0;
        }
      }
      
      if (batchCount > 0) {
        await batch.commit();
      }
      
      print('✅ 마이그레이션 완료: $migrated개 업데이트, $skipped개 스킵');
      return migrated;
    } catch (e) {
      print('❌ 마이그레이션 실패: $e');
      return -1;
    }
  }
  /// 🔄 Application workDetailId/toId/groupId 마이그레이션
  /// 기존 지원서에 누락된 workDetailId, toId, groupId를 채워넣음
  Future<Map<String, int>> migrateApplicationWorkDetailIds() async {
    try {
      print('🔄 [Migration] Application workDetailId 마이그레이션 시작...');
      
      int migrated = 0;
      int skipped = 0;
      int failed = 0;
      
      // 1. workDetailId가 없는 applications 조회
      final snapshot = await _firestore
          .collection('applications')
          .get();
      
      print('   📊 전체 지원서: ${snapshot.docs.length}개');
      
      // TO 캐시 (중복 조회 방지)
      final Map<String, DocumentSnapshot> toCache = {};
      final Map<String, List<QueryDocumentSnapshot>> workDetailCache = {};
      
      WriteBatch batch = _firestore.batch();
      int batchCount = 0;
      
      for (var appDoc in snapshot.docs) {
        final appData = appDoc.data();
        final existingWorkDetailId = appData['workDetailId'] as String?;
        final existingToId = appData['toId'] as String?;
        final existingGroupId = appData['groupId'] as String?;
        
        // 모두 있으면 스킵
        if (existingWorkDetailId != null && existingWorkDetailId.isNotEmpty &&
            existingToId != null && existingToId.isNotEmpty) {
          skipped++;
          continue;
        }
        
        try {
          // 2. TO 찾기
          final businessId = appData['businessId'] as String?;
          final toTitle = appData['toTitle'] as String?;
          final workDate = appData['workDate'] as Timestamp?;
          
          if (businessId == null || toTitle == null || workDate == null) {
            print('   ⚠️ 필수 필드 누락: ${appDoc.id}');
            failed++;
            continue;
          }
          
          // 캐시 키
          final toCacheKey = '${businessId}_${toTitle}_${workDate.toDate().toIso8601String().split('T')[0]}';
          
          DocumentSnapshot? toDoc;
          if (toCache.containsKey(toCacheKey)) {
            toDoc = toCache[toCacheKey];
          } else {
            // TO 조회 (단기 공고)
            final toSnapshot = await _firestore
                .collection('tos')
                .where('businessId', isEqualTo: businessId)
                .where('title', isEqualTo: toTitle)
                .where('date', isEqualTo: workDate)
                .limit(1)
                .get();
            
            if (toSnapshot.docs.isEmpty) {
              // 장기 공고 시도
              final longTermSnapshot = await _firestore
                  .collection('tos')
                  .where('businessId', isEqualTo: businessId)
                  .where('title', isEqualTo: toTitle)
                  .where('jobType', isEqualTo: 'long_term')
                  .limit(1)
                  .get();
              
              if (longTermSnapshot.docs.isNotEmpty) {
                toDoc = longTermSnapshot.docs.first;
              }
            } else {
              toDoc = toSnapshot.docs.first;
            }
            
            if (toDoc != null) {
              toCache[toCacheKey] = toDoc;
            }
          }
          
          if (toDoc == null) {
            print('   ⚠️ TO를 찾을 수 없음: ${appDoc.id}');
            failed++;
            continue;
          }
          
          final toId = toDoc.id;
          final toData = toDoc.data() as Map<String, dynamic>;
          final groupId = toData['groupId'] as String?;
          
          // 3. WorkDetail 찾기
          String? foundWorkDetailId;
          
          if (existingWorkDetailId == null || existingWorkDetailId.isEmpty) {
            final selectedWorkType = appData['selectedWorkType'] as String?;
            final startTime = appData['startTime'] as String?;
            final endTime = appData['endTime'] as String?;
            
            if (selectedWorkType != null && startTime != null && endTime != null) {
              // WorkDetails 캐시
              List<QueryDocumentSnapshot>? workDetails;
              if (workDetailCache.containsKey(toId)) {
                workDetails = workDetailCache[toId];
              } else {
                final workDetailSnapshot = await _firestore
                    .collection('tos')
                    .doc(toId)
                    .collection('workDetails')
                    .get();
                workDetails = workDetailSnapshot.docs;
                workDetailCache[toId] = workDetails;
              }
              
              // workType + startTime + endTime 매칭
              for (var wd in workDetails!) {
                final wdData = wd.data() as Map<String, dynamic>;
                if (wdData['workType'] == selectedWorkType &&
                    wdData['startTime'] == startTime &&
                    wdData['endTime'] == endTime) {
                  foundWorkDetailId = wd.id;
                  break;
                }
              }
              
              // 시간이 다를 경우 workType만으로 매칭 (폴백)
              if (foundWorkDetailId == null) {
                for (var wd in workDetails) {
                  final wdData = wd.data() as Map<String, dynamic>;
                  if (wdData['workType'] == selectedWorkType) {
                    foundWorkDetailId = wd.id;
                    print('   ⚠️ 시간 불일치, workType만 매칭: ${appDoc.id}');
                    break;
                  }
                }
              }
            }
          }
          
          // 4. 업데이트할 필드 결정
          final updates = <String, dynamic>{};
          
          if ((existingWorkDetailId == null || existingWorkDetailId.isEmpty) && 
              foundWorkDetailId != null) {
            updates['workDetailId'] = foundWorkDetailId;
          }
          
          if (existingToId == null || existingToId.isEmpty) {
            updates['toId'] = toId;
          }
          
          if ((existingGroupId == null || existingGroupId.isEmpty) && groupId != null) {
            updates['groupId'] = groupId;
          }
          
          if (updates.isEmpty) {
            skipped++;
            continue;
          }
          
          // 5. Batch 업데이트
          batch.update(appDoc.reference, updates);
          migrated++;
          batchCount++;
          
          // 500개마다 커밋
          if (batchCount >= 500) {
            await batch.commit();
            print('   📦 진행: $migrated개 마이그레이션됨');
            batch = _firestore.batch();
            batchCount = 0;
          }
          
        } catch (e) {
          print('   ❌ 처리 실패 (${appDoc.id}): $e');
          failed++;
        }
      }
      
      // 남은 배치 커밋
      if (batchCount > 0) {
        await batch.commit();
      }
      
      print('✅ [Migration] 완료!');
      print('   ✅ 마이그레이션: $migrated개');
      print('   ⏭️ 스킵 (이미 있음): $skipped개');
      print('   ❌ 실패: $failed개');
      
      return {
        'migrated': migrated,
        'skipped': skipped,
        'failed': failed,
      };
    } catch (e) {
      print('❌ [Migration] 마이그레이션 실패: $e');
      return {
        'migrated': 0,
        'skipped': 0,
        'failed': -1,
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 통계 재계산
  // ═══════════════════════════════════════════════════════════

  /// WorkDetail 통계 재계산 (TO별)
  Future<bool> recalculateWorkDetailStats(String toId) async {
    try {
      print('📊 WorkDetail 통계 재계산 시작: $toId');
      
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return false;
      }
      
      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;
      
      final appsSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();
      
      print('   전체 지원서: ${appsSnapshot.docs.length}개');
      
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isEmpty) {
        print('   ⚠️ WorkDetails가 없습니다');
        return true;
      }
      
      final batch = _firestore.batch();
      int updatedCount = 0;
      
      for (var workDetailDoc in workDetailsSnapshot.docs) {
        final workDetailId = workDetailDoc.id;
        final workDetailData = workDetailDoc.data();
        final workType = workDetailData['workType'];
        final workStartTime = workDetailData['startTime'] ?? '';
        final workEndTime = workDetailData['endTime'] ?? '';
        
        int confirmedCount = 0;
        int pendingCount = 0;
        
        for (var appDoc in appsSnapshot.docs) {
          final appData = appDoc.data();
          final appWorkDetailId = appData['workDetailId'];
          final selectedWorkType = appData['selectedWorkType'];
          final appStartTime = appData['startTime'] ?? '';
          final appEndTime = appData['endTime'] ?? '';
          final status = appData['status'];
          
          bool isMatch = false;
          if (appWorkDetailId != null && appWorkDetailId.isNotEmpty) {
            isMatch = (appWorkDetailId == workDetailId);
          } else {
            isMatch = (selectedWorkType == workType &&
                       appStartTime == workStartTime &&
                       appEndTime == workEndTime);
          }
          
          if (isMatch) {
            if (status == 'CONFIRMED') confirmedCount++;
            if (status == 'PENDING') pendingCount++;
          }
        }
        
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'currentCount': confirmedCount,
            'pendingCount': pendingCount,
          },
        );
        
        print('   ✅ $workType: 확정 $confirmedCount, 대기 $pendingCount');
        updatedCount++;
      }
      
      await batch.commit();
      clearCache(toId: toId);
      
      print('✅ WorkDetail 통계 재계산 완료: $updatedCount개 업무');
      return true;
    } catch (e) {
      print('❌ WorkDetail 통계 재계산 실패: $e');
      return false;
    }
  }
  
  /// TO 전체 통계 재계산 (TO + WorkDetails)
  Future<bool> recalculateTOStats(String toId) async {
    try {
      print('📊 TO 전체 통계 재계산 시작: $toId');
      
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return false;
      }
      
      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;
      
      final appsSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();
      
      int totalPending = 0;
      int totalConfirmed = 0;
      
      for (var doc in appsSnapshot.docs) {
        final data = doc.data();
        final status = data['status'];
        
        if (status == 'PENDING') totalPending++;
        if (status == 'CONFIRMED') totalConfirmed++;
      }
      
      await _firestore.collection('tos').doc(toId).update({
        'totalPending': totalPending,
        'totalConfirmed': totalConfirmed,
        'updatedAt': Timestamp.now(),
      });
      
      print('   ✅ TO 통계: 대기 $totalPending, 확정 $totalConfirmed');
      
      await recalculateWorkDetailStats(toId);
      await updateTOStatus(toId);
      
      print('✅ TO 전체 통계 재계산 완료');
      return true;
    } catch (e) {
      print('❌ TO 전체 통계 재계산 실패: $e');
      return false;
    }
  }
  
  /// 그룹 전체 통계 재계산
  Future<bool> recalculateGroupStats(String groupId) async {
    try {
      print('📊 그룹 전체 통계 재계산 시작: $groupId');
      
      final groupTOs = await getTOsByGroup(groupId);
      
      if (groupTOs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없습니다: $groupId');
        return false;
      }
      
      print('   그룹 TO: ${groupTOs.length}개');
      
      final results = await Future.wait(
        groupTOs.map((to) => recalculateTOStats(to.id))
      );
      final successCount = results.where((r) => r).length;
      
      print('✅ 그룹 통계 재계산 완료: $successCount/${groupTOs.length}개 성공');
      return successCount == groupTOs.length;
    } catch (e) {
      print('❌ 그룹 통계 재계산 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 우리 사업장 근무 이력 (복합 조회)
  // ═══════════════════════════════════════════════════════════

  /// 특정 사용자의 우리 사업장 근무 이력 조회
  Future<Map<String, dynamic>> getBusinessWorkHistory({
    required String userId,
    required String businessId,
  }) async {
    try {
      print('🔍 [getBusinessWorkHistory] 조회: userId=$userId, businessId=$businessId');
      
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
      
      double? avgRating;
      if (reviews.isNotEmpty) {
        double total = 0;
        for (var review in reviews) {
          total += review.rating;
        }
        avgRating = total / reviews.length;
      }
      
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
}