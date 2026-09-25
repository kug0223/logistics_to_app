import '../core/application_model.dart';

/// 근로자 홈의 **계약해지 응답** 진입점 상태.
///
/// 관리자가 계약해지를 요청하면 실제로 응답해야 하는 사람은 근로자다.
/// 그런데 홈에는 그 일이 할 일로 존재하지 않고 알림 하나가 유일한 경로였다.
/// 알림을 읽거나 지우면 길이 사라지는데, 요청은 D+3 에 자동 승인된다 —
/// 자기 고용이 끝나는 일에 대한 동의 경로가 알림 수명에 묶여 있었다.
///
/// `Notification ≠ Task`: 이 표면은 알림이 아니라 canonical 도메인 상태
/// (`applications.terminationStatus == 'PENDING'`) 에서만 파생된다.
/// 알림을 읽든 지우든 이 값은 변하지 않는다.
///
/// 신분증 열람 요청(`PendingIdRequestSurface`)과 **합치지 않는다.**
/// 신분증 정보 제공 동의와 고용 종료 동의는 같은 종류의 사건이 아니다.
///
/// 홈은 discovery surface 만 담당한다 — 승인·거절 자체는 기존
/// MyRequestsDialog 가 처리한다.
class PendingTerminationSurface {
  /// 응답 대기 중인 계약해지 요청 수.
  final int count;

  /// 1건일 때만 쓰는 사업장명. 여러 건이면 null (홈에서 묶지 않는다).
  final String? businessName;

  /// 1건일 때의 지원서 id — 목적지에서 정확히 그 요청으로 보낸다.
  final String? applicationId;

  /// 조회가 성공했는가.
  ///
  /// false 는 "요청이 없다"가 아니라 **"확인하지 못했다"**다.
  /// `ERROR ≠ EMPTY` — 조회 실패를 0건으로 접으면, 응답하지 않으면
  /// 자동 승인되는 요청이 조용히 사라진다.
  final bool available;

  const PendingTerminationSurface({
    required this.count,
    required this.available,
    this.businessName,
    this.applicationId,
  });

  /// 조회는 성공했고 대기 중인 요청이 없는 상태.
  static const PendingTerminationSurface none =
      PendingTerminationSurface(count: 0, available: true);

  /// 조회하지 못한 상태. 0건과 구분된다.
  static const PendingTerminationSurface unavailable =
      PendingTerminationSurface(count: 0, available: false);

  /// 근로자의 지원서 목록에서 파생.
  ///
  /// PENDING 만 센다. APPROVED / AUTO_APPROVED / REJECTED / CANCELED 로
  /// 넘어간 요청은 더 이상 응답할 것이 없으므로 자동으로 빠진다.
  factory PendingTerminationSurface.from(
    List<ApplicationModel> applications, {
    required bool available,
  }) {
    if (!available) return unavailable;
    final pending = applications
        .where((a) => a.terminationStatus == AppStatus.pending)
        .toList();
    if (pending.isEmpty) return none;
    final single = pending.length == 1 ? pending.first : null;
    final name = single?.businessName.trim();
    return PendingTerminationSurface(
      count: pending.length,
      available: true,
      businessName: (name == null || name.isEmpty) ? null : name,
      applicationId: single?.id,
    );
  }

  bool get isVisible => available && count > 0;

  /// 확인하지 못했다는 사실을 말해야 하는 상태.
  bool get isUnavailable => !available;

  String get title {
    if (count == 1) {
      final name = businessName;
      return name == null
          ? '계약해지 요청을 확인해 주세요'
          : '$name에서 계약해지를 요청했어요';
    }
    return '응답이 필요한 계약해지 요청 $count건';
  }

  String get subtitle => count == 1
      ? '확인하고 동의 또는 거절해 주세요'
      : '각 요청을 확인해 주세요';
}
