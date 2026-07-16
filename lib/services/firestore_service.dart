import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
import '../models/core/business_work_type_model.dart';
import '../models/core/attendance_model.dart';
import '../models/core/schedule_change_request_model.dart';
import '../models/core/review_model.dart';
import '../models/core/monthly_review_model.dart';
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
/// failedIds로 부분 실패 시 재처리 대상 applicationId 특정 가능
class BatchResult {
  final int success;
  final int failed;
  // 실패한 applicationId 목록 — 부분 실패 시 재처리 대상 특정에 사용
  final List<String> failedIds;

  BatchResult({
    required this.success,
    required this.failed,
    List<String>? failedIds,
  }) : failedIds = failedIds ?? [];

  int get total => success + failed;
  bool get hasFailures => failed > 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// 동시성 설계 요약 (동시성 감사 2026-06-16 기준)
// ═══════════════════════════════════════════════════════════════════════════
//
// ✅ 트랜잭션으로 보호되는 경쟁 조건:
//   A01/A05  지원자 확정 시 CONTRACT_PENDING 선점 (_confirmWithConflictCheck)
//            → 두 번째 확정 요청은 alreadyConfirmed=true로 조기 반환
//   A03      사용자 지원 취소 시 확정 상태 재확인 트랜잭션 (cancelApplication)
//            → 조회-취소 사이 관리자 확정을 원자적으로 차단 [A03-FIX]
//   A05      슬롯 마감 후 확정 시도 → CONTRACT_PENDING 롤백 처리
//   B01      급여 마감 시 wageStatus 서버 재확인 트랜잭션 (_closeWages)
//            → 동시 마감 감지 시 skip, totalWorkDays 이중 증가 방지 [B01-FIX]
//   B02      시간 수정 시 wageConfirmed/wageTransferred 상태 트랜잭션 재확인
//            → 마감된 급여를 pending으로 덮어쓰는 것 방지 [B02-FIX]
//   B05      _isProcessing 플래그로 단일 세션 중복 클릭 방어 (wage_confirm_dialog)
//   C02      사업주/근무자 동시 서명 → 각 트랜잭션에서 서명 URL 존재 여부 체크
//   C04      계약서 무효화 + 근무자 서명 race → 트랜잭션 내 voided 상태 재확인
//   C06      슬롯 추가 시 applicationId 멱등성 보호 (_addSlot 트랜잭션)
//   F01/F02  confirmedCount 동시 증감 → FieldValue.increment() 원자 연산 사용
//   노쇼 카운트 원자 갱신 → _applyNoShowPenaltyTransactional 트랜잭션
//   출근/퇴근 중복 방지 → attendanceDocId 결정적 ID + 트랜잭션 set
//
// ⚠️ 의도된 last-write-wins (실사용 충돌 빈도 낮아 허용):
//   A02      더블클릭 중복 지원 — dupQ.get과 batch.set 사이 TOCTOU
//            (UI disabled + 2중 서버 체크로 실용적 방어, Rules 레벨 방어 미구현)
//   A04      두 관리자가 동일 지원자 동시 확정 → CONTRACT_PENDING 선점으로 방어됨
//   B03/B04  급여 수정/취소 트랜잭션 없음 — 단일 관리자 흐름이 일반적, 충돌 빈도 낮음
//   C01      동시 계약서 생성 → isNewUnsaved:true로 각자 다른 doc에 set
//            중복 발생 가능하나 saveEmployerSignature 트랜잭션 전까지 저장 안 됨
//   B16      8일 소급 계산 중 동시 마감 → prevDays 오차 가능 (best effort)
//   D01      알림 중복 발송 → 호출 측 1회 보장 설계, Rules 중복 방어 없음
//   D02      읽음 처리 동시 요청 → isRead:true 덮어쓰기는 멱등하여 안전
//   E01/E02  캐시 stampede → Dart 단일 스레드로 실질 race 없음, 중복 조회는 안전
//   A16~A25  optimistic update → 낙관적 잠금 미사용, 실패 시 UI 리프레시로 복구
// ═══════════════════════════════════════════════════════════════════════════

/// CF onCall 응답의 {_seconds, _nanoseconds} 맵을 Firestore Timestamp로 재수화
/// serializeFirestoreData(CF index.ts)가 직렬화한 형식을 되돌린다.
Map<String, dynamic> _cfHydrate(Map<String, dynamic> m) {
  return m.map((k, v) {
    if (v is Map) {
      final vm = Map<String, dynamic>.from(v);
      if (vm.containsKey('_seconds')) {
        try {
          return MapEntry(k, Timestamp(
            (vm['_seconds'] as num).toInt(),
            (vm['_nanoseconds'] as num? ?? 0).toInt(),
          ));
        } catch (_) {}
      }
      return MapEntry(k, _cfHydrate(vm));
    } else if (v is List) {
      return MapEntry(k, v.map((e) =>
        e is Map ? _cfHydrate(Map<String, dynamic>.from(e)) : e
      ).toList());
    }
    return MapEntry(k, v);
  });
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

  // 확정 일정 날짜별 캐시 ("${uid}_${dateStr}" → List<ApplicationModel>)
  final Map<String, List<ApplicationModel>> _confirmedSchedulesCache = {};
  final Map<String, DateTime> _confirmedSchedulesCacheTs = {};
  static const Duration _confirmedSchedulesCacheTTL = Duration(minutes: 3);

  // 사용자 정보 캐시
  final Map<String, UserModel> _userCache = {};
  final Map<String, DateTime> _userCacheTimestamps = {};
  static const Duration _userCacheTTL = Duration(hours: 1);

  // ═══════════════════════════════════════════════════════════
  // 캐시 관리
  // ═══════════════════════════════════════════════════════════
  
  /// 캐시 초기화 (TO 수정/삭제 시 호출)
  ///
  /// [toId] 지정 시 — 의도된 no-op:
  ///   FirestoreService의 메모리 캐시는 _userCache(uid 키) 하나만 존재하며,
  ///   TO 단위 캐시는 없다. TO 수정 후 데이터는 Source.server 직접 조회이므로
  ///   캐시 무효화가 필요 없다.
  ///   화면 레벨의 workDetails/slots 캐시는 AllTOListScreen 등에서 직접 clear.
  ///   clearCache(toId:)는 "이 TO가 수정됨"을 표시하기 위한 호출 관례 유지용.
  ///
  /// [toId] null 시 — _userCache 전체 클리어 (로그아웃 등)
  void clearCache({String? toId}) {
    if (toId == null) {
      _userCache.clear();
      _userCacheTimestamps.clear();
    }
    // toId 지정 시: TO별 메모리 캐시 없음 — no-op (설계 의도, 위 주석 참고)
  }

  /// 내 지원 목록 캐시 무효화 (지원·취소·확정 후 호출)
  void invalidateMyApplicationsCache(String uid) {
    _myApplicationsCache.remove(uid);
    _myApplicationsCacheTimestamps.remove(uid);
    // 확정 일정 캐시도 같이 무효화 — 지원 상태 변경 시 날짜별 캐시 오염 방지
    _confirmedSchedulesCache.removeWhere((k, _) => k.startsWith('${uid}_'));
    _confirmedSchedulesCacheTs.removeWhere((k, _) => k.startsWith('${uid}_'));
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼 메서드들
  // ═══════════════════════════════════════════════════════════

  /// UID 목록으로 사용자 일괄 조회 (1시간 캐시, 30개씩 청크)
  /// CF callableGetUsersBatch를 통해 서버 사이드 소속 검증 후 반환
  /// — 극도 민감 필드(ci, residentNumber, foreignIdNumber, idCardImageUrl,
  ///   signatureBase64, sealBase64, bankbookImageUrl)는 CF에서 제거됨
  Future<Map<String, UserModel>> getUsersBatch(
    List<String> uids, {
    required String businessId,
  }) async {
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

    if (uncached.isEmpty) return result;

    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetUsersBatch',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));

    for (int i = 0; i < uncached.length; i += 30) {
      final chunk = uncached.skip(i).take(30).toList();
      try {
        final response = await callable.call<Map<String, dynamic>>({
          'uids': chunk,
          'businessId': businessId,
        });
        final usersRaw = (response.data['users'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final entry in usersRaw.entries) {
          final uid = entry.key;
          final data = Map<String, dynamic>.from(entry.value as Map);
          final user = UserModel.fromMap(data, uid);
          _userCache[uid] = user;
          _userCacheTimestamps[uid] = now;
          result[uid] = user;
        }
      } catch (e) {
        debugPrint('❌ getUsersBatch CF 실패 (chunk $i): $e');
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // TO 마감 관리
  // ═══════════════════════════════════════════════════════════

  /// TO 수동 마감 — CF callableCloseTOManually 위임
  // [M-2] closedBy 서버 UID 강제: CF에서 request.auth.uid 사용 → 클라이언트 위조 불가
  // [Charter] AUTO_CANCELED 법적 상태 전이: CF Admin SDK 전용으로 이전
  Future<bool> closeTOManually(String toId, String adminUID) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCloseTOManually',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)));
      await callable.call<Map<String, dynamic>>({'toId': toId});
      clearCache(toId: toId);
      debugPrint('✅ TO 수동 마감 완료 (CF): $toId');
      return true;
    } catch (e) {
      debugPrint('❌ TO 수동 마감 실패: $e');
      return false;
    }
  }

  /// TO 시간만료 자동 마감 — callableUpdateTO CF 위임 (status:CLOSED)
  /// [D-2 FIX 2026-07-15] 직접 쓰기는 isSuperAdmin() 전용 규칙에 의해 일반 관리자 PERMISSION_DENIED
  Future<void> markTOAsExpired(String toId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableUpdateTO',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      await callable.call<Map<String, dynamic>>({
        'toId': toId,
        'updates': {'status': TOStatus.closed},
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
      // [BUGFIX-WHEREIN] toId isEqualTo + status whereIn → PERMISSION_DENIED
      // confirmedStatuses 각각 병렬 isEqualTo 쿼리로 대체 (whereIn 제거)
      final confirmedResults = await Future.wait(
        AppStatus.confirmedStatuses.map((s) => _firestore
            .collection('applications')
            .where('toId', isEqualTo: toId)
            .where('status', isEqualTo: s)
            .count()
            .get()),
      );
      final confirmedCount = confirmedResults.fold<int>(0, (acc, r) => acc + (r.count ?? 0));

      final pendingResult = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('status', isEqualTo: AppStatus.pending)
          .count()
          .get();
      final pendingCount = pendingResult.count ?? 0;

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

  /// TO 재오픈 (마감 취소) — CF callableUpdateTO 위임
  /// [BUG-REOPEN-FIX 2026-07-15] 클라이언트 직접 쓰기 → CF 이전
  ///   rules에서 관리자/하위관리자 TO update 차단(callableUpdateTO CF 이전, 2026-07-14)됨에 따라
  ///   reopenTO 클라이언트 직접 쓰기는 PERMISSION_DENIED로 실패함.
  ///   callableUpdateTO가 isManualClosed:false 재오픈 로직을 서버에서 처리:
  ///   reopenedBy=callerUid·reopenedAt/closedAt/closedBy=serverTimestamp()/delete() 강제.
  Future<bool> reopenTO(String toId, String adminUID) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableUpdateTO',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      await callable.call<Map<String, dynamic>>({
        'toId': toId,
        'updates': {
          'isManualClosed': false,
          'status': TOStatus.active,
        },
      });
      clearCache(toId: toId);
      debugPrint('✅ TO 재오픈 완료 (CF): $toId');
      return true;
    } catch (e) {
      debugPrint('❌ TO 재오픈 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 통계 재계산
  // ═══════════════════════════════════════════════════════════

  /// TO 통계 재계산 — CF callableRecalculateTOStats 위임 (Admin SDK로 보안 규칙 우회)
  Future<bool> recalculateTOStats(String toId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRecalculateTOStats');
      await callable.call({'toId': toId});
      clearCache(toId: toId);
      debugPrint('✅ TO 통계 재계산 완료 (CF): $toId');
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
      // [BUGFIX] whereIn + equality 복합쿼리 시 Firestore 보안 규칙
      //   request.query.filters.businessId가 null 반환 → PERMISSION_DENIED 발생.
      //   statuses 파라미터 제거 후 클라이언트 필터링으로 전환.
      final allApps = await getApplicationsByTOId(
        to.id,
        businessId: to.businessId,
      );
      const activeStatuses = {'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'};
      final apps = slotId != null
          ? allApps.where((a) => a.slotId == slotId && activeStatuses.contains(a.status)).toList()
          : allApps.where((a) => activeStatuses.contains(a.status)).toList();
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

  /// TO 목록 조회 — callableGetAdminTOs CF를 경유하여 server-side 교차검증
  /// [RULE-FIX-CF 2026-07-13] 직접 Firestore → CF 이전 (businessId 교차검증 강화)
  /// [businessIds] null이면 슈퍼관리자 전체 조회, 빈 리스트이면 빈 결과 반환
  Future<List<TOGroupItem>> getTOGroupItemsLight({
    bool activeOnly = false,
    bool closedOnly = false,
    List<String>? businessIds,
  }) async {
    try {
      if (businessIds != null && businessIds.isEmpty) return [];

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetAdminTOs',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

      final params = <String, dynamic>{
        'activeOnly': activeOnly,
        'closedOnly': closedOnly,
      };
      if (businessIds != null) params['businessIds'] = businessIds;

      final result = await callable.call<Map<String, dynamic>>(params);
      final items = (result.data['items'] as List<dynamic>?) ?? [];

      return items.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m.remove('id') as String? ?? '';
        final hydrated = _cfHydrate(m);
        final to = TOModel.tryFromMap(hydrated, id);
        return to != null ? TOGroupItem(singleTO: to) : null;
      }).whereType<TOGroupItem>().toList()
        ..sort((a, b) => b.singleTO.createdAt.compareTo(a.singleTO.createdAt));
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
        try {
          final slot = SlotModel.fromMap(d.data(), d.id, toId);
          return TOItem(
            to: model,
            slot: slot,
            confirmedCount: slot.confirmedCount,
            pendingCount: slot.pendingCount,
            totalRequired: slot.totalRequired,
          );
        } catch (e) {
          debugPrint('⚠️ 슬롯 파싱 실패 (id=${d.id}): $e');
          return null;
        }
      }).whereType<TOItem>().toList();
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
          .map((e) => WorkDetailData.tryFromMap(Map<String, dynamic>.from(e as Map)))
          .whereType<WorkDetailData>()
          .toList();

      final idx = details.indexWhere((d) {
        final compositeId = '${d.workType}_${d.startTime}_${d.endTime}';
        return compositeId == workDetailId || d.workType == workDetailId;
      });
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
          .map((e) => WorkDetailData.tryFromMap(Map<String, dynamic>.from(e as Map)))
          .whereType<WorkDetailData>()
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

      // [D-3 FIX 2026-07-15] 직접 쓰기 → callableUpdateTO CF 이전 (isSuperAdmin 전용 규칙 우회)
      final cfUpdateTO = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableUpdateTO',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      if (allClosed && toStatus != TOStatus.closed) {
        await cfUpdateTO.call<Map<String, dynamic>>({
          'toId': toId,
          'updates': {'status': TOStatus.closed},
        });
        clearCache(toId: toId);
      } else if (!allClosed && (toStatus == TOStatus.closed || toStatus == TOStatus.expired)) {
        await cfUpdateTO.call<Map<String, dynamic>>({
          'toId': toId,
          'updates': {'status': TOStatus.active},
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

  /// 해당 지원서에 출근 기록이 1개 이상 있는지 확인 (관리자 경로)
  /// [H-CF-1] callableAdminHasAttendanceRecord CF 경유 — assertBizAdmin 서버 교차검증
  Future<bool> hasAttendanceRecord(
    String applicationId, {
    required String businessId,
  }) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAdminHasAttendanceRecord')
          .call({'applicationId': applicationId, 'businessId': businessId});
      return (result.data as Map)['hasRecord'] == true;
    } catch (e) {
      debugPrint('⚠️ hasAttendanceRecord 조회 실패 ($applicationId): $e');
      return false;
    }
  }

  /// 근무자 본인 확정 지원서 전체 목록 (장기공고 달력 충돌 체크용)
  /// [CF-MIGRATED 2026-07-15] applications list isSuperAdmin() only
  ///   → callableGetMyApplications CF 경유 (uid 서버 검증)
  Future<List<ApplicationModel>> getMyConfirmedApplicationsForConflictCheck() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyApplications',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call<Map<String, dynamic>>({
        'statuses': [AppStatus.confirmed, AppStatus.contractPending],
        'limit': 200,
      });
      return ((result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .toList());
    } catch (e) {
      debugPrint('⚠️ getMyConfirmedApplicationsForConflictCheck 실패: $e');
      return [];
    }
  }

