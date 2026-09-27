// lib/screens/business_admin/dialogs/attendance_reads.dart
//
// [R7-P1-3 P13-R] 당일명단이 **바깥에서 읽어오는 것들**의 경계.
//
//   8차에 `DayApplicantsReads` 로 한 것과 같은 패턴이다. 화면의 도메인 로직
//   (단기/장기 병합·중복 제거·상태 계산·탭 분류·업무 그룹·정원·수치 표현)은
//   그대로 production State 에 남기고, **원시 외부 호출만** 갈아끼운다.
//   그래서 이 경계는 파싱 이전 단계(Map/문서 데이터)에서 끊는다 —
//   모델 변환이나 필터를 여기로 옮기면 테스트가 제품 로직을 비켜 간다.
//
//   주지 않으면 전부 기존 구현으로 간다(`AttendanceReads.of`).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/core/business_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/ui/day_staffing_row.dart';
import '../../../services/contract_service.dart';
// `fetchApplicationsByBizPaged` 는 `firestore_service.dart` 의 part 다.
import '../../../services/firestore_service.dart';
import '../../../services/work_detail_time_service.dart';
import '../../../models/core/application_model.dart';

class AttendanceReads {
  /// 확정 근무자 원천 — CF 페이징 helper. 단기/장기 두 번 호출한다.
  ///   payload 를 그대로 넘긴다(창 계산은 화면이 한다).
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> payload)
      applicationsPaged;

  /// 업무유형 — `businesses/{id}/workTypes` 의 활성 문서. id → 필드 map.
  final Future<Map<String, Map<String, dynamic>>> Function(String businessId)
      workTypeDocs;

  /// 근태 기록 원천 — `callableGetAdminAttendances` 의 `items`.
  final Future<List<Map<String, dynamic>>> Function({
    required String businessId,
    required int startMs,
    required int endMs,
  }) adminAttendances;

  /// 업무별 근무시간(WorkDetail) 맵.
  final Future<Map<String, dynamic>> Function(List<ApplicationModel> workers)
      workDetailTimes;

  final Future<Map<String, UserModel>> Function({
    required List<String> uids,
    required String businessId,
  }) usersBatch;

  final Future<Map<String, String?>> Function({
    required List<String> appIds,
    required String businessId,
  }) contractStatus;

  final Future<List<DayStaffingRow>> Function({
    required String businessId,
    required int dayStartMs,
  }) dayStaffing;

  final Future<BusinessModel?> Function(String businessId) businessById;

  final Future<Map<String, String>> Function(List<String> businessIds)
      businessNames;

  const AttendanceReads({
    required this.applicationsPaged,
    required this.workTypeDocs,
    required this.adminAttendances,
    required this.workDetailTimes,
    required this.usersBatch,
    required this.contractStatus,
    required this.dayStaffing,
    required this.businessById,
    required this.businessNames,
  });

  /// 기존 구현 — 제품 기본값.
  factory AttendanceReads.of(FirestoreService svc, {ContractService? contracts}) {
    final contractSvc = contracts ?? ContractService();
    return AttendanceReads(
      applicationsPaged: (payload) => fetchApplicationsByBizPaged(payload),
      workTypeDocs: (businessId) async {
        final snapshot = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .collection('workTypes')
            .where('isActive', isEqualTo: true)
            .get();
        return {for (final d in snapshot.docs) d.id: d.data()};
      },
      adminAttendances: ({
        required String businessId,
        required int startMs,
        required int endMs,
      }) async {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableGetAdminAttendances',
                options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 30)));
        final r = await callable.call<Map<String, dynamic>>({
          'businessId': businessId,
          'startMs': startMs,
          'endMs': endMs,
        });
        return ((r.data['items'] as List<dynamic>?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      },
      workDetailTimes: (workers) => WorkDetailTimeService.load(workers),
      usersBatch: ({required uids, required businessId}) => svc.getUsersBatch(
          uids,
          businessId: businessId,
          purpose: FirestoreService.purposeWorkerDirectory),
      contractStatus: ({required appIds, required businessId}) =>
          contractSvc.getContractStatusBatch(appIds, businessId: businessId),
      dayStaffing: ({required businessId, required dayStartMs}) =>
          svc.getDayStaffingDetail(
              businessId: businessId, dayStartMs: dayStartMs),
      businessById: (businessId) => svc.getBusinessById(businessId),
      businessNames: (ids) => svc.getBusinessNames(ids),
    );
  }
}
