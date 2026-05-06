import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/pickers/date_picker_bottom_sheet.dart';
import 'to_section_container.dart';
import '../../../../utils/toast_helper.dart';

const _kPrimary = Color(0xFF1565C0);

/// TO 날짜 선택 공통 위젯 (당근 스타일)
class TODateSelector extends StatefulWidget {
  final bool isLongTerm;
  final bool isReadOnly;

  // 단기 알바용
  final List<DateTime> selectedDates;
  final Function(DateTime)? onDateToggle;
  final Function(List<DateTime>)? onDatesChanged;
  final Function()? onClearAll;
  final int maxSelectableDays;

  // 장기 근무용
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final List<String> selectedWeekdays;
  final Function(DateTime)? onRangeStartChanged;
  final Function(DateTime)? onRangeEndChanged;
  final Function(String)? onWeekdayToggle;

  // 읽기 전용
  final DateTime? displayDate;
  final List<String>? displayWorkDays;

  const TODateSelector({
    super.key,
    required this.isLongTerm,
    this.isReadOnly = false,
    this.selectedDates = const [],
    this.onDateToggle,
    this.onDatesChanged,
    this.onClearAll,
    this.maxSelectableDays = 14,
    this.rangeStart,
    this.rangeEnd,
    this.selectedWeekdays = const [],
    this.onRangeStartChanged,
    this.onRangeEndChanged,
    this.onWeekdayToggle,
    this.displayDate,
    this.displayWorkDays,
  });

  @override
  State<TODateSelector> createState() => _TODateSelectorState();
}

class _TODateSelectorState extends State<TODateSelector> {
  static const int _maxFutureDays = 60;

  DateTime _focusedDay = DateTime.now();
  bool _isCalendarExpanded = true;

  // 범위 선택: 첫 번째 탭으로 시작점만 기억 (selectedDates에 추가하지 않음)
  DateTime? _rangeStart;

  String? _activeQuickSelect;

  @override
  Widget build(BuildContext context) {
    if (widget.isReadOnly) return _buildReadOnlySection(context);
    if (widget.isLongTerm) return _buildLongTermSelector(context);
    return _buildShortTermSelector(context);
  }

