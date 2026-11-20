import 'format_helper.dart';

/// 대기 중 퇴사 요청이 지금 어떤 처리 일정에 있는가.
enum ResignAutoApprovalKind {
  /// 정상 요청 — 요청일(KST) + 3일의 자정에 서버가 자동 승인한다.
  scheduled,

  /// 소급 요청 — 서버가 자동 승인하지 않는다. 관리자가 직접 승인·거절한다.
  manualReview,

  /// 정상 요청인데 자동 승인 예정 자정이 지났는데도 아직 대기 중.
  overdue,

  /// 요청 시각을 모른다 — 일정을 말하지 않는다.
  unknown,
}

/// [D3-RETRO-EXCLUDE] 퇴사 요청 자동 승인 일정 — 서버와 같은 식.
///
///   소급 = 희망일(KST 일) < 요청 시각(KST 일). 서버 `srvIsRetroResignRequest` 와 같다.
///   정상 요청은 masterScheduler 가 `resignRequestedAt <= (오늘 KST 자정 − 3일)` 일 때
///   승인한다 → 요청일 R 의 요청은 R+3 이 끝나는 자정에 승인된다.
///   그래서 R+3 = "오늘 자정", 그 뒤에도 대기면 [ResignAutoApprovalKind.overdue] 다.
///   지난 일정을 다시 약속하거나 음수 일수를 보여 주지 않는다.
class ResignAutoApproval {
  final ResignAutoApprovalKind kind;

  /// [ResignAutoApprovalKind.scheduled] 에서만 의미가 있다. 0 = 오늘 자정.
  final int daysLeft;

  /// 자동 승인 예정 KST 날짜(이 날이 끝나는 자정에 승인). 비교 키([FormatHelper.toKstDate]).
  final DateTime? dueKstDay;

  const ResignAutoApproval._(this.kind, this.daysLeft, this.dueKstDay);

  static bool isRetro({DateTime? requestedAt, DateTime? requestDate}) {
    if (requestedAt == null || requestDate == null) return false;
    return FormatHelper.toKstDate(requestDate)
        .isBefore(FormatHelper.toKstDate(requestedAt));
  }

  factory ResignAutoApproval.of({
    required DateTime? requestedAt,
    required DateTime? requestDate,
    required DateTime now,
  }) {
    if (requestedAt == null) {
      return const ResignAutoApproval._(ResignAutoApprovalKind.unknown, 0, null);
    }
    if (isRetro(requestedAt: requestedAt, requestDate: requestDate)) {
      return const ResignAutoApproval._(
          ResignAutoApprovalKind.manualReview, 0, null);
    }
    final reqDay = FormatHelper.toKstDate(requestedAt);
    final due = reqDay.add(const Duration(days: 3));
    final left = due.difference(FormatHelper.toKstDate(now)).inDays;
    if (left < 0) {
      return ResignAutoApproval._(ResignAutoApprovalKind.overdue, 0, due);
    }
    return ResignAutoApproval._(ResignAutoApprovalKind.scheduled, left, due);
  }

  /// 'M/d' — [dueKstDay] 는 이미 KST 날짜 키라 다시 변환하지 않는다.
  String get dueLabel =>
      dueKstDay == null ? '' : '${dueKstDay!.month}/${dueKstDay!.day}';

  /// 관리자 퇴사 요청 관리 카드의 일정 줄.
  String get adminCardText => switch (kind) {
        ResignAutoApprovalKind.scheduled =>
          daysLeft > 0 ? '$daysLeft일 후 자동 승인' : '오늘 자정 자동 승인',
        ResignAutoApprovalKind.manualReview => '소급 요청 · 자동 승인 안 됨 · 관리자 검토 대기',
        ResignAutoApprovalKind.overdue => '자동 승인 예정일($dueLabel) 지남 · 아직 대기 중',
        ResignAutoApprovalKind.unknown => '승인 대기 중',
      };

  /// 관리자 고정 근무자 상태 배너의 괄호 안.
  String get adminBannerText => switch (kind) {
        ResignAutoApprovalKind.scheduled =>
          daysLeft > 0 ? '$daysLeft일 후 자동 승인' : '오늘 자동 승인',
        ResignAutoApprovalKind.manualReview => '소급 요청 · 관리자 검토 필요',
        ResignAutoApprovalKind.overdue => '자동 승인 예정일 $dueLabel 지남',
        ResignAutoApprovalKind.unknown => '승인 대기',
      };

  /// 근로자 퇴사 상태 배너의 괄호 안.
  String get workerDetailText => switch (kind) {
        ResignAutoApprovalKind.scheduled =>
          daysLeft > 0 ? '$daysLeft일 후 자동 승인' : '오늘 자정 자동 승인',
        ResignAutoApprovalKind.manualReview => '소급 요청 · 관리자 검토 후 처리',
        ResignAutoApprovalKind.overdue => '자동 승인 예정일 지남 · 처리 대기',
        ResignAutoApprovalKind.unknown => '처리 대기',
      };

  /// 관리자 카드의 긴급 표시 — 자동 승인이 임박했거나 예정이 지났을 때.
  ///   소급 요청은 자동 승인 기한이 없으므로 긴급이 아니다(검토 필요는 문구가 말한다).
  bool get isUrgent => switch (kind) {
        ResignAutoApprovalKind.scheduled => daysLeft <= 1,
        ResignAutoApprovalKind.overdue => true,
        ResignAutoApprovalKind.manualReview || ResignAutoApprovalKind.unknown => false,
      };
}
