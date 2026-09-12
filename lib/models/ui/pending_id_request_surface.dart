import '../core/id_card_access_request_model.dart';

/// USER 홈의 신분증 열람 요청 진입점 상태.
///
/// [DS-03] 요청은 idCardAccessRequests에 notification과 독립적으로 저장된다.
/// 이 클래스는 canonical 요청 목록에서 홈 표면의 노출 여부와 문구만 파생시킨다.
/// 별도 저장 필드를 만들지 않는다 — source of truth는 요청 컬렉션 하나다.
///
/// 홈은 discovery surface만 담당한다. 승인·거절과 개별 요청 row는
/// 기존 MyRequestsDialog가 처리하므로 여기서 다루지 않는다.
class PendingIdRequestSurface {
  /// 처리 대기 중인 요청 수.
  final int count;

  /// 1건일 때만 사용하는 사업장명. 여러 건이면 null (홈에서 묶지 않는다).
  final String? businessName;

  const PendingIdRequestSurface({required this.count, this.businessName});

  /// 표시할 요청이 없는 상태. 조회 실패도 이 상태로 수렴한다.
  static const PendingIdRequestSurface empty = PendingIdRequestSurface(count: 0);

  /// 조회 결과에서 생성.
  factory PendingIdRequestSurface.from(List<IdCardAccessRequestModel> requests) {
    if (requests.isEmpty) return empty;
    final single = requests.length == 1 ? requests.first : null;
    final name = single?.requesterBusinessName.trim();
    return PendingIdRequestSurface(
      count: requests.length,
      businessName: (name == null || name.isEmpty) ? null : name,
    );
  }

  bool get isVisible => count > 0;

  String get title {
    if (count == 1) {
      final name = businessName;
      return name == null
          ? '신분증 열람 요청이 있어요'
          : '$name에서 신분증 열람을 요청했어요';
    }
    return '처리할 신분증 열람 요청 $count건';
  }

  String get subtitle =>
      count == 1 ? '확인하고 승인 또는 거절해 주세요' : '요청 내용을 확인해 주세요';
}
