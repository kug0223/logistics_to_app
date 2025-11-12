import 'package:flutter/material.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../utils/format_helper.dart';

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
            Text(work.workTypeIcon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                work.workType,
                style: const TextStyle(fontSize: 18),
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
                icon: Icons.access_time,
                label: '근무 시간',
                value: '${work.startTime} ~ ${work.endTime}',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                icon: Icons.attach_money,
                label: '급여',
                value: FormatHelper.formatWage(work.wage),
                valueColor: Colors.green[700],
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                icon: Icons.people,
                label: '모집 인원',
                value: '${work.requiredCount}명',
              ),
              // TODO: WorkDetailModel에 description 필드 추가 필요
              /* 
              if (work.description != null && work.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                _buildInfoRow(
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
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}