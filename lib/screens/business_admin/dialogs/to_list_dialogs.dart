import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../controllers/workforce_controller.dart';
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

/// TO 삭제 다이얼로그 — [POSTING-V2-01C.2] 미공개(DRAFT) 공고 정리 전용.
  ///
  /// 옛 계약은 '삭제하면 지원서가 자동 취소된다'였고, 그래서 확정 근무자 수를
  /// 미리 세어 경고했다. 서버 계약이 relation-zero only로 바뀌면서 관계가 있으면
  /// 삭제 자체가 거부되므로 '자동 취소' 전제가 사라졌다.
  ///
  /// 관계 존재 여부는 클라이언트가 판정하지 않는다 — checkTOBeforeDelete는
  /// 활성 지원서만 보므로 REJECTED/CANCELED/EXPIRED·계약 기록을 놓치고,
  /// 그 결과로 "삭제 가능"이라 안심시킨 뒤 서버가 거부하는 상태가 된다.
  /// canonical 판정은 서버 하나로 둔다.
  Future<void> showDeleteTODialog(TOItem toItem) async {
    final to = toItem.to;

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StyledDialog(
        title: '미공개 공고 삭제',
        subtitle: to.title,
        icon: Icons.delete_forever,
        headerColor: AppColors.error,
        content: StyledDialogInfoCard.warning(
          '삭제한 공고는 복구할 수 없습니다.\n'
          '지원·초대·근무 기록이 있는 공고는 삭제할 수 없습니다.',
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
        // [POSTING-V2-01C.2] 실패 시 deleteTO가 서버 메시지를 그대로 토스트한다.
        // 여기서 다시 generic 토스트를 띄우면 그 안내를 덮는다.
        // 낙관적 제거도 하지 않는다 — 성공한 경우에만 onChanged로 목록을 갱신한다.
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
      // [POSTING-V2-02B.2] 종료는 Home 인력 현황의 모집 대상을 줄인다.
      //   generic onChanged가 아니라 이 action 지점에서만 알린다 —
      //   같은 콜백을 쓰는 삭제·초대는 Home에 영향이 없다.
      WorkforceController.notifyDataChanged(
        origin: AdminMutationOrigin.jobs,
      );
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
      // [POSTING-V2-02B.2] 재오픈은 Home 인력 현황의 모집 대상을 되살린다
      WorkforceController.notifyDataChanged(
        origin: AdminMutationOrigin.jobs,
      );
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
              '근무 시작 시간이 지난 공고는 다시 열 수 없습니다.',
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
              '새로운 날짜로 공고를 등록하세요.',
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