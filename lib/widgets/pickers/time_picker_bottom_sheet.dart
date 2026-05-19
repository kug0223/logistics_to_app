import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../calendar/carrot_style_calendar.dart';

/// ⏰ 시간 선택 바텀시트 (휠 피커)
/// 
/// iOS 스타일의 시간 선택 휠 피커
/// 
/// 사용 예:
/// ```dart
/// final time = await TimePickerBottomSheet.show(
///   context: context,
///   initialTime: TimeOfDay.now(),
///   title: '시간 선택',
/// );
/// ```
class TimePickerBottomSheet extends StatefulWidget {
  /// 초기 선택 시간
  final TimeOfDay? initialTime;
  
  /// 제목
  final String title;
  
  /// 부제목
  final String? subtitle;
  
  /// 분 간격 (1, 5, 10, 15, 30)
  final int minuteInterval;
  
  /// 24시간 형식 사용
  final bool use24HourFormat;

  const TimePickerBottomSheet({
    super.key,
    this.initialTime,
    required this.title,
    this.subtitle,
    this.minuteInterval = 10,
    this.use24HourFormat = true,
  });

  /// 바텀시트 표시
  static Future<TimeOfDay?> show({
    required BuildContext context,
    TimeOfDay? initialTime,
    String title = '시간 선택',
    String? subtitle,
    int minuteInterval = 10,
    bool use24HourFormat = true,
  }) {
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TimePickerBottomSheet(
        initialTime: initialTime,
        title: title,
        subtitle: subtitle,
        minuteInterval: minuteInterval,
        use24HourFormat: use24HourFormat,
      ),
    );
  }

  @override
  State<TimePickerBottomSheet> createState() => _TimePickerBottomSheetState();
}

class _TimePickerBottomSheetState extends State<TimePickerBottomSheet> {
  late int _selectedHour;
  late int _selectedMinute;
  bool _isAM = true; // 12시간 형식용 (기본값 설정)
  
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _ampmController;

