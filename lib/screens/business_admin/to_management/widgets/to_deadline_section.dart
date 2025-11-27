import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/toast_helper.dart';
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
  
  /// 범위 종료일 (장기 TO 생성 시 마감일 유효성 검사용)
  final DateTime? rangeEndDate;

  const TODeadlineSection({
    super.key,
    required this.isLongTerm,
    this.hoursBeforeStart = 2,
    this.onHoursChanged,
    this.fixedDeadline,
    this.onFixedDeadlineChanged,
    this.rangeEndDate,
  });

  @override
  Widget build(BuildContext context) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '지원 마감 설정',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          if (isLongTerm)
            _buildFixedDeadline(context)
          else
            _buildHoursBeforeDeadline(context),
        ],
      ),
    );
  }

  /// 단기 TO: N시간 전 마감
  Widget _buildHoursBeforeDeadline(BuildContext context) {
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
                theme.primaryColor.withOpacity(0.1),
                theme.primaryColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '각 업무별로 시작 시간 기준으로 자동 마감됩니다',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: theme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 시간 선택
        Row(
          children: [
            Text(
              '업무 시작',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.primaryColor),
              ),
              child: DropdownButton<int>(
                value: hoursBeforeStart,
                underline: const SizedBox(),
                items: List.generate(24, (index) => index + 1)
                    .map((hour) => DropdownMenuItem(
                          value: hour,
                          child: Text(
                            '$hour시간 전',
                            style: ResponsiveHelper.bodyStyle(context),
                          ),
                        ))
                    .toList(),
                onChanged: onHoursChanged != null 
                    ? (value) => onHoursChanged!(value!)
                    : null,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '마감',
              style: ResponsiveHelper.bodyStyle(context),
            ),
          ],
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
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.orange[700],
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '지원 마감 날짜와 시간을 직접 설정하세요',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.orange[900],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        
        // 날짜/시간 선택 버튼
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectDateTime(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '지원 마감',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        fixedDeadline != null
                            ? DateFormat('yyyy-MM-dd HH:mm').format(fixedDeadline!)
                            : '날짜와 시간을 선택하세요',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          color: fixedDeadline != null ? Colors.black : Colors.grey[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.calendar_today,
                    color: theme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDateTime(BuildContext context) async {
    if (rangeEndDate == null && onFixedDeadlineChanged != null) {
      ToastHelper.showError('먼저 근무 종료일을 선택해주세요');
      return;
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: fixedDeadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: rangeEndDate ?? DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ko', 'KR'),
    );

    if (pickedDate != null && context.mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: fixedDeadline != null 
            ? TimeOfDay.fromDateTime(fixedDeadline!)
            : const TimeOfDay(hour: 18, minute: 0),
      );

      if (pickedTime != null && onFixedDeadlineChanged != null) {
        final dateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        onFixedDeadlineChanged!(dateTime);
      }
    }
  }
}