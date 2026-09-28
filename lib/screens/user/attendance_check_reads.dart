import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../services/firestore_service.dart';

/// [R7-P2-1 잔여] 출퇴근 화면이 **목록을 만들 때** 나가는 읽기 경계.
///
/// 홈 쪽 `UserHomeReads` 와 같은 형태다 — 화면이 실제로 나가서 읽는 호출만
/// 들고 있고, 날짜 필터·제외 술어·정렬·문구는 전부 화면에 남는다.
/// production 은 `reads: null` 이라 기존 `FirestoreService` 인스턴스를 그대로 쓴다.
///
/// 체크인·체크아웃 mutation 은 **이 경계에 넣지 않는다** — 읽기만 갈아끼운다.
class AttendanceCheckReads {
  const AttendanceCheckReads({
    required this.myApplications,
    required this.todayAttendance,
  });

  final Future<List<ApplicationModel>> Function(String uid) myApplications;

  final Future<AttendanceModel?> Function({
    required String userId,
    required String applicationId,
  }) todayAttendance;

  factory AttendanceCheckReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return AttendanceCheckReads(
      myApplications: svc.getMyApplications,
      todayAttendance: ({required String userId, required String applicationId}) =>
          svc.getTodayAttendance(userId: userId, applicationId: applicationId),
    );
  }
}
