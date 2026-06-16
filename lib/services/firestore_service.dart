import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/format_helper.dart';
import '../models/core/user_model.dart';
import '../models/core/to_model.dart';
import '../models/core/slot_model.dart';
import '../models/core/work_detail_data.dart';
import '../models/core/application_model.dart';
import '../models/ui/admin_to_list_ui_models.dart';
import '../models/core/business_model.dart';
import '../models/core/work_type_model.dart';
import '../utils/toast_helper.dart';
import '../utils/attendance_status_helper.dart';
import '../models/core/business_work_type_model.dart';
import '../models/core/attendance_model.dart';
import '../models/core/schedule_change_request_model.dart';
import '../models/core/review_model.dart';
import '../models/core/id_card_access_request_model.dart';
import '../models/core/notification_model.dart';
import '../models/core/worker_location_model.dart';
import '../models/core/to_filter_state.dart';
import '../utils/week_helper.dart';
import '../utils/wage_calculator.dart';
import '../utils/network_checker.dart';

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
part 'firestore/worker_location_firestore.dart';

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

  // 내 전체 지원 목록 캐시 (uid → List<ApplicationModel>)
  final Map<String, List<ApplicationModel>> _myApplicationsCache = {};
  final Map<String, DateTime> _myApplicationsCacheTimestamps = {};
  static const Duration _myApplicationsCacheTTL = Duration(minutes: 1);

  // 사용자 정보 캐시
  final Map<String, UserModel> _userCache = {};
  final Map<String, DateTime> _userCacheTimestamps = {};
  static const Duration _userCacheTTL = Duration(hours: 1);

  // ═══════════════════════════════════════════════════════════
  // 캐시 관리
  // ═══════════════════════════════════════════════════════════
  
  /// 캐시 초기화 (TO 수정/삭제 시 호출)
  void clearCache({String? toId}) {
    // toId 기준 캐시는 application_firestore.dart에서 직접 관리
    if (toId == null) {
      _userCache.clear();
      _userCacheTimestamps.clear();
    }
  }

  /// 내 지원 목록 캐시 무효화 (지원·취소·확정 후 호출)
  void invalidateMyApplicationsCache(String uid) {
    _myApplicationsCache.remove(uid);
    _myApplicationsCacheTimestamps.remove(uid);
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼 메서드들
  // ═══════════════════════════════════════════════════════════

  /// UID 목록으로 사용자 일괄 조회 (1시간 캐시, 30개씩 청크)
  Future<Map<String, UserModel>> getUsersBatch(List<String> uids) async {
    if (uids.isEmpty) return {};

    final result = <String, UserModel>{};
    final uncached = <String>[];
    final now = DateTime.now();

    for (final uid in uids.toSet()) {
      final cached = _userCache[uid];
      final ts = _userCacheTimestamps[uid];
      if (cached != null && ts != null && now.difference(ts) < _userCacheTTL) {
        result[uid] = cached;
      } else {
        uncached.add(uid);
      }
    }

    for (int i = 0; i < uncached.length; i += 30) {
      final chunk = uncached.skip(i).take(30).toList();
      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .limit(chunk.length) // 보안규칙 request.query.limit <= 30 충족
          .get(const GetOptions(source: Source.server));
      for (final doc in snap.docs) {
        final user = UserModel.fromMap(doc.data(), doc.id);
        _userCache[doc.id] = user;
        _userCacheTimestamps[doc.id] = now;
        result[doc.id] = user;
      }
    }

    return result;
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
        'status': TOStatus.closed,
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

  /// TO 시간만료 자동 마감 (isManualClosed: false — 재오픈 버튼 미표시)
  Future<void> markTOAsExpired(String toId) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'status': TOStatus.closed,
        'isManualClosed': false,
        'closedAt': FieldValue.serverTimestamp(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'closedBy': FieldValue.delete(),
      });
      clearCache(toId: toId);
    } catch (e) {
      debugPrint('❌ markTOAsExpired 실패 ($toId): $e');
    }
  }

  /// TO 통계 재계산 (슈퍼어드민 전용)
  ///
  /// Firestore 콘솔 직접 수정이나 과거 race condition으로 드리프트된 경우
  /// totalConfirmed / totalPending 을 실제 지원서 수 기준으로 재동기화.
  Future<void> reconcileTOStats(String toId) async {
    try {
      // 실제 CONFIRMED/PENDING 지원서 수 집계
      final confirmedSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .get(const GetOptions(source: Source.server));
      final pendingSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('status', isEqualTo: AppStatus.pending)
          .get(const GetOptions(source: Source.server));

      final confirmedCount = confirmedSnap.docs.length;
      final pendingCount = pendingSnap.docs.length;

      await _firestore.collection('tos').doc(toId).update({
        'totalConfirmed': confirmedCount,
        'totalPending': pendingCount,
      });
      clearCache(toId: toId);
      debugPrint('✅ TO 통계 재계산 완료: confirmed=$confirmedCount pending=$pendingCount ($toId)');
    } catch (e) {
      debugPrint('❌ TO 통계 재계산 실패: $e');
    }
  }

  /// TO 재오픈 (마감 취소)
  Future<bool> reopenTO(String toId, String adminUID) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'isManualClosed': false,
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
        'status': TOStatus.active,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'closedBy': FieldValue.delete(), // 재오픈 시 직접마감 표시 초기화
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
          .get(const GetOptions(source: Source.server));

      int totalPending = 0;
      int totalConfirmed = 0;
      for (final doc in appsSnap.docs) {
        final status = doc.data()['status'] as String?;
        if (status == AppStatus.pending) totalPending++;
        // CONTRACT_PENDING도 확정 인원으로 집계
        if (AppStatus.confirmedStatuses.contains(status)) totalConfirmed++;
      }

      // totalRequired 초과 확정 시 TO status → full, 미만이면 active 복구
      final toUpdate = <String, dynamic>{
        'totalPending': totalPending,
        'totalConfirmed': totalConfirmed,
      };
      final notClosed = to.status != TOStatus.closed &&
          to.status != TOStatus.expired;
      if (notClosed) {
        final shouldBeFull = to.totalRequired > 0 && totalConfirmed >= to.totalRequired;
        toUpdate['status'] = shouldBeFull ? TOStatus.full : TOStatus.active;
      }

      await _firestore.collection('tos').doc(toId).update(toUpdate);

      // flex TO: 슬롯별 통계도 재계산
      if (to.isFlexType) {
        // slotId별 집계
        final Map<String, Map<String, int>> slotStats = {};
        for (final doc in appsSnap.docs) {
          final data = doc.data();
          final status = data['status'] as String?;
          final sid = data['slotId'] as String?;
          if (sid == null || !AppStatus.activeStates.contains(status)) continue;
          slotStats[sid] ??= {'pending': 0, 'confirmed': 0};
          if (status == AppStatus.pending) slotStats[sid]!['pending'] = slotStats[sid]!['pending']! + 1;
          if (AppStatus.confirmedStatuses.contains(status)) slotStats[sid]!['confirmed'] = slotStats[sid]!['confirmed']! + 1;
        }

        // 슬롯 전체 조회 후 일괄 업데이트
        final slotsSnap = await _firestore
            .collection('tos').doc(toId)
            .collection('slots').get(const GetOptions(source: Source.server));
        if (slotsSnap.docs.isNotEmpty) {
          var batch = _firestore.batch();
          int batchCount = 0;
          for (final slotDoc in slotsSnap.docs) {
            final stats = slotStats[slotDoc.id] ?? {'pending': 0, 'confirmed': 0};
            batch.update(slotDoc.reference, {
              'pendingCount': stats['pending'],
              'confirmedCount': stats['confirmed'],
            });
            batchCount++;
            if (batchCount >= 499) {
              await batch.commit();
              batch = _firestore.batch();
              batchCount = 0;
            }
          }
          if (batchCount > 0) await batch.commit();
        }
      }

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
  /// [slotId] 전달 시 해당 슬롯(날짜) 지원서만 집계 (flex 타입 날짜별 정확한 수치)
  /// [slotWorkDetails] 전달 시 마스터 TO workDetails 대신 슬롯 문서의 workDetails 사용
  Future<Map<String, dynamic>> loadTOWorkDetails(
    TOModel to, {
    String? slotId,
    List<WorkDetailData>? slotWorkDetails,
  }) async {
    // 슬롯 자체 workDetails 우선 (Firestore 컬렉션 쿼리 캐시 stale 방지)
    final workDetails = (slotWorkDetails != null && slotWorkDetails.isNotEmpty)
        ? slotWorkDetails
        : to.workDetails;
    final Map<String, Map<String, int>> workStats = {
      for (final w in workDetails) w.id: {'confirmed': 0, 'pending': 0},
    };
    try {
      // slotId 쿼리는 보안 규칙 제한 — toId 전체를 가져와 클라이언트에서 필터
      final allApps = await getApplicationsByTOId(
        to.id,
        businessId: to.businessId,
        statuses: const ['PENDING', 'CONFIRMED', 'CONTRACT_PENDING'],
      );
      final apps = slotId != null
          ? allApps.where((a) => a.slotId == slotId).toList()
          : allApps;
      for (final app in apps) {
        // workDetailId가 compositeId 형식(workType과 다름)이면 그대로 사용,
        // 아니면 시간 정보로 composite key 생성 (레거시 데이터 호환)
        final wdId = app.workDetailId;
        final key = (wdId != null && wdId.isNotEmpty && wdId != app.selectedWorkType)
            ? wdId
            : '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
        workStats[key] ??= {'confirmed': 0, 'pending': 0};
        if (AppStatus.confirmedStatuses.contains(app.status)) {
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

      // businessIds > 30 이면 청크 분할 (Firestore whereIn 30개 제한)
      if (businessIds != null && businessIds.length > 30) {
        final allItems = <TOGroupItem>[];
        for (int i = 0; i < businessIds.length; i += 30) {
          final chunk = businessIds.skip(i).take(30).toList();
          Query chunkQuery = _firestore.collection('tos').orderBy('createdAt', descending: true)
              .where('businessId', whereIn: chunk);
          if (activeOnly) {
            chunkQuery = chunkQuery.where('status', whereIn: TOStatus.openStates);
          } else if (closedOnly) {
            chunkQuery = chunkQuery.where('status', whereIn: TOStatus.closedStates);
          }
          final chunkSnap = await chunkQuery.get(const GetOptions(source: Source.server));
          allItems.addAll(chunkSnap.docs.map(
            (d) => TOGroupItem(singleTO: TOModel.fromMap(d.data() as Map<String, dynamic>, d.id))));
        }
        allItems.sort((a, b) => b.singleTO.createdAt.compareTo(a.singleTO.createdAt));
        return allItems;
      }

      Query query = _firestore.collection('tos').orderBy('createdAt', descending: true);
      if (businessIds != null && businessIds.length == 1) {
        query = query.where('businessId', isEqualTo: businessIds.first);
      } else if (businessIds != null && businessIds.length > 1) {
        query = query.where('businessId', whereIn: businessIds.toList());
      }
      if (activeOnly) {
        query = query.where('status', whereIn: TOStatus.openStates);
      } else if (closedOnly) {
        query = query.where('status', whereIn: TOStatus.closedStates);
      }
      final snap = await query.get(const GetOptions(source: Source.server));
      return snap.docs
          .map((d) => TOGroupItem(singleTO: TOModel.fromMap(d.data() as Map<String, dynamic>, d.id)))
          .toList();
    } catch (e) {
      debugPrint('❌ getTOGroupItemsLight 실패: $e');
      return [];
    }
  }

  /// flex TO의 슬롯을 날짜순으로 로드하여 TOItem 목록 반환
  /// [masterTO] 전달 시 TO 문서 재조회 생략
  Future<List<TOItem>> loadGroupTOsLight(String toId, {TOModel? masterTO}) async {
    try {
      final snap = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('slots')
          .orderBy('date')
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) return [];

      final model = masterTO ?? await getTO(toId);
      if (model == null) return [];

      return snap.docs.map((d) {
        final slot = SlotModel.fromMap(d.data(), d.id, toId);
        return TOItem(
          to: model,
          slot: slot,
          confirmedCount: slot.confirmedCount,
          pendingCount: slot.pendingCount,
          totalRequired: slot.totalRequired,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ loadGroupTOsLight 실패: $e');
      return [];
    }
  }

  /// flex TO 목록의 슬롯 날짜를 일괄 조회 (캘린더 필터용)
  /// Returns: { toId: [slotDate, ...] }
  Future<Map<String, List<DateTime>>> getFlexTOSlotDates(List<String> toIds) async {
    if (toIds.isEmpty) return {};
    try {
      final futures = toIds.map((toId) async {
        final snap = await _firestore
            .collection('tos')
            .doc(toId)
            .collection('slots')
            .get();
        final dates = snap.docs
            .map((d) => (d.data()['date'] as Timestamp?)?.toDate().toLocal())
            .whereType<DateTime>()
            .toList();
        return MapEntry(toId, dates);
      });
      final entries = await Future.wait(futures);
      return Map.fromEntries(entries.where((e) => e.value.isNotEmpty));
    } catch (e) {
      debugPrint('❌ getFlexTOSlotDates 실패: $e');
      return {};
    }
  }

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
  /// uid 전달 시 Firestore 쿼리에 직접 포함 (보안 규칙 `uid == auth.uid` 필터 충족)
  Future<List<ApplicationModel>> getApplicationsForTO({
    required String toId,
    String? uid,
  }) async {
    return getApplicationsByTOId(toId, uid: uid);
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
      workDetailId: workDetailId,
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

  /// workDetails 배열에서 특정 업무를 수정하는 공통 헬퍼
  /// workDetails 배열 수정 후 업데이트된 목록 반환 (실패 시 null)
  Future<List<WorkDetailData>?> _updateWorkDetailInArray({
    required String toId,
    String? slotId,
    required String workDetailId,
    required WorkDetailData Function(WorkDetailData d) updater,
  }) async {
    try {
      final docRef = slotId != null
          ? _firestore.collection('tos').doc(toId).collection('slots').doc(slotId)
          : _firestore.collection('tos').doc(toId);

      final snap = await docRef.get(const GetOptions(source: Source.server));
      if (!snap.exists) return null;

      final raw = (snap.data() as Map<String, dynamic>)['workDetails'] as List? ?? [];
      final details = raw
          .map((e) => WorkDetailData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      final idx = details.indexWhere((d) => d.workType == workDetailId);
      if (idx == -1) return null;

      details[idx] = updater(details[idx]);
      await docRef.update({'workDetails': WorkDetailData.listToFirestore(details)});
      clearCache(toId: toId);
      return details;
    } catch (e) {
      debugPrint('❌ [WorkDetail] 배열 수정 실패: $e');
      return null;
    }
  }

  Future<bool> closeWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
    String? slotId,
  }) async {
    final updated = await _updateWorkDetailInArray(
      toId: toId,
      slotId: slotId,
      workDetailId: workDetailId,
      updater: (d) => d.copyWith(
        isManualClosed: true,
        closedAt: DateTime.now(),
        closedBy: adminUID,
      ),
    );
    if (updated == null) return false;

    if (slotId != null) {
      await _syncSlotCascadeStatus(toId, slotId);
      await _syncTOCascadeStatus(toId);
    }
    return true;
  }

  Future<bool> reopenWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
    String? slotId,
  }) async {
    final updated = await _updateWorkDetailInArray(
      toId: toId,
      slotId: slotId,
      workDetailId: workDetailId,
      updater: (d) => d.copyWith(clearClosedAt: true),
    );
    if (updated == null) return false;

    if (slotId != null) {
      await _syncSlotCascadeStatus(toId, slotId);
      await _syncTOCascadeStatus(toId);
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════
  // Cascade 상태 동기화 (단일 진입점)
  //
  // 마감 이유 구분 기준 — closedBy 필드:
  //   있음(adminUID) → 관리자 직접 마감 → cascade 재오픈 불가
  //   없음            → cascade/시간만료 → cascade 재오픈 가능
  //
  // 호출 규칙:
  //   workDetail 변경 → _syncSlotCascadeStatus → _syncTOCascadeStatus
  //   slot 배치 변경  → _syncTOCascadeStatus 만
  // ═══════════════════════════════════════════════════════════

  /// 슬롯의 cascade 상태를 workDetail 기반으로 평가
  ///
  /// - 직접 마감된 슬롯(closedBy 있음) · 날짜 경과 슬롯은 건드리지 않음
  /// - 모든 workDetail 닫힘 → cascade 마감 (closedBy 없음)
  /// - workDetail 하나라도 열림 + 슬롯이 cascade 마감 상태 → cascade 재오픈
  Future<void> _syncSlotCascadeStatus(String toId, String slotId) async {
    try {
      final slotRef = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);
      final slotSnap = await slotRef.get(const GetOptions(source: Source.server));
      if (!slotSnap.exists) return;
      final slotData = slotSnap.data()!;

      // 직접 마감된 슬롯 — cascade 평가 대상 아님
      if (slotData['closedBy'] != null) return;

      // 날짜 경과 슬롯 — 상태 변경 불필요 (TO 레벨에서 날짜 기반으로 처리)
      // toDate()는 UTC 기준 DateTime → toLocal()로 KST 변환 후 비교
      final dateTs = slotData['date'] as Timestamp?;
      if (dateTs != null) {
        final sd = dateTs.toDate().toLocal();
        final now = DateTime.now();
        if (DateTime(sd.year, sd.month, sd.day)
            .isBefore(DateTime(now.year, now.month, now.day))) { return; }
      }

      final rawList = slotData['workDetails'] as List? ?? [];
      if (rawList.isEmpty) return;
      final workDetails = rawList
          .map((e) => WorkDetailData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      final allClosed = workDetails.every((d) => d.isClosed || d.isTimeExpired);
      final currentStatus = slotData['status'] as String? ?? SlotStatus.open;
      // cascade 재오픈 가능 조건: 슬롯이 닫혀 있고 관리자 직접마감(closedBy)이 없음
      // isManualClosed 체크 제거 — CF 자동만료 슬롯(isManualClosed 미설정)도 포함
      final isCascadeClosed =
          currentStatus == SlotStatus.closed && slotData['closedBy'] == null;

      if (allClosed && currentStatus != SlotStatus.closed) {
        await slotRef.update({
          'status': SlotStatus.closed,
          'isManualClosed': false,
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': FieldValue.delete(),
        });
      } else if (!allClosed && isCascadeClosed) {
        await slotRef.update({
          'status': SlotStatus.open,
          'isManualClosed': false,
          'reopenedAt': FieldValue.serverTimestamp(),
          'closedAt': FieldValue.delete(),
        });
      }
    } catch (e) {
      debugPrint('❌ [Slot] cascade 상태 동기화 실패: $e');
    }
  }

  /// TO의 cascade 상태를 슬롯 기반으로 평가
  ///
  /// - 직접 마감된 TO(closedBy 있음)는 건드리지 않음
  /// - 모든 슬롯 실질적으로 닫힘 → cascade 마감 (closedBy 없음)
  /// - 열린 슬롯 있음 + TO가 cascade 마감 상태 → cascade 재오픈
  Future<void> _syncTOCascadeStatus(String toId) async {
    try {
      final toRef = _firestore.collection('tos').doc(toId);
      final toSnap = await toRef.get(const GetOptions(source: Source.server));
      if (!toSnap.exists) return;
      final toData = toSnap.data()!;

      // 직접 마감된 TO — cascade 평가 대상 아님
      if (toData['closedBy'] != null) return;

      final slotsSnap = await _firestore
          .collection('tos').doc(toId).collection('slots')
          .get(const GetOptions(source: Source.server));
      if (slotsSnap.docs.isEmpty) return;

      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);

      final allClosed = slotsSnap.docs.every((d) {
        final data = d.data();
        if (data['isManualClosed'] == true) return true;
        final status = data['status'] as String? ?? '';
        if (status == SlotStatus.closed || status == SlotStatus.full) return true;
        final dateTs = data['date'] as Timestamp?;
        if (dateTs != null) {
          final sd = dateTs.toDate().toLocal();
          if (DateTime(sd.year, sd.month, sd.day).isBefore(todayMidnight)) return true;
        }
        return false;
      });

      final toStatus = toData['status'] as String? ?? '';

      if (allClosed && toStatus != TOStatus.closed) {
        await toRef.update({
          'status': TOStatus.closed,
          'isManualClosed': false,
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': FieldValue.delete(),
        });
        clearCache(toId: toId);
      } else if (!allClosed && (toStatus == TOStatus.closed || toStatus == TOStatus.expired)) {
        await toRef.update({
          'status': TOStatus.active,
          'isManualClosed': false,
          'reopenedAt': FieldValue.serverTimestamp(),
        });
        clearCache(toId: toId);
      }
    } catch (e) {
      debugPrint('❌ [TO] cascade 상태 동기화 실패: $e');
    }
  }

  Future<bool> stopEmergencyRecruitment({
    required String toId,
    required String workDetailId,
    String? adminUID,
    String? slotId,
  }) async {
    final result = await _updateWorkDetailInArray(
      toId: toId,
      slotId: slotId,
      workDetailId: workDetailId,
      updater: (d) => d.copyWith(clearEmergency: true),
    );
    return result != null;
  }

  /// 해당 지원서에 출근 기록이 1개 이상 있는지 확인
  Future<bool> hasAttendanceRecord(String applicationId) async {
    try {
      final snap = await _firestore
          .collection('attendance')
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ hasAttendanceRecord 조회 실패 ($applicationId): $e');
      return false;
    }
  }

  /// workDate가 지난 PENDING 지원서를 AUTO_CANCELED로 일괄 처리
  Future<void> autoExpirePendingApplications(String uid) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);

      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: AppStatus.pending)
          .where('workDate', isLessThan: Timestamp.fromDate(todayStart))
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'status': AppStatus.autoCanceled,
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'AUTO_EXPIRED',
        });
      }
      await batch.commit();
      debugPrint('✅ 만료 PENDING 지원서 ${snapshot.docs.length}개 자동 취소');
    } catch (e) {
      debugPrint('❌ 자동 만료 처리 실패: $e');
    }
  }

  /// 마이그레이션 메서드 — 완료됨, no-op
  Future<Map<String, dynamic>> migrateApplicationWorkDetailIds() async =>
      {'migrated': 0, 'skipped': 0, 'failed': 0};
  Future<int> migrateAllGroupMasterStats() async => 0;

  /// 계약해지 요청 (관리자 → 근무자)
  Future<bool> requestTermination({
    required String applicationId,
    String? toId,
    String? uid,
    String? businessId,
    String? reason,
    String? requestedByUid,
  }) async {
    try {
      final appDoc = await _firestore.collection('applications').doc(applicationId).get(const GetOptions(source: Source.server));
      if (!appDoc.exists) return false;
      final app = ApplicationModel.fromMap(appDoc.data()!, appDoc.id);

      final workerUid = uid ?? app.uid;
      final bId = businessId ?? app.businessId;
      final terminationDate = app.workEndDate ?? DateTime.now().add(const Duration(days: 30));

      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': AppStatus.pending,
        'terminationRequestedAt': FieldValue.serverTimestamp(),
        'terminationReason': reason,
        'terminationRequestedByUid': requestedByUid,
        'terminationEffectiveDate': Timestamp.fromDate(terminationDate),
      });

      String businessName = '';
      if (bId.isNotEmpty) {
        final bizDoc = await _firestore.collection('businesses').doc(bId).get(const GetOptions(source: Source.server));
        businessName = bizDoc.data()?['name'] as String? ?? '';
      }

      if (workerUid.isNotEmpty) {
        final notification = NotificationModel.createTerminationRequested(
          userId: workerUid,
          businessName: businessName,
          businessId: bId,
          terminationDate: terminationDate,
          applicationId: applicationId,
          reason: reason,
        );
        await createNotification(notification);
      }

      debugPrint('✅ 계약해지 요청 전송: $applicationId → $workerUid');
      return true;
    } catch (e) {
      debugPrint('❌ requestTermination 실패: $e');
      return false;
    }
  }

  /// 계약해지 요청 취소
  Future<bool> cancelTerminationRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': null,
        'terminationRequestedAt': null,
        'terminationReason': null,
        'terminationRequestedByUid': null,
        'terminationEffectiveDate': null,
      });
      debugPrint('✅ 계약해지 요청 취소: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ cancelTerminationRequest 실패: $e');
      return false;
    }
  }

  /// 계약해지 승인 (근무자 → 관리자 요청 수락)
  Future<bool> approveTermination(String applicationId, {String? adminUID}) async {
    try {
      final appDoc = await _firestore.collection('applications').doc(applicationId).get(const GetOptions(source: Source.server));
      if (!appDoc.exists) return false;
      final app = ApplicationModel.fromMap(appDoc.data()!, appDoc.id);

      final effectiveDate = app.terminationEffectiveDate ?? DateTime.now();

      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': AppStatus.approved,
        'terminationRespondedAt': FieldValue.serverTimestamp(),
        'actualResignDate': Timestamp.fromDate(effectiveDate),
        'status': AppStatus.canceled,
      });

      final requestedByUid = adminUID ?? app.terminationRequestedByUid;
      if (requestedByUid != null && requestedByUid.isNotEmpty) {
        final notification = NotificationModel.createTerminationApproved(
          userId: requestedByUid,
          businessName: app.businessName,
          businessId: app.businessId,
          applicationId: applicationId,
          actualResignDate: effectiveDate,
        );
        await createNotification(notification);
      }

      debugPrint('✅ 계약해지 승인: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ approveTermination 실패: $e');
      return false;
    }
  }

  /// 계약해지 거절 (근무자 → 관리자 요청 거절)
  Future<bool> rejectTermination({
    required String applicationId,
    String? adminUID,
    String? rejectReason,
  }) async {
    try {
      final appDoc = await _firestore.collection('applications').doc(applicationId)
          .get(const GetOptions(source: Source.server));
      if (!appDoc.exists) return false;
      final appData = appDoc.data()!;

      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': AppStatus.rejected,
        'terminationRespondedAt': FieldValue.serverTimestamp(),
        'terminationRejectReason': rejectReason,
      });

      // 계약해지 거절 알림 — 지원자에게 발송 (BUG-04 수정)
      final workerUid = appData['uid'] as String?;
      if (workerUid != null) {
        await createNotification(NotificationModel.createResignRejected(
          userId: workerUid,
          businessName: appData['businessName'] as String? ?? '',
          businessId: appData['businessId'] as String? ?? '',
          applicationId: applicationId,
          rejectReason: rejectReason,
        ));
      }

      debugPrint('✅ 계약해지 거절: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ rejectTermination 실패: $e');
      return false;
    }
  }

  /// 퇴사 요청 (근무자 → 관리자)
  Future<bool> requestResignation({
    required String applicationId,
    String? toId,
    String? uid,
    String? reason,
    DateTime? resignDate,
  }) async {
    try {
      final appDoc = await _firestore.collection('applications').doc(applicationId).get(const GetOptions(source: Source.server));
      if (!appDoc.exists) return false;
      final app = ApplicationModel.fromMap(appDoc.data()!, appDoc.id);

      final effectiveResignDate = resignDate ?? app.workEndDate ?? DateTime.now();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': AppStatus.pending,
        'resignRequestedAt': FieldValue.serverTimestamp(),
        'resignRequestDate': Timestamp.fromDate(effectiveResignDate),
      });

      // 관리자에게 알림
      final bizDoc = await _firestore.collection('businesses').doc(app.businessId).get(const GetOptions(source: Source.server));
      final ownerId = bizDoc.data()?['ownerId'] as String?;
      final workerName = uid != null
          ? (await getUser(uid))?.name ?? '근무자'
          : '근무자';

      if (ownerId != null && ownerId.isNotEmpty) {
        final notification = NotificationModel.createResignRequested(
          userId: ownerId,
          workerName: workerName,
          businessName: app.businessName,
          resignDate: effectiveResignDate,
          applicationId: applicationId,
        );
        await createNotification(notification);
      }

      debugPrint('✅ 퇴사 요청 전송: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ requestResignation 실패: $e');
      return false;
    }
  }

  /// 퇴사 요청 취소 (근무자)
  Future<bool> cancelResignRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': null,
        'resignRequestedAt': null,
        'resignRequestDate': null,
      });
      debugPrint('✅ 퇴사 요청 취소: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ cancelResignRequest 실패: $e');
      return false;
    }
  }

  /// 퇴사 승인 (관리자)
  Future<bool> approveResignation({
    required String applicationId,
    required String adminUID,
  }) async {
    try {
      final appDoc = await _firestore.collection('applications').doc(applicationId).get(const GetOptions(source: Source.server));
      if (!appDoc.exists) return false;
      final app = ApplicationModel.fromMap(appDoc.data()!, appDoc.id);

      final actualResignDate = app.resignRequestDate ?? DateTime.now();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': AppStatus.approved,
        'resignApprovedAt': FieldValue.serverTimestamp(),
        'resignApprovedBy': adminUID,
        'actualResignDate': Timestamp.fromDate(actualResignDate),
        'status': AppStatus.canceled,
      });

      // 탈퇴일 이후 scheduled 출근기록 → absent 처리 (orphan 방지)
      final scheduledAttendances = await _firestore
          .collection('attendance')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'scheduled')
          .get(const GetOptions(source: Source.server));
      if (scheduledAttendances.docs.isNotEmpty) {
        final cancelBatch = _firestore.batch();
        for (final doc in scheduledAttendances.docs) {
          final workDate = (doc.data()['workDate'] as Timestamp?)?.toDate();
          if (workDate != null && !workDate.isBefore(actualResignDate)) {
            cancelBatch.update(doc.reference, {
              'status': AttendanceModel.statusAbsent,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        await cancelBatch.commit();
      }

      // 근무자에게 알림
      if (app.uid.isNotEmpty) {
        final notification = NotificationModel.createResignApproved(
          userId: app.uid,
          businessName: app.businessName,
          businessId: app.businessId,
          actualResignDate: actualResignDate,
          applicationId: applicationId,
        );
        await createNotification(notification);
      }

      debugPrint('✅ 퇴사 승인: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ approveResignation 실패: $e');
      return false;
    }
  }

  /// 퇴사 거절 (관리자)
  Future<bool> rejectResignation({
    required String applicationId,
    String? adminUID,
    String? rejectReason,
  }) async {
    try {
      final appDoc = await _firestore.collection('applications').doc(applicationId).get(const GetOptions(source: Source.server));
      if (!appDoc.exists) return false;
      final app = ApplicationModel.fromMap(appDoc.data()!, appDoc.id);

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': AppStatus.rejected,
        'resignApprovedAt': FieldValue.serverTimestamp(),
        'resignApprovedBy': adminUID,
        'resignRejectReason': rejectReason,
      });

      // 근무자에게 알림
      if (app.uid.isNotEmpty) {
        final notification = NotificationModel.createResignRejected(
          userId: app.uid,
          businessName: app.businessName,
          businessId: app.businessId,
          applicationId: applicationId,
          rejectReason: rejectReason,
        );
        await createNotification(notification);
      }

      debugPrint('✅ 퇴사 거절: $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ rejectResignation 실패: $e');
      return false;
    }
  }

  /// 퇴사 신청 목록 조회 (resignStatus == PENDING)
  Future<List<ApplicationModel>> getResignRequests(String businessId) async {
    final snap = await _firestore
        .collection('applications')
        .where('businessId', isEqualTo: businessId)
        .where('resignStatus', isEqualTo: AppStatus.pending)
        .orderBy('resignRequestedAt', descending: true)
        .limit(200)
        .get(const GetOptions(source: Source.server));
    return snap.docs.map((d) => ApplicationModel.fromFirestore(d)).toList();
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
      debugPrint('🔍 [getBusinessWorkHistory] 조회: userId=$userId, businessId=$businessId');
      
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: userId)
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .orderBy('workDate', descending: true)
          .get(const GetOptions(source: Source.server));
      
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
          .get(const GetOptions(source: Source.server));
      
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