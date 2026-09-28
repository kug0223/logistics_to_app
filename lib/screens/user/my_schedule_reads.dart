import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/invite_region_preference.dart';
import '../../models/core/worker_availability_model.dart';
import '../../services/availability_service.dart';
import '../../services/firestore_service.dart';
import '../../services/invite_region_service.dart';

/// [R7-P2-3 READ] 일정 탭이 **화면을 만들 때** 나가는 읽기 경계.
///
/// 근무 가능일은 **초대의 절반**이다 — 나머지 절반(초대 받을 지역·수신 여부)은
/// 같은 문서의 다른 필드가 정한다. 화면이 무엇을 약속하는지 확인하려면 두 값을
/// 함께 줄 수 있어야 한다. production 은 `reads: null` 이라 기존 서비스를 쓴다.
///
/// 가능일 저장(쓰기)은 이 경계에 넣지 않는다 — 읽기만 갈아끼운다.
class MyScheduleReads {
  const MyScheduleReads({
    required this.myApplications,
    required this.myMonthlyAttendances,
    required this.myAvailability,
    required this.invitePreference,
  });

  final Future<List<ApplicationModel>> Function(String uid) myApplications;

  final Future<List<AttendanceModel>> Function({
    required String userId,
    required int year,
    required int month,
  }) myMonthlyAttendances;

  final Future<WorkerAvailabilityModel?> Function(String uid) myAvailability;

  /// 실패해도 OFF 로 단정하지 않는다 — `unknown` 이 따로 있다.
  final Future<InviteRegionPreference> Function(String uid) invitePreference;

  factory MyScheduleReads.of([
    FirestoreService? service,
    AvailabilityService? availabilityService,
    InviteRegionService? inviteRegionService,
  ]) {
    final svc = service ?? FirestoreService();
    final av = availabilityService ?? AvailabilityService();
    final ir = inviteRegionService ?? InviteRegionService();
    return MyScheduleReads(
      myApplications: svc.getMyApplications,
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) =>
          svc.getMyMonthlyAttendances(userId: userId, year: year, month: month),
      myAvailability: av.loadMyAvailability,
      invitePreference: ir.loadMine,
    );
  }
}
