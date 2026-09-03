import 'package:flutter/material.dart';

/// 탭 전환 인터페이스 — InheritedWidget 패턴
///
/// UserRootScreen이 제공하고, 하위 위젯(UserHomeScreen 등)이 소비한다.
/// 순환 import 없이 홈 탭 → 일자리/일정/MY 탭 전환이 가능하다.
///
/// 사용 예:
/// ```dart
/// // 일반 탭 전환
/// UserTabScope.of(context)?.switchToTab(1);
///
/// // 날짜를 지정하여 일자리 탭으로 이동 (홈 CTA 버튼용)
/// UserTabScope.of(context)?.switchToTabWithDate(1, selectedDate);
///
/// // 일정 탭으로 이동하며 현재 달로 리셋 (홈 "근무 기록 보기" 버튼용)
/// UserTabScope.of(context)?.switchToScheduleNow();
/// ```
class UserTabScope extends InheritedWidget {
  /// 일반 탭 전환 (날짜 전달 없음).
  /// BottomNavigationBar.onTap 및 날짜 미지정 이동에 사용.
  final void Function(int index) switchToTab;

  /// 날짜를 지정하여 일자리 탭(index=1)으로 이동.
  /// 홈의 날짜 선택 CTA 버튼에서만 호출한다.
  /// 전달된 날짜는 [pendingJobDate]로 노출되고,
  /// UserJobTab이 소비(clearPendingJobDate 호출)하면 null이 된다.
  final void Function(int index, DateTime date) switchToTabWithDate;

  /// 홈에서 전달된 대기 중인 날짜 필터.
  /// null = 미설정(일반 탭 전환) / non-null = 홈 CTA 경유 진입.
  /// UserJobTab은 이 값을 읽어 _filter.dateRange에 적용한 뒤
  /// [clearPendingJobDate]를 호출해 null로 초기화한다.
  final DateTime? pendingJobDate;

  /// UserJobTab이 pendingJobDate를 소비한 후 호출.
  /// 이후 재진입 시 날짜 필터가 재적용되지 않도록 root 상태를 초기화.
  final VoidCallback clearPendingJobDate;

  /// 홈 "근무 기록 보기" → 일정 탭 이동 + 현재 달 리셋 요청.
  /// null = 미설정 / non-null = 홈 경유 진입 (항상 DateTime.now()).
  /// MyScheduleScreen이 소비([clearPendingScheduleMonth] 호출)하면 null이 된다.
  final DateTime? pendingScheduleMonth;

  /// MyScheduleScreen이 pendingScheduleMonth를 소비한 후 호출.
  final VoidCallback clearPendingScheduleMonth;

  /// 일정 탭(index=2)으로 전환하며 현재 달로 리셋을 요청한다.
  /// 홈의 "근무 기록 보기" 버튼에서만 호출한다.
  final VoidCallback switchToScheduleNow;

  const UserTabScope({
    super.key,
    required this.switchToTab,
    required this.switchToTabWithDate,
    required this.pendingJobDate,
    required this.clearPendingJobDate,
    required this.pendingScheduleMonth,
    required this.clearPendingScheduleMonth,
    required this.switchToScheduleNow,
    required super.child,
  });

  /// 가장 가까운 UserTabScope를 찾는다. 없으면 null 반환.
  static UserTabScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserTabScope>();

  @override
  bool updateShouldNotify(UserTabScope oldWidget) =>
      switchToTab != oldWidget.switchToTab ||
      pendingJobDate != oldWidget.pendingJobDate ||
      pendingScheduleMonth != oldWidget.pendingScheduleMonth;
}
