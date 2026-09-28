import '../../models/core/attendance_model.dart';
import '../../services/firestore_service.dart';

/// [R7-P2-4 P24-Q] 중간정산 요청 화면이 **정산 후보를 만들 때** 나가는 읽기 경계.
///
/// 이 화면은 "정산할 수 있는 근무가 있는가" 를 말한다 — 돈 이야기다.
/// 못 읽은 것을 "없다" 로 말하면 사용자가 받을 돈을 포기한다. 그 구분을
/// 실제로 확인하려면 실패를 줄 수 있어야 한다. production 은 `reads: null`.
///
/// 정산 **신청(쓰기)** 은 이 경계에 넣지 않는다 — 읽기만 갈아끼운다.
class InterimSettlementReads {
  const InterimSettlementReads({required this.myMonthlyAttendances});

  final Future<List<AttendanceModel>> Function({
    required String userId,
    required int year,
    required int month,
  }) myMonthlyAttendances;

  factory InterimSettlementReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return InterimSettlementReads(
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) =>
          svc.getMyMonthlyAttendances(userId: userId, year: year, month: month),
    );
  }
}
