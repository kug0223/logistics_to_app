// lib/services/support_review_queue_service.dart
// Support Review Queue — 전체 기간 PENDING 지원서 로드 서비스
//
// 기존 PendingApprovalCalendarDialog는 월별 조회만 지원.
// 이 서비스는 날짜 제한 없이 전체 PENDING을 로드한다.
//
// [CR-01 FIX] Firestore direct list → callableGetPendingApplicationsForReview CF 전환
//   - Firestore Rules: non-SUPER_ADMIN list deny → PERMISSION_DENIED 가 catch→[] 로 흡수되어
//     ERROR가 EMPTY로 보이는 버그(CR-01) 수정.
//   - catch→[] 제거: 실패는 caller까지 throw, UI가 ERROR 상태로 처리.
//   - per-business 실패 시 전체 load ERROR — silent partial list 금지.

import 'package:cloud_firestore/cloud_firestore.dart'; // Timestamp (cfHydrate)
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/application_model.dart';
import '../models/core/user_model.dart';
import 'firestore_service.dart';

/// CF serializeFirestoreData({_seconds, _nanoseconds}) → Firestore Timestamp 재수화.
/// firestore_service.dart의 동명 private 함수와 동일 로직 — CF parse 표준 패턴.
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

class SupportReviewQueueService {
  SupportReviewQueueService._();
  static final SupportReviewQueueService instance = SupportReviewQueueService._();

  final _svc = FirestoreService();

  // ─── 전체 기간 PENDING 로드 ──────────────────────────────────────────────

  /// 관리 사업장 전체의 PENDING 지원서를 workDate 오름차순으로 반환.
  ///
  /// [CR-01 FIX] callableGetPendingApplicationsForReview CF 경유.
  /// per-business 실패 시 Future.wait가 throw — caller까지 ERROR 전파 (partial list 금지).
  Future<List<ApplicationModel>> loadPendingApplications(
    List<String> businessIds,
  ) async {
    if (businessIds.isEmpty) return [];

    final results = await Future.wait(
      businessIds.map(_fetchPerBusiness),
    );

    final all = results.expand((e) => e).toList();
    // workDate 기준 오름차순 (기한 지남 → 오늘 → 예정 순서)
    all.sort((a, b) => a.workDate.compareTo(b.workDate));
    return all;
  }

  /// [CR-01 FIX] Firestore direct query 제거 → callableGetPendingApplicationsForReview.
  /// catch→[] 없음 — 실패는 rethrow되어 loadPendingApplications → caller까지 전파.
  Future<List<ApplicationModel>> _fetchPerBusiness(String bizId) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable(
          'callableGetPendingApplicationsForReview',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        );
    final result = await callable.call<Map<String, dynamic>>({'businessId': bizId});

    final raw = (result.data['applications'] as List? ?? []).whereType<Map>().toList();
    return raw.map((e) {
      final hydrated = _cfHydrate(Map<String, dynamic>.from(e));
      final id = hydrated.remove('id') as String? ?? '';
      final app = ApplicationModel.tryFromMap(hydrated, id);
      if (app == null) return null;
      // [Section 6] business binding defense — server가 이미 filter했지만 client 2차 확인
      if (app.businessId != bizId) {
        debugPrint('[SupportReviewQueue] businessId mismatch (skip): expected=$bizId got=${app.businessId}');
        return null;
      }
      return app;
    }).whereType<ApplicationModel>().toList();
  }

  // ─── 사용자 정보 배치 로드 ────────────────────────────────────────────────

  /// 지원서 목록에서 uid를 수집해 UserModel을 배치 로드한다.
  ///
  /// [primaryBizId]: getUsersBatch에 전달할 사업장 컨텍스트 (첫 번째 사업장).
  Future<Map<String, UserModel>> loadUsers(
    List<ApplicationModel> apps,
    String primaryBizId,
  ) async {
    final uids = apps.map((a) => a.uid).toSet().toList();
    if (uids.isEmpty) return {};
    try {
      return await _svc.getUsersBatch(uids, businessId: primaryBizId);
    } catch (e) {
      debugPrint('[SupportReviewQueue] 사용자 배치 로드 실패: $e');
      return {};
    }
  }
}
