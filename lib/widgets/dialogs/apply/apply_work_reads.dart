/// [R7-P2-2 A1 후속] 지원창이 **열릴 때** 나가는 세 읽기.
///
/// `ApplyWorkDialog._loadInitialData()` 의 `Future.wait` 세 원소가 그것이고,
/// 그 셋이 끝나야 `finally` 가 `_isLoading` 을 내려 업무 카드가 그려진다.
/// 세 호출이 모두 `FirestoreService` 하드 싱글턴(+ private Firebase 인스턴스)과
/// Dart extension 의 **정적 디스패치** 뒤에 있어서, 하위 클래스 fake 로는
/// 대신할 수 없었다 — 그게 ABR-2 의 영구 로딩이었다.
///
/// 여기 있는 것은 **읽기뿐**이다. 지원·취소·확정 같은 mutation 은 넣지 않는다.
/// 장기공고 전용 추가 읽기(`workerHasAttendanceRecord`,
/// `getMyConfirmedApplicationsForConflictCheck`)는 이 경계에 없다 — 이번 범위는
/// 초기 로딩을 끝내는 세 호출이다.
///
/// production 은 `reads: null` 이라 아래 기본값이 **같은 uid/key 로 지금 쓰는
/// 서비스 메서드를 그대로** 부른다. 순서·실패 의미도 화면에 남는다.
library;

import '../../../models/core/application_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/schedule_conflict_service.dart';

class ApplyWorkReads {
  const ApplyWorkReads({
    required this.applicationsForTO,
    required this.confirmedSchedules,
    required this.conflictsForWorkDetails,
    required this.myApplicationsForTOFresh,
    required this.businessForPolicy,
  });

  /// ① 이 TO 에 대한 **내** 지원서. key = toId + uid.
  final Future<List<ApplicationModel>> Function({
    required String toId,
    required String uid,
  }) applicationsForTO;

  /// ② 그 날짜의 내 확정 근무. key = uid + workDate.
  final Future<List<ApplicationModel>> Function({
    required String uid,
    required DateTime workDate,
  }) confirmedSchedules;

  /// ③ 그 날짜·업무들에 대한 시간 충돌. key = workDate + workDetails.
  final Future<Map<String, ConflictInfo>> Function({
    required DateTime workDate,
    required List<WorkDetailData> workDetails,
  }) conflictsForWorkDetails;

  /// ④ 지원 결과가 UNKNOWN 일 때 **다시 보는** 내 지원서. 캐시를 쓰지 않는다.
  ///   읽기다 — 재전송이 아니다.
  final Future<List<ApplicationModel>> Function(String toId)
      myApplicationsForTOFresh;

  /// ⑤ [R7-PAYROLL-POLICY.4C] 이 사업장의 **근태·급여 처리 기준**.
  ///
  ///   이 경로(카드 → 지원 시트)는 공고 상세를 거치지 않을 수 있어
  ///   근로자가 기준을 본 적이 없었다. 그런데 지원하는 순간 그 기준이
  ///   지원서에 고정된다 — 보지 못한 조건으로 약속의 씨앗이 생긴다.
  ///
  ///   그래서 시트가 열릴 때 **한 번** 읽어 확인 화면에 보여주고, 그 값에서
  ///   만든 토큰을 submit 에 함께 보낸다. 상시 listener 를 만들지 않는다.
  ///   읽지 못하면 `null` — 모름이고, 사업장 기본값으로 메우지 않는다.
  final Future<BusinessModel?> Function(String businessId) businessForPolicy;

  factory ApplyWorkReads.of([
    FirestoreService? service,
    ScheduleConflictService? conflictService,
  ]) {
    final svc = service ?? FirestoreService();
    final cs = conflictService ?? ScheduleConflictService();
    return ApplyWorkReads(
      applicationsForTO: ({required String toId, required String uid}) =>
          svc.getApplicationsForTO(toId: toId, uid: uid),
      confirmedSchedules: ({required String uid, required DateTime workDate}) =>
          svc.getConfirmedSchedules(uid: uid, workDate: workDate),
      conflictsForWorkDetails: (
              {required DateTime workDate,
              required List<WorkDetailData> workDetails}) =>
          cs.checkConflictsForWorkDetails(
              workDate: workDate, workDetails: workDetails),
      myApplicationsForTOFresh: svc.getMyApplicationsForTOFresh,
      businessForPolicy: svc.getBusinessById,
    );
  }
}
