// lib/services/staffing_readiness_service.dart
//
// callableGetStaffingReadiness 호출 서비스
//
// [설계 원칙]
//   - OWNER scope: selectedBusinessId 없이 호출 → 서버가 uid 기반으로 모든 사업장 집계
//   - SubAdmin scope: selectedBusinessId 전달 → 서버 검증 후 단일 사업장 집계
//   - 에러: StaffingReadinessModel.empty() 반환 (available: false)
//
import 'package:cloud_functions/cloud_functions.dart';

import '../models/ui/staffing_readiness_model.dart';

class StaffingReadinessService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static final HttpsCallable _callable =
      _functions.httpsCallable('callableGetStaffingReadiness');

  /// D0~D+7 인력 현황을 서버에서 조회한다.
  ///
  /// [selectedBusinessId] SubAdmin이 특정 사업장을 선택했을 때 전달.
  ///   OWNER는 null로 호출하면 서버가 모든 관리 사업장을 집계.
  static Future<StaffingReadinessModel> fetchReadiness({
    String? selectedBusinessId,
  }) async {
    final result = await _callable.call<Map<Object?, Object?>>({
      if (selectedBusinessId != null)
        'selectedBusinessId': selectedBusinessId,
    });
    return StaffingReadinessModel.fromCallable(result);
  }
}
