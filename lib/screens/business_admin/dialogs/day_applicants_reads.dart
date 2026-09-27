import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../models/ui/day_staffing_row.dart';
import '../../../services/contract_service.dart';
import '../../../services/firestore_service.dart';

/// [R8 O03] 일자별 인력 현황 화면이 **읽는** 것들.
///
///   이 화면은 한 번 로드에 서비스 읽기를 여러 번 한다. 그 숫자가 크다는 것은
///   의존성 규모의 설명이고 "실행할 수 없다"는 뜻이 아니었다 — 읽는 경계를
///   한 곳에 모으면 화면은 그대로 둔 채 바깥만 갈아끼울 수 있다.
///
///   `WorkforceController` 가 이미 같은 방식이다(읽기를 optional 로 받고 주지
///   않으면 서비스로 간다). 새 프레임워크를 만들지 않고 그 패턴을 쓴다.
///
///   여기에는 도메인 계산을 두지 않는다. 읽기만 모은다 — 그룹 구성·캐시·머리말
///   수치·scope label 은 화면이 계속 자기가 한다.
class DayApplicantsReads {
  const DayApplicantsReads({
    required this.pendingApplications,
    required this.confirmedWorkers,
    required this.dayStaffing,
    required this.dayInvitations,
    required this.hasWorkedMap,
    required this.noShowApplicationIds,
    required this.usersBatch,
    required this.weeklyAttendance,
    required this.slotWorkDetailCapacities,
    required this.slotWorkDetails,
    required this.to,
    required this.contractStatusBatch,
  });

  /// 실제 화면이 쓰는 기본값 — 기존 서비스에 그대로 위임한다.
  factory DayApplicantsReads.of(
    FirestoreService svc, {
    ContractService? contracts,
  }) {
    final cs = contracts ?? ContractService();
    return DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) =>
          svc.getPendingApplicationsByDateAndBusiness(
              date: date, businessId: businessId, purpose: purpose),
      confirmedWorkers: ({required date, required businessId}) =>
          svc.getConfirmedWorkersByDateAndBusinessOrThrow(
              date: date, businessId: businessId),
      dayStaffing: ({required businessId, required dayStartMs}) =>
          svc.getDayStaffingDetail(
              businessId: businessId, dayStartMs: dayStartMs),
      dayInvitations: ({required date, required businessId}) =>
          svc.getDayInvitationsByDateAndBusiness(
              date: date, businessId: businessId),
      hasWorkedMap: ({required businessId, required date}) =>
          svc.loadHasWorkedMap(businessId: businessId, date: date),
      noShowApplicationIds: ({required businessId, required date}) =>
          svc.getNoShowApplicationIdsByDate(businessId: businessId, date: date),
      usersBatch: (uids, {required businessId, purpose}) =>
          svc.getUsersBatch(uids, businessId: businessId, purpose: purpose),
      weeklyAttendance: ({required businessId, required weekStart,
              required weekEnd}) =>
          svc.getWeeklyAttendanceByBusiness(
              businessId: businessId, weekStart: weekStart, weekEnd: weekEnd),
      slotWorkDetailCapacities: (toId, slotId) =>
          svc.getSlotWorkDetailCapacities(toId, slotId),
      slotWorkDetails: (toId, slotId) => svc.getSlotWorkDetails(toId, slotId),
      to: (toId) => svc.getTO(toId),
      contractStatusBatch: (ids, {required businessId}) =>
          cs.getContractStatusBatch(ids, businessId: businessId),
    );
  }

  final Future<List<ApplicationModel>> Function({
    required DateTime date,
    required String businessId,
    String? purpose,
  }) pendingApplications;

  final Future<List<ApplicationModel>> Function({
    required DateTime date,
    required String businessId,
  }) confirmedWorkers;

  final Future<List<DayStaffingRow>> Function({
    required String businessId,
    required int dayStartMs,
  }) dayStaffing;

  final Future<List<ApplicationModel>> Function({
    required DateTime date,
    required String businessId,
  }) dayInvitations;

  final Future<Map<String, bool>> Function({
    required String businessId,
    required DateTime date,
  }) hasWorkedMap;

  final Future<Set<String>> Function({
    required String businessId,
    required DateTime date,
  }) noShowApplicationIds;

  final Future<Map<String, UserModel>> Function(
    List<String> uids, {
    required String businessId,
    String? purpose,
  }) usersBatch;

  final Future<Map<String, List<AttendanceModel>>> Function({
    required String businessId,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) weeklyAttendance;

  final Future<Map<String, int>> Function(String toId, String slotId)
      slotWorkDetailCapacities;

  final Future<List<WorkDetailData>> Function(String toId, String slotId)
      slotWorkDetails;

  final Future<TOModel?> Function(String toId) to;

  final Future<Map<String, String?>> Function(
    List<String> applicationIds, {
    required String businessId,
  }) contractStatusBatch;
}
