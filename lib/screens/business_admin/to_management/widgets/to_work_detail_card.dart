import 'package:flutter/material.dart';
import '../../../../models/work_detail_input.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../widgets/work_type_icon.dart';

/// ✨ TO 업무 상세 카드
/// WorkDetailInput (create) 또는 WorkDetailModel (edit) 모두 지원
class TOWorkDetailCard extends StatelessWidget {
  // 공통 필드
  final String workType;
  final String workTypeIcon;
  final String workTypeColor;
  final String? workTypeBackgroundColor;
  final int wage;
  final int requiredCount;
  final String startTime;
  final String endTime;
  final String wageType;
  
  // edit에서만 사용
  final int? currentCount;
  final bool canDelete;
  
  // 콜백
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const TOWorkDetailCard({
    super.key,
    required this.workType,
    required this.workTypeIcon,
    required this.workTypeColor,
    this.workTypeBackgroundColor,
    required this.wage,
    required this.requiredCount,
    required this.startTime,
    required this.endTime,
    this.wageType = 'hourly',
    this.currentCount,
    this.canDelete = true,
    this.onEdit,
    this.onDelete,
  });

  /// WorkDetailInput에서 생성
  factory TOWorkDetailCard.fromInput({
    required WorkDetailInput detail,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return TOWorkDetailCard(
      workType: detail.workType ?? '',
      workTypeIcon: detail.workTypeIcon,
      workTypeColor: detail.workTypeColor,
      workTypeBackgroundColor: detail.workTypeBackgroundColor,
      wage: detail.wage ?? 0,
      requiredCount: detail.requiredCount ?? 0,
      startTime: detail.startTime ?? '',
      endTime: detail.endTime ?? '',
      wageType: detail.wageType,
      canDelete: true,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }

  /// WorkDetailModel에서 생성
  factory TOWorkDetailCard.fromModel({
    required WorkDetailModel work,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return TOWorkDetailCard(
      workType: work.workType,
      workTypeIcon: work.workTypeIcon,
      workTypeColor: work.workTypeColor,
      workTypeBackgroundColor: work.workTypeBackgroundColor,
      wage: work.wage,
      requiredCount: work.requiredCount,
      startTime: work.startTime,
      endTime: work.endTime,
      wageType: work.wageType,
      currentCount: work.currentCount,
      canDelete: work.currentCount == 0,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }

  String get _wageTypeLabel {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      case 'monthly':
        return '월급';
      default:
        return '급여';
    }
  }

  String get _formattedWage {
    return wage.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = FormatHelper.parseColor(workTypeBackgroundColor ?? '#2196F3');
    final iconColor = FormatHelper.parseColor(workTypeColor);

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[50]!,
            Colors.grey[100]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 아이콘 + 업무명 + 버튼들
          Row(
            children: [
              // 아이콘
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: WorkTypeIcon.buildFromString(
                  workTypeIcon,
                  color: iconColor,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              
              // 업무명 + 시간
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workType,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text(
                          '$startTime ~ $endTime',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // 수정 버튼 (edit 모드에서만)
              if (onEdit != null) ...[
                Material(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                      child: Icon(
                        Icons.edit,
                        color: Colors.orange[700],
                        size: ResponsiveHelper.iconSize(context, 20),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              ],
              
              // 삭제 버튼
              if (onDelete != null)
                Material(
                  color: canDelete ? Colors.red[50] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: canDelete ? onDelete : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                      child: Icon(
                        Icons.delete_outline,
                        color: canDelete ? Colors.red[700] : Colors.grey[400],
                        size: ResponsiveHelper.iconSize(context, 20),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 하단: 급여 + 인원
          Row(
            children: [
              // 급여
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _wageTypeLabel,
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      '$_formattedWage원',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
              
              Container(
                width: 1,
                height: 40,
                color: Colors.grey[300],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              
              // 인원
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '필요 인원',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      children: [
                        Text(
                          '$requiredCount명',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                        // 확정 인원 표시 (edit 모드)
                        if (currentCount != null && currentCount! > 0) ...[
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$currentCount명 확정',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: Colors.orange[900],
                              ).copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}