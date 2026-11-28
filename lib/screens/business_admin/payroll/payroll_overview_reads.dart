import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/core/attendance_model.dart';
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
    this.outstandingRecords,
    this.personLabels,
    this.monthLedgerCounts,
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

  /// CF `callableGetAdminAttendances` — 미확정·미이체 건수의 **canonical 원장**.
  ///
  ///   실패는 **throw** 한다. 호출부가 0 이 아니라 '모름'으로 다룬다.
  ///   `limitReached` 를 함께 돌려준다 — 서버가 10,000건에서 끊으므로 그때의
  ///   합계는 실제보다 작다. 통계 서비스와 같은 관례로 **fail-closed**,
  ///   즉 사실이 아닌 작은 수를 보여주지 않고 모름으로 다룬다.
  final Future<({List<Map<String, dynamic>> items, bool limitReached})> Function({
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

  /// [PERF-L22] 전체 미이체 근태(2020-01-01~ · `getAllOutstandingWages`). 있으면 배너 숫자를 이것으로 세고,
  ///   **같은 목록**을 배너 → 대시보드로 넘겨 대시보드가 같은 전 기간 조회를 다시 하지 않게 한다.
  ///   null 이면(시험 등) 예전처럼 [todayPaymentCount] 를 쓴다. 실패는 throw.
  final Future<List<AttendanceModel>> Function(String businessId)? outstandingRecords;

  /// [PAYROLL-ANNUAL-READ.48] CF `callableGetPayrollMonthLedgerCounts` — 한 달 원장을 서버가 끝까지 세어
  ///   숫자만 돌려준다(읽기 전용, **서버 후보 — 미배포**). 한 달이 10,000건을 넘어 원장 응답이 잘렸을
  ///   때만 부른다. 함수가 없으면 throw — 그 달은 '확인 못함'으로 남는다. null 이면 부르지 않는다.
  final Future<Object?> Function({
    required String businessId,
    required String yearMonth,
  })? monthLedgerCounts;

  /// [PAYROLL-DETAIL.32] 사업장 안 인력번호(uid → 'P-301'). 근무자 목록에 **같은 이름이 있을 때만**
  ///   부른다 — 이름만으로는 누구의 상세로 들어가는지 가를 수 없다. null 이면 번호 없이 그린다.
  final Future<Map<String, String>> Function({
    required String businessId,
    required List<String> uids,
  })? personLabels;

  factory PayrollOverviewReads.of({
    FirestoreService? firestoreService,
    PayrollPaymentService? paymentService,
    FirebaseFirestore? firestore,
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
          // [impl_55 · AUD-4 H4] 조회 실패를 null/[] 로 접는 변형 대신 OrThrow — '사업장 없음'으로 오인하지 않게.
          final biz = await svc.getBusinessByIdOrThrow(effectiveBusinessId);
          return biz != null ? [biz] : <BusinessModel>[];
        }
        return svc.getBusinessesByIdsOrThrow(managedIds);
      },
      payrollSummaries: ({required String businessId, required int year}) async {
        // [PAYROLL-ANNUAL-READ.48] 화면 대기 30초(.39-A1) — 연결이 안 되면 플러그인 timeout 이
        //   적용되지 않아 기기에서 3분 넘게 스피너가 돌았다.
        final r = await callable('callableGetPayrollSummaries', 30)
            .call<Map<String, dynamic>>({'businessId': businessId, 'year': year})
            .timeout(PayrollPaymentService.readWait);
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
        // [PAYROLL-ANNUAL-READ.48] 화면 쪽 대기도 .39-A1 과 같은 30초(연결이 안 되면 플러그인
        //   timeout 이 적용되지 않는다). 읽기 전용이라 늦은 응답은 버린다.
        final r = await callable('callableGetAdminAttendances', 60)
            .call<Map<String, dynamic>>({
          'businessId': businessId,
          'yearMonthGte': yearMonthGte,
          'yearMonthLte': yearMonthLte,
        }).timeout(PayrollPaymentService.readWait);
        final items = ((r.data['items'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        return (
          items: items,
          limitReached: r.data['limitReached'] == true,
        );
      },
      workerSummaries: (summaryId) async {
        // [DU1 MONTH-READ-SOURCE] 서버 조회만 쓴다. 기본 get 은 서버 불가 시 캐시로 대체하고
        //   빈 캐시면 **빈 결과를 성공으로** 준다 — 그러면 화면이 조회 불가를 '확정 0'·'집계 누락(복원)'으로
        //   말했다. 서버 불가는 오류(unavailable)로 올라와 '불러오지 못했습니다·다시 시도'가 된다.
        final snap = await (firestore ?? FirebaseFirestore.instance)
            .collection('payroll_summaries')
            .doc(summaryId)
            .collection('workers')
            .get(const GetOptions(source: Source.server));
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
      outstandingRecords: (businessId) =>
          pay.getAllOutstandingWages(businessId: businessId),
      monthLedgerCounts: ({required String businessId, required String yearMonth}) async {
        final r = await callable('callableGetPayrollMonthLedgerCounts', 30)
            .call<Map<String, dynamic>>({'businessId': businessId, 'yearMonth': yearMonth})
            .timeout(PayrollPaymentService.readWait);
        return r.data;
      },
      personLabels: ({required String businessId, required List<String> uids}) async {
        final users = await svc.getUsersBatch(uids,
            businessId: businessId, purpose: FirestoreService.purposeWorkerDirectory);
        return {
          for (final e in users.entries)
            if (e.value.personLabel != null) e.key: e.value.personLabel!,
        };
      },
    );
  }
}
