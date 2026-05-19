import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import 'to_section_container.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/app_select_field.dart';

/// ✨ TO 공개 설정 섹션
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TOPublishSection extends StatelessWidget {
  /// 공개 모드: 'immediate' (즉시) | 'scheduled' (예약)
  final String publishMode;
  final void Function(String mode) onPublishModeChanged;
  
  /// 예약 설정: D-N (1, 2, 3...)
  final int publishDaysBefore;
  final void Function(int days) onDaysBeforeChanged;
  
  /// 예약 설정: 시간 ('09:00', '14:00' 등)
  final String publishTime;
  final void Function(String time) onTimeChanged;
  
  /// 미리보기용 날짜 목록 (단기: 선택된 날짜들, 장기: 시작일)
  final List<DateTime> previewDates;
  
  /// 장기 근무 여부
  final bool isLongTerm;

  const TOPublishSection({
    super.key,
    required this.publishMode,
    required this.onPublishModeChanged,
    this.publishDaysBefore = 1,
    required this.onDaysBeforeChanged,
    this.publishTime = '14:00',
    required this.onTimeChanged,
    this.previewDates = const [],
    this.isLongTerm = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 타이틀
          Text(
            '공고 공개 설정',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 즉시 공개 옵션
          _buildRadioOption(
            context,
            theme,
            value: 'immediate',
            title: '즉시 공개',
            subtitle: '등록 완료 후 바로 노출',
            icon: Icons.visibility,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 예약 공개 옵션
          _buildRadioOption(
            context,
            theme,
            value: 'scheduled',
            title: '예약 공개',
            subtitle: '지정한 시간에 자동 공개',
            icon: Icons.schedule,
          ),
          
          // 예약 설정 상세 (예약 모드일 때만)
          if (publishMode == 'scheduled') ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildScheduleSettings(context, theme),
            
            // 미리보기
            if (previewDates.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildPreview(context, theme),
            ],
          ],
        ],
      ),
    );
  }

  /// 라디오 옵션 위젯
  Widget _buildRadioOption(
    BuildContext context,
    ThemeData theme, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = publishMode == value;
    
    return InkWell(
      onTap: () => onPublishModeChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.primaryColor.withValues(alpha: 0.1) 
              : AppColors.grey50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? theme.primaryColor 
                : AppColors.grey300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 라디오 버튼
            Container(
              width: ResponsiveHelper.spacing(context, 24),
              height: ResponsiveHelper.spacing(context, 24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? theme.primaryColor : AppColors.grey400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: ResponsiveHelper.spacing(context, 12),
                        height: ResponsiveHelper.spacing(context, 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.primaryColor,
                        ),
                      ),
                    )
                  : null,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            
            // 아이콘
            Icon(
              icon,
              color: isSelected ? theme.primaryColor : AppColors.grey600,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            
            // 텍스트
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? theme.primaryColor : AppColors.grey800,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Text(
                    subtitle,
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 예약 설정 상세
  Widget _buildScheduleSettings(BuildContext context, ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // D-N 선택
          Text(
            '근무일 기준 (전)',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          AppSelectField<int>(
            value: publishDaysBefore,
            hintText: 'D-N 선택',
            sheetTitle: '공개 기준일 선택',
            items: const [1, 2, 3, 4, 5, 7, 14],
            labelOf: (d) => 'D-$d (근무 $d일 전)',
            prefixIcon: Icons.event,
            onChanged: (value) {
              if (value != null) onDaysBeforeChanged(value);
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 공개 시간 선택
          Text(
            '공개 시간',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          AppSelectField<String>(
            value: publishTime,
            hintText: '시간 선택',
            sheetTitle: '공개 시간 선택',
            items: _generateTimeOptions(),
            labelOf: (t) => t,
            prefixIcon: Icons.access_time,
            onChanged: (value) {
              if (value != null) onTimeChanged(value);
            },
          ),
        ],
      ),
    );
  }

  /// 시간 옵션 생성 (1시간 단위)
  List<String> _generateTimeOptions() {
    final times = <String>[];
    for (int hour = 6; hour <= 22; hour++) {
      times.add('${hour.toString().padLeft(2, '0')}:00');
    }
    return times;
  }

  /// 미리보기
  Widget _buildPreview(BuildContext context, ThemeData theme) {
    
    // 최대 3개만 표시
    final displayDates = previewDates.take(3).toList();
    final hasMore = previewDates.length > 3;
    
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '공개 일정 미리보기',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          ...displayDates.map((date) {
            final publishAt = _calculatePublishAt(date);
            final publishFormat = DateFormat('M/d (E) HH:mm', 'ko_KR');
            
            return Padding(
              padding: EdgeInsets.only(
                bottom: ResponsiveHelper.spacing(context, 4),
              ),
              child: Row(
                children: [
                  Text(
                    isLongTerm ? '시작일' : FormatHelper.formatDate(date),
                    style: ResponsiveHelper.smallStyle(context),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Icon(
                    Icons.arrow_forward,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: AppColors.grey500,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '${publishFormat.format(publishAt)} 공개',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.warningDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }),
          
          if (hasMore)
            Text(
              '외 ${previewDates.length - 3}개...',
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.grey500,
              ),
            ),
        ],
      ),
    );
  }

  /// publishAt 계산
  DateTime _calculatePublishAt(DateTime workDate) {
    final targetDate = workDate.subtract(Duration(days: publishDaysBefore));
    final timeParts = publishTime.split(':');
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
  }
}
