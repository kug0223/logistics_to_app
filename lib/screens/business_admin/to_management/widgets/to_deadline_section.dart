import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/toast_helper.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/pickers/date_picker_bottom_sheet.dart';
import '../../../../widgets/pickers/time_picker_bottom_sheet.dart';
import '../../../../widgets/app_select_field.dart';
import 'to_section_container.dart';

/// ✨ TO 마감 설정 섹션
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TODeadlineSection extends StatelessWidget {
  /// 장기 근무 여부
  final bool isLongTerm;
  
  /// N시간 전 마감 (단기용)
  final int hoursBeforeStart;
  final void Function(int hours)? onHoursChanged;
  
  /// 고정 마감 시간 (장기용)
  final DateTime? fixedDeadline;
  final void Function(DateTime dateTime)? onFixedDeadlineChanged;
  
  /// 근무 시작일 (장기 TO 생성 시 마감일 유효성 검사용 — 마감일은 시작일 이전이어야 함)
  final DateTime? rangeStartDate;

  const TODeadlineSection({
    super.key,
    required this.isLongTerm,
    this.hoursBeforeStart = 2,
    this.onHoursChanged,
    this.fixedDeadline,
    this.onFixedDeadlineChanged,
    this.rangeStartDate,
  });

  @override
  Widget build(BuildContext context) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          _buildSectionHeader(context),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          if (isLongTerm)
            _buildFixedDeadline(context)
          else
            _buildHoursBeforeDeadline(context),
        ],
      ),
    );
  }

  /// 섹션 헤더
  Widget _buildSectionHeader(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.timer_outlined,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '지원 마감 설정',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                isLongTerm ? '고정 마감 시간' : '업무 시작 기준 자동 마감',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 단기 TO: N시간 전 마감
  Widget _buildHoursBeforeDeadline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 안내 메시지
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.infoBg,
                AppColors.infoBg.withValues(alpha: 0.5),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.infoLight,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.info_outline,
                  color: AppColors.infoDark,
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '각 업무별로 시작 시간 기준으로 자동 마감됩니다',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.infoDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        
        AppSelectField<int>(
          value: hoursBeforeStart,
          hintText: '마감 기준 시간 선택',
          sheetTitle: '마감 시간 선택',
          items: List.generate(24, (i) => i + 1),
          labelOf: (h) => '$h시간 전 마감',
          prefixIcon: Icons.schedule,
          enabled: onHoursChanged != null,
          showSearch: false,
          onChanged: (value) {
            if (value != null) onHoursChanged!(value);
          },
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        
        // 예시 안내
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppColors.textSecondary,
                size: ResponsiveHelper.iconSize(context, 16),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  '예: 09:00 시작 업무 → $hoursBeforeStart시간 전인 ${_getExampleTime(hoursBeforeStart)}에 마감',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 장기 TO: 고정 날짜/시간 마감
  Widget _buildFixedDeadline(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 안내 메시지
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.warningBg,
                AppColors.warningBg.withValues(alpha: 0.5),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.warningLight,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.event_available,
                  color: AppColors.warningDark,
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '지원 마감 날짜와 시간을 직접 설정하세요',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.warningDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        
        // 날짜/시간 선택 버튼
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectDateTime(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: fixedDeadline != null 
                    ? theme.primaryColor.withValues(alpha: 0.05)
                    : AppColors.grey50,
                border: Border.all(
                  color: fixedDeadline != null 
                      ? theme.primaryColor
                      : AppColors.border,
                  width: fixedDeadline != null ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // 아이콘
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                    decoration: BoxDecoration(
                      color: fixedDeadline != null
                          ? theme.primaryColor.withValues(alpha: 0.15)
                          : AppColors.grey200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.calendar_today,
                      color: fixedDeadline != null 
                          ? theme.primaryColor
                          : AppColors.textSecondary,
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                  ),
                  
                  SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                  
                  // 텍스트
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '지원 마감',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        Text(
                          fixedDeadline != null
                              ? DateFormat('yyyy년 MM월 dd일 HH:mm', 'ko_KR').format(fixedDeadline!)
                              : '날짜와 시간을 선택하세요',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            color: fixedDeadline != null 
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 화살표
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.edit_calendar,
                      color: theme.primaryColor,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // 선택된 마감일이 있으면 남은 시간 표시
        if (fixedDeadline != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _buildRemainingTime(context),
        ],
      ],
    );
  }

  /// 남은 시간 표시
  Widget _buildRemainingTime(BuildContext context) {
    final now = DateTime.now();
    final difference = fixedDeadline!.difference(now);
    
    String remainingText;
    Color statusColor;
    IconData statusIcon;
    
    if (difference.isNegative) {
      remainingText = '마감됨';
      statusColor = AppColors.error;
      statusIcon = Icons.timer_off;
    } else if (difference.inDays > 0) {
      remainingText = '${difference.inDays}일 ${difference.inHours % 24}시간 남음';
      statusColor = AppColors.success;
      statusIcon = Icons.timer;
    } else if (difference.inHours > 0) {
      remainingText = '${difference.inHours}시간 ${difference.inMinutes % 60}분 남음';
      statusColor = AppColors.warning;
      statusIcon = Icons.timer;
    } else {
      remainingText = '${difference.inMinutes}분 남음';
      statusColor = AppColors.error;
      statusIcon = Icons.timer;
    }
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            color: statusColor,
            size: ResponsiveHelper.iconSize(context, 16),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            remainingText,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: statusColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 예시 시간 계산
  String _getExampleTime(int hoursBefore) {
    final example = DateTime(2024, 1, 1, 9, 0).subtract(Duration(hours: hoursBefore));
    return DateFormat('HH:mm').format(example);
  }

  /// 날짜/시간 선택 (새 피커 사용)
  Future<void> _selectDateTime(BuildContext context) async {
    if (rangeStartDate == null && onFixedDeadlineChanged != null) {
      ToastHelper.showError('먼저 근무 시작일을 선택해주세요');
      return;
    }

    // 마감일은 오늘 이후 ~ 시작일 이전까지 선택 가능
    final maxDate = rangeStartDate ?? DateTime.now().add(const Duration(days: 365));

    // 1단계: 날짜 선택 (커스텀 바텀시트)
    final pickedDate = await DatePickerBottomSheet.show(
      context: context,
      // 과거 마감일이 저장된 경우 오늘로 초기값 설정 (과거 선택 방지)
      initialDate: (fixedDeadline != null && fixedDeadline!.isAfter(DateTime.now()))
          ? fixedDeadline!
          : DateTime.now(),
      title: '마감 날짜 선택',
      subtitle: '지원 마감일을 선택하세요 (시작일 이전)',
      minDate: DateTime.now(),
      maxDate: maxDate,
    );

    if (pickedDate != null && context.mounted) {
      // 2단계: 시간 선택 (커스텀 휠 피커)
      final pickedTime = await TimePickerBottomSheet.show(
        context: context,
        initialTime: fixedDeadline != null 
            ? TimeOfDay.fromDateTime(fixedDeadline!)
            : const TimeOfDay(hour: 18, minute: 0),
        title: '마감 시간 선택',
        subtitle: '지원 마감 시간을 선택하세요',
        minuteInterval: 5,
      );

      if (pickedTime != null && context.mounted && onFixedDeadlineChanged != null) {
        final dateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        if (dateTime.isBefore(DateTime.now())) {
          ToastHelper.showError('마감 시간은 현재 시각 이후여야 합니다');
          return;
        }
        onFixedDeadlineChanged!(dateTime);
      }
    }
  }
}