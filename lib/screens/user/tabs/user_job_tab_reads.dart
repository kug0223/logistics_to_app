import '../../../models/core/application_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/to_filter_state.dart';
import '../../../services/firestore_service.dart';

/// [R7-P2-2 P22-L] 일자리 탭이 **목록을 만들 때** 나가는 읽기 경계.
///
/// 홈·출퇴근 쪽 경계와 같은 형태다 — 화면이 실제로 나가서 읽는 호출만 들고
/// 있고, 필터 계산·모집단 문구·빈/부분/실패 구분은 전부 화면에 남는다.
/// production 은 `reads: null` 이라 기존 `FirestoreService` 인스턴스를 쓴다.
///
/// 지원(쓰기)은 이 경계에 넣지 않는다 — 읽기만 갈아끼운다.
class UserJobTabReads {
  const UserJobTabReads({
    required this.publishedTOsPaged,
    required this.myApplications,
    required this.tosByIds,
  });

  /// 서버 페이지 한 장. `{items, lastToId, hasMore}` 모양을 그대로 돌려준다.
  final Future<Map<String, dynamic>> Function({
    String? lastToId,
    TOFilterState? filter,
  }) publishedTOsPaged;

  final Future<List<ApplicationModel>> Function(String uid) myApplications;

  final Future<List<TOModel>> Function(List<String> ids) tosByIds;

  factory UserJobTabReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return UserJobTabReads(
      publishedTOsPaged: ({String? lastToId, TOFilterState? filter}) =>
          svc.getPublishedTOsPaged(lastToId: lastToId, filter: filter),
      myApplications: svc.getMyApplications,
      tosByIds: svc.getTOsByIds,
    );
  }
}
