// lib/services/unclosed_action_queue_service.dart
// Unclosed Action Queue — callableGetUnclosedActionQueue 클라이언트 서비스
//
// canonical unit: business × workDate (1건 = 한 사업장의 한 근무일)
// CF가 server-side scope(managedBusinessIds / subAdminBusinessIds) + canManageWage
// 를 직접 결정하므로 client는 businessIds를 전달하지 않는다.
//
// available == false 시 rows 신뢰 불가 — UI에서 error state 표시.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// ─── 데이터 모델 ──────────────────────────────────────────────────────────────

class UnclosedQueueItem {
  final String businessId;
  final String businessName;
  final DateTime workDate;     // 로컬 midnight (KST date → DateTime(y,m,d))
  final int totalConfirmed;
  final int closedCount;

  int get remainingCount => totalConfirmed - closedCount;

  const UnclosedQueueItem({
    required this.businessId,
    required this.businessName,
    required this.workDate,
    required this.totalConfirmed,
    required this.closedCount,
  });

  static UnclosedQueueItem? tryFromMap(Map<String, dynamic> m) {
    try {
      final dateStr = m['workDateStr'] as String;          // 'YYYY-MM-DD'
      final parts   = dateStr.split('-');
      return UnclosedQueueItem(
        businessId:     m['businessId']    as String,
        businessName:   m['businessName']  as String,
        workDate:       DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]),
        ),
        totalConfirmed: (m['totalConfirmed'] as num).toInt(),
        closedCount:    (m['closedCount']    as num).toInt(),
      );
    } catch (e) {
      debugPrint('[UnclosedQueue] tryFromMap 실패: $e');
      return null;
    }
  }
}

// ─── 서비스 ───────────────────────────────────────────────────────────────────

typedef UnclosedQueueResult = ({bool available, List<UnclosedQueueItem> rows});

class UnclosedActionQueueService {
  UnclosedActionQueueService._();
  static final UnclosedActionQueueService instance = UnclosedActionQueueService._();

  final _callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable(
        'callableGetUnclosedActionQueue',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );

  Future<UnclosedQueueResult> fetchQueue() async {
    try {
      final result = await _callable.call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data as Map);
      final available = (data['available'] as bool?) ?? false;

      if (!available) {
        debugPrint('[UnclosedQueue] available=false: ${data['error']}');
        return (available: false, rows: <UnclosedQueueItem>[]);
      }

      final rawRows = data['rows'] as List? ?? [];
      final rows = rawRows
          .whereType<Map>()
          .map((m) => UnclosedQueueItem.tryFromMap(
                Map<String, dynamic>.from(m as Map),
              ))
          .whereType<UnclosedQueueItem>()
          .toList();
      return (available: true, rows: rows);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[UnclosedQueue] CF 오류 ${e.code}: ${e.message}');
      return (available: false, rows: <UnclosedQueueItem>[]);
    } catch (e) {
      debugPrint('[UnclosedQueue] 조회 실패: $e');
      return (available: false, rows: <UnclosedQueueItem>[]);
    }
  }
}
