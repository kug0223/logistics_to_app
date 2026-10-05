// lib/widgets/dialogs/apply/commitment_conflict.dart
//
// [R7-APPLICATION-LIFECYCLE.1C] 이미 성립한 **약속**과 후보 근무의 시간 충돌 —
// 판정의 단일 소유자.
//
// 왜 필요했나
//   서버 `callableApplyToTO` 는 같은 시간에 이미 약속(CONFIRMED ·
//   CONTRACT_PENDING)이 있으면 신규 지원을 **결정적으로 거부**한다.
//   그런데 그 사실을 아는 화면이 제각각이었다.
//     · 홈 `HomeRecruitableProjection`  : 약속을 **보지 않는다** →
//       `지원 가능한 일자리 N개` 가 지원할 수 없는 공고를 세고 있었다
//     · 공고 상세 `job_posting_screen`  : 약속을 **보지 않는다** →
//       겹치는 업무에도 `선택` 을 그리고 CTA 수치에 셌다
//     · 일자리 카드 `UserTOCard`        : `지원하기` 라고 말한다
//     · 지원 시트 `ApplyWorkDialog` / `MultiApplyConfirmSheet` : 막는다
//   즉 **같은 사건을 reader 들이 writer 와 다르게** 말했다. 사용자는
//   불가능한 action 을 명시적으로 가능하다고 광고받고, 눌러서 서버 오류로
//   알게 된다.
//
// 무엇을 바꿨나
//   화면마다 충돌 함수를 만들지 않는다. 판정은 여기 한 곳이고, 각 화면은
//   **이미 읽고 있던** 내 지원 목록을 입력으로 넘긴다(새 쿼리·listener 0).
//
// 보이는 것과 지원할 수 있는 것은 다르다
//   충돌 때문에 공고를 숨기지 않는다. 발견은 유지하고 **그 관계만**
//   지원 불가로 말한다. 한 날짜·한 업무가 겹친다고 다른 날짜·다른 업무가
//   사라지면 그것은 또 다른 거짓이다.
//
// 서버가 최종 권위다
//   여기 판정은 UX projection 이다. `callableApplyToTO` 의 서버 guard 는
//   그대로 남는다 — dialog 를 열어 둔 사이에 새 약속이 생기는 경쟁은
//   서버가 거부한다.
import '../../../models/core/application_model.dart';
import '../../../utils/format_helper.dart';

/// 약속 충돌 판정 결과.
enum CommitmentConflictOutcome {
  /// 겹치는 약속이 없다 — 신규 지원 후보다.
  none,

  /// 겹치는 약속이 있다 — 서버가 거부한다.
  conflict,

  /// **판단할 수 없다.** 내 지원 목록을 읽지 못했다.
  ///
  /// `none` 으로 바꾸지 않는다 — 못 읽은 것을 "겹치는 약속이 없다" 로
  /// 바꾸면 모든 공고가 지원 가능하다고 광고된다. 반대로 `conflict` 로도
  /// 바꾸지 않는다 — 읽기 실패 때문에 전부 지원 불가가 되면 그것도 거짓이다.
  /// 각 화면이 자신의 state taxonomy(ERROR/PARTIAL)로 말한다.
  unknown,
}

/// 한 후보 근무에 대한 판정과 **그 판정을 만든 약속**.
class CommitmentConflictDecision {
  const CommitmentConflictDecision(this.outcome, {this.commitment});

  final CommitmentConflictOutcome outcome;

  /// 충돌을 만든 약속. `conflict` 일 때만 있다.
  final ApplicationModel? commitment;

  static const CommitmentConflictDecision none =
      CommitmentConflictDecision(CommitmentConflictOutcome.none);
  static const CommitmentConflictDecision unknown =
      CommitmentConflictDecision(CommitmentConflictOutcome.unknown);

  bool get blocksNewApplication =>
      outcome == CommitmentConflictOutcome.conflict;

  bool get isUnknown => outcome == CommitmentConflictOutcome.unknown;

  /// 충돌 시간대 — `09:00~18:00`. 이유 문구에 쓴다.
  String? get conflictTime {
    final c = commitment;
    if (c == null) return null;
    if (c.startTime.isEmpty || c.endTime.isEmpty) return null;
    return '${c.startTime}~${c.endTime}';
  }

  /// 충돌한 약속의 사업장 — 근로자 **자신의** 일정이다.
  String? get conflictBusinessName {
    final n = commitment?.businessName;
    return (n == null || n.isEmpty) ? null : n;
  }
}

/// 약속 충돌 판정.
///
/// 입력은 순수하다 — 쿼리하지 않는다. 호출자가 이미 들고 있는 내 지원
/// 목록을 넘긴다.
class CommitmentConflictResolver {
  const CommitmentConflictResolver._();

  /// 지원 목록에서 **약속만** 골라낸다.
  ///
  /// 약속은 `CONFIRMED` 와 `CONTRACT_PENDING` 둘이다(`AppStatus
  /// .confirmedStatuses`). 서버 `callableApplyToTO` 의 `confirmedStatuses`
  /// 와 같은 집합이다.
  ///
  /// `PENDING` · `INVITED` 는 약속이 **아니다** — ALfit 정책에서 지원은
  /// 관심이고, 관심끼리는 겹칠 수 있다. 여기서 막으면 정책 위반이다.
  /// `CANCELED` · `AUTO_CANCELED` · `REJECTED` · `EXPIRED` 도 아니다 —
  /// 서버가 재지원을 허용하는 상태다.
  static List<ApplicationModel> commitmentsOf(List<ApplicationModel> apps) =>
      apps
          .where((a) => AppStatus.confirmedStatuses.contains(a.status))
          .toList(growable: false);