  // ============================================================
  // 📅 읽기 전용 섹션
  // ============================================================
  Widget _buildReadOnlySection(BuildContext context) {
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
                  color: _kPrimary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: AppColors.surface,
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
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      dateText,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (widget.isLongTerm && widget.displayWorkDays != null && widget.displayWorkDays!.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Row(
              children: [
                Icon(Icons.event_repeat, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey600),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '근무 요일: ${widget.displayWorkDays!.join(', ')}',
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
                ),
              ],
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warningLight, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.warningDark, size: ResponsiveHelper.iconSize(context, 18)),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    '${widget.isLongTerm ? "계약 기간과 근무 요일" : "날짜"}은(는) 수정할 수 없습니다',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
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
  // 📅 단기 알바 - 당근 스타일 캘린더
  // ============================================================
  Widget _buildShortTermSelector(BuildContext context) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          _buildQuickSelectButtons(context),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          _buildCalendarToggle(context),

          if (_isCalendarExpanded) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildCarrotStyleCalendar(context),
          ],
        ],
      ),
    );
  }

  /// 헤더 (범위 선택 중일 때 힌트로 교체 - 레이아웃 고정)
  Widget _buildHeader(BuildContext context) {
    final fmt = DateFormat('M월 d일 (E)', 'ko_KR');

    return SizedBox(
      height: ResponsiveHelper.spacing(context, 40),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _rangeStart != null
            // 범위 선택 중: 시작일 안내
            ? Container(
                key: const ValueKey('hint'),
                padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app, color: _kPrimary, size: ResponsiveHelper.iconSize(context, 16)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: ResponsiveHelper.smallStyle(context, color: _kPrimary),
                          children: [
                            TextSpan(
                              text: fmt.format(_rangeStart!),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const TextSpan(text: ' · 종료 날짜를 탭하세요'),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        final start = _rangeStart!;
                        setState(() => _rangeStart = null);
                        widget.onDateToggle?.call(start);
                      },
                      child: Icon(Icons.close, color: _kPrimary, size: ResponsiveHelper.iconSize(context, 16)),
                    ),
                  ],
                ),
              )
            // 기본 헤더
            : Row(
                key: const ValueKey('header'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '근무 날짜 선택',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (widget.selectedDates.isNotEmpty) ...[
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 10),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.selectedDates.length}일',
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: AppColors.surface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Opacity(
                    opacity: widget.selectedDates.isNotEmpty ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: widget.selectedDates.isEmpty,
                      child: Material(
                        color: AppColors.errorBg,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _activeQuickSelect = null;
                              _rangeStart = null;
                            });
                            widget.onClearAll?.call();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 12),
                              vertical: ResponsiveHelper.spacing(context, 8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.clear_all, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.errorDark),
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Text(
                                  '전체 해제',
                                  style: ResponsiveHelper.smallStyle(context).copyWith(
                                    color: AppColors.errorDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 빠른 선택 버튼
  Widget _buildQuickSelectButtons(BuildContext context) {
    return Row(
      children: [
        _buildQuickButton(context, id: 'today', icon: Icons.today, label: '오늘'),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _buildQuickButton(context, id: 'thisWeek', icon: Icons.view_week, label: '이번 주'),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _buildQuickButton(context, id: 'nextWeek', icon: Icons.next_week, label: '다음 주'),
      ],
    );
  }

  Widget _buildQuickButton(
    BuildContext context, {
    required String id,
    required IconData icon,
    required String label,
  }) {
    final isActive = _activeQuickSelect == id;

    return Expanded(
      child: Material(
        color: isActive ? _kPrimary : _kPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _handleQuickSelect(id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: isActive ? AppColors.surface : _kPrimary,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  label,
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: isActive ? AppColors.surface : _kPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 캘린더 토글
  Widget _buildCalendarToggle(BuildContext context) {
    return Material(
      color: AppColors.grey100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _isCalendarExpanded = !_isCalendarExpanded),
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
                color: AppColors.grey700,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                _isCalendarExpanded ? '캘린더 접기' : '캘린더 펼치기',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.grey700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 당근 스타일 캘린더
  Widget _buildCarrotStyleCalendar(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCalendarHeader(context),
          _buildWeekdayHeader(context),
          _buildDateGrid(context, today),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
      ),
    );
  }

  /// 캘린더 헤더
  Widget _buildCalendarHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
              });
            },
            icon: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_left, color: _kPrimary),
            ),
          ),
          Text(
            DateFormat('yyyy년 M월', 'ko_KR').format(_focusedDay),
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: _kPrimary,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
              });
            },
            icon: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_right, color: _kPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// 요일 헤더
  Widget _buildWeekdayHeader(BuildContext context) {
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        children: weekdays.asMap().entries.map((entry) {
          final isWeekend = entry.key == 0 || entry.key == 6;
          return Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
                child: Text(
                  entry.value,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: isWeekend ? AppColors.error : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 날짜 그리드
  Widget _buildDateGrid(BuildContext context, DateTime today) {
    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final lastDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday % 7;

    final daysInMonth = lastDayOfMonth.day;
    final totalCells = ((firstWeekday + daysInMonth) / 7).ceil() * 7;

    List<Widget> rows = [];
    List<Widget> currentRow = [];

    for (int i = 0; i < totalCells; i++) {
      final dayOffset = i - firstWeekday;

      if (dayOffset < 0 || dayOffset >= daysInMonth) {
        currentRow.add(Expanded(child: SizedBox(height: ResponsiveHelper.spacing(context, 44))));
      } else {
        final date = DateTime(_focusedDay.year, _focusedDay.month, dayOffset + 1);
        currentRow.add(Expanded(child: _buildDateCell(context, date, today)));
      }

      if (currentRow.length == 7) {
        rows.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
            child: Row(children: currentRow),
          ),
        );
        currentRow = [];
      }
    }

    return Column(children: rows);
  }

  /// 날짜 셀 (당근 스타일 - 연속 날짜 연결 배경)
  Widget _buildDateCell(BuildContext context, DateTime date, DateTime today) {
    final isPast = date.isBefore(today);
    final isTooFar = date.isAfter(today.add(const Duration(days: _maxFutureDays)));
    final isToday = _isSameDay(date, today);
    final isSelected = widget.selectedDates.any((d) => _isSameDay(d, date));
    final isRangeStart = _rangeStart != null && _isSameDay(date, _rangeStart!);

    // 연속 날짜 체크
    final prevDay = date.subtract(const Duration(days: 1));
    final nextDay = date.add(const Duration(days: 1));
    final hasPrev = widget.selectedDates.any((d) => _isSameDay(d, prevDay));
    final hasNext = widget.selectedDates.any((d) => _isSameDay(d, nextDay));

    // 연결 배경 모서리
    BorderRadius borderRadius;
    if (isSelected) {
      if (hasPrev && hasNext) {
        borderRadius = BorderRadius.zero;
      } else if (hasPrev && !hasNext) {
        borderRadius = BorderRadius.horizontal(right: Radius.circular(ResponsiveHelper.spacing(context, 22)));
      } else if (!hasPrev && hasNext) {
        borderRadius = BorderRadius.horizontal(left: Radius.circular(ResponsiveHelper.spacing(context, 22)));
      } else {
        borderRadius = BorderRadius.circular(ResponsiveHelper.spacing(context, 22));
      }
    } else {
      borderRadius = BorderRadius.circular(ResponsiveHelper.spacing(context, 22));
    }

    // 색상
    Color backgroundColor;
    Color textColor;

    if (isPast || isTooFar) {
      backgroundColor = Colors.transparent;
      textColor = AppColors.grey300;
    } else if (isSelected) {
      backgroundColor = _kPrimary;
      textColor = AppColors.surface;
    } else {
      backgroundColor = Colors.transparent;
      textColor = (date.weekday == DateTime.sunday || date.weekday == DateTime.saturday)
          ? AppColors.error
          : AppColors.textPrimary;
    }

    return GestureDetector(
      onTap: (isPast || isTooFar) ? null : () => _handleDateTap(date, today),
      child: Container(
        height: ResponsiveHelper.spacing(context, 38),
        margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 2)),
        decoration: BoxDecoration(
          color: isSelected ? backgroundColor : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 오늘 테두리
            if (isToday && !isSelected)
              Container(
                width: ResponsiveHelper.spacing(context, 36),
                height: ResponsiveHelper.spacing(context, 36),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kPrimary, width: 2),
                ),
              ),

            // 범위 시작점 - 점선 외곽 링 (시각적 구분)
            if (isRangeStart && isSelected)
              Container(
                width: ResponsiveHelper.spacing(context, 36),
                height: ResponsiveHelper.spacing(context, 36),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
              ),

            // 날짜 텍스트
            Text(
              '${date.day}',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: textColor,
                fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
                decoration: isPast ? TextDecoration.lineThrough : null,
                decorationColor: AppColors.grey300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 📅 장기 근무 - 기간 + 요일 선택
  // ============================================================
  Widget _buildLongTermSelector(BuildContext context) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '계약 기간',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          Row(
            children: [
              Expanded(
                child: _buildDateField(
                  context: context,
                  label: '시작일',
                  date: widget.rangeStart,
                  onTap: () => _selectLongTermDate(context, isStart: true),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12)),
                child: const Icon(Icons.arrow_forward, color: _kPrimary),
              ),
              Expanded(
                child: _buildDateField(
                  context: context,
                  label: '종료일',
                  date: widget.rangeEnd,
                  onTap: () => _selectLongTermDate(context, isStart: false),
                ),
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Divider(color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          Text(
            '근무 요일 선택',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '※ 매주 반복되는 근무 요일을 선택하세요',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          _buildWeekdayButtons(context),

          if (widget.selectedWeekdays.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildWeekdaySummary(context),
          ],
        ],
      ),
    );
  }

  Widget _buildDateField({
    required BuildContext context,
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
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          decoration: BoxDecoration(
            color: date != null ? _kPrimary.withValues(alpha: 0.05) : AppColors.grey50,
            border: Border.all(
              color: date != null ? _kPrimary : AppColors.border,
              width: date != null ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                date != null ? FormatHelper.formatDate(date) : '선택하세요',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: date != null ? AppColors.textPrimary : AppColors.textHint,
                  fontWeight: date != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectLongTermDate(BuildContext context, {required bool isStart}) async {
    final picked = await DatePickerBottomSheet.show(
      context: context,
      initialDate: isStart
          ? (widget.rangeStart ?? DateTime.now())
          : (widget.rangeEnd ?? widget.rangeStart ?? DateTime.now()),
      title: isStart ? '계약 시작일' : '계약 종료일',
      subtitle: isStart ? '근무 시작 날짜를 선택하세요' : '근무 종료 날짜를 선택하세요',
      minDate: isStart ? DateTime.now() : (widget.rangeStart ?? DateTime.now()),
      maxDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      if (isStart) {
        widget.onRangeStartChanged?.call(picked);
      } else {
        widget.onRangeEndChanged?.call(picked);
      }
    }
  }

  Widget _buildWeekdayButtons(BuildContext context) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = (constraints.maxWidth - 48) / 7;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: weekdays.map((day) {
            final isSelected = widget.selectedWeekdays.contains(day);
            final isWeekend = day == '토' || day == '일';

            return GestureDetector(
              onTap: () => widget.onWeekdayToggle?.call(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: buttonWidth,
                height: buttonWidth,
                decoration: BoxDecoration(
                  color: isSelected ? _kPrimary : (isWeekend ? AppColors.errorBg : AppColors.grey100),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                      : null,
                ),
                child: Center(
                  child: Text(
                    day,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: isSelected ? AppColors.surface : (isWeekend ? AppColors.error : AppColors.grey700),
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

  Widget _buildWeekdaySummary(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.successBg, AppColors.successLight.withValues(alpha: 0.3)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.successLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.successDark, size: ResponsiveHelper.iconSize(context, 18)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '주 ${widget.selectedWeekdays.length}일 근무',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.successDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '선택된 요일: ${widget.selectedWeekdays.join(', ')}',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.successDark),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🛠️ 이벤트 핸들러
  // ============================================================

  /// 날짜 탭 처리 (당근 스타일 범위 선택)
  void _handleDateTap(DateTime date, DateTime today) {
    setState(() => _activeQuickSelect = null);

    final isAlreadySelected = widget.selectedDates.any((d) => _isSameDay(d, date));

    if (isAlreadySelected) {
      // 범위 시작점을 다시 탭 → 범위 모드 취소
      if (_rangeStart != null && _isSameDay(date, _rangeStart!)) {
        setState(() => _rangeStart = null);
        widget.onDateToggle?.call(date);
        return;
      }
      // 일반 해제
      setState(() => _rangeStart = null);
      widget.onDateToggle?.call(date);
      return;
    }

    // 최대 개수 초과 & 범위 시작 전
    if (widget.selectedDates.length >= widget.maxSelectableDays && _rangeStart == null) {
      ToastHelper.showWarning('최대 ${widget.maxSelectableDays}일까지 선택 가능합니다');
      return;
    }

    if (_rangeStart == null) {
      // 첫 번째 탭: 시작점 설정 + 날짜 선택
      setState(() => _rangeStart = date);
      widget.onDateToggle?.call(date);
    } else {
      // 두 번째 탭: 범위 채우기
      _selectRange(_rangeStart!, date, today);
      setState(() => _rangeStart = null);
    }
  }

  /// 범위 선택 (14일 제한 통합 적용)
  void _selectRange(DateTime start, DateTime end, DateTime today) {
    DateTime rangeStart = start.isBefore(end) ? start : end;
    DateTime rangeEnd = start.isBefore(end) ? end : start;

    // 이미 시작점이 selectedDates에 있으므로 현재 개수 기준으로 체크
    int count = widget.selectedDates.length;
    bool reachedLimit = false;

    final newDates = List<DateTime>.from(widget.selectedDates);

    for (var d = rangeStart; !d.isAfter(rangeEnd); d = d.add(const Duration(days: 1))) {
      if (!d.isBefore(today) && !newDates.any((existing) => _isSameDay(existing, d))) {
        if (count < widget.maxSelectableDays) {
          newDates.add(d);
          count++;
        } else {
          reachedLimit = true;
        }
      }
    }

    if (reachedLimit) {
      ToastHelper.showWarning('최대 ${widget.maxSelectableDays}일까지 선택 가능합니다');
    }

    newDates.sort();

    if (widget.onDatesChanged != null) {
      widget.onDatesChanged!(newDates);
    } else {
      // onDatesChanged 없는 경우: 시작점은 이미 추가됐으므로 나머지만 추가
      for (final d in newDates) {
        if (!widget.selectedDates.any((existing) => _isSameDay(existing, d))) {
          widget.onDateToggle?.call(d);
        }
      }
    }
  }

  /// 빠른 선택 처리 (토글 방식)
  void _handleQuickSelect(String id) {
    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    setState(() => _rangeStart = null);

    if (_activeQuickSelect == id) {
      setState(() => _activeQuickSelect = null);
      widget.onClearAll?.call();
      return;
    }

    List<DateTime> dates = [];

    switch (id) {
      case 'today':
        dates = [todayNormalized];
        break;
      case 'thisWeek':
        dates = _getWeekDates(todayNormalized, isNextWeek: false);
        break;
      case 'nextWeek':
        dates = _getWeekDates(todayNormalized, isNextWeek: true);
        break;
    }

    dates = dates.where((d) => !d.isBefore(todayNormalized)).toList();

    // 14일 제한 적용
    if (dates.length > widget.maxSelectableDays) {
      dates = dates.take(widget.maxSelectableDays).toList();
      ToastHelper.showWarning('최대 ${widget.maxSelectableDays}일까지 선택 가능합니다');
    }

    setState(() => _activeQuickSelect = id);

    if (widget.onDatesChanged != null) {
      widget.onDatesChanged!(dates);
    } else {
      widget.onClearAll?.call();
      for (var date in dates) {
        widget.onDateToggle?.call(date);
      }
    }
  }

  /// 주간 날짜 가져오기 (월~일)
  List<DateTime> _getWeekDates(DateTime today, {required bool isNextWeek}) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final targetMonday = isNextWeek ? monday.add(const Duration(days: 7)) : monday;
    return List.generate(7, (i) => targetMonday.add(Duration(days: i)));
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
