import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';

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
              style: ResponsiveHelper.bodyStyle(dialogContext,
                  color: AppColors.grey700),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // ✅ 공통 위젯 사용
                      WorkTypeIcon.buildWithBackground(
                        iconString: work.workTypeIcon,
                        iconColor: work.workTypeColor,
                        backgroundColor: work.workTypeBackgroundColor,
                        size: 18,
                        containerSize: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          work.workType,
                          style: ResponsiveHelper.bodyStyle(dialogContext)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoText(
                    context: dialogContext,
                    icon: Icons.access_time,
                    text: '${work.startTime} ~ ${work.endTime}',
                  ),
                  const SizedBox(height: 4),
                  _buildInfoText(
                    context: dialogContext,
                    icon: Icons.attach_money,
                    text: FormatHelper.formatWage(work.wage),
                    color: AppColors.successDark,
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
      return _applyToWork(
        context: context,
        work: work,
        to: to,
        onSuccess: onSuccess,
      );
    }

    return false;
  }

  static Widget _buildInfoText({
    required BuildContext context,
    required IconData icon,
    required String text,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon,
            size: ResponsiveHelper.iconSize(context, 14),
            color: color ?? AppColors.grey600),
        const SizedBox(width: 6),
        Text(
          text,
          style: ResponsiveHelper.smallStyle(context,
              color: color ?? AppColors.grey700),
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

      // [S-01] 중복 지원 경합 분석:
      // 이 체크(1차)와 applyToTOWithWorkType 호출 사이에 짧은 gap이 있으나,
      // applyToTO 내부에서 Source.server 기반 2차 중복 체크(application_firestore.dart:351)를
      // 수행하므로 서버 측 방어가 이중으로 존재함. 추가 Firestore Rules 불필요.
      //
      // [설계 주의] 이 1차 쿼리는 toId가 아닌 businessId+toTitle+workDate+workType+time 조합으로
      // 검색한다. 동명의 다른 공고에서 오탐이 이론상 가능하나, 2차 체크(applyToTO)에서
      // toId 기반으로 정확히 확인하므로 실질적 영향 없음. 1차는 빠른 UI 차단용 목적이다.
      final snapshot = await FirebaseFirestore.instance
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('businessId', isEqualTo: to.businessId)
          .where('toTitle', isEqualTo: to.title)
          .where('workDate', isEqualTo: Timestamp.fromDate(to.date))
          .where('selectedWorkType', isEqualTo: work.workType)
          .where('startTime', isEqualTo: work.startTime)
          .where('endTime', isEqualTo: work.endTime)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // ⭐ Phase 2: 취소된 지원인지 확인
        final docData = snapshot.docs.first.data();
        final status = docData['status'];
        
        debugPrint('🔍 apply_dialog 중복 체크: status = $status');
        
        if (AppStatus.inactiveStates.contains(status)) {
          debugPrint('✅ 취소된 지원 → 재지원 허용');
          // 계속 진행
        } else {
          debugPrint('❌ 유효한 지원 존재 (status: $status) → 차단');
          ToastHelper.showWarning('이미 지원한 업무입니다.');
          return false;
        }
      }

      // 지원서 생성
      final success = await firestoreService.applyToTOWithWorkType(
        uid: uid,
        businessId: to.businessId,
        businessName: to.businessName,
        toTitle: to.title,
        workDate: to.date,
        selectedWorkType: work.workType,
        workDetailId: work.id,
        wage: work.wage,
        // 🔥 업무 상세 정보 추가
        wageType: work.wageType,
        workTypeIcon: work.workTypeIcon,
        workTypeColor: work.workTypeColor,
        workTypeBackgroundColor: work.workTypeBackgroundColor,
        startTime: work.startTime,
        endTime: work.endTime,
        // ⭐ Phase 1: 장기 공고 정보 추가
        workEndDate: to.endDate,
        workDays: to.workDays,
        type: to.isLongTerm ? 'long_term' : 'short',
      );

      if (success) {
        ToastHelper.showSuccess('지원이 완료되었습니다!');
        debugPrint('🎉 지원 성공! onSuccess() 호출');
        onSuccess();
        debugPrint('✅ onSuccess() 호출 완료');
        return true;
      } else {
        ToastHelper.showError('지원에 실패했습니다.');
        return false;
      }
    } catch (e) {
      debugPrint('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }
}