  /// 단기 후보 — 날짜 하나 × 시간대 하나.
  static CommitmentConflictDecision forShortTerm({
    required List<ApplicationModel> commitments,
    required DateTime workDate,
    required String startTime,
    required String endTime,
    bool commitmentsKnown = true,
  }) {
    if (!commitmentsKnown) return CommitmentConflictDecision.unknown;
    if (startTime.isEmpty || endTime.isEmpty) {
      // 후보의 시간을 모르면 겹침을 말할 수 없다.
      return CommitmentConflictDecision.unknown;
    }
    final day = FormatHelper.toKstDate(workDate);
    for (final c in commitments) {
      if (!ApplicationModel.hasTimeOverlap(
          startTime, endTime, c.startTime, c.endTime)) {
        continue;
      }
      if (_commitmentCoversDay(c, day)) {
        return CommitmentConflictDecision(
            CommitmentConflictOutcome.conflict, commitment: c);
      }
    }
    return CommitmentConflictDecision.none;
  }

  /// 장기 후보 — 기간 × 요일 × 시간대.
  ///
  /// [endDate] 가 `null` 이면 **종료를 모른다** — 서버와 같이 무한으로 본다
  /// (서버: `new Date(9999, 11, 31)`).
  static CommitmentConflictDecision forLongTerm({
    required List<ApplicationModel> commitments,
    required DateTime startDate,
    required DateTime? endDate,
    required List<String> workDays,
    required String startTime,
    required String endTime,
    bool commitmentsKnown = true,
  }) {
    if (!commitmentsKnown) return CommitmentConflictDecision.unknown;
    if (startTime.isEmpty || endTime.isEmpty) {
      return CommitmentConflictDecision.unknown;
    }
    final newStart = FormatHelper.toKstDate(startDate);
    final newEnd = endDate == null ? null : FormatHelper.toKstDate(endDate);

    for (final c in commitments) {
      if (!ApplicationModel.hasTimeOverlap(
          startTime, endTime, c.startTime, c.endTime)) {
        continue;
      }
      if (c.isLongTermApplication) {
        // 장기 ↔ 장기 — 기간이 겹치고 **요일이 하나라도** 겹치면 충돌.
        //   기간만 겹쳐도 요일이 서로 다르면 같은 시간에 일하는 날이 없다.
        final cStart = _commitmentStart(c);
        final cEnd = _commitmentEnd(c);
        if (newEnd != null && newEnd.isBefore(cStart)) continue;
        if (cEnd != null && newStart.isAfter(cEnd)) continue;
        final cDays = c.workDays ?? const <String>[];
        if (cDays.isEmpty || workDays.isEmpty) continue;
        if (!workDays.any(cDays.contains)) continue;
        return CommitmentConflictDecision(
            CommitmentConflictOutcome.conflict, commitment: c);
      }

      // 장기 후보 ↔ 단기 약속 — 그 하루가 내 기간 안이고 내 근무요일이면 충돌.
      final cDay = FormatHelper.toKstDate(c.workDate);
      if (cDay.isBefore(newStart)) continue;
      if (newEnd != null && cDay.isAfter(newEnd)) continue;
      if (workDays.isNotEmpty &&
          !workDays.contains(FormatHelper.weekday(cDay))) {
        continue;
      }
      return CommitmentConflictDecision(
          CommitmentConflictOutcome.conflict, commitment: c);
    }
    return CommitmentConflictDecision.none;
  }

  /// 이 약속이 [day] 에 그 시간대를 차지하는가 — 기간·요일을 서버와 같은
  /// 식으로 본다. 날짜 한 곳의 약속 목록이 필요한 자리(인접 경고 등)가 쓴다.
  static bool coversDay(ApplicationModel commitment, DateTime day) =>
      _commitmentCoversDay(commitment, FormatHelper.toKstDate(day));

  /// 이 약속이 [day] 에 그 시간대를 차지하는가.
  static bool _commitmentCoversDay(ApplicationModel c, DateTime day) {
    if (!c.isLongTermApplication) {
      return FormatHelper.toKstDate(c.workDate) == day;
    }
    final start = _commitmentStart(c);
    final end = _commitmentEnd(c);
    if (day.isBefore(start)) return false;
    if (end != null && day.isAfter(end)) return false;
    final days = c.workDays ?? const <String>[];
    // 요일을 모르는 약속은 어떤 날도 차지한다고 말하지 않는다 —
    //   서버도 `appWorkDays.includes(weekday)` 가 false 면 넘어간다.
    if (days.isEmpty) return false;
    return days.contains(FormatHelper.weekday(day));
  }

  /// 약속의 시작일.
  ///
  /// 서버는 두 자리에서 서로 다르게 읽는다 — `callableApplyToTO` 는
  /// `workDate` 를, 공용 좌석 엔진은 `desiredStartDate ?? workDate` 를 본다.
  /// 둘 중 **이른 쪽**을 쓴다. 어느 서버 경로가 거부하든 화면이 먼저
  /// 지원 불가로 말해야 하고, 늦은 쪽을 쓰면 `callableApplyToTO` 가
  /// 거부하는 관계를 화면이 "지원 가능" 이라고 광고한다.
  static DateTime _commitmentStart(ApplicationModel c) {
    final anchor = FormatHelper.toKstDate(c.workDate);
    final desired = c.desiredStartDate;
    if (desired == null) return anchor;
    final d = FormatHelper.toKstDate(desired);
    return d.isBefore(anchor) ? d : anchor;
  }

  /// 약속의 마지막 근무일. `null` = 모름(무한).
  static DateTime? _commitmentEnd(ApplicationModel c) {
    final end = c.effectiveEndDate;
    return end == null ? null : FormatHelper.toKstDate(end);
  }
}
