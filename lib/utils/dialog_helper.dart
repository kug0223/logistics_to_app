import 'package:flutter/material.dart';
import 'responsive_helper.dart';
import 'toast_helper.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogs/styled_dialog.dart';
import '../widgets/common/loading_widget.dart';

/// 공통 다이얼로그 헬퍼
class DialogHelper {
  /// 확인 다이얼로그 (예/아니오)
  /// 
  /// 사용 예:
  /// ```dart
  /// final confirmed = await DialogHelper.showConfirm(
  ///   context,
  ///   title: '삭제',
  ///   message: '정말 삭제하시겠습니까?',
  ///   confirmText: '삭제',
  ///   confirmColor: AppColors.error,
  /// );
  /// if (confirmed) { ... }
  /// ```
  static Future<bool> showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '확인',
    String cancelText = '취소',
    Color? confirmColor,
    IconData? icon,
    Color? iconColor,
  }) async {
    final theme = Theme.of(context);
    
    final accentColor = confirmColor ?? iconColor ?? theme.primaryColor;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _buildDialog(
        context,
        title: title,
        icon: icon ?? Icons.help_outline,
        accentColor: accentColor,
        body: Text(
          message,
          style: ResponsiveHelper.bodyStyle(
            context,
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        actions: [
          _cancelBtn(context, () => Navigator.pop(dialogContext, false), cancelText),
          _confirmBtn(context, () => Navigator.pop(dialogContext, true), confirmText, accentColor),
        ],
      ),
    );
    return result ?? false;
  }

  /// 위험한 작업 확인 다이얼로그 (빨간색 강조)
  /// 
  /// 사용 예:
  /// ```dart
  /// final confirmed = await DialogHelper.showDangerConfirm(
  ///   context,
  ///   title: '삭제',
  ///   message: '이 작업은 되돌릴 수 없습니다.',
  /// );
  /// ```
  static Future<bool> showDangerConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '삭제',
    String cancelText = '취소',
  }) {
    return showConfirm(
      context,
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      confirmColor: AppColors.error,
      icon: Icons.warning,
      iconColor: AppColors.error,
    );
  }

  /// 알림 다이얼로그 (확인만)
  /// 
  /// 사용 예:
  /// ```dart
  /// await DialogHelper.showAlert(
  ///   context,
  ///   title: '오류',
  ///   message: '권한이 없습니다.',
  /// );
  /// ```
  static Future<void> showAlert(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = '확인',
    IconData? icon,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    
    final accentColor = iconColor ?? theme.primaryColor;

    return showDialog(
      context: context,
      builder: (dialogContext) => _buildDialog(
        context,
        title: title,
        icon: icon ?? Icons.notifications_outlined,
        accentColor: accentColor,
        body: Text(
          message,
          style: ResponsiveHelper.bodyStyle(
            context,
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        actions: [
          _confirmBtn(context, () => Navigator.pop(dialogContext), buttonText, accentColor),
        ],
      ),
    );
  }

  /// 에러 알림 다이얼로그
  static Future<void> showError(
    BuildContext context, {
    String title = '오류',
    required String message,
  }) {
    return showAlert(
      context,
      title: title,
      message: message,
      icon: Icons.error_outline,
      iconColor: AppColors.error,
    );
  }

  /// 성공 알림 다이얼로그
  static Future<void> showSuccess(
    BuildContext context, {
    String title = '완료',
    required String message,
  }) {
    return showAlert(
      context,
      title: title,
      message: message,
      icon: Icons.check_circle_outline,
      iconColor: AppColors.success,
    );
  }

  /// 정보 알림 다이얼로그
  static Future<void> showInfo(
    BuildContext context, {
    String title = '안내',
    required String message,
  }) {
    return showAlert(
      context,
      title: title,
      message: message,
      icon: Icons.info_outline,
      iconColor: AppColors.info,
    );
  }

  /// 로딩 다이얼로그 표시
  /// 
  /// 사용 예:
  /// ```dart
  /// DialogHelper.showLoading(context, message: '처리 중...');
  /// // 작업 수행
  /// Navigator.pop(context); // 닫기
  /// ```
  static void showLoading(
    BuildContext context, {
    String message = '처리 중...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 16)),
            ),
            child: Padding(
              padding: ResponsiveHelper.cardPadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LoadingWidget(),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  Text(
                    message,
                    style: ResponsiveHelper.bodyStyle(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 선택 다이얼로그 (여러 옵션 중 선택)
  /// 
  /// 사용 예:
  /// ```dart
  /// final selected = await DialogHelper.showOptions<String>(
  ///   context,
  ///   title: '정렬',
  ///   options: ['최신순', '오래된순', '이름순'],
  /// );
  /// if (selected != null) { ... }
  /// ```
  static Future<T?> showOptions<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    String Function(T)? optionLabel,
  }) {
    final theme = Theme.of(context);

    return showDialog<T>(
      context: context,
      builder: (dialogContext) => _buildDialog(
        context,
        title: title,
        icon: Icons.list_outlined,
        accentColor: theme.primaryColor,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final label = optionLabel?.call(option) ?? option.toString();
            return InkWell(
              onTap: () => Navigator.pop(dialogContext, option),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 4),
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chevron_right,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: theme.primaryColor),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(label, style: ResponsiveHelper.bodyStyle(context)),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          _cancelBtn(context, () => Navigator.pop(dialogContext), '취소'),
        ],
      ),
    );
  }

  /// 커스텀 콘텐츠 다이얼로그
  /// 
  /// 사용 예:
  /// ```dart
  /// await DialogHelper.showCustom(
  ///   context,
  ///   title: '상세 정보',
  ///   content: MyCustomWidget(),
  /// );
  /// ```
  static Future<T?> showCustom<T>(
    BuildContext context, {
    String? title,
    required Widget content,
    List<Widget>? actions,
    bool barrierDismissible = true,
    IconData? icon,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) {
        if (title != null) {
          return _buildDialog(
            context,
            title: title,
            icon: icon ?? Icons.info_outline,
            accentColor: iconColor ?? theme.primaryColor,
            body: content,
            actions: actions ?? [],
          );
        }
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 24)),
          ),
          content: content,
          actionsPadding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          actions: actions,
        );
      },
    );
  }

  /// 로그아웃 확인 다이얼로그 (자주 쓰는 패턴)
  static Future<bool> showLogoutConfirm(BuildContext context) {
    return showConfirm(
      context,
      title: '로그아웃',
      message: '로그아웃 하시겠습니까?',
      confirmText: '로그아웃',
      confirmColor: AppColors.error,
      icon: Icons.logout,
      iconColor: AppColors.error,
    );
  }

  /// 삭제 확인 다이얼로그 (자주 쓰는 패턴)
  static Future<bool> showDeleteConfirm(
    BuildContext context, {
    String itemName = '항목',
    String? additionalMessage,
  }) {
    final message = additionalMessage != null
        ? '$itemName을(를) 삭제하시겠습니까?\n\n$additionalMessage'
        : '$itemName을(를) 삭제하시겠습니까?';

    return showDangerConfirm(
      context,
      title: '삭제',
      message: message,
      confirmText: '삭제',
    );
  }

  /// 취소 확인 다이얼로그 (자주 쓰는 패턴)
  static Future<bool> showCancelConfirm(
    BuildContext context, {
    String title = '취소',
    String message = '정말 취소하시겠습니까?',
  }) {
    return showConfirm(
      context,
      title: title,
      message: message,
      confirmText: '취소하기',
      confirmColor: AppColors.warning,
      icon: Icons.cancel_outlined,
      iconColor: AppColors.warning,
    );
  }

  /// 텍스트 입력 다이얼로그
  /// 
  /// 사용 예:
  /// ```dart
  /// final reason = await DialogHelper.showTextInput(
  ///   context,
  ///   title: '거절 사유',
  ///   message: '거절 사유를 입력해주세요.',
  ///   hintText: '사유 입력',
  ///   confirmText: '거절',
  ///   confirmColor: AppColors.error,
  /// );
  /// if (reason != null) { ... }
  /// ```
  static Future<String?> showTextInput(
    BuildContext context, {
    required String title,
    String? message,
    String? hintText,
    String? initialValue,
    int maxLines = 3,
    int? maxLength,
    String confirmText = '확인',
    String cancelText = '취소',
    Color? confirmColor,
    IconData? icon,
    Color? iconColor,
    bool Function(String?)? validator,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final theme = Theme.of(context);
    
    final accentColor = confirmColor ?? iconColor ?? theme.primaryColor;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _buildDialog(
        context,
        title: title,
        icon: icon ?? Icons.edit_outlined,
        accentColor: accentColor,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(
                message,
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            ],
            TextField(
              controller: controller,
              maxLines: maxLines,
              maxLength: maxLength,
              style: ResponsiveHelper.bodyStyle(context),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: ResponsiveHelper.bodyStyle(
                  context,
                  color: theme.hintColor,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          _cancelBtn(context, () => Navigator.pop(dialogContext), cancelText),
          _confirmBtn(
            context,
            () {
              final value = controller.text.trim();
              if (validator != null && !validator(value)) return;
              Navigator.pop(dialogContext, value);
            },
            confirmText,
            accentColor,
          ),
        ],
      ),
    );
    
    controller.dispose();
    return result;
  }
  /// 거절 사유 선택 다이얼로그
  /// 
  /// 미리 정의된 사유 중 선택하거나 기타(직접 입력) 가능
  static Future<String?> showRejectReasonPicker(
    BuildContext context, {
    required String title,
    String? targetName,
    String? message,
  }) async {
    // 거절 사유 옵션
    final reasons = [
      '경력/경험 부족',
      '일정 불가',
      '다른 지원자 확정',
      '인원 충원 완료',
      '서류 미비',
      '기타',
    ];
    
    String? selectedReason;
    final customController = TextEditingController(
      text: '지원해 주셔서 감사합니다. 이번에는 인연이 닿지 않았지만, 다음에 또 지원 부탁드립니다.',
    );
    
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isCustom = selectedReason == '기타';
            
            return StyledDialog(
              title: title,
              subtitle: message ?? (targetName != null ? '$targetName님의 지원을 거절합니다' : '거절 사유를 선택해주세요'),
              icon: Icons.cancel,
              headerColor: AppColors.error,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 라디오 리스트 (RadioGroup으로 groupValue/onChanged 위임)
                  RadioGroup<String>(
                    groupValue: selectedReason,
                    onChanged: (value) {
                      setDialogState(() => selectedReason = value);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: reasons.map((reason) => RadioListTile<String>(
                        title: Text(
                          reason,
                          style: ResponsiveHelper.bodyStyle(context),
                        ),
                        value: reason,
                        activeColor: AppColors.error,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      )).toList(),
                    ),
                  ),
                  
                  // 기타 선택 시 입력 필드
                  if (isCustom) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    TextField(
                      controller: customController,
                      maxLines: 2,
                      maxLength: 100,
                      style: ResponsiveHelper.bodyStyle(context),
                      decoration: InputDecoration(
                        hintText: '거절 사유를 입력하세요',
                        hintStyle: ResponsiveHelper.bodyStyle(
                          context,
                          color: AppColors.grey400,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 12),
                          vertical: ResponsiveHelper.spacing(context, 12),
                        ),
                        counterText: '',
                      ),
                      autofocus: false,
                    ),
                  ],
                ],
              ),
              actions: [
                StyledDialogButton.cancel(
                  onPressed: () => Navigator.pop(dialogContext),
                ),
                StyledDialogButton.danger(
                  text: '거절',
                  onPressed: selectedReason == null
                      ? () {
                          ToastHelper.showWarning('거절 사유를 선택해주세요');
                        }
                      : () {
                          String finalReason;
                          if (isCustom) {
                            final customText = customController.text.trim();
                            if (customText.isEmpty) {
                              ToastHelper.showWarning('거절 사유를 입력해주세요');
                              return;
                            }
                            finalReason = customText;
                          } else {
                            finalReason = selectedReason!;
                          }
                          Navigator.pop(dialogContext, finalReason);
                        },
                ),
              ],
            );
          },
        );
      },
    );
    customController.dispose();
    return result;
  }

  /// 서류 미등록 안내 다이얼로그 (서류 관리로 이동)
  /// 
  /// 사용 예:
  /// ```dart
  /// final shouldNavigate = await DialogHelper.showDocumentRequired(
  ///   context,
  ///   title: '서류 등록 필요',
  ///   missingDocuments: ['신분증', '통장사본'],
  /// );
  /// if (shouldNavigate) {
  ///   // 서류 관리 화면으로 이동
  /// }
  /// ```
  static Future<bool> showDocumentRequired(
    BuildContext context, {
    required String title,
    required List<String> missingDocuments,
  }) async {
    final theme = Theme.of(context);
    
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _buildDialog(
        context,
        title: title,
        icon: Icons.warning_amber_rounded,
        accentColor: AppColors.warning,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '지원하기 전에 서류 등록이 필요합니다.',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: AppColors.warning,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '미등록 항목:',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  ...missingDocuments.map((doc) => Padding(
                        padding: EdgeInsets.only(
                          left: ResponsiveHelper.spacing(context, 8),
                          top: ResponsiveHelper.spacing(context, 4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: ResponsiveHelper.iconSize(context, 6),
                              color: AppColors.warning,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Text(
                              doc,
                              style: ResponsiveHelper.bodyStyle(
                                context,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '설정 > 내 서류 관리에서\n서류를 등록해주세요.',
              style: ResponsiveHelper.smallStyle(
                context,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        actions: [
          _cancelBtn(context, () => Navigator.pop(dialogContext, false), '취소'),
          _confirmBtn(
              context, () => Navigator.pop(dialogContext, true), '서류 등록하기', AppColors.warning),
        ],
      ),
    );
    return result ?? false;
  }

  // ═══════════════════════════════════════════════════════════
  // Private helpers
  // ═══════════════════════════════════════════════════════════

  /// 앱 통일 스타일 다이얼로그 프레임
  static Widget _buildDialog(
    BuildContext context, {
    required String title,
    required Widget body,
    required List<Widget> actions,
    required IconData icon,
    required Color accentColor,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 그라데이션 헤더
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 18)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor, accentColor.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      title,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 본문
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 4),
              ),
              child: body,
            ),
            // 버튼 행
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
              decoration: const BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: actions
                    .asMap()
                    .entries
                    .map((e) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: e.key > 0
                                  ? ResponsiveHelper.spacing(context, 8)
                                  : 0,
                            ),
                            child: e.value,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 취소 버튼
  static Widget _cancelBtn(
    BuildContext context,
    VoidCallback onPressed,
    String text,
  ) {
    return Material(
      color: AppColors.grey100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 13)),
          child: Center(
            child: Text(
              text,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.grey700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 확인 버튼
  static Widget _confirmBtn(
    BuildContext context,
    VoidCallback onPressed,
    String text,
    Color color,
  ) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 13)),
          child: Center(
            child: Text(
              text,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}