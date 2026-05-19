import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../calendar/carrot_style_calendar.dart';

/// 📅 날짜 선택 바텀시트
/// 
/// 당근마켓 스타일의 날짜 선택 바텀시트
/// 
/// 사용 예:
/// ```dart
/// final date = await DatePickerBottomSheet.show(
///   context: context,
///   initialDate: DateTime.now(),
///   title: '날짜 선택',
/// );
/// ```
class DatePickerBottomSheet extends StatefulWidget {
  /// 초기 선택 날짜
  final DateTime? initialDate;
  
  /// 제목
  final String title;
  
  /// 부제목
  final String? subtitle;
  
  /// 선택 가능한 최소 날짜
  final DateTime? minDate;
  
  /// 선택 가능한 최대 날짜
  final DateTime? maxDate;
  
  /// 과거 날짜 선택 허용
  final bool allowPastDates;

  /// 비활성화할 특정 날짜 목록
  final List<DateTime>? disabledDates;

  /// 선택 가능한 날짜 판단 함수 (false 반환 시 비활성화)
  final bool Function(DateTime)? enabledDayPredicate;

  const DatePickerBottomSheet({
    super.key,
    this.initialDate,
    required this.title,
    this.subtitle,
    this.minDate,
    this.maxDate,
    this.allowPastDates = false,
    this.disabledDates,
    this.enabledDayPredicate,
  });

  /// 바텀시트 표시
  static Future<DateTime?> show({
    required BuildContext context,
    DateTime? initialDate,
    String title = '날짜 선택',
    String? subtitle,
    DateTime? minDate,
    DateTime? maxDate,
    bool allowPastDates = false,
    List<DateTime>? disabledDates,
    bool Function(DateTime)? enabledDayPredicate,
  }) {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DatePickerBottomSheet(
        initialDate: initialDate,
        title: title,
        subtitle: subtitle,
        minDate: minDate,
        maxDate: maxDate,
        allowPastDates: allowPastDates,
        disabledDates: disabledDates,
        enabledDayPredicate: enabledDayPredicate,
      ),
    );
  }

  @override
  State<DatePickerBottomSheet> createState() => _DatePickerBottomSheetState();
}

class _DatePickerBottomSheetState extends State<DatePickerBottomSheet> {
  late DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바
            _buildHandle(context),
            
            // 헤더
            _buildHeader(context, theme),
            
            // 선택된 날짜 표시
            if (_selectedDate != null)
              _buildSelectedDateDisplay(context, theme),
            
            // 캘린더
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
              ),
              child: CarrotStyleCalendar(
                mode: CalendarMode.single,
                selectedDate: _selectedDate,
                minDate: widget.minDate,
                maxDate: widget.maxDate,
                allowPastDates: widget.allowPastDates,
                disabledDates: widget.disabledDates,
                enabledDayPredicate: widget.enabledDayPredicate,
                onDateSelected: (date) {
                  setState(() => _selectedDate = date);
                },
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 버튼
            _buildButtons(context, theme),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],
        ),
      ),
    );
  }

  /// 핸들바
  Widget _buildHandle(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.grey300,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.calendar_today,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    widget.subtitle!,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 선택된 날짜 표시
  Widget _buildSelectedDateDisplay(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor.withValues(alpha: 0.1),
            theme.primaryColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            FormatHelper.formatDateLong(_selectedDate!),
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 버튼
  Widget _buildButtons(BuildContext context, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      child: Row(
        children: [
          // 취소 버튼
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                side: BorderSide(color: AppColors.grey400),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
          
          // 확인 버튼
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _selectedDate != null 
                  ? () => Navigator.pop(context, _selectedDate)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: AppColors.surface,
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                '선택 완료',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.surface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 📅 날짜 범위 선택 바텀시트
class DateRangePickerBottomSheet extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String title;
  final String? subtitle;
  final DateTime? minDate;
  final DateTime? maxDate;
  final bool allowPastDates;
  final List<DateTime>? disabledDates;
  final bool Function(DateTime)? enabledDayPredicate;

  const DateRangePickerBottomSheet({
    super.key,
    this.initialStart,
    this.initialEnd,
    required this.title,
    this.subtitle,
    this.minDate,
    this.maxDate,
    this.allowPastDates = false,
    this.disabledDates,
    this.enabledDayPredicate,
  });

  /// 바텀시트 표시
  static Future<DateTimeRange?> show({
    required BuildContext context,
    DateTime? initialStart,
    DateTime? initialEnd,
    String title = '기간 선택',
    String? subtitle,
    DateTime? minDate,
    DateTime? maxDate,
    bool allowPastDates = false,
    List<DateTime>? disabledDates,
    bool Function(DateTime)? enabledDayPredicate,
  }) {
    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DateRangePickerBottomSheet(
        initialStart: initialStart,
        initialEnd: initialEnd,
        title: title,
        subtitle: subtitle,
        minDate: minDate,
        maxDate: maxDate,
        allowPastDates: allowPastDates,
        disabledDates: disabledDates,
        enabledDayPredicate: enabledDayPredicate,
      ),
    );
  }

  @override
  State<DateRangePickerBottomSheet> createState() => _DateRangePickerBottomSheetState();
}

class _DateRangePickerBottomSheetState extends State<DateRangePickerBottomSheet> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.initialStart;
    _rangeEnd = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바
            _buildHandle(context),
            
            // 헤더
            _buildHeader(context, theme),
            
            // 선택된 범위 표시
            _buildSelectedRangeDisplay(context, theme),
            
            // 캘린더
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
              ),
              child: CarrotStyleCalendar(
                mode: CalendarMode.range,
                rangeStart: _rangeStart,
                rangeEnd: _rangeEnd,
                minDate: widget.minDate,
                maxDate: widget.maxDate,
                allowPastDates: widget.allowPastDates,
                disabledDates: widget.disabledDates,
                enabledDayPredicate: widget.enabledDayPredicate,
                onRangeChanged: (start, end) {
                  setState(() {
                    _rangeStart = start;
                    _rangeEnd = end;
                  });
                },
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 버튼
            _buildButtons(context, theme),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.grey300,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.date_range,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    widget.subtitle!,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedRangeDisplay(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // 시작일
          Expanded(
            child: _buildDateBox(
              context,
              theme,
              label: '시작일',
              date: _rangeStart,
              isSelected: _rangeStart != null && _rangeEnd == null,
            ),
          ),
          
          // 화살표
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
            ),
            child: Icon(
              Icons.arrow_forward,
              color: AppColors.textSecondary,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
          ),
          
          // 종료일
          Expanded(
            child: _buildDateBox(
              context,
              theme,
              label: '종료일',
              date: _rangeEnd,
              isSelected: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBox(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required DateTime? date,
    required bool isSelected,
  }) {
    final dateFormat = DateFormat('M월 d일', 'ko_KR');
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: isSelected 
            ? theme.primaryColor.withValues(alpha: 0.1)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? theme.primaryColor : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            date != null ? dateFormat.format(date) : '선택',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: date != null ? AppColors.textPrimary : AppColors.textHint,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context, ThemeData theme) {
    final isValid = _rangeStart != null && _rangeEnd != null;
    
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                side: BorderSide(color: AppColors.grey400),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
              onPressed: isValid 
                  ? () => Navigator.pop(context, DateTimeRange(
                      start: _rangeStart!,
                      end: _rangeEnd!,
                    ))
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: AppColors.surface,
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                '선택 완료',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.surface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}