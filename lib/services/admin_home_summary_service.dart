// admin_home_summary_service.dart
// PHASE 1 — Admin Home Summary Data Layer
//
// callableGetAdminHomeSummary를 호출하는 클라이언트 서비스
// OWNER scope는 서버가 auth uid 기준으로 결정 (selectedBusinessId 없음)
// SUB_ADMIN은 effectiveBusinessId를 selectedBusinessId로 전달 → 서버가 membership 검증 후 단일 scope 반환
//
// 사용 예:
//   // OWNER:
//   final summary = await AdminHomeSummaryService().fetchSummary();
//   // SUB_ADMIN:
//   final summary = await AdminHomeSummaryService().fetchSummary(
//     selectedBusinessId: up.effectiveBusinessId,
//   );

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/ui/admin_home_summary_model.dart';

class AdminHomeSummaryService {
  /// Admin Home Summary를 서버에서 가져온다.
  ///
  /// - [selectedBusinessId]: SUB_ADMIN이 특정 사업장 scope를 요청할 때 전달.
  ///   서버가 caller의 subAdminBusinessIds 기반으로 권한 검증 후 해당 사업장만 집계.
  ///   null이면 기존 동작 유지 (OWNER=전체 aggregate, SUB_ADMIN=전체 subAdmin aggregate).
  /// - 반환: [AdminHomeSummaryModel] 또는 예외 throw
  /// - 오류 처리: 호출자가 try-catch로 감싸야 함
  Future<AdminHomeSummaryModel> fetchSummary({String? selectedBusinessId}) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetAdminHomeSummary');

    final result = await callable.call<Map<Object?, Object?>>({
      if (selectedBusinessId != null) 'selectedBusinessId': selectedBusinessId,
    });
    return AdminHomeSummaryModel.fromCallable(result);
  }

  /// 특정 섹션이 available:false인지 확인 (로그용)
  static void logUnavailableSections(AdminHomeSummaryModel model) {
    final actions = model.actions;
    if (!actions.approval.available)        debugPrint('[adminHomeSummary] approval 로드 실패');
    if (!actions.unsentContract.available)  debugPrint('[adminHomeSummary] unsentContract 로드 실패');
    if (!actions.unpaidWage.available)      debugPrint('[adminHomeSummary] unpaidWage 로드 실패');
    if (!actions.unclosed.available)        debugPrint('[adminHomeSummary] unclosed 로드 실패');
    if (!actions.wageChangeRequest.available) debugPrint('[adminHomeSummary] wageChangeRequest 로드 실패');
    if (!actions.settlementRequest.available) debugPrint('[adminHomeSummary] settlementRequest 로드 실패');
    if (!model.upcoming.expiringContract.available) debugPrint('[adminHomeSummary] expiringContract 로드 실패');
  }
}
