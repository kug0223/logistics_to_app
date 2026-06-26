// lib/utils/payment_due_date_calculator.dart
//
// 지급 예정일(paymentDueDate) 계산 유틸리티
//
// payScheduleType별 계산 규칙:
//   same_day  → 근무일 당일
//   next_day  → 근무일 + 1일
//   weekly    → 근무일이 속한 주의 payScheduleDay(요일)
//   monthly   → 근무일이 속한 달의 payScheduleDay(일)
//
// 주의: 지급일이 과거가 되는 경우(주급/월급에서 이미 지난 날)
//       → 다음 주기의 지급일로 자동 이월

class PaymentDueDateCalculator {
  /// payScheduleType + payScheduleDay + workDate → 지급 예정일 계산
  /// 반환: 날짜만 (시분초 0), null이면 계산 불가(payScheduleType 미설정)
  static DateTime? calculate({
    required String? payScheduleType,
    required int? payScheduleDay,
    required DateTime workDate,
  }) {
    final base = DateTime(workDate.year, workDate.month, workDate.day);

    switch (payScheduleType) {
      case 'same_day':
        return base;

      case 'next_day':
        return base.add(const Duration(days: 1));

      case 'weekly':
        // payScheduleDay: 1=월, 2=화, ..., 7=일
        final targetWeekday = payScheduleDay?.clamp(1, 7) ?? 5; // 기본 금요일
        return _nextWeekday(base, targetWeekday);

      case 'monthly':
        // payScheduleDay: 1~31 (말일 이상이면 해당 월 말일)
        final targetDay = payScheduleDay?.clamp(1, 31) ?? 25; // 기본 25일
        return _nextMonthlyDay(base, targetDay);

      default:
        return null; // payScheduleType 미설정 = null
    }
  }

  /// 오늘이 paymentDueDate인지 확인 (지급일 도래 여부)
  static bool isDueToday(DateTime? paymentDueDate) {
    if (paymentDueDate == null) return false;
    final today = DateTime.now();
    return paymentDueDate.year  == today.year &&
           paymentDueDate.month == today.month &&
           paymentDueDate.day   == today.day;
  }

  /// 오늘 기준 지급 예정일이 오늘 이하인지 (지나쳤거나 당일)
  static bool isDueOnOrBefore(DateTime? paymentDueDate, {DateTime? reference}) {
    if (paymentDueDate == null) return false;
    final ref = reference ?? DateTime.now();
    final refDate = DateTime(ref.year, ref.month, ref.day);
    final dueDate = DateTime(
        paymentDueDate.year, paymentDueDate.month, paymentDueDate.day);
    return !dueDate.isAfter(refDate);
  }

  // ─── 내부 헬퍼 ─────────────────────────────────────────────────

  /// 해당 주 또는 다음 주의 목표 요일 날짜 반환
  /// workDate가 이미 그 요일이면 당일 반환
  static DateTime _nextWeekday(DateTime from, int targetWeekday) {
    // Dart weekday: 1=월 ... 7=일
    final diff = (targetWeekday - from.weekday) % 7;
    return from.add(Duration(days: diff));
  }

  /// 해당 월 또는 다음 달의 목표 일자 반환
  /// 해당 월에 targetDay가 없으면(ex: 2월 30일) 말일로 클램프
  static DateTime _nextMonthlyDay(DateTime from, int targetDay) {
    // 이번 달 가능 여부 확인
    final lastDayOfMonth = _lastDayOf(from.year, from.month);
    final clampedDay = targetDay.clamp(1, lastDayOfMonth);
    final thisMonthDue = DateTime(from.year, from.month, clampedDay);

    if (!thisMonthDue.isBefore(from)) {
      return thisMonthDue; // 아직 지급일 안 지남 → 이번 달
    }

    // 이번 달 지급일 이미 지남 → 다음 달
    final nextMonth = from.month == 12
        ? DateTime(from.year + 1, 1, 1)
        : DateTime(from.year, from.month + 1, 1);
    final lastDayOfNext = _lastDayOf(nextMonth.year, nextMonth.month);
    final nextDay = targetDay.clamp(1, lastDayOfNext);
    return DateTime(nextMonth.year, nextMonth.month, nextDay);
  }

  // DateTime(y, month+1, 0) — Dart가 월 오버플로우(13월→1월)를 자동 처리; day=0은 전달 마지막 날
  static int _lastDayOf(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// payScheduleType 한국어 라벨
  static String label(String? type) {
    switch (type) {
      case 'same_day': return '당일';
      case 'next_day': return '익일';
      case 'weekly':   return '주급';
      case 'monthly':  return '월급';
      default:         return '미설정';
    }
  }

  /// 지급일 그룹 정렬 순서 (당일 > 익일 > 주급 > 월급 > 미설정)
  static int sortOrder(String? type) {
    switch (type) {
      case 'same_day': return 0;
      case 'next_day': return 1;
      case 'weekly':   return 2;
      case 'monthly':  return 3;
      default:         return 4;
    }
  }
}
