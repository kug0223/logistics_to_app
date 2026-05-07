import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../models/core/user_model.dart';
import '../models/core/to_model.dart';
import '../models/core/slot_model.dart';
import '../models/core/work_detail_data.dart';
import '../models/core/application_model.dart';
import '../models/ui/admin_to_list_ui_models.dart';
import '../models/core/business_model.dart';
import '../models/core/work_type_model.dart';
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
part 'firestore/application_firestore.dart';
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
  // 싱글톤: 앱 전체에서 인스턴스 하나만 사용 → 캐시 공유, Firestore 읽기 절감
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // ═══════════════════════════════════════════════════════════
  // 캐시 변수들
  // ═══════════════════════════════════════════════════════════
  final Map<String, List<ApplicationModel>> _applicationCache = {};

  // 사용자 정보 캐시
  final Map<String, UserModel> _userCache = {};
  final Map<String, DateTime> _userCacheTimestamps = {};
  final Duration _userCacheValidDuration = const Duration(hours: 1);

  // 캐시 유효 시간
  final Duration _cacheValidDuration = const Duration(minutes: 5);
  final Map<String, DateTime> _cacheTimestamps = {};

  // ═══════════════════════════════════════════════════════════
  // 캐시 관리
  // ═══════════════════════════════════════════════════════════
  
  /// 캐시 초기화 (TO 수정/삭제 시 호출)
  void clearCache({String? toId}) {
    if (toId != null) {
      _applicationCache.remove(toId);
      _cacheTimestamps.remove('application_$toId');
    } else {
      _applicationCache.clear();
      _cacheTimestamps.clear();
      _userCache.clear();
      _userCacheTimestamps.clear();
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
  

  // ═══════════════════════════════════════════════════════════
  // TO 마감 관리
  // ═══════════════════════════════════════════════════════════

  /// TO 수동 마감
  Future<bool> closeTOManually(String toId, String adminUID) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'isManualClosed': true,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': adminUID,
        'status': 'CLOSED',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      clearCache(toId: toId);
      debugPrint('✅ TO 수동 마감 완료: $toId');
      return true;
    } catch (e) {
      debugPrint('❌ TO 수동 마감 실패: $e');
      return false;
    }
  }

  /// TO 재오픈 (마감 취소)
  Future<bool> reopenTO(String toId, String adminUID) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'isManualClosed': false,
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
        'status': 'ACTIVE',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      clearCache(toId: toId);
      debugPrint('✅ TO 재오픈 완료: $toId');
      return true;
    } catch (e) {
      debugPrint('❌ TO 재오픈 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 통계 재계산
  // ═══════════════════════════════════════════════════════════

  /// TO 통계 재계산 (applications에서 직접 집계)
  Future<bool> recalculateTOStats(String toId) async {
    try {
      final to = await getTO(toId);
      if (to == null) return false;

      final appsSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('businessId', isEqualTo: to.businessId)
          .get();

      int totalPending = 0;
      int totalConfirmed = 0;
      for (final doc in appsSnap.docs) {
        final status = doc.data()['status'];
        if (status == 'PENDING') totalPending++;
        if (status == 'CONFIRMED') totalConfirmed++;
      }

      await _firestore.collection('tos').doc(toId).update({
        'totalPending': totalPending,
        'totalConfirmed': totalConfirmed,
      });

      clearCache(toId: toId);
      debugPrint('✅ TO 통계 재계산 완료: $toId (대기 $totalPending, 확정 $totalConfirmed)');
      return true;
    } catch (e) {
      debugPrint('❌ TO 통계 재계산 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 하위 호환 메서드 (구 아키텍처 → 신 아키텍처 브리지)
  // Phase 5-6 리팩터링 완료 후 제거 예정.
  // ═══════════════════════════════════════════════════════════

  /// 캐시 무효화 (clearCache 별칭)
  void invalidateListCache() => clearCache();

  /// 구 getWorkDetails — TO 문서에 내장된 workDetails 배열 반환
  Future<List<WorkDetailData>> getWorkDetails(String toId) async {
    final to = await getTO(toId);
    return to?.workDetails ?? [];
  }

  /// 구 loadTOWorkDetails — TO 내장 workDetails + 실제 지원 통계 반환
  Future<Map<String, dynamic>> loadTOWorkDetails(TOModel to) async {
    final workDetails = to.workDetails;
    final Map<String, Map<String, int>> workStats = {
      for (final w in workDetails) w.id: {'confirmed': 0, 'pending': 0},
    };
    try {
      final apps = await getApplicationsByTOId(to.id, businessId: to.businessId);
      for (final app in apps) {
        if (app.status != 'CONFIRMED' && app.status != 'PENDING') continue;
        final key = app.selectedWorkType;
        workStats[key] ??= {'confirmed': 0, 'pending': 0};
        if (app.status == 'CONFIRMED') {
          workStats[key]!['confirmed'] = (workStats[key]!['confirmed'] ?? 0) + 1;
        } else {
          workStats[key]!['pending'] = (workStats[key]!['pending'] ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint('⚠️ loadTOWorkDetails stats 조회 실패: $e');
    }
    return {'workDetails': workDetails, 'workStats': workStats};
  }

  /// 구 getTOGroupItemsLight — TO 목록을 TOGroupItem으로 래핑
  /// [businessIds] null이면 슈퍼관리자 전체 조회, 비어있으면 빈 결과 반환
  Future<List<TOGroupItem>> getTOGroupItemsLight({
    bool activeOnly = false,
    bool closedOnly = false,
    List<String>? businessIds,
  }) async {
    try {
      // 사업장 목록이 빈 리스트면 조회 대상 없음
      if (businessIds != null && businessIds.isEmpty) return [];

      Query query = _firestore.collection('tos').orderBy('createdAt', descending: true);
      if (businessIds != null && businessIds.length == 1) {
        query = query.where('businessId', isEqualTo: businessIds.first);
      } else if (businessIds != null && businessIds.length > 1) {
        query = query.where('businessId', whereIn: businessIds.take(10).toList());
      }
      if (activeOnly) {
        query = query.where('status', whereIn: ['ACTIVE', 'FULL', 'SCHEDULED']);
      } else if (closedOnly) {
        query = query.where('status', whereIn: ['CLOSED', 'EXPIRED']);
      }
      final snap = await query.get();
      return snap.docs
          .map((d) => TOGroupItem(singleTO: TOModel.fromMap(d.data() as Map<String, dynamic>, d.id)))
          .toList();
    } catch (e) {
      debugPrint('❌ getTOGroupItemsLight 실패: $e');
      return [];
    }
  }

  /// 구 loadGroupTOsLight — 그룹 구조 제거됨, 빈 리스트 반환
  Future<List<TOItem>> loadGroupTOsLight(String groupId) async => [];

  /// 구 getActiveTOs — getPublishedTOs 위임
  Future<List<TOModel>> getActiveTOs({String? businessId, bool publishedOnly = false}) async {
    if (businessId != null) {
      return getTOsByBusiness(businessId, activeOnly: true);
    }
    return getPublishedTOs();
  }

  /// 구 getApplicationsByTO — businessId+title로 조회
  Future<List<ApplicationModel>> getApplicationsByTO(
    String businessId,
    String toTitle,
    DateTime workDate,
  ) async {
    try {
      final snap = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .get();
      return snap.docs.map((d) => ApplicationModel.fromFirestore(d)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 구 getApplicationsForTO — getApplicationsByTOId 위임
  Future<List<ApplicationModel>> getApplicationsForTO({
    required String toId,
    String? uid,
  }) async {
    final apps = await getApplicationsByTOId(toId);
    if (uid != null) return apps.where((a) => a.uid == uid).toList();
    return apps;
  }

  /// 구 getTOByApplication — application의 toId로 TO 조회
  Future<TOModel?> getTOByApplication(ApplicationModel app) async {
    if (app.toId == null) return null;
    return getTO(app.toId!);
  }

  /// 구 syncGroupStats / syncGroupMasterStats — TO 통계 재계산으로 위임
  Future<bool> syncGroupStats(String toId) async => recalculateTOStats(toId);
  Future<bool> syncGroupMasterStats(String toId) async => recalculateTOStats(toId);

  /// 구 applyToTOWithWorkType — applyToTO 위임 (toId 필수)
  Future<bool> applyToTOWithWorkType({
    required String uid,
    required String businessId,
    required String businessName,
    required String toTitle,
    required DateTime workDate,
    required String selectedWorkType,
    String? workDetailId,
    required int wage,
    String? wageType,
    String? workTypeIcon,
    String? workTypeColor,
    String? workTypeBackgroundColor,
    String? startTime,
    String? endTime,
    DateTime? workEndDate,
    List<String>? workDays,
    String? type,
    String? toId,
    String? slotId,
    DateTime? desiredStartDate,
  }) async {
    if (toId == null) {
      debugPrint('⚠️ applyToTOWithWorkType: toId 없음');
      return false;
    }
    return applyToTO(
      toId: toId,
      slotId: slotId,
      businessId: businessId,
      businessName: businessName,
      toTitle: toTitle,
      workDate: workDate,
      uid: uid,
      selectedWorkType: selectedWorkType,
      startTime: startTime ?? '',
      endTime: endTime ?? '',
      wage: wage,
      wageType: wageType ?? 'hourly',
      workTypeIcon: workTypeIcon ?? '📋',
      workTypeColor: workTypeColor ?? '#2196F3',
      workTypeBackgroundColor: workTypeBackgroundColor ?? '#E3F2FD',
      workEndDate: workEndDate,
      workDays: workDays,
      desiredStartDate: desiredStartDate,
    );
  }

  /// 구 WorkDetail 관련 메서드 — 내장 배열로 전환, no-op
  Future<bool> closeWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async => false;
  Future<bool> reopenWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async => false;
  Future<bool> stopEmergencyRecruitment({
    required String toId,
    required String workDetailId,
    String? adminUID,
  }) async => false;

  /// 출근 기록 확인 — attendance_firestore에서 처리, 여기서는 false 반환
  Future<bool> hasAttendanceRecord(String applicationId) async => false;

  /// 구 자동 만료 — no-op
  Future<void> autoExpirePendingApplications(String uid) async {}

  /// 마이그레이션 메서드 — 완료됨, no-op
  Future<Map<String, dynamic>> migrateApplicationWorkDetailIds() async =>
      {'migrated': 0, 'skipped': 0, 'failed': 0};
  Future<int> migrateAllGroupMasterStats() async => 0;

  /// 퇴사/해지 관련 메서드 스텁 — Phase 5에서 구현 예정
  Future<bool> requestTermination({
    required String applicationId,
    String? toId,
    String? uid,
    String? businessId,
    String? reason,
    String? requestedByUid,
  }) async => false;

  Future<bool> cancelTerminationRequest(String applicationId) async => false;

  Future<bool> approveTermination(String applicationId, {String? adminUID}) async => false;

  Future<bool> rejectTermination({
    required String applicationId,
    String? adminUID,
    String? rejectReason,
  }) async => false;

  Future<bool> requestResignation({
    required String applicationId,
    String? toId,
    String? uid,
    String? reason,
    DateTime? resignDate,
  }) async => false;

  Future<bool> cancelResignRequest(String applicationId) async => false;

  Future<bool> approveResignation({
    required String applicationId,
    required String adminUID,
  }) async => false;

  Future<bool> rejectResignation({
    required String applicationId,
    String? adminUID,
    String? rejectReason,
  }) async => false;

  /// applyForTO 스텁 — applyToTO 대체 래퍼 (Phase 6에서 구현 예정)
  Future<void> applyForTO({
    required String toId,
    required String workDetailId,
    required String workType,
    required String uid,
    DateTime? desiredStartDate,
  }) async {
    debugPrint('⚠️ applyForTO: stub — Phase 6에서 applyToTO로 대체 예정');
  }

  /// 퇴사 신청 목록 조회 스텁
  Future<List<ApplicationModel>> getResignRequests(String businessId) async => [];

  // ═══════════════════════════════════════════════════════════
  // 우리 사업장 근무 이력 (복합 조회)
  // ═══════════════════════════════════════════════════════════

  /// 특정 사용자의 우리 사업장 근무 이력 조회
  Future<Map<String, dynamic>> getBusinessWorkHistory({
    required String userId,
    required String businessId,
  }) async {
    try {
      debugPrint('🔍 [getBusinessWorkHistory] 조회: userId=$userId, businessId=$businessId');
      
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
      
      debugPrint('✅ [getBusinessWorkHistory] 조회 완료: ${applications.length}회 근무');
      
      return {
        'workCount': applications.length,
        'lastWorkDate': lastApp.workDate,
        'lastWorkType': lastApp.selectedWorkType,
        'averageRating': avgRating,
        'reviews': reviews,
        'applications': applications,
      };
    } catch (e) {
      debugPrint('❌ [getBusinessWorkHistory] 실패: $e');
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