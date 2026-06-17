import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 외국인 계정 승인 상태 배너
///
/// accountStatus가 'pending' 또는 'rejected'인 외국인 사용자 홈/설정 화면 상단에 표시.
class AccountStatusBanner extends StatelessWidget {
  final String accountStatus;
  final String? rejectedReason;

  const AccountStatusBanner({
    super.key,
    required this.accountStatus,
    this.rejectedReason,
  });

  @override
  Widget build(BuildContext context) {
    if (accountStatus == 'pending') {
      return _banner(
        context,
        icon: Icons.hourglass_top,
        color: AppColors.warning,
        bgColor: AppColors.warningBg,
        title: '가입 승인 대기 중',
        message: '슈퍼관리자가 검토 중입니다. 승인 완료 후 모든 기능을 이용할 수 있습니다.',
      );
    }

    if (accountStatus == 'rejected') {
      return _banner(
        context,
        icon: Icons.cancel,
        color: AppColors.error,
        bgColor: AppColors.errorBg,
        title: '가입 거절됨',
        message: rejectedReason ?? '고객센터에 문의해주세요.',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _banner(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: bgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: ResponsiveHelper.smallStyle(context, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
