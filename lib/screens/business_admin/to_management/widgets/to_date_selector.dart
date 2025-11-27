import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../../../utils/responsive_helper.dart';
import 'to_section_container.dart';

// 위젯 파일 위치: lib/screens/business_admin/to_management/widgets/

/// TO 날짜 선택 공통 위젯
/// - 단기 알바: 다중 날짜 선택 (캘린더)
/// - 장기 근무: 기간 + 요일 선택
class TODateSelector extends StatefulWidget {
  // ============================================================
  // 공통 파라미터
  // ============================================================
  final bool isLongTerm;
  final bool isReadOnly; // edit 화면에서 수정 불가 표시용
  
  // ============================================================
  // 단기 알바용 파라미터
  // ============================================================
  final List<DateTime> selectedDates;
  final Function(DateTime)? onDateToggle;
  final Function()? onClearAll;
  
  // ============================================================
  // 장기 근무용 파라미터
  // ============================================================
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final List<String> selectedWeekdays;
  final Function(DateTime)? onRangeStartChanged;
  final Function(DateTime)? onRangeEndChanged;
  final Function(String)? onWeekdayToggle;
  
  // ============================================================
  // 읽기 전용 모드 (edit 화면)
  // ============================================================
  final DateTime? displayDate; // 단일 날짜 표시용
  final List<String>? displayWorkDays; // 근무 요일 표시용

  const TODateSelector({
    super.key,
    required this.isLongTerm,
    this.isReadOnly = false,
    // 단기
    this.selectedDates = const [],
    this.onDateToggle,
    this.onClearAll,
    // 장기
    this.rangeStart,
    this.rangeEnd,
    this.selectedWeekdays = const [],
    this.onRangeStartChanged,
    this.onRangeEndChanged,
    this.onWeekdayToggle,
    // 읽기 전용
    this.displayDate,
    this.displayWorkDays,
  });

  @override
  State<TODateSelector> createState() => _TODateSelectorState();
}

