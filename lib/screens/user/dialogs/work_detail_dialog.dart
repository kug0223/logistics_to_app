import 'package:flutter/material.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../../theme/app_colors.dart';

/// 업무 상세 다이얼로그
class WorkDetailDialog {
  static void show({
    required BuildContext context,
    required WorkDetailModel work,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(
              work.workTypeIcon, 
              style: TextStyle(
                fontSize: ResponsiveHelper.getFontSize(context, 24),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Text(
                work.workType,
                style: ResponsiveHelper.subtitleStyle(context),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(
                context: context,
                icon: Icons.access_time,
                label: '근무 시간',
                value: '${work.startTime} ~ ${work.endTime}',
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildInfoRow(
                context: context,
                icon: Icons.attach_money,
                label: '급여',
                value: FormatHelper.formatWage(work.wage),
                valueColor: AppColors.successDark,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildInfoRow(
                context: context,
                icon: Icons.people,
                label: '모집 인원',
                value: '${work.requiredCount}명',
              ),
              // TODO: WorkDetailModel에 description 필드 추가 필요
              /* 
              if (work.description != null && work.description!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                const Divider(),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildInfoRow(
                  context: context,
                  icon: Icons.description,
                  label: '상세 설명',
                  value: work.description!,
                ),
              ],
              */
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  static Widget _buildInfoRow({
    required BuildContext context,  // ⭐ 추가
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon, 
          size: ResponsiveHelper.iconSize(context, 20), 
          color: AppColors.grey600
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                value,
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: valueColor ?? Colors.black87,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
