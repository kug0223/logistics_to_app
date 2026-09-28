import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/core/business_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/payroll_payment_service.dart';

/// [R7-P1-5 PAY-4] 급여 개요·월 상세의 **원시 외부 읽기 경계**.
///
/// P1-3 `AttendanceReads` · P1-4 `AdminHomeReads` 와 같은 형태다 — 화면이 실제로
/// 나가서 읽는 호출만 함수로 들고 있고 **파싱 이전에서 끊는다.** 월별 집계 구성,
/// 미확정·미이체 판정, 모름 표시, 정렬·검색·문구는 전부 화면에 남는다.
class PayrollOverviewReads {
  const PayrollOverviewReads({
    required this.businesses,
    required this.payrollSummaries,
    required this.adminAttendances,
    required this.workerSummaries,
    required this.repairSummary,
    required this.todayPaymentCount,
  });

  /// 관리 사업장 목록(SubAdmin 은 선택 사업장 하나).
  final Future<List<BusinessModel>> Function({
    required bool isSubAdmin,
    required String? effectiveBusinessId,
    required List<String> managedIds,
  }) businesses;

  /// CF `callableGetPayrollSummaries` — 월별 집계 projection 의 items.
  final Future<List<Map<String, dynamic>>> Function({
    required String businessId,
    required int year,
  }) payrollSummaries;

  /// CF `callableGetAdminAttendances` — 미확정·미이체 건수의 유일한 원천.
  /// 실패는 **throw** 한다. 호출부가 0 이 아니라 '모름'으로 다룬다.
  final Future<List<Map<String, dynamic>>> Function({
    required String businessId,
    required String yearMonthGte,
    required String yearMonthLte,
  }) adminAttendances;

  /// `payroll_summaries/{id}/workers` — 근무자별 집계(문서 id + 데이터).
  final Future<List<({String id, Map<String, dynamic> data})>> Function(
      String summaryId) workerSummaries;

  /// CF `callableRepairPayrollSummaries` — 집계 문서 재생성(**서버 쓰기**).
  final Future<void> Function({
    required String businessId,
    required String yearMonth,
  }) repairSummary;

  /// 오늘 지급 대상 건수. 모르면 null.
  final Future<int?> Function(String businessId) todayPaymentCount;

  factory PayrollOverviewReads.of({
    FirestoreService? firestoreService,
    PayrollPaymentService? paymentService,
  }) {
    final svc = firestoreService ?? FirestoreService();
    final pay = paymentService ?? PayrollPaymentService();
    HttpsCallable callable(String name, int timeoutSec) =>
        FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable(
            name,
            options: HttpsCallableOptions(
                timeout: Duration(seconds: timeoutSec)));

    return PayrollOverviewReads(
      businesses: ({
        required bool isSubAdmin,
        required String? effectiveBusinessId,
        required List<String> managedIds,
      }) async {
        if (isSubAdmin && effectiveBusinessId != null) {
          final biz = await svc.getBusinessById(effectiveBusinessId);
          return biz != null ? [biz] : <BusinessModel>[];
        }
        return svc.getBusinessesByIds(managedIds);
      },
      payrollSummaries: ({required String businessId, required int year}) async {
        final r = await callable('callableGetPayrollSummaries', 30)
            .call<Map<String, dynamic>>({'businessId': businessId, 'year': year});
        return ((r.data['items'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      },
      adminAttendances: ({
        required String businessId,
        required String yearMonthGte,
        required String yearMonthLte,
      }) async {
        final r = await callable('callableGetAdminAttendances', 60)
            .call<Map<String, dynamic>>({
          'businessId': businessId,
          'yearMonthGte': yearMonthGte,
          'yearMonthLte': yearMonthLte,
        });
        return ((r.data['items'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      },
      workerSummaries: (summaryId) async {
        final snap = await FirebaseFirestore.instance
            .collection('payroll_summaries')
            .doc(summaryId)
            .collection('workers')
            .get();
        return snap.docs
            .map((d) => (id: d.id, data: d.data()))
            .toList();
      },
      repairSummary: ({
        required String businessId,
        required String yearMonth,
      }) async {
        await callable('callableRepairPayrollSummaries', 30)
            .call<Map<String, dynamic>>(
                {'businessId': businessId, 'yearMonth': yearMonth});
      },
      todayPaymentCount: (businessId) =>
          pay.getTodayPaymentCount(businessId: businessId),
    );
  }
}