class _TODateSelectorState extends State<TODateSelector> {
  DateTime _focusedDay = DateTime.now();
  bool _isCalendarExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.isReadOnly) {
      return _buildReadOnlySection(context);
    }
    
    if (widget.isLongTerm) {
      return _buildLongTermSelector(context);
    }
    
    return _buildShortTermSelector(context);
  }

  // ============================================================
  // 📅 읽기 전용 섹션 (edit 화면용)
  // ============================================================
  Widget _buildReadOnlySection(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    
    String dateText;
    if (widget.isLongTerm && widget.rangeStart != null && widget.rangeEnd != null) {
      final isSameYear = widget.rangeStart!.year == now.year;
      final format = DateFormat(isSameYear ? 'M월 d일 (E)' : 'yyyy년 M월 d일 (E)', 'ko_KR');
      dateText = '${format.format(widget.rangeStart!)} ~ ${format.format(widget.rangeEnd!)}';
    } else if (widget.displayDate != null) {
      final isSameYear = widget.displayDate!.year == now.year;
      final format = DateFormat(isSameYear ? 'M월 d일 (E)' : 'yyyy년 M월 d일 (E)', 'ko_KR');
      dateText = format.format(widget.displayDate!);
    } else {
      dateText = '날짜 정보 없음';
    }

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.primaryColor,
                      theme.primaryColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isLongTerm ? '계약 기간' : '근무 날짜',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      dateText,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // 장기 근무 요일 표시
          if (widget.isLongTerm && widget.displayWorkDays != null && widget.displayWorkDays!.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Row(
              children: [
                Icon(
                  Icons.event_repeat,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Colors.grey[600],
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '근무 요일: ${widget.displayWorkDays!.join(', ')}',
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ],
          
          // 수정 불가 안내
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  color: Colors.orange[700],
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    '${widget.isLongTerm ? "계약 기간과 근무 요일" : "날짜"}은(는) 수정할 수 없습니다',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📅 단기 알바 - 다중 날짜 선택
  // ============================================================
  Widget _buildShortTermSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '근무 날짜 선택',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.selectedDates.isNotEmpty)
                _buildClearAllButton(context),
            ],
          ),
          
          // 선택된 날짜 요약
          if (widget.selectedDates.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildDateSummary(context, theme),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 캘린더 토글 버튼
          _buildCalendarToggle(context, theme),

          // 캘린더
          if (_isCalendarExpanded) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildCalendar(context, theme),
          ],
        ],
      ),
    );
  }

  /// 전체 해제 버튼
  Widget _buildClearAllButton(BuildContext context) {
    return Material(
      color: Colors.red[50],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: widget.onClearAll,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.clear_all,
                size: ResponsiveHelper.iconSize(context, 18),
                color: Colors.red[700],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '전체 해제',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 날짜 요약 표시
  Widget _buildDateSummary(BuildContext context, ThemeData theme) {
    final groups = _groupConsecutiveDates(widget.selectedDates);

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withOpacity(0.1),
            theme.primaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: ResponsiveHelper.iconSize(context, 16),
                color: theme.primaryColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '선택된 날짜: ${widget.selectedDates.length}일',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: groups.map((group) {
              if (group.length == 1) {
                return _buildSingleDateChip(context, theme, group[0]);
              } else {
                return _buildDateRangeChip(context, theme, group.first, group.last, group.length);
              }
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 단일 날짜 칩
  Widget _buildSingleDateChip(BuildContext context, ThemeData theme, DateTime date) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${date.month}/${date.day}',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          GestureDetector(
            onTap: () => widget.onDateToggle?.call(date),
            child: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 2)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: ResponsiveHelper.iconSize(context, 16),
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 연속 날짜 범위 칩
  Widget _buildDateRangeChip(BuildContext context, ThemeData theme, DateTime start, DateTime end, int count) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green[600]!,
            Colors.green[400]!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${start.month}/${start.day} ~ ${end.month}/${end.day}',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 8),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count일',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          GestureDetector(
            onTap: () {
              // 범위 내 모든 날짜 삭제
              for (var date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
                widget.onDateToggle?.call(date);
              }
            },
            child: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 2)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: ResponsiveHelper.iconSize(context, 16),
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 캘린더 토글 버튼
  Widget _buildCalendarToggle(BuildContext context, ThemeData theme) {
    return Material(
      color: theme.primaryColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() {
            _isCalendarExpanded = !_isCalendarExpanded;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isCalendarExpanded ? Icons.expand_less : Icons.expand_more,
                color: theme.primaryColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                _isCalendarExpanded ? '캘린더 접기' : '캘린더 펼치기',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 캘린더 위젯
  Widget _buildCalendar(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: ResponsiveHelper.cardPadding(context),
      child: TableCalendar(
        locale: 'ko_KR',
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 90)),
        focusedDay: _focusedDay,
        calendarFormat: CalendarFormat.month,
        selectedDayPredicate: (day) {
          return widget.selectedDates.any((date) =>
              date.year == day.year &&
              date.month == day.month &&
              date.day == day.day);
        },
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _focusedDay = focusedDay;
          });
          widget.onDateToggle?.call(DateTime(
            selectedDay.year,
            selectedDay.month,
            selectedDay.day,
          ));
        },
        onPageChanged: (focusedDay) {
          setState(() {
            _focusedDay = focusedDay;
          });
        },
        calendarStyle: CalendarStyle(
          selectedDecoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.primaryColor,
                theme.primaryColor.withOpacity(0.8),
              ],
            ),
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          outsideDaysVisible: false,
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: ResponsiveHelper.smallStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
          weekendStyle: ResponsiveHelper.smallStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red[400],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 📅 장기 근무 - 기간 + 요일 선택
  // ============================================================
  Widget _buildLongTermSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '계약 기간',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 시작일/종료일
          Row(
            children: [
              Expanded(
                child: _buildDateField(
                  context: context,
                  theme: theme,
                  label: '시작일',
                  date: widget.rangeStart,
                  onTap: () => _selectDate(context, isStart: true),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                ),
                child: Icon(
                  Icons.arrow_forward,
                  color: theme.primaryColor,
                ),
              ),
              Expanded(
                child: _buildDateField(
                  context: context,
                  theme: theme,
                  label: '종료일',
                  date: widget.rangeEnd,
                  onTap: () => _selectDate(context, isStart: false),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Divider(color: Colors.grey[300]),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          Text(
            '근무 요일 선택',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '※ 매주 반복되는 근무 요일을 선택하세요',
            style: ResponsiveHelper.smallStyle(
              context,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 요일 버튼들
          _buildWeekdayButtons(context, theme),
          
          // 선택 요약
          if (widget.selectedWeekdays.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildWeekdaySummary(context),
          ],
        ],
      ),
    );
  }

  /// 날짜 필드
  Widget _buildDateField({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                date != null
                    ? DateFormat('yyyy-MM-dd').format(date)
                    : '선택하세요',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  color: date != null ? Colors.black : Colors.grey[400],
                  fontWeight: date != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 날짜 선택 다이얼로그
  Future<void> _selectDate(BuildContext context, {required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (widget.rangeStart ?? DateTime.now())
          : (widget.rangeEnd ?? widget.rangeStart ?? DateTime.now()),
      firstDate: isStart ? DateTime.now() : (widget.rangeStart ?? DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null) {
      if (isStart) {
        widget.onRangeStartChanged?.call(picked);
      } else {
        widget.onRangeEndChanged?.call(picked);
      }
    }
  }

  /// 요일 버튼들
  Widget _buildWeekdayButtons(BuildContext context, ThemeData theme) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = (constraints.maxWidth - 48) / 7;
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: weekdays.map((day) {
            final isSelected = widget.selectedWeekdays.contains(day);
            return GestureDetector(
              onTap: () => widget.onWeekdayToggle?.call(day),
              child: Container(
                width: buttonWidth,
                height: buttonWidth,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.primaryColor,
                            theme.primaryColor.withOpacity(0.8),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: theme.primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    day,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: isSelected ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// 요일 선택 요약
  Widget _buildWeekdaySummary(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green[50]!,
            Colors.green[100]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green[700],
                size: ResponsiveHelper.iconSize(context, 18),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '주 ${widget.selectedWeekdays.length}일 근무',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: Colors.green[900],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '선택된 요일: ${widget.selectedWeekdays.join(', ')}',
            style: ResponsiveHelper.smallStyle(
              context,
              color: Colors.green[800],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🛠️ 유틸리티 함수
  // ============================================================
  
  /// 연속 날짜 그룹화
  List<List<DateTime>> _groupConsecutiveDates(List<DateTime> dates) {
    if (dates.isEmpty) return [];
    
    final sorted = List<DateTime>.from(dates)..sort();
    List<List<DateTime>> groups = [];
    List<DateTime> currentGroup = [sorted[0]];

    for (int i = 1; i < sorted.length; i++) {
      final diff = sorted[i].difference(sorted[i - 1]).inDays;

      if (diff == 1) {
        currentGroup.add(sorted[i]);
      } else {
        groups.add(currentGroup);
        currentGroup = [sorted[i]];
      }
    }

    groups.add(currentGroup);
    return groups;
  }
}