import 'dart:math' show max;

import 'package:flutter/material.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// ⚡ 출퇴근 빠른 시간 선택 바텀시트
///
/// 출근/퇴근 처리 전용.
/// - 예정 시간 칩 (TO startTime/endTime 기반, 선택적)
/// - 현재 시각 칩 (10분 단위 반올림, 기본 선택)
/// - ±10분 버튼으로 미세 조정
/// - 확인 버튼에 선택 시간 실시간 표시
///
/// 시간 수정(기록 수정)은 기존 [TimePickerBottomSheet] 사용.
class AttendanceQuickTimeSheet extends StatefulWidget {
  final String title;

  /// 예정 시간 목록 (HH:mm 형식).
  /// 개별 처리: 1개 (해당 업무의 startTime/endTime)
  /// 일괄 처리: 선택된 직원들의 고유 시간 목록 (여러 업무 섞인 경우 복수 칩)
  final List<String>? scheduledTimes;

  final bool isCheckIn; // true: 출근, false: 퇴근 (색상·아이콘 결정)

  const AttendanceQuickTimeSheet({
    super.key,
    required this.title,
    this.scheduledTimes,
    this.isCheckIn = true,
  });

  static Future<String?> show({
    required BuildContext context,
    required String title,
    List<String>? scheduledTimes,
    bool isCheckIn = true,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AttendanceQuickTimeSheet(
        title: title,
        scheduledTimes: scheduledTimes,
        isCheckIn: isCheckIn,
      ),
    );
  }

  @override
  State<AttendanceQuickTimeSheet> createState() => _AttendanceQuickTimeSheetState();
}

class _AttendanceQuickTimeSheetState extends State<AttendanceQuickTimeSheet> {
  late int _hour;
  late int _minute;

  // 현재 시각을 10분 단위로 반올림
  static ({int hour, int minute}) _roundedNow() {
    final now = DateTime.now();
    final roundedStep = (now.minute / 10).round();
    if (roundedStep >= 6) {
      return (hour: (now.hour + 1) % 24, minute: 0);
    }
    return (hour: now.hour, minute: roundedStep * 10);
  }

  // 예정 시간 목록 파싱 (HH:mm → (hour, minute)) — 중복 제거, 정렬
  List<({int hour, int minute})> get _scheduledList {
    final times = widget.scheduledTimes;
    if (times == null || times.isEmpty) return [];
    final seen = <String>{};
    final result = <({int hour, int minute})>[];
    for (final t in times) {
      if (!seen.add(t)) continue;
      try {
        final parts = t.split(':');
        result.add((hour: int.parse(parts[0]), minute: int.parse(parts[1])));
      // 잘못된 형식의 시간 문자열은 조용히 건너뜀 — 파싱 불가 항목 제외
      } catch (_) {}
    }
    result.sort((a, b) => a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute));
    return result;
  }

  @override
  void initState() {
    super.initState();
    final now = _roundedNow();
    _hour = now.hour;
    _minute = now.minute;
  }

  String get _timeString => FormatHelper.formatHourMinute(_hour, _minute);

  void _adjustMinutes(int delta) {
    setState(() {
      // 24시간 순환 — 23:50 + 10분 = 00:00, 00:00 - 10분 = 23:50
      final total = ((_hour * 60 + _minute + delta) % (24 * 60) + 24 * 60) % (24 * 60);
      _hour = total ~/ 60;
      _minute = (total % 60) ~/ 10 * 10; // 10분 단위 유지
    });
  }

  void _select(int hour, int minute) => setState(() {
        _hour = hour;
        _minute = minute;
      });

  bool _isSelected(int hour, int minute) => _hour == hour && _minute == minute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _roundedNow();
    final scheduledList = _scheduledList;
    final isCheckIn = widget.isCheckIn;
    final actionLabel = isCheckIn ? '출근' : '퇴근';
    final actionIcon = isCheckIn ? Icons.login : Icons.logout;
    final actionColor = isCheckIn ? AppColors.success : AppColors.purple;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 16),
          0,
          ResponsiveHelper.spacing(context, 16),
          // edge-to-edge 대응: viewPaddingOf는 SafeArea 소비 무관 물리적 인셋.
          // max로 SafeArea 정상 동작 시 이중 합산 방지.
          max(
            ResponsiveHelper.spacing(context, 20),
            MediaQuery.viewPaddingOf(context).bottom,
          ),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 핸들바
              Center(
                child: Container(
                  margin: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 헤더
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                    decoration: BoxDecoration(
                      color: actionColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      actionIcon,
                      color: actionColor,
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: ResponsiveHelper.subtitleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // 선택 시간 표시 카드
              Container(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 14),
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      actionColor.withValues(alpha: 0.12),
                      actionColor.withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: actionColor.withValues(alpha: 0.25)),
                ),
                child: Center(
                  child: Text(
                    _timeString,
                    style: ResponsiveHelper.titleStyle(context).copyWith(
                      color: actionColor,
                      fontWeight: FontWeight.bold,
                      fontSize: ResponsiveHelper.getFontSize(context, 34),
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // 빠른 선택 칩
              Text(
                '빠른 선택',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textSecondary),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 8),
                children: [
                  // 예정 시간 칩 (업무별 고유 시간 목록)
                  ...scheduledList.map((s) => _buildChip(
                    context: context,
                    label: '예정  ${FormatHelper.formatHourMinute(s.hour, s.minute)}',
                    hour: s.hour,
                    minute: s.minute,
                    actionColor: actionColor,
                  )),
                  // 현재 시각 칩
                  _buildChip(
                    context: context,
                    label: '현재  ${FormatHelper.formatHourMinute(now.hour, now.minute)}',
                    hour: now.hour,
                    minute: now.minute,
                    actionColor: actionColor,
                  ),
                ],
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // ±10분 조정 바
              Container(
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // -10분 버튼
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _adjustMinutes(-10),
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(12)),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(context, 14)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.remove,
                                      size: ResponsiveHelper.iconSize(context, 16),
                                      color: AppColors.grey700),
                                  SizedBox(
                                      width: ResponsiveHelper.spacing(context, 4)),
                                  Text(
                                    '10분',
                                    style: ResponsiveHelper.smallStyle(context,
                                            color: AppColors.grey700)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 구분선
                      VerticalDivider(
                          width: 1, thickness: 1, color: AppColors.border),

                      // 현재 선택 시간
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Text(
                            _timeString,
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      ),

                      // 구분선
                      VerticalDivider(
                          width: 1, thickness: 1, color: AppColors.border),

                      // +10분 버튼
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _adjustMinutes(10),
                            borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(12)),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(context, 14)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '10분',
                                    style: ResponsiveHelper.smallStyle(context,
                                            color: AppColors.grey700)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(
                                      width: ResponsiveHelper.spacing(context, 4)),
                                  Icon(Icons.add,
                                      size: ResponsiveHelper.iconSize(context, 16),
                                      color: AppColors.grey700),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 20)),

              // 취소 / 처리 버튼
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14)),
                        side: BorderSide(color: AppColors.grey300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        '취소',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: AppColors.grey700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _timeString),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: actionColor,
                        foregroundColor: AppColors.surface,
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        '$_timeString 로 $actionLabel 처리',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: AppColors.surface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required int hour,
    required int minute,
    required Color actionColor,
  }) {
    final selected = _isSelected(hour, minute);
    return Material(
      color: selected ? actionColor : AppColors.grey100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _select(hour, minute),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 9),
          ),
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: selected ? AppColors.surface : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
