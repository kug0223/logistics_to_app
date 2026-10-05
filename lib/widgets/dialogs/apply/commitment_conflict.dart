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
  const CommitmentConflictDecision(this.outcome,
      {this.commitment, this.conflictDate});

  final CommitmentConflictOutcome outcome;

  /// 충돌을 만든 약속. `conflict` 일 때만 있다.
  final ApplicationModel? commitment;

  /// [R7-APPLICATION-LIFECYCLE.1C.2] 겹치는 **첫 날**(KST). 장기 후보에서만
  /// 채워진다 — 기간 중 어느 날이 문제인지 사용자에게 말할 수 있다.
  final DateTime? conflictDate;

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
      if (coversDay(c, day)) {
        return CommitmentConflictDecision(
            CommitmentConflictOutcome.conflict, commitment: c);
      }
    }
    return CommitmentConflictDecision.none;
  }

  /// 장기 후보 — 사용자가 **실제로 선택한** 기간 × 요일 × 시간대.
  ///
  /// [R7-APPLICATION-LIFECYCLE.1C.2] 판정을 서버
  /// `longTermConflictDay` 와 같은 두 축으로 바꿨다. 예전에는 "기간 교집합 +
  /// 요일 교집합" 만 봐서
  ///   · 승인된 **추가근무** 날의 겹침을 놓쳤고(서버는 거부한다)
  ///   · 승인된 **휴무** 로 비워진 날을 여전히 약속이라고 봤다(과잉 차단)
  ///
  /// 기간 전체를 하루씩 훑지 않는다.
  ///   ① 공통 근무요일 — 교집합 안의 그 요일 날짜는 **휴무가 아니면** 둘 다
  ///      근무다. 실패는 휴무로만 생기므로 `휴무 수 + 1` 개만 보면 결정된다.
  ///   ② 추가근무 날짜 — 약속 쪽 배열(유한)만 확인한다. 공통 요일이 아니어도
  ///      이쪽에서 잡힌다. (신규 후보에는 추가근무·휴무가 없다.)
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
    if (startTime.isEmpty || endTime.isEmpty || workDays.isEmpty) {
      // 후보의 시간·요일을 아직 모르면 겹침을 말할 수 없다.
      return CommitmentConflictDecision.unknown;
    }
    final newStart = FormatHelper.toKstDate(startDate);
    final newEnd = endDate == null ? null : FormatHelper.toKstDate(endDate);

    for (final c in commitments) {
      if (!ApplicationModel.hasTimeOverlap(
          startTime, endTime, c.startTime, c.endTime)) {
        continue;
      }
      if (!c.isLongTermApplication) {
        // 장기 후보 ↔ 단기 약속 — 그 하루가 내 기간 안이고 내 근무요일이면 충돌.
        final cDay = FormatHelper.toKstDate(c.workDate);
        if (cDay.isBefore(newStart)) continue;
        if (newEnd != null && cDay.isAfter(newEnd)) continue;
        if (!workDays.contains(FormatHelper.weekday(cDay))) continue;
        return CommitmentConflictDecision(
            CommitmentConflictOutcome.conflict, commitment: c);
      }

      final hit = _longTermClashDay(
        commitment: c,
        candStart: newStart,
        candEnd: newEnd,
        candWorkDays: workDays,
      );
      if (hit != null) {
        return CommitmentConflictDecision(
            CommitmentConflictOutcome.conflict,
            commitment: c, conflictDate: hit);
      }
    }
    return CommitmentConflictDecision.none;
  }

  /// 장기 약속과 장기 후보가 실제로 같은 날 겹치는 **첫 날**. 없으면 null.
  static DateTime? _longTermClashDay({
    required ApplicationModel commitment,
    required DateTime candStart,
    required DateTime? candEnd,
    required List<String> candWorkDays,
  }) {
    final cStart = FormatHelper.toKstDate(
        commitment.desiredStartDate ?? commitment.workDate);
    final cEndRaw = commitment.effectiveEndDate;
    final cEnd = cEndRaw == null ? null : FormatHelper.toKstDate(cEndRaw);

    // 교집합 — 종료를 모르는 쪽은 열린 구간으로 본다.
    final lo = candStart.isAfter(cStart) ? candStart : cStart;
    DateTime? hi;
    if (candEnd != null && cEnd != null) {
      hi = candEnd.isBefore(cEnd) ? candEnd : cEnd;
    } else {
      hi = candEnd ?? cEnd;
    }
    if (hi != null && lo.isAfter(hi)) return null;

    bool bothOn(DateTime day) =>
        coversDay(commitment, day) &&
        candWorkDays.contains(FormatHelper.weekday(day));

    // ① 공통 근무요일 — 실패는 휴무로만 생기므로 `휴무 수 + 1` 로 상계된다.
    final cDays = commitment.workDays ?? const <String>[];
    final common = candWorkDays.where(cDays.contains).toList();
    if (common.isNotEmpty) {
      final budget = (commitment.leaveDates?.length ?? 0) + 1;
      // 종료를 모르면 상계만큼의 공통 요일을 보기 위해 넉넉히 둔다.
      final scanEnd = hi ?? lo.add(Duration(days: 7 * (budget + 1)));
      var seen = 0;
      for (var d = lo;
          !d.isAfter(scanEnd) && seen < budget;
          d = d.add(const Duration(days: 1))) {
        if (!common.contains(FormatHelper.weekday(d))) continue;
        seen++;
        if (bothOn(d)) return d;
      }
    }

    // ② 약속 쪽 추가근무 날짜 — 공통 요일이 아니어도 그 날은 근무다.
    final extras = [...?commitment.extraWorkDates]
        .map(FormatHelper.toKstDate)
        .toList()
      ..sort();
    for (final d in extras) {
      if (d.isBefore(lo)) continue;
      if (hi != null && d.isAfter(hi)) continue;
      if (bothOn(d)) return d;
    }
    return null;
  }

  /// 이 약속이 [day] 에 그 시간대를 차지하는가.
  ///
  /// [R7-APPLICATION-LIFECYCLE.1C.2] 판정을 **canonical 근무일 소유자**
  /// (`ApplicationModel.isWorkingOnDate`)에 위임한다 — 서버
  /// `longTermEligibleOnDay` 와 같은 규칙이다(희망 시작일, 희망일이 없을 때의
  /// 확정일 보정, 퇴사일, 추가근무·휴무, KST). 예전에는 이 자리에 구간·요일만
  /// 보는 식을 따로 적어 두었고, 그래서 승인된 추가근무·휴무를 보지 못했다.
  static bool coversDay(ApplicationModel commitment, DateTime day) {
    final d = FormatHelper.toKstDate(day);
    if (commitment.isWorkingOnDate(d)) return true;
    // 종료일을 **모르는** 약속은 끝났다고 단정하지 않는다 — 겹침 판정에서는
    //   열린 구간으로 본다(서버 `longTermCommitmentOnDay` 와 같은 방어).
    //   근무일 판정은 그대로 `false` 다 — 모르는 것으로 출근·급여를 만들지
    //   않는 쪽이 canonical 이고, 이 보정은 겹침 질문에만 쓴다.
    if (!commitment.isLongTermApplication) return false;
    if (commitment.effectiveEndDate != null) return false;
    return commitment
        .copyWith(workEndDate: DateTime.utc(9999, 12, 31))
        .isWorkingOnDate(d);
  }
}
