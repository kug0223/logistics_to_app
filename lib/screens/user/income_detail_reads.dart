import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../services/firestore_service.dart';

/// [R7-P2-4 P24-I] 수입 상세가 **그 달을 만들 때** 나가는 읽기 경계.
///
/// 이 화면의 핵심은 "지금 보고 있는 달" 하나다 — 라벨·조회 연월·금액 모집단이
/// 같은 달을 가리켜야 한다. 그 일치를 실제 시트 제스처로 확인하려면 달마다
/// 다른 금액을 줄 수 있어야 한다. production 은 `reads: null`.
///
/// 급여 처리·이체(쓰기)는 이 경계에 없다 — 이 화면은 읽기 전용이다.
class IncomeDetailReads {
  const IncomeDetailReads({
    required this.myApplications,
    required this.myMonthlyAttendances,
  });

  final Future<List<ApplicationModel>> Function(String uid) myApplications;

  final Future<List<AttendanceModel>> Function({
    required String userId,
    required int year,
    required int month,
  }) myMonthlyAttendances;

  factory IncomeDetailReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return IncomeDetailReads(
      myApplications: svc.getMyApplications,
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) =>
          svc.getMyMonthlyAttendances(userId: userId, year: year, month: month),
    );
  }
}
