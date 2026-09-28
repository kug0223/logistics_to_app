import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/id_card_access_request_model.dart';
import '../../models/core/renewal_proposal_model.dart';
import '../../models/core/to_model.dart';
import '../../services/firestore_service.dart';

/// [R7-P2-1 P21-E] 지원자 홈의 **원시 외부 읽기 경계**.
///
/// 관리자 쪽 `AdminHomeReads`·`PayrollOverviewReads` 와 같은 형태다 — 홈이 실제로
/// 나가서 읽는 호출만 함수로 들고 있고 **파싱 이전에서 끊는다.** Priority Hero 판정,
/// 주간 7일, 지원현황 집계, 수입, 추천, 실패·부분 문구는 전부 화면에 남는다.
///
/// 실패는 **throw** 한다 — 홈이 호출마다 따로 잡아 이전 값을 유지하고
/// "최신이 아닐 수 있다"고 말한다(0으로 덮지 않는다).
class UserHomeReads {
  const UserHomeReads({
    required this.myApplications,
    required this.myMonthlyAttendances,
    required this.publishedTOs,
    required this.pendingIdCardRequests,
    required this.myRenewalProposals,
    required this.businessById,
    required this.invalidatePublishedTOsCache,
  });

  final Future<List<ApplicationModel>> Function(String uid) myApplications;

  final Future<List<AttendanceModel>> Function({
    required String userId,
    required int year,
    required int month,
  }) myMonthlyAttendances;

  final Future<List<TOModel>> Function() publishedTOs;

  final Future<List<IdCardAccessRequestModel>> Function(String uid)
      pendingIdCardRequests;

  final Future<List<RenewalProposalModel>> Function() myRenewalProposals;

  final Future<BusinessModel?> Function(String businessId) businessById;

  final void Function() invalidatePublishedTOsCache;

  factory UserHomeReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return UserHomeReads(
      myApplications: svc.getMyApplications,
      myMonthlyAttendances: ({
        required String userId,
        required int year,
        required int month,
      }) =>
          svc.getMyMonthlyAttendances(userId: userId, year: year, month: month),
      publishedTOs: svc.getPublishedTOs,
      pendingIdCardRequests: svc.getPendingIdCardRequestsForUser,
      myRenewalProposals: svc.getMyRenewalProposals,
      businessById: svc.getBusinessById,
      invalidatePublishedTOsCache: svc.invalidatePublishedTOsCache,
    );
  }
}
