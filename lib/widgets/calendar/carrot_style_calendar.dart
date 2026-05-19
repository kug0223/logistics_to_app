import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';

/// 🥕 당근마켓 스타일 월간 캘린더
/// 
/// 재사용 가능한 공통 캘린더 위젯
/// - 단일 날짜 선택
/// - 다중 날짜 선택
/// - 범위 선택 (시작일 ~ 종료일)
/// 
/// 사용 예:
/// ```dart
/// CarrotStyleCalendar(
///   mode: CalendarMode.single,
///   selectedDate: _selectedDate,
///   onDateSelected: (date) => setState(() => _selectedDate = date),
/// )
/// ```
class CarrotStyleCalendar extends StatefulWidget {
  /// 선택 모드
  final CalendarMode mode;
  
  /// 현재 포커스된 월
  final DateTime? focusedMonth;
  
  /// 선택 가능한 최소 날짜
  final DateTime? minDate;
  
  /// 선택 가능한 최대 날짜
  final DateTime? maxDate;
  
  /// 단일 선택 모드용
  final DateTime? selectedDate;
  final void Function(DateTime)? onDateSelected;
  
  /// 다중 선택 모드용
  final List<DateTime>? selectedDates;
  final void Function(DateTime)? onDateToggled;
  final int maxSelectableDays;
  
  /// 범위 선택 모드용
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final void Function(DateTime?, DateTime?)? onRangeChanged;
  
  /// 월 변경 콜백
  final void Function(DateTime)? onMonthChanged;
  
  /// 오늘 이전 날짜 선택 가능 여부
  final bool allowPastDates;

  /// 비활성화할 특정 날짜 목록 (예: 이미 사용된 날짜)
  final List<DateTime>? disabledDates;

  /// 선택 가능한 날짜 판단 함수 (false 반환 시 비활성화)
  final bool Function(DateTime)? enabledDayPredicate;

  /// 헤더 표시 여부
  final bool showHeader;
  
  /// 컴팩트 모드 (작은 사이즈)
  final bool compact;

  const CarrotStyleCalendar({
    super.key,
    this.mode = CalendarMode.single,
    this.focusedMonth,
    this.minDate,
    this.maxDate,
    this.selectedDate,
    this.onDateSelected,
    this.selectedDates,
    this.onDateToggled,
    this.maxSelectableDays = 30,
    this.rangeStart,
    this.rangeEnd,
    this.onRangeChanged,
    this.onMonthChanged,
    this.allowPastDates = false,
    this.disabledDates,
    this.enabledDayPredicate,
    this.showHeader = true,
    this.compact = false,
  });

  @override
  State<CarrotStyleCalendar> createState() => _CarrotStyleCalendarState();
}

class _CarrotStyleCalendarState extends State<CarrotStyleCalendar> {
  late DateTime _focusedMonth;
  DateTime? _rangeStartTemp; // 범위 선택 시 임시 시작점
  
  @override
  void initState() {
    super.initState();
    _focusedMonth = widget.focusedMonth ?? DateTime.now();
  }
  