  /// 근무자 본인 출근 기록 존재 여부 확인 (USER 경로)
  /// [CF-MIGRATED 2026-07-15] attendance list isAdminOf only — USER 직접 list 차단
  ///   → callableWorkerHasAttendanceRecord CF 경유 (applicationId 소유권 서버 검증)
  Future<bool> workerHasAttendanceRecord(String applicationId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableWorkerHasAttendanceRecord',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 10)));
      final result = await callable.call<Map<String, dynamic>>({'applicationId': applicationId});
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      return data['hasRecord'] as bool? ?? false;
    } catch (e) {
      debugPrint('⚠️ workerHasAttendanceRecord 조회 실패 ($applicationId): $e');
      return false;
    }
  }

  /// workDate가 지난 PENDING 지원서를 AUTO_CANCELED로 일괄 처리
  /// Firestore rules가 클라이언트의 AUTO_CANCELED 전환을 차단 → CF callableExpireApplications 경유
  /// [A7-FIX] uid 전달 — 전역 스캔 대신 해당 사용자의 지원서만 처리해 불필요한 Firestore 읽기 부하 차단
  Future<void> autoExpirePendingApplications(String uid) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableExpireApplications');
      await callable.call({'uid': uid});
      debugPrint('✅ 만료 PENDING 지원서 자동 취소 (CF)');
    } catch (e) {
      debugPrint('❌ 자동 만료 처리 실패: $e');
    }
  }

  /// 마이그레이션 메서드 — 완료됨, no-op
  Future<Map<String, dynamic>> migrateApplicationWorkDetailIds() async =>
      {'migrated': 0, 'skipped': 0, 'failed': 0};
  Future<int> migrateAllGroupMasterStats() async => 0;

  /// 계약해지 요청 (관리자 → 근무자) — CF callableRequestTermination 위임 (Admin SDK로 보안 규칙 우회)
  Future<bool> requestTermination({
    required String applicationId,
    String? uid,
    String? businessId,
    String? reason,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRequestTermination');
      await callable.call({
        'applicationId': applicationId,
        'businessId': businessId,
        'uid': uid,
        'reason': reason,
      });
      debugPrint('✅ 계약해지 요청 전송 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ requestTermination 실패: $e');
      return false;
    }
  }

  /// 계약해지 요청 취소 — CF callableCancelTermination 위임 (Admin SDK로 보안 규칙 우회)
  Future<bool> cancelTerminationRequest(String applicationId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCancelTermination');
      await callable.call({'applicationId': applicationId});
      debugPrint('✅ 계약해지 요청 취소 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ cancelTerminationRequest 실패: $e');
      return false;
    }
  }

  /// 계약해지 승인 (근무자 → 관리자 요청 수락)
  /// CF callableApproveTermination으로 위임 — 트랜잭션·TO 카운터·알림을 서버에서 원자적 처리
  Future<bool> approveTermination(String applicationId, {String? adminUID}) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableApproveTermination');
      await callable.call({'applicationId': applicationId});
      debugPrint('✅ 계약해지 승인 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ approveTermination 실패: $e');
      return false;
    }
  }

  /// 계약해지 거절 (근무자 → 관리자 요청 거절)
  Future<bool> rejectTermination({
    required String applicationId,
    String? rejectReason,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRejectTermination');
      await callable.call({
        'applicationId': applicationId,
        if (rejectReason != null) 'rejectReason': rejectReason,
      });
      debugPrint('✅ 계약해지 거절 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ rejectTermination 실패: $e');
      return false;
    }
  }

  /// 퇴사 요청 (근무자 → 관리자)
  Future<bool> requestResignation({
    required String applicationId,
    DateTime? resignDate,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRequestResignation');
      await callable.call({
        'applicationId': applicationId,
        if (resignDate != null) 'resignDateIso': resignDate.toIso8601String(),
      });
      debugPrint('✅ 퇴사 요청 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ requestResignation 실패: $e');
      return false;
    }
  }

  /// 퇴사 요청 취소 (근무자) — CF callableCancelResignRequest 위임
  /// cancelTerminationRequest와 대칭성 확보, rules 클라이언트 경로 제거를 위해 CF 이전
  Future<bool> cancelResignRequest(String applicationId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCancelResignRequest');
      await callable.call({'applicationId': applicationId});
      debugPrint('✅ 퇴사 요청 취소 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ cancelResignRequest 실패: $e');
      return false;
    }
  }

  /// 퇴사 승인 (관리자)
  /// CF callableApproveResignation으로 위임 — 트랜잭션·TO 카운터·scheduled attendance·알림을 서버에서 원자적 처리
  Future<bool> approveResignation({
    required String applicationId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableApproveResignation');
      await callable.call({'applicationId': applicationId});
      debugPrint('✅ 퇴사 승인 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ approveResignation 실패: $e');
      return false;
    }
  }

  /// 퇴사 거절 (관리자) — CF callableRejectResignation 위임
  /// resignRejectedBy를 서버 검증된 callerUid로 기록 — 클라이언트 adminUID 위조 차단
  Future<bool> rejectResignation({
    required String applicationId,
    String? rejectReason,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRejectResignation');
      await callable.call({
        'applicationId': applicationId,
        if (rejectReason != null) 'rejectReason': rejectReason,
      });
      debugPrint('✅ 퇴사 거절 (CF): $applicationId');
      return true;
    } catch (e) {
      debugPrint('❌ rejectResignation 실패: $e');
      return false;
    }
  }

  /// 퇴사 신청 목록 조회 (resignStatus == PENDING) — CF 경유, 보안 규칙 우회
  Future<List<ApplicationModel>> getResignRequests(String businessId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz');
      final result = await callable.call({
        'businessId': businessId,
        'resignStatus': AppStatus.pending,
        'limit': 200,
      });
      final raw = List<Map>.from(result.data['applications'] as List? ?? []);
      final apps = raw.map((e) => ApplicationModel.tryFromMap(
        Map<String, dynamic>.from(e),
        e['id'] as String? ?? '',
      )).whereType<ApplicationModel>().toList();
      // CF는 orderBy 미지원 — 클라이언트에서 resignRequestedAt 기준 정렬
      apps.sort((a, b) =>
          (b.resignRequestedAt ?? DateTime(0)).compareTo(a.resignRequestedAt ?? DateTime(0)));
      return apps;
    } catch (e) {
      debugPrint('❌ getResignRequests 실패: $e');
      return [];
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
      debugPrint('🔍 [getBusinessWorkHistory] 조회: userId=$userId, businessId=$businessId');
      
      // [CF-FIX] uid + businessId 다중 equality 쿼리 → PERMISSION_DENIED 우회
      // callableGetApplicationsByBiz (Admin SDK)로 교체
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz');
      final cfResult = await callable.call({
        'businessId': businessId,
        'uid': userId,
      });
      final rawApps = List<Map>.from(cfResult.data['applications'] as List? ?? []);

      if (rawApps.isEmpty) {
        return {
          'workCount': 0,
          'lastWorkDate': null,
          'lastWorkType': null,
          'averageRating': null,
          'reviews': <ReviewModel>[],
        };
      }

      final allFetched = rawApps.map((e) => ApplicationModel.tryFromMap(
        Map<String, dynamic>.from(e),
        e['id'] as String? ?? '',
      )).whereType<ApplicationModel>().toList();

      final applications = allFetched
          .where((a) => AppStatus.confirmedStatuses.contains(a.status))
          .toList()
          ..sort((a, b) => b.workDate.compareTo(a.workDate));

      // [RULE-FIX-CF 2026-07-13] monthly_reviews admin path → CF 이전
      // 다중 where 필터 + limitType=LIMIT_TO_FIRST → filters 평가 실패 방지
      final reviewCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMonthlyReviewsForUser',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final reviewResult = await reviewCallable.call<Map<String, dynamic>>({
        'targetUserId': userId,
        'businessId': businessId,
        'reviewType': 'ADMIN_TO_USER',
        'publishedOnly': true,
        'limit': 5,
      });
      final rawReviewItems = (reviewResult.data['items'] as List? ?? []);
      final reviews = rawReviewItems
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return MonthlyReviewModel.tryFromMap(raw, id);
          })
          .whereType<MonthlyReviewModel>()
          .toList();

      double? avgRating;
      if (reviews.isNotEmpty) {
        double total = 0;
        for (var review in reviews) {
          total += review.rating;
        }
        avgRating = total / reviews.length;
      }
      
      if (applications.isEmpty) {
        return {
          'workCount': 0,
          'lastWorkDate': null,
          'lastWorkType': null,
          'averageRating': avgRating,
          'reviews': reviews,
        };
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