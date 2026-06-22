import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

/// TO 관련 다이얼로그 모음
class TOListDialogs {
  final BuildContext context;
  final FirestoreService firestoreService;
  final VoidCallback onChanged;

  TOListDialogs({
    required this.context,
    required this.firestoreService,
    required this.onChanged,
  });

/// TO 삭제 다이얼로그
  Future<void> showDeleteTODialog(TOItem toItem) async {
    final to = toItem.to;

    final checkResult = await firestoreService.checkTOBeforeDelete(to.id, businessId: to.businessId);
    final hasApplicants = checkResult['hasApplicants'] as bool;
    final confirmedCount = checkResult['confirmedCount'] as int;
    final totalCount = checkResult['totalCount'] as int;

    String content = '다음 TO를 삭제하시겠습니까?\n\n📋 ${to.title}';

    if (hasApplicants) {
      content += '\n\n👤 지원자: $totalCount명 (확정 $confirmedCount명)';
      if (confirmedCount > 0) {
        content += '\n⚠️ 확정된 근무자가 있습니다!\n삭제 시 모든 지원서가 자동 취소되고 알림이 발송됩니다.';
      } else {
        content += '\n삭제 시 모든 지원서가 자동 취소됩니다.';
      }
    }

    if (!context.mounted) return;
    final confirmed = await DialogHelper.showDeleteConfirm(
      context,
      itemName: '공고',
      additionalMessage: content,
    );

    if (confirmed == true) {
      try {
        final success = await firestoreService.deleteTO(to.id);
        if (success) {
          if (!context.mounted) return;
          onChanged();
        }
      } catch (e) {
        debugPrint('❌ TO 삭제 실패: $e');
        if (context.mounted) ToastHelper.showError('공고 삭제 중 오류가 발생했습니다.');
      }
    }
  }

  /// TO 마감 다이얼로그
  Future<void> showCloseTODialog(TOModel to) async {
    // [특이사항] uid null → '' 폴백 시 closedBy가 빈 문자열로 기록돼 감사 로그 훼손.
    // 세션 만료 시 작업 불가로 처리하여 미인증 상태의 마감 기록을 방지한다.
    final adminUID =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (adminUID == null) {
      ToastHelper.showError('로그인 세션이 만료되었습니다. 다시 로그인해 주세요.');
      return;
    }

    final confirmed = await DialogHelper.showCustom<bool>(
      context,
      title: '공고 마감',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이 공고를 마감 처리하시겠습니까?'),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
          Container(
            padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• 더 이상 지원을 받을 수 없습니다', 
                  style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                ),
                Text(
                  '• 재오픈으로 다시 활성화 가능합니다', 
                  style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
          ),
          child: const Text('마감'),
        ),
      ],
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    DialogHelper.showLoading(context, message: '처리 중...');

    try {
      final success = await firestoreService.closeTOManually(to.id, adminUID);

      if (!context.mounted) return;
      Navigator.pop(context); // 로딩 닫기

      if (success) {
        ToastHelper.showSuccess('공고가 마감되었습니다.');
        onChanged();
      } else {
        ToastHelper.showError('공고 마감에 실패했습니다.');
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      debugPrint('❌ TO 마감 실패: $e');
      ToastHelper.showError('공고 마감 중 오류가 발생했습니다.');
    }
  }

  /// TO 재오픈 다이얼로그
  Future<void> showReopenTODialog(TOModel to) async {
    final adminUID =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (adminUID == null) {
      ToastHelper.showError('로그인 세션이 만료되었습니다. 다시 로그인해 주세요.');
      return;
    }

    if (to.isTimeExpired) {
      _showTimeExpiredDialog(to);
      return;
    }

    final isFull = to.isFull;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '공고 재오픈',
        icon: Icons.lock_open,
        headerColor: AppColors.success,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 공고를 다시 오픈하시겠습니까?'),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

            if (isFull) ...[
              StyledDialogInfoCard.warning('이미 인원이 충족된 공고입니다.\n추가 지원자를 받으시겠습니까?'),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            ],

            StyledDialogInfoCard.success('• 지원자가 다시 지원할 수 있습니다\n• 기존 확정 지원자는 유지됩니다'),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '재오픈',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    DialogHelper.showLoading(context, message: '재오픈 중...');

    try {
      final success = await firestoreService.reopenTO(to.id, adminUID);

      if (!context.mounted) return;
      Navigator.pop(context);

      if (success) {
        ToastHelper.showSuccess('공고가 재오픈되었습니다.');
        onChanged();
      } else {
        ToastHelper.showError('공고 재오픈에 실패했습니다.');
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      debugPrint('❌ TO 재오픈 실패: $e');
      ToastHelper.showError('공고 재오픈 중 오류가 발생했습니다.');
    }
  }

  // ========================================
  // Helper 메서드들
  // ========================================

  void _showTimeExpiredDialog(TOModel to) {
    showDialog(
      context: context,
      builder: (context) => StyledDialog(
        title: '재오픈 불가',
        icon: Icons.error_outline,
        headerColor: AppColors.error,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무 시작 시간이 지난 TO는 재오픈할 수 없습니다.',
              style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            StyledDialogInfoCard.error(
              '근무일: ${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(to.date)}\n근무 시간: ${to.startTime} ~ ${to.endTime}',
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            Text(
              '새로운 날짜로 TO를 생성하세요.',
              style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        actions: [
          StyledDialogButton.primary(
            text: '확인',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
  
}