  @override
  void didUpdateWidget(CarrotStyleCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusedMonth != null && widget.focusedMonth != oldWidget.focusedMonth) {
      _focusedMonth = widget.focusedMonth!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더 (월 네비게이션)
          if (widget.showHeader) _buildHeader(context, theme),
          
          // 요일 헤더
          _buildWeekdayHeader(context),
          
          // 날짜 그리드
          _buildDaysGrid(context, theme),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
      ),
    );
  }

  /// 헤더 (월 네비게이션)
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 이전 월
          _buildNavButton(
            context,
            icon: Icons.chevron_left,
            onTap: _goToPreviousMonth,
          ),
          
          // 현재 월 표시
          GestureDetector(
            onTap: _goToCurrentMonth,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                FormatHelper.formatYearMonth(_focusedMonth),
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ),
          
          // 다음 월
          _buildNavButton(
            context,
            icon: Icons.chevron_right,
            onTap: _goToNextMonth,
          ),
        ],
      ),
    );
  }

  /// 네비게이션 버튼
  Widget _buildNavButton(BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: AppColors.grey100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 24),
          ),
        ),
      ),
    );
  }

  /// 요일 헤더
  Widget _buildWeekdayHeader(BuildContext context) {
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: Row(
        children: weekdays.asMap().entries.map((entry) {
          final index = entry.key;
          final day = entry.value;
          
          Color textColor;
          if (index == 0) {
            textColor = AppColors.error; // 일요일
          } else if (index == 6) {
            textColor = AppColors.info; // 토요일
          } else {
            textColor = AppColors.textSecondary;
          }
          
          return Expanded(
            child: Center(
              child: Text(
                day,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 날짜 그리드
  Widget _buildDaysGrid(BuildContext context, ThemeData theme) {
    final days = _generateDaysInMonth();
    final cellSize = widget.compact 
        ? ResponsiveHelper.spacing(context, 36)
        : ResponsiveHelper.spacing(context, 44);
    
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
      ),
      child: Column(
        children: List.generate(
          (days.length / 7).ceil(),
          (weekIndex) {
            return Row(
              children: List.generate(7, (dayIndex) {
                final index = weekIndex * 7 + dayIndex;
                if (index >= days.length) {
                  return Expanded(child: SizedBox(height: cellSize));
                }
                
                final day = days[index];
                return Expanded(
                  child: _buildDayCell(context, theme, day, cellSize, dayIndex),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  /// 개별 날짜 셀
  Widget _buildDayCell(
    BuildContext context,
    ThemeData theme,
    DateTime? day,
    double cellSize,
    int weekdayIndex,
  ) {
    if (day == null) {
      return SizedBox(height: cellSize);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _isSameDay(day, today);
    final isCurrentMonth = day.month == _focusedMonth.month;
    final isDisabled = _isDateDisabled(day);

    // 선택 상태 확인
    final isSelected = _isDateSelected(day);
    final isRangeStart = widget.mode == CalendarMode.range &&
        widget.rangeStart != null && _isSameDay(day, widget.rangeStart!);
    final isRangeEnd = widget.mode == CalendarMode.range &&
        widget.rangeEnd != null && _isSameDay(day, widget.rangeEnd!);
    final isInRange = _isInRange(day);
    final isRangeActive = isRangeStart || isRangeEnd || isInRange;

    // ── Range 모드: 전체 너비 배경 + Stack (TODateSelector와 동일 구조) ──
    // rangeEnd가 null이면 아직 범위 미확정 → circle로 표시 (아래 일반 모드로 fall-through)
    final rangeConfirmed = widget.rangeEnd != null;
    if (widget.mode == CalendarMode.range && isRangeActive && !isDisabled && rangeConfirmed) {
      final isSingleDay = isRangeStart && isRangeEnd &&
          _isSameDay(widget.rangeStart!, widget.rangeEnd!);

      BorderRadius stripeBorderRadius;
      if (isSingleDay) {
        stripeBorderRadius = BorderRadius.circular(cellSize / 2);
      } else {
        final roundLeft = isRangeStart || weekdayIndex == 0;
        final roundRight = isRangeEnd || weekdayIndex == 6;
        final r = Radius.circular(cellSize / 2);
        if (roundLeft && roundRight) {
          stripeBorderRadius = BorderRadius.all(r);
        } else if (roundLeft) {
          stripeBorderRadius = BorderRadius.horizontal(left: r);
        } else if (roundRight) {
          stripeBorderRadius = BorderRadius.horizontal(right: r);
        } else {
          stripeBorderRadius = BorderRadius.zero;
        }
      }

      return GestureDetector(
        onTap: () => _onDayTap(day),
        child: Container(
          height: cellSize,
          // 가로 여백 없음 → 셀이 맞닿아 매끄럽게 연결됨
          margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 2)),
          decoration: BoxDecoration(
            color: theme.primaryColor,
            borderRadius: stripeBorderRadius,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isRangeStart && !isSingleDay)
                Container(
                  width: cellSize - ResponsiveHelper.spacing(context, 8),
                  height: cellSize - ResponsiveHelper.spacing(context, 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                  ),
                ),
              Text(
                '${day.day}',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.surface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── 일반 모드: circle 스타일 ──
    Color textColor;
    Color? backgroundColor;
    Color? borderColor;

    if (isDisabled) {
      textColor = AppColors.grey300;
    } else if (isSelected) {
      textColor = AppColors.surface;
      backgroundColor = theme.primaryColor;
    } else if (isToday) {
      textColor = theme.primaryColor;
      borderColor = theme.primaryColor;
    } else if (!isCurrentMonth) {
      textColor = AppColors.grey300;
    } else if (weekdayIndex == 0) {
      textColor = AppColors.error;
    } else if (weekdayIndex == 6) {
      textColor = AppColors.info;
    } else {
      textColor = AppColors.textPrimary;
    }

    return GestureDetector(
      onTap: isDisabled ? null : () => _onDayTap(day),
      child: Container(
        height: cellSize,
        margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 2)),
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: borderColor != null
              ? Border.all(color: borderColor, width: 2)
              : null,
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: textColor,
              fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// 해당 월의 날짜 생성
  List<DateTime?> _generateDaysInMonth() {
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    
    final List<DateTime?> days = [];
    
    // 이전 월의 날짜 (빈 공간)
    final firstWeekday = firstDayOfMonth.weekday % 7;
    for (int i = 0; i < firstWeekday; i++) {
      final prevDay = firstDayOfMonth.subtract(Duration(days: firstWeekday - i));
      days.add(prevDay);
    }
    
    // 현재 월의 날짜
    for (int i = 1; i <= lastDayOfMonth.day; i++) {
      days.add(DateTime(_focusedMonth.year, _focusedMonth.month, i));
    }
    
    // 다음 월의 날짜 (6주 채우기)
    while (days.length < 42) {
      final nextDay = lastDayOfMonth.add(Duration(days: days.length - firstWeekday - lastDayOfMonth.day + 1));
      days.add(nextDay);
    }
    
    return days;
  }

  /// 날짜 선택 처리
  void _onDayTap(DateTime day) {
    // 인접 월 날짜 탭 시 해당 월로 이동
    if (day.month != _focusedMonth.month || day.year != _focusedMonth.year) {
      setState(() => _focusedMonth = DateTime(day.year, day.month));
      widget.onMonthChanged?.call(_focusedMonth);
    }

    switch (widget.mode) {
      case CalendarMode.single:
        widget.onDateSelected?.call(day);
        break;

      case CalendarMode.multiple:
        widget.onDateToggled?.call(day);
        break;

      case CalendarMode.range:
        _handleRangeSelection(day);
        break;
    }
  }

  /// 범위 선택 처리
  void _handleRangeSelection(DateTime day) {
    if (_rangeStartTemp == null || widget.rangeEnd != null) {
      // 첫 번째 선택 또는 재선택
      setState(() => _rangeStartTemp = day);
      widget.onRangeChanged?.call(day, null);
    } else {
      // 두 번째 선택
      DateTime start = _rangeStartTemp!;
      DateTime end = day;
      
      // 시작일이 종료일보다 뒤면 swap
      if (start.isAfter(end)) {
        final temp = start;
        start = end;
        end = temp;
      }
      
      setState(() => _rangeStartTemp = null);
      widget.onRangeChanged?.call(start, end);
    }
  }

  /// 날짜 비활성화 여부
  bool _isDateDisabled(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 과거 날짜 체크
    if (!widget.allowPastDates && day.isBefore(today)) {
      return true;
    }
    
    // 최소/최대 날짜 체크
    if (widget.minDate != null && day.isBefore(widget.minDate!)) {
      return true;
    }
    if (widget.maxDate != null && day.isAfter(widget.maxDate!)) {
      return true;
    }

    // 명시적 비활성화 날짜 체크
    if (widget.disabledDates != null) {
      final dayOnly = DateTime(day.year, day.month, day.day);
      if (widget.disabledDates!.any((d) => d.year == dayOnly.year && d.month == dayOnly.month && d.day == dayOnly.day)) {
        return true;
      }
    }

    // enabledDayPredicate: false 반환 시 비활성화
    if (widget.enabledDayPredicate != null) {
      final dayOnly = DateTime(day.year, day.month, day.day);
      if (!widget.enabledDayPredicate!(dayOnly)) return true;
    }

    return false;
  }

  /// 날짜 선택 여부
  bool _isDateSelected(DateTime day) {
    switch (widget.mode) {
      case CalendarMode.single:
        return widget.selectedDate != null && _isSameDay(day, widget.selectedDate!);
        
      case CalendarMode.multiple:
        return widget.selectedDates?.any((d) => _isSameDay(d, day)) ?? false;
        
      case CalendarMode.range:
        return (widget.rangeStart != null && _isSameDay(day, widget.rangeStart!)) ||
               (widget.rangeEnd != null && _isSameDay(day, widget.rangeEnd!));
    }
  }

  /// 범위 내 날짜 여부
  bool _isInRange(DateTime day) {
    if (widget.mode != CalendarMode.range) return false;
    if (widget.rangeStart == null || widget.rangeEnd == null) return false;
    
    return day.isAfter(widget.rangeStart!) && day.isBefore(widget.rangeEnd!);
  }

  /// 같은 날짜인지 확인
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 이전 월로 이동
  void _goToPreviousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
    widget.onMonthChanged?.call(_focusedMonth);
  }

  /// 다음 월로 이동
  void _goToNextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
    widget.onMonthChanged?.call(_focusedMonth);
  }

  /// 현재 월로 이동
  void _goToCurrentMonth() {
    setState(() {
      _focusedMonth = DateTime.now();
    });
    widget.onMonthChanged?.call(_focusedMonth);
  }
}

/// 캘린더 선택 모드
enum CalendarMode {
  /// 단일 날짜 선택
  single,
  
  /// 다중 날짜 선택
  multiple,
  
  /// 범위 선택 (시작일 ~ 종료일)
  range,
}