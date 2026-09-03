import 'package:cloud_functions/cloud_functions.dart';
import '../models/core/available_worker_model.dart';

/// Phase 8.1B — 근무 가능 인력 조회 + 제안 서비스
///
/// 보안 설계:
///   · `callableGetAvailableWorkers` — 서버에서 권한 검증 + 개인정보 마스킹 후 반환
///   · `callableInviteWorker` — 기존 CF 재사용, 서버에서 용량·중복 검증
class AvailableWorkersResult {
  final List<AvailableWorkerModel> candidates;
  final bool hasMore;
  final String? nextCursor;

  const AvailableWorkersResult({
    required this.candidates,
    required this.hasMore,
    this.nextCursor,
  });
}

class AvailableWorkersService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 근무 가능 인력 조회.
  ///
  /// [toId], [slotId] 필수. 서버가 businessCity, 날짜, 시간을 자동 derive.
  Future<AvailableWorkersResult> getAvailableWorkers({
    required String toId,
    required String slotId,
    String? workDetailId,
    int pageSize = 20,
    String? cursor,
  }) async {
    final callable =
        _functions.httpsCallable('callableGetAvailableWorkers');
    final result = await callable.call<Map<String, dynamic>>({
      'toId': toId,
      'slotId': slotId,
      if (workDetailId != null && workDetailId.isNotEmpty)
        'workDetailId': workDetailId,
      'pageSize': pageSize,
      if (cursor != null) 'cursor': cursor,
    });
    final data = result.data;
    return AvailableWorkersResult(
      candidates: AvailableWorkerModel.listFromResponse(
          data['candidates'] as List<dynamic>?),
      hasMore: data['hasMore'] as bool? ?? false,
      nextCursor: data['nextCursor'] as String?,
    );
  }

  /// 근무 제안 (기존 callableInviteWorker 재사용).
  ///
  /// [selectedWorkType], [workDetailStartTime], [workDetailEndTime] — 동일 workType 복수 시
  /// 정확한 WorkDetail을 서버에서 식별하기 위해 필요. WorkDetailData.id = '${workType}_${startTime}_$endTime'.
  ///
  /// 성공 시 applicationId 반환.
  Future<String> inviteWorker({
    required String toId,
    required String businessId,
    required String targetUid,
    required DateTime workDate,
    String? slotId,
    String? selectedWorkType,
    String? workDetailStartTime,
    String? workDetailEndTime,
  }) async {
    final callable = _functions.httpsCallable('callableInviteWorker');
    final result = await callable.call<Map<String, dynamic>>({
      'toId': toId,
      'businessId': businessId,
      'targetUid': targetUid,
      'workDate': workDate.toIso8601String(),
      if (slotId != null && slotId.isNotEmpty) 'slotId': slotId,
      if (selectedWorkType != null && selectedWorkType.isNotEmpty)
        'selectedWorkType': selectedWorkType,
      if (workDetailStartTime != null && workDetailStartTime.isNotEmpty)
        'workDetailStartTime': workDetailStartTime,
      if (workDetailEndTime != null && workDetailEndTime.isNotEmpty)
        'workDetailEndTime': workDetailEndTime,
    });
    return result.data['applicationId'] as String? ?? '';
  }
}
