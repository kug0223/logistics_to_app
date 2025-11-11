import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/work_type_icon.dart';

/// 지원하기 확인 다이얼로그
class ApplyDialog {
  static Future<bool> show({
    required BuildContext context,
    required WorkDetailModel work,
    required TOModel to,
    required VoidCallback onSuccess,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('지원하기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '다음 업무에 지원하시겠습니까?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // ✅ 공통 위젯 사용
                      WorkTypeIcon.buildWithBackground(
                        iconString: work.workTypeIcon ?? 'work',
                        iconColor: work.workTypeColor,
                        backgroundColor: work.workTypeBackgroundColor,
                        size: 18,
                        containerSize: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          work.workType,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoText(
                    icon: Icons.access_time,
                    text: '${work.startTime} ~ ${work.endTime}',
                  ),
                  const SizedBox(height: 4),
                  _buildInfoText(
                    icon: Icons.attach_money,
                    text: FormatHelper.formatWage(work.wage),
                    color: Colors.green[700],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('지원하기'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      return await _applyToWork(
        context: context,
        work: work,
        to: to,
        onSuccess: onSuccess,
      );
    }

    return false;
  }

  static Widget _buildInfoText({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: color ?? Colors.grey[700],
          ),
        ),
      ],
    );
  }

  /// 실제 지원 처리
  static Future<bool> _applyToWork({
    required BuildContext context,
    required WorkDetailModel work,
    required TOModel to,
    required VoidCallback onSuccess,
  }) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return false;
      }

      final firestoreService = FirestoreService();

      // 중복 지원 체크 (직접 쿼리)
      final snapshot = await FirebaseFirestore.instance
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('businessId', isEqualTo: to.businessId)
          .where('toTitle', isEqualTo: to.title)
          .where('workDate', isEqualTo: Timestamp.fromDate(to.date))
          .where('selectedWorkType', isEqualTo: work.workType)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        ToastHelper.showWarning('이미 지원한 업무입니다.');
        return false;
      }

      // 지원서 생성
      final success = await firestoreService.applyToTOWithWorkType(
        uid: uid,
        businessId: to.businessId,
        businessName: to.businessName,
        toTitle: to.title,
        workDate: to.date,
        selectedWorkType: work.workType,
        wage: work.wage,
        startTime: work.startTime,
        endTime: work.endTime,
        // ⭐ Phase 1: 장기 공고 정보 추가
        workEndDate: to.endDate,
        workDays: to.workDays,
        type: to.isLongTerm ? 'long_term' : 'short',
      );

      if (success) {
        ToastHelper.showSuccess('지원이 완료되었습니다!');
        print('🎉 지원 성공! onSuccess() 호출');
        onSuccess();
        print('✅ onSuccess() 호출 완료');
        return true;
      } else {
        ToastHelper.showError('지원에 실패했습니다.');
        return false;
      }
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }
}