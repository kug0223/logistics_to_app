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
    if (checkResult['hasError'] == true) {
      if (context.mounted) ToastHelper.showError('지원자 정보를 확인할 수 없습니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    final hasApplicants = checkResult['hasApplicants'] as bool;
    final confirmedCount = checkResult['confirmedCount'] as int;
    final totalCount = checkResult['totalCount'] as int;

    // [4I.1A] delete dialog copy 개선 — StyledDialog 패턴, 정확한 semantics
    // 삭제: Firestore 문서 제거(되돌릴 수 없음), 계약/근무 기록 유지, 지원서 자동 취소
    String bodyText =
        '삭제한 공고는 목록에서 제거되며 되돌릴 수 없습니다.\n'
        '이미 생성된 계약·근무 기록은 유지됩니다.';
    if (hasApplicants) {
      if (confirmedCount > 0) {
        bodyText += '\n\n확정 근무자 $confirmedCount명 포함, 총 $totalCount명의 지원서가 자동 취소됩니다.';
      } else {
        bodyText += '\n\n대기 중인 지원서 $totalCount건이 자동 취소됩니다.';
      }
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StyledDialog(
        title: '공고 삭제',
        subtitle: to.title,
        icon: Icons.delete_forever,
        headerColor: AppColors.error,
        content: StyledDialogInfoCard(
          message: bodyText,
          icon: confirmedCount > 0 ? Icons.warning_amber : Icons.info_outline,
          color: confirmedCount > 0 ? AppColors.warning : AppColors.info,
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          StyledDialogButton.danger(
            text: '삭제',
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await firestoreService.deleteTO(to.id);
        if (success) {
          if (!context.mounted) return;
          onChanged();
        } else {
          if (context.mounted) ToastHelper.showError('공고 삭제에 실패했습니다.');
        }
      } catch (e) {
        debugPrint('❌ TO 삭제 실패: $e');
        if (context.mounted) ToastHelper.showError('공고 삭제 중 오류가 발생했습니다.');
      }
    }
  }

  /// TO 마감 다이얼로그
  Future<void> showCloseTODialog(TOModel to) async {
    // uid null → '' 폴백 시 closedBy가 빈 문자열로 기록돼 감사 로그 훼손.
    // 세션 만료 시 작업 불가로 처리하여 미인증 상태의 마감 기록을 방지한다.
    final adminUID =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (adminUID == null) {
      ToastHelper.showError('로그인 세션이 만료되었습니다. 다시 로그인해 주세요.');
      return;
    }

    // [4I.1] StyledDialog 패턴으로 전환, copy 업데이트
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StyledDialog(
        title: '공고 종료',
        subtitle: '이 공고를 종료할까요?',
        icon: Icons.lock_outline,
        headerColor: AppColors.warning,
        content: StyledDialogInfoCard.warning(
          '신규 지원을 받지 않습니다.\n'
          '기존 지원자는 그대로 유지되며, 확정된 근무 일정은 변경되지 않습니다.\n\n'
          '재오픈으로 언제든 다시 활성화할 수 있습니다.',
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          StyledDialogButton.primary(
            text: '종료',
            backgroundColor: AppColors.warning,
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);

    DialogHelper.showLoading(context, message: '처리 중...');

    bool? success;
    try {
      success = await firestoreService.closeTOManually(to.id, adminUID);
    } catch (e) {
      debugPrint('❌ TO 마감 실패: $e');
      if (context.mounted) ToastHelper.showError('공고 종료 중 오류가 발생했습니다.');
    } finally {
      if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
    }

    if (success == null) return;
    if (success) {
      ToastHelper.showSuccess('공고가 종료되었습니다.');
      onChanged();
    } else {
      ToastHelper.showError('공고 종료에 실패했습니다.');
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
      barrierDismissible: false,
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
    final rootNav = Navigator.of(context, rootNavigator: true);

    DialogHelper.showLoading(context, message: '재오픈 중...');

    bool? success;
    try {
      success = await firestoreService.reopenTO(to.id, adminUID);
    } catch (e) {
      debugPrint('❌ TO 재오픈 실패: $e');
      if (context.mounted) ToastHelper.showError('공고 재오픈 중 오류가 발생했습니다.');
    } finally {
      if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
    }

    if (success == null) return;
    if (success) {
      ToastHelper.showSuccess('공고가 재오픈되었습니다.');
      onChanged();
    } else {
      ToastHelper.showError('공고 재오픈에 실패했습니다.');
    }
  }

  // ========================================
  // Helper 메서드들
  // ========================================

  void _showTimeExpiredDialog(TOModel to) {
    showDialog(
      context: context,
      barrierDismissible: false,
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