   @override
  void initState() {
    super.initState();
    
    final initial = widget.initialTime ?? TimeOfDay.now();
    
    // _isAM은 항상 초기화 (24시간 형식에서도 내부 계산용으로 사용)
    _isAM = initial.hour < 12;
    
    if (widget.use24HourFormat) {
      _selectedHour = initial.hour;
    } else {
      _selectedHour = initial.hourOfPeriod == 0 ? 12 : initial.hourOfPeriod;
    }
    
    // 분을 가장 가까운 interval로 반올림
    _selectedMinute = (initial.minute / widget.minuteInterval).round() * widget.minuteInterval;
    if (_selectedMinute >= 60) _selectedMinute = 60 - widget.minuteInterval;
    
    _hourController = FixedExtentScrollController(
      initialItem: widget.use24HourFormat ? _selectedHour : _selectedHour - 1,
    );
    _minuteController = FixedExtentScrollController(
      initialItem: _selectedMinute ~/ widget.minuteInterval,
    );
    _ampmController = FixedExtentScrollController(
      initialItem: _isAM ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _ampmController.dispose();
    super.dispose();
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
            
            // 선택된 시간 표시
            _buildSelectedTimeDisplay(context, theme),
            
            // 시간 선택 휠
            _buildTimePicker(context, theme),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 빠른 선택 버튼
            _buildQuickSelectButtons(context, theme),
            
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
              Icons.access_time,
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

  /// 선택된 시간 표시
  Widget _buildSelectedTimeDisplay(BuildContext context, ThemeData theme) {
    final displayTime = _getDisplayTime();
    
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 24),
        vertical: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor.withValues(alpha: 0.1),
            theme.primaryColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.schedule,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 28),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Text(
            displayTime,
            style: ResponsiveHelper.titleStyle(context).copyWith(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: ResponsiveHelper.getFontSize(context, 28),
            ),
          ),
        ],
      ),
    );
  }

  /// 시간 선택 휠
  Widget _buildTimePicker(BuildContext context, ThemeData theme) {
    final wheelHeight = ResponsiveHelper.spacing(context, 180);
    final itemExtent = ResponsiveHelper.spacing(context, 50);
    
    return Container(
      height: wheelHeight,
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // 선택 영역 하이라이트
          Center(
            child: Container(
              height: itemExtent,
              margin: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
              ),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.primaryColor.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          
          // 휠 피커들
          Row(
            children: [
              // 시간
              Expanded(
                flex: 2,
                child: _buildWheelPicker(
                  context,
                  theme,
                  controller: _hourController,
                  itemCount: widget.use24HourFormat ? 24 : 12,
                  itemBuilder: (index) {
                    final hour = widget.use24HourFormat ? index : index + 1;
                    return hour.toString().padLeft(2, '0');
                  },
                  onChanged: (index) {
                    setState(() {
                      _selectedHour = widget.use24HourFormat ? index : index + 1;
                    });
                  },
                  itemExtent: itemExtent,
                ),
              ),
              
              // 구분자
              Text(
                ':',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: ResponsiveHelper.getFontSize(context, 24),
                ),
              ),
              
              // 분
              Expanded(
                flex: 2,
                child: _buildWheelPicker(
                  context,
                  theme,
                  controller: _minuteController,
                  itemCount: 60 ~/ widget.minuteInterval,
                  itemBuilder: (index) {
                    final minute = index * widget.minuteInterval;
                    return minute.toString().padLeft(2, '0');
                  },
                  onChanged: (index) {
                    setState(() {
                      _selectedMinute = index * widget.minuteInterval;
                    });
                  },
                  itemExtent: itemExtent,
                ),
              ),
              
              // AM/PM (12시간 형식일 때만)
              if (!widget.use24HourFormat) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  flex: 2,
                  child: _buildWheelPicker(
                    context,
                    theme,
                    controller: _ampmController,
                    itemCount: 2,
                    itemBuilder: (index) => index == 0 ? '오전' : '오후',
                    onChanged: (index) {
                      setState(() {
                        _isAM = index == 0;
                      });
                    },
                    itemExtent: itemExtent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 개별 휠 피커
  Widget _buildWheelPicker(
    BuildContext context,
    ThemeData theme, {
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) itemBuilder,
    required void Function(int index) onChanged,
    required double itemExtent,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: itemExtent,
      perspective: 0.005,
      diameterRatio: 1.5,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          final isSelected = controller.hasClients && 
              controller.selectedItem == index;
          
          return Center(
            child: Text(
              itemBuilder(index),
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                color: isSelected 
                    ? theme.primaryColor 
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: isSelected 
                    ? ResponsiveHelper.getFontSize(context, 22)
                    : ResponsiveHelper.getFontSize(context, 18),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 빠른 선택 버튼
  Widget _buildQuickSelectButtons(BuildContext context, ThemeData theme) {
    final quickTimes = [
      ('09:00', 9, 0),
      ('12:00', 12, 0),
      ('14:00', 14, 0),
      ('18:00', 18, 0),
    ];
    
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '빠른 선택',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: quickTimes.map((time) {
              final isSelected = widget.use24HourFormat
                  ? _selectedHour == time.$2 && _selectedMinute == time.$3
                  : false;
              
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 4),
                  ),
                  child: Material(
                    color: isSelected 
                        ? theme.primaryColor 
                        : AppColors.grey100,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => _setQuickTime(time.$2, time.$3),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 10),
                        ),
                        child: Center(
                          child: Text(
                            time.$1,
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: isSelected 
                                  ? AppColors.surface 
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
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
              onPressed: () => Navigator.pop(context, _getSelectedTime()),
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

  /// 빠른 시간 설정
  void _setQuickTime(int hour, int minute) {
    setState(() {
      if (widget.use24HourFormat) {
        _selectedHour = hour;
        _hourController.jumpToItem(hour);
      } else {
        _isAM = hour < 12;
        _selectedHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        _hourController.jumpToItem(_selectedHour - 1);
        _ampmController.jumpToItem(_isAM ? 0 : 1);
      }
      _selectedMinute = minute;
      _minuteController.jumpToItem(minute ~/ widget.minuteInterval);
    });
  }

  /// 선택된 시간 가져오기
  TimeOfDay _getSelectedTime() {
    if (widget.use24HourFormat) {
      return TimeOfDay(hour: _selectedHour, minute: _selectedMinute);
    } else {
      int hour24;
      if (_isAM) {
        hour24 = _selectedHour == 12 ? 0 : _selectedHour;
      } else {
        hour24 = _selectedHour == 12 ? 12 : _selectedHour + 12;
      }
      return TimeOfDay(hour: hour24, minute: _selectedMinute);
    }
  }

  /// 표시용 시간 문자열
  String _getDisplayTime() {
    if (widget.use24HourFormat) {
      return '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}';
    } else {
      final ampm = _isAM ? '오전' : '오후';
      return '$ampm ${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}';
    }
  }
}

/// 📅⏰ 날짜+시간 통합 선택 바텀시트
class DateTimePickerBottomSheet extends StatefulWidget {
  final DateTime? initialDateTime;
  final String title;
  final String? subtitle;
  final DateTime? minDate;
  final DateTime? maxDate;
  final bool allowPastDates;
  final int minuteInterval;

  const DateTimePickerBottomSheet({
    super.key,
    this.initialDateTime,
    required this.title,
    this.subtitle,
    this.minDate,
    this.maxDate,
    this.allowPastDates = false,
    this.minuteInterval = 5,
  });

  /// 바텀시트 표시
  static Future<DateTime?> show({
    required BuildContext context,
    DateTime? initialDateTime,
    String title = '날짜 및 시간 선택',
    String? subtitle,
    DateTime? minDate,
    DateTime? maxDate,
    bool allowPastDates = false,
    int minuteInterval = 5,
  }) {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DateTimePickerBottomSheet(
        initialDateTime: initialDateTime,
        title: title,
        subtitle: subtitle,
        minDate: minDate,
        maxDate: maxDate,
        allowPastDates: allowPastDates,
        minuteInterval: minuteInterval,
      ),
    );
  }

  @override
  State<DateTimePickerBottomSheet> createState() => _DateTimePickerBottomSheetState();
}

class _DateTimePickerBottomSheetState extends State<DateTimePickerBottomSheet> {
  late DateTime? _selectedDate;
  late TimeOfDay _selectedTime;
  int _currentStep = 0; // 0: 날짜, 1: 시간

  // 시간 휠 컨트롤러
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late int _selectedHour;
  late int _selectedMinute;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateTime ?? DateTime.now();
    _selectedDate = initial;
    _selectedTime = TimeOfDay.fromDateTime(initial);

    _selectedHour = _selectedTime.hour;
    final rounded = (_selectedTime.minute / widget.minuteInterval).round() * widget.minuteInterval;
    _selectedMinute = rounded >= 60 ? 60 - widget.minuteInterval : rounded;

    _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute ~/ widget.minuteInterval);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
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
            
            // 선택된 날짜+시간 표시
            _buildSelectedDisplay(context, theme),
            
            // 탭 인디케이터
            _buildTabIndicator(context, theme),
            
            // 컨텐츠 (날짜 또는 시간)
            Flexible(
              child: _currentStep == 0
                  ? _buildDatePicker(context, theme)
                  : _buildTimePicker(context, theme),
            ),
            
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
              Icons.event,
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

  Widget _buildSelectedDisplay(BuildContext context, ThemeData theme) {
    final dateFormat = DateFormat('M월 d일 (E)', 'ko_KR');
    final timeStr = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      padding: ResponsiveHelper.cardPadding(context),
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
            Icons.calendar_today,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            _selectedDate != null 
                ? dateFormat.format(_selectedDate!)
                : '날짜 선택',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Icon(
            Icons.access_time,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            timeStr,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabIndicator(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTabButton(context, theme, 0, '날짜', Icons.calendar_today),
          _buildTabButton(context, theme, 1, '시간', Icons.access_time),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    BuildContext context,
    ThemeData theme,
    int index,
    String label,
    IconData icon,
  ) {
    final isSelected = _currentStep == index;
    
    return Expanded(
      child: Material(
        color: isSelected ? theme.primaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _currentStep = index),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.surface : AppColors.textSecondary,
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  label,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: isSelected ? AppColors.surface : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      child: CarrotStyleCalendar(
        mode: CalendarMode.single,
        selectedDate: _selectedDate,
        minDate: widget.minDate,
        maxDate: widget.maxDate,
        allowPastDates: widget.allowPastDates,
        onDateSelected: (date) {
          setState(() {
            _selectedDate = date;
            _currentStep = 1;
          });
        },
      ),
    );
  }

  Widget _buildTimePicker(BuildContext context, ThemeData theme) {
    final wheelHeight = ResponsiveHelper.spacing(context, 180);
    final itemExtent = ResponsiveHelper.spacing(context, 50);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 선택된 시간 미리보기
        Container(
          margin: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 24),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              theme.primaryColor.withValues(alpha: 0.1),
              theme.primaryColor.withValues(alpha: 0.05),
            ]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule, color: theme.primaryColor, size: ResponsiveHelper.iconSize(context, 24)),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: ResponsiveHelper.getFontSize(context, 28),
                ),
              ),
            ],
          ),
        ),

        // 휠 피커
        Container(
          height: wheelHeight,
          margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
          decoration: BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Center(
                child: Container(
                  height: itemExtent,
                  margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              Row(
                children: [
                  // 시
                  Expanded(
                    flex: 2,
                    child: _buildWheelColumn(
                      context, theme,
                      controller: _hourController,
                      itemCount: 24,
                      itemBuilder: (i) => i.toString().padLeft(2, '0'),
                      onChanged: (i) => setState(() {
                        _selectedHour = i;
                        _selectedTime = TimeOfDay(hour: _selectedHour, minute: _selectedMinute);
                      }),
                      itemExtent: itemExtent,
                    ),
                  ),
                  Text(
                    ':',
                    style: ResponsiveHelper.titleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: ResponsiveHelper.getFontSize(context, 24),
                    ),
                  ),
                  // 분
                  Expanded(
                    flex: 2,
                    child: _buildWheelColumn(
                      context, theme,
                      controller: _minuteController,
                      itemCount: 60 ~/ widget.minuteInterval,
                      itemBuilder: (i) => (i * widget.minuteInterval).toString().padLeft(2, '0'),
                      onChanged: (i) => setState(() {
                        _selectedMinute = i * widget.minuteInterval;
                        _selectedTime = TimeOfDay(hour: _selectedHour, minute: _selectedMinute);
                      }),
                      itemExtent: itemExtent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 빠른 선택
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
          child: Row(
            children: [('09:00', 9, 0), ('12:00', 12, 0), ('14:00', 14, 0), ('18:00', 18, 0)]
                .map((t) {
              final isSelected = _selectedHour == t.$2 && _selectedMinute == t.$3;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
                  child: Material(
                    color: isSelected ? theme.primaryColor : AppColors.grey100,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => setState(() {
                        _selectedHour = t.$2;
                        _selectedMinute = t.$3;
                        _selectedTime = TimeOfDay(hour: t.$2, minute: t.$3);
                        _hourController.jumpToItem(t.$2);
                        _minuteController.jumpToItem(t.$3 ~/ widget.minuteInterval);
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
                        child: Center(
                          child: Text(
                            t.$1,
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: isSelected ? AppColors.surface : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
    );
  }

  Widget _buildWheelColumn(
    BuildContext context,
    ThemeData theme, {
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) itemBuilder,
    required void Function(int) onChanged,
    required double itemExtent,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: itemExtent,
      perspective: 0.005,
      diameterRatio: 1.5,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          final isSelected = controller.hasClients && controller.selectedItem == index;
          return Center(
            child: Text(
              itemBuilder(index),
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                color: isSelected ? theme.primaryColor : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: isSelected
                    ? ResponsiveHelper.getFontSize(context, 22)
                    : ResponsiveHelper.getFontSize(context, 18),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildButtons(BuildContext context, ThemeData theme) {
    final isValid = _selectedDate != null;
    
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
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
                  '이전',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: AppColors.grey700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
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
              onPressed: isValid ? _handleNext : null,
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
                _currentStep == 0 ? '다음' : '선택 완료',
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

  void _handleNext() {
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
    } else {
      // 완료
      final result = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      Navigator.pop(context, result);
    }
  }
}