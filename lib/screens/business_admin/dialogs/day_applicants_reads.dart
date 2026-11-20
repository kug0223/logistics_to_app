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
    this.contractAttendances,
  });

  /// 테스트 전용 — null 이면 운영 구현을 쓴다(WorkApplicantsReads.debugOverride 와 같은 관례).
  ///   공고 카드처럼 이 화면을 **직접 만들지 않는** 경로를 실제 위젯으로 검증할 때 쓴다.
  static DayApplicantsReads? debugOverride;

  /// 실제 화면이 쓰는 기본값 — 기존 서비스에 그대로 위임한다.
  factory DayApplicantsReads.of(
    FirestoreService svc, {
    ContractService? contracts,
  }) {
    final cs = contracts ?? ContractService();
    // [ADMIN-APPLICANTS-POSTCONFIRM] 근무 이력(hasWorked)과 노쇼(noShow)는 같은 날의 같은
    //   GetAdminAttendances 를 따로 두 번 불렀다. 한 로드에서 동시에 출발하므로 **진행 중인**
    //   요청 하나를 함께 쓴다 — 끝나면 바로 놓아 다음 로드는 새로 읽는다(결과 보관 없음).
    // [STATUS-DIALOG-READS.27] 계약 발행 판정 근태도 **같은 날 같은 창**이다 — 상한 도달의 취급만
    //   다르다(이쪽은 로그만, 계약 판정은 던짐). 응답 하나를 받아 각자 판정한다(CF 2→1).
    final dayAttendance =
        <String, Future<({List<AttendanceModel> rows, bool limitReached})>>{};
    Future<({List<AttendanceModel> rows, bool limitReached})> dayRaw(
        String businessId, DateTime date) {
      final key = '$businessId|${date.millisecondsSinceEpoch}';
      final inFlight = dayAttendance[key];
      if (inFlight != null) return inFlight;
      final request =
          svc.getAttendanceByDateWithLimit(businessId: businessId, date: date);
      dayAttendance[key] = request;
      void release() {
        if (identical(dayAttendance[key], request)) dayAttendance.remove(key);
      }
      request.then((_) => release(), onError: (Object _) => release());
      return request;
    }
    Future<List<AttendanceModel>> sharedDay(String businessId, DateTime date) =>
        dayRaw(businessId, date).then((r) => r.rows);
    // [CONFIRM-TO-CONTRACT.21] 확정 직후 계약 작성 판정과 명단 재조회가 같은 확정자 명단·
    //   계약 판정 근태를 동시에 읽는다. 위와 같은 규칙 — **진행 중인** 요청만 함께 쓰고 끝나면 놓는다.
    final inFlight = <String, Future<Object?>>{};
    Future<T> shared<T>(String key, Future<T> Function() start) {
      final cur = inFlight[key];
      if (cur != null) return cur as Future<T>;
      final request = start();
      inFlight[key] = request;
      void release() {
        if (identical(inFlight[key], request)) inFlight.remove(key);
      }
      request.then((_) => release(), onError: (Object _) => release());
      return request;
    }
    // [STATUS-DIALOG-READS.27] 대기 지원자와 초대 현황은 같은 요청이다(그날 · applicantReview).
    //   위와 같은 규칙 — 진행 중인 요청만 함께 쓰고 끝나면 놓는다(CF 2→1).
    Future<List<Map<String, dynamic>>> reviewDay(String businessId, DateTime date) =>
        shared('review|$businessId|${date.millisecondsSinceEpoch}',
            () => svc.fetchDayApplicantReviewRaw(date: date, businessId: businessId));
    return DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) =>
          svc.getPendingApplicationsByDateAndBusiness(
              date: date, businessId: businessId, purpose: purpose,
              reviewRaw: purpose == FirestoreService.purposeApplicantReview
                  ? reviewDay(businessId, date)
                  : null),
      confirmedWorkers: ({required date, required businessId}) => shared(
          'confirmed|$businessId|${date.millisecondsSinceEpoch}',
          () => svc.getConfirmedWorkersByDateAndBusinessOrThrow(
              date: date, businessId: businessId)),
      dayStaffing: ({required businessId, required dayStartMs}) =>
          svc.getDayStaffingDetail(
              businessId: businessId, dayStartMs: dayStartMs),
      dayInvitations: ({required date, required businessId}) =>
          svc.getDayInvitationsByDateAndBusiness(
              date: date, businessId: businessId,
              reviewRaw: reviewDay(businessId, date)),
      hasWorkedMap: ({required businessId, required date}) =>
          svc.loadHasWorkedMap(businessId: businessId, date: date,
              attendances: sharedDay(businessId, date)),
      noShowApplicationIds: ({required businessId, required date}) =>
          svc.getNoShowApplicationIdsByDate(businessId: businessId, date: date,
              attendances: sharedDay(businessId, date)),
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
      // [NOSHOW-CONTRACT-GUARD] 실패·조회 상한 도달을 **던지는** 읽기.
      //   [STATUS-DIALOG-READS.27] 같은 날 공유 응답에서 상한 도달을 여기서 던진다 —
      //   예전 `getAttendanceForKstDays(first: date, last: date)` 와 같은 창·같은 판정이다.
      contractAttendances: ({required businessId, required date}) =>
          dayRaw(businessId, date).then((r) {
            if (r.limitReached) {
              throw StateError('callableGetAdminAttendances limit reached — 결과가 잘렸을 수 있다');
            }
            return r.rows;
          }),
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

  /// [REISSUE-RECOVERY] 조회 실패와 "계약 없음"을 나눠 받는다.
  final Future<ContractStatusBatch> Function(
    List<String> applicationIds, {
    required String businessId,
  }) contractStatusBatch;

  /// [NOSHOW-CONTRACT-GUARD] 그 날의 근태 — 노쇼·결근 근무일에 계약서를 권하지 않기 위해.
  ///   null(주지 않음)이거나 실패하면 화면은 근태를 **모르는** 것으로 보고
  ///   단기 근무의 `계약서 작성` 을 내지 않는다.
  final Future<List<AttendanceModel>> Function({
    required String businessId,
    required DateTime date,
  })? contractAttendances;
